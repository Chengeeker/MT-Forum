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
import 'package:mt_forum/main.dart';
import 'package:mt_forum/pages/about_dialog.dart';
import 'package:mt_forum/pages/settings_page.dart';

import 'widget_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, (_) async => '');
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, null),
  );

  Widget host({
    ThemeData? theme,
    GlobalKey? boundary,
    bool reducedMotion = false,
  }) => RepaintBoundary(
    key: boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.lightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showForumAboutDialog(context),
            child: const Text('打开关于'),
          ),
        ),
      ),
    ),
  );

  testWidgets('我的设置提供关于应用，版本与图标完整，原地60ms淡入', (tester) async {
    await tester.pumpWidget(
      MtForumApp(
        preferences: Preferences(await SharedPreferences.getInstance()),
        client: fixture.FakeClient(),
        useBrowserReader: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('关于应用'),
      160,
      scrollable: scrollable,
    );
    expect(find.text('关于应用'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('关于与支持')).dx,
      tester.getTopLeft(find.byIcon(Icons.info_outline_rounded)).dx,
    );
    await tester.tap(find.text('关于应用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 15));
    final dialog = find.byType(AlertDialog);
    final route = ModalRoute.of(tester.element(dialog))!;
    expect(route.transitionDuration, const Duration(milliseconds: 60));
    final rect = tester.getRect(dialog);
    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.getRect(dialog), rect);
    expect(
      find.ancestor(of: dialog, matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    expect(
      find.ancestor(of: dialog, matching: find.byType(SlideTransition)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    final version = RegExp(
      r'^version: ([^+]+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
    expect(find.text('v$version'), findsOneWidget);
    expect(find.text('GitHub 开源地址'), findsOneWidget);
    expect(find.text('github.com/Chengeeker/MT-Forum'), findsOneWidget);
    final image = tester.widget<Image>(
      find.descendant(of: dialog, matching: find.byType(Image)),
    );
    expect(
      tester.getSize(find.descendant(of: dialog, matching: find.byType(Image))),
      const Size(72, 72),
    );
    final provider = image.image as ResizeImage;
    expect(
      (provider.imageProvider as AssetImage).assetName,
      'assets/app-icon.png',
    );
    expect(provider.width, lessThanOrEqualTo(288));
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('关于应用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开源许可入口保留组件授权说明，可返回关于弹窗', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('打开关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.textContaining('Review 组件（MIT'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我知道了'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('个性化中移除旧版重复关于入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          preferences: Preferences(await SharedPreferences.getInstance()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -2400));
    await tester.pumpAndSettle();
    expect(find.text('关于 MT论坛'), findsNothing);
    expect(find.text('WebDAV备份'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动态效果时弹窗无动画，点击遮罩可关闭', (tester) async {
    await tester.pumpWidget(host(reducedMotion: true));
    await tester.tap(find.text('打开关于'));
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(tester.element(find.byType(AlertDialog)))!
          .transitionDuration,
      Duration.zero,
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关于弹窗明暗纯黑及窄屏大字体预览，内容可滚动且操作可达', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fontFile = File('C:/Windows/Fonts/msyh.ttc');
    if (fontFile.existsSync()) {
      final font = FontLoader('AboutPreview')
        ..addFont(
          Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
        );
      await tester.runAsync(font.load);
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
    for (final (name, dark, black, scale) in [
      ('light', false, false, 1.0),
      ('dark', true, false, 1.0),
      ('pureblack', true, true, 1.0),
      ('large', true, false, 2.0),
    ]) {
      tester.view.physicalSize = scale == 2
          ? const Size(320, 640)
          : const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      final base = dark
          ? AppTheme.darkTheme(isPureBlack: black)
          : AppTheme.lightTheme();
      final theme = base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: 'AboutPreview'),
        dialogTheme: base.dialogTheme.copyWith(
          contentTextStyle: base.dialogTheme.contentTextStyle?.copyWith(
            fontFamily: 'AboutPreview',
          ),
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(host(theme: theme, boundary: key));
      await tester.tap(find.text('打开关于'));
      await tester.pumpAndSettle();
      final imageFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Image),
      );
      await tester.runAsync(
        () => precacheImage(
          tester.widget<Image>(imageFinder).image,
          tester.element(imageFinder),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('GitHub 开源地址'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(find.text('我知道了')).dy,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );
      expect(find.byType(Divider), findsNothing);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('docs/preview-about-$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
    }
  });
}
