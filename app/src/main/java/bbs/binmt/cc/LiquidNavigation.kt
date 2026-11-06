@file:OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)

package bbs.binmt.cc

import android.os.Build
import android.util.Log
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.VelocityTracker
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.input.key.*
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlin.math.*
import kotlinx.coroutines.*

private val tabLabels = listOf("首页", "发现", "发帖", "消息", "我的")
private val tabIcons =
    listOf(
        Icons.Outlined.Home,
        Icons.Outlined.Search,
        Icons.Outlined.Add,
        Icons.Outlined.MailOutline,
        Icons.Outlined.PersonOutline,
    )
private val activeTabIcons =
    listOf(
        Icons.Filled.Home,
        Icons.Outlined.Search,
        Icons.Outlined.Add,
        Icons.Filled.Email,
        Icons.Filled.Person,
    )

@Composable
internal fun navigationGlassBottomPadding(): Dp =
    maxOf(21.dp, WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding())

internal fun navigationGlassBar(size: Size, density: Float) =
    Rect(20 * density, 15 * density, size.width - 20 * density, size.height - 15 * density)

internal fun navigationGlassLens(
    size: Size,
    density: Float,
    lens: Float,
    pressed: Float,
    velocity: Float,
): Rect {
    val slot = (navigationGlassBar(size, density).width - 8 * density) / tabLabels.size
    val cx = 24 * density + slot * (lens + .5f)
    val jelly = jellyScale(velocity, pressed)
    val width = (slot * (1 + .06f * pressed) + 24 * density * pressed) * jelly[0]
    val height = (48 * density * (1 + .06f * pressed) + 16 * density * pressed) * jelly[1]
    return Rect(
        cx - width / 2,
        (size.height - height) / 2,
        cx + width / 2,
        (size.height + height) / 2,
    )
}

@Composable
internal fun navigationGlassMotion(
    selected: Int,
    touching: Boolean,
    dragging: Boolean,
    target: Float,
    longPressed: Boolean,
): Pair<Float, Float> {
    val held = touching && dragging
    val water = touching && longPressed
    val lens by
        animateFloatAsState(
            if (held) target else selected.toFloat(),
            glassSpring(if (held) 150 else 350, if (held) .14f else .15f),
            label = "glass-position",
        )
    val press by
        animateFloatAsState(
            if (water) 1f else 0f,
            if (water) glassSpring(300, .15f) else tween(240, easing = FastOutSlowInEasing),
            label = "glass-thickness",
        )
    return lens to press.coerceIn(0f, 1f)
}

@Composable
internal fun LiquidNavigation(state: ForumState, modifier: Modifier = Modifier) {
    val backdrop = LocalBackdrop.current ?: return
    val density = LocalDensity.current.density
    val scope = rememberCoroutineScope()
    val colors = MaterialTheme.colorScheme
    val dark = backdrop.background.luminance() < .5f
    var gpuFailed by remember { mutableStateOf(false) }
    val gpu = Build.VERSION.SDK_INT >= 33 && !gpuFailed
    var touching by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf(false) }
    var target by remember { mutableFloatStateOf(state.tab.toFloat()) }
    var longPressed by remember { mutableStateOf(false) }
    val (lens, press) = navigationGlassMotion(state.tab, touching, dragging, target, longPressed)
    var origin by remember { mutableStateOf(Offset.Zero) }
    var vertical by remember { mutableStateOf(false) }
    var velocity by remember { mutableStateOf<VelocityTracker?>(null) }
    var hold by remember { mutableStateOf<Job?>(null) }

    DisposableEffect(Unit) {
        onDispose {
            hold?.cancel()

            velocity?.recycle()
        }
    }

    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal))
            .padding(bottom = navigationGlassBottomPadding()),
        contentAlignment = Alignment.Center,
    ) {
        val barWidth = (maxWidth - 40.dp).coerceAtMost(440.dp)
        if (barWidth <= 8.dp) return@BoxWithConstraints
        val normal = rememberGraphicsLayer()
        val selected = rememberGraphicsLayer()
        val normalColor = if (dark) Color.White else colors.onSurfaceVariant
        Box(Modifier.width(barWidth).height(56.dp)) {
            Box(Modifier.requiredSize(barWidth + 40.dp, 86.dp).align(Alignment.Center)) {
                if (!dark)
                    Box(
                        Modifier.align(Alignment.Center)
                            .size(barWidth, 56.dp)
                            .glassEdgeShadow(
                                GlassShadow(4.4f, 1.1f, Color.Black.copy(alpha = .033f)),
                                GlassShadow(1.1f, .55f, Color.Black.copy(alpha = .011f)),
                            )
                    )
                GlassTabLabels(barWidth, tabIcons, normalColor, normal)
                GlassTabLabels(barWidth, activeTabIcons, colors.primary, selected)
                if (gpu)
                    GlassNavigationGpu(
                        backdrop,
                        normal,
                        selected,
                        lens,
                        press,
                        dark,
                        colors.surfaceContainerHigh,
                        Modifier.fillMaxSize(),
                        onFailure = { gpuFailed = true },
                    )
                else
                    NavigationGlassCompatibility(
                        backdrop,
                        normal,
                        selected,
                        normalColor,
                        colors.primary,
                        colors.surfaceContainerHigh,
                        lens,
                        press,
                        dark,
                    )
            }
            val barPixels = barWidth.value * density
            val slot = (barPixels - 8 * density) / tabLabels.size
            fun slotAt(x: Float) = ((x - 4 * density) / slot).coerceIn(0f, tabLabels.size.toFloat())
            Row(
                Modifier.fillMaxSize()
                    .pointerInteropFilter { event ->
                        val x = event.x
                        val y = event.y
                        when (event.actionMasked) {
                            MotionEvent.ACTION_DOWN -> {

                                dragging = false
                                longPressed = false
                                hold?.cancel()
                                velocity?.recycle()
                                velocity = VelocityTracker.obtain().also { it.addMovement(event) }
                                origin = Offset(x, y)
                                vertical = false
                                touching = true
                                target =
                                    (slotAt(x) - .5f).coerceIn(0f, tabLabels.lastIndex.toFloat())
                                hold =
                                    scope.launch {
                                        delay(220)
                                        longPressed = true
                                        dragging = true
                                        state.haptic(HapticFeedbackConstants.LONG_PRESS)
                                    }
                            }
                            MotionEvent.ACTION_MOVE ->
                                if (touching) {
                                    velocity?.addMovement(event)
                                    val dx = x - origin.x
                                    val dy = y - origin.y
                                    if (hypot(dx, dy) > 18 * density) {
                                        hold?.cancel()
                                        if (!vertical && abs(dx) > abs(dy)) dragging = true
                                        else if (!dragging) vertical = true
                                    }
                                    if (!vertical)
                                        target =
                                            (slotAt(x) - .5f).coerceIn(
                                                0f,
                                                tabLabels.lastIndex.toFloat(),
                                            )
                                }
                            MotionEvent.ACTION_UP,
                            MotionEvent.ACTION_CANCEL,
                            MotionEvent.ACTION_POINTER_DOWN -> {
                                hold?.cancel()
                                if (
                                    event.actionMasked == MotionEvent.ACTION_UP &&
                                        touching &&
                                        !vertical
                                ) {
                                    velocity?.addMovement(event)
                                    velocity?.computeCurrentVelocity(1000)
                                    val speed = (velocity?.xVelocity ?: 0f) / density
                                    val cell = slotAt(x).toInt().coerceAtMost(tabLabels.lastIndex)
                                    val chosen =
                                        if (dragging && abs(speed) >= 800 && cell == state.tab)
                                            (cell + if (speed > 0) 1 else -1).coerceIn(
                                                tabLabels.indices
                                            )
                                        else cell
                                    if (!dragging || chosen != state.tab) {
                                        state.selectTab(chosen, withFeedback = !longPressed)
                                    }
                                }
                                touching = false
                                velocity?.recycle()
                                velocity = null

                                dragging = false
                                longPressed = false
                            }
                        }
                        true
                    }
                    .padding(horizontal = 4.dp)
            ) {
                tabLabels.forEachIndexed { index, label ->
                    var focused by remember { mutableStateOf(false) }
                    Box(
                        Modifier.weight(1f)
                            .fillMaxHeight()
                            .border(
                                2.dp,
                                if (focused) colors.primary else Color.Transparent,
                                CircleShape,
                            )
                            .onFocusChanged { focused = it.isFocused }
                            .onKeyEvent {
                                if (
                                    it.type == KeyEventType.KeyUp &&
                                        (it.key == Key.Enter ||
                                            it.key == Key.Spacebar ||
                                            it.key == Key.DirectionCenter)
                                ) {
                                    state.selectTab(index)
                                    true
                                } else false
                            }
                            .focusable()
                            .semantics {
                                contentDescription = label
                                role = Role.Tab
                                this.selected = state.tab == index
                                onClick {
                                    state.selectTab(index)
                                    true
                                }
                            }
                    )
                }
            }
        }
    }
}

@Composable
private fun NavigationGlassCompatibility(
    backdrop: Backdrop,
    normal: GraphicsLayer,
    selected: GraphicsLayer,
    normalColor: Color,
    selectedColor: Color,
    fallbackColor: Color,
    lens: Float,
    pressed: Float,
    dark: Boolean,
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val owner = LocalLifecycleOwner.current
    var failed by remember { mutableStateOf(false) }
    val view = remember(context, failed) { if (failed) null else NavigationGlassView(context) }
    val crop = rememberGraphicsLayer()
    val transform = remember { Matrix() }
    var visible by remember(view) { mutableStateOf(false) }
    var coordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var dimensions by remember { mutableStateOf(IntSize.Zero) }
    val latest by rememberUpdatedState(CompatibilityMotion(lens, pressed, dark))

    if (!visible)
        Canvas(Modifier.fillMaxSize()) {
            drawNavigationGlassFallback(
                navigationGlassBar(size, density.density),
                navigationGlassLens(size, density.density, lens, 0f, 0f),
                dark,
                fallbackColor,
                normal,
                selected,
            )
        }
    if (view == null) return
    AndroidView(
        factory = { view },
        modifier =
            Modifier.fillMaxSize().onGloballyPositioned {
                coordinates = it
                dimensions = it.size
            },
    )
    DisposableEffect(view) {
        view.failure = {
            Log.w("NavigationGlass", it)
            failed = true
        }
        onDispose { view.close() }
    }
    LaunchedEffect(
        view,
        backdrop,
        dimensions,
        density,
        direction,
        normalColor,
        selectedColor,
        owner,
    ) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            var lastFrame = 0L
            var previousLens = latest.lens
            var previousVelocity = 0f
            var previousRevision = -1L
            var previousMotion: CompatibilityMotion? = null
            var previousTransform = FloatArray(0)
            var generation = -1
            var lastRead = 0L
            while (isActive && !failed) {
                val frame = withFrameNanos { it }
                val values = latest
                val speed =
                    if (values.pressed <= .001f || lastFrame == 0L) 0f
                    else (values.lens - previousLens) * 1_000_000_000f / (frame - lastFrame)
                lastFrame = frame
                previousLens = values.lens
                if (!view.ready) {
                    visible = false
                    generation = -1
                    continue
                }
                val source = backdrop.coordinates
                val target = coordinates
                if (
                    source?.isAttached != true ||
                        target?.isAttached != true ||
                        dimensions == IntSize.Zero ||
                        normal.size != dimensions ||
                        selected.size != dimensions
                )
                    continue
                target.transformFrom(source, transform)
                val surface = view.surfaceGeneration
                val readLabels = surface != generation
                val revision = backdrop.revision
                val readBackground =
                    readLabels ||
                        !transform.values.contentEquals(previousTransform) ||
                        (revision != previousRevision && frame - lastRead >= 32_000_000L)
                if (!readBackground && previousMotion == values && previousVelocity == speed)
                    continue
                var background: android.graphics.Bitmap? = null
                var labels: android.graphics.Bitmap? = null
                var activeLabels: android.graphics.Bitmap? = null
                try {
                    if (readBackground) {
                        val sampled =
                            IntSize((dimensions.width + 1) / 2, (dimensions.height + 1) / 2)
                        crop.record(density, direction, sampled) {
                            drawRect(backdrop.background)
                            scale(
                                sampled.width.toFloat() / dimensions.width,
                                sampled.height.toFloat() / dimensions.height,
                                Offset.Zero,
                            ) {
                                withTransform({ transform(transform) }) {
                                    drawLayer(backdrop.layer)
                                }
                            }
                        }
                        lastRead = frame
                        background = crop.readNavigationGlassBitmap()
                    }
                    if (readLabels) {
                        labels = normal.readNavigationGlassBitmap()
                        activeLabels = selected.readNavigationGlassBitmap()
                    }
                    val done = CompletableDeferred<Boolean>()
                    view.render(
                        background,
                        labels,
                        values.lens,
                        values.pressed,
                        values.dark,
                        density.density,
                        lensVelocity = speed,
                        selectedLabels = activeLabels,
                        generation = surface,
                        outputSize = dimensions,
                    ) {
                        done.complete(it)
                    }
                    background = null
                    labels = null
                    activeLabels = null
                    visible = done.await()
                    generation = if (visible) surface else -1
                    if (visible) {
                        if (readBackground) {
                            previousRevision = revision
                            previousTransform = transform.values.copyOf()
                        }
                        previousVelocity = speed
                        previousMotion = values
                    }
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    Log.w("NavigationGlass", "Cannot capture backdrop", e)
                    failed = true
                } finally {
                    background?.recycle()
                    labels?.recycle()
                    activeLabels?.recycle()
                }
            }
        }
    }
}

private data class CompatibilityMotion(val lens: Float, val pressed: Float, val dark: Boolean)

private suspend fun GraphicsLayer.readNavigationGlassBitmap(): android.graphics.Bitmap {
    val bitmap = toImageBitmap().asAndroidBitmap()
    if (bitmap.config == android.graphics.Bitmap.Config.ARGB_8888) return bitmap
    return try {
        withContext(Dispatchers.Default) {
            checkNotNull(bitmap.copy(android.graphics.Bitmap.Config.ARGB_8888, false))
        }
    } finally {
        bitmap.recycle()
    }
}

internal fun DrawScope.drawNavigationGlassFallback(
    bar: Rect,
    pill: Rect,
    dark: Boolean,
    color: Color,
    labels: GraphicsLayer,
    activeLabels: GraphicsLayer,
) {
    drawRoundRect(color, bar.topLeft, bar.size, CornerRadius(bar.height / 2))
    drawRoundRect(
        (if (dark) Color.White else Color.Black).copy(alpha = 38f / 255),
        pill.topLeft,
        pill.size,
        CornerRadius(minOf(pill.width, pill.height) / 2),
    )
    val mask =
        Path().apply {
            addRoundRect(RoundRect(pill, CornerRadius(minOf(pill.width, pill.height) / 2)))
        }
    clipPath(mask, ClipOp.Difference) { drawLayer(labels) }
    clipPath(mask) { drawLayer(activeLabels) }
}

@Composable
private fun GlassTabLabels(
    barWidth: Dp,
    icons: List<androidx.compose.ui.graphics.vector.ImageVector>,
    color: Color,
    layer: GraphicsLayer,
) {
    Box(
        Modifier.fillMaxSize()
            .drawWithContent { layer.record { this@drawWithContent.drawContent() } }
            .clearAndSetSemantics {}
    ) {
        Row(Modifier.align(Alignment.Center).size(barWidth, 56.dp).padding(horizontal = 4.dp)) {
            tabLabels.forEachIndexed { index, name ->
                Column(
                    Modifier.weight(1f).fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(icons[index], null, Modifier.size(24.dp), tint = color)
                    Spacer(Modifier.height(2.dp))
                    Text(
                        name,
                        fontSize = 10.5.sp,
                        lineHeight = 11.55.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        color = color,
                    )
                }
            }
        }
    }
}
