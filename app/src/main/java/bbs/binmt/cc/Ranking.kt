package bbs.binmt.cc

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.jsoup.Jsoup

data class Ranking(
    val title: String,
    val categories: List<NativeTab>,
    val filters: List<NativeTab>,
    val periods: List<NativeTab>,
    val entries: List<Pair<Int, Link>>,
    val more: Link?,
)

fun ranking(source: String, url: String): Ranking {
    val doc = Jsoup.parse(source, url)
    val root = doc.selectFirst(".ct2_a .mn")
    fun tabs(selector: String) =
        nativeTabs(doc.selectFirst(selector), url).filter { query(it.url, "mod") == "ranklist" }
    val categories = tabs(".ct2_a .tbn ul")
    val filters = tabs(".ct2_a .mn .tb")
    val periods = tabs(".ct2_a .mn .tbmu")
    val title = root?.selectFirst("h1.mt,.bm_h h2")?.text() ?: "排行榜"
    val metric = root?.selectFirst(".tl tr")?.children()?.lastOrNull()?.text().orEmpty()
    val seen = mutableSetOf<String>()
    val entries =
        root
            ?.select(".tl tr,.hasrank dl,.bm_c .xl > li")
            ?.mapIndexedNotNull { index, row ->
                val anchor =
                    row.selectFirst("th a[href],dt:not(.y) a[href]")
                        ?: row.select("a[href]").firstOrNull {
                            threadId(safeUrl(it.attr("href"), url).orEmpty()) != null
                        }
                        ?: return@mapIndexedNotNull null
                val target =
                    safeUrl(anchor.attr("href"), url)?.takeIf(::sameOrigin)
                        ?: return@mapIndexedNotNull null
                if (!seen.add(target)) return@mapIndexedNotNull null
                val rankNode = row.selectFirst(".icn,.ranknum")
                val rank =
                    (rankNode?.selectFirst("img")?.attr("alt") ?: rankNode?.text())?.toIntOrNull()
                        ?: if (row.tagName() == "li") index + 1 else return@mapIndexedNotNull null
                val stat =
                    when (row.tagName()) {
                        "tr" ->
                            row.children().lastOrNull()?.text().orEmpty().let {
                                if (it.isBlank()) "" else "$metric $it"
                            }
                        "dl" -> row.selectFirst("dd:not(.ranknum):not(.m)")?.text().orEmpty()
                        else -> ""
                    }
                rank to
                    Link(
                        anchor.text(),
                        target,
                        detail =
                            listOf(row.selectFirst(".frm")?.text().orEmpty(), stat)
                                .filter { it.isNotBlank() }
                                .joinToString(" · "),
                        image =
                            safeUrl(row.selectFirst(".avt img")?.attr("src").orEmpty(), url)
                                .orEmpty(),
                        author = row.selectFirst("em a[href],.by cite a[href]")?.text().orEmpty(),
                    )
            }
            .orEmpty()
    val more =
        root?.selectFirst(".bm_h a[href]")?.let {
            safeUrl(it.attr("href"), url)
                ?.takeIf { sameOrigin(it) && query(it, "mod") == "ranklist" }
                ?.let { Link("完整帖子排行", it) }
        }
    return Ranking(title, categories, filters, periods, entries, more)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RankingPage(
    state: ForumState,
    modifier: Modifier,
    scroll: LazyListState,
    open: (String) -> Unit,
) {
    val data =
        remember(state.page?.source) { ranking(state.page?.source.orEmpty(), state.currentUrl) }
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
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (state.error.isNotEmpty())
                    FailurePanel(state.error) { state.replace(state.currentUrl) }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    data.periods.forEach { period ->
                        FilterChip(
                            period.selected,
                            { state.replace(period.url) },
                            label = { Text(period.label) },
                            enabled = !state.busy,
                        )
                    }
                }
                Text(
                    data.title,
                    Modifier.padding(top = 4.dp, bottom = 12.dp),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            items(data.entries, key = { it.second.url }) { (rank, link) ->
                Section(radius = 12) {
                    Row(
                        Modifier.fillMaxWidth().clickable { open(link.url) }.padding(12.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Surface(
                            Modifier.size(32.dp),
                            shape = RoundedCornerShape(10.dp),
                            color =
                                if (rank <= 3) MaterialTheme.colorScheme.primaryContainer
                                else MaterialTheme.colorScheme.surfaceContainerHighest,
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Text(
                                    "$rank",
                                    style = MaterialTheme.typography.titleSmall,
                                    color =
                                        if (rank <= 3) MaterialTheme.colorScheme.onPrimaryContainer
                                        else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                link.title,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.titleSmall,
                            )
                            if (link.author.isNotBlank() || link.image.isNotBlank())
                                Row(
                                    Modifier.padding(top = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Avatar(link.image, 24)
                                    if (link.author.isNotEmpty()) {
                                        Spacer(Modifier.width(6.dp))
                                        Text(
                                            link.author,
                                            Modifier.weight(1f),
                                            style = MaterialTheme.typography.bodySmall,
                                        )
                                    }
                                }
                            if (link.detail.isNotBlank())
                                Text(
                                    link.detail,
                                    Modifier.padding(top = 6.dp),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                        }
                    }
                }
            }
            if (data.entries.isEmpty() && !state.busy)
                item { Text("没有可显示的排行数据", Modifier.padding(24.dp)) }
            data.more?.let {
                item {
                    TextButton(onClick = { open(it.url) }, enabled = !state.busy) { Text(it.title) }
                }
            }
        }
    }
}
