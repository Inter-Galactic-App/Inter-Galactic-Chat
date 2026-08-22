class CallSessionEventGate {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  bool shouldProcess({
    required bool isEnding,
    required bool isEnded,
    required bool transientResourcesDisposed,
  }) {
    return !_disposed && !isEnding && !isEnded && !transientResourcesDisposed;
  }

  bool runIfActive({
    required bool isEnding,
    required bool isEnded,
    required bool transientResourcesDisposed,
    required void Function() handleEvent,
  }) {
    if (!shouldProcess(
      isEnding: isEnding,
      isEnded: isEnded,
      transientResourcesDisposed: transientResourcesDisposed,
    )) {
      return false;
    }

    handleEvent();
    return true;
  }

  bool shouldNotify({
    required bool isEnding,
    required bool isEnded,
    required bool transientResourcesDisposed,
    required bool closed,
  }) {
    return !closed &&
        shouldProcess(
          isEnding: isEnding,
          isEnded: isEnded,
          transientResourcesDisposed: transientResourcesDisposed,
        );
  }

  bool notifyIfActive({
    required bool isEnding,
    required bool isEnded,
    required bool transientResourcesDisposed,
    required bool closed,
    required void Function() notify,
  }) {
    if (!shouldNotify(
      isEnding: isEnding,
      isEnded: isEnded,
      transientResourcesDisposed: transientResourcesDisposed,
      closed: closed,
    )) {
      return false;
    }

    notify();
    return true;
  }

  void dispose() {
    _disposed = true;
  }
}
