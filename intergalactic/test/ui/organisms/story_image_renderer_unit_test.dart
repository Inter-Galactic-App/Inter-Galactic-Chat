import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_image_renderer.dart';

void main() {
  test('camera drafts can use a preview-sized normalized base', () async {
    final sourceBytes = _solidPng(width: 320, height: 180);

    final draft = await StoryImageRenderer.createDraft(
      sourceBytes: sourceBytes,
      sourceName: 'camera.jpg',
      sourceMimeType: 'image/jpeg',
      previewOnly: true,
    );

    final preview = img.decodePng(draft.baseBytes);
    expect(preview, isNotNull);
    expect(preview!.width, storyEditorPreviewWidth);
    expect(preview.height, storyEditorPreviewHeight);
    expect(draft.baseIsPreviewOnly, isTrue);
    expect(draft.imageFitMode, StoryImageFitMode.contain);

    final fullSizeBase = img.decodePng(
      StoryImageRenderer.normalizeToStoryCanvas(sourceBytes),
    );
    expect(fullSizeBase, isNotNull);
    expect(fullSizeBase!.width, storyEditorOutputWidth);
    expect(fullSizeBase.height, storyEditorOutputHeight);
  });

  test('async normalization preserves fit backgrounds', () async {
    final sourceBytes = _solidPng(width: 320, height: 180);

    final baseBytes = await StoryImageRenderer.normalizeToStoryCanvasAsync(
      sourceBytes,
      imageFitMode: StoryImageFitMode.contain,
      backgroundColor: const Color(0xFF4DD0E1),
    );

    final decoded = img.decodePng(baseBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, storyEditorOutputWidth);
    expect(decoded.height, storyEditorOutputHeight);
    expect(decoded.getPixel(0, 0).r, 77);
    expect(decoded.getPixel(0, 0).g, 208);
    expect(decoded.getPixel(0, 0).b, 225);
  });
}

Uint8List _solidPng({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodePng(image));
}
