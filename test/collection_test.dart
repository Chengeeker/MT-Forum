import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/native_forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/pages/home_page.dart';
import 'package:mt_forum/pages/web_page.dart';
import 'package:mt_forum/pages/native_forum_page.dart';
import 'package:mt_forum/pages/forum_page.dart';
import 'package:mt_forum/pages/thread_collection_list.dart';
import 'package:mt_forum/core/theme/app_theme.dart';
import 'package:mt_forum/core/widgets/forum_avatar.dart';

class CollectionClient extends ForumClient {
  int summaries = 0, writes = 0;
  bool fail = true;
  Map<String, dynamic>? fields;
  Completer<(String, Uri)>? delayed;
  @override
  Future<String> source(String url) async =>
      File('test/fixtures/favorites.html').readAsStringSync();
  @override
  Future<ThreadSummary> threadSummary(
    String url,
    bool Function() active,
  ) async {
    summaries++;
    return ThreadSummary(
      parseForum(
        File('test/fixtures/thread.html').readAsStringSync(),
        forumUri(url),
      ),
    );
  }

  @override
  Future<(String, Uri)> submit(
    Uri action,
    Map<String, dynamic> values, {
    String method = 'POST',
  }) async {
    writes++;
    fields = values;
    if (delayed != null) return delayed!.future;
    if (fail) throw const ForumFailure('模拟删除失败');
    return ('<div id="messagetext">删除成功</div>', action);
  }
}

class DelayedPreviewClient extends CollectionClient {
  final requests = <(String, Completer<ThreadSummary>, bool Function())>[];
  @override
  Future<String> source(String url) async =>
      (await super.source(url))
          .replaceAll('forum-2-1.html', 'thread-124-1-1.html')
          .replaceAll('收藏示例板块', '收藏第二帖');

  @override
  Future<ThreadSummary> threadSummary(String url, bool Function() active) {
    summaries++;
    final request = Completer<ThreadSummary>();
    requests.add((url, request, active));
    return request.future;
  }

  void complete(int index, {String author = '测试作者'}) {
    final (url, request, _) = requests[index];
    request.complete(
      ThreadSummary(
        parseForum(
          File('test/fixtures/thread.html')
              .readAsStringSync()
              .replaceAll('测试作者', author),
          forumUri(url),
        ),
      ),
    );
  }
}

Future<Preferences> historyPreferences(int count) async {
  final preferences = Preferences(await SharedPreferences.getInstance());
  preferences.history = [
    for (var i = 0; i < count; i++)
      ForumLink('历史条目$i', '$forumOrigin/thread-${100 + i}-1-1.html'),
  ];
  return preferences;
}

int preparedRows(WidgetTester tester) =>
    (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
            as SliverChildBuilderDelegate)
        .childCount! -
    2;

void main() {
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
  test('收藏从同一行配对帖子与收藏 ID，排除删除链接并保留板块', () {
    final items = parseFavorites(
      File('test/fixtures/favorites.html').readAsStringSync(),
      forumUri('home.php?mod=space&do=favorite'),
    );
    expect(items.map((e) => e.id), ['10', '11']);
    expect(items.first.link.title, '收藏示例帖子');
    expect(boardId(forumUri(items.last.link.url)), '2');
  });
  testWidgets('收藏整批准备后显示卡片，不逐张显示标题再补全文', (tester) async {
    final client = DelayedPreviewClient();
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '我的收藏',
          uri: forumUri('home.php?mod=space&do=favorite'),
          client: client,
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pump();
    expect(client.requests, hasLength(2));
    expect(find.text('收藏示例帖子'), findsNothing);
    client.complete(0);
    await tester.pump();
    expect(find.text('测试作者'), findsNothing);
    expect(preparedRows(tester), 0);
    client.complete(1);
    await tester.pump();
    expect(preparedRows(tester), 2);
    expect(find.text('收藏示例帖子'), findsOneWidget);
    expect(find.text('测试作者'), findsNWidgets(2));
    for (final tile in tester.widgetList<ThreadTile>(find.byType(ThreadTile))) {
      expect(tile.loadSummary, isNull);
      expect(tile.summary, isNotNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史分批预取、整批追加，滚回及记录重排不重复请求', (tester) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = DelayedPreviewClient();
    final preferences = await historyPreferences(30);
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(client: client, preferences: preferences),
      ),
    );
    await tester.pump();
    expect(client.requests, hasLength(collectionPreviewBatchSize));
    expect(preparedRows(tester), 0);
    client.complete(0);
    await tester.pump();
    expect(preparedRows(tester), 0);
    expect(find.text('历史条目0'), findsNothing);
    for (var i = 1; i < 10; i++) {
      client.complete(i);
    }
    await tester.pump();
    expect(preparedRows(tester), 10);
    expect(find.text('测试作者'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('历史条目9'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(client.requests, hasLength(20));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final offset = position.pixels;
    final firstTile = find.byType(ThreadTile).first;
    final key = tester.widget<ThreadTile>(firstTile).key!;
    final height = tester.getSize(firstTile).height;
    client.complete(10);
    await tester.pump();
    expect(preparedRows(tester), 10);
    for (var i = 11; i < 20; i++) {
      client.complete(i);
    }
    await tester.pump();
    expect(preparedRows(tester), 20);
    expect(position.pixels, closeTo(offset, 0.01));
    expect(tester.getSize(find.byKey(key)).height, height);
    position.jumpTo(0);
    await tester.pump();
    await tester.pump();
    expect(client.requests, hasLength(20));
    await preferences.visited(preferences.history[2]);
    await tester.pump();
    expect(client.requests, hasLength(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('预览超时保留标题，迟到响应不改行高，显式重试才更新', (tester) async {
    final client = DelayedPreviewClient();
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(
          client: client,
          preferences: await historyPreferences(1),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 13));
    await tester.pump();
    expect(find.text('历史条目0'), findsOneWidget);
    expect(find.text('测试作者'), findsNothing);
    final height = tester.getSize(find.byType(ThreadTile)).height;
    client.complete(0);
    await tester.pump();
    expect(find.text('测试作者'), findsNothing);
    expect(tester.getSize(find.byType(ThreadTile)).height, height);
    await tester.tap(find.text('部分帖子预览未能加载，点此重试'));
    await tester.pump();
    expect(client.requests, hasLength(2));
    client.complete(1);
    await tester.pump();
    expect(find.text('测试作者'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史会话变化丢弃旧批次和内存中的旧账号作者', (tester) async {
    final client = DelayedPreviewClient();
    final preferences = await historyPreferences(1);
    preferences.history = [
      preferences.history.single.copyWith(
        author: '旧账号私密作者',
        imageUrl: 'https://cdn.binmt.cc/old.jpg',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryPage(client: client, preferences: preferences),
      ),
    );
    await tester.pump();
    sessionRevision.value++;
    await tester.pump();
    expect(client.requests, hasLength(2));
    expect(client.requests.first.$3(), isFalse);
    client.complete(0, author: '迟到旧账号作者');
    await tester.pump();
    expect(find.text('迟到旧账号作者'), findsNothing);
    expect(find.text('旧账号私密作者'), findsNothing);
    client.complete(1, author: '当前账号作者');
    await tester.pump();
    expect(find.text('当前账号作者'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('收藏使用帖子卡片，删除前确认且失败保留选中项', (tester) async {
    final client = CollectionClient();
    final preferences = Preferences(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '我的收藏',
          uri: forumUri('home.php?mod=space&do=favorite'),
          client: client,
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('favorite[]'), findsNothing);
    expect(find.text('填写信息'), findsNothing);
    expect(find.text('测试作者'), findsOneWidget);
    expect(find.text('UID 123'), findsOneWidget);
    expect(find.textContaining('用于测试列表摘要'), findsOneWidget);
    expect(find.byType(ForumAvatar), findsOneWidget);
    expect(client.summaries, 1);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('管理收藏'));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('删除选中收藏（1）'));
    await tester.pumpAndSettle();
    expect(client.writes, 0);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.writes, 1);
    expect(client.fields!['favorite[]'], ['10']);
    expect(client.fields!['formhash'], 'fixture-token');
    expect(find.text('删除选中收藏（1）'), findsOneWidget);
    client.fail = false;
    await tester.tap(find.text('删除选中收藏（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.writes, 2);
    expect(find.text('删除选中收藏（0）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('账号切换后迟到的收藏提交不能恢复旧列表', (tester) async {
    final client = CollectionClient()..delayed = Completer<(String, Uri)>();
    final preferences = Preferences(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        home: NativeForumPage(
          title: '我的收藏',
          uri: forumUri('home.php?mod=space&do=favorite'),
          client: client,
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理收藏'));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.text('删除选中收藏（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pump();
    sessionRevision.value++;
    await tester.pump();
    client.delayed!.complete((
      '<div id="messagetext">删除成功</div>',
      forumUri('home.php?mod=spacecp&ac=favorite&op=delete'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('测试作者'), findsNothing);
    expect(find.textContaining('账号状态已变化'), findsOneWidget);
    expect(client.writes, 1);
  });
  testWidgets('收藏与历史明暗预览，历史重开仍补全资料且不存正文', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await SharedPreferences.getInstance();
    final preferences = Preferences(store);
    await preferences.visited(
      const ForumLink('历史示例帖子', '$forumOrigin/thread-123-1-1.html'),
    );
    expect(store.getString('history'), isNot(contains('测试作者')));
    final restored = Preferences(store);
    Directory('docs').createSync(recursive: true);
    final fontFile = File('C:/Windows/Fonts/msyh.ttc');
    if (fontFile.existsSync()) {
      for (final family in ['Roboto', 'Ahem']) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
          );
        await tester.runAsync(loader.load);
      }
    }
    for (final dark in [true, false]) {
      for (final history in [true, false]) {
        final boundary = GlobalKey();
        final client = CollectionClient();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
              home: history
                  ? HistoryPage(client: client, preferences: restored)
                  : NativeForumPage(
                      title: '我的收藏',
                      uri: forumUri('home.php?mod=space&do=favorite'),
                      client: client,
                      preferences: restored,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('测试作者'), findsOneWidget);
        expect(find.text('UID 123'), findsOneWidget);
        expect(find.textContaining('用于测试列表摘要'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'docs/preview-${history ? 'history' : 'favorites'}-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    sessionRevision.value++;
    await tester.pumpAndSettle();
    expect(find.text('测试作者'), findsNothing);
  });
}
