package bbs.binmt.cc

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.pager.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.flow.distinctUntilChanged

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RootPages(
    state: ForumState,
    modifier: Modifier,
    scrolls: MutableMap<String, LazyListState>,
    open: (String) -> Unit,
    website: (String) -> Unit,
    images: (GallerySelection, String) -> Unit,
    video: (String, String) -> Unit,
    dirty: (Boolean) -> Unit,
) {
    val tabs = listOf(0, 1, 3, 4)
    val pager =
        rememberPagerState(
            initialPage = tabs.indexOf(state.tab).coerceAtLeast(0),
            pageCount = { 4 },
        )
    var programmatic by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(state.tab) {
        val target = tabs.indexOf(state.tab)
        if (target >= 0 && target != pager.currentPage) {
            programmatic = true
            try {
                if (
                    android.provider.Settings.Global.getFloat(
                        context.contentResolver,
                        android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
                        1f,
                    ) == 0f
                )
                    pager.scrollToPage(target)
                else
                    pager.animateScrollToPage(
                        target,
                        animationSpec =
                            tween(300, easing = CubicBezierEasing(.645f, .045f, .355f, 1f)),
                    )
            } finally {
                programmatic = false
            }
        }
    }
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }
            .distinctUntilChanged()
            .collect { if (!programmatic && tabs[it] != state.tab) state.selectTab(tabs[it]) }
    }
    HorizontalPager(pager, modifier = modifier, beyondViewportPageCount = 3) { index ->
        val content =
            Modifier.fillMaxSize()
                .then(
                    if (index == pager.currentPage) Modifier else Modifier.clearAndSetSemantics {}
                )
        when (tabs[index]) {
            0 ->
                HomePage(
                    state,
                    content,
                    scrolls.getOrPut("home") { LazyListState() },
                    open,
                    state.tabPage(0),
                )
            1 -> DiscoverPage(state, content, open) { state.show("search") }
            4 -> MyPage(state, content, open)
            else ->
                if (!state.authenticated)
                    Column(
                        content.padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(Icons.Outlined.MailOutline, null, Modifier.size(40.dp))
                        Spacer(Modifier.height(12.dp))
                        Text("登录后查看消息", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = { state.show("login") }) { Text("登录 / 注册") }
                    }
                else
                    NativePage(
                        state,
                        content,
                        scrolls.getOrPut("messages") { LazyListState() },
                        open,
                        website,
                        images,
                        video,
                        dirty,
                        state.tabPage(3),
                        state.tabUrl(3),
                    )
        }
    }
    if (state.composeBoardOpen)
        OriginalBottomSheet(
            onDismissRequest = { state.composeBoardOpen = false },
            contentWindowInsets = {
                BottomSheetDefaults.windowInsets.only(
                    WindowInsetsSides.Top + WindowInsetsSides.Horizontal
                )
            },
        ) {
            Column(
                Modifier.fillMaxHeight(.5f).padding(start = 16.dp, top = 8.dp, end = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("选择发帖板块", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(16.dp))
                LazyColumn(
                    Modifier.weight(1f),
                    contentPadding = PaddingValues(
                        bottom = WindowInsets.safeDrawing.asPaddingValues().calculateBottomPadding()
                    ),
                ) {
                    items(forumBoards) { board ->
                        ListItem(
                            headlineContent = {
                                Text(
                                    board.title,
                                    style =
                                        MaterialTheme.typography.titleMedium.copy(
                                            fontSize = 15.sp,
                                            lineHeight = 20.25.sp,
                                        ),
                                )
                            },
                            colors =
                                ListItemDefaults.colors(
                                    containerColor = androidx.compose.ui.graphics.Color.Transparent
                                ),
                            leadingContent = { Icon(board.icon, null) },
                            modifier =
                                Modifier.clickable {
                                    state.composeBoardOpen = false
                                    open(
                                        "$ORIGIN/forum.php?mod=post&action=newthread&fid=${board.id}"
                                    )
                                },
                        )
                    }
                }
            }
        }
}
