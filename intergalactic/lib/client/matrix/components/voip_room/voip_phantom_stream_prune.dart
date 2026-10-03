/// Pure prune decision for phantom remote streams (BUG-321).
///
/// A participant on a poor connection can have LiveKit re-publish their
/// microphone under a NEW track sid when their connection cycles, without a
/// clean `TrackUnpublishedEvent` reaching every observer - the SDK and the
/// session both document that publish/unpublish events are dropped while a
/// room is `connecting`/`reconnecting`. The observer's `streams` list then
/// keeps the old sid alongside the new one: the sender sees themselves
/// streaming once, every observer sees the tile two or more times, and only
/// the newest sid carries media.
///
/// The periodic remote-media reconciler already ADDS and repairs streams for
/// live publications, but it only ever removed a stream through an SDK event
/// or a participant disconnect - never for a publication that simply vanished
/// under a still-connected identity. This is that missing prune, kept pure so
/// it can be tested without a live room.
///
/// The condition is deliberately tight: a stream is phantom only when its
/// participant is STILL connected (present in the sweep snapshot) yet none of
/// that participant's current publications carry the stream's sid. A
/// participant absent from the snapshot - fully gone, or momentarily missing
/// mid-reconnect - is left to `onParticipantDisconnected` and the next sweep,
/// so a transient reconnect can never prune live tiles.
Set<String> phantomIncomingStreamSidsToPrune({
  required Map<String, Set<String>> liveSidsByConnectedIdentity,
  required Iterable<PhantomStreamCandidate> streams,
}) {
  final prune = <String>{};
  for (final stream in streams) {
    if (!stream.incoming) {
      // Outgoing (local) streams are the app's own publications, not remote
      // snapshot state; never prune them from here.
      continue;
    }
    final liveSids = liveSidsByConnectedIdentity[stream.participantIdentity];
    if (liveSids == null) {
      continue;
    }
    if (!liveSids.contains(stream.sid)) {
      prune.add(stream.sid);
    }
  }
  return prune;
}

/// Whether a reconciler repair may still build a session stream for the
/// publication it was decided for (BUG-321, origin).
///
/// A repair runs across await points - `publication.subscribe()`,
/// `enable()`, an audio-flow sample - and the publication it was decided for
/// can be unpublished in between. The unpublish handler removes the stream,
/// then the in-flight repair puts it back; and because the SDK has already
/// dropped the publication, no second `TrackUnpublishedEvent` can ever arrive
/// to clean the re-added stream up. It is stranded for the rest of the call.
/// So a repair must re-read the participant's LIVE publications rather than
/// trust the snapshot its sweep started from.
bool mayBuildStreamForPublication({
  required Set<String> participantPublicationSids,
  required String publicationSid,
}) {
  return participantPublicationSids.contains(publicationSid);
}

/// The diagnostics-export line for one session stream (BUG-321). Pure so the
/// shape a capture reader greps for is pinned by a test: a phantom is
/// `publication_live=false owner_connected=true`.
String describeSessionStreamForDiagnostics({
  required String sid,
  required String redactedOwner,
  required String type,
  required String direction,
  required bool publicationLive,
  required bool trackAttached,
  required bool ownerConnected,
}) {
  return 'stream sid=$sid owner=$redactedOwner type=$type '
      'direction=$direction publication_live=$publicationLive '
      'track_attached=$trackAttached owner_connected=$ownerConnected';
}

/// The minimal view of a session stream the prune decision needs.
class PhantomStreamCandidate {
  const PhantomStreamCandidate({
    required this.sid,
    required this.participantIdentity,
    required this.incoming,
  });

  final String sid;
  final String participantIdentity;
  final bool incoming;
}
