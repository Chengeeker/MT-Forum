import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/pages/forum_page.dart';
import 'package:mt_forum/pages/media_page.dart';
import 'package:mt_forum/pages/native_forum_page.dart';
import 'package:mt_forum/core/widgets/forum_avatar.dart';
import 'package:mt_forum/core/widgets/app_section_card.dart';

import 'native_forum_test.dart' as fixture;

import 'package:html/parser.dart' as html;
import 'package:mt_forum/data/native_forum.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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

class MarkdownThreadClient extends ThreadClient {
  @override
  Future<ForumDocument> load(String url) async => parseForum(
    '<div id="thread_subject">Markdown 代码块</div>'
    '<div id="post_900"><div class="pls"><div class="authi">'
    '<a href="space-uid-1.html">代码作者</a></div></div>'
    '<div id="postmessage_900"><p>工具列表</p>'
    '<div class="blockcode"><div id="code_1"><ol>'
    '<li><code>/opt/dt/bin/aapt2 6.2 MB<br>arm64 静态编译</code></li>'
    '<li><code>/opt/dt/bin/zipalign 815 KB</code></li>'
    '</ol></div><em onclick="copycode(\'code_1\')">复制代码</em>'
    '</div></div></div>',
    forumUri(url),
  );
}

class PendingThreadClient extends ThreadClient {
  final pending = Completer<ForumDocument>();
  @override
  Future<ForumDocument> load(String url) => pending.future;
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

  testWidgets('图片播放器顶部使用 Review 返回、页码和保存控件', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ForumImageGalleryPage(
          images: ['https://bbs.binmt.cc/data/forum/test.jpg'],
          previews: ['https://bbs.binmt.cc/data/forum/test-thumb.jpg'],
          initialIndex: 0,
          heroTagPrefix: 'gallery-test',
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('保存到相册'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-loading-preview-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('液态玻璃图片播放器在返回转场时移除玻璃按钮', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ForumImageGalleryPage(
                  images: ['https://bbs.binmt.cc/data/forum/test.jpg'],
                  initialIndex: 0,
                  heroTagPrefix: 'glass-return-test',
                  useLiquidGlass: true,
                ),
              ),
            ),
            child: const Text('打开图片'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开图片'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GlassButton), findsNWidgets(2));

    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(GlassButton), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

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
  testWidgets('帖子加载中顶栏直接显示已知作者信息，不闪现文章标题', (tester) async {
    final client = PendingThreadClient();
    final preferences = Preferences(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ForumPage(
                  link: const ForumLink(
                    '示例帖子',
                    'https://bbs.binmt.cc/thread-123-1-1.html',
                    author: '首楼作者',
                    date: '发表于 10:45',
                    role: '高中生',
                    imageUrl: 'https://cdn.binmt.cc/avatar.jpg',
                    profile: 'https://bbs.binmt.cc/space-uid-123.html',
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.text('首楼作者')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.text('高中生')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.text('发表于 10:45')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: appBar, matching: find.text('示例帖子')),
      findsNothing,
    );
    expect(find.textContaining('UID'), findsNothing);
    client.pending.complete(
      parseForum(
        File('test/fixtures/thread.html').readAsStringSync(),
        forumUri('https://bbs.binmt.cc/thread-123-1-1.html'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('首楼头像、用户名、等级、时间在顶栏显示，正文卡片不重复作者信息', (tester) async {
    await openThread(tester, ThreadClient());
    final author = find.text('测试作者');
    expect(
      find.ancestor(of: author, matching: find.byType(AppBar)),
      findsOneWidget,
    );
    expect(find.text('示例帖子'), findsOneWidget);
    expect(find.text('管理员'), findsOneWidget);
    expect(find.text('2026-10-26'), findsOneWidget);
    expect(find.textContaining('UID'), findsNothing);
    final firstPost = find.byType(AppSectionCard).first;
    expect(
      find.descendant(of: firstPost, matching: find.text('测试作者')),
      findsNothing,
    );
    expect(
      find.descendant(of: firstPost, matching: find.text('管理员')),
      findsNothing,
    );
    expect(
      find.descendant(of: firstPost, matching: find.text('2026-10-26')),
      findsNothing,
    );
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
  testWidgets('Discuz Markdown 代码块使用 M3 卡片并可复制原文', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await openThread(tester, MarkdownThreadClient());
    expect(find.text('代码'), findsOneWidget);
    expect(find.text('复制代码'), findsOneWidget);
    expect(find.textContaining('/opt/dt/bin/aapt2 6.2 MB'), findsOneWidget);
    expect(find.textContaining('arm64 静态编译'), findsOneWidget);

    await tester.tap(find.text('复制代码'));
    await tester.pumpAndSettle();
    expect(
      copied,
      '/opt/dt/bin/aapt2 6.2 MB\narm64 静态编译\n/opt/dt/bin/zipalign 815 KB',
    );
    expect(find.text('代码已复制'), findsOneWidget);
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
