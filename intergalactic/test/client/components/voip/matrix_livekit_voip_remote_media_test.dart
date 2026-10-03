// Remote-media reconciliation driven through the real
// `MatrixLivekitVoipSession` (P0-3, C-L2, C-4).
//
// The acceptance criterion for this slice is the first test: a publication
// that appears while the room is `reconnecting` is rendered without a rejoin.
// Before the widening there was no path to that at all — `addInitialStreams`
// ran exactly once, from the constructor, and the only ongoing reconciler was
// restricted to microphone audio, so remote camera, screen-share video and
// screen-share audio had no desired-vs-actual check at any point in a
// session's life. A rejoin "fixed" it purely because a new session re-ran the
// one snapshot that exists.
//
// The rest of the file guards the two ways a widened reconciler goes wrong:
// firing on the tautology (`subscribed` is *defined* as
// `subscriptionAllowed && track != null`, so it is always false at publish
// time), and fighting the app's own decision to unsubscribe hidden screen
// shares.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_room_teardown_barrier.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'fakes/voip_fakes.dart';

const _aliceStateKey = '_@alice:example.org_ALICEDEVICE_m.call';
const _bobIdentity = '@bob:example.org:BOBDEVICE';
const _carolIdentity = '@carol:example.org:CAROLDEVICE';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(LiveKitRoomTeardownBarrier.debugResetForTesting);
  tearDown(LiveKitRoomTeardownBarrier.debugResetForTesting);

  group('remote media reconciliation', () {
    test('ACCEPTANCE: a camera published while the room is reconnecting is '
        'rendered without a rejoin', () async {
      final harness = await _RemoteMediaHarness.create();

      // The SDK emits TrackPublishedEvent only while the room is `connected`
      // (livekit_client-2.5.4 participant/remote.dart:283). A camera that
      // comes up during a reconnect therefore produces no event at all.
      harness.livekitRoom.setConnectionState(lk.ConnectionState.reconnecting);
      final carolCamera = _cameraPublication();
      final carol = FakeRemoteParticipant(
        identity: _carolIdentity,
        publications: <lk.RemoteTrackPublication>[carolCamera],
      );
      harness.livekitRoom.addRemoteParticipant(carol);
      await harness.livekitRoom.emitIfConnected(
        lk.TrackPublishedEvent(participant: carol, publication: carolCamera),
      );

      expect(
        harness.livekitRoom.eventsDroppedWhileNotConnected,
        hasLength(1),
        reason: 'the publish event must actually be dropped by the SDK gate',
      );
      expect(
        harness.streamIds,
        isNot(contains('pub-carol-camera')),
        reason: 'nothing event-driven can have rendered it',
      );

      // The periodic sweep — the only reconciliation that does not depend on
      // an SDK event arriving. No reconnect, no new session, no rejoin.
      await harness.session.debugReconcileRemoteMediaForTesting(
        trigger: 'test_reconnecting',
      );

      expect(harness.streamIds, contains('pub-carol-camera'));
      expect(
        harness.livekitRoom.connectionState,
        lk.ConnectionState.reconnecting,
        reason: 'the repair must not have required the room to come back',
      );
      expect(
        harness.session.streams
            .firstWhere((stream) => stream.streamId == 'pub-carol-camera')
            .type,
        VoipStreamType.video,
      );
    });

    test(
      'a screen share published during a reconnect is rendered too',
      () async {
        // Zero remote screen-share publications exist anywhere in the recovered
        // field corpus against 409 local ones, so there is no observed behaviour
        // to match here — only the contract.
        final harness = await _RemoteMediaHarness.create();

        harness.livekitRoom.setConnectionState(lk.ConnectionState.reconnecting);
        final share = _screenSharePublication();
        final shareAudio = FakeRemoteTrackPublication<lk.RemoteAudioTrack>(
          sid: 'pub-carol-screenshare-audio',
          kind: lk.TrackType.AUDIO,
          source: lk.TrackSource.screenShareAudio,
        );
        final carol = FakeRemoteParticipant(
          identity: _carolIdentity,
          publications: <lk.RemoteTrackPublication>[share, shareAudio],
        );
        harness.livekitRoom.addRemoteParticipant(carol);

        await harness.session.debugReconcileRemoteMediaForTesting();

        expect(
          harness.streamIds,
          containsAll(<String>[
            'pub-carol-screenshare',
            'pub-carol-screenshare-audio',
          ]),
        );
        expect(
          harness.session.streams
              .firstWhere(
                (stream) => stream.streamId == 'pub-carol-screenshare',
              )
              .type,
          VoipStreamType.screenshare,
        );
        expect(
          harness.session.streams
              .firstWhere(
                (stream) => stream.streamId == 'pub-carol-screenshare-audio',
              )
              .type,
          VoipStreamType.audio,
          reason:
              'screenshare audio is routed by isScreenShareAudio, not by type; '
              'reporting it as screenshare would make the receive-quality '
              'policy treat it as a video tile',
        );
      },
    );

    test('a participant already in the room at join is rendered by the '
        'snapshot, and the sweep does not re-subscribe them', () async {
      // room.dart:500-503 discards the publications it creates for
      // participants already present, so no publish event ever fires for them.
      final harness = await _RemoteMediaHarness.create();

      expect(harness.streamIds, contains('pub-bob-microphone'));

      await harness.session.debugReconcileRemoteMediaForTesting();

      expect(
        harness.bobMicrophone.operations.subscribeCount,
        0,
        reason:
            'bob has no attached track, so `publication.subscribed` is false '
            'by definition. Subscribing on that is the tautological repair.',
      );
    });

    test('TAUTOLOGY GUARD: a freshly published remote camera is built but not '
        'subscribed', () async {
      final harness = await _RemoteMediaHarness.create();
      final carolCamera = _cameraPublication();
      final carol = FakeRemoteParticipant(
        identity: _carolIdentity,
        publications: <lk.RemoteTrackPublication>[carolCamera],
      );
      harness.livekitRoom.addRemoteParticipant(carol);

      await harness.session.debugReconcileRemoteMediaForTesting();
      await harness.session.debugReconcileRemoteMediaForTesting();
      await harness.session.debugReconcileRemoteMediaForTesting();

      expect(harness.streamIds, contains('pub-carol-camera'));
      expect(
        carolCamera.operations.subscribeCount,
        0,
        reason:
            '`subscribed` is defined as `subscriptionAllowed && track != null` '
            'so it is guaranteed false here. The room auto-subscribes; the '
            'sink arrives on its own. Repairing this state would fire on every '
            'publication on every sweep and prove nothing.',
      );
      expect(carolCamera.operations.unsubscribeCount, 0);
    });

    test('a publication the app disabled itself is left alone', () async {
      // CallView's receive-quality policy disables and unsubscribes off-screen
      // screen shares, which is exactly the detached state in which the SDK
      // stops emitting mute/unmute. The reconciler must not fight it.
      final harness = await _RemoteMediaHarness.create();
      final share = _screenSharePublication(
        track: FakeRemoteVideoTrack(sid: 'track-carol-screenshare'),
      );
      final carol = FakeRemoteParticipant(
        identity: _carolIdentity,
        publications: <lk.RemoteTrackPublication>[share],
      );
      harness.livekitRoom.addRemoteParticipant(carol);
      await harness.session.debugReconcileRemoteMediaForTesting();

      final shareStream = harness.session.streams.firstWhere(
        (stream) => stream.streamId == 'pub-carol-screenshare',
      );
      await shareStream.setReceivePriority(VoipStreamReceivePriority.disabled);
      expect(share.operations.unsubscribeCount, 1);
      expect(share.track, isNull, reason: 'the app detached it on purpose');
      share.operations.clear();

      await harness.session.debugReconcileRemoteMediaForTesting();
      await harness.session.debugReconcileRemoteMediaForTesting();

      expect(share.operations.subscribeCount, 0);
      expect(
        harness.streamIds,
        contains('pub-carol-screenshare'),
        reason: 'the tile stays; only the media is dropped',
      );
    });

    test(
      'the same publication is repaired once the app wants it again',
      () async {
        final harness = await _RemoteMediaHarness.create();
        final share = _screenSharePublication(
          track: FakeRemoteVideoTrack(sid: 'track-carol-screenshare'),
        );
        final carol = FakeRemoteParticipant(
          identity: _carolIdentity,
          publications: <lk.RemoteTrackPublication>[share],
        );
        harness.livekitRoom.addRemoteParticipant(carol);
        await harness.session.debugReconcileRemoteMediaForTesting();

        final shareStream = harness.session.streams.firstWhere(
          (stream) => stream.streamId == 'pub-carol-screenshare',
        );
        await shareStream.setReceivePriority(
          VoipStreamReceivePriority.disabled,
        );
        // Reveal the tile without going through the LiveKit re-subscribe, which
        // is the state left behind when the reveal path fails or never runs.
        await shareStream.setReceivePriority(VoipStreamReceivePriority.high);
        share.operations.clear();
        await share.disable();
        share.operations.clear();

        await harness.session.debugReconcileRemoteMediaForTesting();

        expect(
          share.operations.subscribeCount,
          1,
          reason:
              'receive is enabled again but the publication is still '
              'disabled, which is a genuine control-plane divergence',
        );
      },
    );

    test(
      'a remote camera that muted while detached loses its stale tile',
      () async {
        final harness = await _RemoteMediaHarness.create();
        final carolCamera = _cameraPublication();
        final carol = FakeRemoteParticipant(
          identity: _carolIdentity,
          publications: <lk.RemoteTrackPublication>[carolCamera],
        );
        harness.livekitRoom.addRemoteParticipant(carol);
        await harness.session.debugReconcileRemoteMediaForTesting();
        expect(harness.streamIds, contains('pub-carol-camera'));

        // Mute events come from a listener attached to the track, so with no
        // track there is no event — but `publication.muted` is still updated
        // from the server's TrackInfo, which is why polling can see this at all.
        carolCamera.setMuted(true);
        await harness.session.debugReconcileRemoteMediaForTesting();

        expect(harness.streamIds, isNot(contains('pub-carol-camera')));
      },
    );

    test('ACCEPTANCE (BUG-321 origin): an unpublish that lands mid-repair is '
        'not undone by that repair', () async {
      // Read from a 68-minute capture, in production order: the sweep decides
      // a repair for a screen share, the sharer's republish unpublishes it
      // while `subscribe()` is awaited, the unpublish handler removes the
      // stream - and the repair then re-adds it. No second unpublish can
      // follow for a publication the SDK has already dropped, so that stream
      // is stranded for the rest of the call. The removal is issued from
      // inside the awaited call rather than sequenced around the sweep, so
      // the test cannot pass by running the two in an order production never
      // produces.
      final harness = await _RemoteMediaHarness.create();
      late final FakeRemoteTrackPublication<lk.RemoteVideoTrack> share;
      late final FakeRemoteParticipant carol;
      share = FakeRemoteTrackPublication<lk.RemoteVideoTrack>(
        sid: 'pub-carol-screenshare',
        kind: lk.TrackType.VIDEO,
        source: lk.TrackSource.screenShareVideo,
        mimeType: 'video/VP8',
        track: FakeRemoteVideoTrack(sid: 'track-carol-screenshare'),
        // The app's own receive switch is off, which is what makes the policy
        // choose `subscribe` - the repair the capture recorded.
        enabled: false,
        onSubscribe: () async {
          carol.removePublication(share.sid);
          await harness.livekitRoom.emit(
            lk.TrackUnpublishedEvent(participant: carol, publication: share),
          );
        },
      );
      carol = FakeRemoteParticipant(
        identity: _carolIdentity,
        publications: <lk.RemoteTrackPublication>[share],
      );
      harness.livekitRoom.addRemoteParticipant(carol);

      await harness.session.debugReconcileRemoteMediaForTesting();
      await pumpEventQueue();

      // PRECONDITION, not a result. The collision only exists because the
      // sweep chose `subscribe` for this publication: that is the one action
      // that awaits `subscribe()`, and `onSubscribe` is the only thing that
      // emits the unpublish. If the policy stops choosing the repair, nothing
      // is unpublished, no stream is ever added, and the assertion below
      // passes over a scenario that no longer happened.
      expect(
        share.operations.subscribeCount,
        1,
        reason:
            'the sweep must still decide the repair this test collides with, '
            'or nothing below is being exercised',
      );
      expect(
        carol.trackPublications.containsKey('pub-carol-screenshare'),
        isFalse,
        reason:
            'and the unpublish must have landed from inside that awaited '
            'call, which is what makes it mid-repair rather than sequenced',
      );

      expect(
        harness.streamIds,
        isNot(contains('pub-carol-screenshare')),
        reason:
            'the repair was decided before the unpublish and completed after '
            'it; re-adding the stream here strands it permanently',
      );
    });

    test('a departed participant is not resurrected by the sweep', () async {
      final harness = await _RemoteMediaHarness.create();
      final carolCamera = _cameraPublication();
      final carol = FakeRemoteParticipant(
        identity: _carolIdentity,
        publications: <lk.RemoteTrackPublication>[carolCamera],
      );
      harness.livekitRoom.addRemoteParticipant(carol);
      await harness.session.debugReconcileRemoteMediaForTesting();
      expect(harness.streamIds, contains('pub-carol-camera'));

      harness.livekitRoom.removeRemoteParticipant(_carolIdentity);
      await harness.livekitRoom.emit(
        lk.ParticipantDisconnectedEvent(participant: carol),
      );
      await harness.session.debugReconcileRemoteMediaForTesting();

      expect(harness.streamIds, isNot(contains('pub-carol-camera')));
    });

    test('C-4: an audio publication with no attached track reports audio, not '
        'video', () async {
      final harness = await _RemoteMediaHarness.create();

      final microphone = harness.session.streams.firstWhere(
        (stream) => stream.streamId == 'pub-bob-microphone',
      );

      expect(harness.bobMicrophone.track, isNull);
      expect(
        microphone.type,
        VoipStreamType.audio,
        reason:
            'type is derived from publication.kind now. Deriving it from the '
            'transient publication.track made every remote microphone report '
            'video for the whole pre-attach window.',
      );
    });

    test('C-4: a remote participant muted before we subscribe reports '
        'muted', () async {
      final harness = await _RemoteMediaHarness.create();
      harness.bobMicrophone.setMuted(true);

      final microphone = harness.session.streams.firstWhere(
        (stream) => stream.streamId == 'pub-bob-microphone',
      );

      expect(
        microphone.isMuted,
        isTrue,
        reason:
            'publication.muted is written from the server TrackInfo and is '
            'readable with no sink attached; track.muted is not reachable at '
            'all until one is',
      );
    });
  });

  group('phantom stream prune, driven through the session (BUG-321)', () {
    // WHAT WOULD MAKE THESE WRONG, stated first. Six unit tests already pin
    // `phantomIncomingStreamSidsToPrune`, and every one passed while NOTHING
    // connected that predicate to the session: REVIEW mutated the call site's
    // lifecycle gate to `true` and then to `false` - removing the only guard
    // against pruning live tiles, then switching the headline fix off
    // entirely - and all 713 tests stayed green both times. A pure-function
    // test cannot see a call site.
    //
    // THE CONDITION IS REPRODUCED, not described: the publication is removed
    // from the participant's `trackPublications` with NO TrackUnpublishedEvent
    // while the participant stays connected. That is the BUG-321 shape.

    test(
      'a publication that vanished under a connected participant is pruned',
      () async {
        final harness = await _RemoteMediaHarness.create();
        final bob = harness.livekitRoom.remoteParticipants.values
            .whereType<FakeRemoteParticipant>()
            .firstWhere((participant) => participant.identity == _bobIdentity);
        expect(harness.streamIds, contains('pub-bob-microphone'));

        bob.trackPublications.remove('pub-bob-microphone');
        // The republish: the reconnect brings the microphone back under a
        // NEW sid while the old one is dropped with no unpublish event. What
        // makes bob a prune candidate is his PRESENCE in the snapshot, not
        // the republish - the test below covers the same participant
        // publishing nothing at all.
        bob.trackPublications['pub-bob-microphone-2'] =
            FakeRemoteTrackPublication<lk.RemoteAudioTrack>(
              sid: 'pub-bob-microphone-2',
              kind: lk.TrackType.AUDIO,
            );

        await harness.session.debugReconcileRemoteMediaForTesting();
        await pumpEventQueue();

        expect(
          harness.streamIds,
          isNot(contains('pub-bob-microphone')),
          reason:
              'the phantom tile has to go, and this is the assertion the '
              'six predicate tests could not make',
        );
      },
    );

    test('a connected participant who unpublished EVERYTHING has their '
        'phantom pruned too', () async {
      // The same dropped-TrackUnpublishedEvent shape in its most complete
      // form, and the one the sweep's own map could not express: the prune
      // reads a participant with no key as "not in this snapshot, leave them
      // alone", and the key used to be written only from inside the
      // publication loop - so a still-connected participant publishing
      // nothing had no key, and their stale tiles were skipped by exactly the
      // prune that exists for them. Nothing else removes those tiles either:
      // no unpublish event is coming and the participant never disconnects.
      final harness = await _RemoteMediaHarness.create();
      final bob = harness.livekitRoom.remoteParticipants.values
          .whereType<FakeRemoteParticipant>()
          .firstWhere((participant) => participant.identity == _bobIdentity);
      expect(harness.streamIds, contains('pub-bob-microphone'));

      bob.trackPublications.clear();

      await harness.session.debugReconcileRemoteMediaForTesting();
      await pumpEventQueue();

      expect(
        harness.livekitRoom.remoteParticipants.containsKey(_bobIdentity),
        isTrue,
        reason:
            'the premise: bob is still connected, so this is a prune '
            'decision and not a disconnect',
      );
      expect(harness.streamIds, isNot(contains('pub-bob-microphone')));
    });

    test('a phantom is NOT pruned while the room is reconnecting', () async {
      // The control, and the case that catches a gate widened to `true`. A
      // reconnecting snapshot can be incomplete, so a publication missing
      // during a reconnect is not evidence that it is gone; pruning then drops
      // LIVE tiles, which is worse than the bug being fixed.
      final harness = await _RemoteMediaHarness.create();
      final bob = harness.livekitRoom.remoteParticipants.values
          .whereType<FakeRemoteParticipant>()
          .firstWhere((participant) => participant.identity == _bobIdentity);
      expect(harness.streamIds, contains('pub-bob-microphone'));

      harness.livekitRoom.setConnectionState(lk.ConnectionState.reconnecting);
      harness.session.onRoomReconnecting(const lk.RoomReconnectingEvent());
      bob.trackPublications.remove('pub-bob-microphone');
      bob.trackPublications['pub-bob-microphone-2'] =
          FakeRemoteTrackPublication<lk.RemoteAudioTrack>(
            sid: 'pub-bob-microphone-2',
            kind: lk.TrackType.AUDIO,
          );

      await harness.session.debugReconcileRemoteMediaForTesting();
      await pumpEventQueue();

      expect(
        harness.streamIds,
        contains('pub-bob-microphone'),
        reason: 'an incomplete reconnect snapshot must not drop a live tile',
      );
    });
  });
}

FakeRemoteTrackPublication<lk.RemoteVideoTrack> _cameraPublication() {
  return FakeRemoteTrackPublication<lk.RemoteVideoTrack>(
    sid: 'pub-carol-camera',
    kind: lk.TrackType.VIDEO,
    source: lk.TrackSource.camera,
    mimeType: 'video/VP8',
  );
}

FakeRemoteTrackPublication<lk.RemoteVideoTrack> _screenSharePublication({
  lk.RemoteVideoTrack? track,
}) {
  return FakeRemoteTrackPublication<lk.RemoteVideoTrack>(
    sid: 'pub-carol-screenshare',
    kind: lk.TrackType.VIDEO,
    source: lk.TrackSource.screenShareVideo,
    mimeType: 'video/VP8',
    track: track,
  );
}

class _RemoteMediaHarness {
  _RemoteMediaHarness._({
    required this.livekitRoom,
    required this.bobMicrophone,
    required this.session,
  });

  final FakeLiveKitRoom livekitRoom;
  final FakeRemoteTrackPublication<lk.RemoteAudioTrack> bobMicrophone;
  final MatrixLivekitVoipSession session;

  Iterable<String> get streamIds =>
      session.streams.map((stream) => stream.streamId);

  static Future<_RemoteMediaHarness> create() async {
    final bobMicrophone = FakeRemoteTrackPublication<lk.RemoteAudioTrack>(
      sid: 'pub-bob-microphone',
      kind: lk.TrackType.AUDIO,
    );
    final bob = FakeRemoteParticipant(
      identity: _bobIdentity,
      publications: <lk.RemoteTrackPublication>[bobMicrophone],
    );
    final livekitRoom = FakeLiveKitRoom(
      remoteParticipants: <lk.RemoteParticipant>[bob],
    );
    final session = MatrixLivekitVoipSession(
      FakeCallMatrixRoom(),
      livekitRoom,
      stateKey: _aliceStateKey,
      foci: <Uri>[Uri.parse('https://livekit.example.org')],
    );
    addTearDown(session.hangUpCall);
    // Drain the constructor's initial-snapshot reconciliation so each test
    // starts from a settled state.
    await pumpEventQueue();

    return _RemoteMediaHarness._(
      livekitRoom: livekitRoom,
      bobMicrophone: bobMicrophone,
      session: session,
    );
  }
}
