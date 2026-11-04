import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mt_forum/core/design_system/components/review_liquid_navigation_bar.dart';
import 'package:mt_forum/core/theme/app_theme.dart';

const _tabs = [
  GlassTab(icon: Icon(Icons.home), label: '首页'),
  GlassTab(icon: Icon(Icons.search), label: '发现'),
  GlassTab(icon: Icon(Icons.add), label: '发帖'),
  GlassTab(icon: Icon(Icons.mail), label: '消息'),
  GlassTab(icon: Icon(Icons.person), label: '我的'),
];

Future<Rect> _mount(WidgetTester tester, List<int> selections) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final selected = ValueNotifier(0);
  addTearDown(selected.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      home: ValueListenableBuilder<int>(
        valueListenable: selected,
        builder: (context, index, _) => Scaffold(
          bottomNavigationBar: ReviewLiquidNavigationBar(
            selectedIndex: index,
            onSelected: (target) {
              selections.add(target);
              selected.value = target;
            },
            hasBottomInset: false,
            width: 358,
            tabs: _tabs,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getRect(find.byType(GlassTabBar));
}

Offset _slot(Rect bar, int index) =>
    Offset(bar.left + bar.width * (index + 0.5) / 5, bar.center.dy);

GlassTabBar _bar(WidgetTester tester) =>
    tester.widget<GlassTabBar>(find.byType(GlassTabBar));

void main() {
  testWidgets('Review短点按松手才切换，按下不先膨胀再平移', (tester) async {
    final selections = <int>[];
    final bar = await _mount(tester, selections);
    final gesture = await tester.startGesture(_slot(bar, 1));
    await tester.pump(const Duration(milliseconds: 80));
    expect(selections, isEmpty);
    expect(_bar(tester).selectedIndex, 0);
    expect(_bar(tester).indicatorExpansion, EdgeInsets.zero);
    expect(_bar(tester).indicatorPinchStrength, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selections, [1]);
    expect(_bar(tester).selectedIndex, 1);
    expect(_bar(tester).indicatorExpansion, EdgeInsets.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Review长按220ms才扩展水珠，松手收回且不触发同页动作', (tester) async {
    final selections = <int>[];
    final bar = await _mount(tester, selections);
    final gesture = await tester.startGesture(_slot(bar, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_bar(tester).indicatorExpansion, EdgeInsets.zero);
    await tester.pump(const Duration(milliseconds: 80));
    expect(selections, isEmpty);
    expect(
      _bar(tester).indicatorExpansion,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    expect(_bar(tester).indicatorPinchStrength, 0.7);
    expect(_bar(tester).pressScale, 1.06);
    expect(tester.getSize(find.byType(GlassTabBar)).height, 56);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(_bar(tester).indicatorExpansion, EdgeInsets.zero);
    expect(_bar(tester).indicatorPinchStrength, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Review慢拖按最终水珠位置选择，不在经过中间入口时提交', (tester) async {
    final selections = <int>[];
    final bar = await _mount(tester, selections);
    final gesture = await tester.startGesture(_slot(bar, 0));
    for (var index = 1; index < 5; index++) {
      await tester.pump(const Duration(milliseconds: 160));
      await gesture.moveTo(_slot(bar, index));
      await tester.pump();
      expect(selections, isEmpty);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(selections, [4]);
    expect(_bar(tester).selectedIndex, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Review快速抛动只提交相邻一项', (tester) async {
    final selections = <int>[];
    final bar = await _mount(tester, selections);
    await tester.flingFrom(_slot(bar, 0), Offset(bar.width * 0.8, 0), 2500);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(selections, [1]);
    expect(_bar(tester).selectedIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Review拖动取消不切页，销毁时清理长按计时器', (tester) async {
    final selections = <int>[];
    final bar = await _mount(tester, selections);
    final gesture = await tester.startGesture(_slot(bar, 0));
    await tester.pump(const Duration(milliseconds: 240));
    await gesture.moveTo(_slot(bar, 3));
    await tester.pump();
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(_bar(tester).selectedIndex, 0);
    final next = await tester.startGesture(_slot(bar, 1));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(const SizedBox.shrink());
    await next.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(selections, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
