import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/database/multiple_database_server.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';

/// The release-instant observation from the B5 device proof, reproduced and
/// fixed. The wrapper judged the database quiescent and released it, and
/// 10 ms later two SDK member lookups failed at the server with `Bad state:
/// No element` (server-side `_loadExecutor` / `_spawnTransaction`) and
/// `Channel was closed before receiving a response`.
///
/// The shape: work issued on a transaction executor AFTER that transaction
/// completed. drift resolves the engine from the zone, so a future spawned
/// inside a `transaction()` block and outliving it still targets that
/// transaction's executor - a nested begin, or a plain statement. drift only
/// asserts against this in debug builds. At the server the request waits for
/// the dead executor's turn in the backlog, which never comes; the parent's
/// count dropped at commit, so the wrapper sees nothing in flight. Without a
/// release that is a silent hang; the release is what made it loud.
///
/// Before the fix, the first two tests reproduced the observation exactly
/// against the real drift server isolate: the request never settled, the
/// wrapper reported quiescent, `release()` succeeded on the first check and
/// the request then failed with `DriftRemoteException: Bad state: No
/// element`. Now late work runs on the root connection, counted.
///
/// WHAT WOULD MAKE THESE WRONG: a fix that merely threw on late use would
/// also pass a "does not hang" test, so these assert that the work actually
/// COMPLETES with the right result, and that while it runs the wrapper is
/// not quiescent. Timeouts turn a regression into a failure, not a hang.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-stale-txn');
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

  /// The drift `transaction()` sequence, executor-level: begin, open at the
  /// server, run, commit. Returns the executor so the test can hold it past
  /// its lifetime, exactly as a stale zone does.
  Future<TransactionExecutor> completedTransaction(
    ReleasableConnection holder,
  ) async {
    final transaction = holder.beginTransaction();
    await transaction.ensureOpen(_NoopUser());
    await transaction.runInsert("INSERT INTO t (v) VALUES (?)", ['in-txn']);
    await transaction.send();
    return transaction;
  }

  const wait = Duration(seconds: 5);

  test('a nested transaction begun on a completed transaction runs as a '
      'top-level one, counted, and completes', () async {
    final holder = await openWrapped('stale-nested.db');
    final stale = await completedTransaction(holder);
    expect(holder.isQuiescent, isTrue, reason: 'the parent committed');
    final usesBefore = ReleasableConnection.staleTransactionUses;

    // `transaction()` inside a finished transaction's zone resolves to it
    // and begins a nested transaction on its executor.
    final nested = stale.beginTransaction();
    expect(ReleasableConnection.staleTransactionUses, usesBefore + 1);
    expect(await nested.ensureOpen(_NoopUser()).timeout(wait), isTrue);
    expect(
      holder.isQuiescent,
      isFalse,
      reason: 'the late block is counted, so a release would refuse',
    );
    expect(await holder.release(), isFalse);

    await nested
        .runInsert("INSERT INTO t (v) VALUES (?)", ['late'])
        .timeout(wait);
    await nested.send().timeout(wait);
    expect(holder.isQuiescent, isTrue);

    final rows = await holder.runSelect('SELECT v FROM t ORDER BY v', const []);
    expect(rows.map((r) => r['v']).toList(), ['in-txn', 'late']);

    expect(await holder.release(), isTrue);
    expect(await holder.reestablish(), ReestablishResult.established);
  });

  test('a statement on a completed transaction runs on the connection and '
      'completes', () async {
    final holder = await openWrapped('stale-statement.db');
    final stale = await completedTransaction(holder);
    final usesBefore = ReleasableConnection.staleTransactionUses;

    final rows = await stale
        .runSelect('SELECT v FROM t', const [])
        .timeout(wait);
    expect(rows.map((r) => r['v']).toList(), ['in-txn']);
    expect(ReleasableConnection.staleTransactionUses, usesBefore + 1);

    expect(await holder.release(), isTrue);
    expect(await holder.reestablish(), ReestablishResult.established);
  });

  test(
    'a live transaction is untouched: counted, refuses the release',
    () async {
      final holder = await openWrapped('live.db');
      final usesBefore = ReleasableConnection.staleTransactionUses;
      final live = holder.beginTransaction();
      await live.ensureOpen(_NoopUser());
      await live.runInsert("INSERT INTO t (v) VALUES (?)", ['live']);

      expect(holder.isQuiescent, isFalse);
      expect(await holder.release(), isFalse);

      await live.send();
      expect(ReleasableConnection.staleTransactionUses, usesBefore);
      expect(await holder.release(), isTrue);
      expect(await holder.reestablish(), ReestablishResult.established);
    },
  );

  test('late work after a ROLLBACK: reads run on the root, writes and nested '
      'blocks throw, and nothing the rollback discarded lands', () async {
    // REVIEW's finding on 681b6d47: send(), rollback() and close() all set
    // the same flag, so a write after a rollback was redirected to the root
    // and silently, durably committed what the rollback had discarded.
    // close() is refused the same way but not exercised here: drift never
    // closes an opened transaction executor without send() or rollback(),
    // and doing so leaves the server-side transaction in its backlog, which
    // hangs every later request on that server.
    final holder = await openWrapped('stale-rollback.db');
    final abandoned = holder.beginTransaction();
    await abandoned.ensureOpen(_NoopUser());
    await abandoned.runInsert("INSERT INTO t (v) VALUES (?)", ['discarded']);
    await abandoned.rollback();
    expect(holder.isQuiescent, isTrue);

    await expectLater(
      abandoned.runInsert("INSERT INTO t (v) VALUES (?)", ['late']),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      abandoned.runCustom("INSERT INTO t (v) VALUES ('late-custom')"),
      throwsA(isA<StateError>()),
    );
    expect(() => abandoned.beginTransaction(), throwsA(isA<StateError>()));
    expect(() => abandoned.beginExclusive(), throwsA(isA<StateError>()));

    // A read is harmless and stays counted on the root.
    final rows = await abandoned
        .runSelect('SELECT v FROM t', const [])
        .timeout(wait);
    expect(rows, isEmpty, reason: 'the rollback discarded its row');

    final fromRoot = await holder.runSelect('SELECT v FROM t', const []);
    expect(fromRoot, isEmpty, reason: 'and no late write landed');

    expect(await holder.release(), isTrue);
    expect(await holder.reestablish(), ReestablishResult.established);
  });

  test('late work on a completed transaction of a RELEASED connection still '
      'meets the loud StateError', () async {
    // Redirecting to the root must not become a lazy reconnect: with the
    // connection released and nothing pending, the root throws.
    final holder = await openWrapped('stale-released.db');
    final stale = await completedTransaction(holder);
    expect(await holder.release(), isTrue);

    expect(() => stale.beginTransaction(), throwsA(isA<StateError>()));
    await expectLater(
      stale.runSelect('SELECT v FROM t', const []),
      throwsA(isA<StateError>()),
    );

    expect(await holder.reestablish(), ReestablishResult.established);
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
