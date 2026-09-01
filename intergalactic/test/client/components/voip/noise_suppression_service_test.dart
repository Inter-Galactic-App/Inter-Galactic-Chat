import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_diagnostic_directory.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_enhanced_backend.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';

/// The reasons `shouldRetryInitialization` treats as transient.
///
/// Shared so the retry test and the terminal test cannot drift apart: retry is
/// an allowlist, so the only assertion with teeth about a terminal reason is
/// that it is absent from THIS list, and that check is worthless if each test
/// keeps a private copy.
const _retryableReasons = [
  'flutter_webrtc_unavailable',
  'audio_processing_unavailable',
  'not_initialized',
];

/// Failures that abort the native process rather than returning an error.
/// Retrying any of these in a loop takes the app down with it.
const _terminalReasons = [
  'deepfilternet_create_failed',
  'deepfilternet_disabled_after_abort',
  'native_backend_init_failed',
];

void main() {
  group('NoiseSuppressionService', () {
    // REGRESSION, Android v0.8.1+1001: noise suppression never engaged on a
    // call. df_create had SUCCEEDED - the model was loaded - but the processor
    // never attached to WebRTC's capture chain, because flutter_webrtc creates
    // its AudioProcessingController when it builds the PeerConnectionFactory,
    // which happens after the call-join path initializes this service. The
    // device log showed the contradiction that made it permanent:
    //   nativeAvailable=true nativeActive=true
    //   nativeReason=audio_processing_unavailable
    //   processingApplied=false dfFrames=0
    // The Android plugin derived `available` from nativeReady alone, so a
    // backend that was processing nothing reported itself available, and the
    // retry below - which lists that exact reason - was skipped by the
    // `status.available` guard.
    test('retries a backend that reports a transient attach failure', () {
      expect(
        NoiseSuppressionService.shouldRetryInitialization(
          isNativeRnnoisePlatform: true,
          status: _status(
            available: false,
            enabled: true,
            reason: 'audio_processing_unavailable',
          ),
        ),
        isTrue,
        reason:
            'A cold call join always fails its first attach; the retry after '
            'the microphone is enabled is what makes suppression engage.',
      );
    });

    test('retries every reason the contract lists as transient', () {
      // The test above pins only `audio_processing_unavailable`, so a change
      // that dropped either of the other two retry paths would not have
      // failed anything. `not_initialized` in particular is the string the
      // Android plugin reports after a WebRTC reset and when no processor
      // exists at all.
      for (final retryable in _retryableReasons) {
        expect(
          NoiseSuppressionService.shouldRetryInitialization(
            isNativeRnnoisePlatform: true,
            status: _status(available: false, enabled: true, reason: retryable),
          ),
          isTrue,
          reason: '$retryable is a transient backend state and must retry.',
        );
      }
    });

    test(
      'an available backend blocks the retry, so available must be honest',
      () {
        expect(
          NoiseSuppressionService.shouldRetryInitialization(
            isNativeRnnoisePlatform: true,
            status: _status(
              available: true,
              enabled: true,
              reason: 'audio_processing_unavailable',
            ),
          ),
          isFalse,
          reason:
              'This is the v0.8.1+1001 state. Re-initializing a working backend '
              'is pointless, so the guard is right and the plugin must not '
              'report available=true when nothing is attached.',
        );
      },
    );

    test('does not retry a terminal native failure', () {
      // Retry is an ALLOWLIST: `shouldRetryInitialization` returns false for
      // every reason it does not recognise. So asserting `isFalse` for a named
      // terminal reason is nearly vacuous on its own - a typo in the string
      // below, or deleting the reason from production entirely, still passes.
      //
      // The assertion that carries weight is the negative membership one
      // afterwards: it fails if any of these is ever added to the retryable
      // set, which is the actual regression - a df_create abort retried in a
      // loop takes the process down with it.
      for (final terminal in _terminalReasons) {
        expect(
          _retryableReasons,
          isNot(contains(terminal)),
          reason:
              '$terminal must never join the retryable set; df_create aborts '
              'the process rather than returning an error.',
        );
      }

      for (final terminal in _terminalReasons) {
        expect(
          NoiseSuppressionService.shouldRetryInitialization(
            isNativeRnnoisePlatform: true,
            status: _status(available: false, enabled: true, reason: terminal),
          ),
          isFalse,
          reason:
              'df_create aborts the process rather than returning an error, so '
              '$terminal must not be retried in a loop.',
        );
      }
    });

    test('does not retry on a platform with no native backend', () {
      expect(
        NoiseSuppressionService.shouldRetryInitialization(
          isNativeRnnoisePlatform: false,
          status: _status(
            available: false,
            enabled: true,
            reason: 'audio_processing_unavailable',
          ),
        ),
        isFalse,
      );
    });

    test('keeps WebRTC suppression on until RNNoise has processed frames', () {
      final status = _status(
        available: true,
        enabled: true,
        framesProcessed: 0,
      );

      expect(
        NoiseSuppressionService.shouldReplaceBuiltInNoiseSuppression(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          status: status,
        ),
        isFalse,
      );
    });

    test('keeps WebRTC suppression on after healthy RNNoise verification', () {
      final status = _status(
        available: true,
        enabled: true,
        framesProcessed: 50,
        lastVadProbability: 0.9,
        lastInputRms: 0.08,
        lastOutputRms: 0.04,
        lastOutputRatio: 0.5,
      );

      expect(
        NoiseSuppressionService.shouldReplaceBuiltInNoiseSuppression(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          status: status,
        ),
        isFalse,
      );
      expect(
        NoiseSuppressionService.nativeSuppressionLooksHealthy(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          status: status,
        ),
        isTrue,
      );
    });

    test('keeps WebRTC suppression on for collapsed speech-like output', () {
      final status = _status(
        available: true,
        enabled: true,
        framesProcessed: 50,
        lastVadProbability: 0.95,
        lastInputRms: 0.08,
        lastOutputRms: 0.000001,
        lastOutputRatio: 0.00001,
      );

      expect(
        NoiseSuppressionService.shouldReplaceBuiltInNoiseSuppression(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          status: status,
        ),
        isFalse,
      );
    });

    test('keeps WebRTC suppression on for PCM-scale silent-output reports', () {
      final status = _status(
        available: true,
        enabled: true,
        framesProcessed: 50,
        lastInputScaleFactor: 32768,
        lastVadProbability: 1,
        lastInputRms: 0.08,
        lastOutputRms: 0.00003,
        lastOutputRatio: 0.0004,
      );

      expect(
        NoiseSuppressionService.shouldReplaceBuiltInNoiseSuppression(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          status: status,
        ),
        isFalse,
      );
    });

    test('keeps WebRTC suppression on for native guard failures', () {
      for (final status in [
        _status(
          available: true,
          enabled: true,
          framesProcessed: 50,
          formatMismatchDetected: true,
        ),
        _status(
          available: true,
          enabled: true,
          framesProcessed: 50,
          suspiciousOutputDetected: true,
        ),
      ]) {
        expect(
          NoiseSuppressionService.shouldReplaceBuiltInNoiseSuppression(
            isNativeRnnoisePlatform: true,
            desiredEnabled: true,
            status: status,
          ),
          isFalse,
        );
      }
    });

    test(
      'requests RNNoise reference capture format on supported native desktop platforms',
      () {
        expect(
          NoiseSuppressionService.shouldRequestRnnoiseReferenceCaptureFormat(
            isNativeRnnoisePlatform: true,
            desiredEnabled: true,
          ),
          isTrue,
        );
        expect(
          NoiseSuppressionService.shouldRequestRnnoiseReferenceCaptureFormat(
            isNativeRnnoisePlatform: true,
            desiredEnabled: false,
          ),
          isFalse,
        );
        expect(
          NoiseSuppressionService.shouldRequestRnnoiseReferenceCaptureFormat(
            isNativeRnnoisePlatform: false,
            desiredEnabled: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'treats the user toggle and diagnostic scenario as RNNoise compatibility mode',
      () {
        expect(
          NoiseSuppressionService.compatibilityModeEnabledForPreferences(
            desiredEnabled: true,
            userCompatibilityModeEnabled: true,
            developerModeEnabled: false,
            tapOrderScenarioKey: 'manual',
          ),
          isTrue,
        );
        expect(
          NoiseSuppressionService.compatibilityModeEnabledForPreferences(
            desiredEnabled: true,
            userCompatibilityModeEnabled: false,
            developerModeEnabled: true,
            tapOrderScenarioKey: NoiseSuppressionService
                .diagnosticRnnoiseCompatibilityScenarioKey,
          ),
          isTrue,
        );
        expect(
          NoiseSuppressionService.compatibilityModeEnabledForPreferences(
            desiredEnabled: true,
            userCompatibilityModeEnabled: false,
            developerModeEnabled: false,
            tapOrderScenarioKey: NoiseSuppressionService
                .diagnosticRnnoiseCompatibilityScenarioKey,
          ),
          isFalse,
        );
        expect(
          NoiseSuppressionService.compatibilityModeEnabledForPreferences(
            desiredEnabled: false,
            userCompatibilityModeEnabled: true,
            developerModeEnabled: true,
            tapOrderScenarioKey: NoiseSuppressionService
                .diagnosticRnnoiseCompatibilityScenarioKey,
          ),
          isFalse,
        );
      },
    );

    test('diagnostic compatibility scenario maps to the clean native path', () {
      final compatibilityMode =
          NoiseSuppressionService.compatibilityModeEnabledForPreferences(
            desiredEnabled: true,
            userCompatibilityModeEnabled: false,
            developerModeEnabled: true,
            tapOrderScenarioKey: NoiseSuppressionService
                .diagnosticRnnoiseCompatibilityScenarioKey,
          );
      final effectiveProfile =
          NoiseSuppressionTuningProfile.effectiveForCompatibilityMode(
            NoiseSuppressionTuningProfile.balanced,
            compatibilityModeEnabled: compatibilityMode,
          );

      expect(effectiveProfile, NoiseSuppressionTuningProfile.compatibility);
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          tuningProfile: effectiveProfile,
        ),
        NoiseSuppressionPipelineMode.cleanRnnoise,
      );
    });

    test('maps enabled native RNNoise presets to native pipeline modes', () {
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.gentle,
        ),
        NoiseSuppressionPipelineMode.cleanRnnoise,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.compatibility,
        ),
        NoiseSuppressionPipelineMode.cleanRnnoise,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.balanced,
        ),
        NoiseSuppressionPipelineMode.tunedGate,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.strong,
        ),
        NoiseSuppressionPipelineMode.tunedGate,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.fromPreferenceValues(
            presetKey: NoiseSuppressionTuningProfile.customKey,
            customVadThreshold: 0.9,
            customSpeechGraceMs: 80,
            customClosedGainPercent: 1,
            customTransientSensitivityPercent: 80,
          ),
        ),
        NoiseSuppressionPipelineMode.tunedGate,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: false,
        ),
        NoiseSuppressionPipelineMode.off,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: false,
          desiredEnabled: true,
        ),
        NoiseSuppressionPipelineMode.off,
      );
    });

    test('maps developer diagnostic hook overrides explicitly', () {
      expect(
        NoiseSuppressionPipelineMode.fromStatusLabel('identity'),
        NoiseSuppressionPipelineMode.identity,
      );
      expect(
        NoiseSuppressionPipelineMode.fromStatusLabel('prototype_suppression'),
        NoiseSuppressionPipelineMode.prototypeSuppression,
      );
      expect(
        NoiseSuppressionPipelineMode.fromStatusLabel(
          'prototype_suppression_v2',
        ),
        NoiseSuppressionPipelineMode.prototypeSuppressionV2,
      );
      expect(
        NoiseSuppressionPipelineMode.fromStatusLabel('deepfilternet'),
        NoiseSuppressionPipelineMode.deepFilterNet,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: false,
          diagnosticHookModeOverride: NoiseSuppressionPipelineMode.identity,
        ),
        NoiseSuppressionPipelineMode.identity,
      );
      expect(
        NoiseSuppressionService.nativeHookEnabledForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: false,
          diagnosticHookModeOverride: NoiseSuppressionPipelineMode.identity,
        ),
        isTrue,
      );
      expect(
        NoiseSuppressionService.nativeHookEnabledForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          diagnosticHookModeOverride: NoiseSuppressionPipelineMode.off,
        ),
        isFalse,
      );
    });

    test('maps persisted hook mode preferences explicitly', () {
      expect(
        NoiseSuppressionService.diagnosticHookModeForPreference(
          isNativeRnnoisePlatform: true,
          developerModeEnabled: true,
          hookMode: NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
        ),
        NoiseSuppressionPipelineMode.deepFilterNet,
      );
      expect(
        NoiseSuppressionService.diagnosticHookModeForPreference(
          isNativeRnnoisePlatform: true,
          developerModeEnabled: false,
          hookMode: NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
          enhancedBaselineAllowed: true,
        ),
        NoiseSuppressionPipelineMode.deepFilterNet,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.balanced,
          diagnosticHookModeOverride:
              NoiseSuppressionService.diagnosticHookModeForPreference(
                isNativeRnnoisePlatform: true,
                developerModeEnabled: true,
                hookMode:
                    NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
              ),
        ),
        NoiseSuppressionPipelineMode.deepFilterNet,
      );
      expect(
        NoiseSuppressionService.nativeHookEnabledForPreference(
          isNativeRnnoisePlatform: true,
          desiredEnabled: false,
          diagnosticHookModeOverride:
              NoiseSuppressionService.diagnosticHookModeForPreference(
                isNativeRnnoisePlatform: true,
                developerModeEnabled: true,
                hookMode:
                    NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
              ),
        ),
        isTrue,
      );
      expect(
        NoiseSuppressionService.diagnosticHookModeForPreference(
          isNativeRnnoisePlatform: true,
          developerModeEnabled: false,
          hookMode: NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
        ),
        isNull,
      );
      expect(
        NoiseSuppressionService.diagnosticHookModeForPreference(
          isNativeRnnoisePlatform: true,
          developerModeEnabled: true,
          hookMode: 'rnnoise',
        ),
        isNull,
      );
      expect(
        NoiseSuppressionService.diagnosticHookModeForPreference(
          isNativeRnnoisePlatform: false,
          developerModeEnabled: true,
          hookMode: NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
        ),
        isNull,
      );
    });

    test(
      'keeps Enhanced DeepFilterNet fail-open without developer gate',
      () async {
        final notRequested =
            await NoiseSuppressionEnhancedBackendResolver.resolve(
              requested: false,
              developerModeEnabled: false,
            );
        expect(notRequested.requested, isFalse);
        expect(notRequested.available, isFalse);
        expect(notRequested.reason, 'not_requested');
        expect(notRequested.productionDefaultChanged, isFalse);

        final blocked = await NoiseSuppressionEnhancedBackendResolver.resolve(
          requested: true,
          developerModeEnabled: false,
        );
        expect(blocked.available, isFalse);
        expect(
          blocked.reason,
          isNot(
            NoiseSuppressionEnhancedBackendConstants
                .developerModeRequiredReason,
          ),
        );
        expect(blocked.fallbackMode, 'standard');
        expect(
          blocked.failureLabels,
          contains('enhanced_fallback_to_standard'),
        );
        expect(
          blocked.failureLabels,
          isNot(
            contains(
              NoiseSuppressionEnhancedBackendConstants
                  .developerModeRequiredReason,
            ),
          ),
        );
      },
    );

    test(
      'reports native Enhanced DeepFilterNet mode selection on Windows',
      () async {
        if (!Platform.isWindows) {
          return;
        }

        final status = await NoiseSuppressionEnhancedBackendResolver.resolve(
          requested: true,
          developerModeEnabled: true,
          nativeStatus: _status(
            available: true,
            enabled: true,
            framesProcessed: 2,
            pipelineMode: NoiseSuppressionPipelineMode.deepFilterNet,
            deepFilterNetRuntimeAvailable: true,
            deepFilterNetProcessingApplied: true,
            deepFilterNetFramesProcessed: 2,
            deepFilterNetFrameLength: 480,
            deepFilterNetReason: 'deepfilternet_ready',
            deepFilterNetLastLocalSnr: 11.5,
          ),
        );

        expect(status.available, isTrue);
        expect(status.reason, 'deepfilternet_ready');
        expect(status.runtimeAvailable, isTrue);
        expect(status.appIntegrated, isTrue);
        expect(status.callbackBufferingProven, isTrue);
        expect(status.callRoomProcessingReady, isTrue);
        expect(status.productionDefaultChanged, isTrue);
        expect(
          status.failureLabels,
          isNot(contains('hush_support_not_bundled')),
        );
        expect(status.supportLayerRequested, isFalse);
      },
    );

    test('reports missing Hush support files only when requested', () async {
      if (!Platform.isWindows) {
        return;
      }

      final status = await NoiseSuppressionEnhancedBackendResolver.resolve(
        requested: true,
        developerModeEnabled: true,
        hushSupportRequested: true,
        nativeStatus: _status(
          available: true,
          enabled: true,
          framesProcessed: 2,
          pipelineMode: NoiseSuppressionPipelineMode.deepFilterNet,
          deepFilterNetRuntimeAvailable: true,
          deepFilterNetProcessingApplied: true,
          deepFilterNetFramesProcessed: 2,
          deepFilterNetFrameLength: 480,
          deepFilterNetReason: 'deepfilternet_ready',
          deepFilterNetHushBypassFrames: 1,
          deepFilterNetHushReason: 'deepfilternet_model_missing',
        ),
      );

      expect(status.supportLayerRequested, isTrue);
      expect(status.failureLabels, contains('hush_support_not_bundled'));
    });

    test('does not report Hush support files missing when present', () async {
      if (!Platform.isWindows) {
        return;
      }

      final modelDirectory = await Directory.systemTemp.createTemp(
        'intergalactic_hush_test_',
      );
      addTearDown(() async {
        if (modelDirectory.existsSync()) {
          await modelDirectory.delete(recursive: true);
        }
      });
      for (final fileName
          in NoiseSuppressionEnhancedBackendConstants.hushModelFiles) {
        final file = File(
          '${modelDirectory.path}${Platform.pathSeparator}'
          '${fileName.replaceAll('/', Platform.pathSeparator)}',
        );
        await file.parent.create(recursive: true);
        await file.writeAsString('test');
      }

      final status = await NoiseSuppressionEnhancedBackendResolver.resolve(
        requested: true,
        developerModeEnabled: true,
        hushModelDirectoryOverride: modelDirectory.path,
        hushSupportRequested: true,
        nativeStatus: _status(
          available: true,
          enabled: true,
          framesProcessed: 2,
          pipelineMode: NoiseSuppressionPipelineMode.deepFilterNet,
          deepFilterNetRuntimeAvailable: true,
          deepFilterNetProcessingApplied: true,
          deepFilterNetFramesProcessed: 2,
          deepFilterNetReason: 'deepfilternet_ready',
        ),
      );

      expect(status.supportModelPresent, isTrue);
      expect(status.supportLayerRequested, isTrue);
      expect(status.missingSupportModelFiles, isEmpty);
      expect(status.failureLabels, isNot(contains('hush_support_not_bundled')));
    });

    test('reports Enhanced waiting for callback audio separately', () async {
      if (!Platform.isWindows) {
        return;
      }

      final status = await NoiseSuppressionEnhancedBackendResolver.resolve(
        requested: true,
        developerModeEnabled: true,
        hushSupportRequested: true,
        nativeStatus: _status(
          available: true,
          enabled: true,
          framesProcessed: 0,
          pipelineMode: NoiseSuppressionPipelineMode.deepFilterNet,
          deepFilterNetRuntimeAvailable: false,
          deepFilterNetReason: 'deepfilternet_not_initialized',
        ),
      );

      expect(status.modelPresent, isTrue);
      expect(status.available, isTrue);
      expect(status.reason, 'deepfilternet_not_initialized');
      expect(status.runtimeAvailable, isFalse);
      expect(status.appIntegrated, isTrue);
      expect(status.callRoomProcessingReady, isFalse);
      expect(
        status.failureLabels,
        contains('enhanced_runtime_waiting_or_unavailable'),
      );
      expect(status.failureLabels, isNot(contains('hush_support_not_bundled')));
    });

    test(
      'reports Enhanced fallback when native mode is not selected',
      () async {
        if (!Platform.isWindows) {
          return;
        }

        final status = await NoiseSuppressionEnhancedBackendResolver.resolve(
          requested: true,
          developerModeEnabled: true,
          nativeStatus: _status(
            available: true,
            enabled: true,
            framesProcessed: 4,
            pipelineMode: NoiseSuppressionPipelineMode.tunedGate,
          ),
        );

        expect(status.modelPresent, isTrue);
        expect(status.available, isFalse);
        expect(status.reason, 'deepfilternet_not_initialized');
        expect(status.runtimeAvailable, isFalse);
        expect(status.appIntegrated, isTrue);
        expect(status.callRoomProcessingReady, isFalse);
        expect(status.productionDefaultChanged, isTrue);
        expect(status.failureLabels, contains('enhanced_mode_not_selected'));
      },
    );

    test('parses native resampler diagnostics from status JSON', () {
      final status = NoiseSuppressionNativeStatus.fromJson(<String, dynamic>{
        'supported': true,
        'available': true,
        'requestedEnabled': true,
        'enabled': true,
        'active': true,
        'framesProcessed': 8,
        'resamplerUses': 16,
        'resamplerInputUnderruns': 1,
        'resamplerOutputUnderruns': 2,
        'resamplerMode': 'windowed_sinc',
        'resamplerInputFrames': 160,
        'resamplerOutputFrames': 480,
        'resamplerSourceRateHz': 16000,
        'resamplerTargetRateHz': 48000,
        'pipelineMode': 'deepfilternet',
        'processingApplied': true,
        'identityFrames': 4,
        'deepFilterNetRuntimeAvailable': true,
        'deepFilterNetProcessingApplied': true,
        'deepFilterNetFramesProcessed': 6,
        'deepFilterNetBypassFrames': 1,
        'deepFilterNetFrameLength': 480,
        'deepFilterNetReason': 'deepfilternet_ready',
        'deepFilterNetLastLocalSnr': 12.25,
        'deepFilterNetSpeechProtectedFrames': 3,
        'deepFilterNetLastSpeechProtectWetMix': 0.58,
        'deepFilterNetAttenuationLimitDb': 60,
        'deepFilterNetPostFilterBeta': 0.02,
        'deepFilterNetTransientSuppressionEnabled': true,
        'deepFilterNetTransientSuppressedFrames': 2,
        'deepFilterNetTransientAdjustedSamples': 96,
        'deepFilterNetLastTransientGain': 0.42,
        'deepFilterNetHushSuppressionEnabled': true,
        'deepFilterNetHushRuntimeAvailable': true,
        'deepFilterNetHushProcessingApplied': true,
        'deepFilterNetHushFramesProcessed': 5,
        'deepFilterNetHushBypassFrames': 1,
        'deepFilterNetHushFrameLength': 160,
        'deepFilterNetHushReason': 'deepfilternet_ready',
        'deepFilterNetHushLastLocalSnr': 7.5,
        'deepFilterNetHushRecoveryFrames': 3,
        'deepFilterNetHushLastRecoveryGain': 1.5,
        'deepFilterNetHushLastInputRms': 0.04,
        'deepFilterNetHushLastOutputRms': 0.038,
        'lastInputMin': -0.25,
        'lastInputMax': 0.5,
        'lastOutputMin': -0.125,
        'lastOutputMax': 0.25,
        'lastInputMaxDelta': 0.2,
        'lastOutputMaxDelta': 0.1,
        'inputClippingSamples': 3,
        'outputClippingSamples': 1,
        'outputLimiterSamples': 4,
        'outputAntiAliasUses': 8,
        'callbackAverageProcessingMs': 0.5,
        'callbackMaxProcessingMs': 0.9,
        'callbackBudgetMisses': 0,
        'diagnosticCaptureActive': true,
        'diagnosticCaptureStageFiles':
            'webrtc_hook_input.wav,rnnoise_input_48k.wav,'
            'rnnoise_output_48k.wav,deepfilternet_output.wav,'
            'speech_protect_output.wav,transient_guard_output.wav,'
            'hush_input_16k.wav,hush_output_16k.wav,hush_output.wav,'
            'final_to_webrtc.wav,'
            'device_raw_wasapi.wav',
        'wasapiSidecarActive': true,
        'wasapiSidecarFrames': 4800,
        'wasapiSidecarDroppedPackets': 1,
        'wasapiSidecarWrittenFiles': 1,
        'wasapiSidecarSampleRateHz': 48000,
        'wasapiSidecarChannels': 2,
        'wasapiSidecarDeviceResolution': 'selected_device',
        'wasapiSidecarLastError': '',
        'noiseGateClosedGain': 0.015,
        'transientSensitivity': 0.65,
        'fastCloseEnabled': true,
        // Distinct NONZERO values on purpose. These four fields default to 0,
        // so a missing or misspelled parser mapping resolves to 0 and every
        // assertion in an all-zero fixture still passes - the parse would be
        // broken and the test green. Different values also catch two keys
        // wired to the same field.
        'deepFilterNetDryDelayFrames': 2,
        'deepFilterNetWarmupMs': 314.5,
        'deepFilterNetHushWarmupMs': 271.25,
        'deepFilterNetPrewarmPendingFrames': 7,
        'reason': 'ready',
      });

      expect(status.resamplerMode, 'windowed_sinc');
      expect(status.resamplerInputFrames, 160);
      expect(status.resamplerOutputFrames, 480);
      expect(status.resamplerSourceRateHz, 16000);
      expect(status.resamplerTargetRateHz, 48000);
      expect(status.resamplerInputUnderruns, 1);
      expect(status.resamplerOutputUnderruns, 2);
      expect(status.pipelineMode, NoiseSuppressionPipelineMode.deepFilterNet);
      expect(status.processingApplied, isTrue);
      expect(status.identityFrames, 4);
      expect(status.deepFilterNetRuntimeAvailable, isTrue);
      expect(status.deepFilterNetProcessingApplied, isTrue);
      expect(status.deepFilterNetFramesProcessed, 6);
      expect(status.deepFilterNetBypassFrames, 1);
      expect(status.deepFilterNetFrameLength, 480);
      expect(status.deepFilterNetReason, 'deepfilternet_ready');
      expect(status.deepFilterNetLastLocalSnr, 12.25);
      expect(status.deepFilterNetSpeechProtectedFrames, 3);
      expect(status.deepFilterNetLastSpeechProtectWetMix, 0.58);
      expect(status.deepFilterNetAttenuationLimitDb, 60);
      expect(status.deepFilterNetPostFilterBeta, 0.02);
      expect(status.deepFilterNetTransientSuppressionEnabled, isTrue);
      expect(status.deepFilterNetTransientSuppressedFrames, 2);
      expect(status.deepFilterNetTransientAdjustedSamples, 96);
      expect(status.deepFilterNetLastTransientGain, 0.42);
      expect(status.deepFilterNetDryDelayFrames, 2);
      expect(status.deepFilterNetWarmupMs, 314.5);
      expect(status.deepFilterNetHushWarmupMs, 271.25);
      expect(status.deepFilterNetPrewarmPendingFrames, 7);
      expect(status.deepFilterNetHushSuppressionEnabled, isTrue);
      expect(status.deepFilterNetHushRuntimeAvailable, isTrue);
      expect(status.deepFilterNetHushProcessingApplied, isTrue);
      expect(status.deepFilterNetHushFramesProcessed, 5);
      expect(status.deepFilterNetHushBypassFrames, 1);
      expect(status.deepFilterNetHushFrameLength, 160);
      expect(status.deepFilterNetHushReason, 'deepfilternet_ready');
      expect(status.deepFilterNetHushLastLocalSnr, 7.5);
      expect(status.deepFilterNetHushRecoveryFrames, 3);
      expect(status.deepFilterNetHushLastRecoveryGain, 1.5);
      expect(status.deepFilterNetHushLastInputRms, 0.04);
      expect(status.deepFilterNetHushLastOutputRms, 0.038);
      expect(status.lastInputMin, -0.25);
      expect(status.lastInputMax, 0.5);
      expect(status.lastOutputMin, -0.125);
      expect(status.lastOutputMax, 0.25);
      expect(status.lastInputMaxDelta, 0.2);
      expect(status.lastOutputMaxDelta, 0.1);
      expect(status.inputClippingSamples, 3);
      expect(status.outputClippingSamples, 1);
      expect(status.outputLimiterSamples, 4);
      expect(status.outputAntiAliasUses, 8);
      expect(status.callbackAverageProcessingMs, 0.5);
      expect(status.callbackMaxProcessingMs, 0.9);
      expect(status.diagnosticCaptureActive, isTrue);
      expect(
        status.diagnosticCaptureStageFileNames,
        containsAll(<String>[
          'webrtc_hook_input.wav',
          'rnnoise_input_48k.wav',
          'rnnoise_output_48k.wav',
          'deepfilternet_output.wav',
          'speech_protect_output.wav',
          'transient_guard_output.wav',
          'hush_input_16k.wav',
          'hush_output_16k.wav',
          'hush_output.wav',
          'final_to_webrtc.wav',
          'device_raw_wasapi.wav',
        ]),
      );
      expect(status.wasapiSidecarActive, isTrue);
      expect(status.wasapiSidecarFrames, 4800);
      expect(status.wasapiSidecarDroppedPackets, 1);
      expect(status.wasapiSidecarWrittenFiles, 1);
      expect(status.wasapiSidecarSampleRateHz, 48000);
      expect(status.wasapiSidecarChannels, 2);
      expect(status.wasapiSidecarDeviceResolution, 'selected_device');
      expect(status.noiseGateClosedGain, 0.015);
      expect(status.transientSensitivity, 0.65);
      expect(status.fastCloseEnabled, isTrue);
      expect(status.reason, 'ready');
    });

    test(
      'builds local-only report bundle metadata for small WAV artifacts',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'rnnoise-small-wav-report-',
        );
        addTearDown(() async {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });
        await File(
          '${directory.path}${Platform.pathSeparator}capture-metadata.txt',
        ).writeAsString('metadata');
        await File(
          '${directory.path}${Platform.pathSeparator}final_to_webrtc.wav',
        ).writeAsBytes(<int>[0, 1, 2, 3, 4, 5]);

        final bundle = await collectNoiseSuppressionDiagnosticReportBundle(
          directoryPath: directory.path,
        );

        expect(bundle.hasWavArtifacts, isTrue);
        expect(bundle.allWavArtifactsAttached, isFalse);
        expect(bundle.attachments, isEmpty);
        expect(bundle.metadata['type'], 'audio_pipeline_diagnostic_wav_set');
        expect(bundle.metadata['transport_status'], 'local_only');
        expect(bundle.metadata['attached_wav_count'], 0);
        expect(bundle.metadata['omitted_wav_count'], 1);
        expect(
          bundle.userMessage,
          contains('WAV bug-report upload is disabled'),
        );
        final files = bundle.metadata['files']! as List<Object?>;
        final file = files.single! as Map<String, Object?>;
        expect(file['attached'], isFalse);
        expect(file['omitted_reason'], 'bug_report_audio_upload_removed');
        expect(
          File(
            '${directory.path}${Platform.pathSeparator}'
            '$noiseSuppressionDiagnosticManifestFileName',
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('keeps large WAV sets local-only', () async {
      final directory = await Directory.systemTemp.createTemp(
        'rnnoise-large-wav-report-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      await File(
        '${directory.path}${Platform.pathSeparator}final_to_webrtc.wav',
      ).writeAsBytes(List<int>.filled(8192, 7));

      final bundle = await collectNoiseSuppressionDiagnosticReportBundle(
        directoryPath: directory.path,
      );

      expect(bundle.hasWavArtifacts, isTrue);
      expect(bundle.allWavArtifactsAttached, isFalse);
      expect(bundle.attachments, isEmpty);
      expect(bundle.metadata['transport_status'], 'local_only');
      expect(bundle.metadata['omitted_wav_count'], 1);
      expect(bundle.userMessage, contains('WAV bug-report upload is disabled'));
    });
  });
}

NoiseSuppressionNativeStatus _status({
  required bool available,
  required bool enabled,
  int framesProcessed = 0,
  bool formatMismatchDetected = false,
  bool suspiciousOutputDetected = false,
  double lastInputScaleFactor = 1,
  double lastVadProbability = 0,
  double lastInputRms = 0,
  double lastOutputRms = 0,
  double lastOutputRatio = 1,
  double noiseGateClosedGain = 0.03,
  double transientSensitivity = 0,
  bool fastCloseEnabled = false,
  NoiseSuppressionPipelineMode pipelineMode =
      NoiseSuppressionPipelineMode.cleanRnnoise,
  bool deepFilterNetRuntimeAvailable = false,
  bool deepFilterNetProcessingApplied = false,
  int deepFilterNetFramesProcessed = 0,
  int deepFilterNetBypassFrames = 0,
  int deepFilterNetFrameLength = 0,
  String deepFilterNetReason = 'deepfilternet_not_initialized',
  double deepFilterNetLastLocalSnr = 0,
  int deepFilterNetSpeechProtectedFrames = 0,
  double deepFilterNetLastSpeechProtectWetMix = 1,
  double deepFilterNetAttenuationLimitDb = 0,
  double deepFilterNetPostFilterBeta = 0,
  bool deepFilterNetTransientSuppressionEnabled = false,
  int deepFilterNetTransientSuppressedFrames = 0,
  int deepFilterNetTransientAdjustedSamples = 0,
  double deepFilterNetLastTransientGain = 1,
  bool deepFilterNetHushSuppressionEnabled = false,
  bool deepFilterNetHushRuntimeAvailable = false,
  bool deepFilterNetHushProcessingApplied = false,
  int deepFilterNetHushFramesProcessed = 0,
  int deepFilterNetHushBypassFrames = 0,
  int deepFilterNetHushFrameLength = 0,
  String deepFilterNetHushReason = 'deepfilternet_not_initialized',
  double deepFilterNetHushLastLocalSnr = 0,
  int deepFilterNetHushRecoveryFrames = 0,
  double deepFilterNetHushLastRecoveryGain = 1,
  double deepFilterNetHushLastInputRms = 0,
  double deepFilterNetHushLastOutputRms = 0,
  int captureGapEvents = 0,
  double lastCallbackIntervalMs = 0,
  double maxCallbackIntervalMs = 0,
  int framesSinceCaptureResume = 0,
  int deepFilterNetGapRecoveries = 0,
  String reason = 'ready',
}) {
  return NoiseSuppressionNativeStatus(
    supported: true,
    available: available,
    requestedEnabled: enabled,
    enabled: enabled,
    active: enabled && framesProcessed > 0,
    formatMismatchDetected: formatMismatchDetected,
    suspiciousOutputDetected: suspiciousOutputDetected,
    formatMismatchReason: formatMismatchDetected ? 'frame_count' : 'none',
    sampleRateHz: 48000,
    numChannels: 1,
    expectedFramesPer10ms: 480,
    lastNumBands: 1,
    lastNumFrames: 480,
    lastBufferSize: 480,
    framesProcessed: framesProcessed,
    bypassFrames: 0,
    gatedFrames: 0,
    resamplerUses: 0,
    resamplerInputUnderruns: 0,
    resamplerOutputUnderruns: 0,
    resamplerOverruns: 0,
    resamplerMode: 'none',
    resamplerInputFrames: 0,
    resamplerOutputFrames: 0,
    resamplerSourceRateHz: 0,
    resamplerTargetRateHz: 0,
    pipelineMode: pipelineMode,
    vadLowFrames: 0,
    vadMidFrames: 0,
    vadHighFrames: framesProcessed,
    referenceVadThreshold: 0.9,
    recentVadAverage: lastVadProbability,
    speechGraceRemainingFrames: 0,
    referenceSpeechGraceFrames: 20,
    noiseGateClosedGain: noiseGateClosedGain,
    transientSensitivity: transientSensitivity,
    fastCloseEnabled: fastCloseEnabled,
    lastGateReason: 'pass',
    lastGateGain: 1,
    lastInputScaleFactor: lastInputScaleFactor,
    lastVadProbability: lastVadProbability,
    lastInputRms: lastInputRms,
    lastOutputRms: lastOutputRms,
    lastOutputRatio: lastOutputRatio,
    lastInputPeak: lastInputRms,
    lastOutputPeak: lastOutputRms,
    lastInputMin: -lastInputRms,
    lastInputMax: lastInputRms,
    lastOutputMin: -lastOutputRms,
    lastOutputMax: lastOutputRms,
    lastInputMaxDelta: 0,
    lastOutputMaxDelta: 0,
    processingApplied: enabled,
    identityFrames: 0,
    deepFilterNetRuntimeAvailable: deepFilterNetRuntimeAvailable,
    deepFilterNetProcessingApplied: deepFilterNetProcessingApplied,
    deepFilterNetFramesProcessed: deepFilterNetFramesProcessed,
    deepFilterNetBypassFrames: deepFilterNetBypassFrames,
    deepFilterNetFrameLength: deepFilterNetFrameLength,
    deepFilterNetReason: deepFilterNetReason,
    deepFilterNetLastLocalSnr: deepFilterNetLastLocalSnr,
    deepFilterNetSpeechProtectedFrames: deepFilterNetSpeechProtectedFrames,
    deepFilterNetLastSpeechProtectWetMix: deepFilterNetLastSpeechProtectWetMix,
    deepFilterNetAttenuationLimitDb: deepFilterNetAttenuationLimitDb,
    deepFilterNetPostFilterBeta: deepFilterNetPostFilterBeta,
    deepFilterNetTransientSuppressionEnabled:
        deepFilterNetTransientSuppressionEnabled,
    deepFilterNetTransientSuppressedFrames:
        deepFilterNetTransientSuppressedFrames,
    deepFilterNetTransientAdjustedSamples:
        deepFilterNetTransientAdjustedSamples,
    deepFilterNetLastTransientGain: deepFilterNetLastTransientGain,
    deepFilterNetHushSuppressionEnabled: deepFilterNetHushSuppressionEnabled,
    deepFilterNetHushRuntimeAvailable: deepFilterNetHushRuntimeAvailable,
    deepFilterNetHushProcessingApplied: deepFilterNetHushProcessingApplied,
    deepFilterNetHushFramesProcessed: deepFilterNetHushFramesProcessed,
    deepFilterNetHushBypassFrames: deepFilterNetHushBypassFrames,
    deepFilterNetHushFrameLength: deepFilterNetHushFrameLength,
    deepFilterNetHushReason: deepFilterNetHushReason,
    deepFilterNetHushLastLocalSnr: deepFilterNetHushLastLocalSnr,
    deepFilterNetHushRecoveryFrames: deepFilterNetHushRecoveryFrames,
    deepFilterNetHushLastRecoveryGain: deepFilterNetHushLastRecoveryGain,
    deepFilterNetHushLastInputRms: deepFilterNetHushLastInputRms,
    deepFilterNetHushLastOutputRms: deepFilterNetHushLastOutputRms,
    clippingSamples: 0,
    inputClippingSamples: 0,
    outputClippingSamples: 0,
    outputLimiterSamples: 0,
    outputAntiAliasUses: 0,
    nonFiniteSamples: 0,
    callbackAverageProcessingMs: 0,
    callbackMaxProcessingMs: 0,
    callbackBudgetMisses: 0,
    rnnoiseStateResets: 0,
    captureGapEvents: captureGapEvents,
    lastCallbackIntervalMs: lastCallbackIntervalMs,
    maxCallbackIntervalMs: maxCallbackIntervalMs,
    framesSinceCaptureResume: framesSinceCaptureResume,
    deepFilterNetGapRecoveries: deepFilterNetGapRecoveries,
    deepFilterNetDryDelayFrames: 0,
    deepFilterNetWarmupMs: 0,
    deepFilterNetHushWarmupMs: 0,
    deepFilterNetPrewarmPendingFrames: 0,
    diagnosticCaptureActive: false,
    diagnosticCaptureFrames: 0,
    diagnosticCaptureDroppedFrames: 0,
    diagnosticCaptureWrittenFiles: 0,
    diagnosticCaptureLastError: '',
    diagnosticCaptureStageFiles: '',
    wasapiSidecarActive: false,
    wasapiSidecarFrames: 0,
    wasapiSidecarDroppedPackets: 0,
    wasapiSidecarWrittenFiles: 0,
    wasapiSidecarSampleRateHz: 0,
    wasapiSidecarChannels: 0,
    wasapiSidecarDeviceResolution: 'not_started',
    wasapiSidecarLastError: '',
    reason: reason,
  );
}
