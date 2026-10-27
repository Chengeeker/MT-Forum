import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/main.dart';
import 'package:mt_forum/core/theme/app_theme.dart';
import 'package:mt_forum/pages/native_forum_page.dart';
import 'package:mt_forum/pages/account_page.dart';
import 'package:mt_forum/pages/forum_page.dart';

import 'native_forum_test.dart' as fixture;
import 'thread_ui_test.dart' as thread_fixture;

class FixtureClient extends ForumClient {
  @override
  Future<ThreadSummary> threadSummary(String url, bool Function() active) =>
      BoardFixtureClient().threadSummary(url, active);
  @override
  Future<String> source(String url) => fixture.NativeClient().source(url);
  @override
  Future<ForumDocument> load(String url) async => parseForum(
    File(
      url.contains('mod=guide')
          ? 'test/fixtures/guide.html'
          : 'test/fixtures/home.html',
    ).readAsStringSync(),
    forumUri(url),
  );
}

class BoardFixtureClient extends ForumClient {
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
  Future<ForumDocument> load(String url) async => parseForum(
    File('test/fixtures/board-dense.html').readAsStringSync(),
    forumUri('forum-2-1.html'),
  );
}

class MessagesPreviewClient extends FixtureClient {
  @override
  Future<String> source(String url) async => url.contains('do=pm')
      ? File('test/fixtures/messages.html').readAsStringSync()
      : super.source(url);
}

void main() {
  testWidgets('首页明暗主题静态预览与布局检查', (tester) async {
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
    Directory('docs').createSync(recursive: true);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    SharedPreferences.setMockInitialValues({});
    final preferences = Preferences(await SharedPreferences.getInstance());
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      preferences.mode = mode;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MtForumApp(
            preferences: preferences,
            client: FixtureClient(),
            useBrowserReader: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('docs/preview-${mode.name}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      for (final section in [('排行榜', 'ranking'), ('最新作者', 'latest')]) {
        await tester.scrollUntilVisible(
          find.text(section.$1),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('docs/preview-${section.$2}-${mode.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    for (final screen in ['board', 'profile']) {
      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ForumClient.platform,
          (_) async => screen == 'profile' ? 'forum_auth=fixture' : '',
        );
        final boundary = GlobalKey();
        preferences.mode = mode;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: screen == 'profile'
                ? MtForumApp(
                    preferences: preferences,
                    client: FixtureClient(),
                    useBrowserReader: false,
                  )
                : MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: mode == ThemeMode.dark
                        ? AppTheme.darkTheme()
                        : AppTheme.lightTheme(),
                    home: ForumPage(
                      link: const ForumLink(
                        '版本发布',
                        'https://bbs.binmt.cc/forum-2-1.html',
                      ),
                      client: BoardFixtureClient(),
                      preferences: preferences,
                    ),
                  ),
          ),
        );
        await tester.pumpAndSettle();
        if (screen == 'profile') {
          await tester.tap(find.text('我的').last);
          await tester.pumpAndSettle();
          expect(find.text('测试账号'), findsOneWidget);
          expect(find.text('UID: 123'), findsOneWidget);
          expect(find.text('退出登录'), findsNothing);
        } else {
          expect(find.text('置顶帖'), findsOneWidget);
          expect(find.text('测试作者'), findsWidgets);
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('docs/preview-$screen-${mode.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => '',
    );
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: mode == ThemeMode.dark
                ? AppTheme.darkTheme()
                : AppTheme.lightTheme(),
            home: NativeForumPage(
              title: '回复',
              uri: forumUri('forum.php?mod=post&action=reply&tid=123'),
              client: fixture.NativeClient(),
              preferences: preferences,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('docs/preview-reply-${mode.name}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    for (final screen in ['sign', 'messages', 'quote']) {
      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: mode == ThemeMode.dark
                  ? AppTheme.darkTheme()
                  : AppTheme.lightTheme(),
              home: NativeForumPage(
                title: screen == 'sign'
                    ? '签到'
                    : screen == 'messages'
                    ? '消息'
                    : '回复',
                uri: forumUri(
                  screen == 'sign'
                      ? 'k_misign-sign.html'
                      : screen == 'messages'
                      ? 'home.php?mod=space&do=pm'
                      : 'forum.php?mod=post&action=reply&tid=123&repquote=123',
                ),
                client: screen == 'sign'
                    ? fixture.SignClient()
                    : screen == 'messages'
                    ? fixture.MessagesClient()
                    : fixture.NativeClient(),
                preferences: preferences,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('docs/preview-$screen-${mode.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    for (final screen in ['thread', 'composer']) {
      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ForumClient.platform,
          (_) async => 'forum_auth=fixture',
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: mode == ThemeMode.dark
                  ? AppTheme.darkTheme()
                  : AppTheme.lightTheme(),
              home: ForumPage(
                link: const ForumLink(
                  '示例帖子',
                  'https://bbs.binmt.cc/thread-123-1-1.html',
                ),
                client: thread_fixture.ThreadClient(),
                preferences: preferences,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (screen == 'composer') {
          await tester.tap(find.text('说点什么吧…'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextFormField),
            '在帖子底部直接回复，保留阅读上下文。',
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('docs/preview-$screen-${mode.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => '',
    );
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: mode == ThemeMode.dark
                ? AppTheme.darkTheme()
                : AppTheme.lightTheme(),
            home: ForumAccountPage(client: fixture.NativeClient()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('UID: 123'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('docs/preview-account-${mode.name}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => 'forum_auth=fixture',
    );
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      preferences.mode = mode;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MtForumApp(
            key: ValueKey(mode),
            preferences: preferences,
            client: MessagesPreviewClient(),
            useBrowserReader: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('消息').last);
      await tester.pumpAndSettle();
      expect(find.text('系统提醒'), findsOneWidget);
      expect(find.text('首页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('docs/preview-messages-tab-${mode.name}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.view.physicalSize = const Size(360, 800);
    preferences.mode = ThemeMode.dark;
    preferences.textScale = 1.4;
    final scaledBoundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: scaledBoundary,
        child: MtForumApp(
          key: const ValueKey('scaled-messages'),
          preferences: preferences,
          client: MessagesPreviewClient(),
          useBrowserReader: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (scaledBoundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('docs/preview-messages-scaled-dark.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
