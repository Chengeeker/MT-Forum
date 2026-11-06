package bbs.binmt.cc

import androidx.activity.BackEventCompat
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.Flow

class RouteMotion(
    val layer: GraphicsLayer,
    private val scope: CoroutineScope,
    val reduced: () -> Boolean,
) {
    var previous by mutableStateOf<ImageBitmap?>(null)
    var reverse by mutableStateOf(false)
    var width by mutableIntStateOf(0)
    val progress = Animatable(1f)
    private var job: Job? = null

    private suspend fun capture() =
        try {
            layer.toImageBitmap()
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Exception) {
            null
        }

    fun navigate(direction: Int, action: () -> Unit) {
        if (direction == 0 || reduced() || width == 0) {
            action()
            return
        }
        val oldJob = job
        oldJob?.cancel()
        job =
            scope.launch {
                oldJob?.join()
                val image = capture()
                if (image == null) {
                    action()
                    return@launch
                }
                reverse = direction < 0
                progress.snapTo(0f)
                previous = image
                action()
                try {
                    progress.animateTo(
                        1f,
                        tween(
                            if (reverse) 220 else 320,
                            easing =
                                if (reverse) CubicBezierEasing(.55f, .055f, .675f, .19f)
                                else CubicBezierEasing(.215f, .61f, .355f, 1f),
                        ),
                    )
                } finally {
                    previous = null
                }
            }
    }

    suspend fun predictive(state: ForumState, events: Flow<BackEventCompat>) {
        if (reduced()) {
            events.collect {}
            state.back()
            return
        }
        job?.cancelAndJoin()
        val image = capture()
        if (image == null || !state.previewBack()) {
            events.collect {}
            state.back()
            return
        }
        reverse = true
        progress.snapTo(0f)
        previous = image
        try {
            events.collect { progress.snapTo(it.progress) }
            progress.animateTo(
                1f,
                tween(
                    ((1 - progress.value) * 220).toInt(),
                    easing = CubicBezierEasing(.55f, .055f, .675f, .19f),
                ),
            )
            state.finishBackPreview(true)
        } catch (cancel: CancellationException) {
            withContext(NonCancellable) {
                progress.animateTo(0f, tween((progress.value * 220).toInt()))
                state.finishBackPreview(false)
            }
        } finally {
            previous = null
        }
    }
}

@Composable
fun rememberRouteMotion(): RouteMotion {
    val layer = rememberGraphicsLayer()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    return remember(layer, scope) {
        RouteMotion(layer, scope) {
            android.provider.Settings.Global.getFloat(
                context.contentResolver,
                android.provider.Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) == 0f
        }
    }
}

@Composable
fun RouteMotionHost(motion: RouteMotion, content: @Composable (Modifier) -> Unit) {
    val direction = if (LocalLayoutDirection.current == LayoutDirection.Rtl) -1 else 1
    Box(Modifier.fillMaxSize()) {
        if (!motion.reverse)
            motion.previous?.let {
                Image(it, null, Modifier.matchParentSize(), contentScale = ContentScale.FillBounds)
            }
        content(
            Modifier.onSizeChanged { motion.width = it.width }
                .graphicsLayer {
                    translationX =
                        if (motion.previous != null && !motion.reverse)
                            (1 - motion.progress.value) * motion.width * direction
                        else 0f
                }
                .drawWithContent {
                    motion.layer.record { this@drawWithContent.drawContent() }
                    drawLayer(motion.layer)
                }
        )
        if (motion.reverse)
            motion.previous?.let {
                Image(
                    it,
                    null,
                    Modifier.matchParentSize().graphicsLayer {
                        translationX = motion.progress.value * motion.width * direction
                    },
                    contentScale = ContentScale.FillBounds,
                )
            }
    }
}
