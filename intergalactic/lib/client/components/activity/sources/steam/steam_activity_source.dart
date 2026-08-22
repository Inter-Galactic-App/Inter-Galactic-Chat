import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/steam/steam_api_client.dart';
import 'package:intergalactic/debug/log.dart';

class SteamActivitySource implements GameActivitySource {
  SteamActivitySource({
    required String Function() summaryEndpoint,
    required String? Function() steamId,
    required bool Function() enabled,
    SteamApiClient? apiClient,
    Duration pollInterval = const Duration(seconds: 60),
    Duration transientFailureGrace = const Duration(minutes: 3),
    DateTime Function()? clock,
  }) : _summaryEndpoint = summaryEndpoint,
       _steamId = steamId,
       _enabled = enabled,
       _apiClient = apiClient ?? SteamApiClient(),
       _pollInterval = pollInterval,
       _transientFailureGrace = transientFailureGrace,
       _clock = clock ?? DateTime.now;

  final String Function() _summaryEndpoint;
  final String? Function() _steamId;
  final bool Function() _enabled;
  final SteamApiClient _apiClient;
  final Duration _pollInterval;
  final Duration _transientFailureGrace;
  final DateTime Function() _clock;
  final StreamController<UserActivity?> _controller =
      StreamController.broadcast();
  final StreamController<String?> _connectionController =
      StreamController.broadcast();

  Timer? _timer;
  UserActivity? _activity;
  String? _connectionIssue;
  bool _polling = false;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime? _lastPlayingActivityAt;
  String? _lastTransientHoldLogKey;

  @override
  String get id => 'steam';

  @override
  ActivityKind get kind => ActivityKind.game;

  @override
  UserActivity? get currentActivity =>
      _isActive && _enabled() ? _activity : null;

  @override
  Stream<UserActivity?> get onActivityChanged => _controller.stream;

  Stream<String?> get onConnectionIssueChanged => _connectionController.stream;
  String? get connectionIssue => _connectionIssue;

  @visibleForTesting
  bool get debugHasActiveTimer => _timer?.isActive ?? false;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('Cannot restart a disposed SteamActivitySource');
    }

    _generation++;
    if (!_enabled()) {
      _running = false;
      _timer?.cancel();
      _timer = null;
      _setActivity(null);
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
    _setConnectionIssue(null);
    _setActivity(null);
  }

  @override
  Future<void> dispose() async {
    await stop();
    _disposed = true;
    _generation++;
    await _controller.close();
    await _connectionController.close();
  }

  @override
  Future<void> executeControl(String controlId) async {
    throw UnsupportedError(
      'Steam activity source does not support controls: $controlId',
    );
  }

  Future<void> refresh() async {
    final generation = _generation;
    if (!_isActive || !_enabled()) {
      _setActivity(null);
      return;
    }

    final endpoint = Uri.tryParse(_summaryEndpoint().trim());
    final steamId = _steamId()?.trim() ?? '';
    if (endpoint == null ||
        !endpoint.hasScheme ||
        endpoint.host.isEmpty ||
        steamId.isEmpty) {
      _setConnectionIssue(
        'Steam activity needs a Steam ID and activity connection.',
      );
      _setActivity(null);
      return;
    }

    if (_polling) {
      return;
    }

    _polling = true;
    try {
      final summary = await _apiClient.getPlayerSummary(
        endpoint: endpoint,
        steamId: steamId,
      );
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      _setConnectionIssue(null);
      _setActivity(summary?.toActivity());
    } on SteamActivityNetworkException catch (error) {
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      _setConnectionIssue(
        'Steam activity could not be reached. Check your Steam connection and try again.',
      );
      if (!_holdCurrentPlayingActivity(
        failureKey: 'network:${error.host}:${error.errorType}',
        reason: error.errorType,
      )) {
        _setActivity(null);
      }
    } catch (_) {
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      _setConnectionIssue(
        'Steam activity could not be checked. Review the Steam connection settings.',
      );
      _setActivity(null);
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
      _setActivity(null);
    }
  }

  void _setConnectionIssue(String? issue) {
    if (_connectionIssue == issue || _connectionController.isClosed) {
      return;
    }

    _connectionIssue = issue;
    _connectionController.add(issue);
  }

  void _setActivity(UserActivity? activity) {
    if ((!_isActive && activity != null) || _controller.isClosed) {
      return;
    }

    if (_sameActivity(activity)) {
      _recordPlayingActivity(activity);
      return;
    }

    _activity = activity;
    _recordPlayingActivity(activity);
    _controller.add(currentActivity);
  }

  void _recordPlayingActivity(UserActivity? activity) {
    if (activity != null && activity.isVisible) {
      _lastPlayingActivityAt = _clock();
    }
  }

  bool _holdCurrentPlayingActivity({
    required String failureKey,
    required String reason,
  }) {
    final activity = _activity;
    final lastPlayingAt = _lastPlayingActivityAt;
    if (activity == null || !activity.isVisible || lastPlayingAt == null) {
      final noHoldKey = 'no_hold:$failureKey';
      if (_lastTransientHoldLogKey != noHoldKey) {
        _lastTransientHoldLogKey = noHoldKey;
        Log.d(
          'Steam activity transient failure has no playing activity to hold '
          'reason=$reason',
          category: LogCategory.app,
          source: 'steam-activity',
        );
      }
      return false;
    }

    final age = _clock().difference(lastPlayingAt);
    if (age > _transientFailureGrace) {
      return false;
    }

    if (_lastTransientHoldLogKey != failureKey) {
      _lastTransientHoldLogKey = failureKey;
      Log.d(
        'Holding last Steam activity through transient provider failure '
        'reason=$reason age_seconds=${age.inSeconds}',
        category: LogCategory.app,
        source: 'steam-activity',
      );
    }
    return true;
  }

  bool get _isActive => _running && !_disposed;

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
        _activity!.metadata['app_id'] == activity.metadata['app_id'];
  }
}
