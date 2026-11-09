package app.yomatv.engine

import java.net.URI

object Provider {
    const val UA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
    fun allowed(url: String, kind: String): Boolean = runCatching {
        val u = URI(url); val host = u.host?.lowercase() ?: return false
        if (u.scheme != "https" || u.rawUserInfo != null || u.fragment != null) return false
        if (kind != "video" && u.port != -1 || kind == "video" && u.port !in setOf(-1, 443, 183)) return false
        when (kind) {
            "page" -> host == "animeav1.com" && Regex("/media/[A-Za-z0-9_-]+/\\d+(?:\\.\\d+)?").matches(u.path)
            "embed" -> host in setOf("mp4upload.com", "www.mp4upload.com") && Regex("/(?:embed-)?[A-Za-z0-9]{5,40}(?:\\.html)?/?").matches(u.path)
            "video" -> (host == "mp4upload.com" || host.endsWith(".mp4upload.com")) && u.path.endsWith(".mp4")
            else -> false
        }
    }.getOrDefault(false)

    fun video(html: String): String {
        // Parse source data only. Never execute provider scripts or advertising.
        val patterns = listOf(
            Regex("player\\.src\\s*\\(\\s*\\{[\\s\\S]{0,1500}?\\bsrc\\s*:\\s*([\"'])(.*?)\\1"),
            Regex("<source[^>]+src=[\"']([^\"']+)[\"']", RegexOption.IGNORE_CASE)
        )
        for ((index, regex) in patterns.withIndex()) {
            for (match in regex.findAll(html)) {
                val url = unescape(match.groupValues[if (index == 0) 2 else 1])
                if (allowed(url, "video")) return url
            }
        }
        throw ProviderChanged("MP4Upload no ofrece un MP4 reconocible. El archivo puede haberse eliminado o el servidor cambió.")
    }

    fun embed(html: String, language: String): String {
        val value = JsData.property(html, "embeds") as? Map<*, *> ?: throw ProviderChanged("AnimeAV1 cambió su estructura: no hay servidores.")
        for ((key, entries) in value) {
            if (key.toString().uppercase() != language.uppercase()) continue
            for (entry in entries as? List<*> ?: emptyList<Any>()) {
                val data = entry as? Map<*, *> ?: continue
                val url = data["url"] as? String ?: continue
                if (data["server"] == "MP4Upload" && allowed(url, "embed")) return url
            }
        }
        throw ProviderChanged("No hay MP4Upload en $language para este capítulo. No se cambió el idioma.")
    }

    private fun unescape(s: String) = s.replace("\\/", "/").replace("&amp;", "&").replace("\\u0026", "&").replace("\\x26", "&")
}

class ProviderChanged(message: String) : java.io.IOException(message)

/** Bounded parser for Svelte's literal data; no eval or script execution. */
class JsData(private val text: String) {
    private var i = 0
    private var nodes = 0
    private fun ws() { while (i < text.length && text[i].isWhitespace()) i++ }
    private fun string(): String {
        val quote = text[i++]; val out = StringBuilder()
        while (i < text.length && out.length < 2_000_000) {
            val c = text[i++]
            if (c == quote) return out.toString()
            if (c != '\\') { out.append(c); continue }
            when (val e = text.getOrNull(i++) ?: error("escape")) {
                'u', 'x' -> { val count = if (e == 'u') 4 else 2; out.append(text.substring(i, i + count).toInt(16).toChar()); i += count }
                'n' -> out.append('\n'); 'r' -> out.append('\r'); 't' -> out.append('\t')
                else -> out.append(e)
            }
        }
        error("string")
    }
    private fun value(depth: Int = 0): Any? {
        require(depth < 40 && ++nodes < 100_000); ws()
        return when (text.getOrNull(i)) {
            '\'', '"' -> string()
            '{' -> {
                i++; val map = linkedMapOf<String, Any?>(); ws()
                while (text.getOrNull(i) != '}') {
                    ws(); val key = if (text.getOrNull(i) in listOf('\'', '"')) string() else read(Regex("[A-Za-z_$][\\w$]*"))
                    ws(); require(text.getOrNull(i++) == ':'); map[key] = value(depth + 1); ws()
                    if (text.getOrNull(i) == '}') break
                    require(text.getOrNull(i++) == ','); ws()
                }; i++; map
            }
            '[' -> {
                i++; val list = mutableListOf<Any?>(); ws()
                while (text.getOrNull(i) != ']') {
                    list.add(value(depth + 1)); ws(); if (text.getOrNull(i) == ']') break
                    require(text.getOrNull(i++) == ','); ws()
                }; i++; list
            }
            else -> read(Regex("(?:true|false|null|-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)")).let {
                when (it) { "true" -> true; "false" -> false; "null" -> null; else -> it.toDouble() }
            }
        }
    }
    private fun read(regex: Regex): String { val match = regex.find(text, i); require(match?.range?.first == i); i = match!!.range.last + 1; return match.value }
    companion object {
        fun property(html: String, name: String): Any? {
            val matches = Regex("(?:[\"']${Regex.escape(name)}[\"']|\\b${Regex.escape(name)})\\s*:").findAll(html)
            for (match in matches.take(30)) {
                try { return JsData(html.substring(match.range.last + 1)).value() } catch (_: RuntimeException) { }
            }
            return null
        }
    }
}
