import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/notification_companion_controller.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';

void main() {
  group('NotificationCompanionController', () {
    test('emits approved message notifications when enabled', () async {
      final controller = NotificationCompanionController();
      final emitted = expectLater(
        controller.messages,
        emits(
          isA<NotificationCompanionMessage>()
              .having((message) => message.roomId, 'roomId', '!room:test')
              .having((message) => message.clientId, 'clientId', 'client-a')
              .having((message) => message.body, 'body', 'Hello there')
              .having((message) => message.bodyRedacted, 'redacted', false),
        ),
      );

      controller.handleApprovedNotification(
        _messageContent(),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );

      await emitted;
    });

    test('does not emit when companion is disabled', () async {
      final controller = NotificationCompanionController();
      var emitted = false;
      final subscription = controller.messages.listen((_) => emitted = true);

      controller.handleApprovedNotification(
        _messageContent(),
        enabled: false,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );
      await pumpEventQueue();

      expect(emitted, isFalse);
      await subscription.cancel();
    });

    test('redacts message body when previews are disabled', () {
      final controller = NotificationCompanionController();

      final message = controller.buildMessage(
        _messageContent(),
        showPreviews: false,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );

      expect(message.body, NotificationCompanionMessage.genericBody);
      expect(message.bodyRedacted, isTrue);
    });

    test('redacts message body while screen sharing privacy is active', () {
      final controller = NotificationCompanionController();

      final message = controller.buildMessage(
        _messageContent(),
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: true,
      );

      expect(message.body, NotificationCompanionMessage.genericBody);
      expect(message.bodyRedacted, isTrue);
    });

    test('keeps the most recent companion message as latest', () {
      final controller = NotificationCompanionController();

      controller.handleApprovedNotification(
        _messageContent(eventId: r'$first', content: 'First'),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );
      controller.handleApprovedNotification(
        _messageContent(eventId: r'$second', content: 'Second'),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );

      expect(controller.latest?.eventId, r'$second');
      expect(controller.latest?.body, 'Second');
      expect(controller.state.count, 2);
    });

    test('clears pending notifications by room and client', () {
      final controller = NotificationCompanionController();

      controller.handleApprovedNotification(
        _messageContent(eventId: r'$first', content: 'First'),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );
      controller.handleApprovedNotification(
        _messageContent(
          eventId: r'$second',
          content: 'Second',
          roomId: '!other:test',
        ),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );

      controller.clearRoom('!room:test', clientId: 'client-a');

      expect(controller.state.count, 1);
      expect(controller.latest?.eventId, r'$second');
    });

    test('removes pending notifications that no longer have unread rooms', () {
      final controller = NotificationCompanionController();

      controller.handleApprovedNotification(
        _messageContent(eventId: r'$first', content: 'First'),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );
      controller.handleApprovedNotification(
        _messageContent(
          eventId: r'$second',
          content: 'Second',
          roomId: '!other:test',
        ),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );

      final removedMessages = controller.reconcileUnreadRooms(
        (message) => message.roomId == '!other:test',
      );

      expect(removedMessages.map((message) => message.eventId), [r'$first']);
      expect(controller.state.count, 1);
      expect(controller.latest?.eventId, r'$second');
    });

    test('clears all pending companion notifications', () {
      final controller = NotificationCompanionController();

      controller.handleApprovedNotification(
        _messageContent(eventId: r'$first', content: 'First'),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );
      controller.handleApprovedNotification(
        _messageContent(eventId: r'$second', content: 'Second'),
        enabled: true,
        showPreviews: true,
        hidePreviewsWhileScreenSharing: true,
        isScreenSharing: false,
      );

      controller.clearPending();

      expect(controller.state.count, 0);
      expect(controller.latest, isNull);
    });

    test('tracks whether the overlay window is open', () {
      final controller = NotificationCompanionController();

      expect(controller.isOverlayHostAvailable, isFalse);
      expect(controller.isOverlayOpen, isFalse);

      controller.setOverlayHostAvailable(true);
      expect(controller.isOverlayHostAvailable, isTrue);

      controller.setOverlayOpen(true);
      expect(controller.isOverlayOpen, isTrue);

      controller.setOverlayHostAvailable(false);
      expect(controller.isOverlayHostAvailable, isFalse);
      expect(controller.isOverlayOpen, isFalse);

      controller.setOverlayHostAvailable(true);
      controller.setOverlayOpen(false);
      expect(controller.isOverlayOpen, isFalse);
    });
  });
}

MessageNotificationContent _messageContent({
  String eventId = r'$event',
  String content = 'Hello there',
  String roomId = '!room:test',
}) {
  return MessageNotificationContent(
    senderName: 'Nova',
    senderId: '@nova:test',
    roomName: 'Bridge',
    content: content,
    eventId: eventId,
    roomId: roomId,
    clientId: 'client-a',
    isDirectMessage: false,
  );
}
