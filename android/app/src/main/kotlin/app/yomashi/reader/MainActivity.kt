package app.yomashi.reader

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
        downloads = null
        volumeEnabled = false
        super.cleanUpFlutterEngine(flutterEngine)
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

