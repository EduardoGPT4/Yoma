package app.yomatv.engine

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

data class Resume(val etag: String = "", val modified: String = "", val total: Long = 0)
data class TransferProgress(val bytes: Long, val total: Long, val bytesPerSecond: Double, val resume: Resume)
class TransferStopped : IOException("Descarga pausada; el archivo parcial se conserva.")
class HttpFailure(val code: Int) : IOException("El servidor respondió HTTP $code.")

object Network {
    fun open(url: String, headers: Map<String, String> = emptyMap(),
             allowed: (String) -> Boolean): HttpURLConnection {
        var current = url
        repeat(6) {
            require(allowed(current)) { "Dirección de servidor no admitida." }
            val connection = URL(current).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 20_000; connection.readTimeout = 20_000
            connection.setRequestProperty("User-Agent", Provider.UA)
            connection.setRequestProperty("Accept-Encoding", "identity")
            headers.forEach { (key, value) -> connection.setRequestProperty(key, value) }
            val code = connection.responseCode
            if (code !in setOf(301, 302, 303, 307, 308)) return connection
            val location = connection.getHeaderField("Location")
            connection.disconnect()
            if (location == null) throw IOException("Redirección incompleta del servidor.")
            current = URL(URL(current), location).toString()
        }
        throw IOException("Demasiadas redirecciones del servidor.")
    }
    fun html(url: String, kind: String, referer: String): String {
        val connection = open(url, mapOf("Referer" to referer)) { Provider.allowed(it, kind) }
        try {
            if (connection.responseCode != 200) throw HttpFailure(connection.responseCode)
            val data = connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(16 * 1024)
                while (true) {
                    val count = input.read(buffer); if (count < 0) break
                    output.write(buffer, 0, count)
                    if (output.size() > 8 * 1024 * 1024) throw ProviderChanged("La página excede el tamaño permitido.")
                }; output.toByteArray()
            }
            if (data.size > 8 * 1024 * 1024) throw ProviderChanged("La página excede el tamaño permitido.")
            return data.toString(Charsets.UTF_8)
        } finally { connection.disconnect() }
    }
}

class Transfer(private val allowed: (String) -> Boolean = { Provider.allowed(it, "video") }) {
    @Volatile private var active: HttpURLConnection? = null
    @Volatile private var stopped = false
    fun stop() { stopped = true; active?.disconnect() }

    fun download(url: String, referer: String, file: File, saved: Resume = Resume(),
                 cancelled: () -> Boolean = { false }, checkpoint: (TransferProgress) -> Unit = {}): TransferProgress {
        var offset = file.takeIf { it.exists() }?.length() ?: 0L
        // Without a validator a new response might be a different file of equal length.
        if (offset > 0 && saved.etag.isBlank() && saved.modified.isBlank()) { file.writeBytes(byteArrayOf()); offset = 0 }
        val headers = mutableMapOf("Referer" to referer)
        if (offset > 0) {
            headers["Range"] = "bytes=$offset-"
            headers["If-Range"] = saved.etag.ifBlank { saved.modified }
        }
        if (stopped || cancelled()) throw TransferStopped()
        val connection = Network.open(url, headers, allowed); active = connection
        try {
            val code = connection.responseCode
            if (code == 416 && offset > 0 && saved.total == offset &&
                connection.getHeaderField("Content-Range") == "bytes */$offset") {
                return TransferProgress(offset, offset, 0.0, saved)
            }
            if (code != 200 && code != 206) throw HttpFailure(code)
            val etag = connection.getHeaderField("ETag").orEmpty()
            val modified = connection.getHeaderField("Last-Modified").orEmpty()
            val range = connection.getHeaderField("Content-Range").orEmpty()
            var total = connection.contentLengthLong
            if (code == 206) {
                val match = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(range) ?: throw IOException("Rango de descarga inválido.")
                val start = match.groupValues[1].toLong(); val end = match.groupValues[2].toLong()
                total = match.groupValues[3].toLong()
                if (start != offset || end < start || end >= total || total < 1 ||
                    connection.contentLengthLong > 0 && connection.contentLengthLong != end - start + 1)
                    throw IOException("El servidor no respetó el punto de reanudación.")
                if (offset > 0 && (saved.total > 0 && total != saved.total ||
                    saved.etag.isNotBlank() && etag != saved.etag ||
                    saved.etag.isBlank() && modified != saved.modified)) {
                    file.writeBytes(byteArrayOf())
                    throw IOException("El archivo cambió en el servidor. Se reiniciará sin mezclar versiones.")
                }
            } else offset = 0 // If-Range rejected or Range ignored: replace, never append.
            if (total > 20L * 1024 * 1024 * 1024) throw IOException("El archivo excede el límite de 20 GB.")
            val contentType = connection.contentType.orEmpty().lowercase()
            if (contentType.contains("text/") || contentType.contains("json")) throw IOException("El servidor devolvió una página en lugar del video.")
            val resume = Resume(etag, modified, total.coerceAtLeast(0))
            file.parentFile?.mkdirs()
            val before = System.nanoTime(); var last = before; var bytes = offset
            checkpoint(TransferProgress(bytes, total.coerceAtLeast(0), 0.0, resume))
            connection.inputStream.use { input ->
                FileOutputStream(file, code == 206 && offset > 0).use { output ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        if (stopped || cancelled()) throw TransferStopped()
                        val count = input.read(buffer)
                        if (count < 0) break
                        bytes += count
                        if (bytes > 20L * 1024 * 1024 * 1024 || total > 0 && bytes > total) throw IOException("Tamaño de video inesperado.")
                        output.write(buffer, 0, count)
                        val now = System.nanoTime()
                        if (now - last >= 1_000_000_000) {
                            checkpoint(TransferProgress(bytes, total.coerceAtLeast(0), (bytes - offset) / ((now - before) / 1e9), resume))
                            last = now
                        }
                    }
                    output.fd.sync()
                }
            }
            if (total > 0 && bytes != total) throw IOException("La conexión terminó antes de completar el video.")
            if (bytes < 1024) throw IOException("El archivo es demasiado pequeño para ser un capítulo.")
            val result = TransferProgress(bytes, bytes, (bytes - offset) / ((System.nanoTime() - before) / 1e9), resume.copy(total = bytes))
            checkpoint(result)
            return result
        } finally { connection.disconnect(); active = null }
    }
}

object Integrity {
    fun mp4(file: File): Boolean = runCatching {
        if (file.length() < 1024) return false
        var ftyp = false; var moov = false; var mdat = false
        java.io.RandomAccessFile(file, "r").use { input ->
            var offset = 0L; var boxes = 0
            while (offset + 8 <= input.length() && ++boxes < 100_000) {
                input.seek(offset); var size = input.readInt().toLong() and 0xffffffffL
                val type = ByteArray(4).also { input.readFully(it) }.toString(Charsets.US_ASCII)
                var header = 8
                if (size == 1L) { size = input.readLong(); header = 16 }
                if (size == 0L) size = input.length() - offset
                if (size < header || size > input.length() - offset) return false
                if (offset == 0L && type != "ftyp") return false
                when (type) { "ftyp" -> ftyp = true; "moov" -> moov = true; "mdat" -> mdat = true }
                offset += size
            }
            offset == input.length() && ftyp && moov && mdat
        }
    }.getOrDefault(false)
    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered(256 * 1024).use { input ->
            val bytes = ByteArray(256 * 1024)
            while (true) { val count = input.read(bytes); if (count < 0) break; digest.update(bytes, 0, count) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
