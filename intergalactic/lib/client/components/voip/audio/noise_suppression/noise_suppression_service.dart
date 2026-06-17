import 'dart:async';

import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';

import 'noise_suppression_tuning_profile.dart';

class NoiseSuppressionDiagnosticCaptureResult {
  const NoiseSuppressionDiagnosticCaptureResult({
    required this.status,
    required this.directoryPath,
  });

  final NoiseSuppressionNativeStatus status;
  final String directoryPath;
}

class NoiseSuppressionService {
  NoiseSuppressionService._();

  static final NoiseSuppressionService instance = NoiseSuppressionService._();

  final StreamController<NoiseSuppressionNativeStatus>
      _statusChangedController = StreamController.broadcast();

  Future<NoiseSuppressionNativeStatus>? _initialization;
  Future<void> _operationChain = Future<void>.value();
  NoiseSuppressionNativeStatus _status =
      NoiseSuppressionNativeStatus.unavailable();
  NoiseSuppressionTuningProfile _tuningProfile =
      NoiseSuppressionTuningProfile.balanced;
  NoiseSuppressionPipelineMode? _diagnosticHookModeOverride;
  bool _desiredEnabled = false;
  bool _availabilityWarningLogged = false;
  bool _formatMismatchLogged = false;
  bool _suspiciousOutputLogged = false;
  bool _disposed = false;
  String? _diagnosticCaptureDirectoryPath;
  final Set<Timer> _pendingHealthRefreshTimers = {};
  static const int _verifiedFramesBeforeReplacingWebrtcSuppression = 50;
  static const double _speechLikeVadThreshold = 0.78;
  static const double _speechInputRmsFloor = 0.008;
  static const double _collapsedOutputRmsCeiling = 0.001;
  static const double _collapsedOutputRatioCeiling = 0.08;

  Stream<NoiseSuppressionNativeStatus> get onStatusChanged =>
      _statusChangedController.stream;

  NoiseSuppressionNativeStatus get status => _status;

  NoiseSuppressionTuningProfile get tuningProfile => _tuningProfile;

  String? get diagnosticCaptureDirectoryPath => _diagnosticCaptureDirectoryPath;

  bool get desiredEnabled => _desiredEnabled;

  bool get isAvailable => _status.available;

  bool get isEnabled => _status.enabled;

  bool get shouldDisableBuiltInNoiseSuppression =>
      shouldReplaceBuiltInNoiseSuppression(
        isWindows: PlatformUtils.isWindows,
        desiredEnabled: _desiredEnabled,
        status: _status,
      );

  bool get shouldRequestReferenceCaptureFormat =>
      shouldRequestRnnoiseReferenceCaptureFormat(
        isWindows: PlatformUtils.isWindows,
        desiredEnabled: _desiredEnabled,
      );

  static bool shouldReplaceBuiltInNoiseSuppression({
    required bool isWindows,
    required bool desiredEnabled,
    required NoiseSuppressionNativeStatus status,
  }) {
    // Keep WebRTC's built-in suppression active while RNNoise remains a
    // Windows-first additive processor. Current field logs show RNNoise can
    // classify keyboard/click transients as speech-like, so replacing WebRTC
    // NS makes those noises more audible. The native health check is still
    // reported for diagnostics and fail-open decisions, but it no longer turns
    // off the WebRTC baseline.
    return false;
  }

  static bool shouldRequestRnnoiseReferenceCaptureFormat({
    required bool isWindows,
    required bool desiredEnabled,
  }) {
    return isWindows && desiredEnabled;
  }

  static NoiseSuppressionPipelineMode pipelineModeForPreference({
    required bool isWindows,
    required bool desiredEnabled,
    NoiseSuppressionTuningProfile tuningProfile =
        NoiseSuppressionTuningProfile.balanced,
    NoiseSuppressionPipelineMode? diagnosticHookModeOverride,
  }) {
    if (!isWindows) {
      return NoiseSuppressionPipelineMode.off;
    }
    if (diagnosticHookModeOverride != null) {
      return diagnosticHookModeOverride;
    }
    if (!desiredEnabled) {
      return NoiseSuppressionPipelineMode.off;
    }
    return switch (tuningProfile.presetKey) {
      NoiseSuppressionTuningProfile.gentleKey =>
        NoiseSuppressionPipelineMode.cleanRnnoise,
      _ => NoiseSuppressionPipelineMode.tunedGate,
    };
  }

  static bool nativeHookEnabledForPreference({
    required bool isWindows,
    required bool desiredEnabled,
    NoiseSuppressionPipelineMode? diagnosticHookModeOverride,
  }) {
    if (!isWindows) {
      return false;
    }
    if (diagnosticHookModeOverride != null) {
      return diagnosticHookModeOverride != NoiseSuppressionPipelineMode.off;
    }
    return desiredEnabled;
  }

  static bool nativeSuppressionLooksHealthy({
    required bool isWindows,
    required bool desiredEnabled,
    required NoiseSuppressionNativeStatus status,
  }) {
    return isWindows &&
        desiredEnabled &&
        status.available &&
        status.enabled &&
        status.framesProcessed >=
            _verifiedFramesBeforeReplacingWebrtcSuppression &&
        !status.formatMismatchDetected &&
        !status.suspiciousOutputDetected &&
        !speechOutputLooksCollapsed(status);
  }

  static bool speechOutputLooksCollapsed(NoiseSuppressionNativeStatus status) {
    return status.lastVadProbability >= _speechLikeVadThreshold &&
        status.lastInputRms >= _speechInputRmsFloor &&
        status.lastOutputRms < _collapsedOutputRmsCeiling &&
        status.lastOutputRatio < _collapsedOutputRatioCeiling;
  }

  List<String> diagnosticsLines({String header = 'RNNoise diagnostics'}) {
    final status = _status;
    final nativeHealthy = nativeSuppressionLooksHealthy(
      isWindows: PlatformUtils.isWindows,
      desiredEnabled: _desiredEnabled,
      status: status,
    );
    final webrtcSuppression =
        nativeHealthy ? 'on (hybrid RNNoise)' : 'on (fail-open)';

    return <String>[
      header,
      'reason: ${status.reason}',
      'capture profile WebRTC NS: $webrtcSuppression',
      'frames: ${status.framesProcessed}; bypassed: ${status.bypassFrames}; '
          'gated: ${status.gatedFrames}; resampled: ${status.resamplerUses}',
      'resampler: ${status.resamplerMode}; '
          '${status.resamplerInputFrames}->'
          '${status.resamplerOutputFrames} frames; '
          '${status.resamplerSourceRateHz}->'
          '${status.resamplerTargetRateHz} Hz; '
          'underruns=${status.resamplerInputUnderruns}/'
          '${status.resamplerOutputUnderruns}; '
          'overruns=${status.resamplerOverruns}; '
          'antiAlias=${status.outputAntiAliasUses}',
      'pipeline: ${status.pipelineMode.statusLabel}; '
          'processingApplied=${status.processingApplied}; '
          'identityFrames=${status.identityFrames}; '
          'callbackAvg=${status.callbackAverageProcessingMs.toStringAsFixed(2)}ms; '
          'callbackMax=${status.callbackMaxProcessingMs.toStringAsFixed(2)}ms; '
          'budgetMisses=${status.callbackBudgetMisses}; '
          'stateResets=${status.rnnoiseStateResets}',
      'tuning: preset=${_tuningProfile.presetKey}; '
          'nativeVad=${status.referenceVadThreshold.toStringAsFixed(2)}; '
          'grace=${status.referenceSpeechGraceFrames * 10}ms/'
          '${status.referenceSpeechGraceFrames}f; '
          'closedGain=${(status.noiseGateClosedGain * 100).toStringAsFixed(1)}%; '
          'transient=${(status.transientSensitivity * 100).toStringAsFixed(0)}%; '
          'fastClose=${status.fastCloseEnabled}',
      'gate: ${status.lastGateReason}; '
          'gain=${status.lastGateGain.toStringAsFixed(2)}; '
          'threshold=${status.referenceVadThreshold.toStringAsFixed(2)}; '
          'grace=${status.speechGraceRemainingFrames}/'
          '${status.referenceSpeechGraceFrames}; '
          'vadAvg=${status.recentVadAverage.toStringAsFixed(2)}; '
          'vadBuckets=${status.vadLowFrames}/'
          '${status.vadMidFrames}/${status.vadHighFrames}',
      'signal: vad=${status.lastVadProbability.toStringAsFixed(2)}; '
          'in=${status.lastInputRms.toStringAsFixed(4)} '
          'peak=${status.lastInputPeak.toStringAsFixed(4)} '
          'min/max=${status.lastInputMin.toStringAsFixed(4)}/'
          '${status.lastInputMax.toStringAsFixed(4)}; '
          'out=${status.lastOutputRms.toStringAsFixed(4)} '
          'peak=${status.lastOutputPeak.toStringAsFixed(4)} '
          'min/max=${status.lastOutputMin.toStringAsFixed(4)}/'
          '${status.lastOutputMax.toStringAsFixed(4)}; '
          'ratio=${status.lastOutputRatio.toStringAsFixed(2)}; '
          'delta=${status.lastInputMaxDelta.toStringAsFixed(3)}/'
          '${status.lastOutputMaxDelta.toStringAsFixed(3)}; '
          'scale=${status.inputScaleLabel} '
          'x${status.lastInputScaleFactor.toStringAsFixed(0)}',
      'format: ${status.lastNumBands} band(s), '
          '${status.lastNumFrames}/${status.expectedFramesPer10ms} frames, '
          '${status.lastBufferSize} samples, ${status.sampleRateHz} Hz, '
          '${status.numChannels} channel(s)',
      'guards: formatMismatch=${status.formatMismatchDetected}'
          '(${status.formatMismatchReason}), '
          'suspiciousOutput=${status.suspiciousOutputDetected}, '
          'speechCollapsed=${speechOutputLooksCollapsed(status)}, '
          'clip=${status.clippingSamples} '
          '(in=${status.inputClippingSamples}, '
          'out=${status.outputClippingSamples}), '
          'limiter=${status.outputLimiterSamples}, '
          'nonFinite=${status.nonFiniteSamples}, '
          'nativeHealthy=$nativeHealthy',
      'diagnostic capture: active=${status.diagnosticCaptureActive}; '
          'callbacks=${status.diagnosticCaptureFrames}; '
          'dropped=${status.diagnosticCaptureDroppedFrames}; '
          'files=${status.diagnosticCaptureWrittenFiles}; '
          'lastError=${status.diagnosticCaptureLastError.isEmpty ? 'none' : status.diagnosticCaptureLastError}',
      'diagnostic stage files: '
          '${status.diagnosticCaptureStageFileNames.isEmpty ? 'unknown' : status.diagnosticCaptureStageFileNames.join(', ')}',
      'WASAPI sidecar: active=${status.wasapiSidecarActive}; '
          'frames=${status.wasapiSidecarFrames}; '
          'dropped=${status.wasapiSidecarDroppedPackets}; '
          'files=${status.wasapiSidecarWrittenFiles}; '
          'format=${status.wasapiSidecarSampleRateHz}Hz/'
          '${status.wasapiSidecarChannels}ch; '
          'device=${status.wasapiSidecarDeviceResolution}; '
          'lastError=${status.wasapiSidecarLastError.isEmpty ? 'none' : status.wasapiSidecarLastError}',
    ];
  }

  Future<NoiseSuppressionNativeStatus> init({
    required bool enabled,
    NoiseSuppressionTuningProfile? tuningProfile,
  }) {
    return _enqueueOperation(() {
      _disposed = false;
      _desiredEnabled = enabled;
      if (tuningProfile != null) {
        _tuningProfile = tuningProfile;
      }
      return _ensureInitializedLocked();
    });
  }

  Future<NoiseSuppressionNativeStatus> ensureInitialized() {
    return _enqueueOperation(_ensureInitializedLocked);
  }

  Future<NoiseSuppressionNativeStatus> applyPreference(
    bool enabled, {
    NoiseSuppressionTuningProfile? tuningProfile,
  }) async {
    return _enqueueOperation(() async {
      _disposed = false;
      _desiredEnabled = enabled;
      if (tuningProfile != null) {
        _tuningProfile = tuningProfile;
      }
      await _ensureInitializedLocked();

      await IntergalacticNoiseSuppression.instance.configure(
        _tuningProfile.nativeConfig,
      );
      await IntergalacticNoiseSuppression.instance.setPipelineMode(
        pipelineModeForPreference(
          isWindows: PlatformUtils.isWindows,
          desiredEnabled: enabled,
          tuningProfile: _tuningProfile,
          diagnosticHookModeOverride: _diagnosticHookModeOverride,
        ),
      );
      final status = await IntergalacticNoiseSuppression.instance.setEnabled(
        nativeHookEnabledForPreference(
          isWindows: PlatformUtils.isWindows,
          desiredEnabled: enabled,
          diagnosticHookModeOverride: _diagnosticHookModeOverride,
        ),
      );
      _updateStatus(status);
      return status;
    });
  }

  Future<NoiseSuppressionNativeStatus> configureTuning(
    NoiseSuppressionTuningProfile tuningProfile,
  ) async {
    return _enqueueOperation(() async {
      _tuningProfile = tuningProfile;
      await _ensureInitializedLocked();
      var status = await IntergalacticNoiseSuppression.instance.configure(
        _tuningProfile.nativeConfig,
      );
      status = await IntergalacticNoiseSuppression.instance.setPipelineMode(
        pipelineModeForPreference(
          isWindows: PlatformUtils.isWindows,
          desiredEnabled: _desiredEnabled,
          tuningProfile: _tuningProfile,
          diagnosticHookModeOverride: _diagnosticHookModeOverride,
        ),
      );
      _updateStatus(status);
      return status;
    });
  }

  Future<NoiseSuppressionDiagnosticCaptureResult> startDiagnosticCapture({
    required String directoryPath,
    Duration duration = const Duration(seconds: 10),
    int stageMask = NoiseSuppressionDiagnosticStageMask.all,
    bool includeWasapiSidecar = false,
    String? wasapiDeviceId,
  }) async {
    return _enqueueOperation(() async {
      await _ensureInitializedLocked();
      final status =
          await IntergalacticNoiseSuppression.instance.startDiagnosticCapture(
        directoryPath: directoryPath,
        duration: duration,
        stageMask: stageMask,
        includeWasapiSidecar: includeWasapiSidecar,
        wasapiDeviceId: wasapiDeviceId,
      );
      _diagnosticCaptureDirectoryPath = directoryPath;
      _updateStatus(status);
      return NoiseSuppressionDiagnosticCaptureResult(
        status: status,
        directoryPath: directoryPath,
      );
    });
  }

  Future<NoiseSuppressionNativeStatus> stopDiagnosticCapture() async {
    return _enqueueOperation(() async {
      final status =
          await IntergalacticNoiseSuppression.instance.stopDiagnosticCapture();
      _updateStatus(status);
      return status;
    });
  }

  Future<NoiseSuppressionNativeStatus> refresh() async {
    return _enqueueOperation(() async {
      final status = await IntergalacticNoiseSuppression.instance.getStatus();
      _updateStatus(status);
      return status;
    });
  }

  Future<NoiseSuppressionNativeStatus> applyDiagnosticHookMode(
    NoiseSuppressionPipelineMode? mode,
  ) async {
    return _enqueueOperation(() async {
      _diagnosticHookModeOverride = mode;
      await _ensureInitializedLocked();
      var status = await IntergalacticNoiseSuppression.instance.setPipelineMode(
        pipelineModeForPreference(
          isWindows: PlatformUtils.isWindows,
          desiredEnabled: _desiredEnabled,
          tuningProfile: _tuningProfile,
          diagnosticHookModeOverride: _diagnosticHookModeOverride,
        ),
      );
      status = await IntergalacticNoiseSuppression.instance.setEnabled(
        nativeHookEnabledForPreference(
          isWindows: PlatformUtils.isWindows,
          desiredEnabled: _desiredEnabled,
          diagnosticHookModeOverride: _diagnosticHookModeOverride,
        ),
      );
      _updateStatus(status);
      return status;
    });
  }

  Future<NoiseSuppressionNativeStatus> dispose() async {
    return _enqueueOperation(() async {
      _disposed = true;
      _diagnosticHookModeOverride = null;
      for (final timer in _pendingHealthRefreshTimers) {
        timer.cancel();
      }
      _pendingHealthRefreshTimers.clear();
      final status = await IntergalacticNoiseSuppression.instance.shutdown();
      _initialization = null;
      _updateStatus(status);
      return status;
    });
  }

  void scheduleHealthRefresh({Duration delay = const Duration(seconds: 2)}) {
    if (_disposed || !_desiredEnabled || !PlatformUtils.isWindows) {
      return;
    }

    for (final timer in _pendingHealthRefreshTimers) {
      timer.cancel();
    }
    _pendingHealthRefreshTimers.clear();

    for (final refreshDelay in <Duration>[delay, const Duration(seconds: 5)]) {
      late final Timer timer;
      timer = Timer(refreshDelay, () {
        _pendingHealthRefreshTimers.remove(timer);
        if (_disposed) {
          return;
        }
        unawaited(refresh());
      });
      _pendingHealthRefreshTimers.add(timer);
    }
  }

  Future<NoiseSuppressionNativeStatus> _initializeBackend() async {
    var status = await IntergalacticNoiseSuppression.instance.initialize(
      enabled: PlatformUtils.isWindows && _desiredEnabled,
    );
    status = await IntergalacticNoiseSuppression.instance.configure(
      _tuningProfile.nativeConfig,
    );
    status = await IntergalacticNoiseSuppression.instance.setPipelineMode(
      pipelineModeForPreference(
        isWindows: PlatformUtils.isWindows,
        desiredEnabled: _desiredEnabled,
        tuningProfile: _tuningProfile,
        diagnosticHookModeOverride: _diagnosticHookModeOverride,
      ),
    );
    status = await IntergalacticNoiseSuppression.instance.setEnabled(
      nativeHookEnabledForPreference(
        isWindows: PlatformUtils.isWindows,
        desiredEnabled: _desiredEnabled,
        diagnosticHookModeOverride: _diagnosticHookModeOverride,
      ),
    );
    _updateStatus(status);
    return status;
  }

  Future<NoiseSuppressionNativeStatus> _ensureInitializedLocked() async {
    if (_initialization == null || _shouldRetryInitialization(_status)) {
      final initialization = _initializeBackend();
      _initialization = initialization;
      try {
        return await initialization;
      } catch (_) {
        if (identical(_initialization, initialization)) {
          _initialization = null;
        }
        rethrow;
      }
    }
    return _initialization!;
  }

  bool _shouldRetryInitialization(NoiseSuppressionNativeStatus status) {
    if (!PlatformUtils.isWindows || !status.supported || status.available) {
      return false;
    }

    return switch (status.reason) {
      'flutter_webrtc_unavailable' ||
      'audio_processing_unavailable' ||
      'not_initialized' =>
        true,
      _ => false,
    };
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final previousOperation = _operationChain;
    final completer = Completer<T>();

    _operationChain = () async {
      try {
        await previousOperation;
      } catch (_) {
        // Ignore earlier failures so later operations can still run.
      }

      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();

    return completer.future;
  }

  void _updateStatus(NoiseSuppressionNativeStatus status) {
    _status = status;
    _statusChangedController.add(status);

    if (_desiredEnabled &&
        PlatformUtils.isWindows &&
        !status.available &&
        !_availabilityWarningLogged) {
      _availabilityWarningLogged = true;
      Log.w(
        "RNNoise noise suppression unavailable (${status.reason}); continuing with standard WebRTC capture processing.",
      );
    }

    if (status.available) {
      _availabilityWarningLogged = false;
    }

    if (status.formatMismatchDetected && !_formatMismatchLogged) {
      _formatMismatchLogged = true;
      Log.w(
        "RNNoise noise suppression detected an unexpected WebRTC capture format; audio will continue without RNNoise processing until the format matches expected full-band float frames.",
      );
    }

    if (!status.formatMismatchDetected) {
      _formatMismatchLogged = false;
    }

    if (status.suspiciousOutputDetected && !_suspiciousOutputLogged) {
      _suspiciousOutputLogged = true;
      Log.w(
        "RNNoise noise suppression produced suspicious output and is bypassing frames; audio will continue through the standard capture path.",
      );
    }

    if (speechOutputLooksCollapsed(status) && !_suspiciousOutputLogged) {
      _suspiciousOutputLogged = true;
      Log.w(
        "RNNoise noise suppression produced collapsed speech-like output; keeping WebRTC noise suppression active until native output recovers.",
      );
    }

    if (!status.suspiciousOutputDetected &&
        !speechOutputLooksCollapsed(status)) {
      _suspiciousOutputLogged = false;
    }
  }
}
