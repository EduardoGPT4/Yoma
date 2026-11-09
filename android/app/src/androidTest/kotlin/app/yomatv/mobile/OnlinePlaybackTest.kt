package app.yomatv.mobile

import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.media3.common.Player
import androidx.media3.datasource.DataSpec
import androidx.media3.exoplayer.ExoPlayer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList

@RunWith(AndroidJUnit4::class)
@androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
class OnlinePlaybackTest {
    private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=instrumentation.targetContext
    private val owner=900_110_001L
    private fun payload(revision: String="test-revision", mal: Long=12)=JSONObject().put("owner",owner).put("episode_id",777)
        .put("slug","qa-stream").put("number","1").put("title","Historia de prueba").put("language","SUB")
        .put("mal_account_id",mal).put("progress_revision",revision)
    private fun waitFor(condition:()->Boolean){val deadline=System.currentTimeMillis()+20000;while(System.currentTimeMillis()<deadline){if(condition())return;Thread.sleep(100)};assertTrue("Timed out",condition())}
    @Test fun onlineProgressIsSeparateAndIdentityChangesResetPendingMarks(){
        Store(context).use{store->
            store.writableDatabase.delete("downloads","owner=?",arrayOf(owner.toString()))
            store.writableDatabase.delete("online_playback","owner=?",arrayOf(owner.toString()))
            store.add(payload());val local=store.list(owner).single()
            store.update(local,"position" to 5000L,"duration" to 30000L)
            val online=store.openOnline(payload());assertTrue(online.online);assertEquals(5000L,online.position)
            store.update(online,"position" to 25000L,"watched" to true,"pending" to true)
            assertEquals(25000L,store.list(owner).single().position);assertTrue(store.list(owner).single().watched);assertEquals("queued",store.list(owner).single().state)
            assertNull(store.get(online.key,owner+1,true));assertTrue(store.openOnline(payload()).pending)
            val revised=store.openOnline(payload("new-revision"));assertEquals(0L,revised.position);assertFalse(revised.pending);assertFalse(revised.watched)
            store.update(online,"pending" to true,"watched" to true);assertFalse(store.get(online.key,owner,true)!!.pending)
            store.update(revised,"pending" to true)
            val otherMal=store.openOnline(payload("new-revision",99));assertFalse(otherMal.pending)
            assertEquals(1,store.list(owner).size);assertEquals(1,store.playback(owner).size)
        }
    }
    @Test fun authenticatedPlanKeepsLanguageIdentityAndNextEpisode(){
        val plan=JSONObject().put("owner",owner).put("slug","qa-stream").put("title","Historia").put("language","DUB")
            .put("mal_account_id",42).put("progress_revision","revision")
            .put("episodes",JSONArray().put(JSONObject().put("episode_id",777).put("number","1").put("next_episode_id",778)))
        val ep=OnlinePlayback.payload(plan,owner,777);assertEquals("DUB",ep.getString("language"));assertEquals(42,ep.getInt("mal_account_id"));assertEquals(778,ep.getInt("next_episode_id"))
        try{OnlinePlayback.payload(plan,owner+1,777);fail()}catch(_:IllegalArgumentException){}
        try{OnlinePlayback.payload(plan,owner,999);fail()}catch(_:java.io.IOException){}
    }
    @Test fun upgradePreservesTheDownloadedLibrary(){
        val path=java.io.File(context.cacheDir,"qa-online-upgrade.db")
        val isolated=object:android.content.ContextWrapper(context){override fun getDatabasePath(name:String)=path}
        try{
            Store(isolated).use{store->store.add(payload());store.writableDatabase.execSQL("DROP TABLE online_playback");store.writableDatabase.version=1}
            Store(isolated).use{store->assertEquals(1,store.list(owner).size);assertTrue(store.playback(owner).isEmpty());assertEquals(3,store.readableDatabase.version)}
        }finally{android.database.sqlite.SQLiteDatabase.deleteDatabase(path)}
    }
    @Test fun onlinePlayerDecodesSeeksAndUsesTheSameEightyPercentRule(){
        androidx.work.WorkManager.getInstance(context).cancelAllWork().result.get()
        Prefs(context).apply{this.owner=this@OnlinePlaybackTest.owner;paused=true;wifiOnly=true;cleanWatched=false}
        MediaServer().use{server->Store(context).use{store->
            store.writableDatabase.delete("downloads","owner=?",arrayOf(owner.toString()))
            store.writableDatabase.delete("online_playback","owner=?",arrayOf(owner.toString()))
            val ep=store.openOnline(payload(mal=0))
            val intent=Intent(context,PlayerActivity::class.java).putExtra("owner",owner).putExtra("key",ep.key).putExtra("online",true).putExtra("qa_stream",server.url)
            ActivityScenario.launch<PlayerActivity>(intent).use{scenario->
                val field=PlayerActivity::class.java.getDeclaredField("player").apply{isAccessible=true}
                waitFor{var ready=false;scenario.onActivity{val p=field.get(it)as? ExoPlayer;ready=p?.playbackState==Player.STATE_READY && p.duration>0};ready}
                scenario.onActivity{val p=field.get(it)as ExoPlayer;p.pause();p.seekTo(10000)}
                Thread.sleep(700);assertFalse(store.get(ep.key,owner,true)!!.watched)
                scenario.onActivity{(field.get(it)as ExoPlayer).seekTo(25000)}
                waitFor{store.get(ep.key,owner,true)!!.watched}
                waitFor{var ready=false;scenario.onActivity{ready=(field.get(it)as ExoPlayer).playbackState==Player.STATE_READY};ready}
                assertEquals(0,store.list(owner).size);assertTrue(store.get(ep.key,owner,true)!!.position>=24000)
                scenario.onActivity{activity->(PlayerActivity::class.java.getDeclaredField("view").apply{isAccessible=true}.get(activity)as androidx.media3.ui.PlayerView).showController()};Thread.sleep(300)
                instrumentation.uiAutomation.takeScreenshot()?.let{bitmap->
                    val file=java.io.File(context.getExternalFilesDir(null),"verification/online-player.png");file.parentFile?.mkdirs();file.outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
                }
            }
            assertTrue(server.requests.isNotEmpty());assertTrue(store.get(ep.key,owner,true)!!.position>=24000)
        }}
    }
    @Test fun streamSourceValidatesRangesAndProviderHosts(){
        MediaServer().use{server->
            val source=StreamDataSource(server.url){it.startsWith(server.base)}
            val spec=DataSpec.Builder().setUri(server.url).setPosition(64).setLength(128).build()
            assertEquals(128,source.open(spec));val buffer=ByteArray(128);assertEquals(128,source.read(buffer,0,128));assertArrayEquals(server.bytes.copyOfRange(64,192),buffer);source.close()
            assertTrue(server.requests.any{it.contains("bytes=64-191")})
            try{StreamDataSource(server.url).open(DataSpec(android.net.Uri.parse(server.url)));fail()}catch(_:IllegalArgumentException){}
        }
    }
    @Test fun liveMp4UploadPlaysAcrossTheReportedStallPosition(){
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("online_live")=="true")
        androidx.work.WorkManager.getInstance(context).cancelAllWork().result.get()
        Prefs(context).apply{this.owner=this@OnlinePlaybackTest.owner;paused=true;cleanWatched=false}
        Store(context).use{store->
            val data=payload(mal=0).put("slug","dark-summoner-to-dekiteiru").put("number","5").put("title","Dark Summoner to Dekiteiru")
            val ep=store.openOnline(data)
            val intent=Intent(context,PlayerActivity::class.java).putExtra("owner",owner).putExtra("key",ep.key).putExtra("online",true)
            ActivityScenario.launch<PlayerActivity>(intent).use{scenario->
                val field=PlayerActivity::class.java.getDeclaredField("player").apply{isAccessible=true}
                fun await(seconds:Int, condition:()->Boolean){val deadline=System.currentTimeMillis()+seconds*1000L;while(System.currentTimeMillis()<deadline){if(condition())return;Thread.sleep(200)};assertTrue("Public stream was not ready",condition())}
                val start=System.nanoTime()
                await(90){var ready=false;scenario.onActivity{val p=field.get(it)as? ExoPlayer;ready=p?.playbackState==Player.STATE_READY && p.duration>140000};ready}
                val readyMs=(System.nanoTime()-start)/1e6
                scenario.onActivity{val p=field.get(it)as ExoPlayer;p.seekTo(125000);p.play()}
                await(90){var advanced=false;scenario.onActivity{val p=field.get(it)as ExoPlayer;assertNull(p.playerError);advanced=p.currentPosition>=132000 && p.isPlaying};advanced}
                scenario.onActivity{(field.get(it)as ExoPlayer).pause()}
                assertFalse(store.get(ep.key,owner,true)!!.watched)
                val result=JSONObject().put("ok",true).put("episode","dark-summoner-to-dekiteiru/5").put("initial_ready_ms",readyMs)
                    .put("played_across_130_seconds",true).put("real_mal_write",false).put("physical_phone",false)
                val file=java.io.File(context.getExternalFilesDir(null),"verification/online-live.json");file.parentFile?.mkdirs();file.writeText(result.toString(2))
                instrumentation.sendStatus(0,android.os.Bundle().apply{putString("online_live_result",result.toString())})
            }
        }
    }
    private inner class MediaServer : AutoCloseable {
        val socket=ServerSocket(0,10,java.net.InetAddress.getByName("127.0.0.1"))
        val base="http://127.0.0.1:${socket.localPort}/"
        val url=base+"sample.mp4"
        val bytes=instrumentation.context.assets.open("sample.mp4").use{it.readBytes()}
        val requests=CopyOnWriteArrayList<String>()
        @Volatile var closed=false
        val thread=Thread{
            while(!closed)try{socket.accept().use{client->
                client.soTimeout=10000
                val reader=client.getInputStream().bufferedReader();val request=reader.readLine();var range=""
                while(true){val line=reader.readLine()?:break;if(line.isEmpty())break;if(line.startsWith("Range:",true))range=line.substringAfter(':').trim()}
                requests.add("$request $range")
                val parts=Regex("bytes=(\\d+)-(\\d*)").matchEntire(range)
                val start=parts?.groupValues?.get(1)?.toInt()?:0
                val end=(parts?.groupValues?.get(2)?.toIntOrNull()?:bytes.lastIndex).coerceAtMost(bytes.lastIndex)
                val data=bytes.copyOfRange(start,end+1)
                val headers="HTTP/1.1 ${if(parts==null)"200 OK" else "206 Partial Content"}\r\nContent-Type: video/mp4\r\nContent-Length: ${data.size}\r\nAccept-Ranges: bytes\r\n${if(parts!=null)"Content-Range: bytes $start-$end/${bytes.size}\r\n" else ""}Connection: close\r\n\r\n"
                client.getOutputStream().write(headers.toByteArray());client.getOutputStream().write(data)
            }}catch(error:Exception){if(!closed && error !is java.net.SocketException)throw error}
        }.apply{isDaemon=true;start()}
        override fun close(){closed=true;socket.close();thread.join(2000)}
    }
}
