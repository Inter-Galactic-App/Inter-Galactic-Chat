import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_editor.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_filter.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_image_renderer.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  // `testWidgets` passes this to `test()` itself, so `flutter test --timeout`
  // cannot lower it. At the ten minute default, renderer work that escapes
  // `_renderReal` stalls the whole suite long enough to read as a wedged tool
  // rather than a broken test. Nothing here takes more than a few seconds.
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(minutes: 2));
  }

  testWidgets('renderer creates a 9:16 PNG story canvas', (tester) async {
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 320, height: 180),
        sourceName: 'landscape.jpg',
        sourceMimeType: 'image/jpeg',
      ),
    );

    final decoded = img.decodePng(draft.baseBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, storyEditorOutputWidth);
    expect(decoded.height, storyEditorOutputHeight);
    expect(draft.previewBytes, isNotNull);
  });

  testWidgets('renderer can defer full-size work for camera drafts', (
    tester,
  ) async {
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 320, height: 180),
        sourceName: 'camera.jpg',
        sourceMimeType: 'image/jpeg',
        previewOnly: true,
      ),
    );

    final preview = img.decodePng(draft.baseBytes);
    expect(preview, isNotNull);
    expect(preview!.width, storyEditorPreviewWidth);
    expect(preview.height, storyEditorPreviewHeight);
    expect(draft.baseIsPreviewOnly, isTrue);

    const renderer = StoryImageRenderer();
    final upload = await _renderReal(
      tester,
      () => renderer.renderUpload(draft),
    );
    final rendered = img.decodePng(upload.bytes);
    expect(rendered, isNotNull);
    expect(rendered!.width, storyEditorOutputWidth);
    expect(rendered.height, storyEditorOutputHeight);
    expect(upload.name, 'camera-story.png');
  });

  testWidgets('renderer can fit a whole photo on a black story canvas', (
    tester,
  ) async {
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 320, height: 180),
        sourceName: 'landscape.jpg',
        imageFitMode: StoryImageFitMode.contain,
      ),
    );

    final decoded = img.decodePng(draft.baseBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, storyEditorOutputWidth);
    expect(decoded.height, storyEditorOutputHeight);
    expect(draft.imageFitMode, StoryImageFitMode.contain);
    expect(decoded.getPixel(0, 0).r, 0);
    expect(decoded.getPixel(0, 0).g, 0);
    expect(decoded.getPixel(0, 0).b, 0);
    expect(
      decoded
          .getPixel(storyEditorOutputWidth ~/ 2, storyEditorOutputHeight ~/ 2)
          .r,
      255,
    );
  });

  testWidgets('renderer can fit a whole photo on a custom story canvas', (
    tester,
  ) async {
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 320, height: 180),
        sourceName: 'landscape.jpg',
        imageFitMode: StoryImageFitMode.contain,
        backgroundColor: const Color(0xFF4DD0E1),
      ),
    );

    final decoded = img.decodePng(draft.baseBytes);

    expect(decoded, isNotNull);
    expect(draft.backgroundColor, const Color(0xFF4DD0E1));
    expect(decoded!.getPixel(0, 0).r, 77);
    expect(decoded.getPixel(0, 0).g, 208);
    expect(decoded.getPixel(0, 0).b, 225);
  });

  testWidgets('renderer can fit a whole photo on a gradient story canvas', (
    tester,
  ) async {
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 320, height: 180),
        sourceName: 'landscape.jpg',
        imageFitMode: StoryImageFitMode.contain,
        backgroundColor: const Color(0xFF111827),
        backgroundGradientColor: const Color(0xFF4DD0E1),
        backgroundMode: StoryCanvasBackgroundMode.gradient,
      ),
    );

    final decoded = img.decodePng(draft.baseBytes);

    expect(decoded, isNotNull);
    expect(draft.backgroundMode, StoryCanvasBackgroundMode.gradient);
    expect(decoded!.getPixel(0, 0).r, 17);
    expect(decoded.getPixel(0, 0).g, 24);
    expect(decoded.getPixel(0, 0).b, 39);
    expect(decoded.getPixel(0, storyEditorOutputHeight - 1).r, 77);
    expect(decoded.getPixel(0, storyEditorOutputHeight - 1).g, 208);
    expect(decoded.getPixel(0, storyEditorOutputHeight - 1).b, 225);
  });

  testWidgets('renderer creates a text-only story canvas', (tester) async {
    final draft = await StoryImageRenderer.createTextDraft(
      backgroundColor: const Color(0xFF111827),
      backgroundGradientColor: const Color(0xFF4DD0E1),
      backgroundMode: StoryCanvasBackgroundMode.gradient,
    );

    final decoded = img.decodePng(draft.baseBytes);

    expect(draft.isTextOnly, isTrue);
    expect(draft.imageFitMode, StoryImageFitMode.contain);
    expect(decoded, isNotNull);
    expect(decoded!.width, storyEditorOutputWidth);
    expect(decoded.height, storyEditorOutputHeight);
    expect(decoded.getPixel(0, 0).r, 17);
    expect(decoded.getPixel(0, storyEditorOutputHeight - 1).g, 208);
  });

  testWidgets('renderer bakes text, emoji, sticker, and mention overlays', (
    tester,
  ) async {
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
        sourceMimeType: 'image/png',
      ),
    );
    const renderer = StoryImageRenderer();
    final baseBytes = await _renderReal(
      tester,
      () => renderer.renderPngBytes(draft),
    );
    final stickerBytes = _solidPng(
      width: 48,
      height: 48,
      color: img.ColorRgb8(0, 255, 0),
    );

    final edited = draft.copyWith(
      overlays: [
        const StoryTextOverlay(
          id: 'text',
          center: Offset(0.5, 0.3),
          text: 'Hello',
          backgroundColor: Color(0xFF0000FF),
        ),
        const StoryEmojiOverlay(
          id: 'emoji',
          center: Offset(0.5, 0.5),
          emoji: '\u{2728}',
        ),
        StoryStickerOverlay(
          id: 'sticker',
          center: const Offset(0.5, 0.7),
          label: 'test',
          image: MemoryImage(stickerBytes),
        ),
        const StoryMentionOverlay(
          id: 'mention',
          center: Offset(0.5, 0.86),
          userId: '@theo:intergalactic.local',
          displayName: 'Theo',
        ),
      ],
    );

    final upload = await _renderReal(
      tester,
      () => renderer.renderUpload(edited),
    );
    final decoded = img.decodePng(upload.bytes);

    expect(upload.mimeType, 'image/png');
    expect(upload.name, 'source-story.png');
    expect(decoded, isNotNull);
    expect(decoded!.width, storyEditorOutputWidth);
    expect(decoded.height, storyEditorOutputHeight);
    expect(upload.bytes, isNot(equals(baseBytes)));
    expect(upload.mentionedUserIds, contains('@theo:intergalactic.local'));
    expect(
      _hasPixel(
        decoded,
        (pixel) => pixel.r < 20 && pixel.g < 20 && pixel.b > 220,
      ),
      isTrue,
    );
  });

  testWidgets('renderer applies a story filter to the base canvas', (
    tester,
  ) async {
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
        sourceMimeType: 'image/png',
      ),
    );
    const renderer = StoryImageRenderer();
    final originalBytes = await _renderReal(
      tester,
      () => renderer.renderPngBytes(draft),
    );
    final filtered = draft.copyWith(
      filterPreset: StoryFilterPreset.sepia,
      filterIntensity: 1,
    );

    final filteredBytes = await _renderReal(
      tester,
      () => renderer.renderPngBytes(filtered),
    );
    final decoded = img.decodePng(filteredBytes);

    expect(decoded, isNotNull);
    expect(decoded!.width, storyEditorOutputWidth);
    expect(decoded.height, storyEditorOutputHeight);
    expect(filteredBytes, isNot(equals(originalBytes)));
  });

  testWidgets('filtered renders keep overlays unfiltered', (tester) async {
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
        sourceMimeType: 'image/png',
      ),
    );
    const renderer = StoryImageRenderer();
    final edited = draft.copyWith(
      filterPreset: StoryFilterPreset.mono,
      overlays: const [
        StoryTextOverlay(
          id: 'text',
          center: Offset(0.5, 0.42),
          text: 'Blue',
          backgroundColor: Color(0xFF0000FF),
        ),
      ],
    );

    final decoded = img.decodePng(
      await _renderReal(tester, () => renderer.renderPngBytes(edited)),
    );

    expect(decoded, isNotNull);
    expect(
      _hasPixel(
        decoded!,
        (pixel) => pixel.r < 20 && pixel.g < 20 && pixel.b > 220,
      ),
      isTrue,
    );
  });

  testWidgets('text toolbar action adds an overlay before done', (
    tester,
  ) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
      ),
    );
    StoryDraft? updatedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (draft) => updatedDraft = draft,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.text_fields));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Story text');
    await tester.tap(find.byIcon(Icons.format_italic));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Story text'), findsOneWidget);

    // Each toolbar button rebuilds with the overlay it edits, so the taps have
    // to be pumped apart. Back to back they all read the pre-tap overlay and
    // the last one silently reverts the others.
    await tester.tap(find.byIcon(Icons.text_increase));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.rotate_90_degrees_cw));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await _pumpUntil(tester, () => updatedDraft != null);

    expect(updatedDraft, isNotNull);
    final textOverlay = updatedDraft!.overlays.single as StoryTextOverlay;
    expect(textOverlay.text, 'Story text');
    expect(textOverlay.fontSize, greaterThan(96));
    expect(textOverlay.rotationRadians, isNot(0));
    expect(textOverlay.isBold, isFalse);
    expect(textOverlay.isItalic, isTrue);
  });

  testWidgets('text toolbar can apply a background fill', (tester) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
      ),
    );
    StoryDraft? updatedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (draft) => updatedDraft = draft,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.text_fields));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Filled');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.format_color_fill));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('story-color-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await _pumpUntil(tester, () => updatedDraft != null);

    final textOverlay = updatedDraft!.overlays.single as StoryTextOverlay;
    expect(textOverlay.backgroundColor, const Color(0xFFFF6B6B));
  });

  testWidgets('emoji sheet exposes a full emoji picker entry', (tester) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (_) {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('fit whole photo toolbar action updates the draft canvas', (
    tester,
  ) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 320, height: 180),
        sourceName: 'landscape.png',
      ),
    );
    StoryDraft? updatedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (draft) => updatedDraft = draft,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.fit_screen));
    await _settleCanvasWork(tester);
    await tester.tap(find.text('Done'));
    await _pumpUntil(tester, () => updatedDraft != null);

    expect(updatedDraft, isNotNull);
    expect(updatedDraft!.imageFitMode, StoryImageFitMode.contain);
    final decoded = img.decodePng(updatedDraft!.baseBytes);
    expect(decoded!.getPixel(0, 0).r, 0);
  });

  testWidgets('background color toolbar action updates fit canvas', (
    tester,
  ) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 320, height: 180),
        sourceName: 'landscape.png',
      ),
    );
    StoryDraft? updatedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (draft) => updatedDraft = draft,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.fit_screen));
    await _settleCanvasWork(tester);
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('story-background-color-6')));
    await _settleCanvasWork(tester);
    await tester.tap(find.text('Done'));
    await _pumpUntil(tester, () => updatedDraft != null);

    expect(updatedDraft, isNotNull);
    expect(updatedDraft!.backgroundColor, const Color(0xFF4DD0E1));
    final decoded = img.decodePng(updatedDraft!.baseBytes);
    expect(decoded!.getPixel(0, 0).r, 77);
    expect(decoded.getPixel(0, 0).g, 208);
    expect(decoded.getPixel(0, 0).b, 225);
  });

  testWidgets('background toolbar action can apply a gradient fit canvas', (
    tester,
  ) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 320, height: 180),
        sourceName: 'landscape.png',
      ),
    );
    StoryDraft? updatedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (draft) => updatedDraft = draft,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.fit_screen));
    await _settleCanvasWork(tester);
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('story-gradient-0')));
    await _settleCanvasWork(tester);
    await tester.tap(find.text('Done'));
    await _pumpUntil(tester, () => updatedDraft != null);

    expect(updatedDraft, isNotNull);
    expect(updatedDraft!.backgroundMode, StoryCanvasBackgroundMode.gradient);
    expect(updatedDraft!.backgroundColor, const Color(0xFF111827));
    expect(updatedDraft!.backgroundGradientColor, const Color(0xFF4DD0E1));
  });

  testWidgets('mention toolbar action adds a visual mention overlay', (
    tester,
  ) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
      ),
    );
    StoryDraft? updatedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (draft) => updatedDraft = draft,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.alternate_email));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await _pumpUntil(tester, () => updatedDraft != null);

    expect(updatedDraft, isNotNull);
    final mentionOverlay = updatedDraft!.overlays.single as StoryMentionOverlay;
    expect(mentionOverlay.userId, '@theo:intergalactic.local');
    expect(mentionOverlay.label, '@Theo');
    expect(
      updatedDraft!.visualMentionUserIds,
      contains('@theo:intergalactic.local'),
    );
  });

  testWidgets('emoji overlays can be resized and rotated from toolbar', (
    tester,
  ) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
      ),
    );
    StoryDraft? updatedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (draft) => updatedDraft = draft,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('\u{1F602}'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.text_increase));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.rotate_90_degrees_cw));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await _pumpUntil(tester, () => updatedDraft != null);

    final emojiOverlay = updatedDraft!.overlays.single as StoryEmojiOverlay;
    expect(emojiOverlay.fontSize, greaterThan(140));
    expect(emojiOverlay.rotationRadians, isNot(0));
  });

  testWidgets(
    'compact filter controls update preset and intensity before done',
    (tester) async {
      final client = DemoClient.createOfflineDemo();
      addTearDown(client.close);
      final draft = await _renderReal(
        tester,
        () => StoryImageRenderer.createDraft(
          sourceBytes: _solidPng(width: 300, height: 500),
          sourceName: 'source.png',
        ),
      );
      StoryDraft? updatedDraft;

      await tester.pumpWidget(
        MaterialApp(
          home: HomeStoryEditor(
            client: client,
            draft: draft,
            onDone: (draft) => updatedDraft = draft,
            onCancel: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.filter_b_and_w_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Original'), findsWidgets);
      expect(find.text('Sepia'), findsOneWidget);
      expect(find.text('Warm'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('story-filter-intensity')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('story-filter-sepia')));
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('story-filter-intensity'));
      expect(slider, findsOneWidget);
      final before = tester.widget<Slider>(slider).value;
      await tester.drag(slider, const Offset(-160, 0));
      await tester.pumpAndSettle();
      final after = tester.widget<Slider>(slider).value;
      expect(after, lessThan(before));

      await tester.tap(find.text('Done'));
      await _pumpUntil(tester, () => updatedDraft != null);

      expect(updatedDraft, isNotNull);
      expect(updatedDraft!.filterPreset, StoryFilterPreset.sepia);
      expect(updatedDraft!.filterIntensity, lessThan(1));
      expect(updatedDraft!.previewBytes, isNotNull);
    },
  );

  testWidgets('mobile canvas swipe cycles filters and button opens intensity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);
    final draft = await _renderReal(
      tester,
      () => StoryImageRenderer.createDraft(
        sourceBytes: _solidPng(width: 300, height: 500),
        sourceName: 'source.png',
      ),
    );
    StoryDraft? updatedDraft;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (draft) => updatedDraft = draft,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.fling(
      find.byKey(const ValueKey('story-filter-canvas')),
      const Offset(-260, 0),
      1200,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.filter_b_and_w_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Mono'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('story-filter-intensity')),
      findsOneWidget,
    );

    await tester.tap(find.text('Done'));
    await _pumpUntil(tester, () => updatedDraft != null);

    expect(updatedDraft, isNotNull);
    expect(updatedDraft!.filterPreset, StoryFilterPreset.mono);
    expect(updatedDraft!.filterIntensity, 1);
  });
}

/// Runs renderer work that needs the real event loop.
///
/// [StoryImageRenderer] hands canvas work to a background isolate through
/// `compute`, and encodes PNGs through `Picture.toImage` /
/// `Image.toByteData`. Those only complete on the real event loop, which the
/// fake-async zone a `testWidgets` body runs in never advances. Awaiting them
/// directly leaves the test wedged until the binding's ten minute backstop
/// timeout instead of failing fast, so hop back to the real zone for the call.
Future<T> _renderReal<T>(WidgetTester tester, Future<T> Function() body) async {
  final result = await tester.runAsync(body);
  if (result == null) {
    fail('tester.runAsync did not run the renderer work.');
  }
  return result;
}

/// Pumps until [ready] holds, letting the editor's real work make progress.
///
/// [HomeStoryEditor] starts the same isolate and engine work from its own
/// handlers — `Done` renders a preview, the canvas actions re-normalize the
/// base image. Those futures only advance on the real event loop, so a plain
/// `pumpAndSettle` spins on the progress indicator until it times out. Hopping
/// out to the real zone between pumps lets the work land.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  await tester.pump();
  while (!ready()) {
    if (!DateTime.now().isBefore(deadline)) {
      fail('Timed out waiting for the story editor to finish rendering.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// Pumps until a canvas action has finished and the editor accepts input again.
///
/// The editor disables its `Done` button for the duration of the render, so an
/// enabled one is the signal that the new canvas has been installed.
Future<void> _settleCanvasWork(WidgetTester tester) async {
  await _pumpUntil(tester, () {
    final buttons = find.widgetWithText(TextButton, 'Done').evaluate();
    return buttons.any(
      (element) => (element.widget as TextButton).onPressed != null,
    );
  });
  await tester.pumpAndSettle();
}

bool _hasPixel(img.Image image, bool Function(img.Pixel pixel) test) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (test(image.getPixel(x, y))) {
        return true;
      }
    }
  }
  return false;
}

Uint8List _solidPng({
  required int width,
  required int height,
  img.Color? color,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color ?? img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodePng(image));
}
