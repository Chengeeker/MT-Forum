import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/pages/forum_page.dart';
import 'package:mt_forum/pages/native_forum_page.dart';
import 'package:mt_forum/core/widgets/forum_avatar.dart';

import 'native_forum_test.dart' as fixture;

import 'package:html/parser.dart' as html;
import 'package:mt_forum/data/native_forum.dart';

class ThreadClient extends fixture.NativeClient {
  int writes = 0;
  @override
  Future<ForumDocument> load(String url) async => parseForum(
    File('test/fixtures/thread.html').readAsStringSync(),
    forumUri(url),
  );
  @override
  Future<(String, Uri)> submit(
    Uri action,
    Map<String, dynamic> fields, {
    String method = 'POST',
  }) {
    writes++;
    return super.submit(action, fields, method: method);
  }
}

class NoWrapThreadClient extends ThreadClient {
  @override
  Future<ForumDocument> load(String url) async => parseForum(
    '<div id="thread_subject">通知帖子</div>'
    '<div id="post_1"><div class="pls"><div class="authi">'
    '<a href="space-uid-1.html">测试用户</a></div></div>'
    '<div id="postmessage_1"><div style="width:900px"><table width="900"><tr><td nowrap>'
    '<span style="color:red; white-space:nowrap">手机号</span>'
    '注销了，申请换绑登录论坛的手机号。</td></tr></table></div></div></div>',
    forumUri(url),
  );
}

class NoticeThreadClient extends ThreadClient {
  NoticeThreadClient(this.href);
  final String href;
  final loaded = <String>[];

  @override
  Future<String> source(String url) async {
    if (url.contains('do=notice')) {
      return '<div id="ct"><div class="mn"><div class="nts"><dl><dd>有新的回复 <a href="$href">查看</a></dd></dl></div></div></div>';
    }
    if (url.contains('plugin.php?id=threadview')) {
      return '<link rel="canonical" href="https://bbs.binmt.cc/thread-123-1-1.html">${File('test/fixtures/thread.html').readAsStringSync()}';
    }
    return super.source(url);
  }

  @override
  Future<ForumDocument> load(String url) async {
    loaded.add(url);
    return parseForum(
      File('test/fixtures/thread.html').readAsStringSync(),
      forumUri('forum.php?mod=viewthread&tid=123&page=2'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          ForumClient.platform,
          (_) async => 'forum_auth=fixture',
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, null),
  );
  Future<void> openThread(
    WidgetTester tester,
    ThreadClient client, {
    double scale = 1,
    double keyboard = 0,
  }) async {
    final preferences = Preferences(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ForumPage(
                  link: const ForumLink(
                    '示例帖子',
                    'https://bbs.binmt.cc/thread-123-1-1.html',
                  ),
                  client: client,
                  preferences: preferences,
                ),
              ),
            ),
            child: const Text('打开帖子'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开帖子'));
    await tester.pumpAndSettle();
  }

  for (final href in [
    'forum.php?mod=redirect&amp;goto=findpost&amp;pid=901&amp;ptid=123',
    'forum.php?mod=redirect&amp;goto=findpost&amp;pid=901',
    'plugin.php?id=threadview',
  ]) {
    testWidgets('通知查看 $href 进入原生帖子并使用正确帖子编号回复', (tester) async {
      final client = NoticeThreadClient(href);
      final preferences = Preferences(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          home: NativeForumPage(
            title: '消息',
            uri: forumUri('home.php?mod=space&do=notice&view=mypost'),
            client: client,
            preferences: preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '查看'));
      await tester.pumpAndSettle();
      expect(find.byType(ForumPage), findsOneWidget);
      expect(find.byType(ForumAvatar), findsWidgets);
      expect(find.text('说点什么吧…'), findsOneWidget);
      if (href.contains('pid=')) {
        expect(client.loaded.single, contains('pid=901'));
      } else {
        expect(client.loaded, isEmpty);
      }
      await tester.tap(find.text('说点什么吧…'));
      await tester.pumpAndSettle();
      expect(client.requests.last, contains('action=reply&tid=123'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('帖子内头像使用官网资源，默认头像使用原图而非人形占位', (tester) async {
    await openThread(tester, ThreadClient());
    expect(find.byType(ForumAvatar), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/forum-default-avatar.gif',
      ),
      findsWidgets,
    );
    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('帖子正文将官网 nowrap 行内样式换成正常多行', (tester) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openThread(tester, NoWrapThreadClient());
    final paragraph = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('手机号注销了，申请换绑登录论坛的手机号。'),
    );
    expect(paragraph, findsOneWidget);
    expect(tester.getSize(paragraph).height, greaterThan(40));
    expect(tester.getRect(paragraph).right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });
  testWidgets('快捷回复网络图片验证 HTTPS 并插入 BBCode', (tester) async {
    final form = NativeForumForm(
      html.parse(fixture.replyFixture).querySelector('form')!,
      forumUri('forum.php?mod=post&action=reply&tid=123'),
    );
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeForumFormView(
            form: form,
            busy: false,
            compactReply: true,
            onSubmit: (_, data, _) async => submitted = data,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('网络图片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'javascript:bad');
    await tester.tap(find.widgetWithText(FilledButton, '插入'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的 HTTPS 地址'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'https://example.test/picture.png',
    );
    await tester.tap(find.widgetWithText(FilledButton, '插入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发送回复'));
    await tester.pumpAndSettle();
    expect(
      submitted?['message'],
      contains('[img]https://example.test/picture.png[/img]'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('快捷回复留在帖子，格式工具和收起保留草稿，失败不重发', (tester) async {
    final client = ThreadClient()..fail = true;
    await openThread(tester, client);
    await tester.tap(find.text('说点什么吧…'));
    await tester.pumpAndSettle();
    expect(find.byType(NativeForumPage), findsNothing);
    final input = find.byType(TextFormField);
    await tester.enterText(input, '快捷回复草稿');
    final controller = tester.widget<TextFormField>(input).controller!;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    await tester.tap(find.byTooltip('加粗'));
    await tester.pumpAndSettle();
    expect(controller.text, '[b]快捷回复草稿[/b]');
    await tester.tap(find.byTooltip('收起编辑栏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续编辑回复…'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(input).controller!.text,
      '[b]快捷回复草稿[/b]',
    );
    await tester.tap(find.byTooltip('发送回复'));
    await tester.pumpAndSettle();
    expect(client.writes, 1);
    expect(client.submitted?['formhash'], 'fixture-token');
    expect(client.submitted?['message'], '[b]快捷回复草稿[/b]');
    expect(find.textContaining('草稿已保留'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('楼层引用使用底部编辑器，成功后清草稿并刷新帖子', (tester) async {
    final client = ThreadClient();
    await openThread(tester, client);
    await tester.tap(find.text('回复').first);
    await tester.pumpAndSettle();
    expect(client.requests.last, contains('repquote=900'));
    expect(find.text('被引用内容'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '楼层引用回复');
    await tester.tap(find.byTooltip('发送回复'));
    await tester.pumpAndSettle();
    expect(client.submitted?['message'], '[quote]被引用内容[/quote]\n楼层引用回复');
    expect(client.writes, 1);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('回复已发送'), findsOneWidget);
    expect(find.byType(ForumPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('大字号与键盘下快捷回复不溢出，退出草稿要确认', (tester) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openThread(tester, ThreadClient(), scale: 2, keyboard: 260);
    await tester.tap(find.text('说点什么吧…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '保留草稿');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未提交的回复？'), findsOneWidget);
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    expect(find.byType(ForumPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
