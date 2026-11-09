package app.yomatv.mobile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.yomatv.engine.Integrity
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
@RunWith(AndroidJUnit4::class)
class LocalAnimeStoreTest {
  private val ctx get()=InstrumentationRegistry.getInstrumentation().targetContext
  private fun payload()=JSONObject().put("owner",1L).put("episode_id",99001).put("slug","qa-local-store").put("number","1").put("language","SUB").put("title","QA local video")
  @Test fun localFilesRemainSeparateFromWebAccountsAndReopenOffline(){
    val local=Store(ctx,"yoma_anime_local_downloads.db")
    val old=Store(ctx)
    try {
      local.add(payload());old.add(payload());val ep=local.list(1).first{it.slug=="qa-local-store"}
      val video=local.video(ep);video.parentFile?.mkdirs()
      InstrumentationRegistry.getInstrumentation().context.assets.open("sample.mp4").use{input->video.outputStream().use{input.copyTo(it)}}
      assertTrue(Integrity.mp4(video));val sha=Integrity.sha256(video)
      local.update(ep.key,1,"state" to "done","bytes" to video.length(),"total" to video.length(),"hash" to sha,"duration" to 30000L)
      val web=old.list(1).first{it.slug=="qa-local-store"}
      assertNotEquals(video.canonicalPath,old.video(web).canonicalPath)
      assertEquals("queued",web.state)
      Store(ctx,"yoma_anime_local_downloads.db").use{reopened->
        val done=reopened.get(ep.key,1)!!;assertEquals("done",done.state);assertEquals(sha,Integrity.sha256(reopened.video(done)))
        reopened.add(payload());assertEquals("done",reopened.get(ep.key,1)!!.state)
        assertEquals(1,reopened.list(1).count{it.slug=="qa-local-store"})
        reopened.removeVideo(done);assertFalse(video.exists())
      }
      old.removeVideo(web)
    } finally {local.close();old.close()}
  }
  @Test fun localQueuePreferencesDoNotDependOnWebIdentity(){
    val web=Prefs(ctx);val before=web.owner;web.owner=777L
    val local=Prefs(ctx,true);assertEquals(1L,local.owner)
    local.paused=true;web.owner=0L;assertEquals(1L,local.owner);assertTrue(local.paused)
    web.owner=before
  }
}
