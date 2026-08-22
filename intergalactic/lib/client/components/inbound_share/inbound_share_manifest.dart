enum InboundShareManifestState { ready, claimed, transferred, released }

class InboundShareManifest {
  const InboundShareManifest({
    required this.token,
    required this.sessionRoot,
    required this.createdAt,
    this.state = InboundShareManifestState.ready,
    this.schemaVersion = 1,
  });
  final int schemaVersion;
  final String token;
  final String sessionRoot;
  final DateTime createdAt;
  final InboundShareManifestState state;
  InboundShareManifest claim() {
    if (state != InboundShareManifestState.ready)
      throw StateError('Inbound share manifest is not claimable.');
    return InboundShareManifest(
      // Carried, not defaulted: a transition must not silently rewrite the
      // manifest's format version.
      schemaVersion: schemaVersion,
      token: token,
      sessionRoot: sessionRoot,
      createdAt: createdAt,
      state: InboundShareManifestState.claimed,
    );
  }

  InboundShareManifest terminal(InboundShareManifestState value) {
    if (value != InboundShareManifestState.transferred &&
        value != InboundShareManifestState.released)
      throw ArgumentError.value(value, 'value');
    if (state != InboundShareManifestState.claimed)
      throw StateError('Inbound share manifest has not been claimed.');
    return InboundShareManifest(
      schemaVersion: schemaVersion,
      token: token,
      sessionRoot: sessionRoot,
      createdAt: createdAt,
      state: value,
    );
  }
}
