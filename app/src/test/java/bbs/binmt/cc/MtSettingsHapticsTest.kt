package bbs.binmt.cc

import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.*
import org.robolectric.shadows.ShadowViewGroup

@Implements(ViewGroup::class)
class SettingsPulseShadow : ShadowViewGroup() {
    companion object { val pulses = mutableListOf<Int>() }
    @Implementation override fun performHapticFeedback(feedbackConstant: Int): Boolean {
        pulses += feedbackConstant
        return super.performHapticFeedback(feedbackConstant)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = android.app.Application::class, qualifiers = "zh-rCN-w360dp-h800dp-mdpi", shadows = [SettingsPulseShadow::class])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class MtSettingsHapticsTest {
    private val compose = createAndroidComposeRule<ComponentActivity>()
    private val register = org.junit.rules.TestRule { base, _ -> object : org.junit.runners.model.Statement() {
        override fun evaluate() {
            val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
            org.robolectric.Shadows.shadowOf(context.packageManager).addActivityIfNotPresent(android.content.ComponentName(context, ComponentActivity::class.java))
            base.evaluate()
        }
    } }
    @get:Rule val rules: org.junit.rules.TestRule = org.junit.rules.RuleChain.outerRule(register).around(compose)
    private val pulses get() = SettingsPulseShadow.pulses

    private fun await(check: () -> Boolean) = compose.waitUntil(5_000) {
        compose.mainClock.advanceTimeByFrame()
        org.robolectric.shadows.ShadowLooper.idleMainLooper()
        check()
    }

    private fun start(): ForumState {
        val app = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.app.Application>()
        val state = ForumState(app, false)
        kotlinx.coroutines.runBlocking { state.settings.writeAll(mapOf("haptics" to true, "customFontWeight" to true,
            "fontWeightAdjustment" to 100, "liquidGlass" to true, "floatingNavigation" to true)) }
        compose.setContent {
            val view = LocalView.current
            state.feedback = { view.performHapticFeedback(it) }
            MaterialTheme { AppearanceSettings(state, Modifier.fillMaxSize()) }
        }
        return state
    }

    @Test fun resetAndGlassSelectionHaveOnePulseAndSliderCommitDoesNotAddSavePulses() {
        val state = start()
        val reset = compose.onNodeWithText("重置").performScrollTo()
        pulses.clear(); reset.performTouchInput { click() }
        await { !state.settings.bool("customFontWeight") }
        assertEquals(1, pulses.size)
        assertEquals(100, state.settings.int("fontWeightAdjustment"))
        pulses.clear()
        compose.onNodeWithContentDescription("字体粗细").performSemanticsAction(SemanticsActions.SetProgress) { it(-300f) }
        await { state.settings.bool("customFontWeight") && state.settings.int("fontWeightAdjustment") == -300 }
        assertTrue("Saving two fields is not two UI interactions", pulses.isEmpty())
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag("glass-choice-entry"))
        val entry = compose.onNodeWithTag("glass-choice-entry")
        pulses.clear(); entry.performTouchInput { click() }; assertEquals(1, pulses.size)
        pulses.clear(); compose.onNodeWithTag("glass-choice-row-true").performTouchInput { click() }
        await { state.settings.bool("translucentNavigationGlass") }
        assertEquals(1, pulses.size)
        entry.performTouchInput { click() }; pulses.clear()
        compose.onNodeWithText("取消").performTouchInput { click() }; assertEquals(1, pulses.size)
    }

    @Test fun disabledFeedbackAndLegacySettingsKeepTheirOriginalBehavior() {
        val state = start()
        pulses.clear(); compose.runOnIdle { state.setSetting("pureBlack", true) }
        assertEquals(1, pulses.size)
        await { state.settings.bool("pureBlack") }
        kotlinx.coroutines.runBlocking { state.settings.write("haptics", false) }
        pulses.clear()
        compose.onNodeWithText("重置").performScrollTo().performTouchInput { click() }
        await { !state.settings.bool("customFontWeight") }
        assertTrue(pulses.isEmpty())
    }
}
