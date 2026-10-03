// The database gate on the key-request responder, asserted where it decides.
//
// WHAT WOULD MAKE THESE WRONG, stated first: a test that only checked the
// returned enum would pass against a responder that consulted the gate, got
// false, and read the encryption store anyway. The gate exists to stop that
// store being read while it is released - the StateError this branch is about
// - so every case asserts on whether loadInboundGroupSession was REACHED, and
// on the enum second.
//
// THE SHAPE THE GATE FORCES. `waitForDatabase` does not answer false the
// moment a database is released; it WAITS, and answers false only when a
// resume fails under it. A failed resume also re-arms the gate for the next
// retry, so a caller that starts AFTER the failure waits for the following
// resume rather than returning. That is deliberate, and it means these tests
// have to start the responder while the database is released and let the
// failed resume land underneath it - which is also how the real caller meets
// this, on a to-device request that arrives mid-suspension.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_history_sharing.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';
import 'package:matrix/encryption.dart' as matrix_crypto;
// SessionKey is not re-exported by encryption.dart, and the responder's
// return type has to match exactly, so the defining library is imported
// directly rather than widening the fake's signature to dynamic.
import 'package:matrix/encryption/utils/session_key.dart' show SessionKey;
import 'package:matrix/matrix.dart' as matrix;

const String _roomId = '!room:example.org';
const String _sessionId = 'session-id';
const String _senderId = '@requester:example.org';

typedef _Scenario = ({
  _FakeMatrixClient client,
  _RecordingKeyManager keyManager,
  MatrixRoom room,
  MatrixHistoryShareReport report,
});

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
    final keyManager = _RecordingKeyManager();
    return (
      client: _FakeMatrixClient(_FakeSdkClient(_FakeEncryption(keyManager))),
      keyManager: keyManager,
      room: _FakeMatrixRoom(),
      report: MatrixHistoryShareReport(targetUserIds: const [_senderId]),
    );
  }

  Future<MatrixKeyRequestOutcome> respond(
    _Scenario s, {
    bool blocked = false,
  }) => s.client.respondToRoomKeyRequest(
    s.room,
    _keyRequest(blocked: blocked),
    s.report,
    allowIneligibleDevice: false,
  );

  test('a released store is not read, and a failed resume defers', () async {
    final trigger = await releasedTrigger();
    final s = scenario();

    final pending = respond(s);
    await Future<void>.delayed(Duration.zero);

    // First half: while the database is merely released, the responder is
    // still waiting and has touched nothing.
    expect(
      s.keyManager.loadCalls,
      isEmpty,
      reason: 'the released encryption store must not be read',
    );

    expect(await trigger.resume(), DatabaseResumeOutcome.failed);

    // Second half: the failure resolves the gate, and the responder reports a
    // deferral without ever having reached the store. Deleting the gate makes
    // the loadCalls assertion fail, not just the enum one.
    expect(await pending, MatrixKeyRequestOutcome.deferred);
    expect(s.keyManager.loadCalls, isEmpty);
  });

  test('a deferral is counted apart from a refusal', () async {
    final trigger = await releasedTrigger();
    final s = scenario();

    final pending = respond(s);
    await Future<void>.delayed(Duration.zero);
    expect(await trigger.resume(), DatabaseResumeOutcome.failed);
    await pending;

    // A deferral must be visible, and must not be laundered into either
    // "ignored" counter - those are decisions about a device.
    expect(s.report.deferredRequests, 1);
    expect(s.report.ineligibleRequestsIgnored, 0);
    expect(s.report.blockedRequestsIgnored, 0);
    expect(
      s.report.toMultilineString(),
      contains('Nothing was refused'),
      reason: 'the operator-visible summary must say a retry will work',
    );
  });

  test('an open gate lets the responder through to the store', () async {
    // No trigger attached, so waitForDatabase answers true immediately. This
    // pins that the gate is what stopped the call above, rather than some
    // other precondition inside the responder.
    DatabaseReleaseTrigger.instance = null;
    final s = scenario();

    final outcome = await respond(s);

    expect(s.keyManager.loadCalls, [(_roomId, _sessionId)]);
    expect(s.report.deferredRequests, 0);
    // The fake store holds no session, so the responder refuses on that -
    // which is the point: it got past the gate and made a real decision.
    expect(outcome, MatrixKeyRequestOutcome.refused);
  });

  test('a refusal decided before the gate is never a deferral', () async {
    // Released and never resumed. A blocked device is refused by an in-memory
    // check ahead of the gate, so this must complete without waiting at all -
    // if the gate ever moved above those checks, this test would hang.
    await releasedTrigger();
    final s = scenario();

    final outcome = await respond(s, blocked: true).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('a policy refusal must not wait on the database'),
    );

    expect(outcome, MatrixKeyRequestOutcome.refused);
    expect(s.report.blockedRequestsIgnored, 1);
    expect(
      s.report.deferredRequests,
      0,
      reason:
          'a policy decision must not be reported as storage unavailability',
    );
    expect(s.keyManager.loadCalls, isEmpty);
  });
}

matrix_crypto.RoomKeyRequest _keyRequest({bool blocked = false}) {
  return matrix_crypto.RoomKeyRequest.fromToDeviceEvent(
    matrix.ToDeviceEvent(
      sender: _senderId,
      type: matrix.EventTypes.RoomKeyRequest,
      content: const <String, dynamic>{},
    ),
    _FakeKeyManagerForRequest(),
    matrix_crypto.KeyManagerKeyShareRequest(
      requestId: 'request-id',
      devices: [_FakeDeviceKeys(blocked: blocked)],
      room: _FakeSdkRoom(),
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

class _RecordingKeyManager implements matrix_crypto.KeyManager {
  final List<(String, String)> loadCalls = [];

  // Recorded through noSuchMethod rather than a typed override: SessionKey is
  // not exported from package:matrix/encryption.dart, and naming a return type
  // this test does not care about would be one more thing to keep in step with
  // the SDK.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadInboundGroupSession) {
      loadCalls.add((
        invocation.positionalArguments[0] as String,
        invocation.positionalArguments[1] as String,
      ));
      return Future<SessionKey?>.value(null);
    }
    return null;
  }
}

class _FakeKeyManagerForRequest implements matrix_crypto.KeyManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeEncryption implements matrix_crypto.Encryption {
  _FakeEncryption(this.keyManager);

  @override
  final matrix_crypto.KeyManager keyManager;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkClient implements matrix.Client {
  _FakeSdkClient(this.encryption);

  @override
  final matrix_crypto.Encryption? encryption;

  @override
  bool get encryptionEnabled => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this._sdkClient);

  final matrix.Client _sdkClient;

  @override
  matrix.Client get matrixClient => _sdkClient;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixRoom implements MatrixRoom {
  @override
  String get identifier => _roomId;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkRoom implements matrix.Room {
  @override
  String get id => _roomId;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDeviceKeys implements matrix.DeviceKeys {
  _FakeDeviceKeys({required this.blocked});

  @override
  final bool blocked;

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
