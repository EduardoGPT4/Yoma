package app.yomashi.reader

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

/** Only an opaque device credential is stored here; MAL tokens stay on the server. */
object MyAnimeListPlatform {
    private const val alias = "yomashi_mal_device_v1"
    private fun load(prefs:SharedPreferences):String? {
        val saved=prefs.getString("session",null) ?: return null
        return try {
            val bytes=Base64.decode(saved,Base64.NO_WRAP)
            require(bytes.size>28)
            val cipher=Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,bytes.copyOfRange(0,12)))
            String(cipher.doFinal(bytes.copyOfRange(12,bytes.size)),Charsets.UTF_8)
        } catch(e:Exception) { check(prefs.edit().remove("session").commit());null }
    }
    private fun save(prefs:SharedPreferences,value:String?) {
        if(value==null) { check(prefs.edit().remove("session").commit());return }
        require(value.length<=8192)
        val cipher=Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE,key()) }
        check(prefs.edit().putString("session",Base64.encodeToString(cipher.iv+cipher.doFinal(value.toByteArray(Charsets.UTF_8)),Base64.NO_WRAP)).commit())
    }
    private fun key(): SecretKey {
        val store=KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias,null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun hex(value:String): ByteArray {
        require(value.length in 32..128 && value.length%32==0 && value.matches(Regex("[0-9a-fA-F]+")))
        return value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }
    private fun identity(value: String?): Pair<String?,Long?> {
        val json = value?.let { JSONObject(it) }
        return Pair(json?.optString("device_token"), json?.optJSONObject("profile")?.optLong("id"))
    }
    fun register(engine:FlutterEngine,context:Context) {
        val prefs=context.getSharedPreferences("yomashi_mal_secure_v1",Context.MODE_PRIVATE)
        MethodChannel(engine.dartExecutor.binaryMessenger,"app.yomashi.reader/myanimelist").setMethodCallHandler { call,result ->
            try {
                // Shared by UI and headless engines: compare + commit cannot interleave.
                synchronized(this) {
                when(call.method) {
                    "load" -> result.success(load(prefs))
                    "save" -> {
                        val before = load(prefs)
                        save(prefs,call.arguments as String)
                        if (identity(before) != identity(call.arguments as String)) NativeAnimeBridge.resetIdentity(context) { result.success(null) }
                        else result.success(null)
                    }
                    "clear" -> { save(prefs,null);NativeAnimeBridge.resetIdentity(context) { result.success(null) } }
                    "replaceIfToken" -> {
                        val args=call.arguments as Map<*, *>
                        val current=load(prefs)?.let { JSONObject(it).optString("device_token","") }
                        if(current!=args["expectedToken"]) result.success(false)
                        else {
                            val before = load(prefs)
                            val next = args["value"] as String?
                            save(prefs,next)
                            if (identity(before) != identity(next)) NativeAnimeBridge.resetIdentity(context) { result.success(true) }
                            else result.success(true)
                        }
                    }
                    "openBrowser" -> {
                        val uri=Uri.parse(call.arguments as String)
                        require(uri.scheme=="https" && uri.host=="hk-br035.gt.tc" && uri.port in listOf(-1,443) && uri.userInfo==null && uri.path=="/seasonav1/yomashi-connect.php")
                        context.startActivity(Intent(Intent.ACTION_VIEW,uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    "hostCookie" -> {
                        // Ordinary first-party hosting handshake, never arbitrary JS evaluation.
                        val args=call.arguments as Map<*, *>
                        val cipher=Cipher.getInstance("AES/CBC/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE,SecretKeySpec(hex(args["key"] as String),"AES"),IvParameterSpec(hex(args["iv"] as String)))
                        val output=cipher.doFinal(hex(args["ciphertext"] as String))
                        require(output.size==16)
                        result.success(output.joinToString("") { "%02x".format(it.toInt() and 255) })
                    }
                    else -> result.notImplemented()
                }
                }
            } catch(e:Exception) { result.error("MAL_PLATFORM","No se pudo completar la conexión segura con MyAnimeList.",null) }
        }
    }
}
