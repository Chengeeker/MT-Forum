package bbs.binmt.cc

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import org.jsoup.Jsoup
import org.jsoup.nodes.TextNode

data class ArticlePart(
    val kind: String,
    val value: String,
    val width: Float? = null,
    val height: Float? = null,
    val title: String = "",
    val original: String? = null,
)

data class GallerySelection(val images: List<String>, val index: Int = 0, val bounds: Rect? = null)

data class ImageAnchor(val url: String, val bounds: Rect?)

fun articleParts(html: String): List<ArticlePart> {
    val doc = Jsoup.parseBodyFragment(html)
    doc.select("script,style,iframe,object,embed").remove()
    val parts = linkedMapOf<String, ArticlePart>()
    val selector =
        ".locked,.attach_nopermission,.blockcode,pre,table,img,video,a.forum-video,p,ul,ol,h1,h2,h3,h4,h5,h6"
    doc.select(selector)
        .filter { it.parents().none { parent -> parent.`is`(selector) } }
        .forEachIndexed { index, node ->
            val marker = "\uE000MTBLOCK${index}\uE001"
            val kind =
                when {
                    node.hasClass("locked") || node.hasClass("attach_nopermission") -> "access"
                    node.hasClass("blockcode") || node.tagName() == "pre" -> "code"
                    node.hasClass("forum-video") -> "video"
                    else -> node.tagName()
                }
            val value =
                when (kind) {
                    "code" -> {
                        val code = node.selectFirst("code,pre") ?: node
                        if (code.select("ol li").isNotEmpty())
                            code.select("ol li").joinToString("\n") { it.wholeText() }
                        else code.wholeText().trimEnd()
                    }
                    "img" -> safeUrl(node.attr("src")).orEmpty()
                    "video" ->
                        safeUrl(
                                node
                                    .attr("href")
                                    .ifBlank { node.attr("src") }
                                    .ifBlank { node.selectFirst("source")?.attr("src").orEmpty() }
                            )
                            .orEmpty()
                    else -> node.outerHtml()
                }
            parts[marker] =
                ArticlePart(
                    kind,
                    value,
                    node.attr("width").toFloatOrNull()?.takeIf { it.isFinite() && it > 0 },
                    node.attr("height").toFloatOrNull()?.takeIf { it.isFinite() && it > 0 },
                    if (kind == "video") node.text().trim() else "",
                    if (kind == "img") safeUrl(node.attr("data-forum-original")) else null,
                )
            node.replaceWith(TextNode(marker))
        }
    val source = doc.body().html()
    val pattern = Regex("\uE000MTBLOCK\\d+\uE001")
    val markers = pattern.findAll(source).toList()
    return buildList {
        pattern.split(source).forEachIndexed { index, chunk ->
            if (Jsoup.parseBodyFragment(chunk).text().isNotBlank()) add(ArticlePart("text", chunk))
            if (index < markers.size)
                parts.getValue(markers[index].value).takeIf { it.value.isNotEmpty() }?.let(::add)
        }
    }
}

@Composable
fun ArticleBody(
    html: String,
    open: (String) -> Unit,
    images: ((ImageAnchor) -> Unit)? = null,
    video: ((String) -> Unit)? = null,
    textStyle: TextStyle = MaterialTheme.typography.bodyLarge,
) {
    val parts = remember(html) { articleParts(html) }
    val context = LocalContext.current
    parts.forEach { part ->
        when (part.kind) {
            "access" ->
                Surface(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    shape = RoundedCornerShape(8.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHighest,
                ) {
                    Box(Modifier.padding(12.dp)) { RichText(part.value, open, textStyle) }
                }
            "p" ->
                Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
                    ArticleBody(
                        remember(part.value) {
                            Jsoup.parseBodyFragment(part.value).selectFirst("p")!!.html()
                        },
                        open,
                        images,
                        video,
                        textStyle,
                    )
                }
            "ul",
            "ol" -> {
                val list =
                    remember(part.value) {
                        Jsoup.parseBodyFragment(part.value).selectFirst(part.kind)!!
                    }
                val first = list.attr("start").toIntOrNull() ?: 1
                Column(Modifier.padding(vertical = 8.dp)) {
                    list
                        .children()
                        .filter { it.tagName() == "li" }
                        .forEachIndexed { index, entry ->
                            Row(Modifier.padding(vertical = 3.dp)) {
                                Box(Modifier.width(24.dp), contentAlignment = Alignment.TopCenter) {
                                    Text(
                                        if (part.kind == "ol") "${first.toLong() + index}."
                                        else "•",
                                        style = textStyle,
                                    )
                                }
                                Column(Modifier.weight(1f)) {
                                    ArticleBody(entry.html(), open, images, video, textStyle)
                                }
                            }
                        }
                }
            }
            "h1",
            "h2",
            "h3",
            "h4",
            "h5",
            "h6" -> {
                val scale =
                    listOf(2f, 1.5f, 1.17f, 1f, .83f, .67f)[part.kind.last().digitToInt() - 1]
                Column(Modifier.padding(top = 16.dp, bottom = 8.dp)) {
                    ArticleBody(
                        remember(part.value) {
                            Jsoup.parseBodyFragment(part.value).selectFirst(part.kind)!!.html()
                        },
                        open,
                        images,
                        video,
                        textStyle.copy(
                            fontSize = textStyle.fontSize * scale,
                            lineHeight = textStyle.lineHeight * scale,
                            fontWeight = MaterialTheme.typography.titleLarge.fontWeight,
                        ),
                    )
                }
            }
            "code" ->
                Column(
                    Modifier.padding(vertical = 8.dp)
                        .fillMaxWidth()
                        .background(
                            MaterialTheme.colorScheme.surfaceContainer,
                            RoundedCornerShape(12.dp),
                        )
                        .border(
                            1.dp,
                            MaterialTheme.colorScheme.outlineVariant,
                            RoundedCornerShape(12.dp),
                        )
                ) {
                    Row(
                        Modifier.padding(start = 12.dp, top = 4.dp, end = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("代码", Modifier.weight(1f), style = MaterialTheme.typography.labelLarge)
                        TextButton(
                            onClick = {
                                (context.getSystemService(android.content.Context.CLIPBOARD_SERVICE)
                                        as android.content.ClipboardManager)
                                    .setPrimaryClip(
                                        android.content.ClipData.newPlainText("代码", part.value)
                                    )
                            }
                        ) {
                            Icon(Icons.Outlined.ContentCopy, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("复制代码")
                        }
                    }
                    SelectionContainer {
                        Text(
                            part.value,
                            Modifier.heightIn(max = 320.dp)
                                .verticalScroll(rememberScrollState())
                                .horizontalScroll(rememberScrollState())
                                .padding(start = 12.dp, top = 4.dp, end = 12.dp, bottom = 12.dp),
                            fontFamily = FontFamily.Monospace,
                            softWrap = false,
                            style = MaterialTheme.typography.bodySmall.copy(lineHeight = 17.4.sp),
                        )
                    }
                }
            "img" -> {
                val original = part.original ?: part.value
                var source by remember(part) { mutableStateOf(part.value) }
                var intrinsic by remember(part) { mutableStateOf(Size.Zero) }
                var failed by remember(part) { mutableStateOf(false) }
                var bounds by remember { mutableStateOf<Rect?>(null) }
                val configuration = LocalConfiguration.current
                val density = LocalDensity.current.density
                BoxWithConstraints {
                    val limitWidth =
                        minOf(
                                maxWidth.value,
                                (configuration.screenWidthDp - 64f).coerceIn(120f, 900f),
                            )
                            .coerceAtLeast(1f)
                    val limitHeight = (configuration.screenHeightDp * .7f).coerceAtLeast(1f)
                    // Decode against the final bounds, not the smaller loading placeholder.
                    val request =
                        remember(source, limitWidth, limitHeight, density) {
                            coil.request.ImageRequest.Builder(context)
                                .data(source)
                                .size(
                                    (limitWidth * density).toInt().coerceAtLeast(1),
                                    (limitHeight * density).toInt().coerceAtLeast(1),
                                )
                                .build()
                        }
                    val dimensions =
                        articleImageSize(
                            intrinsic,
                            part.width,
                            part.height,
                            Size(limitWidth, limitHeight),
                        )
                    val action =
                        Modifier.clickable {
                            images?.invoke(ImageAnchor(original, bounds)) ?: open(original)
                        }
                    if (failed)
                        Box(action.padding(20.dp)) { Icon(Icons.Outlined.BrokenImage, "图片加载失败") }
                    else
                        Box(
                            action
                                .size(dimensions.width.dp, dimensions.height.dp)
                                .onGloballyPositioned { bounds = it.boundsInWindow() },
                            contentAlignment = Alignment.Center,
                        ) {
                            AsyncImage(
                                request,
                                "查看图片",
                                Modifier.fillMaxSize(),
                                contentScale = ContentScale.Fit,
                                onSuccess = { result ->
                                    val d = result.result.drawable
                                    if (d.intrinsicWidth > 0 && d.intrinsicHeight > 0)
                                        intrinsic =
                                            Size(
                                                d.intrinsicWidth.toFloat(),
                                                d.intrinsicHeight.toFloat(),
                                            )
                                },
                                onError = {
                                    if (source != original) source = original else failed = true
                                },
                            )
                            if (intrinsic == Size.Zero) CircularProgressIndicator()
                        }
                }
            }
            "video" ->
                ArticleVideoCard(part.title) { video?.invoke(part.value) ?: open(part.value) }
            "table" -> ArticleTable(part.value, open, images, video, textStyle)
            else -> RichText(part.value, open, textStyle)
        }
    }
}

internal fun articleImageSize(intrinsic: Size, width: Float?, height: Float?, limit: Size): Size {
    val w = width?.coerceIn(1f, limit.width)
    val h = height?.coerceIn(1f, limit.height)
    if (intrinsic.width <= 0 || intrinsic.height <= 0)
        return Size(w ?: minOf(128f, limit.width), h ?: minOf(80f, limit.height))
    if (w != null && h != null) return Size(w, h)
    val ratio = intrinsic.width / intrinsic.height
    val natural =
        Size(
            w ?: h?.let { it * ratio } ?: intrinsic.width,
            h ?: w?.let { it / ratio } ?: intrinsic.height,
        )
    val scale = minOf(1f, limit.width / natural.width, limit.height / natural.height)
    return Size(natural.width * scale, natural.height * scale)
}

@Composable
internal fun ArticleVideoCard(title: String = "", play: () -> Unit) {
    Section(Modifier.padding(vertical = 8.dp)) {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = play).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Outlined.PlayCircleOutline,
                null,
                Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.width(12.dp))
            Text(title.ifEmpty { "播放论坛视频" }, Modifier.weight(1f))
            Icon(Icons.Outlined.ChevronRight, null)
        }
    }
}
