package app.yomatv.mobile

import app.yomashi.reader.R
import app.yomashi.reader.BuildConfig

import android.content.Context
import android.webkit.CookieManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

const val SITE = "https://hk-br035.gt.tc/seasonav1/"
class ApiFailure(val status: Int, message: String) : IOException(message)

/** Cookies stay in Android's private WebView cookie store; never in queue exports. */
class WebApi(private val context: Context, private val base: String = SITE) {
    init { require(base == SITE || BuildConfig.DEBUG && Regex("http://127\\.0\\.0\\.1:[1-9][0-9]{0,4}/").matches(base)) }
    private fun request(action: String, body: JSONObject? = null, csrf: String = ""): JSONObject {
        val url = base + "actions.php" + if (body == null) "?action=$action" else ""
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 20_000; connection.readTimeout = 30_000
            connection.setRequestProperty("User-Agent", Prefs(context).userAgent)
            connection.setRequestProperty("Cookie", CookieManager.getInstance().getCookie(base).orEmpty())
            connection.setRequestProperty("X-Season-Response", "patch")
            connection.setRequestProperty("Referer", base)
            if (body != null) {
                connection.requestMethod = "POST"; connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("X-CSRF-Token", csrf)
                connection.outputStream.use { it.write(body.put("action", action).toString().toByteArray()) }
            }
            val code = connection.responseCode
            if (!connection.contentType.orEmpty().contains("application/json")) throw ApiFailure(503, "Abre el catálogo para renovar la sesión del hosting.")
            val data = (if (code >= 400) connection.errorStream else connection.inputStream)?.use { input ->
                val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(16 * 1024)
                while (true) { val count = input.read(buffer); if (count < 0) break; output.write(buffer, 0, count); if (output.size() > 4 * 1024 * 1024) throw IOException("Respuesta demasiado grande.") }
                output.toString("UTF-8")
            } ?: "{}"
            val json = JSONObject(data)
            if (code != 200 || !json.optBoolean("ok")) throw ApiFailure(code, json.optString("message", "La web no completó la operación."))
            return json
        } finally { connection.disconnect() }
    }
    fun session(owner: Long): JSONObject {
        val data = request("mobile_session").getJSONObject("mobile_session")
        if (data.optLong("user_id") != owner) throw ApiFailure(401, "Inicia sesión con la cuenta que descargó estos capítulos.")
        return data
    }
    fun online(owner: Long, episodeId: Long, language: String): JSONObject {
        return OnlinePlayback.payload(plan(owner,episodeId,language),owner,episodeId)
    }
    fun plan(owner: Long, episodeId: Long, language: String): JSONObject {
        val current=session(owner)
        val plan=request("offline_plan",JSONObject().put("episode_id",episodeId).put("language",language),current.getString("csrf")).getJSONObject("offline_plan")
        require(plan.getLong("owner")==owner);return plan
    }
    fun markLocal(ep: Episode,csrf: String) {request("watched",JSONObject().put("episode_id",ep.episodeId).put("watched",ep.manualWatched==1).put("progress_revision",ep.payload.optString("progress_revision")),csrf)}
    fun mark(ep: Episode, csrf: String): JSONObject = request("watch_scrobble", JSONObject()
        .put("episode_id", ep.episodeId).put("mal_account_id", ep.payload.optLong("mal_account_id"))
        .put("progress_revision", ep.payload.optString("progress_revision"))
        .put("position", ep.position / 1000.0).put("duration", ep.duration / 1000.0), csrf).getJSONObject("watch_sync")
}

open class SyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val owner = inputData.getLong("owner", 0); val context = applicationContext
        if (owner <= 0 || Prefs(context).owner != owner) return Result.success()
        Store(context).use { store ->
            val pending = (store.list(owner)+store.playback(owner)).filter { it.pending && it.watched }
                .distinctBy { "${it.key}:${it.payload.optLong("mal_account_id")}:${it.payload.optString("progress_revision")}" }.take(20)
            val manual=(store.list(owner)+store.playback(owner)).filter{it.markPending&&it.manualWatched>=0}.distinctBy{it.key}.take(50)
            if (pending.isEmpty()&&manual.isEmpty()) return Result.success()
            try {
                val api = WebApi(context); val session = api.session(owner)
                for(ep in manual){
                    if(isStopped||Prefs(context).owner!=owner)return Result.success()
                    try{
                        api.markLocal(ep,session.getString("csrf"))
                        store.update(ep,"mark_pending" to false,"sync" to if(ep.manualWatched==1)"Visto en YomaTV" else "Sin ver en YomaTV")
                    }catch(error:ApiFailure){
                        if(error.status in setOf(400,404,409))store.update(ep,"mark_pending" to false,"sync" to "La marca se conserva en este dispositivo. Reabre el anime para guardarla en la web.") else throw error
                    }
                }
                for (ep in pending) {
                    if (isStopped || Prefs(context).owner != owner) return Result.success()
                    if (ep.payload.optLong("mal_account_id") > 0 && session.optLong("mal_account_id") != ep.payload.optLong("mal_account_id")) {
                        store.update(ep, "sync" to "La cuenta MAL cambió. Revisa este capítulo en la web antes de enviarlo.", "pending" to false)
                        continue
                    }
                    if (ep.payload.optLong("mal_account_id") <= 0) {
                        store.update(ep, "sync" to "Conecta y vincula MAL en la web; este capítulo se conserva como visto local.", "pending" to false)
                        continue
                    }
                    try {
                        val result = api.mark(ep, session.getString("csrf"))
                        val state = result.optString("state")
                        val success = state == "synced" || state == "rewatched"
                        store.update(ep, "sync" to if (success) "Actualizado en MyAnimeList" else result.optString("message", "Pendiente de MyAnimeList"), "pending" to (state == "pending"))
                        if (success) Notices.result(context, "Capítulo ${ep.number} actualizado en MyAnimeList", ep.title, ep.key.hashCode() xor 0x1643)
                        if (state == "pending") return Result.retry()
                    } catch (error: ApiFailure) {
                        if (error.status in setOf(400, 409)) {
                            store.update(ep, "pending" to false, "sync" to error.message.orEmpty())
                        } else throw error
                    }
                }
                return if ((store.list(owner)+store.playback(owner)).any { it.pending||it.markPending }) Result.retry() else Result.success()
            } catch (error: Exception) {
                for (ep in pending+manual) store.update(ep, "sync" to if (error is ApiFailure && error.status in setOf(401, 403)) "Abre el catálogo e inicia sesión para sincronizar." else "Sin conexión; el progreso permanece guardado.")
                return if (error is ApiFailure && error.status in setOf(401, 403) || runAttemptCount >= 5) Result.success() else Result.retry()
            }
        }
    }
}
