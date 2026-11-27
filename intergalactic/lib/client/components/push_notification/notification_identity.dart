import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/utils/custom_uri.dart';

class NotificationIdentity {
  static String roomKey({
    required String clientId,
    required String roomId,
  }) {
    return "$clientId::$roomId";
  }

  static String roomKeyForRoom(Room room) {
    return roomKey(clientId: room.client.identifier, roomId: room.identifier);
  }

  static String roomKeyForMessage(MessageNotificationContent notification) {
    return roomKey(
      clientId: notification.clientId,
      roomId: notification.roomId,
    );
  }

  static String roomKeyForCall(CallNotificationContent notification) {
    return roomKey(
      clientId: notification.clientId,
      roomId: notification.roomId,
    );
  }

  static String roomKeyForStory(StoryNotificationContent notification) {
    return roomKey(
      clientId: notification.clientId,
      roomId: notification.roomId,
    );
  }

  static String roomKeyForMembership(
      RoomMembershipNotificationContent notification) {
    return roomKey(
      clientId: notification.clientId,
      roomId: notification.roomId,
    );
  }

  static String roomKeyForCalendar(
      CalendarReminderNotificationContent notification) {
    return roomKey(
      clientId: notification.clientId,
      roomId: notification.roomId,
    );
  }

  static int messageNotificationId(MessageNotificationContent notification) {
    return _stableId(
      "message|${roomKeyForMessage(notification)}|${notification.eventId}",
    );
  }

  static int messageThreadNotificationId(
      MessageNotificationContent notification) {
    return _stableId("message_thread|${roomKeyForMessage(notification)}");
  }

  static int callNotificationId(CallNotificationContent notification) {
    return _stableId(
      "call|${roomKeyForCall(notification)}|${notification.callId}",
    );
  }

  static int storyNotificationId(StoryNotificationContent notification) {
    return _stableId(
      "story|${roomKeyForStory(notification)}|${notification.eventId}",
    );
  }

  static int membershipNotificationId(
      RoomMembershipNotificationContent notification) {
    return _stableId(
      "membership|${roomKeyForMembership(notification)}|"
      "${notification.eventId}",
    );
  }

  static int calendarReminderNotificationId(
      CalendarReminderNotificationContent notification) {
    return _stableId(
      "calendar|${roomKeyForCalendar(notification)}|${notification.eventUid}|"
      "${notification.eventStart.toUtc().millisecondsSinceEpoch}|"
      "${notification.minutesBefore}",
    );
  }

  static bool matchesPayloadRoom(String? payload, Room room) {
    return matchesPayloadRoute(
      payload,
      clientId: room.client.identifier,
      roomId: room.identifier,
    );
  }

  static bool matchesPayloadRoute(
    String? payload, {
    required String clientId,
    required String roomId,
  }) {
    final parsed = payload == null ? null : CustomURI.parse(payload);
    final targetRoomKey = roomKey(clientId: clientId, roomId: roomId);
    return switch (parsed) {
      OpenRoomURI uri =>
        roomKey(clientId: uri.clientId, roomId: uri.roomId) == targetRoomKey,
      OpenStoryURI uri =>
        roomKey(clientId: uri.clientId, roomId: uri.roomId) == targetRoomKey,
      AcceptCallUri uri =>
        roomKey(clientId: uri.clientId, roomId: uri.roomId) == targetRoomKey,
      DeclineCallUri uri =>
        roomKey(clientId: uri.clientId, roomId: uri.roomId) == targetRoomKey,
      _ => false,
    };
  }

  static int _stableId(String value) {
    var hash = 0x811C9DC5;

    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    return hash & 0x7FFFFFFF;
  }
}
