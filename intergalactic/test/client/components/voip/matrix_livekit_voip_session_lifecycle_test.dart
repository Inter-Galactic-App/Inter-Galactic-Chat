// Session lifecycle driven through the real `MatrixLivekitVoipSession`.
//
// Before this file no test anywhere constructed a `MatrixLivekitVoipSession`
// or a fake `lk.Room`: every session-lifecycle assertion went through a
// free-function `debug*ForTesting` shim, so the wiring between the session and
// the LiveKit room - which is where the confirmed defects live - was never
// exercised.
//
// The third test here is the conversion of an existing behaviour. The
// room-listener teardown step was previously only reachable as
// `debugRunMatrixLivekitVoipSessionCleanupForTesting(operation:
// 'room-listener-dispose', ...)` in
// `matrix_livekit_voip_session_cleanup_test.dart`, which proves the *helper*
// swallows a failure and proves nothing about the session. It now runs the
// real `hangUpCall()` against a fake room and asserts the listener is actually
// disposed and that a room event arriving afterwards is ignored.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
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

  group('MatrixLivekitVoipSession driven through LiveKit fakes', () {
    test('builds streams from the initial room snapshot', () async {
      final harness = await _CallHarness.create();

      expect(harness.session.streams.map((stream) => stream.streamId), <String>[
        'pub-bob-microphone',
      ]);
      expect(
        harness.session.streams.single.streamUserId,
        '@bob:example.org',
        reason: 'the device suffix is stripped from the LiveKit identity',
      );
    });

    test('initial-snapshot reconciliation runs through the session, and does '
        'not subscribe on the definition of `subscribed`', () async {
      final harness = await _CallHarness.create();

      // This test used to assert one subscribe + one enable here, on the
      // grounds that a publication with no attached track "resolves to
      // subscribe". That was the tautology: `RemoteTrackPublication.subscribed`
      // is *defined* as `subscriptionAllowed && track != null`
      // (livekit_client-2.5.4 publication/remote.dart:68-72 over
      // publication/track_publication.dart:59), so it is guaranteed false the
      // instant a publication appears, and a `!subscribed -> subscribe` rule
      // fires on every publication at publish time while detecting nothing.
      // The room is auto-subscribe, so the sink arrives on its own.
      //
      // The reconciler now takes its control-plane reading from
      // `publication.enabled` — the app's own receive switch, the only bit
      // that can actually diverge from intent — and expresses "no media ever
      // arrived" as a duration through VoipRemoteMediaAttachMonitor. See
      // matrix_livekit_voip_remote_media_test.dart.
      await pumpEventQueue();

      expect(harness.bobMicrophone.operations.subscribeCount, 0);
      expect(harness.bobMicrophone.operations.enableCount, 0);
      expect(
        harness.session.streams.map((stream) => stream.streamId),
        contains('pub-bob-microphone'),
        reason:
            'the session is still wired to the reconciler; it just has '
            'nothing to repair here',
      );
    });

    test(
      'adds a stream from a track-published event on its own listener',
      () async {
        final harness = await _CallHarness.create();
        final carolCamera = _cameraPublication();
        final carol = FakeRemoteParticipant(
          identity: _carolIdentity,
          publications: <lk.RemoteTrackPublication>[carolCamera],
        );

        harness.livekitRoom.addRemoteParticipant(carol);
        await harness.livekitRoom.emit(
          lk.TrackPublishedEvent(participant: carol, publication: carolCamera),
        );

        expect(
          harness.session.streams.map((stream) => stream.streamId),
          containsAll(<String>['pub-bob-microphone', 'pub-carol-camera']),
        );
      },
    );

    test(
      'hang-up disposes the room listener, so a later room event is ignored',
      () async {
        final harness = await _CallHarness.create();
        final listener = harness.livekitRoom.attachedListeners.single;

        expect(listener.isDisposed, isFalse);
        expect(listener.handlerCount, greaterThan(0));

        // Hold the ROOM dispose open. `FakeLiveKitRoom.dispose` tears down
        // every listener it created, so once it has run `listener.isDisposed`
        // is true whether or not the session disposed its own listener - the
        // assertion below would pass even if the session step were deleted.
        // Gating the room dispose isolates the session's step, which is the
        // thing this test claims to be about.
        final disposeGate = Completer<void>();
        harness.livekitRoom.disposeGate = disposeGate;

        final hangUp = harness.session.hangUpCall();
        await pumpEventQueue();

        expect(
          listener.isDisposed,
          isTrue,
          reason:
              'the session must dispose its own room listener; the room '
              'dispose has not run yet',
        );

        disposeGate.complete();
        await hangUp;
        await pumpEventQueue();

        expect(harness.session.state, VoipState.ended);
        expect(harness.session.streams, isEmpty);
        expect(harness.livekitRoom.disconnectCount, 1);
        expect(harness.livekitRoom.disposeCount, 1);
        expect(
          harness.matrixRoom.sdkClient.roomStateWrites.single.isClear,
          isTrue,
          reason: 'hang-up clears the MatrixRTC call-member state',
        );

        // A LiveKit event that arrives after teardown must not resurrect a
        // stream. With the listener disposed nothing is subscribed, which is
        // the state the CallSessionEventGate exists to make safe.
        final carolCamera = _cameraPublication();
        final carol = FakeRemoteParticipant(
          identity: _carolIdentity,
          publications: <lk.RemoteTrackPublication>[carolCamera],
        );
        harness.livekitRoom.addRemoteParticipant(carol);
        await harness.livekitRoom.emit(
          lk.TrackPublishedEvent(participant: carol, publication: carolCamera),
        );

        expect(harness.session.streams, isEmpty);
        expect(harness.livekitRoom.eventsDroppedWithoutListener, hasLength(1));
      },
    );

    test('a publish event emitted before the session attaches its listener is '
        'never seen by the session', () async {
      final carolCamera = _cameraPublication();
      final carol = FakeRemoteParticipant(
        identity: _carolIdentity,
        publications: <lk.RemoteTrackPublication>[carolCamera],
      );
      final harness = await _CallHarness.create(
        buildRoom: (room) async {
          // The backend enables media and joins the LiveKit room before the
          // session object exists, so events in this window predate the
          // session's listener. Nothing buffers them.
          await room.emit(
            lk.TrackPublishedEvent(
              participant: carol,
              publication: carolCamera,
            ),
          );
        },
      );

      expect(harness.livekitRoom.eventsDroppedWithoutListener, hasLength(1));
      expect(harness.session.streams.map((stream) => stream.streamId), <String>[
        'pub-bob-microphone',
      ]);

      // Counterfactual: the same event, delivered once a listener exists,
      // does produce the stream. The loss is purely one of timing.
      harness.livekitRoom.addRemoteParticipant(carol);
      await harness.livekitRoom.replayDroppedEvents();

      expect(
        harness.session.streams.map((stream) => stream.streamId),
        containsAll(<String>['pub-bob-microphone', 'pub-carol-camera']),
      );
    });

    test('a muted track under an unmuted publication is expressible end to '
        'end', () async {
      final microphoneTrack = FakeLocalAudioTrack();
      final microphonePublication =
          FakeLocalTrackPublication<lk.LocalAudioTrack>(
            sid: 'pub-alice-microphone',
            kind: lk.TrackType.AUDIO,
          );
      final harness = await _CallHarness.create(
        localParticipant: FakeLocalParticipant(
          identity: '@alice:example.org:ALICEDEVICE',
          publications: <lk.LocalTrackPublication>[microphonePublication],
        ),
      );

      // P0-4 in three lines. A full LiveKit reconnect rebuilds the publication
      // around the *same* already-muted track object with its own `muted`
      // metadata unset. The app's drift reconciler then calls
      // `updateMuted(true)`, which the edge-trigger swallows because the track
      // is already muted - so no event fires and nothing ever writes the
      // publication's flag.
      microphoneTrack.setMuted(true);
      microphonePublication.setTrack(microphoneTrack);
      microphoneTrack.updateMuted(true);

      expect(microphoneTrack.updateMutedCalls, <bool>[true]);
      expect(
        microphoneTrack.mutedChangeNotifications,
        0,
        reason: 'the edge-trigger swallowed it, so no event was emitted',
      );
      expect(microphonePublication.muted, isFalse);

      // KNOWN LIMITATION (P0-4, local-publication lane): this pair of
      // expectations locks in the DEFECTIVE state on purpose - the UI shows a
      // live microphone while the track sends nothing. It is asserted so the
      // divergence is visible in the suite rather than silent. When P0-4 is
      // fixed so the publication flag stops diverging from the track, this
      // expectation SHOULD fail and be rewritten to assert
      // `isMicrophoneMuted == true`. Do not "repair" it to keep the suite
      // green. Same marker shape as participant_loudness_monitor_test.dart.
      expect(
        harness.session.isMicrophoneMuted,
        isFalse,
        reason:
            'isMicrophoneMuted reports the microphone publication, and no '
            'sender is attached here to contradict it, so the UI renders the '
            'mic as live',
      );
      expect(
        harness.session.streams
            .firstWhere((stream) => stream.streamId == 'pub-alice-microphone')
            .isMuted,
        isTrue,
        reason: 'the track itself is muted, so nothing is being sent',
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

class _CallHarness {
  _CallHarness._({
    required this.matrixRoom,
    required this.livekitRoom,
    required this.bobMicrophone,
    required this.session,
  });

  final FakeCallMatrixRoom matrixRoom;
  final FakeLiveKitRoom livekitRoom;
  final FakeRemoteTrackPublication<lk.RemoteAudioTrack> bobMicrophone;
  final MatrixLivekitVoipSession session;

  /// Builds a one-remote-participant call and constructs the real session
  /// around it.
  ///
  /// [buildRoom] runs against the LiveKit room *before* the session exists,
  /// which is the only way to reach the pre-listener window.
  static Future<_CallHarness> create({
    lk.LocalParticipant? localParticipant,
    Future<void> Function(FakeLiveKitRoom room)? buildRoom,
  }) async {
    final bobMicrophone = FakeRemoteTrackPublication<lk.RemoteAudioTrack>(
      sid: 'pub-bob-microphone',
      kind: lk.TrackType.AUDIO,
    );
    final bob = FakeRemoteParticipant(
      identity: _bobIdentity,
      publications: <lk.RemoteTrackPublication>[bobMicrophone],
    );
    final livekitRoom = FakeLiveKitRoom(
      localParticipant: localParticipant,
      remoteParticipants: <lk.RemoteParticipant>[bob],
    );

    if (buildRoom != null) {
      await buildRoom(livekitRoom);
    }

    final matrixRoom = FakeCallMatrixRoom();
    final session = MatrixLivekitVoipSession(
      matrixRoom,
      livekitRoom,
      stateKey: _aliceStateKey,
      foci: <Uri>[Uri.parse('https://livekit.example.org')],
    );

    // Hang-up is memoised, so this is safe even for the test that hangs up
    // itself. It cancels the session's five periodic timers.
    addTearDown(session.hangUpCall);

    return _CallHarness._(
      matrixRoom: matrixRoom,
      livekitRoom: livekitRoom,
      bobMicrophone: bobMicrophone,
      session: session,
    );
  }
}
