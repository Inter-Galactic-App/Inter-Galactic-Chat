import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'emoticon_test_fixtures.dart';

void main() {
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() completed, {
    required String reason,
  }) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump();
      if (completed()) {
        return;
      }
    }
    fail(reason);
  }

  Future<RecordingCutoutBackend> pumpMobileEditor(WidgetTester tester) async {
    final backend = RecordingCutoutBackend(
      syntheticCutoutResult(redSquareOnWhitePng()),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmoticonCreator(
            mobileLayout: true,
            initialSourceImageData: redSquareOnWhitePng(),
            initialSourceImageName: 'Party Ship.PNG',
            autoRunInitialCutout: true,
            cutoutService: ImageCutoutService(backend: backend),
            draftStore: FakeDraftStore([sampleDraft()]),
            onCreate: (_, _, _) async => true,
          ),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => backend.generateCount > 0,
      reason: 'Initial cutout did not complete.',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('emoticon-advanced-edit')));
    await tester.pumpAndSettle();

    return backend;
  }

  Finder tab(String group) => find.byKey(ValueKey('emoticon-tool-tab-$group'));
  Finder tray(String group) =>
      find.byKey(ValueKey('emoticon-tool-tray-$group'));

  testWidgets('editor opens full-height with a dominant canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpMobileEditor(tester);

    expect(find.text('Cutout editor'), findsOneWidget);
    // No tray open: the canvas takes all space above the tab bar.
    final canvas = tester.getRect(
      find.bySemanticsLabel(
        'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
      ),
    );
    expect(canvas.height, greaterThan(800 * 0.5));

    // The Editor exposes no Save control (R6); Save lives on the Quick card.
    expect(find.text('Save!'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('tab bar raises exactly one tray and closes on re-tap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpMobileEditor(tester);

    expect(tray('cutout'), findsNothing);

    await tester.tap(tab('cutout'));
    await tester.pumpAndSettle();
    expect(tray('cutout'), findsOneWidget);

    await tester.tap(tab('output'));
    await tester.pumpAndSettle();
    expect(tray('cutout'), findsNothing);
    expect(tray('output'), findsOneWidget);

    // Re-tapping the active tab closes the tray; the canvas reclaims space.
    final canvasFinder = find.bySemanticsLabel(
      'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
    );
    final canvasWithTray = tester.getRect(canvasFinder).height;
    await tester.tap(tab('output'));
    await tester.pumpAndSettle();
    expect(tray('output'), findsNothing);
    final canvasWithoutTray = tester.getRect(canvasFinder).height;
    expect(canvasWithoutTray, greaterThan(canvasWithTray));
  });

  testWidgets('brush renders the thin tray variant (R5)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpMobileEditor(tester);

    await tester.tap(tab('cutout'));
    await tester.pumpAndSettle();
    final cutoutTrayHeight = tester.getSize(tray('cutout')).height;

    await tester.tap(tab('brush'));
    await tester.pumpAndSettle();
    final brushTrayHeight = tester.getSize(tray('brush')).height;

    expect(brushTrayHeight, lessThan(cutoutTrayHeight));
    expect(find.text('Erase'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    // Switching away restores the standard tray height.
    await tester.tap(tab('output'));
    await tester.pumpAndSettle();
    expect(tester.getSize(tray('output')).height, greaterThan(brushTrayHeight));
  });

  testWidgets('a canvas drag applies the brush through the shared engine', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final backend = await pumpMobileEditor(tester);

    await tester.tap(tab('brush'));
    await tester.pumpAndSettle();

    final canvas = find.bySemanticsLabel(
      'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
    );
    await tester.tapAt(tester.getRect(canvas).center);
    await pumpUntil(
      tester,
      () => backend.renderMasks.isNotEmpty,
      reason: 'Brush render did not complete.',
    );

    expect(backend.renderMasks, isNotEmpty);
  });

  testWidgets('tab bar and tray clear a simulated bottom inset (R7)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.padding = const FakeViewPadding(bottom: 90);
    tester.view.viewPadding = const FakeViewPadding(bottom: 90);
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });

    await pumpMobileEditor(tester);

    final bottomInset = 90 / tester.view.devicePixelRatio;

    await tester.tap(tab('cutout'));
    await tester.pumpAndSettle();

    final tabRect = tester.getRect(tab('cutout'));
    final trayRect = tester.getRect(tray('cutout'));

    expect(tabRect.bottom, lessThanOrEqualTo(800 - bottomInset + 0.01));
    expect(trayRect.bottom, lessThanOrEqualTo(tabRect.top + 0.01));
  });

  testWidgets('the Photo tray offers Select photo with no source (FR5)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var pickCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmoticonCreator(
            mobileLayout: true,
            pickSourceImage: () async {
              pickCount++;
              return FakePickerResult(
                redSquareOnWhitePng(),
                name: 'Flat Robot.PNG',
              );
            },
            cutoutService: ImageCutoutService(
              backend: RecordingCutoutBackend(
                syntheticCutoutResult(redSquareOnWhitePng()),
              ),
            ),
            draftStore: FakeDraftStore(),
            onCreate: (_, _, _) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('emoticon-advanced-edit')));
    await tester.pumpAndSettle();

    // The stranded user's other way out: the empty canvas itself (U5).
    expect(
      find.byKey(const ValueKey('emoticon-canvas-pick-photo')),
      findsOneWidget,
    );

    // The tab key is unchanged by the 'Crop' -> 'Photo' rename (KTD-3).
    expect(tab('crop'), findsOneWidget);
    await tester.tap(tab('crop'));
    await tester.pumpAndSettle();

    final pickButton = find.byKey(const ValueKey('emoticon-editor-pick-photo'));
    expect(pickButton, findsOneWidget);
    expect(find.text('Select photo'), findsWidgets);

    await tester.tap(pickButton);
    await tester.pumpAndSettle();

    expect(pickCount, 1);
    // Picking inside the Editor re-seats the source, so Crop becomes usable
    // and the control now offers to replace the image.
    expect(find.text('Change photo'), findsOneWidget);
  });

  testWidgets('the Photo tray offers Change photo once a source exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpMobileEditor(tester);
    await tester.tap(tab('crop'));
    await tester.pumpAndSettle();

    expect(find.text('Change photo'), findsOneWidget);
    expect(
      tester
          .widget<tiamat.Button>(
            find.byKey(const ValueKey('emoticon-editor-pick-photo')),
          )
          .onTap,
      isNotNull,
    );
  });

  testWidgets('undo/redo live in the editor chrome and drive the history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The backend is no longer inspected: this test now pumps on the undo/redo
    // enabled state, which is what its assertions actually depend on, rather
    // than on the backend's recorded mask count.
    await pumpMobileEditor(tester);
    final undo = find.byKey(const ValueKey('emoticon-mask-undo'));
    final redo = find.byKey(const ValueKey('emoticon-mask-redo'));

    // Present but inert with nothing to step through, so the control does not
    // appear and disappear under the user's thumb.
    expect(undo, findsOneWidget);
    expect(redo, findsOneWidget);
    expect(tester.widget<tiamat.IconButton>(undo).onPressed, isNull);
    expect(tester.widget<tiamat.IconButton>(redo).onPressed, isNull);

    final canvas = find.bySemanticsLabel(
      'Transparent cutout preview on checkerboard background. Drag on the image to refine the mask.',
    );
    await tester.tapAt(tester.getRect(canvas).center);
    // Pump on the state the assertion actually depends on. renderMasks is
    // appended to BEFORE RecordingCutoutBackend.render returns, so waiting on it
    // can proceed while controller.brushRendering is still true - and
    // canUndoBrush requires !brushRendering. The single extra pump() below used
    // to be what covered the rest of the render chain, which made this test
    // depend on how many turns that chain happens to take.
    await pumpUntil(
      tester,
      () => tester.widget<tiamat.IconButton>(undo).onPressed != null,
      reason: 'Undo did not become available after the brush render.',
    );

    expect(tester.widget<tiamat.IconButton>(undo).onPressed, isNotNull);

    await tester.tap(undo);
    await pumpUntil(
      tester,
      () => tester.widget<tiamat.IconButton>(redo).onPressed != null,
      reason: 'Redo did not become available after the undo re-render.',
    );

    // The undo went through the engine, so the preview really went back.
    expect(tester.widget<tiamat.IconButton>(undo).onPressed, isNull);
    expect(tester.widget<tiamat.IconButton>(redo).onPressed, isNotNull);
  });

  testWidgets('tab targets are at least 40x40', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpMobileEditor(tester);

    for (final group in [
      'cutout',
      'brush',
      'crop',
      'output',
      'preview',
      'drafts',
    ]) {
      final size = tester.getSize(tab(group));
      expect(size.height, greaterThanOrEqualTo(40), reason: '$group height');
      expect(size.width, greaterThanOrEqualTo(40), reason: '$group width');
    }
  });
}
