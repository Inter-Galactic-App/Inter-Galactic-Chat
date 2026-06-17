import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/stream_test_host_load_sampler.dart';
import 'package:intergalactic/client/components/voip/stream_test_loaded_libwebrtc_artifact.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/windows_screen_capture_backend.dart';
import 'package:intergalactic/debug/log.dart';

const streamTestRecommendedNextActions = <String>{
  'fix source selection',
  'fix geometry/scaling',
  'fix capture backend',
  'fix WGC substage',
  'fix window-GDI substage',
  'fix game-capture handoff',
  'fix dirty-region behavior',
  'fix frame pacing',
  'fix encoder path',
  'fix receiver subscription/rendering',
  'inspect server/network',
  'collect one specific missing field',
  'no stream change recommended',
};

const int streamTestDefaultDiagnosticLogMarkerLimit = 240;

typedef StreamTestHostLoadSamplerFactory = StreamTestHostLoadSampler Function(
  int? targetProcessId,
);

abstract class StreamTestTarget {
  String get label;
  String get roomId;
  bool get isSharingScreen;

  Future<void> startPreset(
    ScreenShareProfileConfig profile, {
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    bool nativeFramePacingEnabled = false,
    bool dummyNv12LiveSender = false,
  });
  Future<void> stopShare();
  Future<VoipCallDiagnosticsSnapshot> collectDiagnostics();
}

class StreamTestRunConfig {
  const StreamTestRunConfig({
    required this.presets,
    this.durationPerPreset = const Duration(seconds: 30),
    this.warmupDuration = const Duration(seconds: 5),
    this.sampleInterval = const Duration(seconds: 1),
    this.scenarioLabel = 'current-call',
    this.sourceMetadata,
    this.windowsCaptureBackendMode,
    this.windowsCaptureBackendModes,
    this.windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    this.windowsWindowGdiCaptureMode,
    this.windowsWindowGdiCaptureModes,
    this.nativeFramePacingEnabled = false,
    this.dummyNv12LiveSender = false,
    this.gameCaptureTestTarget,
    this.gameCaptureProbe,
  });

  final List<ScreenShareProfileConfig> presets;
  final Duration durationPerPreset;
  final Duration warmupDuration;
  final Duration sampleInterval;
  final String scenarioLabel;
  final StreamTestSourceMetadata? sourceMetadata;
  final WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
  final List<WindowsScreenCaptureBackendMode?>? windowsCaptureBackendModes;
  final WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode;
  final WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode;
  final List<WindowsWindowGdiCaptureMode?>? windowsWindowGdiCaptureModes;
  final bool nativeFramePacingEnabled;
  final bool dummyNv12LiveSender;
  final GameCaptureTestTargetConfig? gameCaptureTestTarget;
  final GameCaptureProbeConfig? gameCaptureProbe;

  List<WindowsScreenCaptureBackendMode?> get effectiveWindowsBackendModes {
    final modes = windowsCaptureBackendModes;
    final requestedModes = modes != null && modes.isNotEmpty
        ? modes
        : <WindowsScreenCaptureBackendMode?>[windowsCaptureBackendMode];
    final effectiveModes = <WindowsScreenCaptureBackendMode?>[];
    for (final mode in requestedModes) {
      if (mode != null && !mode.streamTestSelectable) {
        continue;
      }
      if (!effectiveModes.contains(mode)) {
        effectiveModes.add(mode);
      }
    }
    if (effectiveModes.isEmpty) {
      effectiveModes.add(null);
    }
    return List.unmodifiable(effectiveModes);
  }

  String get windowsCaptureBackendSelectionLabel {
    final labels = effectiveWindowsBackendModes
        .map((mode) => mode?.label ?? 'App default')
        .toList(growable: false);
    return labels.join(', ');
  }

  List<WindowsWindowGdiCaptureMode?> get effectiveWindowsWindowGdiModes {
    final modes = windowsWindowGdiCaptureModes;
    final requestedModes = modes != null && modes.isNotEmpty
        ? modes
        : <WindowsWindowGdiCaptureMode?>[windowsWindowGdiCaptureMode];
    final effectiveModes = <WindowsWindowGdiCaptureMode?>[];
    for (final mode in requestedModes) {
      if (!effectiveModes.contains(mode)) {
        effectiveModes.add(mode);
      }
    }
    if (effectiveModes.isEmpty) {
      effectiveModes.add(null);
    }
    return List.unmodifiable(effectiveModes);
  }

  String get windowsWindowGdiSelectionLabel {
    final labels = effectiveWindowsWindowGdiModes
        .map((mode) => mode?.label ?? 'Default window GDI')
        .toList(growable: false);
    return labels.join(', ');
  }

  WindowsScreenCaptureBackendMode? get _singleEffectiveWindowsBackendMode {
    final modes = effectiveWindowsBackendModes;
    return modes.length == 1 ? modes.first : null;
  }

  WindowsWindowGdiCaptureMode? get _singleEffectiveWindowsWindowGdiMode {
    final modes = effectiveWindowsWindowGdiModes;
    return modes.length == 1 ? modes.first : null;
  }

  String? get gameCaptureSourceMode =>
      dummyNv12LiveSender ? 'dummy-nv12-live-sender' : null;

  Map<String, Object?> toJson() {
    final singleBackendMode = _singleEffectiveWindowsBackendMode;
    final singleWindowGdiMode = _singleEffectiveWindowsWindowGdiMode;
    return {
      'scenarioLabel': _redactedFreeformLabel(scenarioLabel),
      'durationPerPresetMs': durationPerPreset.inMilliseconds,
      'warmupDurationMs': warmupDuration.inMilliseconds,
      'sampleIntervalMs': sampleInterval.inMilliseconds,
      'source': sourceMetadata?.toJson(),
      'windowsCaptureBackendMode': singleBackendMode?.constraintValue,
      'windowsCaptureBackendSelection':
          singleBackendMode?.label ?? 'App default',
      'windowsCaptureBackendModes': effectiveWindowsBackendModes
          .map((mode) => mode?.constraintValue)
          .toList(growable: false),
      'windowsCaptureBackendSelections': effectiveWindowsBackendModes
          .map((mode) => mode?.label ?? 'App default')
          .toList(growable: false),
      'windowsCaptureDirtyRegionMode':
          windowsCaptureDirtyRegionMode.constraintValue,
      'windowsCaptureDirtyRegionSelection': windowsCaptureDirtyRegionMode.label,
      'windowsWindowGdiCaptureMode': singleWindowGdiMode?.constraintValue,
      'windowsWindowGdiCaptureSelection':
          singleWindowGdiMode?.label ?? 'Default window GDI',
      'windowsWindowGdiCaptureModes': effectiveWindowsWindowGdiModes
          .map((mode) => mode?.constraintValue)
          .toList(growable: false),
      'windowsWindowGdiCaptureSelections': effectiveWindowsWindowGdiModes
          .map((mode) => mode?.label ?? 'Default window GDI')
          .toList(growable: false),
      'nativeFramePacingEnabled': nativeFramePacingEnabled,
      'dummyNv12LiveSender': dummyNv12LiveSender,
      'gameCaptureSourceMode': gameCaptureSourceMode,
      'gameCaptureTestTarget': gameCaptureTestTarget?.toJson(),
      'gameCaptureProbe': gameCaptureProbe?.toJson(),
      'presets': presets.map(_profileToJson).toList(growable: false),
    };
  }
}

class GameCaptureTestTargetConfig {
  const GameCaptureTestTargetConfig({
    this.enabled = false,
    this.width = 1920,
    this.height = 1080,
    this.windowMode = 'windowed',
    this.scene = 'gameplay',
    this.fps = '60',
    this.duration = Duration.zero,
    this.title = 'Inter Galactic Capture Target',
    this.executablePathOverride,
    this.outputRootOverride,
  });

  final bool enabled;
  final int width;
  final int height;
  final String windowMode;
  final String scene;
  final String fps;
  final Duration duration;
  final String title;
  final String? executablePathOverride;
  final String? outputRootOverride;

  String get resolutionLabel => '${width}x$height';

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'width': width,
      'height': height,
      'windowMode': windowMode,
      'scene': scene,
      'fps': fps,
      'durationMs': duration.inMilliseconds,
      'title': title,
      'executablePathOverrideSet': executablePathOverride != null &&
          executablePathOverride!.trim().isNotEmpty,
      'outputRootOverrideSet':
          outputRootOverride != null && outputRootOverride!.trim().isNotEmpty,
    };
  }
}

class GameCaptureTestTargetResult {
  const GameCaptureTestTargetResult({
    required this.config,
    required this.status,
    this.reason,
    this.processId,
    this.executablePath,
    this.outputDirectoryPath,
    this.diagnostics,
    this.selectedAutomatically = false,
  });

  final GameCaptureTestTargetConfig config;
  final String status;
  final String? reason;
  final int? processId;
  final String? executablePath;
  final String? outputDirectoryPath;
  final Map<String, Object?>? diagnostics;
  final bool selectedAutomatically;

  factory GameCaptureTestTargetResult.notApplicable({
    required GameCaptureTestTargetConfig config,
    required String reason,
  }) {
    return GameCaptureTestTargetResult(
      config: config,
      status: 'notApplicable',
      reason: reason,
    );
  }

  factory GameCaptureTestTargetResult.unavailable({
    required GameCaptureTestTargetConfig config,
    required String reason,
    String? executablePath,
  }) {
    return GameCaptureTestTargetResult(
      config: config,
      status: 'unavailable',
      reason: reason,
      executablePath: executablePath,
    );
  }

  factory GameCaptureTestTargetResult.launched({
    required GameCaptureTestTargetConfig config,
    required int processId,
    required String executablePath,
    required String outputDirectoryPath,
  }) {
    return GameCaptureTestTargetResult(
      config: config,
      status: 'launched',
      processId: processId,
      executablePath: executablePath,
      outputDirectoryPath: outputDirectoryPath,
    );
  }

  GameCaptureTestTargetResult withSelection({required bool automatic}) {
    return GameCaptureTestTargetResult(
      config: config,
      status: status,
      reason: reason,
      processId: processId,
      executablePath: executablePath,
      outputDirectoryPath: outputDirectoryPath,
      diagnostics: diagnostics,
      selectedAutomatically: automatic,
    );
  }

  GameCaptureTestTargetResult withDiagnostics(
    Map<String, Object?>? diagnostics, {
    String? status,
    String? reason,
  }) {
    return GameCaptureTestTargetResult(
      config: config,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      processId: processId,
      executablePath: executablePath,
      outputDirectoryPath: outputDirectoryPath,
      diagnostics: diagnostics ?? this.diagnostics,
      selectedAutomatically: selectedAutomatically,
    );
  }

  double? get presentFps => _doubleFromJson(diagnostics?['presentFps']);
  double? get presentGapP95Ms =>
      _doubleFromJson(diagnostics?['presentGapP95Ms']);
  double? get presentGapMaxMs =>
      _doubleFromJson(diagnostics?['presentGapMaxMs']);
  int? get framesPresented => _intFromJson(diagnostics?['framesPresented']);

  bool get hasDiagnostics => diagnostics != null && diagnostics!.isNotEmpty;

  Map<String, Object?> toJson() {
    return {
      'status': status,
      'reason': reason,
      'processIdAvailable': processId != null,
      'executablePathSet': executablePath != null && executablePath!.isNotEmpty,
      'outputDirectoryPathSet':
          outputDirectoryPath != null && outputDirectoryPath!.isNotEmpty,
      'selectedAutomatically': selectedAutomatically,
      'config': config.toJson(),
      'diagnostics': diagnostics,
    };
  }

  String toMarkdown() {
    final fpsLabel = config.fps == 'uncapped' ? 'uncapped' : '${config.fps}fps';
    final buffer = StringBuffer()
      ..writeln('- Status: $status')
      ..writeln('- Target: ${config.title}')
      ..writeln('- Requested: ${config.resolutionLabel} $fpsLabel '
          '${config.windowMode} ${config.scene}')
      ..writeln('- Process id available: ${processId != null ? 'yes' : 'no'}')
      ..writeln('- Auto-selected source: '
          '${selectedAutomatically ? 'yes' : 'no'}');
    if (reason != null) {
      buffer.writeln('- Reason: $reason');
    }
    if (outputDirectoryPath != null) {
      buffer.writeln('- Output directory: configured');
    }
    if (hasDiagnostics) {
      buffer
        ..writeln('- Present FPS: ${_number(presentFps)}')
        ..writeln('- Present gaps: ${_milliseconds(presentGapP95Ms)} p95 / '
            '${_milliseconds(presentGapMaxMs)} max')
        ..writeln('- Frames presented: ${framesPresented ?? 0}');
    } else {
      buffer.writeln('- Diagnostics: not available yet');
    }
    return buffer.toString();
  }
}

class GameCaptureProbeConfig {
  const GameCaptureProbeConfig({
    this.enabled = false,
    this.duration = const Duration(seconds: 10),
    this.maxSavedFrames = 0,
    this.hostTextureConsumerEnabled = true,
    this.hostProofFrames = 0,
    this.publicationHandoffEnabled = true,
    this.publicationHandoffMaxWidth = 1280,
    this.publicationHandoffMaxHeight = 720,
    this.publicationHandoffTargetFps = 30,
    this.targetProcessId,
    this.helperPathOverride,
    this.outputRootOverride,
    this.sourceMetadata,
    this.timing = GameCaptureProbeTiming.standalone,
  });

  final bool enabled;
  final Duration duration;
  final int maxSavedFrames;
  final bool hostTextureConsumerEnabled;
  final int hostProofFrames;
  final bool publicationHandoffEnabled;
  final int publicationHandoffMaxWidth;
  final int publicationHandoffMaxHeight;
  final int publicationHandoffTargetFps;
  final int? targetProcessId;
  final String? helperPathOverride;
  final String? outputRootOverride;
  final StreamTestSourceMetadata? sourceMetadata;
  final GameCaptureProbeTiming timing;

  int? get effectiveTargetProcessId =>
      targetProcessId ?? sourceMetadata?.processId;

  GameCaptureProbeConfig resolveSource(
    StreamTestSourceMetadata? metadata, {
    Duration? defaultDuration,
    Duration? minimumDuration,
    GameCaptureProbeTiming? timing,
    int? publicationHandoffMaxWidth,
    int? publicationHandoffMaxHeight,
    int? publicationHandoffTargetFps,
  }) {
    final requestedDuration = duration.inMilliseconds > 0
        ? duration
        : defaultDuration ?? const Duration(seconds: 10);
    final effectiveDuration = minimumDuration != null &&
            minimumDuration.inMilliseconds > requestedDuration.inMilliseconds
        ? minimumDuration
        : requestedDuration;
    return GameCaptureProbeConfig(
      enabled: enabled,
      duration: effectiveDuration,
      maxSavedFrames: maxSavedFrames,
      hostTextureConsumerEnabled: hostTextureConsumerEnabled,
      hostProofFrames: hostProofFrames,
      publicationHandoffEnabled: publicationHandoffEnabled,
      publicationHandoffMaxWidth:
          publicationHandoffMaxWidth ?? this.publicationHandoffMaxWidth,
      publicationHandoffMaxHeight:
          publicationHandoffMaxHeight ?? this.publicationHandoffMaxHeight,
      publicationHandoffTargetFps:
          publicationHandoffTargetFps ?? this.publicationHandoffTargetFps,
      targetProcessId: targetProcessId,
      helperPathOverride: helperPathOverride,
      outputRootOverride: outputRootOverride,
      sourceMetadata: sourceMetadata ?? metadata,
      timing: timing ?? this.timing,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'durationMs': duration.inMilliseconds,
      'maxSavedFrames': maxSavedFrames,
      'hostTextureConsumerEnabled': hostTextureConsumerEnabled,
      'hostProofFrames': hostProofFrames,
      'publicationHandoffEnabled': publicationHandoffEnabled,
      'publicationHandoffMaxWidth': publicationHandoffMaxWidth,
      'publicationHandoffMaxHeight': publicationHandoffMaxHeight,
      'publicationHandoffTargetFps': publicationHandoffTargetFps,
      'timing': timing.value,
      'targetProcessIdAvailable': effectiveTargetProcessId != null,
      'helperPathOverrideSet':
          helperPathOverride != null && helperPathOverride!.isNotEmpty,
      'outputRootOverrideSet':
          outputRootOverride != null && outputRootOverride!.isNotEmpty,
      'source': sourceMetadata?.toJson(),
    };
  }
}

enum GameCaptureProbeTiming {
  standalone('standalone'),
  concurrentWithInitialPreset('concurrentWithInitialPreset');

  const GameCaptureProbeTiming(this.value);

  final String value;

  String get label {
    switch (this) {
      case GameCaptureProbeTiming.standalone:
        return 'standalone/probe-only';
      case GameCaptureProbeTiming.concurrentWithInitialPreset:
        return 'concurrent with initial stream-test preset';
    }
  }

  String get progressDetail {
    switch (this) {
      case GameCaptureProbeTiming.standalone:
        return 'local diagnostics only';
      case GameCaptureProbeTiming.concurrentWithInitialPreset:
        return 'running with first stream-test preset';
    }
  }
}

abstract class GameCaptureProbeRunner {
  Future<GameCaptureProbeResult> run(GameCaptureProbeConfig config);
}

class UnsupportedGameCaptureProbeRunner implements GameCaptureProbeRunner {
  const UnsupportedGameCaptureProbeRunner();

  @override
  Future<GameCaptureProbeResult> run(GameCaptureProbeConfig config) async {
    return GameCaptureProbeResult.notApplicable(
      config: config,
      reason: 'game-capture probe runner is not available on this platform',
    );
  }
}

class GameCaptureProbeResult {
  const GameCaptureProbeResult({
    required this.status,
    required this.reason,
    required this.config,
    this.resultDirectoryPath,
    this.helperPath,
    this.helperExitCode,
    this.metadata = const {},
    this.startedAt,
    this.endedAt,
  });

  factory GameCaptureProbeResult.fromMetadata({
    required GameCaptureProbeConfig config,
    required Map<String, Object?> metadata,
    String? resultDirectoryPath,
    String? helperPath,
    int? helperExitCode,
  }) {
    final attachStatus = _stringFromJson(metadata['attachStatus']) ?? 'unknown';
    final status = attachStatus == 'attached'
        ? StreamDiagnosticCoverageStatus.available
        : StreamDiagnosticCoverageStatus.unavailable;
    final reason = attachStatus == 'attached'
        ? 'D3D11 hook attached and wrote metadata'
        : _stringFromJson(metadata['result']) ??
            _stringFromJson(metadata['lastError']) ??
            'helper attach status: $attachStatus';
    return GameCaptureProbeResult(
      status: status,
      reason: reason,
      config: config,
      resultDirectoryPath: resultDirectoryPath,
      helperPath: helperPath,
      helperExitCode: helperExitCode,
      metadata: Map.unmodifiable(metadata),
      startedAt: _dateTimeFromJson(metadata['startedAt']),
      endedAt: _dateTimeFromJson(metadata['endedAt']),
    );
  }

  factory GameCaptureProbeResult.unavailable({
    required GameCaptureProbeConfig config,
    required String reason,
    String? helperPath,
    int? helperExitCode,
  }) {
    return GameCaptureProbeResult(
      status: StreamDiagnosticCoverageStatus.unavailable,
      reason: reason,
      config: config,
      helperPath: helperPath,
      helperExitCode: helperExitCode,
    );
  }

  factory GameCaptureProbeResult.missing({
    required GameCaptureProbeConfig config,
    required String reason,
    String? helperPath,
    int? helperExitCode,
  }) {
    return GameCaptureProbeResult(
      status: StreamDiagnosticCoverageStatus.missing,
      reason: reason,
      config: config,
      helperPath: helperPath,
      helperExitCode: helperExitCode,
    );
  }

  factory GameCaptureProbeResult.notApplicable({
    required GameCaptureProbeConfig config,
    required String reason,
  }) {
    return GameCaptureProbeResult(
      status: StreamDiagnosticCoverageStatus.notApplicable,
      reason: reason,
      config: config,
    );
  }

  final StreamDiagnosticCoverageStatus status;
  final String reason;
  final GameCaptureProbeConfig config;
  final String? resultDirectoryPath;
  final String? helperPath;
  final int? helperExitCode;
  final Map<String, Object?> metadata;
  final DateTime? startedAt;
  final DateTime? endedAt;

  String? get schema => _stringFromJson(metadata['schema']);
  String? get requestedBackend => _stringFromJson(metadata['requestedBackend']);
  String? get attachStatus => _stringFromJson(metadata['attachStatus']);
  String? get detectedGraphicsApi =>
      _stringFromJson(metadata['detectedGraphicsApi']);
  double? get presentFps => _doubleFromJson(metadata['presentFps']);
  double? get presentGapP50Ms => _doubleFromJson(metadata['presentGapP50Ms']);
  double? get presentGapP95Ms => _doubleFromJson(metadata['presentGapP95Ms']);
  double? get presentGapMaxMs => _doubleFromJson(metadata['presentGapMaxMs']);
  int? get presentFrameCount => _intFromJson(metadata['presentFrameCount']);
  int? get backbufferWidth => _intFromJson(metadata['backbufferWidth']);
  int? get backbufferHeight => _intFromJson(metadata['backbufferHeight']);
  String? get backbufferFormat => _stringFromJson(metadata['backbufferFormat']);
  int? get sharedTextureRingDepth =>
      _intFromJson(metadata['sharedTextureRingDepth']);
  bool? get sharedTextureSupported =>
      _boolFromJson(metadata['sharedTextureSupported']);
  double? get copyAvgMs => _doubleFromJson(metadata['copyAvgMs']);
  double? get copyMaxMs => _doubleFromJson(metadata['copyMaxMs']);
  double? get resolveAvgMs => _doubleFromJson(metadata['resolveAvgMs']);
  double? get resolveMaxMs => _doubleFromJson(metadata['resolveMaxMs']);
  int? get copiedFrames => _intFromJson(metadata['copiedFrames']);
  int? get droppedFrames => _intFromJson(metadata['droppedFrames']);
  int? get overwrittenFrames => _intFromJson(metadata['overwrittenFrames']);
  int? get cpuReadbackCount => _intFromJson(metadata['cpuReadbackCount']);
  int? get savedFrames => _intFromJson(metadata['savedFrames']);
  int? get visibleFrames => _intFromJson(metadata['visibleFrames']);
  int? get resizeDeviceLossCount =>
      _intFromJson(metadata['resizeDeviceLossCount']);
  String? get fallbackReason => _stringFromJson(metadata['fallbackReason']);
  String? get hookStopReason => _stringFromJson(metadata['hookStopReason']);
  String? get lastError => _stringFromJson(metadata['lastError']);
  Map<String, Object?> get hostConsumerMetadata {
    final value = metadata['hostConsumer'];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  bool? get hostConsumerEnabled =>
      _boolFromJson(hostConsumerMetadata['enabled']);
  bool? get hostSharedStateAvailable =>
      _boolFromJson(hostConsumerMetadata['sharedStateAvailable']);
  bool? get hostD3dDeviceCreated =>
      _boolFromJson(hostConsumerMetadata['d3dDeviceCreated']);
  bool? get hostOpenedSharedTexture =>
      _boolFromJson(hostConsumerMetadata['openedSharedTexture']);
  int? get hostOpenedTextureSlots =>
      _intFromJson(hostConsumerMetadata['openedTextureSlots']);
  int? get hostSharedTextureOpenFailures =>
      _intFromJson(hostConsumerMetadata['sharedTextureOpenFailures']);
  int? get hostObservedFrameSignals =>
      _intFromJson(hostConsumerMetadata['observedFrameSignals']);
  int? get hostConsumedFrames =>
      _intFromJson(hostConsumerMetadata['consumedFrames']);
  int? get hostDuplicateSignals =>
      _intFromJson(hostConsumerMetadata['duplicateSignals']);
  int? get hostMissedFrames =>
      _intFromJson(hostConsumerMetadata['missedFrames']);
  int? get hostInvalidStateReads =>
      _intFromJson(hostConsumerMetadata['invalidStateReads']);
  double? get hostFrameAgeAvgMs =>
      _doubleFromJson(hostConsumerMetadata['frameAgeAvgMs']);
  double? get hostFrameAgeP95Ms =>
      _doubleFromJson(hostConsumerMetadata['frameAgeP95Ms']);
  double? get hostFrameAgeMaxMs =>
      _doubleFromJson(hostConsumerMetadata['frameAgeMaxMs']);
  double? get hostConsumerGapP50Ms =>
      _doubleFromJson(hostConsumerMetadata['consumerGapP50Ms']);
  double? get hostConsumerGapP95Ms =>
      _doubleFromJson(hostConsumerMetadata['consumerGapP95Ms']);
  double? get hostConsumerGapMaxMs =>
      _doubleFromJson(hostConsumerMetadata['consumerGapMaxMs']);
  int? get hostProofReadbackCount =>
      _intFromJson(hostConsumerMetadata['proofReadbackCount']);
  int? get hostVisibleProofFrames =>
      _intFromJson(hostConsumerMetadata['visibleProofFrames']);
  double? get hostProofReadbackAvgMs =>
      _doubleFromJson(hostConsumerMetadata['proofReadbackAvgMs']);
  double? get hostProofReadbackMaxMs =>
      _doubleFromJson(hostConsumerMetadata['proofReadbackMaxMs']);
  String? get hostConsumerLastError =>
      _stringFromJson(hostConsumerMetadata['lastError']);

  Map<String, Object?> get publicationHandoffMetadata {
    final value = metadata['publicationHandoff'];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  bool? get publicationHandoffEnabled =>
      _boolFromJson(publicationHandoffMetadata['enabled']);
  String? get publicationHandoffMode =>
      _stringFromJson(publicationHandoffMetadata['mode']);
  String? get publicationHandoffScaleMode =>
      _stringFromJson(publicationHandoffMetadata['scaleMode']);
  bool? get publicationHandoffSharedStateAvailable =>
      _boolFromJson(publicationHandoffMetadata['sharedStateAvailable']);
  bool? get publicationHandoffD3dDeviceCreated =>
      _boolFromJson(publicationHandoffMetadata['d3dDeviceCreated']);
  bool? get publicationHandoffOpenedSharedTexture =>
      _boolFromJson(publicationHandoffMetadata['openedSharedTexture']);
  int? get publicationHandoffOpenedTextureSlots =>
      _intFromJson(publicationHandoffMetadata['openedTextureSlots']);
  int? get publicationHandoffSharedTextureOpenFailures =>
      _intFromJson(publicationHandoffMetadata['sharedTextureOpenFailures']);
  bool? get publicationHandoffUnsupportedFormat =>
      _boolFromJson(publicationHandoffMetadata['unsupportedFormat']);
  int? get publicationHandoffRequestedMaxWidth =>
      _intFromJson(publicationHandoffMetadata['requestedMaxWidth']);
  int? get publicationHandoffRequestedMaxHeight =>
      _intFromJson(publicationHandoffMetadata['requestedMaxHeight']);
  int? get publicationHandoffRequestedTargetFps =>
      _intFromJson(publicationHandoffMetadata['requestedTargetFps']);
  int? get publicationHandoffSourceWidth =>
      _intFromJson(publicationHandoffMetadata['sourceWidth']);
  int? get publicationHandoffSourceHeight =>
      _intFromJson(publicationHandoffMetadata['sourceHeight']);
  int? get publicationHandoffOutputWidth =>
      _intFromJson(publicationHandoffMetadata['outputWidth']);
  int? get publicationHandoffOutputHeight =>
      _intFromJson(publicationHandoffMetadata['outputHeight']);
  int? get publicationHandoffObservedFrameSignals =>
      _intFromJson(publicationHandoffMetadata['observedFrameSignals']);
  int? get publicationHandoffInputFramesSeen =>
      _intFromJson(publicationHandoffMetadata['inputFramesSeen']);
  int? get publicationHandoffDuplicateSignals =>
      _intFromJson(publicationHandoffMetadata['duplicateSignals']);
  int? get publicationHandoffMissedInputFrames =>
      _intFromJson(publicationHandoffMetadata['missedInputFrames']);
  int? get publicationHandoffPacedDropFrames =>
      _intFromJson(publicationHandoffMetadata['pacedDropFrames']);
  int? get publicationHandoffReadbackFrames =>
      _intFromJson(publicationHandoffMetadata['readbackFrames']);
  int? get publicationHandoffOutputFrames =>
      _intFromJson(publicationHandoffMetadata['outputFrames']);
  int? get publicationHandoffVisibleOutputFrames =>
      _intFromJson(publicationHandoffMetadata['visibleOutputFrames']);
  int? get publicationHandoffInvalidStateReads =>
      _intFromJson(publicationHandoffMetadata['invalidStateReads']);
  double? get publicationHandoffFrameAgeAvgMs =>
      _doubleFromJson(publicationHandoffMetadata['frameAgeAvgMs']);
  double? get publicationHandoffFrameAgeP95Ms =>
      _doubleFromJson(publicationHandoffMetadata['frameAgeP95Ms']);
  double? get publicationHandoffFrameAgeMaxMs =>
      _doubleFromJson(publicationHandoffMetadata['frameAgeMaxMs']);
  double? get publicationHandoffOutputFps =>
      _doubleFromJson(publicationHandoffMetadata['outputFps']);
  double? get publicationHandoffOutputGapP50Ms =>
      _doubleFromJson(publicationHandoffMetadata['outputGapP50Ms']);
  double? get publicationHandoffOutputGapP95Ms =>
      _doubleFromJson(publicationHandoffMetadata['outputGapP95Ms']);
  double? get publicationHandoffOutputGapMaxMs =>
      _doubleFromJson(publicationHandoffMetadata['outputGapMaxMs']);
  double? get publicationHandoffReadbackAvgMs =>
      _doubleFromJson(publicationHandoffMetadata['readbackAvgMs']);
  double? get publicationHandoffReadbackP95Ms =>
      _doubleFromJson(publicationHandoffMetadata['readbackP95Ms']);
  double? get publicationHandoffReadbackMaxMs =>
      _doubleFromJson(publicationHandoffMetadata['readbackMaxMs']);
  double? get publicationHandoffScaleAvgMs =>
      _doubleFromJson(publicationHandoffMetadata['scaleAvgMs']);
  double? get publicationHandoffScaleP95Ms =>
      _doubleFromJson(publicationHandoffMetadata['scaleP95Ms']);
  double? get publicationHandoffScaleMaxMs =>
      _doubleFromJson(publicationHandoffMetadata['scaleMaxMs']);
  double? get publicationHandoffTotalFrameAvgMs =>
      _doubleFromJson(publicationHandoffMetadata['totalFrameAvgMs']);
  double? get publicationHandoffTotalFrameP95Ms =>
      _doubleFromJson(publicationHandoffMetadata['totalFrameP95Ms']);
  double? get publicationHandoffTotalFrameMaxMs =>
      _doubleFromJson(publicationHandoffMetadata['totalFrameMaxMs']);
  String? get publicationHandoffLastError =>
      _stringFromJson(publicationHandoffMetadata['lastError']);

  bool get hasHostConsumerEvidence => hostConsumerMetadata.isNotEmpty;
  bool get hasPublicationHandoffEvidence =>
      publicationHandoffMetadata.isNotEmpty;

  bool get hasHealthyHostTextureConsumer {
    if (config.hostTextureConsumerEnabled != true) {
      return false;
    }
    return hostConsumerEnabled == true &&
        hostSharedStateAvailable == true &&
        hostD3dDeviceCreated == true &&
        hostOpenedSharedTexture == true &&
        (hostOpenedTextureSlots ?? 0) > 0 &&
        (hostConsumedFrames ?? 0) > 0 &&
        (hostSharedTextureOpenFailures ?? 0) == 0 &&
        (hostInvalidStateReads ?? 0) == 0;
  }

  bool get hasVisiblePublicationHandoff {
    if (config.publicationHandoffEnabled != true) {
      return false;
    }
    return publicationHandoffEnabled == true &&
        publicationHandoffSharedStateAvailable == true &&
        publicationHandoffD3dDeviceCreated == true &&
        publicationHandoffOpenedSharedTexture == true &&
        (publicationHandoffOpenedTextureSlots ?? 0) > 0 &&
        (publicationHandoffOutputFrames ?? 0) > 0 &&
        (publicationHandoffVisibleOutputFrames ?? 0) > 0 &&
        (publicationHandoffSharedTextureOpenFailures ?? 0) == 0 &&
        (publicationHandoffInvalidStateReads ?? 0) == 0 &&
        publicationHandoffUnsupportedFormat != true;
  }

  bool get hasHealthyPublicationHandoff {
    if (!hasVisiblePublicationHandoff) {
      return false;
    }
    final targetFps = (publicationHandoffRequestedTargetFps ??
            config.publicationHandoffTargetFps)
        .clamp(1, 240)
        .toDouble();
    final outputFps = publicationHandoffOutputFps;
    if (outputFps == null || outputFps < targetFps * 0.85) {
      return false;
    }
    final p95Gap = publicationHandoffOutputGapP95Ms;
    if (p95Gap != null && p95Gap > (1000 / targetFps) * 1.75) {
      return false;
    }
    return true;
  }

  bool get hasSlowPublicationHandoff =>
      hasVisiblePublicationHandoff && !hasHealthyPublicationHandoff;

  String get publicationHandoffHealthLabel {
    if (hasHealthyPublicationHandoff) {
      return 'healthy';
    }
    if (hasSlowPublicationHandoff) {
      return 'slow';
    }
    return 'not_proven';
  }

  bool get hasCadenceEvidence =>
      presentFps != null ||
      presentGapP50Ms != null ||
      presentGapP95Ms != null ||
      presentGapMaxMs != null;

  bool get isHealthyCadence {
    final fps = presentFps;
    final p95 = presentGapP95Ms;
    final max = presentGapMaxMs;
    return attachStatus == 'attached' &&
        detectedGraphicsApi == 'd3d11' &&
        fps != null &&
        fps >= 28 &&
        (p95 == null || p95 <= 50) &&
        (max == null || max <= 150) &&
        (droppedFrames ?? 0) == 0 &&
        (cpuReadbackCount ?? 0) == 0 &&
        (fallbackReason == null || fallbackReason == 'none');
  }

  String get statusName {
    switch (status) {
      case StreamDiagnosticCoverageStatus.available:
        return 'available';
      case StreamDiagnosticCoverageStatus.missing:
        return 'missing';
      case StreamDiagnosticCoverageStatus.unavailable:
        return 'unavailable';
      case StreamDiagnosticCoverageStatus.notApplicable:
        return 'notApplicable';
    }
  }

  String get summaryLabel {
    if (status != StreamDiagnosticCoverageStatus.available) {
      return reason;
    }
    final buffer = StringBuffer()
      ..write('attach=${attachStatus ?? 'unknown'}')
      ..write(' api=${detectedGraphicsApi ?? 'unknown'}')
      ..write(' timing=${config.timing.value}');
    if (presentFps != null) {
      buffer.write(' present=${_number(presentFps)}fps');
    }
    if (presentGapP95Ms != null || presentGapMaxMs != null) {
      buffer.write(
        ' gaps=${_milliseconds(presentGapP95Ms)} p95 / '
        '${_milliseconds(presentGapMaxMs)} max',
      );
    }
    if (backbufferWidth != null && backbufferHeight != null) {
      buffer.write(' backbuffer=${backbufferWidth}x$backbufferHeight');
    }
    if (config.hostTextureConsumerEnabled || hasHostConsumerEvidence) {
      buffer.write(
        ' hostConsumer='
        '${hasHealthyHostTextureConsumer ? 'healthy' : 'not_proven'}',
      );
      if (hostConsumedFrames != null) {
        buffer.write('/${hostConsumedFrames}frames');
      }
    }
    if (config.publicationHandoffEnabled || hasPublicationHandoffEvidence) {
      buffer.write(
        ' handoff=$publicationHandoffHealthLabel',
      );
      if (publicationHandoffOutputFps != null) {
        buffer.write('/${_number(publicationHandoffOutputFps)}fps');
      }
    }
    return buffer.toString();
  }

  String get classificationEvidenceLabel {
    if (!isHealthyCadence) {
      return 'game-capture probe did not prove a healthy D3D11 Present path';
    }
    if (hasSlowPublicationHandoff) {
      return 'D3D11 Present and host texture consumption are usable, but the '
          'local publication handoff is below target cadence; focus next on '
          'GPU-side scale/readback or encoder handoff before LiveKit publish';
    }
    return 'D3D11 Present cadence is healthy, so tested stutter is more likely '
        'in desktop/window capture acquisition, pre-encode handoff, encoder '
        'handoff, or receiver/rendering than in the game swap-chain itself';
  }

  Map<String, Object?> toJson() {
    return {
      'status': statusName,
      'reason': reason,
      'config': config.toJson(),
      'resultDirectoryPathSet':
          resultDirectoryPath != null && resultDirectoryPath!.isNotEmpty,
      'helperPathSet': helperPath != null && helperPath!.isNotEmpty,
      'helperExitCode': helperExitCode,
      'startedAt': startedAt?.toUtc().toIso8601String(),
      'endedAt': endedAt?.toUtc().toIso8601String(),
      'schema': schema,
      'requestedBackend': requestedBackend,
      'attachStatus': attachStatus,
      'detectedGraphicsApi': detectedGraphicsApi,
      'presentFrameCount': presentFrameCount,
      'presentFps': presentFps,
      'presentGapP50Ms': presentGapP50Ms,
      'presentGapP95Ms': presentGapP95Ms,
      'presentGapMaxMs': presentGapMaxMs,
      'backbufferWidth': backbufferWidth,
      'backbufferHeight': backbufferHeight,
      'backbufferFormat': backbufferFormat,
      'sharedTextureRingDepth': sharedTextureRingDepth,
      'sharedTextureSupported': sharedTextureSupported,
      'copyAvgMs': copyAvgMs,
      'copyMaxMs': copyMaxMs,
      'resolveAvgMs': resolveAvgMs,
      'resolveMaxMs': resolveMaxMs,
      'copiedFrames': copiedFrames,
      'droppedFrames': droppedFrames,
      'overwrittenFrames': overwrittenFrames,
      'cpuReadbackCount': cpuReadbackCount,
      'savedFrames': savedFrames,
      'visibleFrames': visibleFrames,
      'hostTextureConsumer': {
        'available': hasHostConsumerEvidence,
        'healthy': hasHealthyHostTextureConsumer,
        'enabled': hostConsumerEnabled,
        'sharedStateAvailable': hostSharedStateAvailable,
        'd3dDeviceCreated': hostD3dDeviceCreated,
        'openedSharedTexture': hostOpenedSharedTexture,
        'openedTextureSlots': hostOpenedTextureSlots,
        'sharedTextureOpenFailures': hostSharedTextureOpenFailures,
        'observedFrameSignals': hostObservedFrameSignals,
        'consumedFrames': hostConsumedFrames,
        'duplicateSignals': hostDuplicateSignals,
        'missedFrames': hostMissedFrames,
        'invalidStateReads': hostInvalidStateReads,
        'frameAgeAvgMs': hostFrameAgeAvgMs,
        'frameAgeP95Ms': hostFrameAgeP95Ms,
        'frameAgeMaxMs': hostFrameAgeMaxMs,
        'consumerGapP50Ms': hostConsumerGapP50Ms,
        'consumerGapP95Ms': hostConsumerGapP95Ms,
        'consumerGapMaxMs': hostConsumerGapMaxMs,
        'proofReadbackCount': hostProofReadbackCount,
        'visibleProofFrames': hostVisibleProofFrames,
        'proofReadbackAvgMs': hostProofReadbackAvgMs,
        'proofReadbackMaxMs': hostProofReadbackMaxMs,
        'lastError': hostConsumerLastError,
      },
      'publicationHandoff': {
        'available': hasPublicationHandoffEvidence,
        'healthy': hasHealthyPublicationHandoff,
        'healthLabel': publicationHandoffHealthLabel,
        'enabled': publicationHandoffEnabled,
        'mode': publicationHandoffMode,
        'scaleMode': publicationHandoffScaleMode,
        'sharedStateAvailable': publicationHandoffSharedStateAvailable,
        'd3dDeviceCreated': publicationHandoffD3dDeviceCreated,
        'openedSharedTexture': publicationHandoffOpenedSharedTexture,
        'openedTextureSlots': publicationHandoffOpenedTextureSlots,
        'sharedTextureOpenFailures':
            publicationHandoffSharedTextureOpenFailures,
        'unsupportedFormat': publicationHandoffUnsupportedFormat,
        'requestedMaxWidth': publicationHandoffRequestedMaxWidth,
        'requestedMaxHeight': publicationHandoffRequestedMaxHeight,
        'requestedTargetFps': publicationHandoffRequestedTargetFps,
        'sourceWidth': publicationHandoffSourceWidth,
        'sourceHeight': publicationHandoffSourceHeight,
        'outputWidth': publicationHandoffOutputWidth,
        'outputHeight': publicationHandoffOutputHeight,
        'observedFrameSignals': publicationHandoffObservedFrameSignals,
        'inputFramesSeen': publicationHandoffInputFramesSeen,
        'duplicateSignals': publicationHandoffDuplicateSignals,
        'missedInputFrames': publicationHandoffMissedInputFrames,
        'pacedDropFrames': publicationHandoffPacedDropFrames,
        'readbackFrames': publicationHandoffReadbackFrames,
        'outputFrames': publicationHandoffOutputFrames,
        'visibleOutputFrames': publicationHandoffVisibleOutputFrames,
        'invalidStateReads': publicationHandoffInvalidStateReads,
        'frameAgeAvgMs': publicationHandoffFrameAgeAvgMs,
        'frameAgeP95Ms': publicationHandoffFrameAgeP95Ms,
        'frameAgeMaxMs': publicationHandoffFrameAgeMaxMs,
        'outputFps': publicationHandoffOutputFps,
        'outputGapP50Ms': publicationHandoffOutputGapP50Ms,
        'outputGapP95Ms': publicationHandoffOutputGapP95Ms,
        'outputGapMaxMs': publicationHandoffOutputGapMaxMs,
        'readbackAvgMs': publicationHandoffReadbackAvgMs,
        'readbackP95Ms': publicationHandoffReadbackP95Ms,
        'readbackMaxMs': publicationHandoffReadbackMaxMs,
        'scaleAvgMs': publicationHandoffScaleAvgMs,
        'scaleP95Ms': publicationHandoffScaleP95Ms,
        'scaleMaxMs': publicationHandoffScaleMaxMs,
        'totalFrameAvgMs': publicationHandoffTotalFrameAvgMs,
        'totalFrameP95Ms': publicationHandoffTotalFrameP95Ms,
        'totalFrameMaxMs': publicationHandoffTotalFrameMaxMs,
        'lastError': publicationHandoffLastError,
      },
      'resizeDeviceLossCount': resizeDeviceLossCount,
      'fallbackReason': fallbackReason,
      'hookStopReason': hookStopReason,
      'lastError': lastError,
      'healthyPresentCadence': isHealthyCadence,
      'classificationEvidence': classificationEvidenceLabel,
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('- Status: $statusName')
      ..writeln('- Reason: ${_markdownInline(reason)}')
      ..writeln('- Probe mode: D3D11 Present hook, local diagnostics only')
      ..writeln('- Timing: ${config.timing.label}')
      ..writeln('- Target PID available: '
          '${config.effectiveTargetProcessId != null ? 'yes' : 'no'}')
      ..writeln('- Max saved frames: ${config.maxSavedFrames}');
    if (resultDirectoryPath != null) {
      buffer.writeln('- Result folder: configured');
    }
    if (helperExitCode != null) {
      buffer.writeln('- Helper exit code: $helperExitCode');
    }
    if (metadata.isNotEmpty) {
      buffer
        ..writeln('- Attach status: ${attachStatus ?? 'unknown'}')
        ..writeln(
            '- Detected graphics API: ${detectedGraphicsApi ?? 'unknown'}')
        ..writeln('- Present FPS: ${_number(presentFps)}')
        ..writeln('- Present gaps p50/p95/max: '
            '${_milliseconds(presentGapP50Ms)} / '
            '${_milliseconds(presentGapP95Ms)} / '
            '${_milliseconds(presentGapMaxMs)}')
        ..writeln('- Present frames: ${presentFrameCount ?? '?'}')
        ..writeln('- Backbuffer: '
                '${backbufferWidth == null || backbufferHeight == null ? 'unknown' : '${backbufferWidth}x$backbufferHeight'} '
                '${backbufferFormat ?? ''}'
            .trim())
        ..writeln('- Shared texture: '
            'supported=${sharedTextureSupported ?? false}, '
            'ringDepth=${sharedTextureRingDepth ?? '?'}')
        ..writeln('- Host texture consumer: '
            'enabled=${hostConsumerEnabled ?? config.hostTextureConsumerEnabled}, '
            'healthy=$hasHealthyHostTextureConsumer, '
            'opened=${hostOpenedTextureSlots ?? 0}, '
            'consumed=${hostConsumedFrames ?? 0}, '
            'missed=${hostMissedFrames ?? 0}')
        ..writeln('- Host frame age avg/p95/max: '
            '${_milliseconds(hostFrameAgeAvgMs)} / '
            '${_milliseconds(hostFrameAgeP95Ms)} / '
            '${_milliseconds(hostFrameAgeMaxMs)}')
        ..writeln('- Host consumer gaps p50/p95/max: '
            '${_milliseconds(hostConsumerGapP50Ms)} / '
            '${_milliseconds(hostConsumerGapP95Ms)} / '
            '${_milliseconds(hostConsumerGapMaxMs)}')
        ..writeln('- Host proof readbacks/visible: '
            '${hostProofReadbackCount ?? '?'} / '
            '${hostVisibleProofFrames ?? '?'}')
        ..writeln('- Publication handoff: '
            'enabled=${publicationHandoffEnabled ?? config.publicationHandoffEnabled}, '
            'status=$publicationHandoffHealthLabel, '
            'mode=${publicationHandoffMode ?? 'unknown'}')
        ..writeln('- Publication target: '
            '${publicationHandoffRequestedMaxWidth ?? config.publicationHandoffMaxWidth}x'
            '${publicationHandoffRequestedMaxHeight ?? config.publicationHandoffMaxHeight}@'
            '${publicationHandoffRequestedTargetFps ?? config.publicationHandoffTargetFps}fps')
        ..writeln('- Publication source/output: '
            '${publicationHandoffSourceWidth == null || publicationHandoffSourceHeight == null ? 'unknown' : '${publicationHandoffSourceWidth}x$publicationHandoffSourceHeight'} -> '
            '${publicationHandoffOutputWidth == null || publicationHandoffOutputHeight == null ? 'unknown' : '${publicationHandoffOutputWidth}x$publicationHandoffOutputHeight'}')
        ..writeln('- Publication output FPS: '
            '${_number(publicationHandoffOutputFps)}')
        ..writeln('- Publication output gaps p50/p95/max: '
            '${_milliseconds(publicationHandoffOutputGapP50Ms)} / '
            '${_milliseconds(publicationHandoffOutputGapP95Ms)} / '
            '${_milliseconds(publicationHandoffOutputGapMaxMs)}')
        ..writeln('- Publication readback avg/p95/max: '
            '${_milliseconds(publicationHandoffReadbackAvgMs)} / '
            '${_milliseconds(publicationHandoffReadbackP95Ms)} / '
            '${_milliseconds(publicationHandoffReadbackMaxMs)}')
        ..writeln('- Publication scale avg/p95/max: '
            '${_milliseconds(publicationHandoffScaleAvgMs)} / '
            '${_milliseconds(publicationHandoffScaleP95Ms)} / '
            '${_milliseconds(publicationHandoffScaleMaxMs)}')
        ..writeln('- Publication total frame avg/p95/max: '
            '${_milliseconds(publicationHandoffTotalFrameAvgMs)} / '
            '${_milliseconds(publicationHandoffTotalFrameP95Ms)} / '
            '${_milliseconds(publicationHandoffTotalFrameMaxMs)}')
        ..writeln('- Publication frames input/output/visible/paced-drop: '
            '${publicationHandoffInputFramesSeen ?? '?'} / '
            '${publicationHandoffOutputFrames ?? '?'} / '
            '${publicationHandoffVisibleOutputFrames ?? '?'} / '
            '${publicationHandoffPacedDropFrames ?? '?'}')
        ..writeln('- Publication LiveKit path: not implemented in this probe; '
            'this measures local frame handoff readiness only')
        ..writeln('- Copy avg/max: '
            '${_milliseconds(copyAvgMs)} / ${_milliseconds(copyMaxMs)}')
        ..writeln('- Resolve avg/max: '
            '${_milliseconds(resolveAvgMs)} / ${_milliseconds(resolveMaxMs)}')
        ..writeln('- Frames copied/dropped/overwritten: '
            '${copiedFrames ?? '?'} / ${droppedFrames ?? '?'} / '
            '${overwrittenFrames ?? '?'}')
        ..writeln('- CPU readback count: ${cpuReadbackCount ?? '?'}')
        ..writeln('- Saved/visible proof frames: '
            '${savedFrames ?? '?'} / ${visibleFrames ?? '?'}')
        ..writeln('- Fallback reason: ${fallbackReason ?? 'unknown'}')
        ..writeln('- Hook stop reason: ${hookStopReason ?? 'unknown'}')
        ..writeln('- Classification evidence: '
            '${_markdownInline(classificationEvidenceLabel)}');
    }
    return buffer.toString();
  }
}

class StreamTestSourceMetadata {
  const StreamTestSourceMetadata({
    required this.sourceType,
    required this.sourceIdHash,
    this.processId,
    this.audioRequested,
    this.audioMode,
    this.audioState,
    this.audioReason,
    this.sourceTitle,
    this.sourceRuntimeType,
  });

  final String sourceType;
  final String sourceIdHash;
  final int? processId;
  final bool? audioRequested;
  final String? audioMode;
  final String? audioState;
  final String? audioReason;
  final String? sourceTitle;
  final String? sourceRuntimeType;

  String get label {
    final pid = processId == null ? '' : ' pidAvailable=yes';
    final title = sourceTitle == null ? '' : ' titleAvailable=yes';
    return 'type=$sourceType sourceIdHash=$sourceIdHash$pid$title';
  }

  Map<String, Object?> toJson() {
    return {
      'sourceType': sourceType,
      'sourceIdHash': sourceIdHash,
      'processIdAvailable': processId != null,
      'audioRequested': audioRequested,
      'audioMode': audioMode,
      'audioState': audioState,
      'audioReason': audioReason,
      'sourceTitleAvailable': sourceTitle != null && sourceTitle!.isNotEmpty,
      'sourceRuntimeType': sourceRuntimeType,
    };
  }
}

List<WindowsWindowGdiCaptureMode?> _windowGdiModesForBackend(
  StreamTestRunConfig config,
  WindowsScreenCaptureBackendMode? backendMode,
) {
  final sourceType = config.sourceMetadata?.sourceType.toLowerCase();
  final isWindowSource = sourceType == null || sourceType.contains('window');
  if (!isWindowSource) {
    return const [null];
  }
  final effectiveBackend = _effectiveWindowsBackendModeForStreamTestConfig(
    config: config,
    backendMode: backendMode,
  );
  final usesWindowGdi =
      effectiveBackend == WindowsScreenCaptureBackendMode.directxOnly;
  if (!usesWindowGdi) {
    return const [null];
  }
  return config.effectiveWindowsWindowGdiModes;
}

WindowsScreenCaptureBackendMode?
    _effectiveWindowsBackendModeForStreamTestConfig({
  required StreamTestRunConfig config,
  required WindowsScreenCaptureBackendMode? backendMode,
}) {
  if (backendMode != null) {
    return backendMode;
  }
  final sourceType = config.sourceMetadata?.sourceType.toLowerCase();
  if (sourceType != null && sourceType.contains('window')) {
    return defaultWindowsCaptureBackendMode(
      isWindows: true,
      isWebrtcDesktopSource: true,
      isWindowSource: true,
      requestedMode: null,
      preferGameCaptureForWindowSource: true,
      sourceTitle: config.sourceMetadata?.sourceTitle,
    );
  }
  return backendMode;
}

class StreamTestProgress {
  const StreamTestProgress({
    required this.profile,
    required this.windowsCaptureBackendMode,
    required this.windowsCaptureDirtyRegionMode,
    required this.windowsWindowGdiCaptureMode,
    required this.runNumber,
    required this.totalRuns,
    required this.duration,
    required this.warmupDuration,
    required this.nativeFramePacingEnabled,
  })  : _labelOverride = null,
        _detailLabelOverride = null;

  StreamTestProgress.gameCaptureProbe({
    required this.duration,
    GameCaptureProbeTiming timing = GameCaptureProbeTiming.standalone,
  })  : profile = ScreenShareProfileConfig.smooth,
        windowsCaptureBackendMode = null,
        windowsCaptureDirtyRegionMode =
            WindowsScreenCaptureDirtyRegionMode.auto,
        windowsWindowGdiCaptureMode = null,
        runNumber = 0,
        totalRuns = 0,
        warmupDuration = Duration.zero,
        nativeFramePacingEnabled = false,
        _labelOverride = 'D3D11 game probe',
        _detailLabelOverride = 'D3D11 game probe (${duration.inSeconds}s, '
            '${timing.progressDetail})';

  final ScreenShareProfileConfig profile;
  final WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
  final WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode;
  final WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode;
  final int runNumber;
  final int totalRuns;
  final Duration duration;
  final Duration warmupDuration;
  final bool nativeFramePacingEnabled;
  final String? _labelOverride;
  final String? _detailLabelOverride;

  String get backendSelectionLabel =>
      windowsCaptureBackendMode?.label ?? 'App default';

  String get windowGdiSelectionLabel =>
      windowsWindowGdiCaptureMode?.shortLabel ?? 'GDI default';

  String get label =>
      _labelOverride ??
      '$runNumber/$totalRuns ${profile.label} - '
          '$backendSelectionLabel'
          '${windowsWindowGdiCaptureMode == null ? '' : ' + $windowGdiSelectionLabel'}'
          '${nativeFramePacingEnabled ? ' + latest-frame pacer' : ''}'
          '${windowsCaptureDirtyRegionMode == WindowsScreenCaptureDirtyRegionMode.forceFullFrame ? ' + full-frame dirty regions' : ''}';

  String get detailLabel =>
      _detailLabelOverride ??
      '$label (${duration.inSeconds}s'
          '${warmupDuration.inMilliseconds > 0 ? ' + ${warmupDuration.inSeconds}s warmup' : ''}, '
          '${profile.mainLayer.resolutionLabel}@'
          '${profile.mainLayer.diagnosticFramerateLabel})';
}

class StreamTestRunner {
  StreamTestRunner({
    required this.target,
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? delay,
    Future<String> Function()? diagnosticLogProvider,
    void Function(StreamTestProgress progress)? onProgress,
    GameCaptureProbeRunner gameCaptureProbeRunner =
        const UnsupportedGameCaptureProbeRunner(),
    int diagnosticLogMarkerLimit = streamTestDefaultDiagnosticLogMarkerLimit,
    Duration shareStartTimeout = const Duration(seconds: 45),
    Duration shareStopTimeout = const Duration(seconds: 20),
    Duration diagnosticSampleTimeout = const Duration(seconds: 5),
    Duration diagnosticLogTimeout = const Duration(seconds: 4),
    Duration hostLoadSamplerStartTimeout = const Duration(seconds: 3),
    Duration hostLoadSamplerStopTimeout = const Duration(seconds: 3),
    Duration postActiveStartCompletionTimeout = const Duration(seconds: 6),
    Duration? runTimeout,
    Future<StreamTestLoadedLibwebrtcArtifact?> Function()?
        loadedLibwebrtcArtifactProvider,
    StreamTestHostLoadSamplerFactory hostLoadSamplerFactory =
        createStreamTestHostLoadSampler,
  })  : _clock = clock ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed,
        _diagnosticLogProvider = diagnosticLogProvider,
        _onProgress = onProgress,
        _gameCaptureProbeRunner = gameCaptureProbeRunner,
        _diagnosticLogMarkerLimit = diagnosticLogMarkerLimit,
        _shareStartTimeout = shareStartTimeout,
        _shareStopTimeout = shareStopTimeout,
        _diagnosticSampleTimeout = diagnosticSampleTimeout,
        _diagnosticLogTimeout = diagnosticLogTimeout,
        _hostLoadSamplerStartTimeout = hostLoadSamplerStartTimeout,
        _hostLoadSamplerStopTimeout = hostLoadSamplerStopTimeout,
        _postActiveStartCompletionTimeout = postActiveStartCompletionTimeout,
        _loadedLibwebrtcArtifactProvider = loadedLibwebrtcArtifactProvider ??
            loadStreamTestLoadedLibwebrtcArtifact,
        _hostLoadSamplerFactory = hostLoadSamplerFactory,
        _runTimeout = runTimeout;

  final StreamTestTarget target;
  final DateTime Function() _clock;
  final Future<void> Function(Duration duration) _delay;
  final Future<String> Function()? _diagnosticLogProvider;
  final void Function(StreamTestProgress progress)? _onProgress;
  final GameCaptureProbeRunner _gameCaptureProbeRunner;
  final int _diagnosticLogMarkerLimit;
  final Duration _shareStartTimeout;
  final Duration _shareStopTimeout;
  final Duration _diagnosticSampleTimeout;
  final Duration _diagnosticLogTimeout;
  final Duration _hostLoadSamplerStartTimeout;
  final Duration _hostLoadSamplerStopTimeout;
  final Duration _postActiveStartCompletionTimeout;
  final Future<StreamTestLoadedLibwebrtcArtifact?> Function()
      _loadedLibwebrtcArtifactProvider;
  final StreamTestHostLoadSamplerFactory _hostLoadSamplerFactory;
  final Duration? _runTimeout;
  _StreamTestRunGuard? _activeRunGuard;
  static const Duration _shareStartPollInterval = Duration(milliseconds: 100);

  Future<StreamTestRunResult> run(
    StreamTestRunConfig config, {
    GameCaptureTestTargetResult? gameCaptureTestTargetResult,
  }) async {
    final timeout = _runTimeout ?? _runTimeoutForConfig(config);
    final runGuard = _StreamTestRunGuard();
    _activeRunGuard = runGuard;
    try {
      return await _withTimeout(
        _runUnlocked(
          config,
          gameCaptureTestTargetResult: gameCaptureTestTargetResult,
          runGuard: runGuard,
        ),
        timeout,
        'stream-test runner batch',
      );
    } on TimeoutException catch (error, stackTrace) {
      runGuard.cancel();
      Log.onError(
        error,
        stackTrace,
        content:
            'Stream test runner batch timed out; attempting bounded cleanup',
      );
      await _stopShareAfterBatchTimeout();
      rethrow;
    } finally {
      if (identical(_activeRunGuard, runGuard)) {
        _activeRunGuard = null;
      }
    }
  }

  Future<StreamTestRunResult> _runUnlocked(
    StreamTestRunConfig config, {
    GameCaptureTestTargetResult? gameCaptureTestTargetResult,
    required _StreamTestRunGuard runGuard,
  }) async {
    _throwIfRunCanceled(runGuard);
    final hostLoadSampler = await _startHostLoadSampler(config);
    StreamTestHostLoadReport? hostLoadReport;
    try {
      final result = await _runUnlockedCore(
        config,
        gameCaptureTestTargetResult: gameCaptureTestTargetResult,
        runGuard: runGuard,
      );
      hostLoadReport = await _stopHostLoadSampler(
        hostLoadSampler,
        targetProcessLoadRequested: config.sourceMetadata?.processId != null,
      );
      return result.withHostLoadReport(hostLoadReport);
    } finally {
      if (hostLoadReport == null) {
        await _stopHostLoadSampler(
          hostLoadSampler,
          targetProcessLoadRequested: config.sourceMetadata?.processId != null,
        );
      }
    }
  }

  Future<StreamTestRunResult> _runUnlockedCore(
    StreamTestRunConfig config, {
    GameCaptureTestTargetResult? gameCaptureTestTargetResult,
    required _StreamTestRunGuard runGuard,
  }) async {
    _throwIfRunCanceled(runGuard);
    final startedAt = _clock();
    final loadedLibwebrtcArtifact = await _collectLoadedLibwebrtcArtifact();
    _throwIfRunCanceled(runGuard);
    final results = <StreamTestPresetResult>[];
    final diagnosticLogMarkers = <String>[];
    final seenDiagnosticLogMarkers = <String>{};
    final backendModes = config.effectiveWindowsBackendModes;
    final runPlans = <({
      WindowsScreenCaptureBackendMode? backend,
      WindowsWindowGdiCaptureMode? gdi
    })>[];
    for (final backendMode in backendModes) {
      for (final gdiMode in _windowGdiModesForBackend(config, backendMode)) {
        runPlans.add((backend: backendMode, gdi: gdiMode));
      }
    }
    final totalRuns = config.presets.length * runPlans.length;
    GameCaptureProbeResult? gameCaptureProbeResult;
    Future<GameCaptureProbeResult>? gameCaptureProbeFuture;
    final gameCaptureProbeConfig = config.gameCaptureProbe;
    if (gameCaptureProbeConfig?.enabled == true) {
      final runConcurrently = totalRuns > 0;
      final handoffLayer = config.presets.isEmpty
          ? null
          : _effectiveProfileForBackend(
              config: config,
              profile: config.presets.first,
              backendMode: backendModes.isEmpty ? null : backendModes.first,
            ).mainLayer;
      final timing = runConcurrently
          ? GameCaptureProbeTiming.concurrentWithInitialPreset
          : GameCaptureProbeTiming.standalone;
      final resolvedProbeConfig = gameCaptureProbeConfig!.resolveSource(
        config.sourceMetadata,
        defaultDuration: config.durationPerPreset,
        minimumDuration:
            runConcurrently ? _initialPresetProbeDuration(config) : null,
        timing: timing,
        publicationHandoffMaxWidth: handoffLayer?.width,
        publicationHandoffMaxHeight: handoffLayer?.height,
        publicationHandoffTargetFps: handoffLayer?.targetFramerateForScoring,
      );
      _emitProgress(
        StreamTestProgress.gameCaptureProbe(
          duration: resolvedProbeConfig.duration,
          timing: resolvedProbeConfig.timing,
        ),
      );
      if (runConcurrently) {
        gameCaptureProbeFuture =
            _runGameCaptureProbeSafely(resolvedProbeConfig);
      } else {
        gameCaptureProbeResult =
            await _runGameCaptureProbeSafely(resolvedProbeConfig);
      }
    }
    var runNumber = 0;

    void rememberDiagnosticMarkers(List<String> markers) {
      for (final marker in _expandDiagnosticLogMarkerLines(markers)) {
        if (seenDiagnosticLogMarkers.add(marker)) {
          diagnosticLogMarkers.add(marker);
        }
      }
    }

    if (config.presets.isEmpty) {
      rememberDiagnosticMarkers(await _collectDiagnosticLogMarkers());
      return StreamTestRunResult(
        startedAt: startedAt,
        endedAt: _clock(),
        targetLabel: target.label,
        roomId: target.roomId,
        config: config,
        presetResults: const [],
        loadedLibwebrtcArtifact: loadedLibwebrtcArtifact,
        diagnosticLogMarkers: diagnosticLogMarkers,
        gameCaptureTestTargetResult: gameCaptureTestTargetResult,
        gameCaptureProbeResult: gameCaptureProbeResult,
      );
    }

    for (final profile in config.presets) {
      for (final runPlan in runPlans) {
        final backendMode = runPlan.backend;
        final windowGdiMode = runPlan.gdi;
        final effectiveProfile = _effectiveProfileForBackend(
          config: config,
          profile: profile,
          backendMode: backendMode,
        );
        runNumber += 1;
        final presetStartedAt = _clock();
        var diagnosticStartedAt = presetStartedAt;
        var diagnosticEndedAt = presetStartedAt;
        var measurementStartedAt = presetStartedAt;
        final samples = <StreamTestSample>[];
        String? error;
        _emitProgress(
          StreamTestProgress(
            profile: effectiveProfile,
            windowsCaptureBackendMode: backendMode,
            windowsCaptureDirtyRegionMode: config.windowsCaptureDirtyRegionMode,
            windowsWindowGdiCaptureMode: windowGdiMode,
            runNumber: runNumber,
            totalRuns: totalRuns,
            duration: config.durationPerPreset,
            warmupDuration: config.warmupDuration,
            nativeFramePacingEnabled: config.nativeFramePacingEnabled,
          ),
        );

        try {
          if (target.isSharingScreen) {
            await _withTimeout(
              target.stopShare(),
              _shareStopTimeout,
              'pre-run stop share',
            );
            _throwIfRunCanceled(runGuard);
          }
          diagnosticStartedAt = _clock();
          await _withTimeout(
            _startPresetAndWaitForActiveShare(
              profile: effectiveProfile,
              windowsCaptureBackendMode: backendMode,
              windowsCaptureDirtyRegionMode:
                  config.windowsCaptureDirtyRegionMode,
              windowsWindowGdiCaptureMode: windowGdiMode,
              nativeFramePacingEnabled: config.nativeFramePacingEnabled,
              dummyNv12LiveSender: config.dummyNv12LiveSender,
              runGuard: runGuard,
            ),
            _shareStartTimeout,
            'start stream-test preset',
          );
          _throwIfRunCanceled(runGuard);

          if (config.warmupDuration.inMilliseconds > 0) {
            await _delay(config.warmupDuration);
            _throwIfRunCanceled(runGuard);
          }

          measurementStartedAt = _clock();
          final endAt = measurementStartedAt.add(config.durationPerPreset);
          Log.i(
            'Stream test runner measurement started '
            'run=$runNumber/$totalRuns preset=${effectiveProfile.label} '
            'duration=${config.durationPerPreset.inSeconds}s',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
          while (_clock().isBefore(endAt)) {
            await _delay(config.sampleInterval);
            _throwIfRunCanceled(runGuard);
            final sampleTime = _clock();
            final snapshot = await _withTimeout(
              target.collectDiagnostics(),
              _diagnosticSampleTimeout,
              'collect stream diagnostics',
            );
            _throwIfRunCanceled(runGuard);
            samples.add(
              StreamTestSample(
                elapsed: sampleTime.difference(measurementStartedAt),
                snapshot: snapshot,
              ),
            );
            if (samples.length == 1 || samples.length % 5 == 0) {
              Log.i(
                'Stream test runner collected diagnostics sample '
                'run=$runNumber/$totalRuns samples=${samples.length}',
                category: LogCategory.webrtc,
                source: 'stream-test-runner',
              );
            }
          }
          diagnosticEndedAt = _clock();
          Log.i(
            'Stream test runner measurement completed '
            'run=$runNumber/$totalRuns samples=${samples.length}',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        } catch (exception) {
          if (exception is _StreamTestRunCanceled) {
            rethrow;
          }
          error = exception.toString();
          diagnosticEndedAt = _clock();
        } finally {
          try {
            if (!runGuard.isCanceled && target.isSharingScreen) {
              Log.i(
                'Stream test runner cleanup stopping screen share '
                'run=$runNumber/$totalRuns',
                category: LogCategory.webrtc,
                source: 'stream-test-runner',
              );
              await _withTimeout(
                target.stopShare(),
                _shareStopTimeout,
                'cleanup stop share',
              );
              _throwIfRunCanceled(runGuard);
              Log.i(
                'Stream test runner cleanup stopped screen share '
                'run=$runNumber/$totalRuns',
                category: LogCategory.webrtc,
                source: 'stream-test-runner',
              );
            }
          } catch (exception) {
            error = [
              if (error != null) error,
              'cleanup failed: $exception',
            ].join('; ');
          }
        }

        Log.i(
          'Stream test runner collecting diagnostic markers '
          'run=$runNumber/$totalRuns',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        _throwIfRunCanceled(runGuard);
        final presetAnalysisDiagnosticLogMarkers = _diagnosticMarkersForRange(
          await _collectDiagnosticLogMarkers(unbounded: true),
          startedAt: diagnosticStartedAt,
          endedAt: diagnosticEndedAt,
        );
        _throwIfRunCanceled(runGuard);
        final presetDiagnosticLogMarkers = _capDiagnosticLogMarkers(
          presetAnalysisDiagnosticLogMarkers,
          limit: _diagnosticLogMarkerLimit,
        );
        rememberDiagnosticMarkers(presetDiagnosticLogMarkers);
        final nativeDiagnostics = StreamTestNativeDiagnostics.fromMarkers(
          presetAnalysisDiagnosticLogMarkers,
        );

        results.add(
          StreamTestPresetResult(
            profile: effectiveProfile,
            windowsCaptureBackendMode: backendMode,
            windowsCaptureDirtyRegionMode: config.windowsCaptureDirtyRegionMode,
            windowsWindowGdiCaptureMode: windowGdiMode,
            startedAt: measurementStartedAt,
            endedAt: diagnosticEndedAt,
            diagnosticStartedAt: diagnosticStartedAt,
            diagnosticEndedAt: diagnosticEndedAt,
            samples: List.unmodifiable(samples),
            error: error,
            nativeDiagnostics: nativeDiagnostics,
            diagnosticLogMarkers: List.unmodifiable(presetDiagnosticLogMarkers),
            analysisDiagnosticLogMarkers:
                List.unmodifiable(presetAnalysisDiagnosticLogMarkers),
          ),
        );
      }
    }

    if (gameCaptureProbeFuture != null) {
      gameCaptureProbeResult = await gameCaptureProbeFuture;
      _throwIfRunCanceled(runGuard);
    }

    rememberDiagnosticMarkers(await _collectDiagnosticLogMarkers());
    _throwIfRunCanceled(runGuard);
    return StreamTestRunResult(
      startedAt: startedAt,
      endedAt: _clock(),
      targetLabel: target.label,
      roomId: target.roomId,
      config: config,
      presetResults: List.unmodifiable(results),
      loadedLibwebrtcArtifact: loadedLibwebrtcArtifact,
      diagnosticLogMarkers: List.unmodifiable(diagnosticLogMarkers),
      gameCaptureTestTargetResult: gameCaptureTestTargetResult,
      gameCaptureProbeResult: gameCaptureProbeResult,
    );
  }

  Future<StreamTestLoadedLibwebrtcArtifact?>
      _collectLoadedLibwebrtcArtifact() async {
    try {
      final artifact = await _withTimeout(
        _loadedLibwebrtcArtifactProvider(),
        const Duration(seconds: 4),
        'collect loaded libwebrtc artifact identity',
      );
      if (artifact == null) {
        Log.i(
          'Stream test loaded libwebrtc artifact unavailable',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        return null;
      }
      Log.i(
        'Stream test loaded libwebrtc artifact '
        '${artifact.diagnosticLabel}',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      return artifact;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unable to collect stream-test libwebrtc artifact identity',
      );
      return null;
    }
  }

  Future<StreamTestHostLoadSampler> _startHostLoadSampler(
    StreamTestRunConfig config,
  ) async {
    final targetProcessId = config.sourceMetadata?.processId;
    StreamTestHostLoadSampler? sampler;
    try {
      sampler = _hostLoadSamplerFactory(targetProcessId);
      await _withTimeout(
        sampler.start(),
        _hostLoadSamplerStartTimeout,
        'start stream-test host load sampler',
      );
      return sampler;
    } catch (error, stackTrace) {
      if (sampler != null) {
        await _cleanupFailedHostLoadSamplerStart(sampler);
      }
      Log.onError(
        error,
        stackTrace,
        content: 'Unable to start stream-test host load sampler',
      );
      return StreamTestUnavailableHostLoadSampler(
        reason: 'host load sampler failed to start',
        targetProcessLoadRequested: targetProcessId != null,
      );
    }
  }

  Future<void> _cleanupFailedHostLoadSamplerStart(
    StreamTestHostLoadSampler sampler,
  ) async {
    try {
      await _withTimeout(
        sampler.stop(),
        _hostLoadSamplerStopTimeout,
        'cleanup stream-test host load sampler after failed start',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unable to clean up stream-test host load sampler '
            'after failed start',
      );
    }
  }

  Future<StreamTestHostLoadReport> _stopHostLoadSampler(
    StreamTestHostLoadSampler sampler, {
    required bool targetProcessLoadRequested,
  }) async {
    try {
      final report = await _withTimeout(
        sampler.stop(),
        _hostLoadSamplerStopTimeout,
        'stop stream-test host load sampler',
      );
      Log.i(
        'Stream test host load sampler stopped '
        'samples=${report.samples.length} '
        'missing=${report.missingMetricLabels.join(', ')}',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      return report;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unable to stop stream-test host load sampler',
      );
      return StreamTestHostLoadReport.unavailable(
        reason: 'host load sampler failed to stop',
        targetProcessLoadRequested: targetProcessLoadRequested,
      );
    }
  }

  ScreenShareProfileConfig _effectiveProfileForBackend({
    required StreamTestRunConfig config,
    required ScreenShareProfileConfig profile,
    required WindowsScreenCaptureBackendMode? backendMode,
  }) {
    final effectiveBackendMode = _effectiveBackendModeForScoring(
      config: config,
      backendMode: backendMode,
    );
    return profile.withWindowsGameCaptureCadenceCompatibility(
      isExperimentalGameCaptureSource: effectiveBackendMode ==
          WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
    );
  }

  WindowsScreenCaptureBackendMode? _effectiveBackendModeForScoring({
    required StreamTestRunConfig config,
    required WindowsScreenCaptureBackendMode? backendMode,
  }) {
    return _effectiveWindowsBackendModeForStreamTestConfig(
      config: config,
      backendMode: backendMode,
    );
  }

  void _emitProgress(StreamTestProgress progress) {
    try {
      _onProgress?.call(progress);
    } catch (_) {
      // UI progress is best-effort and must not affect measurement.
    }
  }

  void _throwIfRunCanceled(_StreamTestRunGuard runGuard) {
    if (runGuard.isCanceled || !identical(_activeRunGuard, runGuard)) {
      throw const _StreamTestRunCanceled();
    }
  }

  Future<GameCaptureProbeResult> _runGameCaptureProbeSafely(
    GameCaptureProbeConfig config,
  ) async {
    try {
      return await _gameCaptureProbeRunner.run(config);
    } catch (error) {
      return GameCaptureProbeResult.unavailable(
        config: config,
        reason: 'game-capture probe runner failed: $error',
      );
    }
  }

  Duration _initialPresetProbeDuration(StreamTestRunConfig config) {
    final tailMs = max(config.sampleInterval.inMilliseconds * 2, 2000);
    return Duration(
      milliseconds: max(
        1000,
        config.warmupDuration.inMilliseconds +
            config.durationPerPreset.inMilliseconds +
            tailMs,
      ),
    );
  }

  Future<void> _startPresetAndWaitForActiveShare({
    required ScreenShareProfileConfig profile,
    required WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    required WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode,
    required WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    required bool nativeFramePacingEnabled,
    required bool dummyNv12LiveSender,
    required _StreamTestRunGuard runGuard,
  }) async {
    final startCompletion = Completer<void>();
    final startFuture = target.startPreset(
      profile,
      windowsCaptureBackendMode: windowsCaptureBackendMode,
      windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
      nativeFramePacingEnabled: nativeFramePacingEnabled,
      dummyNv12LiveSender: dummyNv12LiveSender,
    );
    unawaited(
      startFuture.then<void>(
        (_) {
          if (!startCompletion.isCompleted) {
            startCompletion.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!startCompletion.isCompleted) {
            startCompletion.completeError(error, stackTrace);
          }
        },
      ),
    );

    while (!target.isSharingScreen) {
      if (startCompletion.isCompleted) {
        await startCompletion.future;
        if (target.isSharingScreen) {
          return;
        }
        throw StateError(
          'Stream-test preset start completed before screen share became '
          'active.',
        );
      }
      await Future.any<void>([
        startCompletion.future,
        _delay(_shareStartPollInterval),
      ]);
      _throwIfRunCanceled(runGuard);
    }

    await Future<void>.value();
    _throwIfRunCanceled(runGuard);
    if (startCompletion.isCompleted) {
      await startCompletion.future;
      return;
    }

    if (!startCompletion.isCompleted) {
      Log.w(
        'Stream test runner observed active screen share before preset start '
        'completed; waiting briefly for post-publish stream-test guards.',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      try {
        await _withTimeout(
          startCompletion.future,
          _postActiveStartCompletionTimeout,
          'post-active stream-test start handoff',
        );
      } on TimeoutException {
        Log.w(
          'Stream test runner post-active start handoff did not complete '
          'before timeout; continuing measurement with active screen share.',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
      }
      _throwIfRunCanceled(runGuard);
    }
  }

  Future<List<String>> _collectDiagnosticLogMarkers({
    int? limit,
    bool unbounded = false,
  }) async {
    final provider = _diagnosticLogProvider;
    if (provider == null) {
      return const [];
    }
    try {
      final text = await _withTimeout(
        provider(),
        _diagnosticLogTimeout,
        'collect stream diagnostic logs',
      );
      return _extractDiagnosticLogMarkers(
        text,
        limit: unbounded ? null : (limit ?? _diagnosticLogMarkerLimit),
      );
    } catch (error) {
      return ['diagnostic log marker read failed: $error'];
    }
  }

  Duration _runTimeoutForConfig(StreamTestRunConfig config) {
    var runPlanCount = 0;
    for (final backendMode in config.effectiveWindowsBackendModes) {
      runPlanCount += _windowGdiModesForBackend(config, backendMode).length;
    }
    final presetCount = config.presets.isEmpty ? 1 : config.presets.length;
    final totalRuns = max(1, presetCount * max(1, runPlanCount));
    final perRunBudget = config.warmupDuration +
        config.durationPerPreset +
        _shareStartTimeout +
        _postActiveStartCompletionTimeout +
        (_shareStopTimeout * 2) +
        _diagnosticSampleTimeout +
        (_diagnosticLogTimeout * 2) +
        const Duration(seconds: 10);
    final probeConfig = config.gameCaptureProbe;
    final probeBudget = probeConfig?.enabled == true
        ? probeConfig!.duration + const Duration(seconds: 10)
        : Duration.zero;
    final hostLoadBudget =
        _hostLoadSamplerStartTimeout + _hostLoadSamplerStopTimeout;
    final totalBudget =
        (perRunBudget * totalRuns) + probeBudget + hostLoadBudget;
    return totalBudget < const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : totalBudget;
  }

  Future<void> _stopShareAfterBatchTimeout() async {
    try {
      if (!target.isSharingScreen) {
        return;
      }
      Log.w(
        'Stream test runner timeout cleanup stopping screen share',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      await _withTimeout(
        target.stopShare(),
        _shareStopTimeout,
        'timeout cleanup stop share',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Stream test runner timeout cleanup failed',
      );
    }
  }

  Future<T> _withTimeout<T>(
    Future<T> operation,
    Duration timeout,
    String label,
  ) {
    if (timeout <= Duration.zero) {
      return operation;
    }
    return operation.timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException(
          '$label timed out after ${_durationLabel(timeout)}',
        );
      },
    );
  }

  String _durationLabel(Duration duration) {
    final milliseconds = duration.inMilliseconds;
    if (milliseconds % Duration.millisecondsPerSecond == 0) {
      return '${duration.inSeconds}s';
    }
    return '${milliseconds}ms';
  }
}

class _StreamTestRunGuard {
  var isCanceled = false;

  void cancel() {
    isCanceled = true;
  }
}

class _StreamTestRunCanceled implements Exception {
  const _StreamTestRunCanceled();

  @override
  String toString() => 'stream-test runner run canceled';
}

class StreamTestSample {
  const StreamTestSample({
    required this.elapsed,
    required this.snapshot,
  });

  final Duration elapsed;
  final VoipCallDiagnosticsSnapshot snapshot;

  Map<String, Object?> toJson() {
    return {
      'elapsedMs': elapsed.inMilliseconds,
      'collectedAt': snapshot.collectedAt.toUtc().toIso8601String(),
      'screenShareProfileLabel': snapshot.screenShareProfileLabel,
      'screenShareProfileDetails': snapshot.screenShareProfileDetails,
      'iceTransportSummary': snapshot.iceTransportSummary,
      'adaptiveFallbackReason': snapshot.adaptiveFallbackReason,
      'tracks': snapshot.tracks.map(_trackToJson).toList(growable: false),
    };
  }
}

class StreamTestPresetResult {
  StreamTestPresetResult({
    required this.profile,
    required this.startedAt,
    required this.endedAt,
    required this.samples,
    DateTime? diagnosticStartedAt,
    DateTime? diagnosticEndedAt,
    this.windowsCaptureBackendMode,
    this.windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    this.windowsWindowGdiCaptureMode,
    this.error,
    this.nativeDiagnostics = const StreamTestNativeDiagnostics(),
    this.diagnosticLogMarkers = const [],
    List<String>? analysisDiagnosticLogMarkers,
  })  : diagnosticStartedAt = diagnosticStartedAt ?? startedAt,
        diagnosticEndedAt = diagnosticEndedAt ?? endedAt,
        score = StreamTestScore.fromSamples(
          profile: profile,
          samples: samples,
          error: error,
          nativeDiagnostics: nativeDiagnostics,
          diagnosticLogMarkers:
              analysisDiagnosticLogMarkers ?? diagnosticLogMarkers,
          measurementStartedAt: startedAt,
          measurementEndedAt: diagnosticEndedAt ?? endedAt,
        );

  final ScreenShareProfileConfig profile;
  final WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
  final WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode;
  final WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode;
  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime diagnosticStartedAt;
  final DateTime diagnosticEndedAt;
  final List<StreamTestSample> samples;
  final String? error;
  final StreamTestNativeDiagnostics nativeDiagnostics;
  final List<String> diagnosticLogMarkers;
  final StreamTestScore score;

  String get backendSelectionLabel =>
      windowsCaptureBackendMode?.label ?? 'App default';

  String get windowGdiSelectionLabel =>
      windowsWindowGdiCaptureMode?.label ?? 'Default window GDI';

  String get nativeBackendLabel {
    final backend = nativeDiagnostics.backendLabel;
    if (backend == 'unknown') {
      return backendSelectionLabel;
    }
    return backend;
  }

  String get resultLabel => '$backendSelectionLabel / ${profile.label}';

  StreamDiagnosticCoverageMatrix get diagnosticCoverage =>
      StreamDiagnosticCoverageMatrix.forPreset(this);

  StreamTestPresetResult withNativeDiagnostics(
    StreamTestNativeDiagnostics diagnostics,
  ) {
    return StreamTestPresetResult(
      profile: profile,
      windowsCaptureBackendMode: windowsCaptureBackendMode,
      windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
      startedAt: startedAt,
      endedAt: endedAt,
      diagnosticStartedAt: diagnosticStartedAt,
      diagnosticEndedAt: diagnosticEndedAt,
      samples: samples,
      error: error,
      nativeDiagnostics: diagnostics,
      diagnosticLogMarkers: diagnosticLogMarkers,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'profile': _profileToJson(profile),
      'windowsCaptureBackendMode': windowsCaptureBackendMode?.constraintValue,
      'windowsCaptureBackendSelection':
          windowsCaptureBackendMode?.label ?? 'App default',
      'windowsCaptureDirtyRegionMode':
          windowsCaptureDirtyRegionMode.constraintValue,
      'windowsCaptureDirtyRegionSelection': windowsCaptureDirtyRegionMode.label,
      'windowsWindowGdiCaptureMode':
          windowsWindowGdiCaptureMode?.constraintValue,
      'windowsWindowGdiCaptureSelection': windowGdiSelectionLabel,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'diagnosticStartedAt': diagnosticStartedAt.toUtc().toIso8601String(),
      'diagnosticEndedAt': diagnosticEndedAt.toUtc().toIso8601String(),
      'durationMs': endedAt.difference(startedAt).inMilliseconds,
      'error': error,
      'nativeDiagnostics': nativeDiagnostics.toJson(),
      'subjectiveNotes': '',
      'diagnosticCoverage': diagnosticCoverage.toJson(),
      'score': score.toJson(),
      'summary': score.summary.toJson(),
      'timeWindows': score.temporalAnalysis.toJson(),
      'samples': samples.map((sample) => sample.toJson()).toList(),
    };
  }
}

class StreamTestTemporalAnalysis {
  const StreamTestTemporalAnalysis({
    required this.windows,
    this.lateDegradationSignals = const [],
  });

  factory StreamTestTemporalAnalysis.fromSamplesAndMarkers({
    required List<StreamTestSample> samples,
    required List<String> nativeDiagnosticMarkers,
    required double targetFps,
    DateTime? measurementStartedAt,
    DateTime? measurementEndedAt,
  }) {
    final totalDuration = _measurementDuration(
      samples: samples,
      measurementStartedAt: measurementStartedAt,
      measurementEndedAt: measurementEndedAt,
    );
    if (totalDuration.inMilliseconds <= 0) {
      return const StreamTestTemporalAnalysis(windows: []);
    }

    final markerSamples =
        _GameCaptureMarkerSample.fromMarkers(nativeDiagnosticMarkers);
    final specs = _temporalWindowSpecs(totalDuration);
    final windows = specs
        .map(
          (spec) => StreamTestTimeWindowSummary.fromSamplesAndMarkers(
            spec: spec,
            samples: samples,
            markerSamples: markerSamples,
            measurementStartedAt: measurementStartedAt,
          ),
        )
        .toList(growable: false);

    return StreamTestTemporalAnalysis(
      windows: List.unmodifiable(windows),
      lateDegradationSignals: List.unmodifiable(
        _lateDegradationSignals(
          windows: windows,
          targetFps: targetFps,
        ),
      ),
    );
  }

  final List<StreamTestTimeWindowSummary> windows;
  final List<String> lateDegradationSignals;

  bool get hasEvidence => windows.any((window) => window.hasEvidence);

  bool get hasLateDegradation => lateDegradationSignals.isNotEmpty;

  Map<String, Object?> toJson() {
    return {
      'windows': windows.map((window) => window.toJson()).toList(),
      'lateDegradationDetected': hasLateDegradation,
      'lateDegradationSignals': lateDegradationSignals,
    };
  }
}

class StreamTestTimeWindowSummary {
  const StreamTestTimeWindowSummary({
    required this.label,
    required this.startOffset,
    required this.endOffset,
    required this.sampleCount,
    required this.summary,
    required this.framePacing,
    this.gameCapture,
  });

  factory StreamTestTimeWindowSummary.fromSamplesAndMarkers({
    required _StreamTestWindowSpec spec,
    required List<StreamTestSample> samples,
    required List<_GameCaptureMarkerSample> markerSamples,
    DateTime? measurementStartedAt,
  }) {
    final windowSamples = samples.where((sample) {
      final elapsed = sample.elapsed;
      return elapsed >= spec.start && elapsed <= spec.end;
    }).toList(growable: false);
    return StreamTestTimeWindowSummary(
      label: spec.label,
      startOffset: spec.start,
      endOffset: spec.end,
      sampleCount: windowSamples.length,
      summary: StreamTestSummary.fromSamples(windowSamples),
      framePacing: StreamTestFramePacingSummary.fromSamples(windowSamples),
      gameCapture: StreamTestGameCaptureWindowCounters.fromMarkerPairs(
        markerSamples: markerSamples,
        measurementStartedAt: measurementStartedAt,
        startOffset: spec.start,
        endOffset: spec.end,
      ),
    );
  }

  final String label;
  final Duration startOffset;
  final Duration endOffset;
  final int sampleCount;
  final StreamTestSummary summary;
  final StreamTestFramePacingSummary framePacing;
  final StreamTestGameCaptureWindowCounters? gameCapture;

  bool get hasEvidence =>
      sampleCount > 0 || (gameCapture?.hasEvidence ?? false);

  String get offsetLabel =>
      '${(startOffset.inMilliseconds / 1000).toStringAsFixed(0)}-'
      '${(endOffset.inMilliseconds / 1000).toStringAsFixed(0)}s';

  Map<String, Object?> toJson() {
    return {
      'label': label,
      'startMs': startOffset.inMilliseconds,
      'endMs': endOffset.inMilliseconds,
      'sampleCount': sampleCount,
      'averageCaptureFps': summary.averageCaptureFps,
      'minimumCaptureFps': summary.minimumCaptureFps,
      'averageEncodeFps': summary.averageEncodeFps,
      'minimumEncodeFps': summary.minimumEncodeFps,
      'averageSendFps': summary.averageSendFps,
      'minimumSendFps': summary.minimumSendFps,
      'averageBitrateBps': summary.averageBitrateBps,
      'maxPacketLossPercent': summary.maxPacketLossPercent,
      'maxRoundTripTimeMs': summary.maxRoundTripTimeMs,
      'framePacing': framePacing.toJson(),
      'gameCapture': gameCapture?.toJson(),
    };
  }
}

class StreamTestRunResult {
  const StreamTestRunResult({
    required this.startedAt,
    required this.endedAt,
    required this.targetLabel,
    required this.roomId,
    required this.config,
    required this.presetResults,
    this.error,
    this.diagnosticLogMarkers = const [],
    this.loadedLibwebrtcArtifact,
    this.gameCaptureTestTargetResult,
    this.gameCaptureProbeResult,
    this.hostLoadReport,
  });

  factory StreamTestRunResult.failure({
    required DateTime startedAt,
    required DateTime endedAt,
    required String targetLabel,
    required String roomId,
    required StreamTestRunConfig config,
    required String error,
    String diagnosticLogText = '',
    int diagnosticLogMarkerLimit = streamTestDefaultDiagnosticLogMarkerLimit,
    StreamTestLoadedLibwebrtcArtifact? loadedLibwebrtcArtifact,
    GameCaptureTestTargetResult? gameCaptureTestTargetResult,
    GameCaptureProbeResult? gameCaptureProbeResult,
    StreamTestHostLoadReport? hostLoadReport,
  }) {
    return StreamTestRunResult(
      startedAt: startedAt,
      endedAt: endedAt,
      targetLabel: targetLabel,
      roomId: roomId,
      config: config,
      presetResults: const [],
      error: Log.redactSensitiveInfo(error),
      diagnosticLogMarkers: streamTestDiagnosticMarkersFromText(
        diagnosticLogText,
        limit: diagnosticLogMarkerLimit,
      ),
      loadedLibwebrtcArtifact: loadedLibwebrtcArtifact,
      gameCaptureTestTargetResult: gameCaptureTestTargetResult,
      gameCaptureProbeResult: gameCaptureProbeResult,
      hostLoadReport: hostLoadReport,
    );
  }

  final DateTime startedAt;
  final DateTime endedAt;
  final String targetLabel;
  final String roomId;
  final StreamTestRunConfig config;
  final List<StreamTestPresetResult> presetResults;
  final String? error;
  final List<String> diagnosticLogMarkers;
  final StreamTestLoadedLibwebrtcArtifact? loadedLibwebrtcArtifact;
  final GameCaptureTestTargetResult? gameCaptureTestTargetResult;
  final GameCaptureProbeResult? gameCaptureProbeResult;
  final StreamTestHostLoadReport? hostLoadReport;

  StreamDiagnosticCoverageMatrix get diagnosticCoverage =>
      StreamDiagnosticCoverageMatrix.forRun(this);

  StreamTestPresetResult? get primaryResult {
    if (presetResults.isEmpty) {
      return null;
    }
    final candidates = presetResults
        .where((result) => result.score.bottleneck.label != 'healthy')
        .toList(growable: false);
    final considered =
        (candidates.isEmpty ? presetResults : candidates).toList();
    considered.sort((a, b) => a.score.totalScore.compareTo(b.score.totalScore));
    return considered.first;
  }

  String get recommendedNextAction {
    final probe = gameCaptureProbeResult;
    if (probe != null && probe.hasSlowPublicationHandoff) {
      return 'fix game-capture handoff';
    }
    return primaryResult?.score.bottleneck.recommendedNextAction ??
        'collect one specific missing field';
  }

  StreamTestRunResult withGameCaptureTestTargetResult(
    GameCaptureTestTargetResult? result,
  ) {
    return StreamTestRunResult(
      startedAt: startedAt,
      endedAt: endedAt,
      targetLabel: targetLabel,
      roomId: roomId,
      config: config,
      presetResults: presetResults,
      error: error,
      diagnosticLogMarkers: diagnosticLogMarkers,
      loadedLibwebrtcArtifact: loadedLibwebrtcArtifact,
      gameCaptureTestTargetResult: result,
      gameCaptureProbeResult: gameCaptureProbeResult,
      hostLoadReport: hostLoadReport,
    );
  }

  StreamTestRunResult withHostLoadReport(StreamTestHostLoadReport? report) {
    return StreamTestRunResult(
      startedAt: startedAt,
      endedAt: endedAt,
      targetLabel: targetLabel,
      roomId: roomId,
      config: config,
      presetResults: presetResults,
      error: error,
      diagnosticLogMarkers: diagnosticLogMarkers,
      loadedLibwebrtcArtifact: loadedLibwebrtcArtifact,
      gameCaptureTestTargetResult: gameCaptureTestTargetResult,
      gameCaptureProbeResult: gameCaptureProbeResult,
      hostLoadReport: report,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schema': 'intergalactic.streamTestRun.v1',
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'durationMs': endedAt.difference(startedAt).inMilliseconds,
      'targetLabel': _redactedFreeformLabel(targetLabel),
      'roomId': _redactedRoomId(roomId),
      'config': config.toJson(),
      'error': error == null ? null : Log.redactSensitiveInfo(error!),
      'diagnosticCoverage': diagnosticCoverage.toJson(),
      'recommendedNextAction': recommendedNextAction,
      'loadedLibwebrtc': loadedLibwebrtcArtifact?.toJson(),
      'hostLoad': hostLoadReport?.toJson(),
      'diagnosticLogMarkers':
          diagnosticLogMarkers.map(_redactedDiagnosticMarker).toList(),
      'gameCaptureTestTarget': gameCaptureTestTargetResult?.toJson(),
      'gameCaptureProbe': gameCaptureProbeResult?.toJson(),
      'presetResults': presetResults.map((result) => result.toJson()).toList(),
    };
  }

  String toJsonText() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  String toMarkdown() {
    final coverage = diagnosticCoverage;
    final primary = primaryResult;
    final buffer = StringBuffer()
      ..writeln('# Inter Galactic Stream Test Run')
      ..writeln()
      ..writeln('- Started: ${startedAt.toLocal()}')
      ..writeln('- Ended: ${endedAt.toLocal()}')
      ..writeln('- Scenario: ${_redactedFreeformLabel(config.scenarioLabel)}')
      ..writeln('- Target: ${_redactedFreeformLabel(targetLabel)}')
      ..writeln('- Room: ${_redactedRoomId(roomId)}')
      ..writeln('- Source: ${config.sourceMetadata?.label ?? 'unknown'}')
      ..writeln('- Run status: ${error == null ? 'completed' : 'failed'}')
      ..writeln('- Windows capture backend: '
          '${config.windowsCaptureBackendSelectionLabel}')
      ..writeln('- Native dirty-region mode: '
          '${config.windowsCaptureDirtyRegionMode.label}')
      ..writeln('- Window GDI capture methods: '
          '${config.windowsWindowGdiSelectionLabel}')
      ..writeln('- Native latest-frame pacer: '
          '${config.nativeFramePacingEnabled ? 'enabled' : 'disabled'}')
      ..writeln(
        '- Preset duration: ${config.durationPerPreset.inSeconds}s',
      )
      ..writeln(
        '- Warmup before sampling: ${config.warmupDuration.inSeconds}s',
      )
      ..writeln('- Sample interval: ${config.sampleInterval.inSeconds}s')
      ..writeln(
        '- Score: stable_fps + target_resolution + low_loss + low_rtt - downgrade_penalty',
      )
      ..writeln(
        '- Stable FPS scoring uses average FPS capped by sampled sender/native frame pacing, with p95/max frame gaps reflected in the score.',
      )
      ..writeln()
      ..writeln('## Executive Summary')
      ..writeln()
      ..writeln(
        '- Primary classification: '
        '${primary?.score.bottleneck.label ?? 'insufficient_evidence'} '
        '(${primary?.score.bottleneck.confidence ?? 'insufficient'} confidence)',
      )
      ..writeln(
        '- Primary bottleneck: '
        '${primary == null ? 'no preset results' : primary.resultLabel}',
      )
      ..writeln(
        '- Recommended next action: $recommendedNextAction',
      )
      ..writeln(
        '- Run error: ${error == null ? 'none' : Log.redactSensitiveInfo(error!)}',
      )
      ..writeln(
        '- Missing evidence: '
        '${coverage.missingFields.isEmpty ? 'none' : coverage.missingFields.join('; ')}',
      );
    if (loadedLibwebrtcArtifact != null) {
      buffer.writeln(
        '- Loaded libwebrtc: ${loadedLibwebrtcArtifact!.diagnosticLabel}',
      );
    }
    if (hostLoadReport != null) {
      buffer.writeln(
        '- Host load: ${_hostLoadCompactLabel(hostLoadReport!)}',
      );
    }
    if (gameCaptureProbeResult?.hasSlowPublicationHandoff == true) {
      buffer.writeln(
        '- Game-capture handoff: slow at '
        '${_number(gameCaptureProbeResult!.publicationHandoffOutputFps)}fps '
        'for target '
        '${gameCaptureProbeResult!.publicationHandoffRequestedTargetFps ?? gameCaptureProbeResult!.config.publicationHandoffTargetFps}fps',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Diagnostic Coverage')
      ..writeln()
      ..write(coverage.toMarkdownTable())
      ..writeln()
      ..writeln('## Host/System Load')
      ..writeln();
    if (hostLoadReport == null) {
      buffer.writeln('Host/system load diagnostics were not collected.');
    } else {
      buffer.write(_hostLoadMarkdown(hostLoadReport!));
    }

    buffer
      ..writeln()
      ..writeln('## Game Capture Test Target')
      ..writeln();
    if (gameCaptureTestTargetResult == null) {
      buffer.writeln(
        'No deterministic D3D11 capture target was requested for this run.',
      );
    } else {
      buffer.write(gameCaptureTestTargetResult!.toMarkdown());
    }

    buffer
      ..writeln()
      ..writeln('## Game Capture Probe')
      ..writeln();
    if (gameCaptureProbeResult == null) {
      buffer.writeln(
        'No D3D11 game-capture probe was requested for this run.',
      );
    } else {
      buffer.write(gameCaptureProbeResult!.toMarkdown());
    }

    buffer
      ..writeln()
      ..writeln('## Summary')
      ..writeln()
      ..writeln(
        '| Preset | Backend | GDI Mode | Capturer | Bottleneck | Score | Capture FPS | Encode FPS | Send FPS | Encoded | Pre-encode | Encode Time | Bitrate | Loss | RTT | Limit | Penalty |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | ---: |',
      );

    for (final result in presetResults) {
      final summary = result.score.summary;
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.backendSelectionLabel)} '
        '| ${_markdownCell(result.windowGdiSelectionLabel)} '
        '| ${_markdownCell(summary.nativeDiagnostics.observedCapturerLabel)} '
        '| ${_markdownCell(result.score.bottleneck.label)} '
        '| ${result.score.totalScore} '
        '| ${_number(summary.averageCaptureFps)} '
        '| ${_number(summary.averageEncodeFps)} '
        '| ${_number(summary.averageSendFps)} '
        '| ${summary.encodedResolutionLabel} '
        '| ${summary.preEncodeResolutionLabel} '
        '| ${_milliseconds(summary.averageEncodeTimeMs)} '
        '| ${_bitrate(summary.averageBitrateBps)} '
        '| ${_percent(summary.maxPacketLossPercent)} '
        '| ${_milliseconds(summary.maxRoundTripTimeMs)} '
        '| ${_markdownCell(summary.qualityLimitationReasonsLabel)} '
        '| ${result.score.downgradePenalty} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Frame Pacing')
      ..writeln()
      ..writeln(
        'Sampled stages are derived from cumulative WebRTC frame counters at the runner sample cadence. Native capture uses native cadence markers when present.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | Native Capture | Capture | Pre-encode | Encoded | Sent | Received | Decoded | Rendered |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
      );
    for (final result in presetResults) {
      final pacing = result.score.summary.framePacing;
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.backendSelectionLabel)} '
        '| ${_markdownCell(pacing.nativeCapture.markdownLabel)} '
        '| ${_markdownCell(pacing.capture.markdownLabel)} '
        '| ${_markdownCell(pacing.preEncode.markdownLabel)} '
        '| ${_markdownCell(pacing.encoded.markdownLabel)} '
        '| ${_markdownCell(pacing.sent.markdownLabel)} '
        '| ${_markdownCell(pacing.received.markdownLabel)} '
        '| ${_markdownCell(pacing.decoded.markdownLabel)} '
        '| ${_markdownCell(pacing.rendered.markdownLabel)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Sender Handoff Diagnostics')
      ..writeln()
      ..writeln(
        'This block follows the live D3D11 game-hook sender boundary: WebRTC OnFrame call duration, source/broadcaster dispatch, VideoStreamEncoder queue/encode timing, native NV12 fence/readiness, Media Foundation input/output timing, and sender drop counters.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | OnFrame Call | Native Frame Age | Delivery Queue | Native Ready | WebRTC Raw Sender | Media Foundation | Sender Counters | Missing Fields |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
      );
    for (final result in presetResults) {
      final summary = result.score.summary;
      final native = summary.nativeDiagnostics;
      final missing = summary.senderHandoffDiagnosticMissingFields;
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.backendSelectionLabel)} '
        '| ${_milliseconds(native.averageGameCaptureDeliveryOnFrameCallMs)} avg / '
        '${_milliseconds(native.maxGameCaptureDeliveryOnFrameCallMs)} max / '
        '${native.gameCaptureDeliveryOnFrameCallSamples} samples '
        '| ${_milliseconds(native.averageGameCaptureNativeNv12ConversionStartAgeMs)} avg / '
        '${_milliseconds(native.maxGameCaptureNativeNv12ConversionStartAgeMs)} max / '
        '${native.gameCaptureNativeNv12ConversionStartAgeSamples} samples '
        '| wait ${_milliseconds(native.averageGameCaptureDeliveryQueueWaitMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryQueueWaitMs)}; '
        'source-submit ${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)} '
        '| deliveryDepth=${native.gameCaptureDeliveryQueueDepth ?? '?'} '
        'readyDrain=${native.gameCaptureNativeNv12ReadyDrainDepth ?? '?'} '
        'policy=${_markdownCell(native.gameCaptureNativeNv12ReadyPolicy ?? 'unknown')} '
        'ownership=${_markdownCell(native.gameCaptureNativeNv12FrameOwnership ?? 'unknown')} '
        'ownedCopy=${native.gameCaptureNativeNv12OwnedCopies} '
        '${_milliseconds(native.averageGameCaptureNativeNv12OwnedCopyMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12OwnedCopyMs)} '
        'fence=${native.gameCaptureNativeNv12FenceAvailable ?? '?'} '
        'signaled=${native.gameCaptureNativeNv12FenceSignaledFrames} '
        'notReady=${native.gameCaptureNativeNv12NotReadyPolls} '
        'readyDropped=${native.gameCaptureNativeNv12ReadyDroppedFrames} '
        'failures=${native.gameCaptureNativeNv12Failures} '
        'cpuFallback=${native.gameCaptureCpuFallbackFrames} '
        '| ${_markdownCell(native.webrtcRawSenderBoundaryLabel)} '
        '| total ${_milliseconds(native.averageEncoderTotalMs)}/'
        '${_milliseconds(native.maxEncoderTotalMs)}; '
        'fenceWait ${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/'
        '${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)}; '
        'input ${_milliseconds(native.averageEncoderProcessInputMs)}/'
        '${_milliseconds(native.maxEncoderProcessInputMs)}; '
        'output ${_milliseconds(native.averageEncoderProcessOutputMs)}/'
        '${_milliseconds(native.maxEncoderProcessOutputMs)}; '
        'callback ${_milliseconds(native.averageEncoderEncodedCallbackMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackMs)}; '
        'callbackWait ${_milliseconds(native.averageEncoderEncodedCallbackQueueWaitMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackQueueWaitMs)}; '
        'callbackEnqueue ${_milliseconds(native.averageEncoderEncodedCallbackEnqueueMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackEnqueueMs)}; '
        'callbackQueue=${native.encoderMaxEncodedCallbackQueueDepth}; '
        'callbackDrops=${native.encoderMaxEncodedCallbackDrops}; '
        'callbackOutputs=${native.encoderMaxEncodedCallbackOutputs}; '
        'queue=${native.encoderMaxQueueDepth}; '
        'retained=${native.encoderMaxRetainedSamples}; '
        'encodedOutputs=${native.encoderMaxEncodedOutputs} '
        '| droppedBeforeEncode=${summary.framesDroppedBeforeEncodeMax ?? '?'}; '
        'droppedByEncoder=${summary.framesDroppedByEncoderMax ?? '?'}; '
        'frames=${summary.framesCapturedMax ?? '?'}/'
        '${summary.framesEncodedMax ?? '?'}/${summary.framesSentMax ?? '?'} '
        '| ${_markdownCell(missing.isEmpty ? 'none' : missing.join(', '))} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Time-Window Degradation')
      ..writeln()
      ..writeln(
        'These windows split the sampled run so a stream that starts smooth and decays later is visible without manually reading raw counters.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | Window | Samples | Capture FPS | Encode FPS | Send FPS | Sent Gap | Render FPS | Native Submitted | D3D11 Readback | Signals |',
      )
      ..writeln(
        '| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | --- |',
      );
    for (final result in presetResults) {
      final temporal = result.score.temporalAnalysis;
      if (!temporal.hasEvidence) {
        buffer.writeln(
          '| ${_markdownCell(result.profile.label)} '
          '| ${_markdownCell(result.backendSelectionLabel)} '
          '| none | 0 | ? | ? | ? | ? | ? | ? | ? | no time-window evidence |',
        );
        continue;
      }
      for (final window in temporal.windows) {
        final framePacing = window.framePacing;
        final gameCapture = window.gameCapture;
        final windowSignals = <String>[
          if (temporal.hasLateDegradation &&
              (window.label == 'late' || window.label == 'tail_10s'))
            ...temporal.lateDegradationSignals,
        ];
        buffer.writeln(
          '| ${_markdownCell(result.profile.label)} '
          '| ${_markdownCell(result.backendSelectionLabel)} '
          '| ${_markdownCell('${window.label} ${window.offsetLabel}')} '
          '| ${window.sampleCount} '
          '| ${_number(window.summary.averageCaptureFps)} '
          '| ${_number(window.summary.averageEncodeFps)} '
          '| ${_number(window.summary.averageSendFps)} '
          '| ${_milliseconds(framePacing.sent.p95IntervalMs)} p95 / '
          '${_milliseconds(framePacing.sent.maxIntervalMs)} max '
          '| ${_number(framePacing.rendered.averageFps)} '
          '| ${_markdownCell(gameCapture == null ? 'native window unavailable' : '${_number(gameCapture.submittedFps)}fps (+${gameCapture.submittedDelta})')} '
          '| ${_markdownCell(gameCapture?.compactLabel ?? 'native window unavailable')} '
          '| ${_markdownCell(windowSignals.isEmpty ? 'none' : windowSignals.join('; '))} |',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('## Capture Cause Attribution')
      ..writeln()
      ..writeln(
        'These fields split native capture-call cost into the likely causes being investigated. `unknown` means the current log did not contain that evidence.',
      )
      ..writeln()
      ..writeln(
        '| Preset | Backend | Full Source Acquisition | Blocking Acquire Wait | CPU Readback / Copy | Dirty-Region Processing | Frame Lifetime / Lock / Sync | Full-Frame Copy Before Downscale |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | --- | --- | --- |',
      );
    for (final result in presetResults) {
      final native = result.nativeDiagnostics;
      buffer.writeln(
        '| ${_markdownCell(result.profile.label)} '
        '| ${_markdownCell(result.nativeBackendLabel)} '
        '| ${_markdownCell(native.fullSourceAcquisitionAttributionLabel)} '
        '| ${_markdownCell(native.blockingAcquireAttributionLabel)} '
        '| ${_markdownCell(native.cpuReadbackAttributionLabel)} '
        '| ${_markdownCell(native.dirtyRegionProcessingAttributionLabel)} '
        '| ${_markdownCell(native.frameLifetimeSyncAttributionLabel)} '
        '| ${_markdownCell(native.fullFrameCopyBeforeDownscaleAttributionLabel)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Native Diagnostic Markers')
      ..writeln();
    if (presetResults.any(
      (result) => result.nativeDiagnostics.hasEvidence,
    )) {
      buffer
        ..writeln(
            '| Preset | Backend | Observed Capturer | Dirty Mode | Native Source | Window Rect | Content | Pre-encode | Canvas | Native FPS | Submitted FPS | Frame Interval | Dominant Phase | Capture Call | Source Capture | WGC Substage | GDI Substage | Callback Entry | Acquire Wait | Post Callback | Unaccounted Wait | Frame Work | Updated Region | Dirty Shape | Dirty Work | Native Encoder | Crop |')
        ..writeln(
            '| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
      for (final result in presetResults) {
        final native = result.nativeDiagnostics;
        buffer.writeln(
          '| ${_markdownCell(result.profile.label)} '
          '| ${_markdownCell(result.nativeBackendLabel)} '
          '| ${_markdownCell(native.observedCapturerLabel)} '
          '| ${_markdownCell(native.dirtyRegionModeLabel)} '
          '| ${native.nativeSourceResolutionLabel} '
          '| ${native.nativeWindowRectResolutionLabel} '
          '| ${native.contentResolutionLabel} '
          '| ${native.preEncodeResolutionLabel} '
          '| ${_markdownCell(native.canvasLabel)} '
          '| ${_number(native.averageNativeFps)} '
          '| ${_number(native.averageSubmittedFps)} '
          '| ${_milliseconds(native.p95FrameIntervalMs)} p95 / '
          '${_milliseconds(native.maxFrameIntervalMs)} max '
          '| ${_markdownCell(native.dominantCaptureDelayStageLabel)} '
          '| ${_milliseconds(native.averageCaptureCallMs)} avg / '
          '${_milliseconds(native.maxCaptureCallMs)} max '
          '| ${_milliseconds(native.averageSourceCaptureMs)} avg / '
          '${_milliseconds(native.maxSourceCaptureMs)} max '
          '| ${_markdownCell(native.reportWgcFrameSummaryLabel)} '
          '| ${_markdownCell(native.reportGdiFrameSummaryLabel)} '
          '| ${_milliseconds(native.averageCallbackEntryDelayMs)} avg / '
          '${_milliseconds(native.maxCallbackEntryDelayMs)} max '
          '| ${_milliseconds(native.averageCaptureAcquireWaitMs)} avg / '
          '${_milliseconds(native.maxCaptureAcquireWaitMs)} max '
          '| ${_milliseconds(native.averagePostCallbackWaitMs)} avg / '
          '${_milliseconds(native.maxPostCallbackWaitMs)} max '
          '| ${_milliseconds(native.averageUnaccountedWaitMs)} avg / '
          '${_milliseconds(native.maxUnaccountedWaitMs)} max '
          '| ${_milliseconds(native.averageFrameCallbackMs)} callback '
          '(${_milliseconds(native.averageFrameConvertMs)} convert, '
          '${_milliseconds(native.averageFrameScaleMs)} scale, '
          '${_milliseconds(native.averageFrameOnFrameMs)} onFrame) '
          '| ${native.updatedRegionNonEmptyCount} dirty / '
          '${native.updatedRegionEmptyCount} empty '
          '| ${_markdownCell(native.updatedRegionShapeLabel)} '
          '| ${_milliseconds(native.averageUpdatedRegionAnalysisMs)} avg / '
          '${_milliseconds(native.maxUpdatedRegionAnalysisMs)} max '
          '| ${_milliseconds(native.averageEncoderTotalMs)} avg / '
          '${_milliseconds(native.maxEncoderTotalMs)} max '
          '| ${native.cropRegion == null ? '?' : native.cropRegion! ? 'true' : 'false'} |',
        );
      }
      buffer.writeln();
    }
    if (diagnosticLogMarkers.isEmpty) {
      buffer.writeln(
        'No matching native capture or encoder log markers were found in the recent diagnostic log tail.',
      );
    } else {
      buffer
        ..writeln('```text')
        ..writeln(
            diagnosticLogMarkers.map(_redactedDiagnosticMarker).join('\n'))
        ..writeln('```');
    }

    for (final result in presetResults) {
      final score = result.score;
      final summary = score.summary;
      buffer
        ..writeln()
        ..writeln('## ${result.resultLabel}')
        ..writeln()
        ..writeln('- Total score: ${score.totalScore}')
        ..writeln('- Requested backend: ${result.backendSelectionLabel}')
        ..writeln('- Native backend: ${result.nativeBackendLabel}')
        ..writeln('- Observed native capturer: '
            '${summary.nativeDiagnostics.observedCapturerLabel}')
        ..writeln('- Native dirty-region mode: '
            '${summary.nativeDiagnostics.dirtyRegionModeLabel}')
        ..writeln('- Applied profile details: ${summary.profileDetailsLabel}')
        ..writeln('- Sender codec/encoder: '
            'codec=${summary.senderCodecsLabel} '
            'engine=${summary.encoderImplementationsLabel} '
            'hw=${summary.hardwareEncodeStatesLabel}')
        ..writeln('- Stable FPS: ${score.stableFps}')
        ..writeln('- Target resolution: ${score.targetResolution}')
        ..writeln('- Low loss: ${score.lowLoss}')
        ..writeln('- Low RTT: ${score.lowRtt}')
        ..writeln('- Downgrade penalty: ${score.downgradePenalty}')
        ..writeln(
          '- Classification: ${score.bottleneck.label} '
          '(${score.bottleneck.confidence} confidence)',
        )
        ..writeln('- Bottleneck: ${score.bottleneck.label}')
        ..writeln('- Bottleneck evidence: '
            '${score.bottleneck.reasons.isEmpty ? 'none' : score.bottleneck.reasons.join('; ')}')
        ..writeln('- Evidence for bottleneck: '
            '${score.bottleneck.effectiveEvidenceFor.isEmpty ? 'none' : score.bottleneck.effectiveEvidenceFor.join('; ')}')
        ..writeln('- Evidence against common false causes: '
            '${score.bottleneck.evidenceAgainstFalseCauses.isEmpty ? 'none' : score.bottleneck.evidenceAgainstFalseCauses.join('; ')}')
        ..writeln('- Missing evidence: '
            '${score.bottleneck.missingFields.isEmpty ? 'none' : score.bottleneck.missingFields.join('; ')}')
        ..writeln(
          '- Recommended next action: '
          '${score.bottleneck.recommendedNextAction}',
        )
        ..writeln(
            '- Average capture FPS: ${_number(summary.averageCaptureFps)}')
        ..writeln(
            '- Minimum capture FPS: ${_number(summary.minimumCaptureFps)}')
        ..writeln('- Average encode FPS: ${_number(summary.averageEncodeFps)}')
        ..writeln('- Minimum encode FPS: ${_number(summary.minimumEncodeFps)}')
        ..writeln('- Average send FPS: ${_number(summary.averageSendFps)}')
        ..writeln('- Minimum send FPS: ${_number(summary.minimumSendFps)}')
        ..writeln('- Average FPS: ${_number(summary.averageFps)}')
        ..writeln('- Minimum FPS: ${_number(summary.minimumFps)}')
        ..writeln('- Average bitrate: ${_bitrate(summary.averageBitrateBps)}')
        ..writeln('- Available outgoing bitrate: '
            '${_bitrate(summary.minimumAvailableOutgoingBitrateBps)} min / '
            '${_bitrate(summary.averageAvailableOutgoingBitrateBps)} avg / '
            '${_bitrate(summary.maximumAvailableOutgoingBitrateBps)} max')
        ..writeln('- Average encode time: '
            '${_milliseconds(summary.averageEncodeTimeMs)}')
        ..writeln(
            '- Max encode time: ${_milliseconds(summary.maxEncodeTimeMs)}')
        ..writeln('- Average packet send delay: '
            '${_milliseconds(summary.averagePacketSendDelayMs)}')
        ..writeln('- Encoded resolution: ${summary.encodedResolutionLabel}')
        ..writeln('- Requested resolution: ${summary.requestedResolutionLabel}')
        ..writeln('- Pre-encode resolution: '
            '${summary.preEncodeResolutionLabel} '
            '(${summary.preEncodeSampleCount}/${summary.senderSampleCount} samples)')
        ..writeln('- Capture pipeline: ${summary.capturePipelineLabel}')
        ..writeln('- Frame pacing: ${summary.framePacing.compactLabel}')
        ..writeln('- Time-window signals: '
            '${score.temporalAnalysis.lateDegradationSignals.isEmpty ? 'none' : score.temporalAnalysis.lateDegradationSignals.join('; ')}')
        ..writeln('- Native capture pipeline: '
            '${summary.nativeDiagnostics.summaryLabel}')
        ..writeln('- Capture output validity: '
            '${summary.nativeDiagnostics.gdiOutputValidityLabel}')
        ..writeln('- Subjective notes: ')
        ..writeln(
            '- Max packet loss: ${_percent(summary.maxPacketLossPercent)}')
        ..writeln('- Max RTT: ${_milliseconds(summary.maxRoundTripTimeMs)}')
        ..writeln(
          '- Quality limitation: ${summary.qualityLimitationReasonsLabel}',
        )
        ..writeln('- Active layers: ${summary.activeLayersLabel}');
      if (result.error != null) {
        buffer.writeln('- Error: `${result.error}`');
      }
    }

    return buffer.toString();
  }
}

class StreamTestScore {
  const StreamTestScore({
    required this.stableFps,
    required this.targetResolution,
    required this.lowLoss,
    required this.lowRtt,
    required this.downgradePenalty,
    required this.bottleneck,
    required this.summary,
    required this.temporalAnalysis,
  });

  factory StreamTestScore.fromSamples({
    required ScreenShareProfileConfig profile,
    required List<StreamTestSample> samples,
    String? error,
    StreamTestNativeDiagnostics nativeDiagnostics =
        const StreamTestNativeDiagnostics(),
    List<String> diagnosticLogMarkers = const [],
    DateTime? measurementStartedAt,
    DateTime? measurementEndedAt,
  }) {
    final summary = StreamTestSummary.fromSamples(
      samples,
      nativeDiagnostics: nativeDiagnostics,
    );
    final targetFps = profile.mainLayer.targetFramerateForScoring.toDouble();
    final temporalAnalysis = StreamTestTemporalAnalysis.fromSamplesAndMarkers(
      samples: samples,
      nativeDiagnosticMarkers: diagnosticLogMarkers,
      measurementStartedAt: measurementStartedAt,
      measurementEndedAt: measurementEndedAt,
      targetFps: targetFps,
    );
    final captureOutputProbablyInvalid =
        summary.nativeDiagnostics.gdiOutputProbablyInvalid;
    final averageFps = summary.averageFps;
    final fpsRatio = _effectiveFpsRatio(
      summary: summary,
      targetFps: targetFps,
      averageFps: averageFps,
    );
    final baseStableFps =
        captureOutputProbablyInvalid ? 0 : _fpsScore(fpsRatio);
    final targetResolution =
        captureOutputProbablyInvalid ? 0 : _resolutionScore(profile, summary);
    final lowLoss = _lossScore(summary);
    final lowRtt = _rttScore(summary);
    final downgradePenalty = _downgradePenalty(
      profile: profile,
      summary: summary,
      fpsRatio: fpsRatio,
      error: error,
    );
    final bottleneck = _classifyBottleneck(
      profile: profile,
      summary: summary,
      temporalAnalysis: temporalAnalysis,
      fpsRatio: fpsRatio,
      error: error,
    );
    final stableFps = _stableFpsScoreForBottleneck(
      baseStableFps: baseStableFps,
      bottleneck: bottleneck,
    );

    return StreamTestScore(
      stableFps: stableFps,
      targetResolution: targetResolution,
      lowLoss: lowLoss,
      lowRtt: lowRtt,
      downgradePenalty: downgradePenalty,
      bottleneck: bottleneck,
      summary: summary,
      temporalAnalysis: temporalAnalysis,
    );
  }

  final int stableFps;
  final int targetResolution;
  final int lowLoss;
  final int lowRtt;
  final int downgradePenalty;
  final StreamTestBottleneck bottleneck;
  final StreamTestSummary summary;
  final StreamTestTemporalAnalysis temporalAnalysis;

  int get totalScore =>
      stableFps + targetResolution + lowLoss + lowRtt - downgradePenalty;

  Map<String, Object?> toJson() {
    return {
      'formula':
          'stable_fps + target_resolution + low_loss + low_rtt - downgrade_penalty; stable_fps uses average FPS capped by sampled sender/native p95/max frame pacing',
      'stable_fps': stableFps,
      'target_resolution': targetResolution,
      'low_loss': lowLoss,
      'low_rtt': lowRtt,
      'downgrade_penalty': downgradePenalty,
      'bottleneck': bottleneck.toJson(),
      'temporalAnalysis': temporalAnalysis.toJson(),
      'total': totalScore,
    };
  }

  static int _fpsScore(double ratio) {
    if (ratio >= 0.9) return 25;
    if (ratio >= 0.75) return 20;
    if (ratio > 0) {
      return (ratio * 25).round().clamp(1, 18).toInt();
    }
    return 0;
  }

  static int _stableFpsScoreForBottleneck({
    required int baseStableFps,
    required StreamTestBottleneck bottleneck,
  }) {
    if (bottleneck.label == 'frame_pacing_unstable' ||
        bottleneck.label == 'delivery_queue_limited' ||
        bottleneck.label == 'native_nv12_ready_limited' ||
        bottleneck.label == 'encoder_handoff_limited') {
      return min(baseStableFps, 10);
    }
    return baseStableFps;
  }

  static int _resolutionScore(
    ScreenShareProfileConfig profile,
    StreamTestSummary summary,
  ) {
    final width = summary.encodedWidth;
    final height = summary.encodedHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 0;
    }

    final targetWidth = profile.mainLayer.width;
    final targetHeight = profile.mainLayer.height;
    final exceedsTarget =
        width > targetWidth + 32 || height > targetHeight + 18;
    final pixelRatio = (width * height) / (targetWidth * targetHeight);
    if (exceedsTarget) return 5;
    if (pixelRatio >= 0.9) return 25;
    if (pixelRatio >= 0.75) return 18;
    if (pixelRatio >= 0.5) return 10;
    return 4;
  }

  static int _lossScore(StreamTestSummary summary) {
    final loss = summary.maxPacketLossPercent;
    if (loss == null) return 0;
    final nack = summary.maxNackCount ?? 0;
    if (loss <= 0.5 && nack <= 2) return 25;
    if (loss <= 1.0 && nack <= 8) return 20;
    if (loss <= 3.0) return 12;
    return 0;
  }

  static int _rttScore(StreamTestSummary summary) {
    final rtt = summary.maxRoundTripTimeMs;
    if (rtt == null) return 0;
    if (rtt <= 60) return 15;
    if (rtt <= 120) return 10;
    if (rtt <= 250) return 5;
    return 0;
  }

  static int _downgradePenalty({
    required ScreenShareProfileConfig profile,
    required StreamTestSummary summary,
    required double fpsRatio,
    String? error,
  }) {
    var penalty = 0;
    if (error != null) {
      penalty += 30;
    }
    if (summary.qualityLimitationReasons.any(
      (reason) => reason.toLowerCase() != 'none',
    )) {
      penalty += 10;
    }
    if (summary.activeLayers.any(_isDowngradedLayer)) {
      penalty += 10;
    }
    if (summary.nativeDiagnostics.gdiOutputProbablyInvalid) {
      penalty += 30;
    }
    if (fpsRatio > 0 && fpsRatio < 0.5) {
      penalty += 10;
    }
    final width = summary.encodedWidth;
    final height = summary.encodedHeight;
    if (width != null && height != null) {
      final pixelRatio = (width * height) /
          (profile.mainLayer.width * profile.mainLayer.height);
      if (pixelRatio < 0.5) {
        penalty += 10;
      }
    }
    return penalty.clamp(0, 30).toInt();
  }

  static bool _isDowngradedLayer(String layer) {
    final normalized = layer.toLowerCase();
    return normalized == 'q' ||
        normalized == 'l' ||
        normalized == 'low' ||
        normalized.contains('low-layer') ||
        normalized.contains('rescue');
  }

  static bool _isLiveKitPublishPreEventError(String? error) {
    if (error == null) {
      return false;
    }
    final normalized = error.toLowerCase();
    return normalized.contains('publishvideotrack') &&
        (normalized.contains('before local track publication') ||
            normalized.contains('stage=publishvideotrack_pre_event'));
  }

  static StreamTestBottleneck _classifyBottleneck({
    required ScreenShareProfileConfig profile,
    required StreamTestSummary summary,
    required StreamTestTemporalAnalysis temporalAnalysis,
    required double fpsRatio,
    String? error,
  }) {
    final reasons = <String>[];
    final native = summary.nativeDiagnostics;
    if (_isLiveKitPublishPreEventError(error)) {
      final reportedError = error ?? 'unknown';
      return StreamTestBottleneck(
        label: 'livekit_publish_pre_event_limited',
        reasons: [
          'LiveKit publishVideoTrack timed out before local publication',
        ],
        confidence: 'high',
        evidenceFor: ['runner reported error: $reportedError'],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(
          summary,
        ),
        missingFields: [
          'LiveKit local publication event',
          'sender track stats',
          'native WebRTC source startup markers',
        ],
        recommendedNextAction: 'fix game-capture handoff',
      );
    }
    if (_nativeEncoderHandoffLimited(summary)) {
      return _nativeEncoderHandoffLimitedBottleneck(summary);
    }
    if (_gameCaptureGpuHandoffUnproven(summary)) {
      return _gameCaptureGpuHandoffUnprovenBottleneck(summary);
    }
    if (error != null) {
      return StreamTestBottleneck(
        label: 'runner_error',
        reasons: ['runner error: $error'],
        confidence: 'high',
        evidenceFor: ['runner reported error: $error'],
        missingFields: _classificationMissingFields(summary),
        recommendedNextAction: 'fix source selection',
      );
    }
    if (summary.senderSampleCount == 0) {
      return const StreamTestBottleneck(
        label: 'no_sent_frames',
        reasons: ['no sender screenshare stats were collected'],
        confidence: 'medium',
        missingFields: [
          'sender track stats',
          'encoded frame size',
          'send FPS',
        ],
        evidenceFor: ['no sender screenshare stats were collected'],
        recommendedNextAction: 'fix source selection',
      );
    }

    if (native.gdiOutputProbablyInvalid) {
      return StreamTestBottleneck(
        label: 'invalid_capture_output',
        reasons: [
          native.gdiOutputValidityLabel,
          if (native.gdiFrameSummaryLabel != 'unknown')
            'window-GDI substage ${native.gdiFrameSummaryLabel}',
        ],
        confidence: 'high',
        evidenceFor: [
          native.gdiOutputValidityLabel,
          'final window-GDI frame producer mix: '
              '${native.gdiFinalMethodMixLabel}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(
          summary,
        ),
        recommendedNextAction: 'fix window-GDI substage',
      );
    }

    if (_resolutionLimitNotApplied(summary)) {
      return StreamTestBottleneck(
        label: 'resolution_limit_not_applied',
        reasons: [
          'requested ${summary.requestedResolutionLabel} but encoded '
              '${summary.encodedResolutionLabel}',
          if (summary.preEncodeResolutionLabel != 'unknown')
            'pre-encode ${summary.preEncodeResolutionLabel}',
        ],
        confidence: 'high',
        evidenceFor: [
          'requested ${summary.requestedResolutionLabel} but encoded '
              '${summary.encodedResolutionLabel}',
          if (summary.preEncodeResolutionLabel != 'unknown')
            'pre-encode ${summary.preEncodeResolutionLabel}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix geometry/scaling',
      );
    }

    final targetFps = profile.mainLayer.targetFramerateForScoring.toDouble();
    final captureFps = summary.averageCaptureFps;
    final encodeFps = summary.averageEncodeFps;
    final sendFps = summary.averageSendFps;
    final frameBudgetMs = targetFps <= 0 ? null : 1000 / targetFps;
    final averageEncodeTimeMs = summary.averageEncodeTimeMs;
    final nativeCaptureLimited = native.isCaptureLimitedFor(
      targetFps: targetFps,
      frameBudgetMs: frameBudgetMs,
    );
    final captureEncodeSendTrack = captureFps == null ||
        (_stageFpsTracks(encodeFps, captureFps) &&
            _stageFpsTracks(sendFps, encodeFps ?? captureFps));
    final nativeNv12SourceActive =
        native.gameCaptureNativeNv12SubmittedFrames > 0 &&
            native.gameCaptureNativeNv12Failures == 0 &&
            native.gameCaptureCpuFallbackFrames == 0;
    if (nativeNv12SourceActive) {
      final missingNativeEncoderFenceTiming =
          _gameCaptureNativeEncoderFenceTimingMissingBottleneck(
        summary: summary,
        native: native,
        frameBudgetMs: frameBudgetMs,
      );
      if (missingNativeEncoderFenceTiming != null) {
        return missingNativeEncoderFenceTiming;
      }
      final liveSenderHandoffBackpressure =
          _gameCaptureLiveSenderHandoffBackpressureBottleneck(
        summary: summary,
        native: native,
        frameBudgetMs: frameBudgetMs,
        targetFps: targetFps,
      );
      if (liveSenderHandoffBackpressure != null) {
        return liveSenderHandoffBackpressure;
      }
      final nativeNv12ReadyLimited = _gameCaptureNativeNv12ReadyBottleneck(
        summary: summary,
        native: native,
        frameBudgetMs: frameBudgetMs,
      );
      if (nativeNv12ReadyLimited != null) {
        return nativeNv12ReadyLimited;
      }
      final gameCaptureOnFrameLimited = _gameCaptureOnFrameLimitedBottleneck(
        summary: summary,
        native: native,
        frameBudgetMs: frameBudgetMs,
      );
      if (gameCaptureOnFrameLimited != null) {
        return gameCaptureOnFrameLimited;
      }
      final gameCaptureNativeDeliveryBackpressure =
          _gameCaptureDeliveryBackpressureBottleneck(
        summary: summary,
        native: native,
        frameBudgetMs: frameBudgetMs,
      );
      if (gameCaptureNativeDeliveryBackpressure != null) {
        return gameCaptureNativeDeliveryBackpressure;
      }
      if (native.isNativeEncoderOverBudgetFor(frameBudgetMs)) {
        return _mediaFoundationEncoderLimitedBottleneck(
          summary: summary,
          frameBudgetMs: frameBudgetMs,
        );
      }
    }
    final loss = summary.maxPacketLossPercent ?? 0;
    final rtt = summary.maxRoundTripTimeMs ?? 0;
    final nack = summary.maxNackCount ?? 0;
    if (loss > 1.0 || rtt > 150 || nack > 8) {
      if (loss > 1.0) {
        reasons.add('packet loss ${loss.toStringAsFixed(1)}%');
      }
      if (rtt > 150) {
        reasons.add('RTT ${rtt.toStringAsFixed(0)}ms');
      }
      if (nack > 8) {
        reasons.add('NACK count $nack');
      }
      return StreamTestBottleneck(
        label: 'network_limited',
        reasons: reasons,
        confidence: 'high',
        evidenceFor: reasons,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) => !evidence.startsWith('network evidence'))
            .toList(growable: false),
        recommendedNextAction: 'inspect server/network',
      );
    }
    final gameCaptureHasSourceFramesBeyondSubmitted =
        native.gameCaptureCopiedFrames >
            native.gameCaptureSubmittedFrames +
                max(10, native.gameCaptureDuplicateSkippedFrames * 2);
    final gameCaptureSubmitGap =
        native.gameCaptureCopiedFrames - native.gameCaptureSubmittedFrames;
    final gameCaptureReadbackDropsHigh =
        native.gameCaptureReadbackLatencyDroppedFrames >
            max(10, gameCaptureSubmitGap ~/ 4);
    final gameCaptureReadbackDeliveryLimited =
        gameCaptureHasSourceFramesBeyondSubmitted &&
            native.gameCaptureGpuScaledFrames > 0 &&
            native.gameCaptureCpuFallbackFrames == 0 &&
            gameCaptureReadbackDropsHigh;
    if (gameCaptureReadbackDeliveryLimited) {
      final copiedEvidence =
          'game hook copied ${native.gameCaptureCopiedFrames} source frames '
          'but submitted ${native.gameCaptureSubmittedFrames}';
      final readbackEvidence = 'readback latency dropped '
          '${native.gameCaptureReadbackLatencyDroppedFrames} frames with '
          '${native.gameCaptureReadbackNotReadyFrames} not-ready maps';
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: [
          copiedEvidence,
          readbackEvidence,
          if (native.gameCaptureMaxReadbackLatencyFrames > 0)
            'readback latency reached '
                '${native.gameCaptureMaxReadbackLatencyFrames} frames',
        ],
        confidence: 'high',
        evidenceFor: [
          copiedEvidence,
          readbackEvidence,
        ],
        evidenceAgainstFalseCauses: [
          if (native.averageEncoderTotalMs != null &&
              frameBudgetMs != null &&
              !native.isNativeEncoderOverBudgetFor(frameBudgetMs))
            'native encoder timing ${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms is below ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
          if (native.gameCaptureNativeNv12SubmittedFrames > 0)
            'native NV12 WebRTC source submission succeeded '
                '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
                '${native.gameCaptureNativeNv12Failures} failures and '
                '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
          'source regressions ${native.gameCaptureSourceFrameRegressions}, '
              'shared slot mismatches '
              '${native.gameCaptureSharedSlotMismatches}',
          ..._evidenceAgainstCommonFalseCauses(summary)
              .where((evidence) => !evidence.startsWith('native encoder'))
              .toList(growable: false),
        ],
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }
    final gameCaptureSubmittedFrames = native.gameCaptureSubmittedFrames;
    final gameCaptureRepeatRatio = gameCaptureSubmittedFrames <= 0
        ? 0.0
        : native.gameCaptureRepeatedFrames / gameCaptureSubmittedFrames;
    final repeatedFrameThreshold = max(
        (targetFps * 2).round(), (gameCaptureSubmittedFrames * 0.02).round());
    final gameCaptureRepeatedDeliveryLimited =
        native.gameCaptureRepeatedFrames > repeatedFrameThreshold &&
            native.gameCaptureGpuScaledFrames > 0 &&
            native.gameCaptureCpuFallbackFrames == 0 &&
            native.gameCaptureSourceFrameRegressions == 0 &&
            native.gameCaptureSharedSlotMismatches == 0;
    if (gameCaptureRepeatedDeliveryLimited) {
      final repeatedEvidence =
          'game hook repeated ${native.gameCaptureRepeatedFrames} of '
          '$gameCaptureSubmittedFrames submitted frames '
          '(${(gameCaptureRepeatRatio * 100).toStringAsFixed(1)}%)';
      final readbackEvidence = [
        if (native.averageGameCaptureReadbackLatencyFrames != null)
          'readback latency averaged '
              '${native.averageGameCaptureReadbackLatencyFrames!.toStringAsFixed(1)} '
              'queued frames',
        if (native.gameCaptureMaxReadbackLatencyFrames > 0)
          'readback latency peaked at '
              '${native.gameCaptureMaxReadbackLatencyFrames} queued frames',
        if (native.gameCaptureReadbackNotReadyFrames > 0)
          '${native.gameCaptureReadbackNotReadyFrames} readback map attempts '
              'were not ready',
      ];
      final nativeNv12Evidence = [
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        if (native.gameCaptureNativeNv12ReadyDroppedFrames > 0)
          'native NV12 ready queue dropped '
              '${native.gameCaptureNativeNv12ReadyDroppedFrames} frames',
        if (native.gameCaptureNativeNv12NotReadyPolls > 0)
          'native NV12 readiness polled not-ready '
              '${native.gameCaptureNativeNv12NotReadyPolls} times',
      ];
      final repeatedPathEvidence =
          nativeNv12SourceActive ? nativeNv12Evidence : readbackEvidence;
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: [
          repeatedEvidence,
          ...repeatedPathEvidence,
          'encoded/sent FPS can remain near target while visual cadence stutters '
              'because repeated source frames are delivered at paced timestamps',
        ],
        confidence: 'high',
        evidenceFor: [
          repeatedEvidence,
          ...repeatedPathEvidence,
        ],
        evidenceAgainstFalseCauses: [
          if (native.averageEncoderTotalMs != null &&
              frameBudgetMs != null &&
              !native.isNativeEncoderOverBudgetFor(frameBudgetMs))
            'native encoder timing ${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms is below ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
          if (native.gameCaptureNativeNv12SubmittedFrames > 0)
            'native NV12 WebRTC source submission succeeded '
                '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
                '${native.gameCaptureNativeNv12Failures} failures and '
                '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
          'source regressions ${native.gameCaptureSourceFrameRegressions}, '
              'shared slot mismatches '
              '${native.gameCaptureSharedSlotMismatches}',
          ..._evidenceAgainstCommonFalseCauses(summary)
              .where((evidence) => !evidence.startsWith('native encoder'))
              .toList(growable: false),
        ],
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }
    final gameCaptureSourcePresentLimited =
        native.gameCaptureDuplicateSkippedFrames > 0 &&
            !gameCaptureHasSourceFramesBeyondSubmitted &&
            native.gameCaptureRepeatedFrames == 0 &&
            native.gameCaptureSourceFrameDuplicates == 0 &&
            native.gameCaptureSourceFrameRegressions == 0 &&
            native.gameCaptureSharedSlotMismatches == 0 &&
            native.gameCaptureGpuScaleFailures == 0 &&
            native.gameCaptureCpuFallbackFrames == 0 &&
            native.averageGameCaptureFps != null &&
            targetFps > 0 &&
            native.averageGameCaptureFps! < targetFps * 0.75 &&
            captureEncodeSendTrack;
    if (gameCaptureSourcePresentLimited) {
      final sourceFps = native.averageGameCaptureFps!;
      final sourceLimitEvidence =
          'game hook saw ${sourceFps.toStringAsFixed(1)} unique source FPS '
          'while preset requested ${targetFps.toStringAsFixed(0)}';
      final duplicateSkipEvidence =
          'skipped ${native.gameCaptureDuplicateSkippedFrames} duplicate '
          'source ticks instead of resubmitting stale frames';
      return StreamTestBottleneck(
        label: 'source_present_limited',
        reasons: [
          sourceLimitEvidence,
          duplicateSkipEvidence,
          if (captureFps != null)
            'capture/encode/send FPS all track around '
                '${captureFps.toStringAsFixed(1)}fps',
        ],
        confidence: 'high',
        evidenceFor: [
          sourceLimitEvidence,
          duplicateSkipEvidence,
        ],
        evidenceAgainstFalseCauses: [
          if (native.averageEncoderTotalMs != null &&
              frameBudgetMs != null &&
              !native.isNativeEncoderOverBudgetFor(frameBudgetMs))
            'native encoder timing ${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms is below ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
          if (native.gameCaptureNativeNv12SubmittedFrames > 0)
            'native NV12 WebRTC source submission succeeded '
                '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
                '${native.gameCaptureNativeNv12Failures} failures and '
                '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
          'source regressions ${native.gameCaptureSourceFrameRegressions}, '
              'shared slot mismatches '
              '${native.gameCaptureSharedSlotMismatches}',
        ],
        missingFields: const [],
        recommendedNextAction: 'no stream change recommended',
      );
    }
    if (temporalAnalysis.hasLateDegradation) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: temporalAnalysis.lateDegradationSignals,
        confidence: 'high',
        evidenceFor: temporalAnalysis.lateDegradationSignals,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }
    if (nativeCaptureLimited && captureEncodeSendTrack) {
      return _nativeCaptureLimitedBottleneck(
        native: native,
        targetFps: targetFps,
        frameBudgetMs: frameBudgetMs,
        captureFps: captureFps,
      );
    }
    final gameCaptureOnFrameLimited = _gameCaptureOnFrameLimitedBottleneck(
      summary: summary,
      native: native,
      frameBudgetMs: frameBudgetMs,
    );
    if (gameCaptureOnFrameLimited != null) {
      return gameCaptureOnFrameLimited;
    }
    final gameCaptureDeliveryBackpressure =
        _gameCaptureDeliveryBackpressureBottleneck(
      summary: summary,
      native: native,
      frameBudgetMs: frameBudgetMs,
    );
    if (gameCaptureDeliveryBackpressure != null) {
      return gameCaptureDeliveryBackpressure;
    }

    final lowStageCadence = captureFps != null &&
        targetFps > 0 &&
        captureFps < targetFps * 0.75 &&
        _stageFpsTracks(encodeFps, captureFps) &&
        _stageFpsTracks(sendFps, encodeFps ?? captureFps);
    if (lowStageCadence) {
      if (averageEncodeTimeMs != null &&
          frameBudgetMs != null &&
          averageEncodeTimeMs > frameBudgetMs * 1.25) {
        return StreamTestBottleneck(
          label: 'encoder_pipeline_limited',
          reasons: [
            'encode time ${averageEncodeTimeMs.toStringAsFixed(0)}ms exceeds '
                '${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
            'capture/encode/send FPS all track around '
                '${captureFps.toStringAsFixed(1)}fps, consistent with encoder '
                'pipeline backpressure',
            if (summary.averagePacketSendDelayMs != null &&
                summary.averagePacketSendDelayMs! > 40)
              'send queue delay ${summary.averagePacketSendDelayMs!.toStringAsFixed(0)}ms',
            if (summary.preEncodeSampleCount == 0)
              'pre-encode dimensions were unavailable in sender stats',
          ],
          confidence: 'high',
          evidenceFor: [
            'encode time ${averageEncodeTimeMs.toStringAsFixed(0)}ms exceeds '
                '${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
            'capture/encode/send FPS track around '
                '${captureFps.toStringAsFixed(1)}fps',
          ],
          evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(
            summary,
          ),
          missingFields: summary.preEncodeSampleCount == 0
              ? const ['pre-encode dimensions']
              : const [],
          recommendedNextAction: 'fix encoder path',
        );
      }
      return StreamTestBottleneck(
        label: 'capture_or_preencode_limited',
        reasons: [
          'capture/pre-encode FPS ${captureFps.toStringAsFixed(1)} is below '
              'target ${targetFps.toStringAsFixed(0)} while encode/send FPS '
              'track the same cadence',
          if (summary.preEncodeSampleCount == 0)
            'pre-encode dimensions were unavailable in sender stats',
        ],
        confidence: summary.preEncodeSampleCount > 0 ? 'medium' : 'low',
        evidenceFor: [
          'capture/pre-encode FPS ${captureFps.toStringAsFixed(1)} is below '
              'target ${targetFps.toStringAsFixed(0)} and encode/send track it',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: summary.nativeDiagnostics.hasEvidence
            ? const []
            : const ['native capture markers'],
        recommendedNextAction: summary.nativeDiagnostics.hasEvidence
            ? 'fix capture backend'
            : 'collect one specific missing field',
      );
    }

    if (captureFps != null &&
        encodeFps != null &&
        captureFps > 0 &&
        encodeFps < captureFps * 0.8) {
      reasons.add(
        'encode FPS ${encodeFps.toStringAsFixed(1)} trails capture FPS '
        '${captureFps.toStringAsFixed(1)}',
      );
    }
    if (averageEncodeTimeMs != null &&
        frameBudgetMs != null &&
        averageEncodeTimeMs > frameBudgetMs * 1.25) {
      reasons.add(
        'encode time ${averageEncodeTimeMs.toStringAsFixed(0)}ms exceeds '
        '${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
      );
    }
    if (summary.framesDroppedByEncoderMax != null &&
        summary.framesDroppedByEncoderMax! > 0) {
      reasons.add(
        'encoder dropped ${summary.framesDroppedByEncoderMax} frames',
      );
    }
    if (summary.qualityLimitationReasons.any(
      (reason) => reason.toLowerCase() == 'cpu',
    )) {
      reasons.add('WebRTC quality limitation is cpu');
    }
    if (reasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'encode_limited',
        reasons: [
          ...reasons,
          if (summary.averagePacketSendDelayMs != null &&
              summary.averagePacketSendDelayMs! > 40)
            'send queue delay ${summary.averagePacketSendDelayMs!.toStringAsFixed(0)}ms follows encoder/backpressure',
        ],
        confidence: averageEncodeTimeMs != null ||
                summary.framesDroppedByEncoderMax != null
            ? 'high'
            : 'medium',
        evidenceFor: reasons,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: averageEncodeTimeMs == null
            ? const ['average encode time']
            : const [],
        recommendedNextAction: 'fix encoder path',
      );
    }

    if (encodeFps != null &&
        sendFps != null &&
        encodeFps > 0 &&
        sendFps < encodeFps * 0.8) {
      reasons.add(
        'send FPS ${sendFps.toStringAsFixed(1)} trails encode FPS '
        '${encodeFps.toStringAsFixed(1)}',
      );
    }
    final sendDelay = summary.averagePacketSendDelayMs;
    if (sendDelay != null && sendDelay > 40) {
      reasons.add('send queue delay ${sendDelay.toStringAsFixed(0)}ms');
    }
    if (reasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'send_limited',
        reasons: reasons,
        confidence: 'medium',
        evidenceFor: reasons,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: summary.averagePacketSendDelayMs == null
            ? const ['packet send delay']
            : const [],
        recommendedNextAction: 'inspect server/network',
      );
    }

    if (captureFps != null &&
        targetFps > 0 &&
        captureFps < targetFps * 0.75 &&
        (encodeFps == null || encodeFps >= captureFps * 0.8) &&
        (sendFps == null || sendFps >= (encodeFps ?? captureFps) * 0.8)) {
      return StreamTestBottleneck(
        label: 'capture_limited',
        reasons: [
          'capture FPS ${captureFps.toStringAsFixed(1)} is below target '
              '${targetFps.toStringAsFixed(0)}',
        ],
        confidence: summary.nativeDiagnostics.hasEvidence ? 'medium' : 'low',
        evidenceFor: [
          'capture FPS ${captureFps.toStringAsFixed(1)} is below target '
              '${targetFps.toStringAsFixed(0)}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: summary.nativeDiagnostics.hasEvidence
            ? const []
            : const ['native capture markers'],
        recommendedNextAction: summary.nativeDiagnostics.hasEvidence
            ? 'fix capture backend'
            : 'collect one specific missing field',
      );
    }

    if (summary.activeLayers.any(_isDowngradedLayer)) {
      return StreamTestBottleneck(
        label: 'downgraded_layer',
        reasons: ['active layers: ${summary.activeLayersLabel}'],
        confidence: 'medium',
        evidenceFor: ['active layers: ${summary.activeLayersLabel}'],
        missingFields: const ['receiver subscribed layer reason'],
        recommendedNextAction: 'fix receiver subscription/rendering',
      );
    }

    final sourceOrderReasons = <String>[];
    if (native.gameCaptureSourceFrameRegressions > 0) {
      sourceOrderReasons.add(
        'source frame index regressed '
        '${native.gameCaptureSourceFrameRegressions} times',
      );
    }
    if (native.gameCaptureSharedSlotMismatches > 0) {
      sourceOrderReasons.add(
        'shared slot frame index mismatched latest frame '
        '${native.gameCaptureSharedSlotMismatches} times',
      );
    }
    if (sourceOrderReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'source_frame_order_unstable',
        reasons: sourceOrderReasons,
        confidence: 'high',
        evidenceFor: [
          ...sourceOrderReasons,
          'source frame ${native.gameCaptureSourceFrameIndex}, '
              'last submitted source frame '
              '${native.gameCaptureLastSubmittedSourceFrameIndex}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix game-capture handoff',
      );
    }

    final timestampReasons = <String>[];
    final maxTimestampDelta = native.maxGameCaptureTimestampDeltaMs;
    final timestampMode = native.gameCaptureTimestampMode;
    final timestampPolicyDeliveryWallMax =
        native.maxGameCaptureDeliveryWallDeltaMs;
    final timestampPolicySourceQpcMax = native.maxGameCaptureSourceQpcDeltaMs;
    final timestampDeltaLooksPaced = maxTimestampDelta != null &&
        frameBudgetMs != null &&
        maxTimestampDelta <= frameBudgetMs * 1.25;
    final wallOrSourceGapDiverged = frameBudgetMs != null &&
        ((timestampPolicyDeliveryWallMax != null &&
                timestampPolicyDeliveryWallMax > frameBudgetMs * 2.0) ||
            native.gameCaptureDeliveryWallOver2xFrames > 0 ||
            (timestampPolicySourceQpcMax != null &&
                timestampPolicySourceQpcMax > frameBudgetMs * 2.0));
    if (timestampMode == 'paced' &&
        native.gameCaptureRepeatedFrames == 0 &&
        timestampDeltaLooksPaced &&
        wallOrSourceGapDiverged) {
      final reasons = <String>[
        'paced timestamps stayed near '
            '${maxTimestampDelta.toStringAsFixed(1)}ms while delivery/source '
            'cadence exceeded a ${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
        if (timestampPolicyDeliveryWallMax != null)
          'delivery wall-clock gap peaked at '
              '${timestampPolicyDeliveryWallMax.toStringAsFixed(1)}ms',
        if (timestampPolicySourceQpcMax != null)
          'source QPC gap peaked at '
              '${timestampPolicySourceQpcMax.toStringAsFixed(1)}ms',
      ];
      return StreamTestBottleneck(
        label: 'timestamp_policy_mismatch',
        reasons: reasons,
        confidence: native.gameCaptureDeliveryWallSamples > 0 ||
                native.gameCaptureSourceQpcSamples > 0
            ? 'high'
            : 'medium',
        evidenceFor: [
          ...reasons,
          'timestamp source-QPC frames '
              '${native.gameCaptureTimestampSourceQpcFrames}, paced fallback '
              '${native.gameCaptureTimestampPacedFallbackFrames}, repeated '
              '${native.gameCaptureTimestampRepeatedFrames}',
          'delivery wall gap distribution >2x='
              '${native.gameCaptureDeliveryWallOver2xFrames}, >3x='
              '${native.gameCaptureDeliveryWallOver3xFrames}, <0.5x='
              '${native.gameCaptureDeliveryWallUnderHalfFrames}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix frame pacing',
      );
    }
    if (maxTimestampDelta != null &&
        frameBudgetMs != null &&
        timestampMode != 'paced' &&
        maxTimestampDelta > frameBudgetMs * 1.25) {
      timestampReasons.add(
        'game-capture delivery timestamp delta peaked at '
        '${maxTimestampDelta.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
    }
    if (native.gameCaptureTimestampAdjustments > 0) {
      timestampReasons.add(
        'game-capture adjusted '
        '${native.gameCaptureTimestampAdjustments} non-monotonic timestamps',
      );
    }
    if (timestampReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: timestampReasons,
        confidence: 'high',
        evidenceFor: [
          ...timestampReasons,
          'timestamp mode ${timestampMode ?? 'unknown'}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix frame pacing',
      );
    }

    final deliveryWallReasons = <String>[];
    final deliveryWallEvidence = <String>[];
    final deliveryWallMissingFields = <String>[];
    final maxDeliveryWallDelta = native.maxGameCaptureDeliveryWallDeltaMs;
    if (maxDeliveryWallDelta != null &&
        frameBudgetMs != null &&
        maxDeliveryWallDelta > frameBudgetMs * 2.0) {
      deliveryWallReasons.add(
        'game-capture actual OnFrame wall-clock gap peaked at '
        '${maxDeliveryWallDelta.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
      final queueWaitMax = native.maxGameCaptureDeliveryQueueWaitMs;
      final readyToSubmitMax = native.maxGameCaptureReadyToSubmitMs;
      final sourceToSubmitMax = native.maxGameCaptureSourceToSubmitMs;
      if (queueWaitMax != null &&
          native.gameCaptureDeliveryQueueWaitSamples > 0) {
        deliveryWallEvidence.add(
          'delivery queue wait max '
          '${queueWaitMax.toStringAsFixed(1)}ms',
        );
        if (queueWaitMax > frameBudgetMs * 2.0) {
          deliveryWallReasons.add(
            'delivery thread queue wait alone exceeded budget at '
            '${queueWaitMax.toStringAsFixed(1)}ms',
          );
        }
      } else {
        deliveryWallMissingFields.add('game-capture delivery queue wait');
      }
      if (readyToSubmitMax != null &&
          native.gameCaptureReadyToSubmitSamples > 0) {
        deliveryWallEvidence.add(
          'ready-to-submit max ${readyToSubmitMax.toStringAsFixed(1)}ms',
        );
      } else {
        deliveryWallMissingFields.add('game-capture ready-to-submit timing');
      }
      if (sourceToSubmitMax != null &&
          native.gameCaptureSourceToSubmitSamples > 0) {
        deliveryWallEvidence.add(
          'source-to-submit max ${sourceToSubmitMax.toStringAsFixed(1)}ms',
        );
        if (sourceToSubmitMax > frameBudgetMs * 3.0) {
          deliveryWallReasons.add(
            'source-to-submit latency exceeded three frame budgets at '
            '${sourceToSubmitMax.toStringAsFixed(1)}ms',
          );
        }
      } else {
        deliveryWallMissingFields.add('game-capture source-to-submit timing');
      }
      if (native.gameCaptureDeliveryWallOver2xFrames > 0 ||
          native.gameCaptureDeliveryWallOver3xFrames > 0 ||
          native.gameCaptureDeliveryWallUnderHalfFrames > 0) {
        deliveryWallEvidence.add(
          'wall-gap distribution >2x=${native.gameCaptureDeliveryWallOver2xFrames}, '
          '>3x=${native.gameCaptureDeliveryWallOver3xFrames}, '
          '<0.5x=${native.gameCaptureDeliveryWallUnderHalfFrames}',
        );
      } else {
        deliveryWallMissingFields.add('game-capture wall-gap distribution');
      }
    }
    if (deliveryWallReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: deliveryWallReasons,
        confidence: deliveryWallMissingFields.isEmpty ? 'high' : 'medium',
        missingFields: deliveryWallMissingFields,
        evidenceFor: [
          ...deliveryWallReasons,
          ...deliveryWallEvidence,
          'timestamp mode ${timestampMode ?? 'unknown'}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix frame pacing',
      );
    }

    final sourceToSubmitReasons = <String>[];
    final sourceToSubmitEvidence = <String>[];
    final sourceToSubmitAverage = native.averageGameCaptureSourceToSubmitMs;
    final sourceToSubmitMax = native.maxGameCaptureSourceToSubmitMs;
    final queueWaitAverage = native.averageGameCaptureDeliveryQueueWaitMs;
    final queueWaitMax = native.maxGameCaptureDeliveryQueueWaitMs;
    final sourceToSubmitSamples = native.gameCaptureSourceToSubmitSamples;
    if (frameBudgetMs != null &&
        native.gameCaptureSubmittedFrames > 0 &&
        native.gameCaptureGpuScaledFrames > 0 &&
        native.gameCaptureCpuFallbackFrames == 0 &&
        sourceToSubmitSamples > 0 &&
        sourceToSubmitAverage != null &&
        sourceToSubmitMax != null &&
        sourceToSubmitAverage > frameBudgetMs * 2.0 &&
        sourceToSubmitMax > frameBudgetMs * 4.0) {
      sourceToSubmitReasons.add(
        'game-capture source-to-submit latency averaged '
        '${sourceToSubmitAverage.toStringAsFixed(1)}ms and peaked at '
        '${sourceToSubmitMax.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
      if (queueWaitAverage != null &&
          queueWaitMax != null &&
          native.gameCaptureDeliveryQueueWaitSamples > 0) {
        sourceToSubmitEvidence.add(
          'delivery queue wait averaged '
          '${queueWaitAverage.toStringAsFixed(1)}ms and peaked at '
          '${queueWaitMax.toStringAsFixed(1)}ms',
        );
      }
      if (native.gameCaptureSourceToReadbackReadySamples > 0 &&
          native.averageGameCaptureSourceToReadbackReadyMs != null &&
          native.maxGameCaptureSourceToReadbackReadyMs != null) {
        sourceToSubmitEvidence.add(
          'source-to-readback-ready averaged '
          '${native.averageGameCaptureSourceToReadbackReadyMs!.toStringAsFixed(1)}ms '
          'and peaked at '
          '${native.maxGameCaptureSourceToReadbackReadyMs!.toStringAsFixed(1)}ms',
        );
      }
      if (native.gameCaptureReadbackQueueToMapSamples > 0 &&
          native.averageGameCaptureReadbackQueueToMapMs != null &&
          native.maxGameCaptureReadbackQueueToMapMs != null) {
        sourceToSubmitEvidence.add(
          'readback queue-to-map averaged '
          '${native.averageGameCaptureReadbackQueueToMapMs!.toStringAsFixed(1)}ms '
          'and peaked at '
          '${native.maxGameCaptureReadbackQueueToMapMs!.toStringAsFixed(1)}ms',
        );
      }
      if (native.gameCaptureMapToI420Samples > 0 &&
          native.averageGameCaptureMapToI420Ms != null &&
          native.maxGameCaptureMapToI420Ms != null) {
        sourceToSubmitEvidence.add(
          'map-to-I420 averaged '
          '${native.averageGameCaptureMapToI420Ms!.toStringAsFixed(1)}ms '
          'and peaked at '
          '${native.maxGameCaptureMapToI420Ms!.toStringAsFixed(1)}ms',
        );
      }
      if (native.gameCaptureSourceToQueueSamples > 0 &&
          native.averageGameCaptureSourceToQueueMs != null &&
          native.maxGameCaptureSourceToQueueMs != null) {
        sourceToSubmitEvidence.add(
          'source-to-delivery-queue averaged '
          '${native.averageGameCaptureSourceToQueueMs!.toStringAsFixed(1)}ms '
          'and peaked at '
          '${native.maxGameCaptureSourceToQueueMs!.toStringAsFixed(1)}ms',
        );
      }
      if (native.averageGameCaptureReadbackLatencyFrames != null) {
        sourceToSubmitEvidence.add(
          'readback latency averaged '
          '${native.averageGameCaptureReadbackLatencyFrames!.toStringAsFixed(1)} '
          'queued frames',
        );
      }
      if (native.gameCaptureReadbackNotReadyFrames > 0) {
        sourceToSubmitEvidence.add(
          '${native.gameCaptureReadbackNotReadyFrames} readback map attempts '
          'were not ready',
        );
      }
    }
    if (sourceToSubmitReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: [
          ...sourceToSubmitReasons,
          'encoded/sent FPS can stay near target while displayed frames are '
              'several frame budgets behind the game source',
        ],
        confidence: 'high',
        evidenceFor: [
          ...sourceToSubmitReasons,
          ...sourceToSubmitEvidence,
        ],
        evidenceAgainstFalseCauses: [
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
          if (native.gameCaptureNativeNv12SubmittedFrames > 0)
            'native NV12 WebRTC source submission succeeded '
                '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
                '${native.gameCaptureNativeNv12Failures} failures and '
                '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
          ..._evidenceAgainstCommonFalseCauses(summary),
        ],
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }

    final readbackLatencyReasons = <String>[];
    final readbackDropCorroboration = <String>[];
    final averageReadbackLatencyFrames =
        native.averageGameCaptureReadbackLatencyFrames;
    if (averageReadbackLatencyFrames != null &&
        averageReadbackLatencyFrames > 3.0) {
      readbackLatencyReasons.add(
        'game-capture readback averages '
        '${averageReadbackLatencyFrames.toStringAsFixed(1)} queued frames',
      );
    }
    if (native.gameCaptureMaxReadbackLatencyFrames > 4 &&
        averageReadbackLatencyFrames != null &&
        averageReadbackLatencyFrames > 2.0) {
      readbackLatencyReasons.add(
        'game-capture readback peaked at '
        '${native.gameCaptureMaxReadbackLatencyFrames} queued frames',
      );
    }
    if (native.gameCaptureReadbackLatencyDroppedFrames > 0) {
      if (averageReadbackLatencyFrames != null &&
          averageReadbackLatencyFrames > 2.0) {
        readbackDropCorroboration.add(
          'average game-capture readback latency '
          '${averageReadbackLatencyFrames.toStringAsFixed(1)} frames '
          'exceeds the healthy one-to-two frame range',
        );
      }
      if (native.gameCaptureMaxReadbackLatencyFrames > 2) {
        readbackDropCorroboration.add(
          'game-capture readback latency peaked at '
          '${native.gameCaptureMaxReadbackLatencyFrames} frames',
        );
      }
      final queuedReadbacks = native.gameCaptureReadbackQueuedFrames;
      if (queuedReadbacks > 0) {
        final dropRatio =
            native.gameCaptureReadbackLatencyDroppedFrames / queuedReadbacks;
        if (dropRatio >= 0.03) {
          readbackDropCorroboration.add(
            'stale-readback drop ratio '
            '${(dropRatio * 100).toStringAsFixed(1)}%',
          );
        }
      }
      readbackDropCorroboration.addAll(
        _framePacingReasons(
          summary: summary,
          frameBudgetMs: frameBudgetMs,
        ),
      );
    }
    if (readbackDropCorroboration.isNotEmpty) {
      readbackLatencyReasons.add(
        'game-capture dropped '
        '${native.gameCaptureReadbackLatencyDroppedFrames} stale readbacks '
        'to bound motion latency',
      );
      readbackLatencyReasons.addAll(readbackDropCorroboration);
    }
    if (readbackLatencyReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: readbackLatencyReasons,
        confidence: 'high',
        evidenceFor: [
          ...readbackLatencyReasons,
          'source regressions '
              '${native.gameCaptureSourceFrameRegressions}, '
              'shared slot mismatches '
              '${native.gameCaptureSharedSlotMismatches}',
        ],
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        missingFields: const [],
        recommendedNextAction: 'fix frame pacing',
      );
    }

    final pacingReasons = _framePacingReasons(
      summary: summary,
      frameBudgetMs: frameBudgetMs,
    );
    if (pacingReasons.isNotEmpty) {
      return StreamTestBottleneck(
        label: 'frame_pacing_unstable',
        reasons: pacingReasons,
        confidence: 'high',
        evidenceFor: pacingReasons,
        evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
        recommendedNextAction: 'fix frame pacing',
      );
    }

    if (fpsRatio >= 0.85) {
      return const StreamTestBottleneck(
        label: 'healthy',
        reasons: [
          'send FPS is near target and no network or encoder limiter was detected'
        ],
        confidence: 'high',
        evidenceFor: [
          'send FPS is near target and no network or encoder limiter was detected'
        ],
        recommendedNextAction: 'no stream change recommended',
      );
    }

    return StreamTestBottleneck(
      label: 'insufficient_evidence',
      reasons: [
        'insufficient corroborating stats; capture=${_number(captureFps)}, '
            'encode=${_number(encodeFps)}, send=${_number(sendFps)}',
      ],
      confidence: 'insufficient',
      missingFields: _classificationMissingFields(summary),
      evidenceFor: [
        'observed FPS ratio ${fpsRatio.toStringAsFixed(2)} lacks a supported '
            'network, encoder, capture, pacing, or receiver cause',
      ],
      evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary),
      recommendedNextAction: 'collect one specific missing field',
    );
  }

  static StreamTestBottleneck _nativeCaptureLimitedBottleneck({
    required StreamTestNativeDiagnostics native,
    required double targetFps,
    required double? frameBudgetMs,
    required double? captureFps,
  }) {
    final reasons = [
      if (native.averageCaptureCallMs != null && frameBudgetMs != null)
        'native capture calls average '
            '${native.averageCaptureCallMs!.toStringAsFixed(0)}ms '
            'against ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
      if (native.averageSourceCaptureMs != null &&
          frameBudgetMs != null &&
          native.averageSourceCaptureMs! > frameBudgetMs)
        'source capture averages '
            '${native.averageSourceCaptureMs!.toStringAsFixed(0)}ms, '
            'so acquisition is consuming the frame budget before local '
            'convert/scale work',
      if (native.wgcFrameSummaryLabel != 'unknown')
        'WGC substage ${native.wgcFrameSummaryLabel}',
      if (native.gdiFrameSummaryLabel != 'unknown')
        'window-GDI substage ${native.gdiFrameSummaryLabel}',
      if (native.p95FrameIntervalMs != null && frameBudgetMs != null)
        'native p95 frame interval '
            '${native.p95FrameIntervalMs!.toStringAsFixed(0)}ms '
            'against ${frameBudgetMs.toStringAsFixed(0)}ms cadence',
      if (native.maxFrameIntervalMs != null && frameBudgetMs != null)
        'native max frame gap '
            '${native.maxFrameIntervalMs!.toStringAsFixed(0)}ms',
      if (native.averageNativeFps != null)
        'native emitted FPS ${native.averageNativeFps!.toStringAsFixed(1)} '
            'is below target ${targetFps.toStringAsFixed(0)}',
      if (native.averageEncoderTotalMs != null)
        'native MediaFoundation encoder averages '
            '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms',
      if (native.updatedRegionEmptyCount > 0 ||
          native.updatedRegionNonEmptyCount > 0)
        'updated regions: ${native.updatedRegionNonEmptyCount} dirty / '
            '${native.updatedRegionEmptyCount} empty; '
            '${native.updatedRegionShapeLabel}',
      if (captureFps != null)
        'capture/encode/send FPS all track around '
            '${captureFps.toStringAsFixed(1)}fps',
      if (native.preEncodeResolutionLabel != 'unknown')
        'native pre-encode ${native.preEncodeResolutionLabel}',
      if (native.backendLabel != 'unknown') 'backend ${native.backendLabel}',
    ];
    final recommendedAction = native.wgcFrameSummaryLabel != 'unknown'
        ? 'fix WGC substage'
        : native.gdiFrameSummaryLabel != 'unknown'
            ? 'fix window-GDI substage'
            : native.updatedRegionShapeLabel != 'unknown' &&
                    native.updatedRegionTinyFrameCount >
                        native.updatedRegionFullFrameCount
                ? 'fix dirty-region behavior'
                : 'fix capture backend';
    return StreamTestBottleneck(
      label: 'native_capture_limited',
      reasons: reasons,
      confidence: 'high',
      evidenceFor: reasons,
      evidenceAgainstFalseCauses: [
        if (native.averageEncoderTotalMs != null &&
            frameBudgetMs != null &&
            !native.isNativeEncoderOverBudgetFor(frameBudgetMs))
          'native encoder timing ${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms is below ${frameBudgetMs.toStringAsFixed(0)}ms frame budget',
      ],
      missingFields: [
        if (native.wgcFrameSummaryLabel == 'unknown' &&
            native.observedCapturerLabel.toLowerCase().contains('wgc'))
          'WGC substage markers',
        if (native.gdiFrameSummaryLabel == 'unknown' &&
            native.observedCapturerLabel.toLowerCase().contains('window-gdi'))
          'window-GDI substage markers',
      ],
      recommendedNextAction: recommendedAction,
    );
  }

  static StreamTestBottleneck?
      _gameCaptureNativeEncoderFenceTimingMissingBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (!native.nativeEncoderFenceWaitMissing) {
      return null;
    }

    final candidates = <String>[];
    final frameBudget = frameBudgetMs ?? 33.3;
    if (native.averageGameCaptureDeliveryOnFrameCallMs != null ||
        native.maxGameCaptureDeliveryOnFrameCallMs != null) {
      candidates.add(
        'candidate webrtc_onframe_limited: OnFrame call '
        '${_milliseconds(native.averageGameCaptureDeliveryOnFrameCallMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryOnFrameCallMs)}',
      );
    }
    if (native.averageGameCaptureDeliveryQueueWaitMs != null ||
        native.averageGameCaptureSourceToSubmitMs != null ||
        native.gameCaptureDeliveryPacerResyncs > 0) {
      candidates.add(
        'candidate delivery_queue_limited: delivery queue wait '
        '${_milliseconds(native.averageGameCaptureDeliveryQueueWaitMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryQueueWaitMs)}, '
        'source-to-submit '
        '${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)}, '
        'pacer resyncs ${native.gameCaptureDeliveryPacerResyncs}',
      );
    }
    if (native.gameCaptureNativeNv12BgraScaleDrawSamples > 0 ||
        native.gameCaptureNativeNv12VideoProcessorBltToReadySamples > 0) {
      candidates.add(
        'candidate native_nv12_ready_limited: BGRA scale '
        '${_milliseconds(native.averageGameCaptureNativeNv12BgraScaleDrawMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12BgraScaleDrawMs)}, '
        'Blt-to-ready '
        '${_milliseconds(native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs)}',
      );
    }
    if (native.averageEncoderTotalMs != null) {
      candidates.add(
        'candidate media_foundation_encoder_limited: aggregate encoder '
        '${_milliseconds(native.averageEncoderTotalMs)}/'
        '${_milliseconds(native.maxEncoderTotalMs)} with '
        '${native.encoderSlowFrameCount}/${native.encoderSampleCount} slow '
        'samples, but no native fence-wait substage timing',
      );
    }

    return StreamTestBottleneck(
      label: 'insufficient_evidence',
      reasons: [
        'D3D11 native NV12 input reached Media Foundation, but parsed '
            'native_ready_fence_wait_ms timing is missing',
        'cannot separate encoder fence wait, WebRTC OnFrame, and delivery '
            'queue pressure for a ${frameBudget.toStringAsFixed(1)}ms frame budget',
      ],
      confidence: 'insufficient',
      evidenceFor: [
        'native NV12 submitted '
            '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
            '${native.gameCaptureNativeNv12Failures} failures and '
            '${native.gameCaptureCpuFallbackFrames} CPU fallback frames',
        'encoder input path ${native.encoderInputPathLabel}; native '
            '${native.encoderNativeInputFrames}, cpu_i420 '
            '${native.encoderCpuI420InputFrames}',
        ...candidates,
      ],
      evidenceAgainstFalseCauses: _evidenceAgainstCommonFalseCauses(summary)
          .where((evidence) =>
              !evidence.startsWith('native MediaFoundation encoder timing'))
          .toList(growable: false),
      missingFields: const [
        'native_ready_fence',
        'native_ready_fence_timeout',
        'native_ready_fence_wait_ms',
        'process_input_ms',
        'process_output_ms',
      ],
      recommendedNextAction: 'collect one specific missing field',
    );
  }

  static StreamTestBottleneck? _gameCaptureNativeNv12ReadyBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        native.gameCaptureNativeNv12SubmittedFrames <= 0 ||
        native.gameCaptureNativeNv12Failures > 0 ||
        native.gameCaptureCpuFallbackFrames > 0) {
      return null;
    }

    final reasons = <String>[];
    final evidence = <String>[];
    final readyDrops = native.gameCaptureNativeNv12ReadyDroppedFrames;
    final readyDroppedFresh =
        native.gameCaptureNativeNv12ReadyDroppedFreshFrames;
    if (readyDrops >
            max(10, native.gameCaptureNativeNv12SubmittedFrames ~/ 50) ||
        readyDroppedFresh > 0) {
      reasons.add(
        'native NV12 ready queue dropped $readyDrops frames'
        '${readyDroppedFresh > 0 ? ' ($readyDroppedFresh fresh)' : ''}',
      );
    }

    final convertAverage = native.averageGameCaptureNativeNv12ConvertMs;
    final convertMax = native.maxGameCaptureNativeNv12ConvertMs;
    if (native.gameCaptureNativeNv12ConvertSamples > 0 &&
        convertAverage != null &&
        convertMax != null &&
        (convertAverage > frameBudgetMs * 0.75 ||
            convertMax > frameBudgetMs * 2.0)) {
      reasons.add(
        'native NV12 readiness averaged '
        '${convertAverage.toStringAsFixed(1)}ms and peaked at '
        '${convertMax.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
    }

    final bltToReadyMax =
        native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs;
    if (native.gameCaptureNativeNv12VideoProcessorBltToReadySamples > 0 &&
        bltToReadyMax != null &&
        bltToReadyMax > frameBudgetMs * 2.0) {
      reasons.add(
        'native NV12 VideoProcessorBlt-to-ready peaked at '
        '${bltToReadyMax.toStringAsFixed(1)}ms',
      );
    }
    final conversionStartAgeAvg =
        native.averageGameCaptureNativeNv12ConversionStartAgeMs;
    final conversionStartAgeMax =
        native.maxGameCaptureNativeNv12ConversionStartAgeMs;
    if (native.gameCaptureNativeNv12ConversionStartAgeSamples > 0 &&
        conversionStartAgeAvg != null &&
        conversionStartAgeMax != null &&
        (conversionStartAgeAvg > frameBudgetMs ||
            conversionStartAgeMax > frameBudgetMs * 2.0)) {
      reasons.add(
        'native NV12 conversion admission saw source age average '
        '${conversionStartAgeAvg.toStringAsFixed(1)}ms and peak '
        '${conversionStartAgeMax.toStringAsFixed(1)}ms',
      );
    }

    if (reasons.isEmpty) {
      return null;
    }

    if (native.gameCaptureNativeNv12NotReadyPolls > 0) {
      evidence.add(
        'native NV12 readiness polled not-ready '
        '${native.gameCaptureNativeNv12NotReadyPolls} times',
      );
    }
    if (native.gameCaptureDeliveryPacerResyncs > 0) {
      evidence.add(
        'delivery pacer resynced '
        '${native.gameCaptureDeliveryPacerResyncs} times '
        '(max lag ${native.gameCaptureDeliveryPacerLagMaxMs}ms)',
      );
    }
    if (readyDroppedFresh > 0) {
      evidence.add(
        'native NV12 ready drain dropped $readyDroppedFresh fresh frames',
      );
    }
    if (native.gameCaptureNativeNv12ReadyDropAgeSamples > 0 &&
        native.maxGameCaptureNativeNv12ReadyDropAgeMs != null) {
      evidence.add(
        'native NV12 ready-drop max source age '
        '${native.maxGameCaptureNativeNv12ReadyDropAgeMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12BgraScaleDrawSamples > 0 &&
        native.averageGameCaptureNativeNv12BgraScaleDrawMs != null &&
        native.maxGameCaptureNativeNv12BgraScaleDrawMs != null) {
      evidence.add(
        'BGRA scale draw averaged '
        '${native.averageGameCaptureNativeNv12BgraScaleDrawMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12BgraScaleDrawMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12VideoProcessorBltSubmitSamples > 0 &&
        native.averageGameCaptureNativeNv12VideoProcessorBltSubmitMs != null &&
        native.maxGameCaptureNativeNv12VideoProcessorBltSubmitMs != null) {
      evidence.add(
        'VideoProcessorBlt submit averaged '
        '${native.averageGameCaptureNativeNv12VideoProcessorBltSubmitMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12VideoProcessorBltSubmitMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12VideoProcessorBltToReadySamples > 0 &&
        native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs != null &&
        native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs != null) {
      evidence.add(
        'VideoProcessorBlt-to-ready averaged '
        '${native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12BufferCreateSamples > 0 &&
        native.averageGameCaptureNativeNv12BufferCreateMs != null) {
      evidence.add(
        'native NV12 buffer creation averaged '
        '${native.averageGameCaptureNativeNv12BufferCreateMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12FrameReadyToQueueSamples > 0 &&
        native.averageGameCaptureNativeNv12FrameReadyToQueueMs != null) {
      evidence.add(
        'native frame ready-to-queue averaged '
        '${native.averageGameCaptureNativeNv12FrameReadyToQueueMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12ConversionStartAgeSamples > 0 &&
        native.averageGameCaptureNativeNv12ConversionStartAgeMs != null &&
        native.maxGameCaptureNativeNv12ConversionStartAgeMs != null) {
      evidence.add(
        'native conversion admission source age averaged '
        '${native.averageGameCaptureNativeNv12ConversionStartAgeMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12ConversionStartAgeMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12StaleBeforeQueueFrames > 0) {
      evidence.add(
        'native NV12 skipped '
        '${native.gameCaptureNativeNv12StaleBeforeQueueFrames} stale frames '
        'before queueing',
      );
    }
    if (native.averageEncoderTotalMs != null) {
      evidence.add(
        'native MediaFoundation encoder timing averaged '
        '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms '
        'with ${native.encoderSlowFrameCount}/'
        '${native.encoderSampleCount} slow samples',
      );
    }

    return StreamTestBottleneck(
      label: 'native_nv12_ready_limited',
      reasons: reasons,
      confidence: evidence.length >= 2 ? 'high' : 'medium',
      evidenceFor: [
        ...reasons,
        ...evidence,
      ],
      evidenceAgainstFalseCauses: [
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames with '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        'native NV12 WebRTC source submitted '
            '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
            '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) =>
                !evidence.startsWith('native MediaFoundation encoder timing'))
            .toList(growable: false),
      ],
      missingFields:
          native.gameCaptureNativeNv12VideoProcessorBltToReadySamples == 0
              ? const ['native NV12 split timing substages']
              : const [],
      recommendedNextAction: 'fix game-capture handoff',
    );
  }

  static StreamTestBottleneck?
      _gameCaptureLiveSenderHandoffBackpressureBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
    required double targetFps,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        targetFps <= 0 ||
        native.gameCaptureNativeNv12SubmittedFrames <= 0 ||
        native.gameCaptureNativeNv12Failures > 0 ||
        native.gameCaptureCpuFallbackFrames > 0 ||
        native.gameCaptureDeliveryOnFrameCallSamples <= 0 ||
        native.encoderNativeInputFrames <= 0 ||
        native.encoderNativeReadyFenceWaitSamples <= 0) {
      return null;
    }

    final callAverage = native.averageGameCaptureDeliveryOnFrameCallMs;
    final callMax = native.maxGameCaptureDeliveryOnFrameCallMs;
    if (callAverage == null || callMax == null) {
      return null;
    }
    final onFrameOverBudget =
        callAverage > frameBudgetMs * 0.75 || callMax > frameBudgetMs * 2.0;
    if (!onFrameOverBudget) {
      return null;
    }

    final fenceHealthy = native.gameCaptureNativeNv12FenceAvailable != false &&
        native.gameCaptureNativeNv12FenceSignaledFrames > 0 &&
        native.gameCaptureNativeNv12FenceSignalFailures == 0 &&
        native.encoderNativeReadyFenceTimeoutFrames == 0;
    final readyQueueHealthy = native.gameCaptureNativeNv12NotReadyPolls == 0 &&
        native.gameCaptureNativeNv12ReadyDroppedFrames == 0 &&
        native.gameCaptureNativeNv12ReadyDroppedFreshFrames == 0 &&
        native.encoderNativeSampleFailures == 0;
    final convertAverage = native.averageGameCaptureNativeNv12ConvertMs;
    final bltReadyAverage =
        native.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs;
    final conversionAgeAverage =
        native.averageGameCaptureNativeNv12ConversionStartAgeMs;
    final nativeReadyTimingHealthy = (convertAverage == null ||
            convertAverage <= frameBudgetMs * 0.75) &&
        (bltReadyAverage == null || bltReadyAverage <= frameBudgetMs * 0.5) &&
        (conversionAgeAverage == null || conversionAgeAverage <= frameBudgetMs);
    if (!fenceHealthy || !readyQueueHealthy || !nativeReadyTimingHealthy) {
      return null;
    }

    final fpsValues = <double>[
      if (summary.averageCaptureFps != null) summary.averageCaptureFps!,
      if (summary.averageEncodeFps != null) summary.averageEncodeFps!,
      if (summary.averageSendFps != null) summary.averageSendFps!,
    ];
    final liveCadenceSlow = fpsValues.any(
      (fps) => fps > 0 && fps < targetFps * 0.75,
    );
    final nativeEncoderSlow =
        native.isNativeEncoderOverBudgetFor(frameBudgetMs);
    final senderEncodeSlow = summary.averageEncodeTimeMs != null &&
        summary.averageEncodeTimeMs! > frameBudgetMs;
    if (!liveCadenceSlow && !nativeEncoderSlow && !senderEncodeSlow) {
      return null;
    }

    final reasons = <String>[
      'live_sender_handoff_backpressure: live WebRTC OnFrame call averaged '
          '${callAverage.toStringAsFixed(1)}ms and peaked at '
          '${callMax.toStringAsFixed(1)}ms for a '
          '${frameBudgetMs.toStringAsFixed(1)}ms frame budget while native '
          'NV12 fences and failures were healthy',
      if (liveCadenceSlow)
        'capture/encode/send cadence stayed below the '
            '${targetFps.toStringAsFixed(0)}fps target '
            '(capture ${_number(summary.averageCaptureFps)}fps, encode '
            '${_number(summary.averageEncodeFps)}fps, send '
            '${_number(summary.averageSendFps)}fps)',
      if (nativeEncoderSlow && native.averageEncoderTotalMs != null)
        'native MediaFoundation timing averaged '
            '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms with '
            '${native.encoderSlowFrameCount}/${native.encoderSampleCount} '
            'slow samples',
    ];
    final evidence = <String>[
      ...reasons,
      'native NV12 fence/ready path: policy '
          '${native.gameCaptureNativeNv12ReadyPolicy ?? 'unknown'}, '
          'fenceAvailable=${native.gameCaptureNativeNv12FenceAvailable}, '
          'fenceSignaled=${native.gameCaptureNativeNv12FenceSignaledFrames}, '
          'notReadyPolls=${native.gameCaptureNativeNv12NotReadyPolls}, '
          'readyDropped=${native.gameCaptureNativeNv12ReadyDroppedFrames}, '
          'failures=${native.gameCaptureNativeNv12Failures}, '
          'cpuFallback=${native.gameCaptureCpuFallbackFrames}',
      'delivery queue wait '
          '${_milliseconds(native.averageGameCaptureDeliveryQueueWaitMs)}/'
          '${_milliseconds(native.maxGameCaptureDeliveryQueueWaitMs)} and '
          'source-to-submit '
          '${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
          '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)}',
      'native frame age at conversion start '
          '${_milliseconds(conversionAgeAverage)}/'
          '${_milliseconds(native.maxGameCaptureNativeNv12ConversionStartAgeMs)}',
      'encoder fence wait '
          '${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/'
          '${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)}, '
          'processInput '
          '${_milliseconds(native.averageEncoderProcessInputMs)}/'
          '${_milliseconds(native.maxEncoderProcessInputMs)}, '
          'processOutput '
          '${_milliseconds(native.averageEncoderProcessOutputMs)}/'
          '${_milliseconds(native.maxEncoderProcessOutputMs)}, '
          'encodedCallback '
          '${_milliseconds(native.averageEncoderEncodedCallbackMs)}/'
          '${_milliseconds(native.maxEncoderEncodedCallbackMs)}, '
          'callbackWait '
          '${_milliseconds(native.averageEncoderEncodedCallbackQueueWaitMs)}/'
          '${_milliseconds(native.maxEncoderEncodedCallbackQueueWaitMs)}, '
          'callbackQueueMax=${native.encoderMaxEncodedCallbackQueueDepth}, '
          'callbackDropsMax=${native.encoderMaxEncodedCallbackDrops}, '
          'queueMax=${native.encoderMaxQueueDepth}, '
          'retainedMax=${native.encoderMaxRetainedSamples}, '
          'encodedOutputsMax=${native.encoderMaxEncodedOutputs}',
    ];

    return StreamTestBottleneck(
      label: 'encoder_handoff_limited',
      reasons: reasons,
      confidence: 'high',
      evidenceFor: evidence,
      evidenceAgainstFalseCauses: [
        'native NV12 readiness was healthy: '
            '${native.gameCaptureNativeNv12NotReadyPolls} not-ready polls, '
            '${native.gameCaptureNativeNv12ReadyDroppedFrames} ready drops, '
            '${native.gameCaptureNativeNv12Failures} native failures, '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        'native fence handoff was available/signaled: '
            '${native.gameCaptureNativeNv12FenceAvailable} / '
            '${native.gameCaptureNativeNv12FenceSignaledFrames}',
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) =>
                !evidence.startsWith('native MediaFoundation encoder timing') &&
                !evidence.startsWith('WebRTC average encode time'))
            .toList(growable: false),
      ],
      missingFields: [
        if (native.gameCaptureDeliverySubmitPrepSamples == 0)
          'delivery submit prep timing',
        if (native.gameCaptureDeliveryPostOnFrameSamples == 0)
          'delivery post-OnFrame timing',
        if (native.gameCaptureNativeBufferReleaseSamples == 0)
          'native buffer release timing',
        if (summary.framesDroppedBeforeEncodeMax == null &&
            summary.framesDroppedByEncoderMax == null)
          'sender drop counters',
        if (native.encoderEncodedCallbackSamples == 0)
          'encoded callback timing',
      ],
      recommendedNextAction: 'fix encoder path',
    );
  }

  static StreamTestBottleneck? _gameCaptureOnFrameLimitedBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        native.gameCaptureSubmittedFrames <= 0 ||
        native.gameCaptureGpuScaledFrames <= 0 ||
        native.gameCaptureCpuFallbackFrames > 0 ||
        native.gameCaptureDeliveryOnFrameCallSamples <= 0) {
      return null;
    }

    final callAverage = native.averageGameCaptureDeliveryOnFrameCallMs;
    final callMax = native.maxGameCaptureDeliveryOnFrameCallMs;
    if (callAverage == null || callMax == null) {
      return null;
    }

    final queueWaitAverage = native.averageGameCaptureDeliveryQueueWaitMs;
    final queueWaitIsDominant = queueWaitAverage != null &&
        queueWaitAverage > frameBudgetMs * 0.75 &&
        queueWaitAverage > callAverage;
    final onFrameOverBudget =
        callAverage > frameBudgetMs * 0.75 || callMax > frameBudgetMs * 2.0;
    if (!onFrameOverBudget || queueWaitIsDominant) {
      return null;
    }

    final reasons = <String>[
      'WebRTC OnFrame call averaged ${callAverage.toStringAsFixed(1)}ms '
          'and peaked at ${callMax.toStringAsFixed(1)}ms for a '
          '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
    ];
    final evidence = <String>[
      ...reasons,
    ];
    if (native.gameCaptureDeliverySubmitPrepSamples > 0 &&
        native.averageGameCaptureDeliverySubmitPrepMs != null &&
        native.maxGameCaptureDeliverySubmitPrepMs != null) {
      evidence.add(
        'submit prep averaged '
        '${native.averageGameCaptureDeliverySubmitPrepMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureDeliverySubmitPrepMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureDeliveryPostOnFrameSamples > 0 &&
        native.averageGameCaptureDeliveryPostOnFrameMs != null &&
        native.maxGameCaptureDeliveryPostOnFrameMs != null) {
      evidence.add(
        'post-OnFrame cleanup averaged '
        '${native.averageGameCaptureDeliveryPostOnFrameMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureDeliveryPostOnFrameMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeBufferReleaseSamples > 0 &&
        native.averageGameCaptureNativeBufferReleaseMs != null &&
        native.maxGameCaptureNativeBufferReleaseMs != null) {
      evidence.add(
        'native buffer release averaged '
        '${native.averageGameCaptureNativeBufferReleaseMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeBufferReleaseMs!.toStringAsFixed(1)}ms',
      );
    }
    if (queueWaitAverage != null &&
        native.maxGameCaptureDeliveryQueueWaitMs != null) {
      evidence.add(
        'delivery queue wait averaged '
        '${queueWaitAverage.toStringAsFixed(1)}ms and peaked at '
        '${native.maxGameCaptureDeliveryQueueWaitMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.averageEncoderTotalMs != null) {
      evidence.add(
        'native MediaFoundation encoder timing averaged '
        '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms '
        'with ${native.encoderSlowFrameCount}/'
        '${native.encoderSampleCount} slow samples',
      );
    }
    if (native.encoderEncodedCallbackSamples > 0) {
      evidence.add(
        'encoded callback averaged '
        '${_milliseconds(native.averageEncoderEncodedCallbackMs)} and peaked at '
        '${_milliseconds(native.maxEncoderEncodedCallbackMs)} '
        '(async frames ${native.encoderEncodedCallbackAsyncFrames}, '
        'queue max ${native.encoderMaxEncodedCallbackQueueDepth}, '
        'drops max ${native.encoderMaxEncodedCallbackDrops})',
      );
    }

    return StreamTestBottleneck(
      label: 'webrtc_onframe_limited',
      reasons: reasons,
      confidence: callAverage > frameBudgetMs ? 'high' : 'medium',
      evidenceFor: evidence,
      evidenceAgainstFalseCauses: [
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames with '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where((item) =>
                !item.startsWith('WebRTC average encode time') &&
                !item.startsWith('native MediaFoundation encoder timing'))
            .toList(growable: false),
      ],
      missingFields: [
        if (native.gameCaptureDeliverySubmitPrepSamples == 0)
          'delivery submit prep timing',
        if (native.gameCaptureDeliveryPostOnFrameSamples == 0)
          'delivery post-OnFrame timing',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0 &&
            native.gameCaptureNativeBufferReleaseSamples == 0)
          'native buffer release timing',
        if (native.encoderEncodedCallbackSamples == 0)
          'encoded callback timing',
      ],
      recommendedNextAction: 'fix encoder path',
    );
  }

  static StreamTestBottleneck? _gameCaptureDeliveryBackpressureBottleneck({
    required StreamTestSummary summary,
    required StreamTestNativeDiagnostics native,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null ||
        frameBudgetMs <= 0 ||
        native.gameCaptureSubmittedFrames <= 0 ||
        native.gameCaptureGpuScaledFrames <= 0 ||
        native.gameCaptureCpuFallbackFrames > 0) {
      return null;
    }

    final reasons = <String>[];
    final evidence = <String>[];
    final nativeNv12SourceActive =
        native.gameCaptureNativeNv12SubmittedFrames > 0 &&
            native.gameCaptureCpuFallbackFrames == 0;
    final readbackIsPrimaryPath = !nativeNv12SourceActive ||
        native.gameCaptureReadbackReadyFrames >
            max(10, native.gameCaptureNativeNv12SubmittedFrames ~/ 2);
    final sourceToSubmitAverage = native.averageGameCaptureSourceToSubmitMs;
    final sourceToSubmitMax = native.maxGameCaptureSourceToSubmitMs;
    if (native.gameCaptureSourceToSubmitSamples > 0 &&
        sourceToSubmitAverage != null &&
        sourceToSubmitMax != null &&
        (sourceToSubmitAverage > frameBudgetMs * 1.75 ||
            sourceToSubmitMax > frameBudgetMs * 3.0)) {
      reasons.add(
        'game-capture source-to-submit latency averaged '
        '${sourceToSubmitAverage.toStringAsFixed(1)}ms and peaked at '
        '${sourceToSubmitMax.toStringAsFixed(1)}ms for a '
        '${frameBudgetMs.toStringAsFixed(1)}ms frame budget',
      );
    }

    final queueWaitAverage = native.averageGameCaptureDeliveryQueueWaitMs;
    final queueWaitMax = native.maxGameCaptureDeliveryQueueWaitMs;
    if (native.gameCaptureDeliveryQueueWaitSamples > 0 &&
        queueWaitAverage != null &&
        queueWaitMax != null &&
        (queueWaitAverage > frameBudgetMs * 0.75 ||
            queueWaitMax > frameBudgetMs * 2.0)) {
      reasons.add(
        'delivery queue wait averaged '
        '${queueWaitAverage.toStringAsFixed(1)}ms and peaked at '
        '${queueWaitMax.toStringAsFixed(1)}ms',
      );
    }

    final deliveryWallMax = native.maxGameCaptureDeliveryWallDeltaMs;
    if (native.gameCaptureDeliveryWallSamples > 0 &&
        deliveryWallMax != null &&
        deliveryWallMax > frameBudgetMs * 3.0) {
      reasons.add(
        'delivery wall-clock gap peaked at '
        '${deliveryWallMax.toStringAsFixed(1)}ms',
      );
    }

    if (reasons.isEmpty) {
      return null;
    }

    if (native.gameCaptureDeliveryOverwrittenFrames > 0) {
      evidence.add(
        'delivery queue overwrote '
        '${native.gameCaptureDeliveryOverwrittenFrames} ready frames',
      );
    }
    if (native.gameCaptureDeliveryPacerResyncs > 0) {
      evidence.add(
        'delivery pacer resynced '
        '${native.gameCaptureDeliveryPacerResyncs} times '
        '(max lag ${native.gameCaptureDeliveryPacerLagMaxMs}ms)',
      );
    }
    if (native.gameCaptureDeliveryRepeatNoQueuedFrames > 0) {
      final repeatAge = native.maxGameCaptureDeliveryRepeatSourceAgeMs;
      evidence.add(
        'delivery pacer repeated '
        '${native.gameCaptureDeliveryRepeatNoQueuedFrames} frames with no '
        'fresh queued frame'
        '${repeatAge == null ? '' : ' (max source age ${repeatAge.toStringAsFixed(1)}ms)'}',
      );
    }
    if (native.gameCaptureDeliverySkipNoQueuedFrames > 0) {
      evidence.add(
        'delivery pacer skipped '
        '${native.gameCaptureDeliverySkipNoQueuedFrames} ticks with no fresh '
        'queued frame',
      );
    }
    if (native.gameCaptureDeliveryFreshWakeAfterSkipFrames > 0) {
      evidence.add(
        'delivery woke immediately after skipped ticks '
        '${native.gameCaptureDeliveryFreshWakeAfterSkipFrames} times',
      );
    }
    if (native.gameCaptureDeliveryOnFrameCallSamples > 0 &&
        native.averageGameCaptureDeliveryOnFrameCallMs != null &&
        native.maxGameCaptureDeliveryOnFrameCallMs != null) {
      evidence.add(
        'WebRTC OnFrame call averaged '
        '${native.averageGameCaptureDeliveryOnFrameCallMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureDeliveryOnFrameCallMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureSourceDuplicateSkipAgeSamples > 0 &&
        native.maxGameCaptureSourceDuplicateSkipAgeMs != null) {
      evidence.add(
        'capture loop skipped unchanged source frames with max source age '
        '${native.maxGameCaptureSourceDuplicateSkipAgeMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureDeliveryOverwrittenFreshFrames > 0) {
      final overwriteAge = native.maxGameCaptureDeliveryOverwriteAgeMs;
      evidence.add(
        'delivery queue overwrote '
        '${native.gameCaptureDeliveryOverwrittenFreshFrames} fresh frames'
        '${overwriteAge == null ? '' : ' (max age ${overwriteAge.toStringAsFixed(1)}ms)'}',
      );
    }
    if (native.gameCaptureSourceToQueueSamples > 0 &&
        native.averageGameCaptureSourceToQueueMs != null &&
        native.maxGameCaptureSourceToQueueMs != null) {
      evidence.add(
        'source-to-delivery-queue averaged '
        '${native.averageGameCaptureSourceToQueueMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureSourceToQueueMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12ReadyDroppedFrames > 0) {
      evidence.add(
        'native NV12 ready queue dropped '
        '${native.gameCaptureNativeNv12ReadyDroppedFrames} frames',
      );
    }
    if (native.gameCaptureNativeNv12ReadyDroppedFreshFrames > 0) {
      final readyDropAge = native.maxGameCaptureNativeNv12ReadyDropAgeMs;
      evidence.add(
        'native NV12 ready drain dropped '
        '${native.gameCaptureNativeNv12ReadyDroppedFreshFrames} fresh frames'
        '${readyDropAge == null ? '' : ' (max age ${readyDropAge.toStringAsFixed(1)}ms)'}',
      );
    }
    if (native.gameCaptureNativeNv12OverwrittenFreshFrames > 0) {
      final overwriteAge = native.maxGameCaptureNativeNv12OverwriteAgeMs;
      evidence.add(
        'native NV12 ring overwrote '
        '${native.gameCaptureNativeNv12OverwrittenFreshFrames} fresh pending frames'
        '${overwriteAge == null ? '' : ' (max age ${overwriteAge.toStringAsFixed(1)}ms)'}',
      );
    }
    if (native.gameCaptureNativeNv12NotReadyPolls > 0) {
      evidence.add(
        'native NV12 readiness polled not-ready '
        '${native.gameCaptureNativeNv12NotReadyPolls} times',
      );
    }
    if (readbackIsPrimaryPath &&
        native.gameCaptureSourceToReadbackReadySamples > 0 &&
        native.averageGameCaptureSourceToReadbackReadyMs != null &&
        native.maxGameCaptureSourceToReadbackReadyMs != null) {
      evidence.add(
        'source-to-readback-ready averaged '
        '${native.averageGameCaptureSourceToReadbackReadyMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureSourceToReadbackReadyMs!.toStringAsFixed(1)}ms',
      );
    }
    if (readbackIsPrimaryPath &&
        native.gameCaptureReadbackQueueToMapSamples > 0 &&
        native.averageGameCaptureReadbackQueueToMapMs != null &&
        native.maxGameCaptureReadbackQueueToMapMs != null) {
      evidence.add(
        'readback queue-to-map averaged '
        '${native.averageGameCaptureReadbackQueueToMapMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureReadbackQueueToMapMs!.toStringAsFixed(1)}ms',
      );
    }
    if (readbackIsPrimaryPath &&
        native.gameCaptureMapToI420Samples > 0 &&
        native.averageGameCaptureMapToI420Ms != null &&
        native.maxGameCaptureMapToI420Ms != null) {
      evidence.add(
        'map-to-I420 averaged '
        '${native.averageGameCaptureMapToI420Ms!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureMapToI420Ms!.toStringAsFixed(1)}ms',
      );
    }
    if (native.gameCaptureNativeNv12ConvertSamples > 0 &&
        native.averageGameCaptureNativeNv12ConvertMs != null &&
        native.maxGameCaptureNativeNv12ConvertMs != null) {
      evidence.add(
        'native NV12 readiness averaged '
        '${native.averageGameCaptureNativeNv12ConvertMs!.toStringAsFixed(1)}ms '
        'and peaked at '
        '${native.maxGameCaptureNativeNv12ConvertMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.averageEncoderTotalMs != null) {
      evidence.add(
        'native MediaFoundation encoder timing averaged '
        '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms '
        'with ${native.encoderSlowFrameCount}/'
        '${native.encoderSampleCount} slow samples',
      );
    }

    final falseCauseEvidence = _evidenceAgainstCommonFalseCauses(summary)
        .where((item) =>
            !item.startsWith('WebRTC average encode time') &&
            !item.startsWith('native MediaFoundation encoder timing'))
        .toList(growable: false);

    return StreamTestBottleneck(
      label: 'delivery_queue_limited',
      reasons: [
        ...reasons,
        'encoded/sent FPS can stay near target while displayed frames are '
            'several frame budgets behind the game source',
        'native game-capture delivery/source-to-submit pressure appears before '
            'the generic sender encoder-pipeline label',
      ],
      confidence: evidence.length >= 2 ? 'high' : 'medium',
      evidenceFor: [
        ...reasons,
        ...evidence,
      ],
      evidenceAgainstFalseCauses: [
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames with '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ...falseCauseEvidence,
      ],
      missingFields: const [],
      recommendedNextAction: 'fix frame pacing',
    );
  }

  static bool _nativeEncoderHandoffLimited(StreamTestSummary summary) {
    final native = summary.nativeDiagnostics;
    if (!native.nativeEncoderHandoffNoOutput) {
      return false;
    }
    if (summary.senderSampleCount == 0) {
      return true;
    }
    final encodeFps = summary.averageEncodeFps;
    final sendFps = summary.averageSendFps;
    return encodeFps == null ||
        encodeFps <= 0.1 ||
        sendFps == null ||
        sendFps <= 0.1 ||
        native.encoderMaxQueueDepth >= max(2, native.encoderSampleCount);
  }

  static StreamTestBottleneck _mediaFoundationEncoderLimitedBottleneck({
    required StreamTestSummary summary,
    required double? frameBudgetMs,
  }) {
    final native = summary.nativeDiagnostics;
    final average = native.averageEncoderTotalMs;
    final budget = frameBudgetMs ?? 33.0;
    final reasons = <String>[
      if (average != null)
        'native MediaFoundation encoder averaged '
            '${average.toStringAsFixed(1)}ms against a '
            '${budget.toStringAsFixed(1)}ms frame budget',
      if (native.encoderSampleCount > 0)
        'native MediaFoundation slow samples '
            '${native.encoderSlowFrameCount}/${native.encoderSampleCount} '
            '(${(native.encoderSlowSampleRatio * 100).toStringAsFixed(1)}%)',
      if (native.encoderInputPaths.isNotEmpty)
        'encoder input path ${native.encoderInputPathLabel}',
    ];
    return StreamTestBottleneck(
      label: 'media_foundation_encoder_limited',
      reasons: reasons,
      confidence: average != null ? 'high' : 'medium',
      evidenceFor: [
        ...reasons,
        if (summary.averageEncodeTimeMs != null)
          'WebRTC average encode time '
              '${summary.averageEncodeTimeMs!.toStringAsFixed(1)}ms',
        if (native.encoderMaxQueueDepth > 0)
          'native encoder queue max ${native.encoderMaxQueueDepth}',
        if (native.encoderMaxRetainedSamples > 0)
          'native encoder retained DXGI samples max '
              '${native.encoderMaxRetainedSamples}',
      ],
      evidenceAgainstFalseCauses: [
        'game-capture GPU scale succeeded '
            '${native.gameCaptureGpuScaledFrames} frames with '
            '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) =>
                !evidence.startsWith('native MediaFoundation encoder timing') &&
                !evidence.startsWith('WebRTC average encode time'))
            .toList(growable: false),
      ],
      missingFields: native.encoderSampleCount == 0
          ? const ['native MediaFoundation encoder timing samples']
          : const [],
      recommendedNextAction: 'fix encoder path',
    );
  }

  static bool _gameCaptureGpuHandoffUnproven(StreamTestSummary summary) {
    final native = summary.nativeDiagnostics;
    if (!native.gameCaptureGpuHandoffUnproven) {
      return false;
    }
    final loss = summary.maxPacketLossPercent ?? 0;
    final rtt = summary.maxRoundTripTimeMs ?? 0;
    final nack = summary.maxNackCount ?? 0;
    return loss <= 1.0 && rtt <= 150 && nack <= 8;
  }

  static StreamTestBottleneck _gameCaptureGpuHandoffUnprovenBottleneck(
    StreamTestSummary summary,
  ) {
    final native = summary.nativeDiagnostics;
    final disabledReason = native.gameCaptureNativeNv12HandoffDisabledReason;
    final reasons = [
      if (disabledReason != null)
        'native NV12 encoder handoff disabled: $disabledReason',
      'game-capture GPU scale produced '
          '${native.gameCaptureGpuScaledFrames} frames but native NV12 source '
          'submitted 0',
      if (native.encoderCpuI420InputFrames > 0)
        'Media Foundation consumed CPU I420 input '
            '${native.encoderCpuI420InputFrames} times instead of native NV12',
      if (native.gameCaptureReadbackQueuedFrames > 0 ||
          native.gameCaptureReadbackNotReadyFrames > 0)
        'fallback path used scaled readback '
            '${native.gameCaptureReadbackQueuedFrames}/'
            '${native.gameCaptureReadbackReadyFrames} with '
            '${native.gameCaptureReadbackNotReadyFrames} not-ready maps',
    ];
    return StreamTestBottleneck(
      label: 'gpu_handoff_unproven',
      reasons: reasons,
      confidence: disabledReason == null ? 'medium' : 'high',
      evidenceFor: reasons,
      evidenceAgainstFalseCauses: [
        'game-capture source/output '
            '${native.gameCaptureSourceResolutionLabel} -> '
            '${native.gameCaptureOutputResolutionLabel}',
        'game-capture GPU scale failures '
            '${native.gameCaptureGpuScaleFailures} and CPU fallbacks '
            '${native.gameCaptureCpuFallbackFrames}',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches '
            '${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) => !evidence.startsWith('native encoder'))
            .toList(growable: false),
      ],
      missingFields: disabledReason == null
          ? const ['native_nv12_encoder_handoff_disabled reason']
          : const [],
      recommendedNextAction: 'fix game-capture handoff',
    );
  }

  static StreamTestBottleneck _nativeEncoderHandoffLimitedBottleneck(
    StreamTestSummary summary,
  ) {
    final native = summary.nativeDiagnostics;
    final reasons = [
      'native NV12 input reached Media Foundation '
          '${native.encoderNativeInputFrames} timing samples',
      'Media Foundation output stayed at ${native.encoderOutputFrames} frames '
          'and ${native.encoderOutputBytes} bytes',
      'encoder queue reached ${native.encoderMaxQueueDepth} pending frames '
          'with ${native.encoderMaxRetainedSamples} retained DXGI samples',
      if (native.encoderNativeSuspendedFrames > 0)
        'native NV12 input was suspended '
            '${native.encoderNativeSuspendedFrames} times',
      if (summary.senderSampleCount == 0)
        'no sender stats were collected after the native handoff marker',
    ];
    return StreamTestBottleneck(
      label: 'encoder_handoff_limited',
      reasons: reasons,
      confidence: 'high',
      evidenceFor: reasons,
      evidenceAgainstFalseCauses: [
        'native sample creation failures: '
            '${native.encoderNativeSampleFailures}',
        if (native.gameCaptureGpuScaledFrames > 0)
          'game-capture GPU scale succeeded '
              '${native.gameCaptureGpuScaledFrames} frames with '
              '${native.gameCaptureCpuFallbackFrames} CPU fallbacks',
        if (native.gameCaptureNativeNv12SubmittedFrames > 0)
          'native NV12 WebRTC source submitted '
              '${native.gameCaptureNativeNv12SubmittedFrames} frames with '
              '${native.gameCaptureNativeNv12Failures} failures',
        'source regressions ${native.gameCaptureSourceFrameRegressions}, '
            'shared slot mismatches ${native.gameCaptureSharedSlotMismatches}',
        ..._evidenceAgainstCommonFalseCauses(summary)
            .where((evidence) => !evidence.startsWith('native encoder'))
            .toList(growable: false),
      ],
      missingFields: const [],
      recommendedNextAction: 'fix encoder path',
    );
  }

  static List<String> _classificationMissingFields(StreamTestSummary summary) {
    final missing = <String>{
      if (summary.averageCaptureFps == null) 'capture FPS',
      if (summary.averageEncodeFps == null) 'encode FPS',
      if (summary.averageSendFps == null) 'send FPS',
      if (summary.preEncodeSampleCount == 0) 'pre-encode dimensions',
      if (summary.averageEncodeTimeMs == null) 'average encode time',
      if (summary.framesDroppedByEncoderMax == null) 'encoder dropped frames',
      if (summary.maxPacketLossPercent == null) 'packet loss',
      if (summary.maxRoundTripTimeMs == null) 'RTT',
      if (summary.maxNackCount == null) 'NACK count',
      if (!summary.nativeDiagnostics.hasEvidence) 'native capture markers',
      if (!summary.framePacing.rendered.hasEvidence) 'receiver render FPS',
    };
    return missing.toList(growable: false)..sort();
  }

  static List<String> _evidenceAgainstCommonFalseCauses(
    StreamTestSummary summary,
  ) {
    final evidence = <String>[];
    final loss = summary.maxPacketLossPercent;
    final rtt = summary.maxRoundTripTimeMs;
    final nack = summary.maxNackCount;
    if (loss != null && rtt != null && nack != null) {
      if (loss <= 1.0 && rtt <= 150 && nack <= 8) {
        evidence.add(
          'network evidence is clean: loss=${loss.toStringAsFixed(1)}%, '
          'RTT=${rtt.toStringAsFixed(0)}ms, NACK=$nack',
        );
      }
    }
    final native = summary.nativeDiagnostics;
    if (summary.averageEncodeTimeMs != null) {
      evidence.add(
        'WebRTC average encode time is '
        '${summary.averageEncodeTimeMs!.toStringAsFixed(1)}ms',
      );
    }
    if (native.averageEncoderTotalMs != null &&
        !native.isNativeEncoderOverBudgetFor(33.0)) {
      evidence.add(
        'native MediaFoundation encoder timing is '
        '${native.averageEncoderTotalMs!.toStringAsFixed(1)}ms avg',
      );
    }
    if (native.gameCaptureNativeNv12SubmittedFrames > 0) {
      evidence.add(
        'native NV12 source submission is active: '
        '${native.gameCaptureNativeNv12SubmittedFrames} frames, '
        '${native.gameCaptureNativeNv12Failures} failures, '
        '${native.gameCaptureReadbackQueuedFrames} readbacks queued',
      );
    }
    if (native.encoderInputPaths.isNotEmpty) {
      evidence.add(
        'native encoder input path ${native.encoderInputPathLabel}; '
        'native=${native.encoderNativeInputFrames}, '
        'cpu_i420=${native.encoderCpuI420InputFrames}, '
        'native_sample_failures=${native.encoderNativeSampleFailures}',
      );
    }
    if (summary.requestedResolutionLabel != 'unknown' &&
        summary.encodedResolutionLabel != 'unknown' &&
        !_resolutionLimitNotApplied(summary)) {
      evidence.add(
        'resolution cap appears applied: requested '
        '${summary.requestedResolutionLabel}, encoded '
        '${summary.encodedResolutionLabel}',
      );
    }
    if (summary.activeLayers.isEmpty ||
        !summary.activeLayers.any(_isDowngradedLayer)) {
      evidence.add('no downgraded sender layer was reported');
    }
    return evidence;
  }

  static bool _stageFpsTracks(double? value, double reference) {
    if (value == null || value <= 0 || reference <= 0) {
      return true;
    }
    return value >= reference * 0.8 && value <= reference * 1.25;
  }

  static double _effectiveFpsRatio({
    required StreamTestSummary summary,
    required double targetFps,
    required double? averageFps,
  }) {
    if (targetFps <= 0) {
      return 0;
    }
    var ratio =
        averageFps == null || averageFps <= 0 ? 0.0 : averageFps / targetFps;
    final frameBudgetMs = 1000 / targetFps;
    for (final stage in _senderPacingStages(summary)) {
      final p95IntervalMs = stage.p95IntervalMs;
      if (p95IntervalMs != null && p95IntervalMs > 0) {
        ratio = min(ratio, (1000 / p95IntervalMs) / targetFps);
      }
      final maxIntervalMs = stage.maxIntervalMs;
      if (maxIntervalMs != null && maxIntervalMs > frameBudgetMs * 3) {
        ratio = min(ratio, (frameBudgetMs * 3) / maxIntervalMs);
      }
      if (stage.staleFrameReuseCount > 0) {
        ratio = min(ratio, 0.49);
      }
    }
    return ratio.clamp(0.0, 1.0).toDouble();
  }

  static List<String> _framePacingReasons({
    required StreamTestSummary summary,
    required double? frameBudgetMs,
  }) {
    if (frameBudgetMs == null || frameBudgetMs <= 0) {
      return const [];
    }
    final reasons = <String>[];
    for (final stage in _senderPacingStages(summary)) {
      final p95IntervalMs = stage.p95IntervalMs;
      if (p95IntervalMs != null && p95IntervalMs > frameBudgetMs * 1.15) {
        reasons.add(
          '${stage.stage} p95 frame interval '
          '${p95IntervalMs.toStringAsFixed(0)}ms exceeds '
          '${frameBudgetMs.toStringAsFixed(0)}ms target cadence',
        );
      }
      final maxIntervalMs = stage.maxIntervalMs;
      if (maxIntervalMs != null && maxIntervalMs > frameBudgetMs * 3) {
        reasons.add(
          '${stage.stage} max frame gap '
          '${maxIntervalMs.toStringAsFixed(0)}ms exceeds '
          '${frameBudgetMs.toStringAsFixed(0)}ms target cadence',
        );
      }
      if (stage.staleFrameReuseCount > 0) {
        reasons.add(
          '${stage.stage} had ${stage.staleFrameReuseCount} stale '
          'frame-counter window(s)',
        );
      }
      if (reasons.length >= 3) {
        break;
      }
    }
    return reasons;
  }

  static List<StreamTestFramePacingStageSummary> _senderPacingStages(
    StreamTestSummary summary,
  ) {
    final pacing = summary.framePacing;
    return [
      pacing.sent,
      pacing.encoded,
      pacing.capture,
      pacing.nativeCapture,
    ];
  }

  static bool _resolutionLimitNotApplied(StreamTestSummary summary) {
    final requestedWidth = summary.requestedWidth;
    final requestedHeight = summary.requestedHeight;
    final encodedWidth = summary.encodedWidth;
    final encodedHeight = summary.encodedHeight;
    if (requestedWidth == null ||
        requestedHeight == null ||
        encodedWidth == null ||
        encodedHeight == null ||
        requestedWidth <= 0 ||
        requestedHeight <= 0 ||
        encodedWidth <= 0 ||
        encodedHeight <= 0) {
      return false;
    }

    final widthTooLarge = encodedWidth > requestedWidth + 32 &&
        encodedWidth > requestedWidth * 1.1;
    final heightTooLarge = encodedHeight > requestedHeight + 18 &&
        encodedHeight > requestedHeight * 1.1;
    return widthTooLarge || heightTooLarge;
  }
}

class StreamTestBottleneck {
  const StreamTestBottleneck({
    required this.label,
    this.reasons = const [],
    this.confidence = 'medium',
    this.missingFields = const [],
    this.evidenceFor = const [],
    this.evidenceAgainstFalseCauses = const [],
    this.recommendedNextAction = 'collect one specific missing field',
  });

  final String label;
  final List<String> reasons;
  final String confidence;
  final List<String> missingFields;
  final List<String> evidenceFor;
  final List<String> evidenceAgainstFalseCauses;
  final String recommendedNextAction;

  List<String> get effectiveEvidenceFor =>
      evidenceFor.isEmpty ? reasons : evidenceFor;

  Map<String, Object?> toJson() {
    return {
      'label': label,
      'reasons': reasons,
      'confidence': confidence,
      'missingFields': missingFields,
      'evidenceFor': effectiveEvidenceFor,
      'evidenceAgainstFalseCauses': evidenceAgainstFalseCauses,
      'recommendedNextAction': recommendedNextAction,
    };
  }
}

enum StreamDiagnosticCoverageStatus {
  available,
  missing,
  unavailable,
  notApplicable,
}

class StreamDiagnosticCoverageItem {
  const StreamDiagnosticCoverageItem({
    required this.category,
    required this.status,
    required this.detail,
    this.missingFields = const [],
  });

  final String category;
  final StreamDiagnosticCoverageStatus status;
  final String detail;
  final List<String> missingFields;

  String get statusName {
    switch (status) {
      case StreamDiagnosticCoverageStatus.available:
        return 'available';
      case StreamDiagnosticCoverageStatus.missing:
        return 'missing';
      case StreamDiagnosticCoverageStatus.unavailable:
        return 'unavailable';
      case StreamDiagnosticCoverageStatus.notApplicable:
        return 'notApplicable';
    }
  }

  String get markdownMarker {
    switch (status) {
      case StreamDiagnosticCoverageStatus.available:
        return '[PASS]';
      case StreamDiagnosticCoverageStatus.missing:
        return '[WARN]';
      case StreamDiagnosticCoverageStatus.unavailable:
        return '[FAIL]';
      case StreamDiagnosticCoverageStatus.notApplicable:
        return '[N/A]';
    }
  }

  Map<String, Object?> toJson() {
    return {
      'category': category,
      'status': statusName,
      'detail': detail,
      'missingFields': missingFields,
    };
  }
}

class StreamDiagnosticCoverageMatrix {
  const StreamDiagnosticCoverageMatrix(this.items);

  factory StreamDiagnosticCoverageMatrix.forRun(StreamTestRunResult result) {
    final sourceItem = result.config.sourceMetadata == null
        ? const StreamDiagnosticCoverageItem(
            category: 'source metadata',
            status: StreamDiagnosticCoverageStatus.missing,
            detail: 'stream-test source metadata was not captured',
            missingFields: ['source type', 'source id hash'],
          )
        : StreamDiagnosticCoverageItem(
            category: 'source metadata',
            status: StreamDiagnosticCoverageStatus.available,
            detail: result.config.sourceMetadata!.label,
          );
    final requestedItem = result.config.presets.isEmpty
        ? const StreamDiagnosticCoverageItem(
            category: 'requested settings',
            status: StreamDiagnosticCoverageStatus.missing,
            detail: 'no stream-test presets were configured',
            missingFields: ['profile name', 'target width', 'target FPS'],
          )
        : StreamDiagnosticCoverageItem(
            category: 'requested settings',
            status: StreamDiagnosticCoverageStatus.available,
            detail: result.config.presets
                .map((profile) =>
                    '${profile.label} ${profile.mainLayer.resolutionLabel}@${profile.mainLayer.diagnosticFramerateLabel}')
                .join(', '),
          );
    final perPresetMatrices = result.presetResults
        .map((preset) => preset.diagnosticCoverage)
        .toList(growable: false);
    return StreamDiagnosticCoverageMatrix([
      sourceItem,
      requestedItem,
      _gameCaptureTestTargetCoverage(result),
      _gameCaptureProbeCoverage(result),
      _loadedLibwebrtcArtifactCoverage(result),
      _hostLoadCoverage(result),
      ..._mergePerPresetCoverage(perPresetMatrices),
    ]);
  }

  factory StreamDiagnosticCoverageMatrix.forPreset(
    StreamTestPresetResult result,
  ) {
    return StreamDiagnosticCoverageMatrix.forSummary(result.score.summary);
  }

  factory StreamDiagnosticCoverageMatrix.forSummary(
    StreamTestSummary summary,
  ) {
    final native = summary.nativeDiagnostics;
    final wgcObserved =
        native.observedCapturerLabel.toLowerCase().contains('wgc') ||
            native.backendLabel.toLowerCase().contains('wgc');
    final gdiObserved =
        native.observedCapturerLabel.toLowerCase().contains('window-gdi') ||
            native.observedCapturerLabel.toLowerCase().contains('windowgdi') ||
            native.observedCapturerLabel.toLowerCase().contains('wingdi');
    final gameHookObserved =
        native.observedCapturerLabel.toLowerCase().contains('game-d3d11') ||
            native.gameCaptureSubmittedFrames > 0 ||
            native.gameCaptureSourceFrameIndex > 0;
    final causeAttribution = native.captureCauseAttribution;
    final missingCauseFields = <String>[
      if (causeAttribution['fullSourceAcquisition'] == 'unknown')
        'source/acquisition size attribution',
      if (causeAttribution['blockingAcquireWait'] == 'unknown')
        'blocking acquire wait attribution',
      if (causeAttribution['cpuReadbackOrCopy'] == 'unknown')
        'CPU readback/copy attribution',
      if (causeAttribution['dirtyRegionProcessing'] == 'unknown')
        'dirty-region processing attribution',
      if (causeAttribution['frameLifetimeOrSynchronization'] == 'unknown')
        'frame lifetime/lock synchronization attribution',
      if (causeAttribution['fullFrameCopyBeforeDownscale'] == 'unknown')
        'pre-downscale full-frame copy attribution',
    ];
    final items = <StreamDiagnosticCoverageItem>[
      if (summary.requestedWidth != null ||
          summary.requestedHeight != null ||
          summary.requestedFps != null ||
          summary.requestedBitrateBps != null ||
          summary.screenShareProfileDetails.isNotEmpty)
        StreamDiagnosticCoverageItem(
          category: 'requested settings',
          status: StreamDiagnosticCoverageStatus.available,
          detail: summary.requestedResolutionLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'requested settings',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'requested sender settings were not present in stats',
          missingFields: [
            'requested width',
            'requested height',
            'requested FPS',
            'requested bitrate',
          ],
        ),
      if (summary.senderSampleCount > 0)
        StreamDiagnosticCoverageItem(
          category: 'sender stats',
          status: StreamDiagnosticCoverageStatus.available,
          detail:
              '${summary.senderSampleCount} sender samples; encoded ${summary.encodedResolutionLabel}; send ${_number(summary.averageSendFps)}fps',
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'sender stats',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'no sender screenshare stats were collected',
          missingFields: [
            'sender track stats',
            'encoded frame size',
            'send FPS',
            'send bitrate',
          ],
        ),
      native.hasEvidence
          ? StreamDiagnosticCoverageItem(
              category: 'native capture markers',
              status: StreamDiagnosticCoverageStatus.available,
              detail: native.summaryLabel,
            )
          : const StreamDiagnosticCoverageItem(
              category: 'native capture markers',
              status: StreamDiagnosticCoverageStatus.missing,
              detail: 'no parsed native capture markers were present',
              missingFields: [
                'native capture cadence',
                'native source size',
                'native pre-encode size',
              ],
            ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'game-capture backend contract',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.gameCaptureBackendContractVersion != null &&
          native.gameCaptureSourceApi != null &&
          native.gameCaptureSourceFormat != null &&
          native.gameCaptureSyncKind != null &&
          native.gameCaptureReadyState != null &&
          native.gameCaptureFailureReason != null)
        StreamDiagnosticCoverageItem(
          category: 'game-capture backend contract',
          status: StreamDiagnosticCoverageStatus.available,
          detail: 'v${native.gameCaptureBackendContractVersion} '
              'api=${native.gameCaptureSourceApi} '
              'format=${native.gameCaptureSourceFormat} '
              'sync=${native.gameCaptureSyncKind} '
              'ready=${native.gameCaptureReadyState} '
              'failure=${native.gameCaptureFailureReason}',
        )
      else
        StreamDiagnosticCoverageItem(
          category: 'game-capture backend contract',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook native markers did not include backend-neutral contract fields',
          missingFields: [
            if (native.gameCaptureBackendContractVersion == null)
              'game-capture backend contract version',
            if (native.gameCaptureSourceApi == null) 'game-capture source API',
            if (native.gameCaptureSourceFormat == null)
              'game-capture source format',
            if (native.gameCaptureSyncKind == null) 'game-capture sync kind',
            if (native.gameCaptureReadyState == null)
              'game-capture ready state',
            if (native.gameCaptureFailureReason == null)
              'game-capture failure reason',
          ],
        ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'game-capture frame order',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.gameCaptureSourceFrameIndex > 0 ||
          native.gameCaptureLastSubmittedSourceFrameIndex > 0 ||
          native.gameCaptureSourceFrameRegressions > 0 ||
          native.gameCaptureSharedSlotMismatches > 0 ||
          native.gameCaptureTimestampMode != null ||
          native.gameCaptureTimestampSamples > 0 ||
          native.gameCaptureDeliveryWallSamples > 0 ||
          native.gameCaptureSourceQpcSamples > 0)
        StreamDiagnosticCoverageItem(
          category: 'game-capture frame order',
          status: StreamDiagnosticCoverageStatus.available,
          detail: 'source=${native.gameCaptureSourceFrameIndex}; '
              'lastSubmitted='
              '${native.gameCaptureLastSubmittedSourceFrameIndex}; '
              'regressions=${native.gameCaptureSourceFrameRegressions}; '
              'slotMismatches=${native.gameCaptureSharedSlotMismatches}; '
              'timestamp=${native.gameCaptureTimestampMode ?? 'unknown'}; '
              'timestampMax='
              '${_milliseconds(native.maxGameCaptureTimestampDeltaMs)}; '
              'deliveryWallMax='
              '${_milliseconds(native.maxGameCaptureDeliveryWallDeltaMs)}; '
              'sourceQpcMax='
              '${_milliseconds(native.maxGameCaptureSourceQpcDeltaMs)}; '
              'timestampAdjustments='
              '${native.gameCaptureTimestampAdjustments}',
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'game-capture frame order',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook native markers did not include frame-order or timestamp fields',
          missingFields: [
            'source frame index',
            'last submitted source frame index',
            'source frame regression count',
            'shared slot mismatch count',
            'delivery timestamp delta',
            'delivery wall-clock delta',
            'source QPC delta',
          ],
        ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'game-capture stage timing',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.gameCaptureSourceToSubmitSamples > 0 &&
          native.gameCaptureSourceToI420ReadySamples > 0 &&
          native.gameCaptureSourceToQueueSamples > 0)
        StreamDiagnosticCoverageItem(
          category: 'game-capture stage timing',
          status: StreamDiagnosticCoverageStatus.available,
          detail: 'source->readbackReady='
              '${_milliseconds(native.averageGameCaptureSourceToReadbackReadyMs)}/'
              '${_milliseconds(native.maxGameCaptureSourceToReadbackReadyMs)}; '
              'readbackQueue->map='
              '${_milliseconds(native.averageGameCaptureReadbackQueueToMapMs)}/'
              '${_milliseconds(native.maxGameCaptureReadbackQueueToMapMs)}; '
              'map->I420='
              '${_milliseconds(native.averageGameCaptureMapToI420Ms)}/'
              '${_milliseconds(native.maxGameCaptureMapToI420Ms)}; '
              'source->I420='
              '${_milliseconds(native.averageGameCaptureSourceToI420ReadyMs)}/'
              '${_milliseconds(native.maxGameCaptureSourceToI420ReadyMs)}; '
              'source->queue='
              '${_milliseconds(native.averageGameCaptureSourceToQueueMs)}/'
              '${_milliseconds(native.maxGameCaptureSourceToQueueMs)}; '
              'source->submit='
              '${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
              '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)}',
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'game-capture stage timing',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook native markers did not include enough source/readback/I420 handoff split fields',
          missingFields: [
            'source to readback-ready timing',
            'readback queue to map timing',
            'map to I420 timing',
            'source to I420-ready timing',
            'source to delivery queue timing',
          ],
        ),
      if (native.hasEvidence && missingCauseFields.isEmpty)
        StreamDiagnosticCoverageItem(
          category: 'capture cause attribution',
          status: StreamDiagnosticCoverageStatus.available,
          detail:
              'source/acquire/readback/dirty/sync/pre-downscale-copy buckets are populated',
        )
      else if (native.hasEvidence)
        StreamDiagnosticCoverageItem(
          category: 'capture cause attribution',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'native markers are present but one or more capture-cause buckets are incomplete',
          missingFields: missingCauseFields,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'capture cause attribution',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'native capture markers were not available',
        ),
      if (!wgcObserved)
        const StreamDiagnosticCoverageItem(
          category: 'WGC substage markers',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'WGC was not the observed native capturer',
        )
      else if (native.wgcFrameSummaryLabel != 'unknown')
        StreamDiagnosticCoverageItem(
          category: 'WGC substage markers',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.wgcFrameSummaryLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'WGC substage markers',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'WGC capturer was observed without substage timing',
          missingFields: [
            'TryGetNextFrame timing',
            'Map timing',
            'row copy timing',
            'frame-pool empty count',
          ],
        ),
      if (!gdiObserved)
        const StreamDiagnosticCoverageItem(
          category: 'window-GDI substage markers',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'window-GDI was not the observed native capturer',
        )
      else if (native.gdiFrameSummaryLabel != 'unknown')
        StreamDiagnosticCoverageItem(
          category: 'window-GDI substage markers',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.gdiFrameSummaryLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'window-GDI substage markers',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'window-GDI capturer was observed without substage timing',
          missingFields: [
            'PrintWindow timing',
            'BitBlt timing',
            'crop timing',
            'owned-window timing',
          ],
        ),
      if (!gdiObserved)
        const StreamDiagnosticCoverageItem(
          category: 'capture output validity',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'window-GDI was not the observed native capturer',
        )
      else if (native.gdiFinalFrameCount > 0)
        StreamDiagnosticCoverageItem(
          category: 'capture output validity',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.gdiOutputValidityLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'capture output validity',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'window-GDI was observed without final-frame validity counters',
          missingFields: [
            'final producer counts',
            'black frame count',
            'low-variance frame count',
          ],
        ),
      if (native.updatedRegionShapeLabel != 'unknown')
        StreamDiagnosticCoverageItem(
          category: 'dirty-region shape',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.updatedRegionShapeLabel,
        )
      else if (native.hasEvidence)
        const StreamDiagnosticCoverageItem(
          category: 'dirty-region shape',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'native markers were present without dirty-region shape',
          missingFields: [
            'updated-region rect count',
            'dirty-area ratio',
            'full-frame update count',
          ],
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'dirty-region shape',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'native capture markers were not available',
        ),
      if (native.averageUpdatedRegionAnalysisMs != null ||
          native.maxUpdatedRegionAnalysisMs != null)
        StreamDiagnosticCoverageItem(
          category: 'dirty-region processing timing',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.dirtyRegionProcessingAttributionLabel,
        )
      else if (native.hasEvidence)
        const StreamDiagnosticCoverageItem(
          category: 'dirty-region processing timing',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'native markers were present without updated-region analysis timing',
          missingFields: ['updated-region analysis timing'],
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'dirty-region processing timing',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'native capture markers were not available',
        ),
      summary.framePacing.hasEvidence
          ? StreamDiagnosticCoverageItem(
              category: 'frame pacing',
              status: StreamDiagnosticCoverageStatus.available,
              detail: summary.framePacing.compactLabel,
            )
          : const StreamDiagnosticCoverageItem(
              category: 'frame pacing',
              status: StreamDiagnosticCoverageStatus.missing,
              detail: 'frame counter cadence was not available',
              missingFields: [
                'framesCaptured counter',
                'framesEncoded counter',
                'framesSent counter',
              ],
            ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'WebRTC raw sender boundary',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (native.hasWebrtcRawSenderBoundaryDiagnostics)
        StreamDiagnosticCoverageItem(
          category: 'WebRTC raw sender boundary',
          status: StreamDiagnosticCoverageStatus.available,
          detail: native.webrtcRawSenderBoundaryLabel,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'WebRTC raw sender boundary',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook markers did not include source broadcast, VideoStreamEncoder, or VideoEncoder::Encode boundary timing',
          missingFields: [
            'WebRTC source sink dispatch timing',
            'VideoBroadcaster lock/sink dispatch timing',
            'VideoStreamEncoder OnFrame timing',
            'VideoStreamEncoder adaptation/drop counters',
            'VideoEncoder::Encode timing',
          ],
        ),
      if (!gameHookObserved)
        const StreamDiagnosticCoverageItem(
          category: 'sender handoff diagnostics',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: 'D3D11 game-hook WebRTC source was not observed',
        )
      else if (summary.hasSenderHandoffDiagnostics)
        StreamDiagnosticCoverageItem(
          category: 'sender handoff diagnostics',
          status: StreamDiagnosticCoverageStatus.available,
          detail: summary.senderHandoffDiagnosticsLabel,
          missingFields: summary.senderHandoffDiagnosticMissingFields,
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'sender handoff diagnostics',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'game-hook markers did not include live OnFrame, native frame age, encoder timing, or sender drop counters',
          missingFields: [
            'delivery_on_frame_call_ms',
            'native_nv12_conversion_start_age_ms',
            'native_ready_fence_wait_ms',
            'process_input_ms',
            'process_output_ms',
            'encoded_callback_ms',
            'sender drop counters',
          ],
        ),
      if (native.nativeEncoderFenceWaitMissing)
        StreamDiagnosticCoverageItem(
          category: 'encoder markers',
          status: StreamDiagnosticCoverageStatus.missing,
          detail:
              'native NV12 encoder timing was present without parsed fence-wait timing; codec=${summary.senderCodecsLabel} engine=${summary.encoderImplementationsLabel} hw=${summary.hardwareEncodeStatesLabel} native=${_milliseconds(native.averageEncoderTotalMs)}',
          missingFields: const [
            'native_ready_fence',
            'native_ready_fence_timeout',
            'native_ready_fence_wait_ms',
            'process_input_ms',
            'process_output_ms',
            'encoded_callback_ms',
          ],
        )
      else if (summary.encoderImplementations.isNotEmpty ||
          summary.hardwareEncodeStates.isNotEmpty ||
          summary.averageEncodeTimeMs != null ||
          native.averageEncoderTotalMs != null)
        StreamDiagnosticCoverageItem(
          category: 'encoder markers',
          status: StreamDiagnosticCoverageStatus.available,
          detail:
              'codec=${summary.senderCodecsLabel} engine=${summary.encoderImplementationsLabel} hw=${summary.hardwareEncodeStatesLabel} native=${_milliseconds(native.averageEncoderTotalMs)} fenceWait=${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)} processInput=${_milliseconds(native.averageEncoderProcessInputMs)}/${_milliseconds(native.maxEncoderProcessInputMs)} processOutput=${_milliseconds(native.averageEncoderProcessOutputMs)}/${_milliseconds(native.maxEncoderProcessOutputMs)} encodedCallback=${_milliseconds(native.averageEncoderEncodedCallbackMs)}/${_milliseconds(native.maxEncoderEncodedCallbackMs)}',
        )
      else
        const StreamDiagnosticCoverageItem(
          category: 'encoder markers',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'encoder implementation/timing was not present',
          missingFields: [
            'encoder implementation',
            'hardware encode state',
            'encode time',
          ],
        ),
      summary.framePacing.received.hasEvidence ||
              summary.framePacing.decoded.hasEvidence ||
              summary.framePacing.rendered.hasEvidence
          ? StreamDiagnosticCoverageItem(
              category: 'receiver stats',
              status: StreamDiagnosticCoverageStatus.available,
              detail:
                  'received=${summary.framePacing.received.markdownLabel}; decoded=${summary.framePacing.decoded.markdownLabel}; rendered=${summary.framePacing.rendered.markdownLabel}',
            )
          : const StreamDiagnosticCoverageItem(
              category: 'receiver stats',
              status: StreamDiagnosticCoverageStatus.missing,
              detail: 'no receiver render/decode cadence was captured',
              missingFields: [
                'receiver render FPS',
                'receiver decode FPS',
                'subscribed layer',
              ],
            ),
      summary.maxPacketLossPercent != null ||
              summary.maxRoundTripTimeMs != null ||
              summary.maxNackCount != null ||
              summary.averageAvailableOutgoingBitrateBps != null
          ? StreamDiagnosticCoverageItem(
              category: 'network/SFU',
              status: StreamDiagnosticCoverageStatus.available,
              detail:
                  'loss=${_percent(summary.maxPacketLossPercent)} RTT=${_milliseconds(summary.maxRoundTripTimeMs)} NACK=${summary.maxNackCount ?? '?'} availableOutgoing=${_bitrate(summary.averageAvailableOutgoingBitrateBps)}',
            )
          : const StreamDiagnosticCoverageItem(
              category: 'network/SFU',
              status: StreamDiagnosticCoverageStatus.missing,
              detail: 'network stats were not present in sender samples',
              missingFields: [
                'packet loss',
                'RTT',
                'NACK',
                'available outgoing bitrate',
              ],
            ),
    ];
    return StreamDiagnosticCoverageMatrix(items);
  }

  final List<StreamDiagnosticCoverageItem> items;

  List<String> get missingFields {
    final fields = <String>{};
    for (final item in items) {
      if (item.status == StreamDiagnosticCoverageStatus.missing ||
          item.status == StreamDiagnosticCoverageStatus.unavailable) {
        fields.addAll(item.missingFields);
      }
    }
    return fields.toList(growable: false)..sort();
  }

  Map<String, Object?> toJson() {
    return {
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'missingFields': missingFields,
    };
  }

  String toMarkdownTable() {
    final buffer = StringBuffer()
      ..writeln('| Category | Status | Detail | Missing Fields |')
      ..writeln('| --- | --- | --- | --- |');
    for (final item in items) {
      buffer.writeln(
        '| ${_markdownCell(item.category)} '
        '| ${item.markdownMarker} ${item.statusName} '
        '| ${_markdownCell(item.detail)} '
        '| ${_markdownCell(item.missingFields.isEmpty ? 'none' : item.missingFields.join(', '))} |',
      );
    }
    return buffer.toString();
  }

  static List<StreamDiagnosticCoverageItem> _mergePerPresetCoverage(
    List<StreamDiagnosticCoverageMatrix> matrices,
  ) {
    if (matrices.isEmpty) {
      return const [
        StreamDiagnosticCoverageItem(
          category: 'sender stats',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: 'no preset results were generated',
          missingFields: ['preset result'],
        ),
      ];
    }
    final categories = <String>[];
    for (final matrix in matrices) {
      for (final item in matrix.items) {
        if (item.category == 'requested settings') {
          continue;
        }
        if (!categories.contains(item.category)) {
          categories.add(item.category);
        }
      }
    }
    return categories.map((category) {
      final categoryItems = matrices
          .expand((matrix) => matrix.items)
          .where((item) => item.category == category)
          .toList(growable: false);
      final status = _aggregateStatus(categoryItems);
      final missing = categoryItems
          .expand((item) => item.missingFields)
          .toSet()
          .toList(growable: false)
        ..sort();
      final counts = <String, int>{};
      for (final item in categoryItems) {
        counts[item.statusName] = (counts[item.statusName] ?? 0) + 1;
      }
      final detail = counts.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
      return StreamDiagnosticCoverageItem(
        category: category,
        status: status,
        detail: detail,
        missingFields: missing,
      );
    }).toList(growable: false);
  }

  static StreamDiagnosticCoverageStatus _aggregateStatus(
    List<StreamDiagnosticCoverageItem> items,
  ) {
    if (items.any(
      (item) => item.status == StreamDiagnosticCoverageStatus.missing,
    )) {
      return StreamDiagnosticCoverageStatus.missing;
    }
    if (items.any(
      (item) => item.status == StreamDiagnosticCoverageStatus.unavailable,
    )) {
      return StreamDiagnosticCoverageStatus.unavailable;
    }
    if (items.any(
      (item) => item.status == StreamDiagnosticCoverageStatus.available,
    )) {
      return StreamDiagnosticCoverageStatus.available;
    }
    return StreamDiagnosticCoverageStatus.notApplicable;
  }

  static StreamDiagnosticCoverageItem _gameCaptureTestTargetCoverage(
    StreamTestRunResult result,
  ) {
    final config = result.config.gameCaptureTestTarget;
    final target = result.gameCaptureTestTargetResult;
    if (config?.enabled != true) {
      return const StreamDiagnosticCoverageItem(
        category: 'game-capture test target',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'deterministic D3D11 capture target was not requested',
      );
    }
    if (target == null) {
      return const StreamDiagnosticCoverageItem(
        category: 'game-capture test target',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'capture target was requested but no launch result was saved',
        missingFields: ['target launch result'],
      );
    }
    if (target.hasDiagnostics) {
      return StreamDiagnosticCoverageItem(
        category: 'game-capture test target',
        status: StreamDiagnosticCoverageStatus.available,
        detail: 'present=${_number(target.presentFps)}fps '
            'p95=${_milliseconds(target.presentGapP95Ms)} '
            'max=${_milliseconds(target.presentGapMaxMs)}',
      );
    }
    if (target.status == 'unavailable' || target.status == 'notApplicable') {
      return StreamDiagnosticCoverageItem(
        category: 'game-capture test target',
        status: StreamDiagnosticCoverageStatus.unavailable,
        detail: target.reason ?? target.status,
        missingFields: const ['capture-target diagnostics'],
      );
    }
    return const StreamDiagnosticCoverageItem(
      category: 'game-capture test target',
      status: StreamDiagnosticCoverageStatus.missing,
      detail: 'capture target launched but diagnostics were not readable',
      missingFields: ['capture-target.json'],
    );
  }

  static StreamDiagnosticCoverageItem _gameCaptureProbeCoverage(
    StreamTestRunResult result,
  ) {
    final config = result.config.gameCaptureProbe;
    final probe = result.gameCaptureProbeResult;
    if (config?.enabled != true) {
      return const StreamDiagnosticCoverageItem(
        category: 'game-capture probe',
        status: StreamDiagnosticCoverageStatus.notApplicable,
        detail: 'D3D11 local game-capture probe was not requested',
      );
    }
    if (probe == null) {
      return const StreamDiagnosticCoverageItem(
        category: 'game-capture probe',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'game-capture probe was requested but no result was produced',
        missingFields: ['game-capture probe result'],
      );
    }
    switch (probe.status) {
      case StreamDiagnosticCoverageStatus.available:
        if (config?.hostTextureConsumerEnabled == true &&
            !probe.hasHostConsumerEvidence) {
          return StreamDiagnosticCoverageItem(
            category: 'game-capture probe',
            status: StreamDiagnosticCoverageStatus.missing,
            detail:
                '${probe.summaryLabel}; host shared-texture consumer missing',
            missingFields: const ['host shared-texture consumer result'],
          );
        }
        if (config?.hostTextureConsumerEnabled == true &&
            !probe.hasHealthyHostTextureConsumer) {
          return StreamDiagnosticCoverageItem(
            category: 'game-capture probe',
            status: StreamDiagnosticCoverageStatus.unavailable,
            detail:
                '${probe.summaryLabel}; host shared-texture consumer did not '
                'open/consume frames',
            missingFields: const [
              'host opened shared texture',
              'host consumed frames',
            ],
          );
        }
        if (config?.publicationHandoffEnabled == true &&
            !probe.hasPublicationHandoffEvidence) {
          return StreamDiagnosticCoverageItem(
            category: 'game-capture probe',
            status: StreamDiagnosticCoverageStatus.missing,
            detail: '${probe.summaryLabel}; publication handoff result missing',
            missingFields: const ['publication-handoff.json'],
          );
        }
        if (config?.publicationHandoffEnabled == true &&
            !probe.hasVisiblePublicationHandoff) {
          return StreamDiagnosticCoverageItem(
            category: 'game-capture probe',
            status: StreamDiagnosticCoverageStatus.unavailable,
            detail:
                '${probe.summaryLabel}; publication handoff did not produce '
                'visible scaled frames',
            missingFields: const [
              'publication handoff opened shared texture',
              'publication handoff output frames',
              'publication handoff visible frames',
            ],
          );
        }
        return StreamDiagnosticCoverageItem(
          category: 'game-capture probe',
          status: StreamDiagnosticCoverageStatus.available,
          detail: probe.summaryLabel,
        );
      case StreamDiagnosticCoverageStatus.missing:
        return StreamDiagnosticCoverageItem(
          category: 'game-capture probe',
          status: StreamDiagnosticCoverageStatus.missing,
          detail: probe.reason,
          missingFields: const ['game-capture metadata.json'],
        );
      case StreamDiagnosticCoverageStatus.unavailable:
        return StreamDiagnosticCoverageItem(
          category: 'game-capture probe',
          status: StreamDiagnosticCoverageStatus.unavailable,
          detail: probe.reason,
          missingFields: const [
            'D3D11 helper attach result',
            'game-capture metadata.json',
          ],
        );
      case StreamDiagnosticCoverageStatus.notApplicable:
        return StreamDiagnosticCoverageItem(
          category: 'game-capture probe',
          status: StreamDiagnosticCoverageStatus.notApplicable,
          detail: probe.reason,
        );
    }
  }

  static StreamDiagnosticCoverageItem _loadedLibwebrtcArtifactCoverage(
    StreamTestRunResult result,
  ) {
    final artifact = result.loadedLibwebrtcArtifact;
    if (artifact == null) {
      return const StreamDiagnosticCoverageItem(
        category: 'loaded libwebrtc hash',
        status: StreamDiagnosticCoverageStatus.unavailable,
        detail:
            'the stream-test report does not expose the loaded libwebrtc artifact hash',
        missingFields: ['loaded libwebrtc artifact identity'],
      );
    }
    return StreamDiagnosticCoverageItem(
      category: 'loaded libwebrtc hash',
      status: StreamDiagnosticCoverageStatus.available,
      detail: artifact.diagnosticLabel,
    );
  }

  static StreamDiagnosticCoverageItem _hostLoadCoverage(
    StreamTestRunResult result,
  ) {
    final hostLoad = result.hostLoadReport;
    if (hostLoad == null) {
      return const StreamDiagnosticCoverageItem(
        category: 'host/system load',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: 'stream-test host load sampler did not run',
        missingFields: [
          'system CPU percent',
          'system memory percent',
          'GPU utilization percent',
        ],
      );
    }
    if (!hostLoad.available) {
      return StreamDiagnosticCoverageItem(
        category: 'host/system load',
        status: StreamDiagnosticCoverageStatus.unavailable,
        detail: hostLoad.unavailableReason ?? 'host load samples unavailable',
        missingFields: const [
          'system CPU percent',
          'system memory percent',
          'GPU utilization percent',
        ],
      );
    }
    final missingFields = hostLoad.missingMetricLabels;
    if (!hostLoad.hasSystemCpuMemoryGpuEvidence) {
      return StreamDiagnosticCoverageItem(
        category: 'host/system load',
        status: StreamDiagnosticCoverageStatus.missing,
        detail: _hostLoadCompactLabel(hostLoad),
        missingFields: missingFields,
      );
    }
    return StreamDiagnosticCoverageItem(
      category: 'host/system load',
      status: StreamDiagnosticCoverageStatus.available,
      detail: _hostLoadCompactLabel(hostLoad),
      missingFields: missingFields,
    );
  }
}

class StreamTestNativeDiagnostics {
  const StreamTestNativeDiagnostics({
    this.captureBackendMode,
    this.observedCapturer,
    this.observedCapturerId,
    this.dirtyRegionMode,
    this.windowGdiCaptureMode,
    this.sourceType,
    this.nativeSourceWidth,
    this.nativeSourceHeight,
    this.requestedMaxWidth,
    this.requestedMaxHeight,
    this.nativeWindowRectWidth,
    this.nativeWindowRectHeight,
    this.contentWidth,
    this.contentHeight,
    this.preEncodeWidth,
    this.preEncodeHeight,
    this.canvas,
    this.cropRegion,
    this.averageNativeFps,
    this.averageSubmittedFps,
    this.targetNativeFps,
    this.averageCaptureCallMs,
    this.maxCaptureCallMs,
    this.averageSourceCaptureMs,
    this.maxSourceCaptureMs,
    this.sourceCaptureSampleCount = 0,
    this.wgcCaptureCalls = 0,
    this.wgcCaptureSuccessCount = 0,
    this.wgcSourceNotCapturableCount = 0,
    this.wgcEnsureFrameCalls = 0,
    this.wgcEnsureSleepCount = 0,
    this.wgcProcessFrameCalls = 0,
    this.wgcProcessFrameSuccessCount = 0,
    this.wgcFramePoolEmptyCount = 0,
    this.wgcFramePoolReuseCount = 0,
    this.wgcCaptureFrameNullCount = 0,
    this.wgcMappedTextureCreateCount = 0,
    this.wgcResizeCount = 0,
    this.wgcFramePoolRecreateCount = 0,
    this.averageWgcGetFrameMs,
    this.maxWgcGetFrameMs,
    this.averageWgcEnsureFrameMs,
    this.maxWgcEnsureFrameMs,
    this.averageWgcProcessFrameMs,
    this.maxWgcProcessFrameMs,
    this.averageWgcTryGetFrameMs,
    this.maxWgcTryGetFrameMs,
    this.averageWgcSurfaceMs,
    this.maxWgcSurfaceMs,
    this.averageWgcTextureMs,
    this.maxWgcTextureMs,
    this.averageWgcContentSizeMs,
    this.maxWgcContentSizeMs,
    this.averageWgcCopyTextureMs,
    this.maxWgcCopyTextureMs,
    this.averageWgcMapTextureMs,
    this.maxWgcMapTextureMs,
    this.averageWgcCopyRowsMs,
    this.maxWgcCopyRowsMs,
    this.averageWgcMonitorScaleMs,
    this.maxWgcMonitorScaleMs,
    this.averageWgcZeroHertzMs,
    this.maxWgcZeroHertzMs,
    this.gdiCaptureCalls = 0,
    this.gdiCaptureSuccessCount = 0,
    this.gdiTemporaryErrorCount = 0,
    this.gdiPermanentErrorCount = 0,
    this.gdiHiddenOrMinimizedCount = 0,
    this.gdiRectFailCount = 0,
    this.gdiDcFailCount = 0,
    this.gdiFrameCreateFailCount = 0,
    this.gdiPrintFullCallCount = 0,
    this.gdiPrintFullSuccessCount = 0,
    this.gdiPrintFallbackCallCount = 0,
    this.gdiPrintFallbackSuccessCount = 0,
    this.gdiBitBltCallCount = 0,
    this.gdiBitBltSuccessCount = 0,
    this.gdiFinalPrintFullCount = 0,
    this.gdiFinalPrintFallbackCount = 0,
    this.gdiFinalBitBltCount = 0,
    this.gdiFinalNoneCount = 0,
    this.gdiBlackFrameCount = 0,
    this.gdiLowVarianceFrameCount = 0,
    this.gdiOwnedWindowFrameCount = 0,
    this.gdiOwnedWindowCaptureCallCount = 0,
    this.gdiOwnedWindowCaptureSuccessCount = 0,
    this.gdiOriginalWidth,
    this.gdiOriginalHeight,
    this.gdiCroppedWidth,
    this.gdiCroppedHeight,
    this.gdiFrameWidth,
    this.gdiFrameHeight,
    this.averageGdiTotalMs,
    this.maxGdiTotalMs,
    this.averageGdiRectMs,
    this.maxGdiRectMs,
    this.averageGdiVisibilityMs,
    this.maxGdiVisibilityMs,
    this.averageGdiGetDcMs,
    this.maxGdiGetDcMs,
    this.averageGdiGetDcSizeMs,
    this.maxGdiGetDcSizeMs,
    this.averageGdiCreateFrameMs,
    this.maxGdiCreateFrameMs,
    this.averageGdiMemDcMs,
    this.maxGdiMemDcMs,
    this.averageGdiPrintFullMs,
    this.maxGdiPrintFullMs,
    this.averageGdiPrintFallbackMs,
    this.maxGdiPrintFallbackMs,
    this.averageGdiBitBltMs,
    this.maxGdiBitBltMs,
    this.averageGdiCleanupMs,
    this.maxGdiCleanupMs,
    this.averageGdiCropMs,
    this.maxGdiCropMs,
    this.averageGdiOwnedEnumMs,
    this.maxGdiOwnedEnumMs,
    this.averageGdiOwnedCaptureMs,
    this.maxGdiOwnedCaptureMs,
    this.averageGdiOwnedCompositeMs,
    this.maxGdiOwnedCompositeMs,
    this.averageCallbackEntryDelayMs,
    this.maxCallbackEntryDelayMs,
    this.averageCaptureResultCallbackMs,
    this.maxCaptureResultCallbackMs,
    this.averageCaptureAcquireWaitMs,
    this.maxCaptureAcquireWaitMs,
    this.averagePostCallbackWaitMs,
    this.maxPostCallbackWaitMs,
    this.averageUnaccountedWaitMs,
    this.maxUnaccountedWaitMs,
    this.captureResultCallbackCount = 0,
    this.maxFrameIntervalMs,
    this.p95FrameIntervalMs,
    this.captureWaitTimeoutCount = 0,
    this.capturePermanentErrorCount = 0,
    this.duplicatedFrameCount = 0,
    this.staleFrameReuseCount = 0,
    this.averageFrameConvertMs,
    this.averageFrameScaleMs,
    this.averageFrameOnFrameMs,
    this.averageFrameCallbackMs,
    this.maxFrameCallbackMs,
    this.updatedRegionEmptyCount = 0,
    this.updatedRegionNonEmptyCount = 0,
    this.updatedRegionRectCount = 0,
    this.updatedRegionMaxRectCount = 0,
    this.averageUpdatedRegionAreaRatio,
    this.maxUpdatedRegionAreaRatio,
    this.averageUpdatedRegionAnalysisMs,
    this.maxUpdatedRegionAnalysisMs,
    this.updatedRegionFullFrameCount = 0,
    this.updatedRegionTinyFrameCount = 0,
    this.latestFramePacerEnabled,
    this.averagePacerSubmittedFps,
    this.averagePacerUniqueFps,
    this.p95PacerIntervalMs,
    this.maxPacerIntervalMs,
    this.averagePacerFrameAgeMs,
    this.maxPacerFrameAgeMs,
    this.averagePacerOnFrameMs,
    this.maxPacerOnFrameMs,
    this.pacerDuplicateSubmitCount = 0,
    this.pacerOverwrittenFrameCount = 0,
    this.pacerSkippedTickCount = 0,
    this.gameCaptureSourceWidth,
    this.gameCaptureSourceHeight,
    this.gameCaptureOutputWidth,
    this.gameCaptureOutputHeight,
    this.gameCaptureFormat,
    this.gameCaptureBackendContractVersion,
    this.gameCaptureSourceMode,
    this.gameCaptureSourceApi,
    this.gameCaptureSourceApiId,
    this.gameCaptureSourceFormat,
    this.gameCaptureSourceFormatId,
    this.gameCaptureColorSpace,
    this.gameCaptureSyncKind,
    this.gameCaptureReadyState,
    this.gameCaptureFailureReason,
    this.gameCaptureConsumerAdapterLuid,
    this.gameCaptureConsumerAdapterVendorId,
    this.gameCaptureConsumerAdapterDeviceId,
    this.gameCaptureSourceAdapterLuid,
    this.gameCaptureCrossAdapterSuspected,
    this.averageGameCaptureFps,
    this.gameCaptureSubmittedFrames = 0,
    this.gameCaptureRepeatedFrames = 0,
    this.gameCaptureDuplicateSkippedFrames = 0,
    this.gameCaptureDeliveryQueuedFrames = 0,
    this.gameCaptureDeliverySubmittedFrames = 0,
    this.gameCaptureDeliveryOverwrittenFrames = 0,
    this.gameCaptureDeliveryPacerResyncs = 0,
    this.gameCaptureDeliveryPacerLagMaxMs = 0,
    this.gameCaptureDeliveryRepeatNoQueuedFrames = 0,
    this.gameCaptureDeliverySkipNoQueuedFrames = 0,
    this.gameCaptureDeliveryFreshWakeAfterSkipFrames = 0,
    this.gameCaptureDeliveryFreshImmediateFrames = 0,
    this.gameCaptureDeliveryRepeatPolicy,
    this.gameCaptureDeliveryQueueDepth,
    this.averageGameCaptureDeliveryRepeatSourceAgeMs,
    this.maxGameCaptureDeliveryRepeatSourceAgeMs,
    this.gameCaptureDeliveryRepeatSourceAgeSamples = 0,
    this.averageGameCaptureDeliveryOnFrameMs,
    this.maxGameCaptureDeliveryOnFrameMs,
    this.averageGameCaptureDeliverySubmitPrepMs,
    this.maxGameCaptureDeliverySubmitPrepMs,
    this.gameCaptureDeliverySubmitPrepSamples = 0,
    this.averageGameCaptureDeliveryOnFrameCallMs,
    this.maxGameCaptureDeliveryOnFrameCallMs,
    this.gameCaptureDeliveryOnFrameCallSamples = 0,
    this.averageGameCaptureDeliveryPostOnFrameMs,
    this.maxGameCaptureDeliveryPostOnFrameMs,
    this.gameCaptureDeliveryPostOnFrameSamples = 0,
    this.averageGameCaptureNativeBufferReleaseMs,
    this.maxGameCaptureNativeBufferReleaseMs,
    this.gameCaptureNativeBufferReleaseSamples = 0,
    this.averageGameCaptureReadyToQueueMs,
    this.maxGameCaptureReadyToQueueMs,
    this.gameCaptureReadyToQueueSamples = 0,
    this.averageGameCaptureDeliveryQueueWaitMs,
    this.maxGameCaptureDeliveryQueueWaitMs,
    this.gameCaptureDeliveryQueueWaitSamples = 0,
    this.averageGameCaptureDeliveryOverwriteAgeMs,
    this.maxGameCaptureDeliveryOverwriteAgeMs,
    this.gameCaptureDeliveryOverwriteAgeSamples = 0,
    this.gameCaptureDeliveryOverwrittenFreshFrames = 0,
    this.averageGameCaptureReadyToSubmitMs,
    this.maxGameCaptureReadyToSubmitMs,
    this.gameCaptureReadyToSubmitSamples = 0,
    this.averageGameCaptureSourceToSubmitMs,
    this.maxGameCaptureSourceToSubmitMs,
    this.gameCaptureSourceToSubmitSamples = 0,
    this.averageGameCaptureSourceToReadbackReadyMs,
    this.maxGameCaptureSourceToReadbackReadyMs,
    this.gameCaptureSourceToReadbackReadySamples = 0,
    this.averageGameCaptureReadbackQueueToMapMs,
    this.maxGameCaptureReadbackQueueToMapMs,
    this.gameCaptureReadbackQueueToMapSamples = 0,
    this.averageGameCaptureMapToI420Ms,
    this.maxGameCaptureMapToI420Ms,
    this.gameCaptureMapToI420Samples = 0,
    this.averageGameCaptureSourceToI420ReadyMs,
    this.maxGameCaptureSourceToI420ReadyMs,
    this.gameCaptureSourceToI420ReadySamples = 0,
    this.averageGameCaptureSourceToQueueMs,
    this.maxGameCaptureSourceToQueueMs,
    this.gameCaptureSourceToQueueSamples = 0,
    this.averageGameCaptureSourceDuplicateSkipAgeMs,
    this.maxGameCaptureSourceDuplicateSkipAgeMs,
    this.gameCaptureSourceDuplicateSkipAgeSamples = 0,
    this.gameCaptureCopiedFrames = 0,
    this.gameCaptureDroppedFrames = 0,
    this.gameCaptureOverwrittenFrames = 0,
    this.gameCaptureGpuScaledFrames = 0,
    this.gameCaptureGpuScaleFailures = 0,
    this.gameCaptureCpuFallbackFrames = 0,
    this.gameCaptureNativeNv12SubmittedFrames = 0,
    this.gameCaptureNativeNv12QueuedFrames = 0,
    this.gameCaptureNativeNv12ReadyFrames = 0,
    this.gameCaptureNativeNv12NotReadyPolls = 0,
    this.gameCaptureNativeNv12ReadyPolicy,
    this.gameCaptureNativeNv12FenceAvailable,
    this.gameCaptureNativeNv12PendingPollMs,
    this.gameCaptureNativeNv12MaxPendingSlots,
    this.gameCaptureNativeNv12ReadyDrainDepth,
    this.gameCaptureNativeNv12FrameOwnership,
    this.gameCaptureNativeNv12FenceSignaledFrames = 0,
    this.gameCaptureNativeNv12FenceReadyFrames = 0,
    this.gameCaptureNativeNv12FenceSignalFailures = 0,
    this.gameCaptureNativeNv12OwnedCopies = 0,
    this.averageGameCaptureNativeNv12OwnedCopyMs,
    this.maxGameCaptureNativeNv12OwnedCopyMs,
    this.gameCaptureNativeNv12OwnedCopySamples = 0,
    this.gameCaptureNativeNv12OverwrittenFrames = 0,
    this.averageGameCaptureNativeNv12OverwriteAgeMs,
    this.maxGameCaptureNativeNv12OverwriteAgeMs,
    this.gameCaptureNativeNv12OverwriteAgeSamples = 0,
    this.gameCaptureNativeNv12OverwrittenFreshFrames = 0,
    this.gameCaptureNativeNv12ReadyDroppedFrames = 0,
    this.averageGameCaptureNativeNv12ReadyDropAgeMs,
    this.maxGameCaptureNativeNv12ReadyDropAgeMs,
    this.gameCaptureNativeNv12ReadyDropAgeSamples = 0,
    this.gameCaptureNativeNv12ReadyDroppedFreshFrames = 0,
    this.gameCaptureNativeNv12Failures = 0,
    this.averageGameCaptureNativeNv12ConvertMs,
    this.maxGameCaptureNativeNv12ConvertMs,
    this.gameCaptureNativeNv12ConvertSamples = 0,
    this.averageGameCaptureNativeNv12BgraScaleDrawMs,
    this.maxGameCaptureNativeNv12BgraScaleDrawMs,
    this.gameCaptureNativeNv12BgraScaleDrawSamples = 0,
    this.averageGameCaptureNativeNv12VideoProcessorBltSubmitMs,
    this.maxGameCaptureNativeNv12VideoProcessorBltSubmitMs,
    this.gameCaptureNativeNv12VideoProcessorBltSubmitSamples = 0,
    this.averageGameCaptureNativeNv12VideoProcessorBltToReadyMs,
    this.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs,
    this.gameCaptureNativeNv12VideoProcessorBltToReadySamples = 0,
    this.averageGameCaptureNativeNv12BufferCreateMs,
    this.maxGameCaptureNativeNv12BufferCreateMs,
    this.gameCaptureNativeNv12BufferCreateSamples = 0,
    this.averageGameCaptureNativeNv12FrameReadyToQueueMs,
    this.maxGameCaptureNativeNv12FrameReadyToQueueMs,
    this.gameCaptureNativeNv12FrameReadyToQueueSamples = 0,
    this.averageGameCaptureNativeNv12ConversionStartAgeMs,
    this.maxGameCaptureNativeNv12ConversionStartAgeMs,
    this.gameCaptureNativeNv12ConversionStartAgeSamples = 0,
    this.gameCaptureNativeNv12StaleBeforeQueueFrames = 0,
    this.gameCaptureNativeNv12HandoffDisabledReason,
    this.gameCaptureReadbackQueuedFrames = 0,
    this.gameCaptureReadbackReadyFrames = 0,
    this.gameCaptureReadbackNotReadyFrames = 0,
    this.gameCaptureReadbackOverwrittenFrames = 0,
    this.gameCaptureReadbackStaleDroppedFrames = 0,
    this.gameCaptureReadbackLatencyDroppedFrames = 0,
    this.gameCaptureReadbackMapAttempts = 0,
    this.gameCaptureSourceFrameIndex = 0,
    this.gameCaptureLastSubmittedSourceFrameIndex = 0,
    this.gameCaptureSourceFrameRegressions = 0,
    this.gameCaptureSourceFrameDuplicates = 0,
    this.gameCaptureSourceFrameGaps = 0,
    this.gameCaptureSharedSlotMismatches = 0,
    this.gameCaptureTimestampMode,
    this.gameCaptureTimestampSourceQpcFrames = 0,
    this.gameCaptureTimestampPacedFallbackFrames = 0,
    this.gameCaptureTimestampRepeatedFrames = 0,
    this.averageGameCaptureTimestampDeltaMs,
    this.maxGameCaptureTimestampDeltaMs,
    this.gameCaptureTimestampSamples = 0,
    this.gameCaptureTimestampAdjustments = 0,
    this.averageGameCaptureDeliveryWallDeltaMs,
    this.maxGameCaptureDeliveryWallDeltaMs,
    this.minGameCaptureDeliveryWallDeltaMs,
    this.gameCaptureDeliveryWallSamples = 0,
    this.gameCaptureDeliveryWallOver2xFrames = 0,
    this.gameCaptureDeliveryWallOver3xFrames = 0,
    this.gameCaptureDeliveryWallUnderHalfFrames = 0,
    this.averageGameCaptureSourceQpcDeltaMs,
    this.maxGameCaptureSourceQpcDeltaMs,
    this.gameCaptureSourceQpcSamples = 0,
    this.gameCaptureSourceQpcRegressions = 0,
    this.averageGameCaptureCopyMs,
    this.averageGameCaptureMapMs,
    this.averageGameCaptureConvertMs,
    this.averageGameCaptureGpuScaleMs,
    this.averageGameCaptureReadbackLatencyMs,
    this.averageGameCaptureReadbackLatencyFrames,
    this.gameCaptureMaxReadbackLatencyFrames = 0,
    this.gameCaptureMapFailures = 0,
    this.gameCaptureConvertFailures = 0,
    this.gameCaptureProofFrames = 0,
    this.gameCaptureVisibleProofFrames = 0,
    this.gameCaptureProofVisible,
    this.gameCaptureProofPath,
    this.gameCaptureProofMinLuma,
    this.gameCaptureProofMaxLuma,
    this.gameCaptureProofNonzeroSamples,
    this.gameCaptureProofSamples,
    this.gameCaptureI420ProofFrames = 0,
    this.gameCaptureVisibleI420ProofFrames = 0,
    this.gameCaptureInitialBlackSkippedFrames = 0,
    this.gameCaptureVisibleSourceSeen,
    this.gameCaptureI420ProofVisible,
    this.gameCaptureI420ProofPath,
    this.gameCaptureI420ProofMinLuma,
    this.gameCaptureI420ProofMaxLuma,
    this.gameCaptureI420ProofNonzeroSamples,
    this.gameCaptureI420ProofSamples,
    this.averageEncoderTotalMs,
    this.maxEncoderTotalMs,
    this.encoderSlowFrameCount = 0,
    this.encoderSampleCount = 0,
    this.encoderInputPaths = const [],
    this.encoderNativeInputFrames = 0,
    this.encoderCpuI420InputFrames = 0,
    this.encoderNativeSampleFailures = 0,
    this.encoderNativeSuspendedFrames = 0,
    this.encoderNativeReadyFenceFrames = 0,
    this.encoderNativeReadyFenceTimeoutFrames = 0,
    this.averageEncoderNativeReadyFenceWaitMs,
    this.maxEncoderNativeReadyFenceWaitMs,
    this.encoderNativeReadyFenceWaitSamples = 0,
    this.encoderNativeSourceMode,
    this.encoderNativeSourceFormat,
    this.encoderNativeSourceFrameIndex = 0,
    this.averageEncoderNativeSourceAgeMs,
    this.maxEncoderNativeSourceAgeMs,
    this.encoderNativeSourceAgeSamples = 0,
    this.averageEncoderNativeSourceAgeAtCreateMs,
    this.maxEncoderNativeSourceAgeAtCreateMs,
    this.averageEncoderNativeBufferAgeMs,
    this.maxEncoderNativeBufferAgeMs,
    this.encoderNativeBufferAgeSamples = 0,
    this.averageEncoderNativeSampleLifetimeMs,
    this.maxEncoderNativeSampleLifetimeMs,
    this.encoderNativeSampleLifetimeSamples = 0,
    this.encoderNativeAdapterLuid,
    this.encoderNativeAdapterVendorId,
    this.encoderNativeAdapterDeviceId,
    this.averageEncoderProcessInputMs,
    this.maxEncoderProcessInputMs,
    this.encoderProcessInputSamples = 0,
    this.averageEncoderProcessOutputMs,
    this.maxEncoderProcessOutputMs,
    this.encoderProcessOutputSamples = 0,
    this.averageEncoderEncodedCallbackMs,
    this.maxEncoderEncodedCallbackMs,
    this.encoderEncodedCallbackSamples = 0,
    this.averageEncoderEncodedCallbackQueueWaitMs,
    this.maxEncoderEncodedCallbackQueueWaitMs,
    this.encoderEncodedCallbackQueueWaitSamples = 0,
    this.averageEncoderEncodedCallbackEnqueueMs,
    this.maxEncoderEncodedCallbackEnqueueMs,
    this.encoderEncodedCallbackEnqueueSamples = 0,
    this.encoderEncodedCallbackAsyncFrames = 0,
    this.encoderMaxEncodedCallbackQueueDepth = 0,
    this.encoderMaxEncodedCallbackDrops = 0,
    this.encoderMaxEncodedCallbackOutputs = 0,
    this.encoderStages = const [],
    this.encoderOutputFrames = 0,
    this.encoderOutputBytes = 0,
    this.encoderMaxQueueDepth = 0,
    this.encoderMaxRetainedSamples = 0,
    this.encoderMaxEncodedOutputs = 0,
    this.averageWebrtcSourceOnFrameMs,
    this.maxWebrtcSourceOnFrameMs,
    this.webrtcSourceOnFrameSamples = 0,
    this.averageWebrtcSourceAdaptMs,
    this.maxWebrtcSourceAdaptMs,
    this.averageWebrtcSourceScaleMs,
    this.maxWebrtcSourceScaleMs,
    this.averageWebrtcSourceBroadcastMs,
    this.maxWebrtcSourceBroadcastMs,
    this.webrtcSourceAdapterDrops = 0,
    this.webrtcSourceScaledFrames = 0,
    this.averageWebrtcVideoBroadcasterMs,
    this.maxWebrtcVideoBroadcasterMs,
    this.webrtcVideoBroadcasterSamples = 0,
    this.averageWebrtcVideoBroadcasterLockWaitMs,
    this.maxWebrtcVideoBroadcasterLockWaitMs,
    this.averageWebrtcVideoBroadcasterSinkDispatchMs,
    this.maxWebrtcVideoBroadcasterSinkDispatchMs,
    this.maxWebrtcVideoBroadcasterSingleSinkMs,
    this.webrtcVideoBroadcasterSlowSinkId,
    this.webrtcVideoBroadcasterSlowSinkMs,
    this.webrtcVideoBroadcasterSlowSinkLabel,
    this.webrtcVideoBroadcasterSlowestSinkId,
    this.webrtcVideoBroadcasterSlowestSinkMs,
    this.webrtcVideoBroadcasterSlowestSinkAverageMs,
    this.webrtcVideoBroadcasterSlowestSinkFrames = 0,
    this.webrtcVideoBroadcasterSlowestSinkLabel,
    this.webrtcVideoBroadcasterSinkCount = 0,
    this.webrtcVideoBroadcasterMaxSinkCount = 0,
    this.webrtcVideoBroadcasterActiveSinks = 0,
    this.webrtcVideoBroadcasterInactiveSinks = 0,
    this.webrtcVideoBroadcasterRequestedSinks = 0,
    this.webrtcVideoBroadcasterBlackFrameSinks = 0,
    this.webrtcVideoBroadcasterRotationAppliedSinks = 0,
    this.webrtcVideoBroadcasterInactiveNativeSinkBypassReported = false,
    this.webrtcVideoBroadcasterInactiveNativeSinksBypassed = 0,
    this.webrtcVideoBroadcasterInactiveNativeSinksBypassedLast = 0,
    this.webrtcVideoBroadcasterSinkRoster,
    this.webrtcVideoBroadcasterBlackSinks = 0,
    this.webrtcVideoBroadcasterRotationDiscards = 0,
    this.webrtcVideoBroadcasterUpdateRectCleared = 0,
    this.webrtcVideoBroadcasterDiscardedFrames = 0,
    this.averageWebrtcVsePostToOnFrameMs,
    this.maxWebrtcVsePostToOnFrameMs,
    this.averageWebrtcVseOnFrameMs,
    this.maxWebrtcVseOnFrameMs,
    this.webrtcVseOnFrameSamples = 0,
    this.webrtcVseQueueOverloadDrops = 0,
    this.webrtcVseEncoderQueueDrops = 0,
    this.webrtcVseCwndDrops = 0,
    this.webrtcVseBadTimestampDrops = 0,
    this.averageWebrtcVseMaybeEncodeMs,
    this.maxWebrtcVseMaybeEncodeMs,
    this.webrtcVseMaybeEncodeSamples = 0,
    this.webrtcVsePendingReplacedDrops = 0,
    this.webrtcVseSizeDrops = 0,
    this.webrtcVsePausedDrops = 0,
    this.webrtcVseMediaOptimizationDrops = 0,
    this.averageWebrtcVseEncodeFrameMs,
    this.maxWebrtcVseEncodeFrameMs,
    this.webrtcVseEncodeFrameSamples = 0,
    this.averageWebrtcVideoEncoderEncodeMs,
    this.maxWebrtcVideoEncoderEncodeMs,
    this.webrtcVideoEncoderEncodeSamples = 0,
    this.webrtcVseEncodeFailures = 0,
    this.webrtcVseEncodeSkippedBeforeEncoder = 0,
  });

  factory StreamTestNativeDiagnostics.fromMarkers(List<String> markers) {
    markers = _expandDiagnosticLogMarkerLines(markers);
    String? captureBackendMode;
    String? observedCapturer;
    int? observedCapturerId;
    String? dirtyRegionMode;
    String? windowGdiCaptureMode;
    String? sourceType;
    int? nativeSourceWidth;
    int? nativeSourceHeight;
    int? requestedMaxWidth;
    int? requestedMaxHeight;
    int? nativeWindowRectWidth;
    int? nativeWindowRectHeight;
    int? contentWidth;
    int? contentHeight;
    int? preEncodeWidth;
    int? preEncodeHeight;
    String? canvas;
    bool? cropRegion;
    final nativeFpsValues = <double>[];
    final submittedFpsValues = <double>[];
    final targetFpsValues = <double>[];
    final captureCallValues = <double>[];
    final maxCaptureCallValues = <double>[];
    final sourceCaptureValues = <double>[];
    var sourceCaptureWeightedTotalMs = 0.0;
    var sourceCaptureWeightedSampleCount = 0;
    final maxSourceCaptureValues = <double>[];
    final callbackEntryDelayValues = <double>[];
    final maxCallbackEntryDelayValues = <double>[];
    final captureResultCallbackValues = <double>[];
    final maxCaptureResultCallbackValues = <double>[];
    final captureAcquireWaitValues = <double>[];
    final maxCaptureAcquireWaitValues = <double>[];
    final postCallbackWaitValues = <double>[];
    final maxPostCallbackWaitValues = <double>[];
    final unaccountedWaitValues = <double>[];
    final maxUnaccountedWaitValues = <double>[];
    final maxFrameIntervalValues = <double>[];
    final p95FrameIntervalValues = <double>[];
    final frameConvertValues = <double>[];
    final frameScaleValues = <double>[];
    final frameOnFrameValues = <double>[];
    final frameCallbackValues = <double>[];
    final maxFrameCallbackValues = <double>[];
    bool? latestFramePacerEnabled;
    final pacerSubmittedFpsValues = <double>[];
    final pacerUniqueFpsValues = <double>[];
    final p95PacerIntervalValues = <double>[];
    final maxPacerIntervalValues = <double>[];
    final pacerFrameAgeValues = <double>[];
    final maxPacerFrameAgeValues = <double>[];
    final pacerOnFrameValues = <double>[];
    final maxPacerOnFrameValues = <double>[];
    final encoderTotalValues = <double>[];
    var encoderSlowFrameCount = 0;
    final encoderInputPaths = <String>{};
    var encoderNativeInputFrames = 0;
    var encoderCpuI420InputFrames = 0;
    var encoderNativeSampleFailures = 0;
    var encoderNativeSuspendedFrames = 0;
    var encoderNativeReadyFenceFrames = 0;
    var encoderNativeReadyFenceTimeoutFrames = 0;
    final encoderNativeReadyFenceWaitValues = <double>[];
    String? encoderNativeSourceMode;
    int? encoderNativeSourceFormat;
    var encoderNativeSourceFrameIndex = 0;
    final encoderNativeSourceAgeValues = <double>[];
    final encoderNativeSourceAgeAtCreateValues = <double>[];
    final encoderNativeBufferAgeValues = <double>[];
    final encoderNativeSampleLifetimeValues = <double>[];
    final encoderNativeSampleLifetimeMaxValues = <double>[];
    var encoderNativeSampleLifetimeSamples = 0;
    String? encoderNativeAdapterLuid;
    int? encoderNativeAdapterVendorId;
    int? encoderNativeAdapterDeviceId;
    final encoderProcessInputValues = <double>[];
    final encoderProcessOutputValues = <double>[];
    final encoderEncodedCallbackValues = <double>[];
    final encoderEncodedCallbackQueueWaitValues = <double>[];
    final encoderEncodedCallbackEnqueueValues = <double>[];
    var encoderEncodedCallbackAsyncFrames = 0;
    var encoderMaxEncodedCallbackQueueDepth = 0;
    var encoderMaxEncodedCallbackDrops = 0;
    var encoderMaxEncodedCallbackOutputs = 0;
    final encoderStages = <String>{};
    var encoderOutputFrames = 0;
    var encoderOutputBytes = 0;
    var encoderMaxQueueDepth = 0;
    var encoderMaxRetainedSamples = 0;
    var encoderMaxEncodedOutputs = 0;
    final webrtcSourceOnFrameMsValues = <double>[];
    final webrtcSourceOnFrameMaxMsValues = <double>[];
    final webrtcSourceAdaptMsValues = <double>[];
    final webrtcSourceAdaptMaxMsValues = <double>[];
    final webrtcSourceScaleMsValues = <double>[];
    final webrtcSourceScaleMaxMsValues = <double>[];
    final webrtcSourceBroadcastMsValues = <double>[];
    final webrtcSourceBroadcastMaxMsValues = <double>[];
    var webrtcSourceOnFrameSamples = 0;
    var webrtcSourceAdapterDrops = 0;
    var webrtcSourceScaledFrames = 0;
    final webrtcVideoBroadcasterMsValues = <double>[];
    final webrtcVideoBroadcasterMaxMsValues = <double>[];
    var webrtcVideoBroadcasterSamples = 0;
    final webrtcVideoBroadcasterLockWaitMsValues = <double>[];
    final webrtcVideoBroadcasterLockWaitMaxMsValues = <double>[];
    final webrtcVideoBroadcasterSinkDispatchMsValues = <double>[];
    final webrtcVideoBroadcasterSinkDispatchMaxMsValues = <double>[];
    final webrtcVideoBroadcasterMaxSingleSinkMsValues = <double>[];
    int? webrtcVideoBroadcasterSlowSinkId;
    double? webrtcVideoBroadcasterSlowSinkMs;
    String? webrtcVideoBroadcasterSlowSinkLabel;
    int? webrtcVideoBroadcasterSlowestSinkId;
    double? webrtcVideoBroadcasterSlowestSinkMs;
    double? webrtcVideoBroadcasterSlowestSinkAverageMs;
    var webrtcVideoBroadcasterSlowestSinkFrames = 0;
    String? webrtcVideoBroadcasterSlowestSinkLabel;
    var webrtcVideoBroadcasterSinkCount = 0;
    var webrtcVideoBroadcasterMaxSinkCount = 0;
    var webrtcVideoBroadcasterActiveSinks = 0;
    var webrtcVideoBroadcasterInactiveSinks = 0;
    var webrtcVideoBroadcasterRequestedSinks = 0;
    var webrtcVideoBroadcasterBlackFrameSinks = 0;
    var webrtcVideoBroadcasterRotationAppliedSinks = 0;
    var webrtcVideoBroadcasterInactiveNativeSinkBypassReported = false;
    var webrtcVideoBroadcasterInactiveNativeSinksBypassed = 0;
    var webrtcVideoBroadcasterInactiveNativeSinksBypassedLast = 0;
    String? webrtcVideoBroadcasterSinkRoster;
    var webrtcVideoBroadcasterBlackSinks = 0;
    var webrtcVideoBroadcasterRotationDiscards = 0;
    var webrtcVideoBroadcasterUpdateRectCleared = 0;
    var webrtcVideoBroadcasterDiscardedFrames = 0;
    final webrtcVsePostToOnFrameMsValues = <double>[];
    final webrtcVsePostToOnFrameMaxMsValues = <double>[];
    final webrtcVseOnFrameMsValues = <double>[];
    final webrtcVseOnFrameMaxMsValues = <double>[];
    var webrtcVseOnFrameSamples = 0;
    var webrtcVseQueueOverloadDrops = 0;
    var webrtcVseEncoderQueueDrops = 0;
    var webrtcVseCwndDrops = 0;
    var webrtcVseBadTimestampDrops = 0;
    final webrtcVseMaybeEncodeMsValues = <double>[];
    final webrtcVseMaybeEncodeMaxMsValues = <double>[];
    var webrtcVseMaybeEncodeSamples = 0;
    var webrtcVsePendingReplacedDrops = 0;
    var webrtcVseSizeDrops = 0;
    var webrtcVsePausedDrops = 0;
    var webrtcVseMediaOptimizationDrops = 0;
    final webrtcVseEncodeFrameMsValues = <double>[];
    final webrtcVseEncodeFrameMaxMsValues = <double>[];
    var webrtcVseEncodeFrameSamples = 0;
    final webrtcVideoEncoderEncodeMsValues = <double>[];
    final webrtcVideoEncoderEncodeMaxMsValues = <double>[];
    var webrtcVideoEncoderEncodeSamples = 0;
    var webrtcVseEncodeFailures = 0;
    var webrtcVseEncodeSkippedBeforeEncoder = 0;
    var scheduleWaitTimeoutCount = 0;
    var schedulePermanentErrorCount = 0;
    var frameWaitTimeoutCount = 0;
    var framePermanentErrorCount = 0;
    var sourceCaptureSampleCount = 0;
    var wgcCaptureCalls = 0;
    var wgcCaptureSuccessCount = 0;
    var wgcSourceNotCapturableCount = 0;
    var wgcEnsureFrameCalls = 0;
    var wgcEnsureSleepCount = 0;
    var wgcProcessFrameCalls = 0;
    var wgcProcessFrameSuccessCount = 0;
    var wgcFramePoolEmptyCount = 0;
    var wgcFramePoolReuseCount = 0;
    var wgcCaptureFrameNullCount = 0;
    var wgcMappedTextureCreateCount = 0;
    var wgcResizeCount = 0;
    var wgcFramePoolRecreateCount = 0;
    final wgcGetFrameValues = <double>[];
    final wgcMaxGetFrameValues = <double>[];
    final wgcEnsureFrameValues = <double>[];
    final wgcMaxEnsureFrameValues = <double>[];
    final wgcProcessFrameValues = <double>[];
    final wgcMaxProcessFrameValues = <double>[];
    final wgcTryGetFrameValues = <double>[];
    final wgcMaxTryGetFrameValues = <double>[];
    final wgcSurfaceValues = <double>[];
    final wgcMaxSurfaceValues = <double>[];
    final wgcTextureValues = <double>[];
    final wgcMaxTextureValues = <double>[];
    final wgcContentSizeValues = <double>[];
    final wgcMaxContentSizeValues = <double>[];
    final wgcCopyTextureValues = <double>[];
    final wgcMaxCopyTextureValues = <double>[];
    final wgcMapTextureValues = <double>[];
    final wgcMaxMapTextureValues = <double>[];
    final wgcCopyRowsValues = <double>[];
    final wgcMaxCopyRowsValues = <double>[];
    final wgcMonitorScaleValues = <double>[];
    final wgcMaxMonitorScaleValues = <double>[];
    final wgcZeroHertzValues = <double>[];
    final wgcMaxZeroHertzValues = <double>[];
    var gdiCaptureCalls = 0;
    var gdiCaptureSuccessCount = 0;
    var gdiTemporaryErrorCount = 0;
    var gdiPermanentErrorCount = 0;
    var gdiHiddenOrMinimizedCount = 0;
    var gdiRectFailCount = 0;
    var gdiDcFailCount = 0;
    var gdiFrameCreateFailCount = 0;
    var gdiPrintFullCallCount = 0;
    var gdiPrintFullSuccessCount = 0;
    var gdiPrintFallbackCallCount = 0;
    var gdiPrintFallbackSuccessCount = 0;
    var gdiBitBltCallCount = 0;
    var gdiBitBltSuccessCount = 0;
    var gdiFinalPrintFullCount = 0;
    var gdiFinalPrintFallbackCount = 0;
    var gdiFinalBitBltCount = 0;
    var gdiFinalNoneCount = 0;
    var gdiBlackFrameCount = 0;
    var gdiLowVarianceFrameCount = 0;
    var gdiOwnedWindowFrameCount = 0;
    var gdiOwnedWindowCaptureCallCount = 0;
    var gdiOwnedWindowCaptureSuccessCount = 0;
    int? gdiOriginalWidth;
    int? gdiOriginalHeight;
    int? gdiCroppedWidth;
    int? gdiCroppedHeight;
    int? gdiFrameWidth;
    int? gdiFrameHeight;
    final gdiTotalValues = <double>[];
    final gdiMaxTotalValues = <double>[];
    final gdiRectValues = <double>[];
    final gdiMaxRectValues = <double>[];
    final gdiVisibilityValues = <double>[];
    final gdiMaxVisibilityValues = <double>[];
    final gdiGetDcValues = <double>[];
    final gdiMaxGetDcValues = <double>[];
    final gdiGetDcSizeValues = <double>[];
    final gdiMaxGetDcSizeValues = <double>[];
    final gdiCreateFrameValues = <double>[];
    final gdiMaxCreateFrameValues = <double>[];
    final gdiMemDcValues = <double>[];
    final gdiMaxMemDcValues = <double>[];
    final gdiPrintFullValues = <double>[];
    final gdiMaxPrintFullValues = <double>[];
    final gdiPrintFallbackValues = <double>[];
    final gdiMaxPrintFallbackValues = <double>[];
    final gdiBitBltValues = <double>[];
    final gdiMaxBitBltValues = <double>[];
    final gdiCleanupValues = <double>[];
    final gdiMaxCleanupValues = <double>[];
    final gdiCropValues = <double>[];
    final gdiMaxCropValues = <double>[];
    final gdiOwnedEnumValues = <double>[];
    final gdiMaxOwnedEnumValues = <double>[];
    final gdiOwnedCaptureValues = <double>[];
    final gdiMaxOwnedCaptureValues = <double>[];
    final gdiOwnedCompositeValues = <double>[];
    final gdiMaxOwnedCompositeValues = <double>[];
    var captureResultCallbackCount = 0;
    var updatedRegionEmptyCount = 0;
    var updatedRegionNonEmptyCount = 0;
    var updatedRegionRectCount = 0;
    var updatedRegionMaxRectCount = 0;
    final updatedRegionAreaRatioValues = <double>[];
    var updatedRegionAreaRatioWeightedTotal = 0.0;
    var updatedRegionAreaRatioWeightedFrames = 0;
    final maxUpdatedRegionAreaRatioValues = <double>[];
    final updatedRegionAnalysisValues = <double>[];
    var updatedRegionAnalysisWeightedTotal = 0.0;
    var updatedRegionAnalysisWeightedFrames = 0;
    final maxUpdatedRegionAnalysisValues = <double>[];
    var updatedRegionFullFrameCount = 0;
    var updatedRegionTinyFrameCount = 0;
    var parsedFrameCadence = false;
    var duplicatedFrameCount = 0;
    var staleFrameReuseCount = 0;
    var pacerDuplicateSubmitCount = 0;
    var pacerOverwrittenFrameCount = 0;
    var pacerSkippedTickCount = 0;
    int? gameCaptureSourceWidth;
    int? gameCaptureSourceHeight;
    int? gameCaptureOutputWidth;
    int? gameCaptureOutputHeight;
    int? gameCaptureFormat;
    int? gameCaptureBackendContractVersion;
    String? gameCaptureSourceMode;
    String? gameCaptureSourceApi;
    int? gameCaptureSourceApiId;
    String? gameCaptureSourceFormat;
    int? gameCaptureSourceFormatId;
    String? gameCaptureColorSpace;
    String? gameCaptureSyncKind;
    String? gameCaptureReadyState;
    String? gameCaptureFailureReason;
    String? gameCaptureConsumerAdapterLuid;
    int? gameCaptureConsumerAdapterVendorId;
    int? gameCaptureConsumerAdapterDeviceId;
    String? gameCaptureSourceAdapterLuid;
    String? gameCaptureCrossAdapterSuspected;
    final gameCaptureFpsValues = <double>[];
    var gameCaptureSubmittedFrames = 0;
    var gameCaptureRepeatedFrames = 0;
    var gameCaptureDuplicateSkippedFrames = 0;
    var gameCaptureDeliveryQueuedFrames = 0;
    var gameCaptureDeliverySubmittedFrames = 0;
    var gameCaptureDeliveryOverwrittenFrames = 0;
    var gameCaptureDeliveryPacerResyncs = 0;
    var gameCaptureDeliveryPacerLagMaxMs = 0;
    var gameCaptureDeliveryRepeatNoQueuedFrames = 0;
    var gameCaptureDeliverySkipNoQueuedFrames = 0;
    var gameCaptureDeliveryFreshWakeAfterSkipFrames = 0;
    var gameCaptureDeliveryFreshImmediateFrames = 0;
    String? gameCaptureDeliveryRepeatPolicy;
    int? gameCaptureDeliveryQueueDepth;
    final gameCaptureDeliveryRepeatSourceAgeMsValues = <double>[];
    final gameCaptureDeliveryRepeatSourceAgeMaxMsValues = <double>[];
    var gameCaptureDeliveryRepeatSourceAgeSamples = 0;
    final gameCaptureDeliveryOnFrameMsValues = <double>[];
    final gameCaptureDeliveryOnFrameMaxMsValues = <double>[];
    final gameCaptureDeliverySubmitPrepMsValues = <double>[];
    final gameCaptureDeliverySubmitPrepMaxMsValues = <double>[];
    var gameCaptureDeliverySubmitPrepSamples = 0;
    final gameCaptureDeliveryOnFrameCallMsValues = <double>[];
    final gameCaptureDeliveryOnFrameCallMaxMsValues = <double>[];
    var gameCaptureDeliveryOnFrameCallSamples = 0;
    final gameCaptureDeliveryPostOnFrameMsValues = <double>[];
    final gameCaptureDeliveryPostOnFrameMaxMsValues = <double>[];
    var gameCaptureDeliveryPostOnFrameSamples = 0;
    final gameCaptureNativeBufferReleaseMsValues = <double>[];
    final gameCaptureNativeBufferReleaseMaxMsValues = <double>[];
    var gameCaptureNativeBufferReleaseSamples = 0;
    final gameCaptureReadyToQueueMsValues = <double>[];
    final gameCaptureReadyToQueueMaxMsValues = <double>[];
    var gameCaptureReadyToQueueSamples = 0;
    final gameCaptureDeliveryQueueWaitMsValues = <double>[];
    final gameCaptureDeliveryQueueWaitMaxMsValues = <double>[];
    var gameCaptureDeliveryQueueWaitSamples = 0;
    final gameCaptureDeliveryOverwriteAgeMsValues = <double>[];
    final gameCaptureDeliveryOverwriteAgeMaxMsValues = <double>[];
    var gameCaptureDeliveryOverwriteAgeSamples = 0;
    var gameCaptureDeliveryOverwrittenFreshFrames = 0;
    final gameCaptureReadyToSubmitMsValues = <double>[];
    final gameCaptureReadyToSubmitMaxMsValues = <double>[];
    var gameCaptureReadyToSubmitSamples = 0;
    final gameCaptureSourceToSubmitMsValues = <double>[];
    final gameCaptureSourceToSubmitMaxMsValues = <double>[];
    var gameCaptureSourceToSubmitSamples = 0;
    final gameCaptureSourceToReadbackReadyMsValues = <double>[];
    final gameCaptureSourceToReadbackReadyMaxMsValues = <double>[];
    var gameCaptureSourceToReadbackReadySamples = 0;
    final gameCaptureReadbackQueueToMapMsValues = <double>[];
    final gameCaptureReadbackQueueToMapMaxMsValues = <double>[];
    var gameCaptureReadbackQueueToMapSamples = 0;
    final gameCaptureMapToI420MsValues = <double>[];
    final gameCaptureMapToI420MaxMsValues = <double>[];
    var gameCaptureMapToI420Samples = 0;
    final gameCaptureSourceToI420ReadyMsValues = <double>[];
    final gameCaptureSourceToI420ReadyMaxMsValues = <double>[];
    var gameCaptureSourceToI420ReadySamples = 0;
    final gameCaptureSourceToQueueMsValues = <double>[];
    final gameCaptureSourceToQueueMaxMsValues = <double>[];
    var gameCaptureSourceToQueueSamples = 0;
    final gameCaptureSourceDuplicateSkipAgeMsValues = <double>[];
    final gameCaptureSourceDuplicateSkipAgeMaxMsValues = <double>[];
    var gameCaptureSourceDuplicateSkipAgeSamples = 0;
    var gameCaptureCopiedFrames = 0;
    var gameCaptureDroppedFrames = 0;
    var gameCaptureOverwrittenFrames = 0;
    var gameCaptureGpuScaledFrames = 0;
    var gameCaptureGpuScaleFailures = 0;
    var gameCaptureCpuFallbackFrames = 0;
    var gameCaptureNativeNv12SubmittedFrames = 0;
    var gameCaptureNativeNv12QueuedFrames = 0;
    var gameCaptureNativeNv12ReadyFrames = 0;
    var gameCaptureNativeNv12NotReadyPolls = 0;
    String? gameCaptureNativeNv12ReadyPolicy;
    bool? gameCaptureNativeNv12FenceAvailable;
    int? gameCaptureNativeNv12PendingPollMs;
    int? gameCaptureNativeNv12MaxPendingSlots;
    int? gameCaptureNativeNv12ReadyDrainDepth;
    String? gameCaptureNativeNv12FrameOwnership;
    var gameCaptureNativeNv12FenceSignaledFrames = 0;
    var gameCaptureNativeNv12FenceReadyFrames = 0;
    var gameCaptureNativeNv12FenceSignalFailures = 0;
    var gameCaptureNativeNv12OwnedCopies = 0;
    final gameCaptureNativeNv12OwnedCopyMsValues = <double>[];
    final gameCaptureNativeNv12OwnedCopyMaxMsValues = <double>[];
    var gameCaptureNativeNv12OwnedCopySamples = 0;
    var gameCaptureNativeNv12OverwrittenFrames = 0;
    final gameCaptureNativeNv12OverwriteAgeMsValues = <double>[];
    final gameCaptureNativeNv12OverwriteAgeMaxMsValues = <double>[];
    var gameCaptureNativeNv12OverwriteAgeSamples = 0;
    var gameCaptureNativeNv12OverwrittenFreshFrames = 0;
    var gameCaptureNativeNv12ReadyDroppedFrames = 0;
    final gameCaptureNativeNv12ReadyDropAgeMsValues = <double>[];
    final gameCaptureNativeNv12ReadyDropAgeMaxMsValues = <double>[];
    var gameCaptureNativeNv12ReadyDropAgeSamples = 0;
    var gameCaptureNativeNv12ReadyDroppedFreshFrames = 0;
    var gameCaptureNativeNv12Failures = 0;
    final gameCaptureNativeNv12ConvertMsValues = <double>[];
    final gameCaptureNativeNv12ConvertMaxMsValues = <double>[];
    var gameCaptureNativeNv12ConvertSamples = 0;
    final gameCaptureNativeNv12BgraScaleDrawMsValues = <double>[];
    final gameCaptureNativeNv12BgraScaleDrawMaxMsValues = <double>[];
    var gameCaptureNativeNv12BgraScaleDrawSamples = 0;
    final gameCaptureNativeNv12VideoProcessorBltSubmitMsValues = <double>[];
    final gameCaptureNativeNv12VideoProcessorBltSubmitMaxMsValues = <double>[];
    var gameCaptureNativeNv12VideoProcessorBltSubmitSamples = 0;
    final gameCaptureNativeNv12VideoProcessorBltToReadyMsValues = <double>[];
    final gameCaptureNativeNv12VideoProcessorBltToReadyMaxMsValues = <double>[];
    var gameCaptureNativeNv12VideoProcessorBltToReadySamples = 0;
    final gameCaptureNativeNv12BufferCreateMsValues = <double>[];
    final gameCaptureNativeNv12BufferCreateMaxMsValues = <double>[];
    var gameCaptureNativeNv12BufferCreateSamples = 0;
    final gameCaptureNativeNv12FrameReadyToQueueMsValues = <double>[];
    final gameCaptureNativeNv12FrameReadyToQueueMaxMsValues = <double>[];
    var gameCaptureNativeNv12FrameReadyToQueueSamples = 0;
    final gameCaptureNativeNv12ConversionStartAgeMsValues = <double>[];
    final gameCaptureNativeNv12ConversionStartAgeMaxMsValues = <double>[];
    var gameCaptureNativeNv12ConversionStartAgeSamples = 0;
    var gameCaptureNativeNv12StaleBeforeQueueFrames = 0;
    String? gameCaptureNativeNv12HandoffDisabledReason;
    var gameCaptureReadbackQueuedFrames = 0;
    var gameCaptureReadbackReadyFrames = 0;
    var gameCaptureReadbackNotReadyFrames = 0;
    var gameCaptureReadbackOverwrittenFrames = 0;
    var gameCaptureReadbackStaleDroppedFrames = 0;
    var gameCaptureReadbackLatencyDroppedFrames = 0;
    var gameCaptureReadbackMapAttempts = 0;
    var gameCaptureSourceFrameIndex = 0;
    var gameCaptureLastSubmittedSourceFrameIndex = 0;
    var gameCaptureSourceFrameRegressions = 0;
    var gameCaptureSourceFrameDuplicates = 0;
    var gameCaptureSourceFrameGaps = 0;
    var gameCaptureSharedSlotMismatches = 0;
    String? gameCaptureTimestampMode;
    var gameCaptureTimestampSourceQpcFrames = 0;
    var gameCaptureTimestampPacedFallbackFrames = 0;
    var gameCaptureTimestampRepeatedFrames = 0;
    final gameCaptureTimestampDeltaMsValues = <double>[];
    final gameCaptureTimestampDeltaMaxMsValues = <double>[];
    var gameCaptureTimestampSamples = 0;
    var gameCaptureTimestampAdjustments = 0;
    final gameCaptureDeliveryWallDeltaMsValues = <double>[];
    final gameCaptureDeliveryWallDeltaMaxMsValues = <double>[];
    final gameCaptureDeliveryWallDeltaMinMsValues = <double>[];
    var gameCaptureDeliveryWallSamples = 0;
    var gameCaptureDeliveryWallOver2xFrames = 0;
    var gameCaptureDeliveryWallOver3xFrames = 0;
    var gameCaptureDeliveryWallUnderHalfFrames = 0;
    final gameCaptureSourceQpcDeltaMsValues = <double>[];
    final gameCaptureSourceQpcDeltaMaxMsValues = <double>[];
    var gameCaptureSourceQpcSamples = 0;
    var gameCaptureSourceQpcRegressions = 0;
    final gameCaptureCopyMsValues = <double>[];
    final gameCaptureMapMsValues = <double>[];
    final gameCaptureConvertMsValues = <double>[];
    final gameCaptureGpuScaleMsValues = <double>[];
    final gameCaptureReadbackLatencyMsValues = <double>[];
    final gameCaptureReadbackLatencyFrameValues = <double>[];
    var gameCaptureMaxReadbackLatencyFrames = 0;
    var gameCaptureMapFailures = 0;
    var gameCaptureConvertFailures = 0;
    var gameCaptureProofFrames = 0;
    var gameCaptureVisibleProofFrames = 0;
    bool? gameCaptureProofVisible;
    String? gameCaptureProofPath;
    int? gameCaptureProofMinLuma;
    int? gameCaptureProofMaxLuma;
    int? gameCaptureProofNonzeroSamples;
    int? gameCaptureProofSamples;
    var gameCaptureI420ProofFrames = 0;
    var gameCaptureVisibleI420ProofFrames = 0;
    var gameCaptureInitialBlackSkippedFrames = 0;
    bool? gameCaptureVisibleSourceSeen;
    bool? gameCaptureI420ProofVisible;
    String? gameCaptureI420ProofPath;
    int? gameCaptureI420ProofMinLuma;
    int? gameCaptureI420ProofMaxLuma;
    int? gameCaptureI420ProofNonzeroSamples;
    int? gameCaptureI420ProofSamples;

    void addMarkerDouble(
      String marker,
      String key,
      List<double> values,
    ) {
      final value = _doubleFromMarker(marker, key);
      if (value != null && value >= 0) {
        values.add(value);
      }
    }

    for (final marker in markers) {
      final lowerMarker = marker.toLowerCase();
      if (lowerMarker.contains('native_nv12_encoder_handoff_disabled')) {
        observedCapturer ??= 'game-d3d11-hook';
        sourceType ??= 'game';
        gameCaptureNativeNv12HandoffDisabledReason =
            _tokenFromMarker(marker, 'reason') ??
                gameCaptureNativeNv12HandoffDisabledReason ??
                'unknown';
      }

      if (marker.toLowerCase().contains('latest-frame pacer enabled')) {
        latestFramePacerEnabled = true;
      } else if (marker.toLowerCase().contains('latest-frame pacer disabled')) {
        latestFramePacerEnabled = false;
      }

      final optionsMatch = _captureOptionsPattern.firstMatch(marker);
      if (optionsMatch != null) {
        sourceType = _stringGroup(optionsMatch, 1) ?? sourceType;
        captureBackendMode = _stringGroup(optionsMatch, 2) ??
            captureBackendMode ??
            _legacyBackendLabelFromOptions(marker);
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'window_gdi_mode') ?? windowGdiCaptureMode;
      }

      final bridgeMatch = _captureBridgePattern.firstMatch(marker);
      if (bridgeMatch != null) {
        sourceType = _stringGroup(bridgeMatch, 1) ?? sourceType;
        requestedMaxWidth = _intGroup(bridgeMatch, 2) ?? requestedMaxWidth;
        requestedMaxHeight = _intGroup(bridgeMatch, 3) ?? requestedMaxHeight;
        captureBackendMode = _stringGroup(bridgeMatch, 5) ?? captureBackendMode;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region') ?? dirtyRegionMode;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'window_gdi_mode') ?? windowGdiCaptureMode;
        final framePacing = _tokenFromMarker(marker, 'frame_pacing');
        if (framePacing != null) {
          latestFramePacerEnabled = framePacing.toLowerCase() == 'latest';
        }
      }

      final sizeMatch = _captureFrameSizePattern.firstMatch(marker);
      if (sizeMatch != null) {
        nativeSourceWidth = _intGroup(sizeMatch, 1) ?? nativeSourceWidth;
        nativeSourceHeight = _intGroup(sizeMatch, 2) ?? nativeSourceHeight;
        requestedMaxWidth = _intGroup(sizeMatch, 3) ?? requestedMaxWidth;
        requestedMaxHeight = _intGroup(sizeMatch, 4) ?? requestedMaxHeight;
        preEncodeWidth = _intGroup(sizeMatch, 5) ?? preEncodeWidth;
        preEncodeHeight = _intGroup(sizeMatch, 6) ?? preEncodeHeight;
        cropRegion = _boolGroup(sizeMatch, 7) ?? cropRegion;
        observedCapturer =
            _tokenFromMarker(marker, 'capturer') ?? observedCapturer;
        observedCapturerId =
            _intFromMarker(marker, 'capturer_id') ?? observedCapturerId;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'window_gdi_mode') ?? windowGdiCaptureMode;
      }

      if (marker.toLowerCase().contains('desktop capture frame size')) {
        observedCapturer =
            _tokenFromMarker(marker, 'capturer') ?? observedCapturer;
        observedCapturerId =
            _intFromMarker(marker, 'capturer_id') ?? observedCapturerId;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'window_gdi_mode') ?? windowGdiCaptureMode;
        final source = _dimensionsFromMarker(marker, 'source');
        nativeSourceWidth = source?.width ?? nativeSourceWidth;
        nativeSourceHeight = source?.height ?? nativeSourceHeight;
        final nativeWindowRect = _dimensionsFromMarker(marker, 'window_rect');
        nativeWindowRectWidth =
            nativeWindowRect?.width ?? nativeWindowRectWidth;
        nativeWindowRectHeight =
            nativeWindowRect?.height ?? nativeWindowRectHeight;
        final requestedMax = _dimensionsFromMarker(marker, 'max');
        requestedMaxWidth = requestedMax?.width ?? requestedMaxWidth;
        requestedMaxHeight = requestedMax?.height ?? requestedMaxHeight;
        final content = _dimensionsFromMarker(marker, 'content');
        contentWidth = content?.width ?? contentWidth;
        contentHeight = content?.height ?? contentHeight;
        final output = _dimensionsFromMarker(marker, 'output');
        preEncodeWidth = output?.width ?? preEncodeWidth;
        preEncodeHeight = output?.height ?? preEncodeHeight;
        canvas = _tokenFromMarker(marker, 'canvas') ?? canvas;
        cropRegion = _boolFromMarker(marker, 'crop_region') ?? cropRegion;
      }

      if (marker.toLowerCase().contains('desktop capture pipeline')) {
        observedCapturer =
            _tokenFromMarker(marker, 'capturer') ?? observedCapturer;
        observedCapturerId =
            _intFromMarker(marker, 'capturer_id') ?? observedCapturerId;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        final nativeSource = _dimensionsFromMarker(marker, 'native_source');
        nativeSourceWidth = nativeSource?.width ?? nativeSourceWidth;
        nativeSourceHeight = nativeSource?.height ?? nativeSourceHeight;
        final requestedMax = _dimensionsFromMarker(marker, 'requested_max');
        requestedMaxWidth = requestedMax?.width ?? requestedMaxWidth;
        requestedMaxHeight = requestedMax?.height ?? requestedMaxHeight;
        final nativeWindowRect =
            _dimensionsFromMarker(marker, 'native_window_rect');
        nativeWindowRectWidth =
            nativeWindowRect?.width ?? nativeWindowRectWidth;
        nativeWindowRectHeight =
            nativeWindowRect?.height ?? nativeWindowRectHeight;
        final content = _dimensionsFromMarker(marker, 'content');
        contentWidth = content?.width ?? contentWidth;
        contentHeight = content?.height ?? contentHeight;
        final preEncode = _dimensionsFromMarker(marker, 'pre_encode');
        preEncodeWidth = preEncode?.width ?? preEncodeWidth;
        preEncodeHeight = preEncode?.height ?? preEncodeHeight;
        final targetFps = _doubleFromMarker(marker, 'target_fps');
        final nativeFps = _doubleFromMarker(marker, 'native_fps');
        if (targetFps != null && targetFps > 0) {
          targetFpsValues.add(targetFps);
        }
        if (nativeFps != null && nativeFps > 0) {
          nativeFpsValues.add(nativeFps);
        }
        canvas = _tokenFromMarker(marker, 'canvas') ?? canvas;
        cropRegion = _boolFromMarker(marker, 'crop_region') ?? cropRegion;
      }

      if (marker.toLowerCase().contains('wgc frame timing')) {
        sourceType = _tokenFromMarker(marker, 'source_type') ?? sourceType;
        final size = _dimensionsFromMarker(marker, 'size');
        nativeSourceWidth = size?.width ?? nativeSourceWidth;
        nativeSourceHeight = size?.height ?? nativeSourceHeight;
        observedCapturer ??= 'wgc';
        wgcCaptureCalls += _intFromMarker(marker, 'calls') ?? 0;
        wgcCaptureSuccessCount += _intFromMarker(marker, 'successes') ?? 0;
        wgcSourceNotCapturableCount +=
            _intFromMarker(marker, 'source_not_capturable') ?? 0;
        wgcEnsureFrameCalls += _intFromMarker(marker, 'ensure_calls') ?? 0;
        wgcEnsureSleepCount += _intFromMarker(marker, 'ensure_sleeps') ?? 0;
        wgcProcessFrameCalls += _intFromMarker(marker, 'process_calls') ?? 0;
        wgcProcessFrameSuccessCount +=
            _intFromMarker(marker, 'process_successes') ?? 0;
        wgcFramePoolEmptyCount +=
            _intFromMarker(marker, 'frame_pool_empty') ?? 0;
        wgcFramePoolReuseCount +=
            _intFromMarker(marker, 'frame_pool_reuse') ?? 0;
        wgcCaptureFrameNullCount +=
            _intFromMarker(marker, 'capture_frame_null') ?? 0;
        wgcMappedTextureCreateCount +=
            _intFromMarker(marker, 'mapped_texture_creates') ?? 0;
        wgcResizeCount += _intFromMarker(marker, 'resizes') ?? 0;
        wgcFramePoolRecreateCount +=
            _intFromMarker(marker, 'frame_pool_recreates') ?? 0;
        addMarkerDouble(marker, 'avg_get_frame_ms', wgcGetFrameValues);
        addMarkerDouble(marker, 'max_get_frame_ms', wgcMaxGetFrameValues);
        addMarkerDouble(marker, 'avg_ensure_frame_ms', wgcEnsureFrameValues);
        addMarkerDouble(
          marker,
          'max_ensure_frame_ms',
          wgcMaxEnsureFrameValues,
        );
        addMarkerDouble(marker, 'avg_process_frame_ms', wgcProcessFrameValues);
        addMarkerDouble(
          marker,
          'max_process_frame_ms',
          wgcMaxProcessFrameValues,
        );
        addMarkerDouble(marker, 'avg_try_get_frame_ms', wgcTryGetFrameValues);
        addMarkerDouble(
          marker,
          'max_try_get_frame_ms',
          wgcMaxTryGetFrameValues,
        );
        addMarkerDouble(marker, 'avg_surface_ms', wgcSurfaceValues);
        addMarkerDouble(marker, 'max_surface_ms', wgcMaxSurfaceValues);
        addMarkerDouble(marker, 'avg_texture_ms', wgcTextureValues);
        addMarkerDouble(marker, 'max_texture_ms', wgcMaxTextureValues);
        addMarkerDouble(
          marker,
          'avg_content_size_ms',
          wgcContentSizeValues,
        );
        addMarkerDouble(
          marker,
          'max_content_size_ms',
          wgcMaxContentSizeValues,
        );
        addMarkerDouble(
          marker,
          'avg_copy_texture_ms',
          wgcCopyTextureValues,
        );
        addMarkerDouble(
          marker,
          'max_copy_texture_ms',
          wgcMaxCopyTextureValues,
        );
        addMarkerDouble(marker, 'avg_map_texture_ms', wgcMapTextureValues);
        addMarkerDouble(marker, 'max_map_texture_ms', wgcMaxMapTextureValues);
        addMarkerDouble(marker, 'avg_copy_rows_ms', wgcCopyRowsValues);
        addMarkerDouble(marker, 'max_copy_rows_ms', wgcMaxCopyRowsValues);
        addMarkerDouble(
          marker,
          'avg_monitor_scale_ms',
          wgcMonitorScaleValues,
        );
        addMarkerDouble(
          marker,
          'max_monitor_scale_ms',
          wgcMaxMonitorScaleValues,
        );
        addMarkerDouble(marker, 'avg_zero_hertz_ms', wgcZeroHertzValues);
        addMarkerDouble(marker, 'max_zero_hertz_ms', wgcMaxZeroHertzValues);
      }

      if (marker.toLowerCase().contains('window gdi frame timing')) {
        sourceType = _tokenFromMarker(marker, 'source_type') ?? sourceType;
        windowGdiCaptureMode =
            _tokenFromMarker(marker, 'capture_mode') ?? windowGdiCaptureMode;
        observedCapturer ??= 'window-gdi';
        final originalSize = _dimensionsFromMarker(marker, 'original_size');
        gdiOriginalWidth = originalSize?.width ?? gdiOriginalWidth;
        gdiOriginalHeight = originalSize?.height ?? gdiOriginalHeight;
        nativeWindowRectWidth = originalSize?.width ?? nativeWindowRectWidth;
        nativeWindowRectHeight = originalSize?.height ?? nativeWindowRectHeight;
        final croppedSize = _dimensionsFromMarker(marker, 'cropped_size');
        gdiCroppedWidth = croppedSize?.width ?? gdiCroppedWidth;
        gdiCroppedHeight = croppedSize?.height ?? gdiCroppedHeight;
        nativeSourceWidth = croppedSize?.width ?? nativeSourceWidth;
        nativeSourceHeight = croppedSize?.height ?? nativeSourceHeight;
        final frameSize = _dimensionsFromMarker(marker, 'frame_size');
        gdiFrameWidth = frameSize?.width ?? gdiFrameWidth;
        gdiFrameHeight = frameSize?.height ?? gdiFrameHeight;
        gdiCaptureCalls += _intFromMarker(marker, 'calls') ?? 0;
        gdiCaptureSuccessCount += _intFromMarker(marker, 'successes') ?? 0;
        gdiTemporaryErrorCount += _intFromMarker(marker, 'temp_errors') ?? 0;
        gdiPermanentErrorCount +=
            _intFromMarker(marker, 'permanent_errors') ?? 0;
        gdiHiddenOrMinimizedCount +=
            _intFromMarker(marker, 'hidden_or_minimized') ?? 0;
        gdiRectFailCount += _intFromMarker(marker, 'rect_fail') ?? 0;
        gdiDcFailCount += _intFromMarker(marker, 'dc_fail') ?? 0;
        gdiFrameCreateFailCount +=
            _intFromMarker(marker, 'frame_create_fail') ?? 0;
        gdiPrintFullCallCount +=
            _intFromMarker(marker, 'print_full_calls') ?? 0;
        gdiPrintFullSuccessCount +=
            _intFromMarker(marker, 'print_full_successes') ?? 0;
        gdiPrintFallbackCallCount +=
            _intFromMarker(marker, 'print_fallback_calls') ?? 0;
        gdiPrintFallbackSuccessCount +=
            _intFromMarker(marker, 'print_fallback_successes') ?? 0;
        gdiBitBltCallCount += _intFromMarker(marker, 'bitblt_calls') ?? 0;
        gdiBitBltSuccessCount +=
            _intFromMarker(marker, 'bitblt_successes') ?? 0;
        gdiFinalPrintFullCount +=
            _intFromMarker(marker, 'final_print_full') ?? 0;
        gdiFinalPrintFallbackCount +=
            _intFromMarker(marker, 'final_print_fallback') ?? 0;
        gdiFinalBitBltCount += _intFromMarker(marker, 'final_bitblt') ?? 0;
        gdiFinalNoneCount += _intFromMarker(marker, 'final_none') ?? 0;
        gdiBlackFrameCount += _intFromMarker(marker, 'black_frame_count') ?? 0;
        gdiLowVarianceFrameCount +=
            _intFromMarker(marker, 'low_variance_frame_count') ?? 0;
        gdiOwnedWindowFrameCount +=
            _intFromMarker(marker, 'owned_window_frames') ?? 0;
        gdiOwnedWindowCaptureCallCount +=
            _intFromMarker(marker, 'owned_capture_calls') ?? 0;
        gdiOwnedWindowCaptureSuccessCount +=
            _intFromMarker(marker, 'owned_capture_successes') ?? 0;
        addMarkerDouble(marker, 'avg_total_ms', gdiTotalValues);
        addMarkerDouble(marker, 'max_total_ms', gdiMaxTotalValues);
        addMarkerDouble(marker, 'avg_rect_ms', gdiRectValues);
        addMarkerDouble(marker, 'max_rect_ms', gdiMaxRectValues);
        addMarkerDouble(marker, 'avg_visibility_ms', gdiVisibilityValues);
        addMarkerDouble(marker, 'max_visibility_ms', gdiMaxVisibilityValues);
        addMarkerDouble(marker, 'avg_get_dc_ms', gdiGetDcValues);
        addMarkerDouble(marker, 'max_get_dc_ms', gdiMaxGetDcValues);
        addMarkerDouble(marker, 'avg_get_dc_size_ms', gdiGetDcSizeValues);
        addMarkerDouble(marker, 'max_get_dc_size_ms', gdiMaxGetDcSizeValues);
        addMarkerDouble(marker, 'avg_create_frame_ms', gdiCreateFrameValues);
        addMarkerDouble(
          marker,
          'max_create_frame_ms',
          gdiMaxCreateFrameValues,
        );
        addMarkerDouble(marker, 'avg_mem_dc_ms', gdiMemDcValues);
        addMarkerDouble(marker, 'max_mem_dc_ms', gdiMaxMemDcValues);
        addMarkerDouble(marker, 'avg_print_full_ms', gdiPrintFullValues);
        addMarkerDouble(marker, 'max_print_full_ms', gdiMaxPrintFullValues);
        addMarkerDouble(
          marker,
          'avg_print_fallback_ms',
          gdiPrintFallbackValues,
        );
        addMarkerDouble(
          marker,
          'max_print_fallback_ms',
          gdiMaxPrintFallbackValues,
        );
        addMarkerDouble(marker, 'avg_bitblt_ms', gdiBitBltValues);
        addMarkerDouble(marker, 'max_bitblt_ms', gdiMaxBitBltValues);
        addMarkerDouble(marker, 'avg_cleanup_ms', gdiCleanupValues);
        addMarkerDouble(marker, 'max_cleanup_ms', gdiMaxCleanupValues);
        addMarkerDouble(marker, 'avg_crop_ms', gdiCropValues);
        addMarkerDouble(marker, 'max_crop_ms', gdiMaxCropValues);
        addMarkerDouble(marker, 'avg_owned_enum_ms', gdiOwnedEnumValues);
        addMarkerDouble(marker, 'max_owned_enum_ms', gdiMaxOwnedEnumValues);
        addMarkerDouble(marker, 'avg_owned_capture_ms', gdiOwnedCaptureValues);
        addMarkerDouble(
          marker,
          'max_owned_capture_ms',
          gdiMaxOwnedCaptureValues,
        );
        addMarkerDouble(
          marker,
          'avg_owned_composite_ms',
          gdiOwnedCompositeValues,
        );
        addMarkerDouble(
          marker,
          'max_owned_composite_ms',
          gdiMaxOwnedCompositeValues,
        );
      }

      final cadenceMatch = _captureCadencePattern.firstMatch(marker);
      if (cadenceMatch != null) {
        final avgCaptureCall = _doubleGroup(cadenceMatch, 2);
        final maxCaptureCall = _doubleGroup(cadenceMatch, 3);
        if (avgCaptureCall != null && avgCaptureCall > 0) {
          captureCallValues.add(avgCaptureCall);
        }
        if (maxCaptureCall != null && maxCaptureCall > 0) {
          maxCaptureCallValues.add(maxCaptureCall);
        }
        final submittedFps = _doubleGroup(cadenceMatch, 6);
        if (submittedFps != null && submittedFps > 0) {
          submittedFpsValues.add(submittedFps);
        }
        scheduleWaitTimeoutCount += _intGroup(cadenceMatch, 7) ?? 0;
        schedulePermanentErrorCount += _intGroup(cadenceMatch, 8) ?? 0;
        final avgResultCallback =
            _doubleFromMarker(marker, 'avg_result_callback_ms');
        final maxResultCallback =
            _doubleFromMarker(marker, 'max_result_callback_ms');
        final avgCallbackEntryDelay =
            _doubleFromMarker(marker, 'avg_callback_entry_delay_ms');
        final maxCallbackEntryDelay =
            _doubleFromMarker(marker, 'max_callback_entry_delay_ms');
        final avgSourceCapture =
            _doubleFromMarker(marker, 'avg_source_capture_ms');
        final maxSourceCapture =
            _doubleFromMarker(marker, 'max_source_capture_ms');
        final avgAcquireWait = _doubleFromMarker(marker, 'avg_acquire_wait_ms');
        final maxAcquireWait = _doubleFromMarker(marker, 'max_acquire_wait_ms');
        final avgPostCallbackWait =
            _doubleFromMarker(marker, 'avg_post_callback_wait_ms');
        final maxPostCallbackWait =
            _doubleFromMarker(marker, 'max_post_callback_wait_ms');
        final avgUnaccountedWait =
            _doubleFromMarker(marker, 'avg_unaccounted_wait_ms');
        final maxUnaccountedWait =
            _doubleFromMarker(marker, 'max_unaccounted_wait_ms');
        final markerSourceCaptureCount =
            _intFromMarker(marker, 'source_capture_count') ?? 0;
        if (avgSourceCapture != null && avgSourceCapture >= 0) {
          if (markerSourceCaptureCount > 0) {
            sourceCaptureWeightedTotalMs +=
                avgSourceCapture * markerSourceCaptureCount;
            sourceCaptureWeightedSampleCount += markerSourceCaptureCount;
          } else {
            sourceCaptureValues.add(avgSourceCapture);
          }
        }
        if (maxSourceCapture != null && maxSourceCapture >= 0) {
          maxSourceCaptureValues.add(maxSourceCapture);
        }
        sourceCaptureSampleCount += markerSourceCaptureCount;
        if (avgCallbackEntryDelay != null && avgCallbackEntryDelay >= 0) {
          callbackEntryDelayValues.add(avgCallbackEntryDelay);
        }
        if (maxCallbackEntryDelay != null && maxCallbackEntryDelay >= 0) {
          maxCallbackEntryDelayValues.add(maxCallbackEntryDelay);
        }
        if (avgResultCallback != null && avgResultCallback >= 0) {
          captureResultCallbackValues.add(avgResultCallback);
        }
        if (maxResultCallback != null && maxResultCallback >= 0) {
          maxCaptureResultCallbackValues.add(maxResultCallback);
        }
        if (avgAcquireWait != null && avgAcquireWait >= 0) {
          captureAcquireWaitValues.add(avgAcquireWait);
        }
        if (maxAcquireWait != null && maxAcquireWait >= 0) {
          maxCaptureAcquireWaitValues.add(maxAcquireWait);
        }
        if (avgPostCallbackWait != null && avgPostCallbackWait >= 0) {
          postCallbackWaitValues.add(avgPostCallbackWait);
        }
        if (maxPostCallbackWait != null && maxPostCallbackWait >= 0) {
          maxPostCallbackWaitValues.add(maxPostCallbackWait);
        }
        if (avgUnaccountedWait != null && avgUnaccountedWait >= 0) {
          unaccountedWaitValues.add(avgUnaccountedWait);
        }
        if (maxUnaccountedWait != null && maxUnaccountedWait >= 0) {
          maxUnaccountedWaitValues.add(maxUnaccountedWait);
        }
        captureResultCallbackCount +=
            _intFromMarker(marker, 'callback_count') ?? 0;
      }

      final frameCadenceMatch = _captureFrameCadencePattern.firstMatch(marker);
      if (frameCadenceMatch != null) {
        parsedFrameCadence = true;
        final nativeFps = _doubleGroup(frameCadenceMatch, 1);
        final submittedFps = _doubleGroup(frameCadenceMatch, 2);
        final maxIntervalMs = _doubleGroup(frameCadenceMatch, 3);
        final p95IntervalMs = _doubleGroup(frameCadenceMatch, 4);
        if (nativeFps != null && nativeFps > 0) {
          nativeFpsValues.add(nativeFps);
        }
        if (submittedFps != null && submittedFps > 0) {
          submittedFpsValues.add(submittedFps);
        }
        if (maxIntervalMs != null && maxIntervalMs > 0) {
          maxFrameIntervalValues.add(maxIntervalMs);
        }
        if (p95IntervalMs != null && p95IntervalMs > 0) {
          p95FrameIntervalValues.add(p95IntervalMs);
        }
        duplicatedFrameCount += _intGroup(frameCadenceMatch, 5) ?? 0;
        staleFrameReuseCount += _intGroup(frameCadenceMatch, 6) ?? 0;
        frameWaitTimeoutCount += _intGroup(frameCadenceMatch, 7) ?? 0;
        framePermanentErrorCount += _intGroup(frameCadenceMatch, 8) ?? 0;
      }

      final frameTimingMatch = _captureFrameTimingPattern.firstMatch(marker);
      if (frameTimingMatch != null) {
        observedCapturer =
            _tokenFromMarker(marker, 'capturer') ?? observedCapturer;
        observedCapturerId =
            _intFromMarker(marker, 'capturer_id') ?? observedCapturerId;
        dirtyRegionMode =
            _tokenFromMarker(marker, 'dirty_region_mode') ?? dirtyRegionMode;
        final avgConvert = _doubleGroup(frameTimingMatch, 1);
        final avgScale = _doubleGroup(frameTimingMatch, 2);
        final avgOnFrame = _doubleGroup(frameTimingMatch, 3);
        final avgCallback = _doubleGroup(frameTimingMatch, 4);
        final maxCallback = _doubleGroup(frameTimingMatch, 5);
        if (avgConvert != null && avgConvert >= 0) {
          frameConvertValues.add(avgConvert);
        }
        if (avgScale != null && avgScale >= 0) {
          frameScaleValues.add(avgScale);
        }
        if (avgOnFrame != null && avgOnFrame >= 0) {
          frameOnFrameValues.add(avgOnFrame);
        }
        if (avgCallback != null && avgCallback > 0) {
          frameCallbackValues.add(avgCallback);
        }
        if (maxCallback != null && maxCallback > 0) {
          maxFrameCallbackValues.add(maxCallback);
        }
        updatedRegionEmptyCount +=
            _intFromMarker(marker, 'updated_region_empty') ?? 0;
        updatedRegionNonEmptyCount +=
            _intFromMarker(marker, 'updated_region_nonempty') ?? 0;
        updatedRegionRectCount +=
            _intFromMarker(marker, 'updated_region_rects') ?? 0;
        updatedRegionMaxRectCount = max(
          updatedRegionMaxRectCount,
          _intFromMarker(marker, 'updated_region_max_rects') ?? 0,
        );
        final avgUpdatedRegionAreaRatio =
            _doubleFromMarker(marker, 'avg_updated_region_area_ratio');
        final maxUpdatedRegionAreaRatio =
            _doubleFromMarker(marker, 'max_updated_region_area_ratio');
        final markerFrameCount = _intGroup(frameTimingMatch, 6) ?? 0;
        if (avgUpdatedRegionAreaRatio != null &&
            avgUpdatedRegionAreaRatio >= 0) {
          if (markerFrameCount > 0) {
            updatedRegionAreaRatioWeightedTotal +=
                avgUpdatedRegionAreaRatio * markerFrameCount;
            updatedRegionAreaRatioWeightedFrames += markerFrameCount;
          } else {
            updatedRegionAreaRatioValues.add(avgUpdatedRegionAreaRatio);
          }
        }
        if (maxUpdatedRegionAreaRatio != null &&
            maxUpdatedRegionAreaRatio >= 0) {
          maxUpdatedRegionAreaRatioValues.add(maxUpdatedRegionAreaRatio);
        }
        final avgUpdatedRegionAnalysisMs =
            _doubleFromMarker(marker, 'avg_updated_region_ms');
        if (avgUpdatedRegionAnalysisMs != null &&
            avgUpdatedRegionAnalysisMs >= 0) {
          if (markerFrameCount > 0) {
            updatedRegionAnalysisWeightedTotal +=
                avgUpdatedRegionAnalysisMs * markerFrameCount;
            updatedRegionAnalysisWeightedFrames += markerFrameCount;
          } else {
            updatedRegionAnalysisValues.add(avgUpdatedRegionAnalysisMs);
          }
        }
        addMarkerDouble(
          marker,
          'max_updated_region_ms',
          maxUpdatedRegionAnalysisValues,
        );
        updatedRegionFullFrameCount +=
            _intFromMarker(marker, 'updated_region_full_frames') ?? 0;
        updatedRegionTinyFrameCount +=
            _intFromMarker(marker, 'updated_region_tiny_frames') ?? 0;
      }

      if (marker.toLowerCase().contains('latest-frame pacer cadence')) {
        latestFramePacerEnabled =
            _boolFromMarker(marker, 'enabled') ?? latestFramePacerEnabled;
        final submittedFps = _doubleFromMarker(marker, 'submitted_fps');
        final uniqueFps = _doubleFromMarker(marker, 'unique_fps');
        final p95IntervalMs = _doubleFromMarker(marker, 'p95_interval_ms');
        final maxIntervalMs = _doubleFromMarker(marker, 'max_interval_ms');
        final avgAgeMs = _doubleFromMarker(marker, 'avg_frame_age_ms');
        final maxAgeMs = _doubleFromMarker(marker, 'max_frame_age_ms');
        final avgOnFrameMs = _doubleFromMarker(marker, 'avg_on_frame_ms');
        final maxOnFrameMs = _doubleFromMarker(marker, 'max_on_frame_ms');
        if (submittedFps != null && submittedFps > 0) {
          pacerSubmittedFpsValues.add(submittedFps);
          submittedFpsValues.add(submittedFps);
        }
        if (uniqueFps != null && uniqueFps > 0) {
          pacerUniqueFpsValues.add(uniqueFps);
        }
        if (p95IntervalMs != null && p95IntervalMs > 0) {
          p95PacerIntervalValues.add(p95IntervalMs);
        }
        if (maxIntervalMs != null && maxIntervalMs > 0) {
          maxPacerIntervalValues.add(maxIntervalMs);
        }
        if (avgAgeMs != null && avgAgeMs >= 0) {
          pacerFrameAgeValues.add(avgAgeMs);
        }
        if (maxAgeMs != null && maxAgeMs >= 0) {
          maxPacerFrameAgeValues.add(maxAgeMs);
        }
        if (avgOnFrameMs != null && avgOnFrameMs >= 0) {
          pacerOnFrameValues.add(avgOnFrameMs);
        }
        if (maxOnFrameMs != null && maxOnFrameMs >= 0) {
          maxPacerOnFrameValues.add(maxOnFrameMs);
        }
        pacerDuplicateSubmitCount +=
            _intFromMarker(marker, 'duplicate_submits') ?? 0;
        pacerOverwrittenFrameCount +=
            _intFromMarker(marker, 'overwritten_frames') ?? 0;
        pacerSkippedTickCount += _intFromMarker(marker, 'skipped_ticks') ?? 0;
      }

      if (marker.toLowerCase().contains('game_capture_webrtc_source')) {
        observedCapturer = 'game-d3d11-hook';
        sourceType ??= 'game';

        final source = _dimensionsFromMarker(marker, 'source');
        gameCaptureSourceWidth = source?.width ?? gameCaptureSourceWidth;
        gameCaptureSourceHeight = source?.height ?? gameCaptureSourceHeight;
        nativeSourceWidth = source?.width ?? nativeSourceWidth;
        nativeSourceHeight = source?.height ?? nativeSourceHeight;

        final output = _dimensionsFromMarker(marker, 'output');
        gameCaptureOutputWidth = output?.width ?? gameCaptureOutputWidth;
        gameCaptureOutputHeight = output?.height ?? gameCaptureOutputHeight;
        preEncodeWidth = output?.width ?? preEncodeWidth;
        preEncodeHeight = output?.height ?? preEncodeHeight;

        gameCaptureFormat =
            _intFromMarker(marker, 'format') ?? gameCaptureFormat;
        gameCaptureBackendContractVersion =
            _intFromMarker(marker, 'backendContractVersion') ??
                gameCaptureBackendContractVersion;
        gameCaptureSourceMode =
            _tokenFromMarker(marker, 'sourceMode') ?? gameCaptureSourceMode;
        gameCaptureSourceApi =
            _tokenFromMarker(marker, 'sourceApi') ?? gameCaptureSourceApi;
        gameCaptureSourceApiId =
            _intFromMarker(marker, 'sourceApiId') ?? gameCaptureSourceApiId;
        gameCaptureSourceFormat =
            _tokenFromMarker(marker, 'sourceFormat') ?? gameCaptureSourceFormat;
        gameCaptureSourceFormatId = _intFromMarker(marker, 'sourceFormatId') ??
            gameCaptureSourceFormatId;
        gameCaptureColorSpace =
            _tokenFromMarker(marker, 'colorSpace') ?? gameCaptureColorSpace;
        gameCaptureSyncKind =
            _tokenFromMarker(marker, 'syncKind') ?? gameCaptureSyncKind;
        gameCaptureReadyState =
            _tokenFromMarker(marker, 'readyState') ?? gameCaptureReadyState;
        gameCaptureFailureReason = _tokenFromMarker(
              marker,
              'failureReason',
            ) ??
            gameCaptureFailureReason;
        gameCaptureConsumerAdapterLuid =
            _tokenFromMarker(marker, 'consumerAdapterLuid') ??
                gameCaptureConsumerAdapterLuid;
        gameCaptureConsumerAdapterVendorId =
            _intFromMarker(marker, 'consumerAdapterVendorId') ??
                gameCaptureConsumerAdapterVendorId;
        gameCaptureConsumerAdapterDeviceId =
            _intFromMarker(marker, 'consumerAdapterDeviceId') ??
                gameCaptureConsumerAdapterDeviceId;
        gameCaptureSourceAdapterLuid =
            _tokenFromMarker(marker, 'sourceAdapterLuid') ??
                gameCaptureSourceAdapterLuid;
        gameCaptureCrossAdapterSuspected =
            _tokenFromMarker(marker, 'crossAdapterSuspected') ??
                gameCaptureCrossAdapterSuspected;

        final fps = _doubleFromMarker(marker, 'fps');
        if (fps != null && fps > 0) {
          gameCaptureFpsValues.add(fps);
          nativeFpsValues.add(fps);
          submittedFpsValues.add(fps);
        }

        gameCaptureSubmittedFrames = max(
          gameCaptureSubmittedFrames,
          _intFromMarker(marker, 'submitted') ?? 0,
        );
        gameCaptureRepeatedFrames = max(
          gameCaptureRepeatedFrames,
          _intFromMarker(marker, 'repeated') ?? 0,
        );
        gameCaptureDuplicateSkippedFrames = max(
          gameCaptureDuplicateSkippedFrames,
          _intFromMarker(marker, 'duplicateSkipped') ?? 0,
        );
        gameCaptureDeliveryQueuedFrames = max(
          gameCaptureDeliveryQueuedFrames,
          _intFromMarker(marker, 'deliveryQueued') ?? 0,
        );
        gameCaptureDeliverySubmittedFrames = max(
          gameCaptureDeliverySubmittedFrames,
          _intFromMarker(marker, 'deliverySubmitted') ?? 0,
        );
        gameCaptureDeliveryOverwrittenFrames = max(
          gameCaptureDeliveryOverwrittenFrames,
          _intFromMarker(marker, 'deliveryOverwritten') ?? 0,
        );
        gameCaptureDeliveryPacerResyncs = max(
          gameCaptureDeliveryPacerResyncs,
          _intFromMarker(marker, 'deliveryPacerResyncs') ??
              _intFromMarker(marker, 'resyncs') ??
              0,
        );
        gameCaptureDeliveryPacerLagMaxMs = max(
          gameCaptureDeliveryPacerLagMaxMs,
          _intFromMarker(marker, 'deliveryPacerLagMaxMs') ??
              _intFromMarker(marker, 'maxLagMs') ??
              _intFromMarker(marker, 'lagMs') ??
              0,
        );
        gameCaptureDeliveryRepeatNoQueuedFrames = max(
          gameCaptureDeliveryRepeatNoQueuedFrames,
          _intFromMarker(marker, 'deliveryRepeatNoQueued') ?? 0,
        );
        gameCaptureDeliverySkipNoQueuedFrames = max(
          gameCaptureDeliverySkipNoQueuedFrames,
          _intFromMarker(marker, 'deliverySkipNoQueued') ?? 0,
        );
        gameCaptureDeliveryFreshWakeAfterSkipFrames = max(
          gameCaptureDeliveryFreshWakeAfterSkipFrames,
          _intFromMarker(marker, 'deliveryFreshWakeAfterSkip') ?? 0,
        );
        gameCaptureDeliveryFreshImmediateFrames = max(
          gameCaptureDeliveryFreshImmediateFrames,
          _intFromMarker(marker, 'deliveryFreshImmediate') ?? 0,
        );
        gameCaptureDeliveryRepeatPolicy =
            _tokenFromMarker(marker, 'deliveryRepeatPolicy') ??
                gameCaptureDeliveryRepeatPolicy;
        gameCaptureDeliveryQueueDepth =
            _intFromMarker(marker, 'deliveryQueueDepth') ??
                _intFromMarker(marker, 'queueDepth') ??
                gameCaptureDeliveryQueueDepth;
        addMarkerDouble(
          marker,
          'deliveryRepeatSourceAgeMs',
          gameCaptureDeliveryRepeatSourceAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryRepeatSourceAgeMaxMs',
          gameCaptureDeliveryRepeatSourceAgeMaxMsValues,
        );
        gameCaptureDeliveryRepeatSourceAgeSamples = max(
          gameCaptureDeliveryRepeatSourceAgeSamples,
          _intFromMarker(marker, 'deliveryRepeatSourceAgeSamples') ?? 0,
        );
        gameCaptureCopiedFrames = max(
          gameCaptureCopiedFrames,
          _intFromMarker(marker, 'copied') ?? 0,
        );
        gameCaptureDroppedFrames = max(
          gameCaptureDroppedFrames,
          _intFromMarker(marker, 'dropped') ?? 0,
        );
        gameCaptureOverwrittenFrames = max(
          gameCaptureOverwrittenFrames,
          _intFromMarker(marker, 'overwritten') ?? 0,
        );
        gameCaptureGpuScaledFrames = max(
          gameCaptureGpuScaledFrames,
          _intFromMarker(marker, 'gpuScaled') ?? 0,
        );
        gameCaptureGpuScaleFailures = max(
          gameCaptureGpuScaleFailures,
          _intFromMarker(marker, 'gpuScaleFailures') ?? 0,
        );
        gameCaptureCpuFallbackFrames = max(
          gameCaptureCpuFallbackFrames,
          _intFromMarker(marker, 'cpuFallback') ?? 0,
        );
        gameCaptureNativeNv12SubmittedFrames = max(
          gameCaptureNativeNv12SubmittedFrames,
          _intFromMarker(marker, 'nativeNv12Submitted') ?? 0,
        );
        gameCaptureNativeNv12QueuedFrames = max(
          gameCaptureNativeNv12QueuedFrames,
          _intFromMarker(marker, 'nativeNv12Queued') ?? 0,
        );
        gameCaptureNativeNv12ReadyFrames = max(
          gameCaptureNativeNv12ReadyFrames,
          _intFromMarker(marker, 'nativeNv12Ready') ?? 0,
        );
        gameCaptureNativeNv12NotReadyPolls = max(
          gameCaptureNativeNv12NotReadyPolls,
          _intFromMarker(marker, 'nativeNv12NotReadyPolls') ?? 0,
        );
        gameCaptureNativeNv12ReadyPolicy =
            _tokenFromMarker(marker, 'nativeNv12ReadyPolicy') ??
                gameCaptureNativeNv12ReadyPolicy;
        gameCaptureNativeNv12FenceAvailable =
            _boolFromMarker(marker, 'nativeNv12FenceAvailable') ??
                gameCaptureNativeNv12FenceAvailable;
        gameCaptureNativeNv12PendingPollMs =
            _intFromMarker(marker, 'nativeNv12PendingPollMs') ??
                gameCaptureNativeNv12PendingPollMs;
        gameCaptureNativeNv12MaxPendingSlots =
            _intFromMarker(marker, 'nativeNv12MaxPendingSlots') ??
                gameCaptureNativeNv12MaxPendingSlots;
        gameCaptureNativeNv12ReadyDrainDepth =
            _intFromMarker(marker, 'nativeNv12ReadyDrainDepth') ??
                gameCaptureNativeNv12ReadyDrainDepth;
        gameCaptureNativeNv12FrameOwnership =
            _tokenFromMarker(marker, 'nativeNv12FrameOwnership') ??
                gameCaptureNativeNv12FrameOwnership;
        gameCaptureNativeNv12FenceSignaledFrames = max(
          gameCaptureNativeNv12FenceSignaledFrames,
          _intFromMarker(marker, 'nativeNv12FenceSignaled') ?? 0,
        );
        gameCaptureNativeNv12FenceReadyFrames = max(
          gameCaptureNativeNv12FenceReadyFrames,
          _intFromMarker(marker, 'nativeNv12FenceReady') ?? 0,
        );
        gameCaptureNativeNv12FenceSignalFailures = max(
          gameCaptureNativeNv12FenceSignalFailures,
          _intFromMarker(marker, 'nativeNv12FenceSignalFailures') ?? 0,
        );
        gameCaptureNativeNv12OwnedCopies = max(
          gameCaptureNativeNv12OwnedCopies,
          _intFromMarker(marker, 'nativeNv12OwnedCopies') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OwnedCopyMs',
          gameCaptureNativeNv12OwnedCopyMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OwnedCopyMaxMs',
          gameCaptureNativeNv12OwnedCopyMaxMsValues,
        );
        gameCaptureNativeNv12OwnedCopySamples = max(
          gameCaptureNativeNv12OwnedCopySamples,
          _intFromMarker(marker, 'nativeNv12OwnedCopySamples') ?? 0,
        );
        gameCaptureNativeNv12OverwrittenFrames = max(
          gameCaptureNativeNv12OverwrittenFrames,
          _intFromMarker(marker, 'nativeNv12Overwritten') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OverwriteAgeMs',
          gameCaptureNativeNv12OverwriteAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12OverwriteAgeMaxMs',
          gameCaptureNativeNv12OverwriteAgeMaxMsValues,
        );
        gameCaptureNativeNv12OverwriteAgeSamples = max(
          gameCaptureNativeNv12OverwriteAgeSamples,
          _intFromMarker(marker, 'nativeNv12OverwriteAgeSamples') ?? 0,
        );
        gameCaptureNativeNv12OverwrittenFreshFrames = max(
          gameCaptureNativeNv12OverwrittenFreshFrames,
          _intFromMarker(marker, 'nativeNv12OverwrittenFresh') ?? 0,
        );
        gameCaptureNativeNv12ReadyDroppedFrames = max(
          gameCaptureNativeNv12ReadyDroppedFrames,
          _intFromMarker(marker, 'nativeNv12ReadyDropped') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ReadyDropAgeMs',
          gameCaptureNativeNv12ReadyDropAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ReadyDropAgeMaxMs',
          gameCaptureNativeNv12ReadyDropAgeMaxMsValues,
        );
        gameCaptureNativeNv12ReadyDropAgeSamples = max(
          gameCaptureNativeNv12ReadyDropAgeSamples,
          _intFromMarker(marker, 'nativeNv12ReadyDropAgeSamples') ?? 0,
        );
        gameCaptureNativeNv12ReadyDroppedFreshFrames = max(
          gameCaptureNativeNv12ReadyDroppedFreshFrames,
          _intFromMarker(marker, 'nativeNv12ReadyDroppedFresh') ?? 0,
        );
        gameCaptureNativeNv12Failures = max(
          gameCaptureNativeNv12Failures,
          _intFromMarker(marker, 'nativeNv12Failures') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ConvertMs',
          gameCaptureNativeNv12ConvertMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ConvertMaxMs',
          gameCaptureNativeNv12ConvertMaxMsValues,
        );
        gameCaptureNativeNv12ConvertSamples = max(
          gameCaptureNativeNv12ConvertSamples,
          _intFromMarker(marker, 'nativeNv12ConvertSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12BgraScaleDrawMs',
          gameCaptureNativeNv12BgraScaleDrawMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12BgraScaleDrawMaxMs',
          gameCaptureNativeNv12BgraScaleDrawMaxMsValues,
        );
        gameCaptureNativeNv12BgraScaleDrawSamples = max(
          gameCaptureNativeNv12BgraScaleDrawSamples,
          _intFromMarker(marker, 'nativeNv12BgraScaleDrawSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltSubmitMs',
          gameCaptureNativeNv12VideoProcessorBltSubmitMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltSubmitMaxMs',
          gameCaptureNativeNv12VideoProcessorBltSubmitMaxMsValues,
        );
        gameCaptureNativeNv12VideoProcessorBltSubmitSamples = max(
          gameCaptureNativeNv12VideoProcessorBltSubmitSamples,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltSubmitSamples',
              ) ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltToReadyMs',
          gameCaptureNativeNv12VideoProcessorBltToReadyMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12VideoProcessorBltToReadyMaxMs',
          gameCaptureNativeNv12VideoProcessorBltToReadyMaxMsValues,
        );
        gameCaptureNativeNv12VideoProcessorBltToReadySamples = max(
          gameCaptureNativeNv12VideoProcessorBltToReadySamples,
          _intFromMarker(
                marker,
                'nativeNv12VideoProcessorBltToReadySamples',
              ) ??
              0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12BufferCreateMs',
          gameCaptureNativeNv12BufferCreateMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12BufferCreateMaxMs',
          gameCaptureNativeNv12BufferCreateMaxMsValues,
        );
        gameCaptureNativeNv12BufferCreateSamples = max(
          gameCaptureNativeNv12BufferCreateSamples,
          _intFromMarker(marker, 'nativeNv12BufferCreateSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12FrameReadyToQueueMs',
          gameCaptureNativeNv12FrameReadyToQueueMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12FrameReadyToQueueMaxMs',
          gameCaptureNativeNv12FrameReadyToQueueMaxMsValues,
        );
        gameCaptureNativeNv12FrameReadyToQueueSamples = max(
          gameCaptureNativeNv12FrameReadyToQueueSamples,
          _intFromMarker(marker, 'nativeNv12FrameReadyToQueueSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ConversionStartAgeMs',
          gameCaptureNativeNv12ConversionStartAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeNv12ConversionStartAgeMaxMs',
          gameCaptureNativeNv12ConversionStartAgeMaxMsValues,
        );
        gameCaptureNativeNv12ConversionStartAgeSamples = max(
          gameCaptureNativeNv12ConversionStartAgeSamples,
          _intFromMarker(marker, 'nativeNv12ConversionStartAgeSamples') ?? 0,
        );
        gameCaptureNativeNv12StaleBeforeQueueFrames = max(
          gameCaptureNativeNv12StaleBeforeQueueFrames,
          _intFromMarker(marker, 'nativeNv12StaleBeforeQueue') ?? 0,
        );
        gameCaptureReadbackQueuedFrames = max(
          gameCaptureReadbackQueuedFrames,
          _intFromMarker(marker, 'readbackQueued') ?? 0,
        );
        gameCaptureReadbackReadyFrames = max(
          gameCaptureReadbackReadyFrames,
          _intFromMarker(marker, 'readbackReady') ?? 0,
        );
        gameCaptureReadbackNotReadyFrames = max(
          gameCaptureReadbackNotReadyFrames,
          _intFromMarker(marker, 'readbackNotReady') ?? 0,
        );
        gameCaptureReadbackOverwrittenFrames = max(
          gameCaptureReadbackOverwrittenFrames,
          _intFromMarker(marker, 'readbackOverwritten') ?? 0,
        );
        gameCaptureReadbackStaleDroppedFrames = max(
          gameCaptureReadbackStaleDroppedFrames,
          _intFromMarker(marker, 'readbackStaleDropped') ?? 0,
        );
        gameCaptureReadbackLatencyDroppedFrames = max(
          gameCaptureReadbackLatencyDroppedFrames,
          _intFromMarker(marker, 'readbackLatencyDropped') ?? 0,
        );
        gameCaptureReadbackMapAttempts = max(
          gameCaptureReadbackMapAttempts,
          _intFromMarker(marker, 'readbackMapAttempts') ?? 0,
        );
        gameCaptureSourceFrameIndex = max(
          gameCaptureSourceFrameIndex,
          _intFromMarker(marker, 'sourceFrameIndex') ?? 0,
        );
        gameCaptureLastSubmittedSourceFrameIndex = max(
          gameCaptureLastSubmittedSourceFrameIndex,
          _intFromMarker(marker, 'lastSubmittedSourceFrameIndex') ?? 0,
        );
        gameCaptureSourceFrameRegressions = max(
          gameCaptureSourceFrameRegressions,
          _intFromMarker(marker, 'sourceFrameRegressions') ?? 0,
        );
        gameCaptureSourceFrameDuplicates = max(
          gameCaptureSourceFrameDuplicates,
          _intFromMarker(marker, 'sourceFrameDuplicates') ?? 0,
        );
        gameCaptureSourceFrameGaps = max(
          gameCaptureSourceFrameGaps,
          _intFromMarker(marker, 'sourceFrameGaps') ?? 0,
        );
        gameCaptureSharedSlotMismatches = max(
          gameCaptureSharedSlotMismatches,
          _intFromMarker(marker, 'sharedSlotMismatches') ?? 0,
        );
        gameCaptureTimestampMode = _tokenFromMarker(marker, 'timestampMode') ??
            gameCaptureTimestampMode;
        gameCaptureTimestampSourceQpcFrames = max(
          gameCaptureTimestampSourceQpcFrames,
          _intFromMarker(marker, 'timestampSourceQpcFrames') ?? 0,
        );
        gameCaptureTimestampPacedFallbackFrames = max(
          gameCaptureTimestampPacedFallbackFrames,
          _intFromMarker(marker, 'timestampPacedFallbackFrames') ?? 0,
        );
        gameCaptureTimestampRepeatedFrames = max(
          gameCaptureTimestampRepeatedFrames,
          _intFromMarker(marker, 'timestampRepeatedFrames') ?? 0,
        );
        addMarkerDouble(
          marker,
          'timestampDeltaMs',
          gameCaptureTimestampDeltaMsValues,
        );
        addMarkerDouble(
          marker,
          'timestampDeltaMaxMs',
          gameCaptureTimestampDeltaMaxMsValues,
        );
        gameCaptureTimestampSamples = max(
          gameCaptureTimestampSamples,
          _intFromMarker(marker, 'timestampSamples') ?? 0,
        );
        gameCaptureTimestampAdjustments = max(
          gameCaptureTimestampAdjustments,
          _intFromMarker(marker, 'timestampAdjustments') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryWallDeltaMs',
          gameCaptureDeliveryWallDeltaMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryWallDeltaMaxMs',
          gameCaptureDeliveryWallDeltaMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryWallDeltaMinMs',
          gameCaptureDeliveryWallDeltaMinMsValues,
        );
        gameCaptureDeliveryWallSamples = max(
          gameCaptureDeliveryWallSamples,
          _intFromMarker(marker, 'deliveryWallSamples') ?? 0,
        );
        gameCaptureDeliveryWallOver2xFrames = max(
          gameCaptureDeliveryWallOver2xFrames,
          _intFromMarker(marker, 'deliveryWallOver2x') ?? 0,
        );
        gameCaptureDeliveryWallOver3xFrames = max(
          gameCaptureDeliveryWallOver3xFrames,
          _intFromMarker(marker, 'deliveryWallOver3x') ?? 0,
        );
        gameCaptureDeliveryWallUnderHalfFrames = max(
          gameCaptureDeliveryWallUnderHalfFrames,
          _intFromMarker(marker, 'deliveryWallUnderHalf') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceQpcDeltaMs',
          gameCaptureSourceQpcDeltaMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceQpcDeltaMaxMs',
          gameCaptureSourceQpcDeltaMaxMsValues,
        );
        gameCaptureSourceQpcSamples = max(
          gameCaptureSourceQpcSamples,
          _intFromMarker(marker, 'sourceQpcSamples') ?? 0,
        );
        gameCaptureSourceQpcRegressions = max(
          gameCaptureSourceQpcRegressions,
          _intFromMarker(marker, 'sourceQpcRegressions') ?? 0,
        );
        gameCaptureMaxReadbackLatencyFrames = max(
          gameCaptureMaxReadbackLatencyFrames,
          _intFromMarker(marker, 'readbackLatencyFramesMax') ?? 0,
        );
        gameCaptureMapFailures = max(
          gameCaptureMapFailures,
          _intFromMarker(marker, 'mapFailures') ?? 0,
        );
        gameCaptureConvertFailures = max(
          gameCaptureConvertFailures,
          _intFromMarker(marker, 'convertFailures') ?? 0,
        );
        gameCaptureProofFrames = max(
          gameCaptureProofFrames,
          _intFromMarker(marker, 'proofFrames') ?? 0,
        );
        gameCaptureVisibleProofFrames = max(
          gameCaptureVisibleProofFrames,
          _intFromMarker(marker, 'visibleProofFrames') ?? 0,
        );
        gameCaptureI420ProofFrames = max(
          gameCaptureI420ProofFrames,
          _intFromMarker(marker, 'i420ProofFrames') ?? 0,
        );
        gameCaptureVisibleI420ProofFrames = max(
          gameCaptureVisibleI420ProofFrames,
          _intFromMarker(marker, 'visibleI420ProofFrames') ?? 0,
        );
        gameCaptureInitialBlackSkippedFrames = max(
          gameCaptureInitialBlackSkippedFrames,
          _intFromMarker(marker, 'initialBlackSkipped') ??
              _intFromMarker(marker, 'skipped') ??
              0,
        );
        gameCaptureVisibleSourceSeen = _boolFromMarker(
              marker,
              'visibleSourceSeen',
            ) ??
            gameCaptureVisibleSourceSeen;
        addMarkerDouble(marker, 'copyMs', gameCaptureCopyMsValues);
        addMarkerDouble(marker, 'mapMs', gameCaptureMapMsValues);
        addMarkerDouble(marker, 'convertMs', gameCaptureConvertMsValues);
        addMarkerDouble(marker, 'gpuScaleMs', gameCaptureGpuScaleMsValues);
        addMarkerDouble(
          marker,
          'deliveryOnFrameMs',
          gameCaptureDeliveryOnFrameMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryOnFrameMaxMs',
          gameCaptureDeliveryOnFrameMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'deliverySubmitPrepMs',
          gameCaptureDeliverySubmitPrepMsValues,
        );
        addMarkerDouble(
          marker,
          'deliverySubmitPrepMaxMs',
          gameCaptureDeliverySubmitPrepMaxMsValues,
        );
        gameCaptureDeliverySubmitPrepSamples = max(
          gameCaptureDeliverySubmitPrepSamples,
          _intFromMarker(marker, 'deliverySubmitPrepSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryOnFrameCallMs',
          gameCaptureDeliveryOnFrameCallMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryOnFrameCallMaxMs',
          gameCaptureDeliveryOnFrameCallMaxMsValues,
        );
        gameCaptureDeliveryOnFrameCallSamples = max(
          gameCaptureDeliveryOnFrameCallSamples,
          _intFromMarker(marker, 'deliveryOnFrameCallSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryPostOnFrameMs',
          gameCaptureDeliveryPostOnFrameMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryPostOnFrameMaxMs',
          gameCaptureDeliveryPostOnFrameMaxMsValues,
        );
        gameCaptureDeliveryPostOnFrameSamples = max(
          gameCaptureDeliveryPostOnFrameSamples,
          _intFromMarker(marker, 'deliveryPostOnFrameSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'nativeBufferReleaseMs',
          gameCaptureNativeBufferReleaseMsValues,
        );
        addMarkerDouble(
          marker,
          'nativeBufferReleaseMaxMs',
          gameCaptureNativeBufferReleaseMaxMsValues,
        );
        gameCaptureNativeBufferReleaseSamples = max(
          gameCaptureNativeBufferReleaseSamples,
          _intFromMarker(marker, 'nativeBufferReleaseSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'readyToQueueMs',
          gameCaptureReadyToQueueMsValues,
        );
        addMarkerDouble(
          marker,
          'readyToQueueMaxMs',
          gameCaptureReadyToQueueMaxMsValues,
        );
        gameCaptureReadyToQueueSamples = max(
          gameCaptureReadyToQueueSamples,
          _intFromMarker(marker, 'readyToQueueSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryQueueWaitMs',
          gameCaptureDeliveryQueueWaitMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryQueueWaitMaxMs',
          gameCaptureDeliveryQueueWaitMaxMsValues,
        );
        gameCaptureDeliveryQueueWaitSamples = max(
          gameCaptureDeliveryQueueWaitSamples,
          _intFromMarker(marker, 'deliveryQueueWaitSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'deliveryOverwriteAgeMs',
          gameCaptureDeliveryOverwriteAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'deliveryOverwriteAgeMaxMs',
          gameCaptureDeliveryOverwriteAgeMaxMsValues,
        );
        gameCaptureDeliveryOverwriteAgeSamples = max(
          gameCaptureDeliveryOverwriteAgeSamples,
          _intFromMarker(marker, 'deliveryOverwriteAgeSamples') ?? 0,
        );
        gameCaptureDeliveryOverwrittenFreshFrames = max(
          gameCaptureDeliveryOverwrittenFreshFrames,
          _intFromMarker(marker, 'deliveryOverwrittenFresh') ?? 0,
        );
        addMarkerDouble(
          marker,
          'readyToSubmitMs',
          gameCaptureReadyToSubmitMsValues,
        );
        addMarkerDouble(
          marker,
          'readyToSubmitMaxMs',
          gameCaptureReadyToSubmitMaxMsValues,
        );
        gameCaptureReadyToSubmitSamples = max(
          gameCaptureReadyToSubmitSamples,
          _intFromMarker(marker, 'readyToSubmitSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceToSubmitMs',
          gameCaptureSourceToSubmitMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceToSubmitMaxMs',
          gameCaptureSourceToSubmitMaxMsValues,
        );
        gameCaptureSourceToSubmitSamples = max(
          gameCaptureSourceToSubmitSamples,
          _intFromMarker(marker, 'sourceToSubmitSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceToReadbackReadyMs',
          gameCaptureSourceToReadbackReadyMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceToReadbackReadyMaxMs',
          gameCaptureSourceToReadbackReadyMaxMsValues,
        );
        gameCaptureSourceToReadbackReadySamples = max(
          gameCaptureSourceToReadbackReadySamples,
          _intFromMarker(marker, 'sourceToReadbackReadySamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'readbackQueueToMapMs',
          gameCaptureReadbackQueueToMapMsValues,
        );
        addMarkerDouble(
          marker,
          'readbackQueueToMapMaxMs',
          gameCaptureReadbackQueueToMapMaxMsValues,
        );
        gameCaptureReadbackQueueToMapSamples = max(
          gameCaptureReadbackQueueToMapSamples,
          _intFromMarker(marker, 'readbackQueueToMapSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'mapToI420Ms',
          gameCaptureMapToI420MsValues,
        );
        addMarkerDouble(
          marker,
          'mapToI420MaxMs',
          gameCaptureMapToI420MaxMsValues,
        );
        gameCaptureMapToI420Samples = max(
          gameCaptureMapToI420Samples,
          _intFromMarker(marker, 'mapToI420Samples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceToI420ReadyMs',
          gameCaptureSourceToI420ReadyMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceToI420ReadyMaxMs',
          gameCaptureSourceToI420ReadyMaxMsValues,
        );
        gameCaptureSourceToI420ReadySamples = max(
          gameCaptureSourceToI420ReadySamples,
          _intFromMarker(marker, 'sourceToI420ReadySamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceToQueueMs',
          gameCaptureSourceToQueueMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceToQueueMaxMs',
          gameCaptureSourceToQueueMaxMsValues,
        );
        gameCaptureSourceToQueueSamples = max(
          gameCaptureSourceToQueueSamples,
          _intFromMarker(marker, 'sourceToQueueSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'sourceDuplicateSkipAgeMs',
          gameCaptureSourceDuplicateSkipAgeMsValues,
        );
        addMarkerDouble(
          marker,
          'sourceDuplicateSkipAgeMaxMs',
          gameCaptureSourceDuplicateSkipAgeMaxMsValues,
        );
        gameCaptureSourceDuplicateSkipAgeSamples = max(
          gameCaptureSourceDuplicateSkipAgeSamples,
          _intFromMarker(marker, 'sourceDuplicateSkipAgeSamples') ?? 0,
        );
        addMarkerDouble(
          marker,
          'readbackLatencyMs',
          gameCaptureReadbackLatencyMsValues,
        );
        addMarkerDouble(
          marker,
          'readbackLatencyFramesAvg',
          gameCaptureReadbackLatencyFrameValues,
        );

        if (marker.toLowerCase().contains(' i420_proof ')) {
          gameCaptureI420ProofFrames = max(
            gameCaptureI420ProofFrames,
            _intFromMarker(marker, 'frame') ?? 0,
          );
          gameCaptureI420ProofVisible =
              _boolFromMarker(marker, 'visible') ?? gameCaptureI420ProofVisible;
          gameCaptureI420ProofMinLuma =
              _intFromMarker(marker, 'minLuma') ?? gameCaptureI420ProofMinLuma;
          gameCaptureI420ProofMaxLuma =
              _intFromMarker(marker, 'maxLuma') ?? gameCaptureI420ProofMaxLuma;
          gameCaptureI420ProofNonzeroSamples =
              _intFromMarker(marker, 'nonzeroSamples') ??
                  gameCaptureI420ProofNonzeroSamples;
          gameCaptureI420ProofSamples =
              _intFromMarker(marker, 'samples') ?? gameCaptureI420ProofSamples;
          final path = _tokenFromMarker(marker, 'path');
          if (path != null) {
            gameCaptureI420ProofPath = path.replaceAll(RegExp(r'^"|"$'), '');
          }
        } else if (marker.toLowerCase().contains(' proof ')) {
          gameCaptureProofVisible =
              _boolFromMarker(marker, 'visible') ?? gameCaptureProofVisible;
          gameCaptureProofMinLuma =
              _intFromMarker(marker, 'minLuma') ?? gameCaptureProofMinLuma;
          gameCaptureProofMaxLuma =
              _intFromMarker(marker, 'maxLuma') ?? gameCaptureProofMaxLuma;
          gameCaptureProofNonzeroSamples =
              _intFromMarker(marker, 'nonzeroSamples') ??
                  gameCaptureProofNonzeroSamples;
          gameCaptureProofSamples =
              _intFromMarker(marker, 'samples') ?? gameCaptureProofSamples;
          final path = _tokenFromMarker(marker, 'path');
          if (path != null) {
            gameCaptureProofPath = path.replaceAll(RegExp(r'^"|"$'), '');
          }
        }
      }

      if (marker
          .toLowerCase()
          .contains('webrtc sender handoff source_on_frame stats')) {
        addMarkerDouble(marker, 'avg_ms', webrtcSourceOnFrameMsValues);
        addMarkerDouble(marker, 'max_ms', webrtcSourceOnFrameMaxMsValues);
        addMarkerDouble(marker, 'adapt_ms', webrtcSourceAdaptMsValues);
        addMarkerDouble(marker, 'adapt_max_ms', webrtcSourceAdaptMaxMsValues);
        addMarkerDouble(marker, 'scale_ms', webrtcSourceScaleMsValues);
        addMarkerDouble(marker, 'scale_max_ms', webrtcSourceScaleMaxMsValues);
        addMarkerDouble(marker, 'broadcast_ms', webrtcSourceBroadcastMsValues);
        addMarkerDouble(
          marker,
          'broadcast_max_ms',
          webrtcSourceBroadcastMaxMsValues,
        );
        webrtcSourceOnFrameSamples = max(
          webrtcSourceOnFrameSamples,
          _intFromMarker(marker, 'calls') ?? 0,
        );
        webrtcSourceAdapterDrops = max(
          webrtcSourceAdapterDrops,
          _intFromMarker(marker, 'adapter_drops') ?? 0,
        );
        webrtcSourceScaledFrames = max(
          webrtcSourceScaledFrames,
          _intFromMarker(marker, 'scaled') ?? 0,
        );
      }

      if (marker
          .toLowerCase()
          .contains('webrtc sender handoff video_broadcaster stats')) {
        addMarkerDouble(marker, 'avg_ms', webrtcVideoBroadcasterMsValues);
        addMarkerDouble(marker, 'max_ms', webrtcVideoBroadcasterMaxMsValues);
        webrtcVideoBroadcasterSamples = max(
          webrtcVideoBroadcasterSamples,
          _intFromMarker(marker, 'frames') ?? 0,
        );
        addMarkerDouble(
          marker,
          'lock_wait_ms',
          webrtcVideoBroadcasterLockWaitMsValues,
        );
        addMarkerDouble(
          marker,
          'lock_wait_max_ms',
          webrtcVideoBroadcasterLockWaitMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'sink_dispatch_ms',
          webrtcVideoBroadcasterSinkDispatchMsValues,
        );
        addMarkerDouble(
          marker,
          'sink_dispatch_max_ms',
          webrtcVideoBroadcasterSinkDispatchMaxMsValues,
        );
        addMarkerDouble(
          marker,
          'max_single_sink_ms',
          webrtcVideoBroadcasterMaxSingleSinkMsValues,
        );
        final slowSinkMs = _doubleFromMarker(marker, 'slow_sink_ms');
        if (slowSinkMs != null &&
            (webrtcVideoBroadcasterSlowSinkMs == null ||
                slowSinkMs >= webrtcVideoBroadcasterSlowSinkMs)) {
          webrtcVideoBroadcasterSlowSinkMs = slowSinkMs;
          webrtcVideoBroadcasterSlowSinkId =
              _intFromMarker(marker, 'slow_sink_id') ??
                  webrtcVideoBroadcasterSlowSinkId;
          webrtcVideoBroadcasterSlowSinkLabel =
              _tokenFromMarker(marker, 'slow_sink_label') ??
                  webrtcVideoBroadcasterSlowSinkLabel;
        }
        final slowestSinkMs = _doubleFromMarker(marker, 'slowest_sink_ms');
        if (slowestSinkMs != null &&
            (webrtcVideoBroadcasterSlowestSinkMs == null ||
                slowestSinkMs >= webrtcVideoBroadcasterSlowestSinkMs)) {
          webrtcVideoBroadcasterSlowestSinkMs = slowestSinkMs;
          webrtcVideoBroadcasterSlowestSinkId =
              _intFromMarker(marker, 'slowest_sink_id') ??
                  webrtcVideoBroadcasterSlowestSinkId;
          webrtcVideoBroadcasterSlowestSinkAverageMs =
              _doubleFromMarker(marker, 'slowest_sink_avg_ms') ??
                  webrtcVideoBroadcasterSlowestSinkAverageMs;
          webrtcVideoBroadcasterSlowestSinkFrames =
              _intFromMarker(marker, 'slowest_sink_frames') ??
                  webrtcVideoBroadcasterSlowestSinkFrames;
          webrtcVideoBroadcasterSlowestSinkLabel =
              _tokenFromMarker(marker, 'slowest_sink_label') ??
                  webrtcVideoBroadcasterSlowestSinkLabel;
        }
        webrtcVideoBroadcasterSinkCount = max(
          webrtcVideoBroadcasterSinkCount,
          _intFromMarker(marker, 'sink_count') ?? 0,
        );
        webrtcVideoBroadcasterMaxSinkCount = max(
          webrtcVideoBroadcasterMaxSinkCount,
          _intFromMarker(marker, 'max_sink_count') ?? 0,
        );
        webrtcVideoBroadcasterActiveSinks = max(
          webrtcVideoBroadcasterActiveSinks,
          _intFromMarker(marker, 'active_sinks') ?? 0,
        );
        webrtcVideoBroadcasterInactiveSinks = max(
          webrtcVideoBroadcasterInactiveSinks,
          _intFromMarker(marker, 'inactive_sinks') ?? 0,
        );
        webrtcVideoBroadcasterRequestedSinks = max(
          webrtcVideoBroadcasterRequestedSinks,
          _intFromMarker(marker, 'requested_sinks') ?? 0,
        );
        webrtcVideoBroadcasterBlackFrameSinks = max(
          webrtcVideoBroadcasterBlackFrameSinks,
          _intFromMarker(marker, 'black_frame_sinks') ?? 0,
        );
        webrtcVideoBroadcasterRotationAppliedSinks = max(
          webrtcVideoBroadcasterRotationAppliedSinks,
          _intFromMarker(marker, 'rotation_applied_sinks') ?? 0,
        );
        final inactiveNativeSinksBypassed =
            _intFromMarker(marker, 'inactive_native_sinks_bypassed');
        final inactiveNativeSinksBypassedLast =
            _intFromMarker(marker, 'inactive_native_sinks_bypassed_last');
        if (inactiveNativeSinksBypassed != null ||
            inactiveNativeSinksBypassedLast != null) {
          webrtcVideoBroadcasterInactiveNativeSinkBypassReported = true;
        }
        if (inactiveNativeSinksBypassed != null) {
          webrtcVideoBroadcasterInactiveNativeSinksBypassed = max(
            webrtcVideoBroadcasterInactiveNativeSinksBypassed,
            inactiveNativeSinksBypassed,
          );
        }
        if (inactiveNativeSinksBypassedLast != null) {
          webrtcVideoBroadcasterInactiveNativeSinksBypassedLast = max(
            webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
            inactiveNativeSinksBypassedLast,
          );
        }
        webrtcVideoBroadcasterSinkRoster =
            _tokenFromMarker(marker, 'sink_roster') ??
                webrtcVideoBroadcasterSinkRoster;
        webrtcVideoBroadcasterBlackSinks = max(
          webrtcVideoBroadcasterBlackSinks,
          _intFromMarker(marker, 'black_sinks') ?? 0,
        );
        webrtcVideoBroadcasterRotationDiscards = max(
          webrtcVideoBroadcasterRotationDiscards,
          _intFromMarker(marker, 'rotation_discards') ?? 0,
        );
        webrtcVideoBroadcasterUpdateRectCleared = max(
          webrtcVideoBroadcasterUpdateRectCleared,
          _intFromMarker(marker, 'update_rect_cleared') ?? 0,
        );
        webrtcVideoBroadcasterDiscardedFrames = max(
          webrtcVideoBroadcasterDiscardedFrames,
          _intFromMarker(marker, 'discarded_frames') ?? 0,
        );
      }

      if (marker
          .toLowerCase()
          .contains('webrtc sender handoff video_stream_encoder stats')) {
        addMarkerDouble(
          marker,
          'post_to_onframe_ms',
          webrtcVsePostToOnFrameMsValues,
        );
        addMarkerDouble(
          marker,
          'post_to_onframe_max_ms',
          webrtcVsePostToOnFrameMaxMsValues,
        );
        addMarkerDouble(marker, 'onframe_ms', webrtcVseOnFrameMsValues);
        addMarkerDouble(
          marker,
          'onframe_max_ms',
          webrtcVseOnFrameMaxMsValues,
        );
        webrtcVseOnFrameSamples = max(
          webrtcVseOnFrameSamples,
          _intFromMarker(marker, 'onframe_calls') ?? 0,
        );
        webrtcVseQueueOverloadDrops = max(
          webrtcVseQueueOverloadDrops,
          _intFromMarker(marker, 'queue_overload_drops') ?? 0,
        );
        webrtcVseEncoderQueueDrops = max(
          webrtcVseEncoderQueueDrops,
          _intFromMarker(marker, 'encoder_queue_drops') ?? 0,
        );
        webrtcVseCwndDrops = max(
          webrtcVseCwndDrops,
          _intFromMarker(marker, 'cwnd_drops') ?? 0,
        );
        webrtcVseBadTimestampDrops = max(
          webrtcVseBadTimestampDrops,
          _intFromMarker(marker, 'bad_timestamp_drops') ?? 0,
        );
        addMarkerDouble(
          marker,
          'maybe_encode_ms',
          webrtcVseMaybeEncodeMsValues,
        );
        addMarkerDouble(
          marker,
          'maybe_encode_max_ms',
          webrtcVseMaybeEncodeMaxMsValues,
        );
        webrtcVseMaybeEncodeSamples = max(
          webrtcVseMaybeEncodeSamples,
          _intFromMarker(marker, 'maybe_encode_calls') ?? 0,
        );
        webrtcVsePendingReplacedDrops = max(
          webrtcVsePendingReplacedDrops,
          _intFromMarker(marker, 'pending_replaced_drops') ?? 0,
        );
        webrtcVseSizeDrops = max(
          webrtcVseSizeDrops,
          _intFromMarker(marker, 'size_drops') ?? 0,
        );
        webrtcVsePausedDrops = max(
          webrtcVsePausedDrops,
          _intFromMarker(marker, 'paused_drops') ?? 0,
        );
        webrtcVseMediaOptimizationDrops = max(
          webrtcVseMediaOptimizationDrops,
          _intFromMarker(marker, 'media_optimization_drops') ?? 0,
        );
        addMarkerDouble(
          marker,
          'encode_frame_ms',
          webrtcVseEncodeFrameMsValues,
        );
        addMarkerDouble(
          marker,
          'encode_frame_max_ms',
          webrtcVseEncodeFrameMaxMsValues,
        );
        webrtcVseEncodeFrameSamples = max(
          webrtcVseEncodeFrameSamples,
          _intFromMarker(marker, 'encode_frame_calls') ?? 0,
        );
        addMarkerDouble(
          marker,
          'video_encoder_encode_ms',
          webrtcVideoEncoderEncodeMsValues,
        );
        addMarkerDouble(
          marker,
          'video_encoder_encode_max_ms',
          webrtcVideoEncoderEncodeMaxMsValues,
        );
        webrtcVideoEncoderEncodeSamples = max(
          webrtcVideoEncoderEncodeSamples,
          _intFromMarker(marker, 'video_encoder_encode_calls') ?? 0,
        );
        webrtcVseEncodeFailures = max(
          webrtcVseEncodeFailures,
          _intFromMarker(marker, 'encode_failures') ?? 0,
        );
        webrtcVseEncodeSkippedBeforeEncoder = max(
          webrtcVseEncodeSkippedBeforeEncoder,
          _intFromMarker(marker, 'encode_skipped_before_encoder') ?? 0,
        );
      }

      if (marker
          .toLowerCase()
          .contains('media foundation h.264 encoded callback timing')) {
        addMarkerDouble(
          marker,
          'callback_ms',
          encoderEncodedCallbackValues,
        );
        addMarkerDouble(
          marker,
          'queue_wait_ms',
          encoderEncodedCallbackQueueWaitValues,
        );
        encoderMaxEncodedCallbackQueueDepth = max(
          encoderMaxEncodedCallbackQueueDepth,
          _intFromMarker(marker, 'queue_depth') ?? 0,
        );
        encoderMaxEncodedCallbackDrops = max(
          encoderMaxEncodedCallbackDrops,
          _intFromMarker(marker, 'callback_drops') ?? 0,
        );
        encoderMaxEncodedCallbackOutputs = max(
          encoderMaxEncodedCallbackOutputs,
          _intFromMarker(marker, 'callback_outputs') ?? 0,
        );
        if (_boolFromMarker(marker, 'async') == true) {
          encoderEncodedCallbackAsyncFrames++;
        }
      }

      final encoderMatch = _mediaFoundationTimingPattern.firstMatch(marker);
      if (encoderMatch != null) {
        final totalMs = _doubleGroup(encoderMatch, 1);
        if (totalMs != null && totalMs > 0) {
          encoderTotalValues.add(totalMs);
        }
        if ((_stringGroup(encoderMatch, 2) ?? '').toLowerCase() == 'yes') {
          encoderSlowFrameCount++;
        }
        final stage = _tokenFromMarker(marker, 'stage');
        if (stage != null) {
          encoderStages.add(stage);
        }
        final inputPath = _tokenFromMarker(marker, 'input_path');
        if (inputPath != null) {
          encoderInputPaths.add(inputPath);
        }
        final nativeInput = _boolFromMarker(marker, 'native_input');
        if (inputPath == 'native_nv12') {
          encoderNativeInputFrames++;
        } else if (inputPath == 'cpu_i420') {
          encoderCpuI420InputFrames++;
        } else if (nativeInput == true) {
          encoderNativeInputFrames++;
        } else if (nativeInput == false) {
          encoderCpuI420InputFrames++;
        }
        if (_boolFromMarker(marker, 'native_sample_failed') == true) {
          encoderNativeSampleFailures++;
        }
        if (_boolFromMarker(marker, 'native_suspended') == true) {
          encoderNativeSuspendedFrames++;
        }
        if (_boolFromMarker(marker, 'native_ready_fence') == true) {
          encoderNativeReadyFenceFrames++;
        }
        if (_boolFromMarker(marker, 'native_ready_fence_timeout') == true) {
          encoderNativeReadyFenceTimeoutFrames++;
        }
        addMarkerDouble(
          marker,
          'native_ready_fence_wait_ms',
          encoderNativeReadyFenceWaitValues,
        );
        encoderNativeSourceMode =
            _tokenFromMarker(marker, 'native_source_mode') ??
                encoderNativeSourceMode;
        encoderNativeSourceFormat =
            _intFromMarker(marker, 'native_source_format') ??
                encoderNativeSourceFormat;
        encoderNativeSourceFrameIndex = max(
          encoderNativeSourceFrameIndex,
          _intFromMarker(marker, 'native_source_frame') ?? 0,
        );
        addMarkerDouble(
          marker,
          'native_source_age_ms',
          encoderNativeSourceAgeValues,
        );
        addMarkerDouble(
          marker,
          'native_source_age_at_create_ms',
          encoderNativeSourceAgeAtCreateValues,
        );
        addMarkerDouble(
          marker,
          'native_buffer_age_ms',
          encoderNativeBufferAgeValues,
        );
        addMarkerDouble(
          marker,
          'native_sample_lifetime_ms',
          encoderNativeSampleLifetimeValues,
        );
        addMarkerDouble(
          marker,
          'native_sample_lifetime_max_ms',
          encoderNativeSampleLifetimeMaxValues,
        );
        encoderNativeSampleLifetimeSamples = max(
          encoderNativeSampleLifetimeSamples,
          _intFromMarker(marker, 'native_sample_lifetime_samples') ?? 0,
        );
        encoderNativeAdapterLuid =
            _tokenFromMarker(marker, 'native_adapter_luid') ??
                encoderNativeAdapterLuid;
        encoderNativeAdapterVendorId =
            _intFromMarker(marker, 'native_adapter_vendor_id') ??
                encoderNativeAdapterVendorId;
        encoderNativeAdapterDeviceId =
            _intFromMarker(marker, 'native_adapter_device_id') ??
                encoderNativeAdapterDeviceId;
        addMarkerDouble(
          marker,
          'process_input_ms',
          encoderProcessInputValues,
        );
        addMarkerDouble(
          marker,
          'process_output_ms',
          encoderProcessOutputValues,
        );
        addMarkerDouble(
          marker,
          'encoded_callback_ms',
          encoderEncodedCallbackValues,
        );
        addMarkerDouble(
          marker,
          'encoded_callback_enqueue_ms',
          encoderEncodedCallbackEnqueueValues,
        );
        if (_boolFromMarker(marker, 'encoded_callback_async') == true) {
          encoderEncodedCallbackAsyncFrames++;
        }
        encoderMaxEncodedCallbackQueueDepth = max(
          encoderMaxEncodedCallbackQueueDepth,
          _intFromMarker(marker, 'encoded_callback_queue_depth') ?? 0,
        );
        encoderMaxEncodedCallbackDrops = max(
          encoderMaxEncodedCallbackDrops,
          _intFromMarker(marker, 'encoded_callback_drops') ?? 0,
        );
        encoderOutputFrames += _intFromMarker(marker, 'outputs') ?? 0;
        encoderOutputBytes += _intFromMarker(marker, 'output_bytes') ?? 0;
        encoderMaxQueueDepth = max(
          encoderMaxQueueDepth,
          _intFromMarker(marker, 'queue') ?? 0,
        );
        encoderMaxRetainedSamples = max(
          encoderMaxRetainedSamples,
          _intFromMarker(marker, 'retained_samples') ?? 0,
        );
        encoderMaxEncodedOutputs = max(
          encoderMaxEncodedOutputs,
          _intFromMarker(marker, 'encoded_outputs') ?? 0,
        );
      }
    }

    return StreamTestNativeDiagnostics(
      captureBackendMode: captureBackendMode,
      observedCapturer: observedCapturer,
      observedCapturerId: observedCapturerId,
      dirtyRegionMode: dirtyRegionMode,
      windowGdiCaptureMode: windowGdiCaptureMode,
      sourceType: sourceType,
      nativeSourceWidth: nativeSourceWidth,
      nativeSourceHeight: nativeSourceHeight,
      requestedMaxWidth: requestedMaxWidth,
      requestedMaxHeight: requestedMaxHeight,
      nativeWindowRectWidth: nativeWindowRectWidth,
      nativeWindowRectHeight: nativeWindowRectHeight,
      contentWidth: contentWidth,
      contentHeight: contentHeight,
      preEncodeWidth: preEncodeWidth,
      preEncodeHeight: preEncodeHeight,
      canvas: canvas,
      cropRegion: cropRegion,
      averageNativeFps: _average(nativeFpsValues),
      averageSubmittedFps: _average(submittedFpsValues),
      targetNativeFps: _average(targetFpsValues),
      averageCaptureCallMs: _average(captureCallValues),
      maxCaptureCallMs: _maxDouble(maxCaptureCallValues),
      averageSourceCaptureMs: sourceCaptureWeightedSampleCount > 0
          ? sourceCaptureWeightedTotalMs / sourceCaptureWeightedSampleCount
          : _average(sourceCaptureValues),
      maxSourceCaptureMs: _maxDouble(maxSourceCaptureValues),
      sourceCaptureSampleCount: sourceCaptureSampleCount,
      wgcCaptureCalls: wgcCaptureCalls,
      wgcCaptureSuccessCount: wgcCaptureSuccessCount,
      wgcSourceNotCapturableCount: wgcSourceNotCapturableCount,
      wgcEnsureFrameCalls: wgcEnsureFrameCalls,
      wgcEnsureSleepCount: wgcEnsureSleepCount,
      wgcProcessFrameCalls: wgcProcessFrameCalls,
      wgcProcessFrameSuccessCount: wgcProcessFrameSuccessCount,
      wgcFramePoolEmptyCount: wgcFramePoolEmptyCount,
      wgcFramePoolReuseCount: wgcFramePoolReuseCount,
      wgcCaptureFrameNullCount: wgcCaptureFrameNullCount,
      wgcMappedTextureCreateCount: wgcMappedTextureCreateCount,
      wgcResizeCount: wgcResizeCount,
      wgcFramePoolRecreateCount: wgcFramePoolRecreateCount,
      averageWgcGetFrameMs: _average(wgcGetFrameValues),
      maxWgcGetFrameMs: _maxDouble(wgcMaxGetFrameValues),
      averageWgcEnsureFrameMs: _average(wgcEnsureFrameValues),
      maxWgcEnsureFrameMs: _maxDouble(wgcMaxEnsureFrameValues),
      averageWgcProcessFrameMs: _average(wgcProcessFrameValues),
      maxWgcProcessFrameMs: _maxDouble(wgcMaxProcessFrameValues),
      averageWgcTryGetFrameMs: _average(wgcTryGetFrameValues),
      maxWgcTryGetFrameMs: _maxDouble(wgcMaxTryGetFrameValues),
      averageWgcSurfaceMs: _average(wgcSurfaceValues),
      maxWgcSurfaceMs: _maxDouble(wgcMaxSurfaceValues),
      averageWgcTextureMs: _average(wgcTextureValues),
      maxWgcTextureMs: _maxDouble(wgcMaxTextureValues),
      averageWgcContentSizeMs: _average(wgcContentSizeValues),
      maxWgcContentSizeMs: _maxDouble(wgcMaxContentSizeValues),
      averageWgcCopyTextureMs: _average(wgcCopyTextureValues),
      maxWgcCopyTextureMs: _maxDouble(wgcMaxCopyTextureValues),
      averageWgcMapTextureMs: _average(wgcMapTextureValues),
      maxWgcMapTextureMs: _maxDouble(wgcMaxMapTextureValues),
      averageWgcCopyRowsMs: _average(wgcCopyRowsValues),
      maxWgcCopyRowsMs: _maxDouble(wgcMaxCopyRowsValues),
      averageWgcMonitorScaleMs: _average(wgcMonitorScaleValues),
      maxWgcMonitorScaleMs: _maxDouble(wgcMaxMonitorScaleValues),
      averageWgcZeroHertzMs: _average(wgcZeroHertzValues),
      maxWgcZeroHertzMs: _maxDouble(wgcMaxZeroHertzValues),
      gdiCaptureCalls: gdiCaptureCalls,
      gdiCaptureSuccessCount: gdiCaptureSuccessCount,
      gdiTemporaryErrorCount: gdiTemporaryErrorCount,
      gdiPermanentErrorCount: gdiPermanentErrorCount,
      gdiHiddenOrMinimizedCount: gdiHiddenOrMinimizedCount,
      gdiRectFailCount: gdiRectFailCount,
      gdiDcFailCount: gdiDcFailCount,
      gdiFrameCreateFailCount: gdiFrameCreateFailCount,
      gdiPrintFullCallCount: gdiPrintFullCallCount,
      gdiPrintFullSuccessCount: gdiPrintFullSuccessCount,
      gdiPrintFallbackCallCount: gdiPrintFallbackCallCount,
      gdiPrintFallbackSuccessCount: gdiPrintFallbackSuccessCount,
      gdiBitBltCallCount: gdiBitBltCallCount,
      gdiBitBltSuccessCount: gdiBitBltSuccessCount,
      gdiFinalPrintFullCount: gdiFinalPrintFullCount,
      gdiFinalPrintFallbackCount: gdiFinalPrintFallbackCount,
      gdiFinalBitBltCount: gdiFinalBitBltCount,
      gdiFinalNoneCount: gdiFinalNoneCount,
      gdiBlackFrameCount: gdiBlackFrameCount,
      gdiLowVarianceFrameCount: gdiLowVarianceFrameCount,
      gdiOwnedWindowFrameCount: gdiOwnedWindowFrameCount,
      gdiOwnedWindowCaptureCallCount: gdiOwnedWindowCaptureCallCount,
      gdiOwnedWindowCaptureSuccessCount: gdiOwnedWindowCaptureSuccessCount,
      gdiOriginalWidth: gdiOriginalWidth,
      gdiOriginalHeight: gdiOriginalHeight,
      gdiCroppedWidth: gdiCroppedWidth,
      gdiCroppedHeight: gdiCroppedHeight,
      gdiFrameWidth: gdiFrameWidth,
      gdiFrameHeight: gdiFrameHeight,
      averageGdiTotalMs: _average(gdiTotalValues),
      maxGdiTotalMs: _maxDouble(gdiMaxTotalValues),
      averageGdiRectMs: _average(gdiRectValues),
      maxGdiRectMs: _maxDouble(gdiMaxRectValues),
      averageGdiVisibilityMs: _average(gdiVisibilityValues),
      maxGdiVisibilityMs: _maxDouble(gdiMaxVisibilityValues),
      averageGdiGetDcMs: _average(gdiGetDcValues),
      maxGdiGetDcMs: _maxDouble(gdiMaxGetDcValues),
      averageGdiGetDcSizeMs: _average(gdiGetDcSizeValues),
      maxGdiGetDcSizeMs: _maxDouble(gdiMaxGetDcSizeValues),
      averageGdiCreateFrameMs: _average(gdiCreateFrameValues),
      maxGdiCreateFrameMs: _maxDouble(gdiMaxCreateFrameValues),
      averageGdiMemDcMs: _average(gdiMemDcValues),
      maxGdiMemDcMs: _maxDouble(gdiMaxMemDcValues),
      averageGdiPrintFullMs: _average(gdiPrintFullValues),
      maxGdiPrintFullMs: _maxDouble(gdiMaxPrintFullValues),
      averageGdiPrintFallbackMs: _average(gdiPrintFallbackValues),
      maxGdiPrintFallbackMs: _maxDouble(gdiMaxPrintFallbackValues),
      averageGdiBitBltMs: _average(gdiBitBltValues),
      maxGdiBitBltMs: _maxDouble(gdiMaxBitBltValues),
      averageGdiCleanupMs: _average(gdiCleanupValues),
      maxGdiCleanupMs: _maxDouble(gdiMaxCleanupValues),
      averageGdiCropMs: _average(gdiCropValues),
      maxGdiCropMs: _maxDouble(gdiMaxCropValues),
      averageGdiOwnedEnumMs: _average(gdiOwnedEnumValues),
      maxGdiOwnedEnumMs: _maxDouble(gdiMaxOwnedEnumValues),
      averageGdiOwnedCaptureMs: _average(gdiOwnedCaptureValues),
      maxGdiOwnedCaptureMs: _maxDouble(gdiMaxOwnedCaptureValues),
      averageGdiOwnedCompositeMs: _average(gdiOwnedCompositeValues),
      maxGdiOwnedCompositeMs: _maxDouble(gdiMaxOwnedCompositeValues),
      averageCallbackEntryDelayMs: _average(callbackEntryDelayValues),
      maxCallbackEntryDelayMs: _maxDouble(maxCallbackEntryDelayValues),
      averageCaptureResultCallbackMs: _average(captureResultCallbackValues),
      maxCaptureResultCallbackMs: _maxDouble(maxCaptureResultCallbackValues),
      averageCaptureAcquireWaitMs: _average(captureAcquireWaitValues),
      maxCaptureAcquireWaitMs: _maxDouble(maxCaptureAcquireWaitValues),
      averagePostCallbackWaitMs: _average(postCallbackWaitValues),
      maxPostCallbackWaitMs: _maxDouble(maxPostCallbackWaitValues),
      averageUnaccountedWaitMs: _average(unaccountedWaitValues),
      maxUnaccountedWaitMs: _maxDouble(maxUnaccountedWaitValues),
      captureResultCallbackCount: captureResultCallbackCount,
      maxFrameIntervalMs: _maxDouble(maxFrameIntervalValues),
      p95FrameIntervalMs: _average(p95FrameIntervalValues),
      captureWaitTimeoutCount:
          parsedFrameCadence ? frameWaitTimeoutCount : scheduleWaitTimeoutCount,
      capturePermanentErrorCount: parsedFrameCadence
          ? framePermanentErrorCount
          : schedulePermanentErrorCount,
      duplicatedFrameCount: duplicatedFrameCount,
      staleFrameReuseCount: staleFrameReuseCount,
      averageFrameConvertMs: _average(frameConvertValues),
      averageFrameScaleMs: _average(frameScaleValues),
      averageFrameOnFrameMs: _average(frameOnFrameValues),
      averageFrameCallbackMs: _average(frameCallbackValues),
      maxFrameCallbackMs: _maxDouble(maxFrameCallbackValues),
      updatedRegionEmptyCount: updatedRegionEmptyCount,
      updatedRegionNonEmptyCount: updatedRegionNonEmptyCount,
      updatedRegionRectCount: updatedRegionRectCount,
      updatedRegionMaxRectCount: updatedRegionMaxRectCount,
      averageUpdatedRegionAreaRatio: updatedRegionAreaRatioWeightedFrames > 0
          ? updatedRegionAreaRatioWeightedTotal /
              updatedRegionAreaRatioWeightedFrames
          : _average(updatedRegionAreaRatioValues),
      maxUpdatedRegionAreaRatio: _maxDouble(maxUpdatedRegionAreaRatioValues),
      averageUpdatedRegionAnalysisMs: updatedRegionAnalysisWeightedFrames > 0
          ? updatedRegionAnalysisWeightedTotal /
              updatedRegionAnalysisWeightedFrames
          : _average(updatedRegionAnalysisValues),
      maxUpdatedRegionAnalysisMs: _maxDouble(maxUpdatedRegionAnalysisValues),
      updatedRegionFullFrameCount: updatedRegionFullFrameCount,
      updatedRegionTinyFrameCount: updatedRegionTinyFrameCount,
      latestFramePacerEnabled: latestFramePacerEnabled,
      averagePacerSubmittedFps: _average(pacerSubmittedFpsValues),
      averagePacerUniqueFps: _average(pacerUniqueFpsValues),
      p95PacerIntervalMs: _average(p95PacerIntervalValues),
      maxPacerIntervalMs: _maxDouble(maxPacerIntervalValues),
      averagePacerFrameAgeMs: _average(pacerFrameAgeValues),
      maxPacerFrameAgeMs: _maxDouble(maxPacerFrameAgeValues),
      averagePacerOnFrameMs: _average(pacerOnFrameValues),
      maxPacerOnFrameMs: _maxDouble(maxPacerOnFrameValues),
      pacerDuplicateSubmitCount: pacerDuplicateSubmitCount,
      pacerOverwrittenFrameCount: pacerOverwrittenFrameCount,
      pacerSkippedTickCount: pacerSkippedTickCount,
      gameCaptureSourceWidth: gameCaptureSourceWidth,
      gameCaptureSourceHeight: gameCaptureSourceHeight,
      gameCaptureOutputWidth: gameCaptureOutputWidth,
      gameCaptureOutputHeight: gameCaptureOutputHeight,
      gameCaptureFormat: gameCaptureFormat,
      gameCaptureBackendContractVersion: gameCaptureBackendContractVersion,
      gameCaptureSourceMode: gameCaptureSourceMode,
      gameCaptureSourceApi: gameCaptureSourceApi,
      gameCaptureSourceApiId: gameCaptureSourceApiId,
      gameCaptureSourceFormat: gameCaptureSourceFormat,
      gameCaptureSourceFormatId: gameCaptureSourceFormatId,
      gameCaptureColorSpace: gameCaptureColorSpace,
      gameCaptureSyncKind: gameCaptureSyncKind,
      gameCaptureReadyState: gameCaptureReadyState,
      gameCaptureFailureReason: gameCaptureFailureReason,
      gameCaptureConsumerAdapterLuid: gameCaptureConsumerAdapterLuid,
      gameCaptureConsumerAdapterVendorId: gameCaptureConsumerAdapterVendorId,
      gameCaptureConsumerAdapterDeviceId: gameCaptureConsumerAdapterDeviceId,
      gameCaptureSourceAdapterLuid: gameCaptureSourceAdapterLuid,
      gameCaptureCrossAdapterSuspected: gameCaptureCrossAdapterSuspected,
      averageGameCaptureFps: _average(gameCaptureFpsValues),
      gameCaptureSubmittedFrames: gameCaptureSubmittedFrames,
      gameCaptureRepeatedFrames: gameCaptureRepeatedFrames,
      gameCaptureDuplicateSkippedFrames: gameCaptureDuplicateSkippedFrames,
      gameCaptureDeliveryQueuedFrames: gameCaptureDeliveryQueuedFrames,
      gameCaptureDeliverySubmittedFrames: gameCaptureDeliverySubmittedFrames,
      gameCaptureDeliveryOverwrittenFrames:
          gameCaptureDeliveryOverwrittenFrames,
      gameCaptureDeliveryPacerResyncs: gameCaptureDeliveryPacerResyncs,
      gameCaptureDeliveryPacerLagMaxMs: gameCaptureDeliveryPacerLagMaxMs,
      gameCaptureDeliveryRepeatNoQueuedFrames:
          gameCaptureDeliveryRepeatNoQueuedFrames,
      gameCaptureDeliverySkipNoQueuedFrames:
          gameCaptureDeliverySkipNoQueuedFrames,
      gameCaptureDeliveryFreshWakeAfterSkipFrames:
          gameCaptureDeliveryFreshWakeAfterSkipFrames,
      gameCaptureDeliveryFreshImmediateFrames:
          gameCaptureDeliveryFreshImmediateFrames,
      gameCaptureDeliveryRepeatPolicy: gameCaptureDeliveryRepeatPolicy,
      gameCaptureDeliveryQueueDepth: gameCaptureDeliveryQueueDepth,
      averageGameCaptureDeliveryRepeatSourceAgeMs:
          _average(gameCaptureDeliveryRepeatSourceAgeMsValues),
      maxGameCaptureDeliveryRepeatSourceAgeMs:
          _maxDouble(gameCaptureDeliveryRepeatSourceAgeMaxMsValues),
      gameCaptureDeliveryRepeatSourceAgeSamples:
          gameCaptureDeliveryRepeatSourceAgeSamples,
      averageGameCaptureDeliveryOnFrameMs:
          _average(gameCaptureDeliveryOnFrameMsValues),
      maxGameCaptureDeliveryOnFrameMs:
          _maxDouble(gameCaptureDeliveryOnFrameMaxMsValues),
      averageGameCaptureDeliverySubmitPrepMs:
          _average(gameCaptureDeliverySubmitPrepMsValues),
      maxGameCaptureDeliverySubmitPrepMs:
          _maxDouble(gameCaptureDeliverySubmitPrepMaxMsValues),
      gameCaptureDeliverySubmitPrepSamples:
          gameCaptureDeliverySubmitPrepSamples,
      averageGameCaptureDeliveryOnFrameCallMs:
          _average(gameCaptureDeliveryOnFrameCallMsValues),
      maxGameCaptureDeliveryOnFrameCallMs:
          _maxDouble(gameCaptureDeliveryOnFrameCallMaxMsValues),
      gameCaptureDeliveryOnFrameCallSamples:
          gameCaptureDeliveryOnFrameCallSamples,
      averageGameCaptureDeliveryPostOnFrameMs:
          _average(gameCaptureDeliveryPostOnFrameMsValues),
      maxGameCaptureDeliveryPostOnFrameMs:
          _maxDouble(gameCaptureDeliveryPostOnFrameMaxMsValues),
      gameCaptureDeliveryPostOnFrameSamples:
          gameCaptureDeliveryPostOnFrameSamples,
      averageGameCaptureNativeBufferReleaseMs:
          _average(gameCaptureNativeBufferReleaseMsValues),
      maxGameCaptureNativeBufferReleaseMs:
          _maxDouble(gameCaptureNativeBufferReleaseMaxMsValues),
      gameCaptureNativeBufferReleaseSamples:
          gameCaptureNativeBufferReleaseSamples,
      averageGameCaptureReadyToQueueMs:
          _average(gameCaptureReadyToQueueMsValues),
      maxGameCaptureReadyToQueueMs:
          _maxDouble(gameCaptureReadyToQueueMaxMsValues),
      gameCaptureReadyToQueueSamples: gameCaptureReadyToQueueSamples,
      averageGameCaptureDeliveryQueueWaitMs:
          _average(gameCaptureDeliveryQueueWaitMsValues),
      maxGameCaptureDeliveryQueueWaitMs:
          _maxDouble(gameCaptureDeliveryQueueWaitMaxMsValues),
      gameCaptureDeliveryQueueWaitSamples: gameCaptureDeliveryQueueWaitSamples,
      averageGameCaptureDeliveryOverwriteAgeMs:
          _average(gameCaptureDeliveryOverwriteAgeMsValues),
      maxGameCaptureDeliveryOverwriteAgeMs:
          _maxDouble(gameCaptureDeliveryOverwriteAgeMaxMsValues),
      gameCaptureDeliveryOverwriteAgeSamples:
          gameCaptureDeliveryOverwriteAgeSamples,
      gameCaptureDeliveryOverwrittenFreshFrames:
          gameCaptureDeliveryOverwrittenFreshFrames,
      averageGameCaptureReadyToSubmitMs:
          _average(gameCaptureReadyToSubmitMsValues),
      maxGameCaptureReadyToSubmitMs:
          _maxDouble(gameCaptureReadyToSubmitMaxMsValues),
      gameCaptureReadyToSubmitSamples: gameCaptureReadyToSubmitSamples,
      averageGameCaptureSourceToSubmitMs:
          _average(gameCaptureSourceToSubmitMsValues),
      maxGameCaptureSourceToSubmitMs:
          _maxDouble(gameCaptureSourceToSubmitMaxMsValues),
      gameCaptureSourceToSubmitSamples: gameCaptureSourceToSubmitSamples,
      averageGameCaptureSourceToReadbackReadyMs:
          _average(gameCaptureSourceToReadbackReadyMsValues),
      maxGameCaptureSourceToReadbackReadyMs:
          _maxDouble(gameCaptureSourceToReadbackReadyMaxMsValues),
      gameCaptureSourceToReadbackReadySamples:
          gameCaptureSourceToReadbackReadySamples,
      averageGameCaptureReadbackQueueToMapMs:
          _average(gameCaptureReadbackQueueToMapMsValues),
      maxGameCaptureReadbackQueueToMapMs:
          _maxDouble(gameCaptureReadbackQueueToMapMaxMsValues),
      gameCaptureReadbackQueueToMapSamples:
          gameCaptureReadbackQueueToMapSamples,
      averageGameCaptureMapToI420Ms: _average(gameCaptureMapToI420MsValues),
      maxGameCaptureMapToI420Ms: _maxDouble(gameCaptureMapToI420MaxMsValues),
      gameCaptureMapToI420Samples: gameCaptureMapToI420Samples,
      averageGameCaptureSourceToI420ReadyMs:
          _average(gameCaptureSourceToI420ReadyMsValues),
      maxGameCaptureSourceToI420ReadyMs:
          _maxDouble(gameCaptureSourceToI420ReadyMaxMsValues),
      gameCaptureSourceToI420ReadySamples: gameCaptureSourceToI420ReadySamples,
      averageGameCaptureSourceToQueueMs:
          _average(gameCaptureSourceToQueueMsValues),
      maxGameCaptureSourceToQueueMs:
          _maxDouble(gameCaptureSourceToQueueMaxMsValues),
      gameCaptureSourceToQueueSamples: gameCaptureSourceToQueueSamples,
      averageGameCaptureSourceDuplicateSkipAgeMs:
          _average(gameCaptureSourceDuplicateSkipAgeMsValues),
      maxGameCaptureSourceDuplicateSkipAgeMs:
          _maxDouble(gameCaptureSourceDuplicateSkipAgeMaxMsValues),
      gameCaptureSourceDuplicateSkipAgeSamples:
          gameCaptureSourceDuplicateSkipAgeSamples,
      gameCaptureCopiedFrames: gameCaptureCopiedFrames,
      gameCaptureDroppedFrames: gameCaptureDroppedFrames,
      gameCaptureOverwrittenFrames: gameCaptureOverwrittenFrames,
      gameCaptureGpuScaledFrames: gameCaptureGpuScaledFrames,
      gameCaptureGpuScaleFailures: gameCaptureGpuScaleFailures,
      gameCaptureCpuFallbackFrames: gameCaptureCpuFallbackFrames,
      gameCaptureNativeNv12SubmittedFrames:
          gameCaptureNativeNv12SubmittedFrames,
      gameCaptureNativeNv12QueuedFrames: gameCaptureNativeNv12QueuedFrames,
      gameCaptureNativeNv12ReadyFrames: gameCaptureNativeNv12ReadyFrames,
      gameCaptureNativeNv12NotReadyPolls: gameCaptureNativeNv12NotReadyPolls,
      gameCaptureNativeNv12ReadyPolicy: gameCaptureNativeNv12ReadyPolicy,
      gameCaptureNativeNv12FenceAvailable: gameCaptureNativeNv12FenceAvailable,
      gameCaptureNativeNv12PendingPollMs: gameCaptureNativeNv12PendingPollMs,
      gameCaptureNativeNv12MaxPendingSlots:
          gameCaptureNativeNv12MaxPendingSlots,
      gameCaptureNativeNv12ReadyDrainDepth:
          gameCaptureNativeNv12ReadyDrainDepth,
      gameCaptureNativeNv12FrameOwnership: gameCaptureNativeNv12FrameOwnership,
      gameCaptureNativeNv12FenceSignaledFrames:
          gameCaptureNativeNv12FenceSignaledFrames,
      gameCaptureNativeNv12FenceReadyFrames:
          gameCaptureNativeNv12FenceReadyFrames,
      gameCaptureNativeNv12FenceSignalFailures:
          gameCaptureNativeNv12FenceSignalFailures,
      gameCaptureNativeNv12OwnedCopies: gameCaptureNativeNv12OwnedCopies,
      averageGameCaptureNativeNv12OwnedCopyMs:
          _average(gameCaptureNativeNv12OwnedCopyMsValues),
      maxGameCaptureNativeNv12OwnedCopyMs:
          _maxDouble(gameCaptureNativeNv12OwnedCopyMaxMsValues),
      gameCaptureNativeNv12OwnedCopySamples:
          gameCaptureNativeNv12OwnedCopySamples,
      gameCaptureNativeNv12OverwrittenFrames:
          gameCaptureNativeNv12OverwrittenFrames,
      averageGameCaptureNativeNv12OverwriteAgeMs:
          _average(gameCaptureNativeNv12OverwriteAgeMsValues),
      maxGameCaptureNativeNv12OverwriteAgeMs:
          _maxDouble(gameCaptureNativeNv12OverwriteAgeMaxMsValues),
      gameCaptureNativeNv12OverwriteAgeSamples:
          gameCaptureNativeNv12OverwriteAgeSamples,
      gameCaptureNativeNv12OverwrittenFreshFrames:
          gameCaptureNativeNv12OverwrittenFreshFrames,
      gameCaptureNativeNv12ReadyDroppedFrames:
          gameCaptureNativeNv12ReadyDroppedFrames,
      averageGameCaptureNativeNv12ReadyDropAgeMs:
          _average(gameCaptureNativeNv12ReadyDropAgeMsValues),
      maxGameCaptureNativeNv12ReadyDropAgeMs:
          _maxDouble(gameCaptureNativeNv12ReadyDropAgeMaxMsValues),
      gameCaptureNativeNv12ReadyDropAgeSamples:
          gameCaptureNativeNv12ReadyDropAgeSamples,
      gameCaptureNativeNv12ReadyDroppedFreshFrames:
          gameCaptureNativeNv12ReadyDroppedFreshFrames,
      gameCaptureNativeNv12Failures: gameCaptureNativeNv12Failures,
      averageGameCaptureNativeNv12ConvertMs:
          _average(gameCaptureNativeNv12ConvertMsValues),
      maxGameCaptureNativeNv12ConvertMs:
          _maxDouble(gameCaptureNativeNv12ConvertMaxMsValues),
      gameCaptureNativeNv12ConvertSamples: gameCaptureNativeNv12ConvertSamples,
      averageGameCaptureNativeNv12BgraScaleDrawMs:
          _average(gameCaptureNativeNv12BgraScaleDrawMsValues),
      maxGameCaptureNativeNv12BgraScaleDrawMs:
          _maxDouble(gameCaptureNativeNv12BgraScaleDrawMaxMsValues),
      gameCaptureNativeNv12BgraScaleDrawSamples:
          gameCaptureNativeNv12BgraScaleDrawSamples,
      averageGameCaptureNativeNv12VideoProcessorBltSubmitMs:
          _average(gameCaptureNativeNv12VideoProcessorBltSubmitMsValues),
      maxGameCaptureNativeNv12VideoProcessorBltSubmitMs:
          _maxDouble(gameCaptureNativeNv12VideoProcessorBltSubmitMaxMsValues),
      gameCaptureNativeNv12VideoProcessorBltSubmitSamples:
          gameCaptureNativeNv12VideoProcessorBltSubmitSamples,
      averageGameCaptureNativeNv12VideoProcessorBltToReadyMs:
          _average(gameCaptureNativeNv12VideoProcessorBltToReadyMsValues),
      maxGameCaptureNativeNv12VideoProcessorBltToReadyMs:
          _maxDouble(gameCaptureNativeNv12VideoProcessorBltToReadyMaxMsValues),
      gameCaptureNativeNv12VideoProcessorBltToReadySamples:
          gameCaptureNativeNv12VideoProcessorBltToReadySamples,
      averageGameCaptureNativeNv12BufferCreateMs:
          _average(gameCaptureNativeNv12BufferCreateMsValues),
      maxGameCaptureNativeNv12BufferCreateMs:
          _maxDouble(gameCaptureNativeNv12BufferCreateMaxMsValues),
      gameCaptureNativeNv12BufferCreateSamples:
          gameCaptureNativeNv12BufferCreateSamples,
      averageGameCaptureNativeNv12FrameReadyToQueueMs:
          _average(gameCaptureNativeNv12FrameReadyToQueueMsValues),
      maxGameCaptureNativeNv12FrameReadyToQueueMs:
          _maxDouble(gameCaptureNativeNv12FrameReadyToQueueMaxMsValues),
      gameCaptureNativeNv12FrameReadyToQueueSamples:
          gameCaptureNativeNv12FrameReadyToQueueSamples,
      averageGameCaptureNativeNv12ConversionStartAgeMs:
          _average(gameCaptureNativeNv12ConversionStartAgeMsValues),
      maxGameCaptureNativeNv12ConversionStartAgeMs:
          _maxDouble(gameCaptureNativeNv12ConversionStartAgeMaxMsValues),
      gameCaptureNativeNv12ConversionStartAgeSamples:
          gameCaptureNativeNv12ConversionStartAgeSamples,
      gameCaptureNativeNv12StaleBeforeQueueFrames:
          gameCaptureNativeNv12StaleBeforeQueueFrames,
      gameCaptureNativeNv12HandoffDisabledReason:
          gameCaptureNativeNv12HandoffDisabledReason,
      gameCaptureReadbackQueuedFrames: gameCaptureReadbackQueuedFrames,
      gameCaptureReadbackReadyFrames: gameCaptureReadbackReadyFrames,
      gameCaptureReadbackNotReadyFrames: gameCaptureReadbackNotReadyFrames,
      gameCaptureReadbackOverwrittenFrames:
          gameCaptureReadbackOverwrittenFrames,
      gameCaptureReadbackStaleDroppedFrames:
          gameCaptureReadbackStaleDroppedFrames,
      gameCaptureReadbackLatencyDroppedFrames:
          gameCaptureReadbackLatencyDroppedFrames,
      gameCaptureReadbackMapAttempts: gameCaptureReadbackMapAttempts,
      gameCaptureSourceFrameIndex: gameCaptureSourceFrameIndex,
      gameCaptureLastSubmittedSourceFrameIndex:
          gameCaptureLastSubmittedSourceFrameIndex,
      gameCaptureSourceFrameRegressions: gameCaptureSourceFrameRegressions,
      gameCaptureSourceFrameDuplicates: gameCaptureSourceFrameDuplicates,
      gameCaptureSourceFrameGaps: gameCaptureSourceFrameGaps,
      gameCaptureSharedSlotMismatches: gameCaptureSharedSlotMismatches,
      gameCaptureTimestampMode: gameCaptureTimestampMode,
      gameCaptureTimestampSourceQpcFrames: gameCaptureTimestampSourceQpcFrames,
      gameCaptureTimestampPacedFallbackFrames:
          gameCaptureTimestampPacedFallbackFrames,
      gameCaptureTimestampRepeatedFrames: gameCaptureTimestampRepeatedFrames,
      averageGameCaptureTimestampDeltaMs:
          _average(gameCaptureTimestampDeltaMsValues),
      maxGameCaptureTimestampDeltaMs:
          _maxDouble(gameCaptureTimestampDeltaMaxMsValues),
      gameCaptureTimestampSamples: gameCaptureTimestampSamples,
      gameCaptureTimestampAdjustments: gameCaptureTimestampAdjustments,
      averageGameCaptureDeliveryWallDeltaMs:
          _average(gameCaptureDeliveryWallDeltaMsValues),
      maxGameCaptureDeliveryWallDeltaMs:
          _maxDouble(gameCaptureDeliveryWallDeltaMaxMsValues),
      minGameCaptureDeliveryWallDeltaMs:
          _minDouble(gameCaptureDeliveryWallDeltaMinMsValues),
      gameCaptureDeliveryWallSamples: gameCaptureDeliveryWallSamples,
      gameCaptureDeliveryWallOver2xFrames: gameCaptureDeliveryWallOver2xFrames,
      gameCaptureDeliveryWallOver3xFrames: gameCaptureDeliveryWallOver3xFrames,
      gameCaptureDeliveryWallUnderHalfFrames:
          gameCaptureDeliveryWallUnderHalfFrames,
      averageGameCaptureSourceQpcDeltaMs:
          _average(gameCaptureSourceQpcDeltaMsValues),
      maxGameCaptureSourceQpcDeltaMs:
          _maxDouble(gameCaptureSourceQpcDeltaMaxMsValues),
      gameCaptureSourceQpcSamples: gameCaptureSourceQpcSamples,
      gameCaptureSourceQpcRegressions: gameCaptureSourceQpcRegressions,
      averageGameCaptureCopyMs: _average(gameCaptureCopyMsValues),
      averageGameCaptureMapMs: _average(gameCaptureMapMsValues),
      averageGameCaptureConvertMs: _average(gameCaptureConvertMsValues),
      averageGameCaptureGpuScaleMs: _average(gameCaptureGpuScaleMsValues),
      averageGameCaptureReadbackLatencyMs:
          _average(gameCaptureReadbackLatencyMsValues),
      averageGameCaptureReadbackLatencyFrames:
          _average(gameCaptureReadbackLatencyFrameValues),
      gameCaptureMaxReadbackLatencyFrames: gameCaptureMaxReadbackLatencyFrames,
      gameCaptureMapFailures: gameCaptureMapFailures,
      gameCaptureConvertFailures: gameCaptureConvertFailures,
      gameCaptureProofFrames: gameCaptureProofFrames,
      gameCaptureVisibleProofFrames: gameCaptureVisibleProofFrames,
      gameCaptureProofVisible: gameCaptureProofVisible,
      gameCaptureProofPath: gameCaptureProofPath,
      gameCaptureProofMinLuma: gameCaptureProofMinLuma,
      gameCaptureProofMaxLuma: gameCaptureProofMaxLuma,
      gameCaptureProofNonzeroSamples: gameCaptureProofNonzeroSamples,
      gameCaptureProofSamples: gameCaptureProofSamples,
      gameCaptureI420ProofFrames: gameCaptureI420ProofFrames,
      gameCaptureVisibleI420ProofFrames: gameCaptureVisibleI420ProofFrames,
      gameCaptureInitialBlackSkippedFrames:
          gameCaptureInitialBlackSkippedFrames,
      gameCaptureVisibleSourceSeen: gameCaptureVisibleSourceSeen,
      gameCaptureI420ProofVisible: gameCaptureI420ProofVisible,
      gameCaptureI420ProofPath: gameCaptureI420ProofPath,
      gameCaptureI420ProofMinLuma: gameCaptureI420ProofMinLuma,
      gameCaptureI420ProofMaxLuma: gameCaptureI420ProofMaxLuma,
      gameCaptureI420ProofNonzeroSamples: gameCaptureI420ProofNonzeroSamples,
      gameCaptureI420ProofSamples: gameCaptureI420ProofSamples,
      averageEncoderTotalMs: _average(encoderTotalValues),
      maxEncoderTotalMs: _maxDouble(encoderTotalValues),
      encoderSlowFrameCount: encoderSlowFrameCount,
      encoderSampleCount: encoderTotalValues.length,
      encoderInputPaths: List.unmodifiable(encoderInputPaths),
      encoderNativeInputFrames: encoderNativeInputFrames,
      encoderCpuI420InputFrames: encoderCpuI420InputFrames,
      encoderNativeSampleFailures: encoderNativeSampleFailures,
      encoderNativeSuspendedFrames: encoderNativeSuspendedFrames,
      encoderNativeReadyFenceFrames: encoderNativeReadyFenceFrames,
      encoderNativeReadyFenceTimeoutFrames:
          encoderNativeReadyFenceTimeoutFrames,
      averageEncoderNativeReadyFenceWaitMs:
          _average(encoderNativeReadyFenceWaitValues),
      maxEncoderNativeReadyFenceWaitMs:
          _maxDouble(encoderNativeReadyFenceWaitValues),
      encoderNativeReadyFenceWaitSamples:
          encoderNativeReadyFenceWaitValues.length,
      encoderNativeSourceMode: encoderNativeSourceMode,
      encoderNativeSourceFormat: encoderNativeSourceFormat,
      encoderNativeSourceFrameIndex: encoderNativeSourceFrameIndex,
      averageEncoderNativeSourceAgeMs: _average(encoderNativeSourceAgeValues),
      maxEncoderNativeSourceAgeMs: _maxDouble(encoderNativeSourceAgeValues),
      encoderNativeSourceAgeSamples: encoderNativeSourceAgeValues.length,
      averageEncoderNativeSourceAgeAtCreateMs:
          _average(encoderNativeSourceAgeAtCreateValues),
      maxEncoderNativeSourceAgeAtCreateMs:
          _maxDouble(encoderNativeSourceAgeAtCreateValues),
      averageEncoderNativeBufferAgeMs: _average(encoderNativeBufferAgeValues),
      maxEncoderNativeBufferAgeMs: _maxDouble(encoderNativeBufferAgeValues),
      encoderNativeBufferAgeSamples: encoderNativeBufferAgeValues.length,
      averageEncoderNativeSampleLifetimeMs:
          _average(encoderNativeSampleLifetimeValues),
      maxEncoderNativeSampleLifetimeMs:
          _maxDouble(encoderNativeSampleLifetimeMaxValues),
      encoderNativeSampleLifetimeSamples: max(
        encoderNativeSampleLifetimeSamples,
        encoderNativeSampleLifetimeValues.length,
      ),
      encoderNativeAdapterLuid: encoderNativeAdapterLuid,
      encoderNativeAdapterVendorId: encoderNativeAdapterVendorId,
      encoderNativeAdapterDeviceId: encoderNativeAdapterDeviceId,
      averageEncoderProcessInputMs: _average(encoderProcessInputValues),
      maxEncoderProcessInputMs: _maxDouble(encoderProcessInputValues),
      encoderProcessInputSamples: encoderProcessInputValues.length,
      averageEncoderProcessOutputMs: _average(encoderProcessOutputValues),
      maxEncoderProcessOutputMs: _maxDouble(encoderProcessOutputValues),
      encoderProcessOutputSamples: encoderProcessOutputValues.length,
      averageEncoderEncodedCallbackMs: _average(encoderEncodedCallbackValues),
      maxEncoderEncodedCallbackMs: _maxDouble(encoderEncodedCallbackValues),
      encoderEncodedCallbackSamples: encoderEncodedCallbackValues.length,
      averageEncoderEncodedCallbackQueueWaitMs:
          _average(encoderEncodedCallbackQueueWaitValues),
      maxEncoderEncodedCallbackQueueWaitMs:
          _maxDouble(encoderEncodedCallbackQueueWaitValues),
      encoderEncodedCallbackQueueWaitSamples:
          encoderEncodedCallbackQueueWaitValues.length,
      averageEncoderEncodedCallbackEnqueueMs:
          _average(encoderEncodedCallbackEnqueueValues),
      maxEncoderEncodedCallbackEnqueueMs:
          _maxDouble(encoderEncodedCallbackEnqueueValues),
      encoderEncodedCallbackEnqueueSamples:
          encoderEncodedCallbackEnqueueValues.length,
      encoderEncodedCallbackAsyncFrames: encoderEncodedCallbackAsyncFrames,
      encoderMaxEncodedCallbackQueueDepth: encoderMaxEncodedCallbackQueueDepth,
      encoderMaxEncodedCallbackDrops: encoderMaxEncodedCallbackDrops,
      encoderMaxEncodedCallbackOutputs: encoderMaxEncodedCallbackOutputs,
      encoderStages: List.unmodifiable(encoderStages),
      encoderOutputFrames: encoderOutputFrames,
      encoderOutputBytes: encoderOutputBytes,
      encoderMaxQueueDepth: encoderMaxQueueDepth,
      encoderMaxRetainedSamples: encoderMaxRetainedSamples,
      encoderMaxEncodedOutputs: encoderMaxEncodedOutputs,
      averageWebrtcSourceOnFrameMs: _average(webrtcSourceOnFrameMsValues),
      maxWebrtcSourceOnFrameMs: _maxDouble(webrtcSourceOnFrameMaxMsValues),
      webrtcSourceOnFrameSamples: webrtcSourceOnFrameSamples,
      averageWebrtcSourceAdaptMs: _average(webrtcSourceAdaptMsValues),
      maxWebrtcSourceAdaptMs: _maxDouble(webrtcSourceAdaptMaxMsValues),
      averageWebrtcSourceScaleMs: _average(webrtcSourceScaleMsValues),
      maxWebrtcSourceScaleMs: _maxDouble(webrtcSourceScaleMaxMsValues),
      averageWebrtcSourceBroadcastMs: _average(webrtcSourceBroadcastMsValues),
      maxWebrtcSourceBroadcastMs: _maxDouble(webrtcSourceBroadcastMaxMsValues),
      webrtcSourceAdapterDrops: webrtcSourceAdapterDrops,
      webrtcSourceScaledFrames: webrtcSourceScaledFrames,
      averageWebrtcVideoBroadcasterMs: _average(webrtcVideoBroadcasterMsValues),
      maxWebrtcVideoBroadcasterMs:
          _maxDouble(webrtcVideoBroadcasterMaxMsValues),
      webrtcVideoBroadcasterSamples: webrtcVideoBroadcasterSamples,
      averageWebrtcVideoBroadcasterLockWaitMs:
          _average(webrtcVideoBroadcasterLockWaitMsValues),
      maxWebrtcVideoBroadcasterLockWaitMs:
          _maxDouble(webrtcVideoBroadcasterLockWaitMaxMsValues),
      averageWebrtcVideoBroadcasterSinkDispatchMs:
          _average(webrtcVideoBroadcasterSinkDispatchMsValues),
      maxWebrtcVideoBroadcasterSinkDispatchMs:
          _maxDouble(webrtcVideoBroadcasterSinkDispatchMaxMsValues),
      maxWebrtcVideoBroadcasterSingleSinkMs:
          _maxDouble(webrtcVideoBroadcasterMaxSingleSinkMsValues),
      webrtcVideoBroadcasterSlowSinkId: webrtcVideoBroadcasterSlowSinkId,
      webrtcVideoBroadcasterSlowSinkMs: webrtcVideoBroadcasterSlowSinkMs,
      webrtcVideoBroadcasterSlowSinkLabel: webrtcVideoBroadcasterSlowSinkLabel,
      webrtcVideoBroadcasterSlowestSinkId: webrtcVideoBroadcasterSlowestSinkId,
      webrtcVideoBroadcasterSlowestSinkMs: webrtcVideoBroadcasterSlowestSinkMs,
      webrtcVideoBroadcasterSlowestSinkAverageMs:
          webrtcVideoBroadcasterSlowestSinkAverageMs,
      webrtcVideoBroadcasterSlowestSinkFrames:
          webrtcVideoBroadcasterSlowestSinkFrames,
      webrtcVideoBroadcasterSlowestSinkLabel:
          webrtcVideoBroadcasterSlowestSinkLabel,
      webrtcVideoBroadcasterSinkCount: webrtcVideoBroadcasterSinkCount,
      webrtcVideoBroadcasterMaxSinkCount: webrtcVideoBroadcasterMaxSinkCount,
      webrtcVideoBroadcasterActiveSinks: webrtcVideoBroadcasterActiveSinks,
      webrtcVideoBroadcasterInactiveSinks: webrtcVideoBroadcasterInactiveSinks,
      webrtcVideoBroadcasterRequestedSinks:
          webrtcVideoBroadcasterRequestedSinks,
      webrtcVideoBroadcasterBlackFrameSinks:
          webrtcVideoBroadcasterBlackFrameSinks,
      webrtcVideoBroadcasterRotationAppliedSinks:
          webrtcVideoBroadcasterRotationAppliedSinks,
      webrtcVideoBroadcasterInactiveNativeSinkBypassReported:
          webrtcVideoBroadcasterInactiveNativeSinkBypassReported,
      webrtcVideoBroadcasterInactiveNativeSinksBypassed:
          webrtcVideoBroadcasterInactiveNativeSinksBypassed,
      webrtcVideoBroadcasterInactiveNativeSinksBypassedLast:
          webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
      webrtcVideoBroadcasterSinkRoster: webrtcVideoBroadcasterSinkRoster,
      webrtcVideoBroadcasterBlackSinks: webrtcVideoBroadcasterBlackSinks,
      webrtcVideoBroadcasterRotationDiscards:
          webrtcVideoBroadcasterRotationDiscards,
      webrtcVideoBroadcasterUpdateRectCleared:
          webrtcVideoBroadcasterUpdateRectCleared,
      webrtcVideoBroadcasterDiscardedFrames:
          webrtcVideoBroadcasterDiscardedFrames,
      averageWebrtcVsePostToOnFrameMs: _average(webrtcVsePostToOnFrameMsValues),
      maxWebrtcVsePostToOnFrameMs:
          _maxDouble(webrtcVsePostToOnFrameMaxMsValues),
      averageWebrtcVseOnFrameMs: _average(webrtcVseOnFrameMsValues),
      maxWebrtcVseOnFrameMs: _maxDouble(webrtcVseOnFrameMaxMsValues),
      webrtcVseOnFrameSamples: webrtcVseOnFrameSamples,
      webrtcVseQueueOverloadDrops: webrtcVseQueueOverloadDrops,
      webrtcVseEncoderQueueDrops: webrtcVseEncoderQueueDrops,
      webrtcVseCwndDrops: webrtcVseCwndDrops,
      webrtcVseBadTimestampDrops: webrtcVseBadTimestampDrops,
      averageWebrtcVseMaybeEncodeMs: _average(webrtcVseMaybeEncodeMsValues),
      maxWebrtcVseMaybeEncodeMs: _maxDouble(webrtcVseMaybeEncodeMaxMsValues),
      webrtcVseMaybeEncodeSamples: webrtcVseMaybeEncodeSamples,
      webrtcVsePendingReplacedDrops: webrtcVsePendingReplacedDrops,
      webrtcVseSizeDrops: webrtcVseSizeDrops,
      webrtcVsePausedDrops: webrtcVsePausedDrops,
      webrtcVseMediaOptimizationDrops: webrtcVseMediaOptimizationDrops,
      averageWebrtcVseEncodeFrameMs: _average(webrtcVseEncodeFrameMsValues),
      maxWebrtcVseEncodeFrameMs: _maxDouble(webrtcVseEncodeFrameMaxMsValues),
      webrtcVseEncodeFrameSamples: webrtcVseEncodeFrameSamples,
      averageWebrtcVideoEncoderEncodeMs:
          _average(webrtcVideoEncoderEncodeMsValues),
      maxWebrtcVideoEncoderEncodeMs:
          _maxDouble(webrtcVideoEncoderEncodeMaxMsValues),
      webrtcVideoEncoderEncodeSamples: webrtcVideoEncoderEncodeSamples,
      webrtcVseEncodeFailures: webrtcVseEncodeFailures,
      webrtcVseEncodeSkippedBeforeEncoder: webrtcVseEncodeSkippedBeforeEncoder,
    );
  }

  final String? captureBackendMode;
  final String? observedCapturer;
  final int? observedCapturerId;
  final String? dirtyRegionMode;
  final String? windowGdiCaptureMode;
  final String? sourceType;
  final int? nativeSourceWidth;
  final int? nativeSourceHeight;
  final int? requestedMaxWidth;
  final int? requestedMaxHeight;
  final int? nativeWindowRectWidth;
  final int? nativeWindowRectHeight;
  final int? contentWidth;
  final int? contentHeight;
  final int? preEncodeWidth;
  final int? preEncodeHeight;
  final String? canvas;
  final bool? cropRegion;
  final double? averageNativeFps;
  final double? averageSubmittedFps;
  final double? targetNativeFps;
  final double? averageCaptureCallMs;
  final double? maxCaptureCallMs;
  final double? averageSourceCaptureMs;
  final double? maxSourceCaptureMs;
  final int sourceCaptureSampleCount;
  final int wgcCaptureCalls;
  final int wgcCaptureSuccessCount;
  final int wgcSourceNotCapturableCount;
  final int wgcEnsureFrameCalls;
  final int wgcEnsureSleepCount;
  final int wgcProcessFrameCalls;
  final int wgcProcessFrameSuccessCount;
  final int wgcFramePoolEmptyCount;
  final int wgcFramePoolReuseCount;
  final int wgcCaptureFrameNullCount;
  final int wgcMappedTextureCreateCount;
  final int wgcResizeCount;
  final int wgcFramePoolRecreateCount;
  final double? averageWgcGetFrameMs;
  final double? maxWgcGetFrameMs;
  final double? averageWgcEnsureFrameMs;
  final double? maxWgcEnsureFrameMs;
  final double? averageWgcProcessFrameMs;
  final double? maxWgcProcessFrameMs;
  final double? averageWgcTryGetFrameMs;
  final double? maxWgcTryGetFrameMs;
  final double? averageWgcSurfaceMs;
  final double? maxWgcSurfaceMs;
  final double? averageWgcTextureMs;
  final double? maxWgcTextureMs;
  final double? averageWgcContentSizeMs;
  final double? maxWgcContentSizeMs;
  final double? averageWgcCopyTextureMs;
  final double? maxWgcCopyTextureMs;
  final double? averageWgcMapTextureMs;
  final double? maxWgcMapTextureMs;
  final double? averageWgcCopyRowsMs;
  final double? maxWgcCopyRowsMs;
  final double? averageWgcMonitorScaleMs;
  final double? maxWgcMonitorScaleMs;
  final double? averageWgcZeroHertzMs;
  final double? maxWgcZeroHertzMs;
  final int gdiCaptureCalls;
  final int gdiCaptureSuccessCount;
  final int gdiTemporaryErrorCount;
  final int gdiPermanentErrorCount;
  final int gdiHiddenOrMinimizedCount;
  final int gdiRectFailCount;
  final int gdiDcFailCount;
  final int gdiFrameCreateFailCount;
  final int gdiPrintFullCallCount;
  final int gdiPrintFullSuccessCount;
  final int gdiPrintFallbackCallCount;
  final int gdiPrintFallbackSuccessCount;
  final int gdiBitBltCallCount;
  final int gdiBitBltSuccessCount;
  final int gdiFinalPrintFullCount;
  final int gdiFinalPrintFallbackCount;
  final int gdiFinalBitBltCount;
  final int gdiFinalNoneCount;
  final int gdiBlackFrameCount;
  final int gdiLowVarianceFrameCount;
  final int gdiOwnedWindowFrameCount;
  final int gdiOwnedWindowCaptureCallCount;
  final int gdiOwnedWindowCaptureSuccessCount;
  final int? gdiOriginalWidth;
  final int? gdiOriginalHeight;
  final int? gdiCroppedWidth;
  final int? gdiCroppedHeight;
  final int? gdiFrameWidth;
  final int? gdiFrameHeight;
  final double? averageGdiTotalMs;
  final double? maxGdiTotalMs;
  final double? averageGdiRectMs;
  final double? maxGdiRectMs;
  final double? averageGdiVisibilityMs;
  final double? maxGdiVisibilityMs;
  final double? averageGdiGetDcMs;
  final double? maxGdiGetDcMs;
  final double? averageGdiGetDcSizeMs;
  final double? maxGdiGetDcSizeMs;
  final double? averageGdiCreateFrameMs;
  final double? maxGdiCreateFrameMs;
  final double? averageGdiMemDcMs;
  final double? maxGdiMemDcMs;
  final double? averageGdiPrintFullMs;
  final double? maxGdiPrintFullMs;
  final double? averageGdiPrintFallbackMs;
  final double? maxGdiPrintFallbackMs;
  final double? averageGdiBitBltMs;
  final double? maxGdiBitBltMs;
  final double? averageGdiCleanupMs;
  final double? maxGdiCleanupMs;
  final double? averageGdiCropMs;
  final double? maxGdiCropMs;
  final double? averageGdiOwnedEnumMs;
  final double? maxGdiOwnedEnumMs;
  final double? averageGdiOwnedCaptureMs;
  final double? maxGdiOwnedCaptureMs;
  final double? averageGdiOwnedCompositeMs;
  final double? maxGdiOwnedCompositeMs;
  final double? averageCallbackEntryDelayMs;
  final double? maxCallbackEntryDelayMs;
  final double? averageCaptureResultCallbackMs;
  final double? maxCaptureResultCallbackMs;
  final double? averageCaptureAcquireWaitMs;
  final double? maxCaptureAcquireWaitMs;
  final double? averagePostCallbackWaitMs;
  final double? maxPostCallbackWaitMs;
  final double? averageUnaccountedWaitMs;
  final double? maxUnaccountedWaitMs;
  final int captureResultCallbackCount;
  final double? maxFrameIntervalMs;
  final double? p95FrameIntervalMs;
  final int captureWaitTimeoutCount;
  final int capturePermanentErrorCount;
  final int duplicatedFrameCount;
  final int staleFrameReuseCount;
  final double? averageFrameConvertMs;
  final double? averageFrameScaleMs;
  final double? averageFrameOnFrameMs;
  final double? averageFrameCallbackMs;
  final double? maxFrameCallbackMs;
  final int updatedRegionEmptyCount;
  final int updatedRegionNonEmptyCount;
  final int updatedRegionRectCount;
  final int updatedRegionMaxRectCount;
  final double? averageUpdatedRegionAreaRatio;
  final double? maxUpdatedRegionAreaRatio;
  final double? averageUpdatedRegionAnalysisMs;
  final double? maxUpdatedRegionAnalysisMs;
  final int updatedRegionFullFrameCount;
  final int updatedRegionTinyFrameCount;
  final bool? latestFramePacerEnabled;
  final double? averagePacerSubmittedFps;
  final double? averagePacerUniqueFps;
  final double? p95PacerIntervalMs;
  final double? maxPacerIntervalMs;
  final double? averagePacerFrameAgeMs;
  final double? maxPacerFrameAgeMs;
  final double? averagePacerOnFrameMs;
  final double? maxPacerOnFrameMs;
  final int pacerDuplicateSubmitCount;
  final int pacerOverwrittenFrameCount;
  final int pacerSkippedTickCount;
  final int? gameCaptureSourceWidth;
  final int? gameCaptureSourceHeight;
  final int? gameCaptureOutputWidth;
  final int? gameCaptureOutputHeight;
  final int? gameCaptureFormat;
  final int? gameCaptureBackendContractVersion;
  final String? gameCaptureSourceMode;
  final String? gameCaptureSourceApi;
  final int? gameCaptureSourceApiId;
  final String? gameCaptureSourceFormat;
  final int? gameCaptureSourceFormatId;
  final String? gameCaptureColorSpace;
  final String? gameCaptureSyncKind;
  final String? gameCaptureReadyState;
  final String? gameCaptureFailureReason;
  final String? gameCaptureConsumerAdapterLuid;
  final int? gameCaptureConsumerAdapterVendorId;
  final int? gameCaptureConsumerAdapterDeviceId;
  final String? gameCaptureSourceAdapterLuid;
  final String? gameCaptureCrossAdapterSuspected;
  final double? averageGameCaptureFps;
  final int gameCaptureSubmittedFrames;
  final int gameCaptureRepeatedFrames;
  final int gameCaptureDuplicateSkippedFrames;
  final int gameCaptureDeliveryQueuedFrames;
  final int gameCaptureDeliverySubmittedFrames;
  final int gameCaptureDeliveryOverwrittenFrames;
  final int gameCaptureDeliveryPacerResyncs;
  final int gameCaptureDeliveryPacerLagMaxMs;
  final int gameCaptureDeliveryRepeatNoQueuedFrames;
  final int gameCaptureDeliverySkipNoQueuedFrames;
  final int gameCaptureDeliveryFreshWakeAfterSkipFrames;
  final int gameCaptureDeliveryFreshImmediateFrames;
  final String? gameCaptureDeliveryRepeatPolicy;
  final int? gameCaptureDeliveryQueueDepth;
  final double? averageGameCaptureDeliveryRepeatSourceAgeMs;
  final double? maxGameCaptureDeliveryRepeatSourceAgeMs;
  final int gameCaptureDeliveryRepeatSourceAgeSamples;
  final double? averageGameCaptureDeliveryOnFrameMs;
  final double? maxGameCaptureDeliveryOnFrameMs;
  final double? averageGameCaptureDeliverySubmitPrepMs;
  final double? maxGameCaptureDeliverySubmitPrepMs;
  final int gameCaptureDeliverySubmitPrepSamples;
  final double? averageGameCaptureDeliveryOnFrameCallMs;
  final double? maxGameCaptureDeliveryOnFrameCallMs;
  final int gameCaptureDeliveryOnFrameCallSamples;
  final double? averageGameCaptureDeliveryPostOnFrameMs;
  final double? maxGameCaptureDeliveryPostOnFrameMs;
  final int gameCaptureDeliveryPostOnFrameSamples;
  final double? averageGameCaptureNativeBufferReleaseMs;
  final double? maxGameCaptureNativeBufferReleaseMs;
  final int gameCaptureNativeBufferReleaseSamples;
  final double? averageGameCaptureReadyToQueueMs;
  final double? maxGameCaptureReadyToQueueMs;
  final int gameCaptureReadyToQueueSamples;
  final double? averageGameCaptureDeliveryQueueWaitMs;
  final double? maxGameCaptureDeliveryQueueWaitMs;
  final int gameCaptureDeliveryQueueWaitSamples;
  final double? averageGameCaptureDeliveryOverwriteAgeMs;
  final double? maxGameCaptureDeliveryOverwriteAgeMs;
  final int gameCaptureDeliveryOverwriteAgeSamples;
  final int gameCaptureDeliveryOverwrittenFreshFrames;
  final double? averageGameCaptureReadyToSubmitMs;
  final double? maxGameCaptureReadyToSubmitMs;
  final int gameCaptureReadyToSubmitSamples;
  final double? averageGameCaptureSourceToSubmitMs;
  final double? maxGameCaptureSourceToSubmitMs;
  final int gameCaptureSourceToSubmitSamples;
  final double? averageGameCaptureSourceToReadbackReadyMs;
  final double? maxGameCaptureSourceToReadbackReadyMs;
  final int gameCaptureSourceToReadbackReadySamples;
  final double? averageGameCaptureReadbackQueueToMapMs;
  final double? maxGameCaptureReadbackQueueToMapMs;
  final int gameCaptureReadbackQueueToMapSamples;
  final double? averageGameCaptureMapToI420Ms;
  final double? maxGameCaptureMapToI420Ms;
  final int gameCaptureMapToI420Samples;
  final double? averageGameCaptureSourceToI420ReadyMs;
  final double? maxGameCaptureSourceToI420ReadyMs;
  final int gameCaptureSourceToI420ReadySamples;
  final double? averageGameCaptureSourceToQueueMs;
  final double? maxGameCaptureSourceToQueueMs;
  final int gameCaptureSourceToQueueSamples;
  final double? averageGameCaptureSourceDuplicateSkipAgeMs;
  final double? maxGameCaptureSourceDuplicateSkipAgeMs;
  final int gameCaptureSourceDuplicateSkipAgeSamples;
  final int gameCaptureCopiedFrames;
  final int gameCaptureDroppedFrames;
  final int gameCaptureOverwrittenFrames;
  final int gameCaptureGpuScaledFrames;
  final int gameCaptureGpuScaleFailures;
  final int gameCaptureCpuFallbackFrames;
  final int gameCaptureNativeNv12SubmittedFrames;
  final int gameCaptureNativeNv12QueuedFrames;
  final int gameCaptureNativeNv12ReadyFrames;
  final int gameCaptureNativeNv12NotReadyPolls;
  final String? gameCaptureNativeNv12ReadyPolicy;
  final bool? gameCaptureNativeNv12FenceAvailable;
  final int? gameCaptureNativeNv12PendingPollMs;
  final int? gameCaptureNativeNv12MaxPendingSlots;
  final int? gameCaptureNativeNv12ReadyDrainDepth;
  final String? gameCaptureNativeNv12FrameOwnership;
  final int gameCaptureNativeNv12FenceSignaledFrames;
  final int gameCaptureNativeNv12FenceReadyFrames;
  final int gameCaptureNativeNv12FenceSignalFailures;
  final int gameCaptureNativeNv12OwnedCopies;
  final double? averageGameCaptureNativeNv12OwnedCopyMs;
  final double? maxGameCaptureNativeNv12OwnedCopyMs;
  final int gameCaptureNativeNv12OwnedCopySamples;
  final int gameCaptureNativeNv12OverwrittenFrames;
  final double? averageGameCaptureNativeNv12OverwriteAgeMs;
  final double? maxGameCaptureNativeNv12OverwriteAgeMs;
  final int gameCaptureNativeNv12OverwriteAgeSamples;
  final int gameCaptureNativeNv12OverwrittenFreshFrames;
  final int gameCaptureNativeNv12ReadyDroppedFrames;
  final double? averageGameCaptureNativeNv12ReadyDropAgeMs;
  final double? maxGameCaptureNativeNv12ReadyDropAgeMs;
  final int gameCaptureNativeNv12ReadyDropAgeSamples;
  final int gameCaptureNativeNv12ReadyDroppedFreshFrames;
  final int gameCaptureNativeNv12Failures;
  final double? averageGameCaptureNativeNv12ConvertMs;
  final double? maxGameCaptureNativeNv12ConvertMs;
  final int gameCaptureNativeNv12ConvertSamples;
  final double? averageGameCaptureNativeNv12BgraScaleDrawMs;
  final double? maxGameCaptureNativeNv12BgraScaleDrawMs;
  final int gameCaptureNativeNv12BgraScaleDrawSamples;
  final double? averageGameCaptureNativeNv12VideoProcessorBltSubmitMs;
  final double? maxGameCaptureNativeNv12VideoProcessorBltSubmitMs;
  final int gameCaptureNativeNv12VideoProcessorBltSubmitSamples;
  final double? averageGameCaptureNativeNv12VideoProcessorBltToReadyMs;
  final double? maxGameCaptureNativeNv12VideoProcessorBltToReadyMs;
  final int gameCaptureNativeNv12VideoProcessorBltToReadySamples;
  final double? averageGameCaptureNativeNv12BufferCreateMs;
  final double? maxGameCaptureNativeNv12BufferCreateMs;
  final int gameCaptureNativeNv12BufferCreateSamples;
  final double? averageGameCaptureNativeNv12FrameReadyToQueueMs;
  final double? maxGameCaptureNativeNv12FrameReadyToQueueMs;
  final int gameCaptureNativeNv12FrameReadyToQueueSamples;
  final double? averageGameCaptureNativeNv12ConversionStartAgeMs;
  final double? maxGameCaptureNativeNv12ConversionStartAgeMs;
  final int gameCaptureNativeNv12ConversionStartAgeSamples;
  final int gameCaptureNativeNv12StaleBeforeQueueFrames;
  final String? gameCaptureNativeNv12HandoffDisabledReason;
  final int gameCaptureReadbackQueuedFrames;
  final int gameCaptureReadbackReadyFrames;
  final int gameCaptureReadbackNotReadyFrames;
  final int gameCaptureReadbackOverwrittenFrames;
  final int gameCaptureReadbackStaleDroppedFrames;
  final int gameCaptureReadbackLatencyDroppedFrames;
  final int gameCaptureReadbackMapAttempts;
  final int gameCaptureSourceFrameIndex;
  final int gameCaptureLastSubmittedSourceFrameIndex;
  final int gameCaptureSourceFrameRegressions;
  final int gameCaptureSourceFrameDuplicates;
  final int gameCaptureSourceFrameGaps;
  final int gameCaptureSharedSlotMismatches;
  final String? gameCaptureTimestampMode;
  final int gameCaptureTimestampSourceQpcFrames;
  final int gameCaptureTimestampPacedFallbackFrames;
  final int gameCaptureTimestampRepeatedFrames;
  final double? averageGameCaptureTimestampDeltaMs;
  final double? maxGameCaptureTimestampDeltaMs;
  final int gameCaptureTimestampSamples;
  final int gameCaptureTimestampAdjustments;
  final double? averageGameCaptureDeliveryWallDeltaMs;
  final double? maxGameCaptureDeliveryWallDeltaMs;
  final double? minGameCaptureDeliveryWallDeltaMs;
  final int gameCaptureDeliveryWallSamples;
  final int gameCaptureDeliveryWallOver2xFrames;
  final int gameCaptureDeliveryWallOver3xFrames;
  final int gameCaptureDeliveryWallUnderHalfFrames;
  final double? averageGameCaptureSourceQpcDeltaMs;
  final double? maxGameCaptureSourceQpcDeltaMs;
  final int gameCaptureSourceQpcSamples;
  final int gameCaptureSourceQpcRegressions;
  final double? averageGameCaptureCopyMs;
  final double? averageGameCaptureMapMs;
  final double? averageGameCaptureConvertMs;
  final double? averageGameCaptureGpuScaleMs;
  final double? averageGameCaptureReadbackLatencyMs;
  final double? averageGameCaptureReadbackLatencyFrames;
  final int gameCaptureMaxReadbackLatencyFrames;
  final int gameCaptureMapFailures;
  final int gameCaptureConvertFailures;
  final int gameCaptureProofFrames;
  final int gameCaptureVisibleProofFrames;
  final bool? gameCaptureProofVisible;
  final String? gameCaptureProofPath;
  final int? gameCaptureProofMinLuma;
  final int? gameCaptureProofMaxLuma;
  final int? gameCaptureProofNonzeroSamples;
  final int? gameCaptureProofSamples;
  final int gameCaptureI420ProofFrames;
  final int gameCaptureVisibleI420ProofFrames;
  final int gameCaptureInitialBlackSkippedFrames;
  final bool? gameCaptureVisibleSourceSeen;
  final bool? gameCaptureI420ProofVisible;
  final String? gameCaptureI420ProofPath;
  final int? gameCaptureI420ProofMinLuma;
  final int? gameCaptureI420ProofMaxLuma;
  final int? gameCaptureI420ProofNonzeroSamples;
  final int? gameCaptureI420ProofSamples;
  final double? averageEncoderTotalMs;
  final double? maxEncoderTotalMs;
  final int encoderSlowFrameCount;
  final int encoderSampleCount;
  final List<String> encoderInputPaths;
  final int encoderNativeInputFrames;
  final int encoderCpuI420InputFrames;
  final int encoderNativeSampleFailures;
  final int encoderNativeSuspendedFrames;
  final int encoderNativeReadyFenceFrames;
  final int encoderNativeReadyFenceTimeoutFrames;
  final double? averageEncoderNativeReadyFenceWaitMs;
  final double? maxEncoderNativeReadyFenceWaitMs;
  final int encoderNativeReadyFenceWaitSamples;
  final String? encoderNativeSourceMode;
  final int? encoderNativeSourceFormat;
  final int encoderNativeSourceFrameIndex;
  final double? averageEncoderNativeSourceAgeMs;
  final double? maxEncoderNativeSourceAgeMs;
  final int encoderNativeSourceAgeSamples;
  final double? averageEncoderNativeSourceAgeAtCreateMs;
  final double? maxEncoderNativeSourceAgeAtCreateMs;
  final double? averageEncoderNativeBufferAgeMs;
  final double? maxEncoderNativeBufferAgeMs;
  final int encoderNativeBufferAgeSamples;
  final double? averageEncoderNativeSampleLifetimeMs;
  final double? maxEncoderNativeSampleLifetimeMs;
  final int encoderNativeSampleLifetimeSamples;
  final String? encoderNativeAdapterLuid;
  final int? encoderNativeAdapterVendorId;
  final int? encoderNativeAdapterDeviceId;
  final double? averageEncoderProcessInputMs;
  final double? maxEncoderProcessInputMs;
  final int encoderProcessInputSamples;
  final double? averageEncoderProcessOutputMs;
  final double? maxEncoderProcessOutputMs;
  final int encoderProcessOutputSamples;
  final double? averageEncoderEncodedCallbackMs;
  final double? maxEncoderEncodedCallbackMs;
  final int encoderEncodedCallbackSamples;
  final double? averageEncoderEncodedCallbackQueueWaitMs;
  final double? maxEncoderEncodedCallbackQueueWaitMs;
  final int encoderEncodedCallbackQueueWaitSamples;
  final double? averageEncoderEncodedCallbackEnqueueMs;
  final double? maxEncoderEncodedCallbackEnqueueMs;
  final int encoderEncodedCallbackEnqueueSamples;
  final int encoderEncodedCallbackAsyncFrames;
  final int encoderMaxEncodedCallbackQueueDepth;
  final int encoderMaxEncodedCallbackDrops;
  final int encoderMaxEncodedCallbackOutputs;
  final List<String> encoderStages;
  final int encoderOutputFrames;
  final int encoderOutputBytes;
  final int encoderMaxQueueDepth;
  final int encoderMaxRetainedSamples;
  final int encoderMaxEncodedOutputs;
  final double? averageWebrtcSourceOnFrameMs;
  final double? maxWebrtcSourceOnFrameMs;
  final int webrtcSourceOnFrameSamples;
  final double? averageWebrtcSourceAdaptMs;
  final double? maxWebrtcSourceAdaptMs;
  final double? averageWebrtcSourceScaleMs;
  final double? maxWebrtcSourceScaleMs;
  final double? averageWebrtcSourceBroadcastMs;
  final double? maxWebrtcSourceBroadcastMs;
  final int webrtcSourceAdapterDrops;
  final int webrtcSourceScaledFrames;
  final double? averageWebrtcVideoBroadcasterMs;
  final double? maxWebrtcVideoBroadcasterMs;
  final int webrtcVideoBroadcasterSamples;
  final double? averageWebrtcVideoBroadcasterLockWaitMs;
  final double? maxWebrtcVideoBroadcasterLockWaitMs;
  final double? averageWebrtcVideoBroadcasterSinkDispatchMs;
  final double? maxWebrtcVideoBroadcasterSinkDispatchMs;
  final double? maxWebrtcVideoBroadcasterSingleSinkMs;
  final int? webrtcVideoBroadcasterSlowSinkId;
  final double? webrtcVideoBroadcasterSlowSinkMs;
  final String? webrtcVideoBroadcasterSlowSinkLabel;
  final int? webrtcVideoBroadcasterSlowestSinkId;
  final double? webrtcVideoBroadcasterSlowestSinkMs;
  final double? webrtcVideoBroadcasterSlowestSinkAverageMs;
  final int webrtcVideoBroadcasterSlowestSinkFrames;
  final String? webrtcVideoBroadcasterSlowestSinkLabel;
  final int webrtcVideoBroadcasterSinkCount;
  final int webrtcVideoBroadcasterMaxSinkCount;
  final int webrtcVideoBroadcasterActiveSinks;
  final int webrtcVideoBroadcasterInactiveSinks;
  final int webrtcVideoBroadcasterRequestedSinks;
  final int webrtcVideoBroadcasterBlackFrameSinks;
  final int webrtcVideoBroadcasterRotationAppliedSinks;
  final bool webrtcVideoBroadcasterInactiveNativeSinkBypassReported;
  final int webrtcVideoBroadcasterInactiveNativeSinksBypassed;
  final int webrtcVideoBroadcasterInactiveNativeSinksBypassedLast;
  final String? webrtcVideoBroadcasterSinkRoster;
  final int webrtcVideoBroadcasterBlackSinks;
  final int webrtcVideoBroadcasterRotationDiscards;
  final int webrtcVideoBroadcasterUpdateRectCleared;
  final int webrtcVideoBroadcasterDiscardedFrames;
  final double? averageWebrtcVsePostToOnFrameMs;
  final double? maxWebrtcVsePostToOnFrameMs;
  final double? averageWebrtcVseOnFrameMs;
  final double? maxWebrtcVseOnFrameMs;
  final int webrtcVseOnFrameSamples;
  final int webrtcVseQueueOverloadDrops;
  final int webrtcVseEncoderQueueDrops;
  final int webrtcVseCwndDrops;
  final int webrtcVseBadTimestampDrops;
  final double? averageWebrtcVseMaybeEncodeMs;
  final double? maxWebrtcVseMaybeEncodeMs;
  final int webrtcVseMaybeEncodeSamples;
  final int webrtcVsePendingReplacedDrops;
  final int webrtcVseSizeDrops;
  final int webrtcVsePausedDrops;
  final int webrtcVseMediaOptimizationDrops;
  final double? averageWebrtcVseEncodeFrameMs;
  final double? maxWebrtcVseEncodeFrameMs;
  final int webrtcVseEncodeFrameSamples;
  final double? averageWebrtcVideoEncoderEncodeMs;
  final double? maxWebrtcVideoEncoderEncodeMs;
  final int webrtcVideoEncoderEncodeSamples;
  final int webrtcVseEncodeFailures;
  final int webrtcVseEncodeSkippedBeforeEncoder;

  bool get hasEvidence =>
      captureBackendMode != null ||
      observedCapturer != null ||
      dirtyRegionMode != null ||
      nativeSourceWidth != null ||
      nativeWindowRectWidth != null ||
      contentWidth != null ||
      preEncodeWidth != null ||
      canvas != null ||
      averageNativeFps != null ||
      averageSubmittedFps != null ||
      averageCaptureCallMs != null ||
      averageSourceCaptureMs != null ||
      averageWgcGetFrameMs != null ||
      wgcCaptureCalls > 0 ||
      wgcFramePoolEmptyCount > 0 ||
      wgcFramePoolReuseCount > 0 ||
      gdiCaptureCalls > 0 ||
      averageGdiTotalMs != null ||
      averageCallbackEntryDelayMs != null ||
      averageCaptureAcquireWaitMs != null ||
      averagePostCallbackWaitMs != null ||
      averageUnaccountedWaitMs != null ||
      maxFrameIntervalMs != null ||
      averageFrameCallbackMs != null ||
      updatedRegionEmptyCount > 0 ||
      updatedRegionNonEmptyCount > 0 ||
      updatedRegionRectCount > 0 ||
      averageUpdatedRegionAreaRatio != null ||
      averageUpdatedRegionAnalysisMs != null ||
      latestFramePacerEnabled != null ||
      averagePacerSubmittedFps != null ||
      gameCaptureSourceMode != null ||
      gameCaptureSourceApi != null ||
      gameCaptureSourceFormat != null ||
      gameCaptureSyncKind != null ||
      gameCaptureReadyState != null ||
      gameCaptureFailureReason != null ||
      gameCaptureConsumerAdapterLuid != null ||
      gameCaptureSourceAdapterLuid != null ||
      gameCaptureCrossAdapterSuspected != null ||
      averageGameCaptureFps != null ||
      gameCaptureSubmittedFrames > 0 ||
      gameCaptureDuplicateSkippedFrames > 0 ||
      gameCaptureDeliveryQueuedFrames > 0 ||
      gameCaptureDeliverySubmittedFrames > 0 ||
      gameCaptureDeliveryPacerResyncs > 0 ||
      gameCaptureDeliveryRepeatNoQueuedFrames > 0 ||
      gameCaptureDeliverySkipNoQueuedFrames > 0 ||
      gameCaptureDeliveryFreshWakeAfterSkipFrames > 0 ||
      gameCaptureDeliveryFreshImmediateFrames > 0 ||
      gameCaptureDeliveryRepeatPolicy != null ||
      gameCaptureDeliveryQueueDepth != null ||
      gameCaptureDeliveryRepeatSourceAgeSamples > 0 ||
      gameCaptureDeliverySubmitPrepSamples > 0 ||
      gameCaptureDeliveryOnFrameCallSamples > 0 ||
      gameCaptureDeliveryPostOnFrameSamples > 0 ||
      gameCaptureNativeBufferReleaseSamples > 0 ||
      gameCaptureDeliveryOverwriteAgeSamples > 0 ||
      gameCaptureDeliveryOverwrittenFreshFrames > 0 ||
      gameCaptureGpuScaledFrames > 0 ||
      gameCaptureCpuFallbackFrames > 0 ||
      gameCaptureNativeNv12SubmittedFrames > 0 ||
      gameCaptureNativeNv12QueuedFrames > 0 ||
      gameCaptureNativeNv12ReadyFrames > 0 ||
      gameCaptureNativeNv12NotReadyPolls > 0 ||
      gameCaptureNativeNv12ReadyPolicy != null ||
      gameCaptureNativeNv12FenceAvailable != null ||
      gameCaptureNativeNv12PendingPollMs != null ||
      gameCaptureNativeNv12MaxPendingSlots != null ||
      gameCaptureNativeNv12ReadyDrainDepth != null ||
      gameCaptureNativeNv12FrameOwnership != null ||
      gameCaptureNativeNv12FenceSignaledFrames > 0 ||
      gameCaptureNativeNv12FenceReadyFrames > 0 ||
      gameCaptureNativeNv12FenceSignalFailures > 0 ||
      gameCaptureNativeNv12OwnedCopies > 0 ||
      gameCaptureNativeNv12OwnedCopySamples > 0 ||
      gameCaptureNativeNv12OverwrittenFrames > 0 ||
      gameCaptureNativeNv12OverwriteAgeSamples > 0 ||
      gameCaptureNativeNv12OverwrittenFreshFrames > 0 ||
      gameCaptureNativeNv12ReadyDroppedFrames > 0 ||
      gameCaptureNativeNv12ReadyDropAgeSamples > 0 ||
      gameCaptureNativeNv12ReadyDroppedFreshFrames > 0 ||
      gameCaptureNativeNv12Failures > 0 ||
      gameCaptureNativeNv12ConvertSamples > 0 ||
      gameCaptureNativeNv12BgraScaleDrawSamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltSubmitSamples > 0 ||
      gameCaptureNativeNv12VideoProcessorBltToReadySamples > 0 ||
      gameCaptureNativeNv12BufferCreateSamples > 0 ||
      gameCaptureNativeNv12FrameReadyToQueueSamples > 0 ||
      gameCaptureNativeNv12ConversionStartAgeSamples > 0 ||
      gameCaptureNativeNv12StaleBeforeQueueFrames > 0 ||
      gameCaptureNativeNv12HandoffDisabledReason != null ||
      gameCaptureReadbackQueuedFrames > 0 ||
      gameCaptureReadbackReadyFrames > 0 ||
      gameCaptureReadbackStaleDroppedFrames > 0 ||
      gameCaptureSourceFrameIndex > 0 ||
      gameCaptureLastSubmittedSourceFrameIndex > 0 ||
      gameCaptureSourceFrameRegressions > 0 ||
      gameCaptureSharedSlotMismatches > 0 ||
      gameCaptureTimestampMode != null ||
      gameCaptureTimestampSourceQpcFrames > 0 ||
      gameCaptureTimestampPacedFallbackFrames > 0 ||
      gameCaptureTimestampRepeatedFrames > 0 ||
      gameCaptureTimestampSamples > 0 ||
      gameCaptureTimestampAdjustments > 0 ||
      gameCaptureDeliveryWallSamples > 0 ||
      gameCaptureSourceQpcSamples > 0 ||
      gameCaptureSourceQpcRegressions > 0 ||
      gameCaptureSourceDuplicateSkipAgeSamples > 0 ||
      gameCaptureProofFrames > 0 ||
      gameCaptureI420ProofFrames > 0 ||
      gameCaptureInitialBlackSkippedFrames > 0 ||
      averageEncoderTotalMs != null ||
      encoderInputPaths.isNotEmpty ||
      encoderNativeReadyFenceWaitSamples > 0 ||
      encoderNativeSourceAgeSamples > 0 ||
      encoderNativeBufferAgeSamples > 0 ||
      encoderNativeSampleLifetimeSamples > 0 ||
      encoderNativeAdapterLuid != null ||
      encoderProcessInputSamples > 0 ||
      encoderProcessOutputSamples > 0 ||
      encoderEncodedCallbackSamples > 0 ||
      encoderEncodedCallbackQueueWaitSamples > 0 ||
      encoderEncodedCallbackEnqueueSamples > 0 ||
      encoderMaxEncodedCallbackQueueDepth > 0 ||
      encoderMaxEncodedCallbackDrops > 0 ||
      encoderOutputFrames > 0 ||
      encoderMaxQueueDepth > 0 ||
      webrtcSourceOnFrameSamples > 0 ||
      webrtcVideoBroadcasterSamples > 0 ||
      webrtcVseOnFrameSamples > 0 ||
      webrtcVseMaybeEncodeSamples > 0 ||
      webrtcVseEncodeFrameSamples > 0 ||
      webrtcVideoEncoderEncodeSamples > 0;

  String get backendLabel => captureBackendMode ?? 'unknown';

  String get observedCapturerLabel => observedCapturer ?? 'unknown';

  String get dirtyRegionModeLabel => dirtyRegionMode ?? 'unknown';

  String get windowGdiCaptureModeLabel => windowGdiCaptureMode ?? 'unknown';

  String get encoderInputPathLabel =>
      encoderInputPaths.isEmpty ? 'unknown' : encoderInputPaths.join(',');

  String get encoderStageLabel =>
      encoderStages.isEmpty ? 'unknown' : encoderStages.join(',');

  bool get nativeEncoderFenceWaitMissing =>
      encoderInputPaths.contains('native_nv12') &&
      encoderNativeInputFrames > 0 &&
      encoderNativeReadyFenceWaitSamples == 0;

  bool get hasWebrtcRawSenderBoundaryDiagnostics =>
      webrtcSourceOnFrameSamples > 0 ||
      webrtcVideoBroadcasterSamples > 0 ||
      webrtcVseOnFrameSamples > 0 ||
      webrtcVseMaybeEncodeSamples > 0 ||
      webrtcVseEncodeFrameSamples > 0 ||
      webrtcVideoEncoderEncodeSamples > 0;

  String get webrtcRawSenderBoundaryLabel {
    if (!hasWebrtcRawSenderBoundaryDiagnostics) {
      return 'missing';
    }
    return 'source_on_frame='
        '${_milliseconds(averageWebrtcSourceOnFrameMs)}/'
        '${_milliseconds(maxWebrtcSourceOnFrameMs)} '
        'source_broadcast='
        '${_milliseconds(averageWebrtcSourceBroadcastMs)}/'
        '${_milliseconds(maxWebrtcSourceBroadcastMs)} '
        'broadcaster='
        '${_milliseconds(averageWebrtcVideoBroadcasterMs)}/'
        '${_milliseconds(maxWebrtcVideoBroadcasterMs)} '
        'broadcaster_lock='
        '${_milliseconds(averageWebrtcVideoBroadcasterLockWaitMs)}/'
        '${_milliseconds(maxWebrtcVideoBroadcasterLockWaitMs)} '
        'broadcaster_sink='
        '${_milliseconds(averageWebrtcVideoBroadcasterSinkDispatchMs)}/'
        '${_milliseconds(maxWebrtcVideoBroadcasterSinkDispatchMs)} '
        'broadcaster_single_sink='
        '${_milliseconds(maxWebrtcVideoBroadcasterSingleSinkMs)} '
        'broadcaster_slow_sink='
        '${webrtcVideoBroadcasterSlowSinkId ?? 'unknown'}:'
        '${webrtcVideoBroadcasterSlowSinkLabel ?? 'unknown'}/'
        '${_milliseconds(webrtcVideoBroadcasterSlowSinkMs)} '
        'broadcaster_slowest_sink='
        '${webrtcVideoBroadcasterSlowestSinkId ?? 'unknown'}:'
        '${webrtcVideoBroadcasterSlowestSinkLabel ?? 'unknown'}/'
        '${_milliseconds(webrtcVideoBroadcasterSlowestSinkMs)} '
        'avg:${_milliseconds(webrtcVideoBroadcasterSlowestSinkAverageMs)} '
        'frames:$webrtcVideoBroadcasterSlowestSinkFrames '
        'broadcaster_sinks=$webrtcVideoBroadcasterSinkCount/'
        '$webrtcVideoBroadcasterMaxSinkCount '
        'broadcaster_sink_types=active:$webrtcVideoBroadcasterActiveSinks '
        'inactive:$webrtcVideoBroadcasterInactiveSinks '
        'requested:$webrtcVideoBroadcasterRequestedSinks '
        'black:$webrtcVideoBroadcasterBlackFrameSinks '
        'rotation:$webrtcVideoBroadcasterRotationAppliedSinks '
        'inactive_native_bypass:'
        '$webrtcVideoBroadcasterInactiveNativeSinksBypassed '
        'last:$webrtcVideoBroadcasterInactiveNativeSinksBypassedLast '
        'reported:$webrtcVideoBroadcasterInactiveNativeSinkBypassReported '
        'broadcaster_roster='
        '${webrtcVideoBroadcasterSinkRoster ?? 'unknown'} '
        'source_adapter_drops=$webrtcSourceAdapterDrops '
        'vse_post_to_onframe='
        '${_milliseconds(averageWebrtcVsePostToOnFrameMs)}/'
        '${_milliseconds(maxWebrtcVsePostToOnFrameMs)} '
        'vse_onframe='
        '${_milliseconds(averageWebrtcVseOnFrameMs)}/'
        '${_milliseconds(maxWebrtcVseOnFrameMs)} '
        'vse_maybe_encode='
        '${_milliseconds(averageWebrtcVseMaybeEncodeMs)}/'
        '${_milliseconds(maxWebrtcVseMaybeEncodeMs)} '
        'vse_encode_frame='
        '${_milliseconds(averageWebrtcVseEncodeFrameMs)}/'
        '${_milliseconds(maxWebrtcVseEncodeFrameMs)} '
        'video_encoder_encode='
        '${_milliseconds(averageWebrtcVideoEncoderEncodeMs)}/'
        '${_milliseconds(maxWebrtcVideoEncoderEncodeMs)} '
        'drops=queue:$webrtcVseEncoderQueueDrops '
        'overload:$webrtcVseQueueOverloadDrops '
        'cwnd:$webrtcVseCwndDrops '
        'media:$webrtcVseMediaOptimizationDrops '
        'failures=$webrtcVseEncodeFailures';
  }

  bool get hasGameCaptureEvidence {
    final observed = observedCapturerLabel.toLowerCase();
    return observed.contains('game-d3d11-hook') ||
        gameCaptureSubmittedFrames > 0 ||
        gameCaptureGpuScaledFrames > 0 ||
        gameCaptureNativeNv12SubmittedFrames > 0 ||
        gameCaptureProofFrames > 0 ||
        gameCaptureI420ProofFrames > 0 ||
        gameCaptureSourceApi != null;
  }

  String get reportWgcFrameSummaryLabel => hasGameCaptureEvidence
      ? 'not_applicable_game_hook'
      : wgcFrameSummaryLabel;

  String get reportGdiFrameSummaryLabel => hasGameCaptureEvidence
      ? 'not_applicable_game_hook'
      : gdiFrameSummaryLabel;

  double get encoderSlowSampleRatio => encoderSampleCount <= 0
      ? 0.0
      : (encoderSlowFrameCount / encoderSampleCount).clamp(0.0, 1.0).toDouble();

  bool isNativeEncoderOverBudgetFor(double? frameBudgetMs) {
    final average = averageEncoderTotalMs;
    if (average == null || encoderSampleCount <= 0) {
      return false;
    }
    final budget = frameBudgetMs ?? 33.0;
    return average > budget || encoderSlowSampleRatio >= 0.25;
  }

  bool get nativeEncoderHandoffNoOutput =>
      encoderInputPaths.contains('native_nv12') &&
      encoderNativeInputFrames > 0 &&
      encoderNativeSampleFailures == 0 &&
      encoderOutputFrames == 0 &&
      encoderMaxQueueDepth > 0;

  bool get gameCaptureGpuHandoffUnproven {
    final observed = observedCapturerLabel.toLowerCase();
    final gameHookObserved = observed.contains('game-d3d11-hook');
    final cpuI420EncoderFallback = encoderCpuI420InputFrames > 0 &&
        encoderNativeInputFrames == 0 &&
        encoderInputPaths.contains('cpu_i420');
    final readbackFallbackObserved = gameCaptureReadbackQueuedFrames > 0 ||
        gameCaptureReadbackReadyFrames > 0 ||
        gameCaptureReadbackNotReadyFrames > 0;
    return gameHookObserved &&
        gameCaptureGpuScaledFrames > 0 &&
        gameCaptureNativeNv12SubmittedFrames == 0 &&
        (gameCaptureNativeNv12HandoffDisabledReason != null ||
            cpuI420EncoderFallback) &&
        readbackFallbackObserved;
  }

  String get nativeSourceResolutionLabel =>
      _resolutionLabel(nativeSourceWidth, nativeSourceHeight);

  String get requestedMaxResolutionLabel =>
      _resolutionLabel(requestedMaxWidth, requestedMaxHeight);

  String get nativeWindowRectResolutionLabel =>
      _resolutionLabel(nativeWindowRectWidth, nativeWindowRectHeight);

  String get contentResolutionLabel =>
      _resolutionLabel(contentWidth, contentHeight);

  String get preEncodeResolutionLabel =>
      _resolutionLabel(preEncodeWidth, preEncodeHeight);

  String get gameCaptureSourceResolutionLabel =>
      _resolutionLabel(gameCaptureSourceWidth, gameCaptureSourceHeight);

  String get gameCaptureOutputResolutionLabel =>
      _resolutionLabel(gameCaptureOutputWidth, gameCaptureOutputHeight);

  String get canvasLabel => canvas ?? 'unknown';

  String get gameCaptureFrameSummaryLabel {
    if (averageGameCaptureFps == null &&
        gameCaptureSubmittedFrames == 0 &&
        gameCaptureProofFrames == 0 &&
        gameCaptureI420ProofFrames == 0) {
      return 'unknown';
    }
    final proofState = gameCaptureProofVisible == null
        ? '?'
        : gameCaptureProofVisible!
            ? 'visible'
            : 'not_visible';
    final i420ProofState = gameCaptureI420ProofVisible == null
        ? '?'
        : gameCaptureI420ProofVisible!
            ? 'visible'
            : 'not_visible';
    return 'source=$gameCaptureSourceResolutionLabel '
        'output=$gameCaptureOutputResolutionLabel '
        'format=${gameCaptureFormat ?? '?'} '
        'backend_contract=${gameCaptureBackendContractVersion ?? '?'} '
        'source_mode=${gameCaptureSourceMode ?? 'helper-d3d11'} '
        'source_api=${gameCaptureSourceApi ?? 'unknown'} '
        'source_format=${gameCaptureSourceFormat ?? 'unknown'} '
        'color_space=${gameCaptureColorSpace ?? 'unknown'} '
        'sync=${gameCaptureSyncKind ?? 'unknown'} '
        'ready=${gameCaptureReadyState ?? 'unknown'} '
        'failure=${gameCaptureFailureReason ?? 'unknown'} '
        'consumer_adapter=${gameCaptureConsumerAdapterLuid ?? 'unknown'} '
        'consumer_vendor=${gameCaptureConsumerAdapterVendorId ?? '?'} '
        'consumer_device=${gameCaptureConsumerAdapterDeviceId ?? '?'} '
        'source_adapter=${gameCaptureSourceAdapterLuid ?? 'unknown'} '
        'cross_adapter=${gameCaptureCrossAdapterSuspected ?? 'unknown'} '
        'fps=${_number(averageGameCaptureFps)} '
        'submitted=$gameCaptureSubmittedFrames '
        'repeated=$gameCaptureRepeatedFrames '
        'duplicate_skipped=$gameCaptureDuplicateSkippedFrames '
        'delivery=$gameCaptureDeliveryQueuedFrames/'
        '$gameCaptureDeliverySubmittedFrames '
        'delivery_overwritten=$gameCaptureDeliveryOverwrittenFrames '
        'delivery_pacer_resyncs=$gameCaptureDeliveryPacerResyncs '
        'delivery_pacer_lag_max='
        '${_milliseconds(gameCaptureDeliveryPacerLagMaxMs.toDouble())} '
        'delivery_repeat_no_queue=$gameCaptureDeliveryRepeatNoQueuedFrames '
        'delivery_skip_no_queue=$gameCaptureDeliverySkipNoQueuedFrames '
        'delivery_fresh_wake_after_skip='
        '$gameCaptureDeliveryFreshWakeAfterSkipFrames '
        'delivery_fresh_immediate=$gameCaptureDeliveryFreshImmediateFrames '
        'delivery_repeat_policy='
        '${gameCaptureDeliveryRepeatPolicy ?? 'skip-on-miss'} '
        'delivery_queue_depth=${gameCaptureDeliveryQueueDepth ?? '?'} '
        'delivery_repeat_source_age='
        '${_milliseconds(averageGameCaptureDeliveryRepeatSourceAgeMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryRepeatSourceAgeMs)} '
        'delivery_on_frame='
        '${_milliseconds(averageGameCaptureDeliveryOnFrameMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryOnFrameMs)} '
        'delivery_submit_prep='
        '${_milliseconds(averageGameCaptureDeliverySubmitPrepMs)}/'
        '${_milliseconds(maxGameCaptureDeliverySubmitPrepMs)} '
        'delivery_on_frame_call='
        '${_milliseconds(averageGameCaptureDeliveryOnFrameCallMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryOnFrameCallMs)} '
        'delivery_post_on_frame='
        '${_milliseconds(averageGameCaptureDeliveryPostOnFrameMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryPostOnFrameMs)} '
        'native_buffer_release='
        '${_milliseconds(averageGameCaptureNativeBufferReleaseMs)}/'
        '${_milliseconds(maxGameCaptureNativeBufferReleaseMs)} '
        'ready_to_queue='
        '${_milliseconds(averageGameCaptureReadyToQueueMs)}/'
        '${_milliseconds(maxGameCaptureReadyToQueueMs)} '
        'delivery_queue_wait='
        '${_milliseconds(averageGameCaptureDeliveryQueueWaitMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryQueueWaitMs)} '
        'delivery_overwrite_age='
        '${_milliseconds(averageGameCaptureDeliveryOverwriteAgeMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryOverwriteAgeMs)} '
        'delivery_overwritten_fresh='
        '$gameCaptureDeliveryOverwrittenFreshFrames '
        'ready_to_submit='
        '${_milliseconds(averageGameCaptureReadyToSubmitMs)}/'
        '${_milliseconds(maxGameCaptureReadyToSubmitMs)} '
        'source_to_submit='
        '${_milliseconds(averageGameCaptureSourceToSubmitMs)}/'
        '${_milliseconds(maxGameCaptureSourceToSubmitMs)} '
        'source_to_readback_ready='
        '${_milliseconds(averageGameCaptureSourceToReadbackReadyMs)}/'
        '${_milliseconds(maxGameCaptureSourceToReadbackReadyMs)} '
        'readback_queue_to_map='
        '${_milliseconds(averageGameCaptureReadbackQueueToMapMs)}/'
        '${_milliseconds(maxGameCaptureReadbackQueueToMapMs)} '
        'map_to_i420='
        '${_milliseconds(averageGameCaptureMapToI420Ms)}/'
        '${_milliseconds(maxGameCaptureMapToI420Ms)} '
        'source_to_i420_ready='
        '${_milliseconds(averageGameCaptureSourceToI420ReadyMs)}/'
        '${_milliseconds(maxGameCaptureSourceToI420ReadyMs)} '
        'source_to_queue='
        '${_milliseconds(averageGameCaptureSourceToQueueMs)}/'
        '${_milliseconds(maxGameCaptureSourceToQueueMs)} '
        'source_duplicate_skip_age='
        '${_milliseconds(averageGameCaptureSourceDuplicateSkipAgeMs)}/'
        '${_milliseconds(maxGameCaptureSourceDuplicateSkipAgeMs)} '
        'copied=$gameCaptureCopiedFrames '
        'dropped=$gameCaptureDroppedFrames '
        'overwritten=$gameCaptureOverwrittenFrames '
        'gpu_scaled=$gameCaptureGpuScaledFrames '
        'gpu_failures=$gameCaptureGpuScaleFailures '
        'cpu_fallback=$gameCaptureCpuFallbackFrames '
        'native_nv12=$gameCaptureNativeNv12SubmittedFrames '
        'native_nv12_async=$gameCaptureNativeNv12QueuedFrames/'
        '$gameCaptureNativeNv12ReadyFrames '
        'native_nv12_not_ready=$gameCaptureNativeNv12NotReadyPolls '
        'native_nv12_ready_policy='
        '${gameCaptureNativeNv12ReadyPolicy ?? 'unknown'} '
        'native_nv12_fence_available='
        '${gameCaptureNativeNv12FenceAvailable ?? '?'} '
        'native_nv12_pending_poll_ms='
        '${gameCaptureNativeNv12PendingPollMs ?? '?'} '
        'native_nv12_max_pending_slots='
        '${gameCaptureNativeNv12MaxPendingSlots ?? '?'} '
        'native_nv12_ready_drain_depth='
        '${gameCaptureNativeNv12ReadyDrainDepth ?? '?'} '
        'native_nv12_frame_ownership='
        '${gameCaptureNativeNv12FrameOwnership ?? 'unknown'} '
        'native_nv12_fence='
        '$gameCaptureNativeNv12FenceSignaledFrames/'
        '$gameCaptureNativeNv12FenceReadyFrames/'
        '$gameCaptureNativeNv12FenceSignalFailures '
        'native_nv12_owned_copy='
        '$gameCaptureNativeNv12OwnedCopies '
        '${_milliseconds(averageGameCaptureNativeNv12OwnedCopyMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12OwnedCopyMs)} '
        'native_nv12_overwritten=$gameCaptureNativeNv12OverwrittenFrames '
        'native_nv12_overwrite_age='
        '${_milliseconds(averageGameCaptureNativeNv12OverwriteAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12OverwriteAgeMs)} '
        'native_nv12_overwritten_fresh='
        '$gameCaptureNativeNv12OverwrittenFreshFrames '
        'native_nv12_ready_dropped='
        '$gameCaptureNativeNv12ReadyDroppedFrames '
        'native_nv12_ready_drop_age='
        '${_milliseconds(averageGameCaptureNativeNv12ReadyDropAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12ReadyDropAgeMs)} '
        'native_nv12_ready_dropped_fresh='
        '$gameCaptureNativeNv12ReadyDroppedFreshFrames '
        'native_nv12_failures=$gameCaptureNativeNv12Failures '
        'native_nv12_convert='
        '${_milliseconds(averageGameCaptureNativeNv12ConvertMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12ConvertMs)} '
        'native_nv12_samples=$gameCaptureNativeNv12ConvertSamples '
        'native_nv12_bgra_scale_draw='
        '${_milliseconds(averageGameCaptureNativeNv12BgraScaleDrawMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12BgraScaleDrawMs)} '
        'native_nv12_blt_submit='
        '${_milliseconds(averageGameCaptureNativeNv12VideoProcessorBltSubmitMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12VideoProcessorBltSubmitMs)} '
        'native_nv12_blt_to_ready='
        '${_milliseconds(averageGameCaptureNativeNv12VideoProcessorBltToReadyMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12VideoProcessorBltToReadyMs)} '
        'native_nv12_buffer_create='
        '${_milliseconds(averageGameCaptureNativeNv12BufferCreateMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12BufferCreateMs)} '
        'native_nv12_frame_ready_to_queue='
        '${_milliseconds(averageGameCaptureNativeNv12FrameReadyToQueueMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12FrameReadyToQueueMs)} '
        'native_nv12_conversion_start_age='
        '${_milliseconds(averageGameCaptureNativeNv12ConversionStartAgeMs)}/'
        '${_milliseconds(maxGameCaptureNativeNv12ConversionStartAgeMs)} '
        'native_nv12_stale_before_queue='
        '$gameCaptureNativeNv12StaleBeforeQueueFrames '
        'native_nv12_disabled='
        '${gameCaptureNativeNv12HandoffDisabledReason ?? 'none'} '
        'readback=$gameCaptureReadbackQueuedFrames/'
        '$gameCaptureReadbackReadyFrames '
        'readback_not_ready=$gameCaptureReadbackNotReadyFrames '
        'readback_overwritten=$gameCaptureReadbackOverwrittenFrames '
        'readback_stale_dropped=$gameCaptureReadbackStaleDroppedFrames '
        'readback_latency_dropped=$gameCaptureReadbackLatencyDroppedFrames '
        'readback_map_attempts=$gameCaptureReadbackMapAttempts '
        'readback_latency='
        '${_milliseconds(averageGameCaptureReadbackLatencyMs)} '
        'readback_latency_frames='
        '${_number(averageGameCaptureReadbackLatencyFrames)}/'
        '$gameCaptureMaxReadbackLatencyFrames '
        'source_frame=$gameCaptureSourceFrameIndex '
        'last_submitted_source_frame='
        '$gameCaptureLastSubmittedSourceFrameIndex '
        'source_regressions=$gameCaptureSourceFrameRegressions '
        'source_duplicates=$gameCaptureSourceFrameDuplicates '
        'source_gaps=$gameCaptureSourceFrameGaps '
        'shared_slot_mismatches=$gameCaptureSharedSlotMismatches '
        'timestamp=${gameCaptureTimestampMode ?? 'unknown'} '
        'timestamp_source_qpc=$gameCaptureTimestampSourceQpcFrames '
        'timestamp_paced_fallback='
        '$gameCaptureTimestampPacedFallbackFrames '
        'timestamp_repeated=$gameCaptureTimestampRepeatedFrames '
        'timestamp_delta=${_milliseconds(averageGameCaptureTimestampDeltaMs)}/'
        '${_milliseconds(maxGameCaptureTimestampDeltaMs)} '
        'timestamp_adjustments=$gameCaptureTimestampAdjustments '
        'delivery_wall_delta='
        '${_milliseconds(averageGameCaptureDeliveryWallDeltaMs)}/'
        '${_milliseconds(maxGameCaptureDeliveryWallDeltaMs)} '
        'delivery_wall_min='
        '${_milliseconds(minGameCaptureDeliveryWallDeltaMs)} '
        'delivery_wall_samples=$gameCaptureDeliveryWallSamples '
        'delivery_wall_over2x=$gameCaptureDeliveryWallOver2xFrames '
        'delivery_wall_over3x=$gameCaptureDeliveryWallOver3xFrames '
        'delivery_wall_under_half=$gameCaptureDeliveryWallUnderHalfFrames '
        'source_qpc_delta='
        '${_milliseconds(averageGameCaptureSourceQpcDeltaMs)}/'
        '${_milliseconds(maxGameCaptureSourceQpcDeltaMs)} '
        'source_qpc_regressions=$gameCaptureSourceQpcRegressions '
        'gpu_scale=${_milliseconds(averageGameCaptureGpuScaleMs)} '
        'copy=${_milliseconds(averageGameCaptureCopyMs)} '
        'map=${_milliseconds(averageGameCaptureMapMs)} '
        'convert=${_milliseconds(averageGameCaptureConvertMs)} '
        'failures=$gameCaptureMapFailures/$gameCaptureConvertFailures '
        'proof=$gameCaptureProofFrames/$gameCaptureVisibleProofFrames '
        '$proofState '
        'initial_black_skipped=$gameCaptureInitialBlackSkippedFrames '
        'visible_source_seen=${gameCaptureVisibleSourceSeen ?? '?'} '
        'luma=${gameCaptureProofMinLuma ?? '?'}/'
        '${gameCaptureProofMaxLuma ?? '?'} '
        'samples=${gameCaptureProofNonzeroSamples ?? '?'}/'
        '${gameCaptureProofSamples ?? '?'} '
        'path=${gameCaptureProofPath ?? 'none'} '
        'i420_proof=$gameCaptureI420ProofFrames/'
        '$gameCaptureVisibleI420ProofFrames '
        '$i420ProofState '
        'i420_luma=${gameCaptureI420ProofMinLuma ?? '?'}/'
        '${gameCaptureI420ProofMaxLuma ?? '?'} '
        'i420_samples=${gameCaptureI420ProofNonzeroSamples ?? '?'}/'
        '${gameCaptureI420ProofSamples ?? '?'} '
        'i420_path=${gameCaptureI420ProofPath ?? 'none'}';
  }

  String get updatedRegionShapeLabel {
    final avgRatio = averageUpdatedRegionAreaRatio;
    final maxRatio = maxUpdatedRegionAreaRatio;
    if (updatedRegionRectCount <= 0 &&
        updatedRegionMaxRectCount <= 0 &&
        avgRatio == null &&
        maxRatio == null &&
        updatedRegionFullFrameCount == 0 &&
        updatedRegionTinyFrameCount == 0) {
      return 'unknown';
    }
    return 'rects=$updatedRegionRectCount max=$updatedRegionMaxRectCount '
        'area=${_ratioPercent(avgRatio)} avg / ${_ratioPercent(maxRatio)} max '
        'full=$updatedRegionFullFrameCount tiny=$updatedRegionTinyFrameCount';
  }

  String get fullSourceAcquisitionAttributionLabel {
    final hasSizeEvidence = nativeSourceWidth != null ||
        requestedMaxWidth != null ||
        contentWidth != null ||
        preEncodeWidth != null;
    if (!hasSizeEvidence && averageSourceCaptureMs == null) {
      return 'unknown';
    }
    final contentRatio = _pixelRatio(
      nativeSourceWidth,
      nativeSourceHeight,
      contentWidth,
      contentHeight,
    );
    final preEncodeRatio = _pixelRatio(
      nativeSourceWidth,
      nativeSourceHeight,
      preEncodeWidth,
      preEncodeHeight,
    );
    return 'source=$nativeSourceResolutionLabel '
        '(${_megapixels(nativeSourceWidth, nativeSourceHeight)}) '
        'requested_max=$requestedMaxResolutionLabel '
        'content=$contentResolutionLabel '
        'pre_encode=$preEncodeResolutionLabel '
        'source_to_content=${_ratioMultiplier(contentRatio)} '
        'source_to_pre_encode=${_ratioMultiplier(preEncodeRatio)} '
        'source_capture=${_milliseconds(averageSourceCaptureMs)} avg / '
        '${_milliseconds(maxSourceCaptureMs)} max';
  }

  String get blockingAcquireAttributionLabel {
    if (averageCaptureAcquireWaitMs == null &&
        averageCallbackEntryDelayMs == null &&
        averageSourceCaptureMs == null &&
        averagePostCallbackWaitMs == null &&
        averageUnaccountedWaitMs == null) {
      return 'unknown';
    }
    return 'dominant=$dominantCaptureDelayStageLabel '
        'acquire_wait=${_milliseconds(averageCaptureAcquireWaitMs)} avg / '
        '${_milliseconds(maxCaptureAcquireWaitMs)} max '
        'callback_entry=${_milliseconds(averageCallbackEntryDelayMs)} avg / '
        '${_milliseconds(maxCallbackEntryDelayMs)} max '
        'source_capture=${_milliseconds(averageSourceCaptureMs)} avg / '
        '${_milliseconds(maxSourceCaptureMs)} max '
        'post_callback=${_milliseconds(averagePostCallbackWaitMs)} avg / '
        '${_milliseconds(maxPostCallbackWaitMs)} max '
        'unaccounted=${_milliseconds(averageUnaccountedWaitMs)} avg / '
        '${_milliseconds(maxUnaccountedWaitMs)} max';
  }

  String get cpuReadbackAttributionLabel {
    final parts = <String>[];
    if (reportWgcFrameSummaryLabel != 'unknown' &&
        reportWgcFrameSummaryLabel != 'not_applicable_game_hook') {
      parts.add(
        'WGC map=${_milliseconds(averageWgcMapTextureMs)} avg / '
        '${_milliseconds(maxWgcMapTextureMs)} max '
        'copy_rows=${_milliseconds(averageWgcCopyRowsMs)} avg / '
        '${_milliseconds(maxWgcCopyRowsMs)} max '
        'copy_texture=${_milliseconds(averageWgcCopyTextureMs)} avg / '
        '${_milliseconds(maxWgcCopyTextureMs)} max '
        'try_get=${_milliseconds(averageWgcTryGetFrameMs)} avg / '
        '${_milliseconds(maxWgcTryGetFrameMs)} max',
      );
    }
    if (reportGdiFrameSummaryLabel != 'unknown' &&
        reportGdiFrameSummaryLabel != 'not_applicable_game_hook') {
      parts.add(
        'GDI mode=$windowGdiCaptureModeLabel '
        'final_methods=[$gdiFinalMethodMixLabel] '
        'black_frames=$gdiBlackFrameCount '
        'low_variance_frames=$gdiLowVarianceFrameCount '
        'print_full=${_milliseconds(averageGdiPrintFullMs)} avg / '
        '${_milliseconds(maxGdiPrintFullMs)} max '
        'print_fallback=${_milliseconds(averageGdiPrintFallbackMs)} avg / '
        '${_milliseconds(maxGdiPrintFallbackMs)} max '
        'bitblt=${_milliseconds(averageGdiBitBltMs)} avg / '
        '${_milliseconds(maxGdiBitBltMs)} max '
        'crop=${_milliseconds(averageGdiCropMs)} avg / '
        '${_milliseconds(maxGdiCropMs)} max',
      );
    }
    if (averageFrameConvertMs != null || averageFrameScaleMs != null) {
      parts.add(
        'wrapper convert=${_milliseconds(averageFrameConvertMs)} '
        'scale=${_milliseconds(averageFrameScaleMs)}',
      );
    }
    if (gameCaptureFrameSummaryLabel != 'unknown') {
      parts.add('game_capture=[$gameCaptureFrameSummaryLabel]');
    }
    return parts.isEmpty ? 'unknown' : parts.join('; ');
  }

  String get dirtyRegionProcessingAttributionLabel {
    final shape = updatedRegionShapeLabel;
    if (shape == 'unknown' && averageUpdatedRegionAnalysisMs == null) {
      return 'unknown';
    }
    return 'mode=$dirtyRegionModeLabel shape=$shape '
        'analysis=${_milliseconds(averageUpdatedRegionAnalysisMs)} avg / '
        '${_milliseconds(maxUpdatedRegionAnalysisMs)} max';
  }

  String get frameLifetimeSyncAttributionLabel {
    if (averageCallbackEntryDelayMs == null &&
        averagePostCallbackWaitMs == null &&
        averageUnaccountedWaitMs == null &&
        averagePacerFrameAgeMs == null) {
      return 'unknown';
    }
    return 'callback_entry=${_milliseconds(averageCallbackEntryDelayMs)} avg / '
        '${_milliseconds(maxCallbackEntryDelayMs)} max '
        'post_callback=${_milliseconds(averagePostCallbackWaitMs)} avg / '
        '${_milliseconds(maxPostCallbackWaitMs)} max '
        'unaccounted=${_milliseconds(averageUnaccountedWaitMs)} avg / '
        '${_milliseconds(maxUnaccountedWaitMs)} max '
        'pacer_age=${_milliseconds(averagePacerFrameAgeMs)} avg / '
        '${_milliseconds(maxPacerFrameAgeMs)} max';
  }

  String get fullFrameCopyBeforeDownscaleAttributionLabel {
    final ratio = _pixelRatio(
      nativeSourceWidth,
      nativeSourceHeight,
      contentWidth,
      contentHeight,
    );
    final hasFrameWork =
        averageFrameConvertMs != null || averageFrameScaleMs != null;
    if (ratio == null && !hasFrameWork) {
      return 'unknown';
    }
    final likelyFullFrameCopy =
        ratio != null && ratio > 1.05 && averageFrameConvertMs != null;
    return 'pre_scale_full_frame_copy='
        '${likelyFullFrameCopy ? 'likely' : 'not_indicated'} '
        'source=$nativeSourceResolutionLabel '
        'content=$contentResolutionLabel '
        'pre_encode=$preEncodeResolutionLabel '
        'source_to_content=${_ratioMultiplier(ratio)} '
        'convert=${_milliseconds(averageFrameConvertMs)} '
        'scale=${_milliseconds(averageFrameScaleMs)} '
        'callback=${_milliseconds(averageFrameCallbackMs)} avg / '
        '${_milliseconds(maxFrameCallbackMs)} max';
  }

  Map<String, Object?> get captureCauseAttribution => {
        'fullSourceAcquisition': fullSourceAcquisitionAttributionLabel,
        'blockingAcquireWait': blockingAcquireAttributionLabel,
        'cpuReadbackOrCopy': cpuReadbackAttributionLabel,
        'dirtyRegionProcessing': dirtyRegionProcessingAttributionLabel,
        'frameLifetimeOrSynchronization': frameLifetimeSyncAttributionLabel,
        'fullFrameCopyBeforeDownscale':
            fullFrameCopyBeforeDownscaleAttributionLabel,
      };

  String get dominantWgcFrameStageLabel {
    final stages = <({String label, double value})>[
      if (averageWgcMapTextureMs != null)
        (label: 'map_texture', value: averageWgcMapTextureMs!),
      if (averageWgcCopyRowsMs != null)
        (label: 'copy_rows', value: averageWgcCopyRowsMs!),
      if (averageWgcZeroHertzMs != null)
        (label: 'zero_hertz_compare', value: averageWgcZeroHertzMs!),
      if (averageWgcCopyTextureMs != null)
        (label: 'copy_texture', value: averageWgcCopyTextureMs!),
      if (averageWgcTryGetFrameMs != null)
        (label: 'try_get_frame', value: averageWgcTryGetFrameMs!),
      if (averageWgcSurfaceMs != null)
        (label: 'surface', value: averageWgcSurfaceMs!),
      if (averageWgcTextureMs != null)
        (label: 'texture', value: averageWgcTextureMs!),
      if (averageWgcContentSizeMs != null)
        (label: 'content_size', value: averageWgcContentSizeMs!),
      if (averageWgcMonitorScaleMs != null)
        (label: 'monitor_scale', value: averageWgcMonitorScaleMs!),
    ];
    final framePoolMissCount = wgcFramePoolEmptyCount +
        wgcFramePoolReuseCount +
        wgcCaptureFrameNullCount;
    final framePoolMissRatio = wgcCaptureCalls <= 0
        ? 0.0
        : framePoolMissCount / max(1, wgcCaptureCalls);
    final ensureSleepRatio = wgcEnsureFrameCalls <= 0
        ? 0.0
        : wgcEnsureSleepCount / max(1, wgcEnsureFrameCalls);
    if (framePoolMissRatio >= 0.10) {
      stages.add(
        (
          label: 'frame_pool_empty',
          value: averageWgcEnsureFrameMs ?? averageWgcProcessFrameMs ?? 0,
        ),
      );
    }
    if (ensureSleepRatio >= 0.10) {
      stages.add(
        (
          label: 'startup_wait',
          value: averageWgcEnsureFrameMs ?? averageWgcGetFrameMs ?? 0,
        ),
      );
    }
    if (stages.isEmpty) {
      if (framePoolMissCount > 0) {
        return 'frame_pool_empty';
      }
      if (wgcEnsureSleepCount > 0) {
        return 'startup_wait';
      }
      return 'unknown';
    }
    stages.sort((a, b) => b.value.compareTo(a.value));
    return stages.first.label;
  }

  String get wgcFrameSummaryLabel {
    if (wgcCaptureCalls <= 0 &&
        averageWgcGetFrameMs == null &&
        averageWgcProcessFrameMs == null) {
      return 'unknown';
    }
    return 'dominant=$dominantWgcFrameStageLabel '
        'calls=$wgcCaptureCalls successes=$wgcCaptureSuccessCount '
        'source_not_capturable=$wgcSourceNotCapturableCount '
        'ensure=${_milliseconds(averageWgcEnsureFrameMs)} avg / '
        '${_milliseconds(maxWgcEnsureFrameMs)} max '
        'ensure_sleeps=$wgcEnsureSleepCount '
        'process=${_milliseconds(averageWgcProcessFrameMs)} avg / '
        '${_milliseconds(maxWgcProcessFrameMs)} max '
        'process_successes=$wgcProcessFrameSuccessCount/$wgcProcessFrameCalls '
        'try_get=${_milliseconds(averageWgcTryGetFrameMs)} avg / '
        '${_milliseconds(maxWgcTryGetFrameMs)} max '
        'map=${_milliseconds(averageWgcMapTextureMs)} avg / '
        '${_milliseconds(maxWgcMapTextureMs)} max '
        'copy_rows=${_milliseconds(averageWgcCopyRowsMs)} avg / '
        '${_milliseconds(maxWgcCopyRowsMs)} max '
        'zero_hertz=${_milliseconds(averageWgcZeroHertzMs)} avg / '
        '${_milliseconds(maxWgcZeroHertzMs)} max '
        'frame_pool_empty=$wgcFramePoolEmptyCount '
        'frame_pool_reuse=$wgcFramePoolReuseCount '
        'capture_frame_null=$wgcCaptureFrameNullCount '
        'resizes=$wgcResizeCount '
        'recreates=$wgcFramePoolRecreateCount';
  }

  String get gdiOriginalResolutionLabel =>
      _resolutionLabel(gdiOriginalWidth, gdiOriginalHeight);

  String get gdiCroppedResolutionLabel =>
      _resolutionLabel(gdiCroppedWidth, gdiCroppedHeight);

  String get gdiFrameResolutionLabel =>
      _resolutionLabel(gdiFrameWidth, gdiFrameHeight);

  int get gdiFinalFrameCount =>
      gdiFinalPrintFullCount +
      gdiFinalPrintFallbackCount +
      gdiFinalBitBltCount +
      gdiFinalNoneCount;

  double? get gdiBlackFrameRatio {
    final total = gdiFinalFrameCount;
    if (total <= 0) {
      return null;
    }
    return (gdiBlackFrameCount / total).clamp(0.0, 1.0).toDouble();
  }

  double? get gdiLowVarianceFrameRatio {
    final total = gdiFinalFrameCount;
    if (total <= 0) {
      return null;
    }
    return (gdiLowVarianceFrameCount / total).clamp(0.0, 1.0).toDouble();
  }

  bool get gdiOutputProbablyInvalid {
    final total = gdiFinalFrameCount;
    if (total < 10) {
      return false;
    }
    final blackThreshold = total * 0.8;
    final lowVarianceThreshold = total * 0.8;
    return gdiBlackFrameCount >= blackThreshold &&
        gdiLowVarianceFrameCount >= lowVarianceThreshold;
  }

  String get gdiOutputValidityLabel {
    final total = gdiFinalFrameCount;
    if (total <= 0) {
      return 'unknown';
    }
    final blackRatio = gdiBlackFrameRatio ?? 0;
    final lowVarianceRatio = gdiLowVarianceFrameRatio ?? 0;
    final status =
        gdiOutputProbablyInvalid ? 'invalid_black_low_variance' : 'valid';
    return '$status black=$gdiBlackFrameCount/$total '
        '(${(blackRatio * 100).toStringAsFixed(1)}%) '
        'low_variance=$gdiLowVarianceFrameCount/$total '
        '(${(lowVarianceRatio * 100).toStringAsFixed(1)}%) '
        'final_methods=[$gdiFinalMethodMixLabel]';
  }

  String get gdiFinalMethodMixLabel {
    final total = gdiFinalFrameCount;
    if (total <= 0) {
      return 'unknown';
    }
    return 'print_full=$gdiFinalPrintFullCount '
        'print_fallback=$gdiFinalPrintFallbackCount '
        'bitblt=$gdiFinalBitBltCount none=$gdiFinalNoneCount';
  }

  String get dominantGdiFrameStageLabel {
    final stages = <({String label, double value})>[
      if (averageGdiPrintFullMs != null)
        (label: 'print_full', value: averageGdiPrintFullMs!),
      if (averageGdiPrintFallbackMs != null)
        (label: 'print_fallback', value: averageGdiPrintFallbackMs!),
      if (averageGdiBitBltMs != null)
        (label: 'bitblt', value: averageGdiBitBltMs!),
      if (averageGdiOwnedCaptureMs != null)
        (label: 'owned_capture', value: averageGdiOwnedCaptureMs!),
      if (averageGdiOwnedCompositeMs != null)
        (label: 'owned_composite', value: averageGdiOwnedCompositeMs!),
      if (averageGdiOwnedEnumMs != null)
        (label: 'owned_enum', value: averageGdiOwnedEnumMs!),
      if (averageGdiCropMs != null) (label: 'crop', value: averageGdiCropMs!),
      if (averageGdiCreateFrameMs != null)
        (label: 'create_frame', value: averageGdiCreateFrameMs!),
      if (averageGdiGetDcSizeMs != null)
        (label: 'get_dc_size', value: averageGdiGetDcSizeMs!),
      if (averageGdiGetDcMs != null)
        (label: 'get_dc', value: averageGdiGetDcMs!),
      if (averageGdiRectMs != null)
        (label: 'window_rect', value: averageGdiRectMs!),
      if (averageGdiVisibilityMs != null)
        (label: 'visibility', value: averageGdiVisibilityMs!),
      if (averageGdiMemDcMs != null)
        (label: 'mem_dc', value: averageGdiMemDcMs!),
      if (averageGdiCleanupMs != null)
        (label: 'cleanup', value: averageGdiCleanupMs!),
    ];
    if (gdiPermanentErrorCount > 0 && gdiCaptureSuccessCount == 0) {
      return 'permanent_error';
    }
    if (gdiTemporaryErrorCount > 0 && gdiCaptureSuccessCount == 0) {
      if (gdiRectFailCount > 0) {
        return 'window_rect';
      }
      if (gdiDcFailCount > 0) {
        return 'get_dc';
      }
      if (gdiFrameCreateFailCount > 0) {
        return 'create_frame';
      }
      return 'temporary_error';
    }
    if (gdiHiddenOrMinimizedCount > 0 &&
        gdiHiddenOrMinimizedCount >= max(1, gdiCaptureCalls) * 0.25) {
      stages.add((label: 'hidden_or_minimized', value: averageGdiTotalMs ?? 0));
    }
    if (stages.isEmpty) {
      return 'unknown';
    }
    stages.sort((a, b) => b.value.compareTo(a.value));
    return stages.first.label;
  }

  String get gdiFrameSummaryLabel {
    if (gdiCaptureCalls <= 0 && averageGdiTotalMs == null) {
      return 'unknown';
    }
    return 'dominant=$dominantGdiFrameStageLabel '
        'mode=$windowGdiCaptureModeLabel '
        'calls=$gdiCaptureCalls successes=$gdiCaptureSuccessCount '
        'temp_errors=$gdiTemporaryErrorCount '
        'permanent_errors=$gdiPermanentErrorCount '
        'hidden=$gdiHiddenOrMinimizedCount '
        'rect_fail=$gdiRectFailCount dc_fail=$gdiDcFailCount '
        'frame_create_fail=$gdiFrameCreateFailCount '
        'original=$gdiOriginalResolutionLabel '
        'cropped=$gdiCroppedResolutionLabel '
        'frame=$gdiFrameResolutionLabel '
        'total=${_milliseconds(averageGdiTotalMs)} avg / '
        '${_milliseconds(maxGdiTotalMs)} max '
        'print_full=${_milliseconds(averageGdiPrintFullMs)} avg / '
        '${_milliseconds(maxGdiPrintFullMs)} max '
        'print_full_successes=$gdiPrintFullSuccessCount/$gdiPrintFullCallCount '
        'print_fallback=${_milliseconds(averageGdiPrintFallbackMs)} avg / '
        '${_milliseconds(maxGdiPrintFallbackMs)} max '
        'print_fallback_successes=$gdiPrintFallbackSuccessCount/'
        '$gdiPrintFallbackCallCount '
        'bitblt=${_milliseconds(averageGdiBitBltMs)} avg / '
        '${_milliseconds(maxGdiBitBltMs)} max '
        'bitblt_successes=$gdiBitBltSuccessCount/$gdiBitBltCallCount '
        'final_methods=[$gdiFinalMethodMixLabel] '
        'black_frames=$gdiBlackFrameCount '
        'low_variance_frames=$gdiLowVarianceFrameCount '
        'crop=${_milliseconds(averageGdiCropMs)} avg / '
        '${_milliseconds(maxGdiCropMs)} max '
        'owned_capture=${_milliseconds(averageGdiOwnedCaptureMs)} avg / '
        '${_milliseconds(maxGdiOwnedCaptureMs)} max '
        'owned_capture_successes=$gdiOwnedWindowCaptureSuccessCount/'
        '$gdiOwnedWindowCaptureCallCount '
        'owned_windows=$gdiOwnedWindowFrameCount';
  }

  String get dominantCaptureDelayStageLabel {
    final phases = <({String label, double value})>[
      if (averageSourceCaptureMs != null)
        (label: 'source_capture', value: averageSourceCaptureMs!),
      if (averageCallbackEntryDelayMs != null)
        (label: 'callback_entry', value: averageCallbackEntryDelayMs!),
      if (averageCaptureResultCallbackMs != null)
        (label: 'capture_callback', value: averageCaptureResultCallbackMs!),
      if (averagePostCallbackWaitMs != null)
        (label: 'post_callback', value: averagePostCallbackWaitMs!),
      if (averageUnaccountedWaitMs != null)
        (label: 'unaccounted_wait', value: averageUnaccountedWaitMs!),
    ];
    if (phases.isEmpty) {
      return 'unknown';
    }
    phases.sort((a, b) => b.value.compareTo(a.value));
    final dominant = phases.first.label;
    if (dominant == 'source_capture' &&
        !hasGameCaptureEvidence &&
        dominantWgcFrameStageLabel != 'unknown') {
      return '$dominant/$dominantWgcFrameStageLabel';
    }
    if (dominant == 'source_capture' &&
        !hasGameCaptureEvidence &&
        dominantGdiFrameStageLabel != 'unknown' &&
        gdiFrameSummaryLabel != 'unknown') {
      return '$dominant/$dominantGdiFrameStageLabel';
    }
    return dominant;
  }

  String get capturePhaseSummaryLabel {
    if (dominantCaptureDelayStageLabel == 'unknown') {
      return 'unknown';
    }
    return 'dominant=$dominantCaptureDelayStageLabel '
        'source=${_milliseconds(averageSourceCaptureMs)} '
        'callback_entry=${_milliseconds(averageCallbackEntryDelayMs)} '
        'callback=${_milliseconds(averageCaptureResultCallbackMs)} '
        'post=${_milliseconds(averagePostCallbackWaitMs)} '
        'unaccounted=${_milliseconds(averageUnaccountedWaitMs)}';
  }

  String get summaryLabel {
    if (!hasEvidence) {
      return 'unknown';
    }
    return 'backend=$backendLabel '
        'capturer=$observedCapturerLabel '
        'dirty_region_mode=$dirtyRegionModeLabel '
        'window_gdi_mode=$windowGdiCaptureModeLabel '
        'source=${nativeSourceResolutionLabel} '
        'requested_max=${requestedMaxResolutionLabel} '
        'window_rect=${nativeWindowRectResolutionLabel} '
        'content=${contentResolutionLabel} '
        'pre_encode=${preEncodeResolutionLabel} '
        'canvas=$canvasLabel '
        'native_fps=${_number(averageNativeFps)} '
        'submitted_fps=${_number(averageSubmittedFps)} '
        'capture_call=${_milliseconds(averageCaptureCallMs)} avg / '
        '${_milliseconds(maxCaptureCallMs)} max '
        'source_capture=${_milliseconds(averageSourceCaptureMs)} avg / '
        '${_milliseconds(maxSourceCaptureMs)} max '
        'source_capture_count=$sourceCaptureSampleCount '
        'wgc_frame=[$reportWgcFrameSummaryLabel] '
        'gdi_frame=[$reportGdiFrameSummaryLabel] '
        'game_capture=[$gameCaptureFrameSummaryLabel] '
        'capture_phase=$capturePhaseSummaryLabel '
        'callback_entry=${_milliseconds(averageCallbackEntryDelayMs)} avg / '
        '${_milliseconds(maxCallbackEntryDelayMs)} max '
        'capture_callback=${_milliseconds(averageCaptureResultCallbackMs)} avg / '
        '${_milliseconds(maxCaptureResultCallbackMs)} max '
        'acquire_wait=${_milliseconds(averageCaptureAcquireWaitMs)} avg / '
        '${_milliseconds(maxCaptureAcquireWaitMs)} max '
        'post_callback=${_milliseconds(averagePostCallbackWaitMs)} avg / '
        '${_milliseconds(maxPostCallbackWaitMs)} max '
        'unaccounted_wait=${_milliseconds(averageUnaccountedWaitMs)} avg / '
        '${_milliseconds(maxUnaccountedWaitMs)} max '
        'callback_count=$captureResultCallbackCount '
        'frame_interval=${_milliseconds(p95FrameIntervalMs)} p95 / '
        '${_milliseconds(maxFrameIntervalMs)} max '
        'frame_callback=${_milliseconds(averageFrameCallbackMs)} avg / '
        '${_milliseconds(maxFrameCallbackMs)} max '
        'pacer=${latestFramePacerEnabled == null ? '?' : latestFramePacerEnabled! ? 'on' : 'off'} '
        'pacer_submit=${_number(averagePacerSubmittedFps)} '
        'pacer_unique=${_number(averagePacerUniqueFps)} '
        'pacer_interval=${_milliseconds(p95PacerIntervalMs)} p95 / '
        '${_milliseconds(maxPacerIntervalMs)} max '
        'pacer_age=${_milliseconds(averagePacerFrameAgeMs)} avg / '
        '${_milliseconds(maxPacerFrameAgeMs)} max '
        'pacer_on_frame=${_milliseconds(averagePacerOnFrameMs)} avg / '
        '${_milliseconds(maxPacerOnFrameMs)} max '
        'convert=${_milliseconds(averageFrameConvertMs)} '
        'scale=${_milliseconds(averageFrameScaleMs)} '
        'on_frame=${_milliseconds(averageFrameOnFrameMs)} '
        'updated_region=$updatedRegionNonEmptyCount dirty / '
        '$updatedRegionEmptyCount empty '
        'updated_region_shape=$updatedRegionShapeLabel '
        'updated_region_analysis=${_milliseconds(averageUpdatedRegionAnalysisMs)} avg / '
        '${_milliseconds(maxUpdatedRegionAnalysisMs)} max '
        'encoder_total=${_milliseconds(averageEncoderTotalMs)} avg / '
        '${_milliseconds(maxEncoderTotalMs)} max '
        'encoder_slow=$encoderSlowFrameCount/$encoderSampleCount '
        'encoder_input=$encoderInputPathLabel '
        'encoder_native_input=$encoderNativeInputFrames '
        'encoder_cpu_i420_input=$encoderCpuI420InputFrames '
        'encoder_native_sample_failures=$encoderNativeSampleFailures '
        'encoder_native_suspended=$encoderNativeSuspendedFrames '
        'encoder_native_ready_fence=$encoderNativeReadyFenceFrames '
        'encoder_native_ready_fence_timeout='
        '$encoderNativeReadyFenceTimeoutFrames '
        'encoder_native_ready_fence_wait='
        '${_milliseconds(averageEncoderNativeReadyFenceWaitMs)} avg / '
        '${_milliseconds(maxEncoderNativeReadyFenceWaitMs)} max '
        'encoder_native_ready_fence_wait_samples='
        '$encoderNativeReadyFenceWaitSamples '
        'encoder_native_source='
        '${encoderNativeSourceMode ?? 'unknown'}/'
        '${encoderNativeSourceFormat ?? '?'} '
        'encoder_native_source_frame=$encoderNativeSourceFrameIndex '
        'encoder_native_source_age='
        '${_milliseconds(averageEncoderNativeSourceAgeMs)} avg / '
        '${_milliseconds(maxEncoderNativeSourceAgeMs)} max '
        'encoder_native_source_age_at_create='
        '${_milliseconds(averageEncoderNativeSourceAgeAtCreateMs)} avg / '
        '${_milliseconds(maxEncoderNativeSourceAgeAtCreateMs)} max '
        'encoder_native_buffer_age='
        '${_milliseconds(averageEncoderNativeBufferAgeMs)} avg / '
        '${_milliseconds(maxEncoderNativeBufferAgeMs)} max '
        'encoder_native_sample_lifetime='
        '${_milliseconds(averageEncoderNativeSampleLifetimeMs)} avg / '
        '${_milliseconds(maxEncoderNativeSampleLifetimeMs)} max '
        'encoder_native_sample_lifetime_samples='
        '$encoderNativeSampleLifetimeSamples '
        'encoder_native_adapter=${encoderNativeAdapterLuid ?? 'unknown'} '
        'encoder_process_input='
        '${_milliseconds(averageEncoderProcessInputMs)} avg / '
        '${_milliseconds(maxEncoderProcessInputMs)} max '
        'encoder_process_input_samples=$encoderProcessInputSamples '
        'encoder_process_output='
        '${_milliseconds(averageEncoderProcessOutputMs)} avg / '
        '${_milliseconds(maxEncoderProcessOutputMs)} max '
        'encoder_process_output_samples=$encoderProcessOutputSamples '
        'encoder_encoded_callback='
        '${_milliseconds(averageEncoderEncodedCallbackMs)} avg / '
        '${_milliseconds(maxEncoderEncodedCallbackMs)} max '
        'encoder_encoded_callback_samples=$encoderEncodedCallbackSamples '
        'encoder_encoded_callback_wait='
        '${_milliseconds(averageEncoderEncodedCallbackQueueWaitMs)} avg / '
        '${_milliseconds(maxEncoderEncodedCallbackQueueWaitMs)} max '
        'encoder_encoded_callback_wait_samples='
        '$encoderEncodedCallbackQueueWaitSamples '
        'encoder_encoded_callback_enqueue='
        '${_milliseconds(averageEncoderEncodedCallbackEnqueueMs)} avg / '
        '${_milliseconds(maxEncoderEncodedCallbackEnqueueMs)} max '
        'encoder_encoded_callback_enqueue_samples='
        '$encoderEncodedCallbackEnqueueSamples '
        'encoder_encoded_callback_async=$encoderEncodedCallbackAsyncFrames '
        'encoder_encoded_callback_queue_max='
        '$encoderMaxEncodedCallbackQueueDepth '
        'encoder_encoded_callback_drops_max=$encoderMaxEncodedCallbackDrops '
        'encoder_encoded_callback_outputs_max='
        '$encoderMaxEncodedCallbackOutputs '
        'encoder_stages=$encoderStageLabel '
        'encoder_outputs=$encoderOutputFrames '
        'encoder_output_bytes=$encoderOutputBytes '
        'encoder_queue_max=$encoderMaxQueueDepth '
        'encoder_retained_max=$encoderMaxRetainedSamples '
        'encoder_encoded_outputs_max=$encoderMaxEncodedOutputs '
        'webrtc_raw_sender=[$webrtcRawSenderBoundaryLabel] '
        'crop_region=${cropRegion == null ? '?' : cropRegion! ? 'true' : 'false'} '
        'wait_timeouts=$captureWaitTimeoutCount '
        'stale=$staleFrameReuseCount/$duplicatedFrameCount '
        'pacer_dupes=$pacerDuplicateSubmitCount '
        'pacer_overwrites=$pacerOverwrittenFrameCount '
        'pacer_skips=$pacerSkippedTickCount';
  }

  bool isCaptureLimitedFor({
    required double targetFps,
    required double? frameBudgetMs,
  }) {
    if (!hasEvidence || targetFps <= 0) {
      return false;
    }

    final captureCallSlow = averageCaptureCallMs != null &&
        frameBudgetMs != null &&
        averageCaptureCallMs! > frameBudgetMs * 1.25;
    final nativeFpsSlow =
        averageNativeFps != null && averageNativeFps! < targetFps * 0.75;
    final p95GapSlow = p95FrameIntervalMs != null &&
        frameBudgetMs != null &&
        p95FrameIntervalMs! > frameBudgetMs * 1.5;
    final maxGapSlow = maxFrameIntervalMs != null &&
        frameBudgetMs != null &&
        maxFrameIntervalMs! > frameBudgetMs * 3;
    final hasStaleFrames = staleFrameReuseCount > 0;
    final encoderLooksFast = averageEncoderTotalMs == null ||
        frameBudgetMs == null ||
        (averageEncoderTotalMs! < frameBudgetMs * 0.75 &&
            encoderSlowFrameCount <= max(1, encoderSampleCount ~/ 10));
    return (captureCallSlow ||
            nativeFpsSlow ||
            p95GapSlow ||
            maxGapSlow ||
            hasStaleFrames) &&
        encoderLooksFast;
  }

  Map<String, Object?> toJson() {
    return {
      'captureBackendMode': captureBackendMode,
      'observedCapturer': observedCapturer,
      'observedCapturerId': observedCapturerId,
      'dirtyRegionMode': dirtyRegionMode,
      'windowGdiCaptureMode': windowGdiCaptureMode,
      'sourceType': sourceType,
      'nativeSourceWidth': nativeSourceWidth,
      'nativeSourceHeight': nativeSourceHeight,
      'requestedMaxWidth': requestedMaxWidth,
      'requestedMaxHeight': requestedMaxHeight,
      'nativeWindowRectWidth': nativeWindowRectWidth,
      'nativeWindowRectHeight': nativeWindowRectHeight,
      'contentWidth': contentWidth,
      'contentHeight': contentHeight,
      'preEncodeWidth': preEncodeWidth,
      'preEncodeHeight': preEncodeHeight,
      'canvas': canvas,
      'cropRegion': cropRegion,
      'averageNativeFps': averageNativeFps,
      'averageSubmittedFps': averageSubmittedFps,
      'targetNativeFps': targetNativeFps,
      'averageCaptureCallMs': averageCaptureCallMs,
      'maxCaptureCallMs': maxCaptureCallMs,
      'averageSourceCaptureMs': averageSourceCaptureMs,
      'maxSourceCaptureMs': maxSourceCaptureMs,
      'sourceCaptureSampleCount': sourceCaptureSampleCount,
      'wgcCaptureCalls': wgcCaptureCalls,
      'wgcCaptureSuccessCount': wgcCaptureSuccessCount,
      'wgcSourceNotCapturableCount': wgcSourceNotCapturableCount,
      'wgcEnsureFrameCalls': wgcEnsureFrameCalls,
      'wgcEnsureSleepCount': wgcEnsureSleepCount,
      'wgcProcessFrameCalls': wgcProcessFrameCalls,
      'wgcProcessFrameSuccessCount': wgcProcessFrameSuccessCount,
      'wgcFramePoolEmptyCount': wgcFramePoolEmptyCount,
      'wgcFramePoolReuseCount': wgcFramePoolReuseCount,
      'wgcCaptureFrameNullCount': wgcCaptureFrameNullCount,
      'wgcMappedTextureCreateCount': wgcMappedTextureCreateCount,
      'wgcResizeCount': wgcResizeCount,
      'wgcFramePoolRecreateCount': wgcFramePoolRecreateCount,
      'averageWgcGetFrameMs': averageWgcGetFrameMs,
      'maxWgcGetFrameMs': maxWgcGetFrameMs,
      'averageWgcEnsureFrameMs': averageWgcEnsureFrameMs,
      'maxWgcEnsureFrameMs': maxWgcEnsureFrameMs,
      'averageWgcProcessFrameMs': averageWgcProcessFrameMs,
      'maxWgcProcessFrameMs': maxWgcProcessFrameMs,
      'averageWgcTryGetFrameMs': averageWgcTryGetFrameMs,
      'maxWgcTryGetFrameMs': maxWgcTryGetFrameMs,
      'averageWgcSurfaceMs': averageWgcSurfaceMs,
      'maxWgcSurfaceMs': maxWgcSurfaceMs,
      'averageWgcTextureMs': averageWgcTextureMs,
      'maxWgcTextureMs': maxWgcTextureMs,
      'averageWgcContentSizeMs': averageWgcContentSizeMs,
      'maxWgcContentSizeMs': maxWgcContentSizeMs,
      'averageWgcCopyTextureMs': averageWgcCopyTextureMs,
      'maxWgcCopyTextureMs': maxWgcCopyTextureMs,
      'averageWgcMapTextureMs': averageWgcMapTextureMs,
      'maxWgcMapTextureMs': maxWgcMapTextureMs,
      'averageWgcCopyRowsMs': averageWgcCopyRowsMs,
      'maxWgcCopyRowsMs': maxWgcCopyRowsMs,
      'averageWgcMonitorScaleMs': averageWgcMonitorScaleMs,
      'maxWgcMonitorScaleMs': maxWgcMonitorScaleMs,
      'averageWgcZeroHertzMs': averageWgcZeroHertzMs,
      'maxWgcZeroHertzMs': maxWgcZeroHertzMs,
      'dominantWgcFrameStage': dominantWgcFrameStageLabel,
      'wgcFrameSummary': wgcFrameSummaryLabel,
      'reportWgcFrameSummary': reportWgcFrameSummaryLabel,
      'gdiCaptureCalls': gdiCaptureCalls,
      'gdiCaptureSuccessCount': gdiCaptureSuccessCount,
      'gdiTemporaryErrorCount': gdiTemporaryErrorCount,
      'gdiPermanentErrorCount': gdiPermanentErrorCount,
      'gdiHiddenOrMinimizedCount': gdiHiddenOrMinimizedCount,
      'gdiRectFailCount': gdiRectFailCount,
      'gdiDcFailCount': gdiDcFailCount,
      'gdiFrameCreateFailCount': gdiFrameCreateFailCount,
      'gdiPrintFullCallCount': gdiPrintFullCallCount,
      'gdiPrintFullSuccessCount': gdiPrintFullSuccessCount,
      'gdiPrintFallbackCallCount': gdiPrintFallbackCallCount,
      'gdiPrintFallbackSuccessCount': gdiPrintFallbackSuccessCount,
      'gdiBitBltCallCount': gdiBitBltCallCount,
      'gdiBitBltSuccessCount': gdiBitBltSuccessCount,
      'gdiFinalPrintFullCount': gdiFinalPrintFullCount,
      'gdiFinalPrintFallbackCount': gdiFinalPrintFallbackCount,
      'gdiFinalBitBltCount': gdiFinalBitBltCount,
      'gdiFinalNoneCount': gdiFinalNoneCount,
      'gdiFinalFrameCount': gdiFinalFrameCount,
      'gdiFinalMethodMix': gdiFinalMethodMixLabel,
      'gdiBlackFrameCount': gdiBlackFrameCount,
      'gdiBlackFrameRatio': gdiBlackFrameRatio,
      'gdiLowVarianceFrameCount': gdiLowVarianceFrameCount,
      'gdiLowVarianceFrameRatio': gdiLowVarianceFrameRatio,
      'gdiOutputProbablyInvalid': gdiOutputProbablyInvalid,
      'gdiOutputValidity': gdiOutputValidityLabel,
      'gdiOwnedWindowFrameCount': gdiOwnedWindowFrameCount,
      'gdiOwnedWindowCaptureCallCount': gdiOwnedWindowCaptureCallCount,
      'gdiOwnedWindowCaptureSuccessCount': gdiOwnedWindowCaptureSuccessCount,
      'gdiOriginalWidth': gdiOriginalWidth,
      'gdiOriginalHeight': gdiOriginalHeight,
      'gdiCroppedWidth': gdiCroppedWidth,
      'gdiCroppedHeight': gdiCroppedHeight,
      'gdiFrameWidth': gdiFrameWidth,
      'gdiFrameHeight': gdiFrameHeight,
      'averageGdiTotalMs': averageGdiTotalMs,
      'maxGdiTotalMs': maxGdiTotalMs,
      'averageGdiRectMs': averageGdiRectMs,
      'maxGdiRectMs': maxGdiRectMs,
      'averageGdiVisibilityMs': averageGdiVisibilityMs,
      'maxGdiVisibilityMs': maxGdiVisibilityMs,
      'averageGdiGetDcMs': averageGdiGetDcMs,
      'maxGdiGetDcMs': maxGdiGetDcMs,
      'averageGdiGetDcSizeMs': averageGdiGetDcSizeMs,
      'maxGdiGetDcSizeMs': maxGdiGetDcSizeMs,
      'averageGdiCreateFrameMs': averageGdiCreateFrameMs,
      'maxGdiCreateFrameMs': maxGdiCreateFrameMs,
      'averageGdiMemDcMs': averageGdiMemDcMs,
      'maxGdiMemDcMs': maxGdiMemDcMs,
      'averageGdiPrintFullMs': averageGdiPrintFullMs,
      'maxGdiPrintFullMs': maxGdiPrintFullMs,
      'averageGdiPrintFallbackMs': averageGdiPrintFallbackMs,
      'maxGdiPrintFallbackMs': maxGdiPrintFallbackMs,
      'averageGdiBitBltMs': averageGdiBitBltMs,
      'maxGdiBitBltMs': maxGdiBitBltMs,
      'averageGdiCleanupMs': averageGdiCleanupMs,
      'maxGdiCleanupMs': maxGdiCleanupMs,
      'averageGdiCropMs': averageGdiCropMs,
      'maxGdiCropMs': maxGdiCropMs,
      'averageGdiOwnedEnumMs': averageGdiOwnedEnumMs,
      'maxGdiOwnedEnumMs': maxGdiOwnedEnumMs,
      'averageGdiOwnedCaptureMs': averageGdiOwnedCaptureMs,
      'maxGdiOwnedCaptureMs': maxGdiOwnedCaptureMs,
      'averageGdiOwnedCompositeMs': averageGdiOwnedCompositeMs,
      'maxGdiOwnedCompositeMs': maxGdiOwnedCompositeMs,
      'dominantGdiFrameStage': dominantGdiFrameStageLabel,
      'gdiFrameSummary': gdiFrameSummaryLabel,
      'reportGdiFrameSummary': reportGdiFrameSummaryLabel,
      'dominantCaptureDelayStage': dominantCaptureDelayStageLabel,
      'capturePhaseSummary': capturePhaseSummaryLabel,
      'averageCallbackEntryDelayMs': averageCallbackEntryDelayMs,
      'maxCallbackEntryDelayMs': maxCallbackEntryDelayMs,
      'averageCaptureResultCallbackMs': averageCaptureResultCallbackMs,
      'maxCaptureResultCallbackMs': maxCaptureResultCallbackMs,
      'averageCaptureAcquireWaitMs': averageCaptureAcquireWaitMs,
      'maxCaptureAcquireWaitMs': maxCaptureAcquireWaitMs,
      'averagePostCallbackWaitMs': averagePostCallbackWaitMs,
      'maxPostCallbackWaitMs': maxPostCallbackWaitMs,
      'averageUnaccountedWaitMs': averageUnaccountedWaitMs,
      'maxUnaccountedWaitMs': maxUnaccountedWaitMs,
      'captureResultCallbackCount': captureResultCallbackCount,
      'maxFrameIntervalMs': maxFrameIntervalMs,
      'p95FrameIntervalMs': p95FrameIntervalMs,
      'captureWaitTimeoutCount': captureWaitTimeoutCount,
      'capturePermanentErrorCount': capturePermanentErrorCount,
      'duplicatedFrameCount': duplicatedFrameCount,
      'staleFrameReuseCount': staleFrameReuseCount,
      'averageFrameConvertMs': averageFrameConvertMs,
      'averageFrameScaleMs': averageFrameScaleMs,
      'averageFrameOnFrameMs': averageFrameOnFrameMs,
      'averageFrameCallbackMs': averageFrameCallbackMs,
      'maxFrameCallbackMs': maxFrameCallbackMs,
      'updatedRegionEmptyCount': updatedRegionEmptyCount,
      'updatedRegionNonEmptyCount': updatedRegionNonEmptyCount,
      'updatedRegionRectCount': updatedRegionRectCount,
      'updatedRegionMaxRectCount': updatedRegionMaxRectCount,
      'averageUpdatedRegionAreaRatio': averageUpdatedRegionAreaRatio,
      'maxUpdatedRegionAreaRatio': maxUpdatedRegionAreaRatio,
      'averageUpdatedRegionAnalysisMs': averageUpdatedRegionAnalysisMs,
      'maxUpdatedRegionAnalysisMs': maxUpdatedRegionAnalysisMs,
      'updatedRegionFullFrameCount': updatedRegionFullFrameCount,
      'updatedRegionTinyFrameCount': updatedRegionTinyFrameCount,
      'latestFramePacerEnabled': latestFramePacerEnabled,
      'averagePacerSubmittedFps': averagePacerSubmittedFps,
      'averagePacerUniqueFps': averagePacerUniqueFps,
      'p95PacerIntervalMs': p95PacerIntervalMs,
      'maxPacerIntervalMs': maxPacerIntervalMs,
      'averagePacerFrameAgeMs': averagePacerFrameAgeMs,
      'maxPacerFrameAgeMs': maxPacerFrameAgeMs,
      'averagePacerOnFrameMs': averagePacerOnFrameMs,
      'maxPacerOnFrameMs': maxPacerOnFrameMs,
      'pacerDuplicateSubmitCount': pacerDuplicateSubmitCount,
      'pacerOverwrittenFrameCount': pacerOverwrittenFrameCount,
      'pacerSkippedTickCount': pacerSkippedTickCount,
      'gameCaptureSourceWidth': gameCaptureSourceWidth,
      'gameCaptureSourceHeight': gameCaptureSourceHeight,
      'gameCaptureOutputWidth': gameCaptureOutputWidth,
      'gameCaptureOutputHeight': gameCaptureOutputHeight,
      'gameCaptureFormat': gameCaptureFormat,
      'gameCaptureBackendContractVersion': gameCaptureBackendContractVersion,
      'gameCaptureSourceMode': gameCaptureSourceMode,
      'gameCaptureSourceApi': gameCaptureSourceApi,
      'gameCaptureSourceApiId': gameCaptureSourceApiId,
      'gameCaptureSourceFormat': gameCaptureSourceFormat,
      'gameCaptureSourceFormatId': gameCaptureSourceFormatId,
      'gameCaptureColorSpace': gameCaptureColorSpace,
      'gameCaptureSyncKind': gameCaptureSyncKind,
      'gameCaptureReadyState': gameCaptureReadyState,
      'gameCaptureFailureReason': gameCaptureFailureReason,
      'gameCaptureConsumerAdapterLuid': gameCaptureConsumerAdapterLuid,
      'gameCaptureConsumerAdapterVendorId': gameCaptureConsumerAdapterVendorId,
      'gameCaptureConsumerAdapterDeviceId': gameCaptureConsumerAdapterDeviceId,
      'gameCaptureSourceAdapterLuid': gameCaptureSourceAdapterLuid,
      'gameCaptureCrossAdapterSuspected': gameCaptureCrossAdapterSuspected,
      'averageGameCaptureFps': averageGameCaptureFps,
      'gameCaptureSubmittedFrames': gameCaptureSubmittedFrames,
      'gameCaptureRepeatedFrames': gameCaptureRepeatedFrames,
      'gameCaptureDuplicateSkippedFrames': gameCaptureDuplicateSkippedFrames,
      'gameCaptureDeliveryQueuedFrames': gameCaptureDeliveryQueuedFrames,
      'gameCaptureDeliverySubmittedFrames': gameCaptureDeliverySubmittedFrames,
      'gameCaptureDeliveryOverwrittenFrames':
          gameCaptureDeliveryOverwrittenFrames,
      'gameCaptureDeliveryPacerResyncs': gameCaptureDeliveryPacerResyncs,
      'gameCaptureDeliveryPacerLagMaxMs': gameCaptureDeliveryPacerLagMaxMs,
      'gameCaptureDeliveryRepeatNoQueuedFrames':
          gameCaptureDeliveryRepeatNoQueuedFrames,
      'gameCaptureDeliverySkipNoQueuedFrames':
          gameCaptureDeliverySkipNoQueuedFrames,
      'gameCaptureDeliveryFreshWakeAfterSkipFrames':
          gameCaptureDeliveryFreshWakeAfterSkipFrames,
      'gameCaptureDeliveryFreshImmediateFrames':
          gameCaptureDeliveryFreshImmediateFrames,
      'gameCaptureDeliveryRepeatPolicy': gameCaptureDeliveryRepeatPolicy,
      'gameCaptureDeliveryQueueDepth': gameCaptureDeliveryQueueDepth,
      'averageGameCaptureDeliveryRepeatSourceAgeMs':
          averageGameCaptureDeliveryRepeatSourceAgeMs,
      'maxGameCaptureDeliveryRepeatSourceAgeMs':
          maxGameCaptureDeliveryRepeatSourceAgeMs,
      'gameCaptureDeliveryRepeatSourceAgeSamples':
          gameCaptureDeliveryRepeatSourceAgeSamples,
      'averageGameCaptureDeliveryOnFrameMs':
          averageGameCaptureDeliveryOnFrameMs,
      'maxGameCaptureDeliveryOnFrameMs': maxGameCaptureDeliveryOnFrameMs,
      'averageGameCaptureDeliverySubmitPrepMs':
          averageGameCaptureDeliverySubmitPrepMs,
      'maxGameCaptureDeliverySubmitPrepMs': maxGameCaptureDeliverySubmitPrepMs,
      'gameCaptureDeliverySubmitPrepSamples':
          gameCaptureDeliverySubmitPrepSamples,
      'averageGameCaptureDeliveryOnFrameCallMs':
          averageGameCaptureDeliveryOnFrameCallMs,
      'maxGameCaptureDeliveryOnFrameCallMs':
          maxGameCaptureDeliveryOnFrameCallMs,
      'gameCaptureDeliveryOnFrameCallSamples':
          gameCaptureDeliveryOnFrameCallSamples,
      'averageGameCaptureDeliveryPostOnFrameMs':
          averageGameCaptureDeliveryPostOnFrameMs,
      'maxGameCaptureDeliveryPostOnFrameMs':
          maxGameCaptureDeliveryPostOnFrameMs,
      'gameCaptureDeliveryPostOnFrameSamples':
          gameCaptureDeliveryPostOnFrameSamples,
      'averageGameCaptureNativeBufferReleaseMs':
          averageGameCaptureNativeBufferReleaseMs,
      'maxGameCaptureNativeBufferReleaseMs':
          maxGameCaptureNativeBufferReleaseMs,
      'gameCaptureNativeBufferReleaseSamples':
          gameCaptureNativeBufferReleaseSamples,
      'averageGameCaptureReadyToQueueMs': averageGameCaptureReadyToQueueMs,
      'maxGameCaptureReadyToQueueMs': maxGameCaptureReadyToQueueMs,
      'gameCaptureReadyToQueueSamples': gameCaptureReadyToQueueSamples,
      'averageGameCaptureDeliveryQueueWaitMs':
          averageGameCaptureDeliveryQueueWaitMs,
      'maxGameCaptureDeliveryQueueWaitMs': maxGameCaptureDeliveryQueueWaitMs,
      'gameCaptureDeliveryQueueWaitSamples':
          gameCaptureDeliveryQueueWaitSamples,
      'averageGameCaptureDeliveryOverwriteAgeMs':
          averageGameCaptureDeliveryOverwriteAgeMs,
      'maxGameCaptureDeliveryOverwriteAgeMs':
          maxGameCaptureDeliveryOverwriteAgeMs,
      'gameCaptureDeliveryOverwriteAgeSamples':
          gameCaptureDeliveryOverwriteAgeSamples,
      'gameCaptureDeliveryOverwrittenFreshFrames':
          gameCaptureDeliveryOverwrittenFreshFrames,
      'averageGameCaptureReadyToSubmitMs': averageGameCaptureReadyToSubmitMs,
      'maxGameCaptureReadyToSubmitMs': maxGameCaptureReadyToSubmitMs,
      'gameCaptureReadyToSubmitSamples': gameCaptureReadyToSubmitSamples,
      'averageGameCaptureSourceToSubmitMs': averageGameCaptureSourceToSubmitMs,
      'maxGameCaptureSourceToSubmitMs': maxGameCaptureSourceToSubmitMs,
      'gameCaptureSourceToSubmitSamples': gameCaptureSourceToSubmitSamples,
      'averageGameCaptureSourceToReadbackReadyMs':
          averageGameCaptureSourceToReadbackReadyMs,
      'maxGameCaptureSourceToReadbackReadyMs':
          maxGameCaptureSourceToReadbackReadyMs,
      'gameCaptureSourceToReadbackReadySamples':
          gameCaptureSourceToReadbackReadySamples,
      'averageGameCaptureReadbackQueueToMapMs':
          averageGameCaptureReadbackQueueToMapMs,
      'maxGameCaptureReadbackQueueToMapMs': maxGameCaptureReadbackQueueToMapMs,
      'gameCaptureReadbackQueueToMapSamples':
          gameCaptureReadbackQueueToMapSamples,
      'averageGameCaptureMapToI420Ms': averageGameCaptureMapToI420Ms,
      'maxGameCaptureMapToI420Ms': maxGameCaptureMapToI420Ms,
      'gameCaptureMapToI420Samples': gameCaptureMapToI420Samples,
      'averageGameCaptureSourceToI420ReadyMs':
          averageGameCaptureSourceToI420ReadyMs,
      'maxGameCaptureSourceToI420ReadyMs': maxGameCaptureSourceToI420ReadyMs,
      'gameCaptureSourceToI420ReadySamples':
          gameCaptureSourceToI420ReadySamples,
      'averageGameCaptureSourceToQueueMs': averageGameCaptureSourceToQueueMs,
      'maxGameCaptureSourceToQueueMs': maxGameCaptureSourceToQueueMs,
      'gameCaptureSourceToQueueSamples': gameCaptureSourceToQueueSamples,
      'averageGameCaptureSourceDuplicateSkipAgeMs':
          averageGameCaptureSourceDuplicateSkipAgeMs,
      'maxGameCaptureSourceDuplicateSkipAgeMs':
          maxGameCaptureSourceDuplicateSkipAgeMs,
      'gameCaptureSourceDuplicateSkipAgeSamples':
          gameCaptureSourceDuplicateSkipAgeSamples,
      'gameCaptureCopiedFrames': gameCaptureCopiedFrames,
      'gameCaptureDroppedFrames': gameCaptureDroppedFrames,
      'gameCaptureOverwrittenFrames': gameCaptureOverwrittenFrames,
      'gameCaptureGpuScaledFrames': gameCaptureGpuScaledFrames,
      'gameCaptureGpuScaleFailures': gameCaptureGpuScaleFailures,
      'gameCaptureCpuFallbackFrames': gameCaptureCpuFallbackFrames,
      'gameCaptureNativeNv12SubmittedFrames':
          gameCaptureNativeNv12SubmittedFrames,
      'gameCaptureNativeNv12QueuedFrames': gameCaptureNativeNv12QueuedFrames,
      'gameCaptureNativeNv12ReadyFrames': gameCaptureNativeNv12ReadyFrames,
      'gameCaptureNativeNv12NotReadyPolls': gameCaptureNativeNv12NotReadyPolls,
      'gameCaptureNativeNv12ReadyPolicy': gameCaptureNativeNv12ReadyPolicy,
      'gameCaptureNativeNv12FenceAvailable':
          gameCaptureNativeNv12FenceAvailable,
      'gameCaptureNativeNv12PendingPollMs': gameCaptureNativeNv12PendingPollMs,
      'gameCaptureNativeNv12MaxPendingSlots':
          gameCaptureNativeNv12MaxPendingSlots,
      'gameCaptureNativeNv12ReadyDrainDepth':
          gameCaptureNativeNv12ReadyDrainDepth,
      'gameCaptureNativeNv12FrameOwnership':
          gameCaptureNativeNv12FrameOwnership,
      'gameCaptureNativeNv12FenceSignaledFrames':
          gameCaptureNativeNv12FenceSignaledFrames,
      'gameCaptureNativeNv12FenceReadyFrames':
          gameCaptureNativeNv12FenceReadyFrames,
      'gameCaptureNativeNv12FenceSignalFailures':
          gameCaptureNativeNv12FenceSignalFailures,
      'gameCaptureNativeNv12OwnedCopies': gameCaptureNativeNv12OwnedCopies,
      'averageGameCaptureNativeNv12OwnedCopyMs':
          averageGameCaptureNativeNv12OwnedCopyMs,
      'maxGameCaptureNativeNv12OwnedCopyMs':
          maxGameCaptureNativeNv12OwnedCopyMs,
      'gameCaptureNativeNv12OwnedCopySamples':
          gameCaptureNativeNv12OwnedCopySamples,
      'gameCaptureNativeNv12OverwrittenFrames':
          gameCaptureNativeNv12OverwrittenFrames,
      'averageGameCaptureNativeNv12OverwriteAgeMs':
          averageGameCaptureNativeNv12OverwriteAgeMs,
      'maxGameCaptureNativeNv12OverwriteAgeMs':
          maxGameCaptureNativeNv12OverwriteAgeMs,
      'gameCaptureNativeNv12OverwriteAgeSamples':
          gameCaptureNativeNv12OverwriteAgeSamples,
      'gameCaptureNativeNv12OverwrittenFreshFrames':
          gameCaptureNativeNv12OverwrittenFreshFrames,
      'gameCaptureNativeNv12ReadyDroppedFrames':
          gameCaptureNativeNv12ReadyDroppedFrames,
      'averageGameCaptureNativeNv12ReadyDropAgeMs':
          averageGameCaptureNativeNv12ReadyDropAgeMs,
      'maxGameCaptureNativeNv12ReadyDropAgeMs':
          maxGameCaptureNativeNv12ReadyDropAgeMs,
      'gameCaptureNativeNv12ReadyDropAgeSamples':
          gameCaptureNativeNv12ReadyDropAgeSamples,
      'gameCaptureNativeNv12ReadyDroppedFreshFrames':
          gameCaptureNativeNv12ReadyDroppedFreshFrames,
      'gameCaptureNativeNv12Failures': gameCaptureNativeNv12Failures,
      'averageGameCaptureNativeNv12ConvertMs':
          averageGameCaptureNativeNv12ConvertMs,
      'maxGameCaptureNativeNv12ConvertMs': maxGameCaptureNativeNv12ConvertMs,
      'gameCaptureNativeNv12ConvertSamples':
          gameCaptureNativeNv12ConvertSamples,
      'averageGameCaptureNativeNv12BgraScaleDrawMs':
          averageGameCaptureNativeNv12BgraScaleDrawMs,
      'maxGameCaptureNativeNv12BgraScaleDrawMs':
          maxGameCaptureNativeNv12BgraScaleDrawMs,
      'gameCaptureNativeNv12BgraScaleDrawSamples':
          gameCaptureNativeNv12BgraScaleDrawSamples,
      'averageGameCaptureNativeNv12VideoProcessorBltSubmitMs':
          averageGameCaptureNativeNv12VideoProcessorBltSubmitMs,
      'maxGameCaptureNativeNv12VideoProcessorBltSubmitMs':
          maxGameCaptureNativeNv12VideoProcessorBltSubmitMs,
      'gameCaptureNativeNv12VideoProcessorBltSubmitSamples':
          gameCaptureNativeNv12VideoProcessorBltSubmitSamples,
      'averageGameCaptureNativeNv12VideoProcessorBltToReadyMs':
          averageGameCaptureNativeNv12VideoProcessorBltToReadyMs,
      'maxGameCaptureNativeNv12VideoProcessorBltToReadyMs':
          maxGameCaptureNativeNv12VideoProcessorBltToReadyMs,
      'gameCaptureNativeNv12VideoProcessorBltToReadySamples':
          gameCaptureNativeNv12VideoProcessorBltToReadySamples,
      'averageGameCaptureNativeNv12BufferCreateMs':
          averageGameCaptureNativeNv12BufferCreateMs,
      'maxGameCaptureNativeNv12BufferCreateMs':
          maxGameCaptureNativeNv12BufferCreateMs,
      'gameCaptureNativeNv12BufferCreateSamples':
          gameCaptureNativeNv12BufferCreateSamples,
      'averageGameCaptureNativeNv12FrameReadyToQueueMs':
          averageGameCaptureNativeNv12FrameReadyToQueueMs,
      'maxGameCaptureNativeNv12FrameReadyToQueueMs':
          maxGameCaptureNativeNv12FrameReadyToQueueMs,
      'gameCaptureNativeNv12FrameReadyToQueueSamples':
          gameCaptureNativeNv12FrameReadyToQueueSamples,
      'averageGameCaptureNativeNv12ConversionStartAgeMs':
          averageGameCaptureNativeNv12ConversionStartAgeMs,
      'maxGameCaptureNativeNv12ConversionStartAgeMs':
          maxGameCaptureNativeNv12ConversionStartAgeMs,
      'gameCaptureNativeNv12ConversionStartAgeSamples':
          gameCaptureNativeNv12ConversionStartAgeSamples,
      'gameCaptureNativeNv12StaleBeforeQueueFrames':
          gameCaptureNativeNv12StaleBeforeQueueFrames,
      'gameCaptureNativeNv12HandoffDisabledReason':
          gameCaptureNativeNv12HandoffDisabledReason,
      'gameCaptureGpuHandoffUnproven': gameCaptureGpuHandoffUnproven,
      'gameCaptureReadbackQueuedFrames': gameCaptureReadbackQueuedFrames,
      'gameCaptureReadbackReadyFrames': gameCaptureReadbackReadyFrames,
      'gameCaptureReadbackNotReadyFrames': gameCaptureReadbackNotReadyFrames,
      'gameCaptureReadbackOverwrittenFrames':
          gameCaptureReadbackOverwrittenFrames,
      'gameCaptureReadbackStaleDroppedFrames':
          gameCaptureReadbackStaleDroppedFrames,
      'gameCaptureReadbackLatencyDroppedFrames':
          gameCaptureReadbackLatencyDroppedFrames,
      'gameCaptureReadbackMapAttempts': gameCaptureReadbackMapAttempts,
      'gameCaptureSourceFrameIndex': gameCaptureSourceFrameIndex,
      'gameCaptureLastSubmittedSourceFrameIndex':
          gameCaptureLastSubmittedSourceFrameIndex,
      'gameCaptureSourceFrameRegressions': gameCaptureSourceFrameRegressions,
      'gameCaptureSourceFrameDuplicates': gameCaptureSourceFrameDuplicates,
      'gameCaptureSourceFrameGaps': gameCaptureSourceFrameGaps,
      'gameCaptureSharedSlotMismatches': gameCaptureSharedSlotMismatches,
      'gameCaptureTimestampMode': gameCaptureTimestampMode,
      'gameCaptureTimestampSourceQpcFrames':
          gameCaptureTimestampSourceQpcFrames,
      'gameCaptureTimestampPacedFallbackFrames':
          gameCaptureTimestampPacedFallbackFrames,
      'gameCaptureTimestampRepeatedFrames': gameCaptureTimestampRepeatedFrames,
      'averageGameCaptureTimestampDeltaMs': averageGameCaptureTimestampDeltaMs,
      'maxGameCaptureTimestampDeltaMs': maxGameCaptureTimestampDeltaMs,
      'gameCaptureTimestampSamples': gameCaptureTimestampSamples,
      'gameCaptureTimestampAdjustments': gameCaptureTimestampAdjustments,
      'averageGameCaptureDeliveryWallDeltaMs':
          averageGameCaptureDeliveryWallDeltaMs,
      'maxGameCaptureDeliveryWallDeltaMs': maxGameCaptureDeliveryWallDeltaMs,
      'minGameCaptureDeliveryWallDeltaMs': minGameCaptureDeliveryWallDeltaMs,
      'gameCaptureDeliveryWallSamples': gameCaptureDeliveryWallSamples,
      'gameCaptureDeliveryWallOver2xFrames':
          gameCaptureDeliveryWallOver2xFrames,
      'gameCaptureDeliveryWallOver3xFrames':
          gameCaptureDeliveryWallOver3xFrames,
      'gameCaptureDeliveryWallUnderHalfFrames':
          gameCaptureDeliveryWallUnderHalfFrames,
      'averageGameCaptureSourceQpcDeltaMs': averageGameCaptureSourceQpcDeltaMs,
      'maxGameCaptureSourceQpcDeltaMs': maxGameCaptureSourceQpcDeltaMs,
      'gameCaptureSourceQpcSamples': gameCaptureSourceQpcSamples,
      'gameCaptureSourceQpcRegressions': gameCaptureSourceQpcRegressions,
      'averageGameCaptureCopyMs': averageGameCaptureCopyMs,
      'averageGameCaptureMapMs': averageGameCaptureMapMs,
      'averageGameCaptureConvertMs': averageGameCaptureConvertMs,
      'averageGameCaptureGpuScaleMs': averageGameCaptureGpuScaleMs,
      'averageGameCaptureReadbackLatencyMs':
          averageGameCaptureReadbackLatencyMs,
      'averageGameCaptureReadbackLatencyFrames':
          averageGameCaptureReadbackLatencyFrames,
      'gameCaptureMaxReadbackLatencyFrames':
          gameCaptureMaxReadbackLatencyFrames,
      'gameCaptureMapFailures': gameCaptureMapFailures,
      'gameCaptureConvertFailures': gameCaptureConvertFailures,
      'gameCaptureProofFrames': gameCaptureProofFrames,
      'gameCaptureVisibleProofFrames': gameCaptureVisibleProofFrames,
      'gameCaptureProofVisible': gameCaptureProofVisible,
      'gameCaptureProofPath': gameCaptureProofPath,
      'gameCaptureProofMinLuma': gameCaptureProofMinLuma,
      'gameCaptureProofMaxLuma': gameCaptureProofMaxLuma,
      'gameCaptureProofNonzeroSamples': gameCaptureProofNonzeroSamples,
      'gameCaptureProofSamples': gameCaptureProofSamples,
      'gameCaptureI420ProofFrames': gameCaptureI420ProofFrames,
      'gameCaptureVisibleI420ProofFrames': gameCaptureVisibleI420ProofFrames,
      'gameCaptureInitialBlackSkippedFrames':
          gameCaptureInitialBlackSkippedFrames,
      'gameCaptureVisibleSourceSeen': gameCaptureVisibleSourceSeen,
      'gameCaptureI420ProofVisible': gameCaptureI420ProofVisible,
      'gameCaptureI420ProofPath': gameCaptureI420ProofPath,
      'gameCaptureI420ProofMinLuma': gameCaptureI420ProofMinLuma,
      'gameCaptureI420ProofMaxLuma': gameCaptureI420ProofMaxLuma,
      'gameCaptureI420ProofNonzeroSamples': gameCaptureI420ProofNonzeroSamples,
      'gameCaptureI420ProofSamples': gameCaptureI420ProofSamples,
      'gameCaptureFrameSummary': gameCaptureFrameSummaryLabel,
      'averageEncoderTotalMs': averageEncoderTotalMs,
      'maxEncoderTotalMs': maxEncoderTotalMs,
      'encoderSlowFrameCount': encoderSlowFrameCount,
      'encoderSampleCount': encoderSampleCount,
      'encoderInputPaths': encoderInputPaths,
      'encoderInputPathLabel': encoderInputPathLabel,
      'encoderNativeInputFrames': encoderNativeInputFrames,
      'encoderCpuI420InputFrames': encoderCpuI420InputFrames,
      'encoderNativeSampleFailures': encoderNativeSampleFailures,
      'encoderNativeSuspendedFrames': encoderNativeSuspendedFrames,
      'encoderNativeReadyFenceFrames': encoderNativeReadyFenceFrames,
      'encoderNativeReadyFenceTimeoutFrames':
          encoderNativeReadyFenceTimeoutFrames,
      'averageEncoderNativeReadyFenceWaitMs':
          averageEncoderNativeReadyFenceWaitMs,
      'maxEncoderNativeReadyFenceWaitMs': maxEncoderNativeReadyFenceWaitMs,
      'encoderNativeReadyFenceWaitSamples': encoderNativeReadyFenceWaitSamples,
      'encoderNativeSourceMode': encoderNativeSourceMode,
      'encoderNativeSourceFormat': encoderNativeSourceFormat,
      'encoderNativeSourceFrameIndex': encoderNativeSourceFrameIndex,
      'averageEncoderNativeSourceAgeMs': averageEncoderNativeSourceAgeMs,
      'maxEncoderNativeSourceAgeMs': maxEncoderNativeSourceAgeMs,
      'encoderNativeSourceAgeSamples': encoderNativeSourceAgeSamples,
      'averageEncoderNativeSourceAgeAtCreateMs':
          averageEncoderNativeSourceAgeAtCreateMs,
      'maxEncoderNativeSourceAgeAtCreateMs':
          maxEncoderNativeSourceAgeAtCreateMs,
      'averageEncoderNativeBufferAgeMs': averageEncoderNativeBufferAgeMs,
      'maxEncoderNativeBufferAgeMs': maxEncoderNativeBufferAgeMs,
      'encoderNativeBufferAgeSamples': encoderNativeBufferAgeSamples,
      'averageEncoderNativeSampleLifetimeMs':
          averageEncoderNativeSampleLifetimeMs,
      'maxEncoderNativeSampleLifetimeMs': maxEncoderNativeSampleLifetimeMs,
      'encoderNativeSampleLifetimeSamples': encoderNativeSampleLifetimeSamples,
      'encoderNativeAdapterLuid': encoderNativeAdapterLuid,
      'encoderNativeAdapterVendorId': encoderNativeAdapterVendorId,
      'encoderNativeAdapterDeviceId': encoderNativeAdapterDeviceId,
      'averageEncoderProcessInputMs': averageEncoderProcessInputMs,
      'maxEncoderProcessInputMs': maxEncoderProcessInputMs,
      'encoderProcessInputSamples': encoderProcessInputSamples,
      'averageEncoderProcessOutputMs': averageEncoderProcessOutputMs,
      'maxEncoderProcessOutputMs': maxEncoderProcessOutputMs,
      'encoderProcessOutputSamples': encoderProcessOutputSamples,
      'averageEncoderEncodedCallbackMs': averageEncoderEncodedCallbackMs,
      'maxEncoderEncodedCallbackMs': maxEncoderEncodedCallbackMs,
      'encoderEncodedCallbackSamples': encoderEncodedCallbackSamples,
      'averageEncoderEncodedCallbackQueueWaitMs':
          averageEncoderEncodedCallbackQueueWaitMs,
      'maxEncoderEncodedCallbackQueueWaitMs':
          maxEncoderEncodedCallbackQueueWaitMs,
      'encoderEncodedCallbackQueueWaitSamples':
          encoderEncodedCallbackQueueWaitSamples,
      'averageEncoderEncodedCallbackEnqueueMs':
          averageEncoderEncodedCallbackEnqueueMs,
      'maxEncoderEncodedCallbackEnqueueMs': maxEncoderEncodedCallbackEnqueueMs,
      'encoderEncodedCallbackEnqueueSamples':
          encoderEncodedCallbackEnqueueSamples,
      'encoderEncodedCallbackAsyncFrames': encoderEncodedCallbackAsyncFrames,
      'encoderMaxEncodedCallbackQueueDepth':
          encoderMaxEncodedCallbackQueueDepth,
      'encoderMaxEncodedCallbackDrops': encoderMaxEncodedCallbackDrops,
      'encoderMaxEncodedCallbackOutputs': encoderMaxEncodedCallbackOutputs,
      'encoderStages': encoderStages,
      'encoderStageLabel': encoderStageLabel,
      'nativeEncoderFenceWaitMissing': nativeEncoderFenceWaitMissing,
      'encoderOutputFrames': encoderOutputFrames,
      'encoderOutputBytes': encoderOutputBytes,
      'encoderMaxQueueDepth': encoderMaxQueueDepth,
      'encoderMaxRetainedSamples': encoderMaxRetainedSamples,
      'encoderMaxEncodedOutputs': encoderMaxEncodedOutputs,
      'nativeEncoderHandoffNoOutput': nativeEncoderHandoffNoOutput,
      'webrtcRawSenderBoundary': {
        'available': hasWebrtcRawSenderBoundaryDiagnostics,
        'sourceOnFrame': {
          'averageMs': averageWebrtcSourceOnFrameMs,
          'maxMs': maxWebrtcSourceOnFrameMs,
          'samples': webrtcSourceOnFrameSamples,
          'averageAdaptMs': averageWebrtcSourceAdaptMs,
          'maxAdaptMs': maxWebrtcSourceAdaptMs,
          'averageScaleMs': averageWebrtcSourceScaleMs,
          'maxScaleMs': maxWebrtcSourceScaleMs,
          'averageBroadcastMs': averageWebrtcSourceBroadcastMs,
          'maxBroadcastMs': maxWebrtcSourceBroadcastMs,
          'adapterDrops': webrtcSourceAdapterDrops,
          'scaledFrames': webrtcSourceScaledFrames,
        },
        'videoBroadcaster': {
          'averageMs': averageWebrtcVideoBroadcasterMs,
          'maxMs': maxWebrtcVideoBroadcasterMs,
          'samples': webrtcVideoBroadcasterSamples,
          'averageLockWaitMs': averageWebrtcVideoBroadcasterLockWaitMs,
          'maxLockWaitMs': maxWebrtcVideoBroadcasterLockWaitMs,
          'averageSinkDispatchMs': averageWebrtcVideoBroadcasterSinkDispatchMs,
          'maxSinkDispatchMs': maxWebrtcVideoBroadcasterSinkDispatchMs,
          'maxSingleSinkMs': maxWebrtcVideoBroadcasterSingleSinkMs,
          'slowSinkId': webrtcVideoBroadcasterSlowSinkId,
          'slowSinkMs': webrtcVideoBroadcasterSlowSinkMs,
          'slowSinkLabel': webrtcVideoBroadcasterSlowSinkLabel,
          'slowestSinkId': webrtcVideoBroadcasterSlowestSinkId,
          'slowestSinkMs': webrtcVideoBroadcasterSlowestSinkMs,
          'slowestSinkAverageMs': webrtcVideoBroadcasterSlowestSinkAverageMs,
          'slowestSinkFrames': webrtcVideoBroadcasterSlowestSinkFrames,
          'slowestSinkLabel': webrtcVideoBroadcasterSlowestSinkLabel,
          'sinkCount': webrtcVideoBroadcasterSinkCount,
          'maxSinkCount': webrtcVideoBroadcasterMaxSinkCount,
          'activeSinks': webrtcVideoBroadcasterActiveSinks,
          'inactiveSinks': webrtcVideoBroadcasterInactiveSinks,
          'requestedSinks': webrtcVideoBroadcasterRequestedSinks,
          'blackFrameSinks': webrtcVideoBroadcasterBlackFrameSinks,
          'rotationAppliedSinks': webrtcVideoBroadcasterRotationAppliedSinks,
          'inactiveNativeSinkBypassReported':
              webrtcVideoBroadcasterInactiveNativeSinkBypassReported,
          'inactiveNativeSinksBypassed':
              webrtcVideoBroadcasterInactiveNativeSinksBypassed,
          'inactiveNativeSinksBypassedLast':
              webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
          'sinkRoster': webrtcVideoBroadcasterSinkRoster,
          'blackSinks': webrtcVideoBroadcasterBlackSinks,
          'rotationDiscards': webrtcVideoBroadcasterRotationDiscards,
          'updateRectCleared': webrtcVideoBroadcasterUpdateRectCleared,
          'discardedFrames': webrtcVideoBroadcasterDiscardedFrames,
        },
        'videoStreamEncoder': {
          'averagePostToOnFrameMs': averageWebrtcVsePostToOnFrameMs,
          'maxPostToOnFrameMs': maxWebrtcVsePostToOnFrameMs,
          'averageOnFrameMs': averageWebrtcVseOnFrameMs,
          'maxOnFrameMs': maxWebrtcVseOnFrameMs,
          'onFrameSamples': webrtcVseOnFrameSamples,
          'queueOverloadDrops': webrtcVseQueueOverloadDrops,
          'encoderQueueDrops': webrtcVseEncoderQueueDrops,
          'cwndDrops': webrtcVseCwndDrops,
          'badTimestampDrops': webrtcVseBadTimestampDrops,
          'averageMaybeEncodeMs': averageWebrtcVseMaybeEncodeMs,
          'maxMaybeEncodeMs': maxWebrtcVseMaybeEncodeMs,
          'maybeEncodeSamples': webrtcVseMaybeEncodeSamples,
          'pendingReplacedDrops': webrtcVsePendingReplacedDrops,
          'sizeDrops': webrtcVseSizeDrops,
          'pausedDrops': webrtcVsePausedDrops,
          'mediaOptimizationDrops': webrtcVseMediaOptimizationDrops,
          'averageEncodeFrameMs': averageWebrtcVseEncodeFrameMs,
          'maxEncodeFrameMs': maxWebrtcVseEncodeFrameMs,
          'encodeFrameSamples': webrtcVseEncodeFrameSamples,
          'averageVideoEncoderEncodeMs': averageWebrtcVideoEncoderEncodeMs,
          'maxVideoEncoderEncodeMs': maxWebrtcVideoEncoderEncodeMs,
          'videoEncoderEncodeSamples': webrtcVideoEncoderEncodeSamples,
          'encodeFailures': webrtcVseEncodeFailures,
          'encodeSkippedBeforeEncoder': webrtcVseEncodeSkippedBeforeEncoder,
        },
        'label': webrtcRawSenderBoundaryLabel,
      },
      'captureCauseAttribution': captureCauseAttribution,
      'summary': summaryLabel,
    };
  }
}

class StreamTestFramePacingSummary {
  const StreamTestFramePacingSummary({
    this.nativeCapture = const StreamTestFramePacingStageSummary(
      stage: 'nativeCapture',
      evidence: 'none',
    ),
    this.capture = const StreamTestFramePacingStageSummary(
      stage: 'capture',
      evidence: 'none',
    ),
    this.preEncode = const StreamTestFramePacingStageSummary(
      stage: 'preEncode',
      evidence: 'none',
    ),
    this.encoded = const StreamTestFramePacingStageSummary(
      stage: 'encoded',
      evidence: 'none',
    ),
    this.sent = const StreamTestFramePacingStageSummary(
      stage: 'sent',
      evidence: 'none',
    ),
    this.received = const StreamTestFramePacingStageSummary(
      stage: 'received',
      evidence: 'none',
    ),
    this.decoded = const StreamTestFramePacingStageSummary(
      stage: 'decoded',
      evidence: 'none',
    ),
    this.rendered = const StreamTestFramePacingStageSummary(
      stage: 'rendered',
      evidence: 'none',
    ),
  });

  factory StreamTestFramePacingSummary.fromSamples(
    List<StreamTestSample> samples, {
    StreamTestNativeDiagnostics nativeDiagnostics =
        const StreamTestNativeDiagnostics(),
  }) {
    return StreamTestFramePacingSummary(
      nativeCapture:
          StreamTestFramePacingStageSummary.fromNative(nativeDiagnostics),
      capture: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'capture',
        evidence: 'sampled framesCaptured counter',
        samples: _counterSamples(
          samples,
          _bestSenderTrack,
          (track) => track.framesCaptured,
        ),
      ),
      preEncode: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'preEncode',
        evidence: 'sampled framesCaptured counter with pre-encode dimensions',
        samples: _counterSamples(
          samples,
          _bestSenderTrack,
          (track) => track.framesCaptured,
          include: (track) =>
              (track.preEncodeWidth ?? 0) > 0 &&
              (track.preEncodeHeight ?? 0) > 0,
        ),
      ),
      encoded: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'encoded',
        evidence: 'sampled framesEncoded counter',
        samples: _counterSamples(
          samples,
          _bestSenderTrack,
          (track) => track.framesEncoded,
        ),
      ),
      sent: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'sent',
        evidence: 'sampled framesSent counter',
        samples: _counterSamples(
          samples,
          _bestSenderTrack,
          (track) => track.framesSent,
        ),
      ),
      received: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'received',
        evidence: 'sampled framesReceived counter',
        samples: _counterSamples(
          samples,
          _bestReceiverTrack,
          (track) => track.framesReceived,
        ),
      ),
      decoded: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'decoded',
        evidence: 'sampled framesDecoded counter',
        samples: _counterSamples(
          samples,
          _bestReceiverTrack,
          (track) => track.framesDecoded,
        ),
      ),
      rendered: StreamTestFramePacingStageSummary.fromCounterSamples(
        stage: 'rendered',
        evidence: 'sampled framesRendered counter',
        samples: _counterSamples(
          samples,
          _bestReceiverTrack,
          (track) => track.framesRendered,
        ),
      ),
    );
  }

  final StreamTestFramePacingStageSummary nativeCapture;
  final StreamTestFramePacingStageSummary capture;
  final StreamTestFramePacingStageSummary preEncode;
  final StreamTestFramePacingStageSummary encoded;
  final StreamTestFramePacingStageSummary sent;
  final StreamTestFramePacingStageSummary received;
  final StreamTestFramePacingStageSummary decoded;
  final StreamTestFramePacingStageSummary rendered;

  List<StreamTestFramePacingStageSummary> get stages => [
        nativeCapture,
        capture,
        preEncode,
        encoded,
        sent,
        received,
        decoded,
        rendered,
      ];

  bool get hasEvidence => stages.any((stage) => stage.hasEvidence);

  String get compactLabel {
    final labels = <String>[];
    for (final stage in stages) {
      if (stage.hasEvidence) {
        labels.add('${stage.stage}=${stage.compactLabel}');
      }
    }
    return labels.isEmpty ? 'unknown' : labels.join(' ');
  }

  Map<String, Object?> toJson() {
    return {
      'nativeCapture': nativeCapture.toJson(),
      'capture': capture.toJson(),
      'preEncode': preEncode.toJson(),
      'encoded': encoded.toJson(),
      'sent': sent.toJson(),
      'received': received.toJson(),
      'decoded': decoded.toJson(),
      'rendered': rendered.toJson(),
    };
  }
}

class StreamTestFramePacingStageSummary {
  const StreamTestFramePacingStageSummary({
    required this.stage,
    required this.evidence,
    this.sampleCount = 0,
    this.averageFps,
    this.minimumFps,
    this.p50IntervalMs,
    this.p95IntervalMs,
    this.maxIntervalMs,
    this.largestFrameDelta,
    this.lastFrameCount,
    this.duplicatedFrameCount = 0,
    this.staleFrameReuseCount = 0,
    this.waitTimeoutCount = 0,
    this.permanentErrorCount = 0,
  });

  factory StreamTestFramePacingStageSummary.fromNative(
    StreamTestNativeDiagnostics diagnostics,
  ) {
    final hasMarkerEvidence = diagnostics.p95FrameIntervalMs != null ||
        diagnostics.maxFrameIntervalMs != null ||
        diagnostics.p95PacerIntervalMs != null ||
        diagnostics.maxPacerIntervalMs != null ||
        diagnostics.averageSubmittedFps != null ||
        diagnostics.averageNativeFps != null ||
        diagnostics.duplicatedFrameCount > 0 ||
        diagnostics.staleFrameReuseCount > 0 ||
        diagnostics.captureWaitTimeoutCount > 0 ||
        diagnostics.capturePermanentErrorCount > 0;
    return StreamTestFramePacingStageSummary(
      stage: 'nativeCapture',
      evidence:
          hasMarkerEvidence ? 'native desktop capture cadence marker' : 'none',
      sampleCount: hasMarkerEvidence ? 1 : 0,
      averageFps:
          diagnostics.averageSubmittedFps ?? diagnostics.averageNativeFps,
      p95IntervalMs:
          diagnostics.p95PacerIntervalMs ?? diagnostics.p95FrameIntervalMs,
      maxIntervalMs:
          diagnostics.maxPacerIntervalMs ?? diagnostics.maxFrameIntervalMs,
      duplicatedFrameCount: diagnostics.pacerDuplicateSubmitCount > 0
          ? diagnostics.pacerDuplicateSubmitCount
          : diagnostics.duplicatedFrameCount,
      staleFrameReuseCount: diagnostics.staleFrameReuseCount,
      waitTimeoutCount: diagnostics.captureWaitTimeoutCount,
      permanentErrorCount: diagnostics.capturePermanentErrorCount,
    );
  }

  factory StreamTestFramePacingStageSummary.fromCounterSamples({
    required String stage,
    required String evidence,
    required List<_FrameCounterSample> samples,
  }) {
    final intervals = <double>[];
    final fpsValues = <double>[];
    int? largestFrameDelta;
    int? lastFrameCount;
    var staleFrameReuseCount = 0;
    _FrameCounterSample? previous;

    for (final sample in samples) {
      final frameCount = sample.frameCount;
      if (frameCount == null || frameCount < 0) {
        continue;
      }
      lastFrameCount = frameCount;
      final lastSample = previous;
      if (lastSample != null) {
        final elapsedMs = sample.collectedAt
                .difference(lastSample.collectedAt)
                .inMicroseconds /
            1000.0;
        final frameDelta = frameCount - lastSample.frameCount!;
        if (elapsedMs > 0 && frameDelta > 0) {
          intervals.add(elapsedMs / frameDelta);
          fpsValues.add(frameDelta * 1000 / elapsedMs);
          largestFrameDelta = largestFrameDelta == null
              ? frameDelta
              : max(largestFrameDelta, frameDelta);
        } else if (elapsedMs > 0 && frameDelta == 0) {
          intervals.add(elapsedMs);
          fpsValues.add(0);
          staleFrameReuseCount++;
        }
      }
      previous = sample;
    }

    return StreamTestFramePacingStageSummary(
      stage: stage,
      evidence: intervals.isEmpty ? 'none' : evidence,
      sampleCount: intervals.length,
      averageFps: _average(fpsValues),
      minimumFps: fpsValues.isEmpty ? null : fpsValues.reduce(min),
      p50IntervalMs: _percentile(intervals, 0.50),
      p95IntervalMs: _percentile(intervals, 0.95),
      maxIntervalMs: _maxDouble(intervals),
      largestFrameDelta: largestFrameDelta,
      lastFrameCount: lastFrameCount,
      staleFrameReuseCount: staleFrameReuseCount,
    );
  }

  final String stage;
  final String evidence;
  final int sampleCount;
  final double? averageFps;
  final double? minimumFps;
  final double? p50IntervalMs;
  final double? p95IntervalMs;
  final double? maxIntervalMs;
  final int? largestFrameDelta;
  final int? lastFrameCount;
  final int duplicatedFrameCount;
  final int staleFrameReuseCount;
  final int waitTimeoutCount;
  final int permanentErrorCount;

  bool get hasEvidence =>
      sampleCount > 0 ||
      averageFps != null ||
      minimumFps != null ||
      p50IntervalMs != null ||
      p95IntervalMs != null ||
      maxIntervalMs != null ||
      largestFrameDelta != null ||
      duplicatedFrameCount > 0 ||
      staleFrameReuseCount > 0 ||
      waitTimeoutCount > 0 ||
      permanentErrorCount > 0;

  String get compactLabel {
    if (!hasEvidence) {
      return 'unknown';
    }
    return 'p50=${_milliseconds(p50IntervalMs)} '
        'p95=${_milliseconds(p95IntervalMs)} '
        'max=${_milliseconds(maxIntervalMs)} '
        'avg_fps=${_number(averageFps)}';
  }

  String get markdownLabel {
    if (!hasEvidence) {
      return '?';
    }
    final extras = <String>[
      'avg ${_number(averageFps)}fps',
      if (minimumFps != null) 'min ${_number(minimumFps)}fps',
      if (sampleCount > 0) '$sampleCount windows',
      if (largestFrameDelta != null) 'largest delta $largestFrameDelta',
      if (staleFrameReuseCount > 0 || duplicatedFrameCount > 0)
        'stale $staleFrameReuseCount / duplicate $duplicatedFrameCount',
      if (waitTimeoutCount > 0) 'wait timeouts $waitTimeoutCount',
      if (permanentErrorCount > 0) 'permanent errors $permanentErrorCount',
    ];
    return '${_milliseconds(p50IntervalMs)} p50 / '
        '${_milliseconds(p95IntervalMs)} p95 / '
        '${_milliseconds(maxIntervalMs)} max (${extras.join(', ')})';
  }

  Map<String, Object?> toJson() {
    return {
      'stage': stage,
      'evidence': evidence,
      'sampleCount': sampleCount,
      'averageFps': averageFps,
      'minimumFps': minimumFps,
      'p50IntervalMs': p50IntervalMs,
      'p95IntervalMs': p95IntervalMs,
      'maxIntervalMs': maxIntervalMs,
      'largestFrameDelta': largestFrameDelta,
      'lastFrameCount': lastFrameCount,
      'duplicatedFrameCount': duplicatedFrameCount,
      'staleFrameReuseCount': staleFrameReuseCount,
      'waitTimeoutCount': waitTimeoutCount,
      'permanentErrorCount': permanentErrorCount,
    };
  }
}

class _FrameCounterSample {
  const _FrameCounterSample({
    required this.collectedAt,
    required this.frameCount,
  });

  final DateTime collectedAt;
  final int? frameCount;
}

class _StreamTestWindowSpec {
  const _StreamTestWindowSpec({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final Duration start;
  final Duration end;
}

class _GameCaptureMarkerSample {
  const _GameCaptureMarkerSample({
    required this.timestamp,
    required this.submitted,
    required this.copied,
    required this.gpuScaled,
    required this.gpuScaleFailures,
    required this.cpuFallback,
    required this.nativeNv12Submitted,
    required this.nativeNv12Queued,
    required this.nativeNv12Ready,
    required this.nativeNv12NotReadyPolls,
    required this.nativeNv12Overwritten,
    required this.nativeNv12OverwrittenFresh,
    required this.nativeNv12ReadyDropped,
    required this.nativeNv12ReadyDroppedFresh,
    required this.nativeNv12Failures,
    required this.readbackQueued,
    required this.readbackReady,
    required this.readbackNotReady,
    required this.readbackStaleDropped,
    required this.readbackLatencyDropped,
    required this.sourceFrameRegressions,
    required this.sourceFrameGaps,
    required this.sharedSlotMismatches,
    required this.deliveryRepeatNoQueued,
    required this.deliveryOverwrittenFresh,
    this.deliveryRepeatSourceAgeMaxMs,
    this.deliveryOverwriteAgeMaxMs,
    this.sourceDuplicateSkipAgeMaxMs,
    this.nativeNv12OverwriteAgeMaxMs,
    this.nativeNv12ReadyDropAgeMaxMs,
    this.deliveryWallDeltaMaxMs,
    this.deliveryQueueWaitMaxMs,
    this.readyToSubmitMaxMs,
    this.sourceToSubmitMaxMs,
    this.sourceToReadbackReadyMaxMs,
    this.readbackQueueToMapMaxMs,
    this.mapToI420MaxMs,
    this.sourceToI420ReadyMaxMs,
    this.sourceToQueueMaxMs,
    required this.deliveryWallOver2x,
    required this.deliveryWallOver3x,
    required this.deliveryWallUnderHalf,
    required this.readbackLatencyFramesMax,
    this.readbackLatencyFramesAvg,
  });

  factory _GameCaptureMarkerSample.fromMarker(String marker) {
    return _GameCaptureMarkerSample(
      timestamp: _markerTimestamp(marker),
      submitted: _intFromMarker(marker, 'submitted') ?? 0,
      copied: _intFromMarker(marker, 'copied') ?? 0,
      gpuScaled: _intFromMarker(marker, 'gpuScaled') ?? 0,
      gpuScaleFailures: _intFromMarker(marker, 'gpuScaleFailures') ?? 0,
      cpuFallback: _intFromMarker(marker, 'cpuFallback') ?? 0,
      nativeNv12Submitted: _intFromMarker(marker, 'nativeNv12Submitted') ?? 0,
      nativeNv12Queued: _intFromMarker(marker, 'nativeNv12Queued') ?? 0,
      nativeNv12Ready: _intFromMarker(marker, 'nativeNv12Ready') ?? 0,
      nativeNv12NotReadyPolls:
          _intFromMarker(marker, 'nativeNv12NotReadyPolls') ?? 0,
      nativeNv12Overwritten:
          _intFromMarker(marker, 'nativeNv12Overwritten') ?? 0,
      nativeNv12OverwrittenFresh:
          _intFromMarker(marker, 'nativeNv12OverwrittenFresh') ?? 0,
      nativeNv12ReadyDropped:
          _intFromMarker(marker, 'nativeNv12ReadyDropped') ?? 0,
      nativeNv12ReadyDroppedFresh:
          _intFromMarker(marker, 'nativeNv12ReadyDroppedFresh') ?? 0,
      nativeNv12Failures: _intFromMarker(marker, 'nativeNv12Failures') ?? 0,
      readbackQueued: _intFromMarker(marker, 'readbackQueued') ?? 0,
      readbackReady: _intFromMarker(marker, 'readbackReady') ?? 0,
      readbackNotReady: _intFromMarker(marker, 'readbackNotReady') ?? 0,
      readbackStaleDropped: _intFromMarker(marker, 'readbackStaleDropped') ?? 0,
      readbackLatencyDropped:
          _intFromMarker(marker, 'readbackLatencyDropped') ?? 0,
      sourceFrameRegressions:
          _intFromMarker(marker, 'sourceFrameRegressions') ?? 0,
      sourceFrameGaps: _intFromMarker(marker, 'sourceFrameGaps') ?? 0,
      sharedSlotMismatches: _intFromMarker(marker, 'sharedSlotMismatches') ?? 0,
      deliveryRepeatNoQueued:
          _intFromMarker(marker, 'deliveryRepeatNoQueued') ?? 0,
      deliveryOverwrittenFresh:
          _intFromMarker(marker, 'deliveryOverwrittenFresh') ?? 0,
      deliveryRepeatSourceAgeMaxMs:
          _doubleFromMarker(marker, 'deliveryRepeatSourceAgeMaxMs'),
      deliveryOverwriteAgeMaxMs:
          _doubleFromMarker(marker, 'deliveryOverwriteAgeMaxMs'),
      sourceDuplicateSkipAgeMaxMs:
          _doubleFromMarker(marker, 'sourceDuplicateSkipAgeMaxMs'),
      nativeNv12OverwriteAgeMaxMs:
          _doubleFromMarker(marker, 'nativeNv12OverwriteAgeMaxMs'),
      nativeNv12ReadyDropAgeMaxMs:
          _doubleFromMarker(marker, 'nativeNv12ReadyDropAgeMaxMs'),
      deliveryWallDeltaMaxMs:
          _doubleFromMarker(marker, 'deliveryWallDeltaMaxMs'),
      deliveryQueueWaitMaxMs:
          _doubleFromMarker(marker, 'deliveryQueueWaitMaxMs'),
      readyToSubmitMaxMs: _doubleFromMarker(marker, 'readyToSubmitMaxMs'),
      sourceToSubmitMaxMs: _doubleFromMarker(marker, 'sourceToSubmitMaxMs'),
      sourceToReadbackReadyMaxMs:
          _doubleFromMarker(marker, 'sourceToReadbackReadyMaxMs'),
      readbackQueueToMapMaxMs:
          _doubleFromMarker(marker, 'readbackQueueToMapMaxMs'),
      mapToI420MaxMs: _doubleFromMarker(marker, 'mapToI420MaxMs'),
      sourceToI420ReadyMaxMs:
          _doubleFromMarker(marker, 'sourceToI420ReadyMaxMs'),
      sourceToQueueMaxMs: _doubleFromMarker(marker, 'sourceToQueueMaxMs'),
      deliveryWallOver2x: _intFromMarker(marker, 'deliveryWallOver2x') ?? 0,
      deliveryWallOver3x: _intFromMarker(marker, 'deliveryWallOver3x') ?? 0,
      deliveryWallUnderHalf:
          _intFromMarker(marker, 'deliveryWallUnderHalf') ?? 0,
      readbackLatencyFramesMax:
          _intFromMarker(marker, 'readbackLatencyFramesMax') ?? 0,
      readbackLatencyFramesAvg:
          _doubleFromMarker(marker, 'readbackLatencyFramesAvg'),
    );
  }

  static List<_GameCaptureMarkerSample> fromMarkers(List<String> markers) {
    final samples = <_GameCaptureMarkerSample>[];
    for (final marker in markers) {
      if (!marker.toLowerCase().contains('game_capture_webrtc_source') ||
          !marker.toLowerCase().contains('stats')) {
        continue;
      }
      final sample = _GameCaptureMarkerSample.fromMarker(marker);
      if (sample.timestamp != null) {
        samples.add(sample);
      }
    }
    samples.sort((left, right) => left.timestamp!.compareTo(right.timestamp!));
    return List.unmodifiable(samples);
  }

  final DateTime? timestamp;
  final int submitted;
  final int copied;
  final int gpuScaled;
  final int gpuScaleFailures;
  final int cpuFallback;
  final int nativeNv12Submitted;
  final int nativeNv12Queued;
  final int nativeNv12Ready;
  final int nativeNv12NotReadyPolls;
  final int nativeNv12Overwritten;
  final int nativeNv12OverwrittenFresh;
  final int nativeNv12ReadyDropped;
  final int nativeNv12ReadyDroppedFresh;
  final int nativeNv12Failures;
  final int readbackQueued;
  final int readbackReady;
  final int readbackNotReady;
  final int readbackStaleDropped;
  final int readbackLatencyDropped;
  final int sourceFrameRegressions;
  final int sourceFrameGaps;
  final int sharedSlotMismatches;
  final int deliveryRepeatNoQueued;
  final int deliveryOverwrittenFresh;
  final double? deliveryRepeatSourceAgeMaxMs;
  final double? deliveryOverwriteAgeMaxMs;
  final double? sourceDuplicateSkipAgeMaxMs;
  final double? nativeNv12OverwriteAgeMaxMs;
  final double? nativeNv12ReadyDropAgeMaxMs;
  final double? deliveryWallDeltaMaxMs;
  final double? deliveryQueueWaitMaxMs;
  final double? readyToSubmitMaxMs;
  final double? sourceToSubmitMaxMs;
  final double? sourceToReadbackReadyMaxMs;
  final double? readbackQueueToMapMaxMs;
  final double? mapToI420MaxMs;
  final double? sourceToI420ReadyMaxMs;
  final double? sourceToQueueMaxMs;
  final int deliveryWallOver2x;
  final int deliveryWallOver3x;
  final int deliveryWallUnderHalf;
  final int readbackLatencyFramesMax;
  final double? readbackLatencyFramesAvg;
}

class StreamTestGameCaptureWindowCounters {
  const StreamTestGameCaptureWindowCounters({
    required this.markerPairCount,
    required this.elapsedMs,
    required this.submittedDelta,
    required this.copiedDelta,
    required this.gpuScaledDelta,
    required this.gpuScaleFailuresDelta,
    required this.cpuFallbackDelta,
    required this.nativeNv12SubmittedDelta,
    required this.nativeNv12QueuedDelta,
    required this.nativeNv12ReadyDelta,
    required this.nativeNv12NotReadyPollsDelta,
    required this.nativeNv12OverwrittenDelta,
    required this.nativeNv12OverwrittenFreshDelta,
    required this.nativeNv12ReadyDroppedDelta,
    required this.nativeNv12ReadyDroppedFreshDelta,
    required this.nativeNv12FailuresDelta,
    required this.readbackQueuedDelta,
    required this.readbackReadyDelta,
    required this.readbackNotReadyDelta,
    required this.readbackStaleDroppedDelta,
    required this.readbackLatencyDroppedDelta,
    required this.sourceFrameRegressionsDelta,
    required this.sourceFrameGapsDelta,
    required this.sharedSlotMismatchesDelta,
    required this.deliveryRepeatNoQueuedDelta,
    required this.deliveryOverwrittenFreshDelta,
    this.maxDeliveryRepeatSourceAgeMs,
    this.maxDeliveryOverwriteAgeMs,
    this.maxSourceDuplicateSkipAgeMs,
    this.maxNativeNv12OverwriteAgeMs,
    this.maxNativeNv12ReadyDropAgeMs,
    this.maxDeliveryWallDeltaMs,
    this.maxDeliveryQueueWaitMs,
    this.maxReadyToSubmitMs,
    this.maxSourceToSubmitMs,
    this.maxSourceToReadbackReadyMs,
    this.maxReadbackQueueToMapMs,
    this.maxMapToI420Ms,
    this.maxSourceToI420ReadyMs,
    this.maxSourceToQueueMs,
    required this.deliveryWallOver2xDelta,
    required this.deliveryWallOver3xDelta,
    required this.deliveryWallUnderHalfDelta,
    required this.maxReadbackLatencyFrames,
    this.maxAverageReadbackLatencyFrames,
  });

  factory StreamTestGameCaptureWindowCounters.fromMarkerPairs({
    required List<_GameCaptureMarkerSample> markerSamples,
    required DateTime? measurementStartedAt,
    required Duration startOffset,
    required Duration endOffset,
  }) {
    if (measurementStartedAt == null || markerSamples.length < 2) {
      return const StreamTestGameCaptureWindowCounters.empty();
    }
    var markerPairCount = 0;
    var elapsedMs = 0.0;
    var submittedDelta = 0;
    var copiedDelta = 0;
    var gpuScaledDelta = 0;
    var gpuScaleFailuresDelta = 0;
    var cpuFallbackDelta = 0;
    var nativeNv12SubmittedDelta = 0;
    var nativeNv12QueuedDelta = 0;
    var nativeNv12ReadyDelta = 0;
    var nativeNv12NotReadyPollsDelta = 0;
    var nativeNv12OverwrittenDelta = 0;
    var nativeNv12OverwrittenFreshDelta = 0;
    var nativeNv12ReadyDroppedDelta = 0;
    var nativeNv12ReadyDroppedFreshDelta = 0;
    var nativeNv12FailuresDelta = 0;
    var readbackQueuedDelta = 0;
    var readbackReadyDelta = 0;
    var readbackNotReadyDelta = 0;
    var readbackStaleDroppedDelta = 0;
    var readbackLatencyDroppedDelta = 0;
    var sourceFrameRegressionsDelta = 0;
    var sourceFrameGapsDelta = 0;
    var sharedSlotMismatchesDelta = 0;
    var deliveryRepeatNoQueuedDelta = 0;
    var deliveryOverwrittenFreshDelta = 0;
    double? maxDeliveryRepeatSourceAgeMs;
    double? maxDeliveryOverwriteAgeMs;
    double? maxSourceDuplicateSkipAgeMs;
    double? maxNativeNv12OverwriteAgeMs;
    double? maxNativeNv12ReadyDropAgeMs;
    double? maxDeliveryWallDeltaMs;
    double? maxDeliveryQueueWaitMs;
    double? maxReadyToSubmitMs;
    double? maxSourceToSubmitMs;
    double? maxSourceToReadbackReadyMs;
    double? maxReadbackQueueToMapMs;
    double? maxMapToI420Ms;
    double? maxSourceToI420ReadyMs;
    double? maxSourceToQueueMs;
    var deliveryWallOver2xDelta = 0;
    var deliveryWallOver3xDelta = 0;
    var deliveryWallUnderHalfDelta = 0;
    var maxReadbackLatencyFrames = 0;
    double? maxAverageReadbackLatencyFrames;

    for (var index = 1; index < markerSamples.length; index++) {
      final previous = markerSamples[index - 1];
      final current = markerSamples[index];
      final currentTimestamp = current.timestamp;
      final previousTimestamp = previous.timestamp;
      if (currentTimestamp == null || previousTimestamp == null) {
        continue;
      }
      final offset = currentTimestamp.difference(measurementStartedAt);
      if (offset < startOffset || offset > endOffset) {
        continue;
      }
      markerPairCount++;
      elapsedMs +=
          currentTimestamp.difference(previousTimestamp).inMicroseconds /
              1000.0;
      submittedDelta += _counterDelta(previous.submitted, current.submitted);
      copiedDelta += _counterDelta(previous.copied, current.copied);
      gpuScaledDelta += _counterDelta(previous.gpuScaled, current.gpuScaled);
      gpuScaleFailuresDelta +=
          _counterDelta(previous.gpuScaleFailures, current.gpuScaleFailures);
      cpuFallbackDelta +=
          _counterDelta(previous.cpuFallback, current.cpuFallback);
      nativeNv12SubmittedDelta += _counterDelta(
        previous.nativeNv12Submitted,
        current.nativeNv12Submitted,
      );
      nativeNv12QueuedDelta += _counterDelta(
        previous.nativeNv12Queued,
        current.nativeNv12Queued,
      );
      nativeNv12ReadyDelta += _counterDelta(
        previous.nativeNv12Ready,
        current.nativeNv12Ready,
      );
      nativeNv12NotReadyPollsDelta += _counterDelta(
        previous.nativeNv12NotReadyPolls,
        current.nativeNv12NotReadyPolls,
      );
      nativeNv12OverwrittenDelta += _counterDelta(
        previous.nativeNv12Overwritten,
        current.nativeNv12Overwritten,
      );
      nativeNv12OverwrittenFreshDelta += _counterDelta(
        previous.nativeNv12OverwrittenFresh,
        current.nativeNv12OverwrittenFresh,
      );
      nativeNv12ReadyDroppedDelta += _counterDelta(
        previous.nativeNv12ReadyDropped,
        current.nativeNv12ReadyDropped,
      );
      nativeNv12ReadyDroppedFreshDelta += _counterDelta(
        previous.nativeNv12ReadyDroppedFresh,
        current.nativeNv12ReadyDroppedFresh,
      );
      nativeNv12FailuresDelta += _counterDelta(
        previous.nativeNv12Failures,
        current.nativeNv12Failures,
      );
      readbackQueuedDelta +=
          _counterDelta(previous.readbackQueued, current.readbackQueued);
      readbackReadyDelta +=
          _counterDelta(previous.readbackReady, current.readbackReady);
      readbackNotReadyDelta +=
          _counterDelta(previous.readbackNotReady, current.readbackNotReady);
      readbackStaleDroppedDelta += _counterDelta(
        previous.readbackStaleDropped,
        current.readbackStaleDropped,
      );
      readbackLatencyDroppedDelta += _counterDelta(
        previous.readbackLatencyDropped,
        current.readbackLatencyDropped,
      );
      sourceFrameRegressionsDelta += _counterDelta(
        previous.sourceFrameRegressions,
        current.sourceFrameRegressions,
      );
      sourceFrameGapsDelta +=
          _counterDelta(previous.sourceFrameGaps, current.sourceFrameGaps);
      sharedSlotMismatchesDelta += _counterDelta(
        previous.sharedSlotMismatches,
        current.sharedSlotMismatches,
      );
      deliveryRepeatNoQueuedDelta += _counterDelta(
        previous.deliveryRepeatNoQueued,
        current.deliveryRepeatNoQueued,
      );
      deliveryOverwrittenFreshDelta += _counterDelta(
        previous.deliveryOverwrittenFresh,
        current.deliveryOverwrittenFresh,
      );
      final repeatSourceAgeMax = current.deliveryRepeatSourceAgeMaxMs;
      if (repeatSourceAgeMax != null) {
        maxDeliveryRepeatSourceAgeMs = max(
          maxDeliveryRepeatSourceAgeMs ?? repeatSourceAgeMax,
          repeatSourceAgeMax,
        );
      }
      final deliveryOverwriteAgeMax = current.deliveryOverwriteAgeMaxMs;
      if (deliveryOverwriteAgeMax != null) {
        maxDeliveryOverwriteAgeMs = max(
          maxDeliveryOverwriteAgeMs ?? deliveryOverwriteAgeMax,
          deliveryOverwriteAgeMax,
        );
      }
      final sourceDuplicateSkipAgeMax = current.sourceDuplicateSkipAgeMaxMs;
      if (sourceDuplicateSkipAgeMax != null) {
        maxSourceDuplicateSkipAgeMs = max(
          maxSourceDuplicateSkipAgeMs ?? sourceDuplicateSkipAgeMax,
          sourceDuplicateSkipAgeMax,
        );
      }
      final nativeOverwriteAgeMax = current.nativeNv12OverwriteAgeMaxMs;
      if (nativeOverwriteAgeMax != null) {
        maxNativeNv12OverwriteAgeMs = max(
          maxNativeNv12OverwriteAgeMs ?? nativeOverwriteAgeMax,
          nativeOverwriteAgeMax,
        );
      }
      final nativeReadyDropAgeMax = current.nativeNv12ReadyDropAgeMaxMs;
      if (nativeReadyDropAgeMax != null) {
        maxNativeNv12ReadyDropAgeMs = max(
          maxNativeNv12ReadyDropAgeMs ?? nativeReadyDropAgeMax,
          nativeReadyDropAgeMax,
        );
      }
      final deliveryWallDeltaMax = current.deliveryWallDeltaMaxMs;
      if (deliveryWallDeltaMax != null) {
        maxDeliveryWallDeltaMs = max(
          maxDeliveryWallDeltaMs ?? deliveryWallDeltaMax,
          deliveryWallDeltaMax,
        );
      }
      final queueWaitMax = current.deliveryQueueWaitMaxMs;
      if (queueWaitMax != null) {
        maxDeliveryQueueWaitMs = max(
          maxDeliveryQueueWaitMs ?? queueWaitMax,
          queueWaitMax,
        );
      }
      final readyToSubmitMax = current.readyToSubmitMaxMs;
      if (readyToSubmitMax != null) {
        maxReadyToSubmitMs = max(
          maxReadyToSubmitMs ?? readyToSubmitMax,
          readyToSubmitMax,
        );
      }
      final sourceToSubmitMax = current.sourceToSubmitMaxMs;
      if (sourceToSubmitMax != null) {
        maxSourceToSubmitMs = max(
          maxSourceToSubmitMs ?? sourceToSubmitMax,
          sourceToSubmitMax,
        );
      }
      final sourceToReadbackReadyMax = current.sourceToReadbackReadyMaxMs;
      if (sourceToReadbackReadyMax != null) {
        maxSourceToReadbackReadyMs = max(
          maxSourceToReadbackReadyMs ?? sourceToReadbackReadyMax,
          sourceToReadbackReadyMax,
        );
      }
      final readbackQueueToMapMax = current.readbackQueueToMapMaxMs;
      if (readbackQueueToMapMax != null) {
        maxReadbackQueueToMapMs = max(
          maxReadbackQueueToMapMs ?? readbackQueueToMapMax,
          readbackQueueToMapMax,
        );
      }
      final mapToI420Max = current.mapToI420MaxMs;
      if (mapToI420Max != null) {
        maxMapToI420Ms = max(maxMapToI420Ms ?? mapToI420Max, mapToI420Max);
      }
      final sourceToI420ReadyMax = current.sourceToI420ReadyMaxMs;
      if (sourceToI420ReadyMax != null) {
        maxSourceToI420ReadyMs = max(
          maxSourceToI420ReadyMs ?? sourceToI420ReadyMax,
          sourceToI420ReadyMax,
        );
      }
      final sourceToQueueMax = current.sourceToQueueMaxMs;
      if (sourceToQueueMax != null) {
        maxSourceToQueueMs = max(
          maxSourceToQueueMs ?? sourceToQueueMax,
          sourceToQueueMax,
        );
      }
      deliveryWallOver2xDelta += _counterDelta(
        previous.deliveryWallOver2x,
        current.deliveryWallOver2x,
      );
      deliveryWallOver3xDelta += _counterDelta(
        previous.deliveryWallOver3x,
        current.deliveryWallOver3x,
      );
      deliveryWallUnderHalfDelta += _counterDelta(
        previous.deliveryWallUnderHalf,
        current.deliveryWallUnderHalf,
      );
      maxReadbackLatencyFrames = max(
        maxReadbackLatencyFrames,
        current.readbackLatencyFramesMax,
      );
      final averageLatency = current.readbackLatencyFramesAvg;
      if (averageLatency != null) {
        maxAverageReadbackLatencyFrames = max(
          maxAverageReadbackLatencyFrames ?? averageLatency,
          averageLatency,
        );
      }
    }

    return StreamTestGameCaptureWindowCounters(
      markerPairCount: markerPairCount,
      elapsedMs: elapsedMs,
      submittedDelta: submittedDelta,
      copiedDelta: copiedDelta,
      gpuScaledDelta: gpuScaledDelta,
      gpuScaleFailuresDelta: gpuScaleFailuresDelta,
      cpuFallbackDelta: cpuFallbackDelta,
      nativeNv12SubmittedDelta: nativeNv12SubmittedDelta,
      nativeNv12QueuedDelta: nativeNv12QueuedDelta,
      nativeNv12ReadyDelta: nativeNv12ReadyDelta,
      nativeNv12NotReadyPollsDelta: nativeNv12NotReadyPollsDelta,
      nativeNv12OverwrittenDelta: nativeNv12OverwrittenDelta,
      nativeNv12OverwrittenFreshDelta: nativeNv12OverwrittenFreshDelta,
      nativeNv12ReadyDroppedDelta: nativeNv12ReadyDroppedDelta,
      nativeNv12ReadyDroppedFreshDelta: nativeNv12ReadyDroppedFreshDelta,
      nativeNv12FailuresDelta: nativeNv12FailuresDelta,
      readbackQueuedDelta: readbackQueuedDelta,
      readbackReadyDelta: readbackReadyDelta,
      readbackNotReadyDelta: readbackNotReadyDelta,
      readbackStaleDroppedDelta: readbackStaleDroppedDelta,
      readbackLatencyDroppedDelta: readbackLatencyDroppedDelta,
      sourceFrameRegressionsDelta: sourceFrameRegressionsDelta,
      sourceFrameGapsDelta: sourceFrameGapsDelta,
      sharedSlotMismatchesDelta: sharedSlotMismatchesDelta,
      deliveryRepeatNoQueuedDelta: deliveryRepeatNoQueuedDelta,
      deliveryOverwrittenFreshDelta: deliveryOverwrittenFreshDelta,
      maxDeliveryRepeatSourceAgeMs: maxDeliveryRepeatSourceAgeMs,
      maxDeliveryOverwriteAgeMs: maxDeliveryOverwriteAgeMs,
      maxSourceDuplicateSkipAgeMs: maxSourceDuplicateSkipAgeMs,
      maxNativeNv12OverwriteAgeMs: maxNativeNv12OverwriteAgeMs,
      maxNativeNv12ReadyDropAgeMs: maxNativeNv12ReadyDropAgeMs,
      maxDeliveryWallDeltaMs: maxDeliveryWallDeltaMs,
      maxDeliveryQueueWaitMs: maxDeliveryQueueWaitMs,
      maxReadyToSubmitMs: maxReadyToSubmitMs,
      maxSourceToSubmitMs: maxSourceToSubmitMs,
      maxSourceToReadbackReadyMs: maxSourceToReadbackReadyMs,
      maxReadbackQueueToMapMs: maxReadbackQueueToMapMs,
      maxMapToI420Ms: maxMapToI420Ms,
      maxSourceToI420ReadyMs: maxSourceToI420ReadyMs,
      maxSourceToQueueMs: maxSourceToQueueMs,
      deliveryWallOver2xDelta: deliveryWallOver2xDelta,
      deliveryWallOver3xDelta: deliveryWallOver3xDelta,
      deliveryWallUnderHalfDelta: deliveryWallUnderHalfDelta,
      maxReadbackLatencyFrames: maxReadbackLatencyFrames,
      maxAverageReadbackLatencyFrames: maxAverageReadbackLatencyFrames,
    );
  }

  const StreamTestGameCaptureWindowCounters.empty()
      : markerPairCount = 0,
        elapsedMs = 0,
        submittedDelta = 0,
        copiedDelta = 0,
        gpuScaledDelta = 0,
        gpuScaleFailuresDelta = 0,
        cpuFallbackDelta = 0,
        nativeNv12SubmittedDelta = 0,
        nativeNv12QueuedDelta = 0,
        nativeNv12ReadyDelta = 0,
        nativeNv12NotReadyPollsDelta = 0,
        nativeNv12OverwrittenDelta = 0,
        nativeNv12OverwrittenFreshDelta = 0,
        nativeNv12ReadyDroppedDelta = 0,
        nativeNv12ReadyDroppedFreshDelta = 0,
        nativeNv12FailuresDelta = 0,
        readbackQueuedDelta = 0,
        readbackReadyDelta = 0,
        readbackNotReadyDelta = 0,
        readbackStaleDroppedDelta = 0,
        readbackLatencyDroppedDelta = 0,
        sourceFrameRegressionsDelta = 0,
        sourceFrameGapsDelta = 0,
        sharedSlotMismatchesDelta = 0,
        deliveryRepeatNoQueuedDelta = 0,
        deliveryOverwrittenFreshDelta = 0,
        maxDeliveryRepeatSourceAgeMs = null,
        maxDeliveryOverwriteAgeMs = null,
        maxSourceDuplicateSkipAgeMs = null,
        maxNativeNv12OverwriteAgeMs = null,
        maxNativeNv12ReadyDropAgeMs = null,
        maxDeliveryWallDeltaMs = null,
        maxDeliveryQueueWaitMs = null,
        maxReadyToSubmitMs = null,
        maxSourceToSubmitMs = null,
        maxSourceToReadbackReadyMs = null,
        maxReadbackQueueToMapMs = null,
        maxMapToI420Ms = null,
        maxSourceToI420ReadyMs = null,
        maxSourceToQueueMs = null,
        deliveryWallOver2xDelta = 0,
        deliveryWallOver3xDelta = 0,
        deliveryWallUnderHalfDelta = 0,
        maxReadbackLatencyFrames = 0,
        maxAverageReadbackLatencyFrames = null;

  final int markerPairCount;
  final double elapsedMs;
  final int submittedDelta;
  final int copiedDelta;
  final int gpuScaledDelta;
  final int gpuScaleFailuresDelta;
  final int cpuFallbackDelta;
  final int nativeNv12SubmittedDelta;
  final int nativeNv12QueuedDelta;
  final int nativeNv12ReadyDelta;
  final int nativeNv12NotReadyPollsDelta;
  final int nativeNv12OverwrittenDelta;
  final int nativeNv12OverwrittenFreshDelta;
  final int nativeNv12ReadyDroppedDelta;
  final int nativeNv12ReadyDroppedFreshDelta;
  final int nativeNv12FailuresDelta;
  final int readbackQueuedDelta;
  final int readbackReadyDelta;
  final int readbackNotReadyDelta;
  final int readbackStaleDroppedDelta;
  final int readbackLatencyDroppedDelta;
  final int sourceFrameRegressionsDelta;
  final int sourceFrameGapsDelta;
  final int sharedSlotMismatchesDelta;
  final int deliveryRepeatNoQueuedDelta;
  final int deliveryOverwrittenFreshDelta;
  final double? maxDeliveryRepeatSourceAgeMs;
  final double? maxDeliveryOverwriteAgeMs;
  final double? maxSourceDuplicateSkipAgeMs;
  final double? maxNativeNv12OverwriteAgeMs;
  final double? maxNativeNv12ReadyDropAgeMs;
  final double? maxDeliveryWallDeltaMs;
  final double? maxDeliveryQueueWaitMs;
  final double? maxReadyToSubmitMs;
  final double? maxSourceToSubmitMs;
  final double? maxSourceToReadbackReadyMs;
  final double? maxReadbackQueueToMapMs;
  final double? maxMapToI420Ms;
  final double? maxSourceToI420ReadyMs;
  final double? maxSourceToQueueMs;
  final int deliveryWallOver2xDelta;
  final int deliveryWallOver3xDelta;
  final int deliveryWallUnderHalfDelta;
  final int maxReadbackLatencyFrames;
  final double? maxAverageReadbackLatencyFrames;

  bool get hasEvidence => markerPairCount > 0;

  double? get submittedFps =>
      elapsedMs > 0 ? submittedDelta * 1000 / elapsedMs : null;

  String get compactLabel {
    if (!hasEvidence) {
      return 'native window unavailable';
    }
    return 'submitted ${_number(submittedFps)}fps, '
        'gpu +$gpuScaledDelta/cpu +$cpuFallbackDelta, '
        'native-nv12 +$nativeNv12SubmittedDelta/'
        'queued +$nativeNv12QueuedDelta/'
        'ready +$nativeNv12ReadyDelta/'
        'not-ready +$nativeNv12NotReadyPollsDelta/'
        'overwrite +$nativeNv12OverwrittenDelta/'
        'overwrite-fresh +$nativeNv12OverwrittenFreshDelta/'
        'ready-drop +$nativeNv12ReadyDroppedDelta/'
        'ready-drop-fresh +$nativeNv12ReadyDroppedFreshDelta/'
        'fail +$nativeNv12FailuresDelta, '
        'readback ready +$readbackReadyDelta/not-ready +$readbackNotReadyDelta, '
        'repeat-no-queue +$deliveryRepeatNoQueuedDelta, '
        'repeat-age ${_milliseconds(maxDeliveryRepeatSourceAgeMs)}, '
        'source-duplicate-age ${_milliseconds(maxSourceDuplicateSkipAgeMs)}, '
        'overwrite-age ${_milliseconds(maxDeliveryOverwriteAgeMs)}, '
        'overwrite-fresh +$deliveryOverwrittenFreshDelta, '
        'nv12-overwrite-age ${_milliseconds(maxNativeNv12OverwriteAgeMs)}, '
        'nv12-ready-drop-age ${_milliseconds(maxNativeNv12ReadyDropAgeMs)}, '
        'wall-gap ${_milliseconds(maxDeliveryWallDeltaMs)}, '
        'queue-wait ${_milliseconds(maxDeliveryQueueWaitMs)}, '
        'ready-submit ${_milliseconds(maxReadyToSubmitMs)}, '
        'source-submit ${_milliseconds(maxSourceToSubmitMs)}, '
        'source-readback ${_milliseconds(maxSourceToReadbackReadyMs)}, '
        'queue-map ${_milliseconds(maxReadbackQueueToMapMs)}, '
        'map-i420 ${_milliseconds(maxMapToI420Ms)}, '
        'source-i420 ${_milliseconds(maxSourceToI420ReadyMs)}, '
        'source-queue ${_milliseconds(maxSourceToQueueMs)}, '
        'gap-counts >2x +$deliveryWallOver2xDelta/'
        '>3x +$deliveryWallOver3xDelta/'
        '<0.5x +$deliveryWallUnderHalfDelta, '
        'latency-drop +$readbackLatencyDroppedDelta, '
        'stale +$readbackStaleDroppedDelta, '
        'max latency ${maxReadbackLatencyFrames}f';
  }

  Map<String, Object?> toJson() {
    return {
      'markerPairCount': markerPairCount,
      'elapsedMs': elapsedMs,
      'submittedDelta': submittedDelta,
      'submittedFps': submittedFps,
      'copiedDelta': copiedDelta,
      'gpuScaledDelta': gpuScaledDelta,
      'gpuScaleFailuresDelta': gpuScaleFailuresDelta,
      'cpuFallbackDelta': cpuFallbackDelta,
      'nativeNv12SubmittedDelta': nativeNv12SubmittedDelta,
      'nativeNv12QueuedDelta': nativeNv12QueuedDelta,
      'nativeNv12ReadyDelta': nativeNv12ReadyDelta,
      'nativeNv12NotReadyPollsDelta': nativeNv12NotReadyPollsDelta,
      'nativeNv12OverwrittenDelta': nativeNv12OverwrittenDelta,
      'nativeNv12OverwrittenFreshDelta': nativeNv12OverwrittenFreshDelta,
      'nativeNv12ReadyDroppedDelta': nativeNv12ReadyDroppedDelta,
      'nativeNv12ReadyDroppedFreshDelta': nativeNv12ReadyDroppedFreshDelta,
      'nativeNv12FailuresDelta': nativeNv12FailuresDelta,
      'readbackQueuedDelta': readbackQueuedDelta,
      'readbackReadyDelta': readbackReadyDelta,
      'readbackNotReadyDelta': readbackNotReadyDelta,
      'readbackStaleDroppedDelta': readbackStaleDroppedDelta,
      'readbackLatencyDroppedDelta': readbackLatencyDroppedDelta,
      'sourceFrameRegressionsDelta': sourceFrameRegressionsDelta,
      'sourceFrameGapsDelta': sourceFrameGapsDelta,
      'sharedSlotMismatchesDelta': sharedSlotMismatchesDelta,
      'deliveryRepeatNoQueuedDelta': deliveryRepeatNoQueuedDelta,
      'deliveryOverwrittenFreshDelta': deliveryOverwrittenFreshDelta,
      'maxDeliveryRepeatSourceAgeMs': maxDeliveryRepeatSourceAgeMs,
      'maxDeliveryOverwriteAgeMs': maxDeliveryOverwriteAgeMs,
      'maxSourceDuplicateSkipAgeMs': maxSourceDuplicateSkipAgeMs,
      'maxNativeNv12OverwriteAgeMs': maxNativeNv12OverwriteAgeMs,
      'maxNativeNv12ReadyDropAgeMs': maxNativeNv12ReadyDropAgeMs,
      'maxDeliveryWallDeltaMs': maxDeliveryWallDeltaMs,
      'maxDeliveryQueueWaitMs': maxDeliveryQueueWaitMs,
      'maxReadyToSubmitMs': maxReadyToSubmitMs,
      'maxSourceToSubmitMs': maxSourceToSubmitMs,
      'maxSourceToReadbackReadyMs': maxSourceToReadbackReadyMs,
      'maxReadbackQueueToMapMs': maxReadbackQueueToMapMs,
      'maxMapToI420Ms': maxMapToI420Ms,
      'maxSourceToI420ReadyMs': maxSourceToI420ReadyMs,
      'maxSourceToQueueMs': maxSourceToQueueMs,
      'deliveryWallOver2xDelta': deliveryWallOver2xDelta,
      'deliveryWallOver3xDelta': deliveryWallOver3xDelta,
      'deliveryWallUnderHalfDelta': deliveryWallUnderHalfDelta,
      'maxReadbackLatencyFrames': maxReadbackLatencyFrames,
      'maxAverageReadbackLatencyFrames': maxAverageReadbackLatencyFrames,
    };
  }
}

class StreamTestSummary {
  const StreamTestSummary({
    required this.senderSampleCount,
    required this.preEncodeSampleCount,
    this.screenShareProfileDetails = const {},
    this.senderCodecs = const {},
    this.encoderImplementations = const {},
    this.hardwareEncodeStates = const {},
    this.averageFps,
    this.minimumFps,
    this.averageCaptureFps,
    this.minimumCaptureFps,
    this.averageEncodeFps,
    this.minimumEncodeFps,
    this.averageSendFps,
    this.minimumSendFps,
    this.averageBitrateBps,
    this.averageAvailableOutgoingBitrateBps,
    this.minimumAvailableOutgoingBitrateBps,
    this.maximumAvailableOutgoingBitrateBps,
    this.requestedWidth,
    this.requestedHeight,
    this.requestedFps,
    this.requestedBitrateBps,
    this.preEncodeWidth,
    this.preEncodeHeight,
    this.encodedWidth,
    this.encodedHeight,
    this.averageEncodeTimeMs,
    this.maxEncodeTimeMs,
    this.averagePacketSendDelayMs,
    this.maxPacketSendDelayMs,
    this.maxPacketLossPercent,
    this.maxRoundTripTimeMs,
    this.maxNackCount,
    this.framesCapturedMax,
    this.framesEncodedMax,
    this.framesSentMax,
    this.framesDroppedBeforeEncodeMax,
    this.framesDroppedByEncoderMax,
    this.qualityLimitationReasons = const {},
    this.activeLayers = const {},
    this.nativeDiagnostics = const StreamTestNativeDiagnostics(),
    this.framePacing = const StreamTestFramePacingSummary(),
  });

  factory StreamTestSummary.fromSamples(
    List<StreamTestSample> samples, {
    StreamTestNativeDiagnostics nativeDiagnostics =
        const StreamTestNativeDiagnostics(),
  }) {
    final senderTracks = samples
        .map((sample) => _bestSenderTrack(sample.snapshot))
        .whereType<VoipTrackDiagnostics>()
        .toList(growable: false);
    final profileDetails = samples
        .map((sample) => sample.snapshot.screenShareProfileDetails)
        .whereType<String>()
        .where((details) => details.trim().isNotEmpty)
        .toSet();
    final senderCodecs = senderTracks
        .map((track) => track.codec)
        .whereType<String>()
        .where((codec) => codec.trim().isNotEmpty)
        .toSet();
    final encoderImplementations = senderTracks
        .map((track) => track.encoderImplementation)
        .whereType<String>()
        .where((implementation) => implementation.trim().isNotEmpty)
        .toSet();
    final hardwareEncodeStates = senderTracks
        .map((track) => track.hardwareEncodeActive)
        .whereType<bool>()
        .toSet();
    final fpsValues = senderTracks
        .map((track) => track.sendFps ?? track.encodeFps ?? track.fps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList(growable: false);
    final captureFpsValues = senderTracks
        .map((track) => track.captureFps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList(growable: false);
    final encodeFpsValues = senderTracks
        .map((track) => track.encodeFps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList(growable: false);
    final sendFpsValues = senderTracks
        .map((track) => track.sendFps)
        .whereType<double>()
        .where((fps) => fps > 0)
        .toList(growable: false);
    final bitrateValues = senderTracks
        .map((track) => track.bitrateBps)
        .whereType<int>()
        .where((bitrate) => bitrate > 0)
        .toList(growable: false);
    final availableOutgoingBitrateValues = senderTracks
        .map((track) => track.availableOutgoingBitrateBps)
        .whereType<int>()
        .where((bitrate) => bitrate > 0)
        .toList(growable: false);
    final encodeTimeValues = senderTracks
        .map((track) => track.averageEncodeTimeMs)
        .whereType<double>()
        .where((duration) => duration > 0)
        .toList(growable: false);
    final sendDelayValues = senderTracks
        .map((track) => track.averagePacketSendDelayMs)
        .whereType<double>()
        .where((duration) => duration > 0)
        .toList(growable: false);
    final bestResolution = senderTracks.fold<({int width, int height})?>(
      null,
      (best, track) {
        final width = track.width;
        final height = track.height;
        if (width == null || height == null || width <= 0 || height <= 0) {
          return best;
        }
        if (best == null || width * height > best.width * best.height) {
          return (width: width, height: height);
        }
        return best;
      },
    );
    final bestPreEncodeResolution =
        senderTracks.fold<({int width, int height})?>(
      null,
      (best, track) {
        final width = track.preEncodeWidth;
        final height = track.preEncodeHeight;
        if (width == null || height == null || width <= 0 || height <= 0) {
          return best;
        }
        if (best == null || width * height > best.width * best.height) {
          return (width: width, height: height);
        }
        return best;
      },
    );
    final requestedTrack = senderTracks.firstWhere(
      (track) =>
          track.requestedWidth != null ||
          track.requestedHeight != null ||
          track.requestedFps != null ||
          track.requestedBitrateBps != null,
      orElse: () => senderTracks.isEmpty
          ? const VoipTrackDiagnostics(
              streamId: '',
              label: '',
              type: VoipStreamType.screenshare,
              direction: VoipDiagnosticsTrackDirection.sender,
            )
          : senderTracks.first,
    );
    final framePacing = StreamTestFramePacingSummary.fromSamples(
      samples,
      nativeDiagnostics: nativeDiagnostics,
    );

    return StreamTestSummary(
      senderSampleCount: senderTracks.length,
      preEncodeSampleCount: senderTracks
          .where((track) =>
              (track.preEncodeWidth ?? 0) > 0 &&
              (track.preEncodeHeight ?? 0) > 0)
          .length,
      screenShareProfileDetails: profileDetails,
      senderCodecs: senderCodecs,
      encoderImplementations: encoderImplementations,
      hardwareEncodeStates: hardwareEncodeStates,
      averageFps: _average(fpsValues),
      minimumFps: fpsValues.isEmpty ? null : fpsValues.reduce(min),
      averageCaptureFps: _average(captureFpsValues),
      minimumCaptureFps:
          captureFpsValues.isEmpty ? null : captureFpsValues.reduce(min),
      averageEncodeFps: _average(encodeFpsValues),
      minimumEncodeFps:
          encodeFpsValues.isEmpty ? null : encodeFpsValues.reduce(min),
      averageSendFps: _average(sendFpsValues),
      minimumSendFps: sendFpsValues.isEmpty ? null : sendFpsValues.reduce(min),
      averageBitrateBps: _averageInt(bitrateValues),
      averageAvailableOutgoingBitrateBps:
          _averageInt(availableOutgoingBitrateValues),
      minimumAvailableOutgoingBitrateBps:
          _minInt(availableOutgoingBitrateValues),
      maximumAvailableOutgoingBitrateBps:
          _maxInt(availableOutgoingBitrateValues),
      requestedWidth: requestedTrack.requestedWidth,
      requestedHeight: requestedTrack.requestedHeight,
      requestedFps: requestedTrack.requestedFps,
      requestedBitrateBps: requestedTrack.requestedBitrateBps,
      preEncodeWidth: bestPreEncodeResolution?.width,
      preEncodeHeight: bestPreEncodeResolution?.height,
      encodedWidth: bestResolution?.width,
      encodedHeight: bestResolution?.height,
      averageEncodeTimeMs: _average(encodeTimeValues),
      maxEncodeTimeMs: _maxDouble(encodeTimeValues),
      averagePacketSendDelayMs: _average(sendDelayValues),
      maxPacketSendDelayMs: _maxDouble(sendDelayValues),
      maxPacketLossPercent: _maxDouble(senderTracks
          .map((track) => track.packetLossPercent)
          .whereType<double>()),
      maxRoundTripTimeMs: _maxDouble(senderTracks
          .map((track) => track.roundTripTimeMs)
          .whereType<double>()),
      maxNackCount: _maxInt(
          senderTracks.map((track) => track.nackCount).whereType<int>()),
      framesCapturedMax: _maxInt(
          senderTracks.map((track) => track.framesCaptured).whereType<int>()),
      framesEncodedMax: _maxInt(
          senderTracks.map((track) => track.framesEncoded).whereType<int>()),
      framesSentMax: _maxInt(
          senderTracks.map((track) => track.framesSent).whereType<int>()),
      framesDroppedBeforeEncodeMax: _maxInt(senderTracks
          .map((track) => track.framesDroppedBeforeEncode)
          .whereType<int>()),
      framesDroppedByEncoderMax: _maxInt(senderTracks
          .map((track) => track.framesDroppedByEncoder)
          .whereType<int>()),
      qualityLimitationReasons: senderTracks
          .map((track) => track.qualityLimitationReason)
          .whereType<String>()
          .where((reason) => reason.trim().isNotEmpty)
          .toSet(),
      activeLayers: senderTracks
          .map((track) => track.activeLayer ?? track.rid)
          .whereType<String>()
          .where((layer) => layer.trim().isNotEmpty)
          .toSet(),
      nativeDiagnostics: nativeDiagnostics,
      framePacing: framePacing,
    );
  }

  final double? averageFps;
  final double? minimumFps;
  final int senderSampleCount;
  final int preEncodeSampleCount;
  final Set<String> screenShareProfileDetails;
  final Set<String> senderCodecs;
  final Set<String> encoderImplementations;
  final Set<bool> hardwareEncodeStates;
  final double? averageCaptureFps;
  final double? minimumCaptureFps;
  final double? averageEncodeFps;
  final double? minimumEncodeFps;
  final double? averageSendFps;
  final double? minimumSendFps;
  final int? averageBitrateBps;
  final int? averageAvailableOutgoingBitrateBps;
  final int? minimumAvailableOutgoingBitrateBps;
  final int? maximumAvailableOutgoingBitrateBps;
  final int? requestedWidth;
  final int? requestedHeight;
  final double? requestedFps;
  final int? requestedBitrateBps;
  final int? preEncodeWidth;
  final int? preEncodeHeight;
  final int? encodedWidth;
  final int? encodedHeight;
  final double? averageEncodeTimeMs;
  final double? maxEncodeTimeMs;
  final double? averagePacketSendDelayMs;
  final double? maxPacketSendDelayMs;
  final double? maxPacketLossPercent;
  final double? maxRoundTripTimeMs;
  final int? maxNackCount;
  final int? framesCapturedMax;
  final int? framesEncodedMax;
  final int? framesSentMax;
  final int? framesDroppedBeforeEncodeMax;
  final int? framesDroppedByEncoderMax;
  final Set<String> qualityLimitationReasons;
  final Set<String> activeLayers;
  final StreamTestNativeDiagnostics nativeDiagnostics;
  final StreamTestFramePacingSummary framePacing;

  String get encodedResolutionLabel {
    if (encodedWidth == null || encodedHeight == null) {
      return 'unknown';
    }
    return '${encodedWidth}x$encodedHeight';
  }

  String get preEncodeResolutionLabel {
    if (preEncodeWidth == null || preEncodeHeight == null) {
      return 'unknown';
    }
    return '${preEncodeWidth}x$preEncodeHeight';
  }

  String get requestedResolutionLabel {
    if (requestedWidth == null || requestedHeight == null) {
      return 'unknown';
    }
    final fpsLabel = requestedFps == null ? '' : '@${_number(requestedFps)}fps';
    return '${requestedWidth}x$requestedHeight$fpsLabel';
  }

  String get qualityLimitationReasonsLabel => qualityLimitationReasons.isEmpty
      ? 'unknown'
      : qualityLimitationReasons.join(', ');

  String get activeLayersLabel =>
      activeLayers.isEmpty ? 'unknown' : activeLayers.join(', ');

  String get profileDetailsLabel => screenShareProfileDetails.isEmpty
      ? 'unknown'
      : screenShareProfileDetails.join(' | ');

  String get senderCodecsLabel =>
      senderCodecs.isEmpty ? 'unknown' : senderCodecs.join(', ');

  String get encoderImplementationsLabel => encoderImplementations.isEmpty
      ? 'unknown'
      : encoderImplementations.join(', ');

  String get hardwareEncodeStatesLabel => hardwareEncodeStates.isEmpty
      ? 'unknown'
      : hardwareEncodeStates.map((active) => active ? 'yes' : 'no').join(', ');

  String get capturePipelineLabel {
    return 'requested=$requestedResolutionLabel '
        'pre_encode=$preEncodeResolutionLabel '
        'encoded=$encodedResolutionLabel '
        'capture=${_number(averageCaptureFps)}fps '
        'encode=${_number(averageEncodeFps)}fps '
        'send=${_number(averageSendFps)}fps';
  }

  List<String> get senderHandoffDiagnosticMissingFields {
    final native = nativeDiagnostics;
    return <String>[
      if (native.gameCaptureDeliveryOnFrameCallSamples == 0)
        'delivery_on_frame_call_ms',
      if (native.gameCaptureNativeNv12ConversionStartAgeSamples == 0)
        'native_nv12_conversion_start_age_ms',
      if (native.gameCaptureNativeNv12SubmittedFrames > 0 &&
          native.gameCaptureNativeNv12FrameOwnership == null)
        'native_nv12_frame_ownership',
      if (native.gameCaptureNativeNv12FrameOwnership == 'owned_texture_copy' &&
          native.gameCaptureNativeNv12OwnedCopySamples == 0)
        'native_nv12_owned_copy_ms',
      if (native.gameCaptureConsumerAdapterLuid == null)
        'consumer_adapter_luid',
      if (native.encoderNativeReadyFenceWaitSamples == 0)
        'native_ready_fence_wait_ms',
      if (native.encoderNativeInputFrames > 0 &&
          native.encoderNativeSourceAgeSamples == 0)
        'native_source_age_ms',
      if (native.encoderNativeInputFrames > 0 &&
          native.encoderNativeBufferAgeSamples == 0)
        'native_buffer_age_ms',
      if (native.encoderNativeInputFrames > 0 &&
          native.encoderNativeSampleLifetimeSamples == 0)
        'native_sample_lifetime_ms',
      if (native.encoderProcessInputSamples == 0) 'process_input_ms',
      if (native.encoderProcessOutputSamples == 0) 'process_output_ms',
      if (native.encoderEncodedCallbackSamples == 0) 'encoded_callback_ms',
      if (!native.hasWebrtcRawSenderBoundaryDiagnostics)
        'webrtc raw sender boundary timing',
      if (native.webrtcSourceOnFrameSamples > 0 &&
          native.webrtcVideoBroadcasterSamples == 0)
        'VideoBroadcaster sink dispatch timing',
      if (native.webrtcVideoBroadcasterSamples > 0 &&
          native.webrtcVideoBroadcasterSlowSinkId == null)
        'VideoBroadcaster slow-sink attribution',
      if (native.webrtcVideoBroadcasterSamples > 0 &&
          native.webrtcVideoBroadcasterSinkRoster == null)
        'VideoBroadcaster sink roster',
      if (native.webrtcVideoBroadcasterSamples > 0 &&
          native.webrtcVideoBroadcasterInactiveSinks > 0 &&
          !native.webrtcVideoBroadcasterInactiveNativeSinkBypassReported)
        'VideoBroadcaster inactive native bypass counter',
      if (native.encoderMaxQueueDepth == 0) 'encoder queue depth',
      if (framesDroppedBeforeEncodeMax == null &&
          framesDroppedByEncoderMax == null)
        'sender drop counters',
    ];
  }

  bool get hasSenderHandoffDiagnostics {
    final native = nativeDiagnostics;
    return native.gameCaptureDeliveryOnFrameCallSamples > 0 ||
        native.gameCaptureNativeNv12ConversionStartAgeSamples > 0 ||
        native.encoderNativeReadyFenceWaitSamples > 0 ||
        native.encoderProcessInputSamples > 0 ||
        native.encoderProcessOutputSamples > 0 ||
        native.encoderEncodedCallbackSamples > 0 ||
        native.encoderEncodedCallbackQueueWaitSamples > 0 ||
        native.encoderEncodedCallbackEnqueueSamples > 0 ||
        native.encoderMaxEncodedCallbackQueueDepth > 0 ||
        native.encoderMaxEncodedCallbackDrops > 0 ||
        native.gameCaptureConsumerAdapterLuid != null ||
        native.gameCaptureNativeNv12FrameOwnership != null ||
        native.gameCaptureNativeNv12OwnedCopySamples > 0 ||
        native.encoderNativeSourceAgeSamples > 0 ||
        native.encoderNativeBufferAgeSamples > 0 ||
        native.encoderNativeSampleLifetimeSamples > 0 ||
        native.encoderNativeAdapterLuid != null ||
        native.encoderMaxQueueDepth > 0 ||
        native.hasWebrtcRawSenderBoundaryDiagnostics ||
        native.webrtcVideoBroadcasterSamples > 0 ||
        framesDroppedBeforeEncodeMax != null ||
        framesDroppedByEncoderMax != null;
  }

  String get senderHandoffDiagnosticsLabel {
    final native = nativeDiagnostics;
    final missing = senderHandoffDiagnosticMissingFields;
    final missingLabel = missing.isEmpty ? 'none' : missing.join(', ');
    return 'on_frame_call='
        '${_milliseconds(native.averageGameCaptureDeliveryOnFrameCallMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryOnFrameCallMs)} '
        'native_age='
        '${_milliseconds(native.averageGameCaptureNativeNv12ConversionStartAgeMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12ConversionStartAgeMs)} '
        'adapter=consumer:${native.gameCaptureConsumerAdapterLuid ?? 'unknown'} '
        'source:${native.gameCaptureSourceAdapterLuid ?? 'unknown'} '
        'cross:${native.gameCaptureCrossAdapterSuspected ?? 'unknown'} '
        'queue_wait='
        '${_milliseconds(native.averageGameCaptureDeliveryQueueWaitMs)}/'
        '${_milliseconds(native.maxGameCaptureDeliveryQueueWaitMs)} '
        'source_submit='
        '${_milliseconds(native.averageGameCaptureSourceToSubmitMs)}/'
        '${_milliseconds(native.maxGameCaptureSourceToSubmitMs)} '
        'delivery_depth:${native.gameCaptureDeliveryQueueDepth ?? '?'} '
        'native_ready=policy:${native.gameCaptureNativeNv12ReadyPolicy ?? 'unknown'} '
        'ready_drain:${native.gameCaptureNativeNv12ReadyDrainDepth ?? '?'} '
        'ownership:${native.gameCaptureNativeNv12FrameOwnership ?? 'unknown'} '
        'owned_copy:${native.gameCaptureNativeNv12OwnedCopies} '
        '${_milliseconds(native.averageGameCaptureNativeNv12OwnedCopyMs)}/'
        '${_milliseconds(native.maxGameCaptureNativeNv12OwnedCopyMs)} '
        'fence:${native.gameCaptureNativeNv12FenceAvailable ?? '?'} '
        'signaled:${native.gameCaptureNativeNv12FenceSignaledFrames} '
        'not_ready:${native.gameCaptureNativeNv12NotReadyPolls} '
        'ready_dropped:${native.gameCaptureNativeNv12ReadyDroppedFrames} '
        'failures:${native.gameCaptureNativeNv12Failures} '
        'cpu_i420:${native.encoderCpuI420InputFrames} '
        'mf=total:${_milliseconds(native.averageEncoderTotalMs)}/'
        '${_milliseconds(native.maxEncoderTotalMs)} '
        'source:${native.encoderNativeSourceMode ?? 'unknown'}/'
        '${native.encoderNativeSourceFormat ?? '?'} '
        'source_age:${_milliseconds(native.averageEncoderNativeSourceAgeMs)}/'
        '${_milliseconds(native.maxEncoderNativeSourceAgeMs)} '
        'buffer_age:${_milliseconds(native.averageEncoderNativeBufferAgeMs)}/'
        '${_milliseconds(native.maxEncoderNativeBufferAgeMs)} '
        'sample_lifetime:${_milliseconds(native.averageEncoderNativeSampleLifetimeMs)}/'
        '${_milliseconds(native.maxEncoderNativeSampleLifetimeMs)} '
        'adapter:${native.encoderNativeAdapterLuid ?? 'unknown'} '
        'fence_wait:${_milliseconds(native.averageEncoderNativeReadyFenceWaitMs)}/'
        '${_milliseconds(native.maxEncoderNativeReadyFenceWaitMs)} '
        'process_input:${_milliseconds(native.averageEncoderProcessInputMs)}/'
        '${_milliseconds(native.maxEncoderProcessInputMs)} '
        'process_output:${_milliseconds(native.averageEncoderProcessOutputMs)}/'
        '${_milliseconds(native.maxEncoderProcessOutputMs)} '
        'encoded_callback:${_milliseconds(native.averageEncoderEncodedCallbackMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackMs)} '
        'callback_wait:${_milliseconds(native.averageEncoderEncodedCallbackQueueWaitMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackQueueWaitMs)} '
        'callback_enqueue:${_milliseconds(native.averageEncoderEncodedCallbackEnqueueMs)}/'
        '${_milliseconds(native.maxEncoderEncodedCallbackEnqueueMs)} '
        'callback_async:${native.encoderEncodedCallbackAsyncFrames} '
        'callback_queue_max:${native.encoderMaxEncodedCallbackQueueDepth} '
        'callback_drops_max:${native.encoderMaxEncodedCallbackDrops} '
        'callback_outputs_max:${native.encoderMaxEncodedCallbackOutputs} '
        'queue_max:${native.encoderMaxQueueDepth} '
        'retained_max:${native.encoderMaxRetainedSamples} '
        'encoded_outputs_max:${native.encoderMaxEncodedOutputs} '
        'webrtc_raw_sender:${native.webrtcRawSenderBoundaryLabel} '
        'sender_drops=before_encode:${framesDroppedBeforeEncodeMax ?? '?'} '
        'by_encoder:${framesDroppedByEncoderMax ?? '?'} '
        'frames=${framesCapturedMax ?? '?'}/${framesEncodedMax ?? '?'}/'
        '${framesSentMax ?? '?'} '
        'missing=[$missingLabel]';
  }

  Map<String, Object?> get senderHandoffDiagnosticsJson {
    final native = nativeDiagnostics;
    return {
      'available': hasSenderHandoffDiagnostics,
      'missingFields': senderHandoffDiagnosticMissingFields,
      'liveOnFrame': {
        'averageMs': native.averageGameCaptureDeliveryOnFrameCallMs,
        'maxMs': native.maxGameCaptureDeliveryOnFrameCallMs,
        'samples': native.gameCaptureDeliveryOnFrameCallSamples,
      },
      'nativeFrameAgeAtConversionStart': {
        'averageMs': native.averageGameCaptureNativeNv12ConversionStartAgeMs,
        'maxMs': native.maxGameCaptureNativeNv12ConversionStartAgeMs,
        'samples': native.gameCaptureNativeNv12ConversionStartAgeSamples,
      },
      'deliveryQueueWait': {
        'averageMs': native.averageGameCaptureDeliveryQueueWaitMs,
        'maxMs': native.maxGameCaptureDeliveryQueueWaitMs,
        'samples': native.gameCaptureDeliveryQueueWaitSamples,
        'queueDepth': native.gameCaptureDeliveryQueueDepth,
      },
      'sourceToSubmit': {
        'averageMs': native.averageGameCaptureSourceToSubmitMs,
        'maxMs': native.maxGameCaptureSourceToSubmitMs,
        'samples': native.gameCaptureSourceToSubmitSamples,
      },
      'adapter': {
        'consumerLuid': native.gameCaptureConsumerAdapterLuid,
        'consumerVendorId': native.gameCaptureConsumerAdapterVendorId,
        'consumerDeviceId': native.gameCaptureConsumerAdapterDeviceId,
        'sourceLuid': native.gameCaptureSourceAdapterLuid,
        'crossAdapterSuspected': native.gameCaptureCrossAdapterSuspected,
      },
      'nativeNv12Ready': {
        'policy': native.gameCaptureNativeNv12ReadyPolicy,
        'fenceAvailable': native.gameCaptureNativeNv12FenceAvailable,
        'fenceSignaled': native.gameCaptureNativeNv12FenceSignaledFrames,
        'fenceReady': native.gameCaptureNativeNv12FenceReadyFrames,
        'fenceSignalFailures': native.gameCaptureNativeNv12FenceSignalFailures,
        'notReadyPolls': native.gameCaptureNativeNv12NotReadyPolls,
        'readyDrainDepth': native.gameCaptureNativeNv12ReadyDrainDepth,
        'frameOwnership': native.gameCaptureNativeNv12FrameOwnership,
        'ownedCopies': native.gameCaptureNativeNv12OwnedCopies,
        'averageOwnedCopyMs': native.averageGameCaptureNativeNv12OwnedCopyMs,
        'maxOwnedCopyMs': native.maxGameCaptureNativeNv12OwnedCopyMs,
        'ownedCopySamples': native.gameCaptureNativeNv12OwnedCopySamples,
        'readyDropped': native.gameCaptureNativeNv12ReadyDroppedFrames,
        'readyDroppedFresh':
            native.gameCaptureNativeNv12ReadyDroppedFreshFrames,
        'submitted': native.gameCaptureNativeNv12SubmittedFrames,
        'failures': native.gameCaptureNativeNv12Failures,
        'cpuFallbackFrames': native.gameCaptureCpuFallbackFrames,
        'staleBeforeQueue': native.gameCaptureNativeNv12StaleBeforeQueueFrames,
      },
      'mediaFoundation': {
        'averageTotalMs': native.averageEncoderTotalMs,
        'maxTotalMs': native.maxEncoderTotalMs,
        'slowSamples': native.encoderSlowFrameCount,
        'samples': native.encoderSampleCount,
        'inputPath': native.encoderInputPathLabel,
        'nativeInputFrames': native.encoderNativeInputFrames,
        'cpuI420InputFrames': native.encoderCpuI420InputFrames,
        'nativeSampleFailures': native.encoderNativeSampleFailures,
        'nativeReadyFenceFrames': native.encoderNativeReadyFenceFrames,
        'nativeReadyFenceTimeoutFrames':
            native.encoderNativeReadyFenceTimeoutFrames,
        'averageNativeReadyFenceWaitMs':
            native.averageEncoderNativeReadyFenceWaitMs,
        'maxNativeReadyFenceWaitMs': native.maxEncoderNativeReadyFenceWaitMs,
        'nativeReadyFenceWaitSamples':
            native.encoderNativeReadyFenceWaitSamples,
        'nativeSourceMode': native.encoderNativeSourceMode,
        'nativeSourceFormat': native.encoderNativeSourceFormat,
        'nativeSourceFrameIndex': native.encoderNativeSourceFrameIndex,
        'averageNativeSourceAgeMs': native.averageEncoderNativeSourceAgeMs,
        'maxNativeSourceAgeMs': native.maxEncoderNativeSourceAgeMs,
        'nativeSourceAgeSamples': native.encoderNativeSourceAgeSamples,
        'averageNativeSourceAgeAtCreateMs':
            native.averageEncoderNativeSourceAgeAtCreateMs,
        'maxNativeSourceAgeAtCreateMs':
            native.maxEncoderNativeSourceAgeAtCreateMs,
        'averageNativeBufferAgeMs': native.averageEncoderNativeBufferAgeMs,
        'maxNativeBufferAgeMs': native.maxEncoderNativeBufferAgeMs,
        'nativeBufferAgeSamples': native.encoderNativeBufferAgeSamples,
        'averageNativeSampleLifetimeMs':
            native.averageEncoderNativeSampleLifetimeMs,
        'maxNativeSampleLifetimeMs': native.maxEncoderNativeSampleLifetimeMs,
        'nativeSampleLifetimeSamples':
            native.encoderNativeSampleLifetimeSamples,
        'nativeAdapterLuid': native.encoderNativeAdapterLuid,
        'nativeAdapterVendorId': native.encoderNativeAdapterVendorId,
        'nativeAdapterDeviceId': native.encoderNativeAdapterDeviceId,
        'averageProcessInputMs': native.averageEncoderProcessInputMs,
        'maxProcessInputMs': native.maxEncoderProcessInputMs,
        'processInputSamples': native.encoderProcessInputSamples,
        'averageProcessOutputMs': native.averageEncoderProcessOutputMs,
        'maxProcessOutputMs': native.maxEncoderProcessOutputMs,
        'processOutputSamples': native.encoderProcessOutputSamples,
        'averageEncodedCallbackMs': native.averageEncoderEncodedCallbackMs,
        'maxEncodedCallbackMs': native.maxEncoderEncodedCallbackMs,
        'encodedCallbackSamples': native.encoderEncodedCallbackSamples,
        'averageEncodedCallbackQueueWaitMs':
            native.averageEncoderEncodedCallbackQueueWaitMs,
        'maxEncodedCallbackQueueWaitMs':
            native.maxEncoderEncodedCallbackQueueWaitMs,
        'encodedCallbackQueueWaitSamples':
            native.encoderEncodedCallbackQueueWaitSamples,
        'averageEncodedCallbackEnqueueMs':
            native.averageEncoderEncodedCallbackEnqueueMs,
        'maxEncodedCallbackEnqueueMs':
            native.maxEncoderEncodedCallbackEnqueueMs,
        'encodedCallbackEnqueueSamples':
            native.encoderEncodedCallbackEnqueueSamples,
        'encodedCallbackAsyncFrames': native.encoderEncodedCallbackAsyncFrames,
        'encodedCallbackQueueMax': native.encoderMaxEncodedCallbackQueueDepth,
        'encodedCallbackDropsMax': native.encoderMaxEncodedCallbackDrops,
        'encodedCallbackOutputsMax': native.encoderMaxEncodedCallbackOutputs,
        'queueMax': native.encoderMaxQueueDepth,
        'retainedSamplesMax': native.encoderMaxRetainedSamples,
        'encodedOutputsMax': native.encoderMaxEncodedOutputs,
        'outputFrames': native.encoderOutputFrames,
        'outputBytes': native.encoderOutputBytes,
        'stage': native.encoderStageLabel,
      },
      'webrtcRawSenderBoundary': {
        'available': native.hasWebrtcRawSenderBoundaryDiagnostics,
        'sourceOnFrame': {
          'averageMs': native.averageWebrtcSourceOnFrameMs,
          'maxMs': native.maxWebrtcSourceOnFrameMs,
          'samples': native.webrtcSourceOnFrameSamples,
          'averageBroadcastMs': native.averageWebrtcSourceBroadcastMs,
          'maxBroadcastMs': native.maxWebrtcSourceBroadcastMs,
          'adapterDrops': native.webrtcSourceAdapterDrops,
          'scaledFrames': native.webrtcSourceScaledFrames,
        },
        'videoBroadcaster': {
          'averageMs': native.averageWebrtcVideoBroadcasterMs,
          'maxMs': native.maxWebrtcVideoBroadcasterMs,
          'samples': native.webrtcVideoBroadcasterSamples,
          'averageLockWaitMs': native.averageWebrtcVideoBroadcasterLockWaitMs,
          'maxLockWaitMs': native.maxWebrtcVideoBroadcasterLockWaitMs,
          'averageSinkDispatchMs':
              native.averageWebrtcVideoBroadcasterSinkDispatchMs,
          'maxSinkDispatchMs': native.maxWebrtcVideoBroadcasterSinkDispatchMs,
          'maxSingleSinkMs': native.maxWebrtcVideoBroadcasterSingleSinkMs,
          'slowSinkId': native.webrtcVideoBroadcasterSlowSinkId,
          'slowSinkMs': native.webrtcVideoBroadcasterSlowSinkMs,
          'slowSinkLabel': native.webrtcVideoBroadcasterSlowSinkLabel,
          'slowestSinkId': native.webrtcVideoBroadcasterSlowestSinkId,
          'slowestSinkMs': native.webrtcVideoBroadcasterSlowestSinkMs,
          'slowestSinkAverageMs':
              native.webrtcVideoBroadcasterSlowestSinkAverageMs,
          'slowestSinkFrames': native.webrtcVideoBroadcasterSlowestSinkFrames,
          'slowestSinkLabel': native.webrtcVideoBroadcasterSlowestSinkLabel,
          'sinkCount': native.webrtcVideoBroadcasterSinkCount,
          'maxSinkCount': native.webrtcVideoBroadcasterMaxSinkCount,
          'activeSinks': native.webrtcVideoBroadcasterActiveSinks,
          'inactiveSinks': native.webrtcVideoBroadcasterInactiveSinks,
          'requestedSinks': native.webrtcVideoBroadcasterRequestedSinks,
          'blackFrameSinks': native.webrtcVideoBroadcasterBlackFrameSinks,
          'rotationAppliedSinks':
              native.webrtcVideoBroadcasterRotationAppliedSinks,
          'inactiveNativeSinkBypassReported':
              native.webrtcVideoBroadcasterInactiveNativeSinkBypassReported,
          'inactiveNativeSinksBypassed':
              native.webrtcVideoBroadcasterInactiveNativeSinksBypassed,
          'inactiveNativeSinksBypassedLast':
              native.webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
          'sinkRoster': native.webrtcVideoBroadcasterSinkRoster,
          'blackSinks': native.webrtcVideoBroadcasterBlackSinks,
          'rotationDiscards': native.webrtcVideoBroadcasterRotationDiscards,
          'updateRectCleared': native.webrtcVideoBroadcasterUpdateRectCleared,
          'discardedFrames': native.webrtcVideoBroadcasterDiscardedFrames,
        },
        'videoStreamEncoder': {
          'averagePostToOnFrameMs': native.averageWebrtcVsePostToOnFrameMs,
          'maxPostToOnFrameMs': native.maxWebrtcVsePostToOnFrameMs,
          'averageOnFrameMs': native.averageWebrtcVseOnFrameMs,
          'maxOnFrameMs': native.maxWebrtcVseOnFrameMs,
          'onFrameSamples': native.webrtcVseOnFrameSamples,
          'queueOverloadDrops': native.webrtcVseQueueOverloadDrops,
          'encoderQueueDrops': native.webrtcVseEncoderQueueDrops,
          'cwndDrops': native.webrtcVseCwndDrops,
          'badTimestampDrops': native.webrtcVseBadTimestampDrops,
          'averageMaybeEncodeMs': native.averageWebrtcVseMaybeEncodeMs,
          'maxMaybeEncodeMs': native.maxWebrtcVseMaybeEncodeMs,
          'maybeEncodeSamples': native.webrtcVseMaybeEncodeSamples,
          'averageEncodeFrameMs': native.averageWebrtcVseEncodeFrameMs,
          'maxEncodeFrameMs': native.maxWebrtcVseEncodeFrameMs,
          'encodeFrameSamples': native.webrtcVseEncodeFrameSamples,
          'averageVideoEncoderEncodeMs':
              native.averageWebrtcVideoEncoderEncodeMs,
          'maxVideoEncoderEncodeMs': native.maxWebrtcVideoEncoderEncodeMs,
          'videoEncoderEncodeSamples': native.webrtcVideoEncoderEncodeSamples,
          'encodeFailures': native.webrtcVseEncodeFailures,
          'encodeSkippedBeforeEncoder':
              native.webrtcVseEncodeSkippedBeforeEncoder,
        },
        'label': native.webrtcRawSenderBoundaryLabel,
      },
      'senderCounters': {
        'framesCapturedMax': framesCapturedMax,
        'framesEncodedMax': framesEncodedMax,
        'framesSentMax': framesSentMax,
        'framesDroppedBeforeEncodeMax': framesDroppedBeforeEncodeMax,
        'framesDroppedByEncoderMax': framesDroppedByEncoderMax,
      },
      'label': senderHandoffDiagnosticsLabel,
    };
  }

  Map<String, Object?> toJson() {
    return {
      'senderSampleCount': senderSampleCount,
      'preEncodeSampleCount': preEncodeSampleCount,
      'screenShareProfileDetails': screenShareProfileDetails.toList()..sort(),
      'senderCodecs': senderCodecs.toList()..sort(),
      'encoderImplementations': encoderImplementations.toList()..sort(),
      'hardwareEncodeStates': _sortedBoolList(hardwareEncodeStates),
      'averageFps': averageFps,
      'minimumFps': minimumFps,
      'averageCaptureFps': averageCaptureFps,
      'minimumCaptureFps': minimumCaptureFps,
      'averageEncodeFps': averageEncodeFps,
      'minimumEncodeFps': minimumEncodeFps,
      'averageSendFps': averageSendFps,
      'minimumSendFps': minimumSendFps,
      'averageBitrateBps': averageBitrateBps,
      'averageAvailableOutgoingBitrateBps': averageAvailableOutgoingBitrateBps,
      'minimumAvailableOutgoingBitrateBps': minimumAvailableOutgoingBitrateBps,
      'maximumAvailableOutgoingBitrateBps': maximumAvailableOutgoingBitrateBps,
      'requestedWidth': requestedWidth,
      'requestedHeight': requestedHeight,
      'requestedFps': requestedFps,
      'requestedBitrateBps': requestedBitrateBps,
      'preEncodeWidth': preEncodeWidth,
      'preEncodeHeight': preEncodeHeight,
      'encodedWidth': encodedWidth,
      'encodedHeight': encodedHeight,
      'averageEncodeTimeMs': averageEncodeTimeMs,
      'maxEncodeTimeMs': maxEncodeTimeMs,
      'averagePacketSendDelayMs': averagePacketSendDelayMs,
      'maxPacketSendDelayMs': maxPacketSendDelayMs,
      'maxPacketLossPercent': maxPacketLossPercent,
      'maxRoundTripTimeMs': maxRoundTripTimeMs,
      'maxNackCount': maxNackCount,
      'framesCapturedMax': framesCapturedMax,
      'framesEncodedMax': framesEncodedMax,
      'framesSentMax': framesSentMax,
      'framesDroppedBeforeEncodeMax': framesDroppedBeforeEncodeMax,
      'framesDroppedByEncoderMax': framesDroppedByEncoderMax,
      'capturePipeline': capturePipelineLabel,
      'framePacing': framePacing.toJson(),
      'senderHandoffDiagnostics': senderHandoffDiagnosticsJson,
      'nativeDiagnostics': nativeDiagnostics.toJson(),
      'diagnosticCoverage':
          StreamDiagnosticCoverageMatrix.forSummary(this).toJson(),
      'qualityLimitationReasons': qualityLimitationReasons.toList()..sort(),
      'activeLayers': activeLayers.toList()..sort(),
    };
  }
}

VoipTrackDiagnostics? _bestSenderTrack(VoipCallDiagnosticsSnapshot snapshot) {
  final candidates = snapshot.tracks.where(
    (track) =>
        track.type == VoipStreamType.screenshare &&
        track.direction == VoipDiagnosticsTrackDirection.sender,
  );
  VoipTrackDiagnostics? best;
  var bestPixels = -1;
  for (final track in candidates) {
    final pixels = (track.width ?? 0) * (track.height ?? 0);
    if (pixels > bestPixels) {
      best = track;
      bestPixels = pixels;
    }
  }
  return best;
}

VoipTrackDiagnostics? _bestReceiverTrack(VoipCallDiagnosticsSnapshot snapshot) {
  final candidates = snapshot.tracks.where(
    (track) =>
        track.type == VoipStreamType.screenshare &&
        track.direction == VoipDiagnosticsTrackDirection.receiver,
  );
  VoipTrackDiagnostics? best;
  var bestPixels = -1;
  for (final track in candidates) {
    final pixels = (track.width ?? 0) * (track.height ?? 0);
    if (pixels > bestPixels) {
      best = track;
      bestPixels = pixels;
    }
  }
  return best;
}

List<_FrameCounterSample> _counterSamples(
  List<StreamTestSample> samples,
  VoipTrackDiagnostics? Function(VoipCallDiagnosticsSnapshot snapshot)
      trackSelector,
  int? Function(VoipTrackDiagnostics track) counterSelector, {
  bool Function(VoipTrackDiagnostics track)? include,
}) {
  final counterSamples = <_FrameCounterSample>[];
  for (final sample in samples) {
    final track = trackSelector(sample.snapshot);
    if (track == null || !(include?.call(track) ?? true)) {
      continue;
    }
    counterSamples.add(
      _FrameCounterSample(
        collectedAt: sample.snapshot.collectedAt,
        frameCount: counterSelector(track),
      ),
    );
  }
  return counterSamples;
}

Duration _measurementDuration({
  required List<StreamTestSample> samples,
  DateTime? measurementStartedAt,
  DateTime? measurementEndedAt,
}) {
  var durationMs = 0;
  if (measurementStartedAt != null && measurementEndedAt != null) {
    durationMs = max(
      durationMs,
      measurementEndedAt.difference(measurementStartedAt).inMilliseconds,
    );
  }
  for (final sample in samples) {
    durationMs = max(durationMs, sample.elapsed.inMilliseconds);
  }
  return Duration(milliseconds: max(0, durationMs));
}

List<_StreamTestWindowSpec> _temporalWindowSpecs(Duration totalDuration) {
  final totalMs = max(1, totalDuration.inMilliseconds);
  Duration ms(int value) =>
      Duration(milliseconds: value.clamp(0, totalMs).toInt());
  if (totalMs < 12000) {
    final midpoint = (totalMs / 2).round();
    return [
      _StreamTestWindowSpec(
        label: 'early',
        start: Duration.zero,
        end: ms(midpoint),
      ),
      _StreamTestWindowSpec(
        label: 'late',
        start: ms(midpoint),
        end: ms(totalMs),
      ),
    ];
  }
  final firstCut = (totalMs / 3).round();
  final secondCut = (totalMs * 2 / 3).round();
  final tailStart = max(0, totalMs - 10000);
  return [
    _StreamTestWindowSpec(
      label: 'early',
      start: Duration.zero,
      end: ms(firstCut),
    ),
    _StreamTestWindowSpec(
      label: 'middle',
      start: ms(firstCut),
      end: ms(secondCut),
    ),
    _StreamTestWindowSpec(
      label: 'late',
      start: ms(secondCut),
      end: ms(totalMs),
    ),
    _StreamTestWindowSpec(
      label: 'tail_10s',
      start: ms(tailStart),
      end: ms(totalMs),
    ),
  ];
}

List<String> _lateDegradationSignals({
  required List<StreamTestTimeWindowSummary> windows,
  required double targetFps,
}) {
  final early = _temporalWindowByLabel(windows, 'early');
  final late = _temporalWindowByLabel(windows, 'late');
  final tail = _temporalWindowByLabel(windows, 'tail_10s') ?? late;
  if (early == null || tail == null) {
    return const [];
  }
  final signals = <String>[];
  final frameBudgetMs = targetFps > 0 ? 1000 / targetFps : null;
  final earlySentFps = early.summary.averageSendFps;
  final tailSentFps = tail.summary.averageSendFps;
  if (targetFps > 0 &&
      earlySentFps != null &&
      tailSentFps != null &&
      earlySentFps >= targetFps * 0.80 &&
      tailSentFps < earlySentFps * 0.85) {
    signals.add(
      'send FPS fell from ${earlySentFps.toStringAsFixed(1)} in the early window to ${tailSentFps.toStringAsFixed(1)} in ${tail.label}',
    );
  }

  final earlySentP95 = early.framePacing.sent.p95IntervalMs;
  final tailSentP95 = tail.framePacing.sent.p95IntervalMs;
  if (earlySentP95 != null && tailSentP95 != null && frameBudgetMs != null) {
    final gapThreshold = max(frameBudgetMs * 1.25, earlySentP95 * 1.25);
    if (tailSentP95 > gapThreshold) {
      signals.add(
        'sent p95 gap grew from ${earlySentP95.toStringAsFixed(0)}ms early to ${tailSentP95.toStringAsFixed(0)}ms in ${tail.label}',
      );
    }
  }

  final earlySentMax = early.framePacing.sent.maxIntervalMs;
  final tailSentMax = tail.framePacing.sent.maxIntervalMs;
  if (earlySentMax != null && tailSentMax != null && frameBudgetMs != null) {
    final maxGapThreshold = max(frameBudgetMs * 2.0, earlySentMax * 1.5);
    if (tailSentMax > maxGapThreshold) {
      signals.add(
        'sent max gap grew from ${earlySentMax.toStringAsFixed(0)}ms early to ${tailSentMax.toStringAsFixed(0)}ms in ${tail.label}',
      );
    }
  }

  final gameCapture = tail.gameCapture;
  if (gameCapture != null && gameCapture.hasEvidence) {
    final earlyGameCapture = early.gameCapture;
    final tailDeliveryWallMax = gameCapture.maxDeliveryWallDeltaMs;
    final earlyDeliveryWallMax = earlyGameCapture?.maxDeliveryWallDeltaMs;
    if (tailDeliveryWallMax != null && frameBudgetMs != null) {
      final deliveryWallThreshold = max(
        frameBudgetMs * 1.75,
        (earlyDeliveryWallMax ?? frameBudgetMs) * 1.25,
      );
      if (tailDeliveryWallMax > deliveryWallThreshold) {
        signals.add(
          '${tail.label} D3D11 delivery wall gap reached '
          '${tailDeliveryWallMax.toStringAsFixed(0)}ms '
          'after early max '
          '${(earlyDeliveryWallMax ?? 0).toStringAsFixed(0)}ms',
        );
      }
    }
    final readbackDropPressure = gameCapture.readbackLatencyDroppedDelta > 0 &&
        gameCapture.maxReadbackLatencyFrames >= 3;
    final staleDropPressure = gameCapture.readbackStaleDroppedDelta >= 20 &&
        gameCapture.maxReadbackLatencyFrames >= 3;
    if (readbackDropPressure || staleDropPressure) {
      signals.add(
        '${tail.label} D3D11 readback pressure: latency-drop +${gameCapture.readbackLatencyDroppedDelta}, stale +${gameCapture.readbackStaleDroppedDelta}, not-ready +${gameCapture.readbackNotReadyDelta}, max latency ${gameCapture.maxReadbackLatencyFrames} frames',
      );
    }
  }
  return signals;
}

StreamTestTimeWindowSummary? _temporalWindowByLabel(
  List<StreamTestTimeWindowSummary> windows,
  String label,
) {
  for (final window in windows) {
    if (window.label == label) {
      return window;
    }
  }
  return null;
}

int _counterDelta(int previous, int current) {
  if (current >= previous) {
    return current - previous;
  }
  return current;
}

Map<String, Object?> _profileToJson(ScreenShareProfileConfig profile) {
  return {
    'storageKey': profile.storageKey,
    'label': profile.label,
    'description': profile.description,
    'profile': profile.profile?.name,
    'codec': profile.codec,
    'useSimulcast': profile.useSimulcast,
    'hardwareEncodeFirst': profile.hardwareEncodeFirst,
    'advancedOverride': profile.advancedOverride,
    'mainLayer': _layerToJson(profile.mainLayer),
    'lowLayer':
        profile.lowLayer == null ? null : _layerToJson(profile.lowLayer!),
  };
}

Map<String, Object?> _layerToJson(ScreenShareVideoLayer layer) {
  return {
    'width': layer.width,
    'height': layer.height,
    'maxFramerate': layer.maxFramerate,
    'targetFramerate': layer.targetFramerateForScoring,
    'maxBitrateBps': layer.maxBitrateBps,
    'minBitrateBps': layer.minBitrateBps,
  };
}

Map<String, Object?> _trackToJson(VoipTrackDiagnostics track) {
  return {
    'streamId': track.streamId,
    'label': track.label,
    'type': track.type.name,
    'direction': track.direction.name,
    'receivePriority': track.receivePriority?.name,
    'requestedWidth': track.requestedWidth,
    'requestedHeight': track.requestedHeight,
    'requestedFps': track.requestedFps,
    'requestedBitrateBps': track.requestedBitrateBps,
    'preEncodeWidth': track.preEncodeWidth,
    'preEncodeHeight': track.preEncodeHeight,
    'width': track.width,
    'height': track.height,
    'fps': track.fps,
    'captureFps': track.captureFps,
    'encodeFps': track.encodeFps,
    'sendFps': track.sendFps,
    'decodeFps': track.decodeFps,
    'renderFps': track.renderFps,
    'bitrateBps': track.bitrateBps,
    'targetBitrateBps': track.targetBitrateBps,
    'availableOutgoingBitrateBps': track.availableOutgoingBitrateBps,
    'availableIncomingBitrateBps': track.availableIncomingBitrateBps,
    'retransmitBitrateBps': track.retransmitBitrateBps,
    'packetsLost': track.packetsLost,
    'packetsSent': track.packetsSent,
    'packetsReceived': track.packetsReceived,
    'nackCount': track.nackCount,
    'pliCount': track.pliCount,
    'firCount': track.firCount,
    'packetLossPercent': track.packetLossPercent,
    'jitterMs': track.jitterMs,
    'jitterBufferDelayMs': track.jitterBufferDelayMs,
    'roundTripTimeMs': track.roundTripTimeMs,
    'codec': track.codec,
    'qualityLimitationReason': track.qualityLimitationReason,
    'framesSent': track.framesSent,
    'framesCaptured': track.framesCaptured,
    'framesEncoded': track.framesEncoded,
    'framesDecoded': track.framesDecoded,
    'framesReceived': track.framesReceived,
    'framesRendered': track.framesRendered,
    'framesDropped': track.framesDropped,
    'framesDroppedBeforeEncode': track.framesDroppedBeforeEncode,
    'framesDroppedByEncoder': track.framesDroppedByEncoder,
    'averageEncodeTimeMs': track.averageEncodeTimeMs,
    'averagePacketSendDelayMs': track.averagePacketSendDelayMs,
    'averageDecodeTimeMs': track.averageDecodeTimeMs,
    'qualityLimitationResolutionChanges':
        track.qualityLimitationResolutionChanges,
    'qualityLimitationDurations': track.qualityLimitationDurations,
    'rid': track.rid,
    'activeLayer': track.activeLayer,
    'encoderImplementation': track.encoderImplementation,
    'decoderImplementation': track.decoderImplementation,
    'hardwareEncodeActive': track.hardwareEncodeActive,
    'freezeCount': track.freezeCount,
    'pauseCount': track.pauseCount,
  };
}

double? _average(Iterable<double> values) {
  var total = 0.0;
  var count = 0;
  for (final value in values) {
    total += value;
    count++;
  }
  return count == 0 ? null : total / count;
}

double? _percentile(Iterable<double> values, double percentile) {
  final sorted = values.where((value) => value.isFinite).toList()..sort();
  if (sorted.isEmpty) {
    return null;
  }
  if (sorted.length == 1) {
    return sorted.first;
  }

  final bounded = max(0.0, min(1.0, percentile));
  final position = (sorted.length - 1) * bounded;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) {
    return sorted[lower];
  }
  final weight = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * weight;
}

int? _averageInt(Iterable<int> values) {
  var total = 0;
  var count = 0;
  for (final value in values) {
    total += value;
    count++;
  }
  return count == 0 ? null : (total / count).round();
}

double? _maxDouble(Iterable<double> values) {
  double? result;
  for (final value in values) {
    result = result == null ? value : max(result, value);
  }
  return result;
}

double? _minDouble(Iterable<double> values) {
  double? result;
  for (final value in values) {
    result = result == null ? value : min(result, value);
  }
  return result;
}

int? _maxInt(Iterable<int> values) {
  int? result;
  for (final value in values) {
    result = result == null ? value : max(result, value);
  }
  return result;
}

int? _minInt(Iterable<int> values) {
  int? result;
  for (final value in values) {
    result = result == null ? value : min(result, value);
  }
  return result;
}

List<bool> _sortedBoolList(Iterable<bool> values) {
  final sorted = values.toList();
  sorted.sort((left, right) {
    if (left == right) {
      return 0;
    }
    return left ? 1 : -1;
  });
  return sorted;
}

String _hostLoadCompactLabel(StreamTestHostLoadReport report) {
  if (!report.available) {
    return 'unavailable (${report.unavailableReason ?? 'no samples'})';
  }
  return 'samples=${report.samples.length}; '
      'CPU avg/max=${_hostLoadMetricPercent(report.systemCpuPercent)}; '
      'RAM avg/max=${_hostLoadMetricPercent(report.memoryUsedPercent)}; '
      'GPU 3D avg/max=${_hostLoadMetricPercent(report.gpu3dPercent)}; '
      'Video Encode avg/max='
      '${_hostLoadMetricPercent(report.gpuVideoEncodePercent)}';
}

String _hostLoadMarkdown(StreamTestHostLoadReport report) {
  final buffer = StringBuffer();
  if (!report.available) {
    buffer
      ..writeln(
        'Host/system load diagnostics were unavailable: '
        '${report.unavailableReason ?? 'no samples'}.',
      )
      ..writeln();
    return buffer.toString();
  }
  if (report.unavailableReason != null) {
    buffer
      ..writeln(
        'Host/system load diagnostics were collected with warning: '
        '${report.unavailableReason}.',
      )
      ..writeln();
  }
  buffer
    ..writeln('- Samples: ${report.samples.length}')
    ..writeln('- Interval: ${report.sampleIntervalMs}ms')
    ..writeln(
      '- Range: ${report.startedAtUtc?.toIso8601String() ?? '?'} to '
      '${report.endedAtUtc?.toIso8601String() ?? '?'}',
    )
    ..writeln(
      '- Missing metrics: '
      '${report.missingMetricLabels.isEmpty ? 'none' : report.missingMetricLabels.join(', ')}',
    )
    ..writeln()
    ..writeln(
      '| Metric | Samples | Average | Max | Min |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: |');
  _writeHostLoadMetricRow(
    buffer,
    label: 'System CPU',
    metric: report.systemCpuPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'Memory Used',
    metric: report.memoryUsedPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'Memory Available',
    metric: report.memoryAvailableMb,
    formatter: (value) => value == null ? '?' : '${value.toStringAsFixed(0)}MB',
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'App CPU',
    metric: report.appCpuPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'Target CPU',
    metric: report.targetCpuPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU 3D',
    metric: report.gpu3dPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Copy',
    metric: report.gpuCopyPercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Video Encode',
    metric: report.gpuVideoEncodePercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Compute',
    metric: report.gpuComputePercent,
    formatter: _percent,
  );
  _writeHostLoadMetricRow(
    buffer,
    label: 'GPU Dedicated Memory',
    metric: report.gpuDedicatedMemoryMb,
    formatter: (value) => value == null ? '?' : '${value.toStringAsFixed(0)}MB',
  );
  return buffer.toString();
}

void _writeHostLoadMetricRow(
  StringBuffer buffer, {
  required String label,
  required StreamTestHostLoadMetricSummary metric,
  required String Function(double? value) formatter,
}) {
  buffer.writeln(
    '| ${_markdownCell(label)} '
    '| ${metric.sampleCount} '
    '| ${formatter(metric.average)} '
    '| ${formatter(metric.maximum)} '
    '| ${formatter(metric.minimum)} |',
  );
}

String _hostLoadMetricPercent(StreamTestHostLoadMetricSummary metric) {
  return '${_percent(metric.average)}/${_percent(metric.maximum)}';
}

String _number(double? value) => value == null ? '?' : value.toStringAsFixed(1);

String _percent(double? value) =>
    value == null ? '?' : '${value.toStringAsFixed(1)}%';

String _ratioPercent(double? value) =>
    value == null ? '?' : '${(value * 100).toStringAsFixed(1)}%';

String _milliseconds(double? value) =>
    value == null ? '?' : '${value.toStringAsFixed(0)}ms';

String _bitrate(int? bitrateBps) {
  if (bitrateBps == null || bitrateBps <= 0) {
    return '?';
  }
  if (bitrateBps >= 1000000) {
    return '${(bitrateBps / 1000000).toStringAsFixed(1)} Mbps';
  }
  return '${(bitrateBps / 1000).toStringAsFixed(0)} kbps';
}

String _markdownCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String _markdownInline(String value) {
  return value.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _resolutionLabel(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 'unknown';
  }
  return '${width}x$height';
}

double? _pixelRatio(int? numeratorWidth, int? numeratorHeight,
    int? denominatorWidth, int? denominatorHeight) {
  if (numeratorWidth == null ||
      numeratorHeight == null ||
      denominatorWidth == null ||
      denominatorHeight == null ||
      numeratorWidth <= 0 ||
      numeratorHeight <= 0 ||
      denominatorWidth <= 0 ||
      denominatorHeight <= 0) {
    return null;
  }
  return (numeratorWidth * numeratorHeight) /
      (denominatorWidth * denominatorHeight);
}

String _megapixels(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return '?MP';
  }
  return '${(width * height / 1000000).toStringAsFixed(2)}MP';
}

String _ratioMultiplier(double? ratio) =>
    ratio == null ? '?' : '${ratio.toStringAsFixed(2)}x';

const _nativeDiagnosticLogNeedles = [
  'desktop capture options',
  'desktop capture cadence',
  'desktop capture frame cadence',
  'desktop capture frame timing',
  'desktop capture frame size',
  'desktop capture latest-frame pacer',
  'desktop capture pipeline',
  'desktop capture bridge start',
  'wgc frame timing',
  'window gdi frame timing',
  'media foundation h.264 encoder timing',
  'media foundation h.264 accepted',
  'media foundation h.264 did not accept',
  'media foundation h.264 initialized',
  'media foundation h.264 using async event drain',
  'game_capture_webrtc_source',
  'webrtc sender handoff',
];

final _captureOptionsPattern = RegExp(
  r'desktop capture options type=([^\s]+).*?\bmode=([^\s]+)',
  caseSensitive: false,
);
final _captureBridgePattern = RegExp(
  r'desktop capture bridge start source_type=([^\s]+)\s+requested_max=(\d+)x(\d+)\s+fps=([0-9.]+)(?:\s+capture_backend=([^\s]+))?',
  caseSensitive: false,
);
final _captureFrameSizePattern = RegExp(
  r'desktop capture frame size source=(\d+)x(\d+)\s+max=(\d+)x(\d+)\s+output=(\d+)x(\d+)\s+crop_region=([^\s]+)',
  caseSensitive: false,
);
final _captureCadencePattern = RegExp(
  r'desktop capture cadence target_delay_ms=([0-9.]+)\s+avg_capture_call_ms=([0-9.]+)\s+max_capture_call_ms=([0-9.]+)\s+scheduled_delay_ms=([0-9.]+)\s+calls=(\d+)(?:\s+submitted_fps=([0-9.]+))?(?:\s+temp_errors=(\d+))?(?:\s+permanent_errors=(\d+))?',
  caseSensitive: false,
);
final _captureFrameCadencePattern = RegExp(
  r'desktop capture frame cadence new_fps=([0-9.]+)\s+submitted_fps=([0-9.]+)\s+max_interval_ms=([0-9.]+)\s+p95_interval_ms=([0-9.]+)\s+duplicated_frames=(\d+)\s+stale_reuse=(\d+)\s+wait_timeouts=(\d+)\s+permanent_errors=(\d+)',
  caseSensitive: false,
);
final _captureFrameTimingPattern = RegExp(
  r'desktop capture frame timing avg_convert_ms=([0-9.]+)\s+avg_scale_ms=([0-9.]+)\s+avg_on_frame_ms=([0-9.]+)\s+avg_callback_ms=([0-9.]+)\s+max_callback_ms=([0-9.]+).*?\bframes=(\d+)',
  caseSensitive: false,
);
final _mediaFoundationTimingPattern = RegExp(
  r'media foundation h\.264 encoder timing.*?\btotal_ms=([0-9.]+).*?\bslow=(yes|no)',
  caseSensitive: false,
);
final _diagnosticMarkerTimestampPattern = RegExp(
  r'^\[?(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\]?',
);

final _keyValueTokenPattern = RegExp(r'\b([A-Za-z0-9_]+)=([^\s]+)');
final _privateDiagnosticKeyValuePattern = RegExp(
  r'\b(source_title|window_title|title|source_name|window_name|process_name|app_name|path|file_path|output_path|helper_path|proof_path)=("[^"]*"|[^\s]+)',
  caseSensitive: false,
);
final _privateDiagnosticPidPattern = RegExp(
  r'\b(pid|process_id|processId)=\d+\b',
  caseSensitive: false,
);
const _safeDiagnosticLabelPrefixes = <String>{
  'current-call',
};

String _redactedFreeformLabel(
  String value, {
  String fallback = '[REDACTED_LABEL]',
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }

  if (_safeDiagnosticLabelPrefixes.contains(trimmed)) {
    return trimmed;
  }

  final prefixMatch = RegExp(r'^([A-Za-z0-9 _.-]{1,40}):').firstMatch(trimmed);
  final prefix = prefixMatch?.group(1);
  if (prefix != null && _safeDiagnosticLabelPrefixes.contains(prefix)) {
    return '$prefix:[REDACTED]';
  }
  return fallback;
}

String _redactedRoomId(String value) => '[MATRIX_ROOM_ID]';

String _redactedDiagnosticMarker(String marker) {
  var redacted = Log.redactSensitiveInfo(marker);
  redacted = redacted.replaceAllMapped(
    _privateDiagnosticKeyValuePattern,
    (match) => '[REDACTED_FIELD]',
  );
  redacted = redacted.replaceAllMapped(
    _privateDiagnosticPidPattern,
    (match) => '[REDACTED_FIELD]',
  );
  return redacted.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

List<String> streamTestDiagnosticMarkersFromText(
  String text, {
  int? limit = streamTestDefaultDiagnosticLogMarkerLimit,
}) {
  return _extractDiagnosticLogMarkers(text, limit: limit);
}

String redactStreamTestDiagnosticMarker(String marker) =>
    _redactedDiagnosticMarker(marker);

List<String> _extractDiagnosticLogMarkers(
  String text, {
  required int? limit,
}) {
  if (text.trim().isEmpty || limit == 0) {
    return const [];
  }
  final matches = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    for (final marker in _expandDiagnosticLogMarkerLine(line)) {
      final normalized = marker.toLowerCase();
      if (_nativeDiagnosticLogNeedles.any(normalized.contains)) {
        matches.add(marker);
      }
    }
  }
  if (limit == null || matches.length <= limit) {
    return List.unmodifiable(matches);
  }
  return _capDiagnosticLogMarkers(matches, limit: limit);
}

List<String> _expandDiagnosticLogMarkerLines(List<String> markers) {
  if (markers.isEmpty) {
    return const [];
  }
  final expanded = <String>[];
  for (final marker in markers) {
    expanded.addAll(_expandDiagnosticLogMarkerLine(marker));
  }
  return List.unmodifiable(expanded);
}

List<String> _expandDiagnosticLogMarkerLine(String marker) {
  if (marker.trim().isEmpty) {
    return const [];
  }
  final matches = <String>[];
  for (final line in const LineSplitter().convert(marker)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    matches.add(trimmed);
  }
  return List.unmodifiable(matches);
}

List<String> _capDiagnosticLogMarkers(
  List<String> markers, {
  required int limit,
}) {
  if (limit <= 0 || markers.isEmpty) {
    return const [];
  }
  if (markers.length <= limit) {
    return List.unmodifiable(markers);
  }
  final selectedIndexes = <int>{};
  for (var index = markers.length - 1; index >= 0; index--) {
    if (markers[index].toLowerCase().contains('game_capture_webrtc_source')) {
      selectedIndexes.add(index);
      if (selectedIndexes.length >= limit) {
        break;
      }
    }
  }
  for (var index = markers.length - 1;
      index >= 0 && selectedIndexes.length < limit;
      index--) {
    selectedIndexes.add(index);
  }
  final orderedIndexes = selectedIndexes.toList(growable: false)..sort();
  return List.unmodifiable(orderedIndexes.map((index) => markers[index]));
}

List<String> _diagnosticMarkersForRange(
  List<String> markers, {
  required DateTime startedAt,
  required DateTime endedAt,
}) {
  markers = _expandDiagnosticLogMarkerLines(markers);
  final withTimestamps = markers
      .map((marker) => (marker: marker, timestamp: _markerTimestamp(marker)))
      .where((entry) => entry.timestamp != null)
      .toList(growable: false);
  if (withTimestamps.isEmpty) {
    return markers;
  }

  final start = startedAt.toUtc();
  final end = endedAt.toUtc();
  final filtered = <String>[];
  DateTime? inheritedTimestamp;
  for (final marker in markers) {
    final timestamp = _markerTimestamp(marker);
    if (timestamp != null) {
      inheritedTimestamp = timestamp;
    }
    final effectiveTimestamp = timestamp ?? inheritedTimestamp;
    if (effectiveTimestamp == null) {
      continue;
    }
    if (!effectiveTimestamp.isBefore(start) &&
        !effectiveTimestamp.isAfter(end)) {
      filtered.add(marker);
    }
  }
  return List.unmodifiable(filtered);
}

DateTime? _markerTimestamp(String marker) {
  final match = _diagnosticMarkerTimestampPattern.firstMatch(marker);
  if (match == null) {
    return null;
  }
  return DateTime.tryParse(match.group(1)!);
}

int? _intGroup(RegExpMatch match, int group) {
  final value = match.group(group);
  return value == null ? null : int.tryParse(value);
}

double? _doubleGroup(RegExpMatch match, int group) {
  final value = match.group(group);
  return value == null ? null : double.tryParse(value);
}

String? _stringGroup(RegExpMatch match, int group) {
  final value = match.group(group)?.trim();
  return value == null || value.isEmpty ? null : value;
}

bool? _boolGroup(RegExpMatch match, int group) {
  final value = _stringGroup(match, group)?.toLowerCase();
  if (value == null) {
    return null;
  }
  if (value == 'true' || value == '1' || value == 'yes') {
    return true;
  }
  if (value == 'false' || value == '0' || value == 'no') {
    return false;
  }
  return null;
}

String? _stringFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _intFromJson(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleFromJson(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

bool? _boolFromJson(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = value?.toString().toLowerCase().trim();
  if (text == 'true' || text == '1' || text == 'yes') {
    return true;
  }
  if (text == 'false' || text == '0' || text == 'no') {
    return false;
  }
  return null;
}

DateTime? _dateTimeFromJson(Object? value) {
  final text = _stringFromJson(value);
  return text == null ? null : DateTime.tryParse(text);
}

bool? _boolFromMarker(String marker, String key) {
  final value = _tokenFromMarker(marker, key)?.toLowerCase();
  if (value == null) {
    return null;
  }
  if (value == 'true' || value == '1' || value == 'yes') {
    return true;
  }
  if (value == 'false' || value == '0' || value == 'no') {
    return false;
  }
  return null;
}

double? _doubleFromMarker(String marker, String key) {
  final value = _tokenFromMarker(marker, key);
  return value == null ? null : double.tryParse(value);
}

int? _intFromMarker(String marker, String key) {
  final value = _tokenFromMarker(marker, key);
  return value == null ? null : int.tryParse(value);
}

String? _tokenFromMarker(String marker, String key) {
  final normalizedKey = key.toLowerCase();
  for (final match in _keyValueTokenPattern.allMatches(marker)) {
    if (match.group(1)?.toLowerCase() == normalizedKey) {
      final value = match.group(2)?.trim();
      return value == null || value.isEmpty ? null : value;
    }
  }
  return null;
}

_MarkerDimensions? _dimensionsFromMarker(String marker, String key) {
  final value = _tokenFromMarker(marker, key);
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final width = _intGroup(match, 1);
  final height = _intGroup(match, 2);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return _MarkerDimensions(width, height);
}

class _MarkerDimensions {
  const _MarkerDimensions(this.width, this.height);

  final int width;
  final int height;
}

String? _legacyBackendLabelFromOptions(String marker) {
  final normalized = marker.toLowerCase();
  final directx =
      normalized.contains('directx=1') || normalized.contains('directx=true');
  final crop = normalized.contains('crop_window=1') ||
      normalized.contains('crop_window=true');
  final wgcScreen = normalized.contains('wgc_screen=1') ||
      normalized.contains('wgc_screen=true');
  final wgcWindow = normalized.contains('wgc_window=1') ||
      normalized.contains('wgc_window=true');
  final wgcFallback = normalized.contains('wgc_fallback=1') ||
      normalized.contains('wgc_fallback=true');
  if (wgcScreen && wgcWindow && !directx && !crop && !wgcFallback) {
    return WindowsScreenCaptureBackendMode.wgcOnly.constraintValue;
  }
  if (directx && !crop && !wgcScreen && !wgcWindow) {
    return WindowsScreenCaptureBackendMode.directxOnly.constraintValue;
  }
  if (directx && crop && !wgcScreen && !wgcWindow) {
    return WindowsScreenCaptureBackendMode.windowCrop.constraintValue;
  }
  if (directx || crop || wgcScreen || wgcWindow || wgcFallback) {
    return WindowsScreenCaptureBackendMode.platformDefault.constraintValue;
  }
  return null;
}
