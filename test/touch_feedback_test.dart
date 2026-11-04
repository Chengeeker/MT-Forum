import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/theme/app_theme.dart';
import 'package:mt_forum/core/utils/haptic_feedback_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final themes = {
    'light': AppTheme.lightTheme(),
    'dark': AppTheme.darkTheme(),
    'pure black': AppTheme.darkTheme(isPureBlack: true),
  };

  for (final entry in themes.entries) {
    test('${entry.key} removes pressed ink and retains focus/hover states', () {
      final theme = entry.value;
      final overlays = [
        theme.filledButtonTheme.style!.overlayColor!,
        theme.elevatedButtonTheme.style!.overlayColor!,
        theme.outlinedButtonTheme.style!.overlayColor!,
        theme.textButtonTheme.style!.overlayColor!,
        theme.iconButtonTheme.style!.overlayColor!,
        theme.segmentedButtonTheme.style!.overlayColor!,
        theme.tabBarTheme.overlayColor!,
        theme.searchBarTheme.overlayColor!,
        theme.navigationBarTheme.overlayColor!,
        theme.checkboxTheme.overlayColor!,
        theme.radioTheme.overlayColor!,
        theme.switchTheme.overlayColor!,
      ];
      expect(theme.splashColor, Colors.transparent);
      expect(theme.highlightColor, Colors.transparent);
      for (final overlay in overlays) {
        expect(overlay.resolve({WidgetState.pressed}), Colors.transparent);
        expect(overlay.resolve({WidgetState.focused}), isNull);
        expect(overlay.resolve({WidgetState.hovered}), isNull);
      }
      expect(theme.focusColor.a, greaterThan(0));
      expect(theme.hoverColor.a, greaterThan(0));
      expect(theme.floatingActionButtonTheme.splashColor, Colors.transparent);
      final slider = theme.sliderTheme.overlayColor!;
      expect(
        WidgetStateProperty.resolveAs(slider, {WidgetState.dragged}),
        Colors.transparent,
      );
      expect(
        WidgetStateProperty.resolveAs<Color>(slider, {WidgetState.focused}).a,
        greaterThan(0),
      );
    });

    testWidgets(
      '${entry.key} tap and long press paint no ink and keep callbacks/haptics',
      (tester) async {
        var taps = 0;
        var holds = 0;
        final vibrations = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') vibrations.add(call);
            return null;
          },
        );
        HapticFeedbackUtil.isEnabled = true;
        HapticFeedbackUtil.resetForTesting();
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
          HapticFeedbackUtil.isEnabled = true;
          HapticFeedbackUtil.resetForTesting();
        });
        const boundaryKey = ValueKey('touch-feedback-pixels');
        const targets = [
          'ink',
          'filled',
          'icon',
          'text',
          'outlined',
          'elevated',
          'tab',
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value.copyWith(platform: TargetPlatform.android),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: Material(
                    child: SizedBox(
                      width: 300,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            key: const ValueKey('ink'),
                            onTap: () => taps++,
                            onLongPress: () => holds++,
                            child: const SizedBox(
                              width: 220,
                              height: 48,
                              child: Text('Row'),
                            ),
                          ),
                          FilledButton(
                            key: const ValueKey('filled'),
                            onPressed: () => taps++,
                            child: const Text('Filled'),
                          ),
                          IconButton(
                            key: const ValueKey('icon'),
                            onPressed: () => taps++,
                            icon: const Icon(Icons.add),
                          ),
                          TextButton(
                            key: const ValueKey('text'),
                            onPressed: () => taps++,
                            child: const Text('Text'),
                          ),
                          OutlinedButton(
                            key: const ValueKey('outlined'),
                            onPressed: () => taps++,
                            child: const Text('Outlined'),
                          ),
                          ElevatedButton(
                            key: const ValueKey('elevated'),
                            onPressed: () => taps++,
                            child: const Text('Elevated'),
                          ),
                          const DefaultTabController(
                            length: 2,
                            child: TabBar(
                              tabs: [
                                Tab(key: ValueKey('tab'), text: 'First'),
                                Tab(text: 'Second'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<Uint8List> pixels() async => (await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        }))!;

        for (final target in targets) {
          final before = await pixels();
          HapticFeedbackUtil.resetForTesting();
          vibrations.clear();
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(ValueKey(target))),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            listEquals(before, await pixels()),
            isTrue,
            reason: '$target tap must not paint ink',
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(
            listEquals(before, await pixels()),
            isTrue,
            reason: '$target hold must not paint ink',
          );
          expect(
            vibrations.where(
              (call) => call.arguments == 'HapticFeedbackType.lightImpact',
            ),
            hasLength(1),
          );
          await gesture.up();
          await tester.pumpAndSettle();
        }
        expect(taps, 5);
        expect(holds, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
