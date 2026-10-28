import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/main.dart';
import 'package:mt_forum/pages/login_page.dart';
import 'package:mt_forum/pages/web_page.dart';
import 'package:mt_forum/pages/forum_page.dart';
import 'package:mt_forum/pages/native_forum_page.dart';
import 'package:mt_forum/pages/home_page.dart';
import 'package:mt_forum/core/utils/haptic_feedback_util.dart';
import 'package:mt_forum/core/widgets/forum_avatar.dart';
import 'package:mt_forum/core/design_system/components/review_frosted_app_bar.dart';

class BoardClient extends ForumClient {
  @override
  Future<ThreadSummary> threadSummary(
    String url,
    bool Function() active,
  ) async => ThreadSummary(
    parseForum(
      File('test/fixtures/thread.html').readAsStringSync(),
      forumUri(url),
    ),
  );
  @override
  Future<ForumDocument> load(String url) async => url.contains('forum-2-2')
      ? const ForumDocument(
          title: '版本发布',
          links: [ForumLink('下一页帖子', 'https://bbs.binmt.cc/thread-3-1-1.html')],
        )
      : parseForum(
          File('test/fixtures/board.html').readAsStringSync(),
          forumUri(url),
        );
}

class DelayedAccountClient extends FakeClient {
  final accountRequest = Completer<String>();
  @override
  Future<String> source(String url) => accountRequest.future;
}

class HomeDetailClient extends FakeClient {
  bool guideFails = false;
  @override
  Future<ForumDocument> load(String url) async {
    if (url.contains('mod=guide')) {
      if (guideFails) throw const ForumFailure('导读暂时不可用');
      return parseForum(
        File('test/fixtures/guide.html').readAsStringSync(),
        forumUri(url),
      );
    }
    return const ForumDocument(
      title: 'MT论坛',
      hot: [
        ForumLink('排行第一', 'https://bbs.binmt.cc/thread-9-1-1.html'),
        ForumLink('排行第二', 'https://bbs.binmt.cc/thread-8-1-1.html'),
      ],
      latest: [
        ForumLink(
          '最新标题',
          'https://bbs.binmt.cc/thread-175375-1-1.html',
          author: '提示中的作者',
          views: '84',
          replies: '3',
          date: '2026-10-26',
        ),
      ],
    );
  }
}

class PaginatedHomeClient extends FakeClient {
  int nextCalls = 0;
  final page = Completer<ForumDocument>();
  @override
  Future<ForumDocument> load(String url) async {
    if (url.contains('page=2')) {
      nextCalls++;
      return page.future;
    }
    if (url.contains('mod=guide')) {
      return ForumDocument(
        title: '最新发表',
        links: [
          for (var i = 0; i < 15; i++)
            ForumLink(
              '分页帖子$i',
              '$forumOrigin/thread-${100 + i}-1-1.html',
              author: '作者$i',
              excerpt: '摘要$i',
            ),
        ],
        next: '$forumOrigin/forum.php?mod=guide&view=newthread&page=2',
      );
    }
    return super.load(url);
  }
}

class ControlledClient extends ForumClient {
  @override
  Future<ThreadSummary> threadSummary(
    String url,
    bool Function() active,
  ) async => throw const ForumFailure('测试无摘要');
  final pending = <Completer<ForumDocument>>[];
  @override
  Future<ForumDocument> load(String url) {
    final request = Completer<ForumDocument>();
    pending.add(request);
    return request.future;
  }
}

class FakeClient extends ForumClient {
  @override
  Future<ThreadSummary> threadSummary(
    String url,
    bool Function() active,
  ) async => throw const ForumFailure('测试无摘要');
  @override
  Future<String> source(String url) async =>
      '<div id="uhd"><h2>测试昵称</h2><img src="https://cdn.binmt.cc/avatar.jpg"></div><div id="ct"><h2>测试昵称 (UID: 123)</h2><li><em>积分</em>100</li></div>';
  bool fail = false;
  int calls = 0;
  @override
  Future<ForumDocument> load(String url) async {
    if (url.contains('mod=guide')) return const ForumDocument(title: '导读');
    calls++;
    if (fail) throw const ForumFailure('测试网络失败');
    return const ForumDocument(
      title: 'MT论坛',
      latest: [
        ForumLink('真实内容的测试替身', 'https://bbs.binmt.cc/thread-1-1-1.html'),
      ],
      hot: [ForumLink('热门话题测试', 'https://bbs.binmt.cc/thread-2-1-1.html')],
    );
  }
}

class MessagesHomeClient extends FakeClient {
  final requests = <String>[];
  @override
  Future<String> source(String url) async {
    if (url.contains('view=mypost')) {
      requests.add(url);
      return File('test/fixtures/messages_mypost.html').readAsStringSync();
    }
    if (url.contains('do=notice')) {
      requests.add(url);
      return File('test/fixtures/messages_system.html').readAsStringSync();
    }
    if (url.contains('do=pm')) {
      requests.add(url);
      return File('test/fixtures/messages.html').readAsStringSync();
    }
    return super.source(url);
  }
}

class DelayedMessagesHomeClient extends FakeClient {
  final pending = <Completer<String>>[];
  @override
  Future<String> source(String url) {
    if (url.contains('do=pm')) {
      final result = Completer<String>();
      pending.add(result);
      return result.future;
    }
    return super.source(url);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    forumAuthenticated.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, (_) async => '');
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, null),
  );

  Future<Preferences> prefs() async {
    SharedPreferences.setMockInitialValues({});
    return Preferences(await SharedPreferences.getInstance());
  }

  for (final enabled in [true, false]) {
    testWidgets('发现搜索图标、文字、空白与编辑搜索栏触感一致 enabled=$enabled', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        HapticFeedbackUtil.isEnabled = true;
        HapticFeedbackUtil.resetForTesting();
      });
      final settings = await prefs();
      settings.haptics = enabled;
      await settings.save();
      await tester.pumpWidget(
        MtForumApp(
          preferences: settings,
          client: FakeClient(),
          useBrowserReader: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发现').last);
      await tester.pumpAndSettle();
      expect(find.text('精华内容'), findsOneWidget);
      expect(find.text('精华采撷'), findsNothing);
      for (final target in ['icon', 'text', 'blank']) {
        final bar = find.byType(SearchBar);
        final icon = find.descendant(
          of: bar,
          matching: find.byIcon(Icons.search),
        );
        expect(
          tester.getRect(icon).left - tester.getRect(bar).left,
          closeTo(16, 1),
        );
        calls.clear();
        HapticFeedbackUtil.resetForTesting();
        if (target == 'icon') {
          await tester.tap(icon);
        } else if (target == 'text') {
          await tester.tapAt(
            tester.getTopLeft(find.byType(TextField)) + const Offset(20, 12),
          );
        } else {
          await tester.tapAt(
            tester.getRect(bar).centerRight - const Offset(24, 0),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(SearchPage), findsOneWidget);
        expect(calls, hasLength(enabled ? 1 : 0));
        calls.clear();
        HapticFeedbackUtil.resetForTesting();
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(calls, hasLength(enabled ? 1 : 0));
        Navigator.of(tester.element(find.byType(SearchPage))).pop();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('首页最新惰性分页、合并去重，末页重复上拉不重复请求', (tester) async {
    final client = PaginatedHomeClient();
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: client,
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('分页帖子14', findRichText: true), findsNothing);
    await tester.scrollUntilVisible(
      find.text('分页帖子14', findRichText: true),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(client.nextCalls, 1);
    client.page.complete(
      const ForumDocument(
        title: '最新发表',
        links: [
          ForumLink('分页帖子14', '$forumOrigin/thread-114-1-1.html'),
          ForumLink(
            '末页新增帖子',
            '$forumOrigin/thread-115-1-1.html',
            excerpt: '末页摘要',
          ),
        ],
        next: '$forumOrigin/forum.php?mod=guide&view=newthread&page=2',
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('已经到底了'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('末页新增帖子', findRichText: true), findsOneWidget);
    expect(find.text('末页摘要'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(client.nextCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('悬浮底栏按下没有水波纹，选中胶囊平滑移动', (tester) async {
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: FakeClient(),
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    final target = find
        .ancestor(of: find.text('发现').last, matching: find.byType(InkWell))
        .first;
    final ink = tester.widget<InkWell>(target);
    expect(ink.splashColor, Colors.transparent);
    expect(ink.highlightColor, Colors.transparent);
    final pill = find
        .descendant(
          of: find.byType(AnimatedSlide),
          matching: find.byType(DecoratedBox),
        )
        .first;
    final start = tester.getTopLeft(pill).dx;
    final gesture = await tester.startGesture(tester.getCenter(target));
    await tester.pump();
    expect(tester.getTopLeft(pill).dx, start);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final middle = tester.getTopLeft(pill).dx;
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(pill).dx;
    expect(middle, greaterThan(start));
    expect(end, greaterThan(middle));
    expect(tester.takeException(), isNull);
  });

  testWidgets('液态玻璃与标准底栏不叠加按压视觉反馈', (tester) async {
    final settings = await prefs();
    settings.liquidGlass = true;
    await tester.pumpWidget(
      MtForumApp(
        preferences: settings,
        client: FakeClient(),
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<GlassTabBar>(find.byType(GlassTabBar)).interactionBehavior,
      GlassInteractionBehavior.none,
    );
    expect(
      tester
          .widget<GlassTabBar>(find.byType(GlassTabBar))
          .indicatorPinchStrength,
      0,
    );
    settings.floatingNavigation = false;
    await settings.save();
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NavigationBar));
    final overlay = Theme.of(context).navigationBarTheme.overlayColor!;
    expect(overlay.resolve({WidgetState.pressed}), Colors.transparent);
    expect(overlay.resolve({WidgetState.focused}), isNull);
    expect(tester.takeException(), isNull);
  });
  for (final fails in [false, true]) {
    testWidgets('首页排名与最新详情，导读失败=$fails 时保留首页数据', (tester) async {
      await tester.pumpWidget(
        MtForumApp(
          preferences: await prefs(),
          client: HomeDetailClient()..guideFails = fails,
          useBrowserReader: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('排行第一'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('1'), findsOneWidget);
      final title = tester.widget<Text>(find.text('排行第一'));
      expect(title.style!.fontWeight, FontWeight.w400);
      expect(title.style!.fontSize, lessThanOrEqualTo(14));
      await tester.scrollUntilVisible(
        find.text(fails ? '提示中的作者' : '最新作者'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('84'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2026-10-26'), findsOneWidget);
      if (!fails) expect(find.byType(ForumAvatar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('板块信息、置顶分组和帖子详情可见，分页保留板块信息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ForumPage(
          link: const ForumLink('版本发布', 'https://bbs.binmt.cc/forum-2-1.html'),
          client: BoardClient(),
          preferences: await prefs(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('置顶帖'), findsOneWidget);
    expect(find.text('公告标题'), findsOneWidget);
    expect(tester.getSize(find.text('置顶')).height, lessThan(26));
    expect(find.text('测试作者'), findsOneWidget);
    expect(find.text('12815'), findsOneWidget);
    expect(find.text('103'), findsOneWidget);
    expect(find.text('2026-10-9'), findsOneWidget);
    expect(find.textContaining('主题: 148'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('加载下一页'), 100);
    await tester.tap(find.text('加载下一页'));
    await tester.pumpAndSettle();
    expect(find.textContaining('主题: 148'), findsOneWidget);
    expect(find.text('下一页帖子'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('退出后迟到的账号资料不能恢复到我的卡片', (tester) async {
    var cookie = 'forum_auth=fixture';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => cookie,
    );
    final client = DelayedAccountClient();
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: client,
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    cookie = '';
    forumAuthenticated.value = false;
    sessionRevision.value++;
    client.accountRequest.complete(
      '<div id="uhd"><h2>旧昵称</h2></div><div id="ct"><h2>旧昵称 (UID: 99)</h2><li><em>积分</em>1</li></div>',
    );
    await tester.pumpAndSettle();
    expect(find.text('旧昵称'), findsNothing);
    expect(find.text('登录 / 注册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('五项悬浮底栏在 $width 宽屏幕有足够点击宽度', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MtForumApp(
          preferences: await prefs(),
          client: FakeClient(),
          useBrowserReader: false,
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['首页', '发现', '发帖', '消息', '我的']) {
        final target = find
            .ancestor(of: find.text(label).last, matching: find.byType(InkWell))
            .first;
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final floating in [false, true]) {
    for (final entry in ['底栏', '顶栏']) {
      testWidgets('游客从$entry进入消息标签，取消登录后保留消息页（悬浮=$floating）', (tester) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ForumClient.platform,
          (_) async => 'forum_auth=; forum_saltkey=guest',
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            ForumClient.platform,
            null,
          );
        });
        final settings = await prefs();
        settings.floatingNavigation = floating;
        final client = FakeClient();
        await tester.pumpWidget(
          MtForumApp(
            preferences: settings,
            client: client,
            useBrowserReader: false,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          entry == '底栏'
              ? find.text('消息').last
              : find.widgetWithIcon(IconButton, Icons.notifications_none),
        );
        await tester.pumpAndSettle();
        expect(find.text('登录后查看消息'), findsOneWidget);
        expect(find.byType(ForumLoginPage), findsNothing);
        expect(find.text('首页'), findsWidgets);
        await tester.tap(find.text('登录 / 注册'));
        await tester.pumpAndSettle();
        expect(find.byType(ForumLoginPage), findsOneWidget);
        expect(find.text('登录 MT论坛'), findsOneWidget);
        expect(find.byType(ForumWebPage), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ForumLoginPage), findsNothing);
        expect(find.byType(ForumWebPage), findsNothing);
        expect(find.text('登录后查看消息'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('版本发布'), findsOneWidget);
        expect(client.calls, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('已登录消息作为底栏页面，分类和切换保持状态', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => 'forum_auth=fixture',
    );
    final client = MessagesHomeClient();
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: client,
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息').last);
    await tester.pumpAndSettle();
    expect(find.byType(NativeForumPage), findsOneWidget);
    expect(
      tester.widget<NativeForumPage>(find.byType(NativeForumPage)).embedded,
      isTrue,
    );
    expect(
      Navigator.of(tester.element(find.byType(NativeForumPage))).canPop(),
      isFalse,
    );
    expect(find.text('系统提醒'), findsOneWidget);
    expect(find.byType(TabBar), findsNWidgets(2));
    expect(
      tester.getRect(find.byType(TabBar).last).bottom,
      closeTo(tester.getRect(find.byType(ReviewFrostedBackdrop)).bottom, 0.5),
    );
    expect(find.text('私人消息'), findsOneWidget);
    expect(find.text('发送消息'), findsOneWidget);
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
      const Offset(3, 0),
    );
    expect(client.requests, hasLength(1));
    await tester.tap(find.text('我的帖子'));
    await tester.pumpAndSettle();
    expect(client.requests.last, contains('view=mypost'));
    expect(find.byType(TabBar), findsNWidgets(2));
    for (final label in ['帖子', '点评', '活动', '悬赏', '商品', '提到我的']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('筛选设置'), findsOneWidget);
    await tester.tap(find.text('系统提醒'));
    await tester.pumpAndSettle();
    expect(client.requests.last, contains('do=notice'));
    expect(find.byType(TabBar), findsOneWidget);
    expect(
      tester.getRect(find.byType(TabBar).first).bottom,
      closeTo(tester.getRect(find.byType(ReviewFrostedBackdrop)).bottom, 0.5),
    );
    expect(
      Navigator.of(tester.element(find.byType(NativeForumPage))).canPop(),
      isFalse,
    );
    await tester.tap(find.text('发现').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息').last);
    await tester.pumpAndSettle();
    expect(client.requests, hasLength(3));
    expect(find.text('系统提醒'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('版本发布'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('消息页登录成功后直接加载消息并保留底栏', (tester) async {
    var cookie = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => cookie,
    );
    final client = MessagesHomeClient()
      ..browserLogin =
          ({
            required loginField,
            required username,
            required password,
            required questionId,
            required answer,
            required remember,
          }) async {
            cookie = 'forum_auth=fixture';
            return '登录成功';
          };
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: client,
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('登录 / 注册'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'fixture');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'fixture-password',
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '登录'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(ForumLoginPage), findsNothing);
    expect(find.text('系统提醒'), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
      const Offset(3, 0),
    );
    expect(client.requests, hasLength(1));
  });

  testWidgets('切换账号后迟到消息不能覆盖新账号内容', (tester) async {
    var cookie = 'forum_auth=first';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => cookie,
    );
    final client = DelayedMessagesHomeClient();
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: client,
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息').last);
    await tester.pump();
    await tester.pump();
    expect(client.pending, hasLength(1));
    cookie = 'forum_auth=second';
    sessionRevision.value++;
    await tester.pump();
    await tester.pump();
    expect(client.pending, hasLength(2));
    final fixture = File('test/fixtures/messages.html').readAsStringSync();
    client.pending[0].complete(fixture.replaceFirst('当前没有相应的短消息', '旧账号消息'));
    client.pending[1].complete(fixture.replaceFirst('当前没有相应的短消息', '新账号消息'));
    await tester.pumpAndSettle();
    expect(find.text('旧账号消息'), findsNothing);
    expect(find.text('新账号消息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Email 原生登录传递官网 loginfield 并通知账号变化', (tester) async {
    var cookie = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => cookie,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ForumClient.platform,
        null,
      );
    });
    String? submittedMethod;
    final client = FakeClient()
      ..browserLogin =
          ({
            required String loginField,
            required String username,
            required String password,
            required int questionId,
            required String answer,
            required bool remember,
          }) async {
            submittedMethod = loginField;
            cookie = 'forum_auth=valid-session';
            return '登录成功';
          };
    bool? result;
    final revision = sessionRevision.value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showForumLogin(context, client),
            child: const Text('打开登录'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('邮箱'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'fixture@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '登录'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(submittedMethod, 'email');
    expect(find.byType(ForumLoginPage), findsNothing);
    expect(sessionRevision.value, revision + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('官网已建立会话但桥接无响应时结束登录，迟到错误不回退', (tester) async {
    var cookie = '';
    final pending = Completer<String>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => cookie,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ForumClient.platform,
        null,
      ),
    );
    final client = FakeClient()
      ..browserLogin = ({
        required String loginField,
        required String username,
        required String password,
        required int questionId,
        required String answer,
        required bool remember,
      }) => pending.future;
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showForumLogin(context, client),
            child: const Text('打开登录'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'fixture');
    await tester.enterText(find.byType(TextFormField).at(1), 'synthetic-only');
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '登录'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();
    cookie = 'forum_auth=server-established';
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(ForumLoginPage), findsNothing);
    expect(forumAuthenticated.value, isTrue);
    pending.completeError(const ForumFailure('迟到的错误'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('已登录会话恢复到我的页面，登录入口不再打开表单', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => 'forum_auth=restored',
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ForumClient.platform,
        null,
      ),
    );
    final client = FakeClient();
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: client,
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('测试昵称'), findsOneWidget);
    expect(find.text('UID: 123'), findsOneWidget);
    expect(find.text('已登录 · 账号资料'), findsNothing);
    expect(find.text('退出登录'), findsNothing);
    expect(find.byType(ForumAvatar), findsOneWidget);
    expect(find.text('登录 / 注册'), findsNothing);
    final context = tester.element(find.text('测试昵称'));
    expect(await showForumLogin(context, client), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ForumLoginPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final cancel in [false, true]) {
    testWidgets(cancel ? '取消登录停止转圈并忽略迟到响应' : '无响应登录在期限后停止转圈并允许重试', (
      tester,
    ) async {
      var cancellations = 0;
      final pending = Completer<String>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ForumClient.platform,
        (_) async => '',
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ForumClient.platform,
          null,
        ),
      );
      final client = FakeClient()
        ..browserLogin =
            ({
              required String loginField,
              required String username,
              required String password,
              required int questionId,
              required String answer,
              required bool remember,
            }) {
              return pending.future;
            }
        ..browserCancelLogin = () async {
          cancellations++;
        };
      await tester.pumpWidget(
        MaterialApp(home: ForumLoginPage(client: client)),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'fixture');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'synthetic-only',
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '登录'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      if (cancel) {
        await tester.scrollUntilVisible(
          find.text('取消登录'),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('取消登录'));
        await tester.pump();
        pending.complete('登录成功');
      } else {
        await tester.pump(const Duration(seconds: 46));
      }
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ForumLoginPage), findsOneWidget);
      expect(cancellations, greaterThanOrEqualTo(1));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '登录'))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('首页专区和快捷入口按参考图收紧尺寸', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: FakeClient(),
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    final boardCard = find
        .ancestor(of: find.text('板块'), matching: find.byType(Card))
        .first;
    expect(tester.getSize(boardCard).height, lessThanOrEqualTo(260));
    final boardHeader = find
        .descendant(of: boardCard, matching: find.byType(ListTile))
        .first;
    expect(tester.getSize(boardHeader).height, greaterThanOrEqualTo(48));
    final avatars = find.descendant(
      of: boardCard,
      matching: find.byType(CircleAvatar),
    );
    expect(avatars, findsNWidgets(12));
    expect(tester.getSize(avatars.first), const Size(36, 36));
    final shortcut = find
        .ancestor(of: find.text('签到'), matching: find.byType(Card))
        .first;
    expect(tester.getSize(shortcut).height, lessThanOrEqualTo(96));
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换账号时旧请求不能重新显示旧账号帖子', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = ControlledClient();
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: client,
        useBrowserReader: false,
      ),
    );
    sessionRevision.value++;
    await tester.pump();
    expect(client.pending, hasLength(2));
    client.pending[0].complete(
      const ForumDocument(
        title: '旧账号',
        hot: [ForumLink('旧账号私密帖子', 'https://bbs.binmt.cc/thread-1-1-1.html')],
      ),
    );
    await tester.pump();
    expect(find.text('旧账号私密帖子'), findsNothing);
    client.pending[1].complete(
      const ForumDocument(
        title: '新账号',
        hot: [ForumLink('新账号公开帖子', 'https://bbs.binmt.cc/thread-2-1-1.html')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新账号公开帖子'), findsOneWidget);
    expect(find.text('旧账号私密帖子'), findsNothing);
  });

  testWidgets('首页切换保持内容，刷新失败保留已加载数据', (tester) async {
    final client = FakeClient();
    await tester.pumpWidget(
      MtForumApp(
        preferences: await prefs(),
        client: client,
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('版本发布'), findsOneWidget);
    await tester.tap(find.text('发现').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页').last);
    await tester.pumpAndSettle();
    expect(client.calls, 1);
    client.fail = true;
    await tester.tap(find.byTooltip('刷新首页'));
    await tester.pumpAndSettle();
    expect(client.calls, 2);
    expect(find.text('测试网络失败'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('热门话题测试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('消息顶栏在窄屏和大字号下完整显示并可滚动到末项', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await tester.runAsync(loader.load);
    }
    for (final scale in [1.0, 1.4, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(
        MtForumApp(
          key: ValueKey(scale),
          preferences: await prefs(),
          client: FakeClient(),
          useBrowserReader: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('消息').last);
      await tester.pumpAndSettle();
      final bar = find.byType(TabBar).first;
      expect(tester.widget<TabBar>(bar).isScrollable, isTrue);
      for (final label in ['消息', '我的帖子', '坛友互动', '系统提醒', '应用提醒']) {
        final tab = find.descendant(
          of: bar,
          matching: find.widgetWithText(Tab, label),
        );
        final text = find.descendant(of: tab, matching: find.byType(RichText));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(
          paragraph.size.width + 0.5,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
          reason: '$label 在 $scale 倍字号下被裁切',
        );
      }
      await tester.drag(bar, const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用提醒'));
      await tester.pumpAndSettle();
      expect(find.text('登录后查看消息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('大字体窄屏和深色设置不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final settings = await prefs();
    settings.mode = ThemeMode.dark;
    await tester.pumpWidget(
      MtForumApp(
        preferences: settings,
        client: FakeClient(),
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('个性化'));
    await tester.tap(find.text('个性化'));
    await tester.pumpAndSettle();
    expect(find.text('纯黑模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
