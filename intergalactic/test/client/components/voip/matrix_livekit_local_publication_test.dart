// Local publication reconciliation, driven through the real
// `MatrixLivekitVoipSession`.
//
// The defect these cover is *sender attachment*, not a track/publication mute
// divergence. That divergence cannot actually occur for a
// `LocalTrackPublication`: `LocalTrackPublication` does not override
// `updateFromInfo`, `LocalParticipant` inherits `Participant.updateFromInfo`
// (`participant.dart:211-233`) which never touches publications, and
// `_metadataMuted` has exactly two writers - so a publication rebuilt by
// `rePublishAllTracks()` cannot end up disagreeing with its track.
//
// What *is* real: `sender.replaceTrack(null)` is invisible to LiveKit. The app
// detaches the RTP sender to mute on Windows, and `publication.muted` is the
// only record that it did. Every SDK-native unmute then clears that record
// without reattaching anything - `skipStopForTrackMute()` is true on Windows
// (`support/platform.dart:42-44`), so `LocalTrack.unmute()` skips
// `restartTrack()` and only calls `enable()` + `updateMuted(false)`. The
// result is a publication reporting `muted == false` over a sender carrying
// nothing, and the unmute path used to be nested inside `if
// (publication.muted)` so it did nothing at all in exactly that state.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_microphone_sender_gate.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_room_teardown_barrier.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'fakes/voip_fakes.dart';

const _aliceStateKey = '_@alice:example.org_ALICEDEVICE_m.call';
const _aliceIdentity = '@alice:example.org:ALICEDEVICE';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LiveKitRoomTeardownBarrier.debugResetForTesting);
  tearDown(LiveKitRoomTeardownBarrier.debugResetForTesting);

  group('LivekitMicrophoneSenderGate', () {
    test('reports detached only when the sender is known to carry nothing', () {
      final track = FakeLocalAudioTrack();
      final publication = _microphonePublication(track: track);

      // No sender yet: undecidable, and must not be mistaken for detached -
      // that is also the normal state while a publication is negotiating.
      expect(
        LivekitMicrophoneSenderGate.attachmentOf(publication),
        LivekitMicrophoneSenderAttachment.unknown,
      );
      expect(LivekitMicrophoneSenderGate.isDetached(publication), isFalse);

      track.attachSender();
      expect(
        LivekitMicrophoneSenderGate.attachmentOf(publication),
        LivekitMicrophoneSenderAttachment.attached,
      );

      track.attachDetachedSender();
      expect(
        LivekitMicrophoneSenderGate.attachmentOf(publication),
        LivekitMicrophoneSenderAttachment.detached,
      );
      expect(LivekitMicrophoneSenderGate.isDetached(publication), isTrue);
    });

    group('Push to Talk join arming', () {
      // BUG-322 residual, raised by REVIEW: the decision that the join must
      // publish rather than skip was covered, and the CALL SITE that acts on
      // it was not. These assert the consequence a user would hear - whether
      // the capture track is live - rather than the predicate.

      test(
        'enables the track once the sender is known to carry nothing',
        () async {
          final track = FakeLocalAudioTrack();
          final publication = _microphonePublication(track: track);
          track.attachSender();
          await track.disable();

          final armed =
              await LivekitMicrophoneSenderGate.armPushToTalkJoinPublication(
                publication: publication,
                track: track,
                source: 'test',
              );

          expect(armed.attachment, LivekitMicrophoneSenderAttachment.detached);
          expect(armed.trackEnabled, isTrue);
          expect(
            track.mediaStreamTrack.enabled,
            isTrue,
            reason:
                'the press has to carry audio, so the track is live once the '
                'sender is detached and nothing can leave',
          );
        },
      );

      test('leaves the track disabled while the publication is still '
          'negotiating', () async {
        // No sender yet. `attachmentOf` calls that `unknown`, and it is the
        // NORMAL state for a publication that has just come back from
        // publishAudioTrack - so this is the common case, not an edge one.
        final track = FakeLocalAudioTrack();
        final publication = _microphonePublication(track: track);
        await track.disable();

        final armed =
            await LivekitMicrophoneSenderGate.armPushToTalkJoinPublication(
              publication: publication,
              track: track,
              source: 'test',
            );

        expect(armed.attachment, LivekitMicrophoneSenderAttachment.unknown);
        expect(armed.trackEnabled, isFalse);
        expect(
          track.mediaStreamTrack.enabled,
          isFalse,
          reason:
              'enabling here would put a LIVE microphone on a Push to Talk '
              'join behind an indicator that reads muted',
        );
      });

      test('leaves the track disabled when the detach itself failed', () async {
        final track = FakeLocalAudioTrack();
        final publication = _microphonePublication(track: track);
        final sender = track.attachSender();
        sender.replaceTrackError = StateError('replaceTrack failed');
        await track.disable();

        final armed =
            await LivekitMicrophoneSenderGate.armPushToTalkJoinPublication(
              publication: publication,
              track: track,
              source: 'test',
            );

        expect(armed.senderMoved, isFalse);
        expect(armed.attachment, LivekitMicrophoneSenderAttachment.attached);
        expect(armed.trackEnabled, isFalse);
        expect(
          track.mediaStreamTrack.enabled,
          isFalse,
          reason: 'the sender is still carrying the track, so audio would flow',
        );
      });
    });

    test('attachment is independent of the publication mute flag', () {
      final track = FakeLocalAudioTrack();
      final publication = _microphonePublication(
        track: track,
        propagateTrackMute: false,
      );
      final sender = track.attachDetachedSender();

      // The silent-mic steady state: nothing is being sent, yet every
      // SDK-derived signal says the microphone is live.
      publication.setMuted(false);

      expect(publication.muted, isFalse);
      expect(LivekitMicrophoneSenderGate.isDetached(publication), isTrue);
      expect(sender.track, isNull);
    });

    test(
      'reattach is driven by sender state, not by publication.muted',
      () async {
        final track = FakeLocalAudioTrack();
        final publication = _microphonePublication(
          track: track,
          propagateTrackMute: false,
        );
        final sender = track.attachDetachedSender();
        publication.setMuted(false);

        final moved = await LivekitMicrophoneSenderGate.setDetached(
          publication,
          detached: false,
          reason: 'unmute',
          source: 'test',
        );

        expect(moved, isTrue);
        expect(sender.reattachCount, 1);
        expect(sender.track, same(track.mediaStreamTrack));
        expect(
          LivekitMicrophoneSenderGate.attachmentOf(publication),
          LivekitMicrophoneSenderAttachment.attached,
        );
      },
    );

    test(
      'detach repairs stale metadata when the sender is already detached',
      () async {
        final track = FakeLocalAudioTrack();
        final publication = _microphonePublication(
          track: track,
          propagateTrackMute: false,
        );
        final sender = track.attachDetachedSender();
        publication.setMuted(false);

        final moved = await LivekitMicrophoneSenderGate.setDetached(
          publication,
          detached: true,
          reason: 'mute',
          source: 'test',
        );

        // Nothing to move, but the metadata was lying and is now corrected.
        // The previous implementation returned early and left it lying.
        expect(moved, isFalse);
        expect(sender.replaceTrackCalls, isEmpty);
        expect(track.muted, isTrue);
      },
    );

    test(
      'a replaceTrack failure is recovered, and metadata is not moved',
      () async {
        final track = FakeLocalAudioTrack();
        final publication = _microphonePublication(
          track: track,
          propagateTrackMute: false,
        );
        final sender = track.attachSender();
        publication.setMuted(false);
        sender.replaceTrackError = StateError('sender is gone');

        final moved = await LivekitMicrophoneSenderGate.setDetached(
          publication,
          detached: true,
          reason: 'mute',
          source: 'test',
        );

        // False through the return value, not an escaping exception - the
        // caller must be able to tell "sender not moved" from a crash on the
        // call-control path. And because the sender did NOT move, the mute
        // metadata must not claim it did.
        expect(moved, isFalse);
        expect(sender.replaceTrackCalls, [null]);
        expect(track.muted, isFalse);
        expect(
          LivekitMicrophoneSenderGate.attachmentOf(publication),
          LivekitMicrophoneSenderAttachment.attached,
        );
      },
    );
  });

  group('Push to Talk join publish outcome', () {
    // BUG-322 residual. The join settles exactly one outcome string and the
    // sender-reconcile diagnostics are its only reader. A create or publish
    // failure was caught, logged, and then reported as
    // `published_muted_push_to_talk_join` anyway - so the outcome claimed a
    // publication the participant does not have, which is the one thing the
    // diagnostics cannot work out for themselves.
    //
    // Neither native capture nor an SFU exists under flutter_test, so the
    // publish here CANNOT succeed: `LocalAudioTrack.create` reaches an absent
    // platform channel, and if it ever got past that the fake participant
    // answers `publishAudioTrack` through noSuchMethod. Both are the real
    // catch path, and the assertion is on what that path reported.
    test('reports failed_push_to_talk_join_publish when nothing was '
        'published', () async {
      final backend = MatrixLivekitBackend(FakeCallMatrixRoom());
      final participant = FakeLocalParticipant(identity: _aliceIdentity);
      final enableState = MatrixLivekitInitialMicrophoneEnableState();

      await backend.debugPublishInitialMicrophoneMutedForPushToTalkForTesting(
        participant,
        audioCaptureOptions: const lk.AudioCaptureOptions(),
        initialMicrophoneEnableState: enableState,
      );

      expect(
        participant.getTrackPublicationBySource(lk.TrackSource.microphone),
        isNull,
        reason: 'the premise: the publish did not happen',
      );
      expect(
        enableState.initialEnableIsSettled,
        isTrue,
        reason:
            'the join-time sender reconcile waits on this, so a failure that '
            'settles nothing costs every Push to Talk join the full fallback',
      );
      expect(
        enableState.initialEnableOutcome,
        'failed_push_to_talk_join_publish',
      );
    });
  });

  group('MatrixLivekitInitialMicrophoneEnableState', () {
    test('reconciles the unmute direction, which had no branch at all', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();

      // Desired: microphone on (the default).
      expect(
        state.shouldReconcileUnmutedPublication(
          publicationMuted: true,
          senderDetached: false,
        ),
        isTrue,
        reason: 'a publication that came back muted must be restored',
      );
      expect(
        state.shouldReconcileUnmutedPublication(
          publicationMuted: false,
          senderDetached: true,
        ),
        isTrue,
        reason:
            'an unmuted publication over a detached sender is the silent mic',
      );
      expect(
        state.shouldReconcileUnmutedPublication(
          publicationMuted: false,
          senderDetached: false,
        ),
        isFalse,
      );

      // The pre-existing mute direction is unchanged.
      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isFalse,
      );
    });

    test('the two directions are mutually exclusive', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      state.markDesiredMicrophoneMuted(stopOnMute: true);

      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isTrue,
      );
      expect(
        state.shouldReconcileUnmutedPublication(
          publicationMuted: false,
          senderDetached: true,
        ),
        isFalse,
        reason: 'the user asked for mute; never fight them back to unmuted',
      );
    });

    test('an ended call reconciles in neither direction', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      state.markCallInactive();

      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isFalse,
      );
      expect(
        state.shouldReconcileUnmutedPublication(
          publicationMuted: true,
          senderDetached: true,
        ),
        isFalse,
      );
    });
  });

  group('MatrixLivekitVoipSession local publication state', () {
    test('unmute reattaches a detached sender even though the publication '
        'already reads unmuted', () async {
      // The regression the audit named as its highest-value test, expressed in
      // sender attachment. Before the fix `setMicrophoneMute(false)` was
      // nested inside `if (publication.muted)`, so in this exact state it
      // returned having done nothing and the user stayed silent until rejoin.
      final track = FakeLocalAudioTrack();
      final publication = _microphonePublication(
        track: track,
        propagateTrackMute: false,
      );
      final sender = track.attachDetachedSender();
      publication.setMuted(false);

      final harness = await _LocalPublicationHarness.create(
        publications: <lk.LocalTrackPublication>[publication],
      );

      expect(sender.track, isNull, reason: 'precondition: nothing is sent');

      await harness.session.setMicrophoneMute(false);

      expect(
        sender.reattachCount,
        1,
        reason: 'unmute must reattach the sender, not trust publication.muted',
      );
      expect(sender.track, same(track.mediaStreamTrack));
      expect(
        LivekitMicrophoneSenderGate.attachmentOf(publication),
        LivekitMicrophoneSenderAttachment.attached,
      );
      expect(harness.session.isMicrophoneMuted, isFalse);
    }, skip: _skipUnlessWindows);

    test('mute detaches the sender even though the publication already reads '
        'muted', () async {
      // The symmetric hot-mic direction. `setMicrophoneMute(true)` used to
      // return early on `publication.muted` alone, leaving an attached sender
      // still carrying audio while the UI showed the user as muted.
      final track = FakeLocalAudioTrack();
      final publication = _microphonePublication(
        track: track,
        propagateTrackMute: false,
      );
      final sender = track.attachSender();
      publication.setMuted(true);

      final harness = await _LocalPublicationHarness.create(
        publications: <lk.LocalTrackPublication>[publication],
      );

      await harness.session.setMicrophoneMute(true);

      expect(
        sender.detachCount,
        1,
        reason: 'the sender was still live; mute must actually detach it',
      );
      expect(sender.track, isNull);
    }, skip: _skipUnlessWindows);

    test(
      'a Push to Talk join is not unmuted by the join-time reconcile',
      () async {
        // BUG-320 x BUG-322, exercised rather than reasoned about because
        // the failure mode if it is wrong is a LIVE MICROPHONE on a user who
        // chose Push to Talk.
        //
        // BUG-320 added a join-time reconcile whose purpose is repairing
        // DETACHED senders. BUG-322 makes a Push to Talk join publish with
        // the sender detached ON PURPOSE - that is PTT's steady state on
        // Windows. So the reconcile now runs against a publication that is
        // detached deliberately, and the question is whether it 'repairs' it.
        //
        // Reasoning was not enough: a mutation on the reconcile branch showed
        // an unsequenced reconcile computing direction=unmute on a
        // publication reading muted=true, so the direction is not a simple
        // read of the mute flag.
        //
        // WHAT THIS SCENARIO CANNOT CATCH, found by REVIEW running the
        // mutation rather than taking the claim. `shouldUnmute` is computed as
        // `!shouldMute && shouldReconcileUnmutedPublication(...)`, so the mute
        // direction SHADOWS the unmute one. On a PTT join `shouldMute` is true
        // - call active, desired disabled, `publication.muted` false as this
        // scenario builds it - which makes `shouldUnmute` false whatever the
        // predicate returns. Delete `_desiredMicrophoneEnabled` from that predicate and
        // this scenario still passes, because the reconcile still takes the
        // mute branch and still leaves the sender detached.
        //
        // So the scenario pins the OUTCOME and the predicate assertion at the
        // end pins the REASON. Without the second, this test would be
        // protected by a short-circuit rather than by what it was written for.
        final track = FakeLocalAudioTrack();
        final publication = _microphonePublication(
          track: track,
          propagateTrackMute: false,
        );
        final sender = track.attachDetachedSender();
        // Published with the sender detached, which is what the Push to Talk
        // join leaves behind. `muted` is set FALSE by hand here, which the
        // real arm does not do - `setDetached(detached: true)` signals muted
        // on every branch that leaves the sender carrying nothing. False is
        // the harder input: it is the only one that makes the drift reconcile
        // take a branch at all, so the state that could put a live microphone
        // on a Push to Talk user is the one under test.
        publication.setMuted(false);

        final enableState = MatrixLivekitInitialMicrophoneEnableState();
        enableState.markDesiredMicrophoneMuted(stopOnMute: false);

        final harness = await _LocalPublicationHarness.create(
          publications: <lk.LocalTrackPublication>[publication],
          initialMicrophoneEnableState: enableState,
        );

        await harness.session.debugReconcileLocalMicrophoneDriftForTesting(
          publication,
          trigger: 'initial_join',
        );

        expect(
          sender.track,
          isNull,
          reason:
              'THE ASSERTION THAT MATTERS: the reconcile must not put a live '
              'microphone on a Push to Talk user',
        );
        expect(
          sender.reattachCount,
          0,
          reason: 'not reattached once, not even transiently',
        );
        expect(
          publication.muted,
          isFalse,
          reason:
              'the reconcile must not have moved the metadata either; this '
              'publication was built pre-arm by construction',
        );

        // The REASON, asserted where the short-circuit cannot hide it. In the
        // Push to Talk join state the unmute direction must be refused on its
        // OWN terms - the app does not want the microphone sending - and not
        // merely because the mute direction won the race to decide first.
        expect(
          enableState.shouldReconcileUnmutedPublication(
            publicationMuted: false,
            senderDetached: true,
          ),
          isFalse,
          reason:
              'a detached sender is Push to Talk steady state, not drift to '
              'repair; this is the term whose removal would put a live '
              'microphone on a Push to Talk user',
        );
      },
      skip: _skipUnlessWindows,
    );

    test('isMicrophoneMuted reports the microphone, not the first audio '
        'publication', () async {
      // `Participant.isMuted` is `audioTrackPublications.firstOrNull?.muted`
      // (`participant/participant.dart:104`). With screen-share audio present
      // that list can lead with the screen share, so the mic indicator was
      // rendering a different track's mute state.
      final screenShareAudio = FakeLocalTrackPublication<lk.LocalAudioTrack>(
        sid: 'pub-alice-screenshare-audio',
        kind: lk.TrackType.AUDIO,
        source: lk.TrackSource.screenShareAudio,
        muted: false,
      );
      final microphone = _microphonePublication(muted: true);

      final harness = await _LocalPublicationHarness.create(
        // Screen-share audio first, which is the ordering that produces the
        // wrong answer.
        publications: <lk.LocalTrackPublication>[screenShareAudio, microphone],
      );

      expect(
        harness.session.livekitRoom.localParticipant?.isMuted,
        isFalse,
        reason: 'the SDK derivation reads the screen-share publication',
      );
      expect(
        harness.session.isMicrophoneMuted,
        isTrue,
        reason: 'the microphone is muted and that is what the indicator means',
      );
    });

    test(
      'isMicrophoneMuted reports muted when the sender carries nothing',
      () async {
        final track = FakeLocalAudioTrack();
        final publication = _microphonePublication(
          track: track,
          propagateTrackMute: false,
        );
        track.attachDetachedSender();
        publication.setMuted(false);

        final harness = await _LocalPublicationHarness.create(
          publications: <lk.LocalTrackPublication>[publication],
        );

        expect(
          harness.session.isMicrophoneMuted,
          isTrue,
          reason: 'nothing is being sent, so the UI must not show a live mic',
        );
      },
    );

    test('isMicrophoneMuted reports muted when nothing is published', () async {
      final harness = await _LocalPublicationHarness.create(
        publications: const <lk.LocalTrackPublication>[],
      );

      expect(harness.session.isMicrophoneMuted, isTrue);
    });

    test(
      'isCameraEnabled requires a live track, not just a present one',
      () async {
        final track = FakeLocalVideoTrack();
        final camera = FakeLocalTrackPublication<lk.LocalVideoTrack>(
          sid: 'pub-alice-camera',
          kind: lk.TrackType.VIDEO,
          source: lk.TrackSource.camera,
          track: track,
          mimeType: 'video/VP8',
        );

        final harness = await _LocalPublicationHarness.create(
          publications: <lk.LocalTrackPublication>[camera],
        );

        expect(harness.session.isCameraEnabled, isTrue);

        // A stopped capture leaves the publication object in place. Presence of
        // the object is not evidence that frames are being produced.
        await track.stop();

        expect(
          harness.session.isCameraEnabled,
          isFalse,
          reason: 'a stopped camera must not keep the button lit',
        );
      },
    );
  });
}

/// The sender detach/reattach path is reached only on Windows
/// (`setMicrophoneMute` branches on `PlatformUtils.isWindows`), because it
/// exists to avoid the native `MediaStreamTrack.enabled` toggle implicated in
/// the Windows crash reports. Everywhere else LiveKit's own mute owns the
/// sender.
final Object? _skipUnlessWindows = PlatformUtils.isWindows
    ? null
    : 'the microphone sender detach/reattach path is Windows-only';

FakeLocalTrackPublication<lk.LocalAudioTrack> _microphonePublication({
  FakeLocalAudioTrack? track,
  bool muted = false,
  bool propagateTrackMute = true,
}) {
  return FakeLocalTrackPublication<lk.LocalAudioTrack>(
    sid: 'pub-alice-microphone',
    kind: lk.TrackType.AUDIO,
    track: track,
    muted: muted,
    propagateTrackMute: propagateTrackMute,
  );
}

class _LocalPublicationHarness {
  _LocalPublicationHarness._({
    required this.livekitRoom,
    required this.session,
  });

  final FakeLiveKitRoom livekitRoom;
  final MatrixLivekitVoipSession session;

  static Future<_LocalPublicationHarness> create({
    required List<lk.LocalTrackPublication> publications,
    MatrixLivekitInitialMicrophoneEnableState? initialMicrophoneEnableState,
  }) async {
    final livekitRoom = FakeLiveKitRoom(
      localParticipant: FakeLocalParticipant(
        identity: _aliceIdentity,
        publications: publications,
      ),
      remoteParticipants: const <lk.RemoteParticipant>[],
    );

    final session = MatrixLivekitVoipSession(
      FakeCallMatrixRoom(),
      livekitRoom,
      stateKey: _aliceStateKey,
      foci: <Uri>[Uri.parse('https://livekit.example.org')],
      initialMicrophoneEnableState: initialMicrophoneEnableState,
    );

    // Hang-up is memoised; this cancels the session's periodic timers.
    addTearDown(session.hangUpCall);

    return _LocalPublicationHarness._(
      livekitRoom: livekitRoom,
      session: session,
    );
  }
}
