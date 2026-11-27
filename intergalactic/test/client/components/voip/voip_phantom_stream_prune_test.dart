import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/voip_phantom_stream_prune.dart';

/// BUG-321: a poorly-connected participant's connection cycles, LiveKit
/// republishes their microphone under a new track sid, and the old sid lingers
/// in an observer's stream list because the `TrackUnpublishedEvent` was
/// dropped during the reconnect. Every observer then sees the participant's
/// tile two or more times, only the newest carrying media.
///
/// WHAT WOULD MAKE THIS WRONG: pruning on "sid absent from the snapshot" alone
/// would drop live tiles during a reconnect, when a participant is briefly
/// missing from the snapshot. So the decision fires ONLY when the participant
/// is still present and the sid is gone from THAT participant's live set, and
/// these tests pin both halves.
void main() {
  PhantomStreamCandidate incoming(String sid, String identity) =>
      PhantomStreamCandidate(
        sid: sid,
        participantIdentity: identity,
        incoming: true,
      );

  test('prunes the stale sid of a still-connected participant who '
      'republished under a new sid', () {
    final prune = phantomIncomingStreamSidsToPrune(
      liveSidsByConnectedIdentity: {
        'flaky@dev': {'TR_new'},
      },
      streams: [
        incoming('TR_old', 'flaky@dev'),
        incoming('TR_new', 'flaky@dev'),
      ],
    );
    expect(prune, {
      'TR_old',
    }, reason: 'only the vanished sid, not the live one');
  });

  test('keeps every stream of a participant absent from the snapshot', () {
    // Mid-reconnect the participant is not in remoteParticipants yet. Leave
    // their tiles to onParticipantDisconnected / the next sweep.
    final prune = phantomIncomingStreamSidsToPrune(
      liveSidsByConnectedIdentity: const {},
      streams: [incoming('TR_old', 'flaky@dev')],
    );
    expect(prune, isEmpty);
  });

  test('keeps a healthy participant whose sid is still live', () {
    final prune = phantomIncomingStreamSidsToPrune(
      liveSidsByConnectedIdentity: {
        'a@dev': {'TR_a'},
        'b@dev': {'TR_b'},
      },
      streams: [incoming('TR_a', 'a@dev'), incoming('TR_b', 'b@dev')],
    );
    expect(prune, isEmpty);
  });

  test(
    'never prunes an outgoing (local) stream even if its sid is unknown',
    () {
      final prune = phantomIncomingStreamSidsToPrune(
        liveSidsByConnectedIdentity: {
          'me@dev': {'TR_remote'},
        },
        streams: [
          const PhantomStreamCandidate(
            sid: 'TR_local',
            participantIdentity: 'me@dev',
            incoming: false,
          ),
        ],
      );
      expect(prune, isEmpty);
    },
  );

  test('prunes multiple stale sids across participants in one pass', () {
    final prune = phantomIncomingStreamSidsToPrune(
      liveSidsByConnectedIdentity: {
        'a@dev': {'TR_a2'},
        'b@dev': {'TR_b2'},
      },
      streams: [
        incoming('TR_a1', 'a@dev'),
        incoming('TR_a2', 'a@dev'),
        incoming('TR_b1', 'b@dev'),
        incoming('TR_b2', 'b@dev'),
      ],
    );
    expect(prune, {'TR_a1', 'TR_b1'});
  });

  test('diagnostics line names a phantom as live=false with its owner still '
      'connected', () {
    final line = describeSessionStreamForDiagnostics(
      sid: 'TR_old',
      redactedOwner: 'abc123',
      type: 'screenshare',
      direction: 'incoming',
      publicationLive: false,
      trackAttached: false,
      ownerConnected: true,
    );
    expect(line, contains('sid=TR_old'));
    expect(line, contains('owner=abc123'));
    expect(line, contains('publication_live=false'));
    expect(line, contains('owner_connected=true'));
  });

  test('a repair may not build a stream for a publication the participant no '
      'longer has', () {
    expect(
      mayBuildStreamForPublication(
        participantPublicationSids: {'TR_new'},
        publicationSid: 'TR_old',
      ),
      isFalse,
    );
    expect(
      mayBuildStreamForPublication(
        participantPublicationSids: {'TR_new', 'TR_old'},
        publicationSid: 'TR_old',
      ),
      isTrue,
    );
  });
}
