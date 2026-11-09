package app.yomatv.mobile

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DownloadsPanelTest {
    private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=instrumentation.targetContext
    private fun episode(slug:String,number:Int,state:String,bytes:Long=20_000_000)=Episode(
        JSONObject().put("owner",900260020L).put("episode_id",number).put("slug",slug).put("number",number.toString())
            .put("title",when(slug){"lunar"->"El jardín lunar";"cristal"->"Ciudad de cristal";"viento"->"Viento del norte";else->"Historia $slug"}).put("language","SUB"),
        state,bytes,100_000_000L,"","",0,0,false,false,"","",0,123456.0,"")
    private fun actions(group:(String?)->Unit={},wifi:(Boolean)->Unit={})=DownloadActions({},group,{},{},{},{},{},wifi,{"${it.state} · ${formatBytes(it.bytes)}"})
    @Test fun transferTicksKeepTheSameViewsAndScrolledPosition(){
        Prefs(context).apply{owner=900260020L;paused=true}
        ActivityScenario.launch<MainActivity>(Intent(context,MainActivity::class.java).putExtra("qa_offline",true)).use{scenario->
            lateinit var panel:DownloadsPanel;lateinit var oldBody:android.view.View;lateinit var oldRow:android.view.View
            val transfer=episode("lunar",3,"downloading")
            val jobs=listOf(transfer)+(1..30).map{episode("complete-$it",it,"done")}
            val state=DownloadSnapshot(900260020L,jobs,"all",null,true,false,true,5_000_000_000)
            var wifiCalls=0;var opened:String?=null
            scenario.onActivity{a->panel=DownloadsPanel(a,actions({opened=it},{wifiCalls++}));a.setContentView(panel);panel.submit(state)}
            instrumentation.waitForIdleSync()
            scenario.onActivity{oldBody=panel.getChildAt(0);oldRow=panel.findViewWithTag("download-active-${transfer.key}");panel.scrollTo(0,650)}
            instrumentation.waitForIdleSync()
            val before=panel.scrollY;assertTrue(before>400)
            scenario.onActivity{
                repeat(100){tick->panel.submit(state.copy(jobs=listOf(transfer.copy(bytes=20_000_000L+tick*10000)) +jobs.drop(1)))}
                assertSame(oldBody,panel.getChildAt(0));assertSame(oldRow,panel.findViewWithTag("download-active-${transfer.key}"))
                panel.findViewWithTag<android.view.View>("download-ready-complete-5").performClick();assertEquals("complete-5",opened)
                panel.submit(state.copy(wifi=false));assertEquals(0,wifiCalls)
            }
            instrumentation.waitForIdleSync();assertEquals(before,panel.scrollY)
            scenario.onActivity{panel.submit(state.copy(group="complete-5"))}
            instrumentation.waitForIdleSync()
            scenario.onActivity{assertNotNull(panel.findViewWithTag<android.view.View>("download-episode-${jobs[5].key}"));panel.submit(state)}
            instrumentation.waitForIdleSync();assertEquals(before,panel.scrollY)
        }
    }
    @Test fun compactDownloadScreenRendersRealCountsAndControls(){
        Prefs(context).apply{owner=900260020L;paused=false}
        ActivityScenario.launch<MainActivity>(Intent(context,MainActivity::class.java).putExtra("qa_offline",true)).use{scenario->
            lateinit var panel:DownloadsPanel;lateinit var screen:android.view.View
            val jobs=listOf(episode("lunar",4,"downloading",68_000_000))+(1..3).map{episode("cristal",it,"done")}+(1..5).map{episode("viento",it+10,"done")}
            scenario.onActivity{a->
                MainActivity::class.java.getDeclaredField("page").apply{isAccessible=true}.set(a,"downloads")
                MainActivity::class.java.getDeclaredField("activeTab").apply{isAccessible=true}.set(a,"downloads")
                (MainActivity::class.java.getDeclaredField("header").apply{isAccessible=true}.get(a)as android.view.View).visibility=android.view.View.VISIBLE
                MainActivity::class.java.getDeclaredMethod("renderDownloadRows",List::class.java).apply{isAccessible=true}.invoke(a,jobs)
                MainActivity::class.java.getDeclaredMethod("updateNav",String::class.java).apply{isAccessible=true}.invoke(a,"")
                panel=MainActivity::class.java.getDeclaredField("downloadsPanel").apply{isAccessible=true}.get(a)as DownloadsPanel
                screen=MainActivity::class.java.getDeclaredField("root").apply{isAccessible=true}.get(a)as android.view.View
            }
            instrumentation.waitForIdleSync()
            scenario.onActivity{
                val texts=mutableListOf<String>()
                fun walk(v:android.view.View){if(v is TextView)texts.add(v.text.toString());if(v is android.view.ViewGroup)for(i in 0 until v.childCount)walk(v.getChildAt(i))}
                walk(panel);assertTrue(texts.contains("Descargando · 1"));assertTrue(texts.any{it.startsWith("3 episodios")});assertTrue(texts.any{it.startsWith("5 episodios")})
                assertNotNull(panel.findViewWithTag<android.view.View>("download-ready-cristal"))
                val bitmap=Bitmap.createBitmap(screen.width,screen.height,Bitmap.Config.ARGB_8888);screen.draw(Canvas(bitmap))
                val file=File(context.getExternalFilesDir(null),"verification/yoma-downloads-compact.png");file.parentFile!!.mkdirs();file.outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
            }
        }
    }
}
