class DirectCallMediaOperationGate {
  const DirectCallMediaOperationGate._();

  static bool shouldRun({
    required bool active,
    required bool ended,
    required bool disposed,
  }) {
    return active && !ended && !disposed;
  }

  static bool shouldProcessStreamListEvent({
    required bool active,
    required bool ended,
    required bool disposed,
  }) {
    return shouldRun(active: active, ended: ended, disposed: disposed);
  }

  static bool shouldNotify({required bool disposed, required bool closed}) {
    return !disposed && !closed;
  }

  static bool shouldNotifyTransient({
    required bool active,
    required bool ended,
    required bool disposed,
    required bool closed,
  }) {
    return shouldRun(active: active, ended: ended, disposed: disposed) &&
        !closed;
  }
}
