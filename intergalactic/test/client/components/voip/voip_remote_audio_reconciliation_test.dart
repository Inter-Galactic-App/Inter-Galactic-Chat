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

    test('restores local playback when mute drift blocks audible audio', () {
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(locallyMuted: true, localVolume: 0.8),
      );

      expect(result.audible, isFalse);
      expect(result.action, VoipRemoteAudioRepairAction.restoreLocalPlayback);
      expect(result.reason, 'local_playback_mute_drift');
    });

    test('does not repair intentional local user mute', () {
      final result = VoipRemoteAudioReconciliationPolicy.evaluate(
        _state(userMuted: true, locallyMuted: true, localVolume: 0),
      );

      expect(result.audible, isFalse);
      expect(result.action, VoipRemoteAudioRepairAction.none);
      expect(result.reason, 'locally_user_muted');
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
  );
}
