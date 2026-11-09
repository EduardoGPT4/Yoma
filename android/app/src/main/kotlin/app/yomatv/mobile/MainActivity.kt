package app.yomatv.mobile

import app.yomashi.reader.R
import app.yomashi.reader.BuildConfig

import android.Manifest
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import androidx.work.WorkInfo
import androidx.work.WorkManager
import org.json.JSONObject

const val INK = 0xff0e0d14.toInt()
const val SURFACE = 0xff1b1925.toInt()
const val PAPER = 0xfff4eee5.toInt()
const val MUTED = 0xffb4adbf.toInt()
const val ACCENT = 0xffff6a55.toInt()
const val MINT = 0xffaee6c9.toInt()

fun android.content.Context.dp(value: Int) = (value * resources.displayMetrics.density).toInt()
fun background(color: Int, radius: Float = 18f) = GradientDrawable().apply { setColor(color); cornerRadius = radius }

class MainActivity : ComponentActivity() {
    private val onlinePlayer=registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { result ->
        val data=result.data
        if(::web.isInitialized && data!=null && data.getLongExtra("owner",0)==prefs.owner){
            val detail=JSONObject().put("owner",prefs.owner).put("episode_id",data.getLongExtra("episode_id",0))
            web.evaluateJavascript("window.dispatchEvent(new CustomEvent('yoma-native-playback-return',{detail:$detail}))",null)
        }
    }
    private lateinit var web: WebView
    private lateinit var root: LinearLayout
    private lateinit var content: FrameLayout
    private lateinit var nav: LinearLayout
    private lateinit var title: TextView
    private lateinit var header: LinearLayout
    private lateinit var accountAvatar: AccountAvatar
    private lateinit var prefs: Prefs
    private var page = "web"
    private var activeTab = "catalog"
    private val webTabs = linkedMapOf<String, WebView>()
    private val readyTabs = mutableSetOf<String>()
    private val restoredTabs = mutableMapOf<String, Bundle>()
    private val nativeScroll = mutableMapOf<String, Int>()
    private var downloadFilter = "all"
    private var userName = ""
    private var userPicture = ""
    private var malConnected = false
    private var group: String? = null
    private var signature = ""
    private var running = false
    private val queries = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var reading = false
    private var queryStore: Store? = null
    private var pendingSync = false
    private var resumed = false
    private var webReady = false
    private var pendingAccount = false
    private var accountReturnPage = "web"
    private var accountReturnTab = "catalog"
    private var downloadsPanel: DownloadsPanel? = null
    private var downloadsOwner = -1L
    private val handler = Handler(Looper.getMainLooper())
    private var fullscreen: View? = null
    private var fullCallback: WebChromeClient.CustomViewCallback? = null
    private val nativePresentation by lazy {
        val css=assets.open("native-layout.css").bufferedReader().use{it.readText()}
        assets.open("native-integration.js").bufferedReader().use{it.readText()}
            .replace("/*YOMA_NATIVE_LAYOUT*/",JSONObject.quote(css))
            .replace("/*YOMA_ANIME_BRAND*/",JSONObject.quote("data:image/png;base64,"+android.util.Base64.encodeToString(assets.open("anime-brand.png").use{it.readBytes()},android.util.Base64.NO_WRAP)))
    }
    private val tick = object : Runnable {
        override fun run() { if (resumed && page == "downloads") renderDownloads() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(INK) }
        root.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout())
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            } else view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            insets
        }
        header = LinearLayout(this).apply { gravity = android.view.Gravity.CENTER_VERTICAL; setPadding(dp(18), dp(8), dp(12), dp(8)) }
        val logo = ImageView(this).apply { setImageResource(R.drawable.anime_brand); contentDescription = "YomaTV" }
        header.addView(logo, LinearLayout.LayoutParams(dp(38), dp(38)).apply { rightMargin = dp(12) })
        title = label("YomaTV", 24, PAPER, true).apply{setPadding(0,0,0,0);minHeight=dp(48);maxLines=1;ellipsize=android.text.TextUtils.TruncateAt.END}
        header.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
        fun headerAction(kind:String,name:String,action:()->Unit){
            val item=FrameLayout(this).apply{background=outlined(SURFACE,dp(24).toFloat());contentDescription=name;isFocusable=true;isClickable=true;setOnClickListener{action()}}
            item.addView(NavGlyph(this,kind),FrameLayout.LayoutParams(dp(23),dp(23),android.view.Gravity.CENTER))
            header.addView(item,LinearLayout.LayoutParams(dp(44),dp(44)).apply{leftMargin=dp(9)})
        }
        headerAction("notifications","Notificaciones"){webRoute("notifications")}
        accountAvatar=AccountAvatar(this).apply{
            contentDescription="Mi cuenta";isFocusable=true;isClickable=true
            setOnClickListener{openWebAccount()}
        }
        header.addView(accountAvatar,LinearLayout.LayoutParams(dp(44),dp(44)).apply{leftMargin=dp(9)})
        root.addView(header)
        content = FrameLayout(this)
        root.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
        nav = LinearLayout(this).apply {
            isBaselineAligned=false
            setPadding(dp(8), dp(4), dp(8), dp(4)); background = outlined(SURFACE, dp(26).toFloat())
            elevation = dp(6).toFloat()
        }
        listOf("catalog" to "Inicio", "schedule" to "Temporada", "downloads" to "Descargas", "more" to "Más").forEach { (key, name) ->
            val item=NavigationTab(this,key,name).apply {
                setOnClickListener { selectTab(key) }
            }
            nav.addView(item,LinearLayout.LayoutParams(0,-1,1f))
        }
        root.addView(nav,LinearLayout.LayoutParams(-1,-2).apply { setMargins(dp(10),0,dp(10),dp(4)) });setContentView(root)
        savedInstanceState?.let { saved ->
            activeTab=saved.getString("activeTab","catalog");group=saved.getString("downloadGroup")
            downloadFilter=saved.getString("downloadFilter","all")
            for(key in listOf("catalog","schedule","more","account"))saved.getBundle("web-$key")?.let{restoredTabs[key]=it}
            for(key in listOf("downloads","more","settings"))nativeScroll[key]=saved.getInt("scroll-$key",0)
            accountReturnPage=saved.getString("accountReturnPage","web");accountReturnTab=saved.getString("accountReturnTab","catalog")
        }
        web = webFor(if(activeTab in setOf("catalog","schedule","more"))activeTab else "catalog")
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                when { fullscreen != null -> exitFullscreen(); page == "account" -> closeWebAccount(); page == "downloads" && group != null -> { group = null; signature = ""; renderDownloads() }; page == "settings" -> if(activeTab=="downloads")show("downloads")else moreMenu(); page == "more" -> selectTab("catalog"); page != "web" -> selectTab("catalog"); web.canGoBack() -> web.goBack(); else -> finish() }
            }
        })
        WorkManager.getInstance(this).getWorkInfosForUniqueWorkLiveData("yoma-anime-downloads").observe(this) { infos ->
            running = infos.any { it.state == WorkInfo.State.RUNNING }; if (page == "downloads") { signature = ""; renderDownloads() }
        }
        if(savedInstanceState?.getString("nativePage")=="account"){
            web=webFor("account");webReady="account" in readyTabs;show("account");pendingAccount=!webReady
        }else selectTab(if (savedInstanceState==null&&intent.getBooleanExtra("downloads", false)) "downloads" else activeTab)
        intent.getStringExtra("yoma_plan")?.let { encoded ->
            require(encoded.length <= 512 * 1024)
            val plan = JSONObject(encoded)
            root.post { choose(plan) }
        }
        if (!(BuildConfig.DEBUG && intent.getBooleanExtra("qa_offline", false))) {
            Queue.start(this); Queue.sync(this)
        }
    }

    private fun webFor(key: String): WebView = webTabs.getOrPut(key) {
        val web = WebView(this)
        web.setBackgroundColor(INK)
        web.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true
            allowFileAccess = false; allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            setSupportMultipleWindows(false)
        }
        prefs.userAgent = web.settings.userAgentString
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false)
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(web, "YomaAndroid", setOf("https://hk-br035.gt.tc")) { view, message, origin, mainFrame, _ ->
                if (mainFrame && origin.scheme == "https" && origin.host == "hk-br035.gt.tc" && origin.port in setOf(-1,443) && trusted(view.url)) {
                    val data = message.data.orEmpty()
                    if (data.length <= 512 * 1024) runCatching { receive(JSONObject(data), view, key) }.onFailure { toast("No se pudo preparar la descarga. Abre de nuevo la ficha.") }
                }
            }
        } else toast("Actualiza Android System WebView para habilitar las descargas desde el catálogo.")
        web.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) { readyTabs.remove(key); if (isActiveBrowser(web)) webReady = false }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!request.isForMainFrame) return false
                val uri = request.url
                if (trusted(uri.toString()) || uri.scheme == "https" && uri.host in setOf("myanimelist.net", "www.myanimelist.net")) return false
                if (uri.scheme == "https") runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                return true
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (trusted(url)) {
                    view.evaluateJavascript(nativePresentation, null)
                    CookieManager.getInstance().flush()
                }
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) { readyTabs.remove(key); if(isActiveBrowser(web))webReady=false; if(isWebPage()&&isActiveBrowser(web)){toast("Sin conexión. Tus capítulos guardados siguen disponibles.");if(prefs.owner>0)selectTab("downloads")} }
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                if (fullscreen != null) { callback.onCustomViewHidden(); return }
                fullscreen = view; fullCallback = callback
                root.visibility = View.GONE
                addContentView(view, ViewGroup.LayoutParams(-1, -1))
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                if (Build.VERSION.SDK_INT >= 30) window.insetsController?.hide(android.view.WindowInsets.Type.systemBars())
            }
            override fun onHideCustomView() { exitFullscreen() }
        }
        val restored=restoredTabs.remove(key)
        if(restored!=null)web.restoreState(restored)
        if(web.url==null && key!="more" && !(BuildConfig.DEBUG && intent.getBooleanExtra("qa_offline",false)))web.loadUrl(SITE+when(key){"schedule"->"#schedule";"account"->"#account";else->"#discover"})
        web
    }
    private fun isWebPage()=page in setOf("web","account")
    private fun isActiveBrowser(candidate:WebView)=::web.isInitialized && candidate===web
    private fun rememberNativeScroll() {
        (content.getChildAt(0) as? ScrollView)?.let{nativeScroll[page]=it.scrollY}
    }
    private fun selectTab(key: String) {
        rememberNativeScroll()
        if(::web.isInitialized && isWebPage())suspendWeb()
        activeTab=key
        when(key){
            "downloads"->show("downloads")
            "more"->show("more")
            else->{web=webFor(key);webReady=key in readyTabs;show("web")}
        }
    }
    override fun onSaveInstanceState(out: Bundle) {
        rememberNativeScroll();out.putString("activeTab",activeTab);out.putString("downloadGroup",group);out.putString("downloadFilter",downloadFilter)
        out.putString("nativePage",page);out.putString("accountReturnPage",accountReturnPage);out.putString("accountReturnTab",accountReturnTab)
        webTabs.forEach{(key,view)->out.putBundle("web-$key",Bundle().also{view.saveState(it)})}
        nativeScroll.forEach{(key,value)->out.putInt("scroll-$key",value)}
        super.onSaveInstanceState(out)
    }

    private fun trusted(url: String?): Boolean {
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
        return uri.scheme == "https" && uri.host == "hk-br035.gt.tc" && uri.port == -1 && uri.userInfo == null && uri.path?.startsWith("/seasonav1/") == true
    }
    private fun exitFullscreen() {
        fullscreen?.let { (it.parent as? ViewGroup)?.removeView(it) }; fullscreen = null
        fullCallback?.onCustomViewHidden(); fullCallback = null; root.visibility = View.VISIBLE
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        if (Build.VERSION.SDK_INT >= 30) window.insetsController?.show(android.view.WindowInsets.Type.systemBars())
    }
    private fun receive(message: JSONObject, source: WebView = web, key: String = activeTab) {
        if(source!==web && message.optString("type") in setOf("auth","plan","play_online"))return
        when (message.optString("type")) {
            "auth" -> {
                readyTabs.add(key); if(source === web)webReady = true
                userName=message.optString("name");malConnected=message.optBoolean("mal")
                val owner = message.optLong("owner").coerceAtLeast(0)
                userPicture=if(owner>0&&malConnected)AccountAvatar.picture(message.optString("avatar"))else ""
                accountAvatar.bind(if(owner>0)userName else "",userPicture)
                content.findViewWithTag<AccountAvatar>("more-account-avatar")?.bind(if(owner>0)userName else "",userPicture)
                if (owner != prefs.owner) {
                    WorkManager.getInstance(this).cancelUniqueWork("yoma-anime-downloads"); prefs.owner = owner; group = null; signature = ""
                    // Hidden tabs must not restore another account's cached library.
                    webTabs.keys.filter{it!=key}.toList().forEach { other ->
                        webTabs.remove(other)?.let{old -> (old.parent as? ViewGroup)?.removeView(old);old.destroy()}
                        readyTabs.remove(other);restoredTabs.remove(other)
                    }
                    downloadsPanel=null;downloadsOwner=-1;nativeScroll.remove("downloads")
                    if (page == "downloads") content.removeAllViews()
                }
                if (owner > 0) { CookieManager.getInstance().flush(); Queue.start(this); Queue.sync(this) }
                if (page == "downloads") renderDownloads()
                if (pendingAccount) { pendingAccount=false; openWebAccount() }
            }
            "plan" -> choose(message)
            "play_online" -> {
                if(!isWebPage() || message.optString("server")!="MP4Upload")return
                val owner=message.getLong("owner")
                require(owner>0 && owner==prefs.owner)
                val payload=OnlinePlayback.payload(message,owner,message.getLong("episode_id"))
                val ep=Store(this).use{it.openOnline(payload)}
                suspendWeb()
                onlinePlayer.launch(Intent(this,PlayerActivity::class.java).putExtra("owner",owner).putExtra("key",ep.key).putExtra("online",true))
            }
            "account" -> if(source===web)openWebAccount()
            "navigation" -> if(source === web) updateNav(message.optString("route"))
            "more" -> { activeTab="more";show("more") }
            "notifications" -> web.evaluateJavascript("document.querySelector('#notifications-toggle')?.click()",null)
        }
    }
    private fun choose(plan: JSONObject) {
        val owner = plan.getLong("owner")
        if (owner <= 0 || owner != prefs.owner) { toast("La cuenta cambió. Abre de nuevo el anime."); return }
        val episodes = plan.getJSONArray("episodes"); require(episodes.length() in 1..10000)
        val slug = plan.getString("slug"); val language = plan.optString("language", "SUB")
        val existing = Store(this).use { store -> store.list(owner).filter { it.state != "removed" }.map { ep ->
                    if(ep.state=="done" && (!store.video(ep).exists() || store.video(ep).length()!=ep.total)){
                        val partial=store.video(ep,true).takeIf{it.exists()}?.length()?:0L
                        store.update(ep.key,owner,"state" to "failed","bytes" to partial,"speed" to 0.0,"error" to "El archivo ya no está disponible en el dispositivo.")
                        ep.copy(state="failed",bytes=partial,speed=0.0,error="El archivo ya no está disponible en el dispositivo.")
                    }else ep
                }.associateBy { it.key } }
        val entries = (0 until episodes.length()).map { episodes.getJSONObject(it) }
            .filter { Episode.key(owner, slug, it.getString("number"), language) !in existing }
            .sortedBy { it.getString("number").toDoubleOrNull() ?: Double.MAX_VALUE }
        if (entries.isEmpty()) { toast("Estos capítulos ya están descargados o en tu cola. Ábrelos en Descargas."); show("downloads"); return }
        val checked = BooleanArray(entries.size)
        entries.indices.filter { !entries[it].optBoolean("watched") }.take(3).forEach { checked[it] = true }
        if (entries.size == 1) checked[0] = true
        val labels = entries.map { "Capítulo ${it.getString("number")}${if (it.optBoolean("watched")) " · visto" else ""}" }.toTypedArray()
        val dialog = AlertDialog.Builder(this).setTitle("${plan.getString("title")} · $language")
            .setMultiChoiceItems(labels, checked) { _, which, value -> checked[which] = value }
            .setNeutralButton("Elegir todos", null)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Guardar", null).create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                val value = !checked.all { it }; checked.indices.forEach { checked[it] = value; dialog.listView.setItemChecked(it, value) }
            }
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                if (prefs.owner != owner) { dialog.dismiss(); toast("La cuenta cambió."); return@setOnClickListener }
                val selected = entries.filterIndexed { index, _ -> checked[index] }
                if (selected.isEmpty()) { toast("Elige al menos un capítulo."); return@setOnClickListener }
                if (selected.size > 500) { toast("Prepara como máximo 500 capítulos por lote."); return@setOnClickListener }
                var added = 0
                try {
                    Store(this).use { store ->
                        val payloads = selected.map { entry ->
                            JSONObject().put("owner", owner).put("episode_id", entry.getLong("episode_id"))
                                .put("slug", slug).put("title", plan.getString("title")).put("number", entry.getString("number"))
                                .put("language", language).put("season", plan.optString("season")).put("cover",plan.optString("cover"))
                                .put("mal_account_id", plan.optLong("mal_account_id")).put("progress_revision", plan.optString("progress_revision"))
                                .put("next_episode_id", entry.optLong("next_episode_id"))
                                .put("watched", entry.optBoolean("watched"))
                                .put("watched_override",entry.opt("watched_override")?:JSONObject.NULL)
                        }
                        added = store.addBatch(payloads)
                    }
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    Queue.start(this); dialog.dismiss(); selectTab("downloads"); toast("$added capítulos añadidos${if (prefs.wifiOnly) " · solo Wi-Fi" else ""}.")
                } catch (_: Exception) { toast("No se pudo guardar el lote. Comprueba los datos del anime.") }
            }
        }
        dialog.show()
    }

    private fun show(target: String) {
        rememberNativeScroll(); page = target; signature = ""
        if(target in setOf("downloads","more"))activeTab=target
        header.visibility = if (target in setOf("web","account")) View.GONE else View.VISIBLE
        (web.parent as? ViewGroup)?.removeView(web)
        content.removeAllViews()
        when (target) {
            "web", "account" -> { title.text = "YomaTV"; content.addView(web, FrameLayout.LayoutParams(-1, -1)); resumeWeb() }
            "downloads" -> { title.text = "YomaTV"; suspendWeb(); downloadsPanel?.takeIf{downloadsOwner==prefs.owner}?.let{content.addView(it)}; renderDownloads() }
            "more" -> { title.text = "YomaTV"; suspendWeb(); renderMore() }
            else -> { title.text = "YomaTV"; suspendWeb(); renderSettings() }
        }
        updateNav(Uri.parse(web.url.orEmpty()).fragment.orEmpty())
    }
    private fun updateNav(route: String) {
        val index=listOf("catalog","schedule","downloads","more").indexOf(activeTab)
        for(i in 0 until nav.childCount){
            val item=nav.getChildAt(i) as LinearLayout;val color=if(i==index)ACCENT else PAPER
            (item.getChildAt(0) as NavGlyph).tint=color
            (item.getChildAt(1) as TextView).setTextColor(color)
            item.isSelected=i==index
        }
    }
    private fun webRoute(route: String) {
        if(isWebPage())suspendWeb()
        activeTab="more";web=webFor("more");webReady="more" in readyTabs;show("web")
        if(trusted(web.url) && webReady) web.evaluateJavascript("location.hash="+JSONObject.quote("#$route"),null) else web.loadUrl(SITE+"#$route")
        updateNav(route)
    }
    private fun moreMenu() { activeTab="more";show("more") }
    private fun renderMore() {
        val layout=container()
        layout.addView(label("Más",36,PAPER,true));layout.addView(label("Tu espacio en YomaTV",16,MUTED))
        val profile=card(layout)
        val identity=LinearLayout(this).apply{gravity=android.view.Gravity.CENTER_VERTICAL}
        identity.addView(AccountAvatar(this).apply{tag="more-account-avatar";bind(if(prefs.owner>0)userName else "",userPicture)},LinearLayout.LayoutParams(dp(60),dp(60)).apply{rightMargin=dp(14)})
        identity.addView(label(if(prefs.owner>0)"Hola, ${userName.ifBlank { "de nuevo" }}" else "Tu próxima historia empieza aquí",22,PAPER,true),LinearLayout.LayoutParams(0,-2,1f))
        profile.addView(identity)
        profile.addView(button(if(prefs.owner>0)"Ver mi cuenta  →" else "Iniciar sesión  →",false){openWebAccount()})
        fun section(title:String, entries:List<Triple<String,String,String>>) {
            val key=entries.first().third
            val section=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;tag="more-section-$key"}
            layout.addView(section,LinearLayout.LayoutParams(-1,-2).apply{topMargin=dp(26)})
            val heading=label(title,14,MUTED).apply{
                tag="more-section-heading-$key";setPadding(dp(4),0,dp(4),0)
                typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL)
                if(Build.VERSION.SDK_INT>=28)isAccessibilityHeading=true
            }
            section.addView(heading,LinearLayout.LayoutParams(-1,-2).apply{bottomMargin=dp(8)})
            val box=card(section).apply{tag="more-section-card-$key"}
            (box.layoutParams as LinearLayout.LayoutParams).topMargin=0
            entries.forEachIndexed{index,(glyph,entryLabel,route)->
                val row=LinearLayout(this).apply{
                    gravity=android.view.Gravity.CENTER_VERTICAL;setPadding(dp(10),dp(12),dp(8),dp(12));minimumHeight=dp(56)
                    tag="more-entry-$route";contentDescription=entryLabel;isFocusable=true;isClickable=true
                    background=android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x22ff6a55),android.graphics.drawable.ColorDrawable(SURFACE),null)
                    setOnClickListener{when(route){"native"->show("settings");"more"->moreMenu();else->webRoute(route)}}
                }
                row.addView(NavGlyph(this,glyph).apply{importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO},LinearLayout.LayoutParams(dp(25),dp(25)).apply{rightMargin=dp(14)})
                row.addView(label(entryLabel,16,PAPER).apply{setPadding(0,0,0,0);importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO},LinearLayout.LayoutParams(0,-2,1f))
                row.addView(NavGlyph(this,"chevron").apply{tint=MUTED;importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO},LinearLayout.LayoutParams(dp(18),dp(18)).apply{leftMargin=dp(8)})
                box.addView(row,LinearLayout.LayoutParams(-1,-2))
                if(index<entries.lastIndex)box.addView(View(this).apply{setBackgroundColor(0xff393449.toInt())},LinearLayout.LayoutParams(-1,dp(1)))
            }
        }
        section("TU BIBLIOTECA",listOf(Triple("library","Mi biblioteca","library"),Triple("history","Historial","history"),Triple("mal","MyAnimeList${if(malConnected)" · Conectado" else ""}","mal"),Triple("favorites","Favoritos","favorites"),Triple("collections","Colecciones","collections")))
        section("PREFERENCIAS",listOf(Triple("appearance","Apariencia y reproducción","settings"),Triple("notifications","Notificaciones","notifications"),Triple("storage","Almacenamiento y descargas","native")))
        section("EXPLORA MÁS",listOf(Triple("radio","Radio anime","radio"),Triple("stats","Estadísticas","stats"),Triple("queue","Cola para la PC","queue"),Triple("sync","Sincronización MAL","sync")))
        layout.addView(label("YomaTV Android · ${BuildConfig.VERSION_NAME}",14,MUTED))
        restoreNativeScroll("more")
    }
    private fun restoreNativeScroll(key:String) {
        (content.getChildAt(0) as? ScrollView)?.let { scroll->scroll.post{scroll.scrollTo(0,nativeScroll[key]?:0)} }
    }
    private fun openWebAccount() {
        if(page!="account") { rememberNativeScroll();accountReturnPage=page;accountReturnTab=activeTab;if(isWebPage())suspendWeb() }
        web=webFor("account");webReady="account" in readyTabs;show("account")
        if(webReady)web.evaluateJavascript("location.hash='#account';if(!state?.user)document.querySelector('#account')?.click()",null)
        else pendingAccount=true
    }
    private fun closeWebAccount() {
        suspendWeb();activeTab=accountReturnTab
        web=webFor(if(activeTab in setOf("catalog","schedule","more"))activeTab else "catalog")
        webReady=webTabs.entries.firstOrNull{it.value===web}?.key in readyTabs
        show(accountReturnPage)
    }
    private fun container(): LinearLayout {
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(18), dp(12), dp(18), dp(24)) }
        val scroll = ScrollView(this).apply { isFillViewport = true; addView(layout) }
        content.removeAllViews(); content.addView(scroll)
        return layout
    }
    private fun renderDownloads() {
        if (page != "downloads" || reading || isDestroyed) return
        reading = true
        val owner = prefs.owner
        queries.execute {
            val result = runCatching {
                val store = queryStore ?: Store(applicationContext).also { queryStore = it }
                store.list(owner).filter { it.state != "removed" }
            }
            runOnUiThread {
                reading = false
                if (!isDestroyed && page == "downloads") {
                    if (owner == prefs.owner) result.onSuccess { renderDownloadRows(it) } else renderDownloads()
                }
            }
        }
    }
    private fun renderDownloadRows(jobs: List<Episode>) {
        pendingSync=jobs.any{it.pending||it.markPending};handler.removeCallbacks(tick)
        if(resumed&&page=="downloads"&&(running||pendingSync))handler.postDelayed(tick,if(running)1000 else 5000)
        val created=downloadsPanel==null||downloadsOwner!=prefs.owner
        if(created){
            downloadsOwner=prefs.owner
            downloadsPanel=DownloadsPanel(this,DownloadActions(
                filter={downloadFilter=it;renderDownloads()},group={group=it;renderDownloads()},
                toggle={toggleDownload(it)},options={episodeMenu(it)},cancel={cancelDownload(it)},
                pauseAll={if(prefs.paused){prefs.paused=false;Queue.start(this,true)}else Queue.pause(this);renderDownloads()},
                storage={show("settings")},wifi={prefs.wifiOnly=it;Queue.start(this,true)},status={status(it)}
            ))
        }
        val panel=downloadsPanel!!
        if(panel.parent!==content){(panel.parent as? ViewGroup)?.removeView(panel);content.removeAllViews();content.addView(panel)}
        val free=runCatching{android.os.StatFs((getExternalFilesDir(null)?:filesDir).absolutePath).availableBytes}.getOrDefault(0L)
        panel.submit(DownloadSnapshot(prefs.owner,jobs,downloadFilter,group,running,prefs.paused,prefs.wifiOnly,free))
        if(created)panel.restorePosition(nativeScroll["downloads"]?:0)
    }
    private fun toggleDownload(ep:Episode){
        if(ep.owner!=prefs.owner)return
        if(ep.state=="verifying")return
        if(ep.state=="done"){
            Store(this).use{store->
                if(!store.video(ep).exists()||store.video(ep).length()!=ep.total){store.update(ep.key,ep.owner,"state" to "failed","error" to "El archivo ya no está en el dispositivo.");renderDownloads()}
                else {web.onPause();startActivity(Intent(this,PlayerActivity::class.java).putExtra("key",ep.key).putExtra("owner",ep.owner))}
            }
        }else{
            Store(this).use{store->
                if(prefs.paused)for(other in store.list(ep.owner).filter{it.key!=ep.key&&it.state in setOf("queued","retry","downloading","verifying")})store.update(other.key,other.owner,"state" to "paused","speed" to 0.0)
                store.update(ep.key,ep.owner,"state" to if(ep.state in setOf("paused","failed")||prefs.paused)"queued" else "paused","attempts" to 0,"error" to "")
            }
            if(prefs.paused)prefs.paused=false
            Queue.start(this);renderDownloads()
        }
    }
    private fun cancelDownload(ep:Episode){
        if(ep.owner!=prefs.owner)return
        AlertDialog.Builder(this).setTitle("¿Cancelar el capítulo ${ep.number}?").setMessage("Se eliminará el archivo parcial de esta descarga. Los capítulos terminados se conservan.")
            .setNegativeButton("Conservar",null).setPositiveButton("Cancelar descarga"){_,_->
                val owner=ep.owner
                queries.execute{
                    val result=runCatching{
                        Store(this).use{store->val fresh=store.get(ep.key,owner)?:return@use;check(fresh.state!="done"){"El capítulo ya terminó. Puedes eliminarlo desde sus opciones."};store.update(ep.key,owner,"state" to "paused","speed" to 0.0)}
                        WorkManager.getInstance(this).cancelUniqueWork("yoma-anime-downloads").result.get()
                        java.io.FileOutputStream(java.io.File(filesDir,"downloads.lock"),true).channel.use{channel->
                            var lock:java.nio.channels.FileLock?=null;var attempts=0
                            while(lock==null&&attempts++<150){lock=try{channel.tryLock()}catch(_:java.nio.channels.OverlappingFileLockException){null};if(lock==null)Thread.sleep(100)}
                            val held=lock?:error("La descarga quedó pausada. Vuelve a intentar eliminarla desde sus opciones.")
                            try{check(prefs.owner==owner){"La cuenta cambió."};Store(this).use{it.removeVideo(ep)}}finally{held.release()}
                        }
                    }
                    if(prefs.owner==owner&&!prefs.paused)Queue.start(this,true)
                    runOnUiThread{if(!isDestroyed){result.onFailure{toast(it.message.orEmpty())};if(page=="downloads")renderDownloads()}}
                }
            }.show()
    }
    private fun status(ep: Episode): String = DownloadPresentation.of(ep,prefs.paused,running).summary
    private fun episodeMenu(ep: Episode) {
        AlertDialog.Builder(this).setTitle("Capítulo ${ep.number}")
            .setItems(arrayOf("Reintentar sincronización con MAL", "Verificar archivo", "Eliminar video")) { _, which ->
                when (which) {
                    0 -> { Store(this).use { it.update(ep.key, ep.owner, "pending" to ep.watched, "sync" to "Pendiente de sincronización") }; Queue.sync(this) }
                    1 -> Thread {
                        val result = Store(this).use { store -> val file = store.video(ep); file.exists() && file.length() == ep.total && app.yomatv.engine.Integrity.mp4(file) && app.yomatv.engine.Integrity.sha256(file) == ep.hash }
                        runOnUiThread { toast(if (result) "El archivo coincide con su SHA-256." else "El archivo está ausente o cambió.") }
                    }.start()
                    2 -> AlertDialog.Builder(this).setTitle("¿Eliminar este video?").setMessage("Se conserva el historial de visto y MAL. Pausa el capítulo primero si está descargando.")
                        .setNegativeButton("Conservar", null).setPositiveButton("Eliminar") { _, _ ->
                            runCatching { Store(this).use { it.removeVideo(ep) } }.onFailure { toast(it.message.orEmpty()) }; signature = ""; renderDownloads()
                        }.show()
                }
            }.show()
    }
    private fun renderSettings() {
        val layout = container()
        layout.addView(label("Tu biblioteca, contigo", 27, PAPER, true))
        layout.addView(label("Los videos se guardan en el almacenamiento privado de YomaTV. Al desinstalar la app, Android elimina esos archivos.", 16, MUTED))
        fun toggle(text: String, value: Boolean, change: (Boolean) -> Unit) {
            layout.addView(toggleControl(text,value,change))
        }
        toggle("Descargar solo por Wi-Fi", prefs.wifiOnly) { prefs.wifiOnly = it; Queue.start(this, true) }
        toggle("Pausar todas las descargas",prefs.paused){paused->if(paused)Queue.pause(this)else{prefs.paused=false;Queue.start(this,true)}}
        toggle("Eliminar videos vistos al cerrar el reproductor", prefs.cleanWatched) { prefs.cleanWatched = it }
        layout.addView(label("Calidad original de MP4Upload. El idioma se toma de tu selección en el reproductor o las preferencias web; nunca se sustituye silenciosamente.", 14, MUTED))
        layout.addView(label("MyAnimeList", 22, PAPER, true))
        layout.addView(label("Al llegar al 80 % de la posición se guarda el visto, incluso al adelantar. Sin internet queda pendiente. Conecta y confirma el anime en MAL antes de descargar para autorizar la sincronización.", 16, MUTED))
        layout.addView(button("Reintentar pendientes", true) { Queue.sync(this); toast("Se revisarán los pendientes de esta cuenta.") })
        layout.addView(button("Cuenta y conexión MAL", false) { openWebAccount() })
        layout.addView(label("Las descargas usan una cola secuencial, cinco intentos con espera progresiva y comprobación MP4 + SHA-256. Android puede detener tareas prolongadas; el parcial se conserva para continuar.", 14, MUTED))
        layout.addView(label("YomaTV Android · ${BuildConfig.VERSION_NAME}", 14, MUTED));restoreNativeScroll("settings")
    }
    private fun label(text: String, size: Int, color: Int = PAPER, serif: Boolean = false) = TextView(this).apply {
        this.text = text; textSize = size.toFloat(); setTextColor(color); includeFontPadding=false
        gravity=android.view.Gravity.START or android.view.Gravity.CENTER_VERTICAL
        textAlignment=View.TEXT_ALIGNMENT_GRAVITY;setLineSpacing(0f,1.15f);setPadding(0,dp(6),0,dp(6))
        if (serif) typeface = Typeface.create("serif", Typeface.NORMAL)
    }
    private fun button(text: String, primary: Boolean, action: () -> Unit) = Button(this).apply {
        this.text = text; isAllCaps = false; textSize = 14f; minHeight = dp(48); minimumHeight = dp(48)
        includeFontPadding=false;gravity=android.view.Gravity.CENTER;textAlignment=View.TEXT_ALIGNMENT_GRAVITY
        minWidth=0;minimumWidth=0;setLineSpacing(0f,1.1f)
        setTextColor(if (primary) INK else PAPER); background = outlined(if (primary) ACCENT else SURFACE, dp(26).toFloat())
        setPadding(dp(12), dp(10), dp(12), dp(10)); setOnClickListener { action() }
    }
    private fun toggleControl(text:String,value:Boolean,change:(Boolean)->Unit)=Switch(this).apply{
        this.text=text;textSize=16f;setTextColor(PAPER);includeFontPadding=false
        gravity=android.view.Gravity.START or android.view.Gravity.CENTER_VERTICAL;textAlignment=View.TEXT_ALIGNMENT_GRAVITY
        minHeight=dp(56);switchPadding=dp(16);setPadding(0,dp(10),0,dp(10));setLineSpacing(0f,1.15f)
        isChecked=value;setOnCheckedChangeListener{_,checked->change(checked)}
    }
    private fun card(parent: LinearLayout): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(12), dp(16), dp(12)); background = outlined(SURFACE, dp(20).toFloat())
        parent.addView(this, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
    }
    private fun toast(message: String) { Toast.makeText(this, message, Toast.LENGTH_LONG).show() }
    private fun suspendWeb() { web.evaluateJavascript("window.dispatchEvent(new Event('season-native-suspend'))",null); web.onPause() }
    private fun resumeWeb() { web.onResume(); web.evaluateJavascript("window.dispatchEvent(new Event('season-native-resume'))",null) }
    override fun onResume() { super.onResume(); resumed = true; if (::web.isInitialized && isWebPage()) resumeWeb(); signature = ""; if (page == "downloads") renderDownloads() }
    override fun onPause() { resumed = false; handler.removeCallbacks(tick); if (::web.isInitialized) suspendWeb(); super.onPause() }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); queries.execute { queryStore?.close() }; queries.shutdown(); webTabs.values.forEach{it.destroy()}; super.onDestroy() }
}
