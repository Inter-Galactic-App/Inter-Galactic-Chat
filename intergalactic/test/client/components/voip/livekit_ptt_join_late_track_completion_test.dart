// What happens to a Push to Talk join microphone create/publish that finishes
// AFTER its timeout.
//
// `Future.timeout` abandons the future it wraps; it cannot cancel it, because
// a `Future` has no cancel. So on a slow Windows microphone both native calls
// in `_publishInitialMicrophoneMutedForPushToTalk` can still be running after
// the join has given up on them, and each one produces an orphan if nothing
// is watching:
//
// * the create hands back a `LocalAudioTrack` whose native capture is open and
//   which no field on the backend holds, so the device stays claimed for the
//   rest of the call;
// * the publish hands back a `LocalTrackPublication` that nothing armed, while
//   the settled outcome says no publication was made.
//
// These drive the real method through
// `debugPublishInitialMicrophoneMutedForPushToTalkForTesting` and hold the
// native calls open with `Completer`s, so the assertions are on what the
// production observers did, not on a helper called in isolation.
//
// What they CANNOT prove: nothing here touches a real microphone, a real
// `MediaStreamTrack` or a real SFU. `FakeLocalAudioTrack.stop()` flips a bool.
// That the app now ASKS for the capture to be released is testable at this
// level; that Windows actually releases it is not.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'fakes/voip_fakes.dart';

const _aliceIdentity = '@alice:example.org:ALICEDEVICE';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MatrixLivekitBackend backend;
  late FakeLocalParticipant participant;
  late MatrixLivekitInitialMicrophoneEnableState enableState;

  setUp(() {
    backend = MatrixLivekitBackend(FakeCallMatrixRoom());
    participant = FakeLocalParticipant(identity: _aliceIdentity);
    enableState = MatrixLivekitInitialMicrophoneEnableState();
    // Short enough that a test can outlast it, long enough that the create and
    // the publish are not racing it in the tests that must NOT time out.
    MatrixLivekitBackend.debugPushToTalkJoinMicrophoneTimeoutForTesting =
        const Duration(milliseconds: 40);
  });

  tearDown(() {
    MatrixLivekitBackend.debugPushToTalkJoinMicrophoneTimeoutForTesting = null;
    MatrixLivekitBackend.debugLocalAudioTrackFactoryForTesting = null;
  });

  Future<void> runJoinPublish() =>
      backend.debugPublishInitialMicrophoneMutedForPushToTalkForTesting(
        participant,
        audioCaptureOptions: const lk.AudioCaptureOptions(),
        initialMicrophoneEnableState: enableState,
      );

  FakeLocalTrackPublication<lk.LocalAudioTrack> microphonePublication(
    FakeLocalAudioTrack track, {
    String sid = 'pub-ptt-join',
  }) => FakeLocalTrackPublication<lk.LocalAudioTrack>(
    sid: sid,
    kind: lk.TrackType.AUDIO,
    track: track,
  );

  group('Push to Talk join microphone create that lands after its timeout', () {
    test('the orphaned capture is stopped rather than left owning the '
        'device', () async {
      final createCompleter = Completer<lk.LocalAudioTrack>();
      MatrixLivekitBackend.debugLocalAudioTrackFactoryForTesting = (_) =>
          createCompleter.future;

      await runJoinPublish();

      expect(
        enableState.initialEnableOutcome,
        'timed_out_push_to_talk_join_create',
        reason:
            'a timeout is not a finished failure - the create is still '
            'running, so the outcome must not claim either a publication or a '
            'settled failure',
      );

      // The create only NOW comes back, which is the whole point: on Windows
      // this is seconds after the join gave up.
      final lateTrack = FakeLocalAudioTrack();
      expect(lateTrack.isActive, isTrue, reason: 'premise: capture is open');
      createCompleter.complete(lateTrack);
      await pumpEventQueue();

      expect(
        lateTrack.isActive,
        isFalse,
        reason:
            'nothing else holds this track - the backend left `track` null - '
            'so if the observer does not stop it the native capture owns the '
            'microphone for the rest of the call',
      );
      expect(
        participant.getTrackPublicationBySource(lk.TrackSource.microphone),
        isNull,
        reason: 'the publish was never reached',
      );
    });

    test('a create that fails after its timeout is absorbed, not rethrown into '
        'the zone', () async {
      final createCompleter = Completer<lk.LocalAudioTrack>();
      MatrixLivekitBackend.debugLocalAudioTrackFactoryForTesting = (_) =>
          createCompleter.future;

      await runJoinPublish();
      expect(
        enableState.initialEnableOutcome,
        'timed_out_push_to_talk_join_create',
      );

      createCompleter.completeError(
        StateError('getUserMedia gave up late'),
        StackTrace.current,
      );
      // If the late error were unhandled it would fail this test through the
      // zone rather than through an expectation.
      await pumpEventQueue();
    });
  });

  group('Push to Talk join microphone publish that lands after its timeout', () {
    test(
      'the late publication is unpublished and the capture released',
      () async {
        final track = FakeLocalAudioTrack();
        MatrixLivekitBackend.debugLocalAudioTrackFactoryForTesting =
            (_) async => track;
        final publishCompleter =
            Completer<lk.LocalTrackPublication<lk.LocalAudioTrack>>();
        participant.onPublishAudioTrack = (_) => publishCompleter.future;

        await runJoinPublish();

        expect(
          enableState.initialEnableOutcome,
          'timed_out_push_to_talk_join_publish',
        );
        expect(
          track.isActive,
          isFalse,
          reason:
              'the device is released as soon as the publish outruns its budget '
              'rather than waiting on a publish that may never return',
        );

        final publication = microphonePublication(track, sid: 'pub-late');
        // Mirrors `addTrackPublication` at livekit_client-2.5.4
        // `participant/local.dart:187`: the publication exists in the room
        // before `publishAudioTrack` returns.
        participant.addPublication(publication);
        publishCompleter.complete(publication);
        await pumpEventQueue();

        expect(
          participant.removePublishedTrackCalls,
          ['pub-late'],
          reason:
              'the join settled `timed_out_...`, so a publication left in the '
              'room is one the session believes does not exist',
        );
        expect(
          participant.getTrackPublicationBySource(lk.TrackSource.microphone),
          isNull,
        );
      },
    );

    test('the catch does NOT report a publication just because the SDK had '
        'already registered one', () async {
      // The finding claimed `getTrackPublicationBySource` "returns null while
      // the publish is still in flight". It does not have to:
      // `publishAudioTrack` registers the publication partway through
      // (`participant/local.dart:187`) and then keeps awaiting
      // `track.onPublish()`, `room.applyAudioSpeakerSettings()` and
      // `track.start()`. A timeout landing in that tail finds the publication
      // present - and the old catch then reported
      // `published_muted_push_to_talk_join` for a publish that had NOT
      // finished and was about to be rolled back.
      final track = FakeLocalAudioTrack();
      MatrixLivekitBackend.debugLocalAudioTrackFactoryForTesting = (_) async =>
          track;
      final publication = microphonePublication(track, sid: 'pub-registered');
      final publishCompleter =
          Completer<lk.LocalTrackPublication<lk.LocalAudioTrack>>();
      participant.onPublishAudioTrack = (_) {
        participant.addPublication(publication);
        return publishCompleter.future;
      };

      await runJoinPublish();

      expect(
        participant.getTrackPublicationBySource(lk.TrackSource.microphone),
        isNotNull,
        reason:
            'the premise: mid-publish the publication IS visible, so a read '
            'here answers "where did the timeout land", not "was anything '
            'published"',
      );
      expect(
        enableState.initialEnableOutcome,
        'timed_out_push_to_talk_join_publish',
        reason:
            'reporting `published_` here would hand the sender-reconcile '
            'diagnostics a publication that the rollback below then removes',
      );

      publishCompleter.complete(publication);
      await pumpEventQueue();

      expect(participant.removePublishedTrackCalls, ['pub-registered']);
    });

    test('a publish that fails after its timeout is absorbed, not rethrown '
        'into the zone', () async {
      // The publish group only ever completed the abandoned future WITH a
      // publication, so the error arm of its observer was never entered. It is
      // the same abandoned-future path: `Future.timeout` cannot cancel
      // `publishAudioTrack`, so a publish that is going to fail keeps running
      // after the join gave up, and the failure lands on a future nothing is
      // awaiting. Without an `onError` on that observer it is an unhandled
      // asynchronous error, which on the join path means a crash report for a
      // call that recovered.
      final track = FakeLocalAudioTrack();
      MatrixLivekitBackend.debugLocalAudioTrackFactoryForTesting = (_) async =>
          track;
      final publishCompleter =
          Completer<lk.LocalTrackPublication<lk.LocalAudioTrack>>();
      participant.onPublishAudioTrack = (_) => publishCompleter.future;

      await runJoinPublish();
      expect(
        enableState.initialEnableOutcome,
        'timed_out_push_to_talk_join_publish',
        reason: 'arms the check: the observer acts only once the timeout fired',
      );

      publishCompleter.completeError(
        StateError('the SFU rejected the track late'),
        StackTrace.current,
      );
      // If the late error were unhandled it would fail this test through the
      // zone rather than through an expectation.
      await pumpEventQueue();

      expect(
        participant.removePublishedTrackCalls,
        isEmpty,
        reason:
            'there is no publication to roll back, so an observer that treats '
            'the failure as an arrival unpublishes a sid that does not exist',
      );
      expect(
        track.isActive,
        isFalse,
        reason:
            'the timeout already released the device; a failing publish must '
            'not reopen it',
      );
    });

    test(
      'the capture is released even when the unpublish itself fails',
      () async {
        final track = FakeLocalAudioTrack();
        MatrixLivekitBackend.debugLocalAudioTrackFactoryForTesting =
            (_) async => track;
        final publishCompleter =
            Completer<lk.LocalTrackPublication<lk.LocalAudioTrack>>();
        participant.onPublishAudioTrack = (_) => publishCompleter.future;
        participant.removePublishedTrackError = StateError('room is gone');

        await runJoinPublish();
        // Re-open the capture so the assertion below is about the ROLLBACK's
        // stop, not the one the catch already did.
        await track.start();
        expect(track.isActive, isTrue);

        final publication = microphonePublication(track, sid: 'pub-late');
        participant.addPublication(publication);
        publishCompleter.complete(publication);
        await pumpEventQueue();

        expect(participant.removePublishedTrackCalls, ['pub-late']);
        expect(
          track.isActive,
          isFalse,
          reason:
              'releasing the device must not depend on the room agreeing to the '
              'unpublish',
        );
      },
    );
  });

  group('the happy path is untouched', () {
    test('a create and publish that finish in time are neither stopped nor '
        'unpublished', () async {
      // The 40 ms budget in `setUp` exists so the groups above can outlast it.
      // This test asserts the opposite - that the create and the publish
      // finish INSIDE it - and it is the only test here racing a real timer it
      // is meant to beat. A loaded machine that takes 40 ms to run two
      // `async` fakes turns this into `timed_out_push_to_talk_join_publish`,
      // which reads as the production regression this file was written to
      // catch rather than as the machine being busy.
      MatrixLivekitBackend.debugPushToTalkJoinMicrophoneTimeoutForTesting =
          const Duration(seconds: 30);

      final track = FakeLocalAudioTrack();
      MatrixLivekitBackend.debugLocalAudioTrackFactoryForTesting = (_) async =>
          track;
      final publication = microphonePublication(track, sid: 'pub-ok');
      participant.onPublishAudioTrack = (_) async {
        participant.addPublication(publication);
        return publication;
      };

      await runJoinPublish();

      expect(
        enableState.initialEnableOutcome,
        'published_muted_push_to_talk_join',
      );

      // Give both observers every chance to misfire.
      await pumpEventQueue();

      expect(
        track.isActive,
        isTrue,
        reason:
            'an observer that acts without checking whether the timeout fired '
            'would stop the microphone of a join that worked',
      );
      expect(participant.removePublishedTrackCalls, isEmpty);
      expect(
        participant.getTrackPublicationBySource(lk.TrackSource.microphone),
        same(publication),
      );
    });
  });
}
