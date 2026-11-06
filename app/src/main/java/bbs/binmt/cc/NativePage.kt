package bbs.binmt.cc

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

data class NativeTab(val label: String, val url: String, val selected: Boolean)

@Composable
private fun NativeCheckbox(
    label: String,
    selected: Boolean,
    enabled: Boolean,
    dense: Boolean,
    change: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = if (dense) 48.dp else 56.dp)
            .toggleable(
                value = selected,
                enabled = enabled,
                role = androidx.compose.ui.semantics.Role.Checkbox,
                onValueChange = change,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label,
            Modifier.weight(1f),
            style =
                MaterialTheme.typography.titleMedium.copy(
                    fontSize = (if (dense) 13 else 15).sp,
                    lineHeight = (if (dense) 17.55f else 20.25f).sp,
                ),
        )
        Spacer(Modifier.width(16.dp))
        Checkbox(selected, null, Modifier.size(40.dp), enabled = enabled)
    }
}

fun nativeTabs(root: Element?, base: String): List<NativeTab> =
    root
        ?.select("a[href],a[onclick]")
        ?.mapNotNull { a ->
            (signRankTarget(a, base) ?: safeUrl(a.attr("href"), base))?.takeIf(::sameOrigin)?.let {
                NativeTab(
                    a.text(),
                    it,
                    a.hasClass("a") || a.parent()?.hasClass("a") == true || it == base,
                )
            }
        }
        ?.distinctBy { it.url }
        .orEmpty()

@Composable
fun TabStrip(tabs: List<NativeTab>, open: (String) -> Unit) = TabStrip(tabs, false, open)

@Composable
fun TabStrip(tabs: List<NativeTab>, fill: Boolean, open: (String) -> Unit) {
    if (tabs.isEmpty()) return
    val height = with(LocalDensity.current) { (15.sp.toDp() * 1.5f + 16.dp).coerceAtLeast(48.dp) }
    Row(
        if (fill) Modifier.fillMaxWidth()
        else Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
    ) {
        tabs.forEach { tab ->
            Box(
                (if (fill) Modifier.weight(1f) else Modifier)
                    .height(height)
                    .clickable { open(tab.url) }
                    .padding(horizontal = if (fill) 4.dp else 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.width(IntrinsicSize.Max).fillMaxHeight()) {
                    Text(
                        tab.label,
                        modifier = Modifier.align(Alignment.Center),
                        style = MaterialTheme.typography.titleSmall,
                        fontSize = 15.sp,
                        lineHeight = androidx.compose.ui.unit.TextUnit.Unspecified,
                        maxLines = 1,
                        color =
                            if (tab.selected) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        fontWeight =
                            if (tab.selected) MaterialTheme.typography.titleSmall.fontWeight
                            else MaterialTheme.typography.bodyMedium.fontWeight,
                    )
                    if (tab.selected)
                        Box(
                            Modifier.align(Alignment.BottomCenter)
                                .fillMaxWidth()
                                .height(3.dp)
                                .background(
                                    MaterialTheme.colorScheme.primary,
                                    androidx.compose.foundation.shape.RoundedCornerShape(
                                        topStart = 3.dp,
                                        topEnd = 3.dp,
                                    ),
                                )
                        )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SegmentedLinks(tabs: List<NativeTab>, open: (String) -> Unit) {
    if (tabs.isEmpty()) return
    val measurer = androidx.compose.ui.text.rememberTextMeasurer()
    val density = LocalDensity.current
    val labelStyle = MaterialTheme.typography.labelLarge
    Row(Modifier.horizontalScroll(rememberScrollState())) {
        SingleChoiceSegmentedButtonRow {
            tabs.forEachIndexed { index, tab ->
                val minWidth =
                    with(density) {
                        measurer
                            .measure(tab.label, style = labelStyle, softWrap = false)
                            .size
                            .width
                            .toDp() + 24.dp
                    }
                SegmentedButton(
                    selected = tab.selected,
                    onClick = { open(tab.url) },
                    shape = SegmentedButtonDefaults.itemShape(index, tabs.size),
                    modifier = Modifier.widthIn(min = minWidth),
                    icon = {},
                    label = { Text(tab.label, style = labelStyle, maxLines = 1, softWrap = false) },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeForm(
    form: Form,
    state: ForumState,
    website: () -> Unit,
    dirty: (Boolean) -> Unit,
    completed: ((Page) -> Unit)? = null,
    draft: androidx.compose.runtime.snapshots.SnapshotStateList<String>? = null,
    compact: Boolean = false,
    collapse: (() -> Unit)? = null,
    focusRequest: Int = 1,
) {
    val editor = remember(form) { state.drafts.getOrPut(form) { ForumState.Draft(form) } }
    val values = draft ?: editor.values
    val post = query(form.action, "mod") == "post"
    val messageIndex = form.fields.indexOfFirst { it.name == "message" }
    val changed = values.indices.any { values[it] != editor.baseline[it] }
    LaunchedEffect(changed) {
        state.dirtyForms[form] = changed
        dirty(state.dirtyForms.values.any { it })
    }
    var confirm by remember { mutableStateOf<List<Pair<String, String>>?>(null) }
    var validation by remember { mutableStateOf("") }
    fun submit(button: Field?) {
        val missing =
            form.fields.indices.firstOrNull {
                form.fields[it].type != "hidden" && form.fields[it].required && values[it].isBlank()
            }
        if (missing != null) {
            validation = "请填写${form.fields[missing].label}"
            return
        }
        validation = ""
        val payload =
            form.fields
                .mapIndexedNotNull { i, field ->
                    when {
                        field.type in setOf("submit", "button", "reset", "file") -> null
                        field.type in setOf("checkbox", "radio") && values[i].isEmpty() -> null
                        else -> field.name to values[i]
                    }
                }
                .toMutableList()
        if (post) {
            payload.removeAll { it.first == "wysiwyg" }
            payload.add("wysiwyg" to "0")
        }
        if (button != null) payload.add(button.name to button.value)
        if (form.fields.any { it.name.startsWith("delete") || it.name == "favorite[]" })
            confirm = payload
        else state.submitFields(form, payload, completed)
    }
    val privacy = query(form.action, "ac") == "privacy"
    var moreOptions by remember(form) { mutableStateOf(false) }
    val groups: List<String?> =
        if (privacy) form.fields.filter { it.type != "hidden" }.map { it.group }.distinct()
        else listOf(null)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        groups.forEach { group ->
            Section(radius = if (compact) 0 else 16) {
                Column(
                    Modifier.padding(if (compact) 0.dp else 16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    if (!compact)
                        Text(
                            if (privacy) group?.ifBlank { null } ?: "筛选设置"
                            else if (post)
                                if (query(form.action, "action") == "reply") "回复内容" else "发布帖子"
                            else form.title,
                            style = MaterialTheme.typography.titleMedium,
                        )
                    if (!form.supported) {
                        Text(
                            "此表单包含尚未适配的附件、验证码或脚本控件，当前无法提交。",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    } else {
                        form.fields.forEachIndexed { i, field ->
                            if (
                                field.type !in
                                    setOf("hidden", "submit", "file", "button", "reset") &&
                                    !(compact &&
                                        (field.name == "subject" || field.type == "checkbox")) &&
                                    (group == null || field.group == group)
                            ) {
                                if (
                                    !privacy &&
                                        field.group.isNotBlank() &&
                                        form.fields.take(i).none {
                                            it.group == field.group && it.type != "hidden"
                                        }
                                ) {
                                    Text(field.group, style = MaterialTheme.typography.titleMedium)
                                    if (field.help.isNotBlank())
                                        Text(field.help, style = MaterialTheme.typography.bodySmall)
                                }
                                if (field.name == "message" && post)
                                    MessageEditor(
                                        values[i],
                                        { values[i] = it },
                                        state.busy,
                                        compact,
                                        if (compact) {
                                            {
                                                submit(
                                                    form.fields.firstOrNull { it.type == "submit" }
                                                )
                                            }
                                        } else null,
                                        collapse,
                                        maxLength = field.maxLength,
                                        focusRequest = focusRequest,
                                        label = field.label,
                                        readOnly = field.readonly,
                                    )
                                else
                                    when (field.type) {
                                        "checkbox" ->
                                            NativeCheckbox(
                                                field.label,
                                                values[i].isNotEmpty(),
                                                !state.busy,
                                                privacy,
                                            ) {
                                                values[i] = if (it) field.controlValue else ""
                                            }
                                        "radio" ->
                                            Row(
                                                Modifier.fillMaxWidth().clickable(
                                                    enabled = !state.busy
                                                ) {
                                                    form.fields.forEachIndexed { j, other ->
                                                        if (other.name == field.name)
                                                            values[j] =
                                                                if (i == j) field.controlValue
                                                                else ""
                                                    }
                                                },
                                                verticalAlignment = Alignment.CenterVertically,
                                            ) {
                                                RadioButton(values[i].isNotEmpty(), null)
                                                Text(field.label)
                                            }
                                        "select" -> {
                                            var expanded by remember { mutableStateOf(false) }
                                            ExposedDropdownMenuBox(
                                                expanded,
                                                {
                                                    if (!state.busy && !field.readonly)
                                                        expanded = it
                                                },
                                            ) {
                                                TextField(
                                                    value =
                                                        field.options
                                                            .firstOrNull { it.first == values[i] }
                                                            ?.second ?: "请选择",
                                                    onValueChange = {},
                                                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                                                    readOnly = true,
                                                    enabled = !state.busy && !field.readonly,
                                                    singleLine = true,
                                                    label = { Text(field.label) },
                                                    trailingIcon = {
                                                        ExposedDropdownMenuDefaults.TrailingIcon(
                                                            expanded
                                                        )
                                                    },
                                                    colors =
                                                        TextFieldDefaults.colors(
                                                            focusedContainerColor =
                                                                androidx.compose.ui.graphics.Color
                                                                    .Transparent,
                                                            unfocusedContainerColor =
                                                                androidx.compose.ui.graphics.Color
                                                                    .Transparent,
                                                            disabledContainerColor =
                                                                androidx.compose.ui.graphics.Color
                                                                    .Transparent,
                                                        ),
                                                )
                                                ExposedDropdownMenu(
                                                    expanded,
                                                    { expanded = false },
                                                ) {
                                                    field.options.forEach { (value, label) ->
                                                        DropdownMenuItem(
                                                            text = { Text(label) },
                                                            onClick = {
                                                                values[i] = value
                                                                expanded = false
                                                            },
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                        else ->
                                            OutlinedTextField(
                                                values[i],
                                                {
                                                    if (it.length <= field.maxLength) values[i] = it
                                                },
                                                Modifier.fillMaxWidth(),
                                                label = { Text(field.label) },
                                                enabled = !state.busy,
                                                readOnly = field.readonly,
                                                minLines =
                                                    if (field.type == "textarea")
                                                        if (field.name == "message") 5 else 3
                                                    else 1,
                                                singleLine = field.type != "textarea",
                                                visualTransformation =
                                                    if (field.type == "password")
                                                        PasswordVisualTransformation()
                                                    else VisualTransformation.None,
                                            )
                                    }
                            }
                        }
                        if (compact && form.fields.any { it.type == "checkbox" }) {
                            Row(
                                Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable {
                                    moreOptions = !moreOptions
                                },
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    "更多选项",
                                    Modifier.weight(1f),
                                    style =
                                        MaterialTheme.typography.titleMedium.copy(
                                            fontSize = 15.sp,
                                            lineHeight = 20.25.sp,
                                        ),
                                )
                                Icon(
                                    if (moreOptions) Icons.Outlined.ExpandLess
                                    else Icons.Outlined.ExpandMore,
                                    if (moreOptions) "收起更多选项" else "展开更多选项",
                                )
                            }
                            if (moreOptions)
                                form.fields.forEachIndexed { i, field ->
                                    if (field.type == "checkbox")
                                        NativeCheckbox(
                                            field.label,
                                            values[i].isNotEmpty(),
                                            !state.busy,
                                            false,
                                        ) {
                                            values[i] = if (it) field.controlValue else ""
                                        }
                                }
                        }
                        if (!compact && (group == null || group == groups.last()))
                            form.links.forEach { link ->
                                TextButton(
                                    onClick = {
                                        if (sameOrigin(link.url)) state.load(link.url)
                                        else state.externalLink = link.url
                                    }
                                ) {
                                    Text(link.title)
                                }
                            }
                        if (validation.isNotEmpty())
                            Text(validation, color = MaterialTheme.colorScheme.error)
                        val buttons =
                            form.fields.filter {
                                it.type == "submit" && (group == null || it.group == group)
                            }
                        if (!compact && buttons.isEmpty())
                            Button(
                                onClick = { submit(null) },
                                enabled = !state.busy,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(if (post) "发送回复" else "保存")
                            }
                        else if (!compact)
                            buttons.forEach { button ->
                                Button(
                                    onClick = { submit(button) },
                                    enabled = !state.busy,
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    Text(
                                        button.label.takeIf { it != button.name }
                                            ?: if (post)
                                                if (query(form.action, "action") == "reply") "发送回复"
                                                else "发表帖子"
                                            else "提交"
                                    )
                                }
                            }
                    }
                }
            }
        }
    }
    confirm?.let { payload ->
        ConfirmDialog("确认操作", "该操作将提交选中的项目，请确认后继续。", { confirm = null }) {
            confirm = null
            state.submitFields(form, payload, completed)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun NativePage(
    state: ForumState,
    modifier: Modifier,
    scroll: LazyListState,
    open: (String) -> Unit,
    website: (String) -> Unit,
    images: (GallerySelection, String) -> Unit,
    video: (String, String) -> Unit,
    dirty: (Boolean) -> Unit,
    page: Page? = state.page,
    url: String = state.currentUrl,
    managingFavorites: Boolean = false,
) {
    if (isMyPosts(url)) {
        MyPostsPage(state, modifier, scroll, open)
        return
    }
    if (query(url, "do") == "favorite") {
        FavoritesPage(state, modifier, scroll, open, managingFavorites)
        return
    }
    if (query(url, "mod") == "ranklist") {
        RankingPage(state, modifier, scroll, open)
        return
    }
    val document = remember(page?.source) { Jsoup.parse(page?.source.orEmpty(), url) }
    var managing by remember(page?.url) { mutableStateOf(false) }
    val messages = document.select(".nts dl,.pml dl")
    val messageRoot = state.tab == 3 && state.isRoot
    val thread = page?.posts?.isNotEmpty() == true
    val favorites = document.select("#favorite_ul > li")
    val ranking = query(url, "mod") == "ranklist"
    val isSign = document.selectFirst(".lineB .paiming") != null
    val profile =
        remember(page?.source) {
            if (document.selectFirst("#uhd") != null)
                runCatching { AccountService.parse(page!!.source) }.getOrNull()
            else null
        }
    val board = boardId(url)
    val targetPost =
        query(url, "pid")
            ?: runCatching {
                    java.net.URI(url).fragment?.removePrefix("pid")?.removePrefix("post_")
                }
                .getOrNull()
    LaunchedEffect(page?.url, targetPost) {
        if (targetPost != null) {
            val index = page?.posts?.indexOfFirst { it.id == targetPost } ?: -1
            if (index >= 0) {
                withFrameNanos {}
                scroll.scrollToItem(
                    (1 +
                            index +
                            (if (page!!.notice.isNotEmpty()) 1 else 0) +
                            (if (state.busy) 1 else 0) +
                            (if (state.error.isNotEmpty()) 1 else 0))
                        .coerceAtMost(scroll.layoutInfo.totalItemsCount - 1)
                        .coerceAtLeast(0)
                )
            }
        }
    }
    LaunchedEffect(scroll, url) {
        snapshotFlow {
                Triple(
                    scroll.layoutInfo.visibleItemsInfo.lastOrNull()?.index?.let {
                        it >= scroll.layoutInfo.totalItemsCount - 3
                    } == true,
                    state.busy,
                    state.page?.next,
                )
            }
            .collect { (near, loading, next) ->
                if (
                    near &&
                        !loading &&
                        state.error.isEmpty() &&
                        next != null &&
                        (board != null ||
                            state.page?.posts?.isNotEmpty() == true ||
                            query(url, "mod") == "guide")
                )
                    state.load(next, push = false, append = true)
            }
    }
    LazyColumn(
        modifier,
        state = scroll,
        contentPadding =
            PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top =
                    LocalContentTop.current +
                        when {
                            thread -> 4.dp
                            board != null -> 12.dp
                            else -> 16.dp
                        },
                bottom = if (thread) 24.dp else if (board != null) 88.dp else 16.dp,
            ),
        verticalArrangement = Arrangement.spacedBy(if (thread || board != null) 0.dp else 12.dp),
    ) {
        if (state.busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        if (state.error.isNotEmpty())
            item { FailurePanel(state.error) { state.load(url, push = false) } }
        if (page != null) {
            if (board != null) {
                item {
                    val subtitle =
                        listOfNotNull(
                                document.selectFirst(".comiis_infotit h1 span")?.text()?.takeIf {
                                    it.isNotBlank()
                                },
                                document
                                    .selectFirst(".comiis_infobox > div:not(.comiis_infotit)")
                                    ?.text()
                                    ?.takeIf { it.isNotBlank() },
                            )
                            .joinToString("\n")
                    Section(Modifier.padding(bottom = 8.dp), radius = 12) {
                        Row(
                            Modifier.fillMaxWidth()
                                .heightIn(min = if (subtitle.isEmpty()) 80.dp else 96.dp)
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            BoardAvatar(
                                safeUrl(
                                        document
                                            .selectFirst(".comiis_listinfo img")
                                            ?.attr("src")
                                            .orEmpty(),
                                        page.url,
                                    )
                                    .orEmpty()
                            )
                            Spacer(Modifier.width(16.dp))
                            Column(Modifier.weight(1f)) {
                                Text(
                                    document.selectFirst(".comiis_infotit h1 a")?.text()
                                        ?: page.title,
                                    style = MaterialTheme.typography.titleMedium,
                                )
                                if (subtitle.isNotEmpty())
                                    Text(subtitle, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
                item {
                    Row(
                        Modifier.padding(start = 3.dp, end = 3.dp, bottom = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        listOf(
                                "全部" to "",
                                "最新" to "orderby=dateline",
                                "热门" to "filter=heat&orderby=heats",
                                "精华" to "filter=digest&digest=1",
                            )
                            .forEach { (label, filter) ->
                                val selected =
                                    if (filter.isEmpty())
                                        !page.url.contains("filter=") &&
                                            !page.url.contains("orderby=")
                                    else page.url.contains(filter)
                                val action = {
                                    state.replace(
                                        "$ORIGIN/forum.php?mod=forumdisplay&fid=$board" +
                                            if (filter.isEmpty()) "" else "&$filter"
                                    )
                                }
                                if (selected)
                                    Button(
                                        action,
                                        Modifier.weight(1f).heightIn(min = 48.dp),
                                        enabled = !state.busy,
                                        contentPadding = PaddingValues(horizontal = 8.dp),
                                    ) {
                                        Text(label, style = MaterialTheme.typography.bodyMedium)
                                    }
                                else
                                    FilledTonalButton(
                                        action,
                                        Modifier.weight(1f).heightIn(min = 48.dp),
                                        enabled = !state.busy,
                                        contentPadding = PaddingValues(horizontal = 8.dp),
                                    ) {
                                        Text(label, style = MaterialTheme.typography.bodyMedium)
                                    }
                            }
                    }
                }
                if (page.links.any { it.pinned })
                    item {
                        Section(Modifier.padding(bottom = 8.dp), radius = 12) {
                            Text(
                                "置顶帖",
                                Modifier.padding(start = 12.dp, top = 12.dp),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            page.links
                                .filter { it.pinned }
                                .forEach { link ->
                                    Row(
                                        Modifier.fillMaxWidth()
                                            .heightIn(min = 48.dp)
                                            .clickable { open(link.url) }
                                            .padding(horizontal = 10.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        ForumLabel("置顶")
                                        Spacer(Modifier.width(8.dp))
                                        Text(
                                            link.title,
                                            maxLines = 1,
                                            overflow =
                                                androidx.compose.ui.text.style.TextOverflow
                                                    .Ellipsis,
                                            style = MaterialTheme.typography.bodyMedium,
                                        )
                                    }
                                }
                        }
                    }
            }
            if (page.posts.isNotEmpty())
                item {
                    Text(
                        page.title,
                        Modifier.padding(vertical = 16.dp),
                        style = MaterialTheme.typography.headlineSmall,
                    )
                }
            if (messageRoot) {
                val actions = document.select("#ct .mn .tb > .o a[href],#ct .mn .tb > .y a[href]")
                if (actions.isNotEmpty())
                    item {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            actions.forEach { action ->
                                val target =
                                    safeUrl(action.attr("href"), page.url)?.takeIf(::sameOrigin)
                                        ?: return@forEach
                                if (action.closest(".o") != null)
                                    Button(onClick = { open(target) }) {
                                        Icon(Icons.Outlined.Edit, null, Modifier.size(18.dp))
                                        Spacer(Modifier.width(8.dp))
                                        Text(action.text())
                                    }
                                else TextButton(onClick = { open(target) }) { Text(action.text()) }
                            }
                        }
                    }
            }
            if (page.notice.isNotEmpty())
                item {
                    if (document.selectFirst(".emp") != null)
                        Section {
                            Column(
                                Modifier.fillMaxWidth().padding(24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Icon(
                                    Icons.Outlined.Inbox,
                                    null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Spacer(Modifier.height(12.dp))
                                Text(
                                    page.notice,
                                    style = MaterialTheme.typography.bodyMedium,
                                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                                )
                            }
                        }
                    else Text(page.notice)
                }
            if (profile != null)
                item {
                    Section {
                        Column(Modifier.padding(16.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Avatar(profile.avatar, 48)
                                Spacer(Modifier.width(12.dp))
                                Column {
                                    Text(profile.name, style = MaterialTheme.typography.titleLarge)
                                    Text(
                                        "UID: ${profile.uid}",
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                            }
                            val actions = nativeTabs(document.selectFirst("#uhd .mn ul"), page.url)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                actions.forEach {
                                    OutlinedButton(onClick = { open(it.url) }) { Text(it.label) }
                                }
                            }
                        }
                    }
                }
            val profileTabs = nativeTabs(document.selectFirst("#uhd .tb"), page.url)
            if (profileTabs.isNotEmpty()) item { SegmentedLinks(profileTabs, open) }
            val navRoots =
                if (ranking) document.select(".ct2_a .tbn ul,.ct2_a .mn .tb,.ct2_a .mn .tbmu")
                else document.select("#ct .mn > .tb,#ct .mn > .tbmu,.paihang")
            navRoots
                .filter {
                    !isSign && !messageRoot && !(query(url, "ac") == "privacy" && it.hasClass("tb"))
                }
                .forEach { root ->
                    item {
                        SegmentedLinks(nativeTabs(root, page.url)) { target ->
                            state.replace(target)
                        }
                    }
                }
            when {
                isSign -> {
                    val data =
                        state.signInfo
                            ?: runCatching { AccountService.parseSignIn(page.source) }.getOrNull()
                    if (data != null) item { SignInView(data, state, open) }
                    item {
                        Text(
                            "签到排行",
                            Modifier.padding(top = 8.dp),
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }
                    item {
                        SegmentedLinks(nativeTabs(document.selectFirst(".paihang"), page.url)) {
                            state.replace(it)
                        }
                    }
                    val rows = document.select("#ranklist table tr")
                    val headers = rows.firstOrNull()?.children()?.map { it.text() }.orEmpty()
                    rows
                        .drop(1)
                        .filter { it.childrenSize() == headers.size }
                        .forEach { row ->
                            item {
                                Section(radius = 12) {
                                    Column(Modifier.padding(12.dp)) {
                                        row.children().forEachIndexed { index, cell ->
                                            if (index == 0) {
                                                val target =
                                                    safeUrl(
                                                        cell
                                                            .selectFirst("a[href]")
                                                            ?.attr("href")
                                                            .orEmpty(),
                                                        page.url,
                                                    )
                                                if (target != null)
                                                    TextButton(onClick = { open(target) }) {
                                                        Text(
                                                            cell.text(),
                                                            style =
                                                                MaterialTheme.typography.titleSmall,
                                                        )
                                                    }
                                                else
                                                    Text(
                                                        cell.text(),
                                                        Modifier.padding(vertical = 3.dp),
                                                        style = MaterialTheme.typography.titleSmall,
                                                    )
                                            } else
                                                Text(
                                                    "${headers[index]}： ${cell.text()}",
                                                    Modifier.padding(vertical = 3.dp),
                                                    style = MaterialTheme.typography.bodySmall,
                                                )
                                        }
                                    }
                                }
                            }
                        }
                }
                messages.isNotEmpty() ->
                    items(messages) { row ->
                        Section {
                            Column(Modifier.padding(16.dp)) {
                                val clone = row.clone()
                                val actions =
                                    clone
                                        .select("a[href]")
                                        .filter { it.text() in setOf("屏蔽", "查看") }
                                        .mapNotNull { a ->
                                            safeUrl(a.attr("href"), page.url)?.let {
                                                a.text() to it
                                            }
                                        }
                                clone
                                    .select("a[href]")
                                    .filter { it.text() in setOf("屏蔽", "查看") }
                                    .forEach { it.remove() }
                                RichText(
                                    clone.html(),
                                    open,
                                    MaterialTheme.typography.bodyMedium.copy(lineHeight = 20.3.sp),
                                )
                                Row {
                                    actions.forEach { (label, url) ->
                                        TextButton(onClick = { open(url) }) { Text(label) }
                                    }
                                }
                            }
                        }
                    }
                favorites.isNotEmpty() -> {
                    item {
                        TextButton(onClick = { managing = !managing }) {
                            Text(if (managing) "完成管理" else "管理收藏")
                        }
                    }
                    if (!managing)
                        items(favorites) { row ->
                            val a =
                                row.select("a[href]").firstOrNull {
                                    val url = safeUrl(it.attr("href"), page.url).orEmpty()
                                    threadId(url) != null || url.contains("forum-")
                                }
                            if (a != null)
                                Section {
                                    Box(Modifier.padding(12.dp)) {
                                        ThreadRow(
                                            Link(a.text(), safeUrl(a.attr("href"), page.url)!!),
                                            open,
                                        )
                                    }
                                }
                        }
                }
                page.posts.isNotEmpty() -> {
                    page.posts.forEachIndexed { index, post ->
                        item(key = "post:${post.id}") {
                            Section(Modifier.padding(bottom = 12.dp), radius = 24) {
                                Column(Modifier.padding(16.dp)) {
                                    if (index > 0) {
                                        Row(
                                            Modifier.fillMaxWidth().clickable {
                                                if (post.profile.isNotEmpty()) open(post.profile)
                                            },
                                            verticalAlignment = Alignment.CenterVertically,
                                        ) {
                                            Avatar(post.avatar, 36)
                                            Spacer(Modifier.width(12.dp))
                                            Column(Modifier.weight(1f)) {
                                                Text(
                                                    post.author,
                                                    style = MaterialTheme.typography.titleSmall,
                                                )
                                                if (post.role.isNotEmpty()) ForumLabel(post.role)
                                                if (post.meta.isNotEmpty())
                                                    Text(
                                                        post.meta,
                                                        style = MaterialTheme.typography.bodySmall,
                                                    )
                                            }
                                            Text(
                                                post.floor.ifBlank { "${index+1}楼" },
                                                style = MaterialTheme.typography.labelMedium,
                                            )
                                        }
                                        Spacer(Modifier.height(16.dp))
                                    }
                                    ArticleBody(
                                        post.html,
                                        { target ->
                                            when {
                                                isThreadReplyLink(target, page.resolvedThreadId) ->
                                                    state.reply()
                                                sameOrigin(target) &&
                                                    query(target, "mod") == "logging" &&
                                                    query(target, "action") == "login" ->
                                                    state.loginForThread()
                                                else -> open(target)
                                            }
                                        },
                                        { anchor ->
                                            val i = post.images.indexOf(anchor.url).coerceAtLeast(0)
                                            images(
                                                GallerySelection(post.images, i, anchor.bounds),
                                                post.author,
                                            )
                                        },
                                        { url -> video(url, post.author) },
                                    )
                                    post.videos
                                        .filter { !post.html.contains(it) }
                                        .forEach { url ->
                                            ArticleVideoCard { video(url, post.author) }
                                        }
                                    TextButton(
                                        modifier = Modifier.align(Alignment.End),
                                        onClick = { state.reply(post.id) },
                                    ) {
                                        Icon(Icons.Outlined.Reply, null, Modifier.size(18.dp))
                                        Spacer(Modifier.width(8.dp))
                                        Text("回复")
                                    }
                                }
                            }
                        }
                    }
                }
                else -> {
                    if (page.content.isNotEmpty())
                        item {
                            ArticleBody(
                                page.content,
                                open,
                                textStyle =
                                    MaterialTheme.typography.bodyMedium.copy(lineHeight = 20.3.sp),
                            )
                        }
                    items(page.links.filter { board == null || !it.pinned }, key = { it.url }) {
                        ThreadRow(it, open)
                    }
                    if (page.content.isEmpty() && page.links.isEmpty() && page.forms.isEmpty())
                        items(page.details) { Section { Text(it, Modifier.padding(16.dp)) } }
                }
            }
            if (page.posts.isEmpty() && (favorites.isEmpty() || managing))
                items(page.forms) { form -> NativeForm(form, state, { website(page.url) }, dirty) }
            if (profile != null && query(page.url, "do") == "profile")
                item {
                    Section {
                        profile.fields.forEach { (label, value) ->
                            Column(
                                Modifier.fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 10.dp)
                            ) {
                                Text(label, style = MaterialTheme.typography.titleMedium)
                                Text(value, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            page.next?.let { next ->
                item {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        TextButton(
                            onClick = {
                                if (
                                    board != null ||
                                        page.posts.isNotEmpty() ||
                                        query(url, "mod") == "guide"
                                )
                                    state.load(next, push = false, append = true)
                                else state.replace(next)
                            },
                            enabled = !state.busy,
                        ) {
                            Text("加载下一页")
                        }
                    }
                }
            }
            if (page.next == null && (thread || board != null))
                item {
                    Box(
                        Modifier.fillMaxWidth().padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            if (thread || page.links.isNotEmpty()) "已经到底了" else "没有可显示的内容",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
        }
    }
}

@Composable
private fun BoardAvatar(url: String) {
    Surface(
        Modifier.size(48.dp),
        shape = androidx.compose.foundation.shape.CircleShape,
        color = MaterialTheme.colorScheme.primaryContainer,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.Forum, null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
            if (url.isNotEmpty())
                coil.compose.AsyncImage(
                    url,
                    null,
                    Modifier.fillMaxSize(),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                )
        }
    }
}

private fun dirtyForm(page: Page) = page.forms.isNotEmpty()
