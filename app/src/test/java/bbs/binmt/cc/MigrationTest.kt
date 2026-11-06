package bbs.binmt.cc

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MigrationTest {
    private fun fixture(name: String) = javaClass.getResource("/fixtures/$name.html")!!.readText()

    @Test
    fun postUsesRealImagePreviewAndNativeReplyLinkWithoutExposingLockedContent() {
        val url = "$ORIGIN/thread-91-1-1.html"
        val html =
            """<h1>帖子</h1><div id="post_1"><div id="postmessage_1">
            <img src="static/none.gif" data-src="https://cdn.binmt.cc/preview.webp"
                file="forum.php?mod=attachment&amp;aid=22" width="480" height="360">
            <div class="locked">如果要查看本帖隐藏内容请<a href="javascript:;">回复</a></div>
            </div><div class="attach_nopermission">您需要<a href="member.php?mod=logging&amp;action=login">登录</a>才可以查看</div></div>"""
        val locked = ForumParser.parse(html, url).posts.single()
        val parts = articleParts(locked.html)
        assertEquals(listOf("img", "access", "access"), parts.map { it.kind })
        assertEquals("https://cdn.binmt.cc/preview.webp", parts[0].value)
        assertEquals(480f, parts[0].width)
        assertEquals(locked.images.single(), parts[0].original)
        assertTrue(acceptsForumMediaCookie(locked.images.single()))
        assertFalse(acceptsForumMediaCookie("https://cdn.binmt.cc/forum.php?mod=attachment"))
        assertFalse(acceptsForumMediaCookie("$ORIGIN/forum.php?mod=post"))
        val reply = org.jsoup.Jsoup.parse(parts[1].value).selectFirst("a")!!.attr("href")
        assertTrue(isThreadReplyLink(reply, "91"))
        assertFalse(isThreadReplyLink(reply, "92"))
        val unlocked =
            ForumParser.parse(
                    """<h1>帖子</h1><div id="postmessage_1"><div class="showhide">服务器已返回内容</div></div>""",
                    url,
                )
                .posts
                .single()
        assertTrue(articleParts(unlocked.html).single().value.contains("服务器已返回内容"))
    }

    @Test
    fun tableSpansKeepRowsAlignedAndNestedTablesSeparate() {
        val cells =
            articleTableCells(
                "<table><tr><th rowspan='2'>A</th><td colspan='2'>B</td></tr><tr><td>C<table><tr><td>嵌套</td></tr></table></td><td>D</td></tr></table>"
            )
        assertEquals(4, cells.size)
        assertEquals(listOf(0 to 0, 0 to 1, 1 to 1, 1 to 2), cells.map { it.row to it.column })
        assertEquals(2, cells[0].rows)
        assertEquals(2, cells[1].columns)
        assertTrue(cells[0].heading)
        assertTrue(cells[2].html.contains("嵌套"))
        val invalid =
            articleTableCells(
                "<table><tr><td rowspan='0' colspan='-3'>x</td><td>y</td></tr><tr><td>z</td></tr></table>"
            )
        assertEquals(2, invalid[0].rows)
        assertEquals(1, invalid[0].columns)
        assertEquals(1, invalid[2].column)
    }

    @Test
    fun articleBlocksPreserveListsHeadingsDimensionsAndVideoLinks() {
        val parts =
            articleParts(
                "<h2>标题</h2><p>前文<img src='/a.png' width='240' height='120'>后文</p><ol start='3'><li>第一项<ul><li>嵌套</li></ul></li></ol><a class='forum-video' href='/v.mp4'>视频标题</a><img src='javascript:alert(1)'><img src='/b.png' width='NaN' height='-2'>"
            )
        assertEquals(listOf("h2", "p", "ol", "video", "img"), parts.map { it.kind })
        val paragraph = org.jsoup.Jsoup.parseBodyFragment(parts[1].value).selectFirst("p")!!
        val image = articleParts(paragraph.html())[1]
        assertEquals(240f, image.width)
        assertEquals(120f, image.height)
        assertEquals("视频标题", parts[3].title)
        assertEquals("$ORIGIN/v.mp4", parts[3].value)
        assertNull(parts.last().width)
        assertNull(parts.last().height)
        assertTrue(parts[2].value.contains("start=\"3\""))
        assertTrue(parts[2].value.contains("<ul>"))
    }

    @Test
    fun articleImageBoundsPreserveAspectRatioAndDeclaredDimensions() {
        val limit = Size(320f, 560f)
        assertEquals(Size(128f, 80f), articleImageSize(Size.Zero, null, null, limit))
        assertEquals(Size(320f, 160f), articleImageSize(Size(1600f, 800f), null, null, limit))
        assertEquals(Size(56f, 560f), articleImageSize(Size(100f, 1000f), null, null, limit))
        assertEquals(Size(40f, 20f), articleImageSize(Size(40f, 20f), null, null, limit))
        assertEquals(Size(100f, 50f), articleImageSize(Size(1600f, 800f), 100f, null, limit))
        assertEquals(Size(160f, 80f), articleImageSize(Size(1600f, 800f), null, 80f, limit))
        assertEquals(Size(320f, 100f), articleImageSize(Size(1600f, 800f), 900f, 100f, limit))
    }

    @Test
    fun myPostsKeepsTypeAndStatusInSeparateRows() {
        val base = "$ORIGIN/home.php?mod=space&do=thread&view=me"
        val (types, status) =
            myPostsTabs(fixture("my-posts-empty"), "$base&type=thread&filter=common", "")
        assertEquals(listOf("主题", "回复", "点评"), types.map { it.label })
        assertEquals("已发表", status.single { it.selected }.label)
        assertEquals("common", query(types[1].url, "filter"))
        assertNull(query(types[2].url, "filter"))
        assertTrue(status.all { isMyPosts(it.url) })
        assertFalse(isMyPosts("$base&uid=123"))
        val (commentTypes, commentStatus) =
            myPostsTabs(fixture("my-posts"), "$base&type=postcomment", "common")
        assertTrue(commentStatus.isEmpty())
        assertEquals("common", query(commentTypes[0].url, "filter"))
        assertFalse(commentTypes.any { it.label == "站外入口" })
    }

    @Test
    fun messageNavigationAndRankingUseActualCategories() {
        val tabs =
            messageTabs(
                fixture("messages_mypost"),
                "$ORIGIN/home.php?mod=space&do=notice&view=mypost",
            )
        assertEquals(6, tabs.size)
        assertTrue(tabs.none { it.label.contains("筛选") || it.label.contains("发送") })
        for (name in listOf("rank-overview", "rank-thread", "rank-member", "rank-forum")) {
            val result = ranking(fixture(name), "$ORIGIN/misc.php?mod=ranklist")
            assertTrue(name, result.categories.isNotEmpty())
            assertTrue(name, result.entries.isNotEmpty())
        }
        val sign = org.jsoup.Jsoup.parse(fixture("sign"))
        assertTrue(
            sign
                .select("a[onclick]")
                .mapNotNull { signRankTarget(it, ORIGIN) }
                .all { query(it, "operation") == "list" }
        )
        assertNull(
            signRankTarget(
                org.jsoup.Jsoup.parse(
                        "<a onclick=\"ajaxget('https://evil.test/?operation=list','ranklist')\">bad</a>"
                    )
                    .selectFirst("a")!!,
                ORIGIN,
            )
        )
    }

    @Test
    fun composerSelectionAndCollectionPrivacy() {
        val input =
            androidx.compose.ui.text.input.TextFieldValue(
                "前选中后",
                androidx.compose.ui.text.TextRange(1, 3),
            )
        val output = insertMarkup(input, "[b]", "[/b]")
        assertEquals("前[b]选中[/b]后", output.text)
        assertEquals(6, output.selection.start)
        val page =
            ForumParser.parse(
                "<h1>title</h1><div id='post_1'><div id='postmessage_1'><div class='locked'>秘密</div>公开内容</div></div>",
                "$ORIGIN/thread-1-1-1.html",
            )
        assertEquals("公开内容", collectionSummary(Link("t", page.url), page).excerpt)
        assertEquals(2, favorites(fixture("favorites"), ORIGIN).size)
        val source =
            "<h1>title</h1><div id='postmessage_1'><table width=900><tr><td nowrap>正文</td></tr></table></div>"
        assertFalse(
            ForumParser.parse(source, "$ORIGIN/thread-1-1-1.html")
                .posts
                .single()
                .html
                .contains("<table")
        )
    }

    @Test
    fun signInImageDigitsAndVisitedStatus() {
        val info = AccountService.parseSignIn(fixture("sign"))
        assertFalse(info.signed)
        assertEquals("124天", info.stats.last().second)
        assertEquals(4, info.stats.size)
        assertNotNull(info.action)
        assertNotNull(info.rules)
        assertTrue(
            AccountService.parseSignIn(
                    fixture("sign").replace("id=\"JD_sign\"", "id=\"JD_sign\" class=\"visited\"")
                )
                .signed
        )
        assertNull(
            AccountService.parseSignIn(
                    fixture("sign")
                        .replace(
                            "plugin.php?id=k_misign:sign&amp;operation=qiandao",
                            "https://evil.test/plugin.php?id=k_misign:sign&amp;operation=qiandao",
                        )
                )
                .action
        )
    }

    @Test
    fun articleMediaAndCodeKeepDocumentOrder() {
        val page =
            ForumParser.parse(
                "<h1>Title</h1><div id='postmessage_1'>前文<img file='/a.png'>中间<pre>  a\n    b</pre>后文<video src='/v.mp4'></video></div>",
                "$ORIGIN/thread-1-1-1.html",
            )
        val parts = articleParts(page.posts.single().html)
        assertEquals(listOf("text", "img", "text", "code", "text", "video"), parts.map { it.kind })
        assertEquals("  a\n    b", parts[3].value)
        assertEquals("$ORIGIN/a.png", parts[1].value)
    }

    @Test
    fun formsKeepDuplicateSelectionsAndSubmitLabels() {
        val form = ForumParser.parse(fixture("favorites"), "$ORIGIN/home.php").forms.single()
        assertEquals(
            listOf("10", "11"),
            form.fields.filter { it.name == "favorite[]" }.map { it.controlValue },
        )
        assertEquals("收藏示例帖子", form.fields.first { it.name == "favorite[]" }.label)
        assertEquals("删除选中收藏", form.fields.last().label)
    }

    @Test
    fun userBroadcastAndWallPreserveDistinctEntriesAndActions() {
        val feed =
            userContent(
                fixture("user-broadcast"),
                "$ORIGIN/home.php?mod=follow&uid=123&do=view&from=space",
            )
        assertEquals(2, feed.entries.size)
        assertTrue(feed.entries.first().body.contains("很有启发"))
        assertFalse(feed.entries.first().body.contains("<script"))
        val wall = userContent(fixture("user-wall"), "$ORIGIN/home.php?mod=space&uid=123&do=wall")
        assertEquals("坛友", wall.entries.single().name)
        assertEquals("回复", wall.entries.single().actions.single().title)
        assertEquals(
            "wall-fixture",
            wall.page!!.forms.single().fields.first { it.name == "formhash" }.value,
        )
        val archive =
            userContent(
                "<xml><![CDATA[false]]></xml>",
                "$ORIGIN/home.php?mod=spacecp&ac=follow&op=getfeed&uid=123&archiver=0&page=3",
                true,
            )
        assertEquals("1", query(archive.next!!, "archiver"))
    }

    @Test
    fun writesCannotTriggerBrowserRetry() {
        assertTrue(readOnlyPage("$ORIGIN/thread-1-1-1.html"))
        for (url in
            listOf(
                "home.php?mod=spacecp&ac=follow&op=add",
                "plugin.php?id=k_misign:sign&operation=qiandao",
                "forum.php?mod=post&action=reply",
            )) assertFalse(readOnlyPage("$ORIGIN/$url"))
        assertTrue(needsAccount("$ORIGIN/home.php?mod=space&do=favorite&view=me"))
    }

    @Test
    fun relativeLinksFormHelpAndGenericContent() {
        assertEquals("$ORIGIN/thread-1-1-1.html", safeUrl("thread-1-1-1.html", ORIGIN))
        val page =
            ForumParser.parse(
                """<div id="ct"><p>注册须知</p><form method="post"><input name="email"><a href="misc.php?mod=faq">用户协议</a></form><script>bad()</script></div>""",
                "$ORIGIN/member.php?mod=register",
            )
        assertEquals("用户协议", page.forms.single().links.single().title)
        assertTrue(page.content.contains("注册须知"))
        assertFalse(page.content.contains("bad()"))
        assertFalse(page.content.contains("<form"))
        assertEquals(
            "color:red;font-weight:700",
            safeTextStyle(
                "width:999px;color:red;background-image:url(https://evil.test);font-weight:700;white-space:nowrap"
            ),
        )
    }

    private fun backup(prefs: JSONObject = JSONObject(), mode: String = "safe") =
        JSONObject()
            .put("app", "bbs.binmt.cc")
            .put("version", "1.0")
            .put("backup_mode", mode)
            .put("preferences", prefs)

    @Test
    fun backupRejectsOverflowAndUnsafeHistoryAndSessions() {
        assertThrows(IllegalArgumentException::class.java) {
            BackupRules.validate(backup(JSONObject().put("color", 4294967296L)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            BackupRules.validate(
                backup(
                    JSONObject()
                        .put(
                            "history",
                            "[{\"title\":\"x\",\"url\":\"https://evil.test/thread-1-1-1.html\"}]",
                        )
                )
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            BackupRules.validate(backup(mode = "full"))
        }
        assertFalse(
            BackupRules.validate(backup(JSONObject().put("webdav_password", "secret")))
                .containsKey("webdav_password")
        )
        assertThrows(IllegalArgumentException::class.java) {
            AccountService.cookiePairs("a_auth=x\r\nInjected=y")
        }
        assertThrows(IllegalArgumentException::class.java) {
            BackupRules.server("https://name:secret@host.test/dav/")
        }
        assertThrows(IllegalArgumentException::class.java) { BackupRules.directory("../other") }
        assertEquals(8443, BackupRules.server("https://host.test:8443/dav/").port)
    }

    @Test
    fun zoomStagesAnchorsAndAxisBounds() {
        val viewport = Size(400f, 800f)
        val wide = Size(1600f, 900f)
        val tall = Size(600f, 2000f)
        assertEquals(2.5f, ImageGeometry.nextScale(1f, wide))
        assertEquals(3.5f, ImageGeometry.nextScale(1f, tall))
        assertEquals(6f, ImageGeometry.nextScale(2.5f, wide))
        assertEquals(1f, ImageGeometry.nextScale(6f, tall))
        val zoom =
            ImageGeometry.transform(ImageTransform(), 2.5f, Offset(100f, 300f), viewport, wide)
        assertEquals(150f, zoom.offset.x)
        assertEquals(0f, zoom.offset.y)
        assertEquals(
            ImageTransform(),
            ImageGeometry.transform(zoom, 1f, Offset.Zero, viewport, wide),
        )
        assertFalse(StorageRules.folder("../a\\b").contains('/'))
        assertEquals(40, StorageRules.folder("🙂".repeat(60)).codePointCount(0, 80))
    }
}
