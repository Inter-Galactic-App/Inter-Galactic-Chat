import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_token_store.dart';

const defaultSpotifySecureTokenKey = 'intergalactic.spotify.tokens.v1';

abstract class SecureKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class SecureSpotifyTokenStore implements SpotifyTokenStore {
  SecureSpotifyTokenStore({
    SecureKeyValueStore storage = const FlutterSecureKeyValueStore(),
    this.key = defaultSpotifySecureTokenKey,
  }) : _storage = storage;

  final SecureKeyValueStore _storage;
  final String key;

  @override
  Future<void> clear() => _storage.delete(key: key);

  @override
  Future<SpotifyTokenSet?> read() async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await clear();
        return null;
      }
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      final accessToken = payload['access_token'];
      if (accessToken is! String || accessToken.trim().isEmpty) {
        await clear();
        return null;
      }

      return SpotifyTokenSet(
        accessToken: accessToken,
        refreshToken: _stringValue(payload['refresh_token']),
        expiresAt: _dateTimeValue(payload['expires_at']),
        scopes: _scopes(payload['scopes']),
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(SpotifyTokenSet tokens) {
    return _storage.write(
      key: key,
      value: jsonEncode({
        'access_token': tokens.accessToken,
        if (tokens.refreshToken != null) 'refresh_token': tokens.refreshToken,
        if (tokens.expiresAt != null)
          'expires_at': tokens.expiresAt!.toUtc().toIso8601String(),
        'scopes': tokens.scopes,
      }),
    );
  }

  String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }

    return null;
  }

  DateTime? _dateTimeValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  List<String> _scopes(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value.whereType<String>().toList(growable: false);
  }
}
