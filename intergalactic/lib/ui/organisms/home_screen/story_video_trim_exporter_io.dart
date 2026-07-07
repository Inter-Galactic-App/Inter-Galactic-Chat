import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const MethodChannel _storyVideoExportChannel = MethodChannel(
  'chat.intergalactic.app/story_video_export',
);

class StoryVideoTrimExportResult {
  const StoryVideoTrimExportResult._({
    required this.status,
    this.path,
    this.name,
    this.sizeBytes,
    this.message,
  });

  factory StoryVideoTrimExportResult.success({
    required String path,
    required String name,
    required int sizeBytes,
  }) =>
      StoryVideoTrimExportResult._(
        status: StoryVideoTrimExportStatus.success,
        path: path,
        name: name,
        sizeBytes: sizeBytes,
      );

  factory StoryVideoTrimExportResult.unsupported([String? message]) =>
      StoryVideoTrimExportResult._(
        status: StoryVideoTrimExportStatus.unsupported,
        message: message,
      );

  factory StoryVideoTrimExportResult.failed([String? message]) =>
      StoryVideoTrimExportResult._(
        status: StoryVideoTrimExportStatus.failed,
        message: message,
      );

  final StoryVideoTrimExportStatus status;
  final String? path;
  final String? name;
  final int? sizeBytes;
  final String? message;

  bool get isSuccess => status == StoryVideoTrimExportStatus.success;
}

enum StoryVideoTrimExportStatus {
  success,
  unsupported,
  failed,
}

class StoryVideoTrimExporter {
  const StoryVideoTrimExporter();

  Future<StoryVideoTrimExportResult> exportTrim({
    required String sourcePath,
    required Duration trimStart,
    required Duration trimEnd,
    required String sourceName,
  }) async {
    final selectedDuration = trimEnd - trimStart;
    if (sourcePath.trim().isEmpty ||
        trimStart.isNegative ||
        selectedDuration <= Duration.zero) {
      return StoryVideoTrimExportResult.failed('Invalid story video trim.');
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return _exportMobileTrim(
        sourcePath: sourcePath,
        trimStart: trimStart,
        trimEnd: trimEnd,
        sourceName: sourceName,
      );
    }

    final toolchain = await const StoryVideoFfmpegTools().findToolchain();
    if (toolchain == null) {
      return StoryVideoTrimExportResult.unsupported(
        'FFmpeg and FFprobe are not available for story video trim export.',
      );
    }

    final tempDirectory = await getTemporaryDirectory();
    final exportDirectory = Directory(
      p.join(tempDirectory.path, 'intergalactic_story_video_exports'),
    );
    await exportDirectory.create(recursive: true);

    final outputName = _trimmedVideoName(sourceName);
    final outputFile = File(p.join(exportDirectory.path, outputName));
    final args = storyVideoTrimExportArguments(
      sourcePath: sourcePath,
      trimStart: trimStart,
      selectedDuration: selectedDuration,
      outputPath: outputFile.path,
    );

    Process? process;
    Future<dynamic>? stdoutDrain;
    Future<dynamic>? stderrDrain;
    int exitCode;
    try {
      process = await Process.start(
        toolchain.ffmpegPath,
        args,
        runInShell: false,
      );
      stdoutDrain = process.stdout.drain<dynamic>();
      stderrDrain = process.stderr.drain<dynamic>();
      exitCode = await process.exitCode.timeout(const Duration(minutes: 2));
      await Future.wait([stdoutDrain, stderrDrain]);
    } on TimeoutException {
      process?.kill();
      await _waitForProcessCleanup(process, stdoutDrain, stderrDrain);
      await _deletePartialOutput(outputFile);
      return StoryVideoTrimExportResult.failed(
        'Story video trim export timed out.',
      );
    } catch (_) {
      await _deletePartialOutput(outputFile);
      return StoryVideoTrimExportResult.failed(
        'Story video trim export failed.',
      );
    }

    if (exitCode != 0 ||
        !await outputFile.exists() ||
        await outputFile.length() <= 0) {
      await _deletePartialOutput(outputFile);
      return StoryVideoTrimExportResult.failed(
        'Story video trim export failed.',
      );
    }

    return StoryVideoTrimExportResult.success(
      path: outputFile.path,
      name: outputName,
      sizeBytes: await outputFile.length(),
    );
  }

  Future<StoryVideoTrimExportResult> _exportMobileTrim({
    required String sourcePath,
    required Duration trimStart,
    required Duration trimEnd,
    required String sourceName,
  }) async {
    try {
      final response = await _storyVideoExportChannel
          .invokeMethod<Map<dynamic, dynamic>>(
            'exportTrim',
            storyVideoMobileTrimExportArguments(
              sourcePath: sourcePath,
              sourceName: sourceName,
              trimStart: trimStart,
              trimEnd: trimEnd,
            ),
          )
          .timeout(const Duration(minutes: 2));
      if (response == null) {
        return StoryVideoTrimExportResult.failed(
          'Story video trim export failed.',
        );
      }
      final path = response['path']?.toString().trim() ?? '';
      final name = response['name']?.toString().trim();
      final sizeBytes = _asInt(response['size'] ?? response['sizeBytes']);
      if (path.isEmpty || sizeBytes == null || sizeBytes <= 0) {
        return StoryVideoTrimExportResult.failed(
          'Story video trim export failed.',
        );
      }
      return StoryVideoTrimExportResult.success(
        path: path,
        name: name?.isNotEmpty == true ? name! : p.basename(path),
        sizeBytes: sizeBytes,
      );
    } on MissingPluginException {
      return StoryVideoTrimExportResult.unsupported(
        'Story video trim export is not available on this platform.',
      );
    } on TimeoutException {
      return StoryVideoTrimExportResult.failed(
        'Story video trim export timed out.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'story_video_export_unsupported') {
        return StoryVideoTrimExportResult.unsupported(error.message);
      }
      return StoryVideoTrimExportResult.failed(error.message);
    } catch (_) {
      return StoryVideoTrimExportResult.failed(
        'Story video trim export failed.',
      );
    }
  }

  String _trimmedVideoName(String sourceName) {
    final baseName = p.basenameWithoutExtension(sourceName).trim();
    final safeBase = baseName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final name = safeBase.isEmpty ? 'story-video' : safeBase;
    return '$name-trim-${DateTime.now().microsecondsSinceEpoch}.mp4';
  }

  Future<void> _deletePartialOutput(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup of our own generated temp export.
    }
  }

  Future<void> _waitForProcessCleanup(
    Process? process,
    Future<dynamic>? stdoutDrain,
    Future<dynamic>? stderrDrain,
  ) async {
    if (process != null) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        // Best-effort timeout cleanup; the caller has already sent kill().
      }
    }

    final drains = [stdoutDrain, stderrDrain].whereType<Future<dynamic>>();
    if (drains.isEmpty) {
      return;
    }

    try {
      await Future.wait(drains).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort drain cleanup after a killed export process.
    }
  }
}

class StoryVideoFfmpegTools {
  const StoryVideoFfmpegTools();

  Future<StoryVideoFfmpegToolchain?> findToolchain() async {
    for (final candidate in _bundledToolchains()) {
      if (await _toolRuns(candidate.ffmpegPath, runInShell: false) &&
          await _toolRuns(candidate.ffprobePath, runInShell: false)) {
        return candidate;
      }
    }

    final pathToolchain = await _pathToolchain();
    if (pathToolchain != null &&
        await _toolRuns(pathToolchain.ffmpegPath, runInShell: false) &&
        await _toolRuns(pathToolchain.ffprobePath, runInShell: false)) {
      return pathToolchain;
    }
    return null;
  }

  Iterable<StoryVideoFfmpegToolchain> _bundledToolchains() sync* {
    if (!Platform.isWindows) {
      return;
    }

    final seen = <String>{};
    final roots = <String>[
      p.dirname(Platform.resolvedExecutable),
      Directory.current.path,
    ];
    for (final root in roots) {
      for (final directory in const ['tools/ffmpeg', 'ffmpeg']) {
        final toolDirectory = p.normalize(p.join(root, directory));
        if (!seen.add(toolDirectory.toLowerCase())) {
          continue;
        }
        yield StoryVideoFfmpegToolchain(
          ffmpegPath: p.join(toolDirectory, 'ffmpeg.exe'),
          ffprobePath: p.join(toolDirectory, 'ffprobe.exe'),
        );
      }
    }
  }

  Future<StoryVideoFfmpegToolchain?> _pathToolchain() async {
    final ffmpegPath = await _resolvePathTool('ffmpeg');
    final ffprobePath = await _resolvePathTool('ffprobe');
    if (ffmpegPath == null || ffprobePath == null) {
      return null;
    }

    return StoryVideoFfmpegToolchain(
      ffmpegPath: ffmpegPath,
      ffprobePath: ffprobePath,
    );
  }

  Future<String?> _resolvePathTool(String executable) async {
    final resolver = Platform.isWindows ? 'where.exe' : 'which';
    final names = [
      Platform.isWindows && !executable.endsWith('.exe')
          ? '$executable.exe'
          : executable,
    ];

    for (final name in names) {
      try {
        final result = await Process.run(
          resolver,
          [name],
          runInShell: false,
        ).timeout(const Duration(seconds: 3));
        if (result.exitCode != 0) {
          continue;
        }
        final lines = result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty);
        if (lines.isNotEmpty) {
          return lines.first;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<bool> _toolRuns(
    String executable, {
    required bool runInShell,
  }) async {
    try {
      final result = await Process.run(
        executable,
        const ['-version'],
        runInShell: runInShell,
      ).timeout(const Duration(seconds: 3));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

class StoryVideoFfmpegToolchain {
  const StoryVideoFfmpegToolchain({
    required this.ffmpegPath,
    required this.ffprobePath,
  });

  final String ffmpegPath;
  final String ffprobePath;
}

List<String> storyVideoTrimExportArguments({
  required String sourcePath,
  required Duration trimStart,
  required Duration selectedDuration,
  required String outputPath,
}) {
  return [
    '-hide_banner',
    '-y',
    '-i',
    sourcePath,
    '-ss',
    _formatStoryVideoTrimTimestamp(trimStart),
    '-t',
    _formatStoryVideoTrimTimestamp(selectedDuration),
    '-map',
    '0:v:0',
    '-map',
    '0:a?',
    '-vf',
    'scale=trunc(iw/2)*2:trunc(ih/2)*2',
    // Use FFmpeg's built-in LGPL-compatible MPEG-4 Part 2 encoder for the
    // bundled desktop exporter; do not require GPL encoders such as libx264.
    '-c:v',
    'mpeg4',
    '-q:v',
    '5',
    '-tag:v',
    'mp4v',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-b:a',
    '128k',
    '-movflags',
    '+faststart',
    outputPath,
  ];
}

Map<String, Object?> storyVideoMobileTrimExportArguments({
  required String sourcePath,
  required String sourceName,
  required Duration trimStart,
  required Duration trimEnd,
}) {
  return <String, Object?>{
    'sourcePath': sourcePath,
    'sourceName': sourceName,
    'trimStartMs': trimStart.inMilliseconds,
    'trimEndMs': trimEnd.inMilliseconds,
  };
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String _formatStoryVideoTrimTimestamp(Duration duration) {
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
