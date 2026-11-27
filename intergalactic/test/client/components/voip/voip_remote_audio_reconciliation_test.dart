import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_session_event_gate.dart';
import 'package:intergalactic/client/components/voip/voip_remote_audio_reconciliation.dart';

void main() {
  group('VoipRemoteAudioReconciliationPolicy', () {
    test(
      'requests subscription when remote audio is published but unsubscribed',
      () {
        final result = VoipRemoteAudioReconciliationPolicy.evaluate(
          _state(trackSubscribed: false),
        );

        expect(result.audible, isFalse);
        expect(result.action, VoipRemoteAudioRepairAction.subscribe);
        expect(result.reason, 'remote_audio_unsubscribed');
      },
    );

    test(
      'requests stream or sink rebuild when subscribed audio is detached',
      () {
        final missingStream = VoipRemoteAudioReconciliationPolicy.evaluate(
          _state(streamObjectExists: false),
        );
        final missingSink = VoipRemoteAudioReconciliationPolicy.evaluate(
          _state(audioSinkAttached: false),
        );

        expect(
          missingStream.action,
          VoipRemoteAudioRepairAction.rebuildStreamOrSink,
        );
        expect(
          missingSink.action,
          VoipRemoteAudioRepairAction.rebuildStreamOrSink,
        );
        expect(missingSink.reason, 'remote_audio_sink_missing');
      },
    );

    test('does not repair a local mute that kept its volume (BUG-282)', () {
      // Regression for 2026-08-02T01:38:32.503Z. Deafen and the screenshare
      // visibility policy both set the mute bit and leave the volume alone, so
      // this state is "muted on purpose by an owner the reconciler cannot
      // name" - not drift. Repairing it un-deafened the user roughly ten
      // seconds after they pressed Deafen.
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(locallyMuted: true, localVolume: 0.8),
      );

      expect(result.audible, isFalse);
      expect(result.action, VoipRemoteAudioRepairAction.none);
      expect(result.reason, 'locally_muted');
    });

    test('does not repair a local mute at full volume either', () {
      // The deafen case exactly: volume untouched at the speaker default.
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(locallyMuted: true, localVolume: 1.25),
      );

      expect(result.action, VoipRemoteAudioRepairAction.none);
      expect(result.reason, 'locally_muted');
    });

    test('does not repair intentional local user mute', () {
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(userMuted: true, locallyMuted: true, localVolume: 0),
      );

      expect(result.audible, isFalse);
      expect(result.action, VoipRemoteAudioRepairAction.none);
      expect(result.reason, 'locally_user_muted');
    });

    test('a real fault still outranks a local mute', () {
      // Ordering guard: the mute branch must stay *below* the subscription and
      // sink branches, or muting a participant would mask a genuine failure.
      final unsubscribed = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(trackSubscribed: false, locallyMuted: true, localVolume: 1.25),
      );
      expect(unsubscribed.action, VoipRemoteAudioRepairAction.subscribe);

      final stalled = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(mediaStalled: true, locallyMuted: true, localVolume: 1.25),
      );
      expect(stalled.action, VoipRemoteAudioRepairAction.resubscribe);
    });

    test(
      'reports audible when publication, subscription, sink, and volume align',
      () {
        final result = VoipRemoteAudioReconciliationPolicy.evaluate(_state());

        expect(result.audible, isTrue);
        expect(result.action, VoipRemoteAudioRepairAction.none);
        expect(result.reason, 'audible');
      },
    );

    test('requests resubscribe when a healthy-looking subscription never '
        'delivers media', () {
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(mediaStalled: true),
      );

      expect(result.audible, isFalse);
      expect(result.action, VoipRemoteAudioRepairAction.resubscribe);
      expect(result.reason, VoipRemoteAudioReasons.mediaStalled);
    });

    test('media stall does not override earlier control-plane repairs', () {
      final unsubscribed = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(trackSubscribed: false, mediaStalled: true),
      );
      final sinkMissing = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(audioSinkAttached: false, mediaStalled: true),
      );

      expect(unsubscribed.action, VoipRemoteAudioRepairAction.subscribe);
      expect(
        sinkMissing.action,
        VoipRemoteAudioRepairAction.rebuildStreamOrSink,
      );
    });

    test('does not repair disconnected, missing, or remotely muted audio', () {
      final disconnected = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(participantConnected: false),
      );
      final missingPublication = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(audioPublicationExists: false),
      );
      final remoteMuted = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(publicationMuted: true),
      );

      expect(disconnected.action, VoipRemoteAudioRepairAction.none);
      expect(disconnected.reason, 'participant_disconnected');
      expect(missingPublication.action, VoipRemoteAudioRepairAction.none);
      expect(missingPublication.reason, 'no_remote_audio_publication');
      expect(remoteMuted.action, VoipRemoteAudioRepairAction.none);
      expect(remoteMuted.reason, 'remote_publication_muted');
    });
  });

  group('VoipRemoteAudioFlowMonitor', () {
    final start = DateTime.utc(2026, 7, 6, 12);

    VoipRemoteAudioFlowMonitor monitor() => VoipRemoteAudioFlowMonitor(
      neverReceivedWindow: const Duration(seconds: 12),
      repairCooldown: const Duration(seconds: 30),
      maxRepairs: 3,
    );

    test('does not stall before the observation window elapses', () {
      final flow = monitor();

      expect(
        flow.recordSample(sid: 'a', packetsReceived: 0, now: start),
        isFalse,
      );
      expect(
        flow.recordSample(
          sid: 'a',
          packetsReceived: 0,
          now: start.add(const Duration(seconds: 11)),
        ),
        isFalse,
      );
    });

    test('stalls after the window with zero packets ever received', () {
      final flow = monitor();

      flow.recordSample(sid: 'a', packetsReceived: 0, now: start);
      expect(
        flow.recordSample(
          sid: 'a',
          packetsReceived: 0,
          now: start.add(const Duration(seconds: 13)),
        ),
        isTrue,
      );
    });

    test('never stalls once packets have been received (DTX-safe)', () {
      final flow = monitor();

      flow.recordSample(sid: 'a', packetsReceived: 40, now: start);
      expect(
        flow.recordSample(
          sid: 'a',
          packetsReceived: 40,
          now: start.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });

    test('unavailable stats never count as a stall', () {
      final flow = monitor();

      flow.recordSample(sid: 'a', packetsReceived: null, now: start);
      expect(
        flow.recordSample(
          sid: 'a',
          packetsReceived: null,
          now: start.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('repairs respect the cooldown and the repair cap', () {
      final flow = monitor();
      var now = start;

      flow.recordSample(sid: 'a', packetsReceived: 0, now: now);
      now = now.add(const Duration(seconds: 13));
      expect(flow.recordSample(sid: 'a', packetsReceived: 0, now: now), isTrue);
      flow.recordRepair('a', now);

      // Inside the cooldown: no repeat repair even past a fresh window.
      now = now.add(const Duration(seconds: 15));
      expect(
        flow.recordSample(sid: 'a', packetsReceived: 0, now: now),
        isFalse,
      );

      // Past the cooldown and a full window: repair again, twice more.
      for (var i = 0; i < 2; i++) {
        now = now.add(const Duration(seconds: 31));
        expect(
          flow.recordSample(sid: 'a', packetsReceived: 0, now: now),
          isTrue,
        );
        flow.recordRepair('a', now);
      }

      // Cap reached: no further repairs.
      now = now.add(const Duration(minutes: 5));
      expect(
        flow.recordSample(sid: 'a', packetsReceived: 0, now: now),
        isFalse,
      );
    });

    test('counter reset restarts the observation window', () {
      final flow = monitor();

      flow.recordSample(sid: 'a', packetsReceived: 120, now: start);
      // Receiver replaced: counter back to zero. Not an instant stall.
      final atReset = start.add(const Duration(minutes: 1));
      expect(
        flow.recordSample(sid: 'a', packetsReceived: 0, now: atReset),
        isFalse,
      );
      // Still zero after a fresh full window: stall.
      expect(
        flow.recordSample(
          sid: 'a',
          packetsReceived: 0,
          now: atReset.add(const Duration(seconds: 13)),
        ),
        isTrue,
      );
    });

    test('retainOnly drops tracking for removed publications', () {
      final flow = monitor();

      flow.recordSample(sid: 'a', packetsReceived: 0, now: start);
      flow.retainOnly(const {'b'});
      // Tracking restarted, so the old window no longer applies.
      expect(
        flow.recordSample(
          sid: 'a',
          packetsReceived: 0,
          now: start.add(const Duration(seconds: 13)),
        ),
        isFalse,
      );
    });
  });

  group('VoipRemoteAudioReconciler', () {
    test('routes subscription repairs to the subscribe callback', () async {
      final actions = <String>[];

      final result = await VoipRemoteAudioReconciler.repair(
        const VoipRemoteAudioReconciliation(
          audible: false,
          action: VoipRemoteAudioRepairAction.subscribe,
          reason: 'remote_audio_unsubscribed',
        ),
        subscribe: () => actions.add('subscribe'),
        rebuildStreamOrSink: () => actions.add('rebuild'),
        restoreLocalPlayback: () => actions.add('restore'),
      );

      expect(actions, ['subscribe']);
      expect(result.attempted, isTrue);
      expect(result.repaired, isTrue);
      expect(result.failed, isFalse);
    });

    test('routes sink repairs to the rebuild callback', () async {
      final actions = <String>[];

      final result = await VoipRemoteAudioReconciler.repair(
        const VoipRemoteAudioReconciliation(
          audible: false,
          action: VoipRemoteAudioRepairAction.rebuildStreamOrSink,
          reason: 'remote_audio_sink_missing',
        ),
        subscribe: () => actions.add('subscribe'),
        rebuildStreamOrSink: () => actions.add('rebuild'),
        restoreLocalPlayback: () => actions.add('restore'),
      );

      expect(actions, ['rebuild']);
      expect(result.repaired, isTrue);
    });

    test('routes playback drift repairs to the restore callback', () async {
      final actions = <String>[];

      final result = await VoipRemoteAudioReconciler.repair(
        const VoipRemoteAudioReconciliation(
          audible: false,
          action: VoipRemoteAudioRepairAction.restoreLocalPlayback,
          reason: 'local_playback_mute_drift',
        ),
        subscribe: () => actions.add('subscribe'),
        rebuildStreamOrSink: () => actions.add('rebuild'),
        restoreLocalPlayback: () => actions.add('restore'),
      );

      expect(actions, ['restore']);
      expect(result.repaired, isTrue);
    });

    test('does not run callbacks when no repair is requested', () async {
      final actions = <String>[];

      final result = await VoipRemoteAudioReconciler.repair(
        const VoipRemoteAudioReconciliation(
          audible: true,
          action: VoipRemoteAudioRepairAction.none,
          reason: 'audible',
        ),
        subscribe: () => actions.add('subscribe'),
        rebuildStreamOrSink: () => actions.add('rebuild'),
        restoreLocalPlayback: () => actions.add('restore'),
      );

      expect(actions, isEmpty);
      expect(result.attempted, isFalse);
      expect(result.repaired, isFalse);
      expect(result.failed, isFalse);
    });

    test('reports repair failures without throwing', () async {
      final errors = <Object>[];

      final result = await VoipRemoteAudioReconciler.repair(
        const VoipRemoteAudioReconciliation(
          audible: false,
          action: VoipRemoteAudioRepairAction.subscribe,
          reason: 'remote_audio_unsubscribed',
        ),
        subscribe: () => throw StateError('stale publication'),
        onError: (error, _, __) => errors.add(error),
      );

      expect(result.attempted, isTrue);
      expect(result.repaired, isFalse);
      expect(result.failed, isTrue);
      expect(result.error, isStateError);
      expect(errors.single, isStateError);
    });

    test('skips repairs when the call event gate is already closed', () async {
      final gate = CallSessionEventGate()..dispose();
      final actions = <String>[];

      final result = await VoipRemoteAudioReconciler.repair(
        const VoipRemoteAudioReconciliation(
          audible: false,
          action: VoipRemoteAudioRepairAction.subscribe,
          reason: 'remote_audio_unsubscribed',
        ),
        isActive: () => gate.shouldProcess(
          isEnding: false,
          isEnded: false,
          transientResourcesDisposed: false,
        ),
        subscribe: () => actions.add('subscribe'),
      );

      expect(actions, isEmpty);
      expect(result.attempted, isFalse);
      expect(result.repaired, isFalse);
      expect(result.inactive, isTrue);
      expect(result.failed, isFalse);
    });

    test(
      'discards awaited repairs when teardown closes the event gate',
      () async {
        final gate = CallSessionEventGate();
        final subscribeStarted = Completer<void>();
        final subscribeCanFinish = Completer<void>();
        final actions = <String>[];

        final repair = VoipRemoteAudioReconciler.repair(
          const VoipRemoteAudioReconciliation(
            audible: false,
            action: VoipRemoteAudioRepairAction.subscribe,
            reason: 'remote_audio_unsubscribed',
          ),
          isActive: () => gate.shouldProcess(
            isEnding: false,
            isEnded: false,
            transientResourcesDisposed: false,
          ),
          subscribe: () async {
            actions.add('subscribe');
            subscribeStarted.complete();
            await subscribeCanFinish.future;
          },
        );

        await subscribeStarted.future;
        gate.dispose();
        subscribeCanFinish.complete();

        final result = await repair;

        expect(actions, ['subscribe']);
        expect(result.attempted, isTrue);
        expect(result.repaired, isFalse);
        expect(result.inactive, isTrue);
        expect(result.failed, isFalse);
      },
    );

    test(
      'discards awaited repair failures after teardown closes the gate',
      () async {
        final gate = CallSessionEventGate();
        final subscribeStarted = Completer<void>();
        final subscribeCanFail = Completer<void>();
        final errors = <Object>[];

        final repair = VoipRemoteAudioReconciler.repair(
          const VoipRemoteAudioReconciliation(
            audible: false,
            action: VoipRemoteAudioRepairAction.subscribe,
            reason: 'remote_audio_unsubscribed',
          ),
          isActive: () => gate.shouldProcess(
            isEnding: false,
            isEnded: false,
            transientResourcesDisposed: false,
          ),
          subscribe: () async {
            subscribeStarted.complete();
            await subscribeCanFail.future;
            throw StateError('stale teardown repair');
          },
          onError: (error, _, __) => errors.add(error),
        );

        await subscribeStarted.future;
        gate.dispose();
        subscribeCanFail.complete();

        final result = await repair;

        expect(errors, isEmpty);
        expect(result.attempted, isTrue);
        expect(result.repaired, isFalse);
        expect(result.inactive, isTrue);
        expect(result.failed, isFalse);
        expect(result.error, isNull);
      },
    );
  });
}

VoipRemoteAudioState _state({
  bool participantConnected = true,
  bool audioPublicationExists = true,
  bool publicationMuted = false,
  bool trackSubscribed = true,
  bool streamObjectExists = true,
  bool audioSinkAttached = true,
  double localVolume = 1,
  bool locallyMuted = false,
  bool userMuted = false,
  bool mediaStalled = false,
}) {
  return VoipRemoteAudioState(
    participantConnected: participantConnected,
    audioPublicationExists: audioPublicationExists,
    publicationMuted: publicationMuted,
    trackSubscribed: trackSubscribed,
    streamObjectExists: streamObjectExists,
    audioSinkAttached: audioSinkAttached,
    localVolume: localVolume,
    locallyMuted: locallyMuted,
    userMuted: userMuted,
    mediaStalled: mediaStalled,
  );
}
