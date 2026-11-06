package bbs.binmt.cc

import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.unit.dp
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "zh-rCN-w390dp-h844dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
class ScreenRenderTest {
    @get:Rule val compose = createEmptyComposeRule()

    private lateinit var activity: androidx.activity.ComponentActivity

    private fun fixture(name: String) = javaClass.getResource("/fixtures/$name.html")!!.readText()

    @Test
    @Config(qualifiers = "zh-rCN-w320dp-h720dp-mdpi")
    fun webDavOptionsFitAtMaximumAppFontScale() {
        activity = org.robolectric.Robolectric.buildActivity(
            androidx.activity.ComponentActivity::class.java
        ).setup().get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        state.screen = "backup"
        state.mode = 2
        state.fontScale = 1.4f
        activity.setContent { ForumApp(state) }
        compose.onNodeWithText("全量安全备份").assertIsSelected()
        for (line in listOf("不含会话及 WebDAV 密码", "含会话及 WebDAV 密码", "含明文凭据，请妥善保管")) {
            val bounds = compose.onNodeWithText(line, useUnmergedTree = true)
                .assertIsDisplayed().getUnclippedBoundsInRoot()
            org.junit.Assert.assertTrue(line, bounds.bottom - bounds.top < 35.dp)
        }
        compose.onNodeWithText("全量备份").performClick().assertIsSelected()
        capture("backup-dark-narrow-large")
    }

    @Test
    fun backPreviewRendersTheActualDestinationBeforeCommit() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        val latestTitle = "首页数据的最新帖子标题"
        state.page = Page("$ORIGIN/", latestTitle, emptyList(), emptyList(), emptyList(), null, "", emptyList())
        state.show("settings")
        state.show("appearance")
        activity.setContent { ForumApp(state) }

        compose.runOnIdle { check(state.previewBack()) }
        compose.onNodeWithText("设置").assertIsDisplayed()
        compose.onNodeWithText(latestTitle).assertDoesNotExist()
        compose.runOnIdle { state.finishBackPreview(true) }

        compose.runOnIdle {
            check(state.previewBack())
            check(state.canBack)
        }
        compose.onNodeWithText("MT论坛").assertIsDisplayed()
        compose.onNodeWithText(latestTitle).assertDoesNotExist()
        compose.onNodeWithContentDescription("返回").assertDoesNotExist()
        compose.runOnIdle { state.finishBackPreview(false) }
        compose.onNodeWithText("设置").assertIsDisplayed()

        compose.runOnIdle { check(state.previewBack()) }
        compose.onNodeWithText("MT论坛").assertIsDisplayed()
        compose.runOnIdle { state.finishBackPreview(true) }
        compose.onNodeWithText("MT论坛").assertIsDisplayed()
        compose.runOnIdle { check(!state.canBack) }
    }

    @Test
    fun selectableHiddenNoticeLinkHandlesASingleTap() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        var opened = ""
        val url = "$ORIGIN/forum.php?mod=post&action=reply&tid=91"
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                RichText("""<a href="$url">回复</a>""", { opened = it })
            }
        }
        compose.runOnIdle {
            fun findText(view: android.view.View): android.widget.TextView? =
                when (view) {
                    is android.widget.TextView -> view.takeIf { it.text.toString() == "回复" }
                    is android.view.ViewGroup ->
                        (0 until view.childCount).firstNotNullOfOrNull {
                            findText(view.getChildAt(it))
                        }
                    else -> null
                }
            val view = checkNotNull(findText(activity.window.decorView))
            org.junit.Assert.assertTrue(view.isTextSelectable)
            val x = view.totalPaddingLeft + view.layout.getPrimaryHorizontal(1)
            val y = view.totalPaddingTop + view.layout.getLineBottom(0) / 2f
            val start = android.os.SystemClock.uptimeMillis()
            for ((offset, action) in
                listOf(
                    0L to android.view.MotionEvent.ACTION_DOWN,
                    20L to android.view.MotionEvent.ACTION_UP,
                )) {
                val event = android.view.MotionEvent.obtain(start, start + offset, action, x, y, 0)
                try {
                    view.dispatchTouchEvent(event)
                } finally {
                    event.recycle()
                }
            }
            org.junit.Assert.assertEquals(url, opened)
        }
    }

    @Test
    fun postBoardSheetAnchorsToWindowBottomAndScrollsBothWays() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        state.composeBoardOpen = true
        activity.setContent { ForumApp(state) }
        val title = compose.onNodeWithText("选择发帖板块").assertIsDisplayed()
        val titleBounds = title.getUnclippedBoundsInRoot()
        val window = compose.onNode(isDialog()).getUnclippedBoundsInRoot()
        val windowHeight = window.bottom - window.top
        org.junit.Assert.assertTrue(windowHeight > 760.dp)
        org.junit.Assert.assertTrue((titleBounds.top - window.top) in windowHeight * .48f..windowHeight * .63f)
        val sheet = hasAnyAncestor(isDialog())
        val list = compose.onNode(hasScrollAction() and sheet)
        val viewport = list.getUnclippedBoundsInRoot()
        org.junit.Assert.assertEquals(window.bottom, viewport.bottom)
        org.junit.Assert.assertTrue((viewport.bottom - viewport.top) in 250.dp..400.dp)
        val last = compose.onNode(hasText(forumBoards.last().title) and sheet)
        last.assertIsNotDisplayed()
        list.performScrollToIndex(forumBoards.lastIndex)
        val lastBounds = last.assertIsDisplayed().getUnclippedBoundsInRoot()
        org.junit.Assert.assertTrue(
            lastBounds.top >= viewport.top && lastBounds.bottom <= viewport.bottom
        )
        org.junit.Assert.assertEquals(titleBounds, title.getUnclippedBoundsInRoot())
        list.performScrollToIndex(0)
        compose.onNode(hasText(forumBoards.first().title) and sheet).assertIsDisplayed()
    }

    @Test
    fun redNoteGlassNavigationKeepsFiveForumActionsAndSeparatesTapFromWater() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        val pulses = mutableListOf<Int>()
        state.settings.preview("haptics", true)
        state.feedback = { pulses.add(it) }
        val dragging = androidx.compose.runtime.mutableStateOf(false)
        val longPressed = androidx.compose.runtime.mutableStateOf(false)
        var motion = 0f to 0f
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                val backdrop = rememberBackdrop(Color.White)
                CompositionLocalProvider(LocalBackdrop provides backdrop) {
                    Box(Modifier.fillMaxSize()) {
                        Box(
                            Modifier.fillMaxSize().captureBackdrop(backdrop).background(Color.White)
                        )
                        Box(Modifier.align(androidx.compose.ui.Alignment.BottomCenter)) {
                            LiquidNavigation(state)
                        }
                    }
                }
            }
            val next =
                navigationGlassMotion(
                    state.tab,
                    dragging.value,
                    dragging.value,
                    4f,
                    longPressed.value,
                )
            androidx.compose.runtime.SideEffect { motion = next }
        }
        val home = compose.onNodeWithContentDescription("首页").assertIsSelected()
        val discover = compose.onNodeWithContentDescription("发现")
        val post = compose.onNodeWithContentDescription("发帖")
        compose.onNodeWithContentDescription("消息").assertExists()
        compose.onNodeWithContentDescription("我的").assertExists()
        post.performTouchInput { click(center) }
        compose.runOnIdle {
            org.junit.Assert.assertTrue(state.composeBoardOpen)
            org.junit.Assert.assertEquals(1, pulses.size)
        }
        home.assertIsSelected()
        compose.mainClock.autoAdvance = false
        try {
            discover.performTouchInput { click(center) }
            repeat(10) {
                compose.mainClock.advanceTimeByFrame()
                compose.runOnIdle { org.junit.Assert.assertEquals(0f, motion.second, 0f) }
            }
            discover.assertIsSelected()
            compose.runOnIdle {
                org.junit.Assert.assertEquals(2, pulses.size)
                org.junit.Assert.assertTrue(motion.first > 0f)
                dragging.value = true
            }
            repeat(10) {
                compose.mainClock.advanceTimeByFrame()
                compose.runOnIdle { org.junit.Assert.assertEquals(0f, motion.second, 0f) }
            }
            compose.runOnIdle {
                org.junit.Assert.assertTrue(motion.first > state.tab)
                longPressed.value = true
            }
            repeat(24) { compose.mainClock.advanceTimeByFrame() }
            compose.runOnIdle { org.junit.Assert.assertTrue(motion.second > .95f) }
            compose.runOnUiThread {
                dragging.value = false
                longPressed.value = false
            }
            repeat(6) {
                compose.mainClock.advanceTimeByFrame()
                compose.waitForIdle()
            }
            var previous = compose.runOnIdle { motion.second }
            org.junit.Assert.assertTrue(
                "release pressure=$previous",
                previous > .001f && previous < .999f,
            )
            repeat(15) {
                compose.mainClock.advanceTimeByFrame()
                val pressure = compose.runOnIdle { motion.second }
                org.junit.Assert.assertTrue(pressure <= previous)
                previous = pressure
            }
            org.junit.Assert.assertEquals(0f, previous, .001f)
        } finally {
            compose.mainClock.autoAdvance = true
        }
    }

    @Test
    fun historyAndLoginContinuationStaySilentAfterUserNavigation() {
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        val pulses = mutableListOf<Int>()
        state.settings.preview("haptics", true)
        state.feedback = { pulses.add(it) }
        state.load("$ORIGIN/thread-91-1-1.html")
        state.clearHistory()
        org.junit.Assert.assertEquals(1, pulses.size)
        state.currentUrl = "$ORIGIN/thread-91-1-1.html"
        state.authenticated = false
        state.reply()
        org.junit.Assert.assertEquals("login", state.screen)
        org.junit.Assert.assertEquals(2, pulses.size)
        state.loginComplete()
        org.junit.Assert.assertEquals(2, pulses.size)
        state.haptic(android.view.HapticFeedbackConstants.LONG_PRESS)
        state.selectTab(4, withFeedback = false)
        org.junit.Assert.assertEquals(3, pulses.size)
        state.settings.preview("haptics", false)
        state.selectTab(1)
        org.junit.Assert.assertEquals(3, pulses.size)
    }

    @Test
    fun compactReplyOptionsCollapseWithoutChangingSelections() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        val form =
            Form(
                "回复",
                "$ORIGIN/forum.php?mod=post&action=reply",
                "POST",
                listOf(
                    Field("message", "内容", "textarea", "正文"),
                    Field("notify", "接收回复通知", "checkbox", "", controlValue = "yes"),
                    Field("replysubmit", "发表回复", "submit", "true"),
                ),
                true,
            )
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                NativeForm(form, state, {}, {}, compact = true)
            }
        }
        compose.onNodeWithText("接收回复通知").assertDoesNotExist()
        compose.onNodeWithText("更多选项").performClick()
        compose.onNodeWithText("接收回复通知").performClick().assertIsOn()
        compose.onNodeWithText("更多选项").performClick()
        compose.onNodeWithText("接收回复通知").assertDoesNotExist()
        compose.onNodeWithText("更多选项").performClick()
        compose.onNodeWithText("接收回复通知").assertIsOn()
        org.junit.Assert.assertEquals("yes", state.drafts.getValue(form).values[1])
    }

    @Test
    fun searchRestoresCapsuleArrowHintAndKeyboardAction() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        state.screen = "search"
        activity.setContent { ForumApp(state) }
        compose.onNode(hasSetTextAction()).assertIsFocused().performImeAction()
        compose.onNodeWithContentDescription("搜索").assertExists()
        compose.onNodeWithText("搜索结果由论坛提供，权限和搜索间隔以网站规则为准。").assertExists()
        org.junit.Assert.assertFalse(state.busy)
        capture("search-light")
        compose.runOnIdle {
            state.mode = 2
            state.pureBlack = true
        }
        capture("search-black")
    }

    @Test
    fun standardDialogRestoresOriginalTitleAndChoiceSummaries() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                ChoiceDialog(
                    "选择字体粗细",
                    listOf(0 to "默认", 100 to "中等"),
                    0,
                    {},
                    summaries = listOf("标准字重", "适度加深笔触"),
                    reviewStyle = true,
                ) {}
            }
        }
        val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNodeWithText("选择字体粗细").performSemanticsAction(
            androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult
        ) {
            it(layouts)
        }
        org.junit.Assert.assertEquals(18f, layouts.single().layoutInput.style.fontSize.value)
        compose.onNodeWithText("标准字重").assertExists()
        compose.onNodeWithText("适度加深笔触").assertExists()
        capture("font-choice-dialog")
    }

    @Test
    fun fullEditorPreservesQuoteAndOriginalPlainField() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        var value = "[quote]原文[/quote]\n\n正文"
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                MessageEditor(value, { value = it }, false, false)
            }
        }
        compose.onNodeWithContentDescription("表情").assertDoesNotExist()
        compose.onNodeWithText("引用内容").assertExists()
        compose.onNodeWithContentDescription("移除引用").performClick()
        org.junit.Assert.assertEquals("正文", value)
        compose.onNode(hasSetTextAction()).performTextReplacement("继续编辑")
        org.junit.Assert.assertEquals("继续编辑", value)
    }

    @Test
    fun richTextIncludesLastLineHeightAtNormalAndLargeText() {
        val context = RuntimeEnvironment.getApplication()
        for (scale in listOf(1, 2)) for (lines in 1..3) {
            val text =
                android.text.SpannableStringBuilder(List(lines) { "Text" }.joinToString("\n"))
            text.setSpan(
                OriginalLineHeight(24 * scale),
                0,
                text.length,
                android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            val view =
                android.widget.TextView(context).apply {
                    includeFontPadding = false
                    setFallbackLineSpacing(false)
                    setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, 16f * scale)
                    this.text = text
                }
            view.measure(
                android.view.View.MeasureSpec.makeMeasureSpec(
                    390,
                    android.view.View.MeasureSpec.EXACTLY,
                ),
                android.view.View.MeasureSpec.makeMeasureSpec(
                    0,
                    android.view.View.MeasureSpec.UNSPECIFIED,
                ),
            )
            org.junit.Assert.assertEquals(lines, view.lineCount)
            org.junit.Assert.assertEquals(24 * scale * lines, view.measuredHeight)
        }
    }

    @Test
    fun articleBlocksRenderInAllThemesAndLargeText() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        state.settings.preview("color", 0)
        state.dynamic = false
        state.show("home")
        val page = ForumParser.parse(fixture("thread"), "$ORIGIN/thread-123-1-1.html")
        state.currentUrl = page.url
        state.page =
            page.copy(
                posts =
                    listOf(
                        page.posts
                            .first()
                            .copy(
                                html =
                                    "<p>正文第一段。</p><p>第二段，保留段落间距。</p><ul><li>列表第一项</li><li>列表第二项</li></ul><pre>  code\n    next line</pre><a class='forum-video' href='/v.mp4'>论坛视频</a><table border='1'><tr><th rowspan='2'>合并</th><td>较长的单元格内容</td></tr><tr><td>下一行</td></tr></table>"
                            )
                    )
            )
        activity.setContent { ForumApp(state) }
        for ((name, mode, black) in
            listOf(Triple("light", 1, false), Triple("dark", 2, false), Triple("black", 2, true))) {
            compose.runOnIdle {
                state.mode = mode
                state.pureBlack = black
            }
            compose.onNodeWithText("复制代码").assertExists()
            compose.onNodeWithText("论坛视频").assertExists()
            capture("article-$name")
        }
        compose.runOnIdle { state.fontScale = 2f }
        capture("article-large")
    }

    @Test
    fun galleryGlassPressDrawsGlowWithoutStealingClick() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        state.settings.preview("liquidGlass", true)
        var clicks = 0
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                Box(
                    Modifier.fillMaxSize().background(Color.Black),
                    contentAlignment = androidx.compose.ui.Alignment.Center,
                ) {
                    GalleryButton(state, { clicks++ }) { androidx.compose.material3.Text("按钮") }
                }
            }
        }
        compose.onNodeWithText("按钮").performTouchInput {
            down(center)
            moveBy(Offset(8f, 0f))
        }
        compose.mainClock.advanceTimeBy(400)
        capture("gallery-pressed-glow")
        compose.onNodeWithText("按钮").performTouchInput { up() }
        compose.runOnIdle { org.junit.Assert.assertEquals(1, clicks) }
    }

    @Test
    fun backdropStaysAlignedWhenGlassIsTranslatedAndScaled() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        activity.setContent {
            val backdrop = rememberBackdrop(Color.Black)
            CompositionLocalProvider(LocalBackdrop provides backdrop) {
                Box(Modifier.size(200.dp).testTag("alignment")) {
                    Canvas(Modifier.fillMaxSize().captureBackdrop(backdrop)) {
                        repeat(10) { stripe ->
                            drawRect(
                                if (stripe % 2 == 0) Color.Red else Color.Blue,
                                Offset(stripe * 20.dp.toPx(), 0f),
                                Size(20.dp.toPx(), size.height),
                            )
                        }
                    }
                    Box(Modifier.offset(20.dp, 30.dp).size(130.dp, 100.dp).background(Color.Green))
                    FrostedBackdrop(
                        Modifier.offset(40.dp, 40.dp).size(80.dp).graphicsLayer {
                            scaleX = 1.5f
                            scaleY = 1.25f
                            translationX = 3.dp.toPx()
                        },
                        false,
                        blurDp = .01f,
                    )
                }
            }
        }
        compose.waitForIdle()
        compose.runOnIdle {
            val view =
                activity.findViewById<android.view.ViewGroup>(android.R.id.content).getChildAt(0)
            val bitmap =
                android.graphics.Bitmap.createBitmap(
                    view.width,
                    view.height,
                    android.graphics.Bitmap.Config.ARGB_8888,
                )
            view.draw(android.graphics.Canvas(bitmap))
            for (x in listOf(30, 50, 70, 90, 110, 130)) {
                org.junit.Assert.assertEquals(
                    "red at $x",
                    android.graphics.Color.red(bitmap.getPixel(x, 10)),
                    android.graphics.Color.red(bitmap.getPixel(x, 70)),
                )
                org.junit.Assert.assertEquals(
                    "blue at $x",
                    android.graphics.Color.blue(bitmap.getPixel(x, 10)),
                    android.graphics.Color.blue(bitmap.getPixel(x, 70)),
                )
                org.junit.Assert.assertEquals(
                    "opaque glass at $x",
                    0,
                    android.graphics.Color.green(bitmap.getPixel(x, 70)),
                )
            }
            bitmap.recycle()
        }
    }

    @org.junit.After
    fun disposeComposition() {
        if (::activity.isInitialized) {
            compose.runOnIdle { activity.setContent {} }
            compose.waitForIdle()
        }
    }

    @Test
    fun editorLengthLimitKeepsVisibleAndSubmittedTextConsistent() {
        var submitted = "ab"
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                MessageEditor("ab", { submitted = it }, false, false, maxLength = 4)
            }
        }
        compose.onNode(hasSetTextAction()).performTextReplacement("12345")
        compose
            .onNode(hasSetTextAction())
            .assert(
                SemanticsMatcher.expectValue(
                    androidx.compose.ui.semantics.SemanticsProperties.EditableText,
                    androidx.compose.ui.text.AnnotatedString("ab"),
                )
            )
        org.junit.Assert.assertEquals("ab", submitted)
        compose.onNode(hasSetTextAction()).performTextReplacement("1234")
        compose
            .onNode(hasSetTextAction())
            .assert(
                SemanticsMatcher.expectValue(
                    androidx.compose.ui.semantics.SemanticsProperties.EditableText,
                    androidx.compose.ui.text.AnnotatedString("1234"),
                )
            )
        org.junit.Assert.assertEquals("1234", submitted)
    }

    @Test
    fun darkHtmlUsesThemeForUnreadableColorsAndKeepsReadableEmphasis() {
        val html =
            """<font color="#111111">正文</font><font color="#88ccff">强调</font><span style="background-color:#ffffff">高亮</span>"""
        fun foregrounds(content: android.text.Spanned) =
            content
                .getSpans(0, content.length, android.text.style.ForegroundColorSpan::class.java)
                .map { it.foregroundColor }
        val foreground = 0xFFE4E2E7.toInt()
        val surface = 0xFF1B1C20.toInt()
        val light = readableHtml(html, false, foreground, surface)
        org.junit.Assert.assertEquals(2, foregrounds(light).size)
        val dark = readableHtml(html, true, foreground, surface)
        org.junit.Assert.assertEquals(light.toString(), dark.toString())
        org.junit.Assert.assertEquals(listOf(0xFF88CCFF.toInt()), foregrounds(dark))
        org.junit.Assert.assertEquals(
            0,
            dark.getSpans(0, dark.length, android.text.style.BackgroundColorSpan::class.java).size,
        )
    }

    @Test
    fun homeKeepsVisibleLatestRowsAndSeparateMoreEntry() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        var opened = ""
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        val home = ForumParser.parse(fixture("home"), "$ORIGIN/")
        val page =
            home.copy(
                hot = emptyList(),
                links = listOf(Link("首页保留的最新帖子", "$ORIGIN/thread-123-1-1.html", author = "首页作者")),
            )
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                HomePage(
                    state,
                    androidx.compose.ui.Modifier,
                    androidx.compose.foundation.lazy.rememberLazyListState(),
                    { opened = it },
                    page,
                )
            }
        }
        compose.onNodeWithText("首页保留的最新帖子").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("最新帖子").assertExists()
        compose.onNodeWithContentDescription("更多最新帖子").performClick()
        org.junit.Assert.assertEquals(HOME_LATEST, opened)
        capture("home-latest-list")
    }

    @Test
    fun accountAndAboutSettingsUseOnePulsePerClick() {
        activity =
            org.robolectric.Robolectric.buildActivity(androidx.activity.ComponentActivity::class.java)
                .setup()
                .get()
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        state.settings.preview("haptics", true)
        var pulses = 0
        var about = 0
        state.feedback = { pulses++ }
        activity.setContent {
            androidx.compose.material3.MaterialTheme {
                SettingsHub(state, Modifier.fillMaxSize()) { about++ }
            }
        }
        val list = compose.onNode(hasScrollAction())
        list.performScrollToNode(hasText("登录账号"))
        compose.onNodeWithText("登录账号").performClick()
        compose.runOnIdle {
            org.junit.Assert.assertEquals(1, pulses)
            org.junit.Assert.assertEquals("login", state.screen)
            state.authenticated = true
        }
        list.performScrollToNode(hasText("检测账号凭据有效性"))
        compose.onNodeWithText("检测账号凭据有效性").performClick()
        compose.runOnIdle { org.junit.Assert.assertEquals(2, pulses) }
        list.performScrollToNode(hasText("退出登录"))
        val logout = compose.onNodeWithText("退出登录")
        fun logoutTitleColor(): Color {
            val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNodeWithText("退出登录", useUnmergedTree = true).performSemanticsAction(
                androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult
            ) { it(layouts) }
            return layouts.single().layoutInput.style.color
        }
        val idleColor = logoutTitleColor()
        compose.runOnIdle { state.utilityBusy = true }
        logout.assertIsNotEnabled()
        org.junit.Assert.assertEquals(idleColor, logoutTitleColor())
        compose.runOnIdle { state.utilityBusy = false }
        logout.performClick()
        compose.onNodeWithText("退出登录？").assertIsDisplayed()
        compose.onNodeWithText("取消").performClick()
        compose.runOnIdle { org.junit.Assert.assertEquals(3, pulses) }
        list.performScrollToNode(hasText("关于应用"))
        compose.onNodeWithText("关于应用").performClick()
        compose.runOnIdle {
            org.junit.Assert.assertEquals(4, pulses)
            state.settings.preview("haptics", false)
        }
        compose.onNodeWithText("关于应用").performClick()
        compose.runOnIdle {
            org.junit.Assert.assertEquals(4, pulses)
            org.junit.Assert.assertEquals(2, about)
        }
    }

    @Test
    fun aboutRestoresOriginalActionsAndBundledLicenses() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        activity.setContent { androidx.compose.material3.MaterialTheme { AboutDialog({}, {}) } }
        compose.onNodeWithContentDescription("MT论坛应用图标").assertIsDisplayed()
        capture("about-bundled-icon")
        compose.onNodeWithText("我知道了").assertExists()
        compose.onNodeWithText("开源许可").performClick()
        compose.onNodeWithText("Review").performClick()
        compose.onNodeWithText("MIT License", substring = true).assertExists()
    }

    @Test
    fun failedVideoSurfaceReleasesPlayerOnDestruction() {
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        var decoder: org.robolectric.shadows.ShadowMediaPlayer? = null
        org.robolectric.shadows.ShadowMediaPlayer.setCreateListener { _, shadow ->
            decoder = shadow
        }
        try {
            val state = ForumState(RuntimeEnvironment.getApplication(), false)
            activity.setContent {
                androidx.compose.material3.MaterialTheme {
                    VideoDialog("https://bbs.binmt.cc/unregistered-test.mp4", state, "", {})
                }
            }
            compose.waitForIdle()
            fun texture(view: android.view.View): android.view.TextureView? {
                if (view is android.view.TextureView) return view
                if (view is android.view.ViewGroup)
                    for (index in 0 until view.childCount) {
                        texture(view.getChildAt(index))?.let {
                            return it
                        }
                    }
                return null
            }
            val root = org.robolectric.shadows.ShadowDialog.getLatestDialog().window!!.decorView
            val view = texture(root)!!
            val surface = android.graphics.SurfaceTexture(0)
            compose.runOnIdle {
                view.surfaceTextureListener!!.onSurfaceTextureAvailable(surface, 390, 220)
            }
            org.junit.Assert.assertNotNull(decoder)
            compose.onNodeWithText("视频加载失败或格式不受支持").assertExists()
            compose.runOnIdle { view.surfaceTextureListener!!.onSurfaceTextureDestroyed(surface) }
            org.junit.Assert.assertEquals(
                org.robolectric.shadows.ShadowMediaPlayer.State.END,
                decoder!!.state,
            )
            surface.release()
        } finally {
            org.robolectric.shadows.ShadowMediaPlayer.setCreateListener(null)
        }
    }

    @Test
    fun originalScreenStructureRendersWithoutInstallingAnApp() {
        lateinit var state: ForumState
        activity =
            org.robolectric.Robolectric.buildActivity(
                    androidx.activity.ComponentActivity::class.java
                )
                .setup()
                .get()
        activity.setContent {
            state =
                androidx.compose.runtime.remember {
                    ForumState(RuntimeEnvironment.getApplication(), false)
                }
            ForumApp(state)
        }
        compose.runOnIdle {
            state.account = Account("测试账号", "123", emptyList(), "")
            state.authenticated = true
            state.screen = "settings"
        }
        compose.onNodeWithText("检测账号凭据有效性").assertExists()
        capture("settings-light")
        compose.runOnIdle { state.screen = "appearance" }
        compose.onNodeWithText("应用字体粗细").assertExists()
        capture("appearance-light")
        for ((screen, sample) in
            listOf(
                "storage" to "图片存储路径",
                "cache" to "重新统计",
                "backup" to "全量安全备份",
                "login" to "使用 QQ 登录",
                "history" to "还没有浏览记录",
            )) {
            compose.runOnIdle { state.screen = screen }
            if (screen == "cache") compose.onNodeWithContentDescription(sample).assertExists()
            else compose.onNodeWithText(sample).assertExists()
            if (screen == "backup") {
                val title = compose.onNodeWithText("全量备份", useUnmergedTree = true)
                    .assertIsDisplayed().getUnclippedBoundsInRoot()
                val details = compose.onNodeWithText(
                    "含会话及 WebDAV 密码", useUnmergedTree = true
                ).assertIsDisplayed().getUnclippedBoundsInRoot()
                val warning = compose.onNodeWithText(
                    "含明文凭据，请妥善保管", useUnmergedTree = true
                ).assertIsDisplayed().getUnclippedBoundsInRoot()
                org.junit.Assert.assertEquals(title.left, details.left)
                org.junit.Assert.assertTrue(details.top - title.bottom >= 3.dp)
                org.junit.Assert.assertTrue(warning.top - details.bottom >= 3.dp)
            }
            capture("$screen-light")
        }
        compose.runOnIdle {
            state.screen = "home"
            state.tab = 0
            state.page = ForumParser.parse(fixture("home"), "$ORIGIN/")
        }
        compose.onNodeWithText("排行榜").assertExists()
        capture("home-light")
        compose.runOnIdle {
            state.mode = 2
            state.settings.preview("liquidGlass", true)
        }
        compose.onNodeWithContentDescription("首页").assertIsSelected()
        capture("home-dark-glass-layout")
        compose.runOnIdle {
            state.mode = 1
            state.settings.preview("liquidGlass", false)
        }
        compose.runOnIdle { state.tab = 1 }
        capture("discover-light")
        compose.runOnIdle { state.tab = 4 }
        capture("account-light")
        compose.runOnIdle {
            state.screen = "settings"
            state.mode = 2
        }
        capture("settings-dark", checkDarkTitle = true)
        compose.runOnIdle {
            state.mode = 1
            state.screen = "home"
            state.tab = 0
            state.guard = null
            state.show("home")
        }
        for ((name, url) in
            listOf(
                "board" to "$ORIGIN/forum-2-1.html",
                "thread" to "$ORIGIN/thread-123-1-1.html",
                "sign" to "$ORIGIN/k_misign-sign.html",
                "rank-thread" to "$ORIGIN/misc.php?mod=ranklist&type=thread",
            )) {
            compose.runOnIdle {
                state.currentUrl = url
                state.page = ForumParser.parse(fixture(name), url)
            }
            capture("$name-light")
        }
        compose.runOnIdle {
            state.back()
            state.tab = 3
            state.screen = "home"
            state.currentUrl = "$ORIGIN/home.php?mod=space&do=notice&view=mypost"
            state.page = ForumParser.parse(fixture("messages_mypost"), state.currentUrl)
        }
        compose.onNodeWithText("坛友互动").assertExists()
        capture("messages-light")
        compose.runOnIdle { state.fontScale = 2f }
        capture("messages-large")
    }

    private fun capture(name: String, checkDarkTitle: Boolean = false) {
        compose.waitForIdle()
        val file = File("build/previews/$name.png")
        file.parentFile!!.mkdirs()
        compose.runOnIdle {
            val view =
                org.robolectric.shadows.ShadowDialog.getLatestDialog()
                    ?.takeIf { it.isShowing }
                    ?.window
                    ?.decorView ?: activity.window.decorView
            val bitmap =
                android.graphics.Bitmap.createBitmap(
                    view.width,
                    view.height,
                    android.graphics.Bitmap.Config.ARGB_8888,
                )
            view.draw(android.graphics.Canvas(bitmap))
            if (checkDarkTitle) {
                // This crop contains the title and back arrow on the custom dark surface.
                val pixels = IntArray(88 * 48)
                bitmap.getPixels(pixels, 0, 88, 8, 4, 88, 48)
                org.junit.Assert.assertTrue(
                    "Dark top bar must draw a light title and back arrow",
                    pixels.count { android.graphics.Color.red(it) > 180 } > 50,
                )
            }
            file.outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            bitmap.recycle()
        }
    }
}
