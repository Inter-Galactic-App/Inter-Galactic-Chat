// A repair that runs, does not throw, and changes nothing must not be recorded
// as a repair.
//
// WHAT WOULD MAKE THESE WRONG, stated first. The field failure this comes from
// was NOT a step that failed. It was a step that succeeded at doing nothing:
// `rebuildStreamOrSink` for a missing audio sink reaches an early return that
// only notifies listeners, cannot attach a track the SDK has not delivered, and
// cannot throw. Every log line said the repair had been applied while the
// participant stayed inaudible until a rejoin. So a test that only checked
// `result.ineffective` would be half the assertion: `repaired` must go FALSE at
// the same time, because `repaired` is what the caller counts and logs.
//
// The reporter is only consulted on the success path. A step that threw is a
// failure and a step that never ran was never attempted; neither of those is
// this, and both are pinned below so the three states cannot collapse into one.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_remote_audio_reconciliation.dart';

const _reconciliation = VoipRemoteAudioReconciliation(
  audible: false,
  action: VoipRemoteAudioRepairAction.rebuildStreamOrSink,
  reason: 'remote_audio_sink_missing',
);

void main() {
  test('a step that reports doing nothing is not a repair', () async {
    var ran = false;

    final result = await VoipRemoteAudioReconciler.repair(
      _reconciliation,
      rebuildStreamOrSink: () {
        ran = true;
      },
      stepWasIneffective: () => true,
    );

    expect(ran, isTrue, reason: 'the step must still have been run');
    expect(result.attempted, isTrue);
    expect(
      result.repaired,
      isFalse,
      reason:
          'this is the assertion the field failure needed: the caller counts '
          'and logs `repaired`, so a no-op reported as repaired is invisible',
    );
    expect(result.ineffective, isTrue);
    expect(
      result.failed,
      isFalse,
      reason:
          'nothing went wrong; the SDK simply has not delivered a track, and '
          'surfacing that as an error would put it in front of the user',
    );
  });

  test('a step that reports it worked is still a repair', () async {
    final result = await VoipRemoteAudioReconciler.repair(
      _reconciliation,
      rebuildStreamOrSink: () {},
      stepWasIneffective: () => false,
    );

    expect(result.repaired, isTrue);
    expect(result.ineffective, isFalse);
  });

  test('no reporter keeps the old meaning', () async {
    // The other four steps pass no reporter. Running without throwing must go
    // on counting as a repair for them, or this change quietly reclassifies
    // every repair in the system.
    final result = await VoipRemoteAudioReconciler.repair(
      _reconciliation,
      rebuildStreamOrSink: () {},
    );

    expect(result.repaired, isTrue);
    expect(result.ineffective, isFalse);
  });

  test('a throwing step is a failure, not an ineffective one', () async {
    Object? reported;

    final result = await VoipRemoteAudioReconciler.repair(
      _reconciliation,
      rebuildStreamOrSink: () => throw StateError('boom'),
      // Deliberately true: a step that threw must never be laundered into the
      // softer classification just because the reporter says so.
      stepWasIneffective: () => true,
      onError: (error, stackTrace, reconciliation) => reported = error,
    );

    expect(result.failed, isTrue);
    expect(result.repaired, isFalse);
    expect(
      result.ineffective,
      isFalse,
      reason: 'a throw is a failure and must stay reportable as one',
    );
    expect(reported, isA<StateError>());
  });

  test('an unwired action never consults the reporter', () async {
    var asked = false;

    final result = await VoipRemoteAudioReconciler.repair(
      _reconciliation,
      // rebuildStreamOrSink deliberately not supplied.
      stepWasIneffective: () {
        asked = true;
        return true;
      },
    );

    expect(result.attempted, isFalse);
    expect(result.repaired, isFalse);
    expect(
      result.ineffective,
      isFalse,
      reason: 'never attempted is a third state, not a quiet no-op',
    );
    expect(asked, isFalse);
  });

  group('the attach monitor says which gate held the escalation back', () {
    test('it reports all three gates for an observed publication', () {
      final monitor = VoipRemoteMediaAttachMonitor();
      final start = DateTime(2026, 9, 7, 3, 30);

      monitor.recordObservation(
        sid: 'SID',
        wanted: true,
        sinkAttached: false,
        now: start,
      );
      monitor.recordRepair('SID', start.add(const Duration(seconds: 2)));

      final described = monitor.describeGateState(
        'SID',
        start.add(const Duration(seconds: 5)),
      );

      // All three are asserted together on purpose. Reporting one of them is
      // what the old log did, and one value cannot say which gate held.
      expect(described, contains('wanted_for=3s'));
      expect(described, contains('repairs=1/3'));
      expect(described, contains('since_repair=3s'));
      expect(described, contains('window_restart=repair'));
    });

    test('it says WHICH of the two restarted the window', () {
      // The 2026-09-07 field case arrived under a publication that never
      // changed, so `!wanted` and `sink_attached` are different stories about
      // it and `wanted_for` alone cannot tell them apart. Both directions are
      // asserted: a test pinning only one would pass against a monitor that
      // hardcoded that string.
      final monitor = VoipRemoteMediaAttachMonitor();
      final at = DateTime(2026, 9, 7, 3, 30);

      monitor.recordObservation(
        sid: 'SID',
        wanted: false,
        sinkAttached: false,
        now: at,
      );
      expect(
        monitor.describeGateState('SID', at),
        contains('window_restart=not_wanted'),
      );

      monitor.recordObservation(
        sid: 'SID',
        wanted: true,
        sinkAttached: true,
        now: at,
      );
      expect(
        monitor.describeGateState('SID', at),
        contains('window_restart=sink_attached'),
      );
    });

    test('an untouched window reports none, not a stale reason', () {
      final monitor = VoipRemoteMediaAttachMonitor();
      final at = DateTime(2026, 9, 7, 3, 30);

      monitor.recordObservation(
        sid: 'SID',
        wanted: true,
        sinkAttached: false,
        now: at,
      );

      expect(
        monitor.describeGateState('SID', at),
        contains('window_restart=none'),
        reason:
            'nothing has restarted it, and a blank would read as a missing '
            'field rather than as a window that has simply been running',
      );
    });

    test('an unobserved publication reports nothing rather than zeroes', () {
      final monitor = VoipRemoteMediaAttachMonitor();

      expect(
        monitor.describeGateState('NEVER-SEEN', DateTime(2026, 9, 7)),
        isNull,
        reason:
            'zeroes would read as a publication observed just now, which is '
            'the opposite of never observed',
      );
    });
  });
}
