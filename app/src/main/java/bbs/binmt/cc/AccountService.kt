package bbs.binmt.cc

import android.webkit.CookieManager
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup

data class Account(
    val name: String,
    val uid: String,
    val fields: List<Pair<String, String>>,
    val avatar: String,
)

data class SignInInfo(
    val signed: Boolean,
    val status: String,
    val name: String,
    val avatar: String,
    val stats: List<Pair<String, String>>,
    val participants: String,
    val action: String?,
    val highlights: List<String> = emptyList(),
    val rules: String? = null,
)

fun authCookie(raw: String = CookieManager.getInstance().getCookie(ORIGIN).orEmpty()) =
    raw.split(';')
        .map { it.trim() }
        .filter {
            it.substringBefore('=').endsWith("_auth") && it.substringAfter('=', "").isNotEmpty()
        }
        .sorted()
        .joinToString(";")

object AccountService {
    fun parse(source: String): Account? {
        val doc = Jsoup.parse(source, ORIGIN)
        if (doc.selectFirst("form[id^=loginform_]") != null) return null
        val heading = doc.selectFirst("#ct h2")?.text().orEmpty()
        val uid =
            Regex("UID:\\s*(\\d+)").find(heading)?.groupValues?.get(1) ?: error("未能读取账号资料，请刷新重试")
        val name = (doc.selectFirst("#uhd h2")?.text() ?: heading.substringBefore("(UID")).trim()
        require(name.isNotBlank()) { "未能读取账号名称" }
        val fields =
            doc.select("#ct li").mapNotNull { row ->
                val label = row.selectFirst("em")?.text().orEmpty()
                val content = row.clone()
                content.select("em").remove()
                if (label.isBlank() || label.contains("IP") || content.text().isBlank()) null
                else label to content.text()
            }
        return Account(
            name,
            uid,
            fields,
            safeUrl(doc.selectFirst("#uhd img")?.attr("src").orEmpty()).orEmpty(),
        )
    }

    suspend fun validate(client: ForumClient): Account? {
        val before = authCookie()
        if (before.isBlank()) return null
        val result = parse(client.source("$ORIGIN/home.php?mod=space&do=profile").second)
        check(authCookie() == before) { "账号已变化，请重试" }
        return result
    }

    internal suspend fun validateBackup(client:ForumClient, cookies:String, uid:String):Account {
        cookiePairs(cookies)
        val account=parse(client.sourceWithCookie("$ORIGIN/home.php?mod=space&do=profile",cookies).second)
        check(account!=null && account.uid==uid){"备份凭据未通过账号验证"}
        return account
    }

    fun cookiePairs(raw: String): List<String> {
        require(raw.length <= 65536 && !raw.any { it.code < 32 || it.code == 127 }) { "备份会话格式无效" }
        val pairs = raw.split(';').map { it.trim() }.filter { it.isNotEmpty() }
        require(pairs.size <= 128 && pairs.all { Regex("^[A-Za-z0-9_.-]+=.*$").matches(it) }) {
            "备份 Cookie 无效"
        }
        return pairs
    }

    private val cookieWrites=Mutex()
    suspend fun replaceCookies(raw:String,expected:String?=null)=cookieWrites.withLock {
        withContext(Dispatchers.Main.immediate+kotlinx.coroutines.NonCancellable) {
            val manager=CookieManager.getInstance()
            fun values(raw:String)=cookiePairs(raw).associate{it.substringBefore('=') to it.substringAfter('=')}
            val old=values(manager.getCookie(ORIGIN).orEmpty());val incoming=values(raw)
            check(expected==null || authCookie()==authCookie(expected)){"账号已改变，未替换当前会话"}
            val owned=linkedMapOf<String,String?>()
            suspend fun set(name:String,value:String?) {
                val cookies=listOf("", "; Domain=bbs.binmt.cc", "; Domain=.binmt.cc").map { domain -> "$name=; Path=/; Max-Age=0; Secure$domain" } +
                    if(value==null)emptyList()else listOf("$name=$value; Path=/; Secure; HttpOnly")
                for(cookie in cookies)kotlinx.coroutines.withTimeout(5000) { suspendCancellableCoroutine<Unit>{continuation->
                    manager.setCookie(ORIGIN,cookie){ok->if(continuation.isActive)continuation.resumeWith(if(ok)Result.success(Unit)else Result.failure(IllegalStateException("会话写入失败")))}
                } }
            }
            try {
                for(name in old.keys+incoming.keys) {
                    val current=values(manager.getCookie(ORIGIN).orEmpty())
                    check(owned.all{current[it.key]==it.value} && (old.keys-owned.keys).all{current[it]==old[it]}){"账号已改变，已停止旧恢复"}
                    if(old[name]==incoming[name])continue
                    owned[name]=incoming[name]
                    set(name,incoming[name])
                }
                manager.flush()
            }catch(failure:Exception){
                try {
                    for((name,value) in owned)if(values(manager.getCookie(ORIGIN).orEmpty())[name]==value)set(name,old[name])
                    manager.flush()
                }catch(rollback:Exception){failure.addSuppressed(rollback)}
                throw failure
            }
        }
    }

    fun parseSignIn(source: String): SignInInfo {
        val doc = Jsoup.parse(source, ORIGIN)
        check(doc.selectFirst("form[id^=loginform_]") == null) { "请先登录论坛账号" }
        val digits =
            listOf("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine")
        doc.select(".pics span").forEach { node ->
            digits
                .indexOfFirst { node.hasClass(it) }
                .takeIf { it >= 0 }
                ?.let { node.text(it.toString()) }
        }
        val status = doc.selectFirst(".paiming .font")?.text().orEmpty()
        val stats =
            doc.select(".countqian li")
                .map { it.select("h4").text() to it.select("p").text().replace(" ", "") }
                .filter { it.first.isNotBlank() && it.second.isNotBlank() }
        check(status.isNotBlank() && stats.isNotEmpty()) { "未能读取签到状态和统计，请刷新重试" }
        val signed =
            doc.selectFirst("#JD_sign")?.let { button ->
                listOf("visited", "visted", "btnvisted").any(button::hasClass) ||
                    button.text().contains("已签")
            } == true ||
                !Regex("未|还没|没有").containsMatchIn(status) &&
                    Regex("已签|已经签到|签到成功|签到排名|今日排名|今天.*排名").containsMatchIn(status)
        val action =
            doc.select("a[href]")
                .mapNotNull { safeUrl(it.attr("href")) }
                .firstOrNull {
                    sameOrigin(it) &&
                        java.net.URI(it).path == "/plugin.php" &&
                        query(it, "id") in setOf("k_misign:sign", "k_misign%3Asign") &&
                        query(it, "operation") == "qiandao" &&
                        !query(it, "formhash").isNullOrBlank()
                }
        return SignInInfo(
            signed,
            status,
            doc.select(".qdright .user .author").text(),
            safeUrl(doc.selectFirst(".qdright .user img")?.attr("src").orEmpty()).orEmpty(),
            stats,
            doc.select(".weather_p .con").text(),
            action,
            doc.select("#pt .xg1").filter { it.select("a").isEmpty() }.map { it.text() },
            doc.select("a[href]")
                .firstOrNull { it.text() == "奖励规则" }
                ?.let { safeUrl(it.attr("href")) }
                ?.takeIf(::sameOrigin),
        )
    }

    private val signMutex = Mutex()

    suspend fun signIn(client: ForumClient, permitted: () -> Boolean): SignInInfo =
        signMutex.withLock {
            val session = authCookie()
            val current = parseSignIn(client.source("$ORIGIN/k_misign-sign.html").second)
            if (current.signed) return@withLock current
            val action = current.action ?: error("未能确认可用的签到操作，请手动刷新签到页")
            check(session.isNotBlank() && session == authCookie() && permitted()) {
                "签到已取消或账号状态已变化"
            }
            client.source(action)
            check(session == authCookie() && permitted()) { "账号状态已变化" }
            parseSignIn(client.source("$ORIGIN/k_misign-sign.html").second).also {
                check(it.signed) { "论坛尚未确认签到成功，请刷新核实，避免重复操作" }
            }
        }
}
