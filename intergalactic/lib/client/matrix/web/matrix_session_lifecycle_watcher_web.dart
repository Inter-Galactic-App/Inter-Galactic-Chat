import 'dart:async';

import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_html/html.dart' as html;

class MatrixSessionLifecycleWatcher {
  static final MatrixSessionLifecycleWatcher _singleton =
      MatrixSessionLifecycleWatcher._internal();

  MatrixSessionLifecycleWatcher._internal();

  factory MatrixSessionLifecycleWatcher() {
    return _singleton;
  }

  static const Duration _refreshDebounce = Duration(seconds: 5);
  static const Duration _aggressiveRefreshThreshold = Duration(hours: 2);
  static const Duration _visibleHealthCheckInterval = Duration(minutes: 15);

  bool isInit = false;
  DateTime? lastResumeRefreshAt;
  Future<void>? _refreshInFlight;
  AppLifecycleListener? _appLifecycleListener;
  StreamSubscription? _windowFocusSubscription;
  StreamSubscription? _visibilityChangeSubscription;
  StreamSubscription? _windowOnlineSubscription;
  Timer? _visibleHealthCheckTimer;

  void init() {
    if (isInit) return;

    _appLifecycleListener = AppLifecycleListener(
      onResume: () => _scheduleRefresh('app resume'),
    );

    if (BuildConfig.WEB) {
      _windowFocusSubscription = html.window.onFocus.listen((_) {
        _scheduleRefresh('web window focus');
      });
      _visibilityChangeSubscription =
          html.document.onVisibilityChange.listen((_) {
        if (html.document.visibilityState == 'visible') {
          _scheduleRefresh('web visibility change');
        }
      });
      _windowOnlineSubscription = html.window.onOnline.listen((_) {
        _scheduleRefresh('web network online');
      });
      _visibleHealthCheckTimer ??=
          Timer.periodic(_visibleHealthCheckInterval, (_) {
        if (html.document.visibilityState == 'visible') {
          _scheduleRefresh('web session health check');
        }
      });
    }

    isInit = true;
  }

  void dispose() {
    _appLifecycleListener?.dispose();
    _appLifecycleListener = null;
    unawaited(_windowFocusSubscription?.cancel());
    _windowFocusSubscription = null;
    unawaited(_visibilityChangeSubscription?.cancel());
    _visibilityChangeSubscription = null;
    unawaited(_windowOnlineSubscription?.cancel());
    _windowOnlineSubscription = null;
    _visibleHealthCheckTimer?.cancel();
    _visibleHealthCheckTimer = null;
    isInit = false;
  }

  void _scheduleRefresh(String reason) {
    unawaited(refreshAllClients(reason: reason));
  }

  Future<void> refreshAllClients({String reason = 'resume'}) async {
    if (_refreshInFlight != null) {
      return _refreshInFlight!;
    }

    final now = DateTime.now();
    final aggressive = lastResumeRefreshAt != null &&
        now.difference(lastResumeRefreshAt!) >= _aggressiveRefreshThreshold;

    if (lastResumeRefreshAt != null &&
        now.difference(lastResumeRefreshAt!) < _refreshDebounce) {
      return;
    }

    lastResumeRefreshAt = now;
    final refreshFuture = _refreshAllClients(reason, aggressive);
    _refreshInFlight = refreshFuture;

    try {
      await refreshFuture;
    } finally {
      if (identical(_refreshInFlight, refreshFuture)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<void> _refreshAllClients(String reason, bool aggressive) async {
    final manager = clientManager;
    if (manager == null) return;

    Log.i(
      'Refreshing Matrix clients after $reason${aggressive ? ' with extended sync' : ''}',
    );

    for (final client in manager.clients) {
      if (client is MatrixClient) {
        await client.refreshSessionAfterResume(aggressive: aggressive);
      }
    }
  }
}
