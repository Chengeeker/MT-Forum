import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/widgets/app_section_card.dart';
import '../core/widgets/forum_avatar.dart';
import '../data/forum.dart';
import '../data/preferences.dart';
import '../data/native_forum.dart';
import 'native_forum_page.dart';
import 'media_page.dart';
import 'login_page.dart';
import 'web_page.dart';

Future<void> openForum(
  BuildContext context,
  ForumLink link,
  ForumClient client,
  Preferences preferences,
) async {
  final uri = forumUri(link.url);
  if (!isForumUri(uri)) {
    await openExternal(context, uri);
    return;
  }
  if (isThreadLink(uri) ||
      boardId(uri) != null ||
      uri.queryParameters['mod'] == 'guide') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ForumPage(link: link, client: client, preferences: preferences),
      ),
    );
  } else {
    await openForumWeb(context, link.title, uri.toString(), client: client);
  }
}

class ForumPage extends StatefulWidget {
  const ForumPage({
    super.key,
    required this.link,
    required this.client,
    required this.preferences,
    this.initialDocument,
    this.forceThread = false,
  });
  final ForumLink link;
  final ForumClient client;
  final Preferences preferences;
  final ForumDocument? initialDocument;
  final bool forceThread;
  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  Future<void> openSite(String title, String path) => openForumWeb(
    context,
    title,
    path,
    client: widget.client,
    preferences: widget.preferences,
  );

  final Object heroScope = Object();
  final scroll = ScrollController();
  ForumDocument? document;
  final summaries = <String, Future<ThreadSummary>>{};
  int listVersion = 0;
  List<ForumLink> links = [];
  List<ForumPost> posts = [];
  String? next, error;
  late String url = widget.link.url;
  bool loading = false;
  NativeForumForm? replyForm;
  final replyFocus = FocusNode();
  String? replyError, replySession, replyTarget;
  bool replyExpanded = false,
      replyLoading = false,
      replySending = false,
      replyDirty = false;
  int replyGeneration = 0;
  int revision = 0;
  bool get isThread =>
      widget.forceThread || isThreadLink(forumUri(widget.link.url));
  String? get currentThreadId =>
      threadId(forumUri(url)) ?? document?.resolvedThreadId;
  @override
  void initState() {
    super.initState();
    sessionRevision.addListener(accountChanged);
    scroll.addListener(() {
      if (scroll.position.extentAfter < 600 &&
          next != null &&
          !loading &&
          error == null) {
        load(more: true);
      }
    });
    final initial = widget.initialDocument;
    if (initial == null) {
      load();
    } else {
      document = initial;
      links = [...initial.links];
      posts = [...initial.posts];
      next = initial.next;
      if (isThread && posts.isNotEmpty) {
        unawaited(widget.preferences.visited(ForumLink(initial.title, url)));
      }
    }
  }

  @override
  void dispose() {
    sessionRevision.removeListener(accountChanged);
    scroll.dispose();
    replyFocus.dispose();
    replyGeneration++;
    super.dispose();
  }

  void accountChanged() {
    revision++;
    setState(() {
      replyGeneration++;
      replyForm = null;
      replySession = null;
      replyTarget = null;
      replyError = null;
      replyLoading = false;
      replySending = false;
      replyDirty = false;
      replyExpanded = false;
      document = null;
      links = [];
      posts = [];
      next = null;
      loading = false;
      error = null;
      summaries.clear();
    });
    load();
  }

  Future<void> load({bool more = false, String? filter}) async {
    if (loading) return;
    final generation = revision;
    final target = more ? next : (filter ?? url);
    if (target == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.client.load(target);
      if (!mounted || generation != revision) return;
      setState(() {
        if (!more) document = data;
        if (more) {
          final seen = links.map((e) => e.url).toSet();
          links.addAll(data.links.where((e) => seen.add(e.url)));
          final pids = posts.map((e) => e.id).toSet();
          posts.addAll(data.posts.where((e) => pids.add(e.id)));
        } else {
          summaries.clear();
          listVersion++;
          links = [...data.links];
          posts = [...data.posts];
          if (filter != null) {
            url = filter;
            scroll.jumpTo(0);
          }
        }
        next = data.next == target ? null : data.next;
      });
      if (isThread && posts.isNotEmpty) {
        await widget.preferences.visited(
          ForumLink(data.title, widget.link.url),
        );
      }
    } catch (e) {
      if (mounted && generation == revision) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && generation == revision) setState(() => loading = false);
    }
  }

  Future<void> writeReply([ForumPost? post]) async {
    if (replySending || replyLoading) return;
    final tid = currentThreadId;
    if (tid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法确定帖子编号，请刷新后重试。')));
      return;
    }
    final target = post?.id ?? '';
    if (replyForm != null && target == replyTarget) {
      setState(() => replyExpanded = true);
      focusReply();
      return;
    }
    if (replyDirty && !await discardReply()) return;
    if (!mounted || !await showForumLogin(context, widget.client) || !mounted) {
      return;
    }
    final uri = forumUri(
      'forum.php?mod=post&action=reply&tid=$tid${post == null ? '' : '&repquote=${post.id}'}',
    );
    var generation = ++replyGeneration;
    setState(() {
      replyExpanded = true;
      replyLoading = true;
      replyDirty = false;
      replyError = null;
      replyForm = null;
      replyTarget = target;
    });
    try {
      var data = NativeForumDocument(
        await widget.client.source(uri.toString()),
        uri,
      );
      if (data.requiresLogin) {
        if (!mounted ||
            !await showForumLogin(context, widget.client, force: true) ||
            !mounted) {
          return;
        }
        generation = ++replyGeneration;
        setState(() {
          replyExpanded = true;
          replyLoading = true;
          replyTarget = target;
        });
        data = NativeForumDocument(
          await widget.client.source(uri.toString()),
          uri,
        );
      }
      if (data.requiresLogin) throw const ForumFailure('登录会话已失效，请重新登录后回复。');
      final form = data.content.querySelector('form#postform');
      if (form == null) {
        throw ForumFailure(
          data.notice.isNotEmpty ? data.notice : '论坛没有返回可用的回复表单。',
        );
      }
      final cookie = await forumAuthCookie();
      if (!mounted || generation != replyGeneration) return;
      setState(() {
        replyForm = NativeForumForm(form, uri);
        replySession = cookie;
      });
      focusReply();
    } catch (e) {
      if (mounted && generation == replyGeneration) {
        setState(() => replyError = '$e');
      }
    } finally {
      if (mounted && generation == replyGeneration) {
        setState(() => replyLoading = false);
      }
    }
  }

  void focusReply() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && replyExpanded) replyFocus.requestFocus();
  });

  Future<bool> discardReply() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('放弃未提交的回复？'),
          content: const Text('当前草稿尚未发送。收起编辑栏可以保留草稿。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> sendReply(
    NativeForumForm form,
    Map<String, dynamic> values,
    dom.Element? button,
  ) async {
    if (replySending) return;
    final generation = replyGeneration;
    setState(() {
      replySending = true;
      replyError = null;
    });
    try {
      if (replySession != await forumAuthCookie()) {
        throw const ForumFailure('账号状态已变化，草稿已保留，请重新验证。');
      }
      final fields = Map<String, dynamic>.from(values);
      final name = button?.attributes['name'];
      if (name != null && name.isNotEmpty) {
        fields[name] = button!.attributes['value'] ?? 'yes';
      }
      final result = await widget.client.submit(
        form.action,
        fields,
        method: form.method,
      );
      final data = NativeForumDocument(result.$1, result.$2);
      if (data.requiresLogin) throw const ForumFailure('登录会话已失效，草稿已保留。');
      final successNotice = RegExp('成功|感谢|审核').hasMatch(data.notice);
      if ((data.notice.isNotEmpty && !successNotice) ||
          (!successNotice && threadId(result.$2) == null)) {
        throw ForumFailure(
          data.notice.isEmpty ? '论坛尚未确认回复成功，请刷新核实后再操作。' : data.notice,
        );
      }
      if (!mounted || generation != replyGeneration) return;
      replyFocus.unfocus();
      setState(() {
        replyDirty = false;
        replyExpanded = false;
        replyForm = null;
        replyTarget = null;
        replySending = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('回复已发送')));
      await load();
    } catch (e) {
      if (mounted && generation == replyGeneration) {
        setState(() => replyError = '$e\n未自动重试，草稿已保留。');
      }
    } finally {
      if (mounted && generation == replyGeneration) {
        setState(() => replySending = false);
      }
    }
  }

  Widget replyBar() => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!replyExpanded)
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      if (replyForm != null) {
                        setState(() => replyExpanded = true);
                        focusReply();
                      } else {
                        writeReply();
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(replyDirty ? '继续编辑回复…' : '说点什么吧…'),
                  ),
                ),
              Offstage(
                offstage: !replyExpanded,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        ((MediaQuery.sizeOf(context).height -
                                    MediaQuery.viewInsetsOf(context).bottom) *
                                .55)
                            .clamp(120, 420),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (replyForm == null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: '收起编辑栏',
                              onPressed: () =>
                                  setState(() => replyExpanded = false),
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                          ),
                        if (replyLoading) const LinearProgressIndicator(),
                        if (replyError != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              replyError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (replyForm != null)
                          NativeForumFormView(
                            key: ObjectKey(replyForm),
                            form: replyForm!,
                            busy: replySending,
                            compactReply: true,
                            replyFocus: replyFocus,
                            onSubmit: sendReply,
                            onChanged: () {
                              if (!replyDirty) {
                                setState(() => replyDirty = true);
                              }
                            },
                            onCollapse: () {
                              replyFocus.unfocus();
                              setState(() => replyExpanded = false);
                            },
                          )
                        else if (!replyLoading)
                          TextButton(
                            onPressed: () => writeReply(
                              posts
                                  .where((p) => p.id == replyTarget)
                                  .firstOrNull,
                            ),
                            child: const Text('重试回复'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<ThreadSummary> summaryFor(
    ForumLink link,
    bool Function() active,
  ) async {
    final account = revision, version = listVersion;
    final future = summaries.putIfAbsent(
      link.url,
      () => widget.client.threadSummary(
        link.url,
        () =>
            mounted &&
            account == revision &&
            version == listVersion &&
            active(),
      ),
    );
    if (summaries.length > 60) summaries.remove(summaries.keys.first);
    try {
      return await future;
    } catch (_) {
      if (identical(summaries[link.url], future)) summaries.remove(link.url);
      rethrow;
    }
  }

  Widget boardHeader(ForumLink board) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AppSectionCard(
      borderRadius: 12,
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 24,
          child: board.imageUrl == null
              ? const Icon(Icons.forum_outlined)
              : ClipOval(
                  child: Image.network(
                    board.imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    headers: forumMediaHeaders(Uri.parse(board.imageUrl!)),
                    errorBuilder: (_, _, _) => const Icon(Icons.forum_outlined),
                  ),
                ),
        ),
        title: Text(
          board.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: board.subtitle.isEmpty
            ? null
            : Text(
                board.subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
      ),
    ),
  );

  Widget pinnedThreads() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AppSectionCard(
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text('置顶帖'),
          ),
          for (final link in links.where((e) => e.pinned))
            ListTile(
              minTileHeight: 48,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              horizontalTitleGap: 8,
              minLeadingWidth: 0,
              leading: const ForumLabel('置顶'),
              title: Text(
                link.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              onTap: () =>
                  openForum(context, link, widget.client, widget.preferences),
            ),
        ],
      ),
    ),
  );

  Widget boardFilters() => Row(
    children: [
      for (final item in [
        ('全部', ''),
        ('最新', 'orderby=dateline'),
        ('热门', 'filter=heat&orderby=heats'),
        ('精华', 'filter=digest&digest=1'),
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Builder(
              builder: (context) {
                final selected = item.$2.isEmpty
                    ? !url.contains('filter=') && !url.contains('orderby=')
                    : url.contains(item.$2);
                final style = FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 48),
                  shape: const StadiumBorder(),
                  textStyle: Theme.of(context).textTheme.bodyMedium,
                );
                void select() => load(
                  filter:
                      '$forumOrigin/forum.php?mod=forumdisplay&fid=${boardId(forumUri(url))}${item.$2.isEmpty ? '' : '&${item.$2}'}',
                );
                return Semantics(
                  selected: selected,
                  child: selected
                      ? FilledButton(
                          style: style,
                          onPressed: loading ? null : select,
                          child: Text(item.$1),
                        )
                      : FilledButton.tonal(
                          style: style,
                          onPressed: loading ? null : select,
                          child: Text(item.$1),
                        ),
                );
              },
            ),
          ),
        ),
    ],
  );

  Widget postImage(
    ForumPost post,
    String heroTagPrefix,
    int index,
    dom.Element element,
  ) {
    if (index >= post.images.length) return const SizedBox.shrink();
    final url = post.images[index];
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final maxWidth = (MediaQuery.sizeOf(context).width - 64)
        .clamp(120, 900)
        .toDouble();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    final imageWidth = double.tryParse(element.attributes['width'] ?? '')
        ?.clamp(1, maxWidth)
        .toDouble();
    final imageHeight = double.tryParse(element.attributes['height'] ?? '')
        ?.clamp(1, maxHeight)
        .toDouble();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ForumImageGalleryPage(
            images: post.images,
            initialIndex: index,
            heroTagPrefix: heroTagPrefix,
          ),
        ),
      ),
      child: Hero(
        tag: '$heroTagPrefix:$index',
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Image.network(
            url,
            width: imageWidth,
            height: imageHeight,
            fit: BoxFit.contain,
            headers: forumMediaHeaders(uri),
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : SizedBox(
                    width: imageWidth ?? 128,
                    height: imageHeight ?? 80,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(20),
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
    );
  }

  Widget videoCard(Uri uri, String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: AppSectionCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ForumVideoPage(url: uri, title: title),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.play_circle_outline_rounded,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title.isEmpty ? '播放论坛视频' : title)),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    ),
  );

  Widget postCard(ForumPost post, int index) {
    var imageIndex = 0;
    final heroTagPrefix = '${identityHashCode(heroScope)}:${post.id}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSectionCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ForumAvatar(url: post.avatar),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: post.profile.isEmpty
                          ? null
                          : () => openSite(post.author, post.profile),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.author,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (post.role.isNotEmpty) ForumLabel(post.role),
                          if (post.meta.isNotEmpty)
                            Text(
                              post.meta,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    index == 0 ? '楼主' : '${index + 1}楼',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectionArea(
                child: SizedBox(
                  width: double.infinity,
                  child: HtmlWidget(
                    post.content,
                    baseUrl: forumUri(widget.link.url),
                    textStyle: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(height: 1.65),
                    onTapUrl: (href) async {
                      final uri = forumUri(href);
                      if (isDirectVideoUri(uri)) {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ForumVideoPage(url: uri, title: '论坛视频'),
                          ),
                        );
                        return true;
                      }
                      await openForum(
                        context,
                        ForumLink('链接', href),
                        widget.client,
                        widget.preferences,
                      );
                      return true;
                    },
                    customWidgetBuilder: (element) {
                      if (element.localName == 'a' &&
                          element.classes.contains('forum-video')) {
                        final uri = forumUri(element.attributes['href'] ?? '');
                        if (isDirectVideoUri(uri)) {
                          return videoCard(uri, element.text.trim());
                        }
                      }
                      if (element.localName == 'a') {
                        final images = element.querySelectorAll('img');
                        if (images.isNotEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final image in images)
                                postImage(
                                  post,
                                  heroTagPrefix,
                                  imageIndex++,
                                  image,
                                ),
                            ],
                          );
                        }
                      }
                      if (element.localName == 'img') {
                        return postImage(
                          post,
                          heroTagPrefix,
                          imageIndex++,
                          element,
                        );
                      }
                      return null;
                    },
                    customStylesBuilder: (element) => {
                      if (element.localName == 'a') 'overflow-wrap': 'anywhere',
                      if (element.localName == 'pre' ||
                          element.classes.contains('blockcode'))
                        'white-space': 'pre-wrap',
                    },
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => writeReply(post),
                  icon: const Icon(Icons.reply, size: 18),
                  label: const Text('回复'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final regular = links.where((e) => !e.pinned).toList();
    return PopScope(
      canPop: !replyDirty && !replySending,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop &&
            !replySending &&
            await discardReply() &&
            context.mounted) {
          setState(() => replyDirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: ReviewFrostedAppBar(
          title: Text(
            widget.link.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: loading ? null : () => load(),
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) async {
                if (value == 'copy') {
                  await Clipboard.setData(
                    ClipboardData(text: forumUri(url).toString()),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('链接已复制')));
                  }
                }
                if (value == 'favorite' && context.mounted) {
                  await openSite(
                    '收藏帖子',
                    'home.php?mod=spacecp&ac=favorite&type=thread&id=$currentThreadId',
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'copy', child: Text('复制链接')),
                if (isThread && currentThreadId != null)
                  const PopupMenuItem(value: 'favorite', child: Text('收藏到论坛')),
              ],
            ),
          ],
        ),
        bottomNavigationBar: isThread ? replyBar() : null,
        floatingActionButton: isThread
            ? null
            : (boardId(forumUri(url)) == null
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => openSite(
                        '发帖',
                        'forum.php?mod=post&action=newthread&fid=${boardId(forumUri(url))}',
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('发帖'),
                    )),
        body: RefreshIndicator(
          onRefresh: () => load(),
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
          child: ListView.builder(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
              16,
              MediaQuery.paddingOf(context).bottom + (isThread ? 24 : 88),
            ),
            itemCount: (isThread ? posts.length : regular.length) + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isThread && document?.board != null)
                      boardHeader(document!.board!),
                    if (isThread && document != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          document!.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    if (!isThread && boardId(forumUri(url)) != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: boardFilters(),
                      ),
                    if (document?.notice.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(document!.notice),
                      ),
                    if (!isThread && links.any((e) => e.pinned))
                      pinnedThreads(),
                  ],
                );
              }

              final count = isThread ? posts.length : regular.length;
              if (index <= count) {
                return isThread
                    ? postCard(posts[index - 1], index - 1)
                    : ThreadTile(
                        key: ValueKey('$listVersion:${regular[index - 1].url}'),
                        link: regular[index - 1],
                        loadSummary: boardId(forumUri(url)) == null
                            ? null
                            : (active) =>
                                  summaryFor(regular[index - 1], active),
                        onTap: () => openForum(
                          context,
                          regular[index - 1],
                          widget.client,
                          widget.preferences,
                        ),
                      );
              }
              if (loading) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (error != null) {
                return FailurePanel(
                  message: error!,
                  retry: () => load(more: next != null),
                );
              }
              if (next != null) {
                return Center(
                  child: TextButton(
                    onPressed: () => load(more: true),
                    child: const Text('加载下一页'),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    count == 0 ? '没有可显示的内容' : '已经到底了',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class ForumLabel extends StatelessWidget {
  const ForumLabel(this.text, {super.key, this.hot = false});
  final String text;
  final bool hot;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: hot ? const Color(0xffff8a00) : const Color(0xffd9363e),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: hot ? const Color(0xff281300) : Colors.white),
      ),
    ),
  );
}

class ThreadTile extends StatefulWidget {
  const ThreadTile({
    super.key,
    required this.link,
    required this.onTap,
    this.loadSummary,
  });
  final ForumLink link;
  final VoidCallback onTap;
  final Future<ThreadSummary> Function(bool Function())? loadSummary;
  @override
  State<ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<ThreadTile> {
  ThreadSummary? summary;
  @override
  void initState() {
    super.initState();
    if (widget.loadSummary != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          final result = await widget.loadSummary!(() => mounted);
          if (mounted) setState(() => summary = result);
        } catch (_) {
          /* Existing list data remains available without a preview. */
        }
      });
    }
  }

  Widget metric(BuildContext context, IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 3),
      Text(value, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final theme = Theme.of(context);
    final author = link.author.isNotEmpty ? link.author : summary?.author ?? '';
    final role = summary?.role.isNotEmpty == true ? summary!.role : link.role;
    final excerpt = summary?.excerpt.isNotEmpty == true
        ? summary!.excerpt
        : link.excerpt;
    final likes = summary?.likes.isNotEmpty == true
        ? summary!.likes
        : link.likes;
    final metrics = <Widget>[
      if (link.views.isNotEmpty)
        metric(context, Icons.visibility_outlined, link.views),
      if (link.replies.isNotEmpty)
        metric(context, Icons.chat_bubble_outline, link.replies),
      if (likes.isNotEmpty) metric(context, Icons.favorite_outline, likes),
    ];
    final date = Text(
      link.date.split(' ').first,
      style: theme.textTheme.bodySmall,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (author.isNotEmpty) ...[
                  Row(
                    children: [
                      ForumAvatar(
                        url: link.imageUrl ?? summary?.avatar,
                        radius: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(author, style: theme.textTheme.bodyMedium),
                            if (role.isNotEmpty) ForumLabel(role),
                            if (summary?.uid.isNotEmpty == true)
                              Text(
                                'UID ${summary!.uid}',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Text.rich(
                  TextSpan(
                    children: [
                      if (link.hot)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_fire_department,
                                  color: Color(0xffff8a00),
                                  size: 18,
                                ),
                                SizedBox(width: 3),
                                ForumLabel('热门', hot: true),
                              ],
                            ),
                          ),
                        ),
                      TextSpan(text: link.title),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (excerpt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                if (metrics.isNotEmpty || link.date.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: MediaQuery.textScalerOf(context).scale(14) > 20
                        ? Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              ...metrics,
                              if (link.date.isNotEmpty) date,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: metrics,
                                ),
                              ),
                              if (link.date.isNotEmpty) date,
                            ],
                          ),
                  ),
                if (link.subtitle.isNotEmpty && author.isEmpty)
                  Text(
                    link.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class FailurePanel extends StatelessWidget {
  const FailurePanel({super.key, required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Icon(
          Icons.cloud_off_outlined,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(onPressed: retry, child: const Text('重试')),
          ],
        ),
      ],
    ),
  );
}
