import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_token_store.dart';

class SpotifyAuthConfig {
  const SpotifyAuthConfig({
    required this.clientId,
    required this.redirectUri,
    this.scopes = SpotifyAuthScopes.activityPresenceAndControls,
  });

  final String clientId;
  final String redirectUri;
  final List<String> scopes;

  bool get isConfigured =>
      clientId.trim().isNotEmpty && redirectUri.trim().isNotEmpty;
}

class SpotifyAuthScopes {
  static const readOnlyPresence = <String>[
    'user-read-currently-playing',
    'user-read-playback-state',
  ];

  static const controls = <String>[
    'user-modify-playback-state',
  ];

  static const library = <String>[
    'user-library-read',
    'user-library-modify',
  ];

  static const activityPresenceAndControls = <String>[
    ...readOnlyPresence,
    ...controls,
    ...library,
  ];
}

class SpotifyPkceChallenge {
  const SpotifyPkceChallenge({
    required this.verifier,
    required this.challenge,
  });

  final String verifier;
  final String challenge;
}

class SpotifyAuthRequest {
  const SpotifyAuthRequest({
    required this.uri,
    required this.pkce,
    required this.state,
  });

  final Uri uri;
  final SpotifyPkceChallenge pkce;
  final String state;
}

class SpotifyPkceAuth {
  const SpotifyPkceAuth();

  SpotifyAuthRequest createAuthorizationRequest(SpotifyAuthConfig config) {
    final pkce = createPkceChallenge();
    final state = _randomUrlSafeString(32);

    return SpotifyAuthRequest(
      uri: Uri.https('accounts.spotify.com', '/authorize', {
        'response_type': 'code',
        'client_id': config.clientId,
        'scope': config.scopes.join(' '),
        'redirect_uri': config.redirectUri,
        'code_challenge_method': 'S256',
        'code_challenge': pkce.challenge,
        'state': state,
      }),
      pkce: pkce,
      state: state,
    );
  }

  SpotifyPkceChallenge createPkceChallenge() {
    final verifier = _randomUrlSafeString(64);
    final digest = sha256.convert(ascii.encode(verifier));
    final challenge = base64UrlEncode(digest.bytes).replaceAll('=', '');

    return SpotifyPkceChallenge(
      verifier: verifier,
      challenge: challenge,
    );
  }

  String _randomUrlSafeString(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}

class SpotifyAccountsClient {
  SpotifyAccountsClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<SpotifyTokenSet> exchangeCode({
    required SpotifyAuthConfig config,
    required String code,
    required String codeVerifier,
  }) async {
    final response = await _httpClient.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.redirectUri,
        'code_verifier': codeVerifier,
      },
    );

    return _parseTokenResponse(response);
  }

  Future<SpotifyTokenSet> refreshToken({
    required SpotifyAuthConfig config,
    required String refreshToken,
    List<String> previousScopes = const [],
  }) async {
    final response = await _httpClient.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    var tokens = _parseTokenResponse(response);
    if (tokens.refreshToken == null) {
      tokens = tokens.copyWith(refreshToken: refreshToken);
    }
    if (tokens.scopes.isEmpty && previousScopes.isNotEmpty) {
      tokens = tokens.copyWith(scopes: previousScopes);
    }
    return tokens;
  }

  SpotifyTokenSet _parseTokenResponse(http.Response response) {
    if (response.statusCode != 200) {
      final errorCode = _spotifyErrorCode(response.body);
      throw SpotifyAuthException(
        errorCode == null
            ? 'Spotify token request failed with HTTP ${response.statusCode}.'
            : 'Spotify token request failed with error $errorCode.',
        errorCode: errorCode,
      );
    }

    final decoded = jsonDecode(response.body);
    final json = decoded is Map<String, Object?>
        ? decoded
        : (decoded as Map).map((key, value) => MapEntry(key.toString(), value));

    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const SpotifyAuthException(
        'Spotify token response did not include an access token.',
      );
    }

    final expiresIn = json['expires_in'] as int?;
    final scope = json['scope'] as String?;

    return SpotifyTokenSet(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)),
      scopes: scope
              ?.split(' ')
              .where((entry) => entry.trim().isNotEmpty)
              .toList(growable: false) ??
          const [],
    );
  }

  String? _spotifyErrorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      final json = decoded is Map<String, Object?>
          ? decoded
          : (decoded as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            );
      final error = json['error'];
      return error is String && error.trim().isNotEmpty ? error.trim() : null;
    } catch (_) {
      return null;
    }
  }
}

class SpotifyAuthException implements Exception {
  const SpotifyAuthException(this.message, {this.errorCode});

  final String message;
  final String? errorCode;

  bool get isInvalidGrant => errorCode == 'invalid_grant';

  @override
  String toString() {
    return message;
  }
}
