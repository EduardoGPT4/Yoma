package app.yomashi.reader

import android.content.Intent
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.yomatv.mobile.Prefs
import app.yomatv.mobile.Store
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class YomaAnimeBridgeTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    @Test fun originAndMainFrameAreRequiredForNativeMessages() {
        Prefs(context).apply { owner=731; paused=true }
        ActivityScenario.launch<app.yomatv.mobile.MainActivity>(Intent(context,app.yomatv.mobile.MainActivity::class.java).putExtra("qa_offline",true)).use { scenario ->
            lateinit var web: WebView
            scenario.onActivity { activity ->
                web=WebView(activity);web.settings.javaScriptEnabled=true;activity.setContentView(web)
                assertTrue(NativeAnimeBridge.attach(activity,web))
            }
            fun page(base:String,html:String) {
                val ready=CountDownLatch(1)
                scenario.onActivity {
                    web.webViewClient=object:WebViewClient(){
                        override fun shouldInterceptRequest(view:WebView, request:android.webkit.WebResourceRequest):android.webkit.WebResourceResponse? {
                            if (!request.isForMainFrame) return null
                            return android.webkit.WebResourceResponse("text/html","UTF-8",java.io.ByteArrayInputStream(html.toByteArray()))
                        }
                        override fun onPageFinished(view:WebView,url:String){ready.countDown()}
                    }
                    web.loadUrl(base)
                }
                assertTrue(ready.await(10,TimeUnit.SECONDS));Thread.sleep(300)
            }
            page("https://untrusted.example/", "<script>window.YomaAndroid?.postMessage('{\"type\":\"auth\",\"owner\":0}')</script>")
            assertEquals(731L,Prefs(context).owner)
            page("https://tv.yoma.site/", "<iframe srcdoc=\"&lt;script>window.YomaAndroid?.postMessage('{&quot;type&quot;:&quot;auth&quot;,&quot;owner&quot;:0}')&lt;/script>\"></iframe>")
            assertEquals(731L,Prefs(context).owner)
            scenario.onActivity { web.evaluateJavascript("YomaAndroid.postMessage(JSON.stringify({type:'auth',owner:0}))",null) }
            val deadline=System.currentTimeMillis()+5000
            while(Prefs(context).owner!=0L&&System.currentTimeMillis()<deadline)Thread.sleep(50)
            assertEquals(0L,Prefs(context).owner)
            scenario.onActivity { web.destroy() }
        }
    }
    @Test fun disconnectKeepsDownloadsAndMangaDataButClearsTheWebIdentity() {
        val owner=900260099L
        Prefs(context).apply{this.owner=owner;paused=true}
        val manga=context.getSharedPreferences("yoma_manga_test_fixture",0);manga.edit().putString("progress","page-12").commit()
        Store(context).use { store ->
            val payload=JSONObject().put("owner",owner).put("episode_id",1).put("slug","identity-fixture").put("number","1").put("language","SUB").put("title","Fixture")
            store.add(payload);val ep=store.list(owner).first{it.slug=="identity-fixture"}
            val file=store.video(ep);file.parentFile!!.mkdirs();file.writeText("local fixture")
            val done=CountDownLatch(1)
            instrumentation.runOnMainSync{NativeAnimeBridge.resetIdentity(context){done.countDown()}}
            assertTrue(done.await(10,TimeUnit.SECONDS));assertEquals(0L,Prefs(context).owner)
            assertNotNull(store.get(ep.key,owner));assertTrue(file.exists());assertEquals("page-12",manga.getString("progress",null))
        }
    }
}
