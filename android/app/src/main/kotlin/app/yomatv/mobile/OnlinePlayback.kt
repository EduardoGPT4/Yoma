package app.yomatv.mobile

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import app.yomatv.engine.HttpFailure
import app.yomatv.engine.Network
import app.yomatv.engine.Provider
import org.json.JSONObject
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection

/** Only metadata from an authenticated plan crosses the WebView bridge. */
object OnlinePlayback {
    fun payload(plan: JSONObject, owner: Long, episodeId: Long): JSONObject {
        require(owner > 0 && plan.getLong("owner") == owner)
        val episodes=plan.getJSONArray("episodes")
        require(episodes.length() in 1..10000)
        val entry=(0 until episodes.length()).map{episodes.getJSONObject(it)}.firstOrNull{it.optLong("episode_id")==episodeId}
            ?: throw IOException("El capítulo ya no aparece en el listado. Actualízalo e inténtalo de nuevo.")
        return JSONObject().put("owner",owner).put("episode_id",episodeId)
            .put("slug",plan.getString("slug")).put("title",plan.getString("title")).put("number",entry.getString("number"))
            .put("language",plan.getString("language")).put("season",plan.optString("season")).put("cover",plan.optString("cover"))
            .put("mal_account_id",plan.optLong("mal_account_id")).put("progress_revision",plan.optString("progress_revision"))
            .put("watched",entry.optBoolean("watched")).put("next_episode_id",entry.optLong("next_episode_id"))
            .put("watched_override",entry.opt("watched_override")?:JSONObject.NULL)
    }
    data class Source(val url: String, val referer: String)
    fun resolve(ep: Episode): Source {
        val page="https://animeav1.com/media/${ep.slug}/${ep.number}"
        require(Provider.allowed(page,"page"))
        val embed=Provider.embed(Network.html(page,"page","https://animeav1.com/"),ep.language)
        return Source(Provider.video(Network.html(embed,"embed",page)),embed)
    }
}

/** Media3 streaming with the same host/redirect checks and Referer as downloads. */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class StreamDataSource(private val referer: String, private val allowed: (String)->Boolean = {Provider.allowed(it,"video")}) : BaseDataSource(true) {
    private var connection: HttpURLConnection? = null
    private var input: InputStream? = null
    private var remaining=C.LENGTH_UNSET.toLong()
    private var opened=false
    override fun open(dataSpec: DataSpec): Long {
        transferInitializing(dataSpec)
        val headers=dataSpec.httpRequestHeaders.toMutableMap().apply {
            put("Referer",referer)
            if(dataSpec.position>0 || dataSpec.length!=C.LENGTH_UNSET.toLong())put("Range","bytes=${dataSpec.position}-${if(dataSpec.length>0)dataSpec.position+dataSpec.length-1 else ""}")
        }
        try {
            val c=Network.open(dataSpec.uri.toString(),headers,allowed);connection=c
            if(c.responseCode !in setOf(200,206))throw HttpFailure(c.responseCode)
            if(c.contentType.orEmpty().lowercase().let{it.startsWith("text/")||it.contains("json")})throw IOException("El servidor no devolvió un video.")
            if(c.responseCode==206){
                val range=Regex("bytes (\\d+)-(\\d+)/(?:\\d+|\\*)").matchEntire(c.getHeaderField("Content-Range").orEmpty())
                if(range==null || range.groupValues[1].toLong()!=dataSpec.position)throw IOException("El servidor no respetó la posición del capítulo.")
            }
            input=c.inputStream
            // Some hosts ignore Range. Skip from the new response, never treat its start as the requested offset.
            var skip=if(c.responseCode==200)dataSpec.position else 0L
            val buffer=ByteArray(16384)
            while(skip>0){val count=input!!.read(buffer,0,minOf(buffer.size.toLong(),skip).toInt());if(count<0)throw IOException("El capítulo terminó antes de la posición solicitada.");skip-=count}
            remaining=when {
                dataSpec.length!=C.LENGTH_UNSET.toLong()->dataSpec.length
                c.contentLengthLong>=0->(c.contentLengthLong-if(c.responseCode==200)dataSpec.position else 0).coerceAtLeast(0)
                else->C.LENGTH_UNSET.toLong()
            }
            opened=true;transferStarted(dataSpec);return remaining
        }catch(error:Exception){close();throw error}
    }
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if(length==0)return 0
        if(remaining==0L)return C.RESULT_END_OF_INPUT
        val count=input?.read(buffer,offset,if(remaining<0)length else minOf(length.toLong(),remaining).toInt()) ?: return C.RESULT_END_OF_INPUT
        if(count<0){if(remaining>0)throw IOException("La conexión se interrumpió antes de completar el fragmento.");return C.RESULT_END_OF_INPUT}
        if(remaining>0)remaining-=count
        bytesTransferred(count);return count
    }
    override fun getUri(): Uri? = connection?.url?.toString()?.let(Uri::parse)
    override fun close() {
        try{input?.close()}finally{input=null;connection?.disconnect();connection=null;if(opened){opened=false;transferEnded()}}
    }
}
