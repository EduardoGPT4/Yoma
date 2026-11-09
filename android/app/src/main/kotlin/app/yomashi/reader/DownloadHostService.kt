package app.yomashi.reader

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Un solo motor Dart, independiente de la Activity, conserva la cola en SQLite.
 * Sin arranque en BOOT_COMPLETED; respeta el timeout dataSync de Android 15+.
 */
class DownloadHostService : Service() {
    private var engine: FlutterEngine? = null
    private val handler = Handler(Looper.getMainLooper())
    private val idle = Runnable { if (pending.isEmpty()) stopSelf() }
    private var wakeLock: PowerManager.WakeLock? = null
    private var busy = 0
    private var runnable = false

    companion object {
        private const val notificationId = 19003001
        private const val channelId = "yomashi_background_v1"
        private var channel: MethodChannel? = null
        private var ready = false
        private var observer: MethodChannel? = null
        private var instance: DownloadHostService? = null
        private val pending = mutableListOf<() -> Unit>()
        private var workerEngine: FlutterEngine? = null
        private var workerDone: ((Boolean)->Unit)? = null
        private var workerCommandFinished = false
        private var workerRunnable = false
        private var workerBusy = 0
        private var workerClosing = false
        private var readerLease = 0L
        fun hostKind(): String = if(workerEngine!=null) "worker" else if(instance!=null) "service" else "idle"
        fun observe(value: MethodChannel?) { observer = value }
        fun dispatch(context: Context, method: String, args: Any?, result: MethodChannel.Result) {
            if(method=="reader") {
                readerLease=if((args as? Map<*, *>)?.get("active")==true) SystemClock.elapsedRealtime()+35000 else 0
                if(ready && !workerClosing) channel?.invokeMethod(method,args)
                result.success(null);return
            }
            instance?.handler?.removeCallbacks(instance!!.idle)
            val action = {
                if(workerEngine!=null) workerBusy++
                instance?.busy = (instance?.busy ?: 0) + 1
                channel?.invokeMethod(method, args, object : MethodChannel.Result {
                    private fun finished() { if(workerEngine!=null) {workerBusy--; finishWorkerIfIdle()} ; instance?.let { it.busy--; it.scheduleIdle() } }
                    override fun success(value: Any?) { finished(); result.success(value) }
                    override fun error(code: String, message: String?, details: Any?) { finished(); result.error(code, message, details) }
                    override fun notImplemented() { finished(); result.notImplemented() }
                })
                Unit
            }
            if (ready && channel != null) { action(); return }
            pending.add(action)
            if(workerEngine!=null) return
            try {
                val intent = Intent(context, DownloadHostService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                pending.remove(action)
                result.error("BACKGROUND_START", "No se pudo iniciar la descarga. Abre la app para reintentar.", null)
            }
        }
        fun storageChannel(engine: FlutterEngine, context: Context) {
            MyAnimeListPlatform.register(engine,context)
            MaintenanceWorker.register(engine,context)
            MethodChannel(engine.dartExecutor.binaryMessenger, "app.yomashi.reader/storage")
                .setMethodCallHandler { call, result ->
                    if (call.method == "freeBytes") {
                        try { result.success(StatFs(call.arguments as String).availableBytes) }
                        catch (error: Exception) { result.error("STORAGE", error.message, null) }
                    } else result.notImplemented()
                }
        }
        private fun finishWorkerIfIdle() {
            if(!workerClosing && workerCommandFinished && !workerRunnable && workerBusy==0 && pending.isEmpty()) { val done=workerDone; workerDone=null; done?.invoke(true) }
        }
        fun beginWorker(context: Context, done: (Boolean)->Unit) {
            if(instance!=null) {
                dispatch(context,"maintenance",null,object: MethodChannel.Result {
                    override fun success(value: Any?) { done(true) }
                    override fun error(code:String,message:String?,details:Any?) { done(false) }
                    override fun notImplemented() { done(false) }
                }); return
            }
            if(workerEngine!=null) { done(false); return }
            workerDone=done; workerCommandFinished=false; workerRunnable=true;workerBusy=0;workerClosing=false
            val loader=FlutterInjector.instance().flutterLoader()
            loader.startInitialization(context); loader.ensureInitializationComplete(context,null)
            val flutter=FlutterEngine(context); workerEngine=flutter
            storageChannel(flutter,context)
            channel=MethodChannel(flutter.dartExecutor.binaryMessenger,"app.yomashi.reader/download_host")
            channel!!.setMethodCallHandler { call,result ->
                val state=call.arguments as? Map<*, *>
                when(call.method) {
                    "ready" -> {
                        ready=true
                        channel?.invokeMethod("reader",mapOf("active" to (SystemClock.elapsedRealtime()<readerLease)))
                        if(state?.get("error")!=null) { val callback=workerDone;workerDone=null;callback?.invoke(false) }
                        else {
                            val waiting=pending.toList();pending.clear();waiting.forEach { it() }
                            channel!!.invokeMethod("maintenance",null,object:MethodChannel.Result {
                                override fun success(value:Any?) { workerCommandFinished=true;workerRunnable=(value as? Map<*, *>)?.get("runnable")==true;finishWorkerIfIdle() }
                                override fun error(code:String,message:String?,details:Any?) { val callback=workerDone;workerDone=null;callback?.invoke(false) }
                                override fun notImplemented() { val callback=workerDone;workerDone=null;callback?.invoke(false) }
                            })
                        }
                        observer?.invokeMethod("state",call.arguments);result.success(null)
                    }
                    "state","progress" -> { workerRunnable=state?.get("runnable")==true;observer?.invokeMethod(call.method,call.arguments);result.success(null);finishWorkerIfIdle() }
                    "completed" -> { observer?.invokeMethod("completed",call.arguments);result.success(null) }
                    else -> result.notImplemented()
                }
            }
            flutter.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),"package:yomashi/main.dart","downloadMain"))
        }
        fun endWorker(context: Context) {
            val flutter=workerEngine ?: return
            workerDone=null
            workerClosing=true;ready=false
            val current=channel
            val handler=Handler(Looper.getMainLooper())
            var closed=false
            val close = { if(!closed) {
                closed=true
                if(workerEngine===flutter) {ready=false;channel?.setMethodCallHandler(null);channel=null;workerEngine=null;workerClosing=false}
                flutter.destroy()
                if(pending.isNotEmpty()) {
                    val intent=Intent(context,DownloadHostService::class.java)
                    try { if(Build.VERSION.SDK_INT>=26) context.startForegroundService(intent) else context.startService(intent) }
                    catch(e:Exception) { android.util.Log.e("YomaShi","No se pudo reabrir la cola",e) }
                }
            };Unit }
            current?.invokeMethod("shutdown",null,object:MethodChannel.Result {
                override fun success(value:Any?) { close() }
                override fun error(code:String,message:String?,details:Any?) { close() }
                override fun notImplemented() { close() }
            })
            handler.postDelayed({close()},3000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(channelId, "Descargas en segundo plano", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val pause = PendingIntent.getService(this, 1, Intent(this, DownloadHostService::class.java).setAction("PAUSE"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        val notification = builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("YomaShi").setContentText("Preparando cola de descargas")
            .setOngoing(true).setContentIntent(open)
            .addAction(R.drawable.ic_notification, "Pausar", pause).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(notificationId, notification)
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "yomashi:downloads")
        wakeLock?.acquire(6 * 60 * 60 * 1000L)
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val flutter = FlutterEngine(applicationContext)
        engine = flutter
        storageChannel(flutter,applicationContext)
        channel = MethodChannel(flutter.dartExecutor.binaryMessenger, "app.yomashi.reader/download_host")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    ready = true
                    channel?.invokeMethod("reader",mapOf("active" to (SystemClock.elapsedRealtime()<readerLease)))
                    val waiting = pending.toList()
                    pending.clear()
                    waiting.forEach { it() }
                    observer?.invokeMethod("state", call.arguments)
                    updateIdle(call.arguments)
                    result.success(null)
                }
                "progress" -> {
                    observer?.invokeMethod("progress", call.arguments)
                    result.success(null)
                }
                "state" -> {
                    observer?.invokeMethod("state", call.arguments)
                    updateIdle(call.arguments)
                    result.success(null)
                }
                "completed" -> {
                    observer?.invokeMethod("completed", call.arguments)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        flutter.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(), "package:yomashi/main.dart", "downloadMain"))
    }

    private fun updateIdle(value: Any?) {
        val state = value as? Map<*, *>
        runnable = state?.get("runnable") == true
        val transferring = (state?.get("jobs") as? List<*>)?.any {
            (it as? Map<*, *>)?.get("status") == "downloading"
        } == true
        if (transferring && wakeLock?.isHeld != true) wakeLock?.acquire(6 * 60 * 60 * 1000L)
        else if (!transferring && wakeLock?.isHeld == true) wakeLock?.release()
        scheduleIdle()
        val active = (state?.get("jobs") as? List<*>)?.size ?: 0
        val manager = getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val pause = PendingIntent.getService(this, 1, Intent(this, DownloadHostService::class.java).setAction("PAUSE"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(notificationId, builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("YomaShi").setContentText("$active trabajos en la cola")
            .setContentIntent(open).addAction(R.drawable.ic_notification, "Pausar", pause)
            .setOngoing(true).build())
    }

    private fun scheduleIdle() {
        handler.removeCallbacks(idle)
        if (!runnable && busy == 0 && pending.isEmpty()) handler.postDelayed(idle, 15000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handler.removeCallbacks(idle)
        if (intent?.action == "PAUSE") {
            val pause = { channel?.invokeMethod("pauseAll", null); Unit }
            if (ready) pause() else pending.add(pause)
        }
        return START_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        channel?.invokeMethod("shutdown", null)
        handler.postDelayed({ stopSelf() }, 1500)
    }
    override fun onDestroy() {
        instance = null
        ready = false
        channel?.setMethodCallHandler(null)
        channel = null
        handler.removeCallbacksAndMessages(null)
        engine?.destroy()
        engine = null
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
