package app.yomashi.reader

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "app.yomashi.reader/volume"
    private var volumeEnabled = false
    private var volumeChannel: MethodChannel? = null
    private var downloads: MethodChannel? = null
    private var translation: ReaderTranslationPlatform? = null
    private var pictureInPicture: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Older generated registrants may omit a newly added plugin after a host symlink failure.
        if (!flutterEngine.plugins.has(io.flutter.plugins.videoplayer.VideoPlayerPlugin::class.java)) {
            flutterEngine.plugins.add(io.flutter.plugins.videoplayer.VideoPlayerPlugin())
        }
        NativeAnimeBridge.register(this, flutterEngine)
        LocalAnimePlatform.register(this, flutterEngine)
        translation = ReaderTranslationPlatform(this, flutterEngine.dartExecutor.binaryMessenger)
        DownloadHostService.storageChannel(flutterEngine,this)
        downloads = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.yomashi.reader/downloads")
        DownloadHostService.observe(downloads)
        downloads?.setMethodCallHandler { call, result ->
            DownloadHostService.dispatch(this, call.method, call.arguments, result)
        }
        // Imagen en imagen del reproductor de YomaTV (antes solo en PlayerActivity).
        pictureInPicture = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.yoma/pip")
        pictureInPicture?.setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(
                    Build.VERSION.SDK_INT >= 26 && packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE),
                )
                "enter" -> {
                    if (Build.VERSION.SDK_INT < 26) { result.success(false); return@setMethodCallHandler }
                    val width = (call.argument<Number>("width")?.toInt() ?: 16).coerceIn(1, 100_000)
                    val height = (call.argument<Number>("height")?.toInt() ?: 9).coerceIn(1, 100_000)
                    // Android solo admite proporciones entre 1:2,39 y 2,39:1.
                    val ratio = when {
                        width * 100L > height * 239L -> Rational(239, 100)
                        height * 100L > width * 239L -> Rational(100, 239)
                        else -> Rational(width, height)
                    }
                    result.success(runCatching {
                        enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(ratio).build())
                    }.getOrDefault(false))
                }
                else -> result.notImplemented()
            }
        }
        volumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        volumeChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setEnabled") {
                volumeEnabled = call.arguments as? Boolean ?: false
                result.success(null)
            } else result.notImplemented()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        translation?.close()
        translation = null
        DownloadHostService.observe(null)
        downloads?.setMethodCallHandler(null)
        volumeChannel?.setMethodCallHandler(null)
        pictureInPicture?.setMethodCallHandler(null)
        pictureInPicture = null
        downloads = null
        volumeEnabled = false
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pictureInPicture?.invokeMethod("changed", isInPictureInPictureMode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        NativeAnimeBridge.onActivityResult(this, requestCode, data)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (!volumeEnabled) return super.onKeyDown(keyCode, event)
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                volumeChannel?.invokeMethod("volumeUp", null)
                return true
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                volumeChannel?.invokeMethod("volumeDown", null)
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}

