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

part 'stream_test_runner_receiver_probe.dart';
part 'stream_test_runner_reporting.dart';
part 'stream_test_runner_scoring.dart';
part 'stream_test_runner_diagnostics.dart';
part 'stream_test_runner_summary.dart';
part 'stream_test_runner_coverage.dart';

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
  Future<void> startReceiverProbe(StreamTestReceiverProbeConfig config);
  Future<StreamTestReceiverProbeResult> stopReceiverProbe();
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
    this.receiverProbe = const StreamTestReceiverProbeConfig(),
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
  final StreamTestReceiverProbeConfig receiverProbe;

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
      'receiverProbe': receiverProbe.toJson(),
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
        StreamTestReceiverProbeResult? receiverProbeResult;
        DateTime? receiverProbeStartedAt;
        var receiverProbeStarted = false;

        Future<void> startReceiverProbeForRun(String phase) async {
          if (!config.receiverProbe.enabled ||
              receiverProbeStarted ||
              receiverProbeResult != null) {
            return;
          }
          final receiverProbeStartDelay = config.receiverProbe.startDelay;
          if (receiverProbeStartDelay.inMilliseconds > 0) {
            Log.i(
              'Stream test receiver probe start deferred '
              'phase=$phase delayMs=${receiverProbeStartDelay.inMilliseconds}',
              category: LogCategory.webrtc,
              source: 'stream-test-runner',
            );
            await _delay(receiverProbeStartDelay);
            _throwIfRunCanceled(runGuard);
          }
          final startedAt = _clock();
          receiverProbeStartedAt = startedAt;
          try {
            Log.i(
              'Stream test receiver probe start requested phase=$phase',
              category: LogCategory.webrtc,
              source: 'stream-test-runner',
            );
            await _withTimeout(
              target.startReceiverProbe(config.receiverProbe),
              config.receiverProbe.inProcess
                  ? const Duration(seconds: 10)
                  : const Duration(seconds: 45),
              config.receiverProbe.inProcess
                  ? 'start in-process receiver probe'
                  : 'write external receiver probe credentials',
            );
            receiverProbeStarted = true;
          } catch (exception, stackTrace) {
            Log.onError(
              exception,
              stackTrace,
              content: 'Stream test receiver probe failed to start',
            );
            receiverProbeResult = StreamTestReceiverProbeResult.startFailed(
              mode: config.receiverProbe.mode,
              inProcess: config.receiverProbe.inProcess,
              startedAt: startedAt,
              endedAt: _clock(),
              error: exception,
            );
          }
          _throwIfRunCanceled(runGuard);
        }

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
          final startReceiverProbeBeforeShare =
              config.receiverProbe.startBeforeShare &&
                  config.receiverProbe.mode !=
                      StreamTestReceiverProbeMode.localPreview;
          if (startReceiverProbeBeforeShare) {
            await startReceiverProbeForRun('before_share');
          }
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
          Log.i(
            'Stream test runner active screen share confirmed '
            'profile=${effectiveProfile.label} '
            'backend=${backendMode?.name ?? 'default'} '
            'receiverProbe=${config.receiverProbe.enabled} '
            'receiverProbeMode=${config.receiverProbe.mode.name}',
          );

          if (!startReceiverProbeBeforeShare) {
            await startReceiverProbeForRun('after_active_share');
          }

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
              'screen-share cleanup failed: $exception',
            ].join('; ');
          }
          if (config.receiverProbe.enabled && receiverProbeStarted) {
            final started = receiverProbeStartedAt ?? diagnosticStartedAt;
            try {
              receiverProbeResult = await _withTimeout(
                target.stopReceiverProbe(),
                const Duration(seconds: 10),
                'stop in-process receiver probe',
              );
            } catch (exception, stackTrace) {
              Log.onError(
                exception,
                stackTrace,
                content: 'Stream test receiver probe failed to stop',
              );
              receiverProbeResult = StreamTestReceiverProbeResult.stopFailed(
                mode: config.receiverProbe.mode,
                inProcess: config.receiverProbe.inProcess,
                startedAt: started,
                endedAt: _clock(),
                error: exception,
              );
            }
          } else if (config.receiverProbe.enabled) {
            try {
              await target.stopReceiverProbe();
            } catch (_) {
              // Best-effort cleanup after a failed or canceled probe start.
            }
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
            receiverProbeResult: receiverProbeResult,
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
