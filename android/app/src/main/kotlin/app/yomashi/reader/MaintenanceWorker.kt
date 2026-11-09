package app.yomashi.reader

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.*
import androidx.work.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import java.util.concurrent.TimeUnit

class MaintenanceWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val done = CompletableDeferred<Boolean>()
        return try {
            setForeground(foreground())
            withContext(Dispatchers.Main) { DownloadHostService.beginWorker(applicationContext) { done.complete(it) } }
            if (withTimeout(20 * 60 * 1000L) { done.await() }) Result.success() else Result.retry()
        } catch(e: CancellationException) {
            throw e
        } catch(e: Exception) {
            Result.retry()
        } finally {
            withContext(kotlinx.coroutines.NonCancellable + Dispatchers.Main) { DownloadHostService.endWorker(applicationContext) }
        }
    }
    private fun foreground(): ForegroundInfo {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        if(Build.VERSION.SDK_INT>=26) manager.createNotificationChannel(NotificationChannel("yomashi_maintenance", "Actualizaciones y copias", NotificationManager.IMPORTANCE_LOW))
        val builder=if(Build.VERSION.SDK_INT>=26) Notification.Builder(applicationContext,"yomashi_maintenance") else Notification.Builder(applicationContext)
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification).setContentTitle("YomaShi")
            .setContentText("Comprobando favoritos y copias de seguridad")
            .addAction(R.drawable.ic_notification,"Cancelar",WorkManager.getInstance(applicationContext).createCancelPendingIntent(id))
            .setOngoing(true).build()
        return ForegroundInfo(19003002,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    }
    companion object {
        fun register(engine: FlutterEngine, context: Context) {
            MethodChannel(engine.dartExecutor.binaryMessenger,"app.yomashi.reader/maintenance").setMethodCallHandler { call,result ->
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any,Any>()
                when(call.method) {
                    "conditions" -> {
                        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL,-1) ?: -1
                        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE,100) ?: 100
                        val manager = context.getSystemService(ConnectivityManager::class.java)
                        val caps = manager.getNetworkCapabilities(manager.activeNetwork)
                        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS,-1)
                        result.success(mapOf("connected" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)==true),
                            "wifi" to (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)==true),
                            "charging" to (status==BatteryManager.BATTERY_STATUS_CHARGING || status==BatteryManager.BATTERY_STATUS_FULL),
                            "battery" to if(level>=0 && scale>0) level*100/scale else 0))
                    }
                    "schedule" -> {
                        val wm=WorkManager.getInstance(context)
                        if(args["updates"]!=true && args["backups"]==false) wm.cancelUniqueWork("yomashi-maintenance")
                        else {
                            val constraints=Constraints.Builder().setRequiresBatteryNotLow(true)
                                .setRequiresCharging(args["chargingOnly"]==true)
                                .setRequiredNetworkType(if(args["updates"]==true && args["wifiOnly"]!=false) NetworkType.UNMETERED else NetworkType.NOT_REQUIRED).build()
                            val work=PeriodicWorkRequestBuilder<MaintenanceWorker>(12,TimeUnit.HOURS).setConstraints(constraints).addTag("yomashi-maintenance").build()
                            wm.enqueueUniquePeriodicWork("yomashi-maintenance",ExistingPeriodicWorkPolicy.UPDATE,work)
                        }
                        result.success(null)
                    }
                    "runOnce" -> {
                        val work=OneTimeWorkRequestBuilder<MaintenanceWorker>().addTag("yomashi-once").build()
                        WorkManager.getInstance(context).enqueueUniqueWork("yomashi-once",ExistingWorkPolicy.KEEP,work)
                        result.success(work.id.toString())
                    }
                    "workState" -> {
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val infos=WorkManager.getInstance(context).getWorkInfosForUniqueWorkFlow(args["name"] as? String ?: "yomashi-once").first()
                                result.success(infos.map { it.state.name })
                            } catch(e:Exception) { result.error("WORK",e.message,null) }
                        }
                    }
                    "notify" -> {
                        val manager=context.getSystemService(NotificationManager::class.java)
                        if(Build.VERSION.SDK_INT>=26) manager.createNotificationChannel(NotificationChannel("yomashi_updates","Capítulos nuevos",NotificationManager.IMPORTANCE_DEFAULT))
                        val open=PendingIntent.getActivity(context,0,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        val builder=if(Build.VERSION.SDK_INT>=26) Notification.Builder(context,"yomashi_updates") else Notification.Builder(context)
                        manager.notify(19003003,builder.setSmallIcon(R.drawable.ic_notification)
                            .setContentTitle("Capítulos nuevos").setContentText("${args["count"]} capítulos en tus favoritos")
                            .setContentIntent(open).setAutoCancel(true).build())
                        result.success(null)
                    }
                    "info" -> {
                        val memory=Debug.MemoryInfo(); Debug.getMemoryInfo(memory)
                        val battery=context.getSystemService(BatteryManager::class.java)
                        result.success(mapOf("package" to context.packageName,"host" to DownloadHostService.hostKind(),"pssKiB" to memory.totalPss,"nativeHeapBytes" to Debug.getNativeHeapAllocatedSize(),
                            "chargeMicroAh" to battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER),"charging" to battery.isCharging))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
