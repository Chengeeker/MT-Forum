package bbs.binmt.cc

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Shader
import androidx.compose.ui.geometry.Size
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NavigationGlassGpuTest {
    @Test
    fun redNoteShaderSamplesPageAndKeepsBothEndLensesInsideCapture() {
        val optics = GlassOptics(RuntimeEnvironment.getApplication())
        val size = Size(390f, 86f)
        val source = Bitmap.createBitmap(390, 86, Bitmap.Config.ARGB_8888)
        val output = Bitmap.createBitmap(390, 86, Bitmap.Config.ARGB_8888)
        try {
            Canvas(source).apply {
                drawRect(0f, 0f, 390f, 43f, Paint().apply { color = Color.RED })
                drawRect(0f, 43f, 390f, 86f, Paint().apply { color = Color.BLUE })
            }
            optics.shader.setInputShader(
                "background",
                BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP),
            )
            val target = Canvas(output)
            // Use host Skia to evaluate AGSL without treating this as an Android GPU test.
            ReflectionHelpers.callInstanceMethod<Unit>(
                target,
                "setHwFeaturesInSwModeEnabled",
                ReflectionHelpers.ClassParameter.from(Boolean::class.javaPrimitiveType, true),
            )
            val paint = Paint().apply { shader = optics.shader }
            for (dark in listOf(false, true)) {
                output.eraseColor(Color.TRANSPARENT)
                optics.configure(size, navigationGlassBar(size, 1f), 1f, dark)
                assertNotNull(optics.effect())
                target.drawRect(0f, 0f, 390f, 86f, paint)
                assertEquals(0, Color.alpha(output.getPixel(4, 43)))
                assertTrue(
                    Color.red(output.getPixel(195, 27)) > Color.blue(output.getPixel(195, 27))
                )
                assertTrue(
                    Color.blue(output.getPixel(195, 60)) > Color.red(output.getPixel(195, 60))
                )
                for (index in listOf(0, 4)) {
                    val lens = navigationGlassLens(size, 1f, index.toFloat(), 1f, 10f)
                    assertTrue(lens.left > 0f && lens.right < size.width)
                    assertTrue(lens.top > 0f && lens.bottom < size.height)
                    output.eraseColor(Color.TRANSPARENT)
                    optics.configure(
                        size,
                        lens,
                        1f,
                        dark,
                        lens = true,
                        pressed = 1f,
                        dragging = true,
                    )
                    target.drawRect(0f, 0f, 390f, 86f, paint)
                    assertEquals(255, Color.alpha(output.getPixel(lens.center.x.toInt(), 43)))
                    assertEquals(0, Color.alpha(output.getPixel(195, 43)))
                }
            }
        } finally {
            output.recycle()
            source.recycle()
        }
    }
}
