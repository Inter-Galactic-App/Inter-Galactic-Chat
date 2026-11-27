import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/controls/emoticon_editor_controls.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';

import 'emoticon_test_fixtures.dart';

/// Widget-level guards for the canvas: no blank frames (U1), bounded preview
/// decodes (U3), the tappable empty state (U5), and gesture arbitration
/// between painting and zooming (U7).
void main() {
  const canvasSize = Size(300, 300);

  EmoticonEditorController buildController(RecordingCutoutBackend backend) {
    return EmoticonEditorController(
      cutoutService: ImageCutoutService(backend: backend),
      draftStore: FakeDraftStore(),
      creatingNew: true,
    );
  }

  Future<EmoticonEditorController> pumpCanvas(
    WidgetTester tester, {
    required RecordingCutoutBackend backend,
    bool withCutout = true,
    VoidCallback? onPickSourceImage,
  }) async {
    final controller = buildController(backend);
    addTearDown(controller.dispose);

    if (withCutout) {
      controller.setSourceImage(redSquareOnWhitePng());
      await controller.runAutoCutout();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => EmoticonCutoutCanvas(
                  controller: controller,
                  square: false,
                  onPickSourceImage: onPickSourceImage,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  Finder canvasImage() => find.descendant(
    of: find.byType(EmoticonCutoutCanvas),
    matching: find.byType(Image),
  );

  group('U1 — no blank frames', () {
    testWidgets('the canvas preview keeps the last frame', (tester) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      await pumpCanvas(tester, backend: backend);

      expect(tester.widget<Image>(canvasImage()).gaplessPlayback, isTrue);
    });

    testWidgets('the mini previews keep the last frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoticonMiniPreview(
              bytes: redSquareOnWhitePng(),
              size: 72,
              background: CutoutPreviewBackground.checkerboard,
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(EmoticonMiniPreview),
          matching: find.byType(Image),
        ),
      );
      expect(image.gaplessPlayback, isTrue);
    });

    testWidgets('the quick-card pick tile keeps the last frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 96,
              height: 96,
              child: EmoticonImagePickTile(
                image: MemoryImage(redSquareOnWhitePng()),
                tooltip: 'Change photo',
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(EmoticonImagePickTile),
          matching: find.byType(Image),
        ),
      );
      expect(image.gaplessPlayback, isTrue);
    });
  });

  group('U3 — bounded preview decode', () {
    testWidgets('the canvas decodes to the laid-out size, not the source', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(tester, backend: backend);

      final provider = tester.widget<Image>(canvasImage()).image;
      expect(provider, isA<ResizeImage>());
      // Bounded by the canvas in device pixels, never by the source
      // resolution, and hard-capped.
      final devicePixelRatio = tester.view.devicePixelRatio;
      expect(
        (provider as ResizeImage).width,
        (canvasSize.width * devicePixelRatio).ceil(),
      );
      expect(provider.width, lessThanOrEqualTo(4096));
      // Display only: the saved bytes are untouched.
      expect(controller.cutoutResult!.pngBytes, isNotEmpty);
      expect(controller.imageData, controller.cutoutResult!.pngBytes);
    });

    testWidgets('the decode width survives a re-cropping settle', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(tester, backend: backend);

      final before =
          (tester.widget<Image>(canvasImage()).image as ResizeImage).width;

      // A key that moved with the output geometry would force a fresh decode
      // of every settled frame — exactly the cost U3 exists to avoid.
      controller.cutoutResult = controller.cutoutResult!.copyWith(
        width: 40,
        height: 64,
      );
      controller.notifyShortcodeChanged();
      await tester.pump();

      expect(
        (tester.widget<Image>(canvasImage()).image as ResizeImage).width,
        before,
      );
    });
  });

  group('U5 — the empty canvas is the way out', () {
    testWidgets('an empty canvas with a callback is a labelled button', (
      tester,
    ) async {
      var picked = 0;
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      await pumpCanvas(
        tester,
        backend: backend,
        withCutout: false,
        onPickSourceImage: () => picked++,
      );

      final target = find.byKey(const ValueKey('emoticon-canvas-pick-photo'));
      expect(target, findsOneWidget);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));

      await tester.tap(target);
      await tester.pump();
      expect(picked, 1);
    });

    testWidgets('an empty canvas without a callback stays a plain icon', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      await pumpCanvas(tester, backend: backend, withCutout: false);

      expect(
        find.byKey(const ValueKey('emoticon-canvas-pick-photo')),
        findsNothing,
      );
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    });

    testWidgets('the empty state is gone once a source image exists', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      await pumpCanvas(tester, backend: backend, onPickSourceImage: () {});

      expect(
        find.byKey(const ValueKey('emoticon-canvas-pick-photo')),
        findsNothing,
      );
      expect(canvasImage(), findsOneWidget);
    });
  });

  group('U7 — a stroke never costs zoom, and zoom never costs a stroke', () {
    testWidgets('a single-pointer drag paints and leaves zoom alone', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(tester, backend: backend);
      final centre = tester.getCenter(find.byType(EmoticonCutoutCanvas));

      final gesture = await tester.startGesture(centre);
      for (var step = 0; step < 5; step++) {
        await gesture.moveBy(const Offset(6, 0));
        await tester.pump();
      }

      expect(controller.strokeActive, isTrue);
      expect(controller.strokeDabs, isNotEmpty);
      expect(backend.renderMasks, isEmpty);
      expect(controller.zoomScale, EmoticonEditorController.minZoomScale);
      expect(controller.zoomOffset, Offset.zero);

      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(controller.strokeActive, isFalse);
      expect(backend.renderMasks, hasLength(1));
    });

    testWidgets('a two-pointer gesture zooms and paints nothing', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(tester, backend: backend);
      final centre = tester.getCenter(find.byType(EmoticonCutoutCanvas));

      final first = await tester.startGesture(centre - const Offset(20, 0));
      final second = await tester.startGesture(centre + const Offset(20, 0));
      await tester.pump();
      for (var step = 0; step < 5; step++) {
        await first.moveBy(const Offset(-8, 0));
        await second.moveBy(const Offset(8, 0));
        await tester.pump();
      }

      expect(
        controller.zoomScale,
        greaterThan(EmoticonEditorController.minZoomScale),
      );
      expect(controller.strokeDabs, isEmpty);
      expect(backend.renderMasks, isEmpty);

      await first.up();
      await second.up();
      await tester.pump();

      expect(backend.renderMasks, isEmpty);
    });

    testWidgets(
      'a second pointer ends an open stroke rather than pinching it',
      (tester) async {
        final backend = RecordingCutoutBackend(
          syntheticCutoutResult(redSquareOnWhitePng()),
        );
        final controller = await pumpCanvas(tester, backend: backend);
        final centre = tester.getCenter(find.byType(EmoticonCutoutCanvas));

        final first = await tester.startGesture(centre);
        // Past the tap slop, so the tap recogniser yields and the scale
        // recogniser (which the brush now rides on) wins the arena.
        for (var step = 0; step < 5; step++) {
          await first.moveBy(const Offset(6, 0));
          await tester.pump();
        }
        expect(controller.strokeActive, isTrue);

        final second = await tester.startGesture(centre + const Offset(60, 0));
        await tester.pump();
        await tester.pump();

        expect(controller.strokeActive, isFalse);
        expect(backend.renderMasks, hasLength(1));

        await first.up();
        await second.up();
        await tester.pump();
      },
    );

    testWidgets('scroll zoom stays anchored under the pointer', (tester) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(tester, backend: backend);
      final canvasRect = tester.getRect(find.byType(EmoticonCutoutCanvas));
      final pointer = canvasRect.topLeft + const Offset(80, 210);
      final localPointer = pointer - canvasRect.topLeft;
      final anchorBefore = controller.normalizedImagePoint(localPointer);

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(pointer));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
      await tester.pump();

      expect(
        controller.zoomScale,
        greaterThan(EmoticonEditorController.minZoomScale),
      );
      final rect = controller.zoomedImageRect();
      expect(
        rect.left + rect.width * anchorBefore.dx,
        closeTo(localPointer.dx, 0.5),
      );
      expect(
        rect.top + rect.height * anchorBefore.dy,
        closeTo(localPointer.dy, 0.5),
      );
    });

    testWidgets('scroll zoom claims the signal so ancestors cannot scroll', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = buildController(backend);
      addTearDown(controller.dispose);
      controller.setSourceImage(redSquareOnWhitePng());
      await controller.runAutoCutout();

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      // The desktop editor puts the canvas inside a scrolling panel. Handling
      // the scroll inline let both act on the same event, so zooming the canvas
      // also scrolled the window.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) =>
                        EmoticonCutoutCanvas(controller: controller),
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      final overCanvas = tester.getCenter(find.byType(EmoticonCutoutCanvas));
      await tester.sendEventToBinding(mouse.hover(overCanvas));
      // Negative dy is scroll-up, which zooms in; scrolling down at rest is
      // already clamped at fit and would prove nothing.
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
      await tester.pump();

      expect(
        controller.zoomScale,
        greaterThan(EmoticonEditorController.minZoomScale),
        reason: 'The canvas should have zoomed.',
      );
      expect(
        scrollController.offset,
        0,
        reason: 'The enclosing panel must not scroll at the same time.',
      );
    });

    testWidgets('a canvas with nothing to zoom leaves scrolling alone', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = buildController(backend);
      addTearDown(controller.dispose);

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) =>
                        EmoticonCutoutCanvas(controller: controller),
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(tester.getCenter(find.byType(EmoticonCutoutCanvas))),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pump();

      // No cutout means nothing to magnify, so the panel must still scroll.
      expect(scrollController.offset, greaterThan(0));
    });

    testWidgets('scrolling down on a canvas already at fit does not zoom, and pins the '
        'current claim behaviour', (tester) async {
      // The gap this closes: the case above has cutoutResult == null, which is
      // the ONLY thing _handlePointerSignal's guard checks. A canvas that HAS
      // a cutout but is already at minZoomScale still registers with the
      // pointerSignalResolver, setZoom clamps, and nothing magnifies - yet the
      // canvas has claimed the signal, so the panel does not scroll.
      //
      // That contradicts the comment above the guard, which says registration
      // happens "only when the canvas will actually zoom". One of the two is
      // wrong. This test pins the CURRENT behaviour rather than asserting the
      // comment, because which one should change is a product call: making the
      // guard match the comment would let a scroll-down at fit escape to the
      // panel, which is arguably right for scrolling and arguably a surprise
      // mid-edit. Routed rather than guessed - if the answer is "the comment
      // was the intent", this test should fail and be rewritten, which is the
      // point of having it.
      // Embedded in a ListView on purpose. Asserting only that zoomScale stays
      // at minZoomScale would prove nothing: setZoom clamps regardless of
      // whether the canvas claimed the pointer signal, so that assertion holds
      // either way. The panel offset is the only observable that distinguishes
      // "claimed and did nothing" from "declined and let the panel scroll".
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = buildController(backend);
      addTearDown(controller.dispose);

      // The cutout is the entire point of this case, and omitting it is not a
      // small slip: without it cutoutResult stays null, the guard declines the
      // signal, and this test silently becomes a duplicate of the sibling above
      // that asserts the opposite. It failed exactly that way first.
      controller.setSourceImage(redSquareOnWhitePng());
      await controller.runAutoCutout();
      expect(
        controller.cutoutResult,
        isNotNull,
        reason: 'Precondition: this case requires a canvas WITH a cutout.',
      );

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) =>
                        EmoticonCutoutCanvas(controller: controller),
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        controller.zoomScale,
        EmoticonEditorController.minZoomScale,
        reason: 'Precondition: the canvas starts at fit.',
      );

      final mouse = TestPointer(2, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(tester.getCenter(find.byType(EmoticonCutoutCanvas))),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(
        controller.zoomScale,
        EmoticonEditorController.minZoomScale,
        reason: 'Already at fit, so a scroll down cannot zoom out further.',
      );
      expect(
        scrollController.offset,
        0,
        reason:
            'CURRENT behaviour: the guard checks only cutoutResult == null, so '
            'a canvas with a cutout claims the signal even at fit and the '
            'panel does not scroll. Compare the sibling test above, where a '
            'null cutoutResult DOES let the panel scroll. If the guard is '
            'ever changed to match its comment, this expectation flips to '
            'greaterThan(0) - which is exactly the signal this test exists '
            'to give.',
      );
    });

    testWidgets('the fit control appears only while magnified', (tester) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(tester, backend: backend);
      final fitControl = find.byKey(
        const ValueKey('emoticon-canvas-fit-to-view'),
      );

      expect(fitControl, findsNothing);

      controller.setZoom(
        scale: 3,
        focalPoint: const Offset(150, 150),
        anchorNormalized: const Offset(0.5, 0.5),
      );
      await tester.pump();
      expect(fitControl, findsOneWidget);

      await tester.tap(fitControl);
      await tester.pump();

      expect(controller.zoomScale, EmoticonEditorController.minZoomScale);
      expect(fitControl, findsNothing);
    });
  });

  group('U6 — the status line is reserved', () {
    testWidgets('a status flip does not change the measured height', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = buildController(backend);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) =>
                    EmoticonStatusMessages(controller: controller),
              ),
            ),
          ),
        ),
      );

      final emptyHeight = tester
          .getSize(find.byType(EmoticonStatusMessages))
          .height;

      controller.statusText = 'Transparent PNG updated.';
      // Notify without going through the engine.
      controller.notifyShortcodeChanged();
      await tester.pump();

      expect(find.text('Transparent PNG updated.'), findsOneWidget);
      expect(
        tester.getSize(find.byType(EmoticonStatusMessages)).height,
        emptyHeight,
      );

      controller.statusText = null;
      controller.notifyShortcodeChanged();
      await tester.pump();

      expect(
        tester.getSize(find.byType(EmoticonStatusMessages)).height,
        emptyHeight,
      );
    });
  });

  group('output bounds', () {
    Finder bounds() => find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter is EmoticonOutputBoundsPainter,
    );

    testWidgets('the artboard is outlined once there is a cutout', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(tester, backend: backend);

      expect(bounds(), findsOneWidget);

      // Square crop and Tight crop differ only in how much transparent margin
      // the output carries. Without a visible artboard the backdrop covers the
      // whole canvas and the two look identical — this rect is the difference.
      final square =
          tester.widget<CustomPaint>(bounds()).painter
              as EmoticonOutputBoundsPainter;

      controller.cutoutResult = controller.cutoutResult!.copyWith(
        width: 40,
        height: 64,
      );
      controller.notifyShortcodeChanged();
      await tester.pump();

      final tight =
          tester.widget<CustomPaint>(bounds()).painter
              as EmoticonOutputBoundsPainter;
      expect(tight.imageRect, isNot(square.imageRect));
    });

    testWidgets('no artboard before a cutout exists', (tester) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      await pumpCanvas(tester, backend: backend, withCutout: false);

      expect(bounds(), findsNothing);
    });
  });

  group('KTD-2 — the Restore ghost', () {
    Finder ghost() => find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is EmoticonSourceGhostPainter,
    );

    /// The source is decoded through `ui.instantiateImageCodec`, which is real
    /// async work outside the fake-async zone — `pumpAndSettle` alone never
    /// lets it complete.
    Future<void> settleSourceDecode(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }

    testWidgets('selecting Restore shows the ghost before any stroke', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(tester, backend: backend);

      expect(ghost(), findsNothing);

      controller.setBrushMode(CutoutBrushMode.restore);
      await settleSourceDecode(tester);

      expect(ghost(), findsOneWidget);

      controller.setBrushMode(CutoutBrushMode.erase);
      await tester.pump();

      expect(ghost(), findsNothing);
    });

    testWidgets('there is no ghost before anything has been cut out', (
      tester,
    ) async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await pumpCanvas(
        tester,
        backend: backend,
        withCutout: false,
      );

      controller.setSourceImage(redSquareOnWhitePng());
      controller.setBrushMode(CutoutBrushMode.restore);
      await settleSourceDecode(tester);

      expect(controller.cutoutResult, isNull);
      expect(ghost(), findsNothing);
    });
  });
}
