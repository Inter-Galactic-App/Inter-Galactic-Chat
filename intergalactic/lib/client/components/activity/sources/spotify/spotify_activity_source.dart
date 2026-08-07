import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_api_client.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_auth.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_playback.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_token_store.dart';
import 'package:intergalactic/debug/log.dart';

class SpotifyActivitySource implements MusicActivitySource {
  SpotifyActivitySource({
    SpotifyAuthConfig? authConfig,
    SpotifyAuthConfig Function()? authConfigProvider,
    required SpotifyTokenStore tokenStore,
    required bool Function() enabled,
    SpotifyApiClient? apiClient,
    SpotifyAccountsClient? accountsClient,
    Duration pollInterval = const Duration(seconds: 8),
    Duration transientFailureGrace = const Duration(minutes: 3),
    DateTime Function()? clock,
  })  : _authConfigProvider = authConfigProvider ??
            (() =>
                authConfig ??
                const SpotifyAuthConfig(clientId: '', redirectUri: '')),
        _tokenStore = tokenStore,
        _enabled = enabled,
        _apiClient = apiClient ?? SpotifyApiClient(),
        _accountsClient = accountsClient ?? SpotifyAccountsClient(),
        _pollInterval = pollInterval,
        _transientFailureGrace = transientFailureGrace,
        _clock = clock ?? DateTime.now;

  final SpotifyAuthConfig Function() _authConfigProvider;
  final SpotifyTokenStore _tokenStore;
  final bool Function() _enabled;
  final SpotifyApiClient _apiClient;
  final SpotifyAccountsClient _accountsClient;
  final Duration _pollInterval;
  final Duration _transientFailureGrace;
  final DateTime Function() _clock;
  final StreamController<UserActivity?> _controller =
      StreamController.broadcast();

  Timer? _timer;
  UserActivity? _activity;
  bool _polling = false;
  int _generation = 0;
  bool _running = false;
  bool _disposed = false;
  DateTime? _lastPlayableActivityAt;
  String? _lastTransientHoldLogKey;

  @override
  String get id => 'spotify';

  @override
  ActivityKind get kind => ActivityKind.music;

  @override
  UserActivity? get currentActivity =>
      _isActive && _enabled() ? _activity : null;

  @override
  Stream<UserActivity?> get onActivityChanged => _controller.stream;

  @visibleForTesting
  bool get debugHasActiveTimer => _timer?.isActive ?? false;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('Cannot restart a disposed SpotifyActivitySource');
    }

    _generation++;
    if (!_enabled()) {
      _running = false;
      _timer?.cancel();
      _timer = null;
      _clearActivity();
      return;
    }

    _running = true;
    final generation = _generation;
    await refresh();
    if (!_isCurrentGeneration(generation) || !_enabled()) {
      return;
    }

    _timer ??= Timer.periodic(_pollInterval, (_) {
      unawaited(refresh());
    });
  }

  @override
  Future<void> stop() async {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _clearActivity();
  }

  @override
  Future<void> dispose() async {
    await stop();
    _disposed = true;
    _generation++;
    await _controller.close();
  }

  @override
  Future<void> executeControl(String controlId) async {
    final config = authConfig;
    if (!_isActive || !_enabled() || !config.isConfigured) {
      return;
    }

    final generation = _generation;
    final tokens = await _readUsableTokens(generation, config);
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    if (tokens == null) {
      return;
    }

    var success = false;
    switch (controlId) {
      case 'previous':
        if (tokens.hasScopes(SpotifyAuthScopes.controls)) {
          success = await _apiClient.previous(tokens.accessToken);
        }
        break;
      case 'play_pause':
        if (tokens.hasScopes(SpotifyAuthScopes.controls)) {
          final isPlaying =
              _activity?.metadata['state'] == SpotifyPlaybackState.playing.name;
          success = isPlaying
              ? await _apiClient.pause(tokens.accessToken)
              : await _apiClient.play(tokens.accessToken);
        }
        break;
      case 'next':
        if (tokens.hasScopes(SpotifyAuthScopes.controls)) {
          success = await _apiClient.next(tokens.accessToken);
        }
        break;
      case 'save_track':
        if (tokens.hasScope('user-library-modify')) {
          final trackUri = _currentTrackUri();
          if (trackUri != null) {
            success = await _apiClient.saveLibraryItem(
              accessToken: tokens.accessToken,
              itemUri: trackUri,
            );
          }
        }
        break;
      case 'remove_saved_track':
        if (tokens.hasScope('user-library-modify')) {
          final trackUri = _currentTrackUri();
          if (trackUri != null) {
            success = await _apiClient.removeLibraryItem(
              accessToken: tokens.accessToken,
              itemUri: trackUri,
            );
          }
        }
        break;
      default:
        return;
    }

    if (success) {
      if (controlId == 'next' || controlId == 'previous') {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      await refresh();
    }
  }

  Future<void> refresh() async {
    final generation = _generation;
    if (!_isActive || !_enabled()) {
      _setActivity(null);
      return;
    }

    final config = authConfig;
    if (!config.isConfigured) {
      _setActivity(
        const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.notConnected,
          reason: 'Spotify client id or redirect uri is not configured.',
        ).toActivity(),
      );
      return;
    }

    final tokens = await _readUsableTokens(generation, config);
    if (!_isCurrentGeneration(generation)) {
      return;
    }

    if (tokens == null) return;

    if (_polling) {
      return;
    }

    _polling = true;
    try {
      var playback = await _apiClient.getCurrentPlayback(tokens.accessToken);
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      if (_holdCurrentPlayableForTransientFailure(playback)) {
        return;
      }

      final trackUri = playback.trackUri ??
          (playback.trackId == null
              ? null
              : 'spotify:track:${playback.trackId}');
      if (trackUri != null && tokens.hasScope('user-library-read')) {
        final isSaved = await _apiClient.isLibraryItemSaved(
          accessToken: tokens.accessToken,
          itemUri: trackUri,
        );
        if (!_isCurrentGeneration(generation)) {
          return;
        }

        if (isSaved != null) {
          playback = playback.copyWith(isSaved: isSaved);
        }
      }

      _setActivity(
        playback.toActivity(
          playbackControlsEnabled: tokens.hasScopes(SpotifyAuthScopes.controls),
          libraryControlsEnabled: tokens.hasScopes(SpotifyAuthScopes.library),
        ),
      );
    } catch (_) {
      final playback = const SpotifyPlaybackSnapshot(
        state: SpotifyPlaybackState.error,
        reason: 'Spotify playback polling failed.',
      );
      if (!_holdCurrentPlayableForTransientFailure(playback)) {
        _setActivity(playback.toActivity());
      }
    } finally {
      _polling = false;
    }
  }

  void notifySettingsChanged() {
    if (_disposed) {
      return;
    }

    if (_enabled()) {
      if (_running) {
        unawaited(refresh());
      } else {
        unawaited(start());
      }
      return;
    }

    if (_running || _timer != null) {
      unawaited(stop());
    } else {
      _clearActivity();
    }
  }

  Future<SpotifyTokenSet?> _readUsableTokens(
    int generation,
    SpotifyAuthConfig config,
  ) async {
    var tokens = await _tokenStore.read();
    if (!_isCurrentGeneration(generation)) {
      return null;
    }

    if (tokens == null) {
      _setActivity(
        const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.notConnected,
          reason: 'Connect Spotify to show playback activity.',
        ).toActivity(),
      );
      return null;
    }

    if (!tokens.isExpired) {
      return tokens;
    }

    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      _setActivity(
        const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.tokenExpired,
          reason: 'Spotify authorization expired.',
        ).toActivity(),
      );
      return null;
    }

    try {
      tokens = await _accountsClient.refreshToken(
        config: config,
        refreshToken: refreshToken,
        previousScopes: tokens.scopes,
      );
      if (!_isCurrentGeneration(generation)) {
        return null;
      }

      await _tokenStore.write(tokens);
      if (!_isCurrentGeneration(generation)) {
        return null;
      }

      return tokens;
    } catch (error) {
      if (error is SpotifyAuthException && error.isInvalidGrant) {
        await _tokenStore.clear();
        if (!_isCurrentGeneration(generation)) {
          return null;
        }

        _setActivity(
          const SpotifyPlaybackSnapshot(
            state: SpotifyPlaybackState.notConnected,
            reason: 'Spotify authorization expired. Connect Spotify again.',
          ).toActivity(),
        );
        return null;
      }

      if (_isTransientActivityFailure(error) &&
          _holdCurrentPlayableActivity(
            failureKey: 'token_refresh:${error.runtimeType}',
            reason: 'token_refresh',
          )) {
        return null;
      }

      _setActivity(
        const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.unauthorized,
          reason: 'Spotify token refresh failed.',
        ).toActivity(),
      );
      return null;
    }
  }

  String? _currentTrackUri() {
    final metadata = _activity?.metadata;
    final trackUri = metadata?['track_uri'];
    if (trackUri is String && trackUri.trim().isNotEmpty) {
      return trackUri;
    }

    final trackId = metadata?['track_id'];
    if (trackId is String && trackId.trim().isNotEmpty) {
      return 'spotify:track:$trackId';
    }

    return null;
  }

  void _setActivity(UserActivity? activity) {
    if ((!_isActive && activity != null) || _controller.isClosed) {
      return;
    }

    if (_sameActivity(activity)) {
      _recordPlayableActivity(activity);
      return;
    }

    _activity = activity;
    _recordPlayableActivity(activity);
    _controller.add(currentActivity);
  }

  void _clearActivity() {
    final hadActivity = _activity != null;
    _activity = null;
    if (hadActivity && !_controller.isClosed) {
      _controller.add(null);
    }
  }

  void _recordPlayableActivity(UserActivity? activity) {
    if (activity != null && activity.isVisible) {
      _lastPlayableActivityAt = _clock();
    }
  }

  bool _holdCurrentPlayableForTransientFailure(
    SpotifyPlaybackSnapshot playback,
  ) {
    if (playback.state != SpotifyPlaybackState.error &&
        playback.state != SpotifyPlaybackState.rateLimited) {
      return false;
    }

    return _holdCurrentPlayableActivity(
      failureKey: 'playback:${playback.state.name}:${playback.reason ?? ''}',
      reason: playback.state.name,
    );
  }

  bool _holdCurrentPlayableActivity({
    required String failureKey,
    required String reason,
  }) {
    final activity = _activity;
    final lastPlayableAt = _lastPlayableActivityAt;
    if (activity == null || !activity.isVisible || lastPlayableAt == null) {
      final noHoldKey = 'no_hold:$failureKey';
      if (_lastTransientHoldLogKey != noHoldKey) {
        _lastTransientHoldLogKey = noHoldKey;
        Log.d(
          'Spotify activity transient failure has no playable activity to hold '
          'reason=$reason',
          category: LogCategory.app,
          source: 'spotify-activity',
        );
      }
      return false;
    }

    final age = _clock().difference(lastPlayableAt);
    if (age > _transientFailureGrace) {
      return false;
    }

    if (_lastTransientHoldLogKey != failureKey) {
      _lastTransientHoldLogKey = failureKey;
      Log.d(
        'Holding last Spotify activity through transient provider failure '
        'reason=$reason age_seconds=${age.inSeconds}',
        category: LogCategory.app,
        source: 'spotify-activity',
      );
    }
    return true;
  }

  bool _isTransientActivityFailure(Object error) {
    final type = error.runtimeType.toString().toLowerCase();
    final text = error.toString().toLowerCase();
    return type.contains('socket') ||
        type.contains('timeout') ||
        type.contains('clientexception') ||
        type.contains('httpexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection closed') ||
        text.contains('timed out');
  }

  bool get _isActive => _running && !_disposed;
  SpotifyAuthConfig get authConfig => _authConfigProvider();

  bool _isCurrentGeneration(int generation) {
    return _isActive && generation == _generation && !_controller.isClosed;
  }

  bool _sameActivity(UserActivity? activity) {
    if (_activity == null || activity == null) {
      return _activity == activity;
    }

    return _activity!.title == activity.title &&
        _activity!.subtitle == activity.subtitle &&
        _activity!.status == activity.status &&
        _activity!.details == activity.details &&
        _activity!.artworkUrl == activity.artworkUrl &&
        _activity!.externalUrl == activity.externalUrl &&
        _sameControls(_activity!.controls, activity.controls);
  }
}

bool _sameControls(List<ActivityControl> left, List<ActivityControl> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    final leftControl = left[index];
    final rightControl = right[index];
    if (leftControl.id != rightControl.id ||
        leftControl.kind != rightControl.kind ||
        leftControl.label != rightControl.label ||
        leftControl.state != rightControl.state ||
        leftControl.tooltip != rightControl.tooltip) {
      return false;
    }
  }

  return true;
}
