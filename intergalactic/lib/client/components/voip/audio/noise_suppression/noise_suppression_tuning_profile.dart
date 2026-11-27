import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';

class NoiseSuppressionTuningProfile {
  const NoiseSuppressionTuningProfile({
    required this.presetKey,
    required this.vadThreshold,
    required this.speechGraceFrames,
    required this.closedGain,
    required this.transientSensitivity,
    required this.fastCloseEnabled,
  });

  static const String gentleKey = 'gentle';
  static const String balancedKey = 'balanced';
  static const String strongKey = 'strong';
  static const String customKey = 'custom';
  static const String compatibilityKey = 'compatibility';
  static const String defaultPresetKey = balancedKey;

  static const NoiseSuppressionTuningProfile gentle =
      NoiseSuppressionTuningProfile(
        presetKey: gentleKey,
        vadThreshold: 0.90,
        speechGraceFrames: 20,
        closedGain: 0.03,
        transientSensitivity: 0.0,
        fastCloseEnabled: false,
      );

  static const NoiseSuppressionTuningProfile compatibility =
      NoiseSuppressionTuningProfile(
        presetKey: compatibilityKey,
        vadThreshold: 0.90,
        speechGraceFrames: 20,
        closedGain: 0.03,
        transientSensitivity: 0.0,
        fastCloseEnabled: false,
      );

  static const NoiseSuppressionTuningProfile balanced =
      NoiseSuppressionTuningProfile(
        presetKey: balancedKey,
        vadThreshold: 0.91,
        speechGraceFrames: 14,
        closedGain: 0.01,
        transientSensitivity: 0.72,
        fastCloseEnabled: true,
      );

  static const NoiseSuppressionTuningProfile strong =
      NoiseSuppressionTuningProfile(
        presetKey: strongKey,
        vadThreshold: 0.95,
        speechGraceFrames: 10,
        closedGain: 0.001,
        transientSensitivity: 1.0,
        fastCloseEnabled: true,
      );

  static const List<String> presetKeys = <String>[
    gentleKey,
    balancedKey,
    strongKey,
    customKey,
  ];

  final String presetKey;
  final double vadThreshold;
  final int speechGraceFrames;
  final double closedGain;
  final double transientSensitivity;
  final bool fastCloseEnabled;

  int get speechGraceMs => speechGraceFrames * 10;
  double get closedGainPercent => closedGain * 100;
  double get transientSensitivityPercent => transientSensitivity * 100;

  /// Builds the static profile-only native config.
  ///
  /// `NoiseSuppressionService` adds runtime preference flags such as
  /// DeepFilterNet transient and Hush support-layer toggles before applying the
  /// config to the native plugin.
  NoiseSuppressionNativeConfig get baseNativeConfig =>
      NoiseSuppressionNativeConfig(
        vadThreshold: vadThreshold,
        speechGraceFrames: speechGraceFrames,
        closedGain: closedGain,
        transientSensitivity: transientSensitivity,
        fastCloseEnabled: fastCloseEnabled,
        deepFilterNetTransientSuppressionEnabled: false,
        deepFilterNetHushSuppressionEnabled: false,
      );

  static NoiseSuppressionTuningProfile fromPreferenceValues({
    required String presetKey,
    required double customVadThreshold,
    required double customSpeechGraceMs,
    required double customClosedGainPercent,
    required double customTransientSensitivityPercent,
  }) {
    return switch (presetKey) {
      gentleKey => gentle,
      compatibilityKey => compatibility,
      strongKey => strong,
      customKey => NoiseSuppressionTuningProfile(
        presetKey: customKey,
        vadThreshold: _clampDouble(customVadThreshold, 0.75, 0.99),
        speechGraceFrames: _speechGraceFramesFromMs(customSpeechGraceMs),
        closedGain: _clampDouble(customClosedGainPercent, 0, 10) / 100.0,
        transientSensitivity:
            _clampDouble(customTransientSensitivityPercent, 0, 100) / 100.0,
        fastCloseEnabled: true,
      ),
      _ => balanced,
    };
  }

  static NoiseSuppressionTuningProfile effectiveForCompatibilityMode(
    NoiseSuppressionTuningProfile profile, {
    required bool compatibilityModeEnabled,
  }) {
    return compatibilityModeEnabled ? compatibility : profile;
  }

  static double _clampDouble(double value, double min, double max) {
    if (value.isNaN) {
      return min;
    }

    if (value < min) {
      return min;
    }

    if (value > max) {
      return max;
    }

    return value;
  }

  static int _speechGraceFramesFromMs(double value) {
    final ms = _clampDouble(value, 0, 300);
    return (ms / 10).round();
  }
}
