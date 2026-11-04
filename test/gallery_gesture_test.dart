import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum.dart';
import 'package:mt_forum/pages/media_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const urls = [
    'https://bbs.binmt.cc/data/forum/gesture-first.png',
    'https://bbs.binmt.cc/data/forum/gesture-second.png',
  ];

  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Future<void> openGallery(
    WidgetTester tester, {
    int count = 1,
    bool reduceMotion = false,
    Size imageSize = const Size(800, 600),
  }) async {
    // Use decoded images: loading placeholders do not install image gestures.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      imageSize.width.toInt(),
      imageSize.height.toInt(),
    );
    picture.dispose();
    for (final url in urls.take(count)) {
      PaintingBinding.instance.imageCache.putIfAbsent(
        ExtendedNetworkImageProvider(
          url,
          cache: true,
          headers: forumMediaHeaders(Uri.parse(url)),
        ),
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: image.clone())),
        ),
      );
    }
    image.dispose();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: ForumImageGalleryPage(
          images: urls.take(count).toList(),
          initialIndex: 0,
          heroTagPrefix: 'gesture-test',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExtendedImageGesture), findsWidgets);
  }

  ExtendedImageGestureState activeImage(WidgetTester tester) => tester
      .stateList<ExtendedImageGestureState>(find.byType(ExtendedImageGesture))
      .firstWhere(
        (state) => state.widget.extendedImageState.imageWidget.image
            .toString()
            .contains(urls[0]),
      );

  Future<void> doubleTap(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(position);
    await tester.pump();
  }

  testWidgets(
    'decoded image double tap zooms twice at the tap and restores fit',
    (tester) async {
      await openGallery(tester);
      final image = activeImage(tester);
      final position =
          tester.getCenter(find.byType(ExtendedImageGesture)) +
          const Offset(100, 40);
      await doubleTap(tester, position);
      await tester.pump(const Duration(milliseconds: 130));
      expect(image.gestureDetails!.totalScale, greaterThan(1));
      expect(image.gestureDetails!.totalScale, lessThan(2.5));
      await tester.pumpAndSettle();
      expect(image.gestureDetails!.totalScale, closeTo(2.5, 0.01));
      expect(image.gestureDetails!.offset!.distance, greaterThan(0));

      await doubleTap(tester, position);
      await tester.pump(const Duration(milliseconds: 130));
      expect(image.gestureDetails!.totalScale, greaterThan(2.5));
      expect(image.gestureDetails!.totalScale, lessThan(6));
      await tester.pumpAndSettle();
      expect(image.gestureDetails!.totalScale, closeTo(6, 0.01));

      await doubleTap(tester, position);
      await tester.pumpAndSettle();
      expect(image.gestureDetails!.totalScale, closeTo(1, 0.01));
      expect(image.gestureDetails!.offset!.distance, closeTo(0, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Review long image ratio uses 3.5x then 6x then fit', (
    tester,
  ) async {
    for (final height in [800, 801]) {
      await openGallery(tester, imageSize: Size(400, height.toDouble()));
      final image = activeImage(tester);
      final center = tester.getCenter(find.byType(ExtendedImageGesture));
      await doubleTap(tester, center);
      await tester.pumpAndSettle();
      expect(
        image.gestureDetails!.totalScale,
        closeTo(height > 800 ? 3.5 : 2.5, 0.01),
      );
      await doubleTap(tester, center);
      await tester.pumpAndSettle();
      expect(image.gestureDetails!.totalScale, closeTo(6, 0.01));
      await doubleTap(tester, center);
      await tester.pumpAndSettle();
      expect(image.gestureDetails!.totalScale, closeTo(1, 0.01));
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('second zoom keeps its center while crossing viewport bounds', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (viewport, imageSize) in [
      (const Size(390, 844), const Size(800, 600)),
      (const Size(844, 390), const Size(600, 800)),
    ]) {
      tester.view.physicalSize = viewport;
      await openGallery(tester, imageSize: imageSize);
      final image = activeImage(tester);
      final center = tester.getCenter(find.byType(ExtendedImageGesture));
      await doubleTap(tester, center);
      await tester.pumpAndSettle();
      expect(image.gestureDetails!.totalScale, closeTo(2.5, 0.01));
      await doubleTap(tester, center);
      for (var frame = 0; frame < 18; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          (image.gestureDetails!.destinationRect!.center - center).distance,
          closeTo(0, 0.01),
          reason: '$viewport zoom frame $frame must retain the focal center',
        );
      }
      expect(image.gestureDetails!.totalScale, closeTo(6, 0.01));
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('second zoom retains the tapped image point after panning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openGallery(tester, imageSize: const Size(800, 800));
    final image = activeImage(tester);
    final center = tester.getCenter(find.byType(ExtendedImageGesture));
    await doubleTap(tester, center);
    await tester.pumpAndSettle();
    await tester.dragFrom(center, const Offset(-60, 25));
    await tester.pumpAndSettle();
    final focalPoint = center + const Offset(20, -20);
    final before = image.gestureDetails!.destinationRect!;
    final fraction = Offset(
      (focalPoint.dx - before.left) / before.width,
      (focalPoint.dy - before.top) / before.height,
    );
    await doubleTap(tester, focalPoint);
    for (var frame = 0; frame < 18; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final rect = image.gestureDetails!.destinationRect!;
      final imagePoint =
          rect.topLeft +
          Offset(fraction.dx * rect.width, fraction.dy * rect.height);
      expect(
        (imagePoint - focalPoint).distance,
        closeTo(0, 0.01),
        reason: 'zoom frame $frame must keep the tapped image point fixed',
      );
    }
    expect(image.gestureDetails!.totalScale, closeTo(6, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('decoded gallery swipes between images at fitted scale', (
    tester,
  ) async {
    await openGallery(tester, count: 2);
    await tester.drag(
      find.byType(ExtendedImageGesturePageView),
      const Offset(-650, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.drag(
      find.byType(ExtendedImageGesturePageView),
      const Offset(650, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinch zoom and pan remain independent of gallery paging', (
    tester,
  ) async {
    await openGallery(tester, count: 2);
    final image = activeImage(tester);
    final center = tester.getCenter(find.byType(ExtendedImageGesturePageView));
    final left = await tester.startGesture(center - const Offset(60, 0));
    final right = await tester.startGesture(
      center + const Offset(60, 0),
      pointer: 2,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await left.moveTo(center - const Offset(160, 0));
    await right.moveTo(center + const Offset(160, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await left.moveTo(center - const Offset(200, 0));
    await right.moveTo(center + const Offset(200, 0));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(image.gestureDetails!.totalScale, greaterThan(1.5));
    final before = image.gestureDetails!.offset!;
    await tester.dragFrom(center, const Offset(90, 45));
    await tester.pumpAndSettle();
    expect((image.gestureDetails!.offset! - before).distance, greaterThan(20));
    expect(find.text('1 / 2'), findsOneWidget);

    await doubleTap(tester, center);
    await tester.pumpAndSettle();
    expect(image.gestureDetails!.totalScale, closeTo(6, 0.01));
    await doubleTap(tester, center);
    await tester.pumpAndSettle();
    expect(image.gestureDetails!.totalScale, closeTo(1, 0.01));
    await tester.dragFrom(center, const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new touch interrupts double tap animation without a jump', (
    tester,
  ) async {
    await openGallery(tester);
    final image = activeImage(tester);
    final center = tester.getCenter(find.byType(ExtendedImageGesture));
    await doubleTap(tester, center);
    await tester.pump(const Duration(milliseconds: 80));
    final scale = image.gestureDetails!.totalScale!;
    expect(scale, greaterThan(1));
    final touch = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(image.gestureDetails!.totalScale, closeTo(scale, 0.01));
    await touch.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap respects reduced motion and disposes mid-animation', (
    tester,
  ) async {
    await openGallery(tester, reduceMotion: true);
    final image = activeImage(tester);
    final center = tester.getCenter(find.byType(ExtendedImageGesture));
    await doubleTap(tester, center);
    expect(image.gestureDetails!.totalScale, closeTo(2.5, 0.01));
    await doubleTap(tester, center);
    expect(image.gestureDetails!.totalScale, closeTo(6, 0.01));
    await doubleTap(tester, center);
    expect(image.gestureDetails!.totalScale, closeTo(1, 0.01));

    await tester.pumpWidget(const SizedBox.shrink());
    await openGallery(tester);
    await doubleTap(tester, center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
