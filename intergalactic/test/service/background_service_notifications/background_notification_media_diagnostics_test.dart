import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/service/background_service_notifications/background_notification_media_diagnostics.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  test(
    'background notification media summary records only image attachment shape',
    () {
      final event = matrix.MatrixEvent(
        type: matrix.EventTypes.Message,
        content: const {'msgtype': 'm.image', 'url': 'mxc://example.org/image'},
        senderId: '@sender:example.org',
        eventId: r'$event',
        originServerTs: DateTime.utc(2026, 8, 12),
      );

      expect(
        summarizeBackgroundNotificationMedia(
          eventClass: BackgroundNotificationEventClass.message,
          implementation: 'matrix_timeline',
          routingEventMatches: true,
          routingRoomMatches: true,
          hasSdkAttachment: true,
          hasPresentation: false,
          matrixEvent: event,
          attachmentCount: 1,
        ),
        'background_notification_media '
        'event_class=message implementation=matrix_timeline event_type=message '
        'message_type=image has_sdk_attachment=true '
        'has_url=true has_file=false routing_event_match=true '
        'routing_room_match=true has_presentation=false '
        'attachment_count=1',
      );
    },
  );

  test(
    'background notification media summary separates custom messages from text and records routing mismatch',
    () {
      final event = matrix.MatrixEvent(
        type: matrix.EventTypes.Message,
        content: const {'msgtype': 'org.example.custom'},
        senderId: '@sender:example.org',
        eventId: r'$event',
        originServerTs: DateTime.utc(2026, 8, 13),
      );

      expect(
        summarizeBackgroundNotificationMedia(
          eventClass: BackgroundNotificationEventClass.message,
          implementation: 'matrix_timeline',
          routingEventMatches: false,
          routingRoomMatches: true,
          hasSdkAttachment: false,
          hasPresentation: false,
          matrixEvent: event,
          attachmentCount: 0,
        ),
        'background_notification_media '
        'event_class=message implementation=matrix_timeline event_type=message '
        'message_type=custom has_sdk_attachment=false '
        'has_url=false has_file=false routing_event_match=false '
        'routing_room_match=true has_presentation=false '
        'attachment_count=0',
      );
    },
  );

  test(
    'background notification media summary reports an unresolved event and an '
    'encrypted file attachment',
    () {
      // The null branch is the one that runs when the background path could
      // not resolve the event at all, so it is the branch most likely to
      // change without anyone noticing.
      expect(
        summarizeBackgroundNotificationMedia(
          eventClass: BackgroundNotificationEventClass.message,
          implementation: 'other_timeline',
          routingEventMatches: false,
          routingRoomMatches: false,
          hasSdkAttachment: false,
          hasPresentation: false,
          matrixEvent: null,
          attachmentCount: 0,
        ),
        'background_notification_media '
        'event_class=message implementation=other_timeline event_type=other '
        'message_type=missing has_sdk_attachment=false '
        'has_url=false has_file=false routing_event_match=false '
        'routing_room_match=false has_presentation=false '
        'attachment_count=0',
      );

      // An encrypted attachment arrives as `file`, not `url`, and that is the
      // shape this diagnostic exists to tell apart.
      final encrypted = matrix.MatrixEvent(
        type: matrix.EventTypes.Message,
        content: const {
          'msgtype': 'm.file',
          'file': {'url': 'mxc://example.org/encrypted'},
        },
        senderId: '@sender:example.org',
        eventId: r'$encrypted',
        originServerTs: DateTime.utc(2026, 8, 17),
      );

      expect(
        summarizeBackgroundNotificationMedia(
          eventClass: BackgroundNotificationEventClass.message,
          implementation: 'matrix_timeline',
          routingEventMatches: true,
          routingRoomMatches: true,
          hasSdkAttachment: true,
          hasPresentation: true,
          matrixEvent: encrypted,
          attachmentCount: 1,
        ),
        contains('has_url=false has_file=true'),
      );
    },
  );
}
