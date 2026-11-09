package bbs.binmt.cc

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.unit.dp
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w390dp-h844dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NavigationInsetsTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test fun standardBarPaintsGestureAndButtonInsetsWithoutMovingItsControls() {
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        activity.enableEdgeToEdge()
        val state = ForumState(activity.application, false)
        state.settings.preview("floatingNavigation", false)
        var dark by mutableStateOf(false)
        activity.setContent {
            MaterialTheme(colorScheme = if (dark) darkColorScheme() else lightColorScheme()) {
                Box(Modifier.fillMaxSize().background(Color.Magenta)) {
                    ForumNavigation(state, Modifier.align(Alignment.BottomCenter).testTag("navigation"))
                }
            }
        }
        compose.waitForIdle()
        for (night in listOf(false, true)) {
            compose.runOnIdle { dark = night }
            for (bottom in listOf(0, 24, 48)) {
                compose.runOnIdle {
                    ViewCompat.dispatchApplyWindowInsets(activity.window.decorView,
                        WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, bottom)).build())
                }
                val bar = compose.onNodeWithTag("navigation").getUnclippedBoundsInRoot()
                assertEquals((68 + bottom).dp, bar.bottom - bar.top)
                val label = compose.onNodeWithText("首页").getUnclippedBoundsInRoot()
                assertTrue(label.bottom <= bar.bottom - bottom.dp)
                if (bottom > 0) compose.runOnIdle {
                    val view = activity.window.decorView
                    val bitmap = android.graphics.Bitmap.createBitmap(view.width, view.height, android.graphics.Bitmap.Config.ARGB_8888)
                    view.draw(android.graphics.Canvas(bitmap))
                    val edge = bitmap.getPixel(1, view.height - bottom - 2)
                    assertNotEquals(android.graphics.Color.MAGENTA, edge)
                    assertEquals(edge, bitmap.getPixel(1, view.height - 2))
                    bitmap.recycle()
                }
            }
        }
        activity.finish()
    }
}
