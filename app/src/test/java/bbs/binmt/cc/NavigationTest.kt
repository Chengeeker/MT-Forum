package bbs.binmt.cc

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NavigationTest {
    @Test
    fun predictiveCancelRestoresRouteAndDraftGuardDefersMutation() {
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        state.show("settings")
        state.show("appearance")
        assertTrue(state.previewBack())
        assertEquals("settings", state.screen)
        state.finishBackPreview(false)
        assertEquals("appearance", state.screen)
        assertTrue(state.previewBack())
        state.finishBackPreview(true)
        assertEquals("settings", state.screen)
        var pending: (() -> Unit)? = null
        state.guard = { _, action -> pending = action }
        state.show("storage")
        assertEquals("settings", state.screen)
        pending!!.invoke()
        assertEquals("storage", state.screen)
        state.writing = true
        state.back()
        assertEquals("storage", state.screen)
    }

    @Test
    fun destructiveLinksWaitForConfirmationAndSameReplyKeepsDraft() {
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        state.load("$ORIGIN/home.php?mod=spacecp&ac=comment&op=delete&id=1")
        assertNotNull(state.pendingAction)
        assertFalse(state.busy)
        state.pendingAction = null
        state.authenticated = true
        state.replyTarget = "123"
        val form = Form("回复", "$ORIGIN/forum.php", "post", emptyList(), true)
        state.dirtyForms[form] = true
        state.reply("123")
        assertEquals(true, state.dirtyForms[form])
        assertEquals(1, state.replyRevision)
    }

    @Test
    fun editorRejectsChangedAccountBeforeAnyRequest() {
        val state = ForumState(RuntimeEnvironment.getApplication(), false)
        val form =
            Form(
                "编辑",
                "$ORIGIN/forum.php?mod=post",
                "post",
                listOf(Field("message", "内容", "textarea", "draft")),
                true,
                "outdated_auth=old",
            )
        state.submitFields(form, listOf("message" to "draft"))
        assertFalse(state.busy)
        assertFalse(state.writing)
        assertTrue(state.error.contains("账号状态已变化"))
    }
}
