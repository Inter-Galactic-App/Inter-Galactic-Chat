import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/audio/windows_call_audio_ducking.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('lower other app volumes defaults to off', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = Preferences();
    await preferences.init();

    expect(preferences.voipLowerOtherAppVolumes.value, isFalse);
  });

  test('an explicit user opt-in survives init', () async {
    SharedPreferences.setMockInitialValues({
      'voip_lower_other_app_volumes': true,
    });

    final preferences = Preferences();
    await preferences.init();

    expect(preferences.voipLowerOtherAppVolumes.value, isTrue);
  });

  test('platform support matches the host platform', () {
    expect(WindowsCallAudioDucking.isSupportedPlatform, Platform.isWindows);
  });

  test(
    'applying the preference degrades quietly whatever the loader reports',
    () {
      // The point of this test is that applying the preference never throws -
      // not that the symbol is missing. Asserting ensureAvailable() == false
      // would make it fail precisely when the patched libwebrtc.dll ships and
      // the feature starts working, which is the opposite of useful.
      //
      // Both states are exercised for real: today's host has no patched
      // libwebrtc loaded (an unresolvable symbol, the same shape as a user on
      // an older libwebrtc.zip), and a host that does have one resolves it.
      WindowsCallAudioDucking.resetForTesting();
      addTearDown(WindowsCallAudioDucking.resetForTesting);

      final available = WindowsCallAudioDucking.ensureAvailable();
      expect(WindowsCallAudioDucking.isAvailable, available);
      expect(
        () => WindowsCallAudioDucking.setLowerOtherAppVolumes(true),
        returnsNormally,
      );
      expect(
        () => WindowsCallAudioDucking.setLowerOtherAppVolumes(false),
        returnsNormally,
      );
    },
  );
}
