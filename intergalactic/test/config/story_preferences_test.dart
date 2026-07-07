import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uploaded story auto-download preference defaults off and persists',
      () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = Preferences();
    await preferences.init();

    expect(preferences.autoSaveUploadedStories.value, isFalse);

    await preferences.autoSaveUploadedStories.set(true);

    final reloadedPreferences = Preferences();
    await reloadedPreferences.init();

    expect(reloadedPreferences.autoSaveUploadedStories.value, isTrue);
  });
}
