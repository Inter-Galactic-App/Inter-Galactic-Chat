import 'dart:async';

import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
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
        // `paused` is where the B5 trigger releases the account database, so
        // from here until `resumed` there is nothing to write presence into.
        // The overdue inactivity timer used to fire either while the app was
        // backgrounded-and-running (iOS had not frozen it yet) or in the
        // first milliseconds of the wake, before the lifecycle event that
        // re-establishes the database - one rejected presence write every
        // cycle, measured on device. Not writing `unavailable` at all costs
        // nothing: sync stops on `paused`, and the server marks the session
        // away on its own. `onResume` already writes `online`, and setState
        // waits for the trigger's re-establish before touching the database.
        //
        // `paused` only: desktop never enters it, and its minimise-to-`hidden`
        // path must keep the inactivity timer so a minimised desktop still
        // goes `unavailable`.
        onPause: () {
          inactivityTimer?.cancel();
          inactivityTimer = null;
          _cancelRetry();
        },
      );
    }

    isInit = true;
  }

  Future<void> setState(UserPresenceStatus state) async {
    final priorPendingState = _pendingRetryState;
    _desiredState = state;
    final generation = ++_stateGeneration;
    if (priorPendingState != null && priorPendingState != state) {
      _cancelRetry();
    }

    // The database may be released (B5). This listener's onResume runs
    // BEFORE the release trigger's observer on the same lifecycle event, and
    // the wrapper cannot know a re-establish is coming until the trigger has
    // scheduled it - so asking the wrapper is a race that the write loses.
    // The trigger arms this gate at release time; it is already complete
    // when nothing was released.
    // A failed re-establish completes the gate with an error: the write is
    // dropped loudly here, and the trigger retries on the next resume.
    final releaseTrigger = DatabaseReleaseTrigger.instance;
    if (releaseTrigger != null) {
      try {
        await releaseTrigger.whenEstablished;
      } catch (error) {
        // Object, not StateError. The trigger completes this gate only with a
        // StateError today, so nothing else can arrive here yet - but every
        // caller reaches setState through unawaited(), so a future error type
        // would leave as an unhandled asynchronous error instead of a dropped
        // update. The type is logged so a new one is visible when it appears.
        Log.w(
          'Dropping presence lifecycle update: ${error.runtimeType}: $error',
          category: LogCategory.matrix,
          source: 'presence-lifecycle',
        );
        return;
      }
      if (generation != _stateGeneration) {
        return;
      }
    }

    // Taken after the wait so the 10 s dedup window measures from the write.
    final now = DateTime.now();
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
          succeeded =
              await _setComponentStatus(component, state, generation) &&
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
