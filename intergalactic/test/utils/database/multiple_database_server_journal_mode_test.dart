import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/database/multiple_database_server.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';

/// REQUIRES NATIVE SQLITE, like the rest of this directory: a failure reading
/// `Failed to load dynamic library 'libsqlite3.so'` is the runner missing
/// `libsqlite3-dev`, not a defect here.
///
/// WHY THIS EXISTS. The iOS Notification Service Extension opens the account
/// database with `SQLITE_OPEN_READONLY`. A read-only open of a **WAL** database
/// fails when the `-shm` file is absent, and that is exactly the state Phase C
/// serves: the app is not running, and B5 released the connection before
/// suspension, so nothing has recreated `-shm`.
///
/// Before this, the invariant held only because rollback-journal is sqlite3's
/// default - `PRAGMA journal_mode` appeared nowhere in the app, while
/// `drift_app_group_migration.dart` recorded "rollback-journal, not WAL" as a
/// decision. Enabling WAL for performance would have made every push
/// notification silently deliver the gateway's generic payload instead of a
/// decrypted one, and there is no Swift test target that would have gone red.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-journal-mode-test');
  });

  tearDown(() async {
    await DatabaseIsolate.releaseAll();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String dbPath(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  Future<String> journalMode(ReleasableConnection c) async {
    final rows = await c.runSelect('PRAGMA journal_mode;', const []);
    return rows.single.values.single.toString().toLowerCase();
  }

  test('the production open path is in rollback-journal mode', () async {
    final holder = await ReleasableConnection.open(dbPath('journal.db'));
    await holder.ensureOpen(_NoopUser());

    expect(
      await journalMode(holder),
      'delete',
      reason:
          'the NSE opens this database SQLITE_OPEN_READONLY, which fails on a '
          'WAL database with no -shm - the app-not-running state Phase C exists '
          'for. If this reads "wal", the extension has silently stopped '
          'rendering and nothing on the Swift side will say so.',
    );
  });

  test('the mode is reapplied after a B5 release and re-establish', () async {
    final holder = await ReleasableConnection.open(dbPath('journal.db'));
    await holder.ensureOpen(_NoopUser());
    expect(await journalMode(holder), 'delete');

    expect(await holder.release(), isTrue);
    expect(await holder.reestablish(), ReestablishResult.established);

    expect(
      await journalMode(holder),
      'delete',
      reason:
          'B5 rebuilds the executor, so a per-connection pragma set only on the '
          'first open would leave the resumed database in a different mode from '
          'the one this suite measured',
    );
  });
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
