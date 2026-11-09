package app.yomashi.reader

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** OCR and translation stay on the phone; only language models are downloaded. */
class ReaderTranslationPlatform(context: Context, messenger: BinaryMessenger) {
    private val context = context.applicationContext
    private val channel = MethodChannel(messenger, "app.yomashi.reader/translation")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val jobs = ConcurrentHashMap<String, Job>()
    private val languages = setOf("ja", "zh", "ko", "en", "es", "pt", "fr", "de", "it")
    private var closed = false
    private var clearingModels = false

    private class Job(val id: String, val reply: MethodChannel.Result) {
        val cancelled = AtomicBoolean(false)
        val stopWaiting = CancellationTokenSource()
        val replied = AtomicBoolean(false)
        var recognizer: TextRecognizer? = null
        var translator: Translator? = null
        var timeout: Runnable? = null
        fun check() { if (cancelled.get()) throw CancellationException() }
    }

    init {
        channel.setMethodCallHandler { call, reply ->
            when (call.method) {
                "translate" -> {
                    val args = call.arguments as? Map<*, *>
                    val id = args?.get("id") as? String
                    val source = args?.get("source") as? String
                    val target = args?.get("target") as? String
                    val path = args?.get("path") as? String
                    if (closed || id.isNullOrBlank() || path.isNullOrBlank() ||
                        source !in languages || target !in languages || source == target) {
                        reply.error("invalid", "Elige dos idiomas diferentes.", null)
                    } else if (jobs.isNotEmpty() || clearingModels) {
                        reply.error("busy", "La traducción anterior aún se está cerrando. Reintenta en unos segundos.", null)
                    } else {
                        val job = Job(id, reply)
                        jobs[id] = job
                        val timeout = Runnable {
                            job.cancelled.set(true)
                            job.stopWaiting.cancel()
                            fail(job, "timeout", "La traducción tardó demasiado. Comprueba la conexión y vuelve a intentarlo.")
                        }
                        job.timeout = timeout
                        main.postDelayed(timeout, 170_000)
                        start(job, path, source!!, target!!, args?.get("wifiOnly") != false)
                    }
                }
                "cancel" -> {
                    jobs[call.arguments as? String]?.let { job ->
                        job.cancelled.set(true)
                        job.stopWaiting.cancel()
                        fail(job, "cancelled", "Traducción cancelada.")
                    }
                    reply.success(null)
                }
                "clearModels" -> {
                    if (closed || jobs.isNotEmpty() || clearingModels) {
                        reply.error("busy", "Espera a que termine la traducción actual.", null)
                    } else {
                        clearingModels = true
                        val manager = RemoteModelManager.getInstance()
                        manager.getDownloadedModels(TranslateRemoteModel::class.java)
                            .continueWithTask { models ->
                                Tasks.whenAll(models.result.map { manager.deleteDownloadedModel(it) })
                            }.addOnCompleteListener { task ->
                                clearingModels = false
                                if (task.isSuccessful) reply.success(null)
                                else reply.error("models", "No se pudieron eliminar los modelos. Reintenta.", null)
                            }
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }

    private fun start(job: Job, path: String, source: String, target: String, wifiOnly: Boolean) {
        // Chained tasks never block the Android UI or wait on model downloads.
        Tasks.call(worker) {
            job.check()
            val input = File(path).canonicalFile
            val root = File(context.cacheDir, "yomashi_translation").canonicalFile
            require(input.path.startsWith(root.path + File.separator) && input.isFile &&
                input.length() <= 40L * 1024 * 1024) { "Imagen de traducción no válida." }
            val image = InputImage.fromFilePath(context, Uri.fromFile(input))
            require(image.width.toLong() * image.height <= 8_100_000) { "La imagen es demasiado grande." }
            val recognizer = when (source) {
                "ja" -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
                "zh" -> TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
                "ko" -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
                else -> TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            }
            job.recognizer = recognizer
            recognizer.process(image)
        }.continueWithTask(worker) { it.result }
            .continueWithTask(worker) { recognized ->
                job.recognizer?.close()
                job.recognizer = null
                job.check()
                val blocks = recognized.result.textBlocks.filter {
                    it.text.isNotBlank() && it.boundingBox != null
                }
                require(blocks.isNotEmpty()) { "No se detectó texto. Prueba otro idioma de origen." }
                require(blocks.size <= 128 && blocks.sumOf { it.text.length } <= 16000) {
                    "Esta página contiene demasiado texto. Prueba una página más corta."
                }
                val translator = Translation.getClient(
                    TranslatorOptions.Builder().setSourceLanguage(source).setTargetLanguage(target).build()
                )
                job.translator = translator
                val conditions = DownloadConditions.Builder().apply { if (wifiOnly) requireWifi() }.build()
                interruptible(job, translator.downloadModelIfNeeded(conditions)).continueWithTask(worker) { downloaded ->
                    job.check()
                    downloaded.result
                    val requests = blocks.map { block ->
                        translator.translate(block.text).continueWith(worker) { translated ->
                            job.check()
                            val bounds = block.boundingBox!!
                            mapOf<String, Any>(
                                "left" to bounds.left, "top" to bounds.top,
                                "width" to bounds.width(), "height" to bounds.height(),
                                "original" to block.text, "translated" to translated.result
                            )
                        }
                    }
                    Tasks.whenAllSuccess<Map<String, Any>>(requests)
                }
            }.addOnCompleteListener(worker) { task ->
                job.recognizer?.close()
                job.translator?.close()
                if (task.isSuccessful && !job.cancelled.get()) {
                    main.post {
                        if (job.replied.compareAndSet(false, true)) {
                            job.reply.success(mapOf("blocks" to task.result))
                        }
                    }
                } else {
                    val error = task.exception
                    val message = when {
                        job.cancelled.get() -> "Traducción cancelada."
                        error is IllegalArgumentException -> error.message ?: "Imagen no válida."
                        else -> "No se pudo reconocer o traducir el texto. Comprueba el idioma y la conexión; si usas solo Wi-Fi, conéctate a esa red."
                    }
                    fail(job, "translation", message)
                }
                main.post {
                    job.timeout?.let(main::removeCallbacks)
                    jobs.remove(job.id)
                    if (closed && jobs.isEmpty()) worker.shutdown()
                }
            }
    }

    private fun <T> interruptible(job: Job, task: Task<T>): Task<T> {
        // Cancelling a Wi-Fi-only wait must let the next attempt change networks.
        // ML Kit may still complete its shared model download in the background.
        val completion = TaskCompletionSource<T>(job.stopWaiting.token)
        task.addOnCompleteListener { finished ->
            if (finished.isSuccessful) completion.trySetResult(finished.result)
            else completion.trySetException(finished.exception ?: CancellationException())
        }
        return completion.task
    }

    private fun fail(job: Job, code: String, message: String) {
        main.post {
            if (job.replied.compareAndSet(false, true)) job.reply.error(code, message, null)
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        jobs.values.forEach {
            it.cancelled.set(true)
            it.stopWaiting.cancel()
            fail(it, "cancelled", "El lector se cerró.")
        }
        if (jobs.isEmpty()) worker.shutdown()
    }
}
