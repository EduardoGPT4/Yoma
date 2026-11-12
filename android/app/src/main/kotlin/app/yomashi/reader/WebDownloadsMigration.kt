package app.yomashi.reader

import android.content.Context
import app.yomatv.mobile.Episode
import app.yomatv.mobile.Store
import app.yomatv.mobile.moveFile
import org.json.JSONArray
import org.json.JSONObject

/**
 * YomaTV usa solo la cola local de la app. Lo que quedaba en la cola de la
 * cuenta web (yoma_anime.db) pasa a ella una vez:
 *
 * - los episodios descargados se mueven a la carpeta local sin descargarlos
 *   de nuevo y conservan su huella;
 * - los que estaban en cola, en pausa o con error se piden en la cola local;
 * - lo visto (posición y «visto») se devuelve a Flutter para su historial.
 *
 * Si un archivo no se puede mover, su fila se queda donde estaba para
 * intentarlo en el siguiente inicio: nunca se borra un episodio completo.
 */
object WebDownloadsMigration {
    const val LEGACY_DATABASE = "yoma_anime.db"
    const val LOCAL_DATABASE = "yoma_anime_local_downloads.db"
    private val pending = setOf("queued", "retry", "downloading", "verifying", "paused", "failed")

    class Result(val moved: Int, val requeued: Int, val kept: Int, val progress: JSONArray) {
        fun toJson(): JSONObject = JSONObject().put("moved", moved).put("requeued", requeued)
            .put("kept", kept).put("progress", progress)
    }

    /** Datos de la obra y el episodio, sin la cuenta web. */
    fun localPayload(web: JSONObject): JSONObject {
        val local = JSONObject()
        for (name in listOf("slug", "title", "cover", "season", "episode_id", "number", "language")) {
            if (web.has(name) && !web.isNull(name)) local.put(name, web.get(name))
        }
        return local.put("owner", 1L).put("mal_account_id", 0).put("progress_revision", "local-v1")
    }

    private fun watched(ep: Episode) = if (ep.manualWatched >= 0) ep.manualWatched == 1 else ep.watched

    private fun progress(ep: Episode) = JSONObject().put("slug", ep.slug).put("title", ep.title)
        .put("episode_id", ep.episodeId).put("number", ep.number).put("language", ep.language)
        .put("position", ep.position).put("duration", ep.duration).put("watched", watched(ep))

    /** [legacy] y [local] son los almacenes; en la app, los de [LEGACY_DATABASE] y [LOCAL_DATABASE]. */
    fun run(legacy: Store, local: Store): Result {
        var moved = 0; var requeued = 0; var kept = 0
        val seen = JSONArray()
        for (ep in legacy.all()) {
            val payload = runCatching { localPayload(ep.payload) }.getOrNull() ?: continue
            if (ep.position > 0 || watched(ep)) seen.put(progress(ep))
            val source = legacy.video(ep)
            when {
                ep.state == "done" && source.isFile && source.length() == ep.total -> {
                    val candidate = Episode(payload, "done", ep.total, ep.total, "", "", 0L, 0L,
                        false, false, "", "", 0, 0.0, ep.hash)
                    val current = local.get(candidate.key, 1L)
                    val target = local.video(candidate)
                    val placed = when {
                        // La cola local está descargando ese mismo episodio: se intenta en el próximo inicio.
                        current?.state in setOf("downloading", "verifying") -> false
                        // Ya estaba descargado en la cola local con el mismo tamaño: se queda esa copia.
                        target.isFile && target.length() == ep.total -> source.delete() || !source.exists()
                        target.exists() -> false
                        else -> moveFile(source, target)
                    }
                    if (placed) {
                        local.adoptDone(payload, ep.total, ep.hash)
                        legacy.update(ep.key, ep.owner, "state" to "removed"); moved++
                    } else kept++
                }
                ep.state in pending -> {
                    legacy.video(ep, true).delete()
                    local.enqueueLocal(payload)
                    legacy.update(ep.key, ep.owner, "state" to "removed"); requeued++
                }
                // Marcado como descargado pero sin archivo: no se descarga otra vez solo.
                else -> legacy.update(ep.key, ep.owner, "state" to "removed")
            }
        }
        // Episodios vistos en streaming desde la web integrada: solo su progreso.
        for (ep in legacy.all(online = true)) if (ep.position > 0 || watched(ep)) seen.put(progress(ep))
        return Result(moved, requeued, kept, seen)
    }

    /** Ejecuta la migración si existe la base de la cuenta web. */
    fun run(context: Context): Result {
        if (!context.getDatabasePath(LEGACY_DATABASE).exists()) return Result(0, 0, 0, JSONArray())
        // La cola de la cuenta web no debe estar escribiendo mientras se mueven sus archivos.
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            runCatching {
                androidx.work.WorkManager.getInstance(context).cancelUniqueWork("yoma-anime-downloads").result.get()
            }
        }
        return Store(context, LEGACY_DATABASE).use { legacy ->
            Store(context, LOCAL_DATABASE).use { local -> run(legacy, local) }
        }
    }
}
