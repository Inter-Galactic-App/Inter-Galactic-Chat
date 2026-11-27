import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_playback.dart';
import 'package:intergalactic/debug/log.dart';

class SpotifyApiClient {
  SpotifyApiClient({
    http.Client? httpClient,
    SpotifyPlaybackParser? parser,
    Duration requestTimeout = const Duration(seconds: 8),
  })  : _httpClient = httpClient ?? http.Client(),
        _parser = parser ?? const SpotifyPlaybackParser(),
        _requestTimeout = requestTimeout;

  final http.Client _httpClient;
  final SpotifyPlaybackParser _parser;
  final Duration _requestTimeout;

  Future<SpotifyPlaybackSnapshot> getCurrentPlayback(String accessToken) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(
            Uri.https('api.spotify.com', '/v1/me/player', {
              'additional_types': 'track,episode',
            }),
            headers: _authHeaders(accessToken),
          )
          .timeout(_requestTimeout);
    } catch (error) {
      _logRequestFailure(
        operation: 'playback',
        method: 'GET',
        path: '/v1/me/player',
        error: error,
      );
      return _networkErrorSnapshot('Spotify playback request failed.');
    }

    return switch (response.statusCode) {
      200 => _parseBody(response.body),
      204 => await _getDeviceFallback(accessToken),
      401 => const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.unauthorized,
          reason: 'Spotify authorization is invalid or expired.',
        ),
      403 => const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.unavailable,
          reason: 'Spotify playback state is unavailable for this account.',
        ),
      429 => const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.rateLimited,
          reason: 'Spotify rate limited playback polling.',
        ),
      _ => SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.error,
          reason: 'Spotify returned HTTP ${response.statusCode}.',
        ),
    };
  }

  Future<String?> getCurrentUserDisplayName(String accessToken) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(
            Uri.https('api.spotify.com', '/v1/me'),
            headers: _authHeaders(accessToken),
          )
          .timeout(_requestTimeout);
    } catch (error) {
      _logRequestFailure(
        operation: 'profile',
        method: 'GET',
        path: '/v1/me',
        error: error,
      );
      return null;
    }

    if (response.statusCode != 200) {
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      final json = decoded is Map<String, Object?>
          ? decoded
          : (decoded as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            );
      final displayName = json['display_name']?.toString().trim();
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }

      final id = json['id']?.toString().trim();
      return id != null && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  Future<SpotifyPlaybackSnapshot> _getDeviceFallback(String accessToken) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(
            Uri.https('api.spotify.com', '/v1/me/player/devices'),
            headers: _authHeaders(accessToken),
          )
          .timeout(_requestTimeout);
    } catch (error) {
      _logRequestFailure(
        operation: 'devices',
        method: 'GET',
        path: '/v1/me/player/devices',
        error: error,
      );
      return _networkErrorSnapshot('Spotify device request failed.');
    }

    return switch (response.statusCode) {
      200 => _parseDevicesBody(response.body),
      401 => const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.unauthorized,
          reason: 'Spotify authorization is invalid or expired.',
        ),
      403 => const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.unavailable,
          reason: 'Spotify device state is unavailable for this account.',
        ),
      429 => const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.rateLimited,
          reason: 'Spotify rate limited device polling.',
        ),
      _ => SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.noActiveDevice,
          reason:
              'Spotify playback returned no content and device lookup returned HTTP ${response.statusCode}.',
        ),
    };
  }

  Future<bool?> isLibraryItemSaved({
    required String accessToken,
    required String itemUri,
  }) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(
            Uri.https('api.spotify.com', '/v1/me/library/contains', {
              'uris': itemUri,
            }),
            headers: _authHeaders(accessToken),
          )
          .timeout(_requestTimeout);
    } catch (error) {
      _logRequestFailure(
        operation: 'library_contains',
        method: 'GET',
        path: '/v1/me/library/contains',
        error: error,
      );
      return null;
    }

    if (response.statusCode != 200) {
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.first == true;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<bool> saveLibraryItem({
    required String accessToken,
    required String itemUri,
  }) async {
    final http.Response response;
    try {
      response = await _httpClient
          .put(
            Uri.https('api.spotify.com', '/v1/me/library', {
              'uris': itemUri,
            }),
            headers: _authHeaders(accessToken),
          )
          .timeout(_requestTimeout);
    } catch (error) {
      _logRequestFailure(
        operation: 'library_save',
        method: 'PUT',
        path: '/v1/me/library',
        error: error,
      );
      return false;
    }

    return _isSuccess(response.statusCode);
  }

  Future<bool> removeLibraryItem({
    required String accessToken,
    required String itemUri,
  }) async {
    final http.Response response;
    try {
      response = await _httpClient
          .delete(
            Uri.https('api.spotify.com', '/v1/me/library', {
              'uris': itemUri,
            }),
            headers: _authHeaders(accessToken),
          )
          .timeout(_requestTimeout);
    } catch (error) {
      _logRequestFailure(
        operation: 'library_remove',
        method: 'DELETE',
        path: '/v1/me/library',
        error: error,
      );
      return false;
    }

    return _isSuccess(response.statusCode);
  }

  Future<bool> play(String accessToken) async {
    return _sendPlaybackCommand(
      accessToken: accessToken,
      method: 'PUT',
      path: '/v1/me/player/play',
    );
  }

  Future<bool> pause(String accessToken) async {
    return _sendPlaybackCommand(
      accessToken: accessToken,
      method: 'PUT',
      path: '/v1/me/player/pause',
    );
  }

  Future<bool> next(String accessToken) async {
    return _sendPlaybackCommand(
      accessToken: accessToken,
      method: 'POST',
      path: '/v1/me/player/next',
    );
  }

  Future<bool> previous(String accessToken) async {
    return _sendPlaybackCommand(
      accessToken: accessToken,
      method: 'POST',
      path: '/v1/me/player/previous',
    );
  }

  Future<bool> _sendPlaybackCommand({
    required String accessToken,
    required String method,
    required String path,
  }) async {
    final request = http.Request(method, Uri.https('api.spotify.com', path))
      ..headers.addAll(_authHeaders(accessToken));
    final http.StreamedResponse response;
    try {
      response = await _httpClient.send(request).timeout(_requestTimeout);
    } catch (error) {
      _logRequestFailure(
        operation: 'playback_command',
        method: method,
        path: path,
        error: error,
      );
      return false;
    }
    try {
      await response.stream.drain<void>();
    } catch (error) {
      _logRequestFailure(
        operation: 'playback_command_body',
        method: method,
        path: path,
        error: error,
      );
      return false;
    }
    if (response.statusCode != 204) {
      Log.d(
        'Spotify request returned non-success '
        'operation=playback_command method=$method path=$path '
        'status=${response.statusCode}',
        category: LogCategory.app,
        source: 'spotify-activity',
      );
    }
    return response.statusCode == 204;
  }

  Map<String, String> _authHeaders(String accessToken) {
    return {'Authorization': 'Bearer $accessToken'};
  }

  bool _isSuccess(int statusCode) {
    return statusCode >= 200 && statusCode < 300;
  }

  SpotifyPlaybackSnapshot _networkErrorSnapshot(String reason) {
    return SpotifyPlaybackSnapshot(
      state: SpotifyPlaybackState.error,
      reason: reason,
    );
  }

  void _logRequestFailure({
    required String operation,
    required String method,
    required String path,
    required Object error,
  }) {
    Log.d(
      'Spotify request failed operation=$operation method=$method path=$path '
      'error=${_errorLabel(error)}',
      category: LogCategory.app,
      source: 'spotify-activity',
    );
  }

  String _errorLabel(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('failed host lookup')) {
      return 'failed_host_lookup';
    }
    if (text.contains('connection closed before full header')) {
      return 'connection_closed_before_header';
    }
    if (text.contains('connection closed')) {
      return 'connection_closed';
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return 'timeout';
    }
    return error.runtimeType.toString();
  }

  SpotifyPlaybackSnapshot _parseBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        return _parser.parseCurrentPlayback(decoded);
      }

      if (decoded is Map) {
        return _parser.parseCurrentPlayback(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      return const SpotifyPlaybackSnapshot(
        state: SpotifyPlaybackState.error,
        reason: 'Spotify playback response could not be decoded.',
      );
    }

    return const SpotifyPlaybackSnapshot(
      state: SpotifyPlaybackState.error,
      reason: 'Spotify playback response was not an object.',
    );
  }

  SpotifyPlaybackSnapshot _parseDevicesBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        return _parser.parseAvailableDevices(decoded);
      }

      if (decoded is Map) {
        return _parser.parseAvailableDevices(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      return const SpotifyPlaybackSnapshot(
        state: SpotifyPlaybackState.error,
        reason: 'Spotify devices response could not be decoded.',
      );
    }

    return const SpotifyPlaybackSnapshot(
      state: SpotifyPlaybackState.error,
      reason: 'Spotify devices response was not an object.',
    );
  }
}
