package bbs.binmt.cc

import io.flutter.embedding.android.FlutterActivity
import android.webkit.CookieManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.URI
import android.content.Intent
import android.app.Activity
import java.util.concurrent.atomic.AtomicInteger
import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var fileResult: MethodChannel.Result? = null
    private data class GallerySave(val bytes: ByteArray?, val name: String, val mime: String, val result: MethodChannel.Result, val album: String = "MT论坛", val source: File? = null)
    private var pendingGallerySave: GallerySave? = null
    private val mediaExecutor = Executors.newSingleThreadExecutor()

    private fun saveMedia(item: GallerySave) {
        mediaExecutor.execute {
            val name = item.name
            val mime = item.mime
            val result = item.result
            val video = mime.startsWith("video/")
            val base = if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
            fun writeTo(output: java.io.OutputStream) {
                if (item.source != null) item.source.inputStream().use { it.copyTo(output) }
                else output.write(item.bytes ?: throw IllegalStateException("Missing media data"))
            }
            try {
                val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val relativePath = "$base/${item.album}"
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                        put(MediaStore.MediaColumns.MIME_TYPE, mime)
                        put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val collection = if (video) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) else MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    val uri = contentResolver.insert(collection, values)
                        ?: throw IllegalStateException("MediaStore insert failed")
                    try {
                        contentResolver.openOutputStream(uri, "w")?.use { writeTo(it) }
                            ?: throw IllegalStateException("MediaStore stream unavailable")
                        contentValuesForComplete().also { contentResolver.update(uri, it, null, null) }
                    } catch (error: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw error
                    }
                    "$relativePath/$name"
                } else {
                    val directory = File(Environment.getExternalStoragePublicDirectory(base), item.album)
                    if (!directory.exists() && !directory.mkdirs()) throw IllegalStateException("Cannot create Pictures directory")
                    val file = File(directory, name)
                    if (file.exists()) throw IllegalStateException("Media file already exists")
                    try { FileOutputStream(file).use { writeTo(it) } }
                    catch (error: Exception) { file.delete(); throw error }
                    android.media.MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mime), null)
                    file.absolutePath
                }
                runOnUiThread { result.success(path) }
            } catch (error: Exception) {
                runOnUiThread { result.error("SAVE_FAILED", error.message ?: "Save failed", null) }
            }
        }
    }

    private fun contentValuesForComplete() = ContentValues().apply {
        put(MediaStore.MediaColumns.IS_PENDING, 0)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bbs.binmt.cc/session")
            .setMethodCallHandler { call, result ->
                if (call.method == "pickFiles") {
                    if (fileResult != null) { result.error("busy", "File picker already open", null); return@setMethodCallHandler }
                    fileResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.arguments == true)
                    }
                    try { startActivityForResult(intent, 4201) }
                    catch (_: Exception) { fileResult = null; result.success(emptyList<String>()) }
                    return@setMethodCallHandler
                }
                if (call.method == "saveMediaToGallery") {
                    val bytes = call.argument<ByteArray>("bytes")
                    val sourcePath = call.argument<String>("sourcePath")
                    val paths = try { Pair(sourcePath?.let { File(it).canonicalFile }, File(cacheDir, "media-downloads").canonicalFile) }
                        catch (_: Exception) { result.error("INVALID_ARGS", "Invalid media path", null); return@setMethodCallHandler }
                    val source = paths.first
                    val downloadRoot = paths.second
                    if (source != null && (bytes != null || !source.path.startsWith(downloadRoot.path + File.separator) || !source.isFile || source.length() <= 0 || source.length() > 512L * 1024 * 1024)) {
                        result.error("INVALID_ARGS", "Invalid downloaded video", null); return@setMethodCallHandler
                    }
                    if (source == null && (bytes == null || bytes.isEmpty() || bytes.size > 64 * 1024 * 1024)) {
                        result.error("INVALID_ARGS", "Invalid image data", null)
                        return@setMethodCallHandler
                    }
                    val fileName = call.argument<String>("fileName") ?: run {
                        result.error("INVALID_ARGS", "Invalid file name", null)
                        return@setMethodCallHandler
                    }
                    if (fileName in setOf(".", "..") || !fileName.matches(Regex("[A-Za-z0-9._-]{1,100}"))) {
                        result.error("INVALID_ARGS", "Invalid file name", null)
                        return@setMethodCallHandler
                    }
                    val imageMime = call.argument<String>("mimeType") ?: run {
                        result.error("INVALID_ARGS", "Invalid image type", null)
                        return@setMethodCallHandler
                    }
                    val allowed = if (source == null) setOf("image/jpeg", "image/png", "image/gif", "image/webp", "image/bmp") else setOf("video/mp4", "video/webm", "video/quicktime", "video/x-matroska")
                    if (imageMime !in allowed) {
                        result.error("INVALID_ARGS", "Invalid image type", null)
                        return@setMethodCallHandler
                    }
                    val album = call.argument<String>("album") ?: "MT论坛"
                    val leaf = album.removePrefix("MT论坛/")
                    if (album != "MT论坛" && (!album.startsWith("MT论坛/") || leaf in setOf(".", "..") || !leaf.matches(Regex("[^\\\\/:*?\"<>|\\p{Cntrl}]{1,80}")))) {
                        result.error("INVALID_ARGS", "Invalid album", null); return@setMethodCallHandler
                    }
                    val item = GallerySave(bytes, fileName, imageMime, result, album, source)
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                        checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                        if (pendingGallerySave != null) {
                            result.error("BUSY", "A gallery save is already awaiting permission", null)
                            return@setMethodCallHandler
                        }
                        pendingGallerySave = item
                        requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4202)
                    } else {
                        saveMedia(item)
                    }
                    return@setMethodCallHandler
                }
                val url = if (call.method == "setCookie") call.argument<String>("url") else call.arguments as? String
                val uri = try { URI(url ?: "") } catch (_: Exception) { null }
                if (uri?.scheme != "https" || uri.host != "bbs.binmt.cc" || (uri.port != -1 && uri.port != 443)) {
                    result.error("origin", "Forum origin required", null)
                } else if (call.method == "cookies") {
                    result.success(CookieManager.getInstance().getCookie(url) ?: "")
                } else if (call.method == "flushForumCookies") {
                    CookieManager.getInstance().flush()
                    result.success(null)
                } else if (call.method == "setCookie") {
                    val cookie = call.argument<String>("cookie")
                    if (cookie == null) result.error("cookie", "Cookie required", null)
                    else CookieManager.getInstance().setCookie(url, cookie) { result.success(null) }
                } else if (call.method == "clearForumSession") {
                    val manager = CookieManager.getInstance()
                    val paths = listOf("/", "/home.php", "/member.php", "/forum.php")
                    val names = paths.flatMap { path -> (manager.getCookie("https://bbs.binmt.cc$path") ?: "").split(';') }
                        .map { it.substringBefore('=').trim() }.filter { it.matches(Regex("[A-Za-z0-9_.-]+")) }.toSet()
                    val domains = listOf("", "bbs.binmt.cc", ".bbs.binmt.cc", "binmt.cc", ".binmt.cc")
                    val remaining = AtomicInteger(names.size * paths.size * domains.size)
                    if (names.isEmpty()) result.success(null)
                    else for (name in names) for (path in paths) for (domain in domains) {
                        val scope = if (domain.isEmpty()) "" else "Domain=$domain;"
                        manager.setCookie("https://bbs.binmt.cc$path", "$name=;Max-Age=0;Expires=Thu, 01 Jan 1970 00:00:00 GMT;Path=$path;${scope}Secure") {
                            if (remaining.decrementAndGet() == 0) { manager.flush(); result.success(null) }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
    @Deprecated("Platform callback")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4202) return
        val pending = pendingGallerySave ?: return
        pendingGallerySave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveMedia(pending)
        } else {
            pending.result.error("PERMISSION_DENIED", "Storage permission denied", null)
        }
    }

    @Deprecated("Platform callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4201) return
        val files = mutableListOf<String>()
        if (resultCode == Activity.RESULT_OK) {
            val clips = data?.clipData
            if (clips != null) for (i in 0 until clips.itemCount) files.add(clips.getItemAt(i).uri.toString())
            else data?.data?.let { files.add(it.toString()) }
        }
        fileResult?.success(files)
        fileResult = null
    }
}
