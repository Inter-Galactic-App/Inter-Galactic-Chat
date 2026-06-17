import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_diagnostic_directory.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';

void main() {
  group('NoiseSuppressionService', () {
    test('keeps WebRTC suppression on until RNNoise has processed frames', () {
      final status = _status(
        available: true,
        enabled: true,
        framesProcessed: 0,
      );

      expect(
        NoiseSuppressionService.shouldReplaceBuiltInNoiseSuppression(
          isWindows: true,
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
          isWindows: true,
          desiredEnabled: true,
          status: status,
        ),
        isFalse,
      );
      expect(
        NoiseSuppressionService.nativeSuppressionLooksHealthy(
          isWindows: true,
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
          isWindows: true,
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
          isWindows: true,
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
            isWindows: true,
            desiredEnabled: true,
            status: status,
          ),
          isFalse,
        );
      }
    });

    test(
      'requests RNNoise reference capture format only when enabled on Windows',
      () {
        expect(
          NoiseSuppressionService.shouldRequestRnnoiseReferenceCaptureFormat(
            isWindows: true,
            desiredEnabled: true,
          ),
          isTrue,
        );
        expect(
          NoiseSuppressionService.shouldRequestRnnoiseReferenceCaptureFormat(
            isWindows: true,
            desiredEnabled: false,
          ),
          isFalse,
        );
        expect(
          NoiseSuppressionService.shouldRequestRnnoiseReferenceCaptureFormat(
            isWindows: false,
            desiredEnabled: true,
          ),
          isFalse,
        );
      },
    );

    test('maps enabled Windows RNNoise presets to native pipeline modes', () {
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isWindows: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.gentle,
        ),
        NoiseSuppressionPipelineMode.cleanRnnoise,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isWindows: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.balanced,
        ),
        NoiseSuppressionPipelineMode.tunedGate,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isWindows: true,
          desiredEnabled: true,
          tuningProfile: NoiseSuppressionTuningProfile.strong,
        ),
        NoiseSuppressionPipelineMode.tunedGate,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isWindows: true,
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
          isWindows: true,
          desiredEnabled: false,
        ),
        NoiseSuppressionPipelineMode.off,
      );
      expect(
        NoiseSuppressionService.pipelineModeForPreference(
          isWindows: false,
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
        NoiseSuppressionService.pipelineModeForPreference(
          isWindows: true,
          desiredEnabled: false,
          diagnosticHookModeOverride: NoiseSuppressionPipelineMode.identity,
        ),
        NoiseSuppressionPipelineMode.identity,
      );
      expect(
        NoiseSuppressionService.nativeHookEnabledForPreference(
          isWindows: true,
          desiredEnabled: false,
          diagnosticHookModeOverride: NoiseSuppressionPipelineMode.identity,
        ),
        isTrue,
      );
      expect(
        NoiseSuppressionService.nativeHookEnabledForPreference(
          isWindows: true,
          desiredEnabled: true,
          diagnosticHookModeOverride: NoiseSuppressionPipelineMode.off,
        ),
        isFalse,
      );
    });

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
        'pipelineMode': 'clean_rnnoise',
        'processingApplied': true,
        'identityFrames': 4,
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
                'rnnoise_output_48k.wav,final_to_webrtc.wav,'
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
        'reason': 'ready',
      });

      expect(status.resamplerMode, 'windowed_sinc');
      expect(status.resamplerInputFrames, 160);
      expect(status.resamplerOutputFrames, 480);
      expect(status.resamplerSourceRateHz, 16000);
      expect(status.resamplerTargetRateHz, 48000);
      expect(status.resamplerInputUnderruns, 1);
      expect(status.resamplerOutputUnderruns, 2);
      expect(status.pipelineMode, NoiseSuppressionPipelineMode.cleanRnnoise);
      expect(status.processingApplied, isTrue);
      expect(status.identityFrames, 4);
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

    test('builds local-only report bundle metadata for small WAV artifacts',
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
              '${directory.path}${Platform.pathSeparator}capture-metadata.txt')
          .writeAsString('metadata');
      await File(
              '${directory.path}${Platform.pathSeparator}final_to_webrtc.wav')
          .writeAsBytes(<int>[0, 1, 2, 3, 4, 5]);

      final bundle = await collectNoiseSuppressionDiagnosticReportBundle(
        directoryPath: directory.path,
      );

      expect(bundle.hasWavArtifacts, isTrue);
      expect(bundle.allWavArtifactsAttached, isFalse);
      expect(bundle.attachments, isEmpty);
      expect(bundle.metadata['transport_status'], 'local_only');
      expect(bundle.metadata['attached_wav_count'], 0);
      expect(bundle.metadata['omitted_wav_count'], 1);
      expect(bundle.userMessage,
          contains('WAV bug-report submission is disabled'));
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
    });

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
              '${directory.path}${Platform.pathSeparator}final_to_webrtc.wav')
          .writeAsBytes(List<int>.filled(8192, 7));

      final bundle = await collectNoiseSuppressionDiagnosticReportBundle(
        directoryPath: directory.path,
      );

      expect(bundle.hasWavArtifacts, isTrue);
      expect(bundle.allWavArtifactsAttached, isFalse);
      expect(bundle.attachments, isEmpty);
      expect(bundle.metadata['transport_status'], 'local_only');
      expect(bundle.metadata['omitted_wav_count'], 1);
      expect(bundle.userMessage,
          contains('WAV bug-report submission is disabled'));
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
    pipelineMode: NoiseSuppressionPipelineMode.cleanRnnoise,
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
    reason: 'ready',
  );
}
