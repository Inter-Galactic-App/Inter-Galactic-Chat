import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/database/multiple_database_server.dart';

/// REQUIRES NATIVE SQLITE, like the rest of this directory: a failure reading
/// `Failed to load dynamic library 'libsqlite3.so'` is the runner missing
/// `libsqlite3-dev`, not a defect here.
///
/// WHAT WOULD MAKE THIS WRONG, stated first: both calls answer `true` with or
/// without the fix, so an assertion on the VALUES proves nothing. What changes
/// is WHEN the second one answers. `_release` is dispatched with `unawaited`,
/// so a second message for the same name is processed during the first one's
/// `await`; it found the entry already evicted and acknowledged success
/// immediately, while the shutdown it is reporting on was still running. A
/// caller acting on that records a database as released while the server is
/// still closing - the 0xdead10cc condition the release exists to avoid. So
/// this asserts on completion ORDER.
///
/// `DatabaseIsolate.release` is driven directly rather than through
/// `ReleasableConnection`, because the wrapper's own gate serialises its
/// release calls and would hide the race this measures.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-release-race-test');
  });

  tearDown(() async {
    await DatabaseIsolate.releaseAll();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String dbPath(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  test(
    'a second release for one name waits for the shutdown it reports on',
    () async {
      final path = dbPath('concurrent.db');
      final connection = await DatabaseIsolate.connect(
        path,
        trackForRelease: true,
      );
      await connection.executor.ensureOpen(_NoopUser());
      await connection.executor.runCustom('CREATE TABLE t (v TEXT)', const []);

      // Issued in the same turn and NOT awaited between, so both messages are in
      // the server isolate's queue before either shutdown finishes. Awaiting the
      // first would make the two sequential and measure nothing.
      final order = <String>[];
      final first = DatabaseIsolate.release(path).then((released) {
        order.add('first:$released');
        return released;
      });
      final second = DatabaseIsolate.release(path).then((released) {
        order.add('second:$released');
        return released;
      });

      expect(await Future.wait([first, second]), [true, true]);
      expect(
        order,
        ['first:true', 'second:true'],
        reason:
            'the second call answered before the shutdown it is reporting on had '
            'finished, so a caller acting on it records a release that has not '
            'happened yet',
      );

      // And the release really did happen: a fresh connect builds a new server
      // over the same file rather than adopting a torn-down one.
      final reconnected = await DatabaseIsolate.connect(
        path,
        trackForRelease: true,
      );
      await reconnected.executor.ensureOpen(_NoopUser());
      expect(
        await reconnected.executor.runSelect('SELECT v FROM t', const []),
        isEmpty,
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
