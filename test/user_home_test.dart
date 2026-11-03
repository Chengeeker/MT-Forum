import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/core/theme/app_theme.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/data/user_home.dart';
import 'package:mt_forum/pages/user_home_page.dart';
import 'package:mt_forum/pages/web_page.dart';

String fixture(String key) =>
    File('test/fixtures/user-$key.html').readAsStringSync();
final profile = forumUri('home.php?mod=space&do=profile&uid=123');

class UserClient extends ForumClient {
  final requests = <String>[];
  int writes = 0;
  bool failMore = false, failSubmit = false, signedFollow = false;
  Map<String, dynamic>? submitted;
  Completer<String>? delayedTopics;
  @override
  Future<String> source(String url) async {
    requests.add(url);
    final q = Uri.parse(url).queryParameters;
    if (q['do'] == 'thread') {
      if (delayedTopics != null) return delayedTopics!.future;
      if (q['page'] == '2') {
        if (failMore) throw const ForumFailure('下一页失败');
        return '<div id="ct"><div class="mn"><div class="tl"><table><tr><th><a href="thread-999-1-1.html">下一页的新主题</a></th></tr><tr><th><a href="thread-175222-1-1.html">我的第一个主题</a></th></tr></table></div></div></div>';
      }
      return fixture('topics');
    }
    if (q['mod'] == 'follow') return fixture('broadcast');
    if (q['do'] == 'wall') return fixture('wall');
    return signedFollow
        ? fixture('profile')
              .replaceAll('op=add&amp;fuid', 'op=del&amp;fuid')
              .replaceAll('收听TA', '取消收听')
        : fixture('profile');
  }

  @override
  Future<(String, Uri)> submit(
    Uri action,
    Map<String, dynamic> fields, {
    String method = 'POST',
  }) async {
    writes++;
    submitted = fields;
    if (failSubmit) throw const ForumFailure('模拟提交失败');
    signedFollow = true;
    return ('<div id="messagetext">操作成功</div>', action);
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

  Future<void> open(
    WidgetTester tester,
    UserClient client, {
    ThemeData? theme,
    GlobalKey? boundary,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RepaintBoundary(
          key: boundary,
          child: UserHomePage(
            uri: profile,
            client: client,
            preferences: Preferences(await SharedPreferences.getInstance()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('主页读取真实栏目与操作，主题不会把最后回复者识别为作者', () {
    final home = ForumUserHome(fixture('profile'), profile);
    expect(home.role, '小学生');
    expect(home.signature, '发现新大陆！');
    expect(home.sections.keys, containsAll(['thread', 'follow', 'wall']));
    expect(home.actions.keys, containsAll(['follow', 'friend', 'pm']));
    final list = ForumUserContent(
      fixture('topics'),
      userTopicsUri(profile),
      topics: true,
    );
    expect(list.threads.length, 2);
    expect(list.threads.first.author, isEmpty);
    expect(list.threads.first.views, '200');
    expect(list.next!.queryParameters['page'], '2');
    final rejected = ForumUserContent(
      fixture('topics').replaceAll('uid=123', 'uid=999'),
      userTopicsUri(profile),
      topics: true,
    );
    expect(rejected.next, isNull);
  });
  test('广播按广播 ID 保留重复引用，留言保留原生表单令牌且清除网页脚本', () {
    final broadcast = ForumUserContent(
      fixture('broadcast'),
      forumUri('home.php?mod=follow&uid=123&do=view'),
      topics: false,
    );
    expect(broadcast.entries.length, 2);
    expect(broadcast.entries.first.body, contains('这篇帖子很有启发'));
    expect(broadcast.entries.first.body, isNot(contains('<script')));
    expect(broadcast.entries.first.body, isNot(contains('900px')));
    final wall = ForumUserContent(
      fixture('wall'),
      forumUri('home.php?mod=space&uid=123&do=wall'),
      topics: false,
    );
    expect(wall.entries.single.author, '坛友');
    expect(wall.entries.single.date, '今天 10:00');
    expect(wall.wallForm!.values()['formhash'], 'wall-fixture');
    expect(wall.entries.single.actions.single.title, '回复');
  });
  testWidgets('主页默认展示主题，资料和广播留言原位切换且不重复加载', (tester) async {
    final client = UserClient();
    await open(tester, client);
    final bar = tester.getRect(find.byType(TabBar));
    for (var index = 0; index < 4; index++) {
      expect(
        tester.getCenter(find.byType(Tab).at(index)).dx,
        closeTo(bar.left + bar.width * (index + .5) / 4, 1),
      );
    }
    expect(find.text('我的第一个主题'), findsOneWidget);
    expect(find.text('注册时间'), findsNothing);
    expect(find.text('最后回复的人'), findsNothing);
    await tester.tap(find.text('广播'));
    await tester.pumpAndSettle();
    expect(find.textContaining('广播内容', findRichText: true), findsOneWidget);
    await tester.tap(find.text('留言板'));
    await tester.pumpAndSettle();
    expect(find.textContaining('期待新的分享', findRichText: true), findsOneWidget);
    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    expect(find.text('注册时间'), findsOneWidget);
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    expect(
      client.requests
          .where((url) => Uri.parse(url).queryParameters['do'] == 'thread')
          .length,
      1,
    );
    expect(find.byType(UserHomePage), findsOneWidget);
    expect(find.byType(InAppBrowserPage), findsNothing);
  });
  test('广播延续官网的 AJAX 分页，主表结束后再读取归档', () {
    final initial = ForumUserContent(
      '${fixture('broadcast')}<script>var feedInfo = {archiver: 1, primary: 1}; var url="op=getfeed";</script>',
      forumUri('home.php?mod=follow&uid=123&do=view'),
      topics: false,
    );
    expect(initial.next!.queryParameters['page'], '2');
    final more = ForumUserContent(
      '<root><![CDATA[${fixture('broadcast')}]]></root>',
      initial.next!,
      topics: false,
      archivedAvailable: true,
    );
    expect(more.entries.length, 2);
    expect(more.next!.queryParameters['page'], '3');
    final archived = ForumUserContent(
      '<root><![CDATA[false]]></root>',
      more.next!,
      topics: false,
      archivedAvailable: true,
    );
    expect(archived.next!.queryParameters['archiver'], '1');
    expect(archived.next!.queryParameters['page'], '1');
    final end = ForumUserContent(
      'false',
      archived.next!,
      topics: false,
      archivedAvailable: true,
    );
    expect(end.next, isNull);
  });
  testWidgets('主题分页失败保留内容并可重试，追加时去重', (tester) async {
    final client = UserClient()..failMore = true;
    await open(tester, client);
    await tester.ensureVisible(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('我的第一个主题'), findsOneWidget);
    expect(find.text('下一页失败'), findsOneWidget);
    client.failMore = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('下一页的新主题'), findsOneWidget);
    expect(find.text('我的第一个主题'), findsOneWidget);
  });
  testWidgets('关注只在点击时提交一次，随后读取服务器状态', (tester) async {
    final client = UserClient();
    await open(tester, client);
    expect(client.writes, 0);
    await tester.tap(find.text('收听TA'));
    await tester.pumpAndSettle();
    expect(client.writes, 1);
    expect(find.text('取消收听'), findsOneWidget);
  });
  testWidgets('留言提交失败保留内容和令牌，不自动重试', (tester) async {
    final client = UserClient()..failSubmit = true;
    await open(tester, client);
    await tester.tap(find.text('留言板'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写留言'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '保留这条留言');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '留言'));
    await tester.tap(find.widgetWithText(FilledButton, '留言'));
    await tester.pumpAndSettle();
    expect(client.writes, 1);
    expect(client.submitted!['formhash'], 'wall-fixture');
    expect(client.submitted!['id'], '123');
    expect(find.text('保留这条留言'), findsOneWidget);
    expect(find.textContaining('提交未自动重试'), findsOneWidget);
  });
  testWidgets('换号后丢弃迟到的主页主题响应', (tester) async {
    final old = Completer<String>();
    final client = UserClient()..delayedTopics = old;
    await tester.pumpWidget(
      MaterialApp(
        home: UserHomePage(
          uri: profile,
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pump();
    client.delayedTopics = null;
    sessionRevision.value++;
    await tester.pumpAndSettle();
    old.complete(
      '<div id="ct"><div class="mn"><div class="tl"><a href="thread-888-1-1.html">旧账号迟到内容</a></div></div></div>',
    );
    await tester.pumpAndSettle();
    expect(find.text('旧账号迟到内容'), findsNothing);
    expect(find.text('我的第一个主题'), findsOneWidget);
  });
  testWidgets('主页明暗与大字体布局预览', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      for (final family in ['Roboto', 'Ahem']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await tester.runAsync(loader.load);
      }
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(icons.load);
    for (final dark in [false, true]) {
      final key = GlobalKey();
      await tester.pumpWidget(const SizedBox());
      await open(
        tester,
        UserClient(),
        boundary: key,
        theme: dark
            ? AppTheme.darkTheme(colorIndex: 2)
            : AppTheme.lightTheme(colorIndex: 2),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('docs').createSync(recursive: true);
        File('docs/preview-user-home-${dark ? 'dark' : 'light'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: UserHomePage(
          uri: profile,
          client: UserClient(),
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tabBar = tester.getRect(find.byType(TabBar));
    for (var index = 0; index < 4; index++) {
      expect(
        tester.getCenter(find.byType(Tab).at(index)).dx,
        closeTo(tabBar.left + tabBar.width * (index + .5) / 4, 1),
      );
    }
    for (final label in ['广播', '留言板', '资料', '主题']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
