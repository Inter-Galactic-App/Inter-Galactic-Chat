import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:media_kit/media_kit.dart';

class StoryVideoProbeResult {
  const StoryVideoProbeResult({
    required this.duration,
    required this.size,
    this.thumbnailBytes,
  });

  final Duration duration;
  final Size? size;
  final Uint8List? thumbnailBytes;
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
      await player.open(Playlist([Media(fileUri.toString())]), play: false);
      final duration = await _waitForDuration(player);
      final size = _readSize(player);
      Uint8List? thumbnail;
      try {
        thumbnail = await player.screenshot();
      } catch (_) {
        thumbnail = null;
      }
      return StoryVideoProbeResult(
        duration: duration,
        size: size,
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

  Size? _readSize(Player player) {
    final width = player.state.width;
    final height = player.state.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width.toDouble(), height.toDouble());
  }
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
  final nextStartMs =
      (trimStart + delta).inMilliseconds.clamp(0, maxStartMs).toInt();
  final nextStart = Duration(milliseconds: nextStartMs);
  return (
    trimStart: nextStart,
    trimEnd: nextStart + selectedDuration,
  );
}
