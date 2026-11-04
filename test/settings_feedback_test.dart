import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/core/theme/app_theme.dart';
import 'package:mt_forum/core/utils/account_status.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/main.dart';
import 'package:mt_forum/pages/app_settings_page.dart';
import 'package:mt_forum/pages/login_page.dart';
import 'package:mt_forum/pages/settings_page.dart';
import 'package:mt_forum/pages/webdav_backup_page.dart';
import 'package:mt_forum/pages/web_page.dart';

import 'widget_test.dart' as fixture;

class EmptyProfileClient extends ForumClient {
  @override
  Future<String> source(String url) async => '<div id="ct">无法读取资料</div>';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, null),
  );

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) =>
      tester.runAsync(() async {
        Directory('docs').createSync(recursive: true);
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('docs/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });

  testWidgets('分组标题与图标起始线对齐，明暗及大字体布局一致', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fontFile = File('C:/Windows/Fonts/msyh.ttc');
    if (fontFile.existsSync()) {
      for (final family in ['Roboto', 'Ahem', 'PreviewCjk']) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
          );
        await tester.runAsync(loader.load);
      }
    }
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'D:/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await tester.runAsync(iconLoader.load);
    for (final (dark, scale, label) in [
      (false, 1.0, 'light'),
      (true, 1.0, 'dark'),
      (true, 2.0, 'large'),
    ]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      final key = GlobalKey();
      final baseTheme = dark ? AppTheme.darkTheme() : AppTheme.lightTheme();
      final previewTheme = baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: 'PreviewCjk'),
        listTileTheme: baseTheme.listTileTheme.copyWith(
          titleTextStyle: baseTheme.listTileTheme.titleTextStyle?.copyWith(
            fontFamily: 'PreviewCjk',
          ),
          subtitleTextStyle: baseTheme.listTileTheme.subtitleTextStyle
              ?.copyWith(fontFamily: 'PreviewCjk'),
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: previewTheme,
            home: SettingsPage(
              preferences: Preferences(await SharedPreferences.getInstance()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in ['外观', '字体', '底部导航', '显示效果', '主题颜色']) {
        await tester.scrollUntilVisible(
          find.text(title),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.getTopLeft(find.text(title)).dx, 32);
      }
      await tester.scrollUntilVisible(
        find.text('使用悬浮底栏'),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getTopLeft(find.byIcon(Icons.dock_rounded)).dx, 32);
      await tester.scrollUntilVisible(
        find.text('主题颜色'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getTopLeft(find.byType(ChoiceChip).first).dx, 32);
      await capture(tester, key, 'preview-settings-content-$label');
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await capture(tester, key, 'preview-settings-top-$label');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('WebDAV二级页标题已按内容内边距对齐', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: WebDavBackupPage(
          preferences: Preferences(await SharedPreferences.getInstance()),
          client: ForumClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('WebDAV 服务器配置'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final titleX = tester.getTopLeft(find.text('WebDAV 服务器配置')).dx;
    expect(titleX, 32);
    expect(tester.getTopLeft(find.byType(TextFormField).first).dx, titleX);
    expect(tester.takeException(), isNull);
  });

  for (final loggingIn in [true, false]) {
    testWidgets('${loggingIn ? '登录' : '退出'}成功提示等待返回完成，固定在底部出现和消失', (
      tester,
    ) async {
      var cookie = loggingIn ? '' : 'forum_auth=fixture';
      forumAuthenticated.value = !loggingIn;
      final settings = Preferences(await SharedPreferences.getInstance());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ForumClient.platform,
        (call) async {
          if (call.method == 'clearForumSession') cookie = '';
          return call.method == 'cookies' ? cookie : null;
        },
      );
      final client = EmptyProfileClient()
        ..browserLogin =
            ({
              required String loginField,
              required String username,
              required String password,
              required int questionId,
              required String answer,
              required bool remember,
            }) async {
              cookie = 'forum_auth=fixture';
              return '登录成功';
            };
      final messenger = GlobalKey<ScaffoldMessengerState>();
      final message = loggingIn ? '登录成功' : '已退出登录';
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messenger,
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            appBar: AppBar(title: const Text('目标页面')),
            bottomNavigationBar: const SizedBox(height: 72),
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  if (loggingIn) {
                    await showForumLogin(context, client);
                  } else {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AppSettingsPage(
                          client: client,
                          preferences: settings,
                        ),
                      ),
                    );
                  }
                },
                child: const Text('打开账号'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开账号'));
      await tester.pumpAndSettle();
      if (loggingIn) {
        await tester.enterText(find.byType(TextFormField).at(0), 'fixture');
        await tester.enterText(find.byType(TextFormField).at(1), 'synthetic');
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, '登录'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.widgetWithText(FilledButton, '登录'));
      } else {
        await tester.scrollUntilVisible(
          find.text('退出登录'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('退出登录'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      if (loggingIn) expect(find.text(message), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(ForumLoginPage), findsNothing);
      expect(
        find.byType(AppSettingsPage),
        loggingIn ? findsNothing : findsOneWidget,
      );
      expect(find.text(message), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
        SnackBarBehavior.floating,
      );
      final settledY = tester.getCenter(find.text(message)).dy;
      expect(
        settledY,
        greaterThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio - 180,
        ),
      );
      messenger.currentState!.hideCurrentSnackBar();
      for (final milliseconds in [30, 60, 90]) {
        await tester.pump(Duration(milliseconds: milliseconds));
        expect(tester.getCenter(find.text(message)).dy, closeTo(settledY, 0.1));
      }
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('成功提示进场位置固定，普通消息仍保留默认动画', (tester) async {
    final messenger = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messenger,
        theme: AppTheme.lightTheme(),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    showAccountStatus(messenger.currentState!, '登录成功');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final firstY = tester.getCenter(find.text('登录成功')).dy;
    for (final milliseconds in [60, 90]) {
      await tester.pump(Duration(milliseconds: milliseconds));
      expect(tester.getCenter(find.text('登录成功')).dy, closeTo(firstY, 0.1));
    }
    await tester.pumpAndSettle();
    messenger.currentState!.removeCurrentSnackBar();
    await tester.pumpAndSettle();
    messenger.currentState!.showSnackBar(const SnackBar(content: Text('普通消息')));
    await tester.pump();
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).animation!.value, 0);
    await tester.pump(const Duration(milliseconds: 50));
    final value = tester
        .widget<SnackBar>(find.byType(SnackBar))
        .animation!
        .value;
    expect(value, greaterThan(0));
    expect(value, lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('所有底栏仅占实际高度，成功提示位于底部且不推动胶囊', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ForumClient.platform,
      (_) async => '',
    );
    for (final mode in ['standard', 'floating', 'glass']) {
      final preferences = Preferences(await SharedPreferences.getInstance())
        ..floatingNavigation = mode != 'standard'
        ..liquidGlass = mode == 'glass';
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MtForumApp(
          preferences: preferences,
          client: fixture.FakeClient(),
          useBrowserReader: false,
        ),
      );
      await tester.pumpAndSettle();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      final bar = find.byWidget(scaffold.bottomNavigationBar!);
      final before = tester.getRect(bar);
      expect(before.height, lessThan(120));
      expect(before.height, greaterThanOrEqualTo(56));
      final context = tester.element(find.byType(Scaffold).first);
      showAccountStatus(ScaffoldMessenger.of(context), '登录成功');
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('登录成功')).dy, greaterThan(644));
      expect(tester.getRect(bar), before);
      expect(tester.takeException(), isNull);
    }
  });
}
