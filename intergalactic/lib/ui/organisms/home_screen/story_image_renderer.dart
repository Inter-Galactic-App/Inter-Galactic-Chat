import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_filter.dart';
import 'package:intergalactic/utils/text_utils.dart';

const int storyEditorPreviewWidth = 270;
const int storyEditorPreviewHeight = 480;

Map<String, Object?> _createStoryCanvasForDraft(Map<String, Object?> request) {
  final sourceBytes = request['sourceBytes'] as Uint8List;
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const StoryImageRenderException('Unsupported story image.');
  }
  final oriented = img.bakeOrientation(decoded);
  final requestedFitMode = _decodeStoryImageFitMode(request['imageFitMode']);
  final fitMode =
      requestedFitMode ?? _defaultStoryImageFitModeForSource(oriented);
  return <String, Object?>{
    'baseBytes': StoryImageRenderer.normalizeOrientedToStoryCanvas(
      oriented,
      width: request['width'] as int? ?? storyEditorOutputWidth,
      height: request['height'] as int? ?? storyEditorOutputHeight,
      imageFitMode: fitMode,
      backgroundColor: _decodeColor(
        request['backgroundColor'],
        const Color(0xFF000000),
      ),
      backgroundGradientColor: _decodeColor(
        request['backgroundGradientColor'],
        const Color(0xFF2E2E38),
      ),
      backgroundMode: _decodeStoryCanvasBackgroundMode(
        request['backgroundMode'],
      ),
    ),
    'imageFitMode': fitMode.name,
  };
}

Uint8List _normalizeStoryCanvasForDraft(Map<String, Object?> request) {
  return (_createStoryCanvasForDraft(request)['baseBytes'] as Uint8List);
}

Uint8List _blankStoryCanvasForDraft(Map<String, Object?> request) {
  return StoryImageRenderer.blankStoryCanvas(
    backgroundColor: _decodeColor(
      request['backgroundColor'],
      const Color(0xFF000000),
    ),
    backgroundGradientColor: _decodeColor(
      request['backgroundGradientColor'],
      const Color(0xFF2E2E38),
    ),
    backgroundMode: _decodeStoryCanvasBackgroundMode(request['backgroundMode']),
  );
}

StoryImageFitMode? _decodeStoryImageFitMode(Object? value) {
  if (value is String) {
    for (final mode in StoryImageFitMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
  }
  return null;
}

StoryImageFitMode _defaultStoryImageFitModeForSource(img.Image oriented) {
  return oriented.width > oriented.height
      ? StoryImageFitMode.contain
      : StoryImageFitMode.cover;
}

StoryCanvasBackgroundMode _decodeStoryCanvasBackgroundMode(Object? value) {
  if (value is String) {
    for (final mode in StoryCanvasBackgroundMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
  }
  return StoryCanvasBackgroundMode.solid;
}

Color _decodeColor(Object? value, Color fallback) {
  return value is int ? Color(value) : fallback;
}

int _encodeColor(Color color) {
  final a = (color.a * 255).round().clamp(0, 255).toInt();
  final r = (color.r * 255).round().clamp(0, 255).toInt();
  final g = (color.g * 255).round().clamp(0, 255).toInt();
  final b = (color.b * 255).round().clamp(0, 255).toInt();
  return (a << 24) | (r << 16) | (g << 8) | b;
}

class StoryImageRenderException implements Exception {
  const StoryImageRenderException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return message;
    }
    return '$message ($cause)';
  }
}

class StoryImageRenderer {
  const StoryImageRenderer();

  static Future<StoryDraft> createDraft({
    required Uint8List sourceBytes,
    required String sourceName,
    String? sourceMimeType,
    StoryImageFitMode? imageFitMode,
    Color backgroundColor = const Color(0xFF000000),
    Color backgroundGradientColor = const Color(0xFF2E2E38),
    StoryCanvasBackgroundMode backgroundMode = StoryCanvasBackgroundMode.solid,
    bool previewOnly = false,
  }) async {
    final width = previewOnly
        ? storyEditorPreviewWidth
        : storyEditorOutputWidth;
    final height = previewOnly
        ? storyEditorPreviewHeight
        : storyEditorOutputHeight;
    final renderResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
          _createStoryCanvasForDraft,
          <String, Object?>{
            'sourceBytes': sourceBytes,
            'width': width,
            'height': height,
            'imageFitMode': imageFitMode?.name,
            'backgroundColor': _encodeColor(backgroundColor),
            'backgroundGradientColor': _encodeColor(backgroundGradientColor),
            'backgroundMode': backgroundMode.name,
          },
        );
    final effectiveFitMode =
        _decodeStoryImageFitMode(renderResult['imageFitMode']) ??
        imageFitMode ??
        StoryImageFitMode.cover;
    final baseBytes = renderResult['baseBytes'] as Uint8List;
    return StoryDraft(
      id: createStoryDraftId(),
      sourceBytes: sourceBytes,
      baseBytes: baseBytes,
      sourceName: sourceName,
      sourceMimeType: sourceMimeType,
      previewBytes: baseBytes,
      baseIsPreviewOnly: previewOnly,
      imageFitMode: effectiveFitMode,
      backgroundColor: backgroundColor,
      backgroundGradientColor: backgroundGradientColor,
      backgroundMode: backgroundMode,
    );
  }

  static Future<StoryDraft> createTextDraft({
    String sourceName = 'text-story.png',
    Color backgroundColor = const Color(0xFF000000),
    Color backgroundGradientColor = const Color(0xFF2E2E38),
    StoryCanvasBackgroundMode backgroundMode = StoryCanvasBackgroundMode.solid,
  }) async {
    final sourceBytes = _transparentPixelPng();
    final baseBytes = blankStoryCanvas(
      backgroundColor: backgroundColor,
      backgroundGradientColor: backgroundGradientColor,
      backgroundMode: backgroundMode,
    );
    return StoryDraft(
      id: createStoryDraftId(),
      sourceBytes: sourceBytes,
      baseBytes: baseBytes,
      sourceName: sourceName,
      sourceMimeType: 'image/png',
      previewBytes: baseBytes,
      imageFitMode: StoryImageFitMode.contain,
      backgroundColor: backgroundColor,
      backgroundGradientColor: backgroundGradientColor,
      backgroundMode: backgroundMode,
      isTextOnly: true,
    );
  }

  static Uint8List blankStoryCanvas({
    Color backgroundColor = const Color(0xFF000000),
    Color backgroundGradientColor = const Color(0xFF2E2E38),
    StoryCanvasBackgroundMode backgroundMode = StoryCanvasBackgroundMode.solid,
  }) {
    final canvas = img.Image(
      width: storyEditorOutputWidth,
      height: storyEditorOutputHeight,
    );
    _fillStoryBackground(
      canvas,
      backgroundColor: backgroundColor,
      backgroundGradientColor: backgroundGradientColor,
      backgroundMode: backgroundMode,
    );
    return Uint8List.fromList(img.encodePng(canvas));
  }

  static Future<Uint8List> blankStoryCanvasAsync({
    Color backgroundColor = const Color(0xFF000000),
    Color backgroundGradientColor = const Color(0xFF2E2E38),
    StoryCanvasBackgroundMode backgroundMode = StoryCanvasBackgroundMode.solid,
  }) {
    return compute<Map<String, Object?>, Uint8List>(
      _blankStoryCanvasForDraft,
      <String, Object?>{
        'backgroundColor': _encodeColor(backgroundColor),
        'backgroundGradientColor': _encodeColor(backgroundGradientColor),
        'backgroundMode': backgroundMode.name,
      },
    );
  }

  static Uint8List _transparentPixelPng() {
    final image = img.Image(width: 1, height: 1, numChannels: 4);
    image.setPixelRgba(0, 0, 0, 0, 0, 0);
    return Uint8List.fromList(img.encodePng(image));
  }

  static Uint8List normalizeToStoryCanvas(
    Uint8List sourceBytes, {
    int width = storyEditorOutputWidth,
    int height = storyEditorOutputHeight,
    StoryImageFitMode imageFitMode = StoryImageFitMode.cover,
    Color backgroundColor = const Color(0xFF000000),
    Color backgroundGradientColor = const Color(0xFF2E2E38),
    StoryCanvasBackgroundMode backgroundMode = StoryCanvasBackgroundMode.solid,
  }) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const StoryImageRenderException('Unsupported story image.');
    }

    final oriented = img.bakeOrientation(decoded);
    return switch (imageFitMode) {
      StoryImageFitMode.cover => _normalizeCoverToStoryCanvas(
        oriented,
        width: width,
        height: height,
      ),
      StoryImageFitMode.contain => _normalizeContainToStoryCanvas(
        oriented,
        backgroundColor,
        backgroundGradientColor,
        backgroundMode,
        width: width,
        height: height,
      ),
    };
  }

  static Future<Uint8List> normalizeToStoryCanvasAsync(
    Uint8List sourceBytes, {
    int width = storyEditorOutputWidth,
    int height = storyEditorOutputHeight,
    StoryImageFitMode imageFitMode = StoryImageFitMode.cover,
    Color backgroundColor = const Color(0xFF000000),
    Color backgroundGradientColor = const Color(0xFF2E2E38),
    StoryCanvasBackgroundMode backgroundMode = StoryCanvasBackgroundMode.solid,
  }) {
    return compute<Map<String, Object?>, Uint8List>(
      _normalizeStoryCanvasForDraft,
      <String, Object?>{
        'sourceBytes': sourceBytes,
        'width': width,
        'height': height,
        'imageFitMode': imageFitMode.name,
        'backgroundColor': _encodeColor(backgroundColor),
        'backgroundGradientColor': _encodeColor(backgroundGradientColor),
        'backgroundMode': backgroundMode.name,
      },
    );
  }

  @visibleForTesting
  static Uint8List normalizeOrientedToStoryCanvas(
    img.Image oriented, {
    int width = storyEditorOutputWidth,
    int height = storyEditorOutputHeight,
    required StoryImageFitMode imageFitMode,
    Color backgroundColor = const Color(0xFF000000),
    Color backgroundGradientColor = const Color(0xFF2E2E38),
    StoryCanvasBackgroundMode backgroundMode = StoryCanvasBackgroundMode.solid,
  }) {
    return switch (imageFitMode) {
      StoryImageFitMode.cover => _normalizeCoverToStoryCanvas(
        oriented,
        width: width,
        height: height,
      ),
      StoryImageFitMode.contain => _normalizeContainToStoryCanvas(
        oriented,
        backgroundColor,
        backgroundGradientColor,
        backgroundMode,
        width: width,
        height: height,
      ),
    };
  }

  static Uint8List _normalizeCoverToStoryCanvas(
    img.Image oriented, {
    required int width,
    required int height,
  }) {
    final sourceRatio = oriented.width / oriented.height;
    final targetRatio = width / height;

    late final int cropWidth;
    late final int cropHeight;
    if (sourceRatio > targetRatio) {
      cropHeight = oriented.height;
      cropWidth = math.max(1, (cropHeight * targetRatio).round());
    } else {
      cropWidth = oriented.width;
      cropHeight = math.max(1, (cropWidth / targetRatio).round());
    }

    final cropX = math.max(0, ((oriented.width - cropWidth) / 2).round());
    final cropY = math.max(0, ((oriented.height - cropHeight) / 2).round());
    final cropped = img.copyCrop(
      oriented,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );
    final resized = img.copyResize(
      cropped,
      width: width,
      height: height,
      interpolation: img.Interpolation.cubic,
    );

    return Uint8List.fromList(img.encodePng(resized));
  }

  static Uint8List _normalizeContainToStoryCanvas(
    img.Image oriented,
    Color backgroundColor,
    Color backgroundGradientColor,
    StoryCanvasBackgroundMode backgroundMode, {
    required int width,
    required int height,
  }) {
    final canvas = img.Image(width: width, height: height);
    _fillStoryBackground(
      canvas,
      backgroundColor: backgroundColor,
      backgroundGradientColor: backgroundGradientColor,
      backgroundMode: backgroundMode,
    );

    final scale = math.min(width / oriented.width, height / oriented.height);
    final fittedWidth = math.max(1, (oriented.width * scale).round());
    final fittedHeight = math.max(1, (oriented.height * scale).round());
    final fitted = img.copyResize(
      oriented,
      width: fittedWidth,
      height: fittedHeight,
      interpolation: img.Interpolation.cubic,
    );
    img.compositeImage(
      canvas,
      fitted,
      dstX: ((width - fittedWidth) / 2).round(),
      dstY: ((height - fittedHeight) / 2).round(),
    );

    return Uint8List.fromList(img.encodePng(canvas));
  }

  Future<StoryPhotoUpload> renderUpload(StoryDraft draft) async {
    final bytes = await renderPngBytes(draft);
    if (!storyImageSizeIsAllowed(bytes.lengthInBytes)) {
      throw const StoryImageRenderException(
        'Rendered story image is larger than the story limit.',
      );
    }

    return StoryPhotoUpload(
      bytes: bytes,
      name: _storyFileName(draft.sourceName),
      mimeType: 'image/png',
      mentionedUserIds: draft.visualMentionUserIds,
    );
  }

  Future<Uint8List> renderPreviewBytes(StoryDraft draft) {
    return renderPngBytes(
      draft,
      width: storyEditorPreviewWidth,
      height: storyEditorPreviewHeight,
    );
  }

  Future<Uint8List> renderPngBytes(
    StoryDraft draft, {
    int width = storyEditorOutputWidth,
    int height = storyEditorOutputHeight,
  }) async {
    final baseBytes = await _baseBytesForRender(draft, width, height);
    final baseImage = await _decodeUiImage(baseBytes);
    final stickerImages = <String, ui.Image>{};
    try {
      for (final overlay in draft.overlays) {
        if (overlay is StoryStickerOverlay) {
          stickerImages[overlay.id] = await _resolveImageProvider(
            overlay.image,
          );
        }
      }

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(
        width / storyEditorOutputWidth,
        height / storyEditorOutputHeight,
      );
      _paintDraft(
        canvas: canvas,
        draft: draft,
        baseImage: baseImage,
        stickerImages: stickerImages,
      );
      ui.Picture? picture;
      ui.Image? outputImage;
      try {
        picture = recorder.endRecording();
        outputImage = await picture.toImage(width, height);
        final data = await outputImage.toByteData(
          format: ui.ImageByteFormat.png,
        );

        if (data == null) {
          throw const StoryImageRenderException('Story image render failed.');
        }
        return Uint8List.sublistView(data);
      } finally {
        outputImage?.dispose();
        picture?.dispose();
      }
    } on StoryImageRenderException {
      rethrow;
    } catch (error) {
      throw StoryImageRenderException('Story image render failed.', error);
    } finally {
      for (final image in stickerImages.values) {
        image.dispose();
      }
      baseImage.dispose();
    }
  }

  Future<Uint8List> _baseBytesForRender(
    StoryDraft draft,
    int width,
    int height,
  ) async {
    if (!draft.baseIsPreviewOnly ||
        width != storyEditorOutputWidth ||
        height != storyEditorOutputHeight) {
      return draft.baseBytes;
    }

    return compute<Map<String, Object?>, Uint8List>(
      _normalizeStoryCanvasForDraft,
      <String, Object?>{
        'sourceBytes': draft.sourceBytes,
        'width': storyEditorOutputWidth,
        'height': storyEditorOutputHeight,
        'imageFitMode': draft.imageFitMode.name,
        'backgroundColor': _encodeColor(draft.backgroundColor),
        'backgroundGradientColor': _encodeColor(draft.backgroundGradientColor),
        'backgroundMode': draft.backgroundMode.name,
      },
    );
  }

  static void _paintDraft({
    required ui.Canvas canvas,
    required StoryDraft draft,
    required ui.Image baseImage,
    required Map<String, ui.Image> stickerImages,
  }) {
    final basePaint = ui.Paint()
      ..isAntiAlias = true
      ..colorFilter = ui.ColorFilter.matrix(
        storyFilterMatrix(draft.filterPreset, intensity: draft.filterIntensity),
      );
    _paintCanvasBackground(canvas, draft);
    canvas.drawImageRect(
      baseImage,
      ui.Rect.fromLTWH(
        0,
        0,
        baseImage.width.toDouble(),
        baseImage.height.toDouble(),
      ),
      ui.Rect.fromLTWH(
        0,
        0,
        storyEditorOutputWidth.toDouble(),
        storyEditorOutputHeight.toDouble(),
      ),
      basePaint,
    );

    for (final overlay in draft.overlays) {
      switch (overlay) {
        case StoryTextOverlay():
          _paintTextOverlay(canvas, overlay);
        case StoryEmojiOverlay():
          _paintEmojiOverlay(canvas, overlay);
        case StoryStickerOverlay():
          final stickerImage = stickerImages[overlay.id];
          if (stickerImage == null) {
            throw StoryImageRenderException(
              'Could not load sticker ${overlay.label}.',
            );
          }
          _paintStickerOverlay(canvas, overlay, stickerImage);
        case StoryMentionOverlay():
          _paintMentionOverlay(canvas, overlay);
      }
    }
  }

  static void _paintCanvasBackground(ui.Canvas canvas, StoryDraft draft) {
    final rect = ui.Rect.fromLTWH(
      0,
      0,
      storyEditorOutputWidth.toDouble(),
      storyEditorOutputHeight.toDouble(),
    );
    final paint = ui.Paint()..isAntiAlias = true;
    switch (draft.backgroundMode) {
      case StoryCanvasBackgroundMode.solid:
        paint.color = draft.backgroundColor;
      case StoryCanvasBackgroundMode.gradient:
        paint.shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          draft.backgroundColor,
          draft.backgroundGradientColor,
        ]);
    }
    canvas.drawRect(rect, paint);
  }

  static void _paintTextOverlay(ui.Canvas canvas, StoryTextOverlay overlay) {
    final textStyle = TextStyle(
      color: overlay.color,
      fontSize: overlay.fontSize,
      fontWeight: overlay.isBold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: overlay.isItalic ? FontStyle.italic : FontStyle.normal,
      shadows: const [
        Shadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 3)),
      ],
    );
    final painter = TextPainter(
      text: TextSpan(
        children: TextUtils.nativeEmojiTextSpans(
          overlay.text,
          style: textStyle,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: storyEditorOutputWidth * 0.86);

    canvas.save();
    canvas.translate(
      overlay.center.dx * storyEditorOutputWidth,
      overlay.center.dy * storyEditorOutputHeight,
    );
    canvas.rotate(overlay.rotationRadians);
    canvas.scale(overlay.scale, overlay.scale);
    final backgroundColor = overlay.backgroundColor;
    if (backgroundColor != null) {
      const horizontalPadding = 28.0;
      const verticalPadding = 16.0;
      final rect = ui.Rect.fromLTWH(
        -painter.width / 2 - horizontalPadding,
        -painter.height / 2 - verticalPadding,
        painter.width + horizontalPadding * 2,
        painter.height + verticalPadding * 2,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(30)),
        ui.Paint()
          ..isAntiAlias = true
          ..color = backgroundColor,
      );
    }
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  static void _paintEmojiOverlay(ui.Canvas canvas, StoryEmojiOverlay overlay) {
    final emojiStyle = TextUtils.withNativeEmojiFallback(
      TextStyle(
        fontSize: overlay.fontSize,
        shadows: const [
          Shadow(color: Colors.black87, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
    );
    final painter = TextPainter(
      text: TextSpan(text: overlay.emoji, style: emojiStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: storyEditorOutputWidth * 0.9);

    canvas.save();
    canvas.translate(
      overlay.center.dx * storyEditorOutputWidth,
      overlay.center.dy * storyEditorOutputHeight,
    );
    canvas.rotate(overlay.rotationRadians);
    canvas.scale(overlay.scale, overlay.scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  static void _paintStickerOverlay(
    ui.Canvas canvas,
    StoryStickerOverlay overlay,
    ui.Image image,
  ) {
    final size = overlay.size;
    canvas.save();
    canvas.translate(
      overlay.center.dx * storyEditorOutputWidth,
      overlay.center.dy * storyEditorOutputHeight,
    );
    canvas.rotate(overlay.rotationRadians);
    canvas.scale(overlay.scale, overlay.scale);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromCenter(center: ui.Offset.zero, width: size, height: size),
      ui.Paint()
        ..isAntiAlias = true
        ..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
  }

  static void _paintMentionOverlay(
    ui.Canvas canvas,
    StoryMentionOverlay overlay,
  ) {
    final mentionStyle = TextStyle(
      color: overlay.foregroundColor,
      fontSize: overlay.fontSize,
      fontWeight: FontWeight.w800,
      shadows: const [
        Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
      ],
    );
    final painter = TextPainter(
      text: TextSpan(
        children: TextUtils.nativeEmojiTextSpans(
          overlay.label,
          style: mentionStyle,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: storyEditorOutputWidth * 0.72);

    canvas.save();
    canvas.translate(
      overlay.center.dx * storyEditorOutputWidth,
      overlay.center.dy * storyEditorOutputHeight,
    );
    canvas.rotate(overlay.rotationRadians);
    canvas.scale(overlay.scale, overlay.scale);
    const horizontalPadding = 38.0;
    const verticalPadding = 18.0;
    final rect = ui.Rect.fromLTWH(
      -painter.width / 2 - horizontalPadding,
      -painter.height / 2 - verticalPadding,
      painter.width + horizontalPadding * 2,
      painter.height + verticalPadding * 2,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(999)),
      ui.Paint()
        ..isAntiAlias = true
        ..color = overlay.backgroundColor,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(999)),
      ui.Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.24),
    );
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  static void _fillStoryBackground(
    img.Image image, {
    required Color backgroundColor,
    required Color backgroundGradientColor,
    required StoryCanvasBackgroundMode backgroundMode,
  }) {
    switch (backgroundMode) {
      case StoryCanvasBackgroundMode.solid:
        img.fill(image, color: _imageColor(backgroundColor));
      case StoryCanvasBackgroundMode.gradient:
        _fillVerticalGradient(
          image,
          startColor: backgroundColor,
          endColor: backgroundGradientColor,
        );
    }
  }

  static void _fillVerticalGradient(
    img.Image image, {
    required Color startColor,
    required Color endColor,
  }) {
    final heightMax = math.max(1, image.height - 1);
    for (var y = 0; y < image.height; y++) {
      final t = y / heightMax;
      final r = _lerpColorComponent(startColor.r, endColor.r, t);
      final g = _lerpColorComponent(startColor.g, endColor.g, t);
      final b = _lerpColorComponent(startColor.b, endColor.b, t);
      final a = _lerpColorComponent(startColor.a, endColor.a, t);
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }
  }

  static Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static img.Color _imageColor(Color color) {
    return img.ColorRgba8(
      _colorComponent(color.r),
      _colorComponent(color.g),
      _colorComponent(color.b),
      _colorComponent(color.a),
    );
  }

  static int _colorComponent(double value) {
    return (value * 255).round().clamp(0, 255).toInt();
  }

  static int _lerpColorComponent(double start, double end, double t) {
    return _colorComponent(start + (end - start) * t);
  }

  static Future<ui.Image> _resolveImageProvider(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(info.image);
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw const StoryImageRenderException('Sticker image timed out.'),
    );
  }

  static String _storyFileName(String sourceName) {
    final name = sourceName.trim();
    if (name.isEmpty) {
      return 'story.png';
    }
    final slash = math.max(name.lastIndexOf('/'), name.lastIndexOf(r'\'));
    final fileName = slash >= 0 ? name.substring(slash + 1) : name;
    final dot = fileName.lastIndexOf('.');
    final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;
    final safeBase = baseName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return '${safeBase.isEmpty ? 'story' : safeBase}-story.png';
  }
}
