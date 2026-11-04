import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/data/user_home.dart';
import 'package:mt_forum/core/theme/app_theme.dart';
import 'package:mt_forum/pages/account_page.dart';
import 'package:mt_forum/pages/forum_page.dart';
import 'package:mt_forum/pages/native_forum_page.dart';
import 'package:mt_forum/pages/user_home_page.dart';
import 'package:mt_forum/pages/web_page.dart';

import 'user_home_test.dart' as user_fixture;

String postsFixture() => File('test/fixtures/my-posts.html').readAsStringSync();
String emptyPostsFixture() =>
    File('test/fixtures/my-posts-empty.html').readAsStringSync();

class OwnContentClient extends user_fixture.UserClient {
  String uid = '123', name = '木棉';
  int previews = 0;
  final emptyFilters = <String>{};
  Completer<String>? pendingFilter;
  String pendingFilterKey = 'save';
  @override
  Future<String> source(String url) async {
    final q = Uri.parse(url).queryParameters;
    if (q['do'] == 'thread' && !q.containsKey('uid')) {
      requests.add(url);
      if (q['filter'] == pendingFilterKey && pendingFilter != null) {
        return pendingFilter!.future;
      }
      if (emptyFilters.contains(q['filter'])) return emptyPostsFixture();
      var source = postsFixture();
      if (q['type'] == 'reply' || q['type'] == 'postcomment') {
        source = source
            .replaceAll(
              'forum.php?mod=viewthread&amp;tid=175222',
              'forum.php?mod=redirect&amp;goto=findpost&amp;ptid=175222&amp;pid=901',
            )
            .replaceAll(
              '</tbody>',
              '<tr><td colspan="5"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=175222&amp;pid=902">我自己的回复内容</a></td></tr></tbody>',
            );
        source = source.replaceAll(
          'type=thread&amp;filter',
          'type=${q['type']}&amp;filter',
        );
      }
      if (q['page'] == '2') {
        source = source.replaceAll('我发表的主题', '第二页主题');
      }
      if (q['type'] == 'postcomment') {
        final doc = html.parse(source);
        doc.querySelector('.tbmu .y')?.remove();
        source = doc.outerHtml;
      }
      return source;
    }
    return (await super.source(url))
        .replaceAll('UID: 123', 'UID: $uid')
        .replaceAll('uid=123', 'uid=$uid')
        .replaceAll('木棉', name);
  }

  @override
  Future<ThreadSummary> threadSummary(
    String url,
    bool Function() active,
  ) async {
    previews++;
    return ThreadSummary(
      parseForum(
        File('test/fixtures/thread.html')
            .readAsStringSync()
            .replaceAll('测试作者', name),
        forumUri(url),
      ),
    );
  }
}

class RouteCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
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

  test('我的帖子空筛选保留分栏且不会误判登录或结构异常', () {
    for (final type in ['thread', 'reply', 'postcomment']) {
      for (final filter in [
        '',
        'common',
        'save',
        'close',
        'aduit',
        'ignored',
        'recyclebin',
      ]) {
        final data = ForumMyPosts(
          emptyPostsFixture().replaceAll(
            'type=thread&amp;filter',
            'type=$type&amp;filter',
          ),
          forumUri(
            'home.php?mod=space&do=thread&view=me&type=$type&filter=$filter',
          ),
        );
        expect(data.threads, isEmpty);
        expect(data.emptyMessage, '暂无相关帖子');
        if (type == 'postcomment') {
          expect(data.statuses, isEmpty);
        } else {
          expect(
            Uri.parse(data.statuses.singleWhere((tab) => tab.selected).url)
                .queryParameters['filter'],
            filter,
          );
        }
        expect(
          data.types.singleWhere((tab) => tab.selected).label,
          {'thread': '主题', 'reply': '回复', 'postcomment': '点评'}[type],
        );
        expect(data.next, isNull);
      }
    }
    final public = ForumUserContent(
      emptyPostsFixture(),
      userTopicsUri(user_fixture.profile),
      topics: true,
    );
    expect(public.threads, isEmpty);
    expect(public.emptyMessage, '暂无相关帖子');
  });

  test('内容类型保留状态，点评不发送无效筛选，离开点评恢复原状态', () {
    final reply = ForumMyPosts(
      postsFixture(),
      forumUri(
        'home.php?mod=space&do=thread&view=me&type=reply&filter=common&page=2',
      ),
    );
    for (final tab in reply.types) {
      final q = Uri.parse(tab.url).queryParameters;
      expect(q['filter'], tab.label == '点评' ? isNull : 'common');
      expect(q.containsKey('page'), isFalse);
    }
    for (final tab in reply.statuses) {
      expect(Uri.parse(tab.url).queryParameters['type'], 'reply');
    }
    final source = html.parse(postsFixture());
    source.querySelector('.tbmu .y')!.remove();
    final comments = ForumMyPosts(
      source.outerHtml,
      forumUri('home.php?mod=space&do=thread&view=me&type=postcomment'),
      lastFilter: 'common',
    );
    expect(comments.statuses, isEmpty);
    expect(comments.types.map((tab) => tab.label), ['主题', '回复', '点评']);
    expect(comments.types.singleWhere((tab) => tab.selected).label, '点评');
    for (final tab in comments.types.where((tab) => tab.label != '点评')) {
      expect(Uri.parse(tab.url).queryParameters['filter'], 'common');
    }
  });

  testWidgets('一级内容分栏固定，加载不回跳，筛选跨类型保留且失败回退', (tester) async {
    final client = OwnContentClient()
      ..pendingFilterKey = 'common'
      ..pendingFilter = Completer<String>();
    final routes = RouteCounter();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: NativeForumPage(
          title: '我的帖子',
          uri: forumUri('home.php?mod=space&do=thread&view=me'),
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pushes = routes.pushes;
    TabController controller(String label) => DefaultTabController.of(
      tester.element(find.widgetWithText(Tab, label)),
    );
    void primaryIsStable(String selected) {
      final primary = tester.widgetList<TabBar>(find.byType(TabBar)).first;
      expect(primary.tabs.map((tab) => (tab as Tab).text), ['主题', '回复', '点评']);
      expect(primary.tabAlignment, TabAlignment.fill);
      expect(controller(selected).index, ['主题', '回复', '点评'].indexOf(selected));
    }

    primaryIsStable('主题');
    await tester.tap(find.widgetWithText(Tab, '已发表'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller('已发表').index, 1);
    expect(find.text('我发表的主题'), findsOneWidget);
    client.pendingFilter!.complete(postsFixture());
    client.pendingFilter = null;
    await tester.pumpAndSettle();
    expect(controller('已发表').index, 1);
    await tester.tap(find.widgetWithText(Tab, '回复'));
    await tester.pumpAndSettle();
    primaryIsStable('回复');
    expect(Uri.parse(client.requests.last).queryParameters['filter'], 'common');
    expect(controller('已发表').index, 1);
    await tester.tap(find.widgetWithText(Tab, '点评'));
    await tester.pumpAndSettle();
    primaryIsStable('点评');
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('已发表'), findsNothing);
    expect(
      Uri.parse(client.requests.last).queryParameters.containsKey('filter'),
      isFalse,
    );
    await tester.tap(find.widgetWithText(Tab, '主题'));
    await tester.pumpAndSettle();
    primaryIsStable('主题');
    expect(controller('已发表').index, 1);
    expect(Uri.parse(client.requests.last).queryParameters['filter'], 'common');
    await tester.tap(find.widgetWithText(TextButton, '下一页'));
    await tester.pumpAndSettle();
    expect(Uri.parse(client.requests.last).queryParameters['filter'], 'common');
    expect(find.text('第二页主题'), findsOneWidget);
    client
      ..pendingFilterKey = 'save'
      ..pendingFilter = Completer<String>();
    await tester.tap(find.widgetWithText(Tab, '草稿箱'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller('草稿箱').index, 2);
    client.pendingFilter!.completeError(const ForumFailure('筛选请求失败'));
    client.pendingFilter = null;
    await tester.pumpAndSettle();
    expect(controller('已发表').index, 1);
    expect(find.text('第二页主题'), findsOneWidget);
    final state = tester.state<NativeForumPageState>(
      find.byType(NativeForumPage),
    );
    expect(state.currentUri.queryParameters['filter'], 'common');
    expect(state.currentUri.queryParameters['page'], '2');
    expect(routes.pushes, pushes);
    expect(tester.takeException(), isNull);
  });

  test('我的帖子仍拒绝登录表单、验证页和缺失结构的响应', () {
    final uri = forumUri('home.php?mod=space&do=thread&view=me&filter=common');
    for (final source in [
      '${emptyPostsFixture()}<form id="loginform_test"><input name="username"></form>',
      '<title>403 Forbidden</title><p class="emp">暂无相关帖子</p>',
      '<div id="ct"><script>challenge()</script></div>',
      emptyPostsFixture().replaceAll('class="emp"', 'class="unknown"'),
      emptyPostsFixture().replaceAll('暂无相关帖子', ''),
    ]) {
      expect(() => ForumMyPosts(source, uri), throwsA(isA<ForumFailure>()));
    }
  });

  testWidgets('已发表为空时显示空状态，其他空分类及切回全部不跳登录或网页', (tester) async {
    final client = OwnContentClient()..emptyFilters.addAll(['common', 'save']);
    final routes = RouteCounter();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: NativeForumPage(
          title: '我的帖子',
          uri: forumUri('home.php?mod=space&do=thread&view=me'),
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pushes = routes.pushes, previews = client.previews;
    for (final label in ['已发表', '草稿箱']) {
      await tester.tap(find.widgetWithText(Tab, label));
      await tester.pumpAndSettle();
      expect(find.text('暂无相关帖子'), findsOneWidget);
      expect(find.text('我发表的主题'), findsNothing);
      expect(find.textContaining('页面未返回'), findsNothing);
      expect(find.textContaining('登录'), findsNothing);
      expect(find.byType(TabBar), findsNWidgets(2));
      expect(routes.pushes, pushes);
      expect(client.previews, previews);
    }
    await tester.tap(find.widgetWithText(Tab, '全部'));
    await tester.pumpAndSettle();
    expect(find.text('我发表的主题'), findsOneWidget);
    expect(find.text('暂无相关帖子'), findsNothing);
    expect(routes.pushes, pushes);
    expect(tester.takeException(), isNull);
  });

  test('我的帖子解析两层分类、真实主题统计和安全本人分页', () {
    final data = ForumMyPosts(
      postsFixture(),
      forumUri('home.php?mod=space&do=thread&view=me'),
    );
    expect(data.statuses.map((tab) => tab.label), [
      '全部',
      '已发表',
      '草稿箱',
      '已关闭',
      '待审核',
      '已忽略',
      '回收站',
    ]);
    expect(data.types.map((tab) => tab.label), ['主题', '回复', '点评']);
    expect(data.threads.single.title, '我发表的主题');
    expect(data.threads.single.author, isEmpty);
    expect(data.threads.single.replies, '2');
    expect(data.threads.single.views, '320');
    for (final tab in [...data.statuses, ...data.types]) {
      final target = Uri.parse(tab.url);
      expect(isForumUri(target), isTrue);
      expect(target.queryParameters['view'], 'me');
      expect(target.queryParameters.containsKey('uid'), isFalse);
    }
    expect(Uri.parse(data.next!).queryParameters['page'], '2');
  });

  testWidgets('本人入口复用完整主页，默认主题且只请求一次资料', (tester) async {
    final client = OwnContentClient();
    await tester.pumpWidget(
      MaterialApp(
        home: ForumAccountPage(
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UserHomePage), findsOneWidget);
    expect(find.text('我的主页'), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(4));
    expect(find.text('我的第一个主题'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
    expect(find.text('收听TA'), findsNothing);
    expect(find.text('加为好友'), findsNothing);
    expect(
      client.requests.where((url) => url.contains('do=profile')),
      hasLength(1),
    );
    expect(Uri.parse(client.requests.last).queryParameters['uid'], '123');
    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    expect(find.text('注册时间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本人换号重新定位UID，不保留旧人的主页', (tester) async {
    final client = OwnContentClient();
    await tester.pumpWidget(
      MaterialApp(home: ForumAccountPage(client: client)),
    );
    await tester.pumpAndSettle();
    client
      ..uid = '789'
      ..name = '当前本人';
    sessionRevision.value++;
    await tester.pumpAndSettle();
    final page = tester.widget<UserHomePage>(find.byType(UserHomePage));
    expect(page.uri.queryParameters['uid'], '789');
    expect(find.text('木棉'), findsNothing);
    expect(find.text('当前本人'), findsWidgets);
    expect(find.text('退出登录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的帖子原生分栏卡片，筛选分页原位切换，回复不冒用首楼', (tester) async {
    final client = OwnContentClient();
    final routes = RouteCounter();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routes],
        home: NativeForumPage(
          title: '我的帖子',
          uri: forumUri('home.php?mod=space&do=thread&view=me'),
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsNWidgets(2));
    for (final bar in tester.widgetList<TabBar>(find.byType(TabBar))) {
      expect(bar.dividerColor, Colors.transparent);
    }
    expect(find.text('填写信息'), findsNothing);
    expect(find.text('最后回复者'), findsNothing);
    expect(find.text('我发表的主题'), findsOneWidget);
    expect(find.text('UID 123'), findsOneWidget);
    final pushes = routes.pushes;
    await tester.tap(find.widgetWithText(Tab, '已发表'));
    await tester.pumpAndSettle();
    expect(Uri.parse(client.requests.last).queryParameters['filter'], 'common');
    expect(routes.pushes, pushes);
    await tester.tap(find.widgetWithText(TextButton, '下一页'));
    await tester.pumpAndSettle();
    expect(find.text('第二页主题'), findsOneWidget);
    expect(routes.pushes, pushes);
    final previews = client.previews;
    await tester.tap(find.widgetWithText(Tab, '回复'));
    await tester.pumpAndSettle();
    expect(find.text('我自己的回复内容'), findsOneWidget);
    expect(client.previews, previews);
    final link = tester.widget<ThreadTile>(find.byType(ThreadTile)).link;
    expect(Uri.parse(link.url).queryParameters['pid'], '901');
    expect(routes.pushes, pushes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的帖子换号后迟到的筛选结果不能恢复旧列表', (tester) async {
    final client = OwnContentClient()..pendingFilter = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '我的帖子',
          uri: forumUri('home.php?mod=space&do=thread&view=me'),
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, '草稿箱'));
    await tester.pump();
    sessionRevision.value++;
    await tester.pump();
    client.pendingFilter!.complete(postsFixture());
    await tester.pumpAndSettle();
    expect(find.text('我发表的主题'), findsNothing);
    expect(find.textContaining('账号状态已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本人主页与我的帖子明暗和大字体布局预览', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fontFile = File('C:/Windows/Fonts/msyh.ttc');
    if (fontFile.existsSync()) {
      for (final family in ['Roboto', 'Ahem']) {
        final font = FontLoader(family)
          ..addFont(
            Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
          );
        await tester.runAsync(font.load);
      }
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'D:/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await tester.runAsync(icons.load);
    Directory('docs').createSync(recursive: true);
    for (final (dark, scale, label) in [
      (true, 1.0, 'dark'),
      (false, 1.0, 'light'),
      (true, 2.0, 'large'),
    ]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final own in [true, false]) {
        final client = OwnContentClient();
        final preferences = Preferences(await SharedPreferences.getInstance());
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
              home: own
                  ? ForumAccountPage(client: client, preferences: preferences)
                  : NativeForumPage(
                      title: '我的帖子',
                      uri: forumUri('home.php?mod=space&do=thread&view=me'),
                      client: client,
                      preferences: preferences,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Tab), findsNWidgets(own ? 4 : 10));
        expect(find.text('填写信息'), findsNothing);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('docs/preview-${own ? 'own-home' : 'my-posts'}-$label.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        if (!own) {
          final primaryTop = tester.getTopLeft(find.byType(TabBar).first).dy;
          await tester.tap(find.widgetWithText(Tab, '点评'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(TabBar), findsOneWidget);
          expect(tester.getTopLeft(find.byType(TabBar)).dy, primaryTop);
          for (final (index, label) in ['主题', '回复', '点评'].indexed) {
            expect(
              tester.getCenter(find.widgetWithText(Tab, label)).dx,
              closeTo(65 + index * 130, 0.1),
            );
          }
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('docs/preview-my-comments-$label.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
  });
}
