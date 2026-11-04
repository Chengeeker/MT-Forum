import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/theme/app_theme.dart';
import 'package:mt_forum/data/account_validation.dart';
import 'package:mt_forum/data/backup_service.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/image_cache_maintenance.dart';
import 'package:mt_forum/data/media_storage.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/pages/app_settings_page.dart';
import 'package:mt_forum/pages/settings_page.dart';
import 'package:mt_forum/pages/storage_settings_page.dart';
import 'package:mt_forum/pages/web_page.dart';
import 'package:mt_forum/pages/webdav_backup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profile = '<div id="ct"><h2>测试用户<span>(UID: 123)</span></h2></div>';
const login = '<form id="loginform_fixture"><input type="password"></form>';

class AccountClient extends ForumClient {
  String response = profile;
  bool fail = false;
  int requests = 0;
  Completer<String>? pending;
  @override
  Future<String> source(String url) async {
    requests++;
    if (fail) throw const ForumFailure('网络失败');
    return pending == null ? response : pending!.future;
  }
}

class VideoAdapter implements HttpClientAdapter {
  VideoAdapter({this.mime = 'video/mp4', this.length, this.stream});
  final String mime;
  final int? length;
  final Stream<Uint8List>? stream;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(
    stream ?? Stream.value(Uint8List.fromList([0, 1, 2, 3, 4])),
    200,
    headers: {
      Headers.contentTypeHeader: [mime],
      if (length != null) Headers.contentLengthHeader: ['$length'],
    },
  );
  @override
  void close({bool force = false}) {}
}

class RedirectAdapter extends VideoAdapter {
  RedirectAdapter(this.location, {this.repeat = false});
  final String location;
  final bool repeat;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(
      options.headers.keys.any((key) => key.toLowerCase() == 'cookie'),
      isFalse,
    );
    if (calls++ == 0 || repeat) {
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': [location],
        },
      );
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      for (final family in ['Roboto', 'Ahem', 'SettingsPreview']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
      }
    }
    final icons = File(
      'D:/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  });
  late Directory temporary;
  late String cookie;
  Map<String, dynamic>? saved;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('mt-settings-');
    cookie = 'forum_auth=fixture';
    saved = null;
    forumAuthenticated.value = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => temporary.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, (call) async {
          if (call.method == 'cookies') return cookie;
          if (call.method == 'clearForumSession') {
            cookie = '';
            return null;
          }
          if (call.method == 'saveMediaToGallery') {
            saved = Map<String, dynamic>.from(call.arguments as Map);
            final file = File(saved!['sourcePath'] as String);
            expect(await file.readAsBytes(), [0, 1, 2, 3, 4]);
            return 'Movies/MT论坛/media.mp4';
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, null);
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });
  Future<Preferences> prefs() async =>
      Preferences(await SharedPreferences.getInstance());

  test('credential checks require a server profile and distinguish unknown failures', () async {
    final client = AccountClient();
    expect((await validateForumAccount(client))!.uid, '123');
    client.response = login;
    expect(await validateForumAccount(client), isNull);
    expect(cookie, isNotEmpty);
    client.response = '<html>verification required</html>';
    await expectLater(
      validateForumAccount(client),
      throwsA(isA<ForumFailure>()),
    );
    client.fail = true;
    await expectLater(
      validateForumAccount(client),
      throwsA(isA<ForumFailure>()),
    );
    expect(cookie, isNotEmpty);
  });
  test('credential check discards results after account changes', () async {
    final client = AccountClient()..pending = Completer<String>();
    final result = validateForumAccount(client);
    await Future<void>.delayed(Duration.zero);
    sessionRevision.value++;
    cookie = 'forum_auth=other';
    client.pending!.complete(profile);
    await expectLater(result, throwsA(isA<ForumFailure>()));
  });
  test(
    'media path choices persist, sanitize names and validate own account',
    () async {
      final settings = await prefs();
      final client = AccountClient();
      expect(
        await MediaStorage.album(
          preferences: settings,
          client: client,
          video: false,
        ),
        'MT论坛',
      );
      expect(client.requests, 0);
      settings.imageSavePathType = 2;
      settings.videoSavePathType = 1;
      settings.imageCacheThresholdMb = 500;
      await settings.save();
      final restored = Preferences(settings.store);
      expect(restored.imageSavePathType, 2);
      expect(restored.videoSavePathType, 1);
      expect(restored.imageCacheThresholdMb, 500);
      expect(
        await MediaStorage.album(
          preferences: restored,
          client: client,
          video: true,
        ),
        'MT论坛/测试用户',
      );
      final folder = await MediaStorage.album(
        preferences: restored,
        client: client,
        video: false,
        author: '../作者/非法\\名字',
      );
      expect(folder.split('/'), hasLength(2));
      expect(folder, isNot(contains('..')));
      expect(
        MediaStorage.safeFolderName('😀' * 100).length,
        lessThanOrEqualTo(80),
      );
      client.response = login;
      await expectLater(
        MediaStorage.album(preferences: restored, client: client, video: true),
        throwsA(isA<ForumFailure>()),
      );
    },
  );
  test('cache clear only removes old direct MD5 files, preserving data and fresh writes', () async {
    final cache = Directory('${temporary.path}/cacheimage');
    await cache.create();
    final old = File('${cache.path}/${'a' * 32}');
    await old.writeAsBytes([1, 2, 3]);
    await old.setLastModified(
      DateTime.now().subtract(const Duration(minutes: 2)),
    );
    final fresh = File('${cache.path}/${'b' * 32}');
    await fresh.writeAsBytes([4, 5]);
    final account = File('${cache.path}/account.json');
    await account.writeAsString('preserve');
    final nested = Directory('${cache.path}/${'c' * 32}');
    await nested.create();
    await File('${nested.path}/history').writeAsString('preserve');
    expect(await ImageCacheMaintenance.scan(cache), 5);
    await ImageCacheMaintenance.checkAndAutoClear(0);
    expect(await old.exists(), isTrue);
    expect(await ImageCacheMaintenance.scan(cache, clear: true), 3);
    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await account.readAsString(), 'preserve');
    expect(await nested.exists(), isTrue);
  });
  test('video save streams a file to the native bridge then removes its temporary file', () async {
    final dio = Dio()..httpClientAdapter = VideoAdapter();
    await MediaStorage.saveVideo(
      Uri.parse('https://bbs.binmt.cc/video.mp4'),
      cancelToken: CancelToken(),
      dio: dio,
    );
    expect(saved!['mimeType'], 'video/mp4');
    expect(saved!['album'], 'MT论坛');
    expect(saved!.containsKey('bytes'), isFalse);
    expect(await File(saved!['sourcePath'] as String).exists(), isFalse);
  });
  test(
    'video rejects manifests, HTML, oversized files and cancelled requests',
    () async {
      for (final url in [
        'http://bbs.binmt.cc/v.mp4',
        'https://bbs.binmt.cc/v.m3u8',
        'https://u:p@bbs.binmt.cc/v.mp4',
      ]) {
        expect(MediaStorage.canSaveVideo(Uri.parse(url)), isFalse);
      }
      for (final adapter in [
        VideoAdapter(mime: 'text/html'),
        VideoAdapter(length: MediaStorage.maxVideoBytes + 1),
      ]) {
        final dio = Dio()..httpClientAdapter = adapter;
        await expectLater(
          MediaStorage.saveVideo(
            Uri.parse('https://bbs.binmt.cc/v.mp4'),
            cancelToken: CancelToken(),
            dio: dio,
          ),
          throwsA(isA<ForumFailure>()),
        );
      }
      final token = CancelToken()..cancel();
      await expectLater(
        MediaStorage.saveVideo(
          Uri.parse('https://bbs.binmt.cc/v.mp4'),
          cancelToken: token,
          dio: Dio()..httpClientAdapter = VideoAdapter(),
        ),
        throwsA(anything),
      );
      expect(saved, isNull);
    },
  );

  test(
    'video follows bounded HTTPS redirects without forwarding forum cookies',
    () async {
      final valid = RedirectAdapter('https://cdn.example.test/signed-video');
      await MediaStorage.saveVideo(
        Uri.parse('https://bbs.binmt.cc/video.mp4'),
        cancelToken: CancelToken(),
        dio: Dio()..httpClientAdapter = valid,
      );
      expect(valid.calls, 2);
      expect(saved, isNotNull);
      for (final target in [
        'http://cdn.example.test/video.mp4',
        'https://user:password@cdn.example.test/v.mp4',
      ]) {
        saved = null;
        final adapter = RedirectAdapter(target);
        await expectLater(
          MediaStorage.saveVideo(
            Uri.parse('https://bbs.binmt.cc/video.mp4'),
            cancelToken: CancelToken(),
            dio: Dio()..httpClientAdapter = adapter,
          ),
          throwsA(isA<ForumFailure>()),
        );
        expect(adapter.calls, 1);
        expect(saved, isNull);
      }
      final loop = RedirectAdapter(
        'https://cdn.example.test/loop',
        repeat: true,
      );
      await expectLater(
        MediaStorage.saveVideo(
          Uri.parse('https://bbs.binmt.cc/video.mp4'),
          cancelToken: CancelToken(),
          dio: Dio()..httpClientAdapter = loop,
        ),
        throwsA(isA<ForumFailure>()),
      );
      expect(loop.calls, 6);
    },
  );

  test('backup includes storage choices and rejects unsupported values before restoration', () async {
    final settings = await prefs();
    settings.imageSavePathType = 2;
    settings.videoSavePathType = 1;
    settings.imageCacheThresholdMb = 500;
    await settings.save();
    final service = ForumBackupService(settings, AccountClient());
    final backup = await service.exportAllData();
    settings.imageSavePathType = 0;
    await settings.save();
    await service.restoreAllData(backup);
    expect(settings.imageSavePathType, 2);
    expect(settings.videoSavePathType, 1);
    final values = Map<String, dynamic>.from(backup['preferences'] as Map);
    values['imageCacheThresholdMb'] = 17;
    expect(
      () => service.validateBackup({...backup, 'preferences': values}),
      throwsFormatException,
    );
    expect(cookie, 'forum_auth=fixture');
  });

  testWidgets(
    'settings, storage and cache layouts in light, dark and large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final (name, dark, scale, width) in [
        ('light', false, 1.0, 390.0),
        ('dark', true, 1.0, 390.0),
        ('large', true, 2.0, 360.0),
      ]) {
        tester.view.physicalSize = Size(width, 844);
        final boundary = GlobalKey();
        final base = dark
            ? AppTheme.darkTheme(colorIndex: 2)
            : AppTheme.lightTheme(colorIndex: 2);
        final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'SettingsPreview'),
          listTileTheme: base.listTileTheme.copyWith(
            titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
              fontFamily: 'SettingsPreview',
            ),
            subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
              fontFamily: 'SettingsPreview',
            ),
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: AppSettingsPage(
                preferences: await prefs(),
                client: AccountClient(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> capture(String page) async {
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            Directory('docs').createSync();
            File('docs/preview-$page-$name.png')
                .writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        final title = find.text('偏好与功能');
        expect(
          tester.getTopLeft(title).dx,
          tester.getTopLeft(find.byIcon(Icons.palette_outlined)).dx,
        );
        await capture('settings-hub');
        await tester.scrollUntilVisible(
          find.text('关于应用'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await capture('settings-hub-bottom');
        await tester.drag(find.byType(ListView), const Offset(0, 2500));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('存储设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('存储设置'));
        await tester.pumpAndSettle();
        await capture('storage-settings');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('缓存管理'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        await capture('cache-management');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  test(
    'cancelling an active video stream removes partial files without saving',
    () async {
      final token = CancelToken();
      var chunks = 0;
      Stream<Uint8List> parts() async* {
        chunks++;
        yield Uint8List.fromList([0, 1, 2]);
        token.cancel('fixture cancellation');
        yield Uint8List.fromList([3, 4]);
      }

      final dio = Dio()..httpClientAdapter = VideoAdapter(stream: parts());
      await expectLater(
        MediaStorage.saveVideo(
          Uri.parse('https://bbs.binmt.cc/video.mp4'),
          cancelToken: token,
          dio: dio,
        ),
        throwsA(anything),
      );
      expect(chunks, 1);
      expect(saved, isNull);
      final root = Directory('${temporary.path}/media-downloads');
      if (await root.exists()) expect(await root.list().toList(), isEmpty);
    },
  );

  testWidgets(
    'settings group navigation, account validation and logout remain native',
    (tester) async {
      final settings = await prefs();
      final client = AccountClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: AppSettingsPage(preferences: settings, client: client),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('个性化'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('存储设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频存储路径'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按帖子作者昵称归类'));
      await tester.pumpAndSettle();
      expect(settings.videoSavePathType, 2);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('缓存管理'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CacheManagementPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('WebDAV备份'));
      await tester.pumpAndSettle();
      expect(find.byType(WebDavBackupPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('检测账号凭据有效性'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检测账号凭据有效性'));
      await tester.pumpAndSettle();
      expect(find.text('账号凭据有效'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('退出登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsPage), findsOneWidget);
      expect(find.text('登录账号'), findsOneWidget);
      expect(cookie, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
