import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_filter.dart';

const int storyEditorOutputWidth = 1080;
const int storyEditorOutputHeight = 1920;
const double storyEditorAspectRatio =
    storyEditorOutputWidth / storyEditorOutputHeight;
const double storyOverlayKeyboardMoveStep = 0.04;

int _storyDraftIdSeed = 0;

const Object _storyOverlayUnset = Object();

String createStoryDraftId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_storyDraftIdSeed++}';

Offset storyOverlayMovedCenter({
  required Offset center,
  required Offset delta,
  double min = 0.04,
  double max = 0.96,
}) {
  final lower = min.clamp(0.0, 1.0).toDouble();
  final upper = max.clamp(lower, 1.0).toDouble();
  return Offset(
    (center.dx + delta.dx).clamp(lower, upper).toDouble(),
    (center.dy + delta.dy).clamp(lower, upper).toDouble(),
  );
}

enum StoryImageFitMode { cover, contain }

enum StoryCanvasBackgroundMode { solid, gradient }

class StoryGradientPreset {
  const StoryGradientPreset(this.startColor, this.endColor);

  final Color startColor;
  final Color endColor;
}

const List<Color> storyEditorBackgroundColors = [
  Color(0xFF000000),
  Color(0xFFFFFFFF),
  Color(0xFF2E2E38),
  Color(0xFFFFD54F),
  Color(0xFFFF6B6B),
  Color(0xFFFF8A65),
  Color(0xFF4DD0E1),
  Color(0xFF4DB6AC),
  Color(0xFF81C784),
  Color(0xFF64B5F6),
  Color(0xFF7986CB),
  Color(0xFFCE93D8),
  Color(0xFFF06292),
];

const List<StoryGradientPreset> storyEditorBackgroundGradientPresets = [
  StoryGradientPreset(Color(0xFF111827), Color(0xFF4DD0E1)),
  StoryGradientPreset(Color(0xFF2E1065), Color(0xFFF06292)),
  StoryGradientPreset(Color(0xFF0F172A), Color(0xFF81C784)),
  StoryGradientPreset(Color(0xFFFF6B6B), Color(0xFFFFD54F)),
  StoryGradientPreset(Color(0xFF1B5E20), Color(0xFF64B5F6)),
  StoryGradientPreset(Color(0xFF2E2E38), Color(0xFFCE93D8)),
];

class StoryDraft {
  StoryDraft({
    required this.id,
    required Uint8List sourceBytes,
    required Uint8List baseBytes,
    required this.sourceName,
    this.sourceMimeType,
    List<StoryOverlay> overlays = const [],
    Uint8List? previewBytes,
    this.baseIsPreviewOnly = false,
    this.rotationTurns = 0,
    this.imageFitMode = StoryImageFitMode.cover,
    this.backgroundColor = const Color(0xFF000000),
    this.backgroundGradientColor = const Color(0xFF2E2E38),
    this.backgroundMode = StoryCanvasBackgroundMode.solid,
    this.filterPreset = StoryFilterPreset.original,
    this.filterIntensity = 1,
    this.isTextOnly = false,
  }) : sourceBytes = Uint8List.fromList(sourceBytes),
       baseBytes = Uint8List.fromList(baseBytes),
       overlays = List.unmodifiable(overlays),
       previewBytes = previewBytes == null
           ? null
           : Uint8List.fromList(previewBytes);

  final String id;
  final Uint8List sourceBytes;
  final Uint8List baseBytes;
  final String sourceName;
  final String? sourceMimeType;
  final List<StoryOverlay> overlays;
  final Uint8List? previewBytes;
  final bool baseIsPreviewOnly;
  final int rotationTurns;
  final StoryImageFitMode imageFitMode;
  final Color backgroundColor;
  final Color backgroundGradientColor;
  final StoryCanvasBackgroundMode backgroundMode;
  final StoryFilterPreset filterPreset;
  final double filterIntensity;
  final bool isTextOnly;

  List<String> get visualMentionUserIds {
    final userIds = <String>{};
    for (final overlay in overlays) {
      if (overlay is StoryMentionOverlay) {
        userIds.add(overlay.userId);
      }
    }
    return List.unmodifiable(userIds);
  }

  StoryDraft copyWith({
    Uint8List? sourceBytes,
    Uint8List? baseBytes,
    String? sourceName,
    String? sourceMimeType,
    List<StoryOverlay>? overlays,
    Uint8List? previewBytes,
    bool? baseIsPreviewOnly,
    int? rotationTurns,
    StoryImageFitMode? imageFitMode,
    Color? backgroundColor,
    Color? backgroundGradientColor,
    StoryCanvasBackgroundMode? backgroundMode,
    StoryFilterPreset? filterPreset,
    double? filterIntensity,
    bool? isTextOnly,
  }) {
    return StoryDraft(
      id: id,
      sourceBytes: sourceBytes ?? this.sourceBytes,
      baseBytes: baseBytes ?? this.baseBytes,
      sourceName: sourceName ?? this.sourceName,
      sourceMimeType: sourceMimeType ?? this.sourceMimeType,
      overlays: overlays ?? this.overlays,
      previewBytes: previewBytes ?? this.previewBytes,
      baseIsPreviewOnly:
          baseIsPreviewOnly ??
          (baseBytes == null ? this.baseIsPreviewOnly : false),
      rotationTurns: rotationTurns ?? this.rotationTurns,
      imageFitMode: imageFitMode ?? this.imageFitMode,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundGradientColor:
          backgroundGradientColor ?? this.backgroundGradientColor,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      filterPreset: filterPreset ?? this.filterPreset,
      filterIntensity: filterIntensity ?? this.filterIntensity,
      isTextOnly: isTextOnly ?? this.isTextOnly,
    );
  }

  StoryDraft replaceOverlay(StoryOverlay overlay) {
    return copyWith(
      overlays: overlays
          .map((existing) => existing.id == overlay.id ? overlay : existing)
          .toList(growable: false),
    );
  }

  StoryDraft removeOverlay(String overlayId) {
    return copyWith(
      overlays: overlays
          .where((overlay) => overlay.id != overlayId)
          .toList(growable: false),
    );
  }

  StoryDraft addOverlay(StoryOverlay overlay) {
    return copyWith(overlays: [...overlays, overlay]);
  }
}

class StoryVideoDraft {
  StoryVideoDraft({
    required this.id,
    required this.path,
    required this.sourceName,
    required this.sizeBytes,
    required this.duration,
    this.sourceMimeType,
    this.width,
    this.height,
    Uint8List? thumbnailBytes,
    this.thumbnailMimeType,
    this.trimStart = Duration.zero,
    Duration? trimEnd,
    List<StoryOverlay> overlays = const [],
    Map<String, Uri> stickerMediaUris = const {},
    this.backgroundColor = const Color(storyDefaultVideoBackgroundColor),
    this.backgroundGradientColor = const Color(
      storyDefaultVideoBackgroundGradientColor,
    ),
    this.backgroundMode = StoryBackgroundMode.solid,
    this.fitMode = StoryVideoFitMode.fit,
    this.canvasMode = StoryVideoCanvasMode.portrait,
    this.displayWidth,
    this.displayHeight,
    this.hasBakedLetterbox = false,
    this.preparedForDecoration = true,
  }) : trimEnd = trimEnd ?? duration,
       overlays = List.unmodifiable(overlays),
       stickerMediaUris = Map.unmodifiable(stickerMediaUris),
       thumbnailBytes = thumbnailBytes == null
           ? null
           : Uint8List.fromList(thumbnailBytes);

  final String id;
  final String path;
  final String sourceName;
  final String? sourceMimeType;
  final int sizeBytes;
  final Duration duration;
  final int? width;
  final int? height;
  final Uint8List? thumbnailBytes;
  final String? thumbnailMimeType;
  final Duration trimStart;
  final Duration trimEnd;
  final List<StoryOverlay> overlays;
  final Map<String, Uri> stickerMediaUris;
  final Color backgroundColor;
  final Color backgroundGradientColor;
  final StoryBackgroundMode backgroundMode;
  final StoryVideoFitMode fitMode;
  final StoryVideoCanvasMode canvasMode;
  final int? displayWidth;
  final int? displayHeight;
  final bool hasBakedLetterbox;
  final bool preparedForDecoration;

  Duration get selectedDuration => trimEnd - trimStart;

  bool get usesFullSource => trimStart == Duration.zero && trimEnd == duration;

  List<String> get visualMentionUserIds {
    final userIds = <String>{};
    for (final overlay in overlays) {
      if (overlay is StoryMentionOverlay) {
        userIds.add(overlay.userId);
      }
    }
    return List.unmodifiable(userIds);
  }

  StoryVideoDraft copyWith({
    String? path,
    String? sourceName,
    String? sourceMimeType,
    int? sizeBytes,
    Duration? duration,
    int? width,
    int? height,
    Uint8List? thumbnailBytes,
    String? thumbnailMimeType,
    Duration? trimStart,
    Duration? trimEnd,
    List<StoryOverlay>? overlays,
    Map<String, Uri>? stickerMediaUris,
    Color? backgroundColor,
    Color? backgroundGradientColor,
    StoryBackgroundMode? backgroundMode,
    StoryVideoFitMode? fitMode,
    StoryVideoCanvasMode? canvasMode,
    Object? displayWidth = _storyOverlayUnset,
    Object? displayHeight = _storyOverlayUnset,
    bool? hasBakedLetterbox,
    bool? preparedForDecoration,
  }) {
    return StoryVideoDraft(
      id: id,
      path: path ?? this.path,
      sourceName: sourceName ?? this.sourceName,
      sourceMimeType: sourceMimeType ?? this.sourceMimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      thumbnailMimeType: thumbnailMimeType ?? this.thumbnailMimeType,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      overlays: overlays ?? this.overlays,
      stickerMediaUris: stickerMediaUris ?? this.stickerMediaUris,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundGradientColor:
          backgroundGradientColor ?? this.backgroundGradientColor,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      fitMode: fitMode ?? this.fitMode,
      canvasMode: canvasMode ?? this.canvasMode,
      displayWidth: identical(displayWidth, _storyOverlayUnset)
          ? this.displayWidth
          : displayWidth as int?,
      displayHeight: identical(displayHeight, _storyOverlayUnset)
          ? this.displayHeight
          : displayHeight as int?,
      hasBakedLetterbox: hasBakedLetterbox ?? this.hasBakedLetterbox,
      preparedForDecoration:
          preparedForDecoration ?? this.preparedForDecoration,
    );
  }

  StoryVideoDraft replaceOverlay(StoryOverlay overlay) {
    return copyWith(
      overlays: overlays
          .map((existing) => existing.id == overlay.id ? overlay : existing)
          .toList(growable: false),
    );
  }

  StoryVideoDraft removeOverlay(String overlayId) {
    final nextStickerUris = Map<String, Uri>.of(stickerMediaUris)
      ..remove(overlayId);
    return copyWith(
      overlays: overlays
          .where((overlay) => overlay.id != overlayId)
          .toList(growable: false),
      stickerMediaUris: nextStickerUris,
    );
  }

  StoryVideoDraft addOverlay(StoryOverlay overlay, {Uri? stickerMediaUri}) {
    return copyWith(
      overlays: [...overlays, overlay],
      stickerMediaUris: stickerMediaUri == null
          ? stickerMediaUris
          : {...stickerMediaUris, overlay.id: stickerMediaUri},
    );
  }

  StoryVideoUpload toUpload({Iterable<String> mentionedUserIds = const []}) {
    final mergedMentionedUserIds = normalizeStoryMentionUserIds([
      ...mentionedUserIds,
      ...visualMentionUserIds,
    ]);
    return StoryVideoUpload(
      path: path,
      name: sourceName,
      mimeType: sourceMimeType,
      sizeBytes: sizeBytes,
      duration: duration,
      width: width,
      height: height,
      thumbnailBytes: thumbnailBytes,
      thumbnailMimeType: thumbnailMimeType,
      trimStart: trimStart,
      trimEnd: trimEnd,
      overlays: overlays
          .map(_storyOverlayToMediaOverlay)
          .whereType<StoryMediaOverlay>()
          .toList(growable: false),
      mentionedUserIds: mergedMentionedUserIds,
      backgroundColor: backgroundColor.toARGB32(),
      backgroundGradientColor: backgroundGradientColor.toARGB32(),
      backgroundMode: backgroundMode,
      fitMode: fitMode,
      canvasMode: StoryVideoCanvasMode.portrait,
      displayWidth: displayWidth,
      displayHeight: displayHeight,
      hasBakedLetterbox: hasBakedLetterbox,
    );
  }

  StoryMediaOverlay? _storyOverlayToMediaOverlay(StoryOverlay overlay) {
    final base = _StoryOverlayExportTransform(
      x: overlay.center.dx,
      y: overlay.center.dy,
      scale: overlay.scale,
      rotationRadians: overlay.rotationRadians,
    );
    switch (overlay) {
      case StoryTextOverlay():
        final textOverlay = overlay;
        return StoryMediaOverlay(
          id: textOverlay.id,
          type: StoryMediaOverlayType.text,
          content: textOverlay.text,
          x: base.x,
          y: base.y,
          scale: base.scale,
          rotationRadians: base.rotationRadians,
          color: textOverlay.color.toARGB32(),
          backgroundColor: textOverlay.backgroundColor?.toARGB32(),
          fontSize: textOverlay.fontSize,
          bold: textOverlay.isBold,
          italic: textOverlay.isItalic,
        );
      case StoryEmojiOverlay():
        final emojiOverlay = overlay;
        return StoryMediaOverlay(
          id: emojiOverlay.id,
          type: StoryMediaOverlayType.emoji,
          content: emojiOverlay.emoji,
          x: base.x,
          y: base.y,
          scale: base.scale,
          rotationRadians: base.rotationRadians,
          fontSize: emojiOverlay.fontSize,
        );
      case StoryStickerOverlay():
        final stickerOverlay = overlay;
        return StoryMediaOverlay(
          id: stickerOverlay.id,
          type: StoryMediaOverlayType.sticker,
          content: stickerOverlay.label,
          mediaUri: stickerMediaUris[stickerOverlay.id],
          x: base.x,
          y: base.y,
          scale: base.scale,
          rotationRadians: base.rotationRadians,
          fontSize: stickerOverlay.size,
        );
      case StoryMentionOverlay():
        return null;
    }
  }
}

class _StoryOverlayExportTransform {
  const _StoryOverlayExportTransform({
    required this.x,
    required this.y,
    required this.scale,
    required this.rotationRadians,
  });

  final double x;
  final double y;
  final double scale;
  final double rotationRadians;
}

sealed class StoryOverlay {
  const StoryOverlay({
    required this.id,
    required this.center,
    this.scale = 1,
    this.rotationRadians = 0,
  });

  final String id;
  final Offset center;
  final double scale;
  final double rotationRadians;

  StoryOverlay copyWithTransform({
    Offset? center,
    double? scale,
    double? rotationRadians,
  });
}

class StoryTextOverlay extends StoryOverlay {
  const StoryTextOverlay({
    required super.id,
    required super.center,
    required this.text,
    this.color = const Color(0xFFFFFFFF),
    this.fontSize = 96,
    this.isBold = true,
    this.isItalic = false,
    this.backgroundColor,
    super.scale,
    super.rotationRadians,
  });

  final String text;
  final Color color;
  final double fontSize;
  final bool isBold;
  final bool isItalic;
  final Color? backgroundColor;

  StoryTextOverlay copyWith({
    String? text,
    Color? color,
    double? fontSize,
    bool? isBold,
    bool? isItalic,
    Object? backgroundColor = _storyOverlayUnset,
    Offset? center,
    double? scale,
    double? rotationRadians,
  }) {
    return StoryTextOverlay(
      id: id,
      center: center ?? this.center,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      backgroundColor: identical(backgroundColor, _storyOverlayUnset)
          ? this.backgroundColor
          : backgroundColor as Color?,
      scale: scale ?? this.scale,
      rotationRadians: rotationRadians ?? this.rotationRadians,
    );
  }

  @override
  StoryTextOverlay copyWithTransform({
    Offset? center,
    double? scale,
    double? rotationRadians,
  }) {
    return copyWith(
      center: center,
      scale: scale,
      rotationRadians: rotationRadians,
    );
  }
}

class StoryEmojiOverlay extends StoryOverlay {
  const StoryEmojiOverlay({
    required super.id,
    required super.center,
    required this.emoji,
    this.fontSize = 140,
    super.scale,
    super.rotationRadians,
  });

  final String emoji;
  final double fontSize;

  StoryEmojiOverlay copyWith({
    String? emoji,
    double? fontSize,
    Offset? center,
    double? scale,
    double? rotationRadians,
  }) {
    return StoryEmojiOverlay(
      id: id,
      center: center ?? this.center,
      emoji: emoji ?? this.emoji,
      fontSize: fontSize ?? this.fontSize,
      scale: scale ?? this.scale,
      rotationRadians: rotationRadians ?? this.rotationRadians,
    );
  }

  @override
  StoryEmojiOverlay copyWithTransform({
    Offset? center,
    double? scale,
    double? rotationRadians,
  }) {
    return copyWith(
      center: center,
      scale: scale,
      rotationRadians: rotationRadians,
    );
  }
}

class StoryStickerOverlay extends StoryOverlay {
  const StoryStickerOverlay({
    required super.id,
    required super.center,
    required this.label,
    required this.image,
    this.size = 360,
    super.scale,
    super.rotationRadians,
  });

  final String label;
  final ImageProvider image;
  final double size;

  StoryStickerOverlay copyWith({
    String? label,
    ImageProvider? image,
    double? size,
    Offset? center,
    double? scale,
    double? rotationRadians,
  }) {
    return StoryStickerOverlay(
      id: id,
      center: center ?? this.center,
      label: label ?? this.label,
      image: image ?? this.image,
      size: size ?? this.size,
      scale: scale ?? this.scale,
      rotationRadians: rotationRadians ?? this.rotationRadians,
    );
  }

  @override
  StoryStickerOverlay copyWithTransform({
    Offset? center,
    double? scale,
    double? rotationRadians,
  }) {
    return copyWith(
      center: center,
      scale: scale,
      rotationRadians: rotationRadians,
    );
  }
}

class StoryMentionOverlay extends StoryOverlay {
  const StoryMentionOverlay({
    required super.id,
    required super.center,
    required this.userId,
    required this.displayName,
    this.fontSize = 58,
    this.foregroundColor = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0xB8000000),
    super.scale,
    super.rotationRadians,
  });

  final String userId;
  final String displayName;
  final double fontSize;
  final Color foregroundColor;
  final Color backgroundColor;

  String get label {
    final name = displayName.trim().isEmpty ? userId : displayName.trim();
    if (name.startsWith('@')) {
      final localpart = name.substring(1).split(':').first.trim();
      return '@${localpart.isEmpty ? name.substring(1) : localpart}';
    }
    return '@$name';
  }

  StoryMentionOverlay copyWith({
    String? userId,
    String? displayName,
    double? fontSize,
    Color? foregroundColor,
    Color? backgroundColor,
    Offset? center,
    double? scale,
    double? rotationRadians,
  }) {
    return StoryMentionOverlay(
      id: id,
      center: center ?? this.center,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      fontSize: fontSize ?? this.fontSize,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      scale: scale ?? this.scale,
      rotationRadians: rotationRadians ?? this.rotationRadians,
    );
  }

  @override
  StoryMentionOverlay copyWithTransform({
    Offset? center,
    double? scale,
    double? rotationRadians,
  }) {
    return copyWith(
      center: center,
      scale: scale,
      rotationRadians: rotationRadians,
    );
  }
}
