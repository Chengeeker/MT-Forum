package bbs.binmt.cc

import io.flutter.embedding.android.FlutterActivity
import android.webkit.CookieManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.URI
import android.content.Intent
import android.app.Activity
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    private var fileResult: MethodChannel.Result? = null
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
                val url = if (call.method == "setCookie") call.argument<String>("url") else call.arguments as? String
                val uri = try { URI(url ?: "") } catch (_: Exception) { null }
                if (uri?.scheme != "https" || uri.host != "bbs.binmt.cc" || (uri.port != -1 && uri.port != 443)) {
                    result.error("origin", "Forum origin required", null)
                } else if (call.method == "cookies") {
                    result.success(CookieManager.getInstance().getCookie(url) ?: "")
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
