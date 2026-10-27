import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum.dart';

class Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['https://example.com/steal'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class SummaryAdapter implements HttpClientAdapter {
  final pending = <Completer<ResponseBody>>[];
  final firstTwo = Completer<void>(), third = Completer<void>();
  int active = 0, maximum = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    active++;
    if (active > maximum) maximum = active;
    final value = Completer<ResponseBody>();
    pending.add(value);
    if (pending.length == 2) firstTwo.complete();
    if (pending.length == 3) third.complete();
    try {
      return await value.future;
    } finally {
      active--;
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('通知帖子跳转识别 ptid 和仅 pid，并限制同源', () {
    final ptid = forumUri(
      'forum.php?mod=redirect&goto=findpost&pid=901&ptid=123',
    );
    final pid = forumUri('forum.php?mod=redirect&goto=findpost&pid=901');
    expect(threadId(ptid), '123');
    expect(isThreadLink(ptid), isTrue);
    expect(isThreadLink(pid), isTrue);
    expect(
      isThreadLink(forumUri('forum.php?mod=redirect&goto=findpost&pid=bad')),
      isFalse,
    );
    expect(
      isThreadLink(
        Uri.parse(
          'https://example.com/forum.php?mod=redirect&goto=findpost&pid=901',
        ),
      ),
      isFalse,
    );
    final source =
        '<link rel="canonical" href="https://bbs.binmt.cc/thread-123-1-1.html">${File('test/fixtures/thread.html').readAsStringSync()}';
    expect(parseForum(source, pid).resolvedThreadId, '123');
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test('摘要最多两个请求，跳过已离开的条目且不占用隐藏浏览器', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, (_) async => '');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ForumClient.platform, null),
    );
    final adapter = SummaryAdapter();
    final client = ForumClient(dio: Dio()..httpClientAdapter = adapter);
    final first = client.threadSummary(
      '$forumOrigin/thread-1-1-1.html',
      () => true,
    );
    final second = client.threadSummary(
      '$forumOrigin/thread-2-1-1.html',
      () => true,
    );
    final cancelled = client.threadSummary(
      '$forumOrigin/thread-3-1-1.html',
      () => false,
    );
    final cancelCheck = expectLater(cancelled, throwsA(isA<ForumFailure>()));
    final fourth = client.threadSummary(
      '$forumOrigin/thread-4-1-1.html',
      () => true,
    );
    await adapter.firstTwo.future.timeout(const Duration(seconds: 3));
    expect(adapter.pending.length, 2);
    final source = File('test/fixtures/thread.html').readAsStringSync();
    for (final item in adapter.pending.toList()) {
      item.complete(ResponseBody.fromString(source, 200));
    }
    await Future.wait([first, second]);
    await adapter.third.future.timeout(const Duration(seconds: 3));
    expect(adapter.pending.length, 3);
    adapter.pending.last.complete(ResponseBody.fromString(source, 200));
    await fourth;
    await cancelCheck;
    expect(adapter.maximum, 2);
    var browserReads = 0;
    final rejected = ForumClient(dio: Dio()..httpClientAdapter = Adapter())
      ..browserRead = (_) async {
        browserReads++;
        return source;
      };
    await expectLater(
      rejected.threadSummary('$forumOrigin/thread-1-1-1.html', () => true),
      throwsA(isA<ForumFailure>()),
    );
    expect(browserReads, 0);
  });
  test('帖子详情读取真实头像、默认头像、用户组及摘要点赞', () {
    final data = parseForum(
      File('test/fixtures/thread.html').readAsStringSync(),
      forumUri('thread-123-1-1.html'),
    );
    expect(data.posts.first.avatar, 'https://cdn.binmt.cc/avatar.jpg');
    expect(data.posts.last.avatar, contains('noavatar_big.gif'));
    expect(data.posts.first.role, '管理员');
    final summary = ThreadSummary(data);
    expect(summary.excerpt, contains('用于测试列表摘要'));
    expect(summary.likes, '29');
    final hidden = parseForum(
      '<title>受限主题</title><div id="post_1"><div class="locked">首楼不可见</div></div><div id="post_2"><div id="postmessage_2">其他人的回复</div></div>',
      forumUri('thread-1-1-1.html'),
    );
    expect(() => ThreadSummary(hidden), throwsA(isA<ForumFailure>()));
  });
  test('导读按行读取作者和计数，不把整个 tbody 当一个帖子', () {
    final data = parseForum(
      File('test/fixtures/guide.html').readAsStringSync(),
      forumUri('forum.php?mod=guide&view=newthread'),
    );
    expect(data.links.map((e) => e.author), ['最新作者', '另一作者']);
    expect(data.links.map((e) => e.views), ['84', '99']);
    expect(
      data.links.first.imageUrl,
      'https://cdn.binmt.cc/uc_server/data/avatar/000/00/01/23_avatar_middle.jpg',
    );
    expect(
      authorAvatar('https://example.com/space-uid-123.html', forumUri('/')),
      isNull,
    );
  });
  test('板块当前模板解析统计、置顶、作者头像和帖子数据', () {
    final data = parseForum(
      File('test/fixtures/board.html').readAsStringSync(),
      forumUri('forum-2-1.html'),
    );
    expect(data.board!.title, '版本发布');
    expect(data.board!.subtitle, contains('主题: 148'));
    expect(data.board!.imageUrl, contains('common_2_icon.png'));
    expect(data.links.length, 2);
    expect(data.links.first.pinned, isTrue);
    final link = data.links.last;
    expect(link.author, '测试作者');
    expect(link.imageUrl, 'https://cdn.binmt.cc/avatar.jpg');
    expect(link.views, '12815');
    expect(link.replies, '103');
    expect(link.date, '2026-10-9');
    expect(link.hot, isTrue);
  });
  test('QQ 授权只允许已核对的 HTTPS 官方主机', () {
    expect(
      isQQLoginUri(Uri.parse('https://graph.qq.com/oauth2.0/show')),
      isTrue,
    );
    expect(
      isQQLoginUri(Uri.parse('https://xui.ptlogin2.qq.com/cgi-bin/xlogin')),
      isTrue,
    );
    for (final address in [
      'http://graph.qq.com/',
      'https://graph.qq.com.evil.test/',
      'https://graph.qq.com:444/',
      'https://user@graph.qq.com/',
    ]) {
      expect(isQQLoginUri(Uri.parse(address)), isFalse);
    }
  });
  test('账号入口要求登录，公开资料和注册不被拦截', () {
    for (final path in [
      'home.php?mod=space&do=pm',
      'home.php?mod=space&do=profile',
      'home.php?mod=space&do=thread&view=me',
      'home.php?mod=space&do=favorite&view=me',
      'home.php?mod=spacecp&ac=favorite&type=thread&id=123',
      'forum.php?mod=post&action=reply&tid=123',
      'forum.php?mod=post&action=newthread&fid=2',
    ]) {
      expect(requiresForumLogin(forumUri(path)), isTrue, reason: path);
    }
    for (final path in [
      'home.php?mod=space&do=profile&uid=123',
      'member.php?mod=register',
      'forum-2-1.html',
      'https://example.com/home.php?mod=space&do=pm',
    ]) {
      expect(requiresForumLogin(forumUri(path)), isFalse, reason: path);
    }
    expect(
      isForumLoginUri(forumUri('member.php?mod=logging&action=login')),
      isTrue,
    );
    expect(
      isForumLoginUri(forumUri('member.php?mod=logging&action=logout')),
      isFalse,
    );
    expect(
      isForumLoginUri(
        Uri.parse('https://example.com/member.php?mod=logging&action=login'),
      ),
      isFalse,
    );
  });
  test('真实首页结构：板块、热门、最新来自不同分区', () {
    final source = File('test/fixtures/home.html');
    final data = parseForum(source.readAsStringSync(), forumUri('/'));
    expect(data.boards.length, 12);
    expect(data.boards.first.title, '版本发布');
    expect(data.boards.every((board) => board.imageUrl != null), isTrue);
    expect(
      data.boards.first.imageUrl,
      'https://cdn.binmt.cc/data/attachment/common/c8/common_2_icon.png',
    );
    expect(data.latest.length, 10);
    expect(data.latest.first.author, 'loptanlang');
    expect(data.latest.first.views, '84');
    expect(data.latest.first.replies, '3');
    expect(data.latest.first.date, '2026-10-25 14:44:04');
    expect(data.hot.length, 10);
    expect(data.latest.first.url, isNot(data.hot.first.url));
    expect(data.online, greaterThan(0));
  });
  test('帖子正文、作者、懒加载图片与分页正确解析', () {
    final data = parseForum(
      '''<title>帖子</title><span id="thread_subject">原始标题</span>
      <div id="post_123"><div class="authi"><a class="xw1" href="space-uid-2.html">Bin</a><em>发表于今天</em></div>
      <div id="postmessage_123">正文<img file="/image.png"><script>evil()</script><iframe src="//bad.test"></iframe></div></div>
      <div class="pg"><a class="nxt" href="thread-99-2-1.html">下一页</a></div>''',
      forumUri('thread-99-1-1.html'),
    );
    expect(data.title, '原始标题');
    expect(data.posts.single.author, 'Bin');
    expect(data.posts.single.content, contains('$forumOrigin/image.png'));
    expect(data.posts.single.content, isNot(contains('script')));
    expect(data.posts.single.content, isNot(contains('iframe')));
    expect(data.next, '$forumOrigin/thread-99-2-1.html');
  });
  test('外站及非 HTTPS 地址不能携带会话或伪装为论坛帖子', () async {
    for (final url in [
      'http://bbs.binmt.cc/',
      'https://bbs.binmt.cc.evil.test/',
      'https://bbs.binmt.cc:444/',
      'javascript:alert(1)',
    ]) {
      expect(isForumUri(Uri.parse(url)), isFalse);
    }
    final adapter = Adapter();
    final client = ForumClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
      client.load('$forumOrigin/'),
      throwsA(isA<ForumFailure>()),
    );
    expect(adapter.requests, hasLength(1));
    final data = parseForum(
      '<a href="https://evil.test/thread-1-1-1.html">外站</a><div id="messagetext">请登录</div>',
      forumUri('/'),
    );
    expect(data.links, isEmpty);
    expect(data.notice, '请登录');
  });
  test('验证页和 403 不当作空帖子', () {
    for (final source in [
      '<title>403 Forbidden</title>',
      '<html><script>var arg1="x"</script></html>',
    ]) {
      expect(
        () => parseForum(source, forumUri('/')),
        throwsA(isA<ForumFailure>()),
      );
    }
  });
}
