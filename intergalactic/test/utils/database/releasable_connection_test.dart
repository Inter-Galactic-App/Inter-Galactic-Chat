import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/database/database_platform.dart';
import 'package:intergalactic/utils/database/multiple_database_server.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';

/// REQUIRES NATIVE SQLITE. These tests drive a real drift database through the
/// production connect path, so the host needs a loadable `libsqlite3.so`
/// (`libsqlite3-dev` on Debian/Ubuntu — the CLI-only `sqlite3` package ships
/// `libsqlite3.so.0` but not the unversioned symlink `DynamicLibrary.open`
/// resolves). A failure reading `Failed to load dynamic library
/// `libsqlite3.so`` is that, not a defect here.
///
/// THE FORGEJO RUNNER NOW HAS IT. Run 1591 failed 11 tests this way and the
/// note that used to sit here said CI could not execute this file at all -
/// which was still being repeated as fact on 2026-09-08, when run 2091
/// executed all 13 of these tests on the self-hosted runner and passed. Do not
/// plan around this suite being CI-invisible; read a recent run instead.
/// B5 re-establish.
///
/// WHAT WOULD MAKE THESE WRONG, stated before running them per cleanup.md
/// Phase 6a: the previous B5 tests passed while proving the wrong thing, because
/// they called `DatabaseIsolate.connect()` themselves and so demonstrated only
/// that a NEW connection works after a release. The claim that matters is that
/// an EXISTING HOLDER recovers.
///
/// So every test below keeps **the same `ReleasableConnection` instance** across
/// the release and queries through it afterwards. If a test constructs a second
/// wrapper, it has stopped testing re-establish and is testing `open()` again.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-reestablish-test');
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

  Future<List<String>> readAll(ReleasableConnection c) async {
    final rows = await c.runSelect('SELECT v FROM t', const []);
    return rows.map((r) => r['v'] as String).toList();
  }

  test('the SAME holder survives release and re-establish', () async {
    final holder = await openWrapped('holder.db');
    await holder.runInsert("INSERT INTO t (v) VALUES (?)", ['before']);

    expect(await holder.release(), isTrue);
    expect(holder.isEstablished, isFalse);

    expect(await holder.reestablish(), ReestablishResult.established);
    expect(holder.isEstablished, isTrue);

    // Queried through the ORIGINAL wrapper, which is the thing the SDK holds.
    expect(await readAll(holder), ['before']);

    await holder.runInsert("INSERT INTO t (v) VALUES (?)", ['after']);
    expect(await readAll(holder), ['before', 'after']);
  });

  test('work attempted while released fails loudly, not silently', () async {
    // A lazy reconnect here would be the wrong behaviour: it would hide a
    // sequencing bug and let work proceed against a connection the caller
    // believes is released.
    final holder = await openWrapped('loud.db');
    expect(await holder.release(), isTrue);

    // Awaited, not fire-and-forget. `runSelect` returns a Future, so a bare
    // `expect` only registers the expectation - the re-establish below could
    // then land first, let the statement succeed, and leave the assertion to
    // fail from a later turn or not at all. `expectLater` is what the sibling
    // suite releasable_connection_pending_test.dart uses for this contract.
    await expectLater(
      holder.runSelect('SELECT v FROM t', const []),
      throwsA(isA<StateError>()),
    );

    expect(await holder.reestablish(), ReestablishResult.established);
    expect(await readAll(holder), isEmpty);
  });

  test('release is refused while a transaction is open', () async {
    final holder = await openWrapped('txn.db');
    final transaction = holder.beginTransaction();
    await transaction.ensureOpen(_NoopUser());

    expect(
      await holder.release(),
      isFalse,
      reason: 'a transaction executor cannot be swapped underneath',
    );
    expect(holder.isEstablished, isTrue, reason: 'refusal must not release');

    await transaction.rollback();

    // Once quiescent the same holder releases normally.
    expect(await holder.release(), isTrue);
    expect(await holder.reestablish(), ReestablishResult.established);
  });

  test('re-establishing an established connection is a no-op', () async {
    final holder = await openWrapped('noop.db');
    await holder.runInsert("INSERT INTO t (v) VALUES (?)", ['v']);

    expect(await holder.reestablish(), ReestablishResult.established);
    expect(await readAll(holder), ['v']);
  });

  test('releasing twice succeeds and still re-establishes', () async {
    final holder = await openWrapped('twice.db');
    expect(await holder.release(), isTrue);
    expect(await holder.release(), isTrue);
    expect(await holder.reestablish(), ReestablishResult.established);
    expect(await readAll(holder), isEmpty);
  });

  test('RE-2: established is never reported without proving openability', () async {
    // REVIEW's probe: release before the SDK's first ensureOpen, make the file
    // unopenable, and re-establish used to return `established` having opened
    // nothing - so the app layer, which gates resumption on exactly this value,
    // would resume onto a wrapper that throws at first use.
    final path = dbPath('unopenable.db');
    final holder = await ReleasableConnection.open(path);
    expect(await holder.release(), isTrue);

    // Replace the database with a directory: openable-as-a-path, not as a file.
    File(path).existsSync() ? File(path).deleteSync() : null;
    Directory(path).createSync();

    expect(
      await holder.reestablish(),
      isNot(ReestablishResult.established),
      reason: 'must not claim established when the database cannot be opened',
    );
    expect(holder.isEstablished, isFalse);
  });

  test(
    'RE-3: release is refused while a standalone statement is in flight',
    () async {
      // Quiescence counted transactions only, so release could fire mid-statement
      // and shut the server down underneath a bare runSelect.
      final holder = await openWrapped('inflight.db');
      await holder.runInsert("INSERT INTO t (v) VALUES (?)", ['v']);

      final slow = holder.runSelect('SELECT v FROM t', const []);
      final releasedDuring = await holder.release();
      await slow;

      expect(
        releasedDuring,
        isFalse,
        reason: 'a statement in flight is not quiescent',
      );
      expect(holder.isEstablished, isTrue);
      expect(
        await holder.release(),
        isTrue,
        reason: 'quiescent once it settles',
      );
    },
  );

  test('RE-4: an exclusive block blocks release until it closes', () async {
    final holder = await openWrapped('exclusive.db');
    final exclusive = holder.beginExclusive();

    expect(await holder.release(), isFalse);
    expect(holder.isEstablished, isTrue);

    await exclusive.close();
    expect(await holder.release(), isTrue);
  });

  test(
    'interleaved release and re-establish do not leave two live inners',
    () async {
      // Without the wrapper's own gate these interleave: drift's opening lock
      // serialises within one executor instance, and a swap replaces the instance.
      final holder = await openWrapped('race.db');
      await holder.runInsert("INSERT INTO t (v) VALUES (?)", ['x']);

      final results = await Future.wait([
        holder.release(),
        holder.reestablish(),
        holder.release(),
        holder.reestablish(),
      ]);

      expect(results, hasLength(4));
      // Whatever the ordering, the wrapper must end usable rather than wedged.
      if (!holder.isEstablished) {
        expect(await holder.reestablish(), ReestablishResult.established);
      }
      expect(await readAll(holder), ['x']);
    },
  );

  test(
    'a close racing a re-establish never strands a live connection',
    () async {
      final holder = await openWrapped('close-race.db');
      await holder.runInsert("INSERT INTO t (v) VALUES (?)", ['x']);

      // Released first so the re-establish below has real work to do: it has
      // to cross the isolate boundary, and that await is the window close()
      // used to slip through by not taking the gate.
      expect(await holder.release(), isTrue);

      await Future.wait([holder.close(), holder.reestablish()]);

      // `live` is what the lifecycle trigger sweeps. A wrapper that is out of
      // it while still holding an executor can never be released again, so the
      // process suspends with the database file open - the 0xdead10cc kill
      // this class exists to prevent.
      final tracked = ReleasableConnection.live.contains(holder);
      expect(
        tracked || !holder.isEstablished,
        isTrue,
        reason:
            'closed wrapper kept a live inner that nothing sweeps: '
            'tracked=$tracked established=${holder.isEstablished}',
      );
    },
  );

  test('a wrapper closed while released reports closed, not failed', () async {
    // The trigger keeps a released database in its pending set until a
    // re-establish reports something other than a failure. `failed` is the
    // one answer it retries forever, so a wrapper that was closed while
    // released - a logout or account removal in that window - left the set
    // permanently non-empty: `resumeSync()` is never called again, and sync
    // stays stopped for every account that IS still live.
    final holder = await openWrapped('closed-outcome.db');
    expect(await holder.release(), isTrue);

    await holder.close();

    expect(
      await holder.reestablish(),
      ReestablishResult.closed,
      reason:
          'a closed wrapper is out of the registry and holds no executor, so '
          'there is nothing left to retry - the trigger must be able to tell '
          'that apart from a re-establish that failed',
    );
    expect(holder.isEstablished, isFalse);
    expect(ReleasableConnection.live.contains(holder), isFalse);
  });

  test('release answers what the server did, not what the wrapper did', () async {
    // `_inner == null` is true after a successful release, after a release
    // whose isolate shutdown failed, and after close() - which hands the
    // executor back without shutting the server down at all. Reading it as
    // "already released, so true" reports a release that did not happen.
    // close() is the reachable one of the three on a host where the isolate
    // release always succeeds.
    final holder = await openWrapped('short-circuit.db');
    await holder.close();

    expect(
      await holder.release(),
      isFalse,
      reason:
          'close() closed the executor; it did not shut the drift server down, '
          'so the database is not released',
    );
  });

  test(
    'a close arriving during re-establish does not strand the server',
    () async {
      // RE-6, in the window this test ACTUALLY reaches, which is not the one
      // its comment used to claim. `reestablish()` queues `_reestablishInGate`
      // in a microtask and `close()` latches `_closeRequested` synchronously,
      // so the flag is already set when the queued action begins: this is
      // "closed before the re-establish starts", not "closed while the open is
      // crossing the isolate boundary". The second needs the connect held open,
      // and is covered by 'a close arriving while the connect is suspended'
      // below.
      //
      // Kept as its own case rather than replaced: both orderings must strand
      // nothing, and this is the production order for a close and a resume
      // landing on the same lifecycle event. Neither call is awaited before the
      // other is issued - hand-sequencing them would test the reverse of what
      // production does.
      //
      // WHAT WOULD MAKE THIS VACUOUS: asserting only the returned outcome.
      // Before the fix the outcome was `established` AND the drift server was
      // left running with the wrapper gone from `_registry`, so the assertion
      // that actually guards the defect is the `connectedDatabases` one - a
      // version that returned `closed` and still stranded the server would pass
      // on the outcome alone.
      final path = dbPath('closed-during-reestablish.db');
      final holder = await openWrapped('closed-during-reestablish.db');

      expect(await holder.release(), isTrue);
      expect(holder.isEstablished, isFalse);
      expect(
        DatabaseIsolate.connectedDatabases.contains(path),
        isFalse,
        reason:
            'arming: the release must actually have shut the server down, '
            'or the re-establish below has nothing to bring back up',
      );

      final reestablishing = holder.reestablish();
      final closing = holder.close();

      final outcome = await reestablishing;
      await closing;

      expect(
        outcome,
        ReestablishResult.closed,
        reason:
            'the wrapper was closing, so it must not report established - '
            'the app layer gates resumption on exactly this value',
      );
      expect(
        holder.isEstablished,
        isFalse,
        reason: 'a closing wrapper must not be left holding an executor',
      );
      expect(
        DatabaseIsolate.connectedDatabases.contains(path),
        isFalse,
        reason:
            'THE DEFECT: the re-establish brought the server up, then the '
            'close removed the wrapper from the registry without shutting it '
            'down, leaving a server no lifecycle sweep could ever reach',
      );
      expect(ReleasableConnection.live.contains(holder), isFalse);
    },
  );

  test(
    'a close arriving while the connect is suspended does not strand the server',
    () async {
      // RE-6 in the window `_closeRequested` was added for: the close lands
      // while `platformConnectDatabase` is still in flight, so the flag is read
      // by a `_reestablishInGate` that is already PAST its `_closed` test and
      // mid-open. Only a gated connect reaches that; the test above can only
      // arrange for the flag to be set before the queued action begins.
      //
      // WHAT WOULD MAKE THIS VACUOUS: asserting the outcome only, or not
      // proving the connect was really suspended when `close()` was called - a
      // connector whose gate never engaged would silently degrade this into a
      // copy of the test above. Both are asserted: `connectSuspended` before
      // the close, and `connectedDatabases` after it, which is the assertion
      // the defect fails.
      final path = dbPath('suspended-connect.db');

      Completer<void>? gate;
      Completer<void>? connectSuspended;

      // Only re-establish connects are gated: `gate` is null for the wrapper's
      // own `open()` below, which must not hang.
      final holder = await ReleasableConnection.openWithConnector(path, (
        name,
      ) async {
        final waitFor = gate;
        if (waitFor != null) {
          connectSuspended!.complete();
          await waitFor.future;
        }
        return platformConnectDatabase(name);
      });
      await holder.ensureOpen(_NoopUser());
      await holder.runCustom('CREATE TABLE IF NOT EXISTS t (v TEXT)');

      expect(await holder.release(), isTrue);
      expect(
        DatabaseIsolate.connectedDatabases.contains(path),
        isFalse,
        reason:
            'arming: the release must actually have shut the server down, '
            'or the re-establish below has nothing to bring back up',
      );

      gate = Completer<void>();
      connectSuspended = Completer<void>();

      final reestablishing = holder.reestablish();
      await connectSuspended.future;
      expect(
        holder.isEstablished,
        isFalse,
        reason:
            'arming: the connect is suspended, so no executor has been '
            'assigned yet - this is the window under test',
      );

      final closing = holder.close();
      gate.complete();

      final outcome = await reestablishing;
      await closing;

      // The defect-guarding assertion goes FIRST, deliberately: `expect` stops
      // at the first failure, so an outcome assertion above it would mask
      // which half a regression broke.
      expect(
        DatabaseIsolate.connectedDatabases.contains(path),
        isFalse,
        reason:
            'THE DEFECT: the suspended connect finished after the close was '
            'requested and brought the server back up, on a wrapper that is '
            'leaving the registry and can never release it again',
      );
      expect(
        outcome,
        ReestablishResult.closed,
        reason:
            'the wrapper was closing before the connect returned, so it must '
            'not report established - the app layer gates resumption on '
            'exactly this value',
      );
      expect(holder.isEstablished, isFalse);
      expect(ReleasableConnection.live.contains(holder), isFalse);
    },
  );

  test(
    'RE-7: a failing executor handback still releases the server it brought up',
    () async {
      // The same suspended-connect window, with the handback throwing.
      // `close()` failing does not un-start the server this re-establish just
      // started, and the wrapper is on its way out of `_registry` either way -
      // so a release skipped because of the throw strands it exactly as the
      // pre-RE-6 code did. Before the fix the throw fell through to the catch
      // clause, which answered `failed` and released nothing.
      //
      // WHAT WOULD MAKE THIS VACUOUS: asserting the outcome only. A version
      // that answered `closed` and skipped the release passes on that alone,
      // so `connectedDatabases` is the assertion that guards the defect, and
      // `handbackAttempted` proves the throwing close was reached at all.
      final path = dbPath('handback-throws.db');

      Completer<void>? gate;
      Completer<void>? connectSuspended;
      var handbackAttempted = false;

      final holder = await ReleasableConnection.openWithConnector(path, (
        name,
      ) async {
        final waitFor = gate;
        if (waitFor == null) return platformConnectDatabase(name);

        connectSuspended!.complete();
        await waitFor.future;
        final real = await platformConnectDatabase(name);
        return real.withExecutor(
          _ThrowingCloseExecutor(real.executor, () => handbackAttempted = true),
        );
      });
      await holder.ensureOpen(_NoopUser());
      await holder.runCustom('CREATE TABLE IF NOT EXISTS t (v TEXT)');

      expect(await holder.release(), isTrue);
      expect(
        DatabaseIsolate.connectedDatabases.contains(path),
        isFalse,
        reason: 'arming: the release must actually have shut the server down',
      );

      gate = Completer<void>();
      connectSuspended = Completer<void>();

      final reestablishing = holder.reestablish();
      await connectSuspended.future;
      final closing = holder.close();
      gate.complete();

      final outcome = await reestablishing;
      await closing;

      expect(
        handbackAttempted,
        isTrue,
        reason:
            'arming: the throwing close must have been reached, or this test '
            'is only re-running the case above',
      );
      // The defect-guarding assertion goes FIRST, deliberately: `expect` stops
      // at the first failure, so an outcome assertion above it would mask
      // which half a regression broke.
      expect(
        DatabaseIsolate.connectedDatabases.contains(path),
        isFalse,
        reason:
            'THE DEFECT: the handback threw, so the server release was skipped '
            'and the server this re-establish started was left running with no '
            'wrapper able to reach it',
      );
      expect(
        outcome,
        ReestablishResult.closed,
        reason:
            'the outcome describes the WRAPPER, which is closing; `failed` '
            'would keep it in the trigger pending set and hold sync stopped '
            'for every account that is still live',
      );
      expect(holder.isEstablished, isFalse);
      expect(ReleasableConnection.live.contains(holder), isFalse);
    },
  );
}

/// A [QueryExecutor] that forwards everything and fails the handback.
///
/// Only `close()` differs. It closes the real executor FIRST and then throws:
/// the exception is the whole point, but leaking a live isolate connection
/// would trade the defect under test for a hung test run. Everything else
/// forwards, because `_reestablishInGate` runs a real `ensureOpen` on this
/// executor before it ever reaches the close.
class _ThrowingCloseExecutor implements QueryExecutor {
  _ThrowingCloseExecutor(this._inner, this._onClose);

  final QueryExecutor _inner;
  final void Function() _onClose;

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _inner.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _inner.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _inner.runInsert(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _inner.runUpdate(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _inner.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _inner.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() => _inner.beginTransaction();

  @override
  QueryExecutor beginExclusive() => _inner.beginExclusive();

  @override
  Future<void> close() async {
    _onClose();
    await _inner.close();
    throw StateError('executor handback failed');
  }
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
