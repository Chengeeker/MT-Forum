package bbs.binmt.cc

import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun Section(
    modifier: Modifier = Modifier,
    radius: Int = 24,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    Surface(
        modifier.fillMaxWidth(),
        color =
            colors.settingsCardColor(LocalBackdrop.current?.background ?: colors.surface),
        shape = RoundedCornerShape(radius.dp),
    ) {
        Column(content = content)
    }
}

@Composable
fun Heading(text: String, top: Int = 28, plain: Boolean = false) {
    Text(
        text,
        Modifier.padding(start = 16.dp, top = top.dp, bottom = 12.dp),
        style =
            if (plain) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.titleSmall,
        color =
            if (plain) MaterialTheme.colorScheme.onSurface
            else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
fun PreferenceRow(
    title: String,
    subtitle: String = "",
    icon: ImageVector? = null,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    dimWhenDisabled: Boolean = true,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = if (subtitle.isBlank()) 56.dp else 72.dp)
            .then(
                if (onClick != null) Modifier.clickable(enabled = enabled, onClick = onClick)
                else Modifier
            )
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let {
            Icon(it, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(16.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                color =
                    if (enabled || !dimWhenDisabled) MaterialTheme.colorScheme.onSurface
                    else MaterialTheme.colorScheme.onSurface.copy(alpha = .38f),
            )
            if (subtitle.isNotBlank())
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
        }
        Spacer(Modifier.width(16.dp))
        if (trailing != null) trailing()
        else
            Icon(
                Icons.Rounded.ChevronRight,
                null,
                Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
    }
}

@Composable
fun SettingSwitch(
    state: ForumState,
    key: String,
    title: String,
    subtitle: String = "",
    icon: ImageVector? = null,
) {
    Box(Modifier.padding(vertical = 3.dp)) {
        PreferenceRow(
            title,
            subtitle,
            icon,
            onClick = { state.setSetting(key, !state.settings.bool(key)) },
            trailing = {
                Switch(
                    state.settings.bool(key),
                    { state.setSetting(key, it) },
                    Modifier.padding(end = 4.dp),
                )
            },
        )
    }
}

@Composable
fun SettingsHub(state: ForumState, modifier: Modifier, about: () -> Unit) {
    var logout by remember { mutableStateOf(false) }
    LazyColumn(
        modifier,
        contentPadding =
            PaddingValues(start = 16.dp, end = 16.dp, top = LocalContentTop.current, bottom = 32.dp),
    ) {
        item {
            Heading("偏好与功能")
            Section {
                PreferenceRow(
                    "个性化",
                    icon = Icons.Outlined.Palette,
                    onClick = { state.show("appearance") },
                )
                SettingSwitch(
                    state,
                    "autoSignIn",
                    "自动签到",
                    "启动时在后台检查并完成当日签到",
                    Icons.Outlined.EventAvailable,
                )
            }
        }
        item {
            Heading("存储与备份")
            Section {
                PreferenceRow(
                    "存储设置",
                    icon = Icons.Outlined.FolderOpen,
                    onClick = { state.show("storage") },
                )
                PreferenceRow(
                    "缓存管理",
                    icon = Icons.Outlined.CleaningServices,
                    onClick = { state.show("cache") },
                )
                PreferenceRow(
                    "WebDAV备份",
                    icon = Icons.Outlined.CloudSync,
                    onClick = { state.show("backup") },
                )
            }
        }
        item {
            Heading("账号设置")
            Section {
                if (!state.authenticated)
                    PreferenceRow(
                        "登录账号",
                        icon = Icons.Rounded.Login,
                        onClick = { state.show("login") },
                    )
                else {
                    PreferenceRow(
                        "检测账号凭据有效性",
                        "向论坛核验当前登录会话",
                        Icons.Outlined.VerifiedUser,
                        enabled = !state.utilityBusy,
                        onClick = state::checkAccount,
                        trailing =
                            if (state.utilityBusy) {
                                {
                                    CircularProgressIndicator(
                                        Modifier.size(18.dp),
                                        strokeWidth = 2.dp,
                                    )
                                }
                            } else null,
                    )
                    PreferenceRow(
                        "退出登录",
                        icon = Icons.Rounded.Logout,
                        enabled = !state.utilityBusy,
                        dimWhenDisabled = false,
                        onClick = {
                            state.haptic()
                            logout = true
                        },
                    )
                }
            }
        }
        item {
            Heading("关于与支持")
            Section {
                PreferenceRow(
                    "关于应用",
                    "版本 ${BuildConfig.VERSION_NAME}",
                    Icons.Outlined.Info,
                    onClick = {
                        state.haptic()
                        about()
                    },
                )
            }
        }
    }
    if (logout)
        ConfirmDialog("退出登录？", "退出后需要重新登录才能使用账号功能。", { logout = false }) {
            logout = false
            state.logout()
        }
}

@Composable
internal fun OriginalAlertDialog(
    onDismissRequest: () -> Unit,
    confirmButton: @Composable () -> Unit,
    dismissButton: (@Composable () -> Unit)? = null,
    title: (@Composable () -> Unit)? = null,
    text: (@Composable () -> Unit)? = null,
    fast: Boolean = false,
) {
    val heading =
        MaterialTheme.typography.titleLarge.copy(
            fontSize = 18.sp,
            lineHeight = androidx.compose.ui.unit.TextUnit.Unspecified,
        )
    AlertDialog(
        onDismissRequest = onDismissRequest,
        modifier =
            Modifier.padding(horizontal = 40.dp, vertical = 24.dp)
                .widthIn(max = 560.dp)
                .fillMaxWidth(),
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        confirmButton = {
            OriginalDialogWindow(fast)
            confirmButton()
        },
        dismissButton = dismissButton,
        title = title?.let { { ProvideTextStyle(heading, it) } },
        text =
            text?.let {
                {
                    ProvideTextStyle(
                        MaterialTheme.typography.bodyMedium.copy(
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        ),
                        it,
                    )
                }
            },
    )
}

@Composable
private fun OriginalDialogWindow(fast: Boolean) {
    val view = androidx.compose.ui.platform.LocalView.current
    SideEffect {
        (view.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window?.apply {
            setDimAmount(if (fast) 128f / 255f else .54f)
            setWindowAnimations(
                if (fast) R.style.OriginalDialogAnimation else R.style.StandardDialogAnimation
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OriginalBottomSheet(
    onDismissRequest: () -> Unit,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    contentWindowInsets: @Composable () -> WindowInsets = { BottomSheetDefaults.windowInsets },
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState,
        contentWindowInsets = contentWindowInsets,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor =
            colors.settingsCardColor(LocalBackdrop.current?.background ?: colors.surface),
        tonalElevation = 0.dp,
        scrimColor = Color.Black.copy(alpha = .54f),
        dragHandle = {
            Box(Modifier.fillMaxWidth().height(48.dp), contentAlignment = Alignment.Center) {
                Box(
                    Modifier.size(38.dp, 4.5.dp)
                        .background(
                            colors.onSurfaceVariant.copy(alpha = .4f),
                            RoundedCornerShape(50),
                        )
                )
            }
        },
        content = content,
    )
}

@Composable
fun ConfirmDialog(
    title: String,
    text: String,
    dismiss: () -> Unit,
    fast: Boolean = false,
    confirm: () -> Unit,
) {
    OriginalAlertDialog(
        onDismissRequest = dismiss,
        fast = fast,
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = { TextButton(onClick = confirm) { Text("确定") } },
        dismissButton = { TextButton(onClick = dismiss) { Text("取消") } },
    )
}

@Composable
fun ChoiceDialog(
    title: String,
    options: List<Pair<Any, String>>,
    selected: Any,
    dismiss: () -> Unit,
    summaries: List<String> = emptyList(),
    fast: Boolean = false,
    reviewStyle: Boolean = false,
    select: (Any) -> Unit,
) {
    OriginalAlertDialog(
        onDismissRequest = dismiss,
        fast = fast,
        title = { Text(title) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                options.forEachIndexed { index, (value, label) ->
                    val summary = summaries.getOrNull(index).orEmpty()
                    Row(
                        Modifier.fillMaxWidth()
                            .heightIn(
                                min =
                                    (if (summary.isEmpty()) 56 else 72).dp +
                                        if (reviewStyle) 4.dp else 6.dp
                            )
                            .clickable { select(value) }
                            .padding(
                                horizontal = 16.dp,
                                vertical = if (reviewStyle) 2.dp else 3.dp,
                            ),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected == value, null, Modifier.size(40.dp))
                        Spacer(Modifier.width(16.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                label,
                                style =
                                    MaterialTheme.typography.titleMedium.copy(
                                        fontSize = (if (reviewStyle) 16 else 15).sp,
                                        lineHeight = (if (reviewStyle) 21.6f else 20.25f).sp,
                                    ),
                            )
                            if (summary.isNotEmpty())
                                Text(
                                    summary,
                                    style =
                                        MaterialTheme.typography.bodyMedium.copy(
                                            fontSize = (if (reviewStyle) 14f else 12.5f).sp,
                                            lineHeight = (if (reviewStyle) 19.6f else 17.5f).sp,
                                        ),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = dismiss) { Text("取消") } },
    )
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun AppearanceSettings(state: ForumState, modifier: Modifier) {
    val settings = state.settings
    LazyColumn(
        modifier,
        contentPadding =
            PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = LocalContentTop.current + 12.dp,
                bottom = 24.dp,
            ),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item { AppearanceModes(settings.int("themeMode"), { state.setSetting("themeMode", it) },
            settings.bool("pureBlack"), { state.setSetting("pureBlack", it) }) }
        item { AppearancePalette(state.dynamic, { state.setSetting("dynamicColor", it) }, settings.int("color"), { state.setSetting("color", it) }) }
        item { FontWeightSetting(settings.bool("customFontWeight"), settings.int("fontWeightAdjustment"), "MT论坛",
            hapticsEnabled = settings.bool("haptics"), onReset = { state.persistSettings(mapOf("customFontWeight" to false)) },
            onCommit = { state.persistSettings(mapOf("fontWeightAdjustment" to it, "customFontWeight" to true)) }) }
        item { FontSizeSetting(state.fontScale) { state.persistSettings(mapOf("textScale" to it)) } }
        item {
            AppearanceSection("底部导航") {
                SettingSwitch(
                    state,
                    "floatingNavigation",
                    "使用悬浮底栏",
                    "居中显示悬浮式导航栏",
                    Icons.Rounded.Dock,
                )
            }
        }
        item {
            AppearanceSection("显示效果") {
                SettingSwitch(
                    state,
                    "liquidGlass",
                    "使用液态玻璃效果",
                    "控制液态玻璃控件；当前应用于悬浮底栏",
                    Icons.Rounded.BlurOn,
                )
                if(settings.bool("liquidGlass") && settings.bool("floatingNavigation")) NavigationGlassChoice(settings.bool("translucentNavigationGlass"), hapticsEnabled = settings.bool("haptics")) { state.persistSettings(mapOf("translucentNavigationGlass" to it)) }
            }
        }
        item { AppearanceSection("触感与震动") {
            AppearanceToggle("触感与震动反馈", "vibration", settings.bool("haptics")) { state.setSetting("haptics", it) }
        } }
    }
}

fun storagePath(type: Int, video: Boolean) =
    "${if(video) "Movies" else "Pictures"}/MT论坛/" +
        when (type) {
            1 -> "本人昵称/"
            2 -> "帖子作者昵称/"
            else -> ""
        }

@Composable
fun CacheSettings(
    state: ForumState,
    modifier: Modifier,
    refresh: Int,
    reportBusy: (Boolean) -> Unit,
) {
    val context = LocalContext.current
    val cache = remember { ImageCache(context) }
    val scope = rememberCoroutineScope()
    var bytes by remember { mutableLongStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var clearing by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf("") }
    var clear by remember { mutableStateOf(false) }
    var threshold by remember { mutableStateOf(false) }
    fun clearCache() {
        if (loading || clearing) return
        clearing = true
        loading = true
        scope.launch {
            try {
                cache.scan(true)
                bytes = cache.scan()
                failure = ""
            } catch (e: Exception) {
                failure = e.message.orEmpty()
            } finally {
                loading = false
                clearing = false
            }
        }
    }
    LaunchedEffect(refresh) {
        loading = true
        try {
            bytes = cache.scan()
            failure = ""
        } catch (e: Exception) {
            failure = e.message.orEmpty()
        } finally {
            loading = false
        }
    }
    SideEffect { reportBusy(loading || clearing) }
    fun thresholdLabel(value: Int): String =
        when {
            value == 0 -> "不限制（关闭自动清理）"
            value >= 1024 -> "${value / 1024} GB"
            else -> "$value MB"
        }
    LazyColumn(
        modifier,
        contentPadding =
            PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = LocalContentTop.current + 16.dp,
                bottom = 16.dp,
            ),
    ) {
        item {
            Section {
                Column(
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Surface(
                        Modifier.size(56.dp),
                        shape = RoundedCornerShape(28.dp),
                        color = MaterialTheme.colorScheme.primaryContainer,
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(Icons.Rounded.CleaningServices, null, Modifier.size(30.dp))
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    if (loading && !clearing) CircularProgressIndicator()
                    else
                        Text(
                            failure.ifEmpty { StorageRules.bytes(bytes) },
                            style = MaterialTheme.typography.headlineMedium,
                        )
                    Spacer(Modifier.height(8.dp))
                    Text("可管理的图片磁盘缓存")
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        item {
            Section {
                Button(
                    onClick = { clear = true },
                    enabled = !loading && failure.isEmpty() && bytes > 0,
                    modifier = Modifier.fillMaxWidth().padding(16.dp).heightIn(min = 48.dp),
                ) {
                    Icon(Icons.Rounded.DeleteSweep, null)
                    Spacer(Modifier.width(8.dp))
                    Text(if (clearing) "正在清理…" else "清理图片缓存")
                }
            }
        }
        item {
            Heading("自动清理规则", 24)
            Section {
                PreferenceRow(
                    "自动清理阈值",
                    thresholdLabel(state.settings.int("imageCacheThresholdMb")),
                    Icons.Outlined.AutoDelete,
                    enabled = !loading,
                    onClick = { threshold = true },
                )
            }
            Text(
                "启动应用和关闭图片浏览时检查阈值。仅清理图片磁盘缓存，保留最近一分钟写入的文件；不会删除相册文件、浏览历史或登录会话。",
                Modifier.padding(16.dp),
            )
        }
    }
    if (clear)
        ConfirmDialog("清理图片缓存？", "不会删除已保存到相册的图片和视频，也不会清除登录会话。", { clear = false }, fast = true) {
            clear = false
            clearCache()
        }
    if (threshold)
        ChoiceDialog(
            "自动清理阈值",
            SettingsStore.thresholds.map { it as Any to thresholdLabel(it) },
            state.settings.int("imageCacheThresholdMb"),
            { threshold = false },
            fast = true,
        ) { value ->
            threshold = false
            loading = true
            scope.launch {
                try {
                    state.settings.write("imageCacheThresholdMb", value)
                    cache.autoClear(value as Int)
                    bytes = cache.scan()
                } catch (e: Exception) {
                    failure = e.message.orEmpty()
                } finally {
                    loading = false
                }
            }
        }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AboutDialog(close: () -> Unit, open: (String) -> Unit) {
    val colors = MaterialTheme.colorScheme
    var licenses by remember { mutableStateOf(false) }
    androidx.compose.ui.window.Dialog(
        onDismissRequest = close,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        OriginalDialogWindow(true)
        Surface(
            modifier =
                Modifier.padding(horizontal = 40.dp, vertical = 24.dp)
                    .widthIn(max = 560.dp)
                    .fillMaxWidth(),
            shape = RoundedCornerShape(20.dp),
            color = colors.surfaceContainerHigh,
        ) {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Column(
                    Modifier.padding(start = 20.dp, top = 24.dp, end = 20.dp, bottom = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Image(
                        painterResource(R.drawable.site_icon),
                        "MT论坛应用图标",
                        Modifier.size(72.dp).clip(RoundedCornerShape(18.dp)),
                        contentScale = ContentScale.Crop,
                    )
                    Spacer(Modifier.height(14.dp))
                    FlowRow(
                        horizontalArrangement =
                            Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            "MT论坛",
                            fontSize = 21.sp,
                            fontWeight = FontWeight.Bold,
                            letterSpacing = .2.sp,
                        )
                        Surface(color = colors.primaryContainer, shape = RoundedCornerShape(8.dp)) {
                            Text(
                                "v${BuildConfig.VERSION_NAME}",
                                Modifier.padding(horizontal = 8.dp, vertical = 2.5.dp),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                color = colors.onPrimaryContainer,
                            )
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    Text("Material 3 论坛客户端", fontSize = 13.sp, color = colors.onSurfaceVariant)
                    Spacer(Modifier.height(30.dp))
                    listOf(
                            Icons.Outlined.Palette to "Material 3 动态配色与个性化主题",
                            Icons.Outlined.Forum to "论坛浏览、搜索、消息与后台签到",
                            Icons.Outlined.PhotoLibrary to "图片画廊、视频播放与 WebDAV 备份",
                        )
                        .forEachIndexed { index, (icon, text) ->
                            if (index > 0) Spacer(Modifier.height(8.dp))
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                                Icon(icon, null, Modifier.size(16.dp), tint = colors.primary)
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    text,
                                    Modifier.weight(1f),
                                    fontSize = 12.5.sp,
                                    lineHeight = 16.875.sp,
                                    color = colors.onSurfaceVariant,
                                )
                            }
                        }
                    Spacer(Modifier.height(26.dp))
                    Surface(
                        onClick = { open("https://github.com/Chengeeker/MT-Forum") },
                        shape = RoundedCornerShape(12.dp),
                        color = colors.surfaceContainerHighest.copy(alpha = .5f),
                        border = BorderStroke(1.dp, colors.outlineVariant.copy(alpha = .4f)),
                    ) {
                        Row(
                            Modifier.fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Rounded.Code,
                                null,
                                Modifier.size(20.dp),
                                tint = colors.primary,
                            )
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text("GitHub 开源地址", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                                Text(
                                    "github.com/Chengeeker/MT-Forum",
                                    fontSize = 11.sp,
                                    color = colors.onSurfaceVariant,
                                )
                            }
                            Icon(
                                Icons.Rounded.OpenInNew,
                                null,
                                Modifier.size(16.dp),
                                tint = colors.primary,
                            )
                        }
                    }
                }
                FlowRow(
                    Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                ) {
                    TextButton(onClick = { licenses = true }) { Text("开源许可") }
                    Button(
                        onClick = close,
                        shape = RoundedCornerShape(12.dp),
                        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 10.dp),
                    ) {
                        Text("我知道了")
                    }
                }
            }
        }
    }
    if (licenses) LicensePage { licenses = false }
}

@Composable
private fun LicensePage(close: () -> Unit) {
    val context = LocalContext.current
    val entries =
        listOf(
            "Review" to "review-license.txt",
            "Liquid Glass" to "liquid-glass-license.txt",
            "Liquid Glass 第三方许可" to "liquid-glass-third-party-notices.txt",
        )
    var selected by remember { mutableStateOf<Pair<String, String>?>(null) }
    val content =
        remember(selected) {
            selected?.let { entry ->
                context.assets.open(entry.second).bufferedReader().use { it.readText() }
            }
        }
    androidx.compose.ui.window.Dialog(
        onDismissRequest = { if (selected != null) selected = null else close() },
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.systemBarsPadding()) {
                Row(
                    Modifier.fillMaxWidth().height(56.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(
                        onClick = { if (selected != null) selected = null else close() },
                        modifier = Modifier.width(56.dp),
                    ) {
                        Icon(
                            androidx.compose.material.icons.Icons.AutoMirrored.Outlined.ArrowBack,
                            "返回",
                        )
                    }
                    Text(
                        selected?.first ?: "开源许可",
                        Modifier.padding(start = 16.dp),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {
                    if (content != null)
                        androidx.compose.foundation.text.selection.SelectionContainer {
                            Text(content)
                        }
                    else {
                        Text("MT论坛", style = MaterialTheme.typography.headlineSmall)
                        Text("1.6.16")
                        Text(
                            "第三方论坛客户端。论坛内容与图标归各自权利人所有。界面复用 Review 组件（MIT，© 2026 Chengeeker）。",
                            Modifier.padding(vertical = 16.dp),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        entries.forEach { entry ->
                            PreferenceRow(entry.first, onClick = { selected = entry })
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun StorageSettings(state: ForumState, modifier: Modifier) {
    var selection by remember { mutableStateOf<String?>(null) }
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(top = LocalContentTop.current)
            .padding(16.dp)
    ) {
        Section {
            PreferenceRow(
                "图片存储路径",
                storagePath(state.settings.int("imageSavePathType"), false),
                Icons.Outlined.Image,
                onClick = { selection = "imageSavePathType" },
            )
            PreferenceRow(
                "视频存储路径",
                storagePath(state.settings.int("videoSavePathType"), true),
                Icons.Outlined.VideoLibrary,
                onClick = { selection = "videoSavePathType" },
            )
        }
        Text("更改只影响之后保存的媒体，已保存文件不会移动。按本人昵称归类需要有效登录会话。", Modifier.padding(16.dp))
    }
    selection?.let { key ->
        ChoiceDialog(
            if (key.startsWith("image")) "图片存储路径" else "视频存储路径",
            listOf(0 to "默认路径", 1 to "按本人昵称归类", 2 to "按帖子作者昵称归类"),
            state.settings.int(key),
            { selection = null },
            summaries = (0..2).map { storagePath(it, key.startsWith("video")) },
            fast = true,
        ) {
            state.setSetting(key, it)
            selection = null
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WebDavField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    icon: ImageVector,
    hint: String?,
    enabled: Boolean,
    secret: Boolean,
) {
    val interaction = remember { MutableInteractionSource() }
    val transform =
        if (secret) PasswordVisualTransformation()
        else androidx.compose.ui.text.input.VisualTransformation.None
    val color = MaterialTheme.colorScheme
    BasicTextField(
        value,
        onChange,
        Modifier.fillMaxWidth().padding(top = 8.dp),
        enabled = enabled,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = color.onSurface),
        singleLine = true,
        visualTransformation = transform,
        interactionSource = interaction,
        cursorBrush = androidx.compose.ui.graphics.SolidColor(color.primary),
        decorationBox = { inner ->
            OutlinedTextFieldDefaults.DecorationBox(
                value = value,
                innerTextField = inner,
                enabled = enabled,
                singleLine = true,
                visualTransformation = transform,
                interactionSource = interaction,
                label = { Text(label) },
                placeholder = hint?.let { text -> { Text(text) } },
                leadingIcon = { Icon(icon, null) },
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
            )
        },
    )
}

@Composable
fun WebDavSettings(state: ForumState, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    val service = remember { BackupService(state.settings, state.client) }
    val fields = remember {
        mutableStateMapOf<String, String>().apply {
            listOf("webdav_url", "webdav_username", "webdav_password", "webdav_directory").forEach {
                put(it, state.settings.string(it))
            }
        }
    }
    var full by remember { mutableStateOf(false) }
    var operation by remember { mutableStateOf<String?>(null) }
    val busy = operation != null
    var message by remember { mutableStateOf(state.settings.secretReadError.orEmpty()) }
    var resultTitle by remember {mutableStateOf("连接测试结果")}
    val focus=androidx.compose.ui.platform.LocalFocusManager.current
    var incoming by remember { mutableStateOf<JSONObject?>(null) }
    var confirmFull by remember { mutableStateOf(false) }
    fun run(kind: String, action: suspend () -> String) {
        if (busy) return
        focus.clearFocus();message=""
        resultTitle=when(kind){"test"->"连接测试结果";"upload"->"备份结果";else->"恢复结果"}
        operation = kind
        scope.launch {
            try {
                BackupRules.server(fields.getValue("webdav_url"))
                BackupRules.directory(fields.getValue("webdav_directory"))
                require(fields.getValue("webdav_username").isNotBlank() && fields.getValue("webdav_password").isNotBlank()) { "请输入账号和授权密码" }
                if(kind!="download" && kind!="restore") state.settings.writeAll(fields.toMap())
                message = action()
            } catch(cancelled:kotlinx.coroutines.CancellationException){throw cancelled}
            catch (failure: Exception) {
                message = webDavError(failure)
            } finally {
                operation = null
            }
        }
    }
    LazyColumn(
        modifier.imePadding(),
        contentPadding =
            PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = LocalContentTop.current + 14.dp,
                bottom = 14.dp,
            ),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            val shape = RoundedCornerShape(16.dp)
            Row(
                Modifier.fillMaxWidth()
                    .background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = .4f), shape)
                    .border(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = .2f), shape)
                    .padding(14.dp)
            ) {
                Icon(
                    Icons.Rounded.CloudSync,
                    null,
                    Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        "备份内容",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "备份应用设置和浏览历史，不包含图片和视频缓存。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        item {
            Section {
                Column(Modifier.selectableGroup()) {
                    listOf(false to "全量安全备份", true to "全量备份").forEach { (value, title) ->
                        Row(
                            Modifier.fillMaxWidth()
                                .selectable(
                                    selected = full == value,
                                    enabled = !busy,
                                    role = Role.RadioButton,
                                    onClick = { full = value },
                                )
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(
                                Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Text(title, style = MaterialTheme.typography.titleMedium)
                                Text(
                                    if (value) "含会话及 WebDAV 密码" else "不含会话及 WebDAV 密码",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                if (value)
                                    Text(
                                        "含明文凭据，请妥善保管",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                            }
                            RadioButton(full == value, null, Modifier.size(24.dp), enabled = !busy)
                        }
                    }
                }
            }
        }
        item {
            Section {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("WebDAV 服务器配置", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    Spacer(Modifier.height(4.dp))
                    listOf(
                            Triple("webdav_url", "服务器 URL", Icons.Rounded.Link),
                            Triple("webdav_username", "账号 / 邮箱", Icons.Rounded.PersonOutline),
                            Triple("webdav_password", "应用密码 / Token", Icons.Rounded.Lock),
                            Triple("webdav_directory", "备份文件夹名称", Icons.Outlined.Folder),
                        )
                        .forEach { (key, label, icon) ->
                            WebDavField(
                                fields[key].orEmpty(),
                                { fields[key] = it },
                                label,
                                icon,
                                hint =
                                    when (key) {
                                        "webdav_url" -> "例如: https://dav.jianguoyun.com/dav/"
                                        "webdav_directory" -> "默认: MT论坛"
                                        else -> null
                                    },
                                enabled = !busy,
                                secret = key == "webdav_password",
                            )
                        }
                    OutlinedButton(
                        onClick = {
                            run("test") {
                                service.test()
                                "连接成功"
                            }
                        },
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        if (operation == "test")
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Rounded.WifiTethering, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(if (operation == "test") "正在测试连接..." else "测试服务器连接")
                    }
                }
            }
        }
        item {
            Section {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("云端备份与还原操作", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Button(
                            onClick = {
                                if (full) confirmFull = true
                                else
                                    run("upload") {
                                        service.upload(false)
                                        "备份成功"
                                    }
                            },
                            enabled = !busy,
                            modifier = Modifier.weight(1f),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 12.dp),
                        ) {
                            if (operation == "upload")
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            else Icon(Icons.Rounded.CloudUpload, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(if (operation == "upload") "正在上传..." else "立即备份到云端")
                        }
                        FilledTonalButton(
                            onClick = {
                                run("download") {
                                    incoming = service.download(fields.toMap())
                                    ""
                                }
                            },
                            enabled = !busy,
                            modifier = Modifier.weight(1f),
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 12.dp),
                        ) {
                            if (operation == "download" || operation == "restore")
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            else Icon(Icons.Rounded.CloudDownload, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(
                                if (operation == "download" || operation == "restore") "正在拉取..."
                                else "从云端恢复备份"
                            )
                        }
                    }
                }
            }
        }
    }
    if (confirmFull)
        ConfirmDialog("全量备份", "备份文件将包含论坛 Cookie 和 WebDAV 密码，确认上传？", { confirmFull = false }) {
            confirmFull = false
            run("upload") {
                service.upload(true)
                "备份成功"
            }
        }
    incoming?.let { data ->
        ConfirmDialog(
            "恢复备份",
            "将覆盖备份中包含的设置和浏览历史。${if(data.optString("backup_mode")=="full") "此全量备份将恢复 WebDAV 密码；论坛凭据验证通过后才替换当前会话。" else "不会替换论坛会话。"}",
            { incoming = null },
        ) {
            incoming = null
            run("restore") {
                val result=service.restore(data)
                state.restored()
                fields.keys.toList().forEach{fields[it]=state.settings.string(it)}
                result
            }
        }
    }
    if (!busy && message.isNotEmpty())
        OriginalAlertDialog(
            onDismissRequest = { message = "" },
            title = { Text(resultTitle) },
            text = { Text(message, Modifier.verticalScroll(rememberScrollState())) },
            confirmButton = { TextButton(onClick = { message = "" }) { Text("知道了") } },
        )
}
