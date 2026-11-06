package bbs.binmt.cc

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.webkit.*
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun BrowserDialog(url: String, onAuthenticated: (() -> Unit)? = null, onClose: () -> Unit) {
    var view by remember { mutableStateOf<WebView?>(null) }
    var error by remember { mutableStateOf("") }
    var current by remember { mutableStateOf(url) }
    var progress by remember { mutableIntStateOf(0) }
    var canBack by remember { mutableStateOf(false) }
    val originalAuth = remember { authCookie() }
    var authenticated by remember { mutableStateOf(false) }
    val loginCompleted by rememberUpdatedState(onAuthenticated)
    val context = LocalContext.current
    val colors = MaterialTheme.colorScheme
    val barColor =
        if (colors.surface == Color.Black) Color.Black
        else if (colors.surface.luminance() < .5f) Color(0xFF111215) else colors.surface
    var upload by remember { mutableStateOf<ValueCallback<Array<Uri>>?>(null) }
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result
            ->
            upload?.onReceiveValue(
                WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
            )
            upload = null
        }
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(Modifier.fillMaxSize(), color = barColor) {
            Column(Modifier.systemBarsPadding()) {
                Row(
                    Modifier.fillMaxWidth()
                        .height(56.dp)
                        .background(
                            Brush.verticalGradient(
                                listOf(barColor.copy(alpha = .95f), barColor.copy(alpha = .45f))
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
                        },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onClose, modifier = Modifier.width(56.dp)) {
                        Icon(Icons.Outlined.Close, "关闭浏览器")
                    }
                    Text(
                        runCatching { java.net.URI(current).host }.getOrDefault("网页"),
                        Modifier.weight(1f).padding(start = 16.dp),
                        maxLines = 1,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    IconButton(onClick = { view?.goBack() }, enabled = canBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, "后退")
                    }
                    IconButton(onClick = { view?.reload() }) { Icon(Icons.Outlined.Refresh, "刷新") }
                }
                if (error.isEmpty() && progress == 0)
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                else if (error.isEmpty() && progress < 100)
                    LinearProgressIndicator(
                        progress = { progress / 100f },
                        modifier = Modifier.fillMaxWidth(),
                    )
                if (error.isNotBlank())
                    Row(
                        Modifier.fillMaxWidth().background(colors.surfaceContainer).padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(error, Modifier.weight(1f))
                        TextButton(onClick = { view?.reload() }) { Text("重试") }
                    }
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { ctx ->
                        WebView(ctx).apply {
                            view = this
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            settings.allowFileAccess = false
                            settings.allowContentAccess = false
                            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                            settings.setSupportMultipleWindows(false)
                            CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
                            webViewClient =
                                object : WebViewClient() {
                                    override fun shouldOverrideUrlLoading(
                                        web: WebView,
                                        request: WebResourceRequest,
                                    ): Boolean {
                                        if (
                                            request.isForMainFrame && request.url.scheme == "mailto"
                                        ) {
                                            runCatching {
                                                    context.startActivity(
                                                        Intent(Intent.ACTION_SENDTO, request.url)
                                                    )
                                                }
                                                .onFailure { error = "没有可打开此链接的应用" }
                                            return true
                                        }
                                        val next = browserUrl(request.url.toString())
                                        if (next == null) {
                                            error = "已阻止不安全或不支持的链接"
                                            return true
                                        }
                                        val host = java.net.URI(next).host
                                        val trusted =
                                            sameOrigin(next) ||
                                                host in
                                                    setOf(
                                                        "graph.qq.com",
                                                        "xui.ptlogin2.qq.com",
                                                        "ssl.ptlogin2.qq.com",
                                                    )
                                        if (sameOrigin(url) && !trusted && request.isForMainFrame) {
                                            runCatching {
                                                    context.startActivity(
                                                        Intent(Intent.ACTION_VIEW, Uri.parse(next))
                                                    )
                                                }
                                                .onFailure { error = "没有可用的外部浏览器" }
                                            return true
                                        }
                                        return false
                                    }

                                    override fun onPageStarted(
                                        web: WebView,
                                        value: String,
                                        icon: android.graphics.Bitmap?,
                                    ) {
                                        current = value
                                        error = ""
                                        progress = 0
                                    }

                                    override fun onReceivedError(
                                        web: WebView,
                                        request: WebResourceRequest,
                                        failure: WebResourceError,
                                    ) {
                                        if (request.isForMainFrame)
                                            error = "网页加载失败：${failure.description}"
                                    }

                                    override fun onReceivedHttpError(
                                        web: WebView,
                                        request: WebResourceRequest,
                                        response: WebResourceResponse,
                                    ) {
                                        if (request.isForMainFrame)
                                            error = "网页返回 HTTP ${response.statusCode}"
                                    }

                                    override fun onPageFinished(web: WebView, value: String) {
                                        CookieManager.getInstance().flush()
                                        current = value
                                        canBack = web.canGoBack()
                                        progress = 100
                                        if (
                                            !authenticated &&
                                                sameOrigin(value) &&
                                                authCookie().isNotBlank() &&
                                                authCookie() != originalAuth
                                        ) {
                                            authenticated = true
                                            loginCompleted?.invoke()
                                        }
                                    }
                                }
                            webChromeClient =
                                object : WebChromeClient() {
                                    override fun onProgressChanged(web: WebView, value: Int) {
                                        progress = value
                                    }

                                    override fun onShowFileChooser(
                                        web: WebView,
                                        callback: ValueCallback<Array<Uri>>,
                                        params: FileChooserParams,
                                    ): Boolean {
                                        if (!sameOrigin(web.url.orEmpty())) return false
                                        upload?.onReceiveValue(null)
                                        upload = callback
                                        runCatching { picker.launch(params.createIntent()) }
                                            .onFailure {
                                                callback.onReceiveValue(null)
                                                upload = null
                                                error = "无法打开文件选择器"
                                            }
                                        return true
                                    }
                                }
                            loadUrl(url)
                        }
                    },
                )
            }
        }
        BackHandler { if (view?.canGoBack() == true) view?.goBack() else onClose() }
    }
    DisposableEffect(Unit) {
        onDispose {
            upload?.onReceiveValue(null)
            view?.stopLoading()
            view?.destroy()
        }
    }
}
