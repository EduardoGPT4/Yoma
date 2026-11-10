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
  @Test fun askingAgainReportsWhatHappenedAndNeverDuplicates(){
    val item=payload().put("slug","qa-local-requeue")
    Store(ctx,"yoma_anime_local_downloads.db").use{db->
      try {
        assertEquals("added",db.enqueueLocal(item))
        val ep=db.list(1).first{it.slug=="qa-local-requeue"}
        // Ya en la cola: no se toca.
        assertEquals("exists",db.enqueueLocal(item));assertEquals("queued",db.get(ep.key,1)!!.state)
        db.update(ep.key,1,"state" to "downloading","bytes" to 50L)
        assertEquals("exists",db.enqueueLocal(item));assertEquals("downloading",db.get(ep.key,1)!!.state)
        // Fallida o en pausa: vuelve a la cola conservando lo descargado.
        db.update(ep.key,1,"state" to "failed","attempts" to 5,"error" to "x")
        assertEquals("requeued",db.enqueueLocal(item))
        db.get(ep.key,1)!!.let{assertEquals("queued",it.state);assertEquals(0,it.attempts);assertEquals("",it.error);assertEquals(50L,it.bytes)}
        db.update(ep.key,1,"state" to "paused")
        assertEquals("requeued",db.enqueueLocal(item));assertEquals("queued",db.get(ep.key,1)!!.state)
        // Descargado con su archivo: no se repite.
        val video=db.video(ep);video.parentFile?.mkdirs();video.writeBytes(ByteArray(64))
        db.update(ep.key,1,"state" to "done","bytes" to 64L,"total" to 64L)
        assertEquals("done",db.enqueueLocal(item));assertEquals("done",db.get(ep.key,1)!!.state)
        // Marcado como descargado pero sin archivo: se descarga de nuevo.
        assertTrue(video.delete())
        assertEquals("requeued",db.enqueueLocal(item))
        db.get(ep.key,1)!!.let{assertEquals("queued",it.state);assertEquals(0L,it.bytes);assertEquals(0L,it.total)}
        assertEquals(1,db.list(1).count{it.slug=="qa-local-requeue"})
      } finally { db.list(1).filter{it.slug=="qa-local-requeue"}.forEach{db.update(it.key,1,"state" to "queued");db.removeVideo(it)} }
    }
  }
  @Test fun localQueuePreferencesDoNotDependOnWebIdentity(){
    val web=Prefs(ctx);val before=web.owner;web.owner=777L
    val local=Prefs(ctx,true);assertEquals(1L,local.owner)
    local.paused=true;web.owner=0L;assertEquals(1L,local.owner);assertTrue(local.paused)
    web.owner=before
  }
}
