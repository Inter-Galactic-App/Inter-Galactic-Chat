import 'dart:async';

import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/widgets.dart';

class UserPresenceLifecycleWatcher {
  static final UserPresenceLifecycleWatcher _singleton =
      UserPresenceLifecycleWatcher._internal();

  UserPresenceLifecycleWatcher._internal();

  factory UserPresenceLifecycleWatcher() {
    return _singleton;
  }

  bool isInit = false;
  DateTime? lastUpdatedStatus = null;
  Timer? inactivityTimer;
  Timer? _retryTimer;
  UserPresenceStatus? _pendingRetryState;
  UserPresenceStatus? _desiredState;
  int _stateGeneration = 0;
  int? _pendingRetryGeneration;

  void init() {
    if (!isInit) {
      AppLifecycleListener(
        onResume: () {
          inactivityTimer?.cancel();
          inactivityTimer = null;
          unawaited(setState(UserPresenceStatus.online));
        },
        onInactive: () {
          inactivityTimer = Timer(Duration(seconds: 15), () {
            unawaited(setState(UserPresenceStatus.unavailable));
          });
        },
      );
    }

    isInit = true;
  }

  Future<void> setState(UserPresenceStatus state) async {
    final now = DateTime.now();
    final priorPendingState = _pendingRetryState;
    _desiredState = state;
    final generation = ++_stateGeneration;
    if (priorPendingState != null && priorPendingState != state) {
      _cancelRetry();
    }

    if (lastUpdatedStatus != null) {
      if (now.difference(lastUpdatedStatus!).inSeconds < 10) {
        return;
      }
    }

    if (clientManager != null) {
      var succeeded = true;
      for (var client in clientManager!.clients) {
        final component = client.getComponent<UserPresenceComponent>();
        if (component != null) {
          succeeded = await _setComponentStatus(component, state, generation) &&
              succeeded;
        }
      }
      if (!succeeded) {
        return;
      }
    }

    if (generation == _stateGeneration && _desiredState == state) {
      _cancelRetry();
      lastUpdatedStatus = now;
    }
  }

  Future<bool> _setComponentStatus(
    UserPresenceComponent component,
    UserPresenceStatus state,
    int generation,
  ) async {
    try {
      await component.setStatus(state);
      return true;
    } on UserPresenceRateLimitException catch (error) {
      _scheduleRetry(state, error.retryAfter, generation);
      Log.d(
        'Deferring Matrix presence lifecycle update until server rate limit resets',
        category: LogCategory.matrix,
        source: 'presence-lifecycle',
      );
      return false;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to update Matrix presence from app lifecycle',
        category: LogCategory.matrix,
        source: 'presence-lifecycle',
      );
      return false;
    }
  }

  void _scheduleRetry(
    UserPresenceStatus state,
    Duration retryAfter,
    int generation,
  ) {
    _pendingRetryState = state;
    _pendingRetryGeneration = generation;
    _retryTimer?.cancel();
    final delay = retryAfter > Duration.zero
        ? retryAfter
        : const Duration(milliseconds: 500);
    _retryTimer = Timer(delay, () {
      final pendingState = _pendingRetryState;
      final pendingGeneration = _pendingRetryGeneration;
      _pendingRetryState = null;
      _pendingRetryGeneration = null;
      _retryTimer = null;
      if (pendingState != null &&
          pendingGeneration == _stateGeneration &&
          pendingState == _desiredState) {
        unawaited(setState(pendingState));
      }
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _pendingRetryState = null;
    _pendingRetryGeneration = null;
  }
}
