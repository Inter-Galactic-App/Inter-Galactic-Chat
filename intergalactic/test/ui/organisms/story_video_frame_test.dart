import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_frame.dart';

void main() {
  test('fit layout centers landscape media on portrait story canvas', () {
    final layout = storyVideoCompositionLayout(
      canvasSize: const Size(108, 192),
      fitMode: StoryVideoFitMode.fit,
      mediaWidth: 1920,
      mediaHeight: 1080,
    );

    expect(layout.canvasRect, const Rect.fromLTWH(0, 0, 108, 192));
    expect(layout.mediaDisplayRect.left, 0);
    expect(layout.mediaDisplayRect.width, 108);
    expect(layout.mediaDisplayRect.top, closeTo(65.625, 0.001));
    expect(layout.mediaDisplayRect.height, closeTo(60.75, 0.001));
    expect(layout.nonMediaRects, hasLength(2));
    expect(layout.nonMediaRects.first.top, 0);
    expect(layout.nonMediaRects.first.bottom, closeTo(65.625, 0.001));
    expect(layout.nonMediaRects.last.top, closeTo(126.375, 0.001));
    expect(layout.nonMediaRects.last.bottom, 192);
    expect(layout.usesBakedLetterboxCrop, isFalse);
    expect(layout.innerFit, BoxFit.contain);
  });

  test('fit layout can crop baked letterboxes inside visible media frame', () {
    final layout = storyVideoCompositionLayout(
      canvasSize: const Size(108, 192),
      fitMode: StoryVideoFitMode.fit,
      mediaWidth: 1080,
      mediaHeight: 1920,
      displayWidth: 1080,
      displayHeight: 608,
      hasBakedLetterbox: true,
    );

    expect(layout.mediaDisplayRect.width, 108);
    expect(layout.mediaDisplayRect.height, closeTo(60.8, 0.001));
    expect(layout.mediaSourceSize, const Size(1080, 1920));
    expect(layout.nonMediaRects, hasLength(2));
    expect(layout.usesBakedLetterboxCrop, isTrue);
    expect(layout.innerFit, BoxFit.fill);
  });

  test('fit layout without media dimensions falls back to full canvas', () {
    // When probing cannot supply media dimensions the layout cannot compute
    // letterbox rects, so the matte paints nothing. Story surfaces therefore
    // render video with a transparent letterbox fill so the base background
    // still owns non-media pixels in this degenerate case.
    final layout = storyVideoCompositionLayout(
      canvasSize: const Size(108, 192),
      fitMode: StoryVideoFitMode.fit,
      mediaWidth: null,
      mediaHeight: null,
    );

    expect(layout.mediaDisplayRect, layout.canvasRect);
    expect(layout.nonMediaRects, isEmpty);
    expect(layout.usesBakedLetterboxCrop, isFalse);
    expect(layout.innerFit, BoxFit.contain);
  });

  test('fill layout covers the story canvas without non-media rects', () {
    final layout = storyVideoCompositionLayout(
      canvasSize: const Size(108, 192),
      fitMode: StoryVideoFitMode.fill,
      mediaWidth: 1920,
      mediaHeight: 1080,
    );

    expect(layout.mediaDisplayRect, layout.canvasRect);
    expect(layout.nonMediaRects, isEmpty);
    expect(layout.usesBakedLetterboxCrop, isFalse);
    expect(layout.innerFit, BoxFit.cover);
  });

  test(
    'background matte paints non-media pixels above media below overlays',
    () async {
      final layout = storyVideoCompositionLayout(
        canvasSize: const Size(108, 192),
        fitMode: StoryVideoFitMode.fit,
        mediaWidth: 1920,
        mediaHeight: 1080,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawRect(
        layout.canvasRect,
        Paint()..color = const Color(0xFF000000),
      );
      canvas.drawRect(
        layout.mediaDisplayRect,
        Paint()..color = const Color(0xFF0000FF),
      );
      paintStoryVideoBackgroundMatte(
        canvas: canvas,
        size: layout.canvasRect.size,
        rects: layout.nonMediaRects,
        backgroundColor: const Color(0xFFFF0000),
        backgroundGradientColor: const Color(0xFFFF0000),
        backgroundMode: StoryBackgroundMode.solid,
      );
      canvas.drawRect(
        const Rect.fromLTWH(8, 8, 8, 8),
        Paint()..color = const Color(0xFFFFFFFF),
      );

      final image = await recorder.endRecording().toImage(108, 192);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      addTearDown(image.dispose);

      expect(_rgbaAt(bytes!, width: 108, x: 4, y: 4), [255, 0, 0, 255]);
      expect(_rgbaAt(bytes, width: 108, x: 54, y: 96), [0, 0, 255, 255]);
      expect(_rgbaAt(bytes, width: 108, x: 10, y: 10), [255, 255, 255, 255]);
      expect(_rgbaAt(bytes, width: 108, x: 4, y: 188), [255, 0, 0, 255]);
    },
  );
}

List<int> _rgbaAt(
  ByteData bytes, {
  required int width,
  required int x,
  required int y,
}) {
  final offset = (y * width + x) * 4;
  return [
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
    bytes.getUint8(offset + 3),
  ];
}
