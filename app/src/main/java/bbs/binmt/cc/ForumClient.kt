package bbs.binmt.cc

import android.webkit.CookieManager
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

class ForumClient(private val context: android.content.Context? = null) {
    suspend fun preview(url: String): Page {
        val result = request(url, null)
        return withContext(Dispatchers.Default) { ForumParser.parse(result.second, result.first) }
    }

    suspend fun load(url: String, fields: Map<String, String>? = null): Page {
        val session = authCookie()
        val response = source(url, fields?.entries?.map { it.key to it.value })
        val page =
            try {
                withContext(Dispatchers.Default) {
                    ForumParser.parse(response.second, response.first)
                }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (failure: Exception) {
                if (fields != null || context == null || !readOnlyPage(url)) throw failure
                val fallback = WebsiteSession(context).read(url)
                withContext(Dispatchers.Default) {
                    ForumParser.parse(fallback.second, fallback.first)
                }
            }
        check(session == authCookie()) { "账号已变化，请刷新后继续" }
        return page.copy(forms = page.forms.map { it.copy(session = session) })
    }

    suspend fun source(
        url: String,
        fields: List<Pair<String, String>>? = null,
    ): Pair<String, String> =
        try {
            request(url, fields)
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (failure: Exception) {
            // A write is never retried through a browser, even when its response was lost.
            if (fields != null || context == null || !readOnlyPage(url)) throw failure
            WebsiteSession(context).read(url)
        }

    internal suspend fun sourceWithCookie(url:String,cookie:String) = request(url,null,cookie)

    private suspend fun request(
        url: String,
        fields: List<Pair<String, String>>?,
        cookieOverride: String? = null,
    ): Pair<String, String> =
        withContext(Dispatchers.IO) {
            var target = url
            var body = fields?.joinToString("&") { "${encode(it.first)}=${encode(it.second)}" }
            repeat(6) {
                require(sameOrigin(target)) { "拒绝向站外发送论坛请求" }
                val connection = URL(target).openConnection() as HttpURLConnection
                val cancellation =
                    launch(Dispatchers.Default, start = CoroutineStart.UNDISPATCHED) {
                        try {
                            awaitCancellation()
                        } finally {
                            connection.disconnect()
                        }
                    }
                val session = authCookie()
                try {
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 15000
                    connection.readTimeout = 20000
                    connection.setRequestProperty("User-Agent", USER_AGENT)
                    connection.setRequestProperty("Referer", "$ORIGIN/")
                    (cookieOverride ?: CookieManager.getInstance().getCookie(target))?.let {
                        connection.setRequestProperty("Cookie", it)
                    }
                    body?.let {
                        connection.requestMethod = "POST"
                        connection.doOutput = true
                        connection.setRequestProperty(
                            "Content-Type",
                            "application/x-www-form-urlencoded; charset=UTF-8",
                        )
                        connection.outputStream.use { output ->
                            output.write(it.toByteArray(Charsets.UTF_8))
                        }
                    }
                    val status = connection.responseCode
                    val cookies =
                        connection.headerFields
                            .filterKeys { it?.equals("Set-Cookie", true) == true }
                            .values
                            .flatten()
                    if(cookieOverride==null)withContext(Dispatchers.Main) {
                        check(authCookie() == session) { "账号已变化，请重试" }
                        cookies.forEach { cookie ->
                            suspendCancellableCoroutine<Unit> { continuation ->
                                CookieManager.getInstance().setCookie(target, cookie) {
                                    if (continuation.isActive) continuation.resume(Unit)
                                }
                            }
                        }
                    }
                    if (status in listOf(301, 302, 303, 307, 308)) {
                        val next = safeUrl(connection.getHeaderField("Location").orEmpty(), target)
                        require(next != null && sameOrigin(next)) { "网站跳转到外部地址，请使用官网入口继续" }
                        if (body != null && status in listOf(307, 308))
                            error("提交遇到重定向，请先核对官网结果，避免重复提交")
                        target = next
                        body = null
                    } else {
                        check(status in 200..299) { "网站请求失败（HTTP $status），请稍后重试" }
                        val bytes =
                            connection.inputStream.use { it.readNBytesCompat(4 * 1024 * 1024) }
                        return@withContext target to bytes.toString(Charsets.UTF_8)
                    }
                } finally {
                    cancellation.cancel()
                    connection.disconnect()
                }
            }
            error("网站重定向次数过多")
        }
}

fun java.io.InputStream.readNBytesCompat(limit: Int): ByteArray {
    val output = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(16384)
    while (true) {
        val count = read(buffer)
        if (count < 0) break
        check(output.size() + count <= limit) { "响应超出大小限制" }
        output.write(buffer, 0, count)
    }
    return output.toByteArray()
}
