package app.yomashi.reader

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.yomatv.mobile.Episode
import app.yomatv.mobile.Store
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WebDownloadsMigrationTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val legacyName = "yoma_anime_migration_fixture.db"
    private val slug = "migration-fixture-" + System.nanoTime()
    private val webOwner = 4242L

    private fun payload(number: String, id: Long) = JSONObject().put("owner", webOwner).put("episode_id", id)
        .put("slug", slug).put("number", number).put("language", "SUB").put("title", "Migración de prueba")
        .put("season", "otoño2026").put("mal_account_id", 77).put("progress_revision", "web-r1")

    @After fun cleanUp() {
        Store(context, WebDownloadsMigration.LOCAL_DATABASE).use { local ->
            for (ep in local.list(1L).filter { it.slug == slug }) {
                for (partial in listOf(false, true)) local.video(ep, partial).delete()
                local.update(ep.key, 1L, "state" to "removed")
            }
        }
        context.deleteDatabase(legacyName)
    }

    @Test fun webQueueMovesToTheLocalQueueWithoutDownloadingAgain() {
        Store(context, legacyName).use { legacy ->
            Store(context, WebDownloadsMigration.LOCAL_DATABASE).use { local ->
                // 1: descargado, con archivo y visto. 2: en cola. 3: «descargado» sin archivo.
                assertTrue(legacy.add(payload("1", 501)))
                assertTrue(legacy.add(payload("2", 502)))
                assertTrue(legacy.add(payload("3", 503)))
                val done = legacy.list(webOwner).first { it.number == "1" }
                val source = legacy.video(done); source.parentFile!!.mkdirs(); source.writeText("episodio uno")
                legacy.update(done.key, webOwner, "state" to "done", "bytes" to source.length(), "total" to source.length(),
                    "hash" to "huella-1", "position" to 1_400_000L, "duration" to 1_420_000L, "watched" to true)
                val missing = legacy.list(webOwner).first { it.number == "3" }
                legacy.update(missing.key, webOwner, "state" to "done", "total" to 10L)

                val size = source.length()
                val result = WebDownloadsMigration.run(legacy, local)

                assertEquals(1, result.moved); assertEquals(1, result.requeued); assertEquals(0, result.kept)
                val moved = local.get(Episode.key(1L, slug, "1", "SUB"), 1L)!!
                assertEquals("done", moved.state); assertEquals("huella-1", moved.hash)
                assertEquals(size, moved.total)
                assertEquals(1L, moved.owner); assertEquals(0L, moved.payload.getLong("mal_account_id"))
                assertEquals("local-v1", moved.payload.getString("progress_revision"))
                assertEquals("episodio uno", local.video(moved).readText())
                assertFalse(source.exists())
                assertEquals("queued", local.get(Episode.key(1L, slug, "2", "SUB"), 1L)!!.state)
                // Sin archivo no se vuelve a descargar solo.
                assertNull(local.get(Episode.key(1L, slug, "3", "SUB"), 1L))
                assertTrue(legacy.list(webOwner).all { it.state == "removed" })
                val seen = (0 until result.progress.length()).map { result.progress.getJSONObject(it) }
                assertEquals(listOf("1"), seen.map { it.getString("number") })
                assertTrue(seen.single().getBoolean("watched")); assertEquals(1_400_000L, seen.single().getLong("position"))

                // Una segunda vez no hace nada.
                val again = WebDownloadsMigration.run(legacy, local)
                assertEquals(0, again.moved + again.requeued + again.kept)
            }
        }
    }

    @Test fun anExistingLocalCopyIsKeptAndTheDuplicateRemoved() {
        Store(context, legacyName).use { legacy ->
            Store(context, WebDownloadsMigration.LOCAL_DATABASE).use { local ->
                assertTrue(legacy.add(payload("1", 601)))
                val ep = legacy.list(webOwner).single()
                val source = legacy.video(ep); source.parentFile!!.mkdirs(); source.writeText("misma copia")
                legacy.update(ep.key, webOwner, "state" to "done", "total" to source.length(), "bytes" to source.length())
                val localPayload = WebDownloadsMigration.localPayload(payload("1", 601))
                assertTrue(local.adoptDone(localPayload, source.length(), "local"))
                val existing = local.get(Episode.key(1L, slug, "1", "SUB"), 1L)!!
                val target = local.video(existing); target.parentFile!!.mkdirs(); target.writeText("misma copia")

                val result = WebDownloadsMigration.run(legacy, local)

                assertEquals(1, result.moved)
                assertEquals("misma copia", target.readText()); assertFalse(source.exists())
                assertEquals("local", local.get(existing.key, 1L)!!.hash)
            }
        }
    }
}
