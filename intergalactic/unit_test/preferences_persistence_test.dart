import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates bundled theme display names to stable asset ids', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'app_theme': 'bundled:Light Side'});

    final prefs = Preferences();
    await prefs.init();

    expect(prefs.theme.value, 'bundled:jedi');
  });

  test('enables update checks for users with the old setup default', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'check_for_updates': false});

    final prefs = Preferences();
    await prefs.init();

    expect(prefs.checkForUpdates.value, isTrue);
  });

  test('recognizes and migrates legacy favorite room ids', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'favorite_room_ids': ['local-client:!room:ourgalaxy.space'],
    });

    final prefs = Preferences();
    await prefs.init();

    expect(
      prefs.isRoomFavorite(
        '@preview:ourgalaxy.space:!room:ourgalaxy.space',
        legacyRoomId: 'local-client:!room:ourgalaxy.space',
      ),
      isTrue,
    );

    await prefs.setRoomFavorite(
      '@preview:ourgalaxy.space:!room:ourgalaxy.space',
      true,
      legacyRoomId: 'local-client:!room:ourgalaxy.space',
    );

    expect(prefs.getFavoriteRoomIds(), [
      '@preview:ourgalaxy.space:!room:ourgalaxy.space',
    ]);
  });
}
