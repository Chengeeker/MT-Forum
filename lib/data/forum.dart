import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

const forumOrigin = 'https://bbs.binmt.cc';
const forumUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

Uri forumUri(String path) => Uri.parse('$forumOrigin/').resolve(path);
bool isForumUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'bbs.binmt.cc' &&
    uri.userInfo.isEmpty &&
    (uri.port == 443);

bool isForumLoginUri(Uri uri) =>
    isForumUri(uri) &&
    uri.path == '/member.php' &&
    uri.queryParameters['mod'] == 'logging' &&
    (uri.queryParameters['action'] ?? 'login') == 'login';

bool isQQLoginUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    const {
      'graph.qq.com',
      'xui.ptlogin2.qq.com',
      'ssl.ptlogin2.qq.com',
    }.contains(uri.host);

bool requiresForumLogin(Uri uri) {
  if (!isForumUri(uri)) return false;
  final query = uri.queryParameters;
  if (uri.path == '/k_misign-sign.html' ||
      (uri.path == '/plugin.php' && query['operation'] == 'qiandao')) {
    return true;
  }
  if (uri.path == '/forum.php') return query['mod'] == 'post';
  if (uri.path != '/home.php') return false;
  if (query['mod'] == 'spacecp') return true;
  return query['mod'] == 'space' &&
      (query['do'] == 'pm' ||
          query['view'] == 'me' ||
          (query['do'] == 'profile' &&
              !query.containsKey('uid') &&
              !query.containsKey('username')));
}

bool isDirectVideoUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    const {
      '.mp4',
      '.m3u8',
      '.m4v',
      '.mov',
      '.webm',
    }.any(uri.path.toLowerCase().endsWith);

Map<String, String> forumMediaHeaders(Uri uri) =>
    isForumUri(uri) || uri.host == 'cdn.binmt.cc'
    ? {'Referer': '$forumOrigin/', 'User-Agent': forumUserAgent}
    : const {};

Uri? _secureMediaUri(String? source, Uri base) {
  if (source == null || source.trim().isEmpty) return null;
  try {
    final uri = base.resolve(source.trim());
    return uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? uri
        : null;
  } on FormatException {
    return null;
  }
}

String? _numericId(String? value) =>
    value != null && RegExp(r'^\d+$').hasMatch(value) ? value : null;

class ForumFailure implements Exception {
  const ForumFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ForumLink {
  const ForumLink(
    this.title,
    this.url, {
    this.subtitle = '',
    this.imageUrl,
    this.author = '',
    this.date = '',
    this.views = '',
    this.replies = '',
    this.pinned = false,
    this.hot = false,
    this.excerpt = '',
    this.role = '',
    this.likes = '',
    this.profile = '',
  });
  final String title, url, subtitle;
  final String author, date, views, replies;
  final String excerpt, role, likes, profile;
  final bool pinned, hot;
  final String? imageUrl;
  ForumLink copyWith({
    String? author,
    String? role,
    String? imageUrl,
    String? profile,
  }) => ForumLink(
    title,
    url,
    subtitle: subtitle,
    imageUrl: imageUrl ?? this.imageUrl,
    author: author ?? this.author,
    date: date,
    views: views,
    replies: replies,
    pinned: pinned,
    hot: hot,
    excerpt: excerpt,
    role: role ?? this.role,
    likes: likes,
    profile: profile ?? this.profile,
  );
  Map<String, String> toJson() => {
    'title': title,
    'url': url,
    'subtitle': subtitle,
  };
  factory ForumLink.fromJson(Map<String, dynamic> json) => ForumLink(
    json['title'] as String,
    json['url'] as String,
    subtitle: json['subtitle'] as String? ?? '',
  );
}

class ForumPost {
  const ForumPost(
    this.id,
    this.author,
    this.meta,
    this.content,
    this.profile, {
    this.images = const [],
    this.imagePreviews = const [],
    this.avatar,
    this.role = '',
  });
  final String id, author, meta, content, profile;
  final List<String> images;
  final List<String> imagePreviews;
  final String? avatar;
  final String role;
}

class ForumDocument {
  const ForumDocument({
    required this.title,
    this.links = const [],
    this.boards = const [],
    this.posts = const [],
    this.latest = const [],
    this.hot = const [],
    this.next,
    this.notice = '',
    this.online,
    this.board,
    this.likes = '',
    this.firstPostId = '',
    this.resolvedThreadId,
  });
  final ForumLink? board;
  final String likes;
  final String firstPostId;
  final String? resolvedThreadId;
  final String title, notice;
  final List<ForumLink> links, boards;
  final List<ForumLink> latest, hot;
  final int? online;
  final List<ForumPost> posts;
  final String? next;
}

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

String forumCodeText(Element block) {
  final pre = block.localName == 'pre' ? block : block.querySelector('pre');
  final source = pre != null
      ? pre.querySelector('code') ?? pre
      : block.querySelector('ol') ?? block.querySelector('code') ?? block;
  final output = StringBuffer();

  void append(Node node) {
    if (node is Text) {
      output.write(node.data);
    } else if (node is Element) {
      if (node.localName == 'br') {
        output.write('\n');
        return;
      }
      for (var i = 0; i < node.nodes.length; i++) {
        final child = node.nodes[i];
        if (node.localName == 'ol' &&
            child is Text &&
            child.data.trim().isEmpty) {
          continue;
        }
        append(child);
        if (node.localName == 'ol' &&
            child is Element &&
            child.localName == 'li' &&
            node.nodes
                .skip(i + 1)
                .any((next) => next is Element && next.localName == 'li')) {
          output.write('\n');
        }
      }
    }
  }

  append(source);
  return output.toString().replaceAll('\r\n', '\n');
}

final _noWrapDeclaration = RegExp(
  r'^\s*white-space\s*:\s*nowrap(?:\s*!\s*important)?\s*$',
  caseSensitive: false,
);
final _fixedWidthDeclaration = RegExp(
  r'^\s*(?:width|min-width|max-width)\s*:',
  caseSensitive: false,
);

Element? _ancestor(Element element, String tag) {
  for (Element? node = element.parent; node != null; node = node.parent) {
    if (node.localName == tag) return node;
  }
  return null;
}

String? threadId(Uri uri) =>
    RegExp(r'^/thread-(\d+)-').firstMatch(uri.path)?.group(1) ??
    (uri.path == '/forum.php' &&
            (uri.queryParameters['mod'] == 'viewthread' ||
                uri.queryParameters['mod'] == 'redirect')
        ? _numericId(uri.queryParameters['tid']) ??
              _numericId(uri.queryParameters['ptid'])
        : null);

bool isThreadLink(Uri uri) =>
    isForumUri(uri) &&
    (threadId(uri) != null ||
        (uri.path == '/forum.php' &&
            uri.queryParameters['mod'] == 'redirect' &&
            uri.queryParameters['goto'] == 'findpost' &&
            _numericId(uri.queryParameters['pid']) != null));

String? boardId(Uri uri) =>
    RegExp(r'^/forum-(\d+)-').firstMatch(uri.path)?.group(1) ??
    (uri.queryParameters['mod'] == 'forumdisplay'
        ? _numericId(uri.queryParameters['fid'])
        : null);

String? authorAvatar(String? href, Uri base) {
  if (href == null) return null;
  final uri = base.resolve(href);
  if (!isForumUri(uri)) return null;
  final uid =
      RegExp(r'^/space-uid-(\d{1,9})\.html$').firstMatch(uri.path)?.group(1) ??
      _numericId(uri.queryParameters['uid']);
  if (uid == null || uid.length > 9) return null;
  final id = uid.padLeft(9, '0');
  return 'https://cdn.binmt.cc/uc_server/data/avatar/${id.substring(0, 3)}/${id.substring(3, 5)}/${id.substring(5, 7)}/${id.substring(7)}_avatar_middle.jpg';
}

String _forumProfile(String? href, Uri base) {
  if (href == null) return '';
  try {
    final uri = base.resolve(href);
    return isForumUri(uri) ? uri.toString() : '';
  } on FormatException {
    return '';
  }
}

ForumDocument parseForum(String source, Uri base) {
  final doc = html.parse(source);
  final title = _clean(
    doc.querySelector('#thread_subject')?.text ??
        doc.querySelector('h1')?.text ??
        doc.querySelector('title')?.text ??
        'MT论坛',
  );
  if (title.contains('403') ||
      source.contains('Sorry, you have been blocked')) {
    throw const ForumFailure('网站拒绝了本次访问（403）。请使用中国大陆网络，或在官网登录后重试。');
  }
  final threadSeen = <String>{};
  final boards = <ForumLink>[];
  final links = <ForumLink>[];
  final threadList = doc.querySelector('#threadlist');
  final roots = boardId(base) != null && threadList != null
      ? [threadList]
      : doc.querySelectorAll('#threadlist, #category_grid, #chart, .fl, .bm_c');
  final anchors = roots.isEmpty
      ? doc.querySelectorAll('a[href]')
      : roots.expand((r) => r.querySelectorAll('a[href]'));
  for (final a in anchors) {
    final uri = base.resolve(a.attributes['href']!);
    if (!isForumUri(uri)) continue;
    final label = _clean(a.text);
    if (label.isEmpty || RegExp(r'^\d+$').hasMatch(label)) continue;
    final tid = threadId(uri);
    if (tid != null && threadSeen.add(tid)) {
      final searchCard = base.path == '/search.php' ? _ancestor(a, 'li') : null;
      final row =
          searchCard ?? _ancestor(a, 'tr') ?? _ancestor(a, 'tbody') ?? a.parent;
      final paragraphs = searchCard?.querySelectorAll('p') ?? <Element>[];
      final counts = paragraphs.isEmpty ? '' : _clean(paragraphs.first.text);
      final searchMeta = paragraphs.length > 1 ? paragraphs.last : null;
      final by = _clean(row?.querySelector('.by')?.text ?? '');
      final user =
          row?.querySelector('.km_user a, .by cite a') ??
          searchMeta?.querySelector('a[href*="uid"],a[href*="username"]');
      final avatar = _secureMediaUri(
        row?.querySelector('.comiis_listtx img')?.attributes['src'],
        base,
      );
      links.add(
        ForumLink(
          label,
          '$forumOrigin/thread-$tid-1-1.html',
          subtitle: by,
          author: _clean(user?.text ?? ''),
          profile: _forumProfile(user?.attributes['href'], base),
          imageUrl:
              avatar?.toString() ??
              authorAvatar(user?.attributes['href'], base),
          excerpt: paragraphs.length > 2 ? _clean(paragraphs[1].text) : '',
          date: searchMeta != null
              ? _clean(searchMeta.text).split(' - ').first
              : _clean(
                  row?.querySelector('.km_user + em span, .by em span')?.text ??
                      '',
                ),
          views:
              RegExp(r'([\d.,万亿]+)\s*次?查看').firstMatch(counts)?.group(1) ??
              _clean(row?.querySelector('.km_view, .num em')?.text ?? ''),
          replies:
              RegExp(r'([\d.,万亿]+)\s*个?回复').firstMatch(counts)?.group(1) ??
              _clean(row?.querySelector('.km_reply, .num a')?.text ?? ''),
          pinned: _ancestor(a, 'tbody')?.id.startsWith('stickthread_') == true,
          hot: row?.querySelector('img[alt="heatlevel"]') != null,
        ),
      );
    }
  }
  for (final card in doc.querySelectorAll('.comiis_fl_g')) {
    final anchor = card.querySelector('a[href*="forum-"]');
    if (anchor == null) continue;
    final uri = base.resolve(anchor.attributes['href']!);
    final fid = boardId(uri);
    if (fid == null || !isForumUri(uri)) continue;
    final image = card.querySelector('img');
    final imageSrc = image?.attributes['src'] ?? image?.attributes['data-src'];
    final imageUri = imageSrc == null ? null : base.resolve(imageSrc);
    final imageUrl =
        imageUri != null &&
            imageUri.scheme == 'https' &&
            (imageUri.host == 'cdn.binmt.cc' || isForumUri(imageUri))
        ? imageUri.toString()
        : null;
    final title = _clean(
      card.querySelector('dt a')?.text ??
          image?.attributes['alt'] ??
          anchor.text,
    );
    if (title.isEmpty) continue;
    if (!boards.any((board) => boardId(Uri.parse(board.url)) == fid)) {
      boards.add(
        ForumLink(title, '$forumOrigin/forum-$fid-1.html', imageUrl: imageUrl),
      );
    }
  }
  final posts = <ForumPost>[];
  for (final body in doc.querySelectorAll('[id^="postmessage_"]')) {
    final id = body.id.replaceFirst('postmessage_', '');
    final post =
        doc.getElementById('post_$id') ?? _ancestor(body, 'table') ?? body;
    final user = post.querySelector(
      '.authi a.xw1, .authi a[href*="uid="], .pls .authi a',
    );
    final profile = user?.attributes['href'];
    // Keep media lazy and restricted to HTTPS; never preload a whole thread.
    final images = <String>[];
    final imagePreviews = <String>[];
    for (final image in body.querySelectorAll('img').toList()) {
      final src =
          image.attributes['file'] ??
          image.attributes['zoomfile'] ??
          image.attributes['data-src'] ??
          image.attributes['src'];
      final uri = _secureMediaUri(src, base);
      if (uri == null) {
        image.remove();
      } else {
        final preview =
            [
                  image.attributes['src'],
                  image.attributes['data-src'],
                  image.attributes['data-original'],
                  image.attributes['file'],
                  image.attributes['zoomfile'],
                ]
                .map((source) => _secureMediaUri(source, base))
                .firstWhere(
                  (candidate) =>
                      candidate != null &&
                      !const {'none.gif', 'blank.gif', 'loading.gif'}.contains(
                        candidate.pathSegments.isEmpty
                            ? ''
                            : candidate.pathSegments.last.toLowerCase(),
                      ),
                  orElse: () => uri,
                )!;
        image.attributes['src'] = preview.toString();
        images.add(uri.toString());
        imagePreviews.add(preview.toString());
      }
    }

    for (final media in body.querySelectorAll('video, iframe, object, embed')) {
      final src =
          media.attributes['src'] ??
          media.attributes['data'] ??
          media.querySelector('source[src]')?.attributes['src'];
      final uri = _secureMediaUri(src, base);
      if (uri != null && isDirectVideoUri(uri)) {
        media.replaceWith(
          Element.tag('a')
            ..attributes['href'] = uri.toString()
            ..classes.add('forum-video')
            ..text = '播放视频',
        );
      } else {
        media.remove();
      }
    }
    for (final anchor in body.querySelectorAll('a[href]')) {
      final uri = _secureMediaUri(anchor.attributes['href'], base);
      if (uri != null && isDirectVideoUri(uri)) {
        anchor.classes.add('forum-video');
        if (anchor.text.trim().isEmpty) anchor.text = '播放视频';
      }
    }
    for (final unsafe in body.querySelectorAll('script, source, form, style')) {
      unsafe.remove();
    }
    for (final element in body.querySelectorAll('*')) {
      element.attributes.removeWhere(
        (name, _) => name.toString().toLowerCase().startsWith('on'),
      );
      final style = element.attributes['style'] ?? '';
      final declarations = style.split(';');
      final noWrap =
          element.localName == 'nobr' ||
          element.attributes.containsKey('nowrap') ||
          declarations.any(_noWrapDeclaration.hasMatch);
      final constrainWidth =
          element.localName != 'img' &&
          (element.attributes.containsKey('width') ||
              declarations.any(_fixedWidthDeclaration.hasMatch));
      if (!noWrap && !constrainWidth) continue;
      declarations
        ..removeWhere(
          (declaration) =>
              declaration.trim().isEmpty ||
              (noWrap && _noWrapDeclaration.hasMatch(declaration)) ||
              (constrainWidth && _fixedWidthDeclaration.hasMatch(declaration)),
        )
        ..addAll([if (noWrap) 'white-space:normal']);
      element.attributes
        ..remove('nowrap')
        ..remove('width')
        ..['style'] = declarations.join(';');
    }
    for (final table in body.querySelectorAll('table').toList().reversed) {
      final rows = table.querySelectorAll('tr');
      final cells = table.querySelectorAll('td,th');
      if (rows.length == 1 &&
          cells.length == 1 &&
          !cells.single.attributes.containsKey('colspan') &&
          !cells.single.attributes.containsKey('rowspan')) {
        final container = Element.tag('div');
        container.nodes.addAll(cells.single.nodes.toList());
        table.replaceWith(container);
      }
    }
    posts.add(
      ForumPost(
        id,
        _clean(user?.text ?? '论坛用户'),
        _clean(post.querySelector('.authi em')?.text ?? ''),
        body.innerHtml,
        profile == null ? '' : base.resolve(profile).toString(),
        images: images,
        imagePreviews: imagePreviews,
        avatar:
            _secureMediaUri(
              post
                  .querySelector('.avtm img,.avatar img,.avt img')
                  ?.attributes['src'],
              base,
            )?.toString() ??
            authorAvatar(profile, base),
        role: _clean(
          post.querySelector('.pls a[href*="ac=usergroup"]')?.text ?? '',
        ),
      ),
    );
  }
  final nextHref = doc.querySelector('.pg a.nxt, a.nxt')?.attributes['href'];
  final nextUri = nextHref == null ? null : base.resolve(nextHref);
  final notice = _clean(
    doc.querySelector('#messagetext, .alert_info, .alert_error')?.text ?? '',
  );
  if (links.isEmpty && boards.isEmpty && posts.isEmpty && notice.isEmpty) {
    throw const ForumFailure('页面未返回可识别的论坛内容。可能需要登录、验证，或网站结构已变化，请打开官网核对。');
  }
  List<ForumLink> section(int index) {
    final boxes = doc.querySelectorAll('.boxbg_7ree');
    if (boxes.length <= index) return [];
    final seen = <String>{};
    return boxes[index]
        .querySelectorAll('a[href]')
        .map((a) {
          final uri = base.resolve(a.attributes['href']!);
          final id = threadId(uri);
          if (id == null || !isForumUri(uri) || !seen.add(id)) return null;
          final tipHtml = html.parseFragment(a.attributes['tips'] ?? '');
          final tip = tipHtml.text ?? '';
          final user = tipHtml.querySelector('a[href*="uid"]');
          String field(String label, String end) =>
              RegExp(
                '$label[：:]\\s*(.*?)$end',
                dotAll: true,
              ).firstMatch(tip)?.group(1)?.trim() ??
              '';
          return ForumLink(
            _clean(a.attributes['title'] ?? a.text),
            '$forumOrigin/thread-$id-1-1.html',
            author: field('作者', r'时间[：:]'),
            profile: _forumProfile(user?.attributes['href'], base),
            imageUrl: authorAvatar(user?.attributes['href'], base),
            date: field('时间', r'浏览[：:]'),
            views: field('浏览', '次'),
            replies: field('回复', '次'),
          );
        })
        .whereType<ForumLink>()
        .where((a) => a.title.isNotEmpty)
        .toList();
  }

  final onlineText = doc.querySelector('#online')?.text ?? '';
  final online = int.tryParse(
    RegExp(r'总计\s*(\d+)').firstMatch(onlineText)?.group(1) ?? '',
  );
  final info = doc.querySelector('.comiis_listinfo');
  final boardImage = _secureMediaUri(
    info?.querySelector('.topico img')?.attributes['src'],
    base,
  );
  final boardTitle = _clean(info?.querySelector('h1 a')?.text ?? '');
  final boardStats = _clean(info?.querySelector('h1 span')?.text ?? '');
  final description = _clean(
    info?.querySelector('.comiis_infobox > div:not(.comiis_infotit)')?.text ??
        '',
  );
  String? resolvedThreadId = threadId(base);
  if (posts.isNotEmpty && resolvedThreadId == null) {
    for (final element in doc.querySelectorAll(
      'link[rel="canonical"][href], form[action*="mod=post"][action*="tid="]',
    )) {
      final target = base.resolve(
        element.attributes['href'] ?? element.attributes['action']!,
      );
      if (!isForumUri(target)) continue;
      resolvedThreadId =
          threadId(target) ??
          (target.path == '/forum.php' &&
                  target.queryParameters['mod'] == 'post' &&
                  target.queryParameters['action'] == 'reply'
              ? _numericId(target.queryParameters['tid'])
              : null);
      if (resolvedThreadId != null) break;
    }
  }
  return ForumDocument(
    title: title,
    links: links,
    boards: boards,
    posts: posts,
    resolvedThreadId: resolvedThreadId,
    latest: section(0),
    hot: section(3),
    online: online,
    board: boardTitle.isEmpty
        ? null
        : ForumLink(
            boardTitle,
            base.toString(),
            imageUrl: boardImage?.toString(),
            subtitle: [
              boardStats,
              description,
            ].where((s) => s.isNotEmpty).join('\n'),
          ),
    next: nextUri != null && isForumUri(nextUri) ? nextUri.toString() : null,
    notice: notice,
    likes: _clean(doc.querySelector('#recommendv_add')?.text ?? ''),
    firstPostId:
        doc
            .querySelectorAll('[id^="post_"]')
            .where((e) => RegExp(r'^post_\d+$').hasMatch(e.id))
            .firstOrNull
            ?.id
            .replaceFirst('post_', '') ??
        '',
  );
}

class ThreadSummary {
  ThreadSummary(ForumDocument document) {
    final post = document.posts.firstOrNull;
    if (post == null) throw const ForumFailure('帖子没有可读取的摘要。');
    if (document.firstPostId.isNotEmpty && post.id != document.firstPostId) {
      throw const ForumFailure('首楼不可读取，不使用其他用户的回复代替摘要。');
    }
    final body = html.parseFragment(post.content);
    for (final node in body.querySelectorAll(
      'script,style,.locked,.showhide,.quote',
    )) {
      node.remove();
    }
    for (final br in body.querySelectorAll('br')) {
      br.replaceWith(Text(' '));
    }
    final text = _clean(body.text ?? '');
    excerpt = String.fromCharCodes(text.runes.take(180));
    role = post.role;
    likes = document.likes;
    avatar = post.avatar;
    author = post.author;
    profile = post.profile;
    final profileUri = forumUri(post.profile);
    uid =
        RegExp(r'space-uid-(\d+)').firstMatch(profileUri.path)?.group(1) ??
        profileUri.queryParameters['uid'] ??
        '';
  }
  late final String excerpt, role, likes, author, uid;
  late final String profile;
  late final String? avatar;
}

class ForumClient {
  ForumClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
            ),
          );
  final Dio _dio;
  final _summaryQueue = [Future<void>.value(), Future<void>.value()];
  int _summarySlot = 0;
  Future<ThreadSummary> threadSummary(String url, bool Function() active) {
    final slot = _summarySlot++ % 2;
    final previous = _summaryQueue[slot];
    final result = () async {
      await previous;
      if (!active()) throw const ForumFailure('已离开此条目。');
      // Preview traffic must not occupy the hidden browser needed for navigation/login.
      return ThreadSummary(await _loadHttp(url));
    }();
    _summaryQueue[slot] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  CancelToken _sessionRequests = CancelToken();
  Future<String> Function(Uri)? browserRead;
  Future<String> Function({
    required String loginField,
    required String username,
    required String password,
    required int questionId,
    required String answer,
    required bool remember,
  })?
  browserLogin;
  Future<void> Function()? browserCancelLogin;
  Future<void> Function()? browserResetSession;
  static const platform = MethodChannel('bbs.binmt.cc/session');

  Future<void> logout() async {
    _sessionRequests.cancel('账号已退出');
    _sessionRequests = CancelToken();
    try {
      await browserResetSession?.call().timeout(const Duration(seconds: 5));
    } catch (_) {
      /* A broken renderer must not trap the account. */
    }
    await platform
        .invokeMethod<void>('clearForumSession', '$forumOrigin/')
        .timeout(const Duration(seconds: 10));
  }

  Future<String> login({
    String loginField = 'username',
    required String username,
    required String password,
    required int questionId,
    required String answer,
    required bool remember,
  }) async {
    final account = username.trim();
    if (!const {'username', 'email'}.contains(loginField)) {
      throw const ForumFailure('不支持的登录方式。');
    }
    if (account.isEmpty || password.isEmpty) {
      throw const ForumFailure('请输入账号和密码。');
    }
    if (account.length > 256 || password.length > 256) {
      throw const ForumFailure('账号或密码长度无效。');
    }
    final submit = browserLogin;
    if (submit == null) {
      throw const ForumFailure('论坛登录组件尚未就绪，请重启应用后重试。');
    }
    return submit(
      loginField: loginField,
      username: account,
      password: password,
      questionId: questionId,
      answer: answer.trim(),
      remember: remember,
    );
  }

  Future<void> cancelLogin() async {
    try {
      await browserCancelLogin?.call().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Cancellation must always release the native form, even after renderer failure.
    }
  }

  Future<ForumDocument> load(String url) async {
    final requests = _sessionRequests;
    final uri = forumUri(url);
    if (!isForumUri(uri)) throw const ForumFailure('已阻止向站外发送论坛会话。');
    try {
      return await _loadHttp(url);
    } on ForumFailure {
      if (requests.isCancelled) throw const ForumFailure('账号状态已变化，请刷新。');
      if (browserRead == null) rethrow;
      return parseForum(await browserRead!(uri), uri);
    }
  }

  Future<ForumDocument> _loadHttp(String url) async {
    final result = await _requestSource(forumUri(url));
    return parseForum(result.$1, result.$2);
  }

  Future<String> source(String url) async {
    final requests = _sessionRequests;
    final uri = forumUri(url);
    if (!isForumUri(uri)) throw const ForumFailure('已阻止站外论坛请求。');
    try {
      return (await _requestSource(uri)).$1;
    } on ForumFailure {
      if (requests.isCancelled) throw const ForumFailure('账号状态已变化，请刷新。');
      if (browserRead == null) rethrow;
      return browserRead!(uri);
    }
  }

  Future<(String, Uri)> submit(
    Uri action,
    Map<String, dynamic> fields, {
    String method = 'POST',
  }) {
    if (!isForumUri(action)) throw const ForumFailure('已阻止向站外提交论坛表单。');
    if (!const {'GET', 'POST'}.contains(method)) {
      throw const ForumFailure('不支持的论坛表单方式。');
    }
    return _requestSource(action, fields: fields, method: method);
  }

  Future<(String, Uri)> _requestSource(
    Uri target, {
    Map<String, dynamic>? fields,
    String method = 'GET',
  }) async {
    var uri = target;
    final sessionRequests = _sessionRequests;
    for (var redirect = 0; redirect < 5; redirect++) {
      if (!isForumUri(uri)) throw const ForumFailure('已阻止向站外发送论坛会话。');
      final encoded = (fields ?? {}).entries
          .expand((entry) {
            final values = entry.value is List
                ? entry.value as List
                : [entry.value];
            return values.map(
              (value) =>
                  '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value.toString())}',
            );
          })
          .join('&');
      final requestUri = method == 'GET' && encoded.isNotEmpty
          ? uri.replace(query: '${uri.hasQuery ? '${uri.query}&' : ''}$encoded')
          : uri;
      String cookie = '';
      try {
        cookie =
            await platform
                .invokeMethod<String>('cookies', uri.toString())
                .timeout(const Duration(seconds: 3)) ??
            '';
      } on MissingPluginException {
        /* No Android session in unit tests. */
      }
      try {
        final response = await _dio.request<List<int>>(
          requestUri.toString(),
          data: method == 'POST' ? encoded : null,
          cancelToken: sessionRequests,
          options: Options(
            method: method,
            contentType: Headers.formUrlEncodedContentType,
            responseType: ResponseType.bytes,
            followRedirects: false,
            validateStatus: (_) => true,
            headers: {
              'User-Agent': forumUserAgent,
              'Referer': '$forumOrigin/',
              if (cookie.isNotEmpty) 'Cookie': cookie,
            },
          ),
        );
        for (final value in response.headers['set-cookie'] ?? <String>[]) {
          if (sessionRequests.isCancelled) {
            throw const ForumFailure('账号状态已变化，请刷新。');
          }
          try {
            await platform.invokeMethod<void>('setCookie', {
              'url': uri.toString(),
              'cookie': value,
            });
          } on MissingPluginException {
            // Unit tests have no Android cookie store.
          }
        }
        final status = response.statusCode ?? 0;
        if (sessionRequests.isCancelled) {
          throw const ForumFailure('账号状态已变化，请刷新。');
        }
        if (status >= 300 && status < 400) {
          final location = response.headers.value('location');
          if (location == null) throw const ForumFailure('网站重定向缺少地址。');
          uri = requestUri.resolve(location);
          if (status == 301 || status == 302 || status == 303) {
            method = 'GET';
            fields = null;
          }
          if (method == 'GET') fields = null;
          continue;
        }
        if (status == 403) {
          throw const ForumFailure('网站拒绝访问（403），请检查是否使用中国大陆网络，或在官网完成验证后重试。');
        }
        if (status != 200) throw ForumFailure('网站暂时无法访问（HTTP $status），请稍后重试。');
        return (
          utf8.decode(response.data ?? [], allowMalformed: true),
          requestUri,
        );
      } on DioException {
        throw const ForumFailure('连接失败，请检查网络后重试；已加载的内容会保留。');
      }
    }
    throw const ForumFailure('网站重定向次数过多，请打开官网检查登录状态。');
  }
}
