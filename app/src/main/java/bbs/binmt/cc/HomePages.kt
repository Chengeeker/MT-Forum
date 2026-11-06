package bbs.binmt.cc

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.flow.distinctUntilChanged

data class Board(val title: String, val id: String, val icon: ImageVector)

val forumBoards =
    listOf(
        Board("版本发布", "2", Icons.Outlined.RocketLaunch),
        Board("插件交流", "37", Icons.Outlined.Extension),
        Board("建议反馈", "38", Icons.Outlined.FactCheck),
        Board("逆向交流", "41", Icons.Outlined.Code),
        Board("玩机交流", "39", Icons.Outlined.PhoneAndroid),
        Board("编程开发", "42", Icons.Outlined.Terminal),
        Board("求助问答", "40", Icons.Outlined.HelpOutline),
        Board("综合交流", "44", Icons.Outlined.Forum),
        Board("休闲灌水", "50", Icons.Outlined.Coffee),
        Board("官方公告", "46", Icons.Outlined.Campaign),
        Board("申诉举报", "53", Icons.Outlined.Shield),
        Board("站务专区", "92", Icons.Outlined.AdminPanelSettings),
    )

@Composable
fun Avatar(url: String, size: Int = 32) {
    Surface(Modifier.size(size.dp), shape = CircleShape, color = Color.Transparent) {
        var failed by remember(url) { mutableStateOf(false) }
        AsyncImage(
            if (url.isBlank() || url.contains("noavatar") || failed)
                "file:///android_asset/forum-default-avatar.gif"
            else url,
            null,
            Modifier.fillMaxSize(),
            contentScale = androidx.compose.ui.layout.ContentScale.Crop,
            onError = { failed = true },
        )
    }
}

@Composable
fun ForumLabel(text: String, hot: Boolean = false) {
    Text(
        text,
        Modifier.background(
                if (hot) Color(0xFFFF8A00) else Color(0xFFD9363E),
                RoundedCornerShape(4.dp),
            )
            .padding(horizontal = 4.dp, vertical = 1.dp),
        style = MaterialTheme.typography.labelSmall,
        color = if (hot) Color(0xFF281300) else Color.White,
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ThreadRow(link: Link, open: (String) -> Unit) {
    Column {
        Column(
            Modifier.fillMaxWidth()
                .clickable { open(link.url) }
                .padding(horizontal = 2.dp, vertical = 10.dp)
        ) {
            if (link.author.isNotBlank()) {
                Row(
                    Modifier.clickable(enabled = link.profile.isNotEmpty()) { open(link.profile) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Avatar(link.image)
                    Spacer(Modifier.width(8.dp))
                    FlowRow(
                        Modifier.weight(1f),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(link.author, style = MaterialTheme.typography.bodyMedium)
                        if (link.role.isNotBlank()) ForumLabel(link.role)
                    }
                }
                Spacer(Modifier.height(6.dp))
            }
            if (link.pinned)
                Text("置顶帖", color = Color(0xFFB3261E), style = MaterialTheme.typography.labelSmall)
            Text(
                androidx.compose.ui.text.buildAnnotatedString {
                    if (link.hot) appendInlineContent("hot", "热门")
                    append(link.title)
                },
                inlineContent =
                    mapOf(
                        "hot" to
                            androidx.compose.foundation.text.InlineTextContent(
                                androidx.compose.ui.text.Placeholder(
                                    56.sp,
                                    20.sp,
                                    androidx.compose.ui.text.PlaceholderVerticalAlign.Center,
                                )
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        Icons.Filled.LocalFireDepartment,
                                        null,
                                        Modifier.size(18.dp),
                                        tint = Color(0xFFFF8A00),
                                    )
                                    Spacer(Modifier.width(3.dp))
                                    ForumLabel("热门", true)
                                }
                            }
                    ),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
            )
            if (link.excerpt.isNotBlank())
                Text(
                    link.excerpt,
                    Modifier.padding(top = 4.dp),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 18.2.sp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            val metrics =
                listOf(
                        Icons.Outlined.Visibility to link.views,
                        Icons.Outlined.ChatBubbleOutline to link.replies,
                        Icons.Outlined.FavoriteBorder to link.likes,
                    )
                    .filter { it.second.isNotEmpty() }
            val metricContent: @Composable () -> Unit = {
                metrics.forEach { (icon, value) ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            icon,
                            null,
                            Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(3.dp))
                        Text(value, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            if (metrics.isNotEmpty() || link.date.isNotEmpty()) {
                if (LocalDensity.current.fontScale * 14 > 20)
                    FlowRow(
                        Modifier.padding(top = 6.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        metricContent()
                        Text(
                            link.date.substringBefore(' '),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                else
                    Row(
                        Modifier.fillMaxWidth().padding(top = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        FlowRow(
                            Modifier.weight(1f),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            metricContent()
                        }
                        Text(
                            link.date.substringBefore(' '),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
            }
            if (link.author.isBlank() && link.detail.isNotBlank())
                Text(
                    link.detail,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodySmall,
                )
        }
        HorizontalDivider(
            Modifier.padding(vertical = .25.dp),
            thickness = .5.dp,
            color =
                if (MaterialTheme.colorScheme.surface == Color.Black) Color.White.copy(alpha = .1f)
                else
                    MaterialTheme.colorScheme.outlineVariant.copy(
                        alpha =
                            if (MaterialTheme.colorScheme.surface.luminance() < .5f) .2f else .3f
                    ),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun homeSectionColor() =
    if (MaterialTheme.colorScheme.surface == Color.Black) MaterialTheme.colorScheme.surfaceContainer
    else MaterialTheme.colorScheme.surfaceContainerLow

@Composable
private fun homeBottomPadding(state: ForumState) =
    if (!state.settings.bool("floatingNavigation") || LocalDensity.current.fontScale * 12 > 16)
        24.dp
    else if (state.settings.bool("liquidGlass")) navigationGlassBottomPadding() + 76.dp else 72.dp

@Composable
fun HomePage(
    state: ForumState,
    modifier: Modifier,
    scroll: LazyListState,
    open: (String) -> Unit,
    page: Page? = state.page,
) {
    var expanded by rememberSaveable { mutableStateOf(true) }
    var consumedTap by rememberSaveable { mutableIntStateOf(state.homeTap) }
    LaunchedEffect(state.homeTap) {
        if (state.homeTap != consumedTap) {
            consumedTap = state.homeTap
            scroll.animateScrollToItem(0)
        }
    }
    LaunchedEffect(scroll, state.currentUrl) {
        snapshotFlow {
                Triple(
                    scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index?.let {
                        it >= scroll.layoutInfo.totalItemsCount - 4
                    } == true,
                    state.busy,
                    state.page?.next,
                )
            }
            .distinctUntilChanged()
            .collect { (near, loading, next) ->
                if (
                    near &&
                        state.tab == 0 &&
                        !loading &&
                        state.error.isEmpty() &&
                        state.page?.links?.isNotEmpty() == true
                )
                    next?.let { state.load(it, push = false, append = true) }
            }
    }
    LazyColumn(
        modifier,
        state = scroll,
        contentPadding =
            PaddingValues(
                start = 10.dp,
                end = 10.dp,
                top = LocalContentTop.current + 6.dp,
                bottom = homeBottomPadding(state),
            ),
        verticalArrangement = Arrangement.Top,
    ) {
        item {
            Row(
                Modifier.padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                listOf(
                        Triple("签到", Icons.Outlined.EventAvailable, "$ORIGIN/k_misign-sign.html"),
                        Triple(
                            "精华",
                            Icons.Outlined.StarOutline,
                            "$ORIGIN/forum.php?mod=guide&view=digest",
                        ),
                        Triple("版规", Icons.Outlined.Gavel, "$ORIGIN/thread-85763-1-1.html"),
                        Triple("手册", Icons.Outlined.MenuBook, "https://mt.cc/guide/"),
                    )
                    .forEach { (title, icon, url) ->
                        Section(Modifier.weight(1f), radius = 12) {
                            Column(
                                Modifier.fillMaxWidth()
                                    .clickable { open(url) }
                                    .padding(vertical = 12.dp, horizontal = 2.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Icon(
                                    icon,
                                    null,
                                    Modifier.size(24.dp),
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                                Spacer(Modifier.height(8.dp))
                                Text(title, style = MaterialTheme.typography.labelMedium)
                            }
                        }
                    }
            }
        }
        item {
            Section(Modifier.padding(bottom = 8.dp), radius = 12) {
                Row(
                    Modifier.fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .clickable { expanded = !expanded }
                        .padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("板块", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    Icon(
                        if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        null,
                    )
                }
                if (expanded)
                    BoxWithConstraints {
                        val columns =
                            if (maxWidth > 650.dp) 6
                            else if (LocalDensity.current.fontScale * 14 > 22) 3 else 4
                        Column(Modifier.padding(start = 8.dp, end = 8.dp, bottom = 8.dp)) {
                            forumBoards.chunked(columns).forEach { row ->
                                Row(Modifier.fillMaxWidth()) {
                                    row.forEach { board ->
                                        Column(
                                            Modifier.weight(1f)
                                                .clickable {
                                                    open("$ORIGIN/forum-${board.id}-1.html")
                                                }
                                                .padding(vertical = 4.dp, horizontal = 2.dp),
                                            horizontalAlignment = Alignment.CenterHorizontally,
                                        ) {
                                            Surface(
                                                Modifier.size(36.dp),
                                                shape = CircleShape,
                                                color = MaterialTheme.colorScheme.secondaryContainer,
                                            ) {
                                                Box(contentAlignment = Alignment.Center) {
                                                    Icon(board.icon, null)
                                                    page
                                                        ?.boards
                                                        ?.firstOrNull {
                                                            query(it.url, "fid") == board.id ||
                                                                it.url.contains(
                                                                    "forum-${board.id}-"
                                                                )
                                                        }
                                                        ?.image
                                                        ?.takeIf { it.isNotBlank() }
                                                        ?.let {
                                                            AsyncImage(
                                                                it,
                                                                null,
                                                                Modifier.fillMaxSize(),
                                                                contentScale =
                                                                    androidx.compose.ui.layout
                                                                        .ContentScale
                                                                        .Crop,
                                                            )
                                                        }
                                                }
                                            }
                                            Spacer(Modifier.height(4.dp))
                                            Text(
                                                board.title,
                                                style = MaterialTheme.typography.labelMedium,
                                                textAlign = TextAlign.Center,
                                            )
                                        }
                                    }
                                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                                }
                            }
                        }
                    }
            }
        }
        item {
            Section(Modifier.padding(bottom = 8.dp), radius = 12) {
                Row(
                    Modifier.fillMaxWidth().padding(start = 12.dp, end = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("排行榜", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    IconButton(onClick = { open("$ORIGIN/misc.php?mod=ranklist") }) {
                        Icon(Icons.Outlined.ChevronRight, "更多排行榜")
                    }
                }
                page?.hot?.take(10)?.forEachIndexed { i, link ->
                    Row(
                        Modifier.fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .clickable { open(link.url) }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "${i+1}",
                            Modifier.width(24.dp),
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.primary,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            link.title,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }
        }
        item {
            Row(
                Modifier.fillMaxWidth()
                    .background(
                        homeSectionColor(),
                        RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp),
                    )
                    .padding(start = 12.dp, end = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("最新帖子", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = { open(HOME_LATEST) }) {
                    Icon(Icons.Outlined.ChevronRight, "更多最新帖子")
                }
            }
        }
        items(page?.links.orEmpty(), key = { it.url }) { link ->
            Box(Modifier.background(homeSectionColor()).padding(horizontal = 12.dp)) {
                ThreadRow(link, open)
            }
        }
        item {
            Box(
                Modifier.fillMaxWidth()
                    .background(
                        homeSectionColor(),
                        RoundedCornerShape(bottomStart = 12.dp, bottomEnd = 12.dp),
                    )
                    .heightIn(min = 64.dp),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    state.busy ->
                        Text(
                            if (page?.links.isNullOrEmpty()) "正在加载最新帖子…" else "正在加载更多帖子…",
                            Modifier.padding(24.dp),
                            style =
                                if (page?.links.isNullOrEmpty()) MaterialTheme.typography.bodyMedium
                                else MaterialTheme.typography.bodySmall,
                        )
                    state.error.isNotEmpty() ->
                        FailurePanel(state.error) {
                            if (page?.next != null)
                                state.load(page.next, push = false, append = true)
                            else state.replace("$ORIGIN/")
                        }
                    page?.next != null ->
                        TextButton(
                            onClick = { state.load(page.next, push = false, append = true) }
                        ) {
                            Text("加载更多帖子")
                        }
                    else ->
                        Text(
                            if (page?.links.isNullOrEmpty()) "暂时没有内容" else "已经到底了",
                            Modifier.padding(24.dp),
                        )
                }
            }
        }
    }
}

@Composable
fun DiscoverPage(
    state: ForumState,
    modifier: Modifier,
    open: (String) -> Unit,
    search: () -> Unit,
) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(top = LocalContentTop.current)
            .padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = homeBottomPadding(state))
    ) {
        Surface(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(onClick = search),
            shape = CircleShape,
            color =
                if (MaterialTheme.colorScheme.surface == Color.Black) Color(0xFF1C1C1E)
                else MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Search, null)
                Spacer(Modifier.width(16.dp))
                Text("搜索帖子、作者与内容", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(24.dp))
        Section {
            listOf(
                    Triple("最新发表", "forum.php?mod=guide&view=newthread", Icons.Outlined.Schedule),
                    Triple(
                        "最新回复",
                        "forum.php?mod=guide&view=new",
                        Icons.Outlined.ChatBubbleOutline,
                    ),
                    Triple(
                        "人气热门",
                        "forum.php?mod=guide&view=hot",
                        Icons.Outlined.LocalFireDepartment,
                    ),
                    Triple("精华内容", "forum.php?mod=guide&view=digest", Icons.Outlined.StarOutline),
                    Triple("排行榜", "misc.php?mod=ranklist", Icons.Outlined.Leaderboard),
                )
                .forEach { (title, path, icon) ->
                    PreferenceRow(title, icon = icon, onClick = { open("$ORIGIN/$path") })
                }
        }
    }
}

@Composable
fun MyPage(state: ForumState, modifier: Modifier, open: (String) -> Unit) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(top = LocalContentTop.current)
            .padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = homeBottomPadding(state))
    ) {
        Section {
            Row(
                Modifier.fillMaxWidth()
                    .clickable {
                        if (state.authenticated) state.show("account") else state.show("login")
                    }
                    .heightIn(min = 72.dp)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Avatar(state.account?.avatar.orEmpty(), 40)
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        state.account?.name ?: if (state.authenticated) "论坛账号" else "登录 / 注册",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        state.account?.let { "UID: ${it.uid}" }
                            ?: if (state.authenticated) "查看资料及管理账号" else "登录、查看资料及管理账号",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.width(16.dp))
                Icon(
                    Icons.Outlined.ChevronRight,
                    null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(Modifier.height(24.dp))
        Section {
            PreferenceRow(
                "我的帖子",
                icon = Icons.Outlined.Article,
                onClick = { open("$ORIGIN/home.php?mod=space&do=thread&view=me") },
            )
            PreferenceRow(
                "我的收藏",
                icon = Icons.Outlined.BookmarkBorder,
                onClick = { open("$ORIGIN/home.php?mod=space&do=favorite&view=me") },
            )
            PreferenceRow(
                "浏览历史",
                icon = Icons.Outlined.History,
                onClick = { state.show("history") },
            )
        }
        Spacer(Modifier.height(24.dp))
        Section {
            PreferenceRow(
                "设置",
                "个性化、存储与账号",
                Icons.Outlined.Settings,
                onClick = { state.show("settings") },
            )
        }
    }
}

@Composable
fun FailurePanel(message: String, retry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Outlined.CloudOff,
            null,
            Modifier.size(36.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Text(message, textAlign = TextAlign.Center)
        Spacer(Modifier.height(12.dp))
        FilledTonalButton(onClick = retry) { Text("重试") }
    }
}

@Composable
fun ForumNavigation(state: ForumState, modifier: Modifier = Modifier) {
    val labels = listOf("首页", "发现", "发帖", "消息", "我的")
    val icons =
        listOf(
            Icons.Outlined.Home,
            Icons.Outlined.Search,
            Icons.Outlined.Add,
            Icons.Outlined.MailOutline,
            Icons.Outlined.PersonOutline,
        )
    if (!state.settings.bool("floatingNavigation") || LocalDensity.current.fontScale * 12 > 16) {
        NavigationBar(
            modifier.navigationBarsPadding().height(68.dp),
            windowInsets = WindowInsets(0, 0, 0, 0),
            containerColor =
                if (MaterialTheme.colorScheme.surface == Color.Black) Color.Black
                else if (MaterialTheme.colorScheme.surface.luminance() < .5f) Color(0xFF16171B)
                else MaterialTheme.colorScheme.surfaceContainer,
        ) {
            labels.forEachIndexed { i, label ->
                NavigationBarItem(
                    state.tab == i,
                    { state.selectTab(i) },
                    icon = {
                        Icon(
                            if (state.tab == i && i == 0) Icons.Rounded.Home
                            else if (state.tab == i && i == 4) Icons.Filled.Person else icons[i],
                            null,
                        )
                    },
                    label = {
                        Text(
                            label,
                            fontSize = 12.sp,
                            fontWeight =
                                FontWeight(
                                    ((if (state.tab == i) 700 else 500) +
                                            state.settings.int("fontWeightAdjustment"))
                                        .coerceIn(100, 900)
                                ),
                        )
                    },
                    colors =
                        NavigationBarItemDefaults.colors(
                            indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            selectedIconColor = MaterialTheme.colorScheme.onPrimaryContainer,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                )
            }
        }
        return
    }
    if (state.settings.bool("liquidGlass")) {
        LiquidNavigation(state, modifier)
        return
    }
    val bottom =
        if (WindowInsets.navigationBars.getBottom(LocalDensity.current) > 0) 6.dp else 14.dp
    val selected by
        animateFloatAsState(
            state.tab.toFloat(),
            tween(
                240,
                easing = androidx.compose.animation.core.CubicBezierEasing(.215f, .61f, .355f, 1f),
            ),
            label = "navigation",
        )
    BoxWithConstraints(
        modifier
            .navigationBarsPadding()
            .fillMaxWidth()
            .padding(start = 16.dp, end = 16.dp, bottom = bottom),
        contentAlignment = Alignment.Center,
    ) {
        val width = maxWidth.coerceAtMost(440.dp)
        Box(
            Modifier.width(width)
                .height(56.dp)
                .dropShadow(
                    CircleShape,
                    Shadow(
                        radius = flutterShadowRadius(16f, LocalDensity.current.density),
                        color =
                            Color.Black.copy(
                                alpha =
                                    if (MaterialTheme.colorScheme.surface.luminance() < .5f) .35f
                                    else .12f
                            ),
                        offset = DpOffset(0.dp, 4.dp),
                    ),
                )
                .background(MaterialTheme.colorScheme.surfaceContainerHigh, CircleShape)
                .padding(4.dp)
        ) {
            val itemWidth = (width - 8.dp) / 5
            Box(
                Modifier.offset(x = itemWidth * selected)
                    .width(itemWidth)
                    .fillMaxHeight()
                    .background(MaterialTheme.colorScheme.secondaryContainer, CircleShape)
            )
            Row {
                labels.forEachIndexed { i, label ->
                    var focused by remember { mutableStateOf(false) }
                    Column(
                        Modifier.weight(1f)
                            .fillMaxHeight()
                            .clip(CircleShape)
                            .border(
                                if (focused) 2.dp else 0.dp,
                                if (focused) MaterialTheme.colorScheme.primary
                                else Color.Transparent,
                                CircleShape,
                            )
                            .onFocusChanged { focused = it.isFocused }
                            .clickable { state.selectTab(i) },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(
                            if (state.tab == i && i == 0) Icons.Filled.Home
                            else if (state.tab == i && i == 3) Icons.Filled.Email
                            else if (state.tab == i && i == 4) Icons.Filled.Person else icons[i],
                            null,
                            Modifier.size(21.dp),
                            tint =
                                if (state.tab == i) MaterialTheme.colorScheme.onSecondaryContainer
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            label,
                            style = MaterialTheme.typography.labelSmall,
                            color =
                                if (state.tab == i) MaterialTheme.colorScheme.onSecondaryContainer
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}
