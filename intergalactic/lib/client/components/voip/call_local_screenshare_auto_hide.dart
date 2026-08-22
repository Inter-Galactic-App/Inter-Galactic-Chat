import 'dart:async';

abstract class CallLocalScreenshareAutoHideTimer {
  void cancel();
}

typedef CallLocalScreenshareAutoHideTimerFactory =
    CallLocalScreenshareAutoHideTimer Function(
      String tileId,
      Duration duration,
      void Function() onTimeout,
    );

class CallLocalScreenshareAutoHideController {
  CallLocalScreenshareAutoHideController({
    required Duration previewDuration,
    CallLocalScreenshareAutoHideTimerFactory? timerFactory,
  }) : _previewDuration = previewDuration,
       _timerFactory = timerFactory ?? _dartTimer;

  final Duration _previewDuration;
  final CallLocalScreenshareAutoHideTimerFactory _timerFactory;
  final Map<String, CallLocalScreenshareAutoHideTimer> _timers = {};
  bool _disposed = false;

  bool get isDisposed => _disposed;

  int get pendingTimerCount => _timers.length;

  bool hasPendingTimer(String tileId) => _timers.containsKey(tileId);

  void markHandled(String tileId, {required Set<String> autoHiddenTileIds}) {
    if (_disposed) {
      return;
    }

    _timers.remove(tileId)?.cancel();
    autoHiddenTileIds.add(tileId);
  }

  void sync({
    required Set<String> localScreenshareTileIds,
    required bool streamTestRunning,
    required Set<String> autoHiddenTileIds,
    required Set<String> hiddenTileIds,
    required Set<String> shownTileIds,
    required void Function(String tileId) onAutoHide,
  }) {
    if (_disposed) {
      return;
    }

    for (final entry in _timers.entries.toList(growable: false)) {
      if (!localScreenshareTileIds.contains(entry.key)) {
        entry.value.cancel();
        _timers.remove(entry.key);
      }
    }

    autoHiddenTileIds.removeWhere(
      (tileId) => !localScreenshareTileIds.contains(tileId),
    );

    if (streamTestRunning) {
      _cancelAllTimers();
      for (final tileId in localScreenshareTileIds) {
        autoHiddenTileIds.remove(tileId);
        hiddenTileIds.remove(tileId);
        shownTileIds.add(tileId);
      }
      return;
    }

    for (final tileId in localScreenshareTileIds) {
      if (_timers.containsKey(tileId) || autoHiddenTileIds.contains(tileId)) {
        continue;
      }

      _timers[tileId] = _timerFactory(
        tileId,
        _previewDuration,
        () => _fire(tileId, onAutoHide),
      );
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _cancelAllTimers();
  }

  void _fire(String tileId, void Function(String tileId) onAutoHide) {
    _timers.remove(tileId);
    if (_disposed) {
      return;
    }

    onAutoHide(tileId);
  }

  void _cancelAllTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  static CallLocalScreenshareAutoHideTimer _dartTimer(
    String _,
    Duration duration,
    void Function() onTimeout,
  ) {
    return _DartCallLocalScreenshareAutoHideTimer(Timer(duration, onTimeout));
  }
}

class _DartCallLocalScreenshareAutoHideTimer
    implements CallLocalScreenshareAutoHideTimer {
  const _DartCallLocalScreenshareAutoHideTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}
