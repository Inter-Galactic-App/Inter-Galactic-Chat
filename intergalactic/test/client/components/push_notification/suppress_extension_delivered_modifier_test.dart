import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/suppress_extension_delivered.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';

void main() {
  group('NotificationModifierSuppressExtensionDelivered', () {
    MessageNotificationContent message(String eventId) =>
        MessageNotificationContent(
          senderName: 'Sender',
          senderId: '@sender:example.org',
          roomName: 'Room',
          roomId: '!room:example.org',
          content: 'hello',
          clientId: 'client',
          eventId: eventId,
          isDirectMessage: false,
        );

    test('drops the app copy of an event the extension delivered', () async {
      var asked = 0;
      final modifier = NotificationModifierSuppressExtensionDelivered(
        deliveredEventIds: () async {
          asked++;
          return {r'$shown', r'$other'};
        },
      );
      expect(await modifier.process(message(r'$shown')), isNull);
      expect(asked, 1);
    });

    test('passes an event the extension has not delivered', () async {
      final modifier = NotificationModifierSuppressExtensionDelivered(
        deliveredEventIds: () async => {r'$other'},
      );
      final content = message(r'$new');
      expect(await modifier.process(content), same(content));
    });

    test('passes when the lookup fails, never silences', () async {
      final modifier = NotificationModifierSuppressExtensionDelivered(
        deliveredEventIds: () async => throw StateError('channel down'),
      );
      final content = message(r'$shown');
      expect(await modifier.process(content), same(content));
    });

    test('does not consult the lookup for non-message content', () async {
      var asked = 0;
      final modifier = NotificationModifierSuppressExtensionDelivered(
        deliveredEventIds: () async {
          asked++;
          return {r'$shown'};
        },
      );
      final content = ErrorNotificationContent(
        title: 'Error',
        content: 'something',
      );
      expect(await modifier.process(content), same(content));
      expect(asked, 0);
    });
  });
}
