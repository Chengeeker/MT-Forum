package bbs.binmt.cc

import android.content.Context
import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
import android.view.TextureView
import androidx.compose.ui.unit.IntSize

/** Runs the retained material's geometry and optical passes on GLES 3, including API 24–32. */
class GlassRenderer(context: Context) : TextureView(context), TextureView.SurfaceTextureListener {
    data class Parameters(
        val density: Float,
        val dark: Boolean,
        val selected: Float = 0f,
        val expansion: Float = 0f,
        val blurOnly: Boolean = false,
        val button: Boolean = false,
        val blurDp: Float = 20f,
        val velocity: Float = 0f,
        val touchX: Float = 0f,
        val touchY: Float = 0f,
        val touchIntensity: Float = 0f,
    )

    private val worker = HandlerThread("ForumGlass").apply { start() }
    private val handler = Handler(worker.looper)
    private var display = EGL14.EGL_NO_DISPLAY
    private var eglContext = EGL14.EGL_NO_CONTEXT
    private var surface = EGL14.EGL_NO_SURFACE
    private var geometry = 0
    private var optical = 0
    private var blur = 0
    private var copy = 0
    private var textures = IntArray(6)
    private var framebuffers = IntArray(4)
    private var widthPx = 0
    private var heightPx = 0
    private var parameters = Parameters(resources.displayMetrics.density, false)
    private var hasImage = false
    private var prepared: Parameters? = null
    private var presented = false
    private var labelsPresented = false
    private var hasLabels = false

    private data class Capture(val bitmap: Bitmap, val viewport: IntSize)

    private var viewport = IntSize.Zero
    private val pendingImage = java.util.concurrent.atomic.AtomicReference<Capture?>(null)
    private val pendingLabels = java.util.concurrent.atomic.AtomicReference<Bitmap?>(null)
    private val queued = java.util.concurrent.atomic.AtomicBoolean(false)
    @Volatile private var pendingParameters = parameters
    @Volatile private var closed = false
    var failure: ((String) -> Unit)? = null
    var ready: (() -> Unit)? = null
    var frame: ((Boolean) -> Unit)? = null
    var labelFrame: ((Boolean) -> Unit)? = null

    init {
        isOpaque = false
        surfaceTextureListener = this
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        isClickable = false
    }

    fun update(value: Parameters) {
        if (pendingParameters == value) return
        pendingParameters = value
        enqueue()
    }

    fun image(bitmap: Bitmap, viewport: IntSize) {
        if (closed) {
            bitmap.recycle()
            return
        }
        pendingImage.getAndSet(Capture(bitmap, viewport))?.bitmap?.recycle()
        if (closed) {
            pendingImage.getAndSet(null)?.bitmap?.recycle()
            return
        }
        enqueue()
    }

    fun labels(bitmap: Bitmap) {
        if (closed) {
            bitmap.recycle()
            return
        }
        pendingLabels.getAndSet(bitmap)?.recycle()
        if (closed) pendingLabels.getAndSet(null)?.recycle() else enqueue()
    }

    private fun enqueue() {
        if (closed || !queued.compareAndSet(false, true)) return
        handler.post {
            queued.set(false)
            parameters = pendingParameters
            val capture = pendingImage.getAndSet(null)
            val labels =
                if (surface != EGL14.EGL_NO_SURFACE) pendingLabels.getAndSet(null) else null
            try {
                if (labels != null) {
                    GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textures[5])
                    GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, labels, 0)
                    hasLabels = true
                }
                if (capture != null && surface != EGL14.EGL_NO_SURFACE) {
                    GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textures[0])
                    GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, capture.bitmap, 0)
                    viewport = capture.viewport
                    hasImage = true
                    prepared = null
                }
                renderSafely()
            } finally {
                capture?.bitmap?.recycle()
                labels?.recycle()
            }
        }
    }

    private val glyphShader =
        """
uniform sampler2D uLabelTexture;
uniform vec4 uLabelRect;
uniform float uUseLabels;
vec4 labelAt(vec2 px) {
    if (uUseLabels < 0.5) return vec4(0.0);
    vec2 uv = (px - uLabelRect.xy) / uLabelRect.zw;
    if (any(lessThan(uv, vec2(0))) || any(greaterThan(uv, vec2(1)))) return vec4(0.0);
    vec2 halfSize = uLensRect.zw * 0.5;
    float r = min(halfSize.x, halfSize.y);
    vec2 q = abs(px - uLensRect.xy) - halfSize + r;
    float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float inside = 1.0 - smoothstep(-0.5, 0.5, sd);
    float halfTexel = 0.5 / uLabelRect.w;
    float y = clamp(uv.y, halfTexel, 1.0 - halfTexel) * 0.5;
    return mix(texture(uLabelTexture, vec2(uv.x, y)),
               texture(uLabelTexture, vec2(uv.x, y + 0.5)), inside);
}
"""

    internal fun source(name: String): String {
        fun expand(file: String): String =
            context.assets
                .open("liquid/$file")
                .bufferedReader()
                .use { it.readText() }
                .replace(Regex("(?m)^#include \\\"([^\\\"]+)\\\"")) { expand(it.groupValues[1]) }
                .replace("#include <flutter/runtime_effect.glsl>", "")
        var code =
            expand(name)
                .replace(Regex("#version[^\\n]*"), "")
                .replace(Regex("layout\\(location\\s*=\\s*\\d+\\)\\s*uniform"), "uniform")
                .replace(
                    "smoothstep(smoothing * 0.5, -smoothing * 0.5, sdN)",
                    "(1.0 - smoothstep(-smoothing * 0.5, smoothing * 0.5, sdN))",
                )
        code =
            code.replace(
                "FlutterFragCoord().xy",
                "vec2(gl_FragCoord.x,uViewportHeight-gl_FragCoord.y)",
            )
        if (name.contains("render")) {
            code =
                code
                    .replace(
                        "uniform vec2 uGeometrySize;",
                        "uniform vec2 uGeometrySize;\nuniform vec4 uLensRect;\nuniform float uRestAmount;\nuniform vec2 uBackdropExtent;",
                    )
                    .replace(
                        "min(uGeometrySize.x, uGeometrySize.y)",
                        "min(uLensRect.z, uLensRect.w)",
                    )
                    .replace(
                        "vec2 centered = geometryUV - vec2(0.5);",
                        "vec2 centered = (fragCoord - uLensRect.xy) / uLensRect.zw;",
                    )
                    .replace(
                        "centered * pinchRamp * uPinchStrength * 0.025;",
                        "centered * pinchRamp * uPinchStrength * 0.025 * (uBackdropExtent / uSize);",
                    )
                    .replace(
                        "fragColor    = vec4(finalColor.rgb * alpha, alpha);",
                        """if (uRestAmount > 0.0) {
    vec3 rest = mix(sampleScene(fragCoord / uSize).rgb, uGlassColor.rgb, 38.0 / 255.0);
    vec4 label = labelAt(fragCoord);
    rest = label.rgb + rest * (1.0 - label.a);
    finalColor.rgb = mix(finalColor.rgb, rest, uRestAmount);
}
fragColor = vec4(finalColor.rgb * alpha, alpha);""",
                    )
            code =
                code.replace(
                    "texture(uGeometryTexture, geometryUV)",
                    "texture(uGeometryTexture,vec2(geometryUV.x,1.0-geometryUV.y))",
                )
            code =
                code.replace(Regex("texture\\(uBackgroundTexture, ([^;]+?)\\)")) {
                    "sampleBackground(${it.groupValues[1]})"
                }
            code =
                code.replace(
                    "uniform sampler2D uBackgroundTexture;",
                    """uniform sampler2D uBackgroundTexture;
uniform float uBackgroundFlip;
$glyphShader
vec4 sampleScene(vec2 uv) {
    return texture(uBackgroundTexture,vec2(uv.x,mix(uv.y,1.0-uv.y,uBackgroundFlip)));
}
vec4 sampleBackground(vec2 uv) {
    vec4 label = labelAt(uv * uSize);
    return label + sampleScene(uv) * (1.0 - label.a);
}""",
                )
        }
        return "#version 300 es\nprecision highp float;\nuniform float uViewportHeight;\n" + code
    }

    private fun shader(type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)
        val ok = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, ok, 0)
        check(ok[0] != 0) { GLES30.glGetShaderInfoLog(shader) }
        return shader
    }

    private fun program(fragment: String): Int {
        val vertex =
            shader(
                GLES30.GL_VERTEX_SHADER,
                "#version 300 es\nvoid main(){vec2 p=vec2(gl_VertexID & 1, gl_VertexID >> 1);gl_Position=vec4(2.0*p-1.0,0,1);}",
            )
        val pixel = shader(GLES30.GL_FRAGMENT_SHADER, fragment)
        val program = GLES30.glCreateProgram()
        GLES30.glAttachShader(program, vertex)
        GLES30.glAttachShader(program, pixel)
        GLES30.glLinkProgram(program)
        GLES30.glDeleteShader(vertex)
        GLES30.glDeleteShader(pixel)
        val ok = IntArray(1)
        GLES30.glGetProgramiv(program, GLES30.GL_LINK_STATUS, ok, 0)
        check(ok[0] != 0) { GLES30.glGetProgramInfoLog(program) }
        return program
    }

    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
        handler.post {
            try {
                display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
                check(EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 0))
                val configs = arrayOfNulls<EGLConfig>(1)
                val count = IntArray(1)
                check(
                    EGL14.eglChooseConfig(
                        display,
                        intArrayOf(
                            EGL14.EGL_RED_SIZE,
                            8,
                            EGL14.EGL_GREEN_SIZE,
                            8,
                            EGL14.EGL_BLUE_SIZE,
                            8,
                            EGL14.EGL_ALPHA_SIZE,
                            8,
                            EGL14.EGL_RENDERABLE_TYPE,
                            EGLExt.EGL_OPENGL_ES3_BIT_KHR,
                            EGL14.EGL_SURFACE_TYPE,
                            EGL14.EGL_WINDOW_BIT,
                            EGL14.EGL_NONE,
                        ),
                        0,
                        configs,
                        0,
                        1,
                        count,
                        0,
                    ) && count[0] > 0
                )
                eglContext =
                    EGL14.eglCreateContext(
                        display,
                        configs[0],
                        EGL14.EGL_NO_CONTEXT,
                        intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
                        0,
                    )
                surface =
                    EGL14.eglCreateWindowSurface(
                        display,
                        configs[0],
                        texture,
                        intArrayOf(EGL14.EGL_NONE),
                        0,
                    )
                check(EGL14.eglMakeCurrent(display, surface, surface, eglContext))
                if (!pendingParameters.blurOnly) {
                    geometry = program(source("liquid_glass_geometry_blended.frag"))
                    optical = program(source("liquid_glass_render.frag"))
                }
                val header =
                    "#version 300 es\nprecision highp float;uniform sampler2D image;uniform vec2 size;uniform vec2 stepSize;uniform float flip;out vec4 color;vec4 sampleAt(vec2 p){return texture(image,vec2(p.x,mix(p.y,1.0-p.y,flip)));}\n"
                blur =
                    program(
                        header +
                            "void main(){vec2 uv=vec2(gl_FragCoord.x,size.y-gl_FragCoord.y)/size;vec4 sum=vec4(0);float weights=0.0;for(int i=-6;i<=6;i++){float f=float(i);float w=exp(-f*f/8.0);sum+=sampleAt(uv+f*stepSize/size)*w;weights+=w;}color=sum/weights;}"
                    )
                copy =
                    program(
                        header +
                            "uniform vec4 uLensRect;\n" +
                            glyphShader +
                            """uniform sampler2D scene;
uniform float composite;
void main() {
    vec2 px = vec2(gl_FragCoord.x,size.y-gl_FragCoord.y);
    vec2 uv = px / size;
    color = sampleAt(uv);
    if(composite>0.5) color += texture(scene,uv) * (1.0-color.a);
    vec4 label = labelAt(px);
    color = label + color * (1.0-label.a);
}"""
                    )
                GLES30.glGenTextures(textures.size, textures, 0)
                GLES30.glGenFramebuffers(4, framebuffers, 0)
                resize(width, height)
                enqueue()
                post { ready?.invoke() }
            } catch (e: Exception) {
                post { failure?.invoke(e.message ?: "玻璃渲染初始化失败") }
            }
        }
    }

    private fun resize(width: Int, height: Int) {
        widthPx = width
        heightPx = height
        hasImage = false
        prepared = null
        textures.forEachIndexed { index, texture ->
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture)
            GLES30.glTexParameteri(
                GLES30.GL_TEXTURE_2D,
                GLES30.GL_TEXTURE_MIN_FILTER,
                GLES30.GL_LINEAR,
            )
            GLES30.glTexParameteri(
                GLES30.GL_TEXTURE_2D,
                GLES30.GL_TEXTURE_MAG_FILTER,
                GLES30.GL_LINEAR,
            )
            GLES30.glTexParameteri(
                GLES30.GL_TEXTURE_2D,
                GLES30.GL_TEXTURE_WRAP_S,
                GLES30.GL_CLAMP_TO_EDGE,
            )
            GLES30.glTexParameteri(
                GLES30.GL_TEXTURE_2D,
                GLES30.GL_TEXTURE_WRAP_T,
                GLES30.GL_CLAMP_TO_EDGE,
            )
            if (index == 5) return@forEachIndexed
            GLES30.glTexImage2D(
                GLES30.GL_TEXTURE_2D,
                0,
                GLES30.GL_RGBA,
                width,
                height,
                0,
                GLES30.GL_RGBA,
                GLES30.GL_UNSIGNED_BYTE,
                null,
            )
            if (index > 0) {
                GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, framebuffers[index - 1])
                GLES30.glFramebufferTexture2D(
                    GLES30.GL_FRAMEBUFFER,
                    GLES30.GL_COLOR_ATTACHMENT0,
                    GLES30.GL_TEXTURE_2D,
                    texture,
                    0,
                )
                check(
                    GLES30.glCheckFramebufferStatus(GLES30.GL_FRAMEBUFFER) ==
                        GLES30.GL_FRAMEBUFFER_COMPLETE
                )
            }
        }
    }

    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {
        handler.post {
            if (surface != EGL14.EGL_NO_SURFACE) {
                resize(width, height)
                post { ready?.invoke() }
            }
        }
    }

    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}

    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
        frame?.invoke(false)
        labelFrame?.invoke(false)
        return !handler.post {
            destroy()
            texture.release()
        }
    }

    private fun destroy() {
        if (display != EGL14.EGL_NO_DISPLAY) {
            GLES30.glDeleteTextures(textures.size, textures, 0)
            GLES30.glDeleteFramebuffers(4, framebuffers, 0)
            listOf(geometry, optical, blur, copy)
                .filter { it != 0 }
                .forEach { GLES30.glDeleteProgram(it) }
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            EGL14.eglDestroySurface(display, surface)
            EGL14.eglDestroyContext(display, eglContext)
            EGL14.eglTerminate(display)
        }
        surface = EGL14.EGL_NO_SURFACE
        display = EGL14.EGL_NO_DISPLAY
        hasImage = false
        prepared = null
        presented = false
        hasLabels = false
        labelsPresented = false
    }

    fun release() {
        if (closed) return
        closed = true
        pendingImage.getAndSet(null)?.bitmap?.recycle()
        pendingLabels.getAndSet(null)?.recycle()
        handler.post {
            destroy()
            worker.quitSafely()
        }
    }

    private fun uniform(program: Int, name: String, vararg values: Float) {
        val location = GLES30.glGetUniformLocation(program, name)
        if (location < 0) return
        when (values.size) {
            1 -> GLES30.glUniform1f(location, values[0])
            2 -> GLES30.glUniform2fv(location, 1, values, 0)
            3 -> GLES30.glUniform3fv(location, 1, values, 0)
            4 -> GLES30.glUniform4fv(location, 1, values, 0)
            else -> GLES30.glUniform1fv(location, values.size, values, 0)
        }
    }

    private fun texture(program: Int, name: String, unit: Int, id: Int) {
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + unit)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, id)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, name), unit)
    }

    private fun begin(program: Int, target: Int) {
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, target)
        GLES30.glViewport(0, 0, widthPx, heightPx)
        GLES30.glUseProgram(program)
        uniform(program, "uViewportHeight", heightPx.toFloat())
    }

    private fun quad() {
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    }

    private fun renderSafely() {
        if (closed || !hasImage || surface == EGL14.EGL_NO_SURFACE) return
        try {
            render()
            if (!presented) {
                presented = true
                post { if (!closed && isAvailable) frame?.invoke(true) }
            }
            if (labelsPresented != hasLabels) {
                labelsPresented = hasLabels
                val shown = labelsPresented
                post { if (!closed && isAvailable) labelFrame?.invoke(shown) }
            }
        } catch (e: Exception) {
            post { failure?.invoke(e.message ?: "玻璃渲染失败") }
        }
    }

    private fun render() {
        val p = parameters
        val w = widthPx.toFloat()
        val h = heightPx.toFloat()
        val density = p.density
        val barWidth = w - if (p.blurOnly || p.button) 0f else 2 * GlassBarCaptureInset * density
        val jelly = glassJelly(p.velocity, .7f * p.expansion.coerceIn(0f, 1f))
        val lensWidth = ((barWidth - 8 * density) / 5 + 24 * density * p.expansion) * jelly.first
        val lensHeight = (48 + 16 * p.expansion) * density * jelly.second
        val lensX =
            (w - barWidth) / 2 + 4 * density + (barWidth - 8 * density) / 5 * (p.selected + .5f)
        fun useLabels(program: Int, enabled: Boolean) {
            uniform(program, "uUseLabels", if (enabled) 1f else 0f)
            texture(program, "uLabelTexture", 2, textures[5])
            if (enabled) {
                uniform(
                    program,
                    "uLabelRect",
                    (w - barWidth) / 2,
                    (h - 56 * density) / 2,
                    barWidth,
                    56 * density,
                )
            }
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        }
        fun blurPass(source: Int, target: Int, sigma: Float, horizontal: Boolean, flip: Boolean) {
            GLES30.glDisable(GLES30.GL_BLEND)
            begin(blur, framebuffers[target - 1])
            texture(blur, "image", 0, textures[source])
            uniform(blur, "size", w, h)
            uniform(
                blur,
                "stepSize",
                if (horizontal) sigma / 2 else 0f,
                if (horizontal) 0f else sigma / 2,
            )
            uniform(blur, "flip", if (flip) 1f else 0f)
            quad()
        }
        fun copyLayer(source: Int, target: Int, composite: Boolean = false) {
            GLES30.glDisable(GLES30.GL_BLEND)
            begin(copy, target)
            texture(copy, "image", 0, textures[source])
            texture(copy, "scene", 1, textures[0])
            uniform(copy, "size", w, h)
            uniform(copy, "flip", 1f)
            uniform(copy, "composite", if (composite) 1f else 0f)
            uniform(copy, "uLensRect", lensX, h / 2, lensWidth, lensHeight)
            useLabels(copy, hasLabels && target == 0 && !p.blurOnly && !p.button)
            quad()
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        }
        fun present() {
            check(GLES30.glGetError() == GLES30.GL_NO_ERROR) { "玻璃 OpenGL 绘制失败" }
            check(EGL14.eglSwapBuffers(display, surface)) { "玻璃帧提交失败" }
        }
        if (p.blurOnly) {
            blurPass(0, 1, p.blurDp * density, horizontal = true, flip = false)
            blurPass(1, 2, p.blurDp * density, horizontal = false, flip = true)
            copyLayer(2, 0)
            present()
            return
        }
        fun material(indicator: Boolean, target: Int) {
            GLES30.glDisable(GLES30.GL_BLEND)
            val x = if (indicator) lensX else w / 2
            val shapeWidth = if (indicator) lensWidth else barWidth
            val shapeHeight =
                if (p.button) minOf(w, h) else if (indicator) lensHeight else 56 * density
            val thickness = (if (p.button) 32f else if (indicator) 20f else 10f) * density / 3
            begin(geometry, framebuffers[2])
            uniform(geometry, "uSize", w, h)
            uniform(
                geometry,
                "uOpticalProps",
                if (p.button) 1.24f else if (indicator) 1.18f else 1.19f,
                if (indicator || p.button) .025f else .008f,
                thickness,
                0f,
            )
            uniform(geometry, "uShapeSettings", 1f, density)
            uniform(geometry, "uNativeEdge", if (indicator && !p.dark) 1f else 0f)
            val shapes = FloatArray(112)
            floatArrayOf(3f, x, h / 2, shapeWidth, shapeHeight, shapeHeight / 2, shapeHeight / 2)
                .copyInto(shapes)
            uniform(geometry, "uShapeData", *shapes)
            quad()
            begin(optical, target)
            GLES30.glEnable(GLES30.GL_BLEND)
            GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
            texture(optical, "uGeometryTexture", 1, textures[3])
            texture(optical, "uBackgroundTexture", 0, if (indicator) textures[1] else textures[2])
            uniform(optical, "uBackgroundFlip", 1f)
            uniform(optical, "uSize", w, h)
            uniform(optical, "uBackdropExtent", viewport.width.toFloat(), viewport.height.toFloat())
            uniform(optical, "uGeometryOffset", 0f, 0f)
            uniform(optical, "uGeometrySize", w, h)
            uniform(optical, "uLensRect", x, h / 2, shapeWidth, shapeHeight)
            useLabels(optical, indicator && hasLabels)
            uniform(
                optical,
                "uRestAmount",
                if (indicator) (1f - p.expansion / .15f).coerceIn(0f, 1f) else 0f,
            )
            val tint = if (indicator) p.dark else !p.dark
            uniform(
                optical,
                "uGlassColor",
                if (tint) 1f else 0f,
                if (tint) 1f else 0f,
                if (tint) 1f else 0f,
                if (indicator) if (p.dark) 38f / 255 else 24f / 255
                else if (p.dark) .4f else 240f / 255,
            )
            uniform(
                optical,
                "uOpticalProps",
                if (p.button) 1.24f else if (indicator) 1.18f else 1.19f,
                if (indicator || p.button) .025f else .008f,
                thickness,
                1f,
            )
            uniform(optical, "uLightConfig", if (indicator) .5f else .25f, 0f, 1.5f)
            uniform(optical, "uLightDirection", -.70710677f, -.70710677f)
            uniform(optical, "uWhiten", 0f)
            uniform(optical, "uWhitenGated", 1f)
            uniform(optical, "uPinchStrength", if (indicator) .7f * p.expansion else 0f)
            uniform(optical, "uBackgroundFallback", 0f, 0f, 0f, 0f)
            uniform(optical, "uCaptureOffset", 0f, 0f)
            uniform(optical, "uEdgeConfig", 0f, 1f, density / 3, 0f)
            uniform(optical, "uPlatformViewMode", 0f)
            uniform(optical, "uBodyMode", 1f)
            uniform(optical, "uTouchPosition", p.touchX, p.touchY)
            uniform(optical, "uTouchIntensity", p.touchIntensity)
            uniform(
                optical,
                "uRimConfig",
                if (indicator && !p.dark) .12f else 0f,
                if (p.dark) 0f else if (indicator) .35f else 1f,
                .2f,
            )
            uniform(optical, "uLensModel", 0f)
            uniform(optical, "uFrost", 0f, 0f, 0f, 1f)
            uniform(optical, "uBodyShade", 0f)
            quad()
        }
        val resting = p.expansion == 0f
        val shell = p.copy(selected = 0f, expansion = if (resting) 0f else 1f, velocity = 0f)
        if (prepared != shell) {
            blurPass(0, 1, 2f * density, horizontal = true, flip = false)
            blurPass(1, 2, 2f * density, horizontal = false, flip = true)
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, framebuffers[3])
            GLES30.glClearColor(0f, 0f, 0f, 0f)
            GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT)
            material(false, framebuffers[3])
            if (!p.button) {
                copyLayer(4, framebuffers[0], composite = true)
                val sigma = (if (resting) 6f else 5f) * density
                blurPass(1, 2, sigma, horizontal = true, flip = true)
                blurPass(2, 1, sigma, horizontal = false, flip = true)
            }
            prepared = shell
        }
        copyLayer(4, 0)
        if (!p.button) material(true, 0)
        GLES30.glDisable(GLES30.GL_BLEND)
        present()
    }
}

internal const val GlassBarCaptureInset = 20

internal fun glassJelly(velocity: Float, strength: Float): Pair<Float, Float> {
    val distortion =
        if (velocity.isFinite()) (kotlin.math.abs(velocity) / 10f).coerceIn(0f, 1f) * .8f * strength
        else 0f
    return (1f - distortion * .5f) to (1f + distortion * .3f)
}
