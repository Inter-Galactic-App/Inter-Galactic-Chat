import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/modifiers/room_notification_snooze.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NotificationModifierRoomSnooze', () {
    late NotificationModifierRoomSnooze modifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();
      modifier = NotificationModifierRoomSnooze();
    });

    test('suppresses message notifications for an active room snooze',
        () async {
      await globals.preferences.setRoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!room:example.org',
        duration: const Duration(hours: 1),
      );

      final result = await modifier.process(_messageNotification());

      expect(result, isNull);
    });

    test('allows notifications for rooms without an active snooze', () async {
      final content = _messageNotification();

      final result = await modifier.process(content);

      expect(result, same(content));
    });

    test('does not suppress calls for a snoozed room', () async {
      await globals.preferences.setRoomNotificationSnooze(
        clientId: '@alice:example.org',
        roomId: '!room:example.org',
        duration: const Duration(hours: 1),
      );
      final content = CallNotificationContent(
        roomId: '!room:example.org',
        senderId: '@bob:example.org',
        senderName: 'Bob',
        roomName: 'Bob',
        clientId: '@alice:example.org',
        callId: 'call-1',
        isDirectMessage: true,
        title: 'Incoming call',
        content: 'Bob is calling',
      );

      final result = await modifier.process(content);

      expect(result, same(content));
    });
  });
}

MessageNotificationContent _messageNotification() {
  return MessageNotificationContent(
    senderName: 'Bob',
    senderId: '@bob:example.org',
    roomName: 'Bob',
    content: 'Hello',
    eventId: r'$event',
    roomId: '!room:example.org',
    clientId: '@alice:example.org',
    isDirectMessage: true,
  );
}
