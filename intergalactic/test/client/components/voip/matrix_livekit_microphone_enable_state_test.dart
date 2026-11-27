import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_microphone_sender_gate.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'fakes/voip_fakes.dart';

void main() {
  group('stalled microphone publication recovery', () {
    FakeLocalTrackPublication<lk.LocalAudioTrack> publication(String sid) =>
        FakeLocalTrackPublication<lk.LocalAudioTrack>(
          sid: sid,
          kind: lk.TrackType.AUDIO,
        );

    test(
      'unpublishes old capture before publishing a fresh microphone',
      () async {
        final participant = FakeLocalParticipant(identity: 'local');
        participant.addPublication(publication('old'));
        var published = false;

        final recovered = await recreateStalledMicrophonePublication(
          participant: participant,
          stalledPublicationSid: 'old',
          mayPublish: () => true,
          publishFresh: () async {
            expect(participant.removePublishedTrackCalls, ['old']);
            expect(
              participant.getTrackPublicationBySource(
                lk.TrackSource.microphone,
              ),
              isNull,
            );
            published = true;
            final replacement = publication('new');
            participant.addPublication(replacement);
            return replacement;
          },
        );

        expect(recovered, isTrue);
        expect(published, isTrue);
        expect(participant.removePublishedTrackCalls, ['old']);
        expect(
          participant
              .getTrackPublicationBySource(lk.TrackSource.microphone)
              ?.sid,
          'new',
        );
      },
    );

    test(
      'does not republish after mute or teardown invalidates recovery',
      () async {
        final participant = FakeLocalParticipant(identity: 'local');
        participant.addPublication(publication('old'));
        var checks = 0;

        final recovered = await recreateStalledMicrophonePublication(
          participant: participant,
          stalledPublicationSid: 'old',
          mayPublish: () => ++checks == 1,
          publishFresh: () => throw StateError('stale capture was republished'),
        );

        expect(recovered, isFalse);
        expect(participant.removePublishedTrackCalls, ['old']);
      },
    );

    test('removes a replacement published after mute or teardown', () async {
      final participant = FakeLocalParticipant(identity: 'local');
      participant.addPublication(publication('old'));
      final publishing = Completer<lk.LocalTrackPublication?>();
      var active = true;

      final recovery = recreateStalledMicrophonePublication(
        participant: participant,
        stalledPublicationSid: 'old',
        mayPublish: () => active,
        publishFresh: () => publishing.future,
      );
      await Future<void>.delayed(Duration.zero);
      final replacement = publication('new');
      participant.addPublication(replacement);
      active = false;
      publishing.complete(replacement);

      expect(await recovery, isFalse);
      expect(participant.removePublishedTrackCalls, ['old', 'new']);
      expect(
        participant.getTrackPublicationBySource(lk.TrackSource.microphone),
        isNull,
      );
    });

    test('does not publish when old track cannot be removed', () async {
      final participant = FakeLocalParticipant(identity: 'local')
        ..addPublication(publication('old'))
        ..removePublishedTrackError = StateError('unpublish failed');

      await expectLater(
        recreateStalledMicrophonePublication(
          participant: participant,
          stalledPublicationSid: 'old',
          mayPublish: () => true,
          publishFresh: () => throw StateError('unexpected publish'),
        ),
        throwsStateError,
      );
      expect(participant.removePublishedTrackCalls, ['old']);
    });

    test('restores after a null replacement leaves no microphone', () async {
      final participant = FakeLocalParticipant(identity: 'local');
      participant.addPublication(publication('old'));
      var restores = 0;

      final recovered = await recreateStalledMicrophonePublication(
        participant: participant,
        stalledPublicationSid: 'old',
        mayPublish: () => true,
        publishFresh: () async => null,
        onRemovedWithoutReplacement: () async {
          restores++;
        },
      );

      expect(recovered, isFalse);
      expect(restores, 1);
      expect(participant.removePublishedTrackCalls, ['old']);
    });

    test('restores after replacement publication throws', () async {
      final participant = FakeLocalParticipant(identity: 'local');
      participant.addPublication(publication('old'));
      var restores = 0;

      await expectLater(
        recreateStalledMicrophonePublication(
          participant: participant,
          stalledPublicationSid: 'old',
          mayPublish: () => true,
          publishFresh: () => throw StateError('capture failed'),
          onRemovedWithoutReplacement: () async {
            restores++;
          },
        ),
        throwsStateError,
      );

      expect(restores, 1);
      expect(participant.removePublishedTrackCalls, ['old']);
    });
  });

  group('MatrixLivekitInitialMicrophoneEnableState', () {
    test(
      'keeps current generation enabled while the call wants microphone',
      () {
        final state = MatrixLivekitInitialMicrophoneEnableState();
        final generation = state.generation;

        expect(state.shouldKeepLateCompletionEnabled, isTrue);
        expect(state.shouldKeepEnabledForGeneration(generation), isTrue);
      },
    );

    test('invalidates pending capture refresh when mute intent changes', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      final refreshGeneration = state.generation;

      state.markDesiredMicrophoneMuted(stopOnMute: true);

      expect(state.desiredMicrophoneEnabled, isFalse);
      expect(state.shouldKeepLateCompletionEnabled, isFalse);
      expect(state.shouldKeepEnabledForGeneration(refreshGeneration), isFalse);

      state.markDesiredMicrophoneEnabled(true);

      expect(state.shouldKeepEnabledForGeneration(refreshGeneration), isFalse);
      expect(state.shouldKeepEnabledForGeneration(state.generation), isTrue);
    });

    test('keeps push-to-talk release ahead of stale profile refreshes', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      final refreshGenerationWhilePressed = state.generation;

      // Push to Talk release mutes the session while a capture-profile refresh
      // may still be between its disable and re-enable awaits.
      state.markDesiredMicrophoneMuted(stopOnMute: false);

      expect(
        state.shouldKeepEnabledForGeneration(refreshGenerationWhilePressed),
        isFalse,
      );

      // A later Push to Talk press should allow current work, not revive the
      // refresh that started before the release.
      state.markDesiredMicrophoneEnabled(true);

      expect(
        state.shouldKeepEnabledForGeneration(refreshGenerationWhilePressed),
        isFalse,
      );
      expect(state.shouldKeepEnabledForGeneration(state.generation), isTrue);
    });

    test(
      're-enables after an awaited removal while call intent stays enabled',
      () async {
        final state = MatrixLivekitInitialMicrophoneEnableState();
        final removal = Completer<void>();
        final generation = state.generation;
        final shouldReenable = () async {
          await removal.future;
          return state.shouldReenableAfterCaptureRefreshRemoval(generation);
        }();

        removal.complete();
        expect(await shouldReenable, isTrue);
      },
    );

    test('reconciles recreated publications to manual mute intent', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();

      state.markDesiredMicrophoneMuted(stopOnMute: true);

      expect(state.desiredMicrophoneEnabled, isFalse);
      expect(state.desiredMuteStopOnMute, isTrue);
      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isTrue,
      );
      expect(
        state.shouldReconcileMutedPublication(publicationMuted: true),
        isFalse,
      );

      state.markDesiredMicrophoneEnabled(true);

      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isFalse,
      );
    });

    test('reconciles recreated publications to push-to-talk mute intent', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();

      state.markDesiredMicrophoneMuted(stopOnMute: false);

      expect(state.desiredMicrophoneEnabled, isFalse);
      expect(state.desiredMuteStopOnMute, isFalse);
      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isTrue,
      );
    });

    test('invalidates pending microphone work when the call ends', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      final generation = state.generation;

      state.markCallInactive();

      expect(state.isCallActive, isFalse);
      expect(state.shouldKeepLateCompletionEnabled, isFalse);
      expect(state.shouldKeepEnabledForGeneration(generation), isFalse);
    });
  });

  group('initial enable settled signal (BUG-320)', () {
    // The session reconciles the join-time publication's sender only AFTER
    // the backend's enable has settled; racing it would inspect a
    // publication still being built. Every settle path marks the state and
    // the first outcome wins.
    test('stays pending until marked, then reports the outcome', () async {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      var settled = false;
      unawaited(state.initialEnableSettled.then((_) => settled = true));
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      expect(state.initialEnableIsSettled, isFalse);
      expect(state.initialEnableOutcome, isNull);

      state.markInitialEnableSettled(outcome: 'completed');
      await Future<void>.delayed(Duration.zero);
      expect(settled, isTrue);
      expect(state.initialEnableIsSettled, isTrue);
      expect(state.initialEnableOutcome, 'completed');
    });

    test('a second mark is ignored and the first outcome is kept', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      state.markInitialEnableSettled(outcome: 'completed_after_timeout');
      state.markInitialEnableSettled(outcome: 'failed');
      expect(state.initialEnableOutcome, 'completed_after_timeout');
    });
  });

  group('LivekitMicrophoneSenderGate.shouldRepublishForDeviceChange', () {
    // "Switch to another mic, it works; switch back, it is dead again": the
    // switch back compared equal device ids and returned early while the
    // sender was still detached.
    test(
      'an unchanged device republishes only when the sender is detached',
      () {
        expect(
          LivekitMicrophoneSenderGate.shouldRepublishForDeviceChange(
            deviceChanged: false,
            senderDetached: false,
          ),
          isFalse,
        );
        expect(
          LivekitMicrophoneSenderGate.shouldRepublishForDeviceChange(
            deviceChanged: false,
            senderDetached: true,
          ),
          isTrue,
        );
      },
    );

    test('a changed device always republishes', () {
      expect(
        LivekitMicrophoneSenderGate.shouldRepublishForDeviceChange(
          deviceChanged: true,
          senderDetached: false,
        ),
        isTrue,
      );
    });
  });
}
