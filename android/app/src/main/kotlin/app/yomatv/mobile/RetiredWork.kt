package app.yomatv.mobile

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * La cola de la cuenta web se retiró en Yoma 3.2.18: YomaTV solo usa la cola
 * local. WorkManager guarda los trabajos por nombre de clase, así que un
 * trabajo de sincronización programado por una versión anterior termina aquí
 * sin hacer nada en vez de fallar al no encontrar su clase.
 */
class SyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result = Result.success()
}
