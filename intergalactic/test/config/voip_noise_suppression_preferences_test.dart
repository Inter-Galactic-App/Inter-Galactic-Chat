import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'defaults Windows voice suppression to Enhanced DeepFilterNet',
    () async {
      SharedPreferences.setMockInitialValues({});

      final preferences = Preferences();
      await preferences.init();

      expect(preferences.voipNoiseSuppressionEnabled.value, isTrue);
      expect(
        preferences.voipNoiseSuppressionHookMode.value,
        'enhanced_deepfilternet',
      );
      expect(
        preferences.voipNoiseSuppressionDeepFilterNetTransientSuppression.value,
        isFalse,
      );
      expect(
        preferences.voipNoiseSuppressionDeepFilterNetHushSuppression.value,
        isFalse,
      );
    },
  );

  test(
    'Windows baseline migration preserves an explicit user off toggle',
    () async {
      if (!Platform.isWindows) {
        return;
      }

      SharedPreferences.setMockInitialValues({
        'voip_noise_suppression_enabled': false,
        'voip_noise_suppression_hook_mode': 'rnnoise',
      });

      final preferences = Preferences();
      await preferences.init();

      expect(preferences.voipNoiseSuppressionEnabled.value, isFalse);
      expect(
        preferences.voipNoiseSuppressionHookMode.value,
        'enhanced_deepfilternet',
      );
    },
  );

  test(
    'Windows baseline migration preserves explicit diagnostic hooks',
    () async {
      if (!Platform.isWindows) {
        return;
      }

      SharedPreferences.setMockInitialValues({
        'voip_noise_suppression_enabled': true,
        'voip_noise_suppression_hook_mode': 'identity',
      });

      final preferences = Preferences();
      await preferences.init();

      expect(preferences.voipNoiseSuppressionEnabled.value, isTrue);
      expect(preferences.voipNoiseSuppressionHookMode.value, 'identity');
    },
  );
}
