import 'dart:async';

/// Polls [isReady] on [interval] until it returns true or [timeout] elapses,
/// then reports the outcome exactly once via [onReady] or [onTimeout].
///
/// Extracted from the cross-signing page so the "wait for encryption to become
/// available" behaviour is testable without a live Matrix client. Elapsed time
/// is accumulated by counting ticks rather than reading the wall clock, so it
/// stays deterministic under `fake_async` in tests.
class EncryptionReadinessWaiter {
  EncryptionReadinessWaiter({
    required this.isReady,
    required this.onReady,
    required this.onTimeout,
    this.interval = const Duration(milliseconds: 500),
    this.timeout = defaultTimeout,
  });

  /// Must outlast the vodozemac init budget in `MatrixClient._checkSystem`
  /// (3 attempts x 20s, plus 2 x 500ms backoff = ~61s). Timing out sooner would
  /// tell the user to reload or sign out while encryption is still coming up
  /// normally -- reintroducing a milder form of the misleading "wait for chat
  /// sync to finish" message this waiter exists to replace.
  static const Duration defaultTimeout = Duration(seconds: 75);

  final bool Function() isReady;
  final void Function() onReady;
  final void Function() onTimeout;
  final Duration interval;
  final Duration timeout;

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _finished = false;

  bool get isFinished => _finished;

  /// Begins waiting. If [isReady] is already true, [onReady] fires
  /// synchronously and no timer is scheduled.
  void start() {
    if (_finished) {
      return;
    }
    if (isReady()) {
      _finish(onReady);
      return;
    }
    _timer = Timer.periodic(interval, (_) {
      if (_finished) {
        return;
      }
      if (isReady()) {
        _finish(onReady);
        return;
      }
      _elapsed += interval;
      if (_elapsed >= timeout) {
        _finish(onTimeout);
      }
    });
  }

  /// Cancels waiting without firing either callback. Safe to call repeatedly,
  /// including after the waiter has already finished.
  void cancel() {
    _finished = true;
    _timer?.cancel();
    _timer = null;
  }

  void _finish(void Function() callback) {
    if (_finished) {
      return;
    }
    _finished = true;
    _timer?.cancel();
    _timer = null;
    callback();
  }
}
