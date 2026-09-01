import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';

/// Every value in a legacy `optional` constraint entry must be a bool or a
/// String, never a number.
///
/// flutter_webrtc's Android `getMapStrValue` stringifies numeric constraints
/// via `ConstraintsMap.getDouble`, which casts directly to `Double`. A Dart
/// `int` arrives as a Java `Integer` and throws ClassCastException while
/// building the microphone track, crashing the app on call join. A double would
/// survive the cast but render "48000.0", which is not a valid sample rate, so
/// strings are the only correct representation here.
void expectAndroidSafeOptionalConstraints(Object? optional) {
  expect(optional, isA<List>());
  for (final entry in optional as List) {
    expect(entry, isA<Map>());
    (entry as Map).forEach((key, value) {
      // Asserted POSITIVELY against the declared contract. `isNot(isA<num>())`
      // was the whole check, which also waves through null, a Map, a List, or
      // any other object - none of which are what the Android side can read,
      // and the numeric case is only the one that happened to crash first.
      expect(
        value,
        anyOf(isA<String>(), isA<bool>()),
        reason:
            "optional constraint '$key' must be a String or a bool; got "
            '${value.runtimeType} ($value). A number in particular crashes '
            'Android in ConstraintsMap.getDouble while building the mic track.',
      );
    });
  }
}

void main() {
  group('NoiseSuppressionCaptureProfile', () {
    test('never emits a numeric value in the optional constraint list', () {
      // Regression guard for the Android call-join crash: the reference-format
      // path is the one that used to inject raw ints.
      final referenced =
          NoiseSuppressionCaptureProfile.addRnnoiseReferenceConstraints(
            <String, dynamic>{},
          );
      expectAndroidSafeOptionalConstraints(referenced['optional']);

      final frontend =
          NoiseSuppressionCaptureProfile.rnnoiseCompatibilityFrontendOptions();
      final built =
          NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraintsForFrontend(
            frontend,
          );
      expectAndroidSafeOptionalConstraints(built['optional']);
    });

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
        optionalConstraints.any((entry) => entry['sampleRate'] == '48000'),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['channelCount'] == '1'),
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
        optionalConstraints.any((entry) => entry['sampleRate'] == '48000'),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['channelCount'] == '1'),
        isTrue,
      );
    });

    test(
      'direct WebRTC constraints include RNNoise reference optional entries',
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
          optionalConstraints.any((entry) => entry['sampleRate'] == '48000'),
          isTrue,
        );
        expect(
          optionalConstraints.any((entry) => entry['channelCount'] == '1'),
          isTrue,
        );
      },
    );

    test('local mic check uses the processed call capture constraints', () {
      final mediaConstraints =
          NoiseSuppressionCaptureProfile.buildLocalProcessedMediaConstraints();

      expect(mediaConstraints['video'], isFalse);
      final audioConstraints = mediaConstraints['audio'] as Map;
      expect(audioConstraints['echoCancellation'], isTrue);
      expect(audioConstraints['noiseSuppression'], isTrue);
      expect(audioConstraints['autoGainControl'], isTrue);
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
        optionalConstraints.any((entry) => entry['autoGainControl'] == true),
        isTrue,
      );
      expect(
        optionalConstraints.any(
          (entry) => entry['googAutoGainControl'] == true,
        ),
        isTrue,
      );
      expect(
        NoiseSuppressionCaptureProfile.localProcessedCaptureLabel,
        'Local processed capture',
      );
    });

    test('the default capture front end enables AGC', () {
      // Enabled 2026-08-20. Measured across three machines: the raw microphone
      // of a participant nobody reports as quiet sits at -23.9 dBFS active
      // speech while the two who do sit at -37.6 and -40.8, and nothing else in
      // the chain can raise a quiet talker - the native processor costs about
      // 1.5 dB and the output limiter never engages.
      final frontend = NoiseSuppressionCaptureProfile.captureFrontendOptions();

      expect(frontend.autoGainControl, isTrue);
      expect(frontend.echoCancellation, isTrue);
      expect(
        frontend.debugOverrideActive,
        isFalse,
        reason: 'this is the path a normal user takes, not the developer one',
      );

      final constraints =
          NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraintsForFrontend(
            frontend,
          );
      expect(constraints['autoGainControl'], isTrue);
    });

    test('AGC stays off in the bypass and compatibility profiles', () {
      // Deliberately NOT changed with the default. The bypass profile exists to
      // disable frontend DSP, so AGC belongs off in it by definition. The
      // RNNoise compatibility profile is a targeted workaround for microphones
      // that pop, and changing a second variable inside it has no evidence
      // behind it - so it keeps its old behaviour until someone measures that
      // combination.
      expect(
        NoiseSuppressionCaptureProfile.voiceProcessingBypassFrontendOptions()
            .autoGainControl,
        isFalse,
      );
      expect(
        NoiseSuppressionCaptureProfile.rnnoiseCompatibilityFrontendOptions()
            .autoGainControl,
        isFalse,
      );
    });

    test('RNNoise compatibility profile disables only WebRTC suppression', () {
      final frontend =
          NoiseSuppressionCaptureProfile.rnnoiseCompatibilityFrontendOptions();

      expect(
        NoiseSuppressionTapOrderScenario.rnnoiseCompatibility,
        NoiseSuppressionService.diagnosticRnnoiseCompatibilityScenarioKey,
      );
      expect(frontend.debugOverrideActive, isFalse);
      expect(
        frontend.tapOrderScenario,
        NoiseSuppressionTapOrderScenario.rnnoiseCompatibility,
      );
      expect(frontend.echoCancellation, isTrue);
      expect(frontend.noiseSuppression, isFalse);
      expect(frontend.autoGainControl, isFalse);
      expect(frontend.highPassFilter, isFalse);
      expect(frontend.typingNoiseDetection, isTrue);
      expect(frontend.requestRnnoiseReferenceFormat, isTrue);
      expect(frontend.includeVolumeConstraint, isTrue);
      expect(frontend.usesRnnoiseCompatibilityMode, isTrue);

      final constraints =
          NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraintsForFrontend(
            frontend,
          );

      expect(constraints['echoCancellation'], isTrue);
      expect(constraints['noiseSuppression'], isFalse);
      expect(constraints['autoGainControl'], isFalse);
      expect((constraints['sampleRate'] as Map)['ideal'], 48000);
      expect((constraints['channelCount'] as Map)['ideal'], 1);
      expect(constraints.containsKey('volume'), isFalse);
      final optionalConstraints =
          constraints['optional'] as List<Map<String, dynamic>>;
      expect(
        optionalConstraints.any(
          (entry) => entry['googNoiseSuppression'] == false,
        ),
        isTrue,
      );
      expect(
        optionalConstraints.any((entry) => entry['voiceIsolation'] == false),
        isTrue,
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
        optionalConstraints.any(
          (entry) => entry['googTypingNoiseDetection'] == false,
        ),
        isTrue,
      );
    });

    test(
      'LiveKit voice-processing bypass constraints disable frontend DSP',
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
          optionalConstraints.any(
            (entry) => entry['echoCancellation'] == false,
          ),
          isTrue,
        );
        expect(
          optionalConstraints.any(
            (entry) => entry['noiseSuppression'] == false,
          ),
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
          optionalConstraints.any(
            (entry) => entry['googTypingNoiseDetection'] == false,
          ),
          isTrue,
        );
      },
    );

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
        expect(status.autoGainControlEnabled, isTrue);
        expect(
          status.lines.join('\n'),
          contains('WebRTC noise suppression: on'),
        );
        expect(status.lines.join('\n'), contains('WebRTC auto gain: on'));
        expect(status.lines.join('\n'), contains('Capture override: off'));
        expect(
          status.lines.join('\n'),
          contains('Native compatibility mode: off'),
        );
        expect(
          status.lines.join('\n'),
          contains('WebRTC high-pass filter: off'),
        );
        expect(
          status.lines.join('\n'),
          contains('WebRTC typing noise detection: on'),
        );
        expect(
          status.lines.join('\n'),
          contains('Native 48 kHz reference request:'),
        );
        expect(status.lines.join('\n'), contains('Mic volume constraint: on'));
        expect(
          status.lines.join('\n'),
          contains('Native noise suppression: off'),
        );
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

      final compatibility = NoiseSuppressionTapOrderScenario.optionsFor(
        NoiseSuppressionTapOrderScenario.rnnoiseCompatibility,
      );
      expect(
        compatibility.tapOrderScenario,
        NoiseSuppressionTapOrderScenario.rnnoiseCompatibility,
      );
      expect(compatibility.debugOverrideActive, isTrue);
      expect(compatibility.noiseSuppression, isFalse);
      expect(compatibility.echoCancellation, isTrue);
      expect(compatibility.autoGainControl, isFalse);
      expect(compatibility.requestRnnoiseReferenceFormat, isTrue);
      expect(compatibility.includeVolumeConstraint, isTrue);

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

    test('call audio instrumentation summary reports platform, call type and '
        'voice-processing bypass intent', () {
      final summary =
          NoiseSuppressionCaptureProfile.callAudioInstrumentationSummary(
            callType: 'group-livekit',
            bypassVoiceProcessing: true,
          );

      expect(summary, startsWith('callAudio '));
      expect(summary, contains('platform='));
      expect(summary, contains('callType=group-livekit'));
      // The voice-processing bypass path disables all WebRTC frontend DSP and
      // records that Apple voice processing is bypassed.
      expect(summary, contains('aec=off'));
      expect(summary, contains('ns=off'));
      expect(summary, contains('agc=off'));
      expect(summary, contains('appleVoiceProcessing=bypassed'));
      expect(summary, contains('nativeAvailable='));
    });
  });
}
