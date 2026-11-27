import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/database/multiple_database_server.dart';

/// REQUIRES NATIVE SQLITE. These tests drive a real drift database through the
/// production connect path, so the host needs a loadable `libsqlite3.so`
/// (`libsqlite3-dev` on Debian/Ubuntu — the CLI-only `sqlite3` package ships
/// `libsqlite3.so.0` but not the unversioned symlink `DynamicLibrary.open`
/// resolves). Forgejo run 1591 failed 11 tests this way on the self-hosted
/// runner; the queue row is "Forgejo CI runner has no libsqlite3". A failure
/// reading `Failed to load dynamic library 'libsqlite3.so'` is that, not a
/// defect here.
/// Covers the release protocol added for B5 (NSE Phase B prerequisite).
///
/// The case that matters is REOPEN AFTER RELEASE. `_activeIsolates` is a
/// `putIfAbsent` cache, so a release that shut the server down without evicting
/// it would leave the dead server in the map, hand it back on the next connect,
/// and throw `StateError` from `serve()` — meaning that account's database never
/// reopens until the process restarts. That failure is strictly worse than
/// never releasing at all, so it is tested directly rather than assumed.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-db-release-test');
  });

  tearDown(() async {
    await DatabaseIsolate.releaseAll();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String dbPath(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  Future<void> write(DatabaseConnection connection, String value) async {
    await connection.executor.ensureOpen(_NoopUser());
    await connection.executor.runCustom(
      'CREATE TABLE IF NOT EXISTS t (v TEXT)',
      const [],
    );
    await connection.executor.runInsert('INSERT INTO t (v) VALUES (?)', [
      value,
    ]);
  }

  Future<List<String>> readAll(DatabaseConnection connection) async {
    await connection.executor.ensureOpen(_NoopUser());
    final rows = await connection.executor.runSelect(
      'SELECT v FROM t',
      const [],
    );
    return rows.map((r) => r['v'] as String).toList();
  }

  test('reopens after release, with data intact', () async {
    final path = dbPath('reopen.db');

    final first = await DatabaseIsolate.connect(path, trackForRelease: true);
    await write(first, 'before-release');
    expect(DatabaseIsolate.connectedDatabases, contains(path));

    expect(await DatabaseIsolate.release(path), isTrue);
    expect(DatabaseIsolate.connectedDatabases, isNot(contains(path)));

    // The regression: without eviction this connect returns the dead server and
    // throws StateError instead of opening.
    final second = await DatabaseIsolate.connect(path, trackForRelease: true);
    expect(await readAll(second), ['before-release']);

    await write(second, 'after-release');
    expect(await readAll(second), ['before-release', 'after-release']);
  });

  test('releasing something never opened succeeds', () async {
    // The caller wants "not holding it". That is already true, so this is not an
    // error - and a release sweep must not fail because one database was closed.
    expect(await DatabaseIsolate.release(dbPath('never-opened.db')), isTrue);
  });

  test('releasing twice succeeds', () async {
    final path = dbPath('twice.db');
    final connection = await DatabaseIsolate.connect(
      path,
      trackForRelease: true,
    );
    await write(connection, 'v');

    expect(await DatabaseIsolate.release(path), isTrue);
    expect(await DatabaseIsolate.release(path), isTrue);
  });

  test(
    'releaseAll releases every connected database and allows reopen',
    () async {
      final a = dbPath('a.db');
      final b = dbPath('b.db');
      await write(await DatabaseIsolate.connect(a, trackForRelease: true), 'a');
      await write(await DatabaseIsolate.connect(b, trackForRelease: true), 'b');
      expect(DatabaseIsolate.connectedDatabases, containsAll([a, b]));

      expect(await DatabaseIsolate.releaseAll(), isTrue);
      expect(DatabaseIsolate.connectedDatabases, isEmpty);

      expect(
        await readAll(await DatabaseIsolate.connect(a, trackForRelease: true)),
        ['a'],
      );
      expect(
        await readAll(await DatabaseIsolate.connect(b, trackForRelease: true)),
        ['b'],
      );
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
