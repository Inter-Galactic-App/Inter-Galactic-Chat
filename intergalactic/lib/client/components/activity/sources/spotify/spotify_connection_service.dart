import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_api_client.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_auth.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_playback.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_token_store.dart';
import 'package:intergalactic/debug/log.dart';

enum SpotifyConnectionState {
  disconnected,
  connecting,
  connected,
  cancelled,
  notConfigured,
  failed,
  reconnectRequired,
}

class SpotifyConnectionStatus {
  const SpotifyConnectionStatus({required this.state, this.message});

  final SpotifyConnectionState state;
  final String? message;

  bool get isBusy => state == SpotifyConnectionState.connecting;
  bool get isConnected => state == SpotifyConnectionState.connected;
}

class SpotifyConnectionService {
  SpotifyConnectionService({
    SpotifyAuthConfig? authConfig,
    SpotifyAuthConfig Function()? authConfigProvider,
    required SpotifyTokenStore tokenStore,
    SpotifyPkceAuth? pkceAuth,
    SpotifyAccountsClient? accountsClient,
    SpotifyApiClient? apiClient,
  }) : _authConfigProvider =
           authConfigProvider ??
           (() =>
               authConfig ??
               const SpotifyAuthConfig(clientId: '', redirectUri: '')),
       _tokenStore = tokenStore,
       _pkceAuth = pkceAuth ?? const SpotifyPkceAuth(),
       _accountsClient = accountsClient ?? SpotifyAccountsClient(),
       _apiClient = apiClient ?? SpotifyApiClient();

  final SpotifyAuthConfig Function() _authConfigProvider;
  final SpotifyTokenStore _tokenStore;
  final SpotifyPkceAuth _pkceAuth;
  final SpotifyAccountsClient _accountsClient;
  final SpotifyApiClient _apiClient;
  final StreamController<SpotifyConnectionStatus> _controller =
      StreamController.broadcast();
  bool _disposed = false;

  SpotifyConnectionStatus _status = const SpotifyConnectionStatus(
    state: SpotifyConnectionState.disconnected,
  );

  Stream<SpotifyConnectionStatus> get onStatusChanged => _controller.stream;
  SpotifyConnectionStatus get status => _status;
  SpotifyAuthConfig get authConfig => _authConfigProvider();

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _controller.close();
  }

  Future<SpotifyConnectionStatus> refreshStatus() async {
    final config = authConfig;
    if (!config.isConfigured) {
      return _setStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.notConfigured,
          message: 'Spotify app configuration is missing.',
        ),
      );
    }

    SpotifyTokenSet? tokens;
    try {
      tokens = await _tokenStore.read();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to read Spotify connection status',
      );
      return _setStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.disconnected,
          message: 'Spotify connection could not be read on this device.',
        ),
      );
    }

    if (tokens == null) {
      if (_status.state == SpotifyConnectionState.reconnectRequired) {
        return _status;
      }
      return _setStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.disconnected,
        ),
      );
    }

    if (tokens.isExpired) {
      final refreshToken = tokens.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        return await _clearTokensAndRequireReconnect();
      }

      try {
        tokens = await _accountsClient.refreshToken(
          config: config,
          refreshToken: refreshToken,
          previousScopes: tokens.scopes,
        );
        await _tokenStore.write(tokens);
      } on SpotifyAuthException catch (error) {
        if (error.isInvalidGrant) {
          return await _clearTokensAndRequireReconnect();
        }
        return _setStatus(
          const SpotifyConnectionStatus(
            state: SpotifyConnectionState.failed,
            message:
                'Spotify connection could not be checked. Try again later.',
          ),
        );
      } catch (_) {
        return _setStatus(
          const SpotifyConnectionStatus(
            state: SpotifyConnectionState.failed,
            message:
                'Spotify connection could not be checked. Try again later.',
          ),
        );
      }
    }

    final SpotifyPlaybackSnapshot playback;
    try {
      playback = await _apiClient.getCurrentPlayback(tokens.accessToken);
    } catch (_) {
      // A transport failure says nothing about the authorization, so it must
      // not clear the token store the way an unauthorized answer below does.
      // It must also not escape: main.dart drives refreshStatus through an
      // unawaited call, where an exception becomes an unhandled async error and
      // leaves the reported status stale.
      return _setStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.failed,
          message: 'Spotify connection could not be checked. Try again later.',
        ),
      );
    }
    if (playback.state == SpotifyPlaybackState.unauthorized ||
        playback.state == SpotifyPlaybackState.tokenExpired) {
      return await _clearTokensAndRequireReconnect();
    }

    if (playback.state == SpotifyPlaybackState.error) {
      // SpotifyApiClient contains its own transport and decode failures and
      // reports them as `error` rather than throwing, so reaching here means
      // the check did not complete. Falling through to `connected` announced
      // that the connection was active on the strength of a request that
      // failed. The tokens are not implicated, so they are left alone.
      return _setStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.failed,
          message: 'Spotify connection could not be checked. Try again later.',
        ),
      );
    }

    return _setStatus(
      const SpotifyConnectionStatus(
        state: SpotifyConnectionState.connected,
        message: 'Spotify connection is active on this device.',
      ),
    );
  }

  /// Clears the stored credentials, then reports that a reconnect is needed.
  ///
  /// `reconnectRequired` is only honest once the tokens are actually gone, and
  /// the clear can fail. It used to escape `refreshStatus`, which main.dart
  /// drives through an unawaited call - so a failed clear became an unhandled
  /// asynchronous error at startup and left the status stale.
  Future<SpotifyConnectionStatus> _clearTokensAndRequireReconnect() async {
    try {
      await _tokenStore.clear();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Could not clear the stored Spotify credentials.',
      );
      return _setStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.failed,
          message: 'Spotify connection could not be checked. Try again later.',
        ),
      );
    }
    return _reconnectRequired();
  }

  SpotifyConnectionStatus _reconnectRequired() {
    return _setStatus(
      const SpotifyConnectionStatus(
        state: SpotifyConnectionState.reconnectRequired,
        message:
            'Spotify authorization expired. Reconnect Spotify to continue.',
      ),
    );
  }

  Future<SpotifyConnectionStatus> connect() async {
    final config = authConfig;
    if (!config.isConfigured) {
      return _setStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.notConfigured,
          message: 'Configure your Spotify app Client ID and Redirect URI.',
        ),
      );
    }

    _setStatus(
      const SpotifyConnectionStatus(
        state: SpotifyConnectionState.connecting,
        message: 'Opening Spotify sign in...',
      ),
    );

    final request = _pkceAuth.createAuthorizationRequest(config);

    try {
      final result = await FlutterWebAuth2.authenticate(
        url: request.uri.toString(),
        callbackUrlScheme: _callbackUrlScheme(config.redirectUri),
        options: const FlutterWebAuth2Options(useWebview: false),
      );

      final callback = Uri.parse(result);
      final error = callback.queryParameters['error'];
      if (error != null && error.isNotEmpty) {
        return _setStatus(
          SpotifyConnectionStatus(
            state: SpotifyConnectionState.failed,
            message: 'Spotify authorization failed: $error',
          ),
        );
      }

      final state = callback.queryParameters['state'];
      if (state != request.state) {
        return _setStatus(
          const SpotifyConnectionStatus(
            state: SpotifyConnectionState.failed,
            message: 'Spotify authorization returned an unexpected state.',
          ),
        );
      }

      final code = callback.queryParameters['code'];
      if (code == null || code.isEmpty) {
        return _setStatus(
          const SpotifyConnectionStatus(
            state: SpotifyConnectionState.failed,
            message: 'Spotify authorization did not return a code.',
          ),
        );
      }

      final tokens = await _accountsClient.exchangeCode(
        config: config,
        code: code,
        codeVerifier: request.pkce.verifier,
      );

      await _tokenStore.write(tokens);
      return _setStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.connected,
          message: 'Spotify connection is saved on this device.',
        ),
      );
    } catch (error) {
      if (error is PlatformException && error.code == 'CANCELED') {
        return _setStatus(
          const SpotifyConnectionStatus(
            state: SpotifyConnectionState.cancelled,
            message: 'Spotify sign in was cancelled.',
          ),
        );
      }

      return _setStatus(
        SpotifyConnectionStatus(
          state: SpotifyConnectionState.failed,
          message: error.toString(),
        ),
      );
    }
  }

  Future<void> disconnect() async {
    await _tokenStore.clear();
    _setStatus(
      const SpotifyConnectionStatus(
        state: SpotifyConnectionState.disconnected,
        message: 'Spotify disconnected.',
      ),
    );
  }

  SpotifyConnectionStatus _setStatus(SpotifyConnectionStatus status) {
    _status = status;
    if (!_disposed && !_controller.isClosed) {
      _controller.add(status);
    }
    return status;
  }

  String _callbackUrlScheme(String redirectUri) {
    final uri = Uri.parse(redirectUri);
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$port';
    }

    return uri.scheme;
  }
}
