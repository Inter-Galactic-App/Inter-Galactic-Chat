import 'package:intergalactic/client/components/voip/stream_test_runner.dart';

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
    this.publicationHandoffMaxWidth,
    this.publicationHandoffMaxHeight,
    this.publicationHandoffMaxFps,
    this.publicationHandoffTargetFps,
    this.publicationHandoffBitrateKbps,
    this.publicationHandoffMinBitrateKbps,
    this.publicationHandoffSingleLayer,
    this.preferHardwareEncoding,
    this.receiverProbe = const StreamTestReceiverProbeConfig(),
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
  final int? publicationHandoffMaxWidth;
  final int? publicationHandoffMaxHeight;
  final int? publicationHandoffMaxFps;
  final int? publicationHandoffTargetFps;
  final int? publicationHandoffBitrateKbps;
  final int? publicationHandoffMinBitrateKbps;
  final bool? publicationHandoffSingleLayer;
  final bool? preferHardwareEncoding;
  final StreamTestReceiverProbeConfig receiverProbe;
  final GameCaptureTestTargetConfig captureTarget;
  final String? runningPath;

  factory StreamTestAutomationRequest.fromJson(
    Map<String, Object?> json, {
    String? runningPath,
  }) {
    final captureTargetJson = _mapValue(json['captureTarget']);
    final publicationHandoffJson = _mapValue(json['publicationHandoff']);
    final receiverProbeJson = _mapValue(json['receiverProbe']);
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
      publicationHandoffMaxWidth:
          _intValue(json['publicationHandoffMaxWidth']) ??
              _intValue(publicationHandoffJson['maxWidth']) ??
              _intValue(publicationHandoffJson['width']),
      publicationHandoffMaxHeight:
          _intValue(json['publicationHandoffMaxHeight']) ??
              _intValue(publicationHandoffJson['maxHeight']) ??
              _intValue(publicationHandoffJson['height']),
      publicationHandoffMaxFps: _intValue(json['publicationHandoffMaxFps']) ??
          _intValue(publicationHandoffJson['maxFps']) ??
          _intValue(publicationHandoffJson['maxFrameRate']),
      publicationHandoffTargetFps:
          _intValue(json['publicationHandoffTargetFps']) ??
              _intValue(publicationHandoffJson['targetFps']) ??
              _intValue(publicationHandoffJson['fps']) ??
              _intValue(publicationHandoffJson['targetFrameRate']),
      publicationHandoffBitrateKbps:
          _intValue(json['publicationHandoffBitrateKbps']) ??
              _intValue(publicationHandoffJson['bitrateKbps']) ??
              _intValue(publicationHandoffJson['maxBitrateKbps']),
      publicationHandoffMinBitrateKbps:
          _intValue(json['publicationHandoffMinBitrateKbps']) ??
              _intValue(publicationHandoffJson['minBitrateKbps']),
      publicationHandoffSingleLayer:
          _boolValue(json['publicationHandoffSingleLayer']) ??
              _boolValue(publicationHandoffJson['singleLayer']),
      preferHardwareEncoding: _boolValue(json['preferHardwareEncoding']) ??
          _boolValue(publicationHandoffJson['preferHardwareEncoding']) ??
          _boolValue(publicationHandoffJson['hardwareEncoding']) ??
          _boolValue(publicationHandoffJson['hardware']),
      receiverProbe: StreamTestReceiverProbeConfig(
        enabled: _boolValue(json['receiverProbeEnabled']) ??
            _boolValue(receiverProbeJson['enabled']) ??
            false,
        mode: _receiverProbeMode(
          _stringValue(json['receiverProbeMode']) ??
              _stringValue(receiverProbeJson['mode']),
        ),
        inProcess: _boolValue(json['receiverProbeInProcess']) ??
            _boolValue(receiverProbeJson['inProcess']) ??
            true,
        externalControlPipe: _stringValue(
              json['receiverProbeExternalControlPipe'],
            ) ??
            _stringValue(receiverProbeJson['externalControlPipe']) ??
            _stringValue(receiverProbeJson['controlPipe']),
        startBeforeShare: _boolValue(json['receiverProbeStartBeforeShare']) ??
            _boolValue(receiverProbeJson['startBeforeShare']) ??
            true,
        startDelay: Duration(
          milliseconds: (_intValue(json['receiverProbeStartDelayMs']) ??
                  _intValue(receiverProbeJson['startDelayMs']) ??
                  0)
              .clamp(0, 120000)
              .toInt(),
        ),
      ),
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
      'publicationHandoffMaxWidth': publicationHandoffMaxWidth,
      'publicationHandoffMaxHeight': publicationHandoffMaxHeight,
      'publicationHandoffMaxFps': publicationHandoffMaxFps,
      'publicationHandoffTargetFps': publicationHandoffTargetFps,
      'publicationHandoffBitrateKbps': publicationHandoffBitrateKbps,
      'publicationHandoffMinBitrateKbps': publicationHandoffMinBitrateKbps,
      'publicationHandoffSingleLayer': publicationHandoffSingleLayer,
      'preferHardwareEncoding': preferHardwareEncoding,
      'receiverProbe': receiverProbe.toJson(),
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
      'publicationHandoff': {
        'maxWidth': publicationHandoffMaxWidth,
        'maxHeight': publicationHandoffMaxHeight,
        'maxFps': publicationHandoffMaxFps,
        'targetFps': publicationHandoffTargetFps,
        'bitrateKbps': publicationHandoffBitrateKbps,
        'minBitrateKbps': publicationHandoffMinBitrateKbps,
        'singleLayer': publicationHandoffSingleLayer,
        'preferHardwareEncoding': preferHardwareEncoding,
      },
      'receiverProbe': receiverProbe.toDiagnosticJson(),
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

  Future<StreamTestAutomationRequest?> takePending() async => null;

  Future<void> complete(
    StreamTestAutomationRequest request, {
    String? reportPath,
    String? error,
  }) async {}

  Future<String?> requestFilePath() async => null;
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

StreamTestReceiverProbeMode _receiverProbeMode(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == 'local-preview' ||
      normalized == 'local_preview' ||
      normalized == 'localpreview') {
    return StreamTestReceiverProbeMode.localPreview;
  }
  if (normalized == 'render' || normalized == 'remote-render') {
    return StreamTestReceiverProbeMode.render;
  }
  return StreamTestReceiverProbeMode.decodeOnly;
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
