import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_aurora.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy theme labels migrate to stable stored ids', () async {
    for (final entry in const {
      'Classic Light': 'light',
      'Sol': 'light',
      'Classic Dark': 'dark',
      'Nebula': 'dark',
      'Arnoled': 'amoled',
      'Amoled': 'amoled',
      'Eclipse': 'amoled',
      'Light Side': 'bundled:jedi',
      'Grand Master': 'bundled:jedi',
      'Dark Side': 'bundled:sith',
      'Dark Lord': 'bundled:sith',
    }.entries) {
      SharedPreferences.setMockInitialValues({'app_theme': entry.key});

      final preferences = Preferences();
      await preferences.init();

      expect(preferences.theme.value, entry.value);
    }
  });

  test('aurora resolves through the stable built-in theme id', () async {
    SharedPreferences.setMockInitialValues({'app_theme': 'Aurora'});

    final preferences = Preferences();
    await preferences.init();
    final theme = await preferences.resolveTheme();

    expect(preferences.theme.value, 'aurora');
    expect(theme.colorScheme.primary, ThemeAuroraColors.primary);
  });
}
