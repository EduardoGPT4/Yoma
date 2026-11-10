package app.yomashi.reader

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import app.yomatv.mobile.*
import app.yomatv.engine.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.FileOutputStream
import java.util.concurrent.Executors

/** Local APK operations never depend on a web user or its cookies. */
object LocalAnimePlatform {
    private val commands=Executors.newSingleThreadExecutor()
    private val network=Executors.newFixedThreadPool(2)
    private val main=Handler(Looper.getMainLooper())
    private fun store(c:Context)=Store(c,"yoma_anime_local_downloads.db")
    private fun payload(args:Any?):JSONObject {
        val obj=JSONObject(args as String)
        require(Regex("[A-Za-z0-9_-]{1,160}").matches(obj.getString("slug")))
        require(Regex("\\d{1,6}(?:\\.\\d{1,3})?").matches(obj.getString("number")))
        require(obj.optString("language","SUB") in setOf("SUB","LAT","DUB"))
        obj.put("owner",1L).put("mal_account_id",0).put("progress_revision","local-v1")
        return obj
    }
    fun register(context:Context,engine:FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger,"app.yoma/anime_local").setMethodCallHandler { call,result ->
            val executor=if(call.method in setOf("resolve","sources"))network else commands
            executor.execute {
                try {
                    val value:Any?=when(call.method) {
                        "sources" -> {
                            val data=payload(call.arguments)
                            val page="https://animeav1.com/media/${data.getString("slug")}/${data.getString("number")}"
                            val html=Network.html(page,"page","https://animeav1.com/")
                            val embeds=JsData.property(html,"embeds") as? Map<*,*> ?: error("La fuente no devolvió servidores reconocibles.")
                            val items=org.json.JSONArray()
                            for((language,rows) in embeds) for(row in rows as? List<*> ?: emptyList<Any>()) {
                                val record=row as? Map<*,*> ?: continue
                                val url=record["url"] as? String ?: continue
                                val server=record["server"] as? String ?: continue
                                if(!url.startsWith("https://") || url.length>4096)continue
                                items.put(JSONObject().put("language",language.toString().uppercase()).put("server",server).put("embed",url).put("supported",server=="MP4Upload"&&Provider.allowed(url,"embed")))
                            }
                            items.toString()
                        }
                        "resolve" -> {
                            val data=payload(call.arguments)
                            val page="https://animeav1.com/media/${data.getString("slug")}/${data.getString("number")}"
                            val embed=data.optString("embed").ifEmpty { Provider.embed(Network.html(page,"page","https://animeav1.com/"),data.optString("language","SUB")) }
                            require(Provider.allowed(embed,"embed")){"Este servidor necesita el reproductor web."}
                            val url=Provider.video(Network.html(embed,"embed",page))
                            JSONObject().put("url",url).put("referer",embed).put("userAgent",Provider.UA).put("server","MP4Upload").toString()
                        }
                        "snapshot" -> {
                            val prefs=Prefs(context,true)
                            val rows=store(context).use { db -> db.list(1).filter{it.state!="removed"}.map { ep ->
                                val file=db.video(ep)
                                JSONObject(ep.payload.toString()).put("key",ep.key).put("state",ep.state).put("bytes",ep.bytes).put("total",ep.total).put("error",ep.error).put("speed",ep.speed)
                                    .put("file",if(ep.state=="done"&&file.isFile&&file.length()==ep.total)file.absolutePath else "")
                            } }
                            JSONObject().put("items",org.json.JSONArray(rows)).put("paused",prefs.paused).put("wifiOnly",prefs.wifiOnly).put("supported",Build.VERSION.SDK_INT>=26).toString()
                        }
                        "migrate" -> store(context).use { db ->
                            // Episodios completos de la carpeta privada a Yoma/YomaTV/Anime;
                            // nunca mientras se descarga o verifica un episodio.
                            if(db.list(1).any{it.state in setOf("downloading","verifying")}) 0
                            else FileOutputStream(java.io.File(context.filesDir,"yoma-anime-local-downloads.lock"),true).channel.use { channel ->
                                val lock=try{channel.tryLock()}catch(_:java.nio.channels.OverlappingFileLockException){null}
                                if(lock==null) 0 else try{db.migrateLocal(1)}finally{lock.release()}
                            }
                        }
                        "enqueue" -> {
                            require(Build.VERSION.SDK_INT>=26){"Las descargas de anime necesitan Android 8 o posterior."}
                            val data=payload(call.arguments)
                            require(data.getLong("episode_id")>0&&data.getString("title").length in 1..500)
                            store(context).use { it.add(data) }
                            Prefs(context,true).paused=false;Queue.startLocal(context);null
                        }
                        "control" -> {
                            val args=JSONObject(call.arguments as String);val action=args.getString("action");val prefs=Prefs(context,true)
                            when(action) {
                                "pauseAll" -> Queue.pauseLocal(context)
                                "resumeAll" -> {prefs.paused=false;Queue.startLocal(context,true)}
                                "wifi" -> {prefs.wifiOnly=args.getBoolean("value");if(!prefs.paused)Queue.startLocal(context,true)}
                                else -> store(context).use { db ->
                                    val ep=db.get(args.getString("key"),1L)?:error("El episodio no está en la cola.")
                                    when(action) {
                                        "pause" -> db.update(ep.key,1,"state" to "paused","speed" to 0.0)
                                        "retry" -> {db.update(ep.key,1,"state" to "queued","attempts" to 0,"error" to "");prefs.paused=false;Queue.startLocal(context)}
                                        "delete","cancel" -> {
                                            require(prefs.paused||db.list(1).none{it.state in setOf("downloading","verifying")}){"Pausa las descargas antes de eliminar un archivo."}
                                            FileOutputStream(java.io.File(context.filesDir,"yoma-anime-local-downloads.lock"),true).channel.use { channel ->
                                                val lock=try{channel.tryLock()}catch(_:java.nio.channels.OverlappingFileLockException){null}
                                                require(lock!=null){"La descarga se está deteniendo. Inténtalo de nuevo."}
                                                try{db.removeVideo(ep)}finally{lock.release()}
                                            }
                                        }
                                        "verify" -> {
                                            val file=db.video(ep);require(file.isFile&&file.length()==ep.total&&Integrity.mp4(file)&&Integrity.sha256(file)==ep.hash){"El archivo no coincide con la descarga verificada."}
                                        }
                                        else -> error("Acción desconocida.")
                                    }
                                }
                            };null
                        }
                        else -> error("Operación local desconocida.")
                    }
                    main.post{result.success(value)}
                }catch(e:Exception){main.post{result.error("anime_local",e.message,null)}}
            }
        }
    }
}
