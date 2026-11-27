import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';

import 'emoticon_test_fixtures.dart';

/// Regression guards for the stroke-scoped brush (U2) and canvas zoom (U7).
///
/// The headline guard is "one render per stroke": if per-dab rendering ever
/// comes back, that test fails first and the whole F1 flicker family is back
/// with it.
void main() {
  const canvasRect = Rect.fromLTWH(0, 0, 100, 100);
  const viewport = Size(200, 200);

  EmoticonEditorController buildController({ImageCutoutBackend? backend}) {
    return EmoticonEditorController(
      cutoutService: ImageCutoutService(
        backend:
            backend ??
            RecordingCutoutBackend(
              syntheticCutoutResult(redSquareOnWhitePng()),
            ),
      ),
      draftStore: FakeDraftStore(),
      creatingNew: true,
    );
  }

  Future<EmoticonEditorController> readyController(
    ImageCutoutBackend backend,
  ) async {
    final controller = buildController(backend: backend);
    controller.setSourceImage(redSquareOnWhitePng());
    await controller.runAutoCutout();
    controller.setViewportSize(viewport);
    return controller;
  }

  /// The source pixel currently under the viewport centre, derived only from
  /// public geometry — the same quantity FR12 requires to survive a settle.
  Offset sourcePointAtViewportCentre(EmoticonEditorController controller) {
    final rect = controller.zoomedImageRect();
    final crop = controller.displayCropBounds!;
    final normalizedX = (viewport.width / 2 - rect.left) / rect.width;
    final normalizedY = (viewport.height / 2 - rect.top) / rect.height;
    return Offset(
      crop.left + crop.width * normalizedX,
      crop.top + crop.height * normalizedY,
    );
  }

  group('stroke lifecycle', () {
    test('a drag of many dabs produces exactly one render', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);
      expect(backend.renderMasks, isEmpty);

      controller.beginBrushStroke();
      for (var step = 0; step < 12; step++) {
        controller.applyBrushAt(Offset(30.0 + step, 40), canvasRect);
      }
      expect(
        backend.renderMasks,
        isEmpty,
        reason: 'Dabs must not render; the settle does.',
      );

      await controller.endBrushStroke();

      expect(backend.renderMasks, hasLength(1));
    });

    test('a stroke that painted nothing never reaches the engine', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.beginBrushStroke();
      // Outside the image rect — the letterbox case.
      controller.applyBrushAt(const Offset(400, 400), canvasRect);
      await controller.endBrushStroke();

      expect(backend.renderMasks, isEmpty);
      expect(controller.strokeGeometry, isNull);
      expect(controller.strokeDabs, isEmpty);
    });

    test('the brush maps through latched geometry, not a moving crop', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);
      controller.setBrushMode(CutoutBrushMode.restore);

      controller.beginBrushStroke();
      // Simulate a stray render landing mid-stroke: the crop shrinks to the
      // subject, which is exactly what `_renderCutout` does on every call.
      controller.cutoutResult = controller.cutoutResult!.copyWith(
        cropBounds: const CutoutIntRect(
          left: 16,
          top: 16,
          right: 47,
          bottom: 47,
        ),
      );
      controller.applyBrushAt(const Offset(75, 75), canvasRect);
      await controller.endBrushStroke();

      // Latched crop (the full 64x64 source) puts this dab at source (48, 48),
      // which starts transparent; the shrunken crop would put it at (40, 40),
      // which is already opaque subject. Only the latched mapping can raise
      // alpha at 48.
      expect(backend.renderMasks.single.alpha[48 * 64 + 48], greaterThan(0));
    });

    test(
      'without a latch the shifted crop moves the same screen point',
      () async {
        final backend = RecordingCutoutBackend(
          syntheticCutoutResult(redSquareOnWhitePng()),
        );
        final controller = await readyController(backend);
        addTearDown(controller.dispose);
        controller.setBrushMode(CutoutBrushMode.restore);

        controller.cutoutResult = controller.cutoutResult!.copyWith(
          cropBounds: const CutoutIntRect(
            left: 16,
            top: 16,
            right: 47,
            bottom: 47,
          ),
        );
        // No beginBrushStroke: the dab resolves through the live crop and lands
        // at source (40, 40) instead. This is the drift the latch removes.
        controller.applyBrushAt(const Offset(75, 75), canvasRect);
        await Future<void>.delayed(Duration.zero);

        expect(backend.renderMasks.single.alpha[48 * 64 + 48], 0);
      },
    );

    test('layout geometry does not change between begin and end', () async {
      final backend = ShrinkingCropCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.beginBrushStroke();
      final latchedWidth = controller.displayImageWidth;
      final latchedCrop = controller.displayCropBounds!;

      for (var step = 0; step < 5; step++) {
        controller.applyBrushAt(Offset(40.0 + step, 40), canvasRect);
        expect(controller.displayImageWidth, latchedWidth);
        expect(controller.displayCropBounds!.left, latchedCrop.left);
        expect(controller.displayCropBounds!.width, latchedCrop.width);
      }

      await controller.endBrushStroke();

      // Re-framing happens exactly once, on stroke end.
      expect(controller.displayImageWidth, isNot(latchedWidth));
    });

    test(
      'the overlay is cleared in the notification that adopts the result',
      () async {
        final backend = RecordingCutoutBackend(
          syntheticCutoutResult(redSquareOnWhitePng()),
        );
        final controller = await readyController(backend);
        addTearDown(controller.dispose);

        final framesShowingBoth = <String>[];
        final settledBytes = controller.cutoutResult!.pngBytes;
        controller.addListener(() {
          final adopted = !identical(
            controller.cutoutResult!.pngBytes,
            settledBytes,
          );
          if (adopted && controller.strokeDabs.isNotEmpty) {
            framesShowingBoth.add('overlay survived the settle');
          }
        });

        controller.beginBrushStroke();
        controller.applyBrushAt(const Offset(50, 50), canvasRect);
        expect(controller.strokeDabs, hasLength(1));
        await controller.endBrushStroke();

        expect(framesShowingBoth, isEmpty);
        expect(controller.strokeDabs, isEmpty);
        expect(controller.strokeGeometry, isNull);
      },
    );

    test('save is blocked while a stroke is open', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);
      controller.shortcodeController.text = 'party';

      expect(controller.canSave, isTrue);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      expect(controller.canSave, isFalse);

      await controller.endBrushStroke();
      expect(controller.canSave, isTrue);
    });

    test('disposing mid-stroke does not notify after dispose', () async {
      final backend = DeferredRenderCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = buildController(backend: backend);
      controller.setSourceImage(redSquareOnWhitePng());
      await controller.runAutoCutout();
      controller.setViewportSize(viewport);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      final settle = controller.endBrushStroke();

      var notifiedAfterDispose = false;
      controller.addListener(() => notifiedAfterDispose = true);
      controller.dispose();
      backend.completeRender();
      await settle;

      expect(notifiedAfterDispose, isFalse);
    });

    test('the exported bytes are unchanged for a fixed dab sequence', () async {
      // The fake echoes the mask it was handed into `pngBytes`, so comparing
      // exported bytes really compares the mask that reached the engine.
      Future<Uint8List> exportAfterDabs({required bool useStroke}) async {
        final controller = await readyController(
          MaskEchoCutoutBackend(syntheticCutoutResult(redSquareOnWhitePng())),
        );
        addTearDown(controller.dispose);

        if (useStroke) {
          controller.beginBrushStroke();
        }
        for (var step = 0; step < 6; step++) {
          controller.applyBrushAt(Offset(30.0 + step * 4, 45), canvasRect);
        }
        if (useStroke) {
          await controller.endBrushStroke();
        } else {
          // Wait on the CONDITION, not on a turn count. Six dabs drive one
          // in-flight render plus one queued trailing render, and _runBrushRender
          // awaits cutoutService.render before adopting the result - so the
          // number of microtask turns needed depends on how many awaits the
          // service adds internally. Two fixed Duration.zero turns encoded that
          // as an assumption, and when it stopped holding the test failed on a
          // null dereference of imageData rather than on the behaviour it guards.
          var turns = 0;
          while (controller.brushRendering || controller.brushRenderQueued) {
            await Future<void>.delayed(Duration.zero);
            turns++;
            if (turns > 1000) {
              fail(
                'Brush render did not settle: brushRendering='
                '${controller.brushRendering} brushRenderQueued='
                '${controller.brushRenderQueued}',
              );
            }
          }
        }
        return controller.imageData!;
      }

      // Same image, same dabs: the stroke-scoped path must export exactly what
      // the per-dab path did (FR7 — the fix is presentation-only).
      final viaStroke = await exportAfterDabs(useStroke: true);
      final viaPerDab = await exportAfterDabs(useStroke: false);

      expect(viaStroke, orderedEquals(viaPerDab));
    });
  });

  group('undo / redo', () {
    test('one stroke is one undo step and it round-trips', () async {
      final backend = MaskEchoCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      expect(controller.canUndoBrush, isFalse);
      expect(controller.canRedoBrush, isFalse);

      final before = Uint8List.fromList(controller.workingMask!.alpha);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      controller.applyBrushAt(const Offset(54, 50), canvasRect);
      await controller.endBrushStroke();

      final after = Uint8List.fromList(controller.workingMask!.alpha);
      expect(after, isNot(orderedEquals(before)));
      // Two dabs, one stroke, one step.
      expect(controller.undoDepth, 1);
      expect(controller.canUndoBrush, isTrue);
      expect(controller.canRedoBrush, isFalse);

      await controller.undoBrush();
      expect(controller.workingMask!.alpha, orderedEquals(before));
      expect(controller.canUndoBrush, isFalse);
      expect(controller.canRedoBrush, isTrue);

      await controller.redoBrush();
      expect(controller.workingMask!.alpha, orderedEquals(after));
      expect(controller.canUndoBrush, isTrue);
      expect(controller.canRedoBrush, isFalse);
    });

    test('an undo is followed through to the rendered output', () async {
      final backend = MaskEchoCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      final before = Uint8List.fromList(controller.imageData!);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      await controller.endBrushStroke();
      expect(controller.imageData, isNot(orderedEquals(before)));

      await controller.undoBrush();

      // The engine ran again, so the preview and the exported bytes actually
      // go back — undo is not merely a bookkeeping change.
      expect(controller.imageData, orderedEquals(before));
    });

    test('a stroke that painted nothing adds no undo step', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(400, 400), canvasRect);
      await controller.endBrushStroke();

      expect(controller.undoDepth, 0);
      expect(controller.canUndoBrush, isFalse);
    });

    test('painting after an undo drops the redo branch', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      await controller.endBrushStroke();
      await controller.undoBrush();
      expect(controller.canRedoBrush, isTrue);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(60, 60), canvasRect);
      await controller.endBrushStroke();

      expect(controller.redoDepth, 0);
      expect(controller.canRedoBrush, isFalse);
    });

    test('Reset is undoable', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      await controller.endBrushStroke();
      final brushed = Uint8List.fromList(controller.workingMask!.alpha);

      await controller.resetCutout();
      expect(
        controller.workingMask!.alpha,
        orderedEquals(controller.autoCutoutMask!.alpha),
      );

      await controller.undoBrush();
      expect(controller.workingMask!.alpha, orderedEquals(brushed));
    });

    test('a fresh auto cutout clears the history', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      await controller.endBrushStroke();
      expect(controller.undoDepth, 1);

      await controller.runAutoCutout();

      expect(controller.undoDepth, 0);
      expect(controller.redoDepth, 0);
    });

    test('replacing the source clears the history', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      await controller.endBrushStroke();
      expect(controller.undoDepth, 1);

      controller.setSourceImage(redSquareOnWhitePng());

      expect(controller.undoDepth, 0);
      expect(controller.canUndoBrush, isFalse);
    });

    test('undo is blocked while a stroke is open', () async {
      final backend = RecordingCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.beginBrushStroke();
      controller.applyBrushAt(const Offset(50, 50), canvasRect);
      await controller.endBrushStroke();

      controller.beginBrushStroke();
      expect(controller.canUndoBrush, isFalse);
      await controller.endBrushStroke();
      expect(controller.canUndoBrush, isTrue);
    });
  });

  group('brush size', () {
    test('the size floor is fine enough for edge work', () {
      // QA found 0.02 too coarse: on a 1000px photo that is a 20px radius.
      expect(EmoticonEditorController.minBrushRadius, lessThanOrEqualTo(0.005));
      expect(EmoticonEditorController.maxBrushRadius, 0.12);
    });

    test('the smallest brush is not inflated by the on-screen floor', () async {
      final controller = await readyController(
        RecordingCutoutBackend(syntheticCutoutResult(redSquareOnWhitePng())),
      );
      addTearDown(controller.dispose);

      // Measured against a realistic photo rather than the 64px fixture: on a
      // tiny source `applyBrush`'s own two-pixel floor dominates and hides the
      // thing under test.
      controller.cutoutResult = controller.cutoutResult!.copyWith(
        sourceWidth: 1000,
        sourceHeight: 1000,
        cropBounds: const CutoutIntRect(
          left: 0,
          top: 0,
          right: 999,
          bottom: 999,
        ),
      );
      const rect = Rect.fromLTWH(0, 0, 1000, 1000);

      // A generous screen floor would draw a ring several times the mask
      // footprint at the small end, and the settle would visibly shrink it.
      controller.setBrushRadius(EmoticonEditorController.minBrushRadius);
      final smallest = controller.brushRadiusPixels(rect);
      controller.setBrushRadius(EmoticonEditorController.maxBrushRadius);
      final largest = controller.brushRadiusPixels(rect);

      expect(smallest, closeTo(5, 0.001));
      expect(largest, closeTo(120, 0.001));
    });
  });

  group('canvas zoom', () {
    test('zoom clamps at both ends and rests at a zero offset', () async {
      final controller = await readyController(
        RecordingCutoutBackend(syntheticCutoutResult(redSquareOnWhitePng())),
      );
      addTearDown(controller.dispose);

      controller.setZoom(
        scale: 40,
        focalPoint: const Offset(100, 100),
        anchorNormalized: const Offset(0.5, 0.5),
      );
      expect(controller.zoomScale, EmoticonEditorController.maxZoomScale);

      controller.setZoom(scale: 0.1);
      expect(controller.zoomScale, EmoticonEditorController.minZoomScale);
      expect(controller.zoomOffset, Offset.zero);
    });

    test('the image cannot be panned out of the viewport', () async {
      final controller = await readyController(
        RecordingCutoutBackend(syntheticCutoutResult(redSquareOnWhitePng())),
      );
      addTearDown(controller.dispose);

      controller.setZoom(
        scale: 4,
        focalPoint: const Offset(100, 100),
        anchorNormalized: const Offset(0.5, 0.5),
      );
      controller.panZoomBy(const Offset(100000, 100000));

      final rect = controller.zoomedImageRect();
      expect(rect.contains(const Offset(100, 100)), isTrue);
    });

    test('zoom keeps the anchored point under the focal point', () async {
      final controller = await readyController(
        RecordingCutoutBackend(syntheticCutoutResult(redSquareOnWhitePng())),
      );
      addTearDown(controller.dispose);

      const focal = Offset(60, 140);
      final anchor = controller.normalizedImagePoint(focal);
      controller.setZoom(scale: 3, focalPoint: focal, anchorNormalized: anchor);

      final rect = controller.zoomedImageRect();
      expect(rect.left + rect.width * anchor.dx, closeTo(focal.dx, 0.001));
      expect(rect.top + rect.height * anchor.dy, closeTo(focal.dy, 0.001));
    });

    test('magnification never changes the mask footprint (FR11)', () async {
      Future<CutoutMask> maskAfterDabAtNormalized(double zoom) async {
        final backend = RecordingCutoutBackend(
          syntheticCutoutResult(redSquareOnWhitePng()),
        );
        final controller = await readyController(backend);
        addTearDown(controller.dispose);

        if (zoom > 1) {
          controller.setZoom(
            scale: zoom,
            focalPoint: const Offset(100, 100),
            anchorNormalized: const Offset(0.5, 0.5),
          );
        }
        final rect = controller.zoomedImageRect();
        controller.beginBrushStroke();
        controller.applyBrushAt(
          Offset(rect.left + rect.width * 0.5, rect.top + rect.height * 0.5),
          rect,
        );
        await controller.endBrushStroke();
        return backend.renderMasks.single;
      }

      final atFit = await maskAfterDabAtNormalized(1);
      final atFourTimes = await maskAfterDabAtNormalized(4);

      expect(atFourTimes.alpha, orderedEquals(atFit.alpha));
    });

    test('the cursor ring grows with magnification', () async {
      final controller = await readyController(
        RecordingCutoutBackend(syntheticCutoutResult(redSquareOnWhitePng())),
      );
      addTearDown(controller.dispose);

      final atFit = controller.brushRadiusPixels(controller.zoomedImageRect());
      controller.setZoom(
        scale: 4,
        focalPoint: const Offset(100, 100),
        anchorNormalized: const Offset(0.5, 0.5),
      );
      final atFourTimes = controller.brushRadiusPixels(
        controller.zoomedImageRect(),
      );

      expect(atFourTimes, closeTo(atFit * 4, 0.001));
    });

    test('a re-cropping settle keeps the viewport centred (FR12)', () async {
      final backend = ShrinkingCropCutoutBackend(
        syntheticCutoutResult(redSquareOnWhitePng()),
      );
      final controller = await readyController(backend);
      addTearDown(controller.dispose);

      controller.setZoom(
        scale: 4,
        focalPoint: const Offset(70, 130),
        anchorNormalized: controller.normalizedImagePoint(
          const Offset(70, 130),
        ),
      );

      controller.beginBrushStroke();
      final before = sourcePointAtViewportCentre(controller);
      controller.applyBrushAt(const Offset(60, 60), canvasRect);
      await controller.endBrushStroke();

      expect(controller.displayCropBounds!.width, lessThan(64));
      final after = sourcePointAtViewportCentre(controller);
      expect(after.dx, closeTo(before.dx, 0.5));
      expect(after.dy, closeTo(before.dy, 0.5));
    });

    test('replacing the source resets zoom', () async {
      final controller = await readyController(
        RecordingCutoutBackend(syntheticCutoutResult(redSquareOnWhitePng())),
      );
      addTearDown(controller.dispose);

      controller.setZoom(
        scale: 4,
        focalPoint: const Offset(100, 100),
        anchorNormalized: const Offset(0.25, 0.25),
      );
      expect(controller.zoomScale, 4);

      controller.setSourceImage(redSquareOnWhitePng());

      expect(controller.zoomScale, EmoticonEditorController.minZoomScale);
      expect(controller.zoomOffset, Offset.zero);
    });
  });

  group('source-to-canvas transform (KTD-2a)', () {
    test('a negative crop left still lands source (0,0) correctly', () async {
      final controller = await readyController(
        RecordingCutoutBackend(syntheticCutoutResult(redSquareOnWhitePng())),
      );
      addTearDown(controller.dispose);

      // Padding and square framing push the crop past the source edge and are
      // not clamped, so a negative left is a real case, not a hypothetical.
      controller.cutoutResult = controller.cutoutResult!.copyWith(
        cropBounds: const CutoutIntRect(
          left: -8,
          top: -4,
          right: 71,
          bottom: 75,
        ),
      );

      const imageRect = Rect.fromLTWH(10, 20, 160, 160);
      final destination = controller.sourceImageDestinationRect(imageRect)!;
      // cropBounds is inclusive, so this crop is 80x80 over a 64x64 source.
      final scaleX = imageRect.width / 80;
      final scaleY = imageRect.height / 80;

      // Source pixel (cropLeft, cropTop) must land on imageRect's top-left.
      expect(destination.left + -8 * scaleX, closeTo(imageRect.left, 0.001));
      expect(destination.top + -4 * scaleY, closeTo(imageRect.top, 0.001));
      expect(destination.left, closeTo(imageRect.left + 8 * scaleX, 0.001));
      expect(destination.top, closeTo(imageRect.top + 4 * scaleY, 0.001));
      expect(destination.width, closeTo(64 * scaleX, 0.001));
      expect(destination.height, closeTo(64 * scaleY, 0.001));
    });
  });
}

/// Returns a smaller `cropBounds` on every render, reproducing the engine's
/// recompute-the-subject-bounds behaviour that F1-b is about.
class ShrinkingCropCutoutBackend implements ImageCutoutBackend {
  ShrinkingCropCutoutBackend(this.result);

  final CutoutResult result;
  final renderMasks = <CutoutMask>[];
  int generateCount = 0;
  int _renders = 0;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    generateCount++;
    return result;
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) async {
    renderMasks.add(mask);
    _renders++;
    final inset = 4 * _renders;
    final side = 64 - inset * 2;
    return result.copyWith(
      mask: mask,
      cropBounds: CutoutIntRect(
        left: inset,
        top: inset,
        right: 63 - inset,
        bottom: 63 - inset,
      ),
      width: side,
      height: side,
    );
  }
}

/// Echoes the mask it rendered into `pngBytes`, so a byte comparison of the
/// exported image is really a comparison of the mask that reached the engine.
class MaskEchoCutoutBackend implements ImageCutoutBackend {
  MaskEchoCutoutBackend(this.result);

  final CutoutResult result;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    return result.copyWith(pngBytes: Uint8List.fromList(result.mask.alpha));
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) async {
    return result.copyWith(
      mask: mask,
      pngBytes: Uint8List.fromList(mask.alpha),
    );
  }
}

class DeferredRenderCutoutBackend implements ImageCutoutBackend {
  DeferredRenderCutoutBackend(this.result);

  final CutoutResult result;
  final _renderGate = Completer<void>();
  int renderCount = 0;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    return result;
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) async {
    renderCount++;
    await _renderGate.future;
    return result.copyWith(mask: mask);
  }

  void completeRender() => _renderGate.complete();
}
