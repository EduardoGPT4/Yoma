package app.yomatv.mobile

import app.yomashi.reader.R
import app.yomashi.reader.BuildConfig

import android.app.AlertDialog
import android.app.PictureInPictureParams
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView

@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class PlayerActivity : ComponentActivity() {
    private lateinit var store: Store
    private lateinit var episode: Episode
    private lateinit var root: FrameLayout
    private lateinit var view: PlayerView
    private lateinit var toast: TextView
    private lateinit var actions: LinearLayout
    private lateinit var caption: TextView
    private lateinit var retry: Button
    private var player: ExoPlayer? = null
    private var alreadyWatched = false
    private var thresholdSent=false
    private var suppressThreshold=false
    private var episodePlan:org.json.JSONObject?=null
    private var pickerSequence=0
    private var notifiedSync = false
    private var lastSave = 0L
    private var nextTask: Runnable? = null
    private var nextTicks = 8
    private var generation = 0
    private var preparing = false
    private var bufferingSince = 0L
    private val resolver = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            save(false)
            val current = store.get(episode.key, episode.owner, episode.online)
            if (current?.sync == "Actualizado en MyAnimeList" && !notifiedSync) {
                notifiedSync = true; slide("Capítulo ${episode.number} actualizado en MyAnimeList")
            }
            if(bufferingSince>0 && android.os.SystemClock.elapsedRealtime()-bufferingSince>30_000)retry.visibility=View.VISIBLE
            handler.postDelayed(this, 1000)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = Store(this)
        val owner = intent.getLongExtra("owner", 0)
        val found = store.get(savedInstanceState?.getString("key") ?: intent.getStringExtra("key").orEmpty(), owner, savedInstanceState?.getBoolean("online") ?: intent.getBooleanExtra("online",false))
        if (owner != Prefs(this).owner || found == null || !found.online && (found.state != "done" || !store.video(found).exists() || store.video(found).length() != found.total)) {
            Toast.makeText(this, "El capítulo no está disponible para esta cuenta.", Toast.LENGTH_LONG).show(); finish(); return
        }
        episode = found; alreadyWatched = found.watched; notifiedSync = found.sync == "Actualizado en MyAnimeList"
        thresholdSent=found.watched&&found.manualWatched<0;suppressThreshold=found.manualWatched==0
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        root = FrameLayout(this).apply { setBackgroundColor(INK) }
        view = PlayerView(this).apply { useController = true; controllerShowTimeoutMs = 2500; setShowNextButton(false); setShowPreviousButton(false); setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING) }
        root.addView(view, FrameLayout.LayoutParams(-1, -1))
        retry=control("Reintentar conexión", "Reintentar reproducción desde la misma posición") { releasePlayer();createPlayer() }.apply{visibility=View.GONE}
        root.addView(retry,FrameLayout.LayoutParams(-2,-2,Gravity.CENTER))
        actions = LinearLayout(this).apply { setPadding(dp(10), dp(4), dp(10), dp(4)); gravity = Gravity.CENTER_VERTICAL; background = background(0xdc0e0d14.toInt(), dp(16).toFloat()) }
        actions.addView(control("‹", "Cerrar reproductor") { finish() })
        caption = TextView(this).apply { text = "${episode.title} · ${episode.number}"; textSize = 16f; setTextColor(PAPER); includeFontPadding=false;gravity=Gravity.CENTER_VERTICAL;maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END }
        actions.addView(caption, LinearLayout.LayoutParams(0,-2,1f))
        actions.addView(control("Episodios", "Elegir episodio y marcar vistos") { chooseEpisode() })
        actions.addView(control("+85 s", "Saltar intro 85 segundos") { player?.let { it.seekTo((it.currentPosition + 85_000).coerceAtMost(it.duration.coerceAtLeast(0))); save(true) } })
        actions.addView(control("1×", "Velocidad de reproducción") { speed() })
        actions.addView(control("▣", "Picture in picture") {
            runCatching { enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(16,9)).build()) }
                .onFailure { slide("Este dispositivo no permite picture-in-picture.") }
        })
        actions.minimumHeight=dp(56)
        root.addView(actions, FrameLayout.LayoutParams(-1, -2, Gravity.TOP).apply { setMargins(dp(8),dp(8),dp(8),0) })
        toast = TextView(this).apply {
            textSize = 15f; setTextColor(PAPER); includeFontPadding=false;gravity=Gravity.CENTER;setLineSpacing(0f,1.15f);setPadding(dp(18), dp(12), dp(18), dp(12)); background = background(SURFACE, dp(24).toFloat()); visibility = View.GONE
        }
        root.addView(toast, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(92); leftMargin = dp(18); rightMargin = dp(18) })
        view.setControllerVisibilityListener(PlayerView.ControllerVisibilityListener { visibility -> if (!isInPictureInPictureMode) actions.visibility = visibility })
        root.setOnApplyWindowInsetsListener { _, insets ->
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                val cutout = insets.getInsets(android.view.WindowInsets.Type.displayCutout())
                root.setPadding(cutout.left, cutout.top, cutout.right, cutout.bottom)
                window.insetsController?.hide(android.view.WindowInsets.Type.systemBars())
                window.insetsController?.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
            insets
        }
        setContentView(root)
    }
    private fun control(text: String, description: String, action: () -> Unit) = Button(this).apply {
        this.text = text; contentDescription = description; isAllCaps = false; textSize = 14f; setTextColor(PAPER)
        includeFontPadding=false;gravity=Gravity.CENTER;setPadding(dp(10),dp(6),dp(10),dp(6))
        background = background(SURFACE, dp(12).toFloat()); minWidth = dp(48); minimumWidth = dp(48); minHeight = dp(48); minimumHeight = dp(48)
        setOnClickListener { action() }
    }
    private fun createPlayer() {
        if (!::episode.isInitialized || player != null || preparing) return
        if (Prefs(this).owner != episode.owner) { finish(); return }
        val current = store.get(episode.key, episode.owner, episode.online) ?: return
        retry.visibility=View.GONE
        // Prefer an intact saved copy, but keep this online session's fresh MAL identity.
        val local=if(current.online)store.get(current.key,current.owner) else current
        val file=local?.takeIf{it.state=="done"}?.let{store.video(it).takeIf{file->file.exists() && file.length()==it.total}}
        if(file!=null){startPlayer(current,android.net.Uri.fromFile(file),null);return}
        if(!current.online){slide("El archivo guardado ya no está disponible.");return}
        val request=++generation;preparing=true;slide("Abriendo capítulo online…")
        resolver.execute {
            val source=runCatching {
                val fixture=intent.getStringExtra("qa_stream").orEmpty()
                if(BuildConfig.DEBUG && Regex("http://127\\.0\\.0\\.1:[1-9][0-9]{0,4}/sample\\.mp4").matches(fixture))OnlinePlayback.Source(fixture,fixture)
                else OnlinePlayback.resolve(current)
            }
            handler.post {
                if(request!=generation || isFinishing || isDestroyed)return@post
                preparing=false
                if(Prefs(this).owner!=current.owner){finish();return@post}
                source.onSuccess{startPlayer(current,android.net.Uri.parse(it.url),it.referer)}.onFailure{
                    retry.visibility=View.VISIBLE;slide(if(it is app.yomatv.engine.ProviderChanged)it.message.orEmpty() else "No se pudo conectar con MP4Upload. Reintenta desde esta posición.")
                }
            }
        }
    }
    private fun startPlayer(current: Episode, uri: android.net.Uri, referer: String?) {
        val builder=ExoPlayer.Builder(this).setSeekBackIncrementMs(10_000).setSeekForwardIncrementMs(10_000)
        if(referer!=null){
            val factory=androidx.media3.datasource.DataSource.Factory {
                StreamDataSource(referer){url->app.yomatv.engine.Provider.allowed(url,"video") || BuildConfig.DEBUG && url==intent.getStringExtra("qa_stream") && uri.host=="127.0.0.1"}
            }
            builder.setMediaSourceFactory(DefaultMediaSourceFactory(factory))
        }
        val exo = builder.build()
        player = exo; view.player = exo
        exo.addListener(object : Player.Listener {
            override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) { save(true) }
            override fun onIsPlayingChanged(isPlaying: Boolean) { if (!isPlaying) save(true) }
            override fun onPlaybackStateChanged(playbackState: Int) {
                bufferingSince=if(playbackState==Player.STATE_BUFFERING)android.os.SystemClock.elapsedRealtime() else 0L
                if(playbackState==Player.STATE_READY)retry.visibility=View.GONE
                if (playbackState == Player.STATE_ENDED) { save(true); scheduleNext() }
            }
            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                if(current.online){retry.visibility=View.VISIBLE;slide("La reproducción se interrumpió. Reintenta sin perder tu posición.")}
                else slide("No se pudo reproducir el archivo. Usa «Verificar archivo» en Descargas.")
            }
        })
        exo.setMediaItem(MediaItem.fromUri(uri))
        val resume=if(current.duration>0 && current.position>=current.duration-5000)0 else current.position.coerceAtLeast(0)
        exo.seekTo(resume); exo.prepare(); exo.playWhenReady = true
    }
    private fun save(force: Boolean) {
        val p = player ?: return
        if (Prefs(this).owner != episode.owner) { p.pause(); finish(); return }
        val duration = p.duration
        if (duration == C.TIME_UNSET || duration <= 0) return
        val position = p.currentPosition.coerceIn(0,duration)
        if(suppressThreshold&&position.toDouble()/duration<.8)suppressThreshold=false
        val threshold = !thresholdSent && !suppressThreshold && position.toDouble() / duration >= .8
        if (force || threshold || System.currentTimeMillis() - lastSave >= 10_000) {
            store.update(episode, "position" to position, "duration" to duration)
            lastSave = System.currentTimeMillis()
        }
        if (threshold) {
            alreadyWatched = true
            thresholdSent=true
            store.update(episode, "watched" to true, "pending" to true, "manual_watched" to -1,"mark_pending" to false,"sync" to "Pendiente de MyAnimeList")
            episode=store.get(episode.key,episode.owner,episode.online)?:episode
            Queue.sync(this); slide("Capítulo ${episode.number} visto · sincronizando con MAL")
        }
    }
    private fun chooseEpisode(){
        player?.pause()
        val current=episode
        if(!current.online){showEpisodes(null);return}
        episodePlan?.let{showEpisodes(it);return}
        val request=++pickerSequence
        val loading=AlertDialog.Builder(this).setTitle("Episodios").setMessage("Cargando episodios…").setNegativeButton("Cancelar",null).create()
        loading.setOnCancelListener{pickerSequence++};loading.setOnDismissListener{if(request==pickerSequence)pickerSequence++};loading.show()
        resolver.execute{
            val result=runCatching{WebApi(this).plan(current.owner,current.episodeId,current.language)}
            handler.post{
                if(request!=pickerSequence||isFinishing||isDestroyed||current.key!=episode.key)return@post
                loading.dismiss()
                if(Prefs(this).owner!=current.owner){finish();return@post}
                result.onSuccess{episodePlan=it;showEpisodes(it)}.onFailure{AlertDialog.Builder(this).setTitle("No pudimos cargar los episodios").setMessage("Tus marcas guardadas se conservan.").setPositiveButton("Reintentar"){_,_->chooseEpisode()}.setNegativeButton("Cerrar",null).show()}
            }
        }
    }
    private fun showEpisodes(plan:org.json.JSONObject?){
        val owner=episode.owner
        val records=if(episode.online)store.list(owner)+store.playback(owner)else store.list(owner).filter{it.state!="removed"}
        val saved=records.filter{it.slug==episode.slug&&it.language==episode.language}.associateBy{it.episodeId}
        val entries=plan?.getJSONArray("episodes")
        val choices=if(entries!=null)(0 until entries.length()).map{index->
            val row=entries.getJSONObject(index);val id=row.getLong("episode_id");val local=saved[id]
            val seen=if(local?.markPending==true)local.watched else if(row.has("watched_override")&&!row.isNull("watched_override"))row.optBoolean("watched_override") else local?.watched?:row.optBoolean("watched")
            EpisodeChoice(id,"Capítulo ${row.getString("number")}",seen,id==episode.episodeId)
        } else saved.values.sortedBy{it.number.toDoubleOrNull()?:Double.MAX_VALUE}.map{EpisodeChoice(it.episodeId,"Capítulo ${it.number}",it.watched,it.episodeId==episode.episodeId,it.state=="done"&&store.video(it).exists())}
        fun resolve(choice:EpisodeChoice):Episode?=if(plan!=null)store.openOnline(OnlinePlayback.payload(plan,owner,choice.id)) else saved[choice.id]?.let{store.get(it.key,owner,it.online)}
        EpisodePicker(this,choices,open={choice->if(Prefs(this).owner==owner)resolve(choice)?.let{switchEpisode(it)}},mark={choice,value->
            if(Prefs(this).owner!=owner)false else runCatching{
                val selected=resolve(choice)?:error("Capítulo no disponible")
                store.markWatched(selected,value)
                if(choice.id==episode.episodeId){episode=store.get(episode.key,owner,episode.online)?:episode;alreadyWatched=value;if(!value){thresholdSent=false;suppressThreshold=true}}
                Queue.sync(this);slide(if(value)"Capítulo marcado como visto en YomaTV" else "Marca de visto retirada en YomaTV");true
            }.getOrElse{slide("No se pudo guardar la marca. Inténtalo de nuevo.");false}
        }).show()
    }
    private fun speed() {
        val values = floatArrayOf(.5f,.75f,1f,1.25f,1.5f,1.75f,2f)
        AlertDialog.Builder(this).setTitle("Velocidad").setItems(values.map { "$it×" }.toTypedArray()) { _, which -> player?.setPlaybackSpeed(values[which]) }.show()
    }
    private fun slide(message: String) {
        toast.animate().cancel(); toast.text = message; toast.visibility = View.VISIBLE; toast.alpha = 0f; toast.translationY = dp(18).toFloat()
        toast.animate().translationY(0f).alpha(1f).setDuration(220).withEndAction {
            toast.postDelayed({ toast.animate().alpha(0f).translationY(dp(12).toFloat()).setDuration(180).withEndAction { toast.visibility = View.GONE }.start() }, 4500)
        }.start()
    }
    private fun scheduleNext() {
        if (nextTask != null) return
        val nextId = episode.payload.optLong("next_episode_id")
        val next = store.list(episode.owner).firstOrNull { it.episodeId == nextId && it.language == episode.language && it.state == "done" && store.video(it).exists() }
        if(nextId<=0){slide("Terminaste el último capítulo disponible.");return}
        if (next == null && !episode.online) { slide("Terminaste. El siguiente capítulo todavía no está guardado."); return }
        nextTicks = 8
        toast.setOnClickListener { nextTask?.let { handler.removeCallbacks(it) }; nextTask = null; toast.setOnClickListener(null); slide("Siguiente automático cancelado") }
        val task = object : Runnable {
            override fun run() {
                if (isFinishing || Prefs(this@PlayerActivity).owner != episode.owner) return
                if (nextTicks <= 0) {
                    nextTask = null;toast.setOnClickListener(null)
                    if(episode.online)openNextOnline(nextId)else if(next!=null)switchEpisode(next)
                    return
                }
                toast.text = "${next?.let{"Capítulo ${it.number}"} ?: "Siguiente capítulo"} en ${nextTicks--} s · toca para cancelar"; toast.visibility = View.VISIBLE; toast.alpha = 1f; toast.translationY = 0f
                handler.postDelayed(this, 1000)
            }
        }
        nextTask = task; handler.post(task)
    }
    private fun openNextOnline(id: Long) {
        val current=episode;val request=++generation;preparing=true
        resolver.execute {
            val result=runCatching{WebApi(this).online(current.owner,id,current.language)}
            handler.post {
                if(request!=generation || isFinishing || isDestroyed)return@post
                preparing=false
                if(Prefs(this).owner!=current.owner){finish();return@post}
                result.onSuccess{switchEpisode(store.openOnline(it))}.onFailure{slide("No se pudo abrir el siguiente capítulo. Vuelve al listado para reintentarlo.")}
            }
        }
    }
    private fun switchEpisode(next: Episode) {
        releasePlayer();cleanupWatched();episode=next;alreadyWatched=next.watched;thresholdSent=next.watched&&next.manualWatched<0;suppressThreshold=next.manualWatched==0;notifiedSync=next.sync=="Actualizado en MyAnimeList";lastSave=0L
        caption.text="${episode.title} · ${episode.number}";createPlayer();slide("Capítulo ${next.number}")
    }
    private fun releasePlayer() { generation++;preparing=false;bufferingSince=0;save(true);if(::view.isInitialized)view.player = null; player?.release(); player = null }
    private fun cleanupWatched() {
        if (!episode.online && Prefs(this).cleanWatched && alreadyWatched) runCatching { store.get(episode.key, episode.owner)?.let { store.removeVideo(it) } }
    }
    override fun finish() {
        if(::episode.isInitialized)setResult(RESULT_OK,android.content.Intent().putExtra("episode_id",episode.episodeId).putExtra("owner",episode.owner))
        super.finish()
    }
    override fun onSaveInstanceState(outState: Bundle){if(::episode.isInitialized){outState.putString("key",episode.key);outState.putBoolean("online",episode.online)};super.onSaveInstanceState(outState)}
    override fun onStart() { super.onStart(); if (::episode.isInitialized) { createPlayer(); handler.post(tick) } }
    override fun onPictureInPictureModeChanged(inPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPictureInPictureMode,newConfig)
        actions.visibility = if (inPictureInPictureMode) View.GONE else View.VISIBLE; view.useController = !inPictureInPictureMode
    }
    override fun onStop() {
        if (::episode.isInitialized && !isInPictureInPictureMode) { nextTask?.let { handler.removeCallbacks(it) }; nextTask = null; handler.removeCallbacks(tick); releasePlayer() }
        super.onStop()
    }
    override fun onDestroy() {
        if (::episode.isInitialized) { releasePlayer(); cleanupWatched() }
        pickerSequence++;resolver.shutdownNow();handler.removeCallbacksAndMessages(null); store.close(); super.onDestroy()
    }
}
