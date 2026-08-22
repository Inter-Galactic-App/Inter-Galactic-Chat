import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/web/web_push_subscription.dart';
import 'package:intergalactic/client/room.dart';

class WebPushNotifier implements Notifier {
  bool get isSupported => false;

  String get permissionState => 'unsupported';

  String? get lastError =>
      'Web push notifications are only available in web builds.';

  WebPushSubscriptionData? get subscription => null;

  @override
  bool get hasPermission => false;

  @override
  bool get needsToken => true;

  @override
  bool get enabled => false;

  @override
  Future<void> init() async {}

  @override
  Future<void> notify(NotificationContent notification) async {}

  @override
  Future<bool> requestPermission() async {
    return false;
  }

  @override
  Future<String?> getToken() async {
    return null;
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<void> clearNotifications(Room room) async {}

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) async {}
}
