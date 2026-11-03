import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/core/theme/app_theme.dart';
import 'package:mt_forum/data/backup_service.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/data/webdav_service.dart';
import 'package:mt_forum/pages/webdav_backup_page.dart';

class BackupClient extends ForumClient {
  VoidCallback? onProfile;
  @override
  Future<String> source(String url) async {
    onProfile?.call();
    return '<div id="uhd"><h2>备份用户</h2></div><div id="ct"><h2>备份用户 (UID: 123)</h2></div>';
  }
}

class DavAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final uploaded = <String>[];
  int mkdirStatus = 201, putStatus = 204, getStatus = 200;
  String body = '{}';
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      uploaded.add(utf8.decode(await requestStream.expand((e) => e).toList()));
    }
    return ResponseBody.fromString(body, switch (options.method) {
      'PROPFIND' => 207,
      'MKCOL' => mkdirStatus,
      'PUT' => putStatus,
      _ => getStatus,
    });
  }

  @override
  void close({bool force = false}) {}
}

class PageDav extends WebDavService {
  Map<String, dynamic>? uploaded, restore;
  int downloads = 0;
  Completer<bool>? pending;
  @override
  Future<bool> uploadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String directoryName,
    required Map<String, dynamic> data,
  }) async {
    uploaded = data;
    return pending?.future ?? true;
  }

  @override
  Future<Map<String, dynamic>?> downloadLatestBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String directoryName,
  }) async {
    downloads++;
    return restore;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Preferences prefs;
  late BackupClient client;
  late ForumBackupService backup;
  late String cookies;
  final calls = <MethodCall>[];
  bool rejectNextCookie = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'color': 2,
      'textScale': 1.1,
      'autoSignIn': true,
      'webdav_url': 'https://dav.example/dav/',
      'webdav_username': 'test-user',
      'webdav_directory': defaultWebDavDirectory,
      'webdav_password': 'dav-secret',
      'history': jsonEncode([
        const ForumLink(
          '已读帖子',
          'https://bbs.binmt.cc/thread-123-1-1.html',
        ).toJson(),
      ]),
      'unrelated_secret': 'excluded',
    });
    prefs = Preferences(await SharedPreferences.getInstance());
    client = BackupClient();
    backup = ForumBackupService(prefs, client);
    cookies = 'forum_auth=old-auth; forum_sid=old-sid';
    calls.clear();
    rejectNextCookie = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, (call) async {
          calls.add(call);
          if (call.method == 'cookies') return cookies;
          if (call.method == 'clearForumSession') cookies = '';
          if (call.method == 'setCookie') {
            if (rejectNextCookie) {
              rejectNextCookie = false;
              throw PlatformException(code: 'RESTORE_FAILED');
            }
            final pair = (call.arguments['cookie'] as String).split(';').first;
            cookies = cookies.isEmpty ? pair : '$cookies; $pair';
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ForumClient.platform, null),
  );

  test('安全备份仅导出白名单，既不读取也不恢复会话和 WebDAV 密码', () async {
    final data = await backup.exportAllData();
    final values = data['preferences'] as Map<String, dynamic>;
    expect(data['backup_mode'], 'safe');
    expect(data.containsKey('forum_session'), isFalse);
    expect(values.containsKey('webdav_password'), isFalse);
    expect(values.containsKey('unrelated_secret'), isFalse);
    values['webdav_password'] = 'injected';
    values['unrelated_secret'] = 'injected';
    values['color'] = 4;
    values['textScale'] = 1;
    data['forum_session'] = {'cookies': 'injected'};
    await backup.restoreAllData(data);
    expect(prefs.color, 4);
    expect(prefs.textScale, 1.0);
    expect(prefs.history.single.title, '已读帖子');
    expect(prefs.store.getString('webdav_password'), 'dav-secret');
    expect(calls, isEmpty);
  });
  test('全量备份恢复整组论坛会话，不保留其他账号旧 Cookie', () async {
    final data = await backup.exportAllData(includeCredentials: true);
    expect((data['forum_session'] as Map)['uid'], '123');
    expect((data['preferences'] as Map)['webdav_password'], 'dav-secret');
    cookies = 'another_auth=other-account; unrelated=stale';
    await prefs.store.setString('webdav_password', 'changed');
    await backup.restoreAllData(data);
    expect(cookies, 'forum_auth=old-auth; forum_sid=old-sid');
    expect(prefs.store.getString('webdav_password'), 'dav-secret');
    expect(calls.any((call) => call.method == 'flushForumCookies'), isTrue);
    final clear = calls.indexWhere(
      (call) => call.method == 'clearForumSession',
    );
    final write = calls.indexWhere((call) => call.method == 'setCookie');
    expect(write, greaterThan(clear));
  });
  test('安全恢复更换 DAV 地址或账号时清除旧密码，不向新服务器沿用凭据', () async {
    final data = await backup.exportAllData();
    (data['preferences'] as Map)['webdav_url'] = 'https://other.example/dav/';
    await backup.restoreAllData(data);
    expect(prefs.store.getString('webdav_url'), 'https://other.example/dav/');
    expect(prefs.store.getString('webdav_password'), isNull);
    expect(cookies, 'forum_auth=old-auth; forum_sid=old-sid');
    expect(calls, isEmpty);
  });
  test('全量未登录备份会清除当前会话，导出时换号则中止', () async {
    cookies = '';
    final signedOut = await backup.exportAllData(includeCredentials: true);
    expect(signedOut['forum_session'], isNull);
    cookies = 'forum_auth=logged-in';
    await backup.restoreAllData(signedOut);
    expect(cookies, isEmpty);
    cookies = 'forum_auth=first';
    client.onProfile = () => cookies = 'forum_auth=second';
    await expectLater(
      backup.exportAllData(includeCredentials: true),
      throwsA(isA<ForumFailure>()),
    );
  });
  test('无效/其他应用备份、恶意历史和 Cookie 在任何写入前拒绝', () async {
    final data = await backup.exportAllData();
    for (final invalid in [
      {...data, 'app': 'Review'},
      {
        ...data,
        'preferences': {'color': 'bad'},
      },
      {
        ...data,
        'preferences': {'themeMode': 10},
      },
      {
        ...data,
        'preferences': {
          'history': '[{"title":"bad","url":"https://example.com/"}]',
        },
      },
      {
        ...data,
        'backup_mode': 'full',
        'forum_session': {
          'uid': '123',
          'cookies': 'forum_auth=evil\r\nInjected: yes',
        },
      },
    ]) {
      await expectLater(backup.restoreAllData(invalid), throwsFormatException);
    }
    expect(calls, isEmpty);
    expect(prefs.color, 2);
  });
  test('原生会话写入失败回滚原会话与设置', () async {
    final data = await backup.exportAllData(includeCredentials: true);
    (data['forum_session'] as Map)['cookies'] = 'forum_auth=new-auth';
    (data['preferences'] as Map)['color'] = 4;
    rejectNextCookie = true;
    await expectLater(
      backup.restoreAllData(data),
      throwsA(isA<PlatformException>()),
    );
    expect(cookies, 'forum_auth=old-auth; forum_sid=old-sid');
    expect(prefs.color, 2);
  });
  test('WebDAV 只允许 HTTPS 或精确本机地址，禁止 URL 凭据和目录穿越', () {
    expect(
      WebDavService.serverUri('dav.example/dav').toString(),
      'https://dav.example/dav/',
    );
    expect(WebDavService.serverUri('http://localhost:8080/').host, 'localhost');
    for (final url in [
      'http://dav.example/',
      'http://localhost.evil.test/',
      'https://user:password@example.com/',
      'https://example.com/?token=secret',
    ]) {
      expect(() => WebDavService.serverUri(url), throwsFormatException);
    }
    for (final path in ['..', '.', '../other', 'one\\two']) {
      expect(() => WebDavService.directory(path), throwsFormatException);
    }
  });
  test('WebDAV 连接、建目录、最新和历史备份使用隔离的请求与文件名', () async {
    final adapter = DavAdapter();
    final service = WebDavService(dio: Dio()..httpClientAdapter = adapter);
    expect(
      await service.testConnection(
        serverUrl: 'https://dav.example/dav/',
        username: 'u',
        password: 'p',
      ),
      isTrue,
    );
    expect(adapter.requests.single.headers['Depth'], '0');
    expect(adapter.requests.single.headers['Authorization'], 'Basic dTpw');
    expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
    expect(adapter.requests.single.followRedirects, isFalse);
    expect(
      await service.uploadBackup(
        serverUrl: 'https://dav.example/dav/',
        username: 'u',
        password: 'p',
        directoryName: '',
        data: {'app': 'bbs.binmt.cc'},
      ),
      isTrue,
    );
    expect(adapter.requests.map((e) => e.method), [
      'PROPFIND',
      'MKCOL',
      'PUT',
      'PUT',
    ]);
    expect(adapter.requests[2].uri.pathSegments, [
      'dav',
      defaultWebDavDirectory,
      'backup_mt_forum_latest.json',
    ]);
    expect(jsonDecode(adapter.uploaded.first)['app'], 'bbs.binmt.cc');
    expect(adapter.uploaded[0], adapter.uploaded[1]);
    adapter.mkdirStatus = 403;
    final count = adapter.requests.length;
    expect(
      await service.uploadBackup(
        serverUrl: 'https://dav.example/dav/',
        username: 'u',
        password: 'p',
        directoryName: 'Custom',
        data: {},
      ),
      isFalse,
    );
    expect(adapter.requests.length, count + 1);
  });
  test('下载拒绝重定向、损坏或过大的云端内容', () async {
    final adapter = DavAdapter()..body = '{"app":"bbs.binmt.cc"}';
    final service = WebDavService(dio: Dio()..httpClientAdapter = adapter);
    Future<Map<String, dynamic>?> read() => service.downloadLatestBackup(
      serverUrl: 'https://dav.example/',
      username: 'u',
      password: 'p',
      directoryName: 'Custom',
    );
    expect((await read())!['app'], 'bbs.binmt.cc');
    expect(
      adapter.requests.last.uri.path,
      '/Custom/backup_mt_forum_latest.json',
    );
    adapter.getStatus = 302;
    expect(await read(), isNull);
    adapter.getStatus = 200;
    adapter.body = 'not json';
    expect(await read(), isNull);
    adapter.body = 'x' * (maxBackupBytes + 1);
    expect(await read(), isNull);
  });
  Future<void> showPage(
    WidgetTester tester,
    PageDav service, {
    ThemeData? theme,
    GlobalKey? boundary,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RepaintBoundary(
          key: boundary,
          child: WebDavBackupPage(
            preferences: prefs,
            client: client,
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reach(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
  }

  testWidgets('Review 同款页面默认安全备份，显式切换后才上传凭据', (tester) async {
    final service = PageDav();
    await showPage(tester, service);
    expect(find.text('全量安全备份'), findsOneWidget);
    await reach(tester, find.text('立即备份到云端'));
    await tester.tap(find.text('立即备份到云端'));
    await tester.pumpAndSettle();
    expect(service.uploaded!['backup_mode'], 'safe');
    expect(calls, isEmpty);
    await tester.drag(find.byType(ListView), const Offset(0, 1500));
    await tester.pumpAndSettle();
    await reach(tester, find.text('全量备份'));
    await tester.tap(find.text('全量备份'));
    await tester.pumpAndSettle();
    await reach(tester, find.text('立即备份到云端'));
    await tester.tap(find.text('立即备份到云端'));
    await tester.pumpAndSettle();
    expect(service.uploaded!['backup_mode'], 'full');
  });
  testWidgets('恢复前需确认，安全恢复即时更新偏好且保留本机密码', (tester) async {
    final service = PageDav()
      ..restore = {
        'app': 'bbs.binmt.cc',
        'version': '1.0',
        'backup_mode': 'safe',
        'preferences': {'color': 4},
      };
    await showPage(tester, service);
    await reach(tester, find.text('从云端恢复备份'));
    await tester.tap(find.text('从云端恢复备份'));
    await tester.pumpAndSettle();
    expect(service.downloads, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.downloads, 0);
    await tester.tap(find.text('从云端恢复备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定恢复'));
    await tester.pumpAndSettle();
    expect(service.downloads, 1);
    expect(prefs.color, 4);
    expect(prefs.store.getString('webdav_password'), 'dav-secret');
  });
  testWidgets('备份处理中禁止重复请求和修改连接配置', (tester) async {
    final service = PageDav()..pending = Completer<bool>();
    await showPage(tester, service);
    await reach(tester, find.text('立即备份到云端'));
    await tester.tap(find.text('立即备份到云端'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '正在上传...'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<PopScope>(find.byType(PopScope).first).canPop,
      isFalse,
    );
    service.pending!.complete(true);
    await tester.pumpAndSettle();
  });
  testWidgets('WebDAV 明暗预览与大字体布局不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
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
    ThemeData previewTheme(bool dark) {
      final theme = dark
          ? AppTheme.darkTheme(colorIndex: 2)
          : AppTheme.lightTheme(colorIndex: 2);
      // List-tile styles without a family otherwise inherit Flutter test's Ahem.
      return theme.copyWith(
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
            fontFamily: 'Roboto',
          ),
          subtitleTextStyle: theme.listTileTheme.subtitleTextStyle?.copyWith(
            fontFamily: 'Roboto',
          ),
        ),
      );
    }

    for (final dark in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      final key = GlobalKey();
      await showPage(
        tester,
        PageDav(),
        boundary: key,
        theme: previewTheme(dark),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('docs').createSync(recursive: true);
        File('docs/preview-webdav-${dark ? 'dark' : 'light'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: previewTheme(false),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: WebDavBackupPage(
          preferences: prefs,
          client: client,
          service: PageDav(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reach(tester, find.text('从云端恢复备份'));
    expect(tester.takeException(), isNull);
  });
}
