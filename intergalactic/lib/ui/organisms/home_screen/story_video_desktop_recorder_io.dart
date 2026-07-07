import 'dart:async';
import 'dart:convert';
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

class StoryDesktopVideoInputDevice {
  const StoryDesktopVideoInputDevice({
    required this.label,
    String? displayName,
  }) : displayName = displayName ?? label;

  final String label;
  final String displayName;
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
    required Future<void> stdoutDrain,
    required Future<void> stderrDrain,
    required Stream<Uint8List> previewFrames,
    required _LatestPreviewFrame latestPreviewFrame,
    required _BoundedProcessOutput stderr,
  })  : _process = process,
        _outputFile = outputFile,
        _stdoutDrain = stdoutDrain,
        _stderrDrain = stderrDrain,
        _previewFrames = previewFrames,
        _latestPreviewFrame = latestPreviewFrame,
        _stderr = stderr;

  final Process _process;
  final File _outputFile;
  final Future<void> _stdoutDrain;
  final Future<void> _stderrDrain;
  final Stream<Uint8List> _previewFrames;
  final _LatestPreviewFrame _latestPreviewFrame;
  final _BoundedProcessOutput _stderr;
  bool _completed = false;

  Stream<Uint8List> get previewFrames => _previewFrames;

  Uint8List? get latestPreviewFrame => _latestPreviewFrame.value;

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
        _storyDesktopVideoRecordingFailureMessage(
          'Desktop story video recording failed.',
          exitCode: exitCode,
          stderr: _stderr.text,
          outputPath: _outputFile.path,
        ),
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

  Future<List<StoryDesktopVideoInputDevice>> listVideoInputDevices() async {
    if (!Platform.isWindows) {
      return const [];
    }

    final toolchain = await tools.findToolchain();
    if (toolchain == null) {
      return const [];
    }

    try {
      final result = await Process.run(
        toolchain.ffmpegPath,
        storyDesktopVideoInputListArguments(),
        runInShell: false,
      ).timeout(const Duration(seconds: 8));
      return parseStoryDesktopVideoInputDevices(
        '${result.stderr}\n${result.stdout}',
      );
    } catch (_) {
      return const [];
    }
  }

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
      final stderr = _BoundedProcessOutput();
      final previewController = StreamController<Uint8List>.broadcast();
      final latestPreviewFrame = _LatestPreviewFrame();
      final stdoutDrain = _drainPreviewFrames(
        process.stdout,
        previewController,
        latestPreviewFrame,
      );
      final stderrDrain = _drainProcessOutput(process.stderr, stderr);
      final earlyExitCode = await process.exitCode
          .then<int?>((code) => code)
          .timeout(const Duration(milliseconds: 700), onTimeout: () => null);
      if (earlyExitCode != null) {
        await Future.wait([stdoutDrain, stderrDrain]);
        await _deletePartialOutput(outputFile);
        return StoryDesktopVideoRecordStartResult.failed(
          _storyDesktopVideoRecordingFailureMessage(
            'Desktop story video recording failed to start.',
            exitCode: earlyExitCode,
            stderr: stderr.text,
            outputPath: outputFile.path,
          ),
        );
      }

      return StoryDesktopVideoRecordStartResult.success(
        session: StoryDesktopVideoRecordingSession._(
          process: process,
          outputFile: outputFile,
          stdoutDrain: stdoutDrain,
          stderrDrain: stderrDrain,
          previewFrames: previewController.stream,
          latestPreviewFrame: latestPreviewFrame,
          stderr: stderr,
        ),
      );
    } catch (error) {
      await _deletePartialOutput(outputFile);
      return StoryDesktopVideoRecordStartResult.failed(
        _storyDesktopVideoRecordingFailureMessage(
          'Desktop story video recording failed to start.',
          stderr: error.toString(),
          outputPath: outputFile.path,
        ),
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
List<String> storyDesktopVideoInputListArguments() {
  return const [
    '-hide_banner',
    '-list_devices',
    'true',
    '-f',
    'dshow',
    '-i',
    'dummy',
  ];
}

@visibleForTesting
List<StoryDesktopVideoInputDevice> parseStoryDesktopVideoInputDevices(
  String output,
) {
  final devices = <StoryDesktopVideoInputDevice>[];
  final seenLabels = <String>{};
  final deviceLinePattern = RegExp(r'"([^"]+)"\s+\((video|audio)\)');
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final match = deviceLinePattern.firstMatch(line);
    if (match == null || match.group(2) != 'video') {
      continue;
    }
    final label = match.group(1)?.trim();
    if (label == null || label.isEmpty) {
      continue;
    }
    if (!seenLabels.add(label.toLowerCase())) {
      continue;
    }
    devices.add(StoryDesktopVideoInputDevice(label: label));
  }
  return devices;
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
    '-map',
    '0:v:0',
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
    '-t',
    _formatStoryDesktopVideoRecordTimestamp(maxDuration),
    '-map',
    '0:v:0',
    '-vf',
    'fps=15,scale=720:-2',
    '-c:v',
    'mjpeg',
    '-q:v',
    '5',
    '-f',
    'image2pipe',
    'pipe:1',
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

Future<void> _drainProcessOutput(
  Stream<List<int>> stream,
  _BoundedProcessOutput output,
) async {
  await for (final chunk in stream) {
    output.add(chunk);
  }
}

Future<void> _drainPreviewFrames(
  Stream<List<int>> stream,
  StreamController<Uint8List> controller,
  _LatestPreviewFrame latestPreviewFrame,
) async {
  final parser = StoryDesktopVideoPreviewFrameParser();
  try {
    await for (final chunk in stream) {
      final frames = parser.add(chunk);
      for (final frame in frames) {
        latestPreviewFrame.value = frame;
        if (!controller.isClosed) {
          controller.add(frame);
        }
      }
    }
  } catch (error, stackTrace) {
    if (!controller.isClosed) {
      controller.addError(error, stackTrace);
    }
  } finally {
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

@visibleForTesting
class StoryDesktopVideoPreviewFrameParser {
  StoryDesktopVideoPreviewFrameParser();

  static const int _maxBufferBytes = 2 * 1024 * 1024;
  final List<int> _buffer = [];

  List<Uint8List> add(List<int> chunk) {
    if (chunk.isEmpty) {
      return const [];
    }
    _buffer.addAll(chunk);
    final frames = <Uint8List>[];

    while (_buffer.isNotEmpty) {
      final start = _indexOfMarker(_buffer, 0xff, 0xd8, 0);
      if (start < 0) {
        _trimWithoutStartMarker();
        break;
      }
      if (start > 0) {
        _buffer.removeRange(0, start);
      }

      final end = _indexOfMarker(_buffer, 0xff, 0xd9, 2);
      if (end < 0) {
        _trimOversizedPartialFrame();
        break;
      }

      final frameEnd = end + 2;
      frames.add(Uint8List.fromList(_buffer.sublist(0, frameEnd)));
      _buffer.removeRange(0, frameEnd);
    }

    return frames;
  }

  void _trimWithoutStartMarker() {
    if (_buffer.length <= 1) {
      return;
    }
    final keepTail = _buffer.last == 0xff ? 1 : 0;
    _buffer.removeRange(0, _buffer.length - keepTail);
  }

  void _trimOversizedPartialFrame() {
    if (_buffer.length <= _maxBufferBytes) {
      return;
    }
    final keepFrom = _lastIndexOfMarker(
      _buffer,
      0xff,
      0xd8,
      _buffer.length - 1,
    );
    if (keepFrom > 0) {
      _buffer.removeRange(0, keepFrom);
      return;
    }
    _buffer.clear();
  }

  int _indexOfMarker(
    List<int> bytes,
    int first,
    int second,
    int start,
  ) {
    for (var index = start; index < bytes.length - 1; index++) {
      if (bytes[index] == first && bytes[index + 1] == second) {
        return index;
      }
    }
    return -1;
  }

  int _lastIndexOfMarker(
    List<int> bytes,
    int first,
    int second,
    int start,
  ) {
    for (var index = start.clamp(0, bytes.length - 2).toInt();
        index >= 0;
        index--) {
      if (bytes[index] == first && bytes[index + 1] == second) {
        return index;
      }
    }
    return -1;
  }
}

class _LatestPreviewFrame {
  Uint8List? value;
}

class _BoundedProcessOutput {
  _BoundedProcessOutput();

  static const int _maxBytes = 8192;
  final List<int> _bytes = [];
  int _droppedBytes = 0;

  void add(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _bytes.addAll(chunk);
    if (_bytes.length <= _maxBytes) {
      return;
    }
    final overflow = _bytes.length - _maxBytes;
    _bytes.removeRange(0, overflow);
    _droppedBytes += overflow;
  }

  String get text {
    final decoded = utf8.decode(_bytes, allowMalformed: true).trim();
    if (_droppedBytes <= 0 || decoded.isEmpty) {
      return decoded;
    }
    return '[truncated $_droppedBytes bytes]\n$decoded';
  }
}

String _storyDesktopVideoRecordingFailureMessage(
  String baseMessage, {
  int? exitCode,
  String? stderr,
  String? stdout,
  String? outputPath,
}) {
  final output = _storyDesktopVideoRecordingDiagnosticSummary(
    stderr?.trim().isNotEmpty == true ? stderr! : stdout,
    outputPath: outputPath,
  );
  final exit = exitCode == null ? '' : ' Exit code: $exitCode.';
  if (output.isEmpty) {
    return '$baseMessage$exit';
  }
  return '$baseMessage$exit FFmpeg output: $output';
}

String _storyDesktopVideoRecordingDiagnosticSummary(
  String? output, {
  String? outputPath,
}) {
  var sanitized = output?.trim() ?? '';
  if (sanitized.isEmpty) {
    return '';
  }
  final path = outputPath?.trim();
  if (path != null && path.isNotEmpty) {
    sanitized = sanitized.replaceAll(path, '<story-output>');
  }
  final lines = sanitized
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) {
    return '';
  }
  return lines.length <= 8
      ? lines.join(' | ')
      : lines.skip(lines.length - 8).join(' | ');
}
