package bbs.binmt.cc

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.jsoup.Jsoup

fun collectionSummary(link: Link, page: Page): Link {
    val post = page.posts.firstOrNull() ?: return link
    val document = Jsoup.parse(page.source)
    val first = document.selectFirst("[id^=post_][id~=post_\\d+]")?.id()?.removePrefix("post_")
    if (first != null && first != post.id) return link
    val body = Jsoup.parseBodyFragment(post.html)
    body.select("script,style,.locked,.showhide,.quote").remove()
    body.select("br").forEach { it.after(" ") }
    val text = body.text().codePoints().limit(180).toArray().let { String(it, 0, it.size) }
    return link.copy(
        author = post.author,
        image = post.avatar,
        role = post.role,
        excerpt = text,
        profile = post.profile,
        likes = document.select("#recommendv_add").text(),
    )
}

@Composable
fun collectionLinks(
    links: List<Link>,
    state: ForumState,
    scroll: LazyListState,
    prepare: Boolean = true,
): Pair<List<Link>, Boolean> {
    if (!prepare) return links to false
    var ready by remember(links) { mutableStateOf(emptyList<Link>()) }
    var loading by remember(links) { mutableStateOf(false) }
    val session = state.authenticated
    LaunchedEffect(links, session) {
        val semaphore = Semaphore(2)
        for (batch in links.chunked(10)) {
            if (ready.isNotEmpty())
                snapshotFlow {
                        scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index?.let {
                            it >= scroll.layoutInfo.totalItemsCount - 4
                        } == true
                    }
                    .first { it }
            loading = true
            val results = batch.toMutableList()
            try {
                withTimeoutOrNull(12000) {
                    batch.forEachIndexed { index, link ->
                        launch {
                            semaphore.withPermit {
                                try {
                                    if (threadId(link.url) != null)
                                        results[index] =
                                            collectionSummary(link, state.client.preview(link.url))
                                } catch (cancel: CancellationException) {
                                    throw cancel
                                } catch (_: Exception) {
                                    // Keep the original row when its HTTP-only summary fails.
                                }
                            }
                        }
                    }
                }
            } finally {
                loading = false
            }
            ready = ready + results
        }
    }
    return ready to loading
}

internal fun isMyPosts(url: String): Boolean =
    sameOrigin(url) &&
        java.net.URI(url).path == "/home.php" &&
        query(url, "mod") == "space" &&
        query(url, "do") == "thread" &&
        query(url, "view") == "me" &&
        query(url, "uid") == null &&
        query(url, "username") == null

internal fun myPostsTabs(
    source: String,
    url: String,
    previousFilter: String,
): Pair<List<NativeTab>, List<NativeTab>> {
    val type = query(url, "type") ?: "thread"
    val filter = query(url, "filter").orEmpty()
    val types = mutableListOf<NativeTab>()
    val statuses = mutableListOf<NativeTab>()
    for (anchor in Jsoup.parse(source).select(".tbmu a[href]")) {
        val target = safeUrl(anchor.attr("href"), url) ?: continue
        if (
            !sameOrigin(target) ||
                java.net.URI(target).path != "/home.php" ||
                query(target, "mod") != "space" ||
                query(target, "do") != "thread" ||
                query(target, "view") != "me" ||
                anchor.text().isBlank()
        )
            continue
        val status = query(target, "filter")
        if (status != null && type == "postcomment") continue
        val destinationType = if (status != null) type else query(target, "type") ?: "thread"
        if (destinationType !in setOf("thread", "reply", "postcomment")) continue
        val destinationFilter = status ?: if (type == "postcomment") previousFilter else filter
        val path =
            "$ORIGIN/home.php?mod=space&do=thread&view=me&type=$destinationType" +
                if (destinationType == "postcomment" || destinationFilter.isEmpty()) ""
                else "&filter=${encode(destinationFilter)}"
        val row = if (status != null) statuses else types
        if (row.none { it.url == path })
            row.add(
                NativeTab(
                    anchor.text(),
                    path,
                    if (status != null) status == filter else destinationType == type,
                )
            )
    }
    return types to statuses
}

@Composable
internal fun MyPostsPage(
    state: ForumState,
    modifier: Modifier,
    scroll: LazyListState,
    open: (String) -> Unit,
) {
    val page = state.page
    val type = query(state.currentUrl, "type") ?: "thread"
    val document = remember(page?.source) { Jsoup.parse(page?.source.orEmpty()) }
    val rows =
        remember(page, type) {
            val links = page?.links.orEmpty().associateBy { threadId(it.url) }
            val threads = linkedMapOf<String, Link>()
            var current: String? = null
            for (row in document.select(".tl tr")) {
                val subject = row.selectFirst("th a[href]")
                if (subject != null) {
                    val target = safeUrl(subject.attr("href"), page!!.url)?.takeIf(::sameOrigin)
                    current = target?.let(::threadId)
                    val tid = current ?: continue
                    val link = links[tid] ?: continue
                    val pid = target?.let { query(it, "pid") }
                    val jump =
                        if (type != "thread" && pid?.all(Char::isDigit) == true && pid.isNotEmpty())
                            "$ORIGIN/forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=$pid"
                        else link.url
                    threads.putIfAbsent(tid, link.copy(url = jump))
                } else if (type != "thread") {
                    val tid = current ?: continue
                    val excerpt =
                        row.selectFirst("td[colspan]")?.text()?.takeIf { it.isNotBlank() }
                            ?: continue
                    threads[tid]?.let {
                        threads[tid] =
                            it.copy(excerpt = (it.excerpt + " " + excerpt).trim().take(180))
                    }
                }
            }
            threads.values.toList()
        }
    val (shown, fetching) = collectionLinks(rows, state, scroll, prepare = type == "thread")
    LazyColumn(
        modifier,
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
            if (state.busy || fetching) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (state.error.isNotEmpty())
                FailurePanel(state.error) { state.replace(state.currentUrl) }
            if (page != null && rows.isEmpty() && !state.busy)
                Text(
                    document.selectFirst(".tl .emp")?.text().orEmpty().ifBlank { "暂无相关帖子" },
                    Modifier.padding(24.dp),
                )
        }
        items(shown, key = { it.url }) {
            Section(radius = 12) {
                Box(Modifier.padding(horizontal = 12.dp)) { ThreadRow(it, open) }
            }
        }
        val current = query(state.currentUrl, "page")?.toIntOrNull() ?: 1
        val pages =
            document.select(".pg a[href]").mapNotNull { anchor ->
                safeUrl(anchor.attr("href"), state.currentUrl)
                    ?.takeIf {
                        sameOrigin(it) &&
                            query(it, "mod") == "space" &&
                            query(it, "do") == "thread" &&
                            query(it, "view") == "me"
                    }
                    ?.let { query(it, "page")?.toIntOrNull()?.takeIf { it > 0 } }
            }
        if (pages.any { it != current })
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    for ((index, label) in
                        listOf(
                            pages.filter { it < current }.maxOrNull() to "上一页",
                            pages.filter { it > current }.minOrNull() to "下一页",
                        )) {
                        if (index != null)
                            TextButton(
                                onClick = {
                                    state.replace(
                                        state.currentUrl.replace(Regex("[&?]page=\\d+"), "") +
                                            "&page=$index"
                                    )
                                },
                                enabled = !state.busy,
                            ) {
                                Text(label)
                            }
                    }
                }
            }
    }
}

data class Favorite(val id: String, val link: Link)

fun favorites(source: String, url: String): List<Favorite> =
    Jsoup.parse(source, url).select("#favorite_ul > li").mapNotNull { row ->
        val id =
            row.selectFirst("input[name='favorite[]']")?.attr("value")
                ?: row.id().removePrefix("fav_")
        val a =
            row.select("a[href]").firstOrNull {
                safeUrl(it.attr("href"), url)?.let { target ->
                    threadId(target) != null ||
                        boardId(target) != null ||
                        query(target, "mod") == "group"
                } == true
            } ?: return@mapNotNull null
        val target = safeUrl(a.attr("href"), url) ?: return@mapNotNull null
        Favorite(
            id,
            Link(a.text(), target, excerpt = row.selectFirst(".xg1,.description")?.text().orEmpty()),
        )
    }

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FavoritesPage(
    state: ForumState,
    modifier: Modifier,
    scroll: LazyListState,
    open: (String) -> Unit,
    managing: Boolean,
) {
    val page = state.page
    val entries = remember(page?.source) { favorites(page?.source.orEmpty(), state.currentUrl) }
    val links = remember(entries) { entries.map { it.link } }
    val (displayed, fetching) = collectionLinks(links, state, scroll)
    val selected = remember(page?.source, managing) { mutableStateListOf<String>() }
    var confirm by remember { mutableStateOf(false) }
    val form = page?.forms?.firstOrNull { it.fields.any { f -> f.name == "favorite[]" } }
    LazyColumn(
        modifier,
        state = scroll,
        contentPadding =
            PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = LocalContentTop.current + 16.dp,
                bottom = 16.dp,
            ),
    ) {
        item {
            if (state.busy || fetching) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (state.error.isNotEmpty())
                FailurePanel(state.error) { state.replace(state.currentUrl) }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("all" to "全部", "thread" to "帖子", "forum" to "板块", "group" to "群组").forEach {
                    (type, label) ->
                    FilterChip(
                        (query(state.currentUrl, "type") ?: "all") == type,
                        { state.replace("$ORIGIN/home.php?mod=space&do=favorite&type=$type") },
                        label = { Text(label) },
                    )
                }
            }
            if (entries.isEmpty() && !state.busy) Text("暂无收藏", Modifier.padding(24.dp))
        }
        itemsIndexed(displayed, key = { _, it -> it.url }) { index, link ->
            Row(verticalAlignment = Alignment.Top) {
                if (managing && form != null)
                    Checkbox(
                        entries[index].id in selected,
                        {
                            if (it) selected.add(entries[index].id)
                            else selected.remove(entries[index].id)
                        },
                        enabled = !state.busy,
                    )
                Box(Modifier.weight(1f)) { ThreadRow(link, open) }
            }
        }
        if (managing && form != null && entries.isNotEmpty())
            item {
                FilledTonalButton(
                    onClick = { confirm = true },
                    enabled = !state.busy && selected.isNotEmpty(),
                ) {
                    Icon(Icons.Outlined.DeleteOutline, null)
                    Text("删除选中收藏（${selected.size}）")
                }
            }
        page?.next?.let { next ->
            item {
                TextButton(onClick = { state.replace(next) }, enabled = !state.busy) { Text("下一页") }
            }
        }
    }
    if (confirm && form != null)
        ConfirmDialog("删除选中收藏？", "确认删除这 ${selected.size} 项收藏？", { confirm = false }) {
            confirm = false
            val fields =
                form.fields
                    .filter { it.name != "favorite[]" && it.type != "submit" }
                    .map { it.name to it.value } +
                    selected.map { "favorite[]" to it } +
                    form.fields
                        .firstOrNull { it.type == "submit" }
                        ?.let { listOf(it.name to it.value) }
                        .orEmpty()
            state.submitFields(form, fields) { state.load(state.currentUrl, push = false) }
        }
}

@Composable
fun HistoryPage(state: ForumState, modifier: Modifier, open: (String) -> Unit) {
    if (state.history.isEmpty()) {
        Box(modifier.padding(top = LocalContentTop.current), contentAlignment = Alignment.Center) {
            Text("还没有浏览记录")
        }
        return
    }
    val scroll = rememberLazyListState()
    val (shown, fetching) = collectionLinks(state.history, state, scroll)
    LazyColumn(
        modifier,
        state = scroll,
        contentPadding =
            PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = LocalContentTop.current + 16.dp,
                bottom = 16.dp,
            ),
    ) {
        item { if (fetching) LinearProgressIndicator(Modifier.fillMaxWidth()) }
        items(shown, key = { it.url }) { ThreadRow(it, open) }
    }
}
