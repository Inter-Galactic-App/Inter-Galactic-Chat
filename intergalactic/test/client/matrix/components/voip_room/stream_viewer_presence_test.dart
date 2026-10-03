import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/stream_viewer_presence.dart';

void main() {
  test('viewer intent targets only publishers of watched shares', () {
    final grouped = groupWatchedScreenSharesByPublisher(
      remoteShares: [
        (streamId: 'share-a', publisherIdentity: 'alice-device'),
        (streamId: 'share-b', publisherIdentity: 'alice-device'),
        (streamId: 'share-c', publisherIdentity: 'bob-device'),
      ],
      watchedIds: {'share-a', 'share-c', 'unknown'},
    );
    expect(grouped, {
      'alice-device': {'share-a'},
      'bob-device': {'share-c'},
    });
  });

  test('viewer intent round-trips and rejects malformed or oversized data', () {
    final intent = StreamViewerIntent({'share-a', 'share-b'});
    expect(
      StreamViewerIntent.decode(
        streamViewerIntentTopic,
        intent.encode(),
      )?.streamIds,
      {'share-a', 'share-b'},
    );
    expect(StreamViewerIntent.decode('other-topic', intent.encode()), isNull);
    expect(StreamViewerIntent.decode(streamViewerIntentTopic, [123]), isNull);
    expect(
      StreamViewerIntent.decode(streamViewerIntentTopic, List.filled(2049, 0)),
      isNull,
    );
  });

  test('only published local shares can gain a watcher', () {
    final presence = StreamViewerPresence();
    final now = DateTime.utc(2026, 9, 27);
    expect(
      presence.update(
        participantIdentity: '@viewer:example.org:DEVICE',
        publishedStreamIds: {'local-share'},
        reportedStreamIds: {'remote-share'},
        now: now,
      ),
      isFalse,
    );
    expect(presence.viewerIdentities, isEmpty);
    expect(
      presence.update(
        participantIdentity: '@viewer:example.org:DEVICE',
        publishedStreamIds: {'local-share'},
        reportedStreamIds: {'local-share', 'remote-share'},
        now: now,
      ),
      isTrue,
    );
    expect(presence.viewerIdentities, {'@viewer:example.org:DEVICE'});
  });

  test('heartbeats refresh expiry without changing the visible list', () {
    final presence = StreamViewerPresence();
    final now = DateTime.utc(2026, 9, 27);
    const identity = '@viewer:example.org:DEVICE';
    final shares = {'share-a'};
    presence.update(
      participantIdentity: identity,
      publishedStreamIds: shares,
      reportedStreamIds: shares,
      now: now,
    );
    expect(
      presence.update(
        participantIdentity: identity,
        publishedStreamIds: shares,
        reportedStreamIds: shares,
        now: now.add(const Duration(seconds: 30)),
      ),
      isFalse,
    );
    expect(
      presence.prune(
        publishedStreamIds: shares,
        now: now.add(const Duration(seconds: 50)),
      ),
      isFalse,
    );
    expect(
      presence.prune(
        publishedStreamIds: shares,
        now: now.add(const Duration(seconds: 76)),
      ),
      isTrue,
    );
    expect(presence.viewerIdentities, isEmpty);
  });

  test('stop, unpublish, and disconnect clear only the affected viewer', () {
    final presence = StreamViewerPresence();
    final now = DateTime.utc(2026, 9, 27);
    for (final identity in ['viewer-a', 'viewer-b']) {
      presence.update(
        participantIdentity: identity,
        publishedStreamIds: {'share-a', 'share-b'},
        reportedStreamIds: {identity == 'viewer-a' ? 'share-a' : 'share-b'},
        now: now,
      );
    }
    expect(presence.prune(publishedStreamIds: {'share-b'}, now: now), isTrue);
    expect(presence.viewerIdentities, {'viewer-b'});
    expect(presence.removeParticipant('viewer-b'), isTrue);
    expect(presence.viewerIdentities, isEmpty);
  });
}
