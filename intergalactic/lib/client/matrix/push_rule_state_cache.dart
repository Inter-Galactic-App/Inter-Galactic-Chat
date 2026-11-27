import 'package:matrix/matrix.dart' as matrix;

/// Caches a room or space push-rule state, which is expensive enough to derive
/// that the UI should not redo it on every build.
///
/// `MatrixRoom` and `MatrixSpace` each held this as a bare nullable field that
/// only a local `setPushRule` on that same instance ever cleared. A rule
/// changed on another device, or through a different wrapper for the same id,
/// therefore stayed invisible until a restart rebuilt the instance - BUG-319.
/// Holding it here means the invalidation rule is written once instead of
/// twice, and can be tested without constructing a Matrix client.
class PushRuleStateCache {
  PushRuleStateCache(this._read);

  final matrix.PushRuleState Function() _read;
  matrix.PushRuleState? _value;

  /// The cached state, read through on first access.
  matrix.PushRuleState get value => _value ??= _read();

  /// The cached state without reading through, or null when nothing is cached.
  /// Diagnostics use this to tell a stale cache from a cold one.
  matrix.PushRuleState? get cachedValue => _value;

  /// Records the state a local write just established, so the write does not
  /// pay for a re-read it already knows the answer to.
  void assign(matrix.PushRuleState value) => _value = value;

  /// Re-reads the state and reports whether it actually changed, so a sync
  /// carrying `m.push_rules` does not notify listeners for nothing.
  bool invalidate() {
    final previous = _value;
    if (previous == null) {
      // Nothing has read this yet, so nothing is showing a stale value and
      // there is no one to notify. Leaving it cold also preserves the laziness
      // the cache exists for: reading here would do the expensive work for
      // every room on the first sync that carries push rules.
      return false;
    }
    final current = _read();
    _value = current;
    return previous != current;
  }
}

/// Implemented by the room and space wrappers so the sync handler can refresh
/// their caches without naming either concrete type.
///
/// The indirection is not decoration: depending on this interface is what lets
/// a test put a double into the client's room list and prove the sync handler
/// actually calls through. Covering [PushRuleStateCache] and the sync predicate
/// separately still leaves the call between them unguarded, and a missing call
/// looks exactly like a working fix.
abstract interface class PushRuleCacheHolder {
  /// Re-reads the push-rule state, returning whether it actually changed.
  bool invalidatePushRuleCache();
}
