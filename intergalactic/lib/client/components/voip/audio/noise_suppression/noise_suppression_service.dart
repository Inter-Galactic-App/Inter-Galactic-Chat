import 'dart:async';

import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';

import 'noise_suppression_diagnostic_directory.dart';
import 'noise_suppression_enhanced_backend.dart';
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
  NoiseSuppressionEnhancedBackendStatus _enhancedBackendStatus =
      NoiseSuppressionEnhancedBackendStatus.notRequested();
  NoiseSuppressionPlatformAudioStatus _platformAudioStatus =
      NoiseSuppressionPlatformAudioStatus.unavailable();
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
  static const String diagnosticRnnoiseCompatibilityScenarioKey =
      'rnnoise_compatibility';
  static const String diagnosticEnhancedBackendModeKey =
      NoiseSuppressionEnhancedBackendConstants.preferenceKey;

  /// Platforms with a native noise-suppression backend the user can switch on:
  /// RNNoise on Windows/macOS, DeepFilterNet on Android.
  ///
  /// Public because the settings UI must gate on exactly this. It previously
  /// kept its own copy that omitted Android, so the whole noise-suppression
  /// section was invisible on Android even though the backend was running.
  static bool get isNativeSuppressionPlatform =>
      PlatformUtils.isWindows ||
      PlatformUtils.isMacOS ||
      PlatformUtils.isAndroid;

  /// Platforms whose backend accepts the RNNoise tuning parameters (preset, VAD
  /// threshold, speech grace, and so on). Android's DeepFilterNet does not - its
  /// `configure` call answers `android_configuration_unsupported` - so those
  /// controls must stay hidden there even though suppression itself works.
  static bool get supportsRnnoiseTuning =>
      PlatformUtils.isWindows || PlatformUtils.isMacOS;

  static bool get _isNativeRnnoisePlatform => isNativeSuppressionPlatform;
  static bool get _isNativeDeepFilterNetBaselinePlatform =>
      PlatformUtils.isWindows || PlatformUtils.isAndroid;

  Stream<NoiseSuppressionNativeStatus> get onStatusChanged =>
      _statusChangedController.stream;

  NoiseSuppressionNativeStatus get status => _status;

  NoiseSuppressionTuningProfile get tuningProfile => _effectiveTuningProfile;

  NoiseSuppressionTuningProfile get selectedTuningProfile => _tuningProfile;

  NoiseSuppressionEnhancedBackendStatus get enhancedBackendStatus =>
      _enhancedBackendStatus;

  NoiseSuppressionPlatformAudioStatus get platformAudioStatus =>
      _platformAudioStatus;

  String? get diagnosticCaptureDirectoryPath => _diagnosticCaptureDirectoryPath;

  bool get desiredEnabled => _desiredEnabled;

  bool get compatibilityModeEnabled => compatibilityModeEnabledForPreferences(
    desiredEnabled: _desiredEnabled,
    userCompatibilityModeEnabled:
        preferences.voipNoiseSuppressionCompatibilityMode.value,
    developerModeEnabled: preferences.developerMode.value,
    tapOrderScenarioKey: preferences.voipAudioCaptureTapOrderScenario.value,
  );

  bool get isAvailable => _status.available;

  bool get isEnabled => _status.enabled;

  bool get enhancedBackendRequested =>
      _isNativeRnnoisePlatform &&
      preferences.voipNoiseSuppressionHookMode.value ==
          diagnosticEnhancedBackendModeKey &&
      (preferences.developerMode.value || _enhancedBaselineRequested);

  bool get _enhancedBaselineRequested =>
      _isNativeDeepFilterNetBaselinePlatform &&
      _desiredEnabled &&
      preferences.voipNoiseSuppressionHookMode.value ==
          diagnosticEnhancedBackendModeKey;

  bool get shouldDisableBuiltInNoiseSuppression =>
      shouldReplaceBuiltInNoiseSuppression(
        isNativeRnnoisePlatform: _isNativeRnnoisePlatform,
        desiredEnabled: _desiredEnabled,
        status: _status,
      );

  bool get shouldRequestReferenceCaptureFormat =>
      shouldRequestRnnoiseReferenceCaptureFormat(
        isNativeRnnoisePlatform: _isNativeRnnoisePlatform,
        desiredEnabled: _desiredEnabled,
      );

  static bool shouldReplaceBuiltInNoiseSuppression({
    required bool isNativeRnnoisePlatform,
    required bool desiredEnabled,
    required NoiseSuppressionNativeStatus status,
  }) {
    // Keep WebRTC's built-in suppression active while RNNoise remains a
    // desktop-native additive processor. Current field logs show RNNoise can
    // classify keyboard/click transients as speech-like, so replacing WebRTC
    // NS makes those noises more audible. The native health check is still
    // reported for diagnostics and fail-open decisions, but it no longer turns
    // off the WebRTC baseline.
    return false;
  }

  static bool shouldRequestRnnoiseReferenceCaptureFormat({
    required bool isNativeRnnoisePlatform,
    required bool desiredEnabled,
  }) {
    return isNativeRnnoisePlatform && desiredEnabled;
  }

  static bool compatibilityModeEnabledForPreferences({
    required bool desiredEnabled,
    required bool userCompatibilityModeEnabled,
    required bool developerModeEnabled,
    required String tapOrderScenarioKey,
  }) {
    return desiredEnabled &&
        (userCompatibilityModeEnabled ||
            (developerModeEnabled &&
                tapOrderScenarioKey ==
                    diagnosticRnnoiseCompatibilityScenarioKey));
  }

  static NoiseSuppressionPipelineMode pipelineModeForPreference({
    required bool isNativeRnnoisePlatform,
    required bool desiredEnabled,
    NoiseSuppressionTuningProfile tuningProfile =
        NoiseSuppressionTuningProfile.balanced,
    NoiseSuppressionPipelineMode? diagnosticHookModeOverride,
  }) {
    if (!isNativeRnnoisePlatform) {
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
      NoiseSuppressionTuningProfile.compatibilityKey =>
        NoiseSuppressionPipelineMode.cleanRnnoise,
      _ => NoiseSuppressionPipelineMode.tunedGate,
    };
  }

  static NoiseSuppressionPipelineMode? diagnosticHookModeForPreference({
    required bool isNativeRnnoisePlatform,
    required bool developerModeEnabled,
    required String hookMode,
    bool enhancedBaselineAllowed = false,
  }) {
    if (!isNativeRnnoisePlatform) {
      return null;
    }
    if (hookMode == diagnosticEnhancedBackendModeKey &&
        (developerModeEnabled || enhancedBaselineAllowed)) {
      return NoiseSuppressionPipelineMode.deepFilterNet;
    }
    if (!developerModeEnabled) {
      return null;
    }
    return switch (hookMode) {
      'identity' => NoiseSuppressionPipelineMode.identity,
      'off' => NoiseSuppressionPipelineMode.off,
      _ => null,
    };
  }

  static bool nativeHookEnabledForPreference({
    required bool isNativeRnnoisePlatform,
    required bool desiredEnabled,
    NoiseSuppressionPipelineMode? diagnosticHookModeOverride,
  }) {
    if (!isNativeRnnoisePlatform) {
      return false;
    }
    if (diagnosticHookModeOverride != null) {
      return diagnosticHookModeOverride != NoiseSuppressionPipelineMode.off;
    }
    return desiredEnabled;
  }

  static bool nativeSuppressionLooksHealthy({
    required bool isNativeRnnoisePlatform,
    required bool desiredEnabled,
    required NoiseSuppressionNativeStatus status,
  }) {
    return isNativeRnnoisePlatform &&
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

  List<String> diagnosticsLines({
    String header = 'Audio pipeline diagnostics',
    bool includeEnhancedBackend = false,
  }) {
    final status = _status;
    final effectiveTuningProfile = _effectiveTuningProfile;
    final nativeHealthy = nativeSuppressionLooksHealthy(
      isNativeRnnoisePlatform: _isNativeRnnoisePlatform,
      desiredEnabled: _desiredEnabled,
      status: status,
    );
    final nativeProcessorLabel =
        status.pipelineMode == NoiseSuppressionPipelineMode.deepFilterNet
        ? 'Enhanced DeepFilterNet'
        : 'RNNoise';
    final webrtcSuppression = nativeHealthy
        ? 'on (hybrid $nativeProcessorLabel)'
        : 'on (fail-open)';

    final lines = <String>[
      header,
      'reason: ${status.reason}',
      'capture profile WebRTC NS: $webrtcSuppression',
      'compatibility mode: '
          '${compatibilityModeEnabled ? 'on (clean native path)' : 'off'}',
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
          'dfFrames=${status.deepFilterNetFramesProcessed}; '
          'dfBypass=${status.deepFilterNetBypassFrames}; '
          'dfReason=${status.deepFilterNetReason}; '
          'dfProtect=${status.deepFilterNetSpeechProtectedFrames}; '
          'dfWet=${(status.deepFilterNetLastSpeechProtectWetMix * 100).toStringAsFixed(0)}%; '
          'dfAtten=${status.deepFilterNetAttenuationLimitDb.toStringAsFixed(0)}dB; '
          'dfClickOn=${status.deepFilterNetTransientSuppressionEnabled}; '
          'dfClick=${status.deepFilterNetTransientSuppressedFrames}; '
          'dfClickSamples=${status.deepFilterNetTransientAdjustedSamples}; '
          'dfClickGain=${(status.deepFilterNetLastTransientGain * 100).toStringAsFixed(0)}%; '
          'dfHushOn=${status.deepFilterNetHushSuppressionEnabled}; '
          'dfHush=${status.deepFilterNetHushFramesProcessed}; '
          'dfHushBypass=${status.deepFilterNetHushBypassFrames}; '
          'dfHushReason=${status.deepFilterNetHushReason}; '
          'dfHushSnr=${status.deepFilterNetHushLastLocalSnr.toStringAsFixed(1)}; '
          'dfHushRecover=${status.deepFilterNetHushRecoveryFrames}; '
          'dfHushGain=${(status.deepFilterNetHushLastRecoveryGain * 100).toStringAsFixed(0)}%; '
          'dfHushIn=${status.deepFilterNetHushLastInputRms.toStringAsFixed(4)}; '
          'dfHushOut=${status.deepFilterNetHushLastOutputRms.toStringAsFixed(4)}; '
          'callbackAvg=${status.callbackAverageProcessingMs.toStringAsFixed(2)}ms; '
          'callbackMax=${status.callbackMaxProcessingMs.toStringAsFixed(2)}ms; '
          'budgetMisses=${status.callbackBudgetMisses}; '
          'stateResets=${status.rnnoiseStateResets}',
      'capture: gapEvents=${status.captureGapEvents}; '
          'intervalMs=${status.lastCallbackIntervalMs.toStringAsFixed(1)}; '
          'maxIntervalMs=${status.maxCallbackIntervalMs.toStringAsFixed(1)}; '
          'framesSinceResume=${status.framesSinceCaptureResume}; '
          'dfGapRecover=${status.deepFilterNetGapRecoveries}; '
          'dfDelay=${status.deepFilterNetDryDelayFrames}f; '
          'dfWarmup=${status.deepFilterNetWarmupMs.toStringAsFixed(0)}ms; '
          'dfHushWarmup=${status.deepFilterNetHushWarmupMs.toStringAsFixed(0)}ms; '
          'dfPrewarmPending=${status.deepFilterNetPrewarmPendingFrames}',
      'tuning: selected=${_tuningProfile.presetKey}; '
          'effective=${effectiveTuningProfile.presetKey}; '
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
      'diagnostic WAV capture: active=${status.diagnosticCaptureActive}; '
          'callbacks=${status.diagnosticCaptureFrames}; '
          'dropped=${status.diagnosticCaptureDroppedFrames}; '
          'files=${status.diagnosticCaptureWrittenFiles}; '
          'lastError=${status.diagnosticCaptureLastError.isEmpty ? 'none' : status.diagnosticCaptureLastError}',
      ..._platformAudioStatus.lines,
      'diagnostic WAV stage files: '
          '${status.diagnosticCaptureStageFileNames.isEmpty ? 'unknown' : status.diagnosticCaptureStageFileNames.join(', ')}',
    ];
    if (includeEnhancedBackend) {
      lines.addAll(_enhancedBackendStatus.diagnosticsLines);
    }
    if (PlatformUtils.isWindows ||
        status.wasapiSidecarActive ||
        status.wasapiSidecarFrames > 0 ||
        status.wasapiSidecarWrittenFiles > 0) {
      lines.add(
        'WASAPI sidecar: active=${status.wasapiSidecarActive}; '
        'frames=${status.wasapiSidecarFrames}; '
        'dropped=${status.wasapiSidecarDroppedPackets}; '
        'files=${status.wasapiSidecarWrittenFiles}; '
        'format=${status.wasapiSidecarSampleRateHz}Hz/'
        '${status.wasapiSidecarChannels}ch; '
        'device=${status.wasapiSidecarDeviceResolution}; '
        'lastError=${status.wasapiSidecarLastError.isEmpty ? 'none' : status.wasapiSidecarLastError}',
      );
    }
    return lines;
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
      return _applyCurrentNativeConfigurationLocked();
    });
  }

  Future<NoiseSuppressionNativeStatus> configureTuning(
    NoiseSuppressionTuningProfile tuningProfile,
  ) async {
    return _enqueueOperation(() async {
      _tuningProfile = tuningProfile;
      await _ensureInitializedLocked();
      return _applyCurrentNativeConfigurationLocked();
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
      await _applyCurrentNativeConfigurationLocked();
      final status = await IntergalacticNoiseSuppression.instance
          .startDiagnosticCapture(
            directoryPath: directoryPath,
            duration: duration,
            stageMask: stageMask,
            includeWasapiSidecar:
                PlatformUtils.isWindows && includeWasapiSidecar,
            wasapiDeviceId: PlatformUtils.isWindows ? wasapiDeviceId : null,
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
      final status = await IntergalacticNoiseSuppression.instance
          .stopDiagnosticCapture();
      _updateStatus(status);
      // The start-time metadata records pre-capture counters (zeros), so
      // append the stop-time snapshot while it is still trustworthy - a
      // later processor re-initialization resets the shared counters.
      final directoryPath = _diagnosticCaptureDirectoryPath;
      if (directoryPath != null) {
        try {
          await appendNoiseSuppressionDiagnosticStopMetadata(
            directoryPath: directoryPath,
            status: status,
          );
        } catch (error) {
          // Type only, never the error's own string: FileSystemException
          // .toString() embeds directoryPath, which carries user-specific local
          // path segments that must not reach application logs.
          Log.w(
            'Could not append stop-time noise-suppression capture metadata: '
            '${error.runtimeType}',
          );
        }
      }
      return status;
    });
  }

  Future<NoiseSuppressionNativeStatus> refresh() async {
    return _enqueueOperation(() async {
      var status = await IntergalacticNoiseSuppression.instance.getStatus();
      _updateStatus(status);

      // A refresh that only observes cannot fix the one failure it is best
      // placed to catch. On Android the backend attaches to WebRTC's capture
      // post-processing chain, but flutter_webrtc only creates the controller
      // that exposes it when it builds its PeerConnectionFactory - which
      // happens AFTER the call-join path calls ensureInitialized(). So the
      // first attach on a cold join always fails with
      // 'audio_processing_unavailable' and the model then sits loaded and
      // ready while no frame ever reaches it.
      //
      // scheduleHealthRefresh() fires this 2s and 5s after the microphone is
      // enabled, which is precisely when the controller does exist, so this is
      // the right place to retry rather than leaving the user with suppression
      // silently off for the whole call. _shouldRetryInitialization keeps it
      // narrow: only the reasons that are genuinely transient, and only while
      // the backend reports itself unavailable.
      if (_shouldRetryInitialization(status)) {
        Log.i(
          'Noise suppression reported a retryable backend state '
          '(${status.reason}); re-initializing',
          category: LogCategory.webrtc,
          source: 'noise-suppression-service',
        );
        await _ensureInitializedLocked();
        status = await _applyCurrentNativeConfigurationLocked();
      }

      await _refreshEnhancedBackendStatusLocked(nativeStatus: status);
      return status;
    });
  }

  Future<NoiseSuppressionEnhancedBackendStatus>
  refreshEnhancedBackendStatus() async {
    return _enqueueOperation(_refreshEnhancedBackendStatusLocked);
  }

  Future<NoiseSuppressionNativeStatus> applyDiagnosticHookMode(
    NoiseSuppressionPipelineMode? mode,
  ) async {
    return _enqueueOperation(() async {
      _diagnosticHookModeOverride = mode;
      await _ensureInitializedLocked();
      return _applyCurrentNativeConfigurationLocked();
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
    if (_disposed || !_desiredEnabled || !_isNativeRnnoisePlatform) {
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
    try {
      _platformAudioStatus = await IntergalacticNoiseSuppression.instance
          .getPlatformAudioStatus();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Platform audio diagnostics failed; continuing noise suppression '
            'initialization',
        category: LogCategory.webrtc,
        source: 'noise-suppression-service',
      );
      _platformAudioStatus = NoiseSuppressionPlatformAudioStatus.unavailable(
        platform: PlatformUtils.isAndroid ? 'android' : 'unknown',
      );
    }
    var status = await IntergalacticNoiseSuppression.instance.initialize(
      enabled: _isNativeRnnoisePlatform && _desiredEnabled,
    );
    _updateStatus(status);
    return _applyCurrentNativeConfigurationLocked();
  }

  Future<NoiseSuppressionNativeStatus>
  _applyCurrentNativeConfigurationLocked() async {
    final effectiveTuningProfile = _effectiveTuningProfile;
    final diagnosticHookModeOverride =
        _diagnosticHookModeOverride ?? _diagnosticHookModeForPreferences();
    final pipelineMode =
        PlatformUtils.isAndroid &&
            _desiredEnabled &&
            diagnosticHookModeOverride == null
        ? NoiseSuppressionPipelineMode.deepFilterNet
        : pipelineModeForPreference(
            isNativeRnnoisePlatform: _isNativeRnnoisePlatform,
            desiredEnabled: _desiredEnabled,
            tuningProfile: effectiveTuningProfile,
            diagnosticHookModeOverride: diagnosticHookModeOverride,
          );
    try {
      // `configure` carries the RNNoise tuning parameters and nothing else.
      // Android's plugin answers it with `android_configuration_unsupported`,
      // which arrives here as a PlatformException - so calling it first aborted
      // the whole try block and `setPipelineMode` / `setEnabled` never ran.
      // Suppression could therefore never turn on at all on Android: the status
      // settled on `native_configuration_failed` while reporting supported=true.
      // Skip the call on the platforms that have no tuning contract; the
      // pipeline mode and the enable flag are supported there and are what
      // actually start DeepFilterNet.
      if (supportsRnnoiseTuning) {
        // Return value intentionally dropped: the two calls below overwrite it.
        await IntergalacticNoiseSuppression.instance.configure(
          _nativeConfigForTuningProfile(effectiveTuningProfile),
        );
      }
      var status = await IntergalacticNoiseSuppression.instance.setPipelineMode(
        pipelineMode,
      );
      status = await IntergalacticNoiseSuppression.instance.setEnabled(
        nativeHookEnabledForPreference(
          isNativeRnnoisePlatform: _isNativeRnnoisePlatform,
          desiredEnabled: _desiredEnabled,
          diagnosticHookModeOverride: diagnosticHookModeOverride,
        ),
      );
      _updateStatus(status);
      await _refreshEnhancedBackendStatusLocked(nativeStatus: status);
      return status;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Noise suppression configuration failed; continuing without '
            'native suppression',
        category: LogCategory.webrtc,
        source: 'noise-suppression-service',
      );
      final failedStatus = NoiseSuppressionNativeStatus.unavailable(
        reason: 'native_configuration_failed',
        supported: _isNativeRnnoisePlatform,
        requestedEnabled: _desiredEnabled,
      );
      _updateStatus(failedStatus);
      await _refreshEnhancedBackendStatusLocked(nativeStatus: failedStatus);
      return failedStatus;
    }
  }

  NoiseSuppressionNativeConfig _nativeConfigForTuningProfile(
    NoiseSuppressionTuningProfile profile,
  ) {
    return NoiseSuppressionNativeConfig(
      vadThreshold: profile.vadThreshold,
      speechGraceFrames: profile.speechGraceFrames,
      closedGain: profile.closedGain,
      transientSensitivity: profile.transientSensitivity,
      fastCloseEnabled: profile.fastCloseEnabled,
      deepFilterNetTransientSuppressionEnabled: preferences
          .voipNoiseSuppressionDeepFilterNetTransientSuppression
          .value,
      deepFilterNetHushSuppressionEnabled:
          preferences.voipNoiseSuppressionDeepFilterNetHushSuppression.value,
    );
  }

  NoiseSuppressionPipelineMode? _diagnosticHookModeForPreferences() {
    return diagnosticHookModeForPreference(
      isNativeRnnoisePlatform: _isNativeRnnoisePlatform,
      developerModeEnabled: preferences.developerMode.value,
      hookMode: preferences.voipNoiseSuppressionHookMode.value,
      enhancedBaselineAllowed: _enhancedBaselineRequested,
    );
  }

  Future<NoiseSuppressionEnhancedBackendStatus>
  _refreshEnhancedBackendStatusLocked({
    NoiseSuppressionNativeStatus? nativeStatus,
  }) async {
    final status = await NoiseSuppressionEnhancedBackendResolver.resolve(
      requested: enhancedBackendRequested,
      developerModeEnabled:
          preferences.developerMode.value || _enhancedBaselineRequested,
      nativeStatus: nativeStatus ?? _status,
      hushSupportRequested:
          preferences.voipNoiseSuppressionDeepFilterNetHushSuppression.value,
    );
    _enhancedBackendStatus = status;
    return status;
  }

  Future<NoiseSuppressionNativeStatus> _ensureInitializedLocked() async {
    if (_initialization == null || _shouldRetryInitialization(_status)) {
      final initialization = _initializeBackend();
      _initialization = initialization;
      try {
        return await initialization;
      } catch (error, stackTrace) {
        if (identical(_initialization, initialization)) {
          _initialization = null;
        }
        // Noise suppression is an optional capture enhancement. A native
        // backend failure (for example the Android libdf.so dlopen failure)
        // must degrade to "unavailable" - not propagate into app startup or
        // call joins, both of which await this initialization.
        Log.onError(
          error,
          stackTrace,
          content:
              'Noise suppression backend initialization failed; continuing '
              'without noise suppression',
          category: LogCategory.webrtc,
          source: 'noise-suppression-service',
        );
        final failedStatus = NoiseSuppressionNativeStatus.unavailable(
          reason: 'native_backend_init_failed',
          supported: _isNativeRnnoisePlatform,
          requestedEnabled: _desiredEnabled,
        );
        _updateStatus(failedStatus);
        return failedStatus;
      }
    }
    return _initialization!;
  }

  bool _shouldRetryInitialization(NoiseSuppressionNativeStatus status) =>
      shouldRetryInitialization(
        isNativeRnnoisePlatform: _isNativeRnnoisePlatform,
        status: status,
      );

  /// Whether a backend in this state is worth re-initializing.
  ///
  /// Static and pure so the decision can be tested directly - it is the hinge
  /// the Android engagement failure turned on, and it was previously
  /// unreachable in exactly the case it was written for.
  ///
  /// The `status.available` guard is deliberate and load-bearing: there is no
  /// point re-initializing a backend that is working. It is also why the
  /// Android plugin must report `available` honestly. In v0.8.1+1001 it
  /// reported availability from `nativeReady` alone - "df_create succeeded" -
  /// while the processor had never attached to WebRTC's capture chain. The
  /// status was therefore available=true AND
  /// reason='audio_processing_unavailable' at the same time, so this returned
  /// false and the retry listed for that very reason never ran. Suppression
  /// stayed silently off for the whole call.
  ///
  /// The listed reasons are the transient ones. A cold call join always hits
  /// 'audio_processing_unavailable' on its first attach, because flutter_webrtc
  /// only creates its AudioProcessingController when it builds the
  /// PeerConnectionFactory, which happens after the join path initializes this
  /// service. Terminal reasons - a failed df_create, a missing model - are
  /// deliberately absent: retrying those just repeats expensive work, and
  /// df_create aborts the process rather than returning an error.
  static bool shouldRetryInitialization({
    required bool isNativeRnnoisePlatform,
    required NoiseSuppressionNativeStatus status,
  }) {
    if (!isNativeRnnoisePlatform || !status.supported || status.available) {
      return false;
    }

    return switch (status.reason) {
      'flutter_webrtc_unavailable' ||
      'audio_processing_unavailable' ||
      'not_initialized' => true,
      _ => false,
    };
  }

  NoiseSuppressionTuningProfile get _effectiveTuningProfile =>
      NoiseSuppressionTuningProfile.effectiveForCompatibilityMode(
        _tuningProfile,
        compatibilityModeEnabled: compatibilityModeEnabled,
      );

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
        _isNativeRnnoisePlatform &&
        !status.available &&
        !_availabilityWarningLogged) {
      _availabilityWarningLogged = true;
      Log.w(
        "Native microphone noise suppression unavailable (${status.reason}); continuing with standard WebRTC capture processing.",
      );
    }

    if (status.available) {
      _availabilityWarningLogged = false;
    }

    if (status.formatMismatchDetected && !_formatMismatchLogged) {
      _formatMismatchLogged = true;
      Log.w(
        "Native microphone noise suppression detected an unexpected WebRTC capture format; audio will continue without native processing until the format matches expected full-band float frames.",
      );
    }

    if (!status.formatMismatchDetected) {
      _formatMismatchLogged = false;
    }

    if (status.suspiciousOutputDetected && !_suspiciousOutputLogged) {
      _suspiciousOutputLogged = true;
      Log.w(
        "Native microphone noise suppression produced suspicious output and is bypassing frames; audio will continue through the standard capture path.",
      );
    }

    if (speechOutputLooksCollapsed(status) && !_suspiciousOutputLogged) {
      _suspiciousOutputLogged = true;
      Log.w(
        "Native microphone noise suppression produced collapsed speech-like output; keeping WebRTC noise suppression active until native output recovers.",
      );
    }

    if (!status.suspiciousOutputDetected &&
        !speechOutputLooksCollapsed(status)) {
      _suspiciousOutputLogged = false;
    }
  }
}
