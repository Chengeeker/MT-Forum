package bbs.binmt.cc

import androidx.compose.runtime.*
import androidx.compose.ui.unit.dp
import org.jsoup.Jsoup

val LocalContentTop = staticCompositionLocalOf { 0.dp }
val messageSections =
    listOf(
        "消息" to "home.php?mod=space&do=pm",
        "我的帖子" to "home.php?mod=space&do=notice&view=mypost",
        "坛友互动" to "home.php?mod=space&do=notice&view=interactive",
        "系统提醒" to "home.php?mod=space&do=notice&view=system",
        "应用提醒" to "home.php?mod=space&do=notice&view=app",
    )

fun messageTabs(source: String, url: String): List<NativeTab> {
    val root = Jsoup.parse(source).selectFirst("#ct .mn .tb") ?: return emptyList()
    return root
        .children()
        .filter { !it.hasClass("o") && !it.hasClass("y") }
        .flatMap { nativeTabs(it, url) }
        .filter {
            query(it.url, "mod") == "space" &&
                query(it.url, "do") == query(url, "do") &&
                (query(url, "do") != "notice" || query(it.url, "view") == query(url, "view"))
        }
}

@Composable
fun PageNavigation(state: ForumState) {
    if (state.screen in setOf("user", "account")) {
        val uid = userId(state.currentUrl) ?: state.account?.uid ?: return
        val data = state.userHomes.getOrPut(uid) { UserHomeData() }
        TabStrip(
            listOf("thread" to "主题", "follow" to "广播", "wall" to "留言板", "profile" to "资料").map {
                NativeTab(it.second, it.first, it.first == data.section)
            },
            true,
        ) {
            data.section = it
        }
        return
    }
    if (state.screen != "home") return
    if (state.tab == 3 && state.isRoot) {
        TabStrip(
            messageSections.map { (label, path) ->
                val url = "$ORIGIN/$path"
                NativeTab(
                    label,
                    url,
                    query(url, "do") == query(state.currentUrl, "do") &&
                        query(url, "view") == query(state.currentUrl, "view"),
                )
            },
            state::replace,
        )
        TabStrip(
            remember(state.page?.source) {
                messageTabs(state.page?.source.orEmpty(), state.currentUrl)
            },
            state::replace,
        )
    } else if (isMyPosts(state.currentUrl)) {
        var lastFilter by remember(state.authenticated) { mutableStateOf("") }
        LaunchedEffect(state.currentUrl) {
            if (query(state.currentUrl, "type") != "postcomment")
                lastFilter = query(state.currentUrl, "filter").orEmpty()
        }
        val (types, statuses) =
            remember(state.currentUrl, state.page?.source, lastFilter) {
                myPostsTabs(state.page?.source.orEmpty(), state.currentUrl, lastFilter)
            }
        TabStrip(types, true) { if (!state.busy && !state.writing) state.replace(it) }
        TabStrip(statuses) { if (!state.busy && !state.writing) state.replace(it) }
    } else if (query(state.currentUrl, "mod") == "ranklist") {
        val data =
            remember(state.page?.source) { ranking(state.page?.source.orEmpty(), state.currentUrl) }
        TabStrip(data.categories, state::replace)
        TabStrip(data.filters, state::replace)
    } else if (query(state.currentUrl, "ac") == "privacy") {
        TabStrip(
            remember(state.page?.source) {
                nativeTabs(
                    Jsoup.parse(state.page?.source.orEmpty()).selectFirst("#ct .mn .tb"),
                    state.currentUrl,
                )
            },
            state::replace,
        )
    }
}
