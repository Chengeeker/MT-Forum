package bbs.binmt.cc

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.system.Os
import android.system.OsConstants
import android.webkit.CookieManager
import coil.ImageLoader
import coil.intercept.Interceptor
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

object StorageRules {
    val imageTypes =
        mapOf(
            "image/jpeg" to "jpg",
            "image/png" to "png",
            "image/gif" to "gif",
            "image/webp" to "webp",
            "image/bmp" to "bmp",
        )
    val videoTypes =
        mapOf(
            "mp4" to "video/mp4",
            "webm" to "video/webm",
            "mov" to "video/quicktime",
            "mkv" to "video/x-matroska",
        )

    fun mediaType(value: String, video: Boolean): String {
        val type = value.substringBefore(';').trim().lowercase()
        require(
            type.isBlank() ||
                type == "application/octet-stream" ||
                if (video) type in videoTypes.values else type in imageTypes
        ) {
            "服务器没有返回可保存的媒体文件"
        }
        return type
    }

    fun folder(value: String): String =
        value
            .replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1f]"), "_")
            .replace(Regex("^\\.+|[.\\s]+$"), "")
            .trim()
            .let {
                if (it.isBlank()) "未知作者"
                else
                    String(
                        it.codePoints().limit(40).toArray(),
                        0,
                        it.codePointCount(0, it.length).coerceAtMost(40),
                    )
            }

    fun videoExtension(url: String): String? =
        runCatching {
                URI(url).path.substringAfterLast('.').lowercase().takeIf {
                    it in setOf("mp4", "webm", "mov", "mkv")
                }
            }
            .getOrNull()

    fun regular(file: File) =
        runCatching { OsConstants.S_ISREG(Os.lstat(file.path).st_mode) }.getOrDefault(false)

    fun bytes(value: Long): String {
        var amount = value.toDouble()
        var index = 0
        val units = listOf("B", "KB", "MB", "GB", "TB")
        while (amount >= 1024 && index < units.lastIndex) {
            amount /= 1024
            index++
        }
        return String.format(
            Locale.ROOT,
            if (index == 0) "%.0f %s" else "%.2f %s",
            amount,
            units[index],
        )
    }
}

internal fun acceptsForumMediaCookie(url: String): Boolean {
    if (!sameOrigin(url)) return false
    val path = URI(url).path
    return path.startsWith("/data/attachment/") ||
        path == "/attachment.php" ||
        path == "/uc_server/avatar.php" ||
        (path == "/forum.php" && query(url, "mod") in setOf("attachment", "image"))
}

class ImageCache(private val context: Context) {
    private val directory = File(context.cacheDir, "compose_cacheimage")

    fun root(): File {
        require(directory.canonicalFile == directory.absoluteFile) { "图片缓存目录不是普通目录" }
        directory.mkdirs()
        return directory
    }

    suspend fun scan(clear: Boolean = false): Long =
        withContext(Dispatchers.IO) {
            var size = 0L
            val now = System.currentTimeMillis()
            root()
                .listFiles()
                .orEmpty()
                .filter { Regex("[a-f0-9]{32}").matches(it.name) && StorageRules.regular(it) }
                .forEach { file ->
                    if (!clear) size += file.length()
                    else if (now - file.lastModified() >= 60000) {
                        val length = file.length()
                        if (file.delete()) size += length
                    }
                }
            size
        }

    suspend fun autoClear(threshold: Int) {
        if (threshold > 0)
            try {
                if (scan() >= threshold * 1024L * 1024) scan(true)
            } catch (_: Exception) {}
    }

    fun loader(): ImageLoader =
        ImageLoader.Builder(context)
            .diskCache(null)
            .components {
                if (Build.VERSION.SDK_INT >= 28) add(coil.decode.ImageDecoderDecoder.Factory())
                else add(coil.decode.GifDecoder.Factory())
                add(
                    Interceptor { chain ->
                        val url = chain.request.data.toString()
                        if (safeUrl(url) == null) return@Interceptor chain.proceed(chain.request)
                        val session = authCookie()
                        val file =
                            withContext(Dispatchers.IO) {
                                val key =
                                    MessageDigest.getInstance("MD5")
                                        .digest("$session\n$url".toByteArray())
                                        .joinToString("") { "%02x".format(it) }
                                val target = File(root(), key)
                                if (!StorageRules.regular(target)) {
                                    val temp = File.createTempFile("image-", ".tmp", root())
                                    try {
                                        MediaStorage.download(
                                            url,
                                            temp,
                                            64L * 1024 * 1024,
                                            forDisplay = true,
                                        ) {}
                                        check(session == authCookie()) { "账号已变化，请重新加载图片" }
                                        check(
                                            temp.renameTo(target) || StorageRules.regular(target)
                                        ) {
                                            "图片缓存写入失败"
                                        }
                                    } finally {
                                        temp.delete()
                                    }
                                }
                                target
                            }
                        check(session == authCookie()) { "账号已变化，请重新加载图片" }
                        chain.proceed(chain.request.newBuilder().data(file).build())
                    }
                )
            }
            .build()
}

object MediaStorage {
    suspend fun download(
        url: String,
        target: File,
        limit: Long,
        video: Boolean = false,
        forDisplay: Boolean = false,
        progress: (Long) -> Unit,
    ): String =
        withContext(Dispatchers.IO) {
            var current = url
            val allowCookie = sameOrigin(url) || URI(url).host == "cdn.binmt.cc"
            repeat(6) {
                require(safeUrl(current) != null) { "媒体链接无效" }
                val connection = URL(current).openConnection() as HttpURLConnection
                try {
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 15000
                    connection.readTimeout = 30000
                    if (URI(current).host in setOf("bbs.binmt.cc", "cdn.binmt.cc")) {
                        connection.setRequestProperty("User-Agent", USER_AGENT)
                        connection.setRequestProperty("Referer", "$ORIGIN/")
                    }
                    if (allowCookie && acceptsForumMediaCookie(current))
                        CookieManager.getInstance().getCookie(current)?.let {
                            connection.setRequestProperty("Cookie", it)
                        }
                    val status = connection.responseCode
                    if (status in setOf(301, 302, 303, 307, 308)) {
                        current =
                            safeUrl(connection.getHeaderField("Location").orEmpty(), current)
                                ?: error("媒体跳转地址无效")
                    } else {
                        check(status in 200..299) { "媒体请求失败（HTTP $status）" }
                        check(connection.contentLengthLong <= limit) { "媒体文件超过大小限制" }
                        val contentType =
                            connection.contentType.orEmpty().substringBefore(';').trim().lowercase()
                        val type =
                            if (forDisplay && contentType.startsWith("image/")) contentType
                            else StorageRules.mediaType(contentType, video)
                        var total = 0L
                        connection.inputStream.use { input ->
                            target.outputStream().use { output ->
                                val buffer = ByteArray(32768)
                                while (true) {
                                    kotlinx.coroutines.currentCoroutineContext().ensureActive()
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    total += count
                                    check(total <= limit) { "媒体文件超过大小限制" }
                                    output.write(buffer, 0, count)
                                    progress(total)
                                }
                            }
                        }
                        check(total > 0) { "媒体内容为空" }
                        return@withContext type
                    }
                } finally {
                    connection.disconnect()
                }
            }
            error("媒体跳转次数过多")
        }

    suspend fun save(
        context: Context,
        state: ForumState,
        url: String,
        video: Boolean,
        author: String,
        progress: (Long) -> Unit,
    ) {
        val type = state.settings.int(if (video) "videoSavePathType" else "imageSavePathType")
        val folder =
            when (type) {
                1 ->
                    "MT论坛/" +
                        StorageRules.folder(
                            AccountService.validate(state.client)?.name
                                ?: error("按本人昵称保存需要有效账号，请登录后重试")
                        )
                2 -> "MT论坛/" + StorageRules.folder(author)
                else -> "MT论坛"
            }
        var extension =
            if (video) StorageRules.videoExtension(url) ?: error("仅支持保存直接链接的视频文件")
            else
                runCatching { URI(url).path.substringAfterLast('.').lowercase() }
                    .getOrNull()
                    ?.takeIf { it in setOf("jpg", "jpeg", "png", "gif", "webp") } ?: "jpg"
        var mime =
            if (video)
                mapOf(
                        "mp4" to "video/mp4",
                        "webm" to "video/webm",
                        "mov" to "video/quicktime",
                        "mkv" to "video/x-matroska",
                    )
                    .getValue(extension)
            else if (extension == "jpg") "image/jpeg" else "image/$extension"
        withContext(Dispatchers.IO) {
            val dir = File(context.cacheDir, "media-downloads")
            dir.mkdirs()
            val temp = File.createTempFile("save-", ".$extension", dir)
            try {
                val type =
                    download(
                        url,
                        temp,
                        if (video) 512L * 1024 * 1024 else 64L * 1024 * 1024,
                        video,
                        progress = progress,
                    )
                if (!video) {
                    mime = type.takeIf { it in StorageRules.imageTypes } ?: "image/jpeg"
                    extension = StorageRules.imageTypes.getValue(mime)
                }
                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                val name = "mt_forum_${System.currentTimeMillis()}.$extension"
                if (Build.VERSION.SDK_INT >= 29) {
                    val collection =
                        if (video)
                            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                        else
                            MediaStore.Images.Media.getContentUri(
                                MediaStore.VOLUME_EXTERNAL_PRIMARY
                            )
                    val values =
                        ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                            put(MediaStore.MediaColumns.MIME_TYPE, mime)
                            put(
                                MediaStore.MediaColumns.RELATIVE_PATH,
                                "${if(video)Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES}/$folder",
                            )
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }
                    val resolver = context.contentResolver
                    val uri = resolver.insert(collection, values) ?: error("无法创建相册记录")
                    try {
                        resolver.openOutputStream(uri)?.use { output ->
                            temp.inputStream().use { copyMedia(it, output) }
                        } ?: error("无法写入相册")
                        check(
                            resolver.update(
                                uri,
                                ContentValues().apply {
                                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                                },
                                null,
                                null,
                            ) > 0
                        ) {
                            "无法完成相册保存"
                        }
                    } catch (failure: Exception) {
                        resolver.delete(uri, null, null)
                        throw failure
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val root =
                        Environment.getExternalStoragePublicDirectory(
                            if (video) Environment.DIRECTORY_MOVIES
                            else Environment.DIRECTORY_PICTURES
                        )
                    val output = File(root, "$folder/$name")
                    require(output.canonicalPath.startsWith(root.canonicalPath + File.separator))
                    output.parentFile!!.mkdirs()
                    try {
                        temp.inputStream().use { input ->
                            output.outputStream().use { copyMedia(input, it) }
                        }
                        MediaScannerConnection.scanFile(
                            context,
                            arrayOf(output.path),
                            arrayOf(mime),
                            null,
                        )
                    } catch (failure: Exception) {
                        output.delete()
                        throw failure
                    }
                }
            } finally {
                temp.delete()
            }
        }
    }

    private suspend fun copyMedia(input: java.io.InputStream, output: java.io.OutputStream) {
        val buffer = ByteArray(32768)
        while (true) {
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            val count = input.read(buffer)
            if (count < 0) break
            output.write(buffer, 0, count)
        }
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
    }
}
