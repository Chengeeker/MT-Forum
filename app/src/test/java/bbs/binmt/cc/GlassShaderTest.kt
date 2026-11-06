package bbs.binmt.cc

import androidx.compose.ui.geometry.Offset
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GlassShaderTest {
    @Test
    fun galleryPressAndAnchorStretchPreserveCenterAndOppositeEdge() {
        assertEquals(Offset(1f, 1f) to Offset.Zero, galleryButtonTransform(Offset.Zero, 0f))
        val pressed = galleryButtonTransform(Offset.Zero, 1f)
        assertEquals(65f / 48f, pressed.first.x, .0001f)
        assertEquals(pressed.first.x, pressed.first.y)
        assertEquals(Offset.Zero, pressed.second)
        val right = galleryButtonTransform(Offset(25f, 0f), 0f)
        val left = galleryButtonTransform(Offset(-25f, 0f), 0f)
        assertEquals(1.3f, right.first.x, .0001f)
        assertEquals(.875f, right.first.y, .0001f)
        assertEquals(right.first, left.first)
        assertEquals(right.second.x, -left.second.x, .0001f)
        assertEquals(3.9f, right.second.x - 24 * (right.first.x - 1), .0001f)
        val vertical = galleryButtonTransform(Offset(0f, 25f), 0f)
        assertEquals(right.first.x, vertical.first.y, .0001f)
        assertEquals(right.first.y, vertical.first.x, .0001f)
        assertEquals(right.second.x, vertical.second.y, .0001f)
    }

    @Test
    fun retainedShadersExpandForGlesWithoutFlutterRuntime() {
        val view = GlassRenderer(RuntimeEnvironment.getApplication())
        try {
            for (name in listOf("liquid_glass_geometry_blended.frag", "liquid_glass_render.frag")) {
                val source = view.source(name)
                assertFalse(Regex("(?m)^#include").containsMatchIn(source))
                assertFalse(source.contains("FlutterFragCoord().xy"))
                assertTrue(source.startsWith("#version 300 es"))
                assertFalse(source.contains("#version 460"))
                File("build/shaders/$name").apply {
                    parentFile!!.mkdirs()
                    writeText(source)
                }
            }
        } finally {
            view.release()
        }
    }

    @Test
    fun galleryJellyRetainsItsExistingBounds() {
        assertEquals(1f to 1f, glassJelly(Float.NaN, .7f))
        assertEquals(1f to 1f, glassJelly(10f, 0f))
        val moving = glassJelly(10f, .7f)
        assertEquals(.72f, moving.first, .0001f)
        assertEquals(1.168f, moving.second, .0001f)
        assertEquals(moving, glassJelly(-10f, .7f))
        assertTrue(64 * moving.second < 96)
    }
}
