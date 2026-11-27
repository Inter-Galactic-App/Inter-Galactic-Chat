import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/background_assertion.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';

/// What one suspension sweep did.
enum DatabaseSuspendOutcome {
  /// A previous sweep is still holding databases released; nothing to do.
  alreadySuspended,

  /// A call (or other live background execution) is running; releasing would
  /// close the database under it, which is worse than the failure this avoids.
  skippedLiveBackgroundExecution,

  nothingToRelease,

  /// Every tracked database released.
  released,

  /// At least one database could not be released before the deadline. The
  /// process suspends holding a lock: the residual B5 exists to measure.
  partial,
}

/// What one resume did.
enum DatabaseResumeOutcome {
  nothingReleased,

  /// Every released database is established again and sync is running.
  established,

  /// At least one database is unreadable before the device's first unlock.
  /// Normal, not an error; retried on the next resume. Sync stays stopped.
  deferredRetryOnNextResume,

  /// At least one re-establish failed outright. Sync stays stopped so the
  /// failure surfaces here rather than as query errors inside the SDK.
  failed,
}

/// Aggregate-only counters for the release sweep, in the shape S&C approved
/// for the NSE diagnostic write (D1, D2): a fixed key set, saturating, and
/// carrying no identifier, path, timestamp or free text. They are surfaced
/// only as the single aggregate line [toLogString] writes after each sweep.
///
/// The one that matters is [timedOut]. It is the residual the B5 scope said
/// must be measured rather than assumed rare: a transaction that outlives the
/// assertion window, so the process suspends holding a lock - the condition
/// B5 exists to prevent.
///
/// `stale_transaction_uses` is read from
/// [ReleasableConnection.staleTransactionUses] rather than counted here,
/// because the condition it measures is not a sweep event - it is process-wide
/// and can happen with no sweep in sight. It reports whether the SDK zone leak
/// occurred at all in a run.
///
/// WHY IT IS ON THIS LINE. Naming the caller that leaks the zone needs a
/// device capture, and until now the only evidence a run produced was a
/// WARNING that exists solely when the leak fires. Absence of a warning and
/// absence of the condition read identically - a capture could not distinguish
/// "did not reproduce" from "the line was filtered out". A number printed
/// every sweep can say zero, which is a result.
class DatabaseReleaseCounters {
  static const int saturation = 0x7fffffff;

  int sweeps = 0;
  int skippedLiveBackgroundExecution = 0;
  int assertionUnavailable = 0;
  int released = 0;
  int releasedAfterWait = 0;
  int releaseFailed = 0;
  int timedOut = 0;
  int reestablished = 0;
  int deferred = 0;
  int reestablishFailed = 0;

  static int bump(int value) => value >= saturation ? saturation : value + 1;

  String toLogString() =>
      'database_release counters sweeps=$sweeps '
      'skipped_live_background=$skippedLiveBackgroundExecution '
      'assertion_unavailable=$assertionUnavailable released=$released '
      'released_after_wait=$releasedAfterWait release_failed=$releaseFailed '
      'timed_out=$timedOut reestablished=$reestablished deferred=$deferred '
      'reestablish_failed=$reestablishFailed '
      'stale_transaction_uses=${ReleasableConnection.staleTransactionUses}';
}

/// The B5 lifecycle trigger: release the account database before suspension,
/// re-establish it on resume.
///
/// WHY. iOS terminates a suspended process that holds a lock on a file in a
/// shared container (`0xdead10cc`). Locks are transaction-scoped, so the
/// exposure is suspending mid-transaction, and the Matrix SDK holds a
/// transaction across sync processing for seconds at a time. Refusing to
/// release while one is open is correct but, alone, a silent no-op in the
/// common case. So this trigger stops sync, which waits for that transaction,
/// under a background assertion that buys the time, then releases.
///
/// THE ONE CONDITION. Release only when there is no in-flight transaction and
/// no live background execution. The first half is the wrapper's quiescence,
/// polled here after sync has been stopped; the second half is
/// [hasLiveBackgroundExecution], because Flutter reports `paused` while a call
/// runs under the audio background mode and releasing then would close the
/// database out from under the call.
///
/// RESUME-RETRY. `reestablish()` may report `deferred` - the file carries
/// `completeUntilFirstUserAuthentication` and is unreadable between a reboot
/// and the first unlock. That is one narrow window, so the retry is simply
/// the next `resumed`; sync stays stopped until every database is established,
/// because a query against a released wrapper throws by design. Bridging
/// `protectedDataDidBecomeAvailable` from native code was considered and
/// rejected on the B5 row: iOS-only, no CI compile gate, for a case the next
/// resume recovers.
///
/// Pure Dart with zero platform conditionals; the platform-specific piece is
/// the assertion host, injected.
class DatabaseReleaseTrigger with WidgetsBindingObserver {
  DatabaseReleaseTrigger({
    required this.databases,
    required this.suspendSync,
    required this.resumeSync,
    required this.hasLiveBackgroundExecution,
    this.assertionHost,
    this.quiescenceTimeout = const Duration(seconds: 4),
    this.pollInterval = const Duration(milliseconds: 50),
    DatabaseReleaseCounters? counters,
  }) : counters = counters ?? DatabaseReleaseCounters();

  static const String _source = 'database-release';
  static const String assertionName = 'intergalactic.database-release';

  /// The databases to sweep, read fresh on each suspension.
  final List<ReleasableDatabase> Function() databases;

  /// Stops every sync loop and waits for the transactions they hold.
  final Future<void> Function() suspendSync;

  /// Restarts the sync loops. Called only once everything is established.
  final void Function() resumeSync;

  final bool Function() hasLiveBackgroundExecution;

  /// Null means no assertion is available on this platform; the sweep still
  /// runs, it just has no guaranteed window.
  final BackgroundAssertionHost? assertionHost;

  /// How long, in total, to wait for quiescence. Sits inside the roughly five
  /// seconds iOS allows after `didEnterBackground` without an assertion and
  /// well inside the ~30 s one grants, so an unavailable assertion still
  /// leaves the sweep bounded.
  final Duration quiescenceTimeout;

  final Duration pollInterval;

  final DatabaseReleaseCounters counters;

  final Set<ReleasableDatabase> _released = {};
  bool _syncSuspended = false;
  Future<void> _serial = Future<void>.value();

  /// Armed at release time, completed when every released database is
  /// established again. See [whenEstablished].
  Completer<void>? _establishedAgain;

  /// The attached trigger, for lifecycle writers that need [whenEstablished].
  static DatabaseReleaseTrigger? instance;

  /// Databases released and not yet re-established.
  List<ReleasableDatabase> get released => List.unmodifiable(_released);

  bool get retryPending => _released.isNotEmpty;

  /// Completes once every database this trigger released is established
  /// again; already complete when nothing is released.
  ///
  /// This is how a lifecycle writer observes the trigger's intent instead of
  /// racing it. The race is real and order-independent: the presence
  /// watcher's `onResume` runs before this trigger's observer (its listener
  /// is registered during client load, the trigger after), and even with the
  /// order reversed the re-establish is scheduled through a serialised gate
  /// and cannot have started inside the observer callback. So a writer that
  /// asks the wrapper "is a re-establish pending?" at wake gets "no" and the
  /// designed `StateError`. The gate is armed when the release happens, long
  /// before any wake, so whoever asks first still waits for the right thing.
  ///
  /// It stays pending across a `deferred` re-establish (self-limiting: the
  /// retry is the next resume) and completes on the resume that succeeds,
  /// which is also when sync restarts. A `failed` re-establish completes it
  /// with a [StateError] instead, so a waiting writer fails loudly rather
  /// than hanging; the gate is re-armed for the retry so a writer arriving
  /// after the failure waits for that. A permanent failure therefore surfaces
  /// once per resume in every waiting writer's own error path, which is the
  /// same loud shape the wrapper keeps one layer down.
  Future<void> get whenEstablished =>
      _establishedAgain?.future ?? Future<void>.value();

  /// [whenEstablished] for a caller that just wants to know whether to
  /// proceed: true when the database is established (or no trigger is
  /// attached, or nothing was released), false when the re-establish failed
  /// - logged here, so the caller can simply return.
  ///
  /// This is the third copy of the same wait (the presence watcher and the
  /// notification router carry their own), so it lives on the trigger. The
  /// callers it exists for are lifecycle- and timer-driven database
  /// accessors that can fire before the trigger's own resume: the presence
  /// READ on the phone at 34e26c9e came from the last-seen cache's cleaner
  /// firing two seconds before `event=resumed`, on a path the writer audit
  /// did not cover because it read timers that write, not timers that read.
  static Future<bool> waitForDatabase(String source) async {
    final trigger = instance;
    if (trigger == null) {
      return true;
    }
    final stopwatch = Stopwatch()..start();
    try {
      await trigger.whenEstablished;
    } on StateError catch (error) {
      Log.w(
        'database_gate source=$source outcome=failed '
        'waited_ms=${stopwatch.elapsedMilliseconds} error=$error',
        category: LogCategory.app,
        source: _source,
      );
      return false;
    }
    if (stopwatch.elapsedMilliseconds > 0) {
      Log.i(
        'database_gate source=$source outcome=established '
        'waited_ms=${stopwatch.elapsedMilliseconds}',
        category: LogCategory.app,
        source: _source,
      );
    }
    return true;
  }

  void attach() {
    WidgetsBinding.instance.addObserver(this);
    instance = this;
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(instance, this)) {
      instance = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        unawaited(suspend());
      case AppLifecycleState.resumed:
        unawaited(resume());
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Serialised so a quick pause/resume cannot interleave a sweep with a
  /// re-establish; each waits for the previous to finish.
  Future<T> _serialised<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Releases the databases, optionally waiting past [quiescenceTimeout].
  ///
  /// [quiescenceDeadline] can only EXTEND the wait, never shorten it, and it
  /// is an absolute instant rather than a duration because this call is
  /// serialised: a duration computed by the caller would start counting when
  /// the sweep finally runs, not when the caller's own window began.
  ///
  /// A caller extends it when it knows how much time it actually has. The
  /// iOS silent wake does: it holds a 25 s native deadline and sets aside a
  /// reserve for exactly this, and a fixed 4 s wait spent only part of that
  /// reserve and then left the database open - which is the termination this
  /// class exists to prevent. Shortening is refused for the same reason: a
  /// caller that is already late gains nothing by giving up sooner.
  Future<DatabaseSuspendOutcome> suspend({DateTime? quiescenceDeadline}) =>
      _serialised(() => _suspend(quiescenceDeadline: quiescenceDeadline));

  Future<DatabaseResumeOutcome> resume() => _serialised(_resume);

  Future<DatabaseSuspendOutcome> _suspend({
    DateTime? quiescenceDeadline,
  }) async {
    counters.sweeps = DatabaseReleaseCounters.bump(counters.sweeps);

    if (_released.isNotEmpty || _syncSuspended) {
      return DatabaseSuspendOutcome.alreadySuspended;
    }

    if (hasLiveBackgroundExecution()) {
      counters.skippedLiveBackgroundExecution = DatabaseReleaseCounters.bump(
        counters.skippedLiveBackgroundExecution,
      );
      Log.i(
        'database_release event=skipped reason=live_background_execution',
        category: LogCategory.app,
        source: _source,
      );
      return DatabaseSuspendOutcome.skippedLiveBackgroundExecution;
    }

    final targets = databases();
    if (targets.isEmpty) {
      return DatabaseSuspendOutcome.nothingToRelease;
    }

    final assertion = await BackgroundAssertion.begin(
      assertionName,
      host: assertionHost,
    );
    if (!assertion.granted) {
      counters.assertionUnavailable = DatabaseReleaseCounters.bump(
        counters.assertionUnavailable,
      );
    }

    try {
      // Sync first. Its transaction is the thing quiescence waits on, and a
      // loop left running would open a new one as soon as the last closed.
      //
      // Marked BEFORE the await: `suspendSync` is injected and carries no
      // no-throw contract, and it may already have stopped some loops when it
      // throws. Setting the flag afterwards would leave `_syncSuspended` false,
      // so the next `_resume()` would take the `nothingReleased` path without
      // calling `resumeSync()` and sync would never restart.
      _syncSuspended = true;
      await suspendSync();

      final floor = DateTime.now().add(quiescenceTimeout);
      final deadline =
          quiescenceDeadline != null && quiescenceDeadline.isAfter(floor)
          ? quiescenceDeadline
          : floor;
      var allReleased = true;

      for (final database in targets) {
        var waited = false;
        while (true) {
          if (await database.release()) {
            _released.add(database);
            counters.released = DatabaseReleaseCounters.bump(counters.released);
            if (waited) {
              counters.releasedAfterWait = DatabaseReleaseCounters.bump(
                counters.releasedAfterWait,
              );
            }
            break;
          }

          if (!database.isEstablished) {
            // The wrapper dropped its executor but the server did not
            // acknowledge the shutdown. It still needs re-establishing on
            // resume, so it counts as released for that purpose.
            _released.add(database);
            counters.releaseFailed = DatabaseReleaseCounters.bump(
              counters.releaseFailed,
            );
            allReleased = false;
            break;
          }

          if (!DateTime.now().isBefore(deadline)) {
            counters.timedOut = DatabaseReleaseCounters.bump(counters.timedOut);
            allReleased = false;
            Log.w(
              'database_release event=timed_out reason=not_quiescent '
              'assertion_granted=${assertion.granted}',
              category: LogCategory.app,
              source: _source,
            );
            break;
          }

          waited = true;
          await Future<void>.delayed(pollInterval);
        }
      }

      if (_released.isNotEmpty) {
        _establishedAgain ??= Completer<void>();
      }

      Log.i(
        'database_release event=suspended released=${_released.length} '
        'of=${targets.length} assertion_granted=${assertion.granted}',
        category: LogCategory.app,
        source: _source,
      );
      Log.i(counters.toLogString(), category: LogCategory.app, source: _source);

      return allReleased
          ? DatabaseSuspendOutcome.released
          : DatabaseSuspendOutcome.partial;
    } finally {
      await assertion.end();
    }
  }

  Future<DatabaseResumeOutcome> _resume() async {
    if (_released.isEmpty) {
      if (_syncSuspended) {
        // Nothing was released (timed out, or the server refused) but sync was
        // stopped for the attempt. The database is still established, so
        // sync can simply continue.
        _syncSuspended = false;
        resumeSync();
      }
      return DatabaseResumeOutcome.nothingReleased;
    }

    var deferred = false;
    var failed = false;
    for (final database in _released.toList()) {
      switch (await database.reestablish()) {
        case ReestablishResult.established:
          _released.remove(database);
          counters.reestablished = DatabaseReleaseCounters.bump(
            counters.reestablished,
          );
        case ReestablishResult.deferred:
          deferred = true;
          counters.deferred = DatabaseReleaseCounters.bump(counters.deferred);
        case ReestablishResult.closed:
          // Closed while it was released. Nothing can re-establish it - it is
          // out of the wrapper registry and holds no executor - so keeping it
          // pending would mean `_released` never empties, `resumeSync()` is
          // never called, and sync stays stopped for every account that IS
          // still live, for the life of the process. Discard it, and do not
          // count it as re-established, because it was not.
          _released.remove(database);
          Log.i(
            'database_release event=discarded_closed',
            category: LogCategory.app,
            source: _source,
          );
        case ReestablishResult.failed:
          failed = true;
          counters.reestablishFailed = DatabaseReleaseCounters.bump(
            counters.reestablishFailed,
          );
      }
    }

    if (_released.isEmpty) {
      _syncSuspended = false;
      resumeSync();
      // Writers waiting on whenEstablished run after sync is back, and the
      // gate is cleared before they run so a fresh release re-arms it.
      final establishedAgain = _establishedAgain;
      _establishedAgain = null;
      establishedAgain?.complete();
      Log.i(
        'database_release event=resumed',
        category: LogCategory.app,
        source: _source,
      );
      return DatabaseResumeOutcome.established;
    }

    if (deferred && !failed) {
      Log.i(
        'database_release event=deferred pending=${_released.length} '
        'retry=next_resume',
        category: LogCategory.app,
        source: _source,
      );
      return DatabaseResumeOutcome.deferredRetryOnNextResume;
    }

    Log.w(
      'database_release event=reestablish_failed pending=${_released.length} '
      'sync=stopped retry=next_resume',
      category: LogCategory.app,
      source: _source,
    );
    final failedGate = _establishedAgain;
    _establishedAgain = Completer<void>();
    // No writer may be waiting; ignore() keeps an unlistened error from
    // reaching the zone's unhandled-error hook while later listeners still
    // receive it.
    failedGate?.future.ignore();
    failedGate?.completeError(
      StateError(
        'database re-establish failed; ${_released.length} database(s) '
        'still released, retry on next resume',
      ),
    );
    return DatabaseResumeOutcome.failed;
  }
}
