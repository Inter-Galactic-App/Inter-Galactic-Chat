import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/ios/ios_remote_wake.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';

void main() {
  group('RemoteWakeCatchUp', () {
    late List<String> journal;
    setUp(() => journal = []);

    RemoteWakeCatchUp catchUp({
      bool foreground = false,
      bool Function()? isForeground,
      DatabaseResumeOutcome resumed = DatabaseResumeOutcome.established,
      Future<void> Function()? sync,
      Duration budget = const Duration(seconds: 5),
    }) => RemoteWakeCatchUp(
      isForeground: isForeground ?? () => foreground,
      resume: () async {
        journal.add('resume');
        return resumed;
      },
      syncAll:
          sync ??
          () async {
            journal.add('sync');
          },
      abortSync: () async {
        journal.add('abort');
      },
      suspend: () async {
        journal.add('suspend');
        return DatabaseSuspendOutcome.released;
      },
      budget: budget,
    );

    test('re-establishes, syncs, then releases, in that order', () async {
      expect(await catchUp().run(), RemoteWakeOutcome.caughtUp);
      expect(journal, ['resume', 'sync', 'suspend']);
    });

    test('does nothing in the foreground, where sync is live', () async {
      expect(
        await catchUp(foreground: true).run(),
        RemoteWakeOutcome.foreground,
      );
      expect(journal, isEmpty);
    });

    test(
      'a deferred re-establish syncs nothing and releases nothing',
      () async {
        expect(
          await catchUp(
            resumed: DatabaseResumeOutcome.deferredRetryOnNextResume,
          ).run(),
          RemoteWakeOutcome.deferred,
        );
        expect(journal, ['resume']);
      },
    );

    // `Future.timeout` completes the future it returns; it does NOT stop the
    // work inside syncAll. Releasing while that sync is still running is the
    // 0xdead10cc kill this class exists to prevent, so the abort has to land
    // BEFORE the suspend - which is what the journal order below pins.
    test('a sync past the budget is aborted, then releases', () async {
      final outcome = await catchUp(
        sync: () => Completer<void>().future,
        budget: const Duration(milliseconds: 20),
      ).run();
      expect(outcome, RemoteWakeOutcome.timedOut);
      expect(journal, ['resume', 'abort', 'suspend']);
    });

    test('an abort that throws does not stop the release', () async {
      final outcome = await RemoteWakeCatchUp(
        isForeground: () => false,
        resume: () async {
          journal.add('resume');
          return DatabaseResumeOutcome.established;
        },
        syncAll: () => Completer<void>().future,
        abortSync: () async {
          journal.add('abort');
          throw StateError('abort failed');
        },
        suspend: () async {
          journal.add('suspend');
          return DatabaseSuspendOutcome.released;
        },
        budget: const Duration(milliseconds: 20),
      ).run();

      expect(
        outcome,
        RemoteWakeOutcome.timedOut,
        reason: 'a failed abort must not become the wake outcome',
      );
      expect(journal, ['resume', 'abort', 'suspend']);
    });

    test('a sync that throws still releases', () async {
      final outcome = catchUp(
        sync: () async {
          journal.add('sync');
          throw StateError('sync failed');
        },
      ).run();
      await expectLater(outcome, throwsA(isA<StateError>()));
      expect(journal, ['resume', 'sync', 'suspend']);
    });

    test(
      'does not release if the app reached the foreground meanwhile',
      () async {
        var foreground = false;
        final outcome = await catchUp(
          isForeground: () => foreground,
          sync: () async {
            journal.add('sync');
            foreground = true;
          },
        ).run();
        expect(outcome, RemoteWakeOutcome.caughtUp);
        expect(journal, ['resume', 'sync']);
      },
    );
  });

  // The sync budget used to be a flat 15 s that started AFTER app
  // initialisation, so a cold background launch could spend most of native's
  // 25 s deadline in initNecessary() and then begin a fresh 15 s sync. Native
  // completes the fetch at the deadline and drops the background assertion,
  // which would leave the catch-up still holding the database with nothing
  // keeping the process alive - the 0xdead10cc kill B5 exists to prevent.
  group('the budget counts the time native spent before Dart existed', () {
    test('accepts only complete route metadata from native', () {
      expect(
        IosRemoteWakeRoute.fromPlatformPayload({
          'client_id': 'client',
          'room_id': '!room:example.org',
          'event_id': r'$event',
        }),
        isNotNull,
      );
      expect(
        IosRemoteWakeRoute.fromPlatformPayload({
          'client_id': 'client',
          'room_id': '!room:example.org',
        }),
        isNull,
      );
      expect(IosRemoteWakeRoute.fromPlatformPayload('route'), isNull);
    });

    test('a cold launch charges native elapsed against the same deadline', () {
      // Native received the push, then the Flutter engine booted. Dart's own
      // stopwatch cannot see that interval, so without it the budget would
      // over-estimate what is left and the release could land after native
      // had dropped the assertion.
      final nativeElapsed = IosRemoteWake.nativeElapsedFrom({
        'wake_id': 'w',
        'native_elapsed_ms': 12000,
      });
      expect(nativeElapsed, const Duration(seconds: 12));

      const dartElapsed = Duration(seconds: 2);
      expect(
        IosRemoteWake.syncBudgetAfter(nativeElapsed + dartElapsed),
        IosRemoteWake.nativeDeadline -
            const Duration(seconds: 14) -
            IosRemoteWake.releaseReserve,
      );
      // The same launch, measured the old way, would have claimed more.
      expect(
        IosRemoteWake.syncBudgetAfter(dartElapsed),
        greaterThan(IosRemoteWake.syncBudgetAfter(nativeElapsed + dartElapsed)),
      );
    });

    test('an elapsed value past the deadline leaves no sync budget', () {
      final nativeElapsed = IosRemoteWake.nativeElapsedFrom({
        'native_elapsed_ms': 99000,
      });
      expect(nativeElapsed, IosRemoteWake.nativeDeadline);
      expect(IosRemoteWake.syncBudgetAfter(nativeElapsed), Duration.zero);
    });

    test('an unusable value falls back to zero rather than a guess', () {
      expect(IosRemoteWake.nativeElapsedFrom(null), Duration.zero);
      expect(IosRemoteWake.nativeElapsedFrom('not a map'), Duration.zero);
      expect(IosRemoteWake.nativeElapsedFrom({'wake_id': 'w'}), Duration.zero);
      expect(
        IosRemoteWake.nativeElapsedFrom({'native_elapsed_ms': -5}),
        Duration.zero,
      );
      expect(
        IosRemoteWake.nativeElapsedFrom({'native_elapsed_ms': 'soon'}),
        Duration.zero,
      );
    });

    test(
      'a non-integer number is accepted, since the channel may widen it',
      () {
        expect(
          IosRemoteWake.nativeElapsedFrom({'native_elapsed_ms': 1500.0}),
          const Duration(milliseconds: 1500),
        );
      },
    );

    test('a mid-handling query tells "nothing to say" apart from zero', () {
      // The wake payload and the query asked at handling time read the same
      // clock but need opposite fallbacks. A payload with no number means the
      // old behaviour, zero. A query with no number means native no longer
      // holds the wake, and the caller must keep what the payload said - so
      // it has to come back as null, not as a Duration.zero that would look
      // like a genuine "no time has passed".
      expect(IosRemoteWake.clampNativeElapsed(null), isNull);
      expect(IosRemoteWake.clampNativeElapsed('soon'), isNull);
      expect(IosRemoteWake.clampNativeElapsed(0), isNull);
      expect(IosRemoteWake.clampNativeElapsed(-5), isNull);
      expect(
        IosRemoteWake.clampNativeElapsed(3200),
        const Duration(milliseconds: 3200),
      );
      expect(
        IosRemoteWake.clampNativeElapsed(99000),
        IosRemoteWake.nativeDeadline,
        reason: 'a query past the deadline must still leave zero budget',
      );
    });

    test('the larger of the two readings is the one that binds', () {
      // What the device showed on 2026-09-08: every wake, cold launch
      // included, took the buffered-channel path, so the payload was stamped
      // at send time and read ~0. The query answers from the same monotonic
      // start, after the engine boot, and is therefore the honest number.
      final atSend = IosRemoteWake.nativeElapsedFrom({'native_elapsed_ms': 1});
      final atHandling = IosRemoteWake.clampNativeElapsed(3400)!;
      expect(atHandling, greaterThan(atSend));
      expect(
        IosRemoteWake.syncBudgetAfter(atHandling),
        lessThan(IosRemoteWake.syncBudgetAfter(atSend)),
        reason:
            'the send-time stamp is what produced the flat 18999 ms budget on '
            'every wake, warm and cold alike',
      );
    });
  });

  // 2026-09-09 on device: the sync overran, the trigger's own fixed 4 s wait
  // expired with the sync's leftovers still holding a transaction, and the
  // account database was left OPEN - `released=0 of=1` - with 1.8 s of the
  // deadline never used. Unused time beside an open database is waste, not a
  // margin.
  // 2026-09-09 on device: the sync overran, the trigger's own fixed 4 s wait
  // expired with the sync's leftovers still holding a transaction, and the
  // account database was left OPEN - `released=0 of=1` - with 1.8 s of the
  // deadline never used. Unused time beside an open database is waste, not a
  // margin.
  group('the release gets the reserve it was promised', () {
    // REVIEW, 2026-09-09: the first version of this guarantee was written in
    // terms of the sync budget, which is the same quantity as "time left"
    // only until syncBudgetAfter clamps at 19 s. Past that the window stopped
    // shrinking and ran to 27 s at spent=22 - past the deadline it claimed to
    // fit inside - and the test asserting the fit picked spent=4, deep in the
    // safe region, so it read as universal while proving one comfortable
    // point. Hence the sweep across the boundary rather than a single value.
    // The instant native stops listening: it completes the fetch on its
    // deadline and drops the assertion, and the reply has to be in before it.
    final cutoff =
        IosRemoteWake.nativeDeadline - IosRemoteWake.completionReserve;

    for (final seconds in [0, 4, 10, 18, 19, 20, 22, 30, 60]) {
      test('at $seconds s spent, the window grants no time past the '
          'cutoff', () {
        final spent = Duration(seconds: seconds);
        final window = IosRemoteWake.releaseWindowAfter(spent);
        expect(
          spent + window,
          lessThanOrEqualTo(spent > cutoff ? spent : cutoff),
          reason:
              'the window may run to the cutoff and no further; a wake that '
              'is already past it is late whatever happens, and the window '
              'must not make it later',
        );
      });
    }

    test('while there is time left, the window is exactly what remains', () {
      // Not just bounded by the cutoff - equal to it. Leaving any of it unspent
      // is the original defect.
      for (final seconds in [0, 4, 10, 18, 19]) {
        final spent = Duration(seconds: seconds);
        expect(
          spent + IosRemoteWake.releaseWindowAfter(spent),
          cutoff,
          reason: 'at $seconds s spent',
        );
      }
    });

    test('an unclamped budget still yields the whole reserve', () {
      // The behaviour in the safe region is unchanged by stating the window in
      // terms of `spent`: it is still the reserve, less the completion.
      const spent = Duration(seconds: 4);
      final budget = IosRemoteWake.syncBudgetAfter(spent);
      expect(
        IosRemoteWake.releaseWindowAfter(spent),
        budget + IosRemoteWake.releaseReserve - IosRemoteWake.completionReserve,
      );
    });

    test('past the deadline the window is zero, and that is not a give-up', () {
      // The floor belongs to the trigger, which refuses to shorten below its
      // own quiescenceTimeout - see 'an earlier deadline cannot shorten it' in
      // database_release_trigger_test.dart. A second floor here could only
      // disagree with that one, and the old one did: it promised five seconds
      // that the deadline no longer contained.
      expect(
        IosRemoteWake.releaseWindowAfter(const Duration(seconds: 30)),
        Duration.zero,
      );
    });
  });

  group('the sync budget is what is left of the wake, not a fixed 15 s', () {
    test('a fast launch leaves nearly the whole deadline', () {
      final budget = IosRemoteWake.syncBudgetAfter(
        const Duration(milliseconds: 500),
      );
      expect(
        budget,
        IosRemoteWake.nativeDeadline -
            const Duration(milliseconds: 500) -
            IosRemoteWake.releaseReserve,
      );
    });

    test('the reserve is always held back for the release itself', () {
      final budget = IosRemoteWake.syncBudgetAfter(Duration.zero);
      expect(
        budget + IosRemoteWake.releaseReserve,
        IosRemoteWake.nativeDeadline,
        reason:
            'the release waits on quiescence, so it cannot be given zero time',
      );
    });

    test('a launch that overran the deadline yields zero, never negative', () {
      expect(
        IosRemoteWake.syncBudgetAfter(const Duration(seconds: 40)),
        Duration.zero,
        reason:
            'a negative budget would make Future.timeout throw immediately in '
            'a way the caller cannot distinguish from a failed sync',
      );
    });

    test('a zero budget starts no sync at all, and still releases', () async {
      final journal = <String>[];
      var syncStarted = false;
      final outcome = await RemoteWakeCatchUp(
        isForeground: () => false,
        resume: () async {
          journal.add('resume');
          return DatabaseResumeOutcome.established;
        },
        syncAll: () {
          syncStarted = true;
          return Completer<void>().future;
        },
        abortSync: () async {
          journal.add('abort');
        },
        suspend: () async {
          journal.add('suspend');
          return DatabaseSuspendOutcome.released;
        },
        budget: Duration.zero,
      ).run();

      expect(outcome, RemoteWakeOutcome.timedOut);
      expect(journal, ['resume', 'suspend']);
      expect(
        syncStarted,
        isFalse,
        reason:
            'timeout(Duration.zero) fires on the next microtask, so a sync '
            'started here would still be running under the release below - '
            'the case a slow cold launch actually produces',
      );
    });
  });
}
