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
    );

    // Hang-up is memoised; this cancels the session's periodic timers.
    addTearDown(session.hangUpCall);

    return _LocalPublicationHarness._(
      livekitRoom: livekitRoom,
      session: session,
    );
  }
}
