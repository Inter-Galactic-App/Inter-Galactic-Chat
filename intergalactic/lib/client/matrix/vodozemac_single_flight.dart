import 'dart:async';

/// Encryption readiness as the rest of the app is allowed to see it.
///
/// Web session restore awaits vodozemac before any restored Matrix client is
/// created. That ordering is a fail-closed requirement - restoring a session
/// before crypto is ready is what left web sessions unencrypted for their
/// whole lifetime - so the wait is not shortened here. What was missing is a
/// state anyone else can READ: while the wait is in progress, and after it has
/// finally failed, surfaces that act directly on encryption had nothing to
/// consult and offered themselves as though crypto were ready.
enum EncryptionAvailability {
  /// Initialization has not finished. Fail closed: treat as not ready.
  pending,

  /// vodozemac initialized. Direct encryption actions may proceed.
  ready,

  /// The bounded retry budget was exhausted. Fail closed, and say so, rather
  /// than leaving surfaces looking operable.
  unavailable,
}

/// Runs vodozemac initialization at most once at a time (CodeRabbit #8).
///
/// The caller bounds each attempt with its own `timeout`, and a Dart timeout
/// does NOT cancel the work it gave up on. Without a latch, attempt two called
/// the initializer again while attempt one's WASM download and bridge setup
/// were still running, so a slow cold start could have two initializations in
/// flight against the same runtime. The completed-initialization check that
/// stood in for this only helps once one of them has finished, which is
/// exactly when the race no longer matters.
///
/// So: a call that arrives while an attempt is pending joins THAT attempt
/// instead of starting another. A failed attempt clears the latch, because a
/// genuine failure must still be retryable - the retry budget exists for the
/// case where the first attempt really did fail, not only for slow ones.
class VodozemacSingleFlight {
  Future<void>? _inFlight;

  /// Whether an attempt is currently running.
  bool get hasAttemptInFlight => _inFlight != null;

  Future<void> run({
    required bool Function() isInitialized,
    required Future<void> Function() initialize,
  }) {
    if (isInitialized()) {
      return Future<void>.value();
    }

    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    final started = initialize();
    _inFlight = started;

    // Two jobs, and the error absorption is not optional. The caller that
    // started this attempt may have already walked away on its own timeout,
    // so if the attempt then fails there would be no listener and the failure
    // would surface as an unhandled async error. This listener is one, and it
    // also clears the latch on both outcomes so a failure can be retried.
    unawaited(
      started
          .then<void>((_) {}, onError: (Object _, StackTrace __) {})
          .whenComplete(() {
            if (identical(_inFlight, started)) {
              _inFlight = null;
            }
          }),
    );

    return started;
  }

  /// Drops the latch without touching the attempt it was holding. For tests
  /// that need a clean instance; production has no reason to call it.
  void reset() {
    _inFlight = null;
  }
}
