// The database gate on the presence WRITE, asserted where it decides.
//
// WHAT WOULD MAKE THESE WRONG. The gate's whole claim is that a failed
// re-establish costs only the PERSIST: the in-memory presence and the change
// notification still happen, because the stored row is a cache of a value the
// server already has. A test that only checked "storePresence was not called"
// would pass against a version that swallowed the presence change entirely,
// which is the failure that would actually be felt - the user's status not
// changing. So each case asserts all three: the memory copy, the
// notification, and whether the store was reached.
//
// THE SHAPE THE GATE FORCES, same as the key-request tests beside these:
// `waitForDatabase` does not answer false when a database is released. It
// waits, and answers false only when a resume fails under it. So the write is
// started while the database is released and the failed resume lands
// underneath it, which is how the real caller meets this - an inactivity
// timer firing during a suspend/resume cycle.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';

const String _userId = '@someone:example.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DatabaseReleaseTrigger.instance = null;
  });

  /// A trigger holding its database released, whose resume will fail.
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

  /// A trigger holding its database released, whose resume will SUCCEED.
  ///
  /// The counterpart to [releasedTrigger]: it separates "the gate said no"
  /// from "something else stopped the write", which is the only way to test
  /// what happens on the far side of an open gate.
  Future<DatabaseReleaseTrigger> recoverableReleasedTrigger() async {
    final trigger = DatabaseReleaseTrigger(
      databases: () => [_RecoverableDatabase()],
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

  ({
    MatrixUserPresenceComponent component,
    _RecordingDatabase database,
    _FakeSdkClient sdk,
  })
  scenario() {
    final database = _RecordingDatabase();
    final sdk = _FakeSdkClient(database);
    final component = MatrixUserPresenceComponent(_FakeMatrixClient(sdk));
    addTearDown(component.dispose);
    return (component: component, database: database, sdk: sdk);
  }

  test('a failed re-establish costs the persist and nothing else', () async {
    final trigger = await releasedTrigger();
    final s = scenario();
    final notified = <String>[];
    final sub = s.component.onPresenceChanged.listen(
      (event) => notified.add(event.$1),
    );
    addTearDown(sub.cancel);

    final pending = s.component.debugRememberPresenceForTesting(
      _userId,
      matrix.PresenceType.online,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      s.database.storeCalls,
      isEmpty,
      reason: 'a released store must not be written',
    );

    expect(await trigger.resume(), DatabaseResumeOutcome.failed);
    await pending;
    await Future<void>.delayed(Duration.zero);

    expect(
      s.database.storeCalls,
      isEmpty,
      reason: 'the failed gate is the whole point: no write reaches the store',
    );
    expect(
      s.sdk.presences[_userId]?.presence,
      matrix.PresenceType.online,
      reason:
          'the in-memory copy is what the app reads next; dropping it would '
          'discard a presence change the user actually made',
    );
    expect(notified, <String>[
      _userId,
    ], reason: 'and the change still has to be announced');
  });

  test('handles every relevant event in one sync list', () {
    final component = _RecordingPresenceComponent(
      _FakeMatrixClient(_FakeSdkClient(_RecordingDatabase())),
    );
    addTearDown(component.dispose);

    component.handleEvents([
      matrix.BasicEvent(type: 'm.typing', content: const {}),
      matrix.BasicEvent(type: 'm.receipt', content: const {}),
      matrix.BasicEvent(type: 'm.room.member', content: const {}),
    ]);

    expect(component.handled, ['typing', 'receipt', 'member']);
  });

  test('a dispose underneath the gate stops the write', () async {
    // The gate WAITS, and a logout or account removal is exactly the kind of
    // thing that happens during that wait. Here the resume SUCCEEDS, so the
    // gate says yes - the only thing standing between it and a write into a
    // database being torn down is the disposal recheck.
    final trigger = await recoverableReleasedTrigger();
    final s = scenario();

    final pending = s.component.debugRememberPresenceForTesting(
      _userId,
      matrix.PresenceType.online,
    );
    await Future<void>.delayed(Duration.zero);
    expect(s.database.storeCalls, isEmpty);

    await s.component.dispose();
    expect(await trigger.resume(), DatabaseResumeOutcome.established);
    await pending;
    await Future<void>.delayed(Duration.zero);

    expect(
      s.database.storeCalls,
      isEmpty,
      reason:
          'the gate opened, so only the disposal recheck can have stopped '
          'this; deleting it makes the store take a write during tear-down',
    );
  });

  test('an open gate writes through to the store', () async {
    // No trigger attached: the gate is open, which is the ordinary case and
    // the control for the test above.
    final s = scenario();

    await s.component.debugRememberPresenceForTesting(
      _userId,
      matrix.PresenceType.unavailable,
    );

    expect(s.database.storeCalls, <String>[_userId]);
    expect(s.sdk.presences[_userId]?.presence, matrix.PresenceType.unavailable);
  });
}

class _RecordingDatabase implements matrix.DatabaseApi {
  final List<String> storeCalls = <String>[];

  @override
  Future<void> storePresence(String userId, matrix.CachedPresence presence) {
    storeCalls.add(userId);
    return Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkClient implements matrix.Client {
  _FakeSdkClient(this.database);

  @override
  final matrix.DatabaseApi database;

  @override
  final Map<String, matrix.CachedPresence> presences =
      <String, matrix.CachedPresence>{};

  @override
  final CachedStreamController<matrix.CachedPresence> onPresenceChanged =
      CachedStreamController<matrix.CachedPresence>();

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController<matrix.SyncUpdate>();

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

class _RecordingPresenceComponent extends MatrixUserPresenceComponent {
  _RecordingPresenceComponent(super.client);

  final handled = <String>[];

  @override
  void handleTyping(matrix.BasicEvent event, DateTime time) {
    handled.add('typing');
  }

  @override
  void handleReadReceipt(matrix.BasicEvent event) {
    handled.add('receipt');
  }

  @override
  void handleRoomMemberEvent(matrix.BasicEvent event) {
    handled.add('member');
  }
}

/// Releases cleanly and comes back, so `resume()` reports `established`.
class _RecoverableDatabase implements ReleasableDatabase {
  bool _established = true;

  @override
  String get databaseName => 'recoverable';

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
  Future<ReestablishResult> reestablish() async {
    _established = true;
    return ReestablishResult.established;
  }
}

/// Releases cleanly and never comes back, so `resume()` reports `failed`.
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
