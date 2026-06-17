import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/components/voip/stream_test_runner.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:path/path.dart' as path;

class StreamTestAutomationRequest {
  const StreamTestAutomationRequest({
    required this.id,
    this.presetKeys = const ['smooth', 'balanced', 'highQuality'],
    this.duration = const Duration(seconds: 30),
    this.warmup = const Duration(seconds: 5),
    this.windowsBackendMode,
    this.compareWindowsBackends = false,
    this.forceFullFrameDirtyRegions = false,
    this.nativeFramePacingEnabled = true,
    this.dummyNv12LiveSender = false,
    this.sourceProcessId,
    this.sourceTitle,
    this.captureTarget = const GameCaptureTestTargetConfig(enabled: true),
    this.runningPath,
  });

  final String id;
  final List<String> presetKeys;
  final Duration duration;
  final Duration warmup;
  final String? windowsBackendMode;
  final bool compareWindowsBackends;
  final bool forceFullFrameDirtyRegions;
  final bool nativeFramePacingEnabled;
  final bool dummyNv12LiveSender;
  final int? sourceProcessId;
  final String? sourceTitle;
  final GameCaptureTestTargetConfig captureTarget;
  final String? runningPath;

  factory StreamTestAutomationRequest.fromJson(
    Map<String, Object?> json, {
    String? runningPath,
  }) {
    final captureTargetJson = _mapValue(json['captureTarget']);
    final targetWidth = _intValue(captureTargetJson['width']) ?? 1920;
    final targetHeight = _intValue(captureTargetJson['height']) ?? 1080;
    final targetMode = _stringValue(captureTargetJson['mode']) ??
        _stringValue(captureTargetJson['windowMode']) ??
        'windowed';
    final targetScene = _stringValue(captureTargetJson['scene']) ?? 'gameplay';
    final targetFps = _stringValue(captureTargetJson['fps']) ?? '60';
    final launchTarget = _boolValue(json['launchCaptureTarget']) ??
        _boolValue(captureTargetJson['enabled']) ??
        true;
    final requestedSourceMode = (_stringValue(json['gameCaptureSourceMode']) ??
            _stringValue(json['sourceMode']))
        ?.trim()
        .toLowerCase();
    final dummyNv12LiveSender = _boolValue(json['dummyNv12LiveSender']) ??
        (requestedSourceMode == 'dummy-nv12-live-sender');
    return StreamTestAutomationRequest(
      id: _safeId(_stringValue(json['id']) ?? _utcStamp()),
      presetKeys: _presetKeys(json['presets']),
      duration: Duration(
        seconds:
            (_intValue(json['durationSeconds']) ?? 30).clamp(5, 600).toInt(),
      ),
      warmup: Duration(
        seconds: (_intValue(json['warmupSeconds']) ?? 5).clamp(0, 120).toInt(),
      ),
      windowsBackendMode: _stringValue(json['windowsBackendMode']) ??
          _stringValue(json['backendMode']),
      compareWindowsBackends:
          _boolValue(json['compareWindowsBackends']) ?? false,
      forceFullFrameDirtyRegions:
          _boolValue(json['forceFullFrameDirtyRegions']) ?? false,
      nativeFramePacingEnabled:
          _boolValue(json['nativeFramePacingEnabled']) ?? true,
      dummyNv12LiveSender: dummyNv12LiveSender,
      sourceProcessId:
          _intValue(json['sourceProcessId']) ?? _intValue(json['processId']),
      sourceTitle: _stringValue(json['sourceTitle']) ??
          _stringValue(json['windowTitle']),
      captureTarget: GameCaptureTestTargetConfig(
        enabled: launchTarget,
        width: targetWidth,
        height: targetHeight,
        windowMode: targetMode,
        scene: targetScene,
        fps: targetFps,
        title: _stringValue(captureTargetJson['title']) ??
            'Inter Galactic Capture Target',
      ),
      runningPath: runningPath,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'presets': presetKeys,
      'durationSeconds': duration.inSeconds,
      'warmupSeconds': warmup.inSeconds,
      'windowsBackendMode': windowsBackendMode,
      'compareWindowsBackends': compareWindowsBackends,
      'forceFullFrameDirtyRegions': forceFullFrameDirtyRegions,
      'nativeFramePacingEnabled': nativeFramePacingEnabled,
      'dummyNv12LiveSender': dummyNv12LiveSender,
      'sourceProcessId': sourceProcessId,
      'sourceTitle': sourceTitle,
      'captureTarget': captureTarget.toJson(),
      'runningPath': runningPath,
    };
  }

  Map<String, Object?> toDiagnosticJson() {
    return {
      'id': id,
      'presets': presetKeys,
      'durationSeconds': duration.inSeconds,
      'warmupSeconds': warmup.inSeconds,
      'windowsBackendMode': windowsBackendMode,
      'compareWindowsBackends': compareWindowsBackends,
      'forceFullFrameDirtyRegions': forceFullFrameDirtyRegions,
      'nativeFramePacingEnabled': nativeFramePacingEnabled,
      'dummyNv12LiveSender': dummyNv12LiveSender,
      'sourceProcessIdSet': sourceProcessId != null,
      'sourceTitleSet': sourceTitle != null && sourceTitle!.trim().isNotEmpty,
      'captureTarget': {
        'enabled': captureTarget.enabled,
        'width': captureTarget.width,
        'height': captureTarget.height,
        'windowMode': captureTarget.windowMode,
        'scene': captureTarget.scene,
        'fps': captureTarget.fps,
        'durationMs': captureTarget.duration.inMilliseconds,
        'titleSet': captureTarget.title.trim().isNotEmpty,
        'executablePathOverrideSet':
            captureTarget.executablePathOverride != null &&
                captureTarget.executablePathOverride!.trim().isNotEmpty,
        'outputRootOverrideSet': captureTarget.outputRootOverride != null &&
            captureTarget.outputRootOverride!.trim().isNotEmpty,
      },
      'runningPathSet': runningPath != null,
    };
  }
}

class StreamTestAutomationCommandChannel {
  const StreamTestAutomationCommandChannel();

  static const requestFileName = 'stream-test-request.json';
  static const staleRunningTimeout = Duration(minutes: 30);
  static final _runningFileNamePattern = RegExp(
    r'^stream-test-request-(.+)\.running\.json$',
  );

  Future<StreamTestAutomationRequest?> takePending() async {
    if (!Platform.isWindows) {
      return null;
    }
    final requestFile = File(await requestFilePath());
    final directory = requestFile.parent;
    if (await directory.exists()) {
      try {
        await _completeStaleRunningFiles(directory);
      } catch (_) {
        // Stale cleanup is best-effort; a fresh request should still run.
      }
    }
    if (!await requestFile.exists()) {
      return null;
    }
    await directory.create(recursive: true);
    final raw = await requestFile.readAsString();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      await _writeError(
        directory.path,
        'invalid',
        'request JSON could not be decoded: $error',
      );
      await requestFile.delete();
      return null;
    }
    if (decoded is! Map) {
      await _writeError(directory.path, 'invalid', 'request JSON is not a map');
      await requestFile.delete();
      return null;
    }
    final requestJson = decoded.map((key, value) => MapEntry(
          key.toString(),
          value,
        ));
    final id = _safeId(_stringValue(requestJson['id']) ?? _utcStamp());
    final runningPath = path.join(
      directory.path,
      'stream-test-request-$id.running.json',
    );
    final runningFile = File(runningPath);
    if (await runningFile.exists()) {
      await runningFile.delete();
    }
    await requestFile.rename(runningPath);
    final request = StreamTestAutomationRequest.fromJson(
      requestJson,
      runningPath: runningPath,
    );
    try {
      await _writeRunningFile(runningFile, request);
    } catch (_) {
      // The renamed request itself remains as the fallback crash breadcrumb.
    }
    return request;
  }

  Future<void> complete(
    StreamTestAutomationRequest request, {
    String? reportPath,
    String? error,
  }) async {
    if (!Platform.isWindows) {
      return;
    }
    final root = await _streamTestDirectoryPath();
    await Directory(root).create(recursive: true);
    final completionPath = path.join(
      root,
      'stream-test-request-${request.id}.complete.json',
    );
    await File(completionPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 'intergalactic.streamTestAutomationResult.v1',
        'id': request.id,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'status': error == null ? 'completed' : 'failed',
        'reportPath': reportPath,
        'error': error,
        'request': request.toDiagnosticJson(),
      }),
      flush: true,
    );
    final runningPath = request.runningPath;
    if (runningPath != null) {
      final runningFile = File(runningPath);
      if (await runningFile.exists()) {
        await runningFile.delete();
      }
    }
  }

  Future<String> requestFilePath() async {
    return path.join(await _streamTestDirectoryPath(), requestFileName);
  }

  Future<void> _writeError(
    String root,
    String id,
    String error,
  ) async {
    await File(path.join(root, 'stream-test-request-$id.error.json'))
        .writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'schema': 'intergalactic.streamTestAutomationResult.v1',
        'id': id,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'failed',
        'error': error,
      }),
      flush: true,
    );
  }

  Future<void> _writeRunningFile(
    File runningFile,
    StreamTestAutomationRequest request,
  ) async {
    await runningFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 'intergalactic.streamTestAutomationRunning.v1',
        'id': request.id,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'running',
        'request': request.toDiagnosticJson(),
      }),
      flush: true,
    );
  }

  Future<void> _completeStaleRunningFiles(Directory directory) async {
    final now = DateTime.now();
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final match = _runningFileNamePattern.firstMatch(
        path.basename(entity.path),
      );
      if (match == null) {
        continue;
      }
      final stat = await entity.stat();
      if (now.difference(stat.modified) < staleRunningTimeout) {
        continue;
      }
      final id = _safeId(match.group(1) ?? 'stale');
      final runningMetadata = await _readRunningFileMetadata(entity);
      final completionFile = File(
        path.join(directory.path, 'stream-test-request-$id.complete.json'),
      );
      if (!await completionFile.exists()) {
        await completionFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'schema': 'intergalactic.streamTestAutomationResult.v1',
            'id': id,
            'completedAt': DateTime.now().toUtc().toIso8601String(),
            'startedAt': runningMetadata.startedAt,
            'status': 'failed',
            'error': 'stream test automation timed out before completion',
            'request': runningMetadata.request,
            'runningPathSet': true,
          }),
          flush: true,
        );
      }
      if (await entity.exists()) {
        await entity.delete();
      }
    }
  }

  Future<String> _streamTestDirectoryPath() async {
    return path.join(await AppConfig.getLogDirectoryPath(), 'stream-tests');
  }

  Future<_RunningStreamTestMetadata> _readRunningFileMetadata(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const _RunningStreamTestMetadata();
      }
      final startedAt = _stringValue(decoded['startedAt']);
      final request = _diagnosticRequestFromRunningJson(decoded);
      return _RunningStreamTestMetadata(
        startedAt: startedAt,
        request: request,
      );
    } catch (_) {
      return const _RunningStreamTestMetadata();
    }
  }

  Map<String, Object?>? _diagnosticRequestFromRunningJson(Map decoded) {
    final requestValue = decoded['request'];
    if (requestValue is Map) {
      final requestJson = requestValue.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (requestJson.containsKey('sourceProcessIdSet') ||
          requestJson.containsKey('sourceTitleSet')) {
        return requestJson;
      }
      try {
        return StreamTestAutomationRequest.fromJson(
          requestJson,
        ).toDiagnosticJson();
      } catch (_) {
        return null;
      }
    }
    final requestJson = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    try {
      return StreamTestAutomationRequest.fromJson(
        requestJson,
      ).toDiagnosticJson();
    } catch (_) {
      return null;
    }
  }
}

class _RunningStreamTestMetadata {
  const _RunningStreamTestMetadata({
    this.startedAt,
    this.request,
  });

  final String? startedAt;
  final Map<String, Object?>? request;
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return null;
}

List<String> _presetKeys(Object? value) {
  final raw =
      value is Iterable ? value : const ['smooth', 'balanced', 'highQuality'];
  final keys = raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return keys.isEmpty ? const ['smooth', 'balanced', 'highQuality'] : keys;
}

String _safeId(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-');
  return sanitized.isEmpty ? _utcStamp() : sanitized;
}

String _utcStamp() {
  return DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
}
