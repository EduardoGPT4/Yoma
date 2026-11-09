package app.yomatv.mobile

import android.graphics.BitmapFactory
import android.widget.ImageView
import java.net.URL

/** Bounded thumbnails only; no account cookies or redirects leave the web session. */
object CoverArt {
    private val tasks=java.util.concurrent.Executors.newFixedThreadPool(2)
    private val cache=android.util.LruCache<String,android.graphics.Bitmap>(20)
    fun show(view:ImageView,url:String){
        val uri=runCatching{android.net.Uri.parse(url)}.getOrNull()?:return
        if(uri.scheme!="https"||uri.host !in setOf("cdn.animeav1.com","cdn.myanimelist.net")||uri.port !in setOf(-1,443))return
        view.tag=url;cache.get(url)?.let{view.setImageBitmap(it);return}
        tasks.execute{
            val result=runCatching{
                val c=URL(url).openConnection() as java.net.HttpURLConnection
                try{
                    c.instanceFollowRedirects=false;c.connectTimeout=6000;c.readTimeout=6000
                    require(c.responseCode==200)
                    val data=c.inputStream.use{input->val out=java.io.ByteArrayOutputStream();val buf=ByteArray(8192);while(true){val n=input.read(buf);if(n<0)break;out.write(buf,0,n);require(out.size()<=2*1024*1024)};out.toByteArray()}
                    BitmapFactory.decodeByteArray(data,0,data.size,BitmapFactory.Options().apply{inSampleSize=2})
                }finally{c.disconnect()}
            }.getOrNull()
            if(result!=null){cache.put(url,result);view.post{if(view.tag==url)view.setImageBitmap(result)}}
        }
    }
}
