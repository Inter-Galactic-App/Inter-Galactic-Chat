import 'dart:async';

import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/room.dart';

class UnifiedPushNotifier implements Notifier {
  StreamController<String> onEndpointChanged = StreamController.broadcast();

  String? get endpoint => null;

  @override
  bool get enabled => false;

  @override
  bool get hasPermission => false;

  @override
  bool get needsToken => true;

  @override
  Future<void> clearNotifications(Room room) async {}

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) async {}

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<String?> getToken() async {
    return null;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> notify(NotificationContent notification) async {}

  @override
  Future<bool> requestPermission() async {
    return false;
  }

  Future<void> unregister() async {}
}
