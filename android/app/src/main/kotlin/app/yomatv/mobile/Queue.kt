package app.yomatv.mobile

import app.yomashi.reader.R
import app.yomashi.reader.BuildConfig

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadataRetriever
import android.os.Build
import androidx.work.*
import app.yomatv.engine.*
import java.io.IOException
import java.util.concurrent.TimeUnit

object Notices {
    fun channels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("yoma_anime_downloads", "Anime · Descargas", NotificationManager.IMPORTANCE_LOW))
        manager.createNotificationChannel(NotificationChannel("yoma_anime_results", "Anime · Capítulos y errores", NotificationManager.IMPORTANCE_DEFAULT))
    }
    fun notification(context: Context, title: String, message: String, ongoing: Boolean = false): Notification {
        val intent = Intent(context, app.yomashi.reader.MainActivity::class.java)
        val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(context, if (ongoing) "yoma_anime_downloads" else "yoma_anime_results")
            .setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle(title).setContentText(message)
            .setContentIntent(pending).setOnlyAlertOnce(ongoing).setOngoing(ongoing).setAutoCancel(!ongoing).build()
    }
    fun result(context: Context, title: String, message: String, id: Int) {
        try { context.getSystemService(NotificationManager::class.java).notify(id, notification(context, title, message)) } catch (_: SecurityException) { }
    }
}

object Queue {
    fun startLocal(context: Context, replace: Boolean = false) {
        val prefs = Prefs(context, true); if (prefs.paused) return
        Notices.channels(context)
        val constraints = Constraints.Builder().setRequiredNetworkType(if (prefs.wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED).setRequiresStorageNotLow(true).build()
        val work = OneTimeWorkRequestBuilder<DownloadWorker>().setInputData(workDataOf("owner" to 1L, "local" to true)).setConstraints(constraints).setBackoffCriteria(BackoffPolicy.EXPONENTIAL,30,TimeUnit.SECONDS).build()
        WorkManager.getInstance(context).enqueueUniqueWork("yoma-anime-local-downloads",if(replace) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.APPEND_OR_REPLACE,work)
    }
    fun pauseLocal(context: Context) { Prefs(context,true).paused=true; WorkManager.getInstance(context).cancelUniqueWork("yoma-anime-local-downloads") }

    /** Detiene la antigua cola de la cuenta web (trabajos de versiones anteriores). */
    fun stopWebQueue(context: Context) {
        val work = WorkManager.getInstance(context)
        work.cancelUniqueWork("yoma-anime-downloads")
        val owner = Prefs(context).owner
        if (owner > 0) work.cancelUniqueWork("yoma-anime-sync-$owner")
    }
}

open class DownloadWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    private val localMode = inputData.getBoolean("local", false)
    private var transfer: Transfer? = null
    private val owner = inputData.getLong("owner", 0)
    override fun getForegroundInfo(): ForegroundInfo {
        val notification = Notices.notification(applicationContext, "YomaTV · Descargas", "Preparando la cola…", true)
        return if (Build.VERSION.SDK_INT >= 29) ForegroundInfo(27101, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC) else ForegroundInfo(27101, notification)
    }
    override fun onStopped() { transfer?.stop(); super.onStopped() }
    override fun doWork(): Result {
        // Un trabajo de la antigua cola de la cuenta web (versiones anteriores) no hace nada.
        if (!localMode) return Result.success()
        // Serializes overlapping WorkManager replacements, including file writes.
        java.io.FileOutputStream(java.io.File(applicationContext.filesDir, "yoma-anime-local-downloads.lock"), true).channel.use { channel ->
            var lock: java.nio.channels.FileLock? = null
            var tries = 0
            while (lock == null && tries++ < 100) {
                if (isStopped) return Result.success()
                lock = try { channel.tryLock() } catch (_: java.nio.channels.OverlappingFileLockException) { null }
                if (lock == null) Thread.sleep(100)
            }
            val acquired = lock ?: return Result.retry()
            try { return runQueue() } finally { acquired.release() }
        }
    }
    private fun runQueue(): Result {
        val context = applicationContext; val prefs = Prefs(context, true)
        if (owner <= 0 || prefs.owner != owner || prefs.paused) return Result.success()
        setForegroundAsync(getForegroundInfo()).get()
        Store(context, "yoma_anime_local_downloads.db").use { store ->
            store.recover(owner)
            for (job in store.list(owner).filter { it.state in setOf("queued", "retry") }) {
                if (isStopped || prefs.paused || prefs.owner != owner) return Result.success()
                try {
                    if (!store.claim(job)) continue
                    // Recover the narrow crash window between rename and DB commit.
                    val existing = store.video(job)
                    if (existing.exists()) {
                        if (job.total > 0 && existing.length() != job.total) throw ProviderChanged("El archivo final cambió. Elimínalo explícitamente antes de descargar otra copia.")
                        val (duration, hash) = verify(existing)
                        store.update(job.key, owner, "state" to "done", "bytes" to existing.length(), "total" to existing.length(), "duration" to duration, "hash" to hash, "speed" to 0.0)
                        continue
                    }
                    val page = "https://animeav1.com/media/${job.slug}/${job.number}"
                    val embed = Provider.embed(Network.html(page, "page", "https://animeav1.com/"), job.language)
                    val video = Provider.video(Network.html(embed, "embed", page))
                    val partial = store.video(job, true); partial.parentFile?.mkdirs()
                    val required = (job.total - partial.length()).coerceAtLeast(16L * 1024 * 1024) + 64L * 1024 * 1024
                    if (partial.parentFile!!.usableSpace < required) throw IOException("No hay espacio suficiente. Libera almacenamiento antes de reintentar.")
                    val engine = Transfer(); transfer = engine
                    var checkAt = 0L; var paused = false
                    val result = engine.download(video, embed, partial, Resume(job.etag, job.modified, job.total), cancelled = {
                        val now = System.currentTimeMillis()
                        if (now - checkAt > 500) {
                            paused = store.get(job.key, owner)?.state == "paused"; checkAt = now
                        }
                        isStopped || prefs.paused || prefs.owner != owner || paused
                    }) { progress ->
                        store.update(job.key, owner, "bytes" to progress.bytes, "total" to progress.total,
                            "etag" to progress.resume.etag, "modified" to progress.resume.modified, "speed" to progress.bytesPerSecond)
                        val text = "Cap. ${job.number} · ${formatBytes(progress.bytes)} / ${formatBytes(progress.total)}"
                        try { context.getSystemService(NotificationManager::class.java).notify(27101, Notices.notification(context, job.title, text, true)) } catch (_: SecurityException) { }
                    }
                    if (isStopped || prefs.owner != owner || prefs.paused) throw TransferStopped()
                    store.update(job.key, owner, "state" to "verifying", "speed" to 0.0)
                    val (duration, hash) = verify(partial)
                    if (isStopped || prefs.owner != owner || prefs.paused || store.get(job.key, owner)?.state == "paused") throw TransferStopped()
                    val target = store.video(job)
                    if (target.exists()) throw IOException("Ya existe un video final. No se sobrescribió.")
                    if (!moveFile(partial, target)) throw IOException("No se pudo guardar el video verificado.")
                    store.update(job.key, owner, "state" to "done", "bytes" to result.bytes, "total" to result.total, "duration" to duration,
                        "hash" to hash, "attempts" to 0, "error" to "", "speed" to 0.0)
                    Notices.result(context, "Capítulo ${job.number} descargado", job.title, job.key.hashCode())
                } catch (_: TransferStopped) {
                    if (store.get(job.key, owner)?.state != "paused") store.update(job.key, owner, "state" to "queued", "speed" to 0.0)
                    if (isStopped || prefs.paused || prefs.owner != owner) return Result.success()
                } catch (error: Exception) {
                    if (isStopped) { if (store.get(job.key, owner)?.state != "paused") store.update(job.key, owner, "state" to "queued", "speed" to 0.0); return Result.success() }
                    val permanent = error is ProviderChanged || error is HttpFailure && error.code in setOf(404, 410)
                    val attempts = job.attempts + 1; val retry = !permanent && attempts < 5
                    val message = when (error) {
                        is ProviderChanged, is HttpFailure -> error.message.orEmpty()
                        is java.net.UnknownHostException -> "Sin conexión o fallo de DNS."
                        is java.net.SocketTimeoutException -> "El servidor tardó demasiado."
                        else -> "No se completó el capítulo. Comprueba conexión, espacio y disponibilidad del servidor."
                    }
                    store.update(job.key, owner, "state" to if (retry) "retry" else "failed", "attempts" to attempts, "error" to message, "speed" to 0.0)
                    if (retry) return Result.retry()
                    Notices.result(context, "No se descargó el capítulo ${job.number}", message, job.key.hashCode())
                } finally { transfer = null }
            }
        }
        return Result.success()
    }
    private fun verify(file: java.io.File): Pair<Long, String> {
        if (!Integrity.mp4(file)) throw ProviderChanged("El MP4 está incompleto o su estructura no es válida. El parcial se conserva para revisarlo.")
        val retriever = MediaMetadataRetriever()
        val duration = try {
            retriever.setDataSource(file.absolutePath)
            val value = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            val hasVideo = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            if (value <= 0 || !hasVideo) throw ProviderChanged("El archivo no contiene video reproducible.")
            retriever.getFrameAtTime(0)?.recycle() ?: throw ProviderChanged("No se pudo decodificar el video.")
            value
        } finally { retriever.release() }
        return duration to Integrity.sha256(file)
    }
}

fun formatBytes(bytes: Long): String = if (bytes <= 0) "—" else if (bytes >= 1024L * 1024 * 1024) "%.2f GB".format(bytes / (1024.0 * 1024 * 1024)) else "%.1f MB".format(bytes / (1024.0 * 1024))
