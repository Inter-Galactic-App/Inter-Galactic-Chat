import 'dart:async';

import 'package:intergalactic/client/components/voip/voip_session.dart';

/// A direct-call wrapper that the component must release after the SDK ends it.
abstract interface class DirectCallSession implements VoipSession {
  Future<void> dispose();
}

/// Owns the app-side wrapper for each active Matrix direct call.
///
/// Matrix reports an ended call after its state has already changed. Reusing
/// the wrapper created at call start lets that wrapper release the timers and
/// subscriptions it owns instead of constructing a second, unobserved wrapper.
class DirectCallSessionOwner<T> {
  final Map<String, T> _sessionsByCallId = {};

  T start(String callId, T Function() create) {
    return _sessionsByCallId.putIfAbsent(callId, create);
  }

  T end(String callId, T Function() create) {
    return _sessionsByCallId.remove(callId) ?? create();
  }

  Future<void> dispose(FutureOr<void> Function(T session) release) async {
    final sessions = _sessionsByCallId.values.toList(growable: false);
    _sessionsByCallId.clear();
    for (final session in sessions) {
      await release(session);
    }
  }
}
