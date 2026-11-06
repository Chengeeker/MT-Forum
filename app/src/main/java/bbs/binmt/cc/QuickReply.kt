package bbs.binmt.cc

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException

@Composable
fun QuickReply(state: ForumState, dirty: (Boolean) -> Unit, website: (String) -> Unit) {
    val tid = state.page?.resolvedThreadId ?: return
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    val density = androidx.compose.ui.platform.LocalDensity.current
    val keyboardHeight = with(density) { WindowInsets.ime.getBottom(this).toDp().value }
    val maxHeight =
        ((androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp - keyboardHeight) *
                .55f)
            .coerceIn(120f, 420f)
            .dp
    var expanded by remember(tid) { mutableStateOf(false) }
    var form by remember(tid) { mutableStateOf<Form?>(null) }
    var loading by remember(tid) { mutableStateOf(false) }
    var error by remember(tid) { mutableStateOf("") }
    var revision by remember(tid) { mutableIntStateOf(0) }
    var changed by remember(tid) { mutableStateOf(false) }
    val draft = remember(tid) { mutableStateListOf<String>() }
    var target by remember(tid) { mutableStateOf<String?>(null) }
    LaunchedEffect(state.replyTarget, state.replyRevision, tid, revision) {
        val request = state.replyTarget ?: return@LaunchedEffect
        expanded = true
        if (form != null && target == request) return@LaunchedEffect
        val url =
            "$ORIGIN/forum.php?mod=post&action=reply&tid=$tid" +
                if (request.isNotBlank()) "&repquote=$request" else ""
        if (!state.authenticated) {
            state.load(url)
            return@LaunchedEffect
        }
        loading = true
        error = ""
        form = null
        target = request
        changed = false
        dirty(false)
        try {
            val data = state.client.load(url)
            val next =
                data.forms.firstOrNull { it.fields.any { field -> field.name == "message" } }
                    ?: error(data.notice.ifBlank { "论坛没有返回可用的回复表单" })
            draft.clear()
            draft.addAll(next.fields.map { it.value })
            form = next
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (e: Exception) {
            error = e.message.orEmpty()
        } finally {
            loading = false
        }
    }
    DisposableEffect(tid) {
        onDispose {
            state.replyTarget = null
            dirty(false)
        }
    }
    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(
            Modifier.navigationBarsPadding()
                .imePadding()
                .padding(start = 12.dp, top = 4.dp, end = 12.dp, bottom = 8.dp)
        ) {
            if (!expanded)
                TextButton(
                    onClick = { if (form != null) expanded = true else state.reply() },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Outlined.Edit, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(if (changed) "继续编辑回复…" else "说点什么吧…")
                }
            Column(
                if (expanded)
                    Modifier.heightIn(max = maxHeight).verticalScroll(rememberScrollState())
                else Modifier.height(0.dp).clearAndSetSemantics {}
            ) {
                if (form == null)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        IconButton(
                            onClick = {
                                expanded = false
                                keyboard?.hide()
                            }
                        ) {
                            Icon(Icons.Outlined.KeyboardArrowDown, "收起编辑栏")
                        }
                    }
                if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (error.isNotEmpty())
                    Text(error, Modifier.padding(8.dp), color = MaterialTheme.colorScheme.error)
                if (state.error.isNotEmpty())
                    Text(
                        state.error,
                        Modifier.padding(8.dp),
                        color = MaterialTheme.colorScheme.error,
                    )
                form?.let { current ->
                    NativeForm(
                        current,
                        state,
                        { website(current.action) },
                        {
                            changed = it
                            dirty(it)
                        },
                        completed = {
                            form = null
                            expanded = false
                            changed = false
                            dirty(false)
                            state.replyTarget = null
                            state.accountMessage = "回复已发送"
                            state.load(state.currentUrl, push = false)
                        },
                        draft = draft,
                        compact = true,
                        focusRequest = if (expanded) state.replyRevision + 1 else 0,
                        collapse = {
                            expanded = false
                            keyboard?.hide()
                        },
                    )
                }
                if (form == null && !loading) TextButton(onClick = { revision++ }) { Text("重试回复") }
            }
        }
    }
}
