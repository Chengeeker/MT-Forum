package bbs.binmt.cc

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

fun insertMarkup(value: TextFieldValue, start: String, end: String = ""): TextFieldValue {
    val from = value.selection.min.coerceIn(0, value.text.length)
    val to = value.selection.max.coerceIn(from, value.text.length)
    val selected = if (end.isEmpty()) "" else value.text.substring(from, to)
    return TextFieldValue(
        value.text.replaceRange(from, to, start + selected + end),
        TextRange(from + start.length + selected.length),
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MessageEditor(
    value: String,
    changed: (String) -> Unit,
    busy: Boolean,
    compact: Boolean,
    send: (() -> Unit)? = null,
    collapse: (() -> Unit)? = null,
    maxLength: Int = Int.MAX_VALUE,
    focusRequest: Int = 1,
    label: String = "内容",
    readOnly: Boolean = false,
) {
    val initial = remember { Regex("(?s)^\\s*(\\[quote\\].*?\\[/quote\\])\\s*").find(value) }
    var quote by remember { mutableStateOf(initial?.groupValues?.get(1).orEmpty()) }
    var text by remember {
        mutableStateOf(
            TextFieldValue(if (initial != null) value.substring(initial.range.last + 1) else value)
        )
    }
    val focus = remember { FocusRequester() }
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    LaunchedEffect(compact, focusRequest) {
        if (compact && focusRequest > 0) {
            focus.requestFocus()
            keyboard?.show()
        }
    }
    var link by remember { mutableStateOf<Boolean?>(null) }
    var emoji by remember { mutableStateOf(false) }
    fun update(next: TextFieldValue) {
        val content = if (quote.isEmpty()) next.text else "$quote\n\n${next.text}"
        if (content.length > maxLength) return
        text = next
        changed(content)
    }
    fun insert(start: String, end: String = "") {
        update(insertMarkup(text, start, end))
        focus.requestFocus()
    }
    Column(verticalArrangement = Arrangement.spacedBy(if (compact) 0.dp else 8.dp)) {
        if (compact)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f).horizontalScroll(rememberScrollState())) {
                    val actions =
                        listOf(
                            Triple("表情", Icons.Outlined.SentimentSatisfied, { emoji = true }),
                            Triple("加粗", Icons.Outlined.FormatBold, { insert("[b]", "[/b]") }),
                            Triple("链接", Icons.Outlined.Link, { link = false }),
                            Triple(
                                "引用",
                                Icons.Outlined.FormatQuote,
                                { insert("[quote]", "[/quote]") },
                            ),
                            Triple("代码", Icons.Outlined.Code, { insert("[code]", "[/code]") }),
                            Triple("网络图片", Icons.Outlined.Image, { link = true }),
                        )
                    actions.forEach { (label, icon, action) ->
                        IconButton(onClick = action, enabled = !busy && !readOnly) {
                            Icon(icon, label)
                        }
                    }
                }
                collapse?.let {
                    IconButton(onClick = it, enabled = !busy) {
                        Icon(Icons.Outlined.KeyboardArrowDown, "收起编辑栏")
                    }
                }
            }
        if (quote.isNotEmpty()) {
            val outline = MaterialTheme.colorScheme.outline
            Column(
                if (compact) Modifier
                else
                    Modifier.padding(bottom = 8.dp)
                        .drawBehind {
                            drawLine(
                                outline,
                                Offset.Zero,
                                Offset(0f, size.height),
                                strokeWidth = 3.dp.toPx(),
                            )
                        }
                        .padding(start = 12.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        if (compact) quote.replace(Regex("\\[[^\\]]+\\]"), "").trim() else "引用内容",
                        Modifier.weight(1f),
                        maxLines = if (compact) 2 else 1,
                        overflow = TextOverflow.Ellipsis,
                        style =
                            if (compact) MaterialTheme.typography.bodySmall
                            else MaterialTheme.typography.bodyMedium,
                    )
                    IconButton(
                        onClick = {
                            quote = ""
                            update(text)
                        },
                        enabled = !busy && !readOnly,
                    ) {
                        Icon(Icons.Outlined.Close, "移除引用", Modifier.size(18.dp))
                    }
                }
                if (!compact)
                    Text(
                        quote.replace(Regex("\\[[^\\]]+\\]"), "").trim(),
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.bodySmall,
                    )
            }
        }
        Row(verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                text,
                { update(it) },
                Modifier.weight(1f).focusRequester(focus),
                enabled = !busy,
                readOnly = readOnly,
                minLines = if (compact) 1 else 5,
                maxLines = if (compact) 5 else Int.MAX_VALUE,
                placeholder =
                    if (compact) {
                        { Text("说点什么吧…") }
                    } else null,
                label =
                    if (compact) null
                    else {
                        { Text(label) }
                    },
                shape = RoundedCornerShape(if (compact) 24.dp else 4.dp),
            )
            if (send != null) {
                Spacer(Modifier.width(8.dp))
                FilledIconButton(onClick = send, enabled = !busy) {
                    if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else Icon(Icons.Outlined.Send, "发送回复")
                }
            }
        }
    }
    if (emoji)
        OriginalBottomSheet(onDismissRequest = { emoji = false }) {
            FlowRow(Modifier.navigationBarsPadding().padding(16.dp)) {
                listOf("😀", "😊", "😂", "🤔", "👍", "👏", "🙏", "🎉", "❤️", "🔥", "🚀", "👀")
                    .forEach { item ->
                        TextButton(
                            onClick = {
                                emoji = false
                                insert(item)
                            }
                        ) {
                            Text(item, fontSize = 24.sp)
                        }
                    }
            }
        }
    link?.let { image ->
        var address by remember { mutableStateOf("") }
        var label by remember { mutableStateOf("") }
        var error by remember { mutableStateOf(false) }
        OriginalAlertDialog(
            onDismissRequest = { link = null },
            title = { Text(if (image) "网络图片" else "插入链接") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        address,
                        {
                            address = it
                            error = false
                        },
                        label = { Text("HTTPS 地址") },
                        isError = error,
                        singleLine = true,
                    )
                    if (!image)
                        OutlinedTextField(label, { label = it }, label = { Text("显示文字（可选）") })
                    if (error) Text("请输入有效的 HTTPS 地址", color = MaterialTheme.colorScheme.error)
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val url = safeUrl(address, address)
                        if (url == null) error = true
                        else {
                            link = null
                            insert(
                                if (image) "[img]$url[/img]"
                                else "[url=$url]${label.ifBlank{url}}[/url]"
                            )
                        }
                    }
                ) {
                    Text("插入")
                }
            },
            dismissButton = { TextButton(onClick = { link = null }) { Text("取消") } },
        )
    }
}
