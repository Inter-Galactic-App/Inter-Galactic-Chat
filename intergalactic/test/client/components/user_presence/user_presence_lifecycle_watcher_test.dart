import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_lifecycle_watcher.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';

/// The B5 device proof found the presence watcher's inactivity timer writing
/// into a released database: armed on `inactive`, it fired either while the
/// app was backgrounded-and-running or in the first milliseconds of the wake.
/// `paused` is where the database is released, so it is where the timer must
/// die. Desktop never enters `paused`, so its minimise path is untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final watcher = UserPresenceLifecycleWatcher();

  setUp(() {
    watcher.init();
    watcher.inactivityTimer?.cancel();
    watcher.inactivityTimer = null;
  });

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }

  testWidgets('pausing cancels the inactivity timer armed on inactive', (
    tester,
  ) async {
    // AppLifecycleListener reports transitions, not states: onInactive fires
    // on resumed -> inactive, and the test binding does not start resumed.
    await lifecycle(tester, AppLifecycleState.resumed);
    await lifecycle(tester, AppLifecycleState.inactive);
    expect(
      watcher.inactivityTimer,
      isNotNull,
      reason: 'inactive arms the 15 s unavailable timer',
    );

    await lifecycle(tester, AppLifecycleState.hidden);
    expect(
      watcher.inactivityTimer,
      isNotNull,
      reason: 'hidden is the desktop minimise path and must keep the timer',
    );

    await lifecycle(tester, AppLifecycleState.paused);
    expect(
      watcher.inactivityTimer,
      isNull,
      reason:
          'the database is released on paused; nothing may write until '
          'resumed',
    );

    // The wake path the framework allows: paused -> hidden -> inactive ->
    // resumed. `inactive` re-arms the timer and `resumed` cancels it again,
    // which is the existing onResume behaviour.
    await lifecycle(tester, AppLifecycleState.hidden);
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.resumed);
    expect(watcher.inactivityTimer, isNull);
  });

  testWidgets(
    'a presence write waits for the release trigger to re-establish',
    (tester) async {
      // The wake race. This watcher's onResume runs BEFORE the trigger's
      // observer, so at the moment of the write the wrapper has no re-establish
      // pending to wait on. The write must observe the trigger's intent - the
      // gate armed at release - not the wrapper's momentary state.
      final db = _ReleasedDatabase();
      final trigger = DatabaseReleaseTrigger(
        databases: () => [db],
        suspendSync: () async {},
        resumeSync: () {},
        hasLiveBackgroundExecution: () => false,
        pollInterval: const Duration(milliseconds: 1),
      );
      trigger.attach();
      addTearDown(trigger.detach);
      await tester.runAsync(() async {
        expect(await trigger.suspend(), DatabaseSuspendOutcome.released);

        var written = false;
        final write = watcher
            .setState(UserPresenceStatus.online)
            .then((_) => written = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(written, isFalse, reason: 'released: the write must wait');

        expect(await trigger.resume(), DatabaseResumeOutcome.established);
        await write.timeout(const Duration(seconds: 5));
        expect(written, isTrue);
      });
    },
  );

  testWidgets(
    'a presence write is dropped, not hung, when re-establish fails',
    (tester) async {
      final db = _ReleasedDatabase(failures: 1);
      final trigger = DatabaseReleaseTrigger(
        databases: () => [db],
        suspendSync: () async {},
        resumeSync: () {},
        hasLiveBackgroundExecution: () => false,
        pollInterval: const Duration(milliseconds: 1),
      );
      trigger.attach();
      addTearDown(trigger.detach);
      await tester.runAsync(() async {
        expect(await trigger.suspend(), DatabaseSuspendOutcome.released);
        final write = watcher.setState(UserPresenceStatus.online);
        expect(await trigger.resume(), DatabaseResumeOutcome.failed);
        // Completes without throwing: the watcher logs and drops the write.
        await write.timeout(const Duration(seconds: 5));
      });
    },
  );
  // DEFENCE IN DEPTH, not a live defect. The trigger completes the gate only
  // with a StateError (database_release_trigger.dart:461) and
  // DatabaseReleaseTrigger.waitForDatabase catches that same type, so no other
  // error type can reach this handler today. But every caller reaches setState
  // through unawaited(), so a gate that ever carried a different error would
  // surface as an unhandled asynchronous error rather than a dropped update.
  // This substitutes that future error type at the gate.
  testWidgets('a non-StateError gate failure is dropped, not thrown', (
    tester,
  ) async {
    DatabaseReleaseTrigger.instance = _ErroringGateTrigger(
      ArgumentError('not a StateError'),
    );
    addTearDown(() => DatabaseReleaseTrigger.instance = null);

    await tester.runAsync(() async {
      // Completing at all is the assertion: the error must not escape.
      await watcher
          .setState(UserPresenceStatus.online)
          .timeout(const Duration(seconds: 5));
    });
  });
}

/// A trigger whose gate fails with an error type the real one does not produce.
/// Only [whenEstablished] is exercised.
class _ErroringGateTrigger extends DatabaseReleaseTrigger {
  _ErroringGateTrigger(this.error)
    : super(
        databases: () => const <ReleasableDatabase>[],
        suspendSync: () async {},
        resumeSync: () {},
        hasLiveBackgroundExecution: () => false,
      );

  final Object error;

  @override
  Future<void> get whenEstablished => Future<void>.error(error);
}

class _ReleasedDatabase implements ReleasableDatabase {
  _ReleasedDatabase({this.failures = 0});
  int failures;
  @override
  String get databaseName => 'fake';
  bool _established = true;
  @override
  bool get isEstablished => _established;
  @override
  bool get isQuiescent => true;
  @override
  Future<bool> release() async {
    _established = false;
    return true;
  }

  @override
  Future<ReestablishResult> reestablish() async {
    if (failures > 0) {
      failures--;
      return ReestablishResult.failed;
    }
    _established = true;
    return ReestablishResult.established;
  }
}
