package app.yomashi.reader

import android.net.Uri

/** Dirección de YomaTV. Cambiar de dominio es cambiar [HOST]; [SITES] son los
 *  dominios propios aceptados como origen de confianza, cada uno con la ruta en
 *  la que vive YomaTV. Debe coincidir con lib/config/yoma_web.dart. */
object YomaWeb {
    const val HOST = "tv.yoma.site"
    val SITES = mapOf("tv.yoma.site" to "/")
    val HOSTS: Set<String> get() = SITES.keys
    val PATH: String get() = SITES.getValue(HOST)
    val SITE: String get() = "https://$HOST$PATH"
    val ORIGINS: Set<String> get() = HOSTS.map { "https://$it" }.toSet()

    /** Ruta de [file] de YomaTV en el dominio de [uri], o null si no es propio. */
    fun pathOf(uri: Uri, file: String): String? = SITES[uri.host]?.let { it + file }

    /** HTTPS de YomaTV, sin usuario ni puerto distinto de 443. */
    fun owns(uri: Uri?): Boolean {
        val root = uri?.host?.let { SITES[it] } ?: return false
        return uri.scheme == "https" && uri.port in setOf(-1, 443) && uri.userInfo == null &&
            (uri.path ?: "").startsWith(root)
    }
}

/** Servicios compartidos por YomaShi y YomaTV (puente de MyAnimeList y
 *  sincronización), en api.yoma.site. La autorización en el navegador sigue en
 *  [CONNECT_HOST], la dirección de retorno registrada en MAL. Debe coincidir con
 *  YomaServices de lib/config/yoma_web.dart. */
object YomaServices {
    const val HOST = "api.yoma.site"
    const val PATH = "/"
    const val CONNECT_HOST = "tv.yoma.site"

    /** Página para conectar MyAnimeList: HTTPS de [CONNECT_HOST], puerto 443, sin usuario. */
    fun isConnectPage(uri: Uri?): Boolean = uri != null && uri.scheme == "https" && uri.host == CONNECT_HOST &&
        uri.port in setOf(-1, 443) && uri.userInfo == null && uri.path == "/yomashi-connect.php"
}
