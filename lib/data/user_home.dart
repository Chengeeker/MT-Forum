import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'forum.dart';
import 'native_forum.dart';

String _text(Element? node) =>
    node?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

class ForumUserHome {
  ForumUserHome(String source, Uri base) {
    final doc = html.parse(source);
    account = ForumAccount.parse(source, requireDetails: false);
    for (final field in account.fields) {
      if (field.$1 == '用户组') role = field.$2;
      if (field.$1 == '个人签名') signature = field.$2;
    }
    for (final anchor in doc.querySelectorAll('#uhd a[href]')) {
      final uri = base.resolve(anchor.attributes['href']!);
      if (!isForumUri(uri) || uri.path != '/home.php') continue;
      final q = uri.queryParameters;
      if (q['uid'] == account.uid) {
        final section = q['mod'] == 'follow' ? 'follow' : q['do'];
        if (q['mod'] == 'follow' || q['mod'] == 'space') {
          if (const ['thread', 'follow', 'wall'].contains(section)) {
            sections[section!] = uri;
          }
        }
      }
      if (q['mod'] == 'spacecp' &&
          const ['follow', 'friend', 'pm'].contains(q['ac']) &&
          (q['ac'] != 'follow' || const ['add', 'del'].contains(q['op'])) &&
          (q['fuid'] ?? q['touid'] ?? q['uid']) == account.uid &&
          _text(anchor).isNotEmpty) {
        actions[q['ac']!] = ForumLink(_text(anchor), uri.toString());
      }
    }
  }
  late final ForumAccount account;
  String role = '', signature = '';
  final sections = <String, Uri>{};
  final actions = <String, ForumLink>{};
}

Uri userTopicsUri(Uri profile) => forumUri('home.php').replace(
  queryParameters: {
    'mod': 'space',
    if (profile.queryParameters['uid'] case final String uid) 'uid': uid,
    if (profile.queryParameters['username'] case final String name)
      'username': name,
    'do': 'thread',
    'view': 'me',
    'type': 'thread',
    'from': 'space',
  },
);

class ForumMyPosts {
  ForumMyPosts(String source, Uri base, {String lastFilter = ''}) {
    final doc = html.parse(source);
    final content = ForumUserContent(source, base, topics: true);
    threads = content.threads;
    final type = base.queryParameters['type'] ?? 'thread';
    final filter = type == 'postcomment'
        ? ''
        : base.queryParameters['filter'] ?? '';
    final selection = base.replace(
      queryParameters: {
        ...base.queryParameters,
        'filter': type == 'postcomment' ? lastFilter : filter,
      },
    );
    for (final anchor in doc.querySelectorAll('.tbmu a[href]')) {
      final target = base.resolve(anchor.attributes['href']!);
      if (!_target(target)) continue;
      final label = _text(anchor);
      if (label.isEmpty) continue;
      final status = target.queryParameters.containsKey('filter');
      if (status && type == 'postcomment') continue;
      final row = status ? statuses : types;
      final url = _normalize(
        status
            ? target.replace(
                queryParameters: {...target.queryParameters, 'type': type},
              )
            : target,
        base: selection,
      ).toString();
      if (row.any((tab) => tab.url == url)) continue;
      row.add(
        ForumMessageTab(
          label: label,
          url: url,
          selected: status
              ? (target.queryParameters['filter'] ?? '') == filter
              : (target.queryParameters['type'] ?? 'thread') == type,
        ),
      );
    }
    if (type != 'thread') {
      String? tid;
      final snippets = <String, StringBuffer>{};
      final targets = <String, String>{};
      for (final row in doc.querySelectorAll('.tl tr')) {
        final subject = row.querySelector('th a[href]');
        if (subject != null) {
          final target = base.resolve(subject.attributes['href']!);
          tid = isForumUri(target) ? threadId(target) : null;
          final pid = target.queryParameters['pid'];
          if (tid != null && pid != null && RegExp(r'^\d+$').hasMatch(pid)) {
            targets.putIfAbsent(
              tid,
              () => forumUri('forum.php')
                  .replace(
                    queryParameters: {
                      'mod': 'redirect',
                      'goto': 'findpost',
                      'ptid': tid!,
                      'pid': pid,
                    },
                  )
                  .toString(),
            );
          }
        } else if (tid != null && row.querySelector('td[colspan]') != null) {
          final text = _text(row.querySelector('td[colspan]'));
          if (text.isNotEmpty) {
            (snippets[tid] ??= StringBuffer()).writeln(text);
          }
        }
      }
      threads = [
        for (final link in threads)
          link.copyWith(
            url: targets[threadId(forumUri(link.url))],
            excerpt: snippets[threadId(forumUri(link.url))] == null
                ? null
                : String.fromCharCodes(
                    snippets[threadId(forumUri(link.url))]!
                        .toString()
                        .trim()
                        .runes
                        .take(180),
                  ),
          ),
      ];
    }
    final currentPage = int.tryParse(base.queryParameters['page'] ?? '') ?? 1;
    var before = 0, after = 1 << 30;
    for (final anchor in doc.querySelectorAll('.pg a[href]')) {
      final target = base.resolve(anchor.attributes['href']!);
      final page = int.tryParse(target.queryParameters['page'] ?? '');
      if (!_target(target) || page == null || page < 1) continue;
      final url = _normalize(base, page: page).toString();
      if (page < currentPage && page > before) {
        before = page;
        previous = url;
      }
      if (page > currentPage && page < after) {
        after = page;
        next = url;
      }
    }
    emptyMessage = _text(doc.querySelector('.tl .emp'));
  }

  static bool _target(Uri uri) =>
      isForumUri(uri) &&
      uri.path == '/home.php' &&
      uri.queryParameters['mod'] == 'space' &&
      uri.queryParameters['do'] == 'thread' &&
      uri.queryParameters['view'] == 'me';

  static Uri _normalize(Uri uri, {Uri? base, int? page}) => forumUri('home.php')
      .replace(
        queryParameters: {
          'mod': 'space',
          'do': 'thread',
          'view': 'me',
          'type':
              uri.queryParameters['type'] ??
              base?.queryParameters['type'] ??
              'thread',
          if ((uri.queryParameters['type'] ?? base?.queryParameters['type']) !=
                  'postcomment' &&
              (uri.queryParameters.containsKey('filter') ||
                  base?.queryParameters.containsKey('filter') == true))
            'filter':
                uri.queryParameters['filter'] ??
                base!.queryParameters['filter']!,
          if (page != null) 'page': '$page',
        },
      );

  late List<ForumLink> threads;
  final statuses = <ForumMessageTab>[], types = <ForumMessageTab>[];
  String? previous, next;
  String emptyMessage = '';
}

bool _sameUserPage(Uri uri, Uri base) =>
    isForumUri(uri) &&
    uri.path == base.path &&
    uri.queryParameters['mod'] == base.queryParameters['mod'] &&
    uri.queryParameters['do'] == base.queryParameters['do'] &&
    uri.queryParameters['uid'] == base.queryParameters['uid'] &&
    uri.queryParameters['username'] == base.queryParameters['username'] &&
    uri.queryParameters['type'] == base.queryParameters['type'] &&
    uri.queryParameters['view'] == base.queryParameters['view'];

class ForumUserEntry {
  ForumUserEntry({
    required this.id,
    required this.author,
    required this.profile,
    required this.date,
    required this.body,
    this.avatar,
    this.thread,
    this.actions = const [],
  });
  final String id, author, profile, date, body;
  final String? avatar;
  final ForumLink? thread;
  final List<ForumLink> actions;
}

class ForumUserContent {
  ForumUserContent(
    String source,
    Uri base, {
    required bool topics,
    bool archivedAvailable = false,
  }) {
    final feedApi =
        base.queryParameters['mod'] == 'spacecp' &&
        base.queryParameters['ac'] == 'follow' &&
        base.queryParameters['op'] == 'getfeed';
    archiveAvailable = archivedAvailable;
    if (feedApi) {
      source =
          RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?.group(1) ??
          source;
      if (source.trim() == 'false') {
        if (base.queryParameters['archiver'] == '0' && archiveAvailable) {
          next = _feedPage(base, archive: true, page: 1);
        }
        return;
      }
    }
    final doc = html.parse(source);
    if (doc.querySelector('form[id^="loginform_"]') != null) {
      throw const ForumFailure('此内容需要登录后查看。');
    }
    // Reuse the shared sanitizer; raw site layout never reaches the page.
    final native = NativeForumDocument(source, base);
    final root =
        doc.querySelector('#ct .mn') ?? doc.querySelector('#ct') ?? doc.body!;
    if (topics) {
      final list = root.querySelector('#threadlist, .tl');
      // Discuz 的空筛选有 .emp 提示，不能交给要求存在帖子链接的解析器。
      if (list != null && _text(list.querySelector('.emp')).isEmpty) {
        final copy = list.clone(true)..id = 'threadlist';
        // The last poster column is not the author on a user's topic list.
        for (final by in copy.querySelectorAll('.by')) {
          by.querySelector('cite')?.remove();
        }
        threads = parseForum(
          '<div id="ct">${copy.outerHtml}</div>',
          base,
        ).links;
      } else if (_text(root.querySelector('.emp')).isEmpty) {
        throw ForumFailure(
          native.notice.isNotEmpty ? native.notice : '未能读取主题列表，请重试。',
        );
      }
    } else {
      for (final row in root.querySelectorAll(
        '[id^="feed_li_"], #comment_ul dl',
      )) {
        final broadcast = row.id.startsWith('feed_li_');
        final author = row.querySelector(
          broadcast ? '.flw_author a' : 'dt a[id^="author_"]',
        );
        final profile = forumUserProfile(
          author?.attributes['href'],
          base,
          username: _text(author),
        );
        final original = row.querySelector(
          broadcast ? '[id^="original_content_"]' : 'dd[id^="comment_"]',
        );
        final body = original == null
            ? null
            : native.content.querySelector('[id="${original.id}"]');
        final note = row.querySelector('.flw_quotenote');
        final title = row.querySelector(
          'h2 a[href*="tid="],h2 a[href*="thread-"]',
        );
        final target = title == null
            ? null
            : base.resolve(title.attributes['href']!);
        final links = <ForumLink>[];
        for (final a in row.querySelectorAll('dt a[href]')) {
          final action = base.resolve(a.attributes['href']!);
          if (isForumUri(action) &&
              action.queryParameters['mod'] == 'spacecp' &&
              action.queryParameters['ac'] == 'comment' &&
              const [
                'reply',
                'edit',
                'delete',
              ].contains(action.queryParameters['op'])) {
            links.add(ForumLink(_text(a), action.toString()));
          }
        }
        entries.add(
          ForumUserEntry(
            id: row.id,
            author: _text(author),
            profile: profile,
            avatar: authorAvatar(profile, base),
            date: _text(
              row.querySelector(
                broadcast ? '.flw_author span' : 'dt > span.xg1',
              ),
            ),
            body:
                '${note == null ? '' : '<p>${htmlEscape(_text(note))}</p>'}${body?.innerHtml ?? ''}',
            thread: target != null && isThreadLink(target) && isForumUri(target)
                ? ForumLink(_text(title), target.toString())
                : null,
            actions: links,
          ),
        );
      }
      if (base.queryParameters['do'] == 'wall') {
        final element = native.content.querySelector(
          'form[id^="quickcommentform_"]',
        );
        wallAvailable = element != null;
        if (element != null &&
            element.querySelector('textarea[name="message"]') != null) {
          final form = NativeForumForm(element, base);
          if (isForumUri(form.action) &&
              form.action.path == '/home.php' &&
              form.action.queryParameters['mod'] == 'spacecp' &&
              form.action.queryParameters['ac'] == 'comment' &&
              form.values()['idtype'] == 'uid' &&
              form.values()['id'] == base.queryParameters['uid']) {
            wallForm = form;
          }
        }
      }
      if (entries.isEmpty &&
          root.querySelector('.emp') == null &&
          !wallAvailable) {
        throw ForumFailure(
          native.notice.isNotEmpty ? native.notice : '未能读取该栏目的内容，请重试。',
        );
      }
    }
    emptyMessage = _text(root.querySelector('.emp'));
    final nextLink = root.querySelector('.pg a.nxt')?.attributes['href'];
    if (nextLink != null) {
      final target = base.resolve(nextLink);
      if (_sameUserPage(target, base) && target != base) next = target;
    }
    if (!topics && entries.isNotEmpty && base.queryParameters['uid'] != null) {
      if (feedApi) {
        next = _feedPage(
          base,
          archive: base.queryParameters['archiver'] == '1',
          page: (int.tryParse(base.queryParameters['page'] ?? '') ?? 1) + 1,
        );
      } else if (base.queryParameters['mod'] == 'follow' &&
          source.contains('op=getfeed')) {
        final flags = RegExp(
          r'feedInfo\s*=\s*\{[^}]*archiver:\s*([01])[^}]*primary:\s*([01])',
        ).firstMatch(source);
        archiveAvailable = flags?.group(1) == '1';
        if (flags?.group(2) == '1' || archiveAvailable) {
          next = _feedPage(base, archive: flags?.group(2) != '1', page: 2);
        }
      }
    }
  }
  List<ForumLink> threads = [];
  final entries = <ForumUserEntry>[];
  Uri? next;
  String emptyMessage = '';
  NativeForumForm? wallForm;
  bool wallAvailable = false;
  bool archiveAvailable = false;
}

Uri _feedPage(Uri base, {required bool archive, required int page}) =>
    forumUri('home.php').replace(
      queryParameters: {
        'mod': 'spacecp',
        'ac': 'follow',
        'op': 'getfeed',
        'uid': base.queryParameters['uid']!,
        'archiver': archive ? '1' : '0',
        'page': '$page',
        'inajax': '1',
        'banavatar': '1',
      },
    );

String htmlEscape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
