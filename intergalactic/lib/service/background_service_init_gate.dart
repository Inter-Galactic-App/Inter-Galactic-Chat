import 'dart:async';

/// Serializes service initialization and only lets callers announce readiness
/// after the shared initialization has completed. The Android service can
/// receive an automatic init and the foreground isolate's explicit init at
/// nearly the same time; a second caller must not observe a half-registered
/// notification manager.
class BackgroundServiceInitGate {
  Future<void>? _initialization;

  Future<void> run({
    required Future<void> Function() initialize,
    required FutureOr<void> Function() onReady,
  }) async {
    final existing = _initialization;
    if (existing != null) {
      await existing;
      return;
    }

    final initialization = Future<void>.sync(initialize);
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
      rethrow;
    }
    await onReady();
  }
}
