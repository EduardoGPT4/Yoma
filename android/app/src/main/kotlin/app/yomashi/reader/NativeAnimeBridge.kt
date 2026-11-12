package app.yomashi.reader

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.webkit.CookieManager
import android.webkit.WebView
import android.widget.Toast
import androidx.work.WorkManager
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import app.yomatv.mobile.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterPlugin
import org.json.JSONObject

/** No JavaScriptInterface: WebKit enforces the origin and main-frame boundary. */
object NativeAnimeBridge {
    private const val playbackRequest = 50861
    private var playbackWeb = java.lang.ref.WeakReference<WebView>(null)
    private const val channelName = "app.yoma/anime"
    /** Canal hacia Flutter: la web integrada pide pantallas de Flutter, nunca actividades propias. */
    private var flutter: MethodChannel? = null
    /** Entrega a Flutter una petición ya validada; las pruebas la sustituyen. */
    @JvmStatic internal var forward: (String) -> Unit = { request ->
        (flutter ?: error("YomaTV no está listo.")).invokeMethod("open", request)
    }
    private val slugPattern = Regex("[A-Za-z0-9_-]{1,160}")
    private fun trusted(web: WebView): Boolean {
        val uri = runCatching { android.net.Uri.parse(web.url) }.getOrNull() ?: return false
        return YomaWeb.owns(uri)
    }
    fun resetIdentity(context: Context, complete: () -> Unit = {}) {
        val prefs = Prefs(context)
        val owner = prefs.owner
        prefs.owner = 0
        if (Build.VERSION.SDK_INT >= 26) {
            WorkManager.getInstance(context).cancelUniqueWork("yoma-anime-downloads")
            if (owner > 0) WorkManager.getInstance(context).cancelUniqueWork("yoma-anime-sync-$owner")
        }
        // Keep downloaded files and their owner-scoped progress. New credentials
        // must establish the web owner again before any worker can resume.
        CookieManager.getInstance().removeAllCookies {
            CookieManager.getInstance().flush()
            complete()
        }
    }
    fun register(activity: Activity, engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
        flutter = channel
        channel.setMethodCallHandler { call, result ->
            try {
                if (Build.VERSION.SDK_INT < 26) {
                    if (call.method == "attach") result.success(false)
                    else result.error("unsupported", "Las descargas de anime necesitan Android 8 o posterior.", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "attach", "detach" -> {
                        val id = (call.arguments as Number).toLong()
                        val plugin = engine.plugins.get(WebViewFlutterPlugin::class.java) as? WebViewFlutterPlugin
                        val web = plugin?.instanceManager?.getInstance<WebView>(id)
                            ?: error("El WebView ya no está disponible.")
                        if (call.method == "attach") result.success(attach(activity, web))
                        else {
                            if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) WebViewCompat.removeWebMessageListener(web, "YomaAndroid")
                            result.success(true)
                        }
                    }
                    "script" -> {
                        val css = activity.assets.open("native-layout.css").bufferedReader().use { it.readText() }
                        result.success(activity.assets.open("native-integration.js").bufferedReader().use { it.readText() }.replace("/*YOMA_NATIVE_LAYOUT*/", JSONObject.quote(css)).replace("/*YOMA_ANIME_BRAND*/", JSONObject.quote("data:image/png;base64," + android.util.Base64.encodeToString(activity.assets.open("anime-brand.png").use { it.readBytes() }, android.util.Base64.NO_WRAP))).replace(".mobile-navigation{display:none!important}", ""))
                    }
                    "resetIdentity" -> resetIdentity(activity) { result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("anime", e.message, null) }
        }
    }
    fun attach(activity: Activity, web: WebView): Boolean {
        if (Build.VERSION.SDK_INT < 26 || !WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return false
        WebViewCompat.removeWebMessageListener(web, "YomaAndroid")
        Notices.channels(activity)
        WebViewCompat.addWebMessageListener(web, "YomaAndroid", YomaWeb.ORIGINS) { view, message, sourceOrigin, mainFrame, _ ->
            if (!mainFrame || sourceOrigin.toString() !in YomaWeb.ORIGINS || !trusted(view)) return@addWebMessageListener
            val text = message.data.orEmpty()
            if (text.length > 512 * 1024) return@addWebMessageListener
            runCatching { receive(activity, view, JSONObject(text)) }.onFailure {
                Toast.makeText(activity, "No se pudo preparar el episodio: ${it.message}", Toast.LENGTH_LONG).show()
            }
        }
        return true
    }
    fun onActivityResult(context: Context, request: Int, data: Intent?) {
        if (request != playbackRequest || data == null) return
        val web = playbackWeb.get() ?: return
        val owner = data.getLongExtra("owner",0)
        if (owner <= 0 || owner != Prefs(context).owner || !trusted(web)) return
        val detail = JSONObject().put("owner",owner).put("episode_id",data.getLongExtra("episode_id",0))
        web.evaluateJavascript("window.dispatchEvent(new CustomEvent('yoma-native-playback-return',{detail:$detail}))",null)
        playbackWeb.clear()
    }
    private fun receive(activity: Activity, web: WebView, message: JSONObject) {
        val prefs = Prefs(activity)
        when (message.optString("type")) {
            "auth" -> {
                val owner = message.optLong("owner").coerceAtLeast(0)
                if (owner != prefs.owner) {
                    val previous = prefs.owner
                    WorkManager.getInstance(activity).cancelUniqueWork("yoma-anime-downloads")
                    if (previous > 0) WorkManager.getInstance(activity).cancelUniqueWork("yoma-anime-sync-$previous")
                    prefs.owner = owner
                }
                prefs.userAgent = web.settings.userAgentString
                CookieManager.getInstance().flush()
                // La cola de la cuenta web ya no se usa: las descargas son locales.
            }
            // Reproducir, descargar un episodio o elegir varios: lo hace Flutter
            // con su reproductor y su cola local; la web solo dice qué anime.
            "open" -> {
                val action = message.getString("action")
                require(action in setOf("play", "download", "episodes"))
                val slug = message.getString("slug")
                require(slugPattern.matches(slug))
                val request = JSONObject().put("action", action).put("slug", slug)
                if (action != "episodes") {
                    val episode = message.getLong("episode_id")
                    require(episode in 1..Int.MAX_VALUE.toLong())
                    request.put("episode_id", episode)
                }
                if (action == "download") {
                    val language = message.optString("language", "SUB").uppercase()
                    require(language in setOf("SUB", "LAT", "DUB"))
                    request.put("language", language)
                }
                forward(request.toString())
            }
            "account" -> web.evaluateJavascript("location.hash='#account'", null)
            // Flutter keeps its navigation and toolbar. Web messages cannot
            // request arbitrary URLs, files, intents or credential operations.
        }
    }
}
