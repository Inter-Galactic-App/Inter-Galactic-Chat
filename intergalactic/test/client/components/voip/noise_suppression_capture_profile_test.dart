import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';

void main() {
  group('NoiseSuppressionCaptureProfile', () {
    test('adds RNNoise reference constraints with typed optional entries', () {
      final constraints = <String, dynamic>{};

      final result =
          NoiseSuppressionCaptureProfile.addRnnoiseReferenceConstraints(
        constraints,
      );

      expect((result['sampleRate'] as Map)['ideal'], 48000);
      expect((result['channelCount'] as Map)['ideal'], 1);
      final optional = result['optional'];
      expect(optional, isA<List<Map<String, dynamic>>>());
      final optionalConstraints = optional as List<Map<String, dynamic>>;
      expect(
        optionalConstraints.any((entry) => entry['sampleRate'] == 48000),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['channelCount'] == 1),
        isTrue,
      );
    });

    test('normalizes existing dynamic optional entries before merging', () {
      final constraints = <String, dynamic>{
        'optional': <dynamic>[
          <String, dynamic>{'echoCancellation': true},
          <String, dynamic>{'noiseSuppression': true},
        ],
      };

      final result =
          NoiseSuppressionCaptureProfile.addRnnoiseReferenceConstraints(
        constraints,
      );

      final optional = result['optional'];
      expect(optional, isA<List<Map<String, dynamic>>>());
      final optionalConstraints = optional as List<Map<String, dynamic>>;
      expect(
        optionalConstraints.any((entry) => entry['echoCancellation'] == true),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['noiseSuppression'] == true),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['sampleRate'] == 48000),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['channelCount'] == 1),
        isTrue,
      );
    });

    test('direct WebRTC constraints include RNNoise reference optional entries',
        () {
      final frontend = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseSameConstraints,
      );

      final constraints =
          NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraintsForFrontend(
        frontend,
      );

      expect((constraints['sampleRate'] as Map)['ideal'], 48000);
      expect((constraints['channelCount'] as Map)['ideal'], 1);
      final optionalConstraints =
          constraints['optional'] as List<Map<String, dynamic>>;
      expect(
        optionalConstraints.any((entry) => entry['sampleRate'] == 48000),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['channelCount'] == 1),
        isTrue,
      );
    });

    test('local mic check uses the processed call capture constraints', () {
      final mediaConstraints =
          NoiseSuppressionCaptureProfile.buildLocalProcessedMediaConstraints();

      expect(mediaConstraints['video'], isFalse);
      final audioConstraints = mediaConstraints['audio'] as Map;
      expect(audioConstraints['echoCancellation'], isTrue);
      expect(audioConstraints['noiseSuppression'], isTrue);
      expect(audioConstraints['autoGainControl'], isFalse);
      final optionalConstraints =
          audioConstraints['optional'] as List<Map<String, dynamic>>;
      expect(
        optionalConstraints.any((entry) => entry['echoCancellation'] == true),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['noiseSuppression'] == true),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['autoGainControl'] == false),
        isTrue,
      );
      expect(
        optionalConstraints
            .any((entry) => entry['googAutoGainControl'] == false),
        isTrue,
      );
      expect(
        NoiseSuppressionCaptureProfile.localProcessedCaptureLabel,
        'Local processed capture',
      );
    });

    test('omits no-op microphone volume constraint at full volume', () {
      final constraints =
          NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraints(
        inputVolume: 1,
      );

      expect(constraints.containsKey('volume'), isFalse);
    });

    test('includes reduced microphone volume constraint', () {
      final constraints =
          NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraints(
        inputVolume: 0.5,
      );

      expect(constraints['volume'], 0.5);
    });

    test('WebRTC voice-processing bypass constraints disable frontend DSP', () {
      final constraints =
          NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraints(
        inputVolume: 0.5,
        bypassVoiceProcessing: true,
      );

      expect(constraints['volume'], 0.5);
      expect(constraints['echoCancellation'], isFalse);
      expect(constraints['noiseSuppression'], isFalse);
      expect(constraints['autoGainControl'], isFalse);
      expect(constraints.containsKey('sampleRate'), isFalse);
      expect(constraints.containsKey('channelCount'), isFalse);
      final optionalConstraints =
          constraints['optional'] as List<Map<String, dynamic>>;
      expect(
        optionalConstraints.any((entry) => entry['voiceIsolation'] == false),
        isTrue,
      );
      expect(
        optionalConstraints
            .any((entry) => entry['googTypingNoiseDetection'] == false),
        isTrue,
      );
    });

    test('LiveKit voice-processing bypass constraints disable frontend DSP',
        () {
      final options =
          NoiseSuppressionCaptureProfile.buildLivekitAudioCaptureOptions(
        inputVolume: 0.5,
        bypassVoiceProcessing: true,
      );

      final constraints = options.toMediaConstraintsMap();
      expect(constraints['volume'], 0.5);
      expect(constraints.containsKey('sampleRate'), isFalse);
      expect(constraints.containsKey('channelCount'), isFalse);
      final optionalConstraints =
          constraints['optional'] as List<Map<String, dynamic>>;
      expect(
        optionalConstraints.any((entry) => entry['echoCancellation'] == false),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['noiseSuppression'] == false),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['autoGainControl'] == false),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['voiceIsolation'] == false),
        isTrue,
      );
      expect(
        optionalConstraints
            .any((entry) => entry['googTypingNoiseDetection'] == false),
        isTrue,
      );
    });

    test(
      'normalizes microphone volume preference without boosting above one',
      () {
        expect(
          NoiseSuppressionCaptureProfile.normalizedMicrophoneVolumePreference(
            50,
          ),
          0.5,
        );
        expect(
          NoiseSuppressionCaptureProfile.normalizedMicrophoneVolumePreference(
            200,
          ),
          1.0,
        );
        expect(
          NoiseSuppressionCaptureProfile.volumeConstraintValue(
            2,
            includeVolumeConstraint: true,
          ),
          isNull,
        );
      },
    );

    test(
      'audio processing status reports WebRTC suppression and AGC state',
      () {
        final status = NoiseSuppressionCaptureProfile.audioProcessingStatus();

        expect(status.echoCancellationEnabled, isTrue);
        expect(status.webrtcNoiseSuppressionEnabled, isTrue);
        expect(status.autoGainControlEnabled, isFalse);
        expect(
          status.lines.join('\n'),
          contains('WebRTC noise suppression: on'),
        );
        expect(status.lines.join('\n'), contains('WebRTC auto gain: off'));
        expect(status.lines.join('\n'), contains('Capture override: off'));
        expect(
          status.lines.join('\n'),
          contains('WebRTC high-pass filter: off'),
        );
        expect(
          status.lines.join('\n'),
          contains('WebRTC typing noise detection: on'),
        );
        expect(status.lines.join('\n'), contains('RNNoise 48 kHz request:'));
        expect(status.lines.join('\n'), contains('Mic volume constraint: on'));
        expect(status.lines.join('\n'), contains('RNNoise: off'));
      },
    );

    test('tap-order scenarios freeze only the intended constraints', () {
      expect(
        NoiseSuppressionTapOrderScenario.comparisonBatchOptions,
        orderedEquals(<String>[
          NoiseSuppressionTapOrderScenario.rnnoiseOffDefault,
          NoiseSuppressionTapOrderScenario.identitySameConstraints,
          NoiseSuppressionTapOrderScenario.rnnoiseSameConstraints,
          NoiseSuppressionTapOrderScenario.rnnoiseNoVolume,
          NoiseSuppressionTapOrderScenario.rnnoiseNo48k,
          NoiseSuppressionTapOrderScenario.rnnoiseAgcOn,
          NoiseSuppressionTapOrderScenario.rnnoiseAgcOff,
          NoiseSuppressionTapOrderScenario.rnnoiseNsOff,
          NoiseSuppressionTapOrderScenario.rnnoiseAecOff,
          NoiseSuppressionTapOrderScenario.identityMinimalFrontend,
          NoiseSuppressionTapOrderScenario.rnnoiseMinimalFrontend,
        ]),
      );
      expect(
        NoiseSuppressionTapOrderScenario.comparisonBatchOptions,
        isNot(contains(NoiseSuppressionTapOrderScenario.manual)),
      );

      final same = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseSameConstraints,
      );
      expect(
        same.tapOrderScenario,
        NoiseSuppressionTapOrderScenario.rnnoiseSameConstraints,
      );
      expect(same.debugOverrideActive, isTrue);
      expect(same.echoCancellation, isTrue);
      expect(same.noiseSuppression, isTrue);
      expect(same.autoGainControl, isFalse);
      expect(same.requestRnnoiseReferenceFormat, isTrue);
      expect(same.includeVolumeConstraint, isTrue);

      final identity = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.identitySameConstraints,
      );
      expect(
        identity.tapOrderScenario,
        NoiseSuppressionTapOrderScenario.identitySameConstraints,
      );
      expect(identity.echoCancellation, same.echoCancellation);
      expect(identity.noiseSuppression, same.noiseSuppression);
      expect(identity.autoGainControl, same.autoGainControl);
      expect(
        identity.requestRnnoiseReferenceFormat,
        same.requestRnnoiseReferenceFormat,
      );
      expect(identity.includeVolumeConstraint, same.includeVolumeConstraint);

      final noVolume = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseNoVolume,
      );
      expect(noVolume.includeVolumeConstraint, isFalse);
      expect(noVolume.requestRnnoiseReferenceFormat, isTrue);

      final no48k = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseNo48k,
      );
      expect(no48k.requestRnnoiseReferenceFormat, isFalse);
      expect(no48k.includeVolumeConstraint, isTrue);

      final agcOn = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseAgcOn,
      );
      expect(agcOn.autoGainControl, isTrue);
      expect(agcOn.echoCancellation, same.echoCancellation);
      expect(agcOn.noiseSuppression, same.noiseSuppression);
      expect(
        agcOn.requestRnnoiseReferenceFormat,
        same.requestRnnoiseReferenceFormat,
      );

      final nsOff = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseNsOff,
      );
      expect(nsOff.noiseSuppression, isFalse);
      expect(nsOff.echoCancellation, isTrue);

      final aecOff = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseAecOff,
      );
      expect(aecOff.echoCancellation, isFalse);
      expect(aecOff.noiseSuppression, isTrue);

      final agcOff = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseAgcOff,
      );
      expect(agcOff.autoGainControl, isFalse);
      expect(agcOff.echoCancellation, same.echoCancellation);
      expect(agcOff.noiseSuppression, same.noiseSuppression);
      expect(
        agcOff.requestRnnoiseReferenceFormat,
        same.requestRnnoiseReferenceFormat,
      );

      final identityMinimal = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.identityMinimalFrontend,
      );
      expect(identityMinimal.echoCancellation, isFalse);
      expect(identityMinimal.noiseSuppression, isFalse);
      expect(identityMinimal.autoGainControl, isFalse);
      expect(identityMinimal.typingNoiseDetection, isFalse);
      expect(identityMinimal.requestRnnoiseReferenceFormat, isFalse);
      expect(identityMinimal.includeVolumeConstraint, isFalse);

      final rnnoiseMinimal = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseMinimalFrontend,
      );
      expect(rnnoiseMinimal.echoCancellation, identityMinimal.echoCancellation);
      expect(rnnoiseMinimal.noiseSuppression, identityMinimal.noiseSuppression);
      expect(rnnoiseMinimal.autoGainControl, identityMinimal.autoGainControl);
      expect(
        rnnoiseMinimal.typingNoiseDetection,
        identityMinimal.typingNoiseDetection,
      );
      expect(
        rnnoiseMinimal.requestRnnoiseReferenceFormat,
        identityMinimal.requestRnnoiseReferenceFormat,
      );
      expect(
        rnnoiseMinimal.includeVolumeConstraint,
        identityMinimal.includeVolumeConstraint,
      );
    });
  });
}
