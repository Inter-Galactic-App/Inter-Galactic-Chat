import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_trim_exporter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StoryDesktopVideoRecordStartResult {
  const StoryDesktopVideoRecordStartResult._({
    required this.status,
    this.session,
    this.message,
  });

  factory StoryDesktopVideoRecordStartResult.success({
    required StoryDesktopVideoRecordingSession session,
  }) =>
      StoryDesktopVideoRecordStartResult._(
        status: StoryDesktopVideoRecordStatus.success,
        session: session,
      );

  factory StoryDesktopVideoRecordStartResult.unsupported([String? message]) =>
      StoryDesktopVideoRecordStartResult._(
        status: StoryDesktopVideoRecordStatus.unsupported,
        message: message,
      );

  factory StoryDesktopVideoRecordStartResult.failed([String? message]) =>
      StoryDesktopVideoRecordStartResult._(
        status: StoryDesktopVideoRecordStatus.failed,
        message: message,
      );

  final StoryDesktopVideoRecordStatus status;
  final StoryDesktopVideoRecordingSession? session;
  final String? message;

  bool get isSuccess => status == StoryDesktopVideoRecordStatus.success;
}

class StoryDesktopVideoRecordResult {
  const StoryDesktopVideoRecordResult._({
    required this.status,
    this.path,
    this.name,
    this.sizeBytes,
    this.message,
  });

  factory StoryDesktopVideoRecordResult.success({
    required String path,
    required String name,
    required int sizeBytes,
  }) =>
      StoryDesktopVideoRecordResult._(
        status: StoryDesktopVideoRecordStatus.success,
        path: path,
        name: name,
        sizeBytes: sizeBytes,
      );

  factory StoryDesktopVideoRecordResult.failed([String? message]) =>
      StoryDesktopVideoRecordResult._(
        status: StoryDesktopVideoRecordStatus.failed,
        message: message,
      );

  final StoryDesktopVideoRecordStatus status;
  final String? path;
  final String? name;
  final int? sizeBytes;
  final String? message;

  bool get isSuccess => status == StoryDesktopVideoRecordStatus.success;
}

enum StoryDesktopVideoRecordStatus {
  success,
  unsupported,
  failed,
}

class StoryDesktopVideoRecordingSession {
  StoryDesktopVideoRecordingSession._({
    required Process process,
    required File outputFile,
    required Future<dynamic> stdoutDrain,
    required Future<dynamic> stderrDrain,
  })  : _process = process,
        _outputFile = outputFile,
        _stdoutDrain = stdoutDrain,
        _stderrDrain = stderrDrain;

  final Process _process;
  final File _outputFile;
  final Future<dynamic> _stdoutDrain;
  final Future<dynamic> _stderrDrain;
  bool _completed = false;

  Future<StoryDesktopVideoRecordResult> stop() async {
    if (_completed) {
      return StoryDesktopVideoRecordResult.failed(
        'Desktop story video recording already finished.',
      );
    }
    _completed = true;

    try {
      _process.stdin.writeln('q');
      await _process.stdin.flush();
      await _process.stdin.close();
    } catch (_) {
      _process.kill();
    }

    final exitCode = await _waitForExitAfterStop();
    await _waitForDrains();

    if (exitCode != 0 ||
        !await _outputFile.exists() ||
        await _outputFile.length() <= 0) {
      await _deleteOutput();
      return StoryDesktopVideoRecordResult.failed(
        'Desktop story video recording failed.',
      );
    }

    return StoryDesktopVideoRecordResult.success(
      path: _outputFile.path,
      name: _outputFile.uri.pathSegments.last,
      sizeBytes: await _outputFile.length(),
    );
  }

  Future<void> cancel() async {
    if (_completed) {
      return;
    }
    _completed = true;
    try {
      _process.stdin.writeln('q');
      await _process.stdin.flush();
      await _process.stdin.close();
    } catch (_) {
      _process.kill();
    }
    await _waitForExitAfterStop();
    await _waitForDrains();
    await _deleteOutput();
  }

  Future<int> _waitForExitAfterStop() async {
    try {
      return await _process.exitCode.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      _process.kill();
      try {
        return await _process.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        return -1;
      }
    }
  }

  Future<void> _waitForDrains() async {
    try {
      await Future.wait([_stdoutDrain, _stderrDrain]).timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      // Best-effort drain cleanup after the FFmpeg process exits or is killed.
    }
  }

  Future<void> _deleteOutput() async {
    try {
      if (await _outputFile.exists()) {
        await _outputFile.delete();
      }
    } catch (_) {
      // Best-effort cleanup of our own generated temp recording.
    }
  }
}

class StoryDesktopVideoRecorder {
  const StoryDesktopVideoRecorder({
    this.tools = const StoryVideoFfmpegTools(),
  });

  final StoryVideoFfmpegTools tools;

  Future<StoryDesktopVideoRecordStartResult> start({
    required String deviceLabel,
    String? sourceName,
  }) async {
    if (!Platform.isWindows) {
      return StoryDesktopVideoRecordStartResult.unsupported(
        'Desktop story video recording is only available on Windows.',
      );
    }
    final effectiveDeviceLabel = deviceLabel.trim();
    if (effectiveDeviceLabel.isEmpty) {
      return StoryDesktopVideoRecordStartResult.unsupported(
        'No camera device is selected for story video recording.',
      );
    }

    final toolchain = await tools.findToolchain();
    if (toolchain == null) {
      return StoryDesktopVideoRecordStartResult.unsupported(
        'FFmpeg and FFprobe are not available for story video recording.',
      );
    }

    final tempDirectory = await getTemporaryDirectory();
    final exportDirectory = Directory(
      p.join(tempDirectory.path, 'intergalactic_story_video_recordings'),
    );
    await exportDirectory.create(recursive: true);

    final outputName = _recordingVideoName(sourceName ?? effectiveDeviceLabel);
    final outputFile = File(p.join(exportDirectory.path, outputName));
    final args = storyDesktopVideoRecordArguments(
      deviceLabel: effectiveDeviceLabel,
      outputPath: outputFile.path,
    );

    try {
      final process = await Process.start(
        toolchain.ffmpegPath,
        args,
        runInShell: false,
      );
      final stdoutDrain = process.stdout.drain<dynamic>();
      final stderrDrain = process.stderr.drain<dynamic>();
      final earlyExitCode = await process.exitCode
          .then<int?>((code) => code)
          .timeout(const Duration(milliseconds: 700), onTimeout: () => null);
      if (earlyExitCode != null) {
        await Future.wait([stdoutDrain, stderrDrain]);
        await _deletePartialOutput(outputFile);
        return StoryDesktopVideoRecordStartResult.failed(
          'Desktop story video recording failed to start.',
        );
      }

      return StoryDesktopVideoRecordStartResult.success(
        session: StoryDesktopVideoRecordingSession._(
          process: process,
          outputFile: outputFile,
          stdoutDrain: stdoutDrain,
          stderrDrain: stderrDrain,
        ),
      );
    } catch (_) {
      await _deletePartialOutput(outputFile);
      return StoryDesktopVideoRecordStartResult.failed(
        'Desktop story video recording failed to start.',
      );
    }
  }

  Future<void> _deletePartialOutput(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup of our own generated temp recording.
    }
  }

  String _recordingVideoName(String sourceName) {
    final baseName = p.basenameWithoutExtension(sourceName).trim();
    final safeBase = baseName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final name = safeBase.isEmpty ? 'story-camera' : safeBase;
    return '$name-recording-${DateTime.now().microsecondsSinceEpoch}.mp4';
  }
}

@visibleForTesting
List<String> storyDesktopVideoRecordArguments({
  required String deviceLabel,
  required String outputPath,
  Duration maxDuration = storyMaxVideoDuration,
}) {
  return [
    '-hide_banner',
    '-y',
    '-f',
    'dshow',
    '-rtbufsize',
    '128M',
    '-framerate',
    '30',
    '-i',
    'video=$deviceLabel',
    '-t',
    _formatStoryDesktopVideoRecordTimestamp(maxDuration),
    '-vf',
    'scale=trunc(iw/2)*2:trunc(ih/2)*2',
    '-c:v',
    'mpeg4',
    '-q:v',
    '5',
    '-tag:v',
    'mp4v',
    '-pix_fmt',
    'yuv420p',
    '-an',
    '-movflags',
    '+faststart',
    outputPath,
  ];
}

String _formatStoryDesktopVideoRecordTimestamp(Duration duration) {
  final totalMilliseconds = duration.inMilliseconds;
  final hours = totalMilliseconds ~/ Duration.millisecondsPerHour;
  final minutes = (totalMilliseconds % Duration.millisecondsPerHour) ~/
      Duration.millisecondsPerMinute;
  final seconds = (totalMilliseconds % Duration.millisecondsPerMinute) ~/
      Duration.millisecondsPerSecond;
  final milliseconds = totalMilliseconds % Duration.millisecondsPerSecond;
  return [
    hours.toString().padLeft(2, '0'),
    minutes.toString().padLeft(2, '0'),
    '${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}',
  ].join(':');
}
