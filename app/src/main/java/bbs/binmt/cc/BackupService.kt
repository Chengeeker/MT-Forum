package bbs.binmt.cc

import android.webkit.CookieManager
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

object BackupRules {
    const val maxBytes = 4 * 1024 * 1024

    fun server(value: String): URI {
        val uri = URI(if (value.trim().contains("://")) value.trim() else "https://${value.trim()}")
        require(
            !uri.host.isNullOrBlank() &&
                uri.userInfo == null &&
                uri.query == null &&
                uri.fragment == null &&
                (uri.scheme == "https" ||
                    uri.scheme == "http" && uri.host in setOf("localhost", "127.0.0.1", "[::1]"))
        ) {
            "请使用有效的 HTTPS WebDAV 服务器地址"
        }
        return URI(uri.toString().let { if (it.endsWith('/')) it else "$it/" })
    }

    fun directory(value: String): String =
        value
            .trim()
            .ifBlank { "MT论坛" }
            .also {
                require(
                    it !in setOf(".", "..") &&
                        !it.any { c -> c == '/' || c == '\\' || c.code < 32 || c.code == 127 }
                ) {
                    "请输入单个文件夹名称，不要包含斜杠或上级目录"
                }
            }

    fun validate(data: JSONObject): Map<String, Any?> {
        require(
            data.optString("app") == "bbs.binmt.cc" &&
                data.optString("version") == "1.0" &&
                data.optString("backup_mode") in setOf("safe", "full")
        ) {
            "不是有效的 MT论坛备份"
        }
        val full = data.getString("backup_mode") == "full"
        val raw = data.getJSONObject("preferences")
        val output = linkedMapOf<String, Any?>()
        for (key in raw.keys()) {
            val expected = SettingsStore.defaults[key] ?: continue
            if (key == "webdav_password" && !full) continue
            val value = raw.get(key)
            require(
                when (expected) {
                    is Boolean -> value is Boolean
                    is Int -> value is Int || value is Long
                    is Float -> value is Number
                    else -> value is String
                }
            ) {
                "备份设置类型无效"
            }
            if (expected is Int)
                require(
                    (value as Number).toLong() in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()
                ) {
                    "备份数字超出范围"
                }
            when (key) {
                "themeMode",
                "imageSavePathType",
                "videoSavePathType" -> require((value as Number).toInt() in 0..2)
                "color" -> require((value as Number).toInt() in 0..7)
                "fontWeightAdjustment" ->
                    require((value as Number).toInt() in SettingsStore.weights)
                "imageCacheThresholdMb" ->
                    require((value as Number).toInt() in SettingsStore.thresholds)
                "textScale" ->
                    require((value as Number).toDouble().isFinite() && value.toDouble() in .8..1.4)
                "webdav_url" -> if ((value as String).isNotEmpty()) server(value)
                "webdav_directory" -> directory(value as String)
                "history" -> {
                    val history = JSONArray(value as String)
                    require(history.length() <= 100)
                    repeat(history.length()) {
                        val row = history.getJSONObject(it)
                        require(
                            row.get("title") is String &&
                                row.get("url") is String &&
                                threadId(row.getString("url")) != null
                        ) {
                            "浏览历史地址无效"
                        }
                    }
                }
            }
            output[key] =
                when (expected) {
                    is Int -> (value as Number).toInt()
                    is Float -> (value as Number).toFloat()
                    else -> value
                }
        }
        if (full) {
            require(data.has("forum_session")) { "全量备份缺少会话信息" }
            if (!data.isNull("forum_session")) {
                val session = data.getJSONObject("forum_session")
                require(
                    Regex("\\d+").matches(session.getString("uid")) &&
                        authCookie(session.getString("cookies")).isNotEmpty()
                ) {
                    "备份会话无效"
                }
                AccountService.cookiePairs(session.getString("cookies"))
            }
        }
        return output
    }
}

class BackupService(private val settings: SettingsStore, private val forum: ForumClient) {
    private val http =
        OkHttpClient.Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()

    private fun base() = BackupRules.server(settings.string("webdav_url"))

    private fun folder() =
        base()
            .resolve(
                encode(BackupRules.directory(settings.string("webdav_directory")))
                    .replace("+", "%20") + "/"
            )

    private suspend fun request(
        uri: URI,
        method: String,
        bytes: ByteArray? = null,
    ): Pair<Int, ByteArray> =
        withContext(Dispatchers.IO) {
            val username = settings.string("webdav_username")
            val password = settings.string("webdav_password")
            require(!username.any { it in ":\r\n" } && !password.any { it in "\r\n" }) {
                "账号或密码格式无效"
            }
            val body =
                bytes?.toRequestBody("application/json; charset=utf-8".toMediaType())
                    ?: if (method in setOf("PUT", "MKCOL", "PROPFIND"))
                        ByteArray(0).toRequestBody(null)
                    else null
            val request =
                Request.Builder()
                    .url(uri.toString())
                    .method(method, body)
                    .header(
                        "Authorization",
                        okhttp3.Credentials.basic(username, password, Charsets.UTF_8),
                    )
                    .header("Depth", "0")
                    .build()
            http.newCall(request).execute().use { response ->
                response.code to
                    (response.body?.byteStream()?.use { it.readNBytesCompat(BackupRules.maxBytes) }
                        ?: ByteArray(0))
            }
        }

    suspend fun test() {
        check(request(base(), "PROPFIND").first in setOf(200, 207)) { "连接失败，请检查服务器、账号与授权密码" }
    }

    suspend fun export(full: Boolean): JSONObject {
        val values = settings.snapshot().filterKeys { full || it != "webdav_password" }
        val data =
            JSONObject()
                .put("app", "bbs.binmt.cc")
                .put("version", "1.0")
                .put("backup_mode", if (full) "full" else "safe")
                .put(
                    "exported_at",
                    java.text
                        .SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", java.util.Locale.ROOT)
                        .format(java.util.Date()),
                )
                .put("preferences", JSONObject(values))
        if (full) {
            val before = CookieManager.getInstance().getCookie(ORIGIN).orEmpty()
            val account = AccountService.validate(forum)
            check(authCookie(before) == authCookie()) { "账号已变化，请重新备份" }
            data.put(
                "forum_session",
                if (account == null) JSONObject.NULL
                else
                    JSONObject()
                        .put("uid", account.uid)
                        .put("cookies", CookieManager.getInstance().getCookie(ORIGIN).orEmpty()),
            )
        }
        BackupRules.validate(data)
        return data
    }

    suspend fun upload(full: Boolean) {
        val bytes = export(full).toString(2).toByteArray(Charsets.UTF_8)
        require(bytes.size <= BackupRules.maxBytes) { "备份文件过大" }
        val target = folder()
        check(request(target, "MKCOL").first in setOf(200, 201, 405)) { "创建备份目录失败" }
        check(
            request(target.resolve("backup_mt_forum_latest.json"), "PUT", bytes).first in
                setOf(200, 201, 204)
        ) {
            "上传备份失败"
        }
        try {
            request(
                target.resolve("backup_mt_forum_${System.currentTimeMillis()}.json"),
                "PUT",
                bytes,
            )
        } catch (_: java.io.IOException) {
            /* Latest backup already succeeded. */
        }
    }

    suspend fun download(): JSONObject {
        val response = request(folder().resolve("backup_mt_forum_latest.json"), "GET")
        check(response.first == 200) { "读取备份失败（HTTP ${response.first}）" }
        return JSONObject(response.second.toString(Charsets.UTF_8)).also {
            BackupRules.validate(it)
        }
    }

    suspend fun restore(data: JSONObject) {
        val incoming = BackupRules.validate(data).toMutableMap()
        val full = data.getString("backup_mode") == "full"
        if (
            !full &&
                listOf("webdav_url", "webdav_username").any {
                    incoming.containsKey(it) && incoming[it] != settings.string(it)
                }
        )
            incoming["webdav_password"] = null
        if (full && !incoming.containsKey("webdav_password")) incoming["webdav_password"] = null
        val old = settings.snapshot()
        val cookies = CookieManager.getInstance().getCookie(ORIGIN).orEmpty()
        try {
            if (full)
                AccountService.replaceCookies(
                    data.optJSONObject("forum_session")?.optString("cookies").orEmpty()
                )
            settings.writeAll(incoming)
        } catch (failure: Exception) {
            try {
                withContext(NonCancellable) {
                    if (full) AccountService.replaceCookies(cookies)
                    settings.writeAll(old)
                }
            } catch (_: Exception) {
                error("恢复失败且本机回滚未完成，请检查设置并重新登录论坛")
            }
            throw failure
        }
    }
}
