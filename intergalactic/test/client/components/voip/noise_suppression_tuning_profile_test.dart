import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';

void main() {
  group('NoiseSuppressionTuningProfile', () {
    test('defaults unknown presets to balanced', () {
      final profile = NoiseSuppressionTuningProfile.fromPreferenceValues(
        presetKey: 'missing',
        customVadThreshold: 0.1,
        customSpeechGraceMs: 999,
        customClosedGainPercent: 50,
        customTransientSensitivityPercent: 500,
      );

      expect(profile.presetKey, NoiseSuppressionTuningProfile.balancedKey);
      expect(profile.vadThreshold, 0.91);
      expect(profile.speechGraceFrames, 14);
      expect(profile.closedGain, 0.01);
      expect(profile.transientSensitivity, 0.72);
      expect(profile.fastCloseEnabled, isTrue);
    });

    test('gentle preserves the documented rollback baseline', () {
      final profile = NoiseSuppressionTuningProfile.fromPreferenceValues(
        presetKey: NoiseSuppressionTuningProfile.gentleKey,
        customVadThreshold: 0.95,
        customSpeechGraceMs: 80,
        customClosedGainPercent: 0.5,
        customTransientSensitivityPercent: 85,
      );

      expect(profile.vadThreshold, 0.90);
      expect(profile.speechGraceFrames, 20);
      expect(profile.closedGain, 0.03);
      expect(profile.transientSensitivity, 0);
      expect(profile.fastCloseEnabled, isFalse);
    });

    test('strong uses the aggressive keyboard/transient profile', () {
      final profile = NoiseSuppressionTuningProfile.fromPreferenceValues(
        presetKey: NoiseSuppressionTuningProfile.strongKey,
        customVadThreshold: 0.9,
        customSpeechGraceMs: 200,
        customClosedGainPercent: 3,
        customTransientSensitivityPercent: 20,
      );

      expect(profile.vadThreshold, 0.95);
      expect(profile.speechGraceFrames, 10);
      expect(profile.closedGain, 0.001);
      expect(profile.transientSensitivity, 1.0);
      expect(profile.fastCloseEnabled, isTrue);
    });

    test('custom values are clamped and converted for native config', () {
      final profile = NoiseSuppressionTuningProfile.fromPreferenceValues(
        presetKey: NoiseSuppressionTuningProfile.customKey,
        customVadThreshold: 1.5,
        customSpeechGraceMs: 305,
        customClosedGainPercent: -2,
        customTransientSensitivityPercent: 150,
      );

      expect(profile.vadThreshold, 0.99);
      expect(profile.speechGraceFrames, 30);
      expect(profile.closedGain, 0);
      expect(profile.transientSensitivity, 1);
      expect(profile.fastCloseEnabled, isTrue);
      expect(profile.nativeConfig.speechGraceFrames, 30);
    });
  });
}
