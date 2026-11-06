package bbs.binmt.cc

import java.net.URI
import java.net.URLEncoder
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

const val ORIGIN = "https://bbs.binmt.cc"
const val USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

private fun resolveUri(value: String, base: String): URI {
    val root = URI(base)
    return (if (root.rawPath.isNullOrEmpty()) URI(root.scheme, root.authority, "/", null, null)
        else root)
        .resolve(value.trim())
}

fun browserUrl(value: String, base: String = ORIGIN): String? =
    runCatching {
            require(value.isNotBlank())
            resolveUri(value, base)
                .takeIf {
                    it.scheme in setOf("https", "http") &&
                        !it.host.isNullOrBlank() &&
                        it.rawUserInfo == null
                }
                ?.toASCIIString()
        }
        .getOrNull()

fun safeUrl(value: String, base: String = "$ORIGIN/"): String? =
    runCatching {
            require(value.isNotBlank())
            resolveUri(value, base)
                .takeIf {
                    it.scheme == "https" &&
                        !it.host.isNullOrBlank() &&
                        it.rawUserInfo == null &&
                        (it.port == -1 || it.port == 443)
                }
                ?.toASCIIString()
        }
        .getOrNull()

fun sameOrigin(value: String): Boolean =
    safeUrl(value)?.let { URI(it).host == "bbs.binmt.cc" } == true

fun query(value: String, key: String): String? =
    runCatching {
            URI(value)
                .rawQuery
                ?.split('&')
                ?.firstOrNull { it.substringBefore('=') == key }
                ?.substringAfter('=')
        }
        .getOrNull()

fun threadId(value: String): String? =
    if (!sameOrigin(value)) null
    else
        Regex("/thread-(\\d+)-").find(value)?.groupValues?.get(1)
            ?: (query(value, "tid") ?: query(value, "ptid"))?.takeIf { it.matches(Regex("\\d+")) }

internal fun isThreadReplyLink(url: String, thread: String?) =
    thread != null &&
        sameOrigin(url) &&
        query(url, "tid") == thread &&
        query(url, "mod") == "post" &&
        query(url, "action") == "reply"

fun encode(value: String) = URLEncoder.encode(value, "UTF-8")

fun avatarUrl(profile: String): String =
    userId(profile)?.let { "$ORIGIN/uc_server/avatar.php?uid=$it&size=middle" }.orEmpty()

fun boardId(value: String): String? =
    if (!sameOrigin(value)) null
    else
        Regex("/forum-(\\d+)-").find(value)?.groupValues?.get(1)
            ?: query(value, "fid")?.takeIf { it.matches(Regex("\\d+")) }

fun readOnlyPage(url: String): Boolean =
    sameOrigin(url) &&
        query(url, "mod") !in setOf("spacecp", "post") &&
        query(url, "action") == null &&
        (query(url, "operation") == null || query(url, "operation") == "list")

fun needsAccount(url: String): Boolean =
    sameOrigin(url) &&
        (query(url, "mod") in setOf("spacecp", "post") ||
            query(url, "do") in setOf("pm", "notice", "favorite") ||
            query(url, "view") == "me" && query(url, "uid") == null ||
            url.contains("k_misign-sign"))

data class Link(
    val title: String,
    val url: String,
    val detail: String = "",
    val image: String = "",
    val author: String = "",
    val date: String = "",
    val views: String = "",
    val replies: String = "",
    val excerpt: String = "",
    val pinned: Boolean = false,
    val role: String = "",
    val profile: String = "",
    val likes: String = "",
    val hot: Boolean = false,
)

data class Post(
    val id: String,
    val author: String,
    val meta: String,
    val html: String,
    val profile: String,
    val images: List<String>,
    val videos: List<String>,
    val avatar: String = "",
    val floor: String = "",
    val role: String = "",
)

data class Field(
    val name: String,
    val label: String,
    val type: String,
    val value: String,
    val options: List<Pair<String, String>> = emptyList(),
    val controlValue: String = value,
    val required: Boolean = false,
    val readonly: Boolean = false,
    val maxLength: Int = Int.MAX_VALUE,
    val group: String = "",
    val help: String = "",
)

data class Form(
    val title: String,
    val action: String,
    val method: String,
    val fields: List<Field>,
    val supported: Boolean,
    val session: String? = null,
    val links: List<Link> = emptyList(),
)

data class Page(
    val url: String,
    val title: String,
    val links: List<Link>,
    val boards: List<Link>,
    val posts: List<Post>,
    val next: String?,
    val notice: String,
    val forms: List<Form>,
    val details: List<String> = emptyList(),
    val source: String = "",
    val hot: List<Link> = emptyList(),
    val online: String = "",
    val resolvedThreadId: String? = null,
    val requiresLogin: Boolean = false,
    val content: String = "",
    val latest: List<Link> = emptyList(),
)

fun safeTextStyle(style: String): String =
    style
        .split(';')
        .mapNotNull {
            val key = it.substringBefore(':').trim().lowercase()
            val value = it.substringAfter(':', "").trim()
            if (
                key in
                    setOf(
                        "color",
                        "background-color",
                        "font-weight",
                        "font-style",
                        "text-decoration",
                    ) && value.matches(Regex("[#a-zA-Z0-9(),.%\\s-]+"))
            )
                "$key:$value"
            else null
        }
        .joinToString(";")

object ForumParser {
    fun parse(source: String, url: String): Page {
        require(sameOrigin(url)) { "只解析同源论坛页面" }
        val doc = Jsoup.parse(source, url)
        val title =
            doc.selectFirst("#thread_subject,.comiis_infotit h1 a,h1")
                ?.let { node ->
                    if (node.hasClass("comiis_infotit")) node.selectFirst("a")?.text()
                    else node.clone().apply { select("span").remove() }.text()
                }
                ?.ifBlank { null } ?: doc.title().ifBlank { "MT论坛" }
        check(!title.contains("403") && !source.contains("Sorry, you have been blocked")) {
            "网站拒绝访问（403），请稍后重试"
        }
        fun link(a: Element): Link? {
            val target = safeUrl(a.attr("href"), url) ?: return null
            if (!sameOrigin(target) || a.text().isBlank() || a.text().matches(Regex("\\d+")))
                return null
            val row = a.closest("tr, li, dl") ?: a.parent()
            val detail =
                row?.select(".by, .km_user, .km_view, .km_reply, .num, .xg1")?.text().orEmpty()
            val paragraphs = row?.select("p")
            val searchMeta =
                paragraphs?.lastOrNull()?.takeIf {
                    row.hasClass("pbw") || row.closest(".slst") != null
                }
            val user =
                row?.selectFirst(".km_user a,.by cite a")
                    ?: searchMeta?.selectFirst("a[href*=uid],a[href*=username]")
            val profile = safeUrl(user?.attr("href").orEmpty(), url).orEmpty()
            val counts = if (searchMeta != null) paragraphs?.firstOrNull()?.text().orEmpty() else ""
            return Link(
                a.attr("title").ifBlank { a.text() },
                target,
                detail,
                safeUrl(row?.selectFirst(".comiis_listtx img")?.attr("src").orEmpty(), url)
                    ?: avatarUrl(profile),
                user?.text().orEmpty(),
                searchMeta?.text()?.substringBefore(" - ")
                    ?: row?.selectFirst(".km_user + em span, .by em span")?.text().orEmpty(),
                Regex("([\\d.,万亿]+)\\s*次?查看").find(counts)?.groupValues?.get(1)
                    ?: row?.selectFirst(".km_view, .num em")?.text().orEmpty(),
                Regex("([\\d.,万亿]+)\\s*个?回复").find(counts)?.groupValues?.get(1)
                    ?: row?.selectFirst(".km_reply, .num a")?.text().orEmpty(),
                row?.select("p")?.let { if (it.size > 2) it[1].text() else "" }.orEmpty(),
                a.closest("tbody")?.id()?.startsWith("stickthread_") == true,
                profile = profile,
                hot = row?.select("img[alt=heatlevel]")?.isNotEmpty() == true,
            )
        }
        val boards =
            doc.select(".comiis_fl_g")
                .mapNotNull { card ->
                    val a = card.selectFirst("a[href*=forum-]") ?: return@mapNotNull null
                    val target = safeUrl(a.attr("href"), url) ?: return@mapNotNull null
                    if (!sameOrigin(target)) return@mapNotNull null
                    Link(
                        card.selectFirst("dt a")?.text() ?: a.text(),
                        target,
                        image =
                            safeUrl(card.selectFirst("img")?.attr("src").orEmpty(), url).orEmpty(),
                    )
                }
                .distinctBy { it.url }
        val root = doc.selectFirst("#threadlist") ?: doc.body()
        val links =
            root
                .select("a[href]")
                .mapNotNull(::link)
                .filter { threadId(it.url) != null }
                .distinctBy { threadId(it.url) }
        val resolved =
            threadId(url)
                ?: doc.select("link[rel=canonical][href], form[action*=tid=]")
                    .firstNotNullOfOrNull {
                        threadId(
                            safeUrl(it.attr(if (it.tagName() == "link") "href" else "action"), url)
                                .orEmpty()
                        )
                    }
        val posts =
            doc.select("[id^=postmessage_]").map { body ->
                val id = body.id().removePrefix("postmessage_")
                val row = doc.getElementById("post_$id") ?: body.parent() ?: body
                val author = row.selectFirst(".authi a.xw1, .authi a[href*=uid], .pls .authi a")
                val images = linkedSetOf<String>()
                val videos =
                    body
                        .select("video[src], source[src], a[href]")
                        .mapNotNull {
                            safeUrl(it.attr(if (it.tagName() == "a") "href" else "src"), url)
                        }
                        .filter {
                            URI(it).path.lowercase().matches(Regex(".*\\.(mp4|m3u8|m4v|mov|webm)$"))
                        }
                        .distinct()
                val clean = body.clone()
                row.select(".attach_nopermission")
                    .filter { body !in it.parents() }
                    .forEach { clean.appendChild(it.clone()) }
                clean.select("script, style, form, iframe, object, embed").remove()
                clean.select(".locked").forEach { notice ->
                    val text = notice.text()
                    if (resolved != null && "隐藏" in text && "回复" in text) {
                        val replyUrl = "$ORIGIN/forum.php?mod=post&action=reply&tid=$resolved"
                        val link = notice.select("a").firstOrNull { it.text().trim() == "回复" }
                        if (link == null)
                            notice
                                .appendText(" ")
                                .appendElement("a")
                                .attr("href", replyUrl)
                                .text("回复帖子")
                        else link.attr("href", replyUrl)
                    }
                }
                clean.select("img").forEach { img ->
                    fun imageUrl(attribute: String) =
                        safeUrl(img.attr(attribute), url)?.takeUnless {
                            URI(it).path.substringAfterLast('/').lowercase() in
                                setOf("none.gif", "blank.gif", "loading.gif")
                        }
                    val target =
                        listOf("file", "zoomfile", "data-original", "data-src", "src")
                            .firstNotNullOfOrNull(::imageUrl)
                    if (target == null) img.remove()
                    else {
                        val preview =
                            listOf("src", "data-src", "data-original")
                                .firstNotNullOfOrNull(::imageUrl)
                        img.attr("src", preview ?: target).attr("data-forum-original", target)
                        images.add(target)
                    }
                }
                clean.select("video,source").forEach { node ->
                    safeUrl(node.attr("src"), url)?.let { node.attr("src", it) }
                }
                clean.select("*").forEach { node ->
                    node
                        .attributes()
                        .asList()
                        .filter {
                            it.key.startsWith("on", true) ||
                                it.key == "nowrap" ||
                                (it.key == "width" && node.tagName() != "img")
                        }
                        .forEach { node.removeAttr(it.key) }
                    if (node.hasAttr("style")) node.attr("style", safeTextStyle(node.attr("style")))
                    if (node.tagName() == "nobr") node.tagName("span")
                }
                clean.select("a[href]").forEach { a ->
                    val target = browserUrl(a.attr("href"), url)
                    if (target == null) a.removeAttr("href") else a.attr("href", target)
                }
                clean.select("table").reversed().forEach { table ->
                    val cells = table.select("td,th")
                    if (
                        table.select("tr").size == 1 &&
                            cells.size == 1 &&
                            !cells[0].hasAttr("colspan") &&
                            !cells[0].hasAttr("rowspan")
                    ) {
                        val block = org.jsoup.nodes.Element("div")
                        block.html(cells[0].html())
                        table.replaceWith(block)
                    }
                }
                Post(
                    id,
                    author?.text() ?: "论坛用户",
                    row.selectFirst(".authi em")?.text().orEmpty(),
                    clean.html(),
                    safeUrl(author?.attr("href").orEmpty(), url).orEmpty(),
                    images.toList(),
                    videos,
                    safeUrl(
                        row.selectFirst(".avtm img,.avatar img,.avt img")?.attr("src").orEmpty(),
                        url,
                    ) ?: avatarUrl(safeUrl(author?.attr("href").orEmpty(), url).orEmpty()),
                    row.selectFirst(".pi strong a, a[id^=postnum]")?.text().orEmpty(),
                    row.selectFirst(".pls a[href*=ac=usergroup]")?.text().orEmpty(),
                )
            }
        val formRoots =
            doc.select("#postform, #ct .mn form, #ct > form, form[id^=loginform], form#scform")
                .ifEmpty { doc.select("form") }
        val forms =
            formRoots
                .filter {
                    it.select("input:not([type=hidden]):not([type=submit]), textarea, select")
                        .isNotEmpty()
                }
                .map { form ->
                    val fields =
                        form
                            .select("input[name], textarea[name], select[name], button[name]")
                            .filter {
                                !it.hasAttr("disabled") &&
                                    it.attr("type") !in listOf("reset", "button", "file")
                            }
                            .map { input ->
                                val type =
                                    when (input.tagName()) {
                                        "textarea" -> "textarea"
                                        "select" -> "select"
                                        "button" -> "submit"
                                        else -> input.attr("type").ifBlank { "text" }
                                    }
                                val name = input.attr("name")
                                val label =
                                    input.closest("label")?.text()?.ifBlank { null }
                                        ?: doc.select("label")
                                            .firstOrNull {
                                                it.attr("for") == input.id() &&
                                                    input.id().isNotBlank()
                                            }
                                            ?.text()
                                        ?: (if (type == "submit")
                                            input.text().ifBlank { input.attr("value") }
                                        else if (name == "favorite[]")
                                            input.closest("li")?.select("a")?.lastOrNull()?.text()
                                        else if (type == "radio" || type == "checkbox")
                                            input.parent()?.text()?.ifBlank { null }
                                        else input.closest("tr")?.selectFirst("th")?.text())
                                        ?: input.attr("placeholder").ifBlank {
                                            mapOf(
                                                "username" to "用户名 / 邮箱",
                                                "password" to "密码",
                                                "subject" to "标题",
                                                "message" to "内容",
                                                "srchtxt" to "搜索关键词",
                                                "answer" to "安全问题答案",
                                            )[name] ?: name
                                        }
                                val value =
                                    when (type) {
                                        "textarea" -> input.wholeText()
                                        "select" ->
                                            (input.selectFirst("option[selected]")
                                                    ?: input.selectFirst("option"))
                                                ?.attr("value")
                                                .orEmpty()
                                        "checkbox",
                                        "radio" ->
                                            if (input.hasAttr("checked"))
                                                input.attr("value").ifBlank { "on" }
                                            else ""
                                        else -> input.attr("value")
                                    }
                                Field(
                                    name,
                                    label,
                                    type,
                                    value,
                                    input.select("option").map {
                                        it.attr("value").ifBlank { it.text() } to it.text()
                                    },
                                    input.attr("value").ifBlank { "on" },
                                    input.hasAttr("required") ||
                                        name in setOf("message", "srchtxt") ||
                                        (name == "subject" && query(url, "action") == "newthread"),
                                    input.hasAttr("readonly"),
                                    input.attr("maxlength").toIntOrNull()?.takeIf { it > 0 }
                                        ?: Int.MAX_VALUE,
                                    input
                                        .closest("table")
                                        ?.selectFirst("caption h2,caption h3")
                                        ?.text()
                                        .orEmpty(),
                                    input
                                        .closest("table")
                                        ?.selectFirst("caption p")
                                        ?.text()
                                        .orEmpty(),
                                )
                            }
                    val action = safeUrl(form.attr("action").ifBlank { url }, url).orEmpty()
                    val supported =
                        sameOrigin(action) &&
                            form.attr("method").lowercase() in setOf("", "get", "post") &&
                            form
                                .select("[id*=seccode], [name*=seccode], [name*=secanswer]")
                                .isEmpty()
                    Form(
                        form
                            .selectFirst("button[type=submit], input[type=submit]")
                            ?.let { it.text().ifBlank { it.attr("value") } }
                            ?.ifBlank { null } ?: "提交",
                        action,
                        form.attr("method").ifBlank { "get" }.lowercase(),
                        fields,
                        supported,
                        links =
                            form
                                .select("a[href]")
                                .mapNotNull { a ->
                                    browserUrl(a.attr("href"), url)
                                        ?.takeIf { a.text().isNotBlank() }
                                        ?.let { Link(a.text(), it) }
                                }
                                .distinctBy { it.url },
                    )
                }
        val notice =
            doc.selectFirst("#messagetext, .alert_info, .alert_error, .emp")?.text().orEmpty()
        val details =
            if (posts.isEmpty())
                doc.select(".pf_l li, .nts dl, .pml dl, .xld dl, .feed li")
                    .map { it.text() }
                    .filter { it.isNotBlank() }
                    .distinct()
            else emptyList()
        val supplemental =
            if (posts.isEmpty() && links.isEmpty())
                doc.select("#ct a[href]")
                    .filter { it.closest(".tb,.tbmu,.appl,.pg,#uhd,form") == null }
                    .mapNotNull(::link)
                    .distinctBy { it.url }
            else emptyList()
        val content =
            if (
                posts.isEmpty() &&
                    links.isEmpty() &&
                    boards.isEmpty() &&
                    doc.selectFirst("#ct,#wp") != null &&
                    doc.selectFirst("#uhd,.lineB .paiming,#favorite_ul") == null
            ) {
                val node = (doc.selectFirst("#ct .mn,#ct,#wp") ?: doc.body()).clone()
                node
                    .select(
                        "script,style,iframe,object,embed,link,meta,form,#hd,#ft,#pt,.appl,.sd,.tb,.tbmu,.pg,.paihang,.emp,.alert_info,.alert_error,#messagetext,.nts dl,.pml dl,h1.mt,h2.mt"
                    )
                    .remove()
                node.select("*").forEach { child ->
                    child
                        .attributes()
                        .asList()
                        .filter {
                            it.key.startsWith("on", true) ||
                                it.key in setOf("style", "width", "height", "class", "nowrap")
                        }
                        .forEach { child.removeAttr(it.key) }
                }
                node.select("a[href]").forEach { a ->
                    browserUrl(a.attr("href"), url)?.let { a.attr("href", it) }
                        ?: a.removeAttr("href")
                }
                node.select("img[src]").forEach { img ->
                    safeUrl(img.attr("src"), url)?.let { img.attr("src", it) } ?: img.remove()
                }
                if (node.text().isNotBlank() || node.selectFirst("img[src]") != null) node.html()
                else ""
            } else ""
        check(
            boards.isNotEmpty() ||
                links.isNotEmpty() ||
                posts.isNotEmpty() ||
                forms.isNotEmpty() ||
                supplemental.isNotEmpty() ||
                notice.isNotEmpty() ||
                details.isNotEmpty() ||
                content.isNotEmpty() ||
                doc.selectFirst(".lineB .paiming, #uhd, #ranklist, [id^=feed_li_], #comment_ul") !=
                    null
        ) {
            "页面未返回可识别内容，请刷新或检查登录状态"
        }
        fun section(index: Int): List<Link> =
            doc.select(".boxbg_7ree")
                .getOrNull(index)
                ?.select("a[href]")
                ?.mapNotNull { anchor ->
                    val target = safeUrl(anchor.attr("href"), url) ?: return@mapNotNull null
                    val id = threadId(target) ?: return@mapNotNull null
                    val tip = Jsoup.parseBodyFragment(anchor.attr("tips"))
                    val description = tip.text()
                    fun field(label: String, end: String) =
                        Regex("$label[：:]\\s*(.*?)$end")
                            .find(description)
                            ?.groupValues
                            ?.get(1)
                            ?.trim()
                            .orEmpty()
                    val profile =
                        tip.selectFirst("a[href*=uid]")
                            ?.let { safeUrl(it.attr("href"), url) }
                            .orEmpty()
                    Link(
                        anchor.attr("title").ifBlank { anchor.text() },
                        "$ORIGIN/thread-$id-1-1.html",
                        image = avatarUrl(profile),
                        author = field("作者", "时间[：:]"),
                        date = field("时间", "浏览[：:]"),
                        views = field("浏览", "次"),
                        replies = field("回复", "次"),
                        profile = profile,
                    )
                }
                ?.filter { it.title.isNotBlank() }
                ?.distinctBy { threadId(it.url) }
                .orEmpty()
        val hot = section(3)
        return Page(
            url,
            title,
            links.ifEmpty { if (content.isEmpty()) supplemental else emptyList() },
            boards,
            posts,
            doc.selectFirst(".pg a.nxt, a.nxt")
                ?.let { safeUrl(it.attr("href"), url) }
                ?.takeIf(::sameOrigin),
            notice,
            forms,
            details,
            source,
            hot,
            Regex("总计\\s*(\\d+)").find(doc.select("#online").text())?.groupValues?.get(1).orEmpty(),
            resolved,
            doc.selectFirst("form[id^=loginform_]") != null,
            content,
            section(0),
        )
    }
}
