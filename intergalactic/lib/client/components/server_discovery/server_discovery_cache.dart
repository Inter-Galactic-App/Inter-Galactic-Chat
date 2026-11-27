import 'server_discovery_models.dart';

class ServerDiscoveryPageCache {
  ServerDiscoveryPageCache({
    this.maxEntries = 64,
    this.maxAge = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxEntries;
  final Duration maxAge;
  final DateTime Function() _clock;

  final Map<ServerDiscoveryCacheKey, ServerDiscoveryPage> _pages = {};
  final Map<ServerDiscoveryCacheKey, DateTime> _storedAt = {};

  ServerDiscoveryPage? read({
    required ServerDiscoveryScope scope,
    required ServerDiscoveryRequest request,
  }) {
    _evictExpired();
    final key = ServerDiscoveryCacheKey(scope: scope, request: request);
    final page = _pages.remove(key);
    final timestamp = _storedAt.remove(key);
    if (page == null || timestamp == null) {
      return null;
    }
    _pages[key] = page;
    _storedAt[key] = timestamp;
    return page;
  }

  void store(ServerDiscoveryPage page) {
    _evictExpired();
    final key = ServerDiscoveryCacheKey(
      scope: page.scope,
      request: page.request,
    );
    _pages.remove(key);
    _storedAt.remove(key);
    _pages[key] = page;
    _storedAt[key] = _clock();
    _evictOverflow();
  }

  void invalidateScope(ServerDiscoveryScope scope) {
    _pages.removeWhere((key, _) => key.scope == scope);
    _storedAt.removeWhere((key, _) => key.scope == scope);
  }

  void invalidateQuery({
    required ServerDiscoveryScope scope,
    required String query,
    required ServerDiscoveryFilter filter,
  }) {
    final normalizedQuery = query.trim();
    _pages.removeWhere((key, _) {
      return key.scope == scope &&
          key.request.normalizedQuery == normalizedQuery &&
          key.request.filter == filter;
    });
    _storedAt.removeWhere((key, _) {
      return key.scope == scope &&
          key.request.normalizedQuery == normalizedQuery &&
          key.request.filter == filter;
    });
  }

  void clear() {
    _pages.clear();
    _storedAt.clear();
  }

  int get length {
    _evictExpired();
    return _pages.length;
  }

  void _evictExpired() {
    final cutoff = _clock().subtract(maxAge);
    final expiredKeys = _storedAt.entries
        .where((entry) => entry.value.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expiredKeys) {
      _pages.remove(key);
      _storedAt.remove(key);
    }
  }

  void _evictOverflow() {
    while (_pages.length > maxEntries && _pages.isNotEmpty) {
      final key = _pages.keys.first;
      _pages.remove(key);
      _storedAt.remove(key);
    }
  }
}

class ServerDiscoveryCacheRegistry {
  static final ServerDiscoveryPageCache instance = ServerDiscoveryPageCache();
}
