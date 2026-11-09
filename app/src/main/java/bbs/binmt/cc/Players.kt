package bbs.binmt.cc

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.view.Surface
import android.view.TextureView
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateOffsetAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.input.pointer.*
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import coil.compose.AsyncImage
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import kotlin.math.roundToInt
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.*

data class ImageTransform(val scale: Float = 1f, val offset: Offset = Offset.Zero)

@Composable
private fun MediaWindow() {
    val view = androidx.compose.ui.platform.LocalView.current
    DisposableEffect(view) {
        val window = (view.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window
        window?.apply {
            setDimAmount(0f)
            statusBarColor = android.graphics.Color.TRANSPARENT
            navigationBarColor = android.graphics.Color.TRANSPARENT
            androidx.core.view.WindowCompat.getInsetsController(this, view).apply {
                isAppearanceLightStatusBars = false
                isAppearanceLightNavigationBars = false
            }
        }
        onDispose {}
    }
}

object ImageGeometry {
    fun nextScale(scale: Float, image: Size) =
        when {
            scale <= 1.05f -> if (image.height / image.width > 2f) 3.5f else 2.5f
            scale <= 3.6f -> 6f
            else -> 1f
        }

    fun transform(
        from: ImageTransform,
        scale: Float,
        anchor: Offset,
        viewport: Size,
        image: Size,
        pan: Offset = Offset.Zero,
    ): ImageTransform {
        if (scale <= 1f) return ImageTransform()
        if (viewport.width <= 0 || viewport.height <= 0 || image.width <= 0 || image.height <= 0)
            return from
        val factor = min(viewport.width / image.width, viewport.height / image.height)
        val maxX = max(0f, (image.width * factor * scale - viewport.width) / 2)
        val maxY = max(0f, (image.height * factor * scale - viewport.height) / 2)
        val center = Offset(viewport.width / 2, viewport.height / 2)
        val offset = anchor + (center + from.offset - anchor) * (scale / from.scale) - center + pan
        return ImageTransform(
            scale,
            Offset(offset.x.coerceIn(-maxX, maxX), offset.y.coerceIn(-maxY, maxY)),
        )
    }
}

class MediaSaveController {
    var busy by mutableStateOf(false)
    val snackbar = SnackbarHostState()
    var start: (String, Boolean) -> Unit = { _, _ -> }
    var cancel: () -> Unit = {}
}

@Composable
private fun mediaSaver(state: ForumState, author: String): MediaSaveController {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val control = remember { MediaSaveController() }
    var pending by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var job by remember { mutableStateOf<Job?>(null) }
    fun save(url: String, video: Boolean) {
        if (control.busy) return
        control.busy = true
        job =
            scope.launch {
                val message =
                    try {
                        MediaStorage.save(context, state, url, video, author) {}
                        "已保存到系统相册"
                    } catch (cancel: CancellationException) {
                        "已取消保存"
                    } catch (e: Exception) {
                        e.message ?: "保存失败"
                    } finally {
                        control.busy = false
                    }
                scope.launch { control.snackbar.showSnackbar(message) }
            }
    }
    val permission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val request = pending
            pending = null
            if (granted && request != null) save(request.first, request.second)
            else scope.launch { control.snackbar.showSnackbar("未获得相册写入权限") }
        }
    SideEffect {
        control.start = { url, video ->
            if (
                Build.VERSION.SDK_INT < 29 &&
                    context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                        PackageManager.PERMISSION_GRANTED
            ) {
                pending = url to video
                permission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            } else save(url, video)
        }
        control.cancel = { job?.cancel() }
    }
    return control
}

@Composable
fun GalleryDialog(
    selection: GallerySelection,
    state: ForumState,
    author: String,
    onClose: () -> Unit,
) {
    val images = selection.images
    val pager = rememberPagerState(initialPage = selection.index, pageCount = { images.size })
    val thumbs = rememberPagerState(initialPage = selection.index, pageCount = { images.size })
    val reelDriving = remember { mutableStateOf(false) }
    GalleryPagerSync(pager, thumbs, reelDriving)
    val save = mediaSaver(state, author)
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var zoomed by remember { mutableStateOf(false) }
    val transition = remember { androidx.compose.animation.core.Animatable(0f) }
    var closing by remember { mutableStateOf(false) }
    var viewportSize by remember { mutableStateOf(Size.Zero) }
    var heroImage by remember { mutableStateOf(Size(1f, 1f)) }
    val reduced =
        android.provider.Settings.Global.getFloat(
            context.contentResolver,
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    LaunchedEffect(Unit) {
        transition.animateTo(
            1f,
            tween(if (reduced) 0 else 330, easing = CubicBezierEasing(.33f, 1f, .68f, 1f)),
        )
    }
    fun close() {
        if (!closing) {
            closing = true
            scope.launch {
                transition.animateTo(0f, tween(if (reduced) 0 else 200))
                onClose()
            }
        }
    }
    val backdrop = rememberBackdrop(Color.Black)
    Dialog(
        onDismissRequest = ::close,
        properties =
            DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        MediaWindow()
        BackHandler(onBack = ::close)
        CompositionLocalProvider(LocalBackdrop provides backdrop) {
            Box(
                Modifier.fillMaxSize()
                    .onSizeChanged { viewportSize = Size(it.width.toFloat(), it.height.toFloat()) }
                    .background(Color.Black.copy(alpha = transition.value))
            ) {
                Box {
                    HorizontalPager(
                        pager,
                        userScrollEnabled = !zoomed,
                        modifier =
                            Modifier.fillMaxSize()
                                .graphicsLayer { alpha = if (transition.value == 1f) 1f else 0f }
                                .captureBackdrop(backdrop),
                    ) { index ->
                        var transform by
                            remember(images[index]) { mutableStateOf(ImageTransform()) }
                        var viewport by remember { mutableStateOf(Size.Zero) }
                        var image by remember { mutableStateOf(Size(1f, 1f)) }
                        var animation by remember { mutableStateOf<Job?>(null) }
                        var failed by remember { mutableStateOf(false) }
                        LaunchedEffect(pager.currentPage) {
                            animation?.cancel()
                            transform = ImageTransform()
                            zoomed = false
                        }
                        DisposableEffect(Unit) { onDispose { animation?.cancel() } }
                        Box(
                            Modifier.fillMaxSize()
                                .onSizeChanged {
                                    viewport = Size(it.width.toFloat(), it.height.toFloat())
                                }
                                .pointerInput(index) {
                                    detectTapGestures(
                                        onDoubleTap = { anchor ->
                                            animation?.cancel()
                                            val start = transform
                                            val target = ImageGeometry.nextScale(start.scale, image)
                                            animation =
                                                scope.launch {
                                                    val reduced =
                                                        android.provider.Settings.Global.getFloat(
                                                            context.contentResolver,
                                                            android.provider.Settings.Global
                                                                .ANIMATOR_DURATION_SCALE,
                                                            1f,
                                                        ) == 0f
                                                    if (reduced)
                                                        transform =
                                                            ImageGeometry.transform(
                                                                start,
                                                                target,
                                                                anchor,
                                                                viewport,
                                                                image,
                                                            )
                                                    else
                                                        animate(
                                                            start.scale,
                                                            target,
                                                            animationSpec =
                                                                tween(
                                                                    260,
                                                                    easing =
                                                                        CubicBezierEasing(
                                                                            .215f,
                                                                            .61f,
                                                                            .355f,
                                                                            1f,
                                                                        ),
                                                                ),
                                                        ) { value, _ ->
                                                            transform =
                                                                ImageGeometry.transform(
                                                                    start,
                                                                    value,
                                                                    anchor,
                                                                    viewport,
                                                                    image,
                                                                )
                                                            zoomed = value > 1.05f
                                                        }
                                                    zoomed = transform.scale > 1.05f
                                                }
                                        }
                                    )
                                }
                                .pointerInput(index) {
                                    awaitEachGesture {
                                        awaitFirstDown(requireUnconsumed = false)
                                        animation?.cancel()
                                        do {
                                            val event = awaitPointerEvent()
                                            val multi = event.changes.count { it.pressed } > 1
                                            if (multi || transform.scale > 1.05f) {
                                                val anchor =
                                                    event.calculateCentroid(useCurrent = false)
                                                if (anchor != Offset.Unspecified) {
                                                    transform =
                                                        ImageGeometry.transform(
                                                            transform,
                                                            (transform.scale *
                                                                    event.calculateZoom())
                                                                .coerceIn(1f, 8f),
                                                            anchor,
                                                            viewport,
                                                            image,
                                                            event.calculatePan(),
                                                        )
                                                    zoomed = transform.scale > 1.05f
                                                    event.changes.forEach {
                                                        if (it.positionChanged()) it.consume()
                                                    }
                                                }
                                            }
                                        } while (event.changes.any { it.pressed })
                                    }
                                }
                        ) {
                            var retryImage by remember { mutableIntStateOf(0) }
                            key(retryImage) {
                                AsyncImage(
                                    coil.request.ImageRequest.Builder(context)
                                        .data(images[index])
                                        .size(coil.size.Size.ORIGINAL)
                                        .build(),
                                    "图片 ${index+1}，双击分档缩放",
                                    contentScale = ContentScale.Fit,
                                    modifier =
                                        Modifier.fillMaxSize()
                                            .graphicsLayer(
                                                scaleX = transform.scale,
                                                scaleY = transform.scale,
                                                translationX = transform.offset.x,
                                                translationY = transform.offset.y,
                                            ),
                                    onSuccess = { result ->
                                        image =
                                            Size(
                                                result.result.drawable.intrinsicWidth.toFloat(),
                                                result.result.drawable.intrinsicHeight.toFloat(),
                                            )
                                        failed = false
                                        if (index == selection.index) heroImage = image
                                    },
                                    onError = { failed = true },
                                )
                            }
                            if (failed)
                                Text(
                                    "图片加载失败，点击重试",
                                    Modifier.align(Alignment.Center).clickable {
                                        failed = false
                                        retryImage++
                                    },
                                    color = Color.White,
                                )
                        }
                    }
                    if (transition.value < 1f && viewportSize.width > 0) {
                        val source =
                            selection.bounds?.takeIf { pager.currentPage == selection.index }
                                ?: Rect(Offset.Zero, viewportSize)
                        val scale =
                            min(
                                viewportSize.width / heroImage.width,
                                viewportSize.height / heroImage.height,
                            )
                        val target = Size(heroImage.width * scale, heroImage.height * scale)
                        val end =
                            Rect(
                                Offset(
                                    (viewportSize.width - target.width) / 2,
                                    (viewportSize.height - target.height) / 2,
                                ),
                                target,
                            )
                        val p = transition.value
                        val rect =
                            Rect(
                                source.left + (end.left - source.left) * p,
                                source.top + (end.top - source.top) * p,
                                source.right + (end.right - source.right) * p,
                                source.bottom + (end.bottom - source.bottom) * p,
                            )
                        val density = LocalDensity.current
                        AsyncImage(
                            images[pager.currentPage],
                            null,
                            Modifier.offset {
                                    androidx.compose.ui.unit.IntOffset(
                                        rect.left.toInt(),
                                        rect.top.toInt(),
                                    )
                                }
                                .size(
                                    with(density) { rect.width.toDp() },
                                    with(density) { rect.height.toDp() },
                                ),
                            contentScale = ContentScale.Fit,
                        )
                    }
                    if (!closing || !state.settings.bool("liquidGlass"))
                        Row(
                            Modifier.align(Alignment.TopCenter)
                                .fillMaxWidth()
                                .statusBarsPadding()
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            GalleryButton(state, ::close) {
                                Icon(
                                    Icons.AutoMirrored.Rounded.ArrowBack,
                                    "返回",
                                    Modifier.size(
                                        22.dp
                                    ),
                                )
                            }
                            Spacer(Modifier.weight(1f))
                            Text(
                                "${pager.currentPage+1} / ${images.size}",
                                Modifier.background(
                                        Color.Black.copy(alpha = .45f),
                                        RoundedCornerShape(16.dp),
                                    )
                                    .padding(horizontal = 14.dp, vertical = 6.dp),
                                color = Color.White,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                            )
                            Spacer(Modifier.weight(1f))
                            GalleryButton(
                                state,
                                { save.start(images[pager.currentPage], false) },
                                !save.busy,
                            ) {
                                if (save.busy)
                                    CircularProgressIndicator(
                                        Modifier.size(18.dp),
                                        color = Color.White,
                                        strokeWidth = 2.dp,
                                    )
                                else
                                    Icon(
                                        Icons.Rounded.Download,
                                        "保存到相册",
                                        Modifier.size(
                                            22.dp
                                        ),
                                    )
                            }
                        }
                    if (images.size > 1 && !closing && transition.value == 1f)
                        BoxWithConstraints(Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding().padding(bottom = 32.dp)) {
                            val cell = maxWidth * .16f
                            HorizontalPager(thumbs, Modifier.fillMaxWidth().height(64.dp), pageSize = PageSize.Fixed(cell),
                                contentPadding = PaddingValues(horizontal = (maxWidth - cell) / 2),
                                flingBehavior = PagerDefaults.flingBehavior(thumbs, pagerSnapDistance = PagerSnapDistance.atMost(images.size))) { index ->
                                val selected = pager.currentPage == index
                                val outline = RoundedCornerShape(8.dp)
                                Box(Modifier.fillMaxSize().padding(horizontal = 3.dp, vertical = 2.dp)
                                    .clip(outline).border(2.dp, if (selected) Color.White else Color.Transparent, outline)
                                    .semantics { this.selected = selected }
                                    .clickable(interactionSource = null, indication = null) {
                                        state.haptic()
                                        reelDriving.value = false
                                        pager.requestScrollToPage(index)
                                        thumbs.requestScrollToPage(index)
                                    }.padding(2.dp).clip(RoundedCornerShape(6.dp))) {
                                    val request = remember(images[index]) { coil.request.ImageRequest.Builder(context).data(images[index]).size(160).build() }
                                    AsyncImage(request, "第 ${index + 1} 张图片", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                                    if (!selected) Box(Modifier.matchParentSize().background(Color.White.copy(alpha = .5f)))
                                }
                            }
                        }
                    SnackbarHost(
                        save.snackbar,
                        Modifier.align(Alignment.BottomCenter).navigationBarsPadding(),
                    )
                }
            }
        }
    }
    DisposableEffect(Unit) { onDispose { state.maintainCache() } }
}

@Composable
internal fun GalleryPagerSync(
    pager: PagerState,
    thumbnails: PagerState,
    reelDriving: MutableState<Boolean>,
): Boolean {
    val reelDragged by thumbnails.interactionSource.collectIsDraggedAsState()
    val mainDragged by pager.interactionSource.collectIsDraggedAsState()
    LaunchedEffect(reelDragged, mainDragged) {
        if (reelDragged) {
            reelDriving.value = true
            pager.stopScroll()
        } else if (mainDragged) {
            reelDriving.value = false
            thumbnails.stopScroll()
            thumbnails.requestScrollToPage(pager.currentPage)
        }
    }
    LaunchedEffect(pager) {
        snapshotFlow { pager.currentPage }
            .collect { index -> if (!reelDriving.value) thumbnails.requestScrollToPage(index) }
    }
    LaunchedEffect(thumbnails) {
        snapshotFlow {
                Triple(
                    reelDriving.value,
                    thumbnails.currentPage,
                    thumbnails.currentPageOffsetFraction,
                )
            }
            .collect { (driving, index, fraction) ->
                if (driving) {
                    // A fast small-page fling can briefly report an offset outside +/- 0.5.
                    val position =
                        (index + fraction).coerceIn(
                            0f,
                            (pager.pageCount - 1).coerceAtLeast(0).toFloat(),
                        )
                    val nearest = position.roundToInt()
                    pager.requestScrollToPage(nearest, position - nearest)
                }
            }
    }
    return reelDragged
}


@Composable
internal fun GalleryButton(
    state: ForumState,
    action: () -> Unit,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val liquid = state.settings.bool("liquidGlass")
    if (!liquid) {
        PlainGalleryControl(null, enabled, action) {
            CompositionLocalProvider(LocalContentColor provides Color.White, content = content)
        }
        return
    }
    val density = LocalDensity.current.density
    var pressed by remember { mutableStateOf(false) }
    var target by remember { mutableStateOf(Offset.Zero) }
    var touch by remember { mutableStateOf(Offset(24f, 24f)) }
    val dark = MaterialTheme.colorScheme.surface.luminance() < .5f
    val press by
        animateFloatAsState(
            if (pressed) 1f else 0f,
            spring(
                dampingRatio = if (pressed) .75f else .55f,
                stiffness = if (pressed) 631.655f else 503.551f,
            ),
            label = "gallery-press",
        )
    val drag by
        animateOffsetAsState(
            target,
            spring(
                dampingRatio = if (pressed) .8f else .5f,
                stiffness = if (pressed) 1754.596f else 157.914f,
            ),
            label = "gallery-drag",
        )
    val light by
        animateFloatAsState(
            if (pressed) (if (dark) .14f else .3f) else 0f,
            tween(if (pressed) 150 else 60, easing = CubicBezierEasing(0f, 0f, .58f, 1f)),
            label = "gallery-light",
        )
    val glow by
        animateFloatAsState(
            if (pressed) 1f else 0f,
            spring(
                dampingRatio = if (pressed) .86f else 1f,
                stiffness = if (pressed) 1754.596f else 157.914f,
            ),
            label = "gallery-glow",
        )
    val glowRadius by
        animateFloatAsState(
            if (pressed) 1f else 1.2f,
            spring(
                dampingRatio = if (pressed) .86f else 1f,
                stiffness = if (pressed) 1754.596f else 157.914f,
            ),
            label = "gallery-glow-radius",
        )
    Box(
        Modifier.size(48.dp)
            .pointerInput(liquid, enabled) {
                if (!liquid || !enabled) return@pointerInput
                awaitEachGesture {
                    val down =
                        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    pressed = true
                    touch = down.position / density
                    try {
                        do {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            val pointer = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!pointer.pressed) break
                            val point = pointer.position / density
                            if ((point - touch).getDistanceSquared() >= 9f) touch = point
                            val delta = (pointer.position - down.position) / density
                            target = delta / (1f + delta.getDistance() * .01f)
                        } while (true)
                    } finally {
                        pressed = false
                        target = Offset.Zero
                    }
                }
            }
            .graphicsLayer {
                if (liquid) {
                    val (scale, translation) = galleryButtonTransform(drag, press)
                    scaleX = scale.x
                    scaleY = scale.y
                    translationX = translation.x * density
                    translationY = translation.y * density
                    alpha = if (enabled) 1f else .5f
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        if (liquid) {
            val (scale, shift) = galleryButtonTransform(drag, press)
            val point =
                Offset(
                    (touch.x - 24 - shift.x) / scale.x + 24,
                    (touch.y - 24 - shift.y) / scale.y + 24,
                )
            GlassBackdrop(
                Modifier.matchParentSize(),
                GlassRenderer.Parameters(
                    density,
                    true,
                    button = true,
                    touchX = point.x * density,
                    touchY = point.y * density,
                    touchIntensity = glow.coerceIn(0f, 1f),
                ),
                { state.error = it },
            )
            Box(Modifier.matchParentSize().background(Color.White.copy(alpha = light), CircleShape))
            if (glow > .001f) {
                val radius = 48f * 1.6f * glowRadius
                Box(Modifier.matchParentSize().clip(CircleShape)) {
                    Box(
                        Modifier.wrapContentSize(Alignment.TopStart, unbounded = true)
                            .offset((point.x - radius).dp, (point.y - radius).dp)
                            .requiredSize((radius * 2).dp)
                            .dropShadow(
                                CircleShape,
                                Shadow(
                                    // Android's radius maps to sigma; Flutter supplied sigma 16
                                    // directly.
                                    radius = ((16f * density - .5f) / .57735f / density).dp,
                                    brush =
                                        Brush.radialGradient(
                                            listOf(Color(0x20FFFFFF), Color.Transparent),
                                            radius = radius * density,
                                        ),
                                    alpha = glow.coerceIn(0f, 1f),
                                    blendMode = BlendMode.Plus,
                                ),
                            )
                    )
                }
            }
        }
        IconButton(onClick = action, enabled = enabled, modifier = Modifier.fillMaxSize()) {
            CompositionLocalProvider(LocalContentColor provides Color.White) { content() }
        }
    }
}

internal fun galleryButtonTransform(drag: Offset, press: Float): Pair<Offset, Offset> {
    val stretch = drag * .8f
    val relative = Offset(abs(stretch.x) / 48f, abs(stretch.y) / 48f)
    val scale =
        Offset(
            (1 + (relative.x * .8f).coerceAtMost(.3f)) *
                (1 - (relative.y * .3f).coerceAtMost(.15f)),
            (1 + (relative.y * .8f).coerceAtMost(.3f)) * (1 - (relative.x * .3f).coerceAtMost(.15f)),
        )
    fun pivotDelta(value: Float): Float {
        val t = (value / 20f).coerceIn(-1f, 1f)
        return -24f * t * abs(t) * (3 - 2 * abs(t))
    }
    val pressScale = 1 + press * 17f / 48f
    return scale * pressScale to
        Offset(
            (pivotDelta(stretch.x) * (1 - scale.x) + scale.x * stretch.x * .15f) * pressScale,
            (pivotDelta(stretch.y) * (1 - scale.y) + scale.y * stretch.y * .15f) * pressScale,
        )
}

@Composable
fun VideoDialog(url: String, state: ForumState, author: String, onClose: () -> Unit) {
    var player by remember { mutableStateOf<MediaPlayer?>(null) }
    var media by remember { mutableStateOf<MediaPlayer?>(null) }
    var error by remember { mutableStateOf("") }
    var playing by remember { mutableStateOf(false) }
    var position by remember { mutableIntStateOf(0) }
    var duration by remember { mutableIntStateOf(0) }
    var buffered by remember { mutableFloatStateOf(0f) }
    var speed by remember { mutableFloatStateOf(1f) }
    var speeds by remember { mutableStateOf(false) }
    var retry by remember { mutableIntStateOf(0) }
    var ratio by remember { mutableFloatStateOf(16f / 9f) }
    val save = mediaSaver(state, author)
    val scopeForVideoNotice = rememberCoroutineScope()
    val backdrop = rememberBackdrop(Color.Black)
    val owner = LocalLifecycleOwner.current
    val context = LocalContext.current
    val audio = remember {
        context.getSystemService(android.content.Context.AUDIO_SERVICE)
            as android.media.AudioManager
    }
    var resumeAfterFocus by remember { mutableStateOf(false) }
    val focus = remember {
        android.media.AudioManager.OnAudioFocusChangeListener { change ->
            if (change == android.media.AudioManager.AUDIOFOCUS_GAIN) {
                if (
                    resumeAfterFocus &&
                        owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
                ) {
                    media?.let {
                        runCatching {
                            it.start()
                            playing = true
                        }
                    }
                }
                resumeAfterFocus = false
            } else {
                resumeAfterFocus =
                    playing && change == android.media.AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
                media?.let { runCatching { it.pause() } }
                playing = false
            }
        }
    }
    @Suppress("DEPRECATION")
    fun startPlayback() {
        if (
            audio.requestAudioFocus(
                focus,
                android.media.AudioManager.STREAM_MUSIC,
                android.media.AudioManager.AUDIOFOCUS_GAIN,
            ) == android.media.AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        ) {
            media?.start()
            playing = media != null
        }
    }
    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                resumeAfterFocus = false
                media?.let { runCatching { it.pause() } }
                playing = false
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose {
            owner.lifecycle.removeObserver(observer)
            audio.abandonAudioFocus(focus)
            player?.release()
        }
    }
    LaunchedEffect(media) {
        while (true) {
            media?.let { active ->
                runCatching {
                    position = active.currentPosition
                    duration = active.duration.coerceAtLeast(0)
                    playing = active.isPlaying
                }
            }
            delay(500)
        }
    }
    Dialog(
        onDismissRequest = onClose,
        properties =
            DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        MediaWindow()
        CompositionLocalProvider(LocalBackdrop provides backdrop) {
            Surface(Modifier.fillMaxSize(), color = Color.Black) {
                Box {
                    Box(
                        Modifier.matchParentSize().captureBackdrop(backdrop),
                        contentAlignment = Alignment.Center,
                    ) {
                        key(retry) {
                            AndroidView(
                                modifier = Modifier.fillMaxWidth().aspectRatio(ratio),
                                factory = { context ->
                                    TextureView(context).apply {
                                        surfaceTextureListener =
                                            object : TextureView.SurfaceTextureListener {
                                                private var surface: Surface? = null
                                                private var active: MediaPlayer? = null

                                                override fun onSurfaceTextureAvailable(
                                                    texture: SurfaceTexture,
                                                    width: Int,
                                                    height: Int,
                                                ) {
                                                    val output = Surface(texture)
                                                    surface = output
                                                    val created = MediaPlayer()
                                                    active = created
                                                    player = created
                                                    try {
                                                        created.setSurface(output)
                                                        created.setAudioAttributes(
                                                            android.media.AudioAttributes.Builder()
                                                                .setContentType(
                                                                    android.media.AudioAttributes
                                                                        .CONTENT_TYPE_MOVIE
                                                                )
                                                                .setUsage(
                                                                    android.media.AudioAttributes
                                                                        .USAGE_MEDIA
                                                                )
                                                                .build()
                                                        )
                                                        created.setOnPreparedListener {
                                                            if (active !== it)
                                                                return@setOnPreparedListener
                                                            media = it
                                                            duration = it.duration
                                                            if (
                                                                it.videoWidth > 0 &&
                                                                    it.videoHeight > 0
                                                            )
                                                                ratio =
                                                                    it.videoWidth.toFloat() /
                                                                        it.videoHeight
                                                            if (position > 0) it.seekTo(position)
                                                            if (
                                                                owner.lifecycle.currentState
                                                                    .isAtLeast(
                                                                        Lifecycle.State.STARTED
                                                                    )
                                                            ) {
                                                                startPlayback()
                                                            }
                                                        }
                                                        created.setOnBufferingUpdateListener {
                                                            _,
                                                            percent ->
                                                            buffered =
                                                                percent.coerceIn(0, 100) / 100f
                                                        }
                                                        created.setOnCompletionListener {
                                                            playing = false
                                                        }
                                                        created.setOnErrorListener { _, _, _ ->
                                                            error = "视频加载失败或格式不受支持"
                                                            media = null
                                                            playing = false
                                                            true
                                                        }
                                                        val headers =
                                                            if (
                                                                java.net.URI(url).host in
                                                                    setOf(
                                                                        "bbs.binmt.cc",
                                                                        "cdn.binmt.cc",
                                                                    )
                                                            )
                                                                mapOf(
                                                                    "User-Agent" to USER_AGENT,
                                                                    "Referer" to "$ORIGIN/",
                                                                )
                                                            else emptyMap()
                                                        created.setDataSource(
                                                            context,
                                                            Uri.parse(url),
                                                            headers,
                                                        )
                                                        created.prepareAsync()
                                                    } catch (_: Exception) {
                                                        error = "视频加载失败或格式不受支持"
                                                    }
                                                }

                                                override fun onSurfaceTextureSizeChanged(
                                                    texture: SurfaceTexture,
                                                    width: Int,
                                                    height: Int,
                                                ) {}

                                                override fun onSurfaceTextureUpdated(
                                                    texture: SurfaceTexture
                                                ) {
                                                    backdrop.frames.tryEmit(Unit)
                                                }

                                                override fun onSurfaceTextureDestroyed(
                                                    texture: SurfaceTexture
                                                ): Boolean {
                                                    if (player === active) {
                                                        media = null
                                                        player = null
                                                        playing = false
                                                    }
                                                    active?.release()
                                                    active = null
                                                    surface?.release()
                                                    surface = null
                                                    return true
                                                }
                                            }
                                    }
                                },
                            )
                        }
                    }
                    ReviewVideoTop(Modifier.align(Alignment.TopCenter), "论坛视频", close = onClose) {
                        if (StorageRules.videoExtension(url) != null) {
                            if (save.busy) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                            ReviewVideoAction(if (save.busy) "close" else "download", if (save.busy) "取消保存" else "保存视频") {
                                if (save.busy) save.cancel() else save.start(url, true)
                            }
                        }
                    }
                    if (media == null && error.isEmpty())
                        CircularProgressIndicator(Modifier.align(Alignment.Center))
                    if (error.isNotEmpty())
                        Column(
                            Modifier.align(Alignment.Center),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Icon(
                                Icons.Outlined.ErrorOutline,
                                null,
                                Modifier.size(48.dp),
                                tint = Color.White.copy(alpha = .7f),
                            )
                            Spacer(Modifier.height(12.dp))
                            Text(error, color = Color.White.copy(alpha = .7f))
                            Spacer(Modifier.height(16.dp))
                            FilledTonalButton(
                                onClick = {
                                    media = null
                                    position = 0
                                    buffered = 0f
                                    speed = 1f
                                    error = ""
                                    retry++
                                }
                            ) {
                                Text("重试")
                            }
                        }
                    ReviewVideoBottom(Modifier.align(Alignment.BottomCenter), position.toLong(), duration.toLong(),
                        (duration * buffered).toLong(), playing, speed, enabled = media != null && error.isEmpty(),
                        onPlay = {
                            if (playing) { media?.pause(); playing = false; resumeAfterFocus = false } else startPlayback()
                        }, onSpeed = { speeds = true }, onSeek = { media?.seekTo(it.toInt()); position = it.toInt() })
                    if (speeds) ReviewVideoChoices("播放倍速", standardVideoSpeeds.map { "${it}X" }, "${speed}X", { speeds = false }) {
                        val requested = it.removeSuffix("X").toFloat()
                        val active = media ?: return@ReviewVideoChoices
                        val wasPlaying = playing
                        runCatching {
                            active.playbackParams = active.playbackParams.setSpeed(requested)
                            if (!wasPlaying) active.pause()
                            speed = requested
                        }.onFailure { scopeForVideoNotice.launch { save.snackbar.showSnackbar("当前视频解码器不支持该倍速") } }
                    }
                    SnackbarHost(
                        save.snackbar,
                        Modifier.align(Alignment.BottomCenter).navigationBarsPadding(),
                    )
                }
            }
        }
    }
}
