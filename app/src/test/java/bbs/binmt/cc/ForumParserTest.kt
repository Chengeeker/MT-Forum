package bbs.binmt.cc

import org.junit.Assert.*
import org.junit.Test

class ForumParserTest {
    private fun fixture(name: String) = javaClass.getResource("/fixtures/$name.html")!!.readText()

    @Test
    fun trustBoundaryRejectsCredentialsPortsAndOtherHosts() {
        assertNull(safeUrl("https://user@bbs.binmt.cc/"))
        assertNull(safeUrl("javascript:alert(1)"))
        assertNull(safeUrl(""))
        assertNull(safeUrl("http://bbs.binmt.cc/"))
        assertFalse(sameOrigin("https://bbs.binmt.cc.evil.example/"))
        assertFalse(sameOrigin("https://bbs.binmt.cc:444/"))
        assertEquals("https://bbs.binmt.cc/thread-123-1-1.html", safeUrl("thread-123-1-1.html"))
    }

    @Test
    fun realFixturesParseHomeBoardsThreadAndPagination() {
        val home = ForumParser.parse(fixture("home"), "$ORIGIN/")
        assertEquals(12, home.boards.size)
        assertTrue(home.links.isNotEmpty())
        for (name in listOf("board", "guide", "search", "favorites", "user-topics")) {
            val page = ForumParser.parse(fixture(name), "$ORIGIN/forum.php")
            assertTrue("$name should expose real links", page.links.isNotEmpty())
            assertTrue(page.links.all { sameOrigin(it.url) })
        }
        val thread = ForumParser.parse(fixture("thread"), "$ORIGIN/thread-123-1-1.html")
        assertTrue(thread.posts.isNotEmpty())
        assertTrue(
            thread.posts.all { !it.html.contains("<script") && !it.html.contains("nowrap=") }
        )
    }

    @Test
    fun sanitizedBodyKeepsTextButDropsExecutableMarkupAndFixedWidth() {
        val page =
            ForumParser.parse(
                "<h1>Title</h1><div id='postmessage_1'><nobr style='white-space:nowrap' width='900'>Long body</nobr><a href='javascript:alert(1)' onclick='bad()'>link</a><script>secret()</script></div>",
                "$ORIGIN/",
            )
        assertTrue(page.posts.single().html.contains("Long body"))
        assertFalse(page.posts.single().html.contains("javascript:"))
        assertFalse(page.posts.single().html.contains("onclick"))
        assertFalse(page.posts.single().html.contains("width="))
    }

    @Test
    fun formsPreserveTokensAndRequireSameOrigin() {
        val source =
            "<form action='/submit' method='post'><input type='hidden' name='formhash' value='token'><textarea name='message'>draft</textarea><input type='submit' name='send' value='yes'></form>"
        val form = ForumParser.parse(source, "$ORIGIN/").forms.single()
        assertTrue(form.supported)
        assertEquals("token", form.fields.first().value)
        assertFalse(
            ForumParser.parse(source.replace("/submit", "https://evil.example/submit"), "$ORIGIN/")
                .forms
                .single()
                .supported
        )
        assertFalse(
            ForumParser.parse(
                    source.replace("</form>", "<input name='seccodeverify'></form>"),
                    "$ORIGIN/",
                )
                .forms
                .single()
                .supported
        )
    }

    @Test
    fun unknownOrBlockedPagesAreFailuresNotEmptySuccess() {
        for (source in listOf("<html>unexpected</html>", "<title>403 Forbidden</title>")) {
            assertThrows(IllegalStateException::class.java) {
                ForumParser.parse(source, "$ORIGIN/")
            }
        }
    }

    @Test
    fun responseSizeIsBounded() {
        assertThrows(IllegalStateException::class.java) {
            ByteArray(17).inputStream().readNBytesCompat(16)
        }
        assertEquals(16, ByteArray(16).inputStream().readNBytesCompat(16).size)
    }

    @Test
    fun emptyNotificationsAreExplicitAndProfileFieldsAreVisible() {
        assertTrue(
            ForumParser.parse(fixture("messages_system"), "$ORIGIN/home.php")
                .notice
                .contains("当前没有")
        )
        assertTrue(
            ForumParser.parse(fixture("user-profile"), "$ORIGIN/home.php").details.any {
                it.contains("注册时间")
            }
        )
    }
}
