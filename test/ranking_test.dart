import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/data/native_forum.dart';
import 'package:mt_forum/data/preferences.dart';
import 'package:mt_forum/pages/native_forum_page.dart';
import 'package:mt_forum/core/design_system/components/review_frosted_app_bar.dart';

String fixture(String type) =>
    File('test/fixtures/rank-$type.html').readAsStringSync();

class RankingClient extends ForumClient {
  final requests = <String>[];
  @override
  Future<String> source(String url) async {
    requests.add(url);
    return fixture(Uri.parse(url).queryParameters['type'] ?? 'overview');
  }
}

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
  for (final type in ['overview', 'thread', 'member', 'forum']) {
    test('官网排行榜 $type 提取显式/图片名次、唯一内容和同源导航', () {
      final data = ForumRanking(
        html.parse(fixture(type)),
        forumUri(
          'misc.php?mod=ranklist${type == 'overview' ? '' : '&type=$type'}',
        ),
      );
      expect(data.entries.length, greaterThanOrEqualTo(10));
      expect(data.entries.take(4).map((entry) => entry.$1), [1, 2, 3, 4]);
      expect(
        data.entries.map((entry) => entry.$2.url).toSet().length,
        data.entries.length,
      );
      expect(data.categories.length, 4);
      expect(
        data.categories.where((tab) => tab.selected).single.label,
        {'overview': '全部', 'thread': '帖子', 'member': '用户', 'forum': '版块'}[type],
      );
      expect(
        data.entries.first.$2.title,
        {
          'overview': '汽水音乐 【免ROOT】',
          'thread': '汽水音乐 【免ROOT】',
          'member': '喵喵猫',
          'forum': '休闲灌水',
        }[type],
      );
      if (type == 'thread') {
        expect(data.entries.first.$2.author, 'colalan');
        expect(data.entries.first.$2.subtitle, contains('回复 677'));
        expect(data.periods.length, 4);
      }
      if (type == 'overview') expect(data.more?.url, contains('type=thread'));
      if (type == 'member') {
        expect(data.entries.first.$2.imageUrl, contains('avatar_small'));
      }
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets('排行榜卡片有排名无重复链接，更多原位切换，360dp字号=$scale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = RankingClient();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: NativeForumPage(
            title: '排行榜',
            uri: forumUri('misc.php?mod=ranklist'),
            client: client,
            preferences: Preferences(await SharedPreferences.getInstance()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HtmlWidget), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('colalan'), findsOneWidget);
      expect(find.text('汽水音乐 【免ROOT】'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('完整帖子排行'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完整帖子排行'));
      await tester.pumpAndSettle();
      expect(find.byType(NativeForumPage), findsOneWidget);
      expect(client.requests.length, 2);
      expect(
        tester.state<NativeForumPageState>(find.byType(NativeForumPage)).error,
        isNull,
      );
      expect(
        tester
            .state<NativeForumPageState>(find.byType(NativeForumPage))
            .scroll
            .offset,
        0,
      );
      expect(
        Navigator.of(tester.element(find.byType(NativeForumPage))).canPop(),
        isFalse,
      );
      expect(find.text('本月'), findsOneWidget);
      expect(find.textContaining('回复 677'), findsOneWidget);
      expect(find.byType(HtmlWidget), findsNothing);
      expect(
        tester
            .widget<ReviewFrostedAppBar>(find.byType(ReviewFrostedAppBar))
            .bottom!
            .preferredSize
            .height,
        (14 * scale + 28).clamp(48, double.infinity) * 2,
      );
      expect(client.requests.length, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
