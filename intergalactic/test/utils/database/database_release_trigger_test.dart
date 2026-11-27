import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/background_assertion.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';

/// B5 lifecycle trigger.
///
/// WHAT WOULD MAKE THESE WRONG, stated first: the trigger's whole job is the
/// ORDER of things - stop sync, wait for quiet, release, end the assertion,
/// and on resume re-establish BEFORE sync restarts. So every test records the
/// order of calls into a single journal and asserts on that, not on end
/// states alone. A test that only checks `isEstablished` at the end would pass
/// against a trigger that restarted sync onto a released database.
void main() {
  late List<String> journal;

  setUp(() {
    journal = [];
  });

  DatabaseReleaseTrigger trigger({
    required List<_FakeDatabase> databases,
    bool liveBackgroundExecution = false,
    BackgroundAssertionHost? host,
    Duration quiescenceTimeout = const Duration(milliseconds: 60),
    Future<void> Function()? suspendSync,
  }) => DatabaseReleaseTrigger(
    databases: () => databases,
    suspendSync: suspendSync ?? () async => journal.add('sync:suspend'),
    resumeSync: () => journal.add('sync:resume'),
    hasLiveBackgroundExecution: () => liveBackgroundExecution,
    assertionHost: host,
    quiescenceTimeout: quiescenceTimeout,
    pollInterval: const Duration(milliseconds: 2),
  );

  test('stops sync, releases under the assertion, then ends it', () async {
    final db = _FakeDatabase('a', journal);
    final host = _FakeAssertionHost(journal);
    final t = trigger(databases: [db], host: host);

    expect(await t.suspend(), DatabaseSuspendOutcome.released);
    expect(journal, [
      'assertion:begin',
      'sync:suspend',
      'a:release',
      'assertion:end',
    ]);
    expect(db.isEstablished, isFalse);
    expect(t.counters.released, 1);
    expect(t.counters.releasedAfterWait, 0);
    expect(t.counters.assertionUnavailable, 0);
  });

  test('skips entirely while background execution is live', () async {
    final db = _FakeDatabase('a', journal);
    final t = trigger(databases: [db], liveBackgroundExecution: true);

    expect(
      await t.suspend(),
      DatabaseSuspendOutcome.skippedLiveBackgroundExecution,
    );
    expect(journal, isEmpty, reason: 'a call must never lose its database');
    expect(db.isEstablished, isTrue);
    expect(t.counters.skippedLiveBackgroundExecution, 1);
  });

  test(
    'waits for an in-flight transaction to finish before releasing',
    () async {
      // The SDK holds a transaction across sync for seconds. Refusal alone is a
      // silent no-op; the trigger has to keep asking until quiet.
      final db = _FakeDatabase('a', journal, refusals: 3);
      final t = trigger(databases: [db]);

      expect(await t.suspend(), DatabaseSuspendOutcome.released);
      expect(db.releaseAttempts, 4);
      expect(t.counters.released, 1);
      expect(t.counters.releasedAfterWait, 1);
    },
  );

  test(
    'a transaction that outlives the window is counted, not waited on',
    () async {
      // The measured residual: the process suspends holding a lock. Sync was
      // stopped for the attempt, so a resume must restart it - with nothing to
      // re-establish because nothing was released.
      final db = _FakeDatabase('a', journal, refusals: 1 << 20);
      final t = trigger(
        databases: [db],
        quiescenceTimeout: const Duration(milliseconds: 20),
      );

      expect(await t.suspend(), DatabaseSuspendOutcome.partial);
      expect(t.counters.timedOut, 1);
      expect(t.counters.released, 0);
      expect(db.isEstablished, isTrue);
      expect(t.released, isEmpty);

      journal.clear();
      expect(await t.resume(), DatabaseResumeOutcome.nothingReleased);
      expect(journal, ['sync:resume']);
    },
  );

  group('a caller with a real deadline can extend the quiescence wait', () {
    // The wake reserves time for the release and then the trigger spent only
    // its own fixed slice of it, giving up with the deadline unused and the
    // database still open. The reserve exists to be spent.
    test('a later deadline keeps polling past quiescenceTimeout', () async {
      // With a 2 ms poll and 100 refusals, the retry sequence substantially
      // exceeds the trigger's 10 ms window even on a fast test runner.
      final db = _FakeDatabase('a', journal, refusals: 100);
      final t = trigger(
        databases: [db],
        quiescenceTimeout: const Duration(milliseconds: 10),
      );

      final outcome = await t.suspend(
        quiescenceDeadline: DateTime.now().add(const Duration(seconds: 5)),
      );

      expect(outcome, DatabaseSuspendOutcome.released);
      expect(db.releaseAttempts, 101);
      expect(t.counters.timedOut, 0);
      expect(t.counters.releasedAfterWait, 1);
    });

    test('an earlier deadline cannot shorten it', () async {
      // A caller that is already late gains nothing by giving up sooner, and
      // an open database is the failure this class exists to prevent - so a
      // deadline in the past is floored, not obeyed.
      final db = _FakeDatabase('a', journal, refusals: 4);
      final t = trigger(
        databases: [db],
        quiescenceTimeout: const Duration(milliseconds: 60),
      );

      final outcome = await t.suspend(
        quiescenceDeadline: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(
        outcome,
        DatabaseSuspendOutcome.released,
        reason: 'the trigger still gets its own window',
      );
      expect(db.releaseAttempts, 5);
      expect(t.counters.timedOut, 0);
    });

    test('an extended wait still ends, and still counts the failure', () async {
      final db = _FakeDatabase('a', journal, refusals: 1 << 20);
      final t = trigger(
        databases: [db],
        quiescenceTimeout: const Duration(milliseconds: 5),
      );

      final outcome = await t.suspend(
        quiescenceDeadline: DateTime.now().add(
          const Duration(milliseconds: 40),
        ),
      );

      expect(outcome, DatabaseSuspendOutcome.partial);
      expect(t.counters.timedOut, 1);
      expect(db.isEstablished, isTrue);
    });
  });

  test('re-establishes every database before sync restarts', () async {
    final a = _FakeDatabase('a', journal);
    final b = _FakeDatabase('b', journal);
    final t = trigger(databases: [a, b]);

    expect(await t.suspend(), DatabaseSuspendOutcome.released);
    journal.clear();

    expect(await t.resume(), DatabaseResumeOutcome.established);
    expect(journal, ['a:reestablish', 'b:reestablish', 'sync:resume']);
    expect(a.isEstablished, isTrue);
    expect(b.isEstablished, isTrue);
    expect(t.counters.reestablished, 2);
    expect(t.retryPending, isFalse);
  });

  test(
    'a deferred re-establish keeps sync stopped and retries on the next resume',
    () async {
      // Reboot-until-first-unlock: the file is unreadable, by design. Sync
      // restarted here would throw at its first query.
      final db = _FakeDatabase('a', journal, deferrals: 1);
      final t = trigger(databases: [db]);

      expect(await t.suspend(), DatabaseSuspendOutcome.released);
      journal.clear();

      expect(await t.resume(), DatabaseResumeOutcome.deferredRetryOnNextResume);
      expect(journal, ['a:reestablish'], reason: 'sync must not resume');
      expect(t.retryPending, isTrue);
      expect(t.counters.deferred, 1);

      journal.clear();
      expect(await t.resume(), DatabaseResumeOutcome.established);
      expect(journal, ['a:reestablish', 'sync:resume']);
      expect(t.retryPending, isFalse);
    },
  );

  test(
    'whenEstablished is armed at release and completes after sync resumes',
    () async {
      // The wake race, in the order production actually runs it: the presence
      // watcher's onResume write arrives BEFORE the trigger's resume has been
      // scheduled, let alone started. A writer that asks the wrapper whether
      // a re-establish is pending gets "no". It has to ask the trigger, whose
      // gate was armed when the database was released.
      final db = _FakeDatabase('a', journal);
      final t = trigger(databases: [db]);

      var beforeRelease = false;
      unawaited(t.whenEstablished.then((_) => beforeRelease = true));
      await Future<void>.delayed(Duration.zero);
      expect(beforeRelease, isTrue, reason: 'nothing released: no wait');

      expect(await t.suspend(), DatabaseSuspendOutcome.released);
      journal.clear();

      // Writer first, then the trigger's serialised resume.
      final write = t.whenEstablished.then((_) => journal.add('writer:write'));
      final resume = t.resume();
      await write;
      expect(await resume, DatabaseResumeOutcome.established);
      expect(journal, ['a:reestablish', 'sync:resume', 'writer:write']);

      // A later release re-arms it.
      expect(await t.suspend(), DatabaseSuspendOutcome.released);
      var reArmed = true;
      unawaited(t.whenEstablished.then((_) => reArmed = false));
      await Future<void>.delayed(Duration.zero);
      expect(reArmed, isTrue, reason: 'released again: must wait again');
      await t.resume();
    },
  );

  test(
    'whenEstablished stays pending across a deferred re-establish',
    () async {
      final db = _FakeDatabase('a', journal, deferrals: 1);
      final t = trigger(databases: [db]);
      expect(await t.suspend(), DatabaseSuspendOutcome.released);

      var established = false;
      unawaited(t.whenEstablished.then((_) => established = true));

      expect(await t.resume(), DatabaseResumeOutcome.deferredRetryOnNextResume);
      await Future<void>.delayed(Duration.zero);
      expect(established, isFalse, reason: 'the file is still unreadable');

      expect(await t.resume(), DatabaseResumeOutcome.established);
      await Future<void>.delayed(Duration.zero);
      expect(established, isTrue);
    },
  );

  test(
    'whenEstablished fails loudly on a failed re-establish and re-arms',
    () async {
      // A permanently unreadable file must not turn every lifecycle writer
      // into a silent hang. The writer waiting now gets the error; a writer
      // arriving after the failure waits for the retry on the next resume.
      final db = _FakeDatabase('a', journal, failures: 1);
      final t = trigger(databases: [db]);
      expect(await t.suspend(), DatabaseSuspendOutcome.released);

      final waitingBefore = expectLater(
        t.whenEstablished,
        throwsA(isA<StateError>()),
      );
      expect(await t.resume(), DatabaseResumeOutcome.failed);
      await waitingBefore;

      var established = false;
      unawaited(t.whenEstablished.then((_) => established = true));
      await Future<void>.delayed(Duration.zero);
      expect(established, isFalse, reason: 're-armed for the retry');

      expect(await t.resume(), DatabaseResumeOutcome.established);
      await Future<void>.delayed(Duration.zero);
      expect(established, isTrue);
    },
  );

  test('a database closed while released is discarded, and sync restarts for '
      'the rest', () async {
    // Logging out or removing an account closes its wrapper. If that lands
    // while the trigger is holding databases released, the wrapper is out of
    // the registry and holds no executor, so nothing can ever re-establish
    // it. Counting that as a failure keeps `_released` non-empty for the
    // life of the process: `resumeSync()` is never called again, and the
    // accounts that are still live stop syncing.
    final gone = _FakeDatabase('gone', journal);
    final live = _FakeDatabase('live', journal);
    final t = trigger(databases: [gone, live]);

    expect(await t.suspend(), DatabaseSuspendOutcome.released);
    expect(t.released, hasLength(2));
    journal.clear();

    gone.closed = true;

    var established = false;
    unawaited(t.whenEstablished.then((_) => established = true));

    expect(await t.resume(), DatabaseResumeOutcome.established);
    expect(journal, ['gone:reestablish', 'live:reestablish', 'sync:resume']);
    expect(t.released, isEmpty, reason: 'nothing is left pending');
    expect(t.retryPending, isFalse);
    expect(
      t.counters.reestablished,
      1,
      reason: 'the closed one was discarded, not re-established',
    );
    expect(t.counters.reestablishFailed, 0);

    await Future<void>.delayed(Duration.zero);
    expect(established, isTrue, reason: 'writers must not block for ever');

    // And the trigger is usable afterwards rather than stuck in the
    // already-suspended branch.
    expect(await t.suspend(), DatabaseSuspendOutcome.released);
  });

  test('waitForDatabase: true with no trigger, waits while released, false '
      'on a failed re-establish', () async {
    // The presence READ on the phone at 34e26c9e: a timer-driven reader
    // fired before the trigger's resume. Readers ask this instead of the
    // wrapper, which cannot know a re-establish is coming.
    DatabaseReleaseTrigger.instance = null;
    expect(await DatabaseReleaseTrigger.waitForDatabase('t'), isTrue);

    final db = _FakeDatabase('a', journal, failures: 1);
    final t = trigger(databases: [db]);
    DatabaseReleaseTrigger.instance = t;
    addTearDown(() => DatabaseReleaseTrigger.instance = null);
    expect(
      await DatabaseReleaseTrigger.waitForDatabase('t'),
      isTrue,
      reason: 'nothing released yet',
    );

    expect(await t.suspend(), DatabaseSuspendOutcome.released);
    bool? answer;
    unawaited(
      DatabaseReleaseTrigger.waitForDatabase('t').then((v) => answer = v),
    );
    await Future<void>.delayed(Duration.zero);
    expect(answer, isNull, reason: 'released: must wait');

    expect(await t.resume(), DatabaseResumeOutcome.failed);
    await Future<void>.delayed(Duration.zero);
    expect(answer, isFalse, reason: 'failed gate: the caller returns');

    final retry = DatabaseReleaseTrigger.waitForDatabase('t');
    expect(await t.resume(), DatabaseResumeOutcome.established);
    expect(await retry, isTrue);
  });

  test(
    'a throwing suspendSync still lets the next resume restart sync',
    () async {
      final db = _FakeDatabase('a', journal);
      final t = trigger(
        databases: [db],
        suspendSync: () async {
          journal.add('sync:suspend');
          throw StateError('the sync loops refused to stop');
        },
      );

      await expectLater(t.suspend(), throwsA(isA<StateError>()));

      // `suspendSync` is injected and carries no no-throw contract, so it may
      // have stopped some loops before throwing. If the suspension is not
      // recorded, this resume takes the nothingReleased path WITHOUT calling
      // resumeSync, and sync never restarts for the life of the process.
      expect(await t.resume(), DatabaseResumeOutcome.nothingReleased);
      expect(
        journal,
        contains('sync:resume'),
        reason: 'sync was stopped and nothing ever restarted it',
      );
    },
  );

  test('a second suspension while released does nothing', () async {
    final db = _FakeDatabase('a', journal);
    final t = trigger(databases: [db]);

    expect(await t.suspend(), DatabaseSuspendOutcome.released);
    journal.clear();
    expect(await t.suspend(), DatabaseSuspendOutcome.alreadySuspended);
    expect(journal, isEmpty);
    expect(db.releaseAttempts, 1);
  });

  test(
    'an unavailable assertion is counted and the sweep still runs',
    () async {
      final db = _FakeDatabase('a', journal);
      final host = _FakeAssertionHost(journal, grant: false);
      final t = trigger(databases: [db], host: host);

      expect(await t.suspend(), DatabaseSuspendOutcome.released);
      expect(t.counters.assertionUnavailable, 1);
      expect(db.isEstablished, isFalse);
      expect(journal, ['assertion:begin', 'sync:suspend', 'a:release']);
    },
  );

  test('a throwing assertion host does not stop the sweep', () async {
    final db = _FakeDatabase('a', journal);
    final host = _FakeAssertionHost(journal, throwOnBegin: true);
    final t = trigger(databases: [db], host: host);

    expect(await t.suspend(), DatabaseSuspendOutcome.released);
    expect(db.isEstablished, isFalse);
  });

  test('counters saturate rather than wrap', () {
    expect(
      DatabaseReleaseCounters.bump(DatabaseReleaseCounters.saturation),
      DatabaseReleaseCounters.saturation,
    );
    expect(DatabaseReleaseCounters.bump(0), 1);
  });

  test('the aggregate line reports stale transaction uses, including zero', () {
    // Zero is the point. Naming the SDK caller that leaks a transaction zone
    // needs a device capture, and before this the only evidence was a WARNING
    // that exists solely when the leak fires - so "did not reproduce" and "the
    // line was filtered out" read identically in a capture. A number that is
    // printed every sweep can say zero, which is a result.
    final before = ReleasableConnection.staleTransactionUses;
    addTearDown(() => ReleasableConnection.staleTransactionUses = before);

    // Built FIRST, on purpose. The trigger holds one counters object for the
    // whole process, so a snapshot taken at construction would read correctly
    // in a test that builds the object after bumping - and stay stuck at the
    // startup value on a device, which is where the number is needed.
    final counters = DatabaseReleaseCounters();
    expect(counters.toLogString(), contains('stale_transaction_uses=$before'));

    ReleasableConnection.staleTransactionUses = before + 2;
    expect(
      counters.toLogString(),
      contains('stale_transaction_uses=${before + 2}'),
      reason:
          'the line must read the live process-wide counter, not a copy '
          'taken when the counters object was made - the leak is not a sweep '
          'event and can happen with no sweep in sight',
    );
  });
}

class _FakeDatabase implements ReleasableDatabase {
  _FakeDatabase(
    this.databaseName,
    this.journal, {
    this.refusals = 0,
    this.deferrals = 0,
    this.failures = 0,
  });

  @override
  final String databaseName;
  final List<String> journal;

  /// How many release attempts to refuse (a transaction in flight) first.
  int refusals;

  /// How many re-establish attempts report deferred first.
  int deferrals;

  /// How many re-establish attempts fail outright first.
  int failures;

  /// Set once the wrapper has been closed: every later re-establish reports
  /// [ReestablishResult.closed], for good.
  bool closed = false;

  int releaseAttempts = 0;
  bool _established = true;

  @override
  bool get isEstablished => _established;

  @override
  bool get isQuiescent => refusals <= 0;

  @override
  Future<bool> release() async {
    releaseAttempts++;
    if (refusals > 0) {
      refusals--;
      return false;
    }
    journal.add('$databaseName:release');
    _established = false;
    return true;
  }

  @override
  Future<ReestablishResult> reestablish() async {
    journal.add('$databaseName:reestablish');
    if (closed) {
      return ReestablishResult.closed;
    }
    if (deferrals > 0) {
      deferrals--;
      return ReestablishResult.deferred;
    }
    if (failures > 0) {
      failures--;
      return ReestablishResult.failed;
    }
    _established = true;
    return ReestablishResult.established;
  }
}

class _FakeAssertionHost implements BackgroundAssertionHost {
  _FakeAssertionHost(
    this.journal, {
    this.grant = true,
    this.throwOnBegin = false,
  });

  final List<String> journal;
  final bool grant;
  final bool throwOnBegin;

  @override
  Future<String?> begin(String name) async {
    journal.add('assertion:begin');
    if (throwOnBegin) {
      throw StateError('channel unavailable');
    }
    return grant ? 'token' : null;
  }

  @override
  Future<void> end(String token) async {
    journal.add('assertion:end');
  }
}
