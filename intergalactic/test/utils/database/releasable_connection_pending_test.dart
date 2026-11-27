import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:intergalactic/utils/database/multiple_database_server.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';

/// The resume race the B5 device proof found: a lifecycle writer's `onResume`
/// and the trigger's `resume()` fire on the same event. In production the
/// writer runs FIRST (its listener registers during client load, the trigger
/// after), and the trigger's resume is serialised a microtask later besides,
/// so at the moment of the write nothing is pending on the wrapper. The
/// wrapper's wait-on-pending covers only a caller landing mid-swap; the
/// production order is covered by the trigger's `whenEstablished` gate, armed
/// at release time. Both are asserted here, in their real order.
///
/// WHAT WOULD MAKE THESE WRONG: if the wrapper's wait also covered "released
/// with nothing pending", the last test would pass for the wrong reason -
/// that is the lazy reconnect the design rejects, and the loud failure is the
/// contract. So it is asserted alongside the others.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-pending-test');
  });

  tearDown(() async {
    await DatabaseIsolate.releaseAll();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String dbPath(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  Future<ReleasableConnection> openWrapped(String name) async {
    final connection = await ReleasableConnection.open(dbPath(name));
    await connection.ensureOpen(_NoopUser());
    await connection.runCustom('CREATE TABLE IF NOT EXISTS t (v TEXT)');
    return connection;
  }

  test(
    'a statement issued while a re-establish is in flight waits for it',
    () async {
      final holder = await openWrapped('pending.db');
      await holder.runInsert("INSERT INTO t (v) VALUES (?)", ['before']);
      expect(await holder.release(), isTrue);

      // Same event-loop turn: the re-establish has been requested but has not
      // completed. A wake-time writer looks exactly like this.
      final reestablishing = holder.reestablish();
      final rows = holder.runSelect('SELECT v FROM t', const []);

      expect(await reestablishing, ReestablishResult.established);
      expect((await rows).map((r) => r['v']).toList(), ['before']);
    },
  );

  test(
    'ensureOpen issued while a re-establish is in flight waits for it',
    () async {
      final holder = await openWrapped('pending-open.db');
      expect(await holder.release(), isTrue);

      final reestablishing = holder.reestablish();
      final opened = holder.ensureOpen(_NoopUser());

      expect(await reestablishing, ReestablishResult.established);
      expect(await opened, isTrue);
    },
  );

  test(
    'production order: the write is issued first, then the trigger resumes',
    () async {
      final holder = await openWrapped('wake-order.db');
      await holder.runInsert("INSERT INTO t (v) VALUES (?)", ['before']);
      final trigger = DatabaseReleaseTrigger(
        databases: () => [holder],
        suspendSync: () async {},
        resumeSync: () {},
        hasLiveBackgroundExecution: () => false,
        pollInterval: const Duration(milliseconds: 2),
      );
      expect(await trigger.suspend(), DatabaseSuspendOutcome.released);
      expect(holder.isEstablished, isFalse);

      // The lifecycle writer, exactly as the presence watcher does it: wait
      // for the trigger's gate, then write. Issued BEFORE resume() exists.
      final write = trigger.whenEstablished.then(
        (_) => holder.runSelect('SELECT v FROM t', const []),
      );
      // Same wrapper, same moment, without the gate: this is the StateError
      // the device proof recorded, and it is still the contract.
      await expectLater(
        holder.runSelect('SELECT v FROM t', const []),
        throwsA(isA<StateError>()),
      );

      final resume = trigger.resume();
      final rows = await write.timeout(const Duration(seconds: 5));
      expect(await resume, DatabaseResumeOutcome.established);
      expect(rows.map((r) => r['v']).toList(), ['before']);
    },
  );

  test(
    'a statement issued while released with nothing pending still throws',
    () async {
      // Backgrounded-and-running: released, and no resume coming. Deferring
      // silently here would hide a sequencing bug; the writer must not exist.
      final holder = await openWrapped('nothing-pending.db');
      expect(await holder.release(), isTrue);

      await expectLater(
        holder.runSelect('SELECT v FROM t', const []),
        throwsA(isA<StateError>()),
      );

      expect(await holder.reestablish(), ReestablishResult.established);
    },
  );
}

class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
