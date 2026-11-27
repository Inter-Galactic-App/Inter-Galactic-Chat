// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_component.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:matrix/matrix.dart' as mx;
// Not exported by package:matrix, but it is the key type of `VoIP.calls`, so a
// fake of that map cannot be written without it. The component under test
// carries the same ignore for the same SDK.
import 'package:matrix/src/voip/models/voip_id.dart';

/// AUD-091: a client's calls must end before the client closes, and closing
/// must never wait on a hang-up for longer than the bound.
///
/// "Every session" is three collections, and each has its own group below:
/// the direct-call map, a room's joined LiveKit call, and a room join still in
/// flight. A fix that ends the active call but not a ringing or joining one is
/// the likely incomplete version, so each is asserted separately.
void main() {
  group('direct calls end when their client closes', () {
    test('every live call is hung up, whatever its state', () async {
      final ringingIn = _FakeCallSession(mx.CallState.kRinging);
      final inviteSent = _FakeCallSession(mx.CallState.kInviteSent);
      final connecting = _FakeCallSession(mx.CallState.kConnecting);
      final connected = _FakeCallSession(mx.CallState.kConnected);
      final component = _directComponent([
        ringingIn,
        inviteSent,
        connecting,
        connected,
      ]);

      await component.dispose();

      expect(ringingIn.hangUps, 1, reason: 'an incoming call still ringing');
      expect(inviteSent.hangUps, 1, reason: 'an outgoing call still ringing');
      expect(connecting.hangUps, 1, reason: 'a call still connecting');
      expect(connected.hangUps, 1, reason: 'the active call');
    });

    test('a call that has already ended is left alone', () async {
      final ended = _FakeCallSession(mx.CallState.kEnded);
      final component = _directComponent([ended]);

      await component.dispose();

      expect(ended.hangUps, 0);
    });
  });

  group('room calls end when their client closes', () {
    test('the joined call is hung up', () async {
      final session = _FakeRoomSession(VoipState.connected);
      final component = _roomComponent()..currentSession = session;

      await component.dispose();

      expect(session.hangUps, 1);
    });

    test('a call already mid-hang-up is awaited, not abandoned', () async {
      // LiveKit's hangUpCall is idempotent: a second call returns the teardown
      // already running. Awaiting it is what lets that teardown finish before
      // the client it needs goes away.
      final session = _FakeRoomSession(VoipState.leaving);
      final component = _roomComponent()..currentSession = session;

      await component.dispose();

      expect(session.hangUps, 1);
    });

    test('a call that has already ended is left alone', () async {
      final session = _FakeRoomSession(VoipState.ended);
      final component = _roomComponent()..currentSession = session;

      await component.dispose();

      expect(session.hangUps, 0);
    });

    test('a join still in flight hangs up the session it produces', () async {
      // No session exists yet when the client closes, so there is nothing to
      // hang up at that moment. The join must notice on arrival that its
      // component is gone and end the call itself, or it lands as a live call
      // that nothing owns.
      final join = Completer<VoipSession?>();
      final component = _roomComponent()..backend = _FakeBackend(join.future);
      final joining = component.joinCall();

      await component.dispose();
      final lateSession = _FakeRoomSession(VoipState.connected);
      join.complete(lateSession);

      expect(await joining, isNull);
      expect(lateSession.hangUps, 1);
      expect(component.currentSession, isNull);
    });
  });

  group('closing never waits on a hang-up past the bound', () {
    // Small enough to keep the test fast, large enough that timer jitter on a
    // loaded CI host cannot fire it early.
    const bound = Duration(milliseconds: 200);
    const tolerance = Duration(seconds: 1);
    // What an unbounded wait turns into: a clean failure here rather than the
    // test runner's thirty-second default.
    const guard = Duration(seconds: 3);

    test('a direct call whose hang-up never completes', () async {
      final wedged = _FakeCallSession(
        mx.CallState.kConnected,
        hangUp: Completer<void>().future,
      );
      final component = _directComponent([wedged], bound: bound);
      final clock = Stopwatch()..start();

      await component.dispose().timeout(guard);

      expect(
        wedged.hangUps,
        1,
        reason:
            'The hang-up must be attempted. Without this a close that never '
            'tried would pass the timing check below for the wrong reason.',
      );
      expect(clock.elapsed, lessThan(bound + tolerance));
    });

    test('a room call whose hang-up never completes', () async {
      final wedged = _FakeRoomSession(
        VoipState.connected,
        hangUp: Completer<void>().future,
      );
      final component = _roomComponent(bound: bound)..currentSession = wedged;
      final clock = Stopwatch()..start();

      await component.dispose().timeout(guard);

      expect(
        wedged.hangUps,
        1,
        reason:
            'The hang-up must be attempted. Without this a close that never '
            'tried would pass the timing check below for the wrong reason.',
      );
      expect(clock.elapsed, lessThan(bound + tolerance));
    });
  });
}

MatrixVoipComponent _directComponent(
  List<_FakeCallSession> calls, {
  Duration? bound,
}) {
  final voip = _FakeVoIP({
    for (final (index, call) in calls.indexed)
      VoipId(roomId: '!direct:example.org', callId: 'call-$index'): call,
  });
  return bound == null
      ? MatrixVoipComponent(_FakeMatrixClient(), voip: voip)
      : MatrixVoipComponent(
          _FakeMatrixClient(),
          voip: voip,
          hangUpBoundOnClose: bound,
        );
}

MatrixVoipRoomComponent _roomComponent({Duration? bound}) {
  return bound == null
      ? MatrixVoipRoomComponent(_FakeMatrixClient(), _FakeMatrixRoom())
      : MatrixVoipRoomComponent(
          _FakeMatrixClient(),
          _FakeMatrixRoom(),
          hangUpBoundOnClose: bound,
        );
}

class _FakeCallSession implements mx.CallSession {
  _FakeCallSession(this.state, {this.hangUp});

  @override
  final mx.CallState state;

  /// Never-completing in the bound tests; immediate otherwise.
  final Future<void>? hangUp;

  int hangUps = 0;

  @override
  bool get callHasEnded => state == mx.CallState.kEnded;

  @override
  Future<void> hangup({
    required mx.CallErrorCode reason,
    bool shouldEmit = true,
  }) {
    hangUps++;
    return hangUp ?? Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoIP implements mx.VoIP {
  _FakeVoIP(this.calls);

  @override
  final Map<VoipId, mx.CallSession> calls;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoomSession implements VoipSession {
  _FakeRoomSession(this.state, {this.hangUp});

  @override
  final VoipState state;

  @override
  String get sessionId => 'room-session';

  /// Never-completing in the bound tests; immediate otherwise.
  final Future<void>? hangUp;

  int hangUps = 0;

  @override
  Future<void> hangUpCall() {
    hangUps++;
    return hangUp ?? Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBackend implements MatrixLivekitBackend {
  _FakeBackend(this._join);

  final Future<VoipSession?> _join;

  @override
  Future<VoipSession?> join() => _join;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  /// Read by the room component's join path for the local membership key; an
  /// account with no user or device yet answers null and the key is skipped.
  @override
  mx.Client get matrixClient => _FakeSdkClient();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdkClient implements mx.Client {
  @override
  String? get userID => null;

  @override
  String? get deviceID => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixRoom implements MatrixRoom {
  @override
  String get identifier => '!room:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
