package app.yomatv.engine

import com.sun.net.httpserver.HttpServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress
import java.nio.ByteBuffer

class TransferTest {
    private lateinit var server: HttpServer
    private lateinit var folder: File
    private lateinit var base: String
    private val data = ByteArray(2 * 1024 * 1024) { (it % 251).toByte() }
    private var mode = "normal"
    private var lastRange: String? = null
    private var lastValidator: String? = null
    @Before fun setup() {
        folder = kotlin.io.path.createTempDirectory("season-transfer-").toFile()
        server = HttpServer.create(InetSocketAddress("127.0.0.1",0),0)
        server.createContext("/video.mp4") { exchange ->
            lastRange = exchange.requestHeaders.getFirst("Range")
            lastValidator = exchange.requestHeaders.getFirst("If-Range")
            val start = lastRange?.substringAfter("bytes=")?.substringBefore('-')?.toIntOrNull() ?: 0
            exchange.responseHeaders.set("Content-Type", if (mode == "html") "text/html" else "video/mp4")
            if (mode != "no-validator") exchange.responseHeaders.set("ETag", if (mode == "changed206") "\"new\"" else "\"v1\"")
            if (mode == "redirect") { exchange.responseHeaders.set("Location", "http://example.invalid/video.mp4"); exchange.sendResponseHeaders(302,-1) }
            else if (start >= data.size) { exchange.responseHeaders.set("Content-Range", "bytes */${data.size}"); exchange.sendResponseHeaders(416,-1) }
            else {
                val partial = start > 0 && mode != "ignore-range"
                val offset = if (partial) start else 0
                if (partial) exchange.responseHeaders.set("Content-Range", "bytes ${if(mode=="wrong-range") start+1 else start}-${data.size-1}/${data.size}")
                exchange.sendResponseHeaders(if(partial)206 else 200, (data.size-offset).toLong())
                runCatching { exchange.responseBody.use { it.write(data,offset,data.size-offset) } }
            }
            exchange.close()
        }
        server.start(); base="http://127.0.0.1:${server.address.port}/video.mp4"
    }
    @After fun cleanup() { server.stop(0); folder.deleteRecursively() }
    private fun transfer() = Transfer { it == base }
    private fun file() = File(folder,"video.part")
    private fun expectFailure(block: () -> Unit) { try { block(); fail("Expected failure") } catch (_: java.io.IOException) { } }
    @Test fun freshDownloadExactBytes() {
        val file=file(); val result=transfer().download(base,base,file)
        assertArrayEquals(data,file.readBytes()); assertEquals(data.size.toLong(),result.total); assertTrue(result.bytesPerSecond>0)
    }
    @Test fun interruptionResumesAtExactOffsetWithValidator() {
        val file=file(); var saved=Resume()
        try { transfer().download(base,base,file,cancelled={file.length()>=512*1024},checkpoint={saved=it.resume}); fail() } catch (_:TransferStopped) { }
        val offset=file.length(); assertTrue(offset in 1 until data.size.toLong())
        transfer().download(base,base,file,saved)
        assertEquals("bytes=$offset-",lastRange); assertEquals("\"v1\"",lastValidator); assertArrayEquals(data,file.readBytes())
    }
    @Test fun serverIgnoresRangeRestartsInsteadOfAppending() {
        val file=file(); file.writeBytes(data.copyOfRange(0,10000)); mode="ignore-range"
        transfer().download(base,base,file,Resume("\"v1\"","",data.size.toLong()))
        assertArrayEquals(data,file.readBytes())
    }
    @Test fun missingValidatorRestartsSafely() {
        val file=file();file.writeBytes(ByteArray(10000){42});mode="no-validator"
        transfer().download(base,base,file,Resume())
        assertNull(lastRange);assertArrayEquals(data,file.readBytes())
    }
    @Test fun wrongRangeCannotCorruptPartial() {
        val file=file();file.writeBytes(data.copyOfRange(0,10000));mode="wrong-range"
        expectFailure {transfer().download(base,base,file,Resume("\"v1\"","",data.size.toLong()))}
        assertEquals(10000L,file.length())
    }
    @Test fun changedValidatorDoesNotMixVersions() {
        val file=file();file.writeBytes(data.copyOfRange(0,10000));mode="changed206"
        expectFailure {transfer().download(base,base,file,Resume("\"v1\"","",data.size.toLong()))}
        assertEquals(0L,file.length())
    }
    @Test fun htmlIsNeverSavedAsVideo() {mode="html";expectFailure {transfer().download(base,base,file())};assertFalse(file().exists())}
    @Test fun redirectOutsideAllowlistRejected() {
        mode="redirect"
        try {transfer().download(base,base,file());fail()}catch(_:IllegalArgumentException){}
    }
    @Test fun completedPartial416CanBeValidatedByCaller() {
        val file=file();file.writeBytes(data)
        assertEquals(file.length(),transfer().download(base,base,file,Resume("\"v1\"","",data.size.toLong())).bytes)
    }
    @Test fun invalid416IsNotSuccess() {
        val file=file();file.writeBytes(data)
        expectFailure {transfer().download(base,base,file,Resume("\"v1\"","",data.size.toLong()+1))}
    }
    @Test fun stopBeforeNetworkPreservesPartial() {
        val file=file();file.writeBytes(data.copyOfRange(0,10000));val engine=transfer();engine.stop()
        expectFailure {engine.download(base,base,file,Resume("\"v1\"","",data.size.toLong()))};assertEquals(10000L,file.length())
    }
    private fun box(type:String, payload:Int) = ByteBuffer.allocate(payload+8).putInt(payload+8).put(type.toByteArray()).put(ByteArray(payload)).array()
    @Test fun mp4StructureAndTruncation() {
        val file=file();file.writeBytes(box("ftyp",16)+box("mdat",4096)+box("moov",32))
        assertTrue(Integrity.mp4(file)); val hash=Integrity.sha256(file); assertEquals(64,hash.length)
        val content=file.readBytes();file.writeBytes(content.copyOf(content.size-10));assertFalse(Integrity.mp4(file))
    }
    @Test fun fakeMp4Rejected() {file().writeText("<html>error</html>".repeat(200));assertFalse(Integrity.mp4(file()))}
    @Test fun overflowingBoxRejected() {file().writeBytes(box("ftyp",16)+ByteBuffer.allocate(1024).putInt(1).put("mdat".toByteArray()).putLong(Long.MAX_VALUE).array());assertFalse(Integrity.mp4(file()))}
    @Test fun providerSourceUsesOnlyMp4UploadCdn() {
        assertEquals("https://a3.mp4upload.com/a/video.mp4",Provider.video("player.src({type:'video/mp4',src:'https://a3.mp4upload.com/a/video.mp4'});"))
        expectFailure {Provider.video("player.src({src:'https://evil.example/video.mp4'});")}
    }
    @Test fun urlsRejectUserInfoPortsFragmentsAndLookalikeDomains() {
        for(url in listOf("https://mp4upload.com.evil.example/video.mp4","https://evil.example@mp4upload.com/video.mp4","http://a3.mp4upload.com/video.mp4","https://a3.mp4upload.com:444/video.mp4","https://a3.mp4upload.com/video.mp4#x"))assertFalse(url,Provider.allowed(url,"video"))
        assertTrue(Provider.allowed("https://a3.mp4upload.com:183/video.mp4","video"))
    }
    @Test fun literalParserUnderstandsSvelteWithoutRunningJavascript() {
        val html="data: {embeds: {SUB: [{server: 'MP4Upload',url: 'https://www.mp4upload.com/embed-abc1234.html'}], LAT: []}}"
        assertEquals("https://www.mp4upload.com/embed-abc1234.html",Provider.embed(html,"SUB"))
        expectFailure {Provider.embed(html,"LAT")}
        expectFailure {Provider.embed("embeds: function(){fetch('secret')}","SUB")}
    }
    @Test fun unicodeAndEscapesInLiteral() {assertEquals(mapOf("text" to "ñ\n/"),JsData.property("a:{text:'\\u00f1\\n\\/'}","a"))}
}
