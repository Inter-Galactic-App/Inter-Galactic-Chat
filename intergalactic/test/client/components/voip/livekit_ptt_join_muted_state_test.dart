// What `publication.muted` actually is after a Push to Talk join.
//
// This exists to settle a disagreement rather than to guard a behaviour, and
// the disagreement was between two agents who each read the code and reached
// opposite conclusions:
//
// * The queue row "Every Windows Push to Talk join logs a drift warning" says
//   `publication.muted` is left FALSE, because BUG-322's design deliberately
//   does not call `publication.mute()`. On that premise
//   `shouldReconcileMutedPublication` - `_callActive && !desiredEnabled &&
//   !publicationMuted` - fires on every PTT join.
// * `agent/voip-debug-integration`'s `e6c38739` says the opposite: "after the
//   Push to Talk join, setDetached has set publication.muted true, so the
//   reconcile observes and logs the join state without acting on it".
//
// The existing test `a Push to Talk join is not unmuted by the join-time
// reconcile` cannot settle it, because it CONSTRUCTS its publication with
// `muted: false`. That is a fixture choice, not a fact about what the arm path
// produces - and a fixture is exactly what neither reading needed.
//
// So these tests drive `armPushToTalkJoinPublication` itself and then look at
// the publication, for each of the three sender states the arm can meet. The
// sender state is the variable that matters: `attachmentOf` documents `unknown`
// as the NORMAL state for a publication still being negotiated, which is
// precisely when the join-time arm runs.
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_microphone_sender_gate.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'fakes/fake_livekit_publications.dart';
import 'fakes/fake_livekit_tracks.dart';

void main() {
  FakeLocalTrackPublication<lk.LocalAudioTrack> publicationFor(
    FakeLocalAudioTrack track, {
    required bool muted,
  }) {
    return FakeLocalTrackPublication<lk.LocalAudioTrack>(
      sid: 'pub-ptt-join',
      kind: lk.TrackType.AUDIO,
      track: track,
      muted: muted,
    );
  }

  group('Push to Talk join arm: what it leaves publication.muted as', () {
    test('with no sender yet - the normal just-published state - muted is set '
        'TRUE and the track is not enabled', () async {
      final track = FakeLocalAudioTrack();
      // Deliberately no sender: `transceiver?.sender` is null until the track
      // is negotiated, and the join-time arm runs before that has settled.
      final publication = publicationFor(track, muted: false);

      final armed =
          await LivekitMicrophoneSenderGate.armPushToTalkJoinPublication(
            publication: publication,
            track: track,
            source: 'test',
          );

      expect(
        publication.muted,
        isTrue,
        reason:
            'setDetached keeps the muted metadata truthful when there is no '
            'sender to move, because that flag is the only thing remote '
            'participants can see',
      );
      expect(
        armed.trackEnabled,
        isFalse,
        reason:
            'the sender is not KNOWN detached, so re-enabling the capture '
            'track here would be a live microphone behind a muted indicator',
      );
      expect(armed.attachment, LivekitMicrophoneSenderAttachment.unknown);
    });

    test('with a sender already carrying nothing, muted is TRUE and the track '
        'is enabled', () async {
      final track = FakeLocalAudioTrack();
      track.attachDetachedSender();
      final publication = publicationFor(track, muted: false);

      final armed =
          await LivekitMicrophoneSenderGate.armPushToTalkJoinPublication(
            publication: publication,
            track: track,
            source: 'test',
          );

      expect(publication.muted, isTrue);
      expect(
        armed.trackEnabled,
        isTrue,
        reason:
            'the sender is known detached, so the track can be enabled and the '
            'first Push to Talk press carries live audio',
      );
    });

    test('with a sender carrying the track, muted is TRUE after the arm moves '
        'it', () async {
      final track = FakeLocalAudioTrack();
      track.attachSender();
      final publication = publicationFor(track, muted: false);

      final armed =
          await LivekitMicrophoneSenderGate.armPushToTalkJoinPublication(
            publication: publication,
            track: track,
            source: 'test',
          );

      expect(publication.muted, isTrue);
      expect(armed.senderMoved, isTrue);
    });

    test('so the join-time reconcile does NOT see drift on a Push to Talk '
        'join', () {
      // The whole point of settling this. `shouldReconcileMutedPublication` is
      // `_callActive && !_desiredMicrophoneEnabled && !publicationMuted`. The
      // arm leaves `publication.muted` true in every sender state above, so
      // the third conjunct is false and the mute direction does not fire.
      //
      // Asserted here as the predicate's own arithmetic rather than through a
      // session, because the session route is what the fixture-based test
      // already covers and it is the PREMISE that was in dispute.
      //
      // This one is arithmetic on constants and survives every mutation, on
      // purpose - it is a statement of the consequence, not a guard. The three
      // tests above are the guard: suppressing every `track.updateMuted` call
      // in the gate turns all three red and leaves this one green, which is
      // exactly the split to expect and the reason it is labelled here.
      const publicationMutedAfterArm = true;
      const callActive = true;
      const desiredMicrophoneEnabled = false;

      final wouldReportDrift =
          callActive && !desiredMicrophoneEnabled && !publicationMutedAfterArm;

      expect(
        wouldReportDrift,
        isFalse,
        reason:
            'if this ever becomes true, the queue row about a per-join drift '
            'warning is correct again and should be reopened',
      );
    });
  });
}
