package bbs.binmt.cc

import android.graphics.Bitmap
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

class Backdrop(val layer: GraphicsLayer, val background: Color) {
    var origin = Offset.Zero
    var coordinates: LayoutCoordinates? = null
    var revision = 0L
        private set

    val frames =
        MutableSharedFlow<Unit>(
            replay = 1,
            extraBufferCapacity = 1,
            onBufferOverflow = BufferOverflow.DROP_OLDEST,
        )

    fun recorded() {
        revision++
        frames.tryEmit(Unit)
    }
}

val LocalBackdrop = staticCompositionLocalOf<Backdrop?> { null }

// Flutter converts radius to sigma before density scaling; Android converts physical radius.
internal fun flutterShadowRadius(radius: Float, density: Float) =
    (radius + (.5f - .5f / density) / .57735f).dp

internal class GlassLabels(val normal: GraphicsLayer, val selected: GraphicsLayer) {
    private var recorded = 0
    val ready = MutableSharedFlow<Unit>(replay = 1)

    fun record(selected: Boolean) {
        if (recorded == 3) return
        recorded = recorded or if (selected) 2 else 1
        if (recorded == 3) ready.tryEmit(Unit)
    }
}

@Composable
fun rememberBackdrop(background: Color): Backdrop {
    val layer = rememberGraphicsLayer()
    return remember(layer, background) { Backdrop(layer, background) }
}

fun Modifier.captureBackdrop(backdrop: Backdrop) =
    graphicsLayer()
        .onGloballyPositioned {
            backdrop.origin = it.positionInRoot()
            backdrop.coordinates = it
        }
        .drawWithContent {
            backdrop.layer.record { this@drawWithContent.drawContent() }
            drawLayer(backdrop.layer)
            backdrop.recorded()
        }

@Composable
internal fun FrostedBackdrop(modifier: Modifier, dark: Boolean, blurDp: Float = 20f) {
    if (Build.VERSION.SDK_INT < 31) {
        BoxWithConstraints(modifier.clipToBounds()) {
            GlassBackdrop(
                Modifier.align(Alignment.Center)
                    .requiredSize(maxWidth + (blurDp * 6).dp, maxHeight + (blurDp * 6).dp),
                GlassRenderer.Parameters(
                    LocalDensity.current.density,
                    dark,
                    blurOnly = true,
                    blurDp = blurDp,
                ),
            )
        }
        return
    }
    val backdrop = LocalBackdrop.current ?: return
    val blurred = rememberGraphicsLayer()
    val transform = remember { Matrix() }
    var coordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    LaunchedEffect(backdrop) { backdrop.frames.collect { revision++ } }
    Canvas(modifier.graphicsLayer().onGloballyPositioned { coordinates = it }) {
        revision
        val source = backdrop.coordinates
        val target = coordinates
        if (source?.isAttached != true || target?.isAttached != true) return@Canvas
        target.transformFrom(source, transform)
        val sigma = blurDp.dp.toPx()
        val margin = (sigma * 3).roundToInt()
        // Sample outside the toolbar before blurring, then clip; otherwise the lower edge smears.
        blurred.record(
            size =
                IntSize(size.width.roundToInt() + margin * 2, size.height.roundToInt() + margin * 2)
        ) {
            drawRect(backdrop.background)
            withTransform({
                translate(margin.toFloat(), margin.toFloat())
                transform(transform)
            }) {
                drawLayer(backdrop.layer)
            }
        }
        blurred.renderEffect = BlurEffect(sigma, sigma, TileMode.Clamp)
        clipRect { translate(-margin.toFloat(), -margin.toFloat()) { drawLayer(blurred) } }
    }
}

@Composable
internal fun GlassBackdrop(
    modifier: Modifier,
    parameters: GlassRenderer.Parameters,
    onFailure: (String) -> Unit = {},
    onFrame: (Boolean) -> Unit = {},
    labels: GlassLabels? = null,
    onLabelFrame: (Boolean) -> Unit = {},
) {
    val backdrop = LocalBackdrop.current ?: return
    val cropped = rememberGraphicsLayer()
    val labelCapture = rememberGraphicsLayer()
    val transform = remember { Matrix() }
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    var view by remember { mutableStateOf<GlassRenderer?>(null) }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var coordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var size by remember { mutableStateOf(IntSize.Zero) }
    var surfaceRevision by remember { mutableIntStateOf(0) }
    val failure by rememberUpdatedState(onFailure)
    val frame by rememberUpdatedState(onFrame)
    val labelFrame by rememberUpdatedState(onLabelFrame)
    val currentBackdrop by rememberUpdatedState(backdrop)
    AndroidView(
        modifier =
            modifier.onGloballyPositioned {
                coordinates = it
                origin = it.positionInRoot()
                size = it.size
                backdrop.frames.tryEmit(Unit)
            },
        factory = { context ->
            GlassRenderer(context).also {
                view = it
                it.failure = { message -> failure(message) }
                it.ready = { currentBackdrop.frames.tryEmit(Unit) }
                it.frame = { ready ->
                    if (!ready) surfaceRevision++
                    frame(ready)
                }
                it.labelFrame = { labelFrame(it) }
            }
        },
        update = { it.update(parameters) },
    )
    LaunchedEffect(backdrop, view, size, origin) {
        backdrop.frames.collect {
            val renderer = view
            if (renderer != null && renderer.isAvailable && size.width > 0 && size.height > 0) {
                try {
                    withFrameNanos {}
                    val source = backdrop.coordinates
                    val target = coordinates
                    if (source?.isAttached != true || target?.isAttached != true) return@collect
                    target.transformFrom(source, transform)
                    cropped.record(density, direction, size) {
                        drawRect(backdrop.background)
                        withTransform({ transform(transform) }) { drawLayer(backdrop.layer) }
                    }
                    val image = cropped.toImageBitmap().asAndroidBitmap()
                    val bitmap =
                        try {
                            withContext(Dispatchers.Default) {
                                image.copy(Bitmap.Config.ARGB_8888, false)
                            }
                        } finally {
                            image.recycle()
                        }
                    if (bitmap != null) renderer.image(bitmap, backdrop.layer.size)
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (e: Exception) {
                    failure(e.message ?: "背景捕获失败")
                }
            }
        }
    }
    LaunchedEffect(view, labels, size, surfaceRevision) {
        val renderer = view ?: return@LaunchedEffect
        val glyphs = labels ?: return@LaunchedEffect
        if (size == IntSize.Zero) return@LaunchedEffect
        glyphs.ready.first()
        try {
            val area = glyphs.normal.size
            if (area.width <= 0 || area.height <= 0) return@LaunchedEffect
            labelCapture.record(density, direction, IntSize(area.width, area.height * 2)) {
                drawLayer(glyphs.normal)
                translate(top = area.height.toFloat()) { drawLayer(glyphs.selected) }
            }
            labelCapture
                .toImageBitmap()
                .asAndroidBitmap()
                .copy(Bitmap.Config.ARGB_8888, false)
                ?.let(renderer::labels)
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (failure: Exception) {
            // The Compose labels stay visible if the device cannot capture a layer.
            labelFrame(false)
        }
    }
    DisposableEffect(view) {
        val renderer = view
        onDispose { renderer?.release() }
    }
}
