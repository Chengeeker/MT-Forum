package bbs.binmt.cc

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class HomeFeedTest {
    private fun home() =
        ForumParser.parse(javaClass.getResource("/fixtures/home.html")!!.readText(), "$ORIGIN/")

    @Test
    fun failedGuideKeepsHomepageListAndRetryEntry() = runBlocking {
        val home = home()
        assertTrue(home.latest.isNotEmpty())
        assertTrue(home.latest.any { it.author.isNotBlank() })
        val (page, error) = loadHomeLatest(home, emptyList()) { error("offline") }
        assertEquals(home.latest, page.links)
        assertEquals(HOME_LATEST, page.next)
        assertTrue(error.isNotEmpty())
    }

    @Test
    fun laterPageFailureKeepsFirstBatchAndRetriesFailedPage() = runBlocking {
        val home = home()
        val next = "$HOME_LATEST&page=2"
        var calls = 0
        val (page, error) =
            loadHomeLatest(home, emptyList()) {
                if (++calls == 1) home.copy(links = home.latest.take(3), next = next)
                else error("offline")
            }
        assertEquals(home.latest.take(3), page.links)
        assertEquals(next, page.next)
        assertTrue(error.isNotEmpty())
    }

    @Test
    fun duplicatePageStopsAndCancellationDoesNotPublishFallback() = runBlocking {
        val home = home()
        var calls = 0
        val (page, _) =
            loadHomeLatest(home, emptyList()) {
                calls++
                home.copy(links = home.latest.take(2), next = "$HOME_LATEST&page=${calls+1}")
            }
        assertEquals(2, calls)
        assertNull(page.next)
        try {
            loadHomeLatest(home, emptyList()) { throw CancellationException() }
            fail("Cancellation must propagate after leaving the page")
        } catch (_: CancellationException) {}
    }
}
