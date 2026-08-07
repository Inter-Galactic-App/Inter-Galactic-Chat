import 'package:intergalactic/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';

class NotificationModifierRoomSnooze implements NotificationModifier {
  @override
  Future<NotificationContent?> process(NotificationContent content) async {
    final target = _roomTarget(content);
    if (target == null) {
      return content;
    }

    if (!preferences.isInit) {
      await preferences.init();
    }

    final snooze = preferences.getRoomNotificationSnooze(
      clientId: target.clientId,
      roomId: target.roomId,
    );
    if (snooze == null) {
      return content;
    }

    Log.i(
      "Suppressing room notification because the chat is snoozed",
      category: LogCategory.notifications,
      source: 'notification-snooze',
    );
    return null;
  }

  ({String clientId, String roomId})? _roomTarget(NotificationContent content) {
    return switch (content) {
      MessageNotificationContent notification => (
          clientId: notification.clientId,
          roomId: notification.roomId,
        ),
      StoryNotificationContent notification => (
          clientId: notification.clientId,
          roomId: notification.roomId,
        ),
      RoomMembershipNotificationContent notification => (
          clientId: notification.clientId,
          roomId: notification.roomId,
        ),
      CalendarReminderNotificationContent notification => (
          clientId: notification.clientId,
          roomId: notification.roomId,
        ),
      _ => null,
    };
  }
}
