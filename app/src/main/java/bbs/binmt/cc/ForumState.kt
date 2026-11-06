package bbs.binmt.cc

import android.app.Application
import android.view.HapticFeedbackConstants
import android.webkit.CookieManager
import androidx.compose.runtime.*
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

internal const val HOME_LATEST = "$ORIGIN/forum.php?mod=guide&view=newthread"

internal suspend fun loadHomeLatest(
    home: Page,
    existing: List<Link>,
    fetch: suspend (String) -> Page,
): Pair<Page, String> {
    var items = existing.ifEmpty { home.latest }
    var next: String? = HOME_LATEST
    val seen = mutableSetOf<String>()
    try {
        var first = true
        while (next != null && seen.add(next)) {
            val batch = fetch(next)
            val combined =
                if (first) batch.links.distinctBy { threadId(it.url) ?: it.url }
                else (items + batch.links).distinctBy { threadId(it.url) ?: it.url }
            val added = if (first) combined.isNotEmpty() else combined.size > items.size
            if (combined.isNotEmpty()) items = combined
            next = batch.next?.takeUnless { it in seen || !added }
            if (items.size >= 20 || !added) break
            first = false
        }
        return home.copy(links = items, next = next) to ""
    } catch (cancel: CancellationException) {
        throw cancel
    } catch (_: Exception) {
        return home.copy(links = items, next = next) to "最新帖子导读加载失败，已保留现有内容"
    }
}

class ForumState
@JvmOverloads
constructor(application: Application, startRequests: Boolean = true) :
    AndroidViewModel(application) {
    private val requestsEnabled = startRequests
    val settings = SettingsStore(application)
    var mode: Int
        get() = settings.int("themeMode")
        set(value) {
            settings.preview("themeMode", value)
        }

    var dynamic: Boolean
        get() = settings.bool("dynamicColor")
        set(value) {
            settings.preview("dynamicColor", value)
        }

    var pureBlack: Boolean
        get() = settings.bool("pureBlack")
        set(value) {
            settings.preview("pureBlack", value)
        }

    var fontScale: Float
        get() = settings.float("textScale")
        set(value) {
            settings.preview("textScale", value)
        }

    var history by mutableStateOf(readHistory(settings.string("history")))
    var screen by mutableStateOf("home")
    var tab by mutableIntStateOf(0)
    var page by mutableStateOf<Page?>(null)
    var busy by mutableStateOf(false)
    var writing by mutableStateOf(false)
    var refreshing by mutableStateOf(false)

    fun refresh() {
        if (!busy && !writing) {
            refreshing = true
            load(currentUrl, push = false)
        }
    }

    var error by mutableStateOf("")
    var externalLink by mutableStateOf<String?>(null)
    var pendingAction by mutableStateOf<(() -> Unit)?>(null)
    var currentUrl by mutableStateOf("$ORIGIN/")

    private data class Route(val page: Page?, val url: String, val screen: String)

    private val stack = mutableStateListOf<Route>()
    private val tabs = mutableMapOf<Int, Pair<Page?, String>>()
    private val visitedPages = mutableSetOf<String>()
    var composeBoardOpen by mutableStateOf(false)
    var homeTap by mutableIntStateOf(0)

    fun tabPage(index: Int) = if (tab == index) page else tabs[index]?.first

    fun tabUrl(index: Int) =
        if (tab == index) currentUrl
        else
            tabs[index]?.second
                ?: if (index == 3) "$ORIGIN/home.php?mod=space&do=pm" else "$ORIGIN/"

    val client = ForumClient(application)
    val userHomes = mutableMapOf<String, UserHomeData>()

    fun openUser(url: String) {
        val action = {
            generation++
            request?.cancel()
            refreshing = false
            busy = false
            stack.add(route())
            currentUrl = url
            screen = "user"
        }
        navigate(1, action)
    }

    private var loginTarget: String? = null
    private var loginDestination: String? = null
    var guard: ((Int, () -> Unit) -> Unit)? = null
    var feedback: ((Int) -> Unit)? = null
    private var replyAfterLogin: String? = null

    fun haptic(type: Int = HapticFeedbackConstants.KEYBOARD_TAP) {
        if (settings.bool("haptics")) feedback?.invoke(type)
    }

    class Draft(form: Form) {
        val session = authCookie()
        val values = mutableStateListOf<String>().apply { addAll(form.fields.map { it.value }) }
        var baseline by mutableStateOf(form.fields.map { it.value })
    }

    val drafts = mutableMapOf<Form, Draft>()
    val dirtyForms = mutableStateMapOf<Form, Boolean>()

    fun discardDrafts() {
        drafts.clear()
        dirtyForms.clear()
    }

    private fun navigate(motion: Int, action: () -> Unit, withFeedback: Boolean = true) {
        if (writing) return
        if (withFeedback) haptic()
        val run = {
            discardDrafts()
            action()
        }
        guard?.invoke(motion, run) ?: run()
    }

    private fun route() = Route(page, currentUrl, screen)

    private var backPreview by mutableStateOf<Route?>(null)

    fun previewBack(): Boolean {
        if (stack.isEmpty()) return false
        backPreview = route()
        val previous = stack.last()
        generation++
        request?.cancel()
        refreshing = false
        busy = false
        page = previous.page
        currentUrl = previous.url
        screen = previous.screen
        return true
    }

    fun finishBackPreview(commit: Boolean) {
        val previous = backPreview ?: return
        if (commit) back()
        else {
            backPreview = null
            page = previous.page
            currentUrl = previous.url
            screen = previous.screen
            if (page == null && screen == "home" && tab in setOf(0, 3))
                load(currentUrl, push = false)
        }
    }

    fun show(destination: String) {
        val action = {
            generation++
            request?.cancel()
            refreshing = false
            busy = false
            stack.add(route())
            screen = destination
        }
        navigate(1, action)
    }

    fun present(result: Page) {
        stack.add(route())
        page = result
        currentUrl = result.url
        screen = "home"
    }

    fun loginComplete() {
        val target = loginTarget
        val destination = loginDestination
        val reply = replyAfterLogin
        loginTarget = null
        loginDestination = null
        replyAfterLogin = null
        checkSession()
        back()
        if (target != null) loadNow(target, true, false, null, resumeReply = reply)
        else if (destination == "composeBoard") composeBoardOpen = true
    }

    fun maintainCache() {
        viewModelScope.launch {
            ImageCache(getApplication()).autoClear(settings.int("imageCacheThresholdMb"))
        }
    }

    var account by mutableStateOf<Account?>(null)
    var authenticated by mutableStateOf(authCookie().isNotBlank())
    var accountMessage by mutableStateOf("")
    var utilityBusy by mutableStateOf(false)
    var signInfo by mutableStateOf<SignInInfo?>(null)
    private var request: Job? = null
    private var generation = 0
    private var auth = authCookie()
    val canBack
        get() = stack.isNotEmpty() || screen != "home"

    // The preview already shows the destination while the source still owns the back gesture.
    val isRoot
        get() = screen == "home" && stack.size == (if (backPreview == null) 0 else 1)

    init {
        if (startRequests) {
            load(currentUrl, push = false)
            refreshAccount()
            if (settings.bool("autoSignIn") && authenticated)
                viewModelScope.launch {
                    try {
                        signInfo =
                            AccountService.signIn(client) {
                                settings.bool("autoSignIn") && authenticated
                            }
                    } catch (_: Exception) {
                        /* Background sign-in failures are retried only by explicit user action. */
                    }
                }
        }
    }

    fun refreshAccount() {
        val session = authCookie()
        viewModelScope.launch {
            try {
                val result = AccountService.validate(client)
                if (session == authCookie()) account = result
            } catch (_: Exception) {
                if (session == authCookie()) account = null
            }
        }
    }

    fun setSetting(key: String, value: Any) {
        haptic()
        persistSetting(key, value)
    }

    private fun persistSetting(key: String, value: Any) {
        viewModelScope.launch {
            try {
                settings.write(key, value)
            } catch (failure: Exception) {
                settings.reload()
                error = failure.message.orEmpty()
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            try {
                AccountService.replaceCookies("")
                checkSession()
                accountMessage = "已退出登录"
            } catch (failure: Exception) {
                accountMessage = failure.message.orEmpty()
            }
        }
    }

    fun checkAccount() {
        if (utilityBusy) return
        utilityBusy = true
        haptic()
        viewModelScope.launch {
            try {
                val result = AccountService.validate(client)
                account = result
                accountMessage =
                    if (result == null) "账号凭据已失效，请重新登录后继续使用账号功能。"
                    else "账号凭据有效\n\n账号：${result.name}\nUID：${result.uid}"
            } catch (_: Exception) {
                accountMessage = "检测未完成，请检查网络或网站验证后重试；这不代表账号已失效。"
            } finally {
                utilityBusy = false
            }
        }
    }

    fun signIn() {
        if (utilityBusy) return
        utilityBusy = true
        viewModelScope.launch {
            try {
                signInfo = AccountService.signIn(client) { authenticated }
                accountMessage = signInfo!!.status
            } catch (failure: Exception) {
                accountMessage = failure.message.orEmpty()
            } finally {
                utilityBusy = false
            }
        }
    }

    private fun authCookie() =
        CookieManager.getInstance()
            .getCookie(ORIGIN)
            .orEmpty()
            .split(';')
            .map { it.trim() }
            .filter { it.substringBefore('=').endsWith("_auth") }
            .sorted()
            .joinToString(";")

    fun checkSession() {
        val next = authCookie()
        if (auth != next) {
            auth = next
            authenticated = next.isNotBlank()
            account = null
            refreshAccount()
            generation++
            request?.cancel()
            refreshing = false
            tabs.clear()
            stack.clear()
            page = null
            userHomes.clear()
            discardDrafts()
            signInfo = null
            if (screen != "login") {
                screen = "home"
                tab = 0
                load("$ORIGIN/", push = false)
            }
        }
    }

    fun selectTab(index: Int, withFeedback: Boolean = true) {
        val action = { selectTabNow(index) }
        navigate(0, action, withFeedback)
    }

    private fun selectTabNow(index: Int) {
        if (index == 2) {
            composeBoardOpen = true
            return
        }
        if (tab == index && screen == "home") {
            if (index == 0) homeTap++
            return
        }
        tabs[tab] = page to currentUrl
        generation++
        request?.cancel()
        refreshing = false
        busy = false
        error = ""
        tab = index
        screen = "home"
        stack.clear()
        val saved = tabs[index]
        page = saved?.first
        currentUrl =
            saved?.second
                ?: listOf(
                    "$ORIGIN/",
                    "$ORIGIN/",
                    "$ORIGIN/",
                    "$ORIGIN/home.php?mod=space&do=pm",
                    "$ORIGIN/home.php?mod=space&do=profile",
                )[index]
        if (page == null && index == 0 || page == null && index == 3 && authenticated)
            load(currentUrl, push = false)
    }

    fun back() {
        if (writing) return
        val leavingScreen = backPreview?.screen ?: screen
        backPreview = null
        discardDrafts()
        generation++
        request?.cancel()
        refreshing = false
        busy = false
        error = ""
        if (leavingScreen == "login") {
            loginTarget = null
            loginDestination = null
            replyAfterLogin = null
        }
        if (stack.isNotEmpty()) {
            val previous = stack.removeAt(stack.lastIndex)
            page = previous.page
            currentUrl = previous.url
            screen = previous.screen
        } else screen = "home"
    }

    fun load(
        url: String,
        push: Boolean = true,
        append: Boolean = false,
        fields: Map<String, String>? = null,
        confirmed: Boolean = false,
    ) {
        if (
            !confirmed &&
                listOf(query(url, "op"), query(url, "action")).any {
                    it in setOf("delete", "remove", "logout")
                }
        ) {
            pendingAction = { load(url, push, append, fields, true) }
            return
        }
        if (push) {
            val action = { loadNow(url, true, append, fields) }
            navigate(1, action)
        } else loadNow(url, false, append, fields)
    }

    fun replace(url: String) {
        if (
            query(url, "operation") == "list" &&
                page?.source?.contains("ranklist") == true &&
                sameOrigin(url)
        ) {
            loadSignRanking(url)
            return
        }
        val action = { loadNow(url, false, false, null) }
        navigate(0, action)
    }

    private fun loadSignRanking(url: String) {
        if (busy) return
        val previous = page ?: return
        busy = true
        error = ""
        val token = ++generation
        request =
            viewModelScope.launch {
                try {
                    val response = client.source(url)
                    val html =
                        Regex("(?s)<!\\[CDATA\\[(.*?)]]>")
                            .find(response.second)
                            ?.groupValues
                            ?.get(1) ?: response.second
                    val doc = org.jsoup.Jsoup.parse(previous.source, previous.url)
                    val fragment = org.jsoup.Jsoup.parse(html, previous.url)
                    val content =
                        fragment.selectFirst("#ranklist")?.html() ?: fragment.body().html()
                    check(fragment.select("table,dl,li,.emp").isNotEmpty()) { "签到排行未返回可识别内容" }
                    doc.selectFirst("#ranklist")?.html(content) ?: error("签到排行容器缺失")
                    doc.select(".paihang a").forEach {
                        it.parent()?.removeClass("a")
                        if (signRankTarget(it, previous.url) == url) it.parent()?.addClass("a")
                    }
                    if (token == generation) page = previous.copy(source = doc.outerHtml())
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (e: Exception) {
                    if (token == generation) error = e.message.orEmpty()
                } finally {
                    if (token == generation) {
                        busy = false
                        refreshing = false
                    }
                }
            }
    }

    private fun loadNow(
        url: String,
        push: Boolean,
        append: Boolean,
        fields: Map<String, String>?,
        resumeReply: String? = null,
    ) {
        if (!requestsEnabled) return
        if (!sameOrigin(url)) {
            error = "此入口需要在浏览器打开"
            return
        }
        if (needsAccount(url) && !authenticated) {
            if (screen != "login") stack.add(route())
            loginTarget = url
            screen = "login"
            return
        }
        if (push) {
            stack.add(route())
            page = null
        }
        if (!append) currentUrl = url
        if (!append) visitedPages.clear()
        else if (url in visitedPages) {
            page = page?.copy(next = null)
            return
        }
        screen = "home"
        request?.cancel()
        val token = ++generation
        busy = true
        error = ""
        request =
            viewModelScope.launch {
                try {
                    val result = client.load(url, fields)
                    if (token != generation) return@launch
                    visitedPages.add(url)
                    val changed = auth != authCookie()
                    if (changed) {
                        auth = authCookie()
                        authenticated = auth.isNotEmpty()
                        account = null
                        tabs.clear()
                        stack.clear()
                        page = null
                        refreshAccount()
                        load("$ORIGIN/", push = false)
                        return@launch
                    }
                    if (result.requiresLogin) {
                        loginTarget = url
                        screen = "login"
                        return@launch
                    }
                    if (
                        fields != null &&
                            result.notice.isNotBlank() &&
                            result.posts.isEmpty() &&
                            !changed &&
                            page?.forms?.isNotEmpty() == true
                    ) {
                        error = result.notice
                        return@launch
                    }
                    page =
                        if (append && page != null && !changed)
                            result.copy(
                                links = (page!!.links + result.links).distinctBy { it.url },
                                posts = (page!!.posts + result.posts).distinctBy { it.id },
                                boards = page!!.boards,
                                hot = page!!.hot,
                                online = page!!.online,
                                title = page!!.title,
                                resolvedThreadId =
                                    page!!.resolvedThreadId ?: result.resolvedThreadId,
                            )
                        else if (url.trimEnd('/') == ORIGIN && fields == null)
                            result.copy(
                                links = page?.links.orEmpty().ifEmpty { result.latest },
                                next = HOME_LATEST,
                            )
                        else result
                    if (page?.next in visitedPages) page = page?.copy(next = null)
                    if (!append) currentUrl = result.url
                    if (url.trimEnd('/') == ORIGIN && fields == null && !append) {
                        val (latest, failure) =
                            loadHomeLatest(result, page?.links.orEmpty()) { client.load(it) }
                        if (token == generation) {
                            page = latest
                            error = failure
                        }
                    }
                    if (result.posts.isNotEmpty()) {
                        if (
                            resumeReply != null &&
                                authenticated &&
                                result.resolvedThreadId == threadId(url)
                        ) {
                            replyTarget = resumeReply
                            replyRevision++
                        }
                        history =
                            (listOf(Link(result.title, result.url)) +
                                    history.filter {
                                        threadId(it.url) !=
                                            (result.resolvedThreadId ?: threadId(result.url))
                                    })
                                .take(100)
                        saveHistory()
                    }
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (failure: Exception) {
                    if (token == generation) {
                        if (auth != authCookie()) checkSession()
                        else error = failure.message ?: "请求失败，请重试"
                    }
                } finally {
                    if (token == generation) {
                        busy = false
                        refreshing = false
                    }
                }
            }
    }

    fun submit(form: Form, values: Map<String, String>) {
        if (!form.supported || busy) return
        if (form.method == "post") load(form.action, push = false, fields = values)
        else
            load(
                form.action +
                    (if ('?' in form.action) "&" else "?") +
                    values.entries.joinToString("&") { "${encode(it.key)}=${encode(it.value)}" },
                push = false,
            )
    }

    var submissionRevision by mutableIntStateOf(0)
    var replyTarget by mutableStateOf<String?>(null)
    var replyRevision by mutableIntStateOf(0)

    fun loginForThread(reply: String? = null) {
        val thread = page?.resolvedThreadId ?: threadId(currentUrl) ?: return
        val returnUrl =
            currentUrl.takeIf { threadId(it) == thread } ?: "$ORIGIN/thread-$thread-1-1.html"
        val action = {
            stack.add(route())
            loginTarget = returnUrl
            replyAfterLogin = reply
            screen = "login"
        }
        navigate(1, action)
    }

    fun reply(postId: String = "") {
        if (!authenticated) {
            loginForThread(postId)
            return
        }
        if (replyTarget == postId && !writing) {
            haptic()
            replyRevision++
            return
        }
        val action: () -> Unit = {
            replyTarget = postId
            replyRevision++
        }
        navigate(0, action)
    }

    fun submitFields(
        form: Form,
        values: List<Pair<String, String>>,
        completed: ((Page) -> Unit)? = null,
    ) {
        if (busy || !form.supported) return
        if ((form.session ?: drafts[form]?.session)?.let { it != authCookie() } == true) {
            error = "账号状态已变化，请重新打开表单。输入已保留。"
            return
        }
        busy = true
        writing = true
        error = ""
        val token = ++generation
        request =
            viewModelScope.launch {
                try {
                    val target =
                        if (form.method == "get")
                            form.action +
                                (if ('?' in form.action) "&" else "?") +
                                values.joinToString("&") {
                                    "${encode(it.first)}=${encode(it.second)}"
                                }
                        else form.action
                    val response =
                        client.source(target, if (form.method == "post") values else null)
                    if (token != generation) return@launch
                    val parsed = ForumParser.parse(response.second, response.first)
                    val success =
                        Regex("成功|感谢|审核|操作完成").containsMatchIn(parsed.notice) &&
                            !Regex("失败|错误|未成功").containsMatchIn(parsed.notice)
                    if (parsed.notice.isNotEmpty() && parsed.posts.isEmpty() && !success) {
                        error = parsed.notice
                        return@launch
                    }
                    if (form.method == "post" && !success && parsed.posts.isEmpty()) {
                        error = "论坛尚未确认提交成功，请核实后再操作。输入已保留。"
                        return@launch
                    }
                    submissionRevision++
                    dirtyForms.remove(form)
                    drafts[form]?.let { it.baseline = it.values.toList() }
                    if (completed != null) completed(parsed)
                    else if (success && parsed.posts.isEmpty()) {
                        accountMessage = parsed.notice
                        if (query(currentUrl, "ac") == "privacy") load(currentUrl, push = false)
                    } else {
                        page = parsed
                        currentUrl = parsed.url
                    }
                    checkSession()
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (failure: Exception) {
                    if (token == generation) error = failure.message.orEmpty()
                } finally {
                    writing = false
                    if (token == generation) {
                        busy = false
                        refreshing = false
                    }
                }
            }
    }

    fun savePreferences() {
        viewModelScope.launch {
            try {
                settings.writeAll(settings.snapshot())
            } catch (failure: Exception) {
                settings.reload()
                error = failure.message.orEmpty()
            }
        }
    }

    private fun saveHistory() {
        persistSetting(
            "history",
            JSONArray()
                .apply {
                    history.forEach { put(JSONObject().put("title", it.title).put("url", it.url)) }
                }
                .toString(),
        )
    }

    fun restored() {
        history = readHistory(settings.string("history"))
        checkSession()
    }

    fun clearHistory() {
        history = emptyList()
        saveHistory()
    }

    private fun readHistory(value: String?): List<Link> =
        runCatching {
                val array = JSONArray(value ?: "[]")
                (0 until minOf(array.length(), 100))
                    .map { array.getJSONObject(it) }
                    .map { Link(it.getString("title"), it.getString("url")) }
                    .filter { sameOrigin(it.url) }
            }
            .getOrDefault(emptyList())
}
