package bbs.binmt.cc

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlin.coroutines.resume
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONTokener
import org.jsoup.Jsoup

@SuppressLint("SetJavaScriptEnabled")
class WebsiteSession(private val context: Context) {
    private suspend fun evaluate(view: WebView, script: String): String =
        suspendCancellableCoroutine { continuation ->
            view.evaluateJavascript(script) { value ->
                if (continuation.isActive)
                    continuation.resume((JSONTokener(value).nextValue() as? String).orEmpty())
            }
        }

    suspend fun <T> page(url: String, action: suspend (WebView) -> T): T =
        withContext(Dispatchers.Main) {
            require(sameOrigin(url))
            val view = WebView(context)
            var loaded = false
            var failure: String? = null
            try {
                view.settings.javaScriptEnabled = true
                view.settings.domStorageEnabled = true
                view.settings.allowFileAccess = false
                view.settings.allowContentAccess = false
                view.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                view.webViewClient =
                    object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            web: WebView,
                            request: WebResourceRequest,
                        ) = request.isForMainFrame && !sameOrigin(request.url.toString())

                        override fun onPageFinished(web: WebView, current: String) {
                            loaded = true
                        }

                        override fun onReceivedError(
                            web: WebView,
                            request: WebResourceRequest,
                            error: WebResourceError,
                        ) {
                            if (request.isForMainFrame) failure = error.description.toString()
                        }
                    }
                withTimeout(45000) {
                    view.loadUrl(url)
                    while (!loaded) {
                        failure?.let { error(it) }
                        delay(100)
                    }
                    action(view)
                }
            } finally {
                view.evaluateJavascript("window.__mtForumLoginCleanup?.()", null)
                view.stopLoading()
                view.destroy()
            }
        }

    suspend fun read(url: String): Pair<String, String> =
        page(url) { view ->
            var source = ""
            repeat(60) {
                require(sameOrigin(view.url.orEmpty()))
                source = evaluate(view, "document.documentElement.outerHTML")
                if (
                    source.contains("id=\"ct\"") ||
                        source.contains("id=\"wp\"") ||
                        source.contains("loginform_") ||
                        source.contains("id=\"messagetext\"")
                )
                    return@page view.url.orEmpty() to source
                delay(500)
            }
            error("页面没有返回可识别内容，请检查网络或网站验证")
        }

    suspend fun login(args: JSONObject) {
        val before = authCookie()
        page("$ORIGIN/member.php?mod=logging&action=login") { view ->
            val script =
                context.assets.open("forum-login.js").bufferedReader().use { it.readText() }
            evaluate(
                view,
                "window.ForumLoginBridge={postMessage:function(m){window.__composeLoginResult=m}};($script)(${args});",
            )
            repeat(80) {
                if (authCookie().isNotEmpty() && authCookie() != before) return@page
                val result = evaluate(view, "window.__composeLoginResult || ''")
                if (result.isNotBlank()) {
                    val response = JSONObject(result)
                    if (!response.optBoolean("success"))
                        error(response.optString("message", "登录失败"))
                }
                delay(500)
            }
            error("论坛没有建立登录会话，请检查账号信息后重试")
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginPage(
    state: ForumState,
    modifier: Modifier,
    open: (String) -> Unit,
    website: (String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val inputColors =
        TextFieldDefaults.colors(
            focusedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
            unfocusedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
            disabledContainerColor = androidx.compose.ui.graphics.Color.Transparent,
            errorContainerColor = androidx.compose.ui.graphics.Color.Transparent,
        )
    var account by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var answer by remember { mutableStateOf("") }
    var field by remember { mutableStateOf("username") }
    var question by remember { mutableIntStateOf(0) }
    var rememberLogin by remember { mutableStateOf(false) }
    var visible by remember { mutableStateOf(false) }
    var expanded by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var loginJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var message by remember { mutableStateOf("") }
    val questions =
        listOf(
            "无安全提问",
            "母亲的名字",
            "爷爷的名字",
            "父亲出生的城市",
            "您其中一位老师的名字",
            "您个人计算机的型号",
            "您最喜欢的餐馆名称",
            "驾驶执照最后四位数字",
        )
    fun login() {
        if (busy) return
        if (
            account.isBlank() ||
                password.isEmpty() ||
                account.length > 256 ||
                password.length > 256 ||
                question != 0 && answer.isBlank()
        ) {
            message = "请输入有效的账号、密码和安全问题答案"
            return
        }
        val args =
            JSONObject()
                .put("attempt", System.currentTimeMillis())
                .put("loginField", field)
                .put("username", account.trim())
                .put("password", password)
                .put("questionId", question)
                .put("answer", answer.trim())
                .put("remember", rememberLogin)
        password = ""
        busy = true
        loginJob =
            scope.launch {
                try {
                    WebsiteSession(context).login(args)
                    state.loginComplete()
                } catch (cancel: kotlinx.coroutines.CancellationException) {
                    throw cancel
                } catch (e: Exception) {
                    message = e.message ?: "登录失败，请检查网络后重试"
                } finally {
                    args.remove("password")
                    busy = false
                }
            }
    }
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(
                start = 20.dp,
                end = 20.dp,
                top = LocalContentTop.current + 28.dp,
                bottom = 32.dp,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Surface(
            Modifier.size(68.dp),
            shape = CircleShape,
            color = MaterialTheme.colorScheme.secondaryContainer,
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Outlined.Forum, null, Modifier.size(34.dp))
            }
        }
        Spacer(Modifier.height(16.dp))
        Text("登录论坛账号", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(8.dp))
        Text(
            "登录信息由论坛验证，密码不会保存在本机。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(28.dp))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            listOf("username" to "用户名", "email" to "邮箱").forEachIndexed { i, (value, label) ->
                SegmentedButton(
                    field == value,
                    { field = value },
                    SegmentedButtonDefaults.itemShape(i, 2),
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(label)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Section {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                TextField(
                    account,
                    { if (it.length <= 256) account = it },
                    Modifier.fillMaxWidth(),
                    label = { Text(if (field == "email") "邮箱" else "用户名") },
                    leadingIcon = {
                        Icon(
                            if (field == "email") Icons.Outlined.Email
                            else Icons.Outlined.PersonOutline,
                            null,
                        )
                    },
                    singleLine = true,
                    enabled = !busy,
                    colors = inputColors,
                )
                TextField(
                    password,
                    { if (it.length <= 256) password = it },
                    Modifier.fillMaxWidth(),
                    label = { Text("密码") },
                    leadingIcon = { Icon(Icons.Outlined.Lock, null) },
                    trailingIcon = {
                        IconButton(onClick = { visible = !visible }) {
                            Icon(
                                if (visible) Icons.Outlined.VisibilityOff
                                else Icons.Outlined.Visibility,
                                if (visible) "隐藏密码" else "显示密码",
                            )
                        }
                    },
                    singleLine = true,
                    enabled = !busy,
                    colors = inputColors,
                    visualTransformation =
                        if (visible) VisualTransformation.None else PasswordVisualTransformation(),
                )
                ExposedDropdownMenuBox(expanded, { if (!busy) expanded = it }) {
                    TextField(
                        value = questions[question],
                        onValueChange = {},
                        enabled = !busy,
                        readOnly = true,
                        colors = inputColors,
                        singleLine = true,
                        label = { Text("安全提问（如未设置可跳过）") },
                        leadingIcon = { Icon(Icons.Outlined.Security, null) },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                        modifier = Modifier.fillMaxWidth().menuAnchor(),
                    )
                    ExposedDropdownMenu(expanded, { expanded = false }) {
                        questions.forEachIndexed { i, label ->
                            DropdownMenuItem(
                                text = { Text(label) },
                                onClick = {
                                    question = i
                                    answer = ""
                                    expanded = false
                                },
                            )
                        }
                    }
                }
                if (question != 0)
                    TextField(
                        answer,
                        { if (it.length <= 100) answer = it },
                        Modifier.fillMaxWidth(),
                        label = { Text("安全提问答案") },
                        leadingIcon = { Icon(Icons.Outlined.Key, null) },
                        enabled = !busy,
                        colors = inputColors,
                    )
            }
        }
        Spacer(Modifier.height(8.dp))
        PreferenceRow(
            "自动登录",
            enabled = !busy,
            onClick = { rememberLogin = !rememberLogin },
            trailing = { Switch(rememberLogin, { rememberLogin = it }, enabled = !busy) },
        )
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = ::login,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().height(56.dp),
        ) {
            if (busy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
            else Text("登录")
        }
        if (busy) TextButton(onClick = { loginJob?.cancel() }) { Text("取消登录") }
        Spacer(Modifier.height(12.dp))
        if (message.isNotBlank())
            Text(message, Modifier.padding(12.dp), color = MaterialTheme.colorScheme.error)
        OutlinedButton(
            enabled = !busy,
            modifier = Modifier.fillMaxWidth(),
            onClick = {
                scope.launch {
                    try {
                        val source =
                            state.client
                                .source("$ORIGIN/member.php?mod=logging&action=login")
                                .second
                        val target =
                            Jsoup.parse(source, ORIGIN)
                                .select("a[href]")
                                .firstOrNull {
                                    it.attr("href").contains("connect") || it.text().contains("QQ")
                                }
                                ?.let { safeUrl(it.attr("href")) } ?: error("官网未提供 QQ 登录入口")
                        require(sameOrigin(target) || java.net.URI(target).host == "graph.qq.com")
                        website(target)
                    } catch (e: Exception) {
                        message = e.message.orEmpty()
                    }
                }
            },
        ) {
            Icon(Icons.Outlined.QrCode2, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("使用 QQ 登录")
        }
        Spacer(Modifier.height(8.dp))
        TextButton(
            enabled = !busy,
            onClick = {
                scope.launch {
                    try {
                        val source =
                            state.client
                                .source("$ORIGIN/member.php?mod=logging&action=login")
                                .second
                        val target =
                            Jsoup.parse(source, ORIGIN)
                                .select("a[href]")
                                .mapNotNull { safeUrl(it.attr("href")) }
                                .firstOrNull {
                                    sameOrigin(it) &&
                                        Regex("register\\d*").matches(query(it, "mod").orEmpty())
                                } ?: error("官网没有返回有效注册入口，请稍后重试")
                        open(target)
                    } catch (e: Exception) {
                        message = e.message.orEmpty()
                    }
                }
            },
        ) {
            Text("没有账号？注册")
        }
    }
}

@Composable
fun SearchPage(state: ForumState, modifier: Modifier) {
    var query by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    fun submit() {
        if (busy || query.isBlank()) return
        val submitted = query.trim()
        keyboard?.hide()
        failure = ""
        busy = true
        scope.launch {
            try {
                val response = state.client.source("$ORIGIN/search.php?mod=forum")
                val page = ForumParser.parse(response.second, response.first)
                val form =
                    page.forms.firstOrNull { it.fields.any { field -> field.name == "srchtxt" } }
                        ?: error("搜索表单未就绪，请重试")
                state.present(page)
                state.submitFields(
                    form,
                    form.fields
                        .filter { it.type != "submit" }
                        .map { it.name to if (it.name == "srchtxt") submitted else it.value } +
                        form.fields
                            .filter { it.type == "submit" }
                            .take(1)
                            .map { it.name to it.value },
                )
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (e: Exception) {
                failure = e.message.orEmpty()
            } finally {
                busy = false
            }
        }
    }
    LaunchedEffect(Unit) { focus.requestFocus() }
    Column(modifier.padding(top = LocalContentTop.current).padding(16.dp)) {
        Surface(
            Modifier.fillMaxWidth(),
            shape = CircleShape,
            color =
                if (MaterialTheme.colorScheme.surface == Color.Black) Color(0xFF1C1C1E)
                else MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Row(
                Modifier.heightIn(min = 56.dp).padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.Search, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                BasicTextField(
                    query,
                    { query = it },
                    Modifier.weight(1f).padding(horizontal = 8.dp).focusRequester(focus),
                    singleLine = true,
                    textStyle =
                        MaterialTheme.typography.bodyLarge.copy(
                            color = MaterialTheme.colorScheme.onSurface
                        ),
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { submit() }),
                    decorationBox = { inner ->
                        Box {
                            if (query.isEmpty())
                                Text(
                                    "输入关键词",
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            inner()
                        }
                    },
                )
                IconButton(onClick = ::submit, enabled = !busy) {
                    Icon(Icons.Outlined.ArrowForward, "搜索")
                }
            }
        }
        Spacer(Modifier.height(24.dp))
        Text("搜索结果由论坛提供，权限和搜索间隔以网站规则为准。", style = MaterialTheme.typography.bodyMedium)
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (failure.isNotEmpty())
            Text(failure, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error)
    }
}
