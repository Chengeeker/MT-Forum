package bbs.binmt.cc

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.PredictiveBackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        coil.Coil.setImageLoader(ImageCache(this).loader())
        setContent {
            val state: ForumState = viewModel()
            ForumApp(state)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForumApp(state: ForumState) {
    val context = LocalContext.current
    val dark = state.mode == 2 || (state.mode == 0 && isSystemInDarkTheme())
    var colors =
        if (state.dynamic && Build.VERSION.SDK_INT >= 31) {
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        } else
            originalColorSchemes[
                state.settings.int("color").coerceIn(0, 7) * 2 + if (dark) 1 else 0]
    if (dark && state.pureBlack)
        colors =
            colors.copy(
                surface = Color.Black,
                background = Color.Black,
                surfaceContainer = Color(0xFF121212),
                surfaceContainerHigh = Color(0xFF181818),
                surfaceContainerHighest = Color(0xFF222222),
            )
    val weight = state.settings.int("fontWeightAdjustment")
    fun text(size: Int, line: Int, base: Int = 400) =
        TextStyle(
            fontSize = size.sp,
            lineHeight = line.sp,
            fontWeight = FontWeight((base + weight).coerceIn(100, 900)),
            letterSpacing = 0.sp,
        )
    val type =
        Typography(
            displayLarge = text(57, 64),
            displayMedium = text(45, 52),
            displaySmall = text(36, 44),
            headlineLarge = text(32, 40),
            headlineMedium = text(28, 36),
            headlineSmall = text(24, 32),
            bodyLarge = text(16, 24),
            bodyMedium = text(14, 20),
            bodySmall = text(12, 16).copy(color = colors.onSurfaceVariant),
            titleLarge = text(22, 28, 700),
            titleMedium = text(16, 24, 600),
            titleSmall = text(14, 20, 600).copy(color = colors.onSurfaceVariant),
            labelLarge = text(14, 20, 600),
            labelMedium = text(12, 16, 500),
            labelSmall = text(11, 16, 500),
        )
    var browser by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(state.externalLink) {
        state.externalLink?.let {
            browser = it
            state.externalLink = null
        }
    }
    val savedRoutes = androidx.compose.runtime.saveable.rememberSaveableStateHolder()
    var about by remember { mutableStateOf(false) }
    var clearHistory by remember { mutableStateOf(false) }
    var cacheRevision by remember { mutableIntStateOf(0) }
    var cacheBusy by remember { mutableStateOf(false) }
    var media by remember { mutableStateOf<GallerySelection?>(null) }
    var mediaAuthor by remember { mutableStateOf("") }
    var video by remember { mutableStateOf<String?>(null) }
    var dirty by remember { mutableStateOf(false) }
    var discard by remember { mutableStateOf(false) }
    var pendingNavigation by remember { mutableStateOf<(() -> Unit)?>(null) }
    val motion = rememberRouteMotion()
    val hostView = androidx.compose.ui.platform.LocalView.current
    SideEffect {
        (context as? android.app.Activity)?.window?.let { window ->
            androidx.core.view.WindowCompat.getInsetsController(window, hostView).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
        state.feedback = { type ->
            hostView.performHapticFeedback(type)
            Unit
        }
        state.guard = { direction, action ->
            if (dirty || state.dirtyForms.values.any { it }) {
                pendingNavigation = { motion.navigate(direction, action) }
                discard = true
            } else motion.navigate(direction, action)
        }
    }
    DisposableEffect(state) {
        onDispose {
            state.guard = null
            state.feedback = null
        }
    }
    val scrolls = remember { mutableMapOf<String, LazyListState>() }
    val root = state.isRoot
    val open: (String) -> Unit = { url ->
        if (url.startsWith("mailto:", true))
            runCatching {
                    context.startActivity(
                        android.content.Intent(
                            android.content.Intent.ACTION_SENDTO,
                            android.net.Uri.parse(url),
                        )
                    )
                }
                .onFailure { state.error = "没有可打开此链接的应用" }
        else
            browserUrl(url)?.let {
                if (
                    java.net
                        .URI(it)
                        .path
                        .lowercase()
                        .matches(Regex(".*\\.(mp4|m3u8|m4v|mov|webm)$")) && safeUrl(it) != null
                )
                    video = it
                else if (userId(it) != null) state.openUser(it)
                else if (sameOrigin(it)) state.load(it) else browser = it
            }
    }
    fun back() {
        if (state.writing) return
        if (dirty || state.dirtyForms.values.any { it }) {
            pendingNavigation = { motion.navigate(-1) { state.back() } }
            discard = true
        } else motion.navigate(-1) { state.back() }
    }
    val density = LocalDensity.current
    val pageBackground = if (dark && !state.pureBlack) Color(0xFF111215) else colors.surface
    val backdrop = rememberBackdrop(pageBackground)
    LaunchedEffect(Unit) {
        ImageCache(context).autoClear(state.settings.int("imageCacheThresholdMb"))
    }
    CompositionLocalProvider(
        LocalDensity provides Density(density.density, density.fontScale * state.fontScale),
        LocalRippleConfiguration provides null,
        LocalBackdrop provides backdrop,
    ) {
        MaterialTheme(colorScheme = colors, typography = type) {
            ProvideTextStyle(type.bodyMedium) {
                PredictiveBackHandler(state.canBack) { events ->
                    if (state.writing) events.collect {}
                    else if (dirty || state.dirtyForms.values.any { it }) {
                        events.collect {}
                        back()
                    } else motion.predictive(state, events)
                }
                val firstPost =
                    state.page?.posts?.firstOrNull()?.takeIf { state.screen == "home" && !root }
                val favoriteScreen =
                    state.screen == "home" && !root && query(state.currentUrl, "do") == "favorite"
                var managingFavorites by remember(favoriteScreen) { mutableStateOf(false) }
                val title =
                    when (state.screen) {
                        "settings" -> "设置"
                        "appearance" -> "个性化"
                        "storage" -> "存储设置"
                        "cache" -> "缓存管理"
                        "backup" -> "WebDAV 云端备份与恢复"
                        "history" -> "浏览历史"
                        "login" -> "登录 MT论坛"
                        "search" -> "搜索论坛"
                        "user" -> "用户主页"
                        "account" -> if (state.account != null) "我的主页" else "论坛账号"
                        "composeBoard" -> "选择发帖板块"
                        else ->
                            if (root) listOf("MT论坛", "发现", "发帖", "消息", "我的")[state.tab]
                            else if (favoriteScreen) "我的收藏"
                            else if (state.currentUrl.contains("k_misign")) "签到"
                            else state.page?.title ?: "MT论坛"
                    }
                RouteMotionHost(motion) { motionModifier ->
                    Scaffold(
                        modifier = motionModifier,
                        containerColor = pageBackground,
                        contentColor = colors.onSurface,
                        topBar = {
                            Box {
                                FrostedBackdrop(Modifier.matchParentSize(), dark)
                                Column(
                                    Modifier.background(pageBackground.copy(alpha = .45f))
                                        .background(
                                            Brush.verticalGradient(
                                                listOf(
                                                    pageBackground.copy(alpha = .95f),
                                                    pageBackground.copy(alpha = 0f),
                                                )
                                            )
                                        )
                                        .drawWithContent {
                                            drawContent()
                                            val stroke = .5.dp.toPx()
                                            drawLine(
                                                colors.outlineVariant.copy(alpha = .24f),
                                                Offset(0f, size.height - stroke / 2),
                                                Offset(size.width, size.height - stroke / 2),
                                                stroke,
                                            )
                                        }
                                ) {
                                    Row(
                                        Modifier.fillMaxWidth()
                                            .statusBarsPadding()
                                            .height(
                                                if (firstPost != null)
                                                    ((14 * 1.25f + 12 * 1.25f) *
                                                            density.fontScale *
                                                            state.fontScale + 16)
                                                        .coerceIn(64f, 120f)
                                                        .dp
                                                else 56.dp
                                            ),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        if (!root)
                                            IconButton(
                                                onClick = ::back,
                                                modifier = Modifier.width(56.dp),
                                            ) {
                                                Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回")
                                            }
                                        if (firstPost != null)
                                            Row(
                                                Modifier.weight(1f)
                                                    .padding(start = 16.dp)
                                                    .clickable {
                                                        if (firstPost.profile.isNotBlank())
                                                            open(firstPost.profile)
                                                    },
                                                verticalAlignment = Alignment.CenterVertically,
                                            ) {
                                                Avatar(firstPost.avatar, 36)
                                                Spacer(Modifier.width(8.dp))
                                                Column(Modifier.weight(1f)) {
                                                    Text(
                                                        firstPost.author,
                                                        style = type.titleSmall,
                                                        maxLines = 1,
                                                        overflow =
                                                            androidx.compose.ui.text.style
                                                                .TextOverflow
                                                                .Ellipsis,
                                                    )
                                                    Spacer(Modifier.height(2.dp))
                                                    Row(
                                                        verticalAlignment =
                                                            Alignment.CenterVertically
                                                    ) {
                                                        if (firstPost.role.isNotEmpty()) {
                                                            ForumLabel(firstPost.role)
                                                            Spacer(Modifier.width(6.dp))
                                                        }
                                                        Text(
                                                            firstPost.meta.ifBlank { " " },
                                                            style = type.bodySmall,
                                                            maxLines = 1,
                                                            overflow =
                                                                androidx.compose.ui.text.style
                                                                    .TextOverflow
                                                                    .Ellipsis,
                                                        )
                                                    }
                                                }
                                            }
                                        else
                                            Text(
                                                title,
                                                Modifier.weight(1f).padding(start = 16.dp),
                                                fontSize = 18.sp,
                                                fontWeight =
                                                    FontWeight((700 + weight).coerceIn(100, 900)),
                                                maxLines = 1,
                                            )
                                        if (root) {
                                            if (
                                                state.tab == 0 &&
                                                    state.page?.online?.isNotEmpty() == true
                                            )
                                                Text(
                                                    "在线 ${state.page!!.online}",
                                                    style = type.labelMedium,
                                                    color = colors.primary,
                                                )
                                            if (
                                                state.tab == 0 ||
                                                    state.tab == 3 && state.authenticated
                                            )
                                                IconButton(
                                                    onClick = { state.replace(state.currentUrl) },
                                                    enabled = !state.busy,
                                                ) {
                                                    Icon(Icons.Outlined.Refresh, "刷新")
                                                }
                                            if (state.tab != 3)
                                                IconButton(onClick = { state.selectTab(3) }) {
                                                    Icon(Icons.Outlined.NotificationsNone, "消息")
                                                }
                                        } else if (state.screen == "cache") {
                                            IconButton(
                                                onClick = { cacheRevision++ },
                                                enabled = !cacheBusy,
                                            ) {
                                                Icon(Icons.Outlined.Refresh, "重新统计")
                                            }
                                        } else if (state.screen == "history") {
                                            IconButton(
                                                onClick = { clearHistory = true },
                                                enabled = state.history.isNotEmpty(),
                                            ) {
                                                Icon(Icons.Outlined.DeleteOutline, "清空历史")
                                            }
                                        } else if (state.screen == "home") {
                                            if (favoriteScreen)
                                                TextButton(
                                                    onClick = {
                                                        managingFavorites = !managingFavorites
                                                    },
                                                    enabled = !state.writing,
                                                ) {
                                                    Text(if (managingFavorites) "完成" else "管理收藏")
                                                }
                                            IconButton(
                                                onClick = { state.replace(state.currentUrl) },
                                                enabled = !state.busy,
                                            ) {
                                                Icon(Icons.Outlined.Refresh, "刷新")
                                            }
                                            if (
                                                firstPost != null ||
                                                    threadId(state.currentUrl) != null ||
                                                    boardId(state.currentUrl) != null ||
                                                    query(state.currentUrl, "mod") == "guide"
                                            ) {
                                                var menu by remember { mutableStateOf(false) }
                                                Box {
                                                    IconButton(onClick = { menu = true }) {
                                                        Icon(Icons.Outlined.MoreVert, "更多")
                                                    }
                                                    DropdownMenu(menu, { menu = false }) {
                                                        DropdownMenuItem(
                                                            text = { Text("复制链接") },
                                                            onClick = {
                                                                menu = false
                                                                (context.getSystemService(
                                                                        android.content.Context
                                                                            .CLIPBOARD_SERVICE
                                                                    )
                                                                        as
                                                                        android.content.ClipboardManager)
                                                                    .setPrimaryClip(
                                                                        android.content.ClipData
                                                                            .newPlainText(
                                                                                "链接",
                                                                                state.currentUrl,
                                                                            )
                                                                    )
                                                            },
                                                        )
                                                        (state.page?.resolvedThreadId
                                                                ?: threadId(state.currentUrl))
                                                            ?.let { tid ->
                                                                DropdownMenuItem(
                                                                    text = { Text("收藏到论坛") },
                                                                    onClick = {
                                                                        menu = false
                                                                        open(
                                                                            "$ORIGIN/home.php?mod=spacecp&ac=favorite&type=thread&id=$tid"
                                                                        )
                                                                    },
                                                                )
                                                            }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    PageNavigation(state)
                                    HorizontalDivider(
                                        thickness = .5.dp,
                                        color = colors.outlineVariant.copy(alpha = .24f),
                                    )
                                }
                            }
                        },
                        floatingActionButton = {
                            if (state.screen == "home" && !root)
                                boardId(state.currentUrl)?.let { fid ->
                                    ExtendedFloatingActionButton(
                                        onClick = {
                                            open(
                                                "$ORIGIN/forum.php?mod=post&action=newthread&fid=$fid"
                                            )
                                        },
                                        icon = { Icon(Icons.Outlined.Edit, null) },
                                        text = { Text("发帖") },
                                        shape =
                                            androidx.compose.foundation.shape.RoundedCornerShape(
                                                20.dp
                                            ),
                                        elevation =
                                            FloatingActionButtonDefaults.elevation(
                                                defaultElevation = 1.5.dp,
                                                pressedElevation = 3.dp,
                                            ),
                                    )
                                }
                        },
                        bottomBar = {
                            if (root) ForumNavigation(state)
                            else if (
                                state.screen == "home" && state.page?.posts?.isNotEmpty() == true
                            )
                                QuickReply(state, { dirty = it }, { browser = it })
                        },
                    ) { padding ->
                        val behind = true
                        CompositionLocalProvider(
                            LocalContentTop provides
                                if (behind) padding.calculateTopPadding() else 0.dp
                        ) {
                            RefreshBody(
                                state,
                                Modifier.padding(
                                        top = if (behind) 0.dp else padding.calculateTopPadding(),
                                        bottom =
                                            if (
                                                root &&
                                                    state.settings.bool("floatingNavigation") &&
                                                    density.fontScale * state.fontScale * 12 <= 16
                                            )
                                                0.dp
                                            else padding.calculateBottomPadding(),
                                    )
                                    .fillMaxSize()
                                    .captureBackdrop(backdrop),
                                contentAlignment = Alignment.TopCenter,
                            ) {
                                val content = Modifier.widthIn(max = 1000.dp).fillMaxSize()
                                savedRoutes.SaveableStateProvider(
                                    if (root) "root" else state.screen + ":" + state.currentUrl
                                ) {
                                    when (state.screen) {
                                        "settings" -> SettingsHub(state, content) { about = true }
                                        "user" ->
                                            UserHomePage(
                                                state,
                                                content,
                                                open,
                                                { browser = it },
                                                { dirty = it },
                                            )
                                        "appearance" -> AppearanceSettings(state, content)
                                        "account" ->
                                            AccountPage(
                                                state,
                                                content,
                                                open,
                                                { browser = it },
                                                { dirty = it },
                                            )
                                        "storage" -> StorageSettings(state, content)
                                        "cache" ->
                                            CacheSettings(state, content, cacheRevision) {
                                                cacheBusy = it
                                            }
                                        "backup" -> WebDavSettings(state, content)
                                        "login" -> LoginPage(state, content, open, { browser = it })
                                        "search" -> SearchPage(state, content)
                                        "history" -> HistoryPage(state, content, open)
                                        else ->
                                            when {
                                                root ->
                                                    RootPages(
                                                        state,
                                                        content,
                                                        scrolls,
                                                        open,
                                                        { browser = it },
                                                        { selection, author ->
                                                            media = selection
                                                            mediaAuthor = author
                                                        },
                                                        { url, author ->
                                                            video = url
                                                            mediaAuthor = author
                                                        },
                                                        { dirty = it },
                                                    )
                                                else ->
                                                    NativePage(
                                                        state,
                                                        content,
                                                        scrolls.getOrPut(state.currentUrl) {
                                                            LazyListState()
                                                        },
                                                        open,
                                                        { browser = it },
                                                        { urls, author ->
                                                            media = urls
                                                            mediaAuthor = author
                                                        },
                                                        { url, author ->
                                                            video = url
                                                            mediaAuthor = author
                                                        },
                                                        { dirty = it },
                                                        managingFavorites = managingFavorites,
                                                    )
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
                if (about) AboutDialog({ about = false }, open)
                state.pendingAction?.let { action ->
                    ConfirmDialog("确认操作？", "此操作将修改论坛数据。", { state.pendingAction = null }) {
                        state.pendingAction = null
                        action()
                    }
                }
                browser?.let {
                    BrowserDialog(
                        it,
                        onAuthenticated =
                            if (state.screen == "login") {
                                {
                                    browser = null
                                    state.loginComplete()
                                }
                            } else null,
                    ) {
                        browser = null
                        state.checkSession()
                    }
                }
                media?.let { GalleryDialog(it, state, mediaAuthor) { media = null } }
                video?.let { VideoDialog(it, state, mediaAuthor) { video = null } }
                if (clearHistory)
                    OriginalAlertDialog(
                        onDismissRequest = { clearHistory = false },
                        title = { Text("清空浏览历史？") },
                        text = { Text("此操作只清除本机记录。") },
                        dismissButton = {
                            TextButton(onClick = { clearHistory = false }) { Text("取消") }
                        },
                        confirmButton = {
                            Button(
                                onClick = {
                                    state.clearHistory()
                                    clearHistory = false
                                }
                            ) {
                                Text("清空")
                            }
                        },
                    )
                if (discard)
                    ConfirmDialog(
                        "放弃未保存的更改？",
                        "当前草稿尚未发送。",
                        {
                            discard = false
                            pendingNavigation = null
                        },
                    ) {
                        discard = false
                        dirty = false
                        val action = pendingNavigation
                        pendingNavigation = null
                        action?.invoke()
                    }
                if (state.accountMessage.isNotEmpty() && !state.utilityBusy)
                    OriginalAlertDialog(
                        onDismissRequest = { state.accountMessage = "" },
                        fast = true,
                        text = { Text(state.accountMessage) },
                        confirmButton = {
                            TextButton(onClick = { state.accountMessage = "" }) { Text("关闭") }
                        },
                    )
            }
        }
    }
}
