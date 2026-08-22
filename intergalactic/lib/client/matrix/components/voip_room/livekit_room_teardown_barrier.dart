import 'dart:async';

import 'package:flutter/foundation.dart';

/// Coordinates native LiveKit room teardown across call-room components.
///
/// A Matrix client can leave one call room and join another before the first
/// component finishes releasing its native LiveKit room. The next native room
/// setup waits for the prior disposal marker, with a caller-owned timeout, so
/// the common path cannot overlap native Room lifecycles indefinitely.
///
/// A teardown whose native release could not be *confirmed* additionally
/// quarantines the Matrix client: joins are vetoed while the previous native
/// room may still be alive (BUG-268). That quarantine is deliberately
/// short-lived. It used to be a process-global `Set<String>` with no eraser
/// other than a test-only reset, so a single slow teardown blocked calling on
/// that account in *every* room until the app was restarted — the
/// "I left a call and now I can only rejoin by restarting" defect. Three
/// separate routes now lift it:
///
///  * [LiveKitRoomTeardownTicket.complete] on any ticket for the client — the
///    native room is confirmed released, including when the confirmation
///    arrives after the caller's timeout already gave up on it;
///  * [register] for a fresh teardown, which supersedes the stale failure and
///    re-gates joins on the new pending teardown instead;
///  * [failedTeardownQuarantine] elapsing, so recovery never depends on
///    another teardown happening at all.
class LiveKitRoomTeardownBarrier {
  LiveKitRoomTeardownBarrier._();

  /// How long a client stays quarantined after a native teardown could not be
  /// confirmed released.
  ///
  /// Sized against the hang-up budgets it backstops: five seconds for the
  /// LiveKit disconnect plus two for the native dispose. Six times that total
  /// leaves room for a slow-but-working release to land and report itself,
  /// while keeping the worst case a retry the user can sit through rather than
  /// an app restart.
  static const Duration failedTeardownQuarantine = Duration(seconds: 30);

  static final Map<String, Future<void>> _pendingByClient =
      <String, Future<void>>{};

  /// When each client's most recent unconfirmed teardown was recorded.
  ///
  /// A timestamp rather than a membership flag: the entry has to be able to
  /// age out on its own.
  static final Map<String, _FailedTeardown> _failedTeardownsAt =
      <String, _FailedTeardown>{};

  static DateTime Function() _clock = DateTime.now;

  static LiveKitRoomTeardownTicket register(String clientKey) {
    // A new teardown supersedes an older unconfirmed one: from here the join
    // gate is held by this ticket's pending future, which is the mechanism
    // that actually prevents overlapping native Room lifetimes. Leaving the
    // old failure in place on top of it only adds a veto nothing can clear.
    _failedTeardownsAt.remove(clientKey);

    final completer = Completer<void>();
    final previous = _pendingByClient[clientKey];
    final pending = previous == null
        ? completer.future
        : Future.wait<void>([previous, completer.future]).then<void>((_) {});

    _pendingByClient[clientKey] = pending;
    unawaited(
      pending.then<void>(
        (_) {
          if (identical(_pendingByClient[clientKey], pending)) {
            _pendingByClient.remove(clientKey);
          }
        },
        onError: (_, __) {
          if (identical(_pendingByClient[clientKey], pending)) {
            _pendingByClient.remove(clientKey);
          }
        },
      ),
    );

    return LiveKitRoomTeardownTicket._(completer, clientKey);
  }

  static Future<bool> waitForPending({
    required String clientKey,
    required Duration timeout,
    DateTime Function()? now,
  }) async {
    final clock = now ?? _clock;
    final deadline = clock().add(timeout);
    while (true) {
      if (_isQuarantined(clientKey, clock)) {
        return false;
      }

      final pending = _pendingByClient[clientKey];
      if (pending == null) {
        return true;
      }

      final remaining = deadline.difference(clock());
      if (remaining <= Duration.zero) {
        return false;
      }

      try {
        await pending.timeout(remaining);
      } on TimeoutException {
        return false;
      }

      if (identical(_pendingByClient[clientKey], pending)) {
        return !_isQuarantined(clientKey, clock);
      }
    }
  }

  static int get debugPendingClientCount => _pendingByClient.length;

  static bool hasFailedTeardown(String clientKey, {DateTime Function()? now}) =>
      _isQuarantined(clientKey, now ?? _clock);

  /// How much of [failedTeardownQuarantine] is left for [clientKey], or `null`
  /// when the client is not quarantined.
  ///
  /// Exists so the join refusal can tell the user this clears by itself.
  static Duration? quarantineRemaining(
    String clientKey, {
    DateTime Function()? now,
  }) {
    final clock = now ?? _clock;
    if (!_isQuarantined(clientKey, clock)) {
      return null;
    }

    final failedAt = _failedTeardownsAt[clientKey]!.at;
    return failedTeardownQuarantine - clock().difference(failedAt);
  }

  static void debugResetForTesting() {
    _pendingByClient.clear();
    _failedTeardownsAt.clear();
    _clock = DateTime.now;
  }

  @visibleForTesting
  static void debugSetClockForTesting(DateTime Function()? clock) {
    _clock = clock ?? DateTime.now;
  }

  static bool _isQuarantined(String clientKey, DateTime Function() clock) {
    final failure = _failedTeardownsAt[clientKey];
    if (failure == null) {
      return false;
    }

    if (clock().difference(failure.at) >= failedTeardownQuarantine) {
      _failedTeardownsAt.remove(clientKey);
      return false;
    }

    return true;
  }

  static void _recordFailure(String clientKey, Object owner) {
    _failedTeardownsAt[clientKey] = _FailedTeardown(at: _clock(), owner: owner);
  }

  /// Lifts a quarantine only when [owner] is the ticket that recorded it.
  ///
  /// Ownership matters because tickets overlap. A late completion from an older
  /// teardown must not clear a quarantine a NEWER teardown recorded: ticket A
  /// fails, ticket B registers and fails, then A completes late — without this
  /// check A would clear B's failure and let a join through while B's native
  /// room may still be alive, which is the overlap BUG-268 exists to prevent.
  static void _clearFailure(String clientKey, Object owner) {
    final failure = _failedTeardownsAt[clientKey];
    if (failure == null || !identical(failure.owner, owner)) {
      return;
    }
    _failedTeardownsAt.remove(clientKey);
  }
}

/// An unconfirmed teardown, and which ticket recorded it.
class _FailedTeardown {
  const _FailedTeardown({required this.at, required this.owner});

  final DateTime at;
  final Object owner;
}

class LiveKitRoomTeardownTicket {
  LiveKitRoomTeardownTicket._(this._completer, this._clientKey);

  final Completer<void> _completer;
  final String _clientKey;

  /// Whether this ticket has already confirmed the native room was released.
  ///
  /// Settlement is monotonic in one direction only: once release is confirmed,
  /// nothing may re-quarantine on this ticket's behalf. The two teardown steps
  /// settle independently, so `livekitRoom.dispose()` can succeed and call
  /// [complete] while the bounded `disconnectCall()` is still running and later
  /// times out into [fail]. Without this flag that ordering re-quarantines a
  /// client whose room is already gone — reintroducing the P0-1 lockout through
  /// the opposite ordering to the one it was fixed for.
  bool _releaseConfirmed = false;

  /// The native room is confirmed released.
  ///
  /// This lifts any quarantine recorded for the client, *including one this
  /// same ticket recorded earlier*: the native dispose is bounded by its
  /// caller, so a dispose that overran its budget and then succeeded reports
  /// [fail] first and [complete] second. That sequence is a slow success, and
  /// treating it as a permanent failure is what made a transient stall look
  /// like a broken install.
  void complete() {
    _releaseConfirmed = true;
    LiveKitRoomTeardownBarrier._clearFailure(_clientKey, this);
    _settle();
  }

  /// The native room release could not be confirmed; quarantine the client
  /// until it is, a fresh teardown supersedes it, or the quarantine expires.
  void fail() {
    // A confirmed release is final for this ticket. The reverse order -
    // fail() then complete() - is still meaningful and still lifts the
    // quarantine: that is the slow-success case documented on [complete].
    if (_releaseConfirmed) {
      _settle();
      return;
    }

    LiveKitRoomTeardownBarrier._recordFailure(_clientKey, this);
    _settle();
  }

  void _settle() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}
