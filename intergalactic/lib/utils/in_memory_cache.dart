import 'dart:async';

class InMemoryCache<T> {
  InMemoryCache({
    this.limit = 50,
    this.maxRetention = const Duration(minutes: 10),
    this.pollFrequency = const Duration(minutes: 2),
  }) {
    _timer = Timer(pollFrequency, clean);
  }

  Timer? _timer;
  final int limit;
  final Duration maxRetention;
  final Duration pollFrequency;
  bool _disposed = false;

  final StreamController<String> _controller = StreamController.broadcast();

  Stream<String> get onRemove => _controller.stream;

  final Map<String, (T, DateTime)> _cache = {};

  void put(String key, T value) {
    if (_disposed) {
      return;
    }

    _cache[key] = (value, DateTime.now());
  }

  T? get(String key) {
    if (_disposed) {
      return null;
    }

    return _cache[key]?.$1;
  }

  Future<void> clean() async {
    if (_disposed) {
      return;
    }

    var keys = _cache.keys.toList();

    for (var key in keys) {
      if (_disposed) {
        return;
      }

      var ts = _cache[key]?.$2;
      if (ts == null) continue;

      var diff = DateTime.now().difference(ts).inSeconds;
      if (diff > maxRetention.inSeconds) {
        if (!_controller.isClosed) {
          _controller.add(key);
        }
        _cache.remove(key);
      }

      await Future.delayed(Duration(milliseconds: 200));
    }

    if (!_disposed) {
      _timer = Timer(pollFrequency, clean);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _cache.clear();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
