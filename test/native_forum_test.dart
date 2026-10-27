import 'dart:typed_data';
import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/native_forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/pages/login_page.dart';
import 'package:mt_forum/pages/native_forum_page.dart';
import 'package:mt_forum/pages/account_page.dart';
import 'package:mt_forum/pages/web_page.dart';
import 'package:mt_forum/core/design_system/components/review_frosted_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

const replyFixture = '''<html><title>回复</title><div id="ct"><div class="mn"><form id="postform" method="post" action="forum.php?mod=post&amp;action=reply&amp;tid=123&amp;replysubmit=yes">
<input type="hidden" name="formhash" value="fixture-token"><input type="hidden" name="noticeauthor" value="fixture-author">
<input type="hidden" name="wysiwyg" value="1"><div id="e_controls"><a href="javascript:;">网页版编辑器</a></div>
<input name="subject" value="RE:测试"><textarea name="message">[quote]被引用内容[/quote]\n</textarea>
<input type="checkbox" name="usesig" value="1" checked><button type="submit" name="replysubmit" value="yes">参与/回复主题</button>
</form></div></div></html>''';

class NativeClient extends ForumClient {
  final requests = <String>[];
  Map<String, dynamic>? submitted;
  bool fail = false;
  @override
  Future<String> source(String url) async {
    requests.add(url);
    if (url.contains('mod=logging')) {
      return '<a href="member.php?mod=register213">立即注册</a>';
    }
    if (url.contains('do=profile')) {
      return '<div id="uhd"><h2>测试账号</h2></div><div id="ct"><div class="mn"><div class="area"></div><div class="bm"><h2>测试账号 (UID: 123)</h2><ul><li><em>用户组</em>测试组</li><li><em>积分</em>100</li><li><em>注册 IP</em>192.0.2.1</li></ul></div></div></div>';
    }
    return url.contains('action=reply') || url.contains('action=newthread')
        ? (url.contains('repquote=')
              ? replyFixture
              : replyFixture.replaceFirst('[quote]被引用内容[/quote]', ''))
        : '<title>原生内容</title><div id="ct"><div class="mn"><h2>原生功能内容</h2><p>资料与消息内容</p></div></div>';
  }

  @override
  Future<(String, Uri)> submit(
    Uri action,
    Map<String, dynamic> fields, {
    String method = 'POST',
  }) async {
    submitted = fields;
    if (fail) throw const ForumFailure('模拟提交失败');
    return (
      '<div id="messagetext">回复成功</div>',
      forumUri('thread-123-1-1.html'),
    );
  }
}

class SignClient extends NativeClient {
  bool signed = false, reject = false;
  int writes = 0;
  @override
  Future<String> source(String url) async {
    requests.add(url);
    final text = File('test/fixtures/sign.html').readAsStringSync();
    return signed
        ? text
              .replaceAll('您今天还没有签到', '您今天已经签到')
              .replaceFirst(RegExp(r'<a id="JD_sign"[\s\S]*?</a>'), '')
        : text;
  }

  @override
  Future<(String, Uri)> submit(
    Uri action,
    Map<String, dynamic> fields, {
    String method = 'POST',
  }) async {
    writes++;
    if (reject) throw const ForumFailure('模拟签到失败');
    signed = true;
    return ('<div id="messagetext">签到成功</div>', action);
  }
}

class MessagesClient extends NativeClient {
  @override
  Future<String> source(String url) async =>
      File('test/fixtures/messages.html').readAsStringSync();
}

class PrivacyClient extends NativeClient {
  @override
  Future<String> source(String url) async {
    requests.add(url);
    final feed = url.contains('op=feed');
    return '<div id="ct"><div class="mn"><ul class="tb">'
        '<li ${feed ? '' : 'class="a"'}><a href="home.php?mod=spacecp&amp;ac=privacy&amp;op=filter">筛选设置</a></li>'
        '<li ${feed ? 'class="a"' : ''}><a href="home.php?mod=spacecp&amp;ac=privacy&amp;op=feed">个人动态发布设置</a></li>'
        '</ul><form method="post" action="home.php?mod=spacecp&amp;ac=privacy&amp;op=filter">'
        '<input type="hidden" name="formhash" value="fixture-token">'
        '<table><caption><h2>屏蔽好友组</h2></caption><tr><td>'
        '<label><input type="checkbox" name="privacy[filter_gid][0]" value="0">好友</label>'
        '</td></tr><tr><td><button type="submit" name="privacy2submit" value="true">保存</button></td></tr></table>'
        '<table><caption><h2>屏蔽提醒</h2><p>选择要过滤的提醒</p></caption><tr><td>'
        '<label><input type="checkbox" name="privacy[filter_note][post]" value="1">回复提醒</label>'
        '</td></tr><tr><td><button type="submit" name="privacy2submit" value="true">保存</button></td></tr></table>'
        '</form></div></div>';
  }
}

class NoticeLayoutClient extends NativeClient {
  @override
  Future<String> source(String url) async =>
      '<div id="ct"><div class="mn"><div class="nts"><dl>'
      '<dt><a href="home.php?mod=spacecp&amp;ac=common&amp;op=ignore">屏蔽</a> '
      '<span>昨天 08:52 </span></dt><dd>'
      '<a href="space-uid-1.html">康哥</a> 回复了您的帖子 '
      '<a href="thread-123-1-1.html">主题标题</a> '
      '<a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=1">查看</a>'
      '</dd></dl></div></div></div>';
}

class EmptyAccountClient extends NativeClient {
  @override
  Future<String> source(String url) async =>
      '<div id="ct"><div class="mn"></div></div>';
}

class SubmitAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  String redirect = '/thread-123-1-1.html';
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    bodies.add(String.fromCharCodes(bytes));
    return requests.length == 1
        ? ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': [redirect],
              'set-cookie': ['forum_auth=updated; Path=/; Secure; HttpOnly'],
            },
          )
        : ResponseBody.fromString('<div id="messagetext">回复成功</div>', 200);
  }

  @override
  void close({bool force = false}) {}
}

class SearchClient extends NativeClient {
  @override
  Future<String> source(String url) async =>
      '<div id="hd"><form id="scform" method="post" action="search.php?searchsubmit=yes"><input type="hidden" name="formhash" value="search-token"><input name="srchtxt"><button name="searchsubmit" type="submit">搜索</button></form></div><div id="ct">首页</div>';
  @override
  Future<(String, Uri)> submit(
    Uri action,
    Map<String, dynamic> fields, {
    String method = 'POST',
  }) async {
    submitted = fields;
    return (
      '<div id="threadlist"><a href="thread-123-1-1.html">原生搜索结果</a></div>',
      forumUri('search.php?mod=forum&searchid=123'),
    );
  }
}

class CancellingAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await cancelFuture;
    throw DioException(requestOptions: options, type: DioExceptionType.cancel);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('签到模型恢复 CSS 数字并隔离隐藏数字、网页面包屑', () {
    final data = NativeForumDocument(
      File('test/fixtures/sign.html').readAsStringSync(),
      forumUri('k_misign-sign.html'),
    );
    expect(data.signIn!.stats, contains(('总天数', '124天')));
    expect(data.signIn!.stats, contains(('连续签到', '1天')));
    expect(data.signIn!.participants, '2404人');
    expect(data.signIn!.rules!.url, contains('operation=rewardrule'));
    expect(
      data.signIn!.ranks!.querySelector('[data-native-navigation]'),
      isNotNull,
    );
    expect(data.content.querySelector('#pt'), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('签到专用布局和消息导航在 $scale 倍字体下不溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final preferences = Preferences(await SharedPreferences.getInstance());
      for (final messages in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: NativeForumPage(
              key: ValueKey(messages),
              title: messages ? '消息' : '签到',
              uri: forumUri(
                messages ? 'home.php?mod=space&do=pm' : 'k_misign-sign.html',
              ),
              client: messages ? MessagesClient() : SignClient(),
              preferences: preferences,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (messages) {
          expect(find.text('系统提醒'), findsOneWidget);
          expect(find.byType(SegmentedButton<String>), findsNWidgets(2));
          expect(find.widgetWithText(FilledButton, '发送消息'), findsOneWidget);
          expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
        } else {
          expect(find.byType(ForumSignInView), findsOneWidget);
          expect(find.text('124天'), findsOneWidget);
          expect(find.text('2453'), findsNothing);
          expect(find.textContaining('MT论坛 »'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
  for (final reject in [false, true]) {
    testWidgets('签到 $reject 失败不重试，成功后按服务器状态禁用按钮', (tester) async {
      final client = SignClient()..reject = reject;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeForumPage(
            title: '签到',
            uri: forumUri('k_misign-sign.html'),
            client: client,
            preferences: Preferences(await SharedPreferences.getInstance()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '立即签到'));
      await tester.pumpAndSettle();
      expect(client.writes, 1);
      expect(find.text(reject ? '立即签到' : '今日已签到'), findsOneWidget);
      if (reject) expect(find.textContaining('未自动重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          ForumClient.platform,
          (_) async => 'forum_auth=fixture',
        );
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, null),
  );

  test('回复表单保留 CSRF、引用字段和 BBCode，移除网页编辑器脚本', () {
    final document = NativeForumDocument(
      replyFixture,
      forumUri('forum.php?mod=post&action=reply&tid=123'),
    );
    final form = NativeForumForm(
      document.content.querySelector('form')!,
      document.uri,
    );
    expect(form.values()['formhash'], 'fixture-token');
    expect(form.values()['noticeauthor'], 'fixture-author');
    expect(form.values()['message'], contains('[quote]被引用内容[/quote]'));
    expect(form.values()['wysiwyg'], '0');
    expect(document.content.querySelector('#e_controls'), isNull);
    expect(isForumUri(form.action), isTrue);
  });

  test('提交字段尊重复选框和禁用字段，站外 action 保留供请求边界拒绝', () {
    final element = html
        .parse(
          '<form action="https://example.com/"><input name="a" value="1" disabled><input type="checkbox" name="b" value="2"><input type="checkbox" name="c" value="3" checked></form>',
        )
        .querySelector('form')!;
    final form = NativeForumForm(element, forumUri('/'));
    expect(form.values(), {'c': '3'});
    expect(isForumUri(form.action), isFalse);
    expect(
      () => ForumClient().submit(form.action, {}),
      throwsA(isA<ForumFailure>()),
    );
  });

  test('原生提交编码正文、共享会话并写回 Cookie，302 后不重复 POST', () async {
    final updates = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, (call) async {
          if (call.method == 'setCookie') {
            updates.add(call.arguments as Map);
            return null;
          }
          return updates.isEmpty ? 'forum_auth=original' : 'forum_auth=updated';
        });
    final adapter = SubmitAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final result = await ForumClient(dio: dio)
        .submit(forumUri('forum.php?mod=post&action=reply&tid=123'), {
          'formhash': 'fixture-token',
          'message': '你好 & reply',
          'replysubmit': 'yes',
          'deletepm[]': ['1', '2'],
        });
    expect(adapter.requests.map((e) => e.method), ['POST', 'GET']);
    expect(Uri.splitQueryString(adapter.bodies.first)['message'], '你好 & reply');
    expect(adapter.bodies.last, isEmpty);
    expect(Uri(query: adapter.bodies.first).queryParametersAll['deletepm[]'], [
      '1',
      '2',
    ]);
    expect(adapter.bodies.first, isNot(contains('%5B%5D%5B%5D')));
    expect(adapter.requests.first.headers['Cookie'], 'forum_auth=original');
    expect(adapter.requests.last.headers['Cookie'], 'forum_auth=updated');
    expect(updates.single['url'], startsWith(forumOrigin));
    expect(result.$2.path, '/thread-123-1-1.html');
  });

  test('提交的站外重定向在第二次请求前被拒绝', () async {
    final adapter = SubmitAdapter()..redirect = 'https://example.com/steal';
    final dio = Dio()..httpClientAdapter = adapter;
    await expectLater(
      ForumClient(dio: dio)
          .submit(forumUri('forum.php'), {'message': 'private'}),
      throwsA(isA<ForumFailure>()),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('注册入口沿用官网动态 mod，拒绝外站冒充注册页', () {
    expect(
      registrationUriFromHtml(
        '<a href="https://example.com/member.php?mod=register">注册</a><a href="member.php?mod=register213">立即注册</a>',
      ).queryParameters['mod'],
      'register213',
    );
    expect(
      () => registrationUriFromHtml(
        '<a href="https://example.com/member.php?mod=register">注册</a>',
      ),
      throwsA(isA<ForumFailure>()),
    );
  });

  test('签到动作只来自当次同源页面，CSS 数字转换为文字', () {
    final document = NativeForumDocument(
      '<div id="wp"><a id="JD_sign" href="plugin.php?id=k_misign:sign&amp;operation=qiandao&amp;formhash=fixture">签到</a><div class="pics"><span class="one"></span><span class="two"></span></div></div>',
      forumUri('k_misign-sign.html'),
    );
    expect(document.signAction?.queryParameters['formhash'], 'fixture');
    expect(document.content.text, contains('12'));
    final offsite = NativeForumDocument(
      '<div id="wp"><p>签到信息</p><a id="JD_sign" href="https://example.com/?operation=qiandao">签到</a></div>',
      forumUri('k_misign-sign.html'),
    );
    expect(offsite.signAction, isNull);
  });

  test('嵌入消息页从当前官方页面提取子分类并保留页面操作', () {
    final document = NativeForumDocument(
      File('test/fixtures/messages_mypost.html').readAsStringSync(),
      forumUri('home.php?mod=space&do=notice&view=mypost'),
      extractMessageTabs: true,
    );
    expect(document.messageTabs.map((tab) => tab.label), [
      '帖子',
      '点评',
      '活动',
      '悬赏',
      '商品',
      '提到我的',
    ]);
    expect(document.messageTabs.first.selected, isTrue);
    expect(
      document.content.querySelector('[data-native-navigation] a')?.text,
      '筛选设置',
    );
    expect(document.messageTabs.any((tab) => tab.label == '筛选设置'), isFalse);
    expect(
      document.content.querySelectorAll('[data-native-navigation]'),
      hasLength(1),
    );
  });

  testWidgets('筛选设置显示真实选项并在原页面切换顶栏', (tester) async {
    final client = PrivacyClient();
    final preferences = Preferences(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '筛选设置',
          uri: forumUri('home.php?mod=spacecp&ac=privacy&op=filter'),
          client: client,
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('好友'), findsOneWidget);
    expect(find.text('屏蔽提醒'), findsOneWidget);
    expect(find.text('回复提醒'), findsOneWidget);
    expect(find.text('选择要过滤的提醒'), findsOneWidget);
    expect(find.text('privacy[filter_gid][0]'), findsNothing);
    await tester.tap(find.text('好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人动态发布设置'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未提交的内容？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(client.requests, hasLength(1));
    await tester.tap(find.text('个人动态发布设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(client.requests.last, contains('op=feed'));
    expect(find.byType(NativeForumPage), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(NativeForumPage))).canPop(),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选设置保留表单令牌与选中的规则', (tester) async {
    final client = PrivacyClient();
    final preferences = Preferences(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '筛选设置',
          uri: forumUri('home.php?mod=spacecp&ac=privacy&op=filter'),
          client: client,
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('好友'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存').first);
    await tester.pumpAndSettle();
    expect(client.submitted?['formhash'], 'fixture-token');
    expect(client.submitted?['privacy[filter_gid][0]'], '0');
    expect(client.submitted?['privacy2submit'], 'true');
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选设置顶栏在窄屏大字号下完整且磨砂边界对齐', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = Preferences(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: NativeForumPage(
          title: '筛选设置',
          uri: forumUri('home.php?mod=spacecp&ac=privacy&op=filter'),
          client: PrivacyClient(),
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(
      tester.getRect(find.byType(TabBar)).bottom,
      closeTo(tester.getRect(find.byType(ReviewFrostedBackdrop)).bottom, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  for (final view in ['mypost', 'interactive', 'system', 'app']) {
    testWidgets('$view 通知只显示正文及屏蔽查看操作', (tester) async {
      final preferences = Preferences(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          home: NativeForumPage(
            title: '消息',
            uri: forumUri('home.php?mod=space&do=notice&view=$view'),
            client: NoticeLayoutClient(),
            preferences: preferences,
            embedded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.textContaining('昨天 08:52'));
      expect(text.data, contains('康哥 回复了您的帖子 主题标题'));
      expect(text.data, isNot(contains('屏蔽')));
      expect(text.data, isNot(contains('查看')));
      expect(find.widgetWithText(TextButton, '屏蔽'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '查看'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '康哥'), findsNothing);
      expect(find.widgetWithText(TextButton, '主题标题'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final path in [
    'forum.php?mod=post&action=reply&tid=123',
    'forum.php?mod=post&action=newthread&fid=50',
    'home.php?mod=space&do=pm',
    'home.php?mod=space&do=profile',
    'home.php?mod=space&do=thread&view=me',
    'home.php?mod=space&do=favorite&view=me',
    'home.php?mod=spacecp&ac=favorite&type=thread&id=123',
    'misc.php?mod=ranklist',
    'member.php?mod=register',
    'k_misign-sign.html',
  ]) {
    testWidgets('$path 统一进入原生功能页', (tester) async {
      final client = NativeClient();
      final preferences = Preferences(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openForumWeb(
                context,
                '功能',
                path,
                client: client,
                preferences: preferences,
              ),
              child: const Text('进入'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('进入'));
      await tester.pumpAndSettle();
      expect(
        find.byType(
          path.contains('do=profile') ? ForumAccountPage : NativeForumPage,
        ),
        findsOneWidget,
      );
      expect(find.byType(ForumWebPage), findsNothing);
      expect(client.requests, hasLength(path.contains('mod=register') ? 2 : 1));
      expect(tester.takeException(), isNull);
    });
  }

  test('退出取消旧请求，不能再转入旧会话的浏览器后备', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          ForumClient.platform,
          (call) async =>
              call.method == 'cookies' ? 'forum_auth=fixture' : null,
        );
    final adapter = CancellingAdapter();
    final client = ForumClient(dio: Dio()..httpClientAdapter = adapter);
    var browserReads = 0;
    client.browserRead = (_) async {
      browserReads++;
      return '<div>old account</div>';
    };
    final request = expectLater(
      client.source('$forumOrigin/home.php'),
      throwsA(isA<ForumFailure>()),
    );
    await adapter.started.future;
    await client.logout();
    await request;
    expect(browserReads, 0);
  });

  testWidgets('退出通知清除其他原生页里的旧账号内容', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '消息',
          uri: forumUri('home.php?mod=space&do=pm'),
          client: NativeClient(),
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('资料与消息内容', findRichText: true), findsOneWidget);
    sessionRevision.value++;
    await tester.pumpAndSettle();
    expect(find.textContaining('资料与消息内容', findRichText: true), findsNothing);
    expect(find.textContaining('账号状态已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('账号解析使用真实资料结构，空内容必须报错', () async {
    final data = ForumAccount.parse(
      await NativeClient().source('home.php?do=profile'),
    );
    expect(data.name, '测试账号');
    expect(data.uid, '123');
    final source = await NativeClient().source('home.php?do=profile');
    expect(
      ForumAccount.parse(
        source.replaceFirst(
          '<h2>',
          '<img src="https://cdn.binmt.cc/avatar.jpg"><h2>',
        ),
      ).avatar,
      'https://cdn.binmt.cc/avatar.jpg',
    );
    expect(
      ForumAccount.parse(
        source.replaceFirst(
          '<h2>',
          '<img src="http://cdn.binmt.cc/avatar.jpg"><h2>',
        ),
      ).avatar,
      isNull,
    );
    expect(data.fields, contains(('积分', '100')));
    expect(data.fields.any((item) => item.$1.contains('IP')), isFalse);
    expect(
      () => ForumAccount.parse('<div id="ct"></div>'),
      throwsA(isA<ForumFailure>()),
    );
    expect(
      () => NativeForumDocument('<div id="ct"></div>', forumUri('/')),
      throwsA(isA<ForumFailure>()),
    );
  });

  testWidgets('账号资料原生显示名称 UID 和积分，不依赖 HTML 布局', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ForumAccountPage(client: NativeClient())),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试账号'), findsOneWidget);
    expect(find.text('UID: 123'), findsOneWidget);
    expect(find.text('积分'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('192.0.2.1'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '退出登录'), findsOneWidget);
    expect(find.byType(ForumWebPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('资料为空时显示错误，并仍能退出登录返回上页', (tester) async {
    var cookie = 'forum_auth=fixture';
    final clears = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (call) async {
        if (call.method == 'clearForumSession') {
          clears.add(call.arguments as String);
          cookie = '';
          return null;
        }
        return cookie;
      },
    );
    var resets = 0;
    final client = EmptyAccountClient()
      ..browserResetSession = () async {
        resets++;
      };
    final before = sessionRevision.value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ForumAccountPage(client: client),
              ),
            ),
            child: const Text('进入账号'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('进入账号'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未能读取账号资料'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();
    expect(clears, ['$forumOrigin/']);
    expect(resets, 1);
    expect(forumAuthenticated.value, isFalse);
    expect(sessionRevision.value, before + 1);
    expect(find.byType(ForumAccountPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消退出不清除会话，失败资料页可重试', (tester) async {
    var cleared = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (call) async {
        if (call.method == 'clearForumSession') cleared = true;
        return call.method == 'cookies' ? 'forum_auth=fixture' : null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: ForumAccountPage(client: EmptyAccountClient())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cleared, isFalse);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '退出登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同名多选框只提交实际选中项', (tester) async {
    final element = html
        .parse(
          '<form method="post" action="home.php"><input type="checkbox" name="items[]" value="1" checked><input type="checkbox" name="items[]" value="2"><button type="submit">提交</button></form>',
        )
        .querySelector('form')!;
    Map<String, dynamic>? fields;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeForumFormView(
            form: NativeForumForm(element, forumUri('/')),
            busy: false,
            onSubmit: (form, data, button) async {
              fields = data;
            },
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .value,
      isTrue,
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).last).value,
      isFalse,
    );
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '提交'));
    await tester.pumpAndSettle();
    expect(fields?['items[]'], ['2']);
  });

  testWidgets('搜索使用官网动态表单并在原生页面显示结果', (tester) async {
    final client = SearchClient();
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '搜索',
          uri: forumUri('/'),
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
          search: 'fixture keyword',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.submitted?['srchtxt'], 'fixture keyword');
    expect(client.submitted?['formhash'], 'search-token');
    expect(find.text('原生搜索结果', findRichText: true), findsOneWidget);
    expect(find.byType(ForumWebPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('成功发送原生回复后关闭编辑页；放弃前保留内容', (tester) async {
    final client = NativeClient();
    final preferences = Preferences(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openForumWeb(
              context,
              '回复',
              'forum.php?mod=post&action=reply&tid=123',
              client: client,
              preferences: preferences,
            ),
            child: const Text('进入'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('进入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '原生回复');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未提交的内容？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '发送回复'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, '发送回复'));
    await tester.pumpAndSettle();
    expect(client.submitted?['message'], '原生回复');
    expect(find.byType(NativeForumPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('原生引用回复使用 M3 编辑器，失败保留输入且不自动重发', (tester) async {
    final client = NativeClient()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '回复',
          uri: forumUri('forum.php?mod=post&action=reply&tid=123&repquote=123'),
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    final input = find.byType(TextFormField).last;
    await tester.enterText(input, '原生回复');
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '发送回复'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, '发送回复'));
    await tester.pumpAndSettle();
    expect(client.submitted?['message'], '[quote]被引用内容[/quote]\n原生回复');
    expect(client.submitted?['formhash'], 'fixture-token');
    expect(client.submitted?['replysubmit'], 'yes');
    expect(find.textContaining('编辑内容已保留'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(input).controller!.text,
      contains('原生回复'),
    );
    expect(find.byType(ForumWebPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('移除引用只改变本次回复，隐藏标题和引用令牌仍保留', (tester) async {
    final client = NativeClient()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '回复',
          uri: forumUri('forum.php?mod=post&action=reply&tid=123&repquote=123'),
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('引用内容'), findsOneWidget);
    await tester.tap(find.byTooltip('移除引用'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '不带引用的新回复');
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '发送回复'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, '发送回复'));
    await tester.pumpAndSettle();
    expect(client.submitted?['message'], '不带引用的新回复');
    expect(client.submitted?['subject'], 'RE:测试');
    expect(client.submitted?['formhash'], 'fixture-token');
    expect(tester.takeException(), isNull);
  });
}
