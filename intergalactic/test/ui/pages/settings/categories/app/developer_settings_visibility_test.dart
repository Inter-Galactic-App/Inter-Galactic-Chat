import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'hide developer settings keeps developer hub but hides app adornments',
    () async {
      SharedPreferences.setMockInitialValues({
        'developer_mode': true,
        'hide_developer_settings': true,
      });
      await globals.preferences.init();

      expect(globals.preferences.developerUiVisible, isFalse);

      final labels = SettingsCategoryApp().tabs
          .map((tab) => tab.label)
          .toList(growable: false);

      expect(labels, contains('Developer'));
      expect(labels, isNot(contains('Experiments')));
    },
  );

  test('developer-only tabs remain visible when not hidden', () async {
    SharedPreferences.setMockInitialValues({
      'developer_mode': true,
      'hide_developer_settings': false,
    });
    await globals.preferences.init();

    expect(globals.preferences.developerUiVisible, isTrue);

    final labels = SettingsCategoryApp().tabs
        .map((tab) => tab.label)
        .toList(growable: false);

    expect(labels, contains('Developer'));
    expect(labels, contains('Experiments'));
  });
}
