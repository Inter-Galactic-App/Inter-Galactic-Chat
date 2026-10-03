import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/database/database_platform.dart';

// `dart:io` and the drift isolate server are reached through
// `database_platform.dart` rather than imported here. This file is pulled into
// the web entry graph by `main.dart`, and importing
// `multiple_database_server.dart` directly dragged `package:drift/native.dart`
// and the sqlite3 FFI bindings into dart2js with it. See the stub for the
// failure that caused.
export 'package:intergalactic/utils/database/database_platform_types.dart'
    show ReestablishResult;

/// How a [ReleasableConnection] reaches a platform database connection.
///
/// Production is always `platformConnectDatabase`. The only other supplier is
/// [ReleasableConnection.openWithConnector]; see there for why the seam exists.
typedef DatabaseConnector =
    Future<DatabaseConnection> Function(String databaseName);

/// What the lifecycle trigger needs from a releasable database, and nothing
/// more. [ReleasableConnection] is the one real implementation; the trigger's
/// tests supply fakes.
abstract class ReleasableDatabase {
  String get databaseName;

  bool get isEstablished;

  /// True when no transaction, exclusive block or standalone statement is in
  /// flight - the only state in which [release] does not refuse.
  bool get isQuiescent;

  Future<bool> release();

  Future<ReestablishResult> reestablish();
}

/// A [QueryExecutor] whose inner executor can be swapped.
///
/// WHY THIS EXISTS. `DatabaseIsolate.release()` shuts the drift server down so
/// no lock is held across suspension (0xdead10cc). But both callers hand their
/// connection to a long-lived object — `MatrixSdkDriftDatabase.init(connection)`
/// and `DriftFileCacheDatabase(connection)` — which would then hold a connection
/// whose server is gone. Release without re-establish breaks the app on resume.
///
/// The design is a stable wrapper the SDK holds forever, with the inner executor
/// swapped **eagerly** on resume rather than lazily on next use. Eager is the
/// whole point: a lazy reconnect would have to handle "used while dead" at every
/// call site inside the SDK, whereas an eager swap means no caller ever observes
/// a dead connection. It also means the Matrix SDK is untouched, so there is no
/// delta to carry on the pinned `upstream-v6.1.1` fork.
class ReleasableConnection implements QueryExecutor, ReleasableDatabase {
  ReleasableConnection._(
    this._databaseName,
    this._inner,
    this._dialect,
    this._connectDatabase,
  );

  /// Every wrapper opened and not yet closed, in this isolate.
  ///
  /// This is what the lifecycle trigger sweeps. It is the registry the B5
  /// design was missing: `DatabaseIsolate.releaseAll()` can shut servers down,
  /// but only the wrappers can re-establish, so the trigger must reach them
  /// rather than the isolate. Per-isolate, like `DatabaseIsolate._connected`.
  static final Set<ReleasableConnection> _registry = {};

  static List<ReleasableConnection> get live => List.unmodifiable(_registry);

  /// Opens [databaseName] and wraps it.
  static Future<ReleasableConnection> open(String databaseName) =>
      _open(databaseName, platformConnectDatabase);

  /// [open], with the platform connect supplied by the caller.
  ///
  /// WHY A SEAM IS NEEDED AT ALL. Two branches of [_reestablishInGate] exist
  /// only for what arrives WHILE the connect is suspended: the
  /// `_closeRequested` test, and the executor handback that follows it. A test
  /// that cannot hold the connect open reaches neither on purpose - it can only
  /// arrange for the close to win the latch BEFORE the queued re-establish
  /// starts, which is a different window from the one the code guards. That is
  /// what the first version of the RE-6 test did, while its comment claimed
  /// otherwise.
  ///
  /// WHY THIS SHAPE. Injected per wrapper rather than through a static hook:
  /// there is no process-wide field to reset, so a test that forgets its
  /// teardown cannot silently redirect every later test in the run. [open]
  /// keeps its exact production signature, so no production call site can pass
  /// a connector even by accident, and the production path is
  /// `platformConnectDatabase` called directly - the same call, in the same
  /// place, as before this seam existed.
  @visibleForTesting
  static Future<ReleasableConnection> openWithConnector(
    String databaseName,
    DatabaseConnector connect,
  ) => _open(databaseName, connect);

  static Future<ReleasableConnection> _open(
    String databaseName,
    DatabaseConnector connect,
  ) async {
    final connection = await connect(databaseName);
    final wrapper = ReleasableConnection._(
      databaseName,
      connection.executor,
      connection.executor.dialect,
      connect,
    );
    _registry.add(wrapper);
    return wrapper;
  }

  final String _databaseName;

  /// The connect this wrapper re-establishes through. `platformConnectDatabase`
  /// outside tests; see [openWithConnector].
  final DatabaseConnector _connectDatabase;

  @override
  String get databaseName => _databaseName;

  /// Captured from the first [ensureOpen] so a rebuilt executor can be reopened
  /// with the same user.
  ///
  /// Sound, and it is what drift itself does: `beforeOpen` and migrations key to
  /// the executor instance and the delegate's open state, never to the user
  /// (`engines.dart:452-476, :512`). The "not called more than once" guarantee
  /// on [QueryExecutorUser] is per-executor, not per-user — a fresh executor
  /// MUST re-run `beforeOpen`, because per-connection pragmas have to be
  /// reapplied to the new connection.
  QueryExecutorUser? _user;

  QueryExecutor? _inner;
  final SqlDialect _dialect;

  /// Whether the drift server behind [_databaseName] is known to be down.
  ///
  /// `_inner == null` does NOT mean that. It is true after a successful
  /// release, after a release whose `DatabaseIsolate.release` reported failure
  /// and left the server up, and after [close], which hands the executor back
  /// without shutting the server down at all. [release] answers with this
  /// rather than with "we have no executor", so a second call reports what was
  /// actually achieved instead of inferring success from a field the failure
  /// path also clears.
  bool _serverShutDown = false;

  /// Serialises release and re-establish against each other.
  ///
  /// drift's own `DelegatedDatabase._openingLock` only serialises opens WITHIN
  /// one instance, and a swap replaces the instance — so it provides nothing
  /// here. Without this lock, interleaved calls can leave two live inners, or a
  /// swap that discards one mid-open. [ensureOpen] is no longer in the gate -
  /// it is tracked as an in-flight statement instead, which keeps [release]
  /// from swapping the executor underneath it, and lets it wait on a pending
  /// re-establish without deadlocking on this gate.
  Future<void> _gate = Future<void>.value();

  /// Transactions in flight. Release refuses while any is open.
  int _openTransactions = 0;

  /// RE-3. Standalone statements in flight.
  ///
  /// Quiescence originally counted transactions only, so `release()` could fire
  /// with a bare `runSelect`/`runInsert`/`runCustom` in progress and shut the
  /// server down underneath it. The SDK issues plenty of single-statement reads
  /// outside a transaction, so that is a live case rather than a theoretical
  /// one.
  int _inFlightStatements = 0;

  /// True when no transaction, exclusive block or standalone statement is in
  /// flight. This is what "quiescent" has to mean for a release to be safe.
  bool get isQuiescent => _openTransactions == 0 && _inFlightStatements == 0;

  Future<T> _tracked<T>(Future<T> Function() run) async {
    _inFlightStatements++;
    try {
      return await run();
    } finally {
      _inFlightStatements--;
    }
  }

  bool get isEstablished => _inner != null;

  Future<T> _serialised<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _gate = _gate.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  QueryExecutor get _live {
    final inner = _inner;
    if (inner == null) {
      // A sequencing bug, not a runtime condition to tolerate. Work must not be
      // attempted while released; the app layer gates resumption on
      // [reestablish] returning [ReestablishResult.established].
      throw StateError(
        'Database work attempted while the connection is released. '
        'Re-establish before resuming work.',
      );
    }
    return inner;
  }

  /// The re-establish currently in progress, if any.
  ///
  /// Set the moment [reestablish] is called, before it takes the gate, so a
  /// caller arriving in the same event-loop turn can see it.
  Future<ReestablishResult>? _pendingReestablish;

  /// Latched by [close]. A re-establish that was already queued behind the
  /// close must not hand this wrapper a live executor afterwards - it is out
  /// of `_registry` by then, so nothing could ever release it again.
  bool _closed = false;

  /// Set by [close] BEFORE it takes the gate, unlike [_closed].
  ///
  /// The two are not redundant. [_closed] says the close has RUN; this says one
  /// has been ASKED FOR. Only the second is visible to a `_reestablishInGate`
  /// that the close is queued behind, and that window is precisely where a
  /// re-established server was being stranded outside `_registry`. See RE-6 in
  /// [close].
  bool _closeRequested = false;

  /// [_live], but an async caller that arrives while a re-establish is in
  /// progress waits for it instead of throwing.
  ///
  /// A narrow courtesy, not the wake-race fix. A re-establish is only "in
  /// progress" once [reestablish] has been called, and at wake the trigger
  /// cannot have called it yet when the first lifecycle writer runs - its
  /// observer runs after the writer's, and its resume is serialised a
  /// microtask later regardless. Lifecycle writers therefore await
  /// `DatabaseReleaseTrigger.whenEstablished`, which is armed at release
  /// time; this wait only covers a caller that lands mid-swap. With nothing
  /// in progress this still throws: silently deferring work is the lazy
  /// reconnect the design rejected. Synchronous factories
  /// ([beginTransaction], [beginExclusive]) cannot wait and keep throwing.
  Future<QueryExecutor> _liveOrPending() async {
    if (_inner == null) {
      final pending = _pendingReestablish;
      if (pending != null) {
        await pending;
      }
    }
    return _live;
  }

  /// Releases the underlying connection so no lock is held at suspension.
  ///
  /// REFUSES, returning false, while a transaction is open — a drift
  /// [TransactionExecutor] is a separate object with its own lifetime and cannot
  /// be swapped underneath, so "reconnect mid-transaction" is meaningless.
  ///
  /// Refusal alone is not a strategy: the Matrix SDK holds a transaction across
  /// sync processing for seconds at a time, so the caller must WAIT for
  /// quiescence under a background-task assertion rather than treating a refusal
  /// as done. See the B5 trigger.
  Future<bool> release() {
    return _serialised(() async {
      if (!isQuiescent) {
        Log.d(
          "Database release refused: $_openTransactions transaction(s) and "
          "$_inFlightStatements statement(s) in flight",
          category: LogCategory.app,
          source: 'database-release',
        );
        return false;
      }
      if (_inner == null) {
        // Not "already released, so true". Dropping the executor is this
        // wrapper's half; the server going down is the half that matters, and
        // the two come apart when `DatabaseIsolate.release` fails or when
        // [close] runs. Answering true here would let a caller record a
        // release while the server is still up.
        return _serverShutDown;
      }

      _inner = null;
      _serverShutDown = await platformReleaseDatabase(_databaseName);
      return _serverShutDown;
    });
  }

  /// Rebuilds the inner executor and reopens it BEFORE exposing it.
  ///
  /// Order matters: connect, then `ensureOpen`, then assign. `_inner` is never a
  /// half-open executor, and a fresh connection is always built rather than
  /// reopened — drift's `_closed` is a one-way latch and says so explicitly
  /// ("Can't re-open a database after closing it"), and violating that surfaces
  /// as a `StateError` at an arbitrary later query rather than here.
  Future<ReestablishResult> reestablish() {
    final inProgress = _pendingReestablish;
    if (inProgress != null) {
      return inProgress;
    }
    final result = _serialised(_reestablishInGate);
    _pendingReestablish = result;
    return result.whenComplete(() {
      if (identical(_pendingReestablish, result)) {
        _pendingReestablish = null;
      }
    });
  }

  Future<ReestablishResult> _reestablishInGate() async {
    if (_closed) {
      return ReestablishResult.closed;
    }
    if (_inner != null) {
      return ReestablishResult.established;
    }

    // RE-1. Deferred-ness MUST be determined here, before crossing the
    // isolate boundary. The open happens inside the drift isolate and the
    // failure crosses back as a drift remote error, not a FileSystemException
    // - so catching that type below could never fire for the case the tri-state
    // exists to serve, and resume-before-first-unlock reported `failed`.
    // Serialisation may also degrade the remote cause, so matching a Dart type
    // through the boundary is fragile in both directions.
    final readable = _probeReadable();
    if (readable != ReestablishResult.established) {
      return readable;
    }

    try {
      final connection = await _connectDatabase(_databaseName);
      // The server is up again from here on, whatever this method goes on to
      // answer - including the closed-mid-open path below, which hands the
      // executor back but does not shut the server down.
      _serverShutDown = false;

      // RE-2. Never report `established` without proving the database opens.
      // Previously ensureOpen ran only when a user had been captured, so a
      // release before the SDK's first ensureOpen assigned `_inner` and
      // claimed success having opened nothing - and the app layer gates
      // resumption on exactly this value.
      final user = _user;
      if (user != null) {
        await connection.executor.ensureOpen(user);
      } else {
        // No captured user yet: prove openability without running migrations,
        // which is what an arbitrary throwaway QueryExecutorUser would do.
        await connection.executor.runSelect('PRAGMA user_version', const []);
      }

      if (_closed || _closeRequested) {
        // Closed while this open was crossing the isolate boundary. Hand back
        // the executor rather than parking it on a wrapper no sweep can see.
        //
        // RE-7. The handback is allowed to fail; the server release below is
        // not allowed to be skipped when it does. A throwing `close()` used to
        // jump straight to the catch clause at the end of this method, which
        // answered `failed` and left the server THIS call had just brought up
        // with no wrapper in `_registry` able to release it - the same stranded
        // server RE-6 fixed, reached through the exception path rather than the
        // success path.
        //
        // Caught and logged HERE rather than rethrown after the release, and
        // deliberately not a `finally`: the release can throw too, and a
        // `finally` would let that second failure replace this one, so the
        // cause that started it would never be recorded anywhere.
        try {
          await connection.executor.close();
        } catch (error, stackTrace) {
          Log.w(
            "Database executor handback failed while closing mid-re-establish; "
            "releasing the server anyway",
            category: LogCategory.app,
            source: 'database-release',
          );
          Log.onError(error, stackTrace);
        }

        // RE-6. Shut the server down too. `close()` deliberately does not - it
        // hands the executor back and leaves the server up, which is correct
        // when the server was already up and something else may hold it. Here
        // it is not: THIS call brought the server up moments ago, on a wrapper
        // that is closing and is leaving `_registry`. Skipping this is what
        // stranded the server with nothing able to reach it.
        _serverShutDown = await platformReleaseDatabase(_databaseName);

        // `closed`, not `failed`, even when the handback threw. The outcome
        // describes the WRAPPER, and this one is closing: out of `_registry`,
        // holding no executor, with nothing left for the trigger to retry.
        // `failed` would keep it in the trigger's pending set, which is the
        // state that holds sync stopped for every account that IS still live.
        return ReestablishResult.closed;
      }

      _inner = connection.executor;
      return ReestablishResult.established;
    } catch (error, stackTrace) {
      Log.w("Database re-establish failed");
      Log.onError(error, stackTrace);
      return ReestablishResult.failed;
    }
  }

  /// Distinguishes "cannot read it yet" from "cannot read it at all".
  ///
  /// The probe itself needs `dart:io`, so it lives behind
  /// `database_platform.dart`. See `database_platform_io.dart` for the errno
  /// reasoning.
  ReestablishResult _probeReadable() =>
      platformProbeDatabaseReadable(_databaseName);

  @override
  SqlDialect get dialect => _dialect;

  /// Tracked, not gated. It used to run inside [_gate], which would deadlock
  /// with [_liveOrPending]: the wait is for a re-establish that itself needs
  /// the gate. Tracking it as an in-flight statement gives the same
  /// protection the gate did - [release] refuses while it runs, so the
  /// executor it opens cannot be swapped underneath it.
  @override
  Future<bool> ensureOpen(QueryExecutorUser user) {
    _user = user;
    return _tracked(() async {
      final inner = await _liveOrPending();
      return inner.ensureOpen(user);
    });
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) {
    return _tracked(() async {
      final inner = await _liveOrPending();
      return inner.runSelect(statement, args);
    });
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    return _tracked(() async {
      final inner = await _liveOrPending();
      return inner.runInsert(statement, args);
    });
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return _tracked(() async {
      final inner = await _liveOrPending();
      return inner.runUpdate(statement, args);
    });
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) {
    return _tracked(() async {
      final inner = await _liveOrPending();
      return inner.runDelete(statement, args);
    });
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) {
    return _tracked(() async {
      final inner = await _liveOrPending();
      return inner.runCustom(statement, args);
    });
  }

  @override
  Future<void> runBatched(BatchedStatements statements) {
    return _tracked(() async {
      final inner = await _liveOrPending();
      return inner.runBatched(statements);
    });
  }

  @override
  TransactionExecutor beginTransaction() {
    // Synchronous factory: it must return an object immediately, so a missing
    // inner can only be signalled by throwing. That is why `deferred` lives
    // beside this interface rather than inside it.
    final transaction = _live.beginTransaction();
    _openTransactions++;
    return _CountedTransaction(transaction, this, _onTransactionDone);
  }

  @override
  QueryExecutor beginExclusive() {
    // RE-4. An exclusive block was invisible to the release guard, which is a
    // hole in the one thing this class exists to protect. Latent today - the
    // pinned SDK and schema package use no `exclusively(` - but counted anyway,
    // because the guard should not depend on a caller not using an API.
    final exclusive = _live.beginExclusive();
    _openTransactions++;
    return _CountedExclusive(exclusive, this, _onTransactionDone);
  }

  @override
  Future<void> close() async {
    // RE-6. Latch the REQUEST before queueing, not inside the queued action.
    //
    // `_closed` is set inside `_serialised`, so a close arriving while
    // `_reestablishInGate` is running queues behind it and `_closed` is still
    // false when that method tests it. The re-establish then assigns `_inner`
    // and answers `established` - and the app layer gates resumption on
    // exactly that value - after which the queued close removes the wrapper
    // from `_registry` and closes the executor, but never shuts the drift
    // server down. The server stays up with no wrapper any sweep can reach,
    // which is the 0xdead10cc exposure this class exists to prevent. Setting
    // the flag here, before the gate, is what makes that window observable.
    _closeRequested = true;

    // Through the gate like every other mutation of `_inner`. Unserialised,
    // close() could interleave with an in-flight re-establish: it would drop
    // the wrapper from `_registry`, and the re-establish would then assign a
    // fresh executor to a wrapper nothing sweeps any more. The process would
    // suspend holding the database open, which is the 0xdead10cc exposure this
    // class exists to prevent.
    return _serialised(() async {
      _closed = true;
      _pendingReestablish = null;
      _registry.remove(this);
      final inner = _inner;
      _inner = null;
      await inner?.close();
    });
  }

  void _onTransactionDone() {
    if (_openTransactions > 0) {
      _openTransactions--;
    }
  }

  /// RE-5. How many statements or nested blocks arrived on a transaction or
  /// exclusive executor AFTER it had completed, and were run on the
  /// connection instead. Saturating, process-wide, no identifiers.
  ///
  /// drift resolves the engine from the zone, so a future spawned inside a
  /// `transaction()` block and outliving it still targets that transaction's
  /// executor. drift only asserts against this in debug builds. In profile
  /// and release the request reaches the server, which waits for the dead
  /// executor's turn in its backlog - forever. Nothing counts it here because
  /// the parent's count dropped at commit, so `release()` sees a quiescent
  /// connection, shuts the server down, and the hung request finally fails
  /// with `Bad state: No element`. That is the B5 release-instant
  /// observation; without a release it is a silent hang.
  static int staleTransactionUses = 0;

  /// [ran] says what actually happened, and it must: this line is the
  /// mechanism for naming the caller that leaked the zone in a device
  /// capture, so the clause a reader looks for is whether the work landed.
  /// Folding "(refused)" into [what] while the sentence still said "ran on
  /// the connection instead" made a refusal read as a completed write.
  static void _noteStaleTransactionUse(String what, {required bool ran}) {
    if (staleTransactionUses < 0x7fffffff) {
      staleTransactionUses++;
    }
    // The stack names the caller that leaked the zone, which is what a device
    // capture needs; after a few the count is enough.
    final withStack = staleTransactionUses <= 3;
    final outcome = ran
        ? 'ran on the connection instead'
        : 'REFUSED: it would commit what the rollback discarded';
    Log.w(
      'database $what issued on a completed transaction; $outcome '
      '(stale_transaction_uses=$staleTransactionUses)',
      category: LogCategory.app,
      source: 'database-release',
    );
    if (withStack) {
      Log.d(
        'stale transaction use stack: ${StackTrace.current}',
        category: LogCategory.app,
        source: 'database-release',
      );
    }
  }
}

/// Wraps a [TransactionExecutor] purely to know when it ends.
///
/// The count is what lets [ReleasableConnection.release] refuse rather than
/// swap an executor out from under a live transaction.
class _CountedTransaction implements TransactionExecutor {
  _CountedTransaction(this._inner, this._root, this._onDone);

  final TransactionExecutor _inner;
  final ReleasableConnection _root;
  final void Function() _onDone;
  bool _finished = false;

  /// True once [send] returned without error. Only then did the parent's
  /// work land, and only then may a late WRITE run on the root.
  bool _committed = false;

  void _finish() {
    if (_finished) return;
    _finished = true;
    _onDone();
  }

  /// Work that arrives after [_finish] runs on [_root] instead of [_inner].
  ///
  /// [_inner] names a server-side executor that no longer exists; a request
  /// on it waits at the server for a turn that never comes (see
  /// [ReleasableConnection.staleTransactionUses]). The root is live and
  /// counted, which is the only route by which every request to the server
  /// stays visible to `release()`.
  ///
  /// Reads run on the root after any end. Writes and nested blocks run on it
  /// only after a COMMIT: the caller wanted to join a parent that has landed,
  /// so nothing is lost by running outside it. After a rollback or an
  /// abandonment the parent's work is gone, and a late write run on the root
  /// would silently and durably land what the rollback discarded - so it
  /// throws instead. That still satisfies the contract: a local throw reaches
  /// the server not at all.
  QueryExecutor? get _afterFinish => _finished ? _root : null;

  QueryExecutor _writeTargetAfterFinish(String what) {
    if (_committed) {
      ReleasableConnection._noteStaleTransactionUse(what, ran: true);
      return _root;
    }
    ReleasableConnection._noteStaleTransactionUse(what, ran: false);
    throw StateError(
      'Database $what issued on a transaction that was rolled back or '
      'abandoned; it would commit what the rollback discarded',
    );
  }

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  bool get supportsNestedTransactions => _inner.supportsNestedTransactions;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) {
    final root = _afterFinish;
    if (root != null) {
      // Not logged: drift calls this before every statement, and the
      // statement that follows is the one worth a line.
      return root.ensureOpen(user);
    }
    return _inner.ensureOpen(user);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse('select', ran: true);
      return root.runSelect(statement, args);
    }
    return _inner.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    if (_finished) {
      return Future.sync(
        () => _writeTargetAfterFinish('insert').runInsert(statement, args),
      );
    }
    return _inner.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    if (_finished) {
      return Future.sync(
        () => _writeTargetAfterFinish('update').runUpdate(statement, args),
      );
    }
    return _inner.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) {
    if (_finished) {
      return Future.sync(
        () => _writeTargetAfterFinish('delete').runDelete(statement, args),
      );
    }
    return _inner.runDelete(statement, args);
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) {
    if (_finished) {
      // A custom statement may write; treat it as one.
      return Future.sync(
        () => _writeTargetAfterFinish(
          'custom statement',
        ).runCustom(statement, args),
      );
    }
    return _inner.runCustom(statement, args);
  }

  @override
  Future<void> runBatched(BatchedStatements statements) {
    if (_finished) {
      return Future.sync(
        () => _writeTargetAfterFinish('batch').runBatched(statements),
      );
    }
    return _inner.runBatched(statements);
  }

  @override
  TransactionExecutor beginTransaction() {
    if (_finished) {
      return _writeTargetAfterFinish('nested transaction').beginTransaction();
    }
    return _inner.beginTransaction();
  }

  @override
  QueryExecutor beginExclusive() {
    if (_finished) {
      return _writeTargetAfterFinish('nested exclusive block').beginExclusive();
    }
    return _inner.beginExclusive();
  }

  @override
  Future<void> send() async {
    try {
      await _inner.send();
      _committed = true;
    } finally {
      _finish();
    }
  }

  @override
  Future<void> rollback() async {
    try {
      await _inner.rollback();
    } finally {
      _finish();
    }
  }

  @override
  Future<void> close() async {
    try {
      await _inner.close();
    } finally {
      _finish();
    }
  }
}

/// Wraps the executor returned by `beginExclusive()` so the exclusive block is
/// visible to the release guard (RE-4).
class _CountedExclusive implements QueryExecutor {
  _CountedExclusive(this._inner, this._root, this._onDone);

  final QueryExecutor _inner;
  final ReleasableConnection _root;
  final void Function() _onDone;
  bool _finished = false;

  void _finish() {
    if (_finished) return;
    _finished = true;
    _onDone();
  }

  /// After the block closed its executor is dead at the server, so late
  /// work runs on the root - unconditionally, which is DELIBERATELY not
  /// `_CountedTransaction`'s rule. That class refuses late writes after a
  /// rollback because they would commit what the rollback discarded. An
  /// exclusive block has no rollback: `close()` is its only and normal end,
  /// every statement inside it was autocommitted as it ran, and nothing was
  /// discarded for a late write to resurrect. Latent today (no caller of
  /// `beginExclusive` in the tree, RE-4), but the reason is recorded so the
  /// asymmetry is not mistaken for an omission.
  QueryExecutor? get _afterFinish => _finished ? _root : null;

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) =>
      (_afterFinish ?? _inner).ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse('select', ran: true);
      return root.runSelect(statement, args);
    }
    return _inner.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse('insert', ran: true);
      return root.runInsert(statement, args);
    }
    return _inner.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse('update', ran: true);
      return root.runUpdate(statement, args);
    }
    return _inner.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse('delete', ran: true);
      return root.runDelete(statement, args);
    }
    return _inner.runDelete(statement, args);
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse(
        'custom statement',
        ran: true,
      );
      return root.runCustom(statement, args);
    }
    return _inner.runCustom(statement, args);
  }

  @override
  Future<void> runBatched(BatchedStatements statements) {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse('batch', ran: true);
      return root.runBatched(statements);
    }
    return _inner.runBatched(statements);
  }

  @override
  TransactionExecutor beginTransaction() {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse(
        'nested transaction',
        ran: true,
      );
      return root.beginTransaction();
    }
    return _inner.beginTransaction();
  }

  @override
  QueryExecutor beginExclusive() {
    final root = _afterFinish;
    if (root != null) {
      ReleasableConnection._noteStaleTransactionUse(
        'nested exclusive block',
        ran: true,
      );
      return root.beginExclusive();
    }
    return _inner.beginExclusive();
  }

  @override
  Future<void> close() async {
    try {
      await _inner.close();
    } finally {
      _finish();
    }
  }
}
