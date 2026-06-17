import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/room.dart';

abstract class Notifier {
  Future<void> notify(NotificationContent notification);

  bool get hasPermission;

  bool get needsToken;

  bool get enabled;

  Future<String?> getToken();

  Future<bool> requestPermission();

  Map<String, dynamic>? extraRegistrationData();

  Future<void> init();

  Future<void> clearNotifications(Room room);

  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) async {}
}
