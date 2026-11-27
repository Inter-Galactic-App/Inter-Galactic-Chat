import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'recent_stickers': '{not valid json',
    });
    await preferences.init();
  });

  test('a corrupt sticker preference is repaired by the next write', () async {
    await preferences.setRecentStickers('client-a', [
      {'key': 'sticker-a'},
    ]);

    expect(
      preferences.getRecentStickers('client-a').map((entry) => entry['key']),
      ['sticker-a'],
    );
  });

  test('clearing preferences removes persisted sticker recents', () async {
    await preferences.setRecentStickers('client-a', [
      {'key': 'sticker-a'},
    ]);

    await preferences.clear();

    expect(preferences.getRecentStickers('client-a'), isEmpty);
  });
}
