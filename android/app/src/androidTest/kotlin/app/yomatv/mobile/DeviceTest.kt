package app.yomatv.mobile

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkManager
import androidx.media3.exoplayer.ExoPlayer
import app.yomatv.engine.Integrity
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
@androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
class DeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context: Context get() = instrumentation.targetContext
    private fun init(owner: Long): Store {
        WorkManager.getInstance(context).cancelAllWork().result.get()
        Prefs(context).apply { this.owner=owner; paused=true; wifiOnly=true; cleanWatched=false }
        val store=Store(context)
        store.writableDatabase.delete("downloads","owner=?",arrayOf(owner.toString()))
        return store
    }
    private fun payload(owner: Long, number: Int = 1, slug: String="qa-synthetic") = JSONObject()
        .put("owner",owner).put("episode_id",number.toLong()).put("slug",slug).put("number",number.toString()).put("title","Historia de prueba")
        .put("language","SUB").put("season","otoño2026").put("mal_account_id",0).put("progress_revision","fixture-only")
    private fun waitFor(seconds: Int=90, condition:()->Boolean) {
        val deadline=System.currentTimeMillis()+seconds*1000L
        while(System.currentTimeMillis()<deadline){if(condition())return;Thread.sleep(100)}
        assertTrue("Condition timed out after ${seconds}s",condition())
    }
    private fun report(name:String, values:JSONObject) {
        val folder=File(context.getExternalFilesDir(null),"verification").apply{mkdirs()}
        File(folder,"$name.json").writeText(values.put("physical_phone",false).put("android_api",android.os.Build.VERSION.SDK_INT).toString(2))
        instrumentation.sendStatus(0,Bundle().apply{putString("season_metrics",values.toString())})
    }
    @Test fun databaseIsolatesAccountsAndDeduplicates() {
        val owner=900_260_001L
        init(owner).use{store->
            assertTrue("first insert",store.add(payload(owner)));assertFalse("duplicate",store.add(payload(owner)))
            val ep=store.list(owner).single();assertNull(store.get(ep.key,owner+1))
            assertTrue(store.video(ep).path.contains("otoño2026"));assertTrue(store.video(ep).name.contains("001"))
            try{store.add(payload(owner).put("slug","../escape"));fail()}catch(_:IllegalArgumentException){}
            store.removeVideo(ep);assertTrue(store.add(payload(owner)));assertEquals(1,store.list(owner).size)
        }
    }
    @Test fun hundredChaptersAreGroupedAndDatabaseIsFast() {
        val owner=900_260_002L;val start=System.nanoTime()
        init(owner).use { store ->
            assertEquals(100,store.addBatch((1..100).map{payload(owner,it)}))
            // Fast phones can insert several chapters in the same millisecond.
            store.writableDatabase.execSQL("UPDATE downloads SET added=1000 WHERE owner=?",arrayOf(owner))
            assertEquals((1..100).map{it.toString()},store.list(owner).map{it.number})
        }
        val writeMs=(System.nanoTime()-start)/1e6
        val readAt=System.nanoTime();repeat(50){Store(context).use{assertEquals(100,it.list(owner).size)}}
        val readMs=(System.nanoTime()-readAt)/1e6/50
        val warmAt=System.nanoTime();Store(context).use{store->repeat(50){assertEquals(100,store.list(owner).size)}}
        val warmMs=(System.nanoTime()-warmAt)/1e6/50
        val intent=Intent(context,MainActivity::class.java).putExtra("downloads",true).putExtra("qa_offline",true)
        val uiAt=System.nanoTime()
        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            Thread.sleep(1000);instrumentation.waitForIdleSync()
            scenario.onActivity { activity ->
                fun texts(view:android.view.View):List<String> = when(view){is android.widget.TextView -> listOf(view.text.toString());is android.view.ViewGroup -> (0 until view.childCount).flatMap{texts(view.getChildAt(it))};else -> emptyList()}
                val text=texts(activity.window.decorView)
                assertEquals(1,text.count{it=="Historia de prueba"});assertTrue(text.any{it.contains("100 capítulos pendientes")})
            }
            report("database-ui",JSONObject().put("insert_100_ms",writeMs).put("read_100_mean_ms",readMs).put("warm_read_100_mean_ms",warmMs).put("grouped_view_launch_ms",(System.nanoTime()-uiAt)/1e6))
        }
    }
    @Test fun offlinePlayerSeeksTo80WithoutWatchingForSeconds() {
        val owner=900_260_003L
        init(owner).use { store ->
            val p=payload(owner);assertTrue(store.add(p));val ep=store.list(owner).single();val file=store.video(ep);file.parentFile!!.mkdirs()
            instrumentation.context.assets.open("sample.mp4").use{input->file.outputStream().use{input.copyTo(it)}}
            store.update(ep.key,owner,"state" to "done","total" to file.length(),"bytes" to file.length(),"duration" to 30_000L,"hash" to Integrity.sha256(file))
            val intent=Intent(context,PlayerActivity::class.java).putExtra("key",ep.key).putExtra("owner",owner)
            val started=System.nanoTime()
            ActivityScenario.launch<PlayerActivity>(intent).use { scenario ->
                var ready=false
                waitFor { scenario.onActivity { activity ->
                    val field=PlayerActivity::class.java.getDeclaredField("player").apply{isAccessible=true}
                    val player=field.get(activity) as? ExoPlayer
                    ready=player?.playbackState==androidx.media3.common.Player.STATE_READY
                };ready }
                val readyMs=(System.nanoTime()-started)/1e6
                scenario.onActivity { activity ->
                    assertEquals(Configuration.ORIENTATION_LANDSCAPE,activity.resources.configuration.orientation)
                    val field=PlayerActivity::class.java.getDeclaredField("player").apply{isAccessible=true}
                    val player=field.get(activity) as ExoPlayer;player.pause();player.seekTo(25_000)
                }
                waitFor(10){Store(context).use{it.get(ep.key,owner)?.watched==true}}
                val marked=store.get(ep.key,owner)!!;assertTrue(marked.position>=24_000);assertTrue(marked.pending)
                report("offline-player",JSONObject().put("ready_ms",readyMs).put("seek_position_ms",marked.position).put("watched_threshold",true).put("landscape",true))
                instrumentation.uiAutomation.takeScreenshot()?.let{bitmap->
                    val folder=File(context.getExternalFilesDir(null),"verification").apply{mkdirs()};File(folder,"player.png").outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
                }
            }
            assertTrue(store.get(ep.key,owner)!!.position>=24_000)
        }
    }
    @Test fun existingFinalFileRecoversWithoutDownloadingAgain() {
        val owner=900_260_005L
        init(owner).use { store ->
            assertTrue(store.add(payload(owner)));val ep=store.list(owner).single();val file=store.video(ep);file.parentFile!!.mkdirs()
            instrumentation.context.assets.open("sample.mp4").use { input -> file.outputStream().use{input.copyTo(it)} }
            store.update(ep.key,owner,"total" to file.length())
            ActivityScenario.launch<MainActivity>(Intent(context,MainActivity::class.java).putExtra("downloads",true).putExtra("qa_offline",true)).use {
                Prefs(context).apply{paused=false;wifiOnly=false};Queue.start(context,true)
                waitFor(30){store.get(ep.key,owner)?.state=="done"}
                assertEquals(Integrity.sha256(file),store.get(ep.key,owner)!!.hash)
            }
        }
    }
    @Test fun idleResourceUsage() {
        val owner=900_260_006L;init(owner).close()
        val scenario=ActivityScenario.launch<MainActivity>(Intent(context,MainActivity::class.java).putExtra("downloads",true).putExtra("qa_offline",true))
        Thread.sleep(1000)
        val start=android.os.Process.getElapsedCpuTime();val wall=System.nanoTime();Thread.sleep(5000)
        val visible=(android.os.Process.getElapsedCpuTime()-start)/((System.nanoTime()-wall)/1e6)*100
        scenario.close();Thread.sleep(1000)
        val cpu=android.os.Process.getElapsedCpuTime();val background=System.nanoTime();Thread.sleep(5000)
        val idle=(android.os.Process.getElapsedCpuTime()-cpu)/((System.nanoTime()-background)/1e6)*100
        val memory=android.os.Debug.MemoryInfo();android.os.Debug.getMemoryInfo(memory)
        report("idle-resources",JSONObject().put("foreground_idle_cpu_percent",visible).put("background_idle_cpu_percent",idle).put("background_pss_mib",memory.totalPss/1024.0).put("sample_seconds",5).put("instrumented_debug_build",true))
    }
    @Test fun nativeApiUsesSessionCookieCsrfAndCapturedIdentity() {
        val owner=900_260_007L;init(owner).use { store ->
            assertTrue(store.add(payload(owner).put("mal_account_id",123)));val ep=store.list(owner).single()
            store.update(ep.key,owner,"position" to 25_000L,"duration" to 30_000L)
            java.net.ServerSocket(0,10,java.net.InetAddress.getByName("127.0.0.1")).use { server ->
                val base="http://127.0.0.1:${server.localPort}/";val seen=java.util.concurrent.CopyOnWriteArrayList<String>();var failure:Throwable?=null
                val thread=Thread {
                    try { repeat(3){index -> server.accept().use { socket ->
                        val reader=socket.getInputStream().bufferedReader();val first=reader.readLine();val headers=mutableMapOf<String,String>()
                        while(true){val line=reader.readLine()?:break;if(line.isBlank())break;headers[line.substringBefore(':').lowercase()]=line.substringAfter(':').trim()}
                        assertEquals("native-test=one",headers["cookie"])
                        val response=if(index==0){assertTrue(first.contains("action=mobile_session"));"{\"ok\":true,\"mobile_session\":{\"user_id\":$owner,\"csrf\":\"fixture-csrf\",\"mal_account_id\":123}}"}else{
                            assertEquals("fixture-csrf",headers["x-csrf-token"])
                            val chars=CharArray(headers["content-length"]!!.toInt());var offset=0;while(offset<chars.size){offset+=reader.read(chars,offset,chars.size-offset)}
                            val body=JSONObject(String(chars))
                            if(index==1){assertEquals("watch_scrobble",body.getString("action"));assertEquals(123,body.getInt("mal_account_id"));assertEquals(25.0,body.getDouble("position"),0.0)}
                            else{assertEquals("watched",body.getString("action"));assertFalse(body.getBoolean("watched"));assertFalse(body.has("position"));assertEquals("fixture-only",body.getString("progress_revision"))}
                            "{\"ok\":true,\"watch_sync\":{\"state\":\"synced\",\"target\":1}}"
                        }
                        seen.add(first);val bytes=response.toByteArray();socket.getOutputStream().use { it.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray());it.write(bytes) }
                    } } }catch(error:Throwable){failure=error}
                }.apply{isDaemon=true;start()}
                val cookie=java.util.concurrent.CountDownLatch(1)
                instrumentation.runOnMainSync { android.webkit.CookieManager.getInstance().setCookie(base,"native-test=one"){cookie.countDown()} }
                assertTrue(cookie.await(5,java.util.concurrent.TimeUnit.SECONDS))
                val api=WebApi(context,base);val session=api.session(owner);assertEquals("synced",api.mark(store.get(ep.key,owner)!!,session.getString("csrf")).getString("state"))
                api.markLocal(store.get(ep.key,owner)!!.copy(manualWatched=0),session.getString("csrf"))
                thread.join(5000);failure?.let{throw AssertionError(it)};assertEquals(3,seen.size)
            }
        }
    }
    @Test fun liveProviderDownloadPauseResumeAndDecode() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live")=="true")
        val owner=900_260_004L
        init(owner).use { store ->
            val p=payload(owner,1,"dark-summoner-to-dekiteiru").put("title","Dark Summoner to Dekiteiru")
            assertTrue(store.add(p));val ep=store.list(owner).single()
            for(partial in listOf(false,true))store.video(ep,partial).delete()
            val fixture=File(context.getExternalFilesDir(null),"fixtures/provider.part")
            var initialBytes=0L
            if(fixture.exists()){
                val metadata=JSONObject(File(fixture.parentFile,"resume.json").readText())
                val partial=store.video(ep,true);partial.parentFile!!.mkdirs();fixture.copyTo(partial,true);initialBytes=partial.length()
                store.update(ep.key,owner,"bytes" to initialBytes,"total" to metadata.getLong("total"),"etag" to metadata.getString("etag"),"modified" to metadata.getString("modified"))
            }
            val intent=Intent(context,MainActivity::class.java).putExtra("downloads",true).putExtra("qa_offline",true)
            ActivityScenario.launch<MainActivity>(intent).use {
                Prefs(context).apply { paused=false;wifiOnly=false }
                val started=System.nanoTime();val cpuStart=android.os.Process.getElapsedCpuTime();Queue.start(context,true)
                waitFor(120){val job=store.get(ep.key,owner)!!;if(job.state=="failed")error(job.error);job.bytes>=initialBytes+1024*1024||job.state=="done"}
                val first=store.get(ep.key,owner)!!
                if(first.state!="done"){
                    store.update(ep.key,owner,"state" to "paused")
                    waitFor(30){WorkManager.getInstance(context).getWorkInfosForUniqueWork("downloads").get().none{work->work.state==androidx.work.WorkInfo.State.RUNNING}}
                    val bytes=store.video(ep,true).length();assertTrue(bytes>0)
                    store.update(ep.key,owner,"state" to "queued");Queue.start(context)
                }
                waitFor(300){val job=store.get(ep.key,owner)!!;if(job.state=="failed")error(job.error);job.state=="done"}
                val elapsed=(System.nanoTime()-started)/1e9;val final=store.get(ep.key,owner)!!
                assertTrue(final.duration>0);assertEquals(final.total,store.video(final).length());assertEquals(64,final.hash.length)
                report("live-download",JSONObject().put("bytes",final.bytes).put("preseeded_partial_bytes",initialBytes).put("received_during_android_test",final.bytes-initialBytes)
                    .put("end_to_end_seconds",elapsed).put("mib_per_second",(final.bytes-initialBytes)/1048576.0/elapsed)
                    .put("cpu_percent",(android.os.Process.getElapsedCpuTime()-cpuStart)/(elapsed*1000)*100)
                    .put("manual_pause_and_resume",first.state!="done").put("duration_ms",final.duration).put("sha256",final.hash).put("decoder_verified",true))
            }
        }
    }
}
