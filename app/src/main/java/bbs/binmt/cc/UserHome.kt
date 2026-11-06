package bbs.binmt.cc

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.distinctUntilChanged
import org.jsoup.Jsoup

fun userId(url: String): String? =
    if (!sameOrigin(url) || query(url, "mod") == "spacecp") null
    else
        Regex("/space-uid-(\\d+)").find(url)?.groupValues?.get(1)
            ?: query(url, "uid")?.takeIf {
                it.matches(Regex("\\d+")) && query(url, "mod") == "space"
            }

data class UserEntry(
    val id: String,
    val name: String,
    val profile: String,
    val avatar: String,
    val date: String,
    val body: String,
    val thread: Link?,
    val actions: List<Link>,
)

data class UserContent(
    val page: Page?,
    val entries: List<UserEntry>,
    val next: String?,
    val archive: Boolean = false,
)

fun userContent(source: String, url: String, archive: Boolean = false): UserContent {
    val html = Regex("<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>").find(source)?.groupValues?.get(1) ?: source
    val uid = query(url, "uid").orEmpty()
    fun feed(archived: Boolean, page: Int) =
        "$ORIGIN/home.php?mod=spacecp&ac=follow&op=getfeed&uid=$uid&archiver=${if(archived)1 else 0}&page=$page&inajax=1&banavatar=1"
    if (html.trim() == "false")
        return UserContent(
            null,
            emptyList(),
            if (query(url, "archiver") == "0" && archive) feed(true, 1) else null,
            archive,
        )
    val doc = Jsoup.parse(html, url)
    check(doc.selectFirst("form[id^=loginform_]") == null) { "此内容需要登录后查看" }
    val entries =
        doc.select("[id^=feed_li_],#comment_ul dl").map { row ->
            val broadcast = row.id().startsWith("feed_li_")
            val author = row.selectFirst(if (broadcast) ".flw_author a" else "dt a[id^=author_]")
            val profile = safeUrl(author?.attr("href").orEmpty(), url).orEmpty()
            val body =
                row.selectFirst(if (broadcast) "[id^=original_content_]" else "dd[id^=comment_]")
                    ?.clone()
            body?.select("script,style,iframe,object,embed")?.remove()
            body?.select("a[href]")?.forEach { a ->
                safeUrl(a.attr("href"), url)?.let { a.attr("href", it) } ?: a.removeAttr("href")
            }
            val title = row.selectFirst("h2 a[href]")
            val thread =
                title?.let { a ->
                    safeUrl(a.attr("href"), url)
                        ?.takeIf { threadId(it) != null }
                        ?.let { Link(a.text(), it) }
                }
            val actions =
                row.select("dt a[href]").mapNotNull { a ->
                    safeUrl(a.attr("href"), url)
                        ?.takeIf {
                            sameOrigin(it) &&
                                query(it, "ac") == "comment" &&
                                query(it, "op") in setOf("reply", "edit", "delete")
                        }
                        ?.let { Link(a.text(), it) }
                }
            UserEntry(
                row.id(),
                author?.text().orEmpty(),
                profile,
                safeUrl(row.selectFirst(".avt img")?.attr("src").orEmpty(), url).orEmpty(),
                row.selectFirst(if (broadcast) ".flw_author span" else "dt > span.xg1")
                    ?.text()
                    .orEmpty(),
                row.selectFirst(".flw_quotenote")?.outerHtml().orEmpty() + body?.html().orEmpty(),
                thread,
                actions,
            )
        }
    val page = ForumParser.parse(html, url)
    var next =
        page.next?.takeIf {
            query(it, "uid") == uid &&
                query(it, "do") == query(url, "do") &&
                query(it, "mod") == query(url, "mod")
        }
    var archived = archive
    if (entries.isNotEmpty() && uid.isNotEmpty()) {
        if (query(url, "op") == "getfeed")
            next = feed(query(url, "archiver") == "1", (query(url, "page")?.toIntOrNull() ?: 1) + 1)
        else if (query(url, "mod") == "follow" && source.contains("op=getfeed")) {
            val flags =
                Regex("feedInfo\\s*=\\s*\\{[^}]*archiver:\\s*([01])[^}]*primary:\\s*([01])")
                    .find(source)
            archived = flags?.groupValues?.get(1) == "1"
            if (flags?.groupValues?.get(2) == "1" || archived)
                next = feed(flags?.groupValues?.get(2) != "1", 2)
        }
    }
    return UserContent(page, entries, next, archived)
}

class UserHomeData {
    var account by mutableStateOf<Account?>(null)
    var source by mutableStateOf("")
    var profileError by mutableStateOf("")
    var section by mutableStateOf("thread")
    val contents = mutableStateMapOf<String, UserContent>()
    val errors = mutableStateMapOf<String, String>()
    val loading = mutableStateMapOf<String, Boolean>()
    val scrolls = mutableMapOf<String, LazyListState>()
    val seen = mutableMapOf<String, MutableSet<String>>()
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun UserHomePage(
    state: ForumState,
    modifier: Modifier,
    open: (String) -> Unit,
    website: (String) -> Unit,
    dirty: (Boolean) -> Unit,
) {
    val uid = userId(state.currentUrl) ?: state.account?.uid ?: return
    val data = remember(uid) { state.userHomes.getOrPut(uid) { UserHomeData() } }
    val scope = rememberCoroutineScope()
    var wall by remember { mutableStateOf(false) }
    var wallDirty by remember { mutableStateOf(false) }
    var discardWall by remember { mutableStateOf(false) }
    var actionBusy by remember { mutableStateOf(false) }
    var pendingFollow by remember { mutableStateOf<Pair<String, String>?>(null) }
    var openWallAfterLoad by remember { mutableStateOf(false) }
    fun closeWall() {
        if (!state.writing) {
            if (wallDirty) discardWall = true else wall = false
        }
    }

    fun target(section: String): String? {
        if (section == "thread") return "$ORIGIN/home.php?mod=space&uid=$uid&do=thread&view=me"
        return nativeTabs(Jsoup.parse(data.source).selectFirst("#uhd .tb"), ORIGIN)
            .firstOrNull {
                if (section == "follow") query(it.url, "mod") == "follow"
                else query(it.url, "do") == section
            }
            ?.url
    }
    fun load(section: String, more: Boolean = false) {
        if (data.loading[section] == true || section == "profile") return
        val url = if (more) data.contents[section]?.next else target(section)
        if (url == null) return
        if (more && url in data.seen[section].orEmpty()) return
        data.loading[section] = true
        data.errors.remove(section)
        scope.launch {
            val session = authCookie()
            try {
                val response = state.client.source(url)
                var result =
                    withContext(Dispatchers.Default) {
                        userContent(
                            response.second,
                            response.first,
                            data.contents[section]?.archive == true,
                        )
                    }
                check(session == authCookie()) { "账号已变化" }
                result =
                    result.copy(
                        page =
                            result.page?.let { p ->
                                p.copy(forms = p.forms.map { it.copy(session = session) })
                            }
                    )
                val old = data.contents[section]
                data.contents[section] =
                    if (more && old != null)
                        result.copy(
                            entries = (old.entries + result.entries).distinctBy { it.id },
                            page =
                                result.page?.copy(
                                    links =
                                        (old.page?.links.orEmpty() + result.page.links).distinctBy {
                                            it.url
                                        }
                                ),
                        )
                    else result
                if (!more) data.seen[section] = mutableSetOf()
                data.seen.getOrPut(section) { mutableSetOf() }.add(url)
                if (section == "wall" && openWallAfterLoad) {
                    if (
                        result.page?.forms?.any { f ->
                            f.supported && f.fields.any { it.name == "message" }
                        } == true
                    )
                        wall = true
                    else state.accountMessage = "论坛未提供可用的留言表单，请刷新后重试。"
                }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (e: Exception) {
                data.errors[section] = e.message.orEmpty()
            } finally {
                data.loading[section] = false
                if (section == "wall") openWallAfterLoad = false
            }
        }
    }
    fun profile() {
        scope.launch {
            try {
                val session = authCookie()
                val response = state.client.source("$ORIGIN/home.php?mod=space&uid=$uid&do=profile")
                val account = AccountService.parse(response.second) ?: error("用户资料不可用")
                check(account.uid == uid) { "论坛返回的资料与目标用户不一致" }
                check(session == authCookie()) { "账号已变化" }
                data.account = account
                data.source = response.second
                data.profileError = ""
                if (data.section != "thread") load(data.section)
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (e: Exception) {
                data.profileError = e.message.orEmpty()
            }
        }
    }
    fun follow(target: String, session: String) {
        actionBusy = true
        state.writing = true
        scope.launch {
            try {
                check(session == authCookie()) { "账号已变化，请重新打开用户主页" }
                val response = state.client.source(target)
                val message =
                    Jsoup.parse(response.second)
                        .selectFirst("#messagetext,.alert_error")
                        ?.text()
                        .orEmpty()
                check(message.isBlank() || Regex("成功|已收听|已关注").containsMatchIn(message)) { message }
                check(session == authCookie()) { "账号已变化" }
                profile()
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (e: Exception) {
                state.accountMessage = "${e.message}\n操作未自动重试。"
            } finally {
                actionBusy = false
                state.writing = false
            }
        }
    }
    fun action(type: String) {
        if (actionBusy) return
        if (!state.authenticated) {
            state.show("login")
            return
        }
        actionBusy = true
        scope.launch {
            try {
                val session = authCookie()
                val response = state.client.source("$ORIGIN/home.php?mod=space&uid=$uid&do=profile")
                check(
                    AccountService.parse(response.second)?.uid == uid && session == authCookie()
                ) {
                    "用户或账号状态已变化，请刷新主页"
                }
                val target =
                    nativeTabs(
                            Jsoup.parse(response.second).selectFirst("#uhd .mn ul"),
                            response.first,
                        )
                        .firstOrNull { query(it.url, "ac") == type }
                        ?.url ?: error("此操作已不可用，请刷新主页")
                if (type != "follow") open(target)
                else if (query(target, "op") == "del") pendingFollow = target to session
                else follow(target, session)
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (e: Exception) {
                state.accountMessage = e.message.orEmpty()
            } finally {
                if (!state.writing) actionBusy = false
            }
        }
    }
    LaunchedEffect(uid, data.section) {
        if (data.account == null) profile()
        if (data.contents[data.section] == null) load(data.section)
    }
    val scroll = data.scrolls.getOrPut(data.section) { LazyListState() }
    val section = data.section
    val content = data.contents[section]
    LaunchedEffect(scroll, section, content?.next) {
        snapshotFlow {
                scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index?.let {
                    it >= scroll.layoutInfo.totalItemsCount - 3
                } == true
            }
            .distinctUntilChanged()
            .collect { if (it && data.errors[section] == null) load(section, true) }
    }
    Column(modifier) {
        LazyColumn(
            Modifier.fillMaxSize(),
            state = scroll,
            contentPadding =
                PaddingValues(
                    start = 16.dp,
                    end = 16.dp,
                    top = LocalContentTop.current + 16.dp,
                    bottom = 16.dp,
                ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Column(Modifier.padding(bottom = 4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(
                            data.account?.avatar.orEmpty().ifBlank { avatarUrl(state.currentUrl) },
                            56,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                data.account?.name ?: "用户主页",
                                style = MaterialTheme.typography.titleLarge,
                            )
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                data.account
                                    ?.fields
                                    ?.firstOrNull { it.first == "用户组" }
                                    ?.second
                                    ?.takeIf { it.isNotBlank() }
                                    ?.let { ForumLabel(it) }
                                Text(
                                    "UID: $uid",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                    data.account
                        ?.fields
                        ?.firstOrNull { it.first == "个人签名" }
                        ?.let {
                            Text(
                                it.second,
                                Modifier.padding(top = 12.dp),
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 3,
                                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                            )
                        }
                    if (state.screen != "account")
                        FlowRow(
                            Modifier.padding(top = if (data.source.isNotEmpty()) 12.dp else 0.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            nativeTabs(Jsoup.parse(data.source).selectFirst("#uhd .mn ul"), ORIGIN)
                                .forEach { action ->
                                    val type = query(action.url, "ac").orEmpty()
                                    if (type == "pm")
                                        FilledTonalButton(
                                            onClick = { action(type) },
                                            enabled = !actionBusy,
                                        ) {
                                            Icon(
                                                Icons.Outlined.MailOutline,
                                                null,
                                                Modifier.size(18.dp),
                                            )
                                            Spacer(Modifier.width(8.dp))
                                            Text(action.label)
                                        }
                                    else
                                        OutlinedButton(
                                            onClick = { action(type) },
                                            enabled = !actionBusy,
                                        ) {
                                            Text(action.label)
                                        }
                                }
                        }
                    if (data.profileError.isNotEmpty())
                        TextButton(onClick = ::profile) {
                            Icon(Icons.Outlined.Refresh, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("用户信息加载失败，点击重试")
                        }
                }
            }
            if (data.loading[section] == true)
                item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            data.errors[section]?.let {
                item { FailurePanel(it) { load(section, content != null) } }
            }
            when (section) {
                "profile" ->
                    items(data.account?.fields.orEmpty()) { (label, value) ->
                        Section(radius = 12) {
                            Column(Modifier.padding(12.dp)) {
                                Text(label, style = MaterialTheme.typography.titleMedium)
                                Text(value, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                "thread" ->
                    items(content?.page?.links.orEmpty(), key = { it.url }) { ThreadRow(it, open) }
                else -> {
                    if (section == "wall")
                        item {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                                FilledTonalButton(
                                    onClick = {
                                        if (state.authenticated) {
                                            openWallAfterLoad = true
                                            load("wall")
                                        } else state.show("login")
                                    },
                                    enabled = data.loading["wall"] != true,
                                ) {
                                    Icon(Icons.Outlined.Edit, null)
                                    Text("写留言")
                                }
                            }
                        }
                    items(content?.entries.orEmpty(), key = { it.id }) { entry ->
                        Section(radius = 12) {
                            Column(Modifier.padding(12.dp)) {
                                Row(
                                    Modifier.fillMaxWidth()
                                        .clickable {
                                            if (entry.profile.isNotBlank()) open(entry.profile)
                                        }
                                        .padding(vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Avatar(
                                        entry.avatar.ifBlank { data.account?.avatar.orEmpty() },
                                        36,
                                    )
                                    Spacer(Modifier.width(10.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(entry.name.ifBlank { data.account?.name ?: "匿名用户" })
                                        if (entry.date.isNotEmpty())
                                            Text(
                                                entry.date,
                                                style = MaterialTheme.typography.bodySmall,
                                            )
                                    }
                                }
                                ArticleBody(
                                    entry.body,
                                    open,
                                    textStyle = MaterialTheme.typography.bodyMedium,
                                )
                                entry.thread?.let {
                                    Row(
                                        Modifier.fillMaxWidth()
                                            .heightIn(min = 56.dp)
                                            .clickable { open(it.url) }
                                            .padding(vertical = 8.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Text(
                                            it.title,
                                            Modifier.weight(1f),
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                            style =
                                                MaterialTheme.typography.titleMedium.copy(
                                                    fontSize = 15.sp,
                                                    lineHeight = 20.25.sp,
                                                ),
                                        )
                                        Spacer(Modifier.width(16.dp))
                                        Icon(Icons.Outlined.ChevronRight, null)
                                    }
                                }
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    entry.actions.forEach {
                                        TextButton(onClick = { open(it.url) }) { Text(it.title) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (content?.next != null)
                item {
                    TextButton(
                        onClick = { load(section, true) },
                        enabled = data.loading[section] != true,
                    ) {
                        Text("加载下一页")
                    }
                }
            else if (data.loading[section] != true && data.errors[section] == null)
                item {
                    Text(
                        content?.page?.notice?.ifBlank { null }
                            ?: if (
                                content?.entries?.isEmpty() != false &&
                                    content?.page?.links?.isEmpty() != false
                            )
                                "暂无内容"
                            else "已经到底了",
                        Modifier.padding(24.dp),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
        }
    }
    if (wall)
        OriginalBottomSheet(
            onDismissRequest = ::closeWall,
            sheetState =
                rememberModalBottomSheetState(
                    skipPartiallyExpanded = true,
                    confirmValueChange = { it != SheetValue.Hidden || !wallDirty && !state.writing },
                ),
        ) {
            androidx.activity.compose.BackHandler { closeWall() }
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("写留言", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                IconButton(onClick = ::closeWall, enabled = !state.writing) {
                    Icon(Icons.Outlined.Close, "关闭留言")
                }
            }
            content
                ?.page
                ?.forms
                ?.firstOrNull { form -> form.fields.any { it.name == "message" } }
                ?.let { form ->
                    NativeForm(
                        form,
                        state,
                        { website(content.page.url) },
                        {
                            wallDirty = it
                            dirty(it)
                        },
                        completed = {
                            wall = false
                            wallDirty = false
                            dirty(false)
                            load("wall")
                        },
                    )
                }
            Spacer(Modifier.height(24.dp))
        }
    pendingFollow?.let { (target, session) ->
        ConfirmDialog("取消收听此用户？", "", { pendingFollow = null }) {
            pendingFollow = null
            follow(target, session)
        }
    }
    if (discardWall)
        ConfirmDialog("放弃这条留言？", "当前内容尚未发送。", { discardWall = false }) {
            discardWall = false
            wallDirty = false
            wall = false
            state.discardDrafts()
            dirty(false)
        }
}
