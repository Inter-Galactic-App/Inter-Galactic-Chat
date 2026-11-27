import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_secure_token_store.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_token_store.dart';

void main() {
  group('SecureSpotifyTokenStore', () {
    test('round trips Spotify tokens through secure storage', () async {
      final storage = _FakeSecureKeyValueStore();
      final store = SecureSpotifyTokenStore(storage: storage);
      final expiresAt = DateTime.utc(2026, 4, 25, 12);

      await store.write(
        SpotifyTokenSet(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: expiresAt,
          scopes: const ['user-read-playback-state'],
        ),
      );

      final tokens = await store.read();

      expect(tokens?.accessToken, 'access');
      expect(tokens?.refreshToken, 'refresh');
      expect(tokens?.expiresAt, expiresAt);
      expect(tokens?.scopes, ['user-read-playback-state']);
    });

    test('clears stored tokens', () async {
      final storage = _FakeSecureKeyValueStore();
      final store = SecureSpotifyTokenStore(storage: storage);
      await store.write(const SpotifyTokenSet(accessToken: 'access'));

      await store.clear();

      expect(await store.read(), isNull);
    });

    test('drops corrupt token payloads', () async {
      final storage = _FakeSecureKeyValueStore()
        ..values[defaultSpotifySecureTokenKey] = '{broken json';
      final store = SecureSpotifyTokenStore(storage: storage);

      expect(await store.read(), isNull);
      expect(storage.values, isEmpty);
    });
  });
}

class _FakeSecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
