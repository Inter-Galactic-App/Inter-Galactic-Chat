import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_probe_platform.dart';
import 'package:media_kit/media_kit.dart';

class StoryVideoProbeResult {
  const StoryVideoProbeResult({
    required this.duration,
    required this.size,
    this.visibleContentSize,
    this.hasBakedLetterbox = false,
    this.thumbnailBytes,
  });

  final Duration duration;

  /// Encoded video size reported by the player or native metadata.
  final Size? size;

  /// Content size after confidently detected baked black bars are excluded.
  final Size? visibleContentSize;
  final bool hasBakedLetterbox;
  final Uint8List? thumbnailBytes;

  Size? get displaySize => visibleContentSize ?? size;
}

class StoryVideoVisibleContentAnalysis {
  const StoryVideoVisibleContentAnalysis({
    required this.visibleSize,
    required this.hasVerticalBars,
    required this.hasHorizontalBars,
  });

  final Size visibleSize;
  final bool hasVerticalBars;
  final bool hasHorizontalBars;
}

class StoryVideoProbe {
  const StoryVideoProbe();

  Future<StoryVideoProbeResult> probe(String path) async {
    final fileUri = await SystemFileProvider(path).resolve();
    if (fileUri == null) {
      throw StateError('Story video file could not be resolved');
    }

    final player = Player();
    try {
      // media_kit creates players with vid=no until a VideoController
      // attaches. The probe never attaches one, so the video track must be
      // enabled explicitly or width/height/screenshot never become available
      // and story drafts lose their media dimensions.
      await enableStoryVideoProbeTrack(player);
      await player.open(Playlist([Media(fileUri.toString())]), play: false);
      final duration = await _waitForDuration(player);
      final size = await _waitForSize(player);
      Uint8List? thumbnail;
      try {
        thumbnail = await player.screenshot();
      } catch (_) {
        thumbnail = null;
      }
      final visible = await storyVideoVisibleContentAnalysisFromThumbnailAsync(
        reportedSize: size,
        thumbnailBytes: thumbnail,
      );
      return StoryVideoProbeResult(
        duration: duration,
        size: size,
        visibleContentSize: visible?.visibleSize,
        hasBakedLetterbox: visible != null,
        thumbnailBytes: thumbnail,
      );
    } finally {
      await player.dispose();
    }
  }

  Future<Duration> _waitForDuration(Player player) async {
    if (player.state.duration > Duration.zero) {
      return player.state.duration;
    }

    final completer = Completer<Duration>();
    late final StreamSubscription<Duration> subscription;
    subscription = player.stream.duration.listen((duration) {
      if (duration > Duration.zero && !completer.isCompleted) {
        completer.complete(duration);
      }
    });
    try {
      return await completer.future.timeout(const Duration(seconds: 4));
    } finally {
      await subscription.cancel();
    }
  }

  Future<Size?> _waitForSize(Player player) async {
    final current = _readSize(player);
    if (current != null) {
      return current;
    }

    // Width/height arrive asynchronously from mpv video-params once the
    // first frame is configured, which can be after the duration event.
    final completer = Completer<Size?>();
    void complete() {
      final size = _readSize(player);
      if (size != null && !completer.isCompleted) {
        completer.complete(size);
      }
    }

    final subscriptions = <StreamSubscription<int?>>[
      player.stream.width.listen((_) => complete()),
      player.stream.height.listen((_) => complete()),
    ];
    try {
      return await completer.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      return _readSize(player);
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  Size? _readSize(Player player) {
    final width = player.state.width;
    final height = player.state.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width.toDouble(), height.toDouble());
  }
}

Size? storyVideoVisibleContentSizeFromThumbnail({
  required Size? reportedSize,
  required Uint8List? thumbnailBytes,
}) {
  return storyVideoVisibleContentAnalysisFromThumbnail(
        reportedSize: reportedSize,
        thumbnailBytes: thumbnailBytes,
      )?.visibleSize ??
      reportedSize;
}

Future<StoryVideoVisibleContentAnalysis?>
storyVideoVisibleContentAnalysisFromThumbnailAsync({
  required Size? reportedSize,
  required Uint8List? thumbnailBytes,
}) async {
  final input = _storyVideoAnalysisInput(
    reportedSize: reportedSize,
    thumbnailBytes: thumbnailBytes,
  );
  if (input == null) {
    return null;
  }

  final result = await compute(_storyVideoVisibleContentAnalysisWorker, input);
  if (result == null) {
    return null;
  }

  return _storyVideoVisibleContentAnalysisFromResult(result);
}

StoryVideoVisibleContentAnalysis?
storyVideoVisibleContentAnalysisFromThumbnail({
  required Size? reportedSize,
  required Uint8List? thumbnailBytes,
}) {
  final input = _storyVideoAnalysisInput(
    reportedSize: reportedSize,
    thumbnailBytes: thumbnailBytes,
  );
  if (input == null) {
    return null;
  }

  final result = _storyVideoVisibleContentAnalysisWorker(input);
  if (result == null) {
    return null;
  }

  return _storyVideoVisibleContentAnalysisFromResult(result);
}

StoryVideoVisibleContentAnalysis _storyVideoVisibleContentAnalysisFromResult(
  _StoryVideoVisibleContentAnalysisResult result,
) {
  return StoryVideoVisibleContentAnalysis(
    visibleSize: Size(result.visibleWidth, result.visibleHeight),
    hasVerticalBars: result.hasVerticalBars,
    hasHorizontalBars: result.hasHorizontalBars,
  );
}

_StoryVideoVisibleContentAnalysisInput? _storyVideoAnalysisInput({
  required Size? reportedSize,
  required Uint8List? thumbnailBytes,
}) {
  if (reportedSize == null ||
      reportedSize.width <= 0 ||
      reportedSize.height <= 0 ||
      thumbnailBytes == null ||
      thumbnailBytes.isEmpty) {
    return null;
  }

  return _StoryVideoVisibleContentAnalysisInput(
    reportedWidth: reportedSize.width,
    reportedHeight: reportedSize.height,
    thumbnailBytes: thumbnailBytes,
  );
}

_StoryVideoVisibleContentAnalysisResult?
_storyVideoVisibleContentAnalysisWorker(
  _StoryVideoVisibleContentAnalysisInput input,
) {
  final thumbnail = img.decodeImage(input.thumbnailBytes);
  if (thumbnail == null || thumbnail.width <= 0 || thumbnail.height <= 0) {
    return null;
  }

  final visible = _storyVideoVisibleContentBounds(thumbnail);
  if (visible == null) {
    return null;
  }

  final visibleRatio = visible.width / visible.height;
  final reportedRatio = input.reportedWidth / input.reportedHeight;
  if (!visibleRatio.isFinite ||
      visibleRatio <= 0 ||
      !reportedRatio.isFinite ||
      reportedRatio <= 0 ||
      (visibleRatio - reportedRatio).abs() < 0.04) {
    return null;
  }

  final visibleSize = visibleRatio > reportedRatio
      ? Size(input.reportedWidth, input.reportedWidth / visibleRatio)
      : Size(input.reportedHeight * visibleRatio, input.reportedHeight);
  return _StoryVideoVisibleContentAnalysisResult(
    visibleWidth: visibleSize.width,
    visibleHeight: visibleSize.height,
    hasVerticalBars: visible.hasVerticalBars,
    hasHorizontalBars: visible.hasHorizontalBars,
  );
}

class _StoryVideoVisibleContentAnalysisInput {
  const _StoryVideoVisibleContentAnalysisInput({
    required this.reportedWidth,
    required this.reportedHeight,
    required this.thumbnailBytes,
  });

  final double reportedWidth;
  final double reportedHeight;
  final Uint8List thumbnailBytes;
}

class _StoryVideoVisibleContentAnalysisResult {
  const _StoryVideoVisibleContentAnalysisResult({
    required this.visibleWidth,
    required this.visibleHeight,
    required this.hasVerticalBars,
    required this.hasHorizontalBars,
  });

  final double visibleWidth;
  final double visibleHeight;
  final bool hasVerticalBars;
  final bool hasHorizontalBars;
}

({
  int left,
  int top,
  int right,
  int bottom,
  int width,
  int height,
  bool hasVerticalBars,
  bool hasHorizontalBars,
})?
_storyVideoVisibleContentBounds(img.Image thumbnail) {
  final minVerticalBar = math.max(2, (thumbnail.height * 0.05).round());
  final minHorizontalBar = math.max(2, (thumbnail.width * 0.05).round());

  var top = 0;
  while (top < thumbnail.height && !_storyVideoRowHasContent(thumbnail, top)) {
    top++;
  }

  var bottom = thumbnail.height - 1;
  while (bottom >= top && !_storyVideoRowHasContent(thumbnail, bottom)) {
    bottom--;
  }

  var left = 0;
  while (left < thumbnail.width &&
      !_storyVideoColumnHasContent(thumbnail, left)) {
    left++;
  }

  var right = thumbnail.width - 1;
  while (right >= left && !_storyVideoColumnHasContent(thumbnail, right)) {
    right--;
  }

  if (top >= bottom || left >= right) {
    return null;
  }

  final verticalCrop = top + (thumbnail.height - 1 - bottom);
  final horizontalCrop = left + (thumbnail.width - 1 - right);
  final topCrop = top;
  final bottomCrop = thumbnail.height - 1 - bottom;
  final leftCrop = left;
  final rightCrop = thumbnail.width - 1 - right;
  final visibleWidth = right - left + 1;
  final visibleHeight = bottom - top + 1;
  final spansWidth = visibleWidth / thumbnail.width >= 0.8;
  final spansHeight = visibleHeight / thumbnail.height >= 0.8;
  final balancedVerticalBars =
      (topCrop - bottomCrop).abs() <= thumbnail.height * 0.08;
  final balancedHorizontalBars =
      (leftCrop - rightCrop).abs() <= thumbnail.width * 0.08;
  final hasVerticalBars =
      topCrop >= minVerticalBar &&
      bottomCrop >= minVerticalBar &&
      verticalCrop / thumbnail.height >= 0.12 &&
      balancedVerticalBars &&
      spansWidth;
  final hasHorizontalBars =
      leftCrop >= minHorizontalBar &&
      rightCrop >= minHorizontalBar &&
      horizontalCrop / thumbnail.width >= 0.12 &&
      balancedHorizontalBars &&
      spansHeight;
  if (!hasVerticalBars && !hasHorizontalBars) {
    return null;
  }
  if (!_storyVideoVisibleRegionHasEnoughContent(
    thumbnail,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  )) {
    return null;
  }

  return (
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    width: visibleWidth,
    height: visibleHeight,
    hasVerticalBars: hasVerticalBars,
    hasHorizontalBars: hasHorizontalBars,
  );
}

bool _storyVideoVisibleRegionHasEnoughContent(
  img.Image thumbnail, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final width = right - left + 1;
  final height = bottom - top + 1;
  if (width <= 0 || height <= 0) {
    return false;
  }

  final stepX = math.max(1, (width / 32).floor());
  final stepY = math.max(1, (height / 32).floor());
  var samples = 0;
  var nonBlack = 0;
  var brightOrColored = 0;
  for (var y = top; y <= bottom; y += stepY) {
    for (var x = left; x <= right; x += stepX) {
      samples++;
      final pixel = thumbnail.getPixel(x, y);
      if (_storyVideoPixelIsBlack(pixel)) {
        continue;
      }
      nonBlack++;
      final luma = pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722;
      final maxChannel = math.max(pixel.r, math.max(pixel.g, pixel.b));
      final minChannel = math.min(pixel.r, math.min(pixel.g, pixel.b));
      if (luma > 32 || maxChannel - minChannel > 12) {
        brightOrColored++;
      }
    }
  }
  if (samples == 0) {
    return false;
  }

  return nonBlack / samples >= 0.18 && brightOrColored / samples >= 0.08;
}

bool _storyVideoRowHasContent(img.Image thumbnail, int y) {
  final minimumContentPixels = math.max(2, (thumbnail.width * 0.03).round());
  var contentPixels = 0;
  for (var x = 0; x < thumbnail.width; x++) {
    if (!_storyVideoPixelIsBlack(thumbnail.getPixel(x, y))) {
      contentPixels++;
      if (contentPixels >= minimumContentPixels) {
        return true;
      }
    }
  }
  return false;
}

bool _storyVideoColumnHasContent(img.Image thumbnail, int x) {
  final minimumContentPixels = math.max(2, (thumbnail.height * 0.03).round());
  var contentPixels = 0;
  for (var y = 0; y < thumbnail.height; y++) {
    if (!_storyVideoPixelIsBlack(thumbnail.getPixel(x, y))) {
      contentPixels++;
      if (contentPixels >= minimumContentPixels) {
        return true;
      }
    }
  }
  return false;
}

bool _storyVideoPixelIsBlack(img.Pixel pixel) {
  final luma = pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722;
  return luma <= 18;
}

String storyVideoDurationLabel(Duration duration) {
  final totalSeconds = duration.inMilliseconds / 1000;
  if (totalSeconds >= 60) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
  return '${totalSeconds.toStringAsFixed(totalSeconds < 10 ? 1 : 0)}s';
}

({Duration trimStart, Duration trimEnd}) storyVideoShiftTrimRange({
  required Duration sourceDuration,
  required Duration trimStart,
  required Duration trimEnd,
  required Duration delta,
}) {
  if (sourceDuration <= Duration.zero) {
    return (trimStart: Duration.zero, trimEnd: Duration.zero);
  }

  final selectedDuration = trimEnd - trimStart;
  if (selectedDuration <= Duration.zero || selectedDuration >= sourceDuration) {
    return (trimStart: Duration.zero, trimEnd: sourceDuration);
  }

  final maxStartMs =
      sourceDuration.inMilliseconds - selectedDuration.inMilliseconds;
  final nextStartMs = (trimStart + delta).inMilliseconds
      .clamp(0, maxStartMs)
      .toInt();
  final nextStart = Duration(milliseconds: nextStartMs);
  return (trimStart: nextStart, trimEnd: nextStart + selectedDuration);
}
