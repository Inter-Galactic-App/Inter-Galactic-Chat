class SpotifyTokenSet {
  const SpotifyTokenSet({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scopes = const [],
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final List<String> scopes;

  bool hasScope(String scope) => scopes.contains(scope);

  bool hasScopes(Iterable<String> scopes) {
    return scopes.every(hasScope);
  }

  bool get isExpired {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) {
      return false;
    }

    return DateTime.now().isAfter(
      expiresAt.subtract(const Duration(seconds: 30)),
    );
  }

  SpotifyTokenSet copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    List<String>? scopes,
  }) {
    return SpotifyTokenSet(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      scopes: scopes ?? this.scopes,
    );
  }
}

abstract class SpotifyTokenStore {
  Future<SpotifyTokenSet?> read();
  Future<void> write(SpotifyTokenSet tokens);
  Future<void> clear();
}

class InMemorySpotifyTokenStore implements SpotifyTokenStore {
  SpotifyTokenSet? _tokens;

  @override
  Future<void> clear() async {
    _tokens = null;
  }

  @override
  Future<SpotifyTokenSet?> read() async {
    return _tokens;
  }

  @override
  Future<void> write(SpotifyTokenSet tokens) async {
    _tokens = tokens;
  }
}
