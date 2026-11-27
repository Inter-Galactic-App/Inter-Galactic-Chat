// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:matrix/matrix.dart' as mx;
// Not exported by package:matrix; see client_close_hangup_test.dart.
import 'package:matrix/src/voip/models/voip_id.dart';

/// AUD-091, the client half: closing a client must reach every room's call.
///
/// Room close deliberately skips the VoIP room component, so calls survive the
/// room view being torn down for picture-in-picture and backgrounding. That is
/// correct for the room and exactly why client close has to reach those
/// components itself: nothing else ever will. These tests pin the list close
/// runs, since MatrixClient itself cannot be constructed in a unit test.
void main() {
  test(
    'includes every room that holds a call component, and no other',
    () async {
      final first = _FakeVoipRoomComponent();
      final second = _FakeVoipRoomComponent();

      final teardowns = MatrixClient.callTeardownsForClose(
        directCalls: null,
        rooms: [_FakeRoom(first), _FakeRoom(null), _FakeRoom(second)],
      );
      for (final teardown in teardowns) {
        await teardown();
      }

      expect(teardowns, hasLength(2));
      expect(first.disposes, 1);
      expect(second.disposes, 1);
    },
  );

  test('includes the direct calls alongside the rooms', () async {
    final call = _FakeCallSession();
    final room = _FakeVoipRoomComponent();

    final teardowns = MatrixClient.callTeardownsForClose(
      directCalls: _directComponent(call),
      rooms: [_FakeRoom(room)],
    );
    for (final teardown in teardowns) {
      await teardown();
    }

    expect(call.hangUps, 1);
    expect(room.disposes, 1);
  });

  test('a client with no calls has nothing to wait on', () {
    expect(
      MatrixClient.callTeardownsForClose(
        directCalls: null,
        rooms: [_FakeRoom(null)],
      ),
      isEmpty,
    );
  });
}

MatrixVoipComponent _directComponent(_FakeCallSession call) {
  return MatrixVoipComponent(
    _FakeMatrixClient(),
    voip: _FakeVoIP({
      VoipId(roomId: '!direct:example.org', callId: 'call'): call,
    }),
  );
}

class _FakeRoom implements Room {
  _FakeRoom(this._voip);

  final _FakeVoipRoomComponent? _voip;

  @override
  T? getComponent<T extends RoomComponent>() {
    final voip = _voip;
    return voip is T ? voip as T : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoipRoomComponent
    implements
        VoipRoomComponent<MatrixClient, MatrixRoom>,
        DisposableComponent {
  int disposes = 0;

  @override
  Future<void> dispose() async {
    disposes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCallSession implements mx.CallSession {
  int hangUps = 0;

  @override
  bool get callHasEnded => false;

  @override
  Future<void> hangup({
    required mx.CallErrorCode reason,
    bool shouldEmit = true,
  }) async {
    hangUps++;
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

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
