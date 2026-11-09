package app.yomatv.mobile

import android.app.Application
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Environment
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

class YomaApp : Application() {
    override fun onCreate() { super.onCreate(); if (android.os.Build.VERSION.SDK_INT >= 26) Notices.channels(this) }
}

class Prefs(context: Context, private val local: Boolean = false) {
    private val p = context.getSharedPreferences(if (local) "yoma_anime_local_private" else "yoma_anime_private", Context.MODE_PRIVATE)
    var owner: Long get() = if (local) 1L else p.getLong("owner", 0); set(v) { p.edit().putLong("owner", v).apply() }
    var userAgent: String get() = p.getString("agent", "").orEmpty(); set(v) { p.edit().putString("agent", v).apply() }
    var wifiOnly: Boolean get() = p.getBoolean("wifi", true); set(v) { p.edit().putBoolean("wifi", v).apply() }
    var paused: Boolean get() = p.getBoolean("paused", false); set(v) { p.edit().putBoolean("paused", v).apply() }
    var cleanWatched: Boolean get() = p.getBoolean("clean", false); set(v) { p.edit().putBoolean("clean", v).apply() }
}

data class Episode(val payload: JSONObject, val state: String, val bytes: Long, val total: Long,
                   val etag: String, val modified: String, val position: Long, val duration: Long,
                   val watched: Boolean, val pending: Boolean, val sync: String, val error: String,
                   val attempts: Int, val speed: Double, val hash: String, val online: Boolean = false,
                   val manualWatched: Int = -1, val markPending: Boolean = false) {
    val owner get() = payload.getLong("owner")
    val episodeId get() = payload.getLong("episode_id")
    val slug get() = payload.getString("slug")
    val title get() = payload.getString("title")
    val number get() = payload.getString("number")
    val language get() = payload.optString("language", "SUB")
    val key get() = key(owner, slug, number, language)
    companion object {
        fun key(owner: Long, slug: String, number: String, language: String): String =
            MessageDigest.getInstance("SHA-256").digest("$owner:$slug:$number:$language".toByteArray()).joinToString("") { "%02x".format(it) }
    }
}

class Store(private val context: Context, private val databaseName: String = "yoma_anime.db") : SQLiteOpenHelper(context, databaseName, null, 3) {
    override fun onConfigure(db: SQLiteDatabase) { db.enableWriteAheadLogging() }
    override fun onCreate(db: SQLiteDatabase) {
        createTable(db, "downloads")
        createTable(db, "online_playback")
    }
    private fun createTable(db: SQLiteDatabase, table: String) {
        db.execSQL("""CREATE TABLE $table(id TEXT PRIMARY KEY,owner INTEGER NOT NULL,payload TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'queued',bytes INTEGER NOT NULL DEFAULT 0,total INTEGER NOT NULL DEFAULT 0,
            etag TEXT NOT NULL DEFAULT '',modified TEXT NOT NULL DEFAULT '',position INTEGER NOT NULL DEFAULT 0,
            duration INTEGER NOT NULL DEFAULT 0,watched INTEGER NOT NULL DEFAULT 0,pending INTEGER NOT NULL DEFAULT 0,
            sync TEXT NOT NULL DEFAULT '',error TEXT NOT NULL DEFAULT '',attempts INTEGER NOT NULL DEFAULT 0,
            speed REAL NOT NULL DEFAULT 0,hash TEXT NOT NULL DEFAULT '',manual_watched INTEGER NOT NULL DEFAULT -1,
            mark_pending INTEGER NOT NULL DEFAULT 0,added INTEGER NOT NULL)""")
        db.execSQL("CREATE INDEX ${table}_owner_state ON $table(owner,state,added)")
    }
    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {
        if(old<2)createTable(db,"online_playback")
        if(old<3)for(table in listOf("downloads","online_playback")){
            val columns=mutableSetOf<String>();db.rawQuery("PRAGMA table_info($table)",null).use{while(it.moveToNext())columns.add(it.getString(it.getColumnIndexOrThrow("name")))}
            if("manual_watched" !in columns)db.execSQL("ALTER TABLE $table ADD COLUMN manual_watched INTEGER NOT NULL DEFAULT -1")
            if("mark_pending" !in columns)db.execSQL("ALTER TABLE $table ADD COLUMN mark_pending INTEGER NOT NULL DEFAULT 0")
        }
    }
    private fun validate(payload: JSONObject) {
        val owner = payload.getLong("owner"); val slug = payload.getString("slug")
        val number = payload.getString("number"); val language = payload.getString("language")
        require(owner > 0 && payload.getLong("episode_id") > 0)
        require(Regex("[A-Za-z0-9_-]{1,160}").matches(slug) && Regex("\\d{1,6}(?:\\.\\d{1,3})?").matches(number))
        require(language in setOf("SUB", "LAT", "DUB") && payload.getString("title").length in 1..500)
        require(payload.toString().length < 8192)
    }
    fun add(payload: JSONObject): Boolean {
        validate(payload)
        val owner = payload.getLong("owner"); val slug = payload.getString("slug")
        val number = payload.getString("number"); val language = payload.getString("language")
        val key = Episode.key(owner, slug, number, language)
        val values = ContentValues().apply {
            put("id", key); put("owner", owner); put("payload", payload.toString()); put("added", System.currentTimeMillis())
            put("watched", if (payload.optBoolean("watched")) 1 else 0)
            if(payload.has("watched_override")&&!payload.isNull("watched_override"))put("manual_watched",if(payload.optBoolean("watched_override"))1 else 0)
        }
        if (writableDatabase.insertWithOnConflict("downloads", null, values, SQLiteDatabase.CONFLICT_IGNORE) != -1L) return true
        val reset = ContentValues().apply {
            put("payload", payload.toString()); put("state", "queued"); put("bytes", 0); put("total", 0)
            put("etag", ""); put("modified", ""); put("hash", ""); put("attempts", 0); put("error", ""); put("speed", 0)
        }
        return writableDatabase.update("downloads", reset, "id=? AND owner=? AND state='removed'", arrayOf(key, owner.toString())) == 1
    }
    fun list(owner: Long): List<Episode> = read("owner=?", arrayOf(owner.toString()))
    fun playback(owner: Long): List<Episode> = read("owner=?", arrayOf(owner.toString()), true)
    /** Online progress never becomes a download job or changes a downloaded file's identity. */
    @Synchronized fun openOnline(payload: JSONObject): Episode {
        validate(payload)
        val owner=payload.getLong("owner")
        val key=Episode.key(owner,payload.getString("slug"),payload.getString("number"),payload.getString("language"))
        val previous=get(key,owner,true)
        val local=get(key,owner)
        val seed=listOfNotNull(previous,local).firstOrNull{it.markPending} ?: previous ?: local
        val sameIdentity=seed != null && seed.payload.optLong("mal_account_id")==payload.optLong("mal_account_id") &&
            seed.payload.optString("progress_revision")==payload.optString("progress_revision")
        val values=ContentValues().apply {
            put("id",key);put("owner",owner);put("payload",payload.toString());put("state","online");put("added",System.currentTimeMillis())
            put("position",if(sameIdentity)seed!!.position else 0L);put("duration",if(sameIdentity)seed!!.duration else 0L)
            val remote=if(payload.has("watched_override")&&!payload.isNull("watched_override"))if(payload.optBoolean("watched_override"))1 else 0 else -1
            val manual=if(sameIdentity&&seed!!.markPending)seed.manualWatched else if(payload.has("watched_override"))remote else if(sameIdentity)seed!!.manualWatched else -1
            put("manual_watched",manual);put("mark_pending",if(sameIdentity && seed!!.markPending)1 else 0)
            put("watched",if(if(manual>=0)manual==1 else payload.optBoolean("watched") || sameIdentity && seed!!.watched)1 else 0)
            put("pending",if(sameIdentity && seed!!.pending)1 else 0);put("sync",if(sameIdentity)seed!!.sync else "")
        }
        writableDatabase.insertWithOnConflict("online_playback",null,values,SQLiteDatabase.CONFLICT_REPLACE)
        return get(key,owner,true)!!
    }
    fun addBatch(payloads: List<JSONObject>): Int {
        var count = 0
        writableDatabase.beginTransaction()
        try {
            for (payload in payloads) if (add(payload)) count++
            writableDatabase.setTransactionSuccessful()
        } finally { writableDatabase.endTransaction() }
        return count
    }
    fun markWatched(ep: Episode, value: Boolean) {
        update(ep,"manual_watched" to if(value)1 else 0,"mark_pending" to true,"watched" to value,"pending" to false,
            "sync" to if(value)"Visto en YomaTV · pendiente de guardar" else "Sin ver en YomaTV · pendiente de guardar")
    }
    fun get(id: String, owner: Long, online: Boolean = false): Episode? = read("id=? AND owner=?", arrayOf(id, owner.toString()), online).firstOrNull()
    private fun read(where: String, values: Array<String>, online: Boolean = false): List<Episode> {
        val rows = mutableListOf<Episode>()
        readableDatabase.query(if(online)"online_playback" else "downloads", null, where, values, null, null, "added,rowid").use { cursor ->
            fun s(key: String) = cursor.getString(cursor.getColumnIndexOrThrow(key))
            fun l(key: String) = cursor.getLong(cursor.getColumnIndexOrThrow(key))
            while (cursor.moveToNext()) rows.add(Episode(JSONObject(s("payload")), s("state"), l("bytes"), l("total"), s("etag"), s("modified"), l("position"), l("duration"), l("watched") == 1L, l("pending") == 1L, s("sync"), s("error"), l("attempts").toInt(), cursor.getDouble(cursor.getColumnIndexOrThrow("speed")), s("hash"),online,l("manual_watched").toInt(),l("mark_pending")==1L))
        }
        return rows
    }
    @Synchronized fun update(key: String, owner: Long, vararg fields: Pair<String, Any>) {
        updateTable("downloads",key,owner,null,*fields)
    }
    @Synchronized fun update(ep: Episode, vararg fields: Pair<String, Any>) {
        writableDatabase.beginTransaction()
        try{
            val changed=updateTable(if(ep.online)"online_playback" else "downloads",ep.key,ep.owner,ep,*fields)
            // A saved copy and a streamed copy share watch progress, never file/job state.
            val progress=fields.filter{it.first in setOf("position","duration","watched","pending","sync","manual_watched","mark_pending")}.toTypedArray()
            if(changed>0 && progress.isNotEmpty())updateTable(if(ep.online)"downloads" else "online_playback",ep.key,ep.owner,ep,*progress)
            writableDatabase.setTransactionSuccessful()
        }finally{writableDatabase.endTransaction()}
    }
    private fun updateTable(table: String,key: String, owner: Long, expected: Episode?, vararg fields: Pair<String, Any>): Int {
        var where="id=? AND owner=?";var args=arrayOf(key,owner.toString())
        if(expected!=null){
            val record=readableDatabase.query(table,arrayOf("payload","manual_watched"),where,args,null,null,null).use{if(it.moveToFirst())it.getString(0) to it.getInt(1) else null} ?: return 0
            val raw=record.first
            if(record.second!=expected.manualWatched)return 0
            val snapshot=JSONObject(raw)
            if(snapshot.optLong("mal_account_id")!=expected.payload.optLong("mal_account_id") || snapshot.optString("progress_revision")!=expected.payload.optString("progress_revision"))return 0
            where+=" AND payload=? AND manual_watched=?";args+=arrayOf(raw,record.second.toString())
        }
        val values = ContentValues()
        for ((name, value) in fields) {
            require(name in setOf("state","bytes","total","etag","modified","position","duration","watched","pending","sync","error","attempts","speed","hash","manual_watched","mark_pending"))
            when (value) {
                is String -> values.put(name, value); is Long -> values.put(name, value); is Int -> values.put(name, value)
                is Boolean -> values.put(name, if (value) 1 else 0); is Double -> values.put(name, value)
            }
        }
        return writableDatabase.update(table, values, where, args)
    }
    fun recover(owner: Long) { writableDatabase.execSQL("UPDATE downloads SET state='queued',speed=0 WHERE owner=? AND state IN ('downloading','verifying')", arrayOf(owner)) }
    fun claim(ep: Episode): Boolean = writableDatabase.update("downloads", ContentValues().apply { put("state", "downloading"); put("error", ""); put("speed", 0) },
        "id=? AND owner=? AND state IN ('queued','retry')", arrayOf(ep.key, ep.owner.toString())) == 1
    fun video(ep: Episode, partial: Boolean = false): File {
        val base = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: context.filesDir
        val root = File(base, "Yoma/YomaTV/EpisodiosDescargados")
        val season = ep.payload.optString("season").takeIf { Regex("(?:invierno|primavera|verano|otoño)\\d{4}").matches(it) } ?: "biblioteca"
        val number = ep.number.substringBefore('.').padStart(4, '0') + ep.number.substringAfter('.', "").let { if (it.isEmpty()) "" else ".$it" }
        val title = ep.title.replace(Regex("[<>:\"/\\\\|?*\\p{Cntrl}]"), "_").trim(' ', '.').take(90).ifBlank { ep.slug }
        val ownerFolder = if(databaseName=="yoma_anime_local_downloads.db")"local" else ep.owner.toString()
        val file = File(root, "$ownerFolder/$season/${ep.slug}/capitulos/$title - $number [${ep.language}].mp4${if (partial) ".part" else ""}")
        require(file.canonicalPath.startsWith(root.canonicalPath + File.separator))
        return file
    }
    fun removeVideo(ep: Episode) {
        writableDatabase.beginTransaction()
        try {
            val current = get(ep.key, ep.owner) ?: return
            if (current.state in setOf("downloading", "verifying")) error("Pausa el capítulo antes de eliminarlo.")
            for (partial in listOf(false, true)) {
                val file = video(current, partial)
                if (file.exists() && !file.delete()) error("No se pudo eliminar el archivo.")
            }
            update(ep.key, ep.owner, "state" to "removed", "bytes" to 0L, "total" to 0L, "speed" to 0.0)
            writableDatabase.setTransactionSuccessful()
        } finally { writableDatabase.endTransaction() }
    }
}
