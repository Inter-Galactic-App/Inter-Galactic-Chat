// The database gate on the AUTOMATIC key-share handler, asserted where it
// decides. Sibling of key_request_database_gate_test.dart, which covers the
// gate one step later, inside `respondToRoomKeyRequest`.
//
// WHAT WOULD MAKE THESE WRONG, stated first: a test that only checked "the
// handler returned" would pass against a handler with no gate at all, because
// the handler returns either way and reports nothing. The gate exists to stop
// the PARTICIPANT read - `_requesterIsJoined` calls
// `room.requestParticipants`, which reaches `client.database.getUsers` in the
// SDK and throws on a released store. That read is also OUTSIDE the handler's
// try, so a throw there escapes the unawaited listener into the zone with no
// `autoHistoryShare` line at all. So every case here asserts on whether
// `requestParticipants` was REACHED.
//
// THE SHAPE THE GATE FORCES, same as the two sibling suites:
// `waitForDatabase` does not answer false the moment a database is released.
// It WAITS, and answers false only when a resume fails under it - and a
// failed resume re-arms the gate, so a caller that starts after the failure
// waits for the following resume. These tests therefore start the handler
// while the database is released and let the failed resume land underneath
// it, which is also how the real caller meets this: a to-device key request
// arriving mid-suspension.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart' show Room;
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_history_sharing.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';
import 'package:matrix/encryption.dart' as matrix_crypto;
import 'package:matrix/matrix.dart' as matrix;

const String _roomId = '!room:example.org';
const String _sessionId = 'session-id';
const String _senderId = '@requester:example.org';
const String _selfId = '@self:example.org';

typedef _Scenario = ({_FakeMatrixClient client, _RecordingSdkRoom sdkRoom});

void main() {
  tearDown(() {
    DatabaseReleaseTrigger.instance = null;
  });

  /// A trigger holding its database released, with a resume that will fail.
  Future<DatabaseReleaseTrigger> releasedTrigger() async {
    final trigger = DatabaseReleaseTrigger(
      databases: () => [_UnrecoverableDatabase()],
      suspendSync: () async {},
      resumeSync: () {},
      hasLiveBackgroundExecution: () => false,
      quiescenceTimeout: const Duration(milliseconds: 60),
      pollInterval: const Duration(milliseconds: 2),
    );
    DatabaseReleaseTrigger.instance = trigger;
    expect(await trigger.suspend(), DatabaseSuspendOutcome.released);
    return trigger;
  }

  _Scenario scenario() {
    final sdkRoom = _RecordingSdkRoom();
    return (
      client: _FakeMatrixClient(_FakeSdkClient(), _FakeMatrixRoom(sdkRoom)),
      sdkRoom: sdkRoom,
    );
  }

  test('a released store is not read, and a failed resume gives up', () async {
    final trigger = await releasedTrigger();
    final s = scenario();

    final pending = s.client.debugHandleRoomKeyRequestForTesting(_keyRequest());
    await Future<void>.delayed(Duration.zero);

    // First half: while the database is merely released, the handler is still
    // waiting at the gate and has read no participants. Without the gate the
    // call is made synchronously inside `_requesterIsJoined`, so this fails
    // on the very first pump.
    expect(
      s.sdkRoom.participantCalls,
      0,
      reason: 'a released store must not be asked for the participant list',
    );

    expect(await trigger.resume(), DatabaseResumeOutcome.failed);
    await pending;

    // Second half: the failure resolves the gate and the handler gives up
    // without ever having reached the read.
    expect(
      s.sdkRoom.participantCalls,
      0,
      reason: 'the closed gate is the whole point: the read never happens',
    );
  });

  test('an open gate lets the handler reach the participant read', () async {
    // No trigger attached, so waitForDatabase answers true immediately. This
    // is the control: it pins that the gate is what stopped the read above,
    // rather than some other precondition earlier in the handler.
    DatabaseReleaseTrigger.instance = null;
    final s = scenario();

    await s.client.debugHandleRoomKeyRequestForTesting(_keyRequest());

    // The fake room reports no joined members, so the handler skips on
    // `requester_not_joined` - which is the point: it got past the gate and
    // made a real decision from a real read.
    expect(s.sdkRoom.participantCalls, 1);
  });

  test('a request for an unloaded room never reaches the gate', () async {
    // Released and never resumed. `client.getRoom` answering null is decided
    // in memory, ahead of the gate, so this must complete without waiting at
    // all - if the gate ever moved above that check, this test would hang.
    await releasedTrigger();
    final s = scenario();
    s.client.roomIsLoaded = false;

    final pending = s.client.debugHandleRoomKeyRequestForTesting(_keyRequest());
    await pending.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('an unloaded room must not wait on the database'),
    );

    expect(s.sdkRoom.participantCalls, 0);
  });
}

matrix_crypto.RoomKeyRequest _keyRequest() {
  return matrix_crypto.RoomKeyRequest.fromToDeviceEvent(
    matrix.ToDeviceEvent(
      sender: _senderId,
      type: matrix.EventTypes.RoomKeyRequest,
      content: const <String, dynamic>{},
    ),
    _FakeKeyManagerForRequest(),
    matrix_crypto.KeyManagerKeyShareRequest(
      requestId: 'request-id',
      devices: [_FakeDeviceKeys()],
      room: _RecordingSdkRoom(),
      sessionId: _sessionId,
    ),
  );
}

class _UnrecoverableDatabase implements ReleasableDatabase {
  bool _established = true;

  @override
  String get databaseName => 'unrecoverable';

  @override
  bool get isEstablished => _established;

  @override
  bool get isQuiescent => true;

  @override
  Future<bool> release() async {
    _established = false;
    return true;
  }

  @override
  Future<ReestablishResult> reestablish() async => ReestablishResult.failed;
}

class _FakeKeyManagerForRequest implements matrix_crypto.KeyManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkClient implements matrix.Client {
  @override
  String? get userID => _selfId;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this._sdkClient, this._room);

  final matrix.Client _sdkClient;
  final MatrixRoom _room;

  /// Lets one test make `getRoom` answer null, the only in-memory exit the
  /// handler takes before the gate.
  bool roomIsLoaded = true;

  @override
  matrix.Client get matrixClient => _sdkClient;

  @override
  Room? getRoom(String identifier) => roomIsLoaded ? _room : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixRoom implements MatrixRoom {
  _FakeMatrixRoom(this._sdkRoom);

  final matrix.Room _sdkRoom;

  @override
  String get identifier => _roomId;

  @override
  bool get isE2EE => true;

  @override
  matrix.Room get matrixRoom => _sdkRoom;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingSdkRoom implements matrix.Room {
  int participantCalls = 0;

  @override
  String get id => _roomId;

  @override
  matrix.HistoryVisibility? get historyVisibility =>
      matrix.HistoryVisibility.shared;

  @override
  Future<List<matrix.User>> requestParticipants([
    List<matrix.Membership> membershipFilter = const [
      matrix.Membership.join,
      matrix.Membership.invite,
      matrix.Membership.knock,
    ],
    bool suppressWarning = false,
    bool? cache,
  ]) async {
    participantCalls += 1;
    return <matrix.User>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDeviceKeys implements matrix.DeviceKeys {
  @override
  bool get blocked => false;

  @override
  String get deviceId => 'DEVICEID';

  @override
  String get userId => _senderId;

  @override
  bool get encryptToDevice => true;

  @override
  bool get verified => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
