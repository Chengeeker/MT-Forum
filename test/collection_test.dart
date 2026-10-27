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
