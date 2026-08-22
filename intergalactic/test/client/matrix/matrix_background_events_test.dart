import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_events.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  test('recognizes true and compatibility sticker event shapes', () {
    final trueSticker = matrix.MatrixEvent(
      type: matrix.EventTypes.Sticker,
      content: const {
        'body': 'sticker.webp',
        'url': 'mxc://example.org/sticker',
      },
      senderId: '@sender:example.org',
      eventId: r'$true-sticker',
      originServerTs: DateTime.utc(2026, 8, 13),
    );
    final compatibilitySticker = matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: const {
        'msgtype': 'm.image',
        'chat.commet.type': 'chat.commet.sticker',
        'body': 'sticker.png',
        'url': 'mxc://example.org/sticker',
      },
      senderId: '@sender:example.org',
      eventId: r'$compatibility-sticker',
      originServerTs: DateTime.utc(2026, 8, 13),
    );
    final ordinaryImage = matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: const {
        'msgtype': 'm.image',
        'body': 'photo.png',
        'url': 'mxc://example.org/photo',
      },
      senderId: '@sender:example.org',
      eventId: r'$ordinary-image',
      originServerTs: DateTime.utc(2026, 8, 13),
    );
    final nonImageCompatibilityEvent = matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: const {
        'msgtype': 'm.text',
        'chat.commet.type': 'chat.commet.sticker',
        'body': 'not a sticker',
      },
      senderId: '@sender:example.org',
      eventId: r'$non-image-compatibility-event',
      originServerTs: DateTime.utc(2026, 8, 13),
    );

    expect(matrixBackgroundEventIsSticker(trueSticker), isTrue);
    expect(matrixBackgroundEventIsSticker(compatibilitySticker), isTrue);
    expect(matrixBackgroundEventIsSticker(ordinaryImage), isFalse);
    expect(matrixBackgroundEventIsSticker(nonImageCompatibilityEvent), isFalse);
  });

  test(
    'accepts encrypted, message, and sticker notification event families',
    () {
      for (final type in [
        matrix.EventTypes.Encrypted,
        matrix.EventTypes.Message,
        matrix.EventTypes.Sticker,
      ]) {
        final event = matrix.MatrixEvent(
          content: const {},
          type: type,
          senderId: '@sender:example.org',
          eventId: r'$candidate-event',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
        );

        expect(matrixBackgroundEventIsNotificationCandidate(event), isTrue);
      }
    },
  );

  test('rejects unrelated notification event families', () {
    final event = matrix.MatrixEvent(
      content: const {},
      type: matrix.EventTypes.Reaction,
      senderId: '@sender:example.org',
      eventId: r'$reaction-event',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
    );

    expect(matrixBackgroundEventIsNotificationCandidate(event), isFalse);
  });

  test(
    'background image events expose an image attachment for notifications',
    () {
      final mediaClient = matrix.Client(
        'background-preview-test',
        database: _FakeMatrixDatabase(),
      );
      final event = matrix.MatrixEvent(
        type: matrix.EventTypes.Message,
        content: const {
          'msgtype': 'm.image',
          'body': 'image.png',
          'url': 'mxc://example.org/image',
          'info': {'mimetype': 'image/png', 'w': 100, 'h': 80},
        },
        senderId: '@sender:example.org',
        eventId: r'$image-event',
        originServerTs: DateTime.utc(2026, 8, 12),
      );

      final backgroundEvent = MatrixBackgroundTimelineEventMessage(
        event,
        mediaClient: mediaClient,
        mediaEvent: matrix.Event.fromMatrixEvent(
          event,
          matrix.Room(id: '!room:example.org', client: mediaClient),
        ),
      );

      expect(backgroundEvent.attachments, hasLength(1));
      expect(backgroundEvent.attachments!.single, isA<ImageAttachment>());
    },
  );

  test(
    'background image events without optional MIME metadata expose an image attachment',
    () {
      final mediaClient = matrix.Client(
        'background-preview-missing-mime-test',
        database: _FakeMatrixDatabase(),
      );
      final event = matrix.MatrixEvent(
        type: matrix.EventTypes.Message,
        content: const {
          'msgtype': 'm.image',
          'body': 'image',
          'url': 'mxc://example.org/image',
        },
        senderId: '@sender:example.org',
        eventId: r'$image-without-mime-event',
        originServerTs: DateTime.utc(2026, 8, 12),
      );

      final backgroundEvent = MatrixBackgroundTimelineEventMessage(
        event,
        mediaClient: mediaClient,
        mediaEvent: matrix.Event.fromMatrixEvent(
          event,
          matrix.Room(id: '!room:example.org', client: mediaClient),
        ),
      );

      expect(backgroundEvent.attachments, hasLength(1));
      final attachment = backgroundEvent.attachments!.single;
      expect(attachment, isA<ImageAttachment>());
      expect((attachment as ImageAttachment).mimeType, 'image/png');
    },
  );

  for (final media in const [
    ('image/png', 'sticker.png'),
    ('image/webp', 'sticker.webp'),
    ('image/gif', 'picker.gif'),
  ]) {
    test(
      'background true sticker ${media.$1} retains notification preview media',
      () {
        final mediaClient = matrix.Client(
          'background-sticker-preview-test',
          database: _FakeMatrixDatabase(),
        );
        final event = matrix.MatrixEvent(
          type: matrix.EventTypes.Sticker,
          content: {
            'body': media.$2,
            'url': 'mxc://example.org/sticker',
            'info': {'mimetype': media.$1, 'w': 120, 'h': 120},
          },
          senderId: '@sender:example.org',
          eventId: r'$sticker-event',
          originServerTs: DateTime.utc(2026, 8, 13),
        );
        final mediaEvent = matrix.Event.fromMatrixEvent(
          event,
          matrix.Room(id: '!room:example.org', client: mediaClient),
        );

        final backgroundEvent = MatrixBackgroundTimelineEventSticker.tryCreate(
          event,
          mediaClient: mediaClient,
          mediaEvent: mediaEvent,
        )!;

        expect(backgroundEvent.stickerName, media.$2);
        expect(backgroundEvent.stickerImage, isNotNull);
        final presentation = NotificationAttachmentPresentation.fromSticker(
          preview: backgroundEvent.stickerImage,
          isAnimated: backgroundEvent.isAnimatedSticker,
        );
        expect(
          presentation.displayText,
          media.$1 == 'image/gif' ? 'Sent a GIF' : 'Sent a sticker',
        );
        expect(presentation.preview, same(backgroundEvent.stickerImage));
      },
    );
  }

  test('background animated WebP sticker retains GIF semantics metadata', () {
    final mediaClient = matrix.Client(
      'background-animated-webp-preview-test',
      database: _FakeMatrixDatabase(),
    );
    final event = matrix.MatrixEvent(
      type: matrix.EventTypes.Sticker,
      content: const {
        'body': 'picker.webp',
        'url': 'mxc://example.org/sticker',
        'info': {
          'chat.commet.animated': true,
          'mimetype': 'image/webp',
          'w': 120,
          'h': 120,
        },
      },
      senderId: '@sender:example.org',
      eventId: r'$animated-webp-event',
      originServerTs: DateTime.utc(2026, 8, 13),
    );
    final mediaEvent = matrix.Event.fromMatrixEvent(
      event,
      matrix.Room(id: '!room:example.org', client: mediaClient),
    );

    final backgroundEvent = MatrixBackgroundTimelineEventSticker.tryCreate(
      event,
      mediaClient: mediaClient,
      mediaEvent: mediaEvent,
    )!;

    expect(backgroundEvent.isAnimatedSticker, isTrue);
    expect(backgroundEvent.stickerImage, isNotNull);
    final presentation = NotificationAttachmentPresentation.fromSticker(
      preview: backgroundEvent.stickerImage,
      isAnimated: backgroundEvent.isAnimatedSticker,
    );
    expect(presentation.displayText, 'Sent a GIF');
    expect(presentation.preview, same(backgroundEvent.stickerImage));
  });

  test('background sticker without a valid media URI falls back safely', () {
    final mediaClient = matrix.Client(
      'background-invalid-sticker-test',
      database: _FakeMatrixDatabase(),
    );
    final event = matrix.MatrixEvent(
      type: matrix.EventTypes.Sticker,
      content: const {'body': 'sticker'},
      senderId: '@sender:example.org',
      eventId: r'$invalid-sticker-event',
      originServerTs: DateTime.utc(2026, 8, 13),
    );

    expect(
      MatrixBackgroundTimelineEventSticker.tryCreate(
        event,
        mediaClient: mediaClient,
        mediaEvent: matrix.Event.fromMatrixEvent(
          event,
          matrix.Room(id: '!room:example.org', client: mediaClient),
        ),
      ),
      isNull,
    );
  });

  test('a sticker with no usable media URI still reads as a sticker', () {
    // Such an event falls back to the message wrapper, whose plainTextBody
    // only knew about encrypted and message types - so a perfectly valid
    // sticker was announced as "Unknown event type" in the notification.
    final withBody = MatrixBackgroundTimelineEventMessage(
      matrix.MatrixEvent(
        type: matrix.EventTypes.Sticker,
        content: const {'body': 'party parrot'},
        senderId: '@sender:example.org',
        eventId: r'$sticker-no-media',
        originServerTs: DateTime.utc(2026, 8, 17),
      ),
    );
    expect(withBody.plainTextBody, 'party parrot');

    final withoutBody = MatrixBackgroundTimelineEventMessage(
      matrix.MatrixEvent(
        type: matrix.EventTypes.Sticker,
        content: const {},
        senderId: '@sender:example.org',
        eventId: r'$sticker-bare',
        originServerTs: DateTime.utc(2026, 8, 17),
      ),
    );
    expect(withoutBody.plainTextBody, 'Sticker');
  });

  test('an animated sticker is classified from its MIME type', () {
    // `body` is not required to be a filename - a picker can send "Picker" -
    // so the .gif suffix alone labelled animated stickers as static.
    expect(
      timelineStickerIsAnimated(const {
        'body': 'Picker',
        'info': {'mimetype': 'image/gif'},
      }, 'Picker'),
      isTrue,
    );
    expect(
      timelineStickerIsAnimated(const {
        'body': 'Picker',
        'info': {'mimetype': 'image/webp'},
      }, 'Picker'),
      isFalse,
    );
  });
}

class _FakeMatrixDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
