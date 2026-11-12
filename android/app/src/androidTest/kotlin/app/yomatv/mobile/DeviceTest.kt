package app.yomatv.mobile

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkManager
import app.yomatv.engine.Integrity
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Cola local de YomaTV (la única desde Yoma 3.2.18) en un dispositivo real o emulador. */
@RunWith(AndroidJUnit4::class)
class DeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context: Context get() = instrumentation.targetContext
    private val localDatabase = "yoma_anime_local_downloads.db"
    private fun init(slug: String): Store {
        WorkManager.getInstance(context).cancelAllWork().result.get()
        Prefs(context, true).apply { paused = true; wifiOnly = true }
        val store = Store(context, localDatabase)
        for (ep in store.list(1L).filter { it.slug == slug }) {
            for (partial in listOf(false, true)) store.video(ep, partial).delete()
        }
        store.writableDatabase.delete("downloads", "owner=1 AND payload LIKE ?", arrayOf("%\"slug\":\"$slug\"%"))
        return store
    }
    private fun payload(number: Int = 1, slug: String) = JSONObject()
        .put("owner", 1L).put("episode_id", number.toLong()).put("slug", slug).put("number", number.toString()).put("title", "Historia de prueba")
        .put("language", "SUB").put("season", "otoño2026").put("mal_account_id", 0).put("progress_revision", "local-v1")
    private fun waitFor(seconds: Int = 90, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + seconds * 1000L
        while (System.currentTimeMillis() < deadline) { if (condition()) return; Thread.sleep(100) }
        assertTrue("Condition timed out after ${seconds}s", condition())
    }
    private fun report(name: String, values: JSONObject) {
        val folder = File(context.getExternalFilesDir(null), "verification").apply { mkdirs() }
        File(folder, "$name.json").writeText(values.put("physical_phone", false).put("android_api", android.os.Build.VERSION.SDK_INT).toString(2))
        instrumentation.sendStatus(0, Bundle().apply { putString("season_metrics", values.toString()) })
    }

    @Test fun databaseDeduplicatesAndRejectsUnsafeNames() {
        val slug = "qa-dedupe"
        init(slug).use { store ->
            assertTrue("first insert", store.add(payload(1, slug))); assertFalse("duplicate", store.add(payload(1, slug)))
            val ep = store.list(1L).single { it.slug == slug }; assertNull(store.get(ep.key, 2L))
            assertTrue(store.video(ep).name.contains("01"))
            try { store.add(payload(1, slug).put("slug", "../escape")); fail() } catch (_: IllegalArgumentException) {}
            store.removeVideo(ep); assertTrue(store.add(payload(1, slug))); assertEquals(1, store.list(1L).count { it.slug == slug })
        }
    }

    @Test fun hundredChaptersKeepTheirOrderAndDatabaseIsFast() {
        val slug = "qa-hundred"; val start = System.nanoTime()
        init(slug).use { store ->
            assertEquals(100, store.addBatch((1..100).map { payload(it, slug) }))
            // Fast phones can insert several chapters in the same millisecond.
            store.writableDatabase.execSQL("UPDATE downloads SET added=1000 WHERE owner=1 AND payload LIKE ?", arrayOf("%\"slug\":\"$slug\"%"))
            assertEquals((1..100).map { it.toString() }, store.list(1L).filter { it.slug == slug }.map { it.number })
        }
        val writeMs = (System.nanoTime() - start) / 1e6
        val readAt = System.nanoTime(); repeat(50) { Store(context, localDatabase).use { assertEquals(100, it.list(1L).count { ep -> ep.slug == slug }) } }
        val readMs = (System.nanoTime() - readAt) / 1e6 / 50
        report("database", JSONObject().put("insert_100_ms", writeMs).put("read_100_mean_ms", readMs))
        init(slug).close()
    }

    @Test fun existingFinalFileRecoversWithoutDownloadingAgain() {
        val slug = "qa-recover"
        init(slug).use { store ->
            assertTrue(store.add(payload(1, slug))); val ep = store.list(1L).single { it.slug == slug }
            val file = store.video(ep); file.parentFile!!.mkdirs()
            instrumentation.context.assets.open("sample.mp4").use { input -> file.outputStream().use { input.copyTo(it) } }
            store.update(ep.key, 1L, "total" to file.length())
            Prefs(context, true).apply { paused = false; wifiOnly = false }; Queue.startLocal(context, true)
            waitFor(30) { store.get(ep.key, 1L)?.state == "done" }
            assertEquals(Integrity.sha256(file), store.get(ep.key, 1L)!!.hash)
        }
        init(slug).close()
    }

    @Test fun oldWebQueueWorkDoesNothing() {
        // Un trabajo de la antigua cola de la cuenta web no descarga ni toca la cola local.
        val slug = "qa-retired"
        init(slug).use { store ->
            assertTrue(store.add(payload(1, slug)))
            val request = androidx.work.OneTimeWorkRequestBuilder<DownloadWorker>().setInputData(androidx.work.workDataOf("owner" to 77L)).build()
            val work = WorkManager.getInstance(context); work.enqueue(request).result.get()
            waitFor(20) { work.getWorkInfoById(request.id).get()?.state?.isFinished == true }
            assertEquals(androidx.work.WorkInfo.State.SUCCEEDED, work.getWorkInfoById(request.id).get()!!.state)
            assertEquals("queued", store.list(1L).single { it.slug == slug }.state)
        }
        init(slug).close()
    }

    @Test fun idleResourceUsage() {
        init("qa-idle").close()
        val scenario = ActivityScenario.launch<app.yomashi.reader.MainActivity>(Intent(context, app.yomashi.reader.MainActivity::class.java))
        Thread.sleep(3000)
        val start = android.os.Process.getElapsedCpuTime(); val wall = System.nanoTime(); Thread.sleep(5000)
        val visible = (android.os.Process.getElapsedCpuTime() - start) / ((System.nanoTime() - wall) / 1e6) * 100
        scenario.close(); Thread.sleep(1000)
        val cpu = android.os.Process.getElapsedCpuTime(); val background = System.nanoTime(); Thread.sleep(5000)
        val idle = (android.os.Process.getElapsedCpuTime() - cpu) / ((System.nanoTime() - background) / 1e6) * 100
        val memory = android.os.Debug.MemoryInfo(); android.os.Debug.getMemoryInfo(memory)
        report("idle-resources", JSONObject().put("foreground_idle_cpu_percent", visible).put("background_idle_cpu_percent", idle).put("background_pss_mib", memory.totalPss / 1024.0).put("sample_seconds", 5).put("instrumented_debug_build", true))
    }

    @Test fun liveProviderDownloadPauseResumeAndDecode() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live") == "true")
        val slug = "dark-summoner-to-dekiteiru"
        init(slug).use { store ->
            val p = payload(1, slug).put("title", "Dark Summoner to Dekiteiru")
            assertTrue(store.add(p)); val ep = store.list(1L).single { it.slug == slug }
            Prefs(context, true).apply { paused = false; wifiOnly = false }
            val started = System.nanoTime(); Queue.startLocal(context, true)
            waitFor(120) { val job = store.get(ep.key, 1L)!!; if (job.state == "failed") error(job.error); job.bytes >= 1024 * 1024 || job.state == "done" }
            val first = store.get(ep.key, 1L)!!
            if (first.state != "done") {
                store.update(ep.key, 1L, "state" to "paused")
                waitFor(30) { WorkManager.getInstance(context).getWorkInfosForUniqueWork("yoma-anime-local-downloads").get().none { it.state == androidx.work.WorkInfo.State.RUNNING } }
                assertTrue(store.video(ep, true).length() > 0)
                store.update(ep.key, 1L, "state" to "queued"); Queue.startLocal(context)
            }
            waitFor(300) { val job = store.get(ep.key, 1L)!!; if (job.state == "failed") error(job.error); job.state == "done" }
            val final = store.get(ep.key, 1L)!!
            assertTrue(final.duration > 0); assertEquals(final.total, store.video(final).length()); assertEquals(64, final.hash.length)
            report("live-download", JSONObject().put("bytes", final.bytes).put("end_to_end_seconds", (System.nanoTime() - started) / 1e9)
                .put("manual_pause_and_resume", first.state != "done").put("sha256", final.hash))
        }
        init(slug).close()
    }
}
