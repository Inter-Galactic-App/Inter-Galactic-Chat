import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/demo/demo_client.dart';

void main() {
  group('storyImageSizeIsAllowed', () {
    test('accepts non-negative sizes up to the story image limit', () {
      expect(storyImageSizeIsAllowed(0), isTrue);
      expect(storyImageSizeIsAllowed(storyMaxImageBytes), isTrue);
    });

    test('rejects negative and oversized images', () {
      expect(storyImageSizeIsAllowed(-1), isFalse);
      expect(storyImageSizeIsAllowed(storyMaxImageBytes + 1), isFalse);
    });
  });

  group('pending story uploads', () {
    test('tracks current user upload state while a share is in flight',
        () async {
      final client = DemoClient.createOfflineDemo();
      addTearDown(client.close);
      final stories = client.getComponent<StoryComponent>()!;
      final ownUserId = client.self!.identifier;
      final started = Completer<void>();
      final release = Completer<void>();

      final tracked = stories.trackPendingStoryUpload(() async {
        started.complete();
        await release.future;
        return 'done';
      });
      await started.future;

      expect(stories.hasPendingStoryUpload(ownUserId), isTrue);
      expect(
        stories.hasPendingStoryUpload('@mira:intergalactic.local'),
        isFalse,
      );

      release.complete();
      expect(await tracked, 'done');
      expect(stories.hasPendingStoryUpload(ownUserId), isFalse);
    });
  });

  group('StoryUploadResult', () {
    test('only reports sentAll for fully delivered uploads', () {
      expect(
        const StoryUploadResult(
          storyCount: 1,
          sentEventCount: 2,
          targetRoomCount: 2,
          failedEventCount: 0,
        ).sentAll,
        isTrue,
      );
      expect(
        const StoryUploadResult(
          storyCount: 1,
          sentEventCount: 1,
          targetRoomCount: 2,
          failedEventCount: 1,
        ).sentAll,
        isFalse,
      );
    });

    test('keeps the retry cursor on a mixed fail-then-success outcome', () {
      const firstFailedUpload = StoryUploadResult(
        storyCount: 1,
        sentEventCount: 1,
        targetRoomCount: 2,
        failedEventCount: 1,
      );
      const laterSuccessfulUpload = StoryUploadResult(
        storyCount: 1,
        sentEventCount: 2,
        targetRoomCount: 2,
        failedEventCount: 0,
      );
      final combined = StoryUploadResult(
        storyCount:
            firstFailedUpload.storyCount + laterSuccessfulUpload.storyCount,
        sentEventCount: firstFailedUpload.sentEventCount +
            laterSuccessfulUpload.sentEventCount,
        targetRoomCount: firstFailedUpload.targetRoomCount +
            laterSuccessfulUpload.targetRoomCount,
        failedEventCount: firstFailedUpload.failedEventCount +
            laterSuccessfulUpload.failedEventCount,
      );

      expect(
        laterSuccessfulUpload.nextRetryIndexAfter(0),
        1,
      );
      expect(
        firstFailedUpload.nextRetryIndexAfter(1),
        1,
      );
      expect(combined.sentAll, isFalse);
      expect(combined.failedEventCount, 1);
    });
  });

  group('parseStoryEventContent', () {
    test('accepts a valid v1 image story', () {
      final now = DateTime.utc(2026, 5, 29, 18);
      final parsed = parseStoryEventContent(
        _validStoryContent(now: now),
        now: now,
      );

      expect(parsed, isNotNull);
      expect(parsed!.storyId, 'story-1');
      expect(parsed.mediaType, StoryMediaType.image);
      expect(parsed.mediaUri.toString(), 'mxc://example.org/story-1');
      expect(parsed.encrypted, isFalse);
      expect(parsed.mentionedUserIds, isEmpty);
    });

    test('parses valid Matrix story mentions and ignores malformed ids', () {
      final now = DateTime.utc(2026, 5, 29, 18);
      final parsed = parseStoryEventContent(
        _validStoryContent(now: now)
          ..['m.mentions'] = {
            'user_ids': [
              '@bob:example.org',
              '@bob:example.org',
              'not-a-user',
              12,
            ],
          },
        now: now,
      );

      expect(parsed, isNotNull);
      expect(parsed!.mentionedUserIds, ['@bob:example.org']);
    });

    test('rejects expired stories', () {
      final now = DateTime.utc(2026, 5, 29, 18);
      final parsed = parseStoryEventContent(
        _validStoryContent(
          now: now,
          createdAt: now.subtract(const Duration(hours: 26)),
          expiresAt: now.subtract(const Duration(hours: 2)),
        ),
        now: now,
      );

      expect(parsed, isNull);
    });

    test('rejects malformed and non-image content', () {
      final now = DateTime.utc(2026, 5, 29, 18);

      expect(parseStoryEventContent({'v': 1}, now: now), isNull);
      expect(
        parseStoryEventContent(
          _validStoryContent(now: now)..['msgtype'] = 'm.video',
          now: now,
        ),
        isNull,
      );
      expect(
        parseStoryEventContent(
          _validStoryContent(now: now)
            ..['info'] = {
              'mimetype': 'application/pdf',
              'size': 1024,
            },
          now: now,
        ),
        isNull,
      );
      expect(
        parseStoryEventContent(
          _validStoryContent(now: now)..['url'] = 'mxc:missing-authority',
          now: now,
        ),
        isNull,
      );
      expect(
        parseStoryEventContent(
          _validStoryContent(now: now)..['url'] = 'mxc://example.org',
          now: now,
        ),
        isNull,
      );
    });

    test('rejects future-invalid and oversized entries', () {
      final now = DateTime.utc(2026, 5, 29, 18);

      expect(
        parseStoryEventContent(
          _validStoryContent(
            now: now,
            createdAt: now.add(const Duration(minutes: 10)),
            expiresAt: now.add(const Duration(hours: 2)),
          ),
          now: now,
        ),
        isNull,
      );

      expect(
        parseStoryEventContent(
          _validStoryContent(now: now)
            ..['info'] = {
              'mimetype': 'image/png',
              'size': storyMaxImageBytes + 1,
            },
          now: now,
        ),
        isNull,
      );
    });

    test('accepts encrypted Matrix file metadata without a plaintext url', () {
      final now = DateTime.utc(2026, 5, 29, 18);
      final content = _validStoryContent(now: now)
        ..remove('url')
        ..['file'] = {
          'url': 'mxc://example.org/encrypted-story',
          'mimetype': 'image/png',
          'v': 'v2',
          'key': {
            'alg': 'A256CTR',
            'ext': true,
            'k': 'abc',
            'key_ops': ['encrypt', 'decrypt'],
            'kty': 'oct',
          },
          'iv': 'iv',
          'hashes': {'sha256': 'hash'},
        };

      final parsed = parseStoryEventContent(content, now: now);

      expect(parsed, isNotNull);
      expect(parsed!.encrypted, isTrue);
      expect(parsed.mediaUri.toString(), 'mxc://example.org/encrypted-story');
    });
  });

  group('parseStoryVideoEventContent', () {
    test('accepts a valid v1 video story with trim and overlays', () {
      final now = DateTime.utc(2026, 6, 8, 14);
      final parsed = parseStoryVideoEventContent(
        _validVideoStoryContent(now: now),
        now: now,
      );

      expect(parsed, isNotNull);
      expect(parsed!.mediaType, StoryMediaType.video);
      expect(parsed.mediaUri.toString(), 'mxc://example.org/video-story-1');
      expect(parsed.durationMs, 24000);
      expect(parsed.trimStartMs, 0);
      expect(parsed.trimEndMs, 24000);
      expect(parsed.width, 1080);
      expect(parsed.height, 1920);
      expect(parsed.thumbnailUri.toString(), 'mxc://example.org/video-thumb-1');
      expect(parsed.backgroundColor, 0xFF10303A);
      expect(parsed.overlays, hasLength(2));
      expect(parsed.overlays.first.type, StoryMediaOverlayType.text);
      expect(parsed.overlays.last.type, StoryMediaOverlayType.emoji);
    });

    test('rejects overlong, oversized, and fake-trim video entries', () {
      final now = DateTime.utc(2026, 6, 8, 14);

      expect(
        parseStoryVideoEventContent(
          _validVideoStoryContent(now: now, durationMs: 31000),
          now: now,
        ),
        isNull,
      );
      expect(
        parseStoryVideoEventContent(
          _validVideoStoryContent(now: now, size: storyMaxVideoBytes + 1),
          now: now,
        ),
        isNull,
      );
      expect(
        parseStoryVideoEventContent(
          _validVideoStoryContent(now: now)
            ..['trim_end_ms'] = storyMaxVideoDuration.inMilliseconds + 1,
          now: now,
        ),
        isNull,
      );
      expect(
        parseStoryVideoEventContent(
          _validVideoStoryContent(now: now)..['url'] = 'mxc:missing-authority',
          now: now,
        ),
        isNull,
      );
    });

    test('accepts encrypted video metadata without a plaintext url', () {
      final now = DateTime.utc(2026, 6, 8, 14);
      final content = _validVideoStoryContent(now: now)
        ..remove('url')
        ..['file'] = {
          'url': 'mxc://example.org/encrypted-video-story',
          'mimetype': 'video/mp4',
          'v': 'v2',
          'key': {
            'alg': 'A256CTR',
            'ext': true,
            'k': 'abc',
            'key_ops': ['encrypt', 'decrypt'],
            'kty': 'oct',
          },
          'iv': 'iv',
          'hashes': {'sha256': 'hash'},
        };

      final parsed = parseStoryVideoEventContent(content, now: now);

      expect(parsed, isNotNull);
      expect(parsed!.encrypted, isTrue);
      expect(
        parsed.mediaUri.toString(),
        'mxc://example.org/encrypted-video-story',
      );
    });

    test('accepts encrypted video thumbnail metadata', () {
      final now = DateTime.utc(2026, 6, 8, 14);
      final content = _validVideoStoryContent(now: now);
      final info = content['info'] as Map<String, Object?>;
      info
        ..remove('thumbnail_url')
        ..['thumbnail_file'] = {
          'url': 'mxc://example.org/encrypted-video-thumb',
          'mimetype': 'image/png',
          'v': 'v2',
          'key': {
            'alg': 'A256CTR',
            'ext': true,
            'k': 'abc',
            'key_ops': ['encrypt', 'decrypt'],
            'kty': 'oct',
          },
          'iv': 'iv',
          'hashes': {'sha256': 'hash'},
        };

      final parsed = parseStoryVideoEventContent(content, now: now);

      expect(parsed, isNotNull);
      expect(
        parsed!.thumbnailUri.toString(),
        'mxc://example.org/encrypted-video-thumb',
      );
    });
  });

  group('parseStoryReactionEventContent', () {
    test('accepts a valid v1 story reaction', () {
      final now = DateTime.utc(2026, 5, 30, 15);
      final parsed = parseStoryReactionEventContent(
        _validStoryReactionContent(now: now),
        now: now,
      );

      expect(parsed, isNotNull);
      expect(parsed!.storyId, 'story-1');
      expect(parsed.storyEventId, r'$story-event');
      expect(parsed.storySenderId, '@alice:example.org');
      expect(parsed.reaction, '\u{2764}\u{FE0F}');
      expect(parsed.mentionedUserIds, isEmpty);
    });

    test('parses valid Matrix story reaction mentions', () {
      final now = DateTime.utc(2026, 5, 30, 15);
      final parsed = parseStoryReactionEventContent(
        _validStoryReactionContent(now: now)
          ..['m.mentions'] = {
            'user_ids': ['@alice:example.org'],
          },
        now: now,
      );

      expect(parsed, isNotNull);
      expect(parsed!.mentionedUserIds, ['@alice:example.org']);
    });

    test('rejects malformed and unsupported story reactions', () {
      final now = DateTime.utc(2026, 5, 30, 15);

      expect(parseStoryReactionEventContent({'v': 1}, now: now), isNull);
      expect(
        parseStoryReactionEventContent(
          _validStoryReactionContent(now: now)..['reaction'] = 'too much',
          now: now,
        ),
        isNull,
      );
      expect(
        parseStoryReactionEventContent(
          _validStoryReactionContent(now: now)..['story_sender'] = 'not-a-user',
          now: now,
        ),
        isNull,
      );
    });

    test('requires matching Matrix annotation relation data', () {
      final now = DateTime.utc(2026, 5, 30, 15);

      expect(
        parseStoryReactionEventContent(
          _validStoryReactionContent(now: now)
            ..['m.relates_to'] = {
              'rel_type': 'm.annotation',
              'event_id': r'$other-event',
              'key': '\u{2764}\u{FE0F}',
            },
          now: now,
        ),
        isNull,
      );
    });
  });

  group('parseStoryNotificationSettingsContent', () {
    test('mentions-only modes notify only for explicit story mentions', () {
      expect(
        StoryNotificationMode.mentionsOnly.shouldNotify(isMention: true),
        isTrue,
      );
      expect(
        StoryNotificationMode.mentionsOnly.shouldNotify(isMention: false),
        isFalse,
      );
      expect(StoryNotificationMode.contacts.shouldNotify(isMention: false),
          isTrue);
      expect(StoryNotificationMode.off.shouldNotify(isMention: true), isFalse);
    });

    test('uses safe defaults when account data is missing or old', () {
      final settings = parseStoryNotificationSettingsContent(null);

      expect(settings.storyPosts, StoryNotificationMode.off);
      expect(settings.storyReactions, StoryNotificationMode.contacts);
      expect(settings.sound, isTrue);
      expect(parseStoryNotificationSettingsContent({'v': 0}).toJson(), {
        'v': 1,
        'story_posts': 'off',
        'story_reactions': 'contacts',
        'sound': true,
      });
    });

    test('accepts enum-backed story notification settings', () {
      final settings = parseStoryNotificationSettingsContent({
        'v': 1,
        'story_posts': 'all',
        'story_reactions': 'mentions_only',
        'sound': false,
      });

      expect(settings.storyPosts, StoryNotificationMode.all);
      expect(settings.storyReactions, StoryNotificationMode.mentionsOnly);
      expect(settings.sound, isFalse);
      expect(settings.toJson(), {
        'v': 1,
        'story_posts': 'all',
        'story_reactions': 'mentions_only',
        'sound': false,
      });
    });

    test(
        'rejects invalid modes back to their fallback while preserving sound default',
        () {
      final settings = parseStoryNotificationSettingsContent({
        'v': 1,
        'story_posts': 'loud',
        'story_reactions': 12,
      });

      expect(settings.storyPosts, StoryNotificationMode.off);
      expect(settings.storyReactions, StoryNotificationMode.contacts);
      expect(settings.sound, isTrue);
    });
  });

  group('countSuppressibleStoryNotifications', () {
    test('counts active unread story events and clamps to raw room count', () {
      final now = DateTime.utc(2026, 5, 29, 18);
      final markers = [
        StoryNotificationMarker(
          roomId: '!room:example.org',
          eventId: r'$story-1',
          originServerTs: now.subtract(const Duration(minutes: 1)),
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        StoryNotificationMarker(
          roomId: '!room:example.org',
          eventId: r'$story-2',
          originServerTs: now.subtract(const Duration(minutes: 2)),
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      ];

      final suppressed = countSuppressibleStoryNotifications(
        markers: markers,
        latestOwnReceiptAt: now.subtract(const Duration(minutes: 5)),
        rawNotificationCount: 1,
      );

      expect(suppressed, 1);
    });

    test('suppresses raw room count while initial marker scan is pending', () {
      final suppressed = countSuppressibleStoryNotifications(
        markers: const [],
        latestOwnReceiptAt: DateTime.utc(2026, 6, 11, 14),
        rawNotificationCount: 3,
        initialScanPending: true,
      );

      expect(suppressed, 3);
    });

    test('uses known markers instead of full pending-scan suppression', () {
      final now = DateTime.utc(2026, 6, 11, 14);
      final markers = [
        StoryNotificationMarker(
          roomId: '!room:example.org',
          eventId: r'$story-1',
          originServerTs: now.subtract(const Duration(minutes: 1)),
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      ];

      final suppressed = countSuppressibleStoryNotifications(
        markers: markers,
        latestOwnReceiptAt: now.subtract(const Duration(minutes: 5)),
        rawNotificationCount: 5,
        initialScanPending: true,
      );

      expect(suppressed, 1);
    });

    test('ignores read events and still suppresses expired story events', () {
      final now = DateTime.utc(2026, 5, 29, 18);
      final markers = [
        StoryNotificationMarker(
          roomId: '!room:example.org',
          eventId: r'$read-story',
          originServerTs: now.subtract(const Duration(minutes: 10)),
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        StoryNotificationMarker(
          roomId: '!room:example.org',
          eventId: r'$expired-story',
          originServerTs: now.subtract(const Duration(minutes: 1)),
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ),
      ];

      final suppressed = countSuppressibleStoryNotifications(
        markers: markers,
        latestOwnReceiptAt: now.subtract(const Duration(minutes: 5)),
        rawNotificationCount: 5,
      );

      expect(suppressed, 1);
    });
  });

  group('storyPostNotificationDedupeKey', () {
    test('keys one logical story independently of room event copies', () {
      final key = storyPostNotificationDedupeKey(
        clientId: 'client-a',
        senderId: '@alice:example.org',
        storyId: 'story-1',
      );

      expect(
        storyPostNotificationDedupeKey(
          clientId: 'client-a',
          senderId: '@alice:example.org',
          storyId: 'story-1',
        ),
        key,
      );
    });

    test('separates accounts, senders, and story ids', () {
      final key = storyPostNotificationDedupeKey(
        clientId: 'client-a',
        senderId: '@alice:example.org',
        storyId: 'story-1',
      );

      expect(
        storyPostNotificationDedupeKey(
          clientId: 'client-b',
          senderId: '@alice:example.org',
          storyId: 'story-1',
        ),
        isNot(key),
      );
      expect(
        storyPostNotificationDedupeKey(
          clientId: 'client-a',
          senderId: '@bob:example.org',
          storyId: 'story-1',
        ),
        isNot(key),
      );
      expect(
        storyPostNotificationDedupeKey(
          clientId: 'client-a',
          senderId: '@alice:example.org',
          storyId: 'story-2',
        ),
        isNot(key),
      );
    });
  });
}

Map<String, Object?> _validStoryReactionContent({
  required DateTime now,
}) {
  return {
    'v': 1,
    'story_id': 'story-1',
    'story_event_id': r'$story-event',
    'story_sender': '@alice:example.org',
    'created_at': now.millisecondsSinceEpoch,
    'reaction': '\u{2764}\u{FE0F}',
    'm.relates_to': {
      'rel_type': 'm.annotation',
      'event_id': r'$story-event',
      'key': '\u{2764}\u{FE0F}',
    },
  };
}

Map<String, Object?> _validStoryContent({
  required DateTime now,
  DateTime? createdAt,
  DateTime? expiresAt,
}) {
  final created = createdAt ?? now.subtract(const Duration(minutes: 2));
  final expires = expiresAt ?? created.add(storyLifetime);
  return {
    'v': 1,
    'story_id': 'story-1',
    'created_at': created.millisecondsSinceEpoch,
    'expires_at': expires.millisecondsSinceEpoch,
    'msgtype': 'm.image',
    'body': 'story.png',
    'filename': 'story.png',
    'url': 'mxc://example.org/story-1',
    'info': {
      'mimetype': 'image/png',
      'size': 1024,
      'w': 100,
      'h': 100,
    },
  };
}

Map<String, Object?> _validVideoStoryContent({
  required DateTime now,
  DateTime? createdAt,
  DateTime? expiresAt,
  int durationMs = 24000,
  int size = 4096,
}) {
  final created = createdAt ?? now.subtract(const Duration(minutes: 2));
  final expires = expiresAt ?? created.add(storyLifetime);
  return {
    'v': 1,
    'story_id': 'video-story-1',
    'media_type': 'video',
    'created_at': created.millisecondsSinceEpoch,
    'expires_at': expires.millisecondsSinceEpoch,
    'duration_ms': durationMs,
    'trim_start_ms': 0,
    'trim_end_ms': durationMs,
    'background_color': 0xFF10303A,
    'overlays': [
      {
        'id': 'text-1',
        'type': 'text',
        'content': 'hello',
        'x': 0.5,
        'y': 0.4,
        'scale': 1,
        'rotation': 0,
        'color': 0xFFFFFFFF,
        'font_size': 96,
        'bold': true,
      },
      {
        'id': 'emoji-1',
        'type': 'emoji',
        'content': '\u{1F525}',
        'x': 0.5,
        'y': 0.55,
        'scale': 1.2,
        'rotation': 0.1,
        'font_size': 140,
      },
    ],
    'msgtype': 'm.video',
    'body': 'story.mp4',
    'filename': 'story.mp4',
    'url': 'mxc://example.org/video-story-1',
    'info': {
      'mimetype': 'video/mp4',
      'size': size,
      'duration': durationMs,
      'w': 1080,
      'h': 1920,
      'thumbnail_url': 'mxc://example.org/video-thumb-1',
      'thumbnail_info': {
        'mimetype': 'image/png',
        'size': 256,
        'w': 180,
        'h': 320,
      },
    },
  };
}
