import 'dart:async';
import 'dart:convert';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/custom_sound_manager.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/image/lod_image.dart';
import 'package:intergalactic/utils/image_utils.dart';
import 'package:intergalactic/utils/notification_utils.dart';
import 'package:intergalactic/utils/shortcuts_manager.dart';
import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_linux/src/model/hint.dart' as notif;
import 'package:launcher_entry/launcher_entry.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:ui' as ui;

class LinuxNotifier implements Notifier {
  @override
  bool get hasPermission => true;

  static NotificationsClient client = NotificationsClient();

  @override
  bool get enabled => true;

  @override
  Future<bool> requestPermission() async {
    return true;
  }

  static LinuxFlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;

  static void backgroundNotificationResponse(NotificationResponse details) {}

  static const callAccept = "call.accept";
  static const callDecline = "call.decline";
  static const openRoom = "room.open";

  static int notificationId = 0;
  static final Map<String, Set<int>> _notificationIdsByRoute = {};

  late LinuxServerCapabilities capabilities;

  final service = LauncherEntryService(
    appUri: 'application://chat.intergalactic.app.desktop',
  );

  static void notificationResponse(NotificationResponse details) {
    final payload = jsonDecode(details.payload!) as Map<String, dynamic>;

    var action = details.actionId ?? payload["default_action_id"];

    if (action == "inline-reply") {
      var clientId = payload['client_id'];
      var roomId = payload['room_id'];
      var eventId = payload['event_id'];
      var message = details.input;

      if (clientId == null) return;
      if (roomId == null) return;
      if (eventId == null) return;
      if (message == null) return;

      var client = clientManager!.getClient(clientId);

      if (client == null) return;

      if (message.trim().isNotEmpty) {
        client.getRoom(roomId)?.sendMessage(message: message.trim());
      }
      return;
    }

    if ([callAccept, openRoom].contains(action)) {
      final roomId = payload['room_id']!;
      EventBus.openRoom.add((roomId, null));
      windowManager.show();
      windowManager.focus();
    }

    if ([callAccept, callDecline].contains(action)) {
      final callId = payload['call_id'];
      final clientId = payload['client_id'];
      final session = clientManager?.callManager.currentSessions
          .where(
            (e) => e.sessionId == callId && e.client.identifier == clientId,
          )
          .firstOrNull;

      if (action == callDecline) {
        clientManager?.callManager.stopRingtone();
      }

      if (session != null) {
        if (action == callAccept) {
          session.acceptCall(withMicrophone: true);
        }

        if (action == callDecline) {
          session.declineCall();
          clientManager?.callManager.stopRingtone();
        }
      } else {
        Log.d("Could not find call session");
      }
    }
  }

  @override
  Future<void> init() async {
    flutterLocalNotificationsPlugin = LinuxFlutterLocalNotificationsPlugin();

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    await flutterLocalNotificationsPlugin?.initialize(
      initializationSettingsLinux,
      onDidReceiveNotificationResponse: notificationResponse,
    );

    capabilities = await flutterLocalNotificationsPlugin!.getCapabilities();

    clientManager!.directMessages.onHighlightedRoomsListUpdated.listen(
      (_) => updateBadgeCount(),
    );
    clientManager!.onSpaceUpdated.stream.listen((_) => updateBadgeCount());

    updateBadgeCount();
  }

  void updateBadgeCount() {
    var counts = NotificationUtils.getNotificationCounts();
    var count = counts.$2;
    service.update(countVisible: count > 0, count: count);
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    switch (notification) {
      case MessageNotificationContent _:
        return displayMessageNotification(notification);
      case RoomMembershipNotificationContent _:
        return displayRoomMembershipNotification(notification);
      case CallNotificationContent _:
        return displayCallNotification(notification);
      case CalendarReminderNotificationContent _:
        return displayCalendarReminderNotification(notification);
      default:
    }
  }

  Future<void> displayMessageNotification(
    MessageNotificationContent content,
  ) async {
    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    var image = await ShortcutsManager.createAvatarImage(
      placeholderColor: room.getColorOfUser(content.senderId),
      placeholderText: content.senderName,
      imageProvider: content.senderImage,
      doCircleMask: true,
      shouldZoomOut: false,
    );

    if (content.isDirectMessage == false) {
      var roomImage = await ShortcutsManager.createAvatarImage(
        placeholderColor: room.defaultColor,
        placeholderText: room.displayName,
        imageProvider: content.roomImage,
        doCircleMask: true,
        shouldZoomOut: false,
      );

      image = await ShortcutsManager.combineRoomAndUserImages(roomImage, image);
    }

    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    String notificationBody = content.content;

    var details = LinuxNotificationDetails(
      icon: ByteDataLinuxIcon(
        LinuxRawIconData(
          data: data,
          width: image.width,
          height: image.height,
          hasAlpha: true,
          channels: 4,
        ),
      ),
      defaultActionName: openRoom,
      actions: [
        if (capabilities.otherCapabilities.contains("inline-reply"))
          LinuxNotificationAction(key: "inline-reply", label: "Reply"),
      ],
      customHints: [
        notif.LinuxNotificationCustomHint(
          'desktop-entry',
          notif.LinuxHintStringValue("chat.intergalactic.app"),
        ),
      ],
      category: LinuxNotificationCategory.imReceived,
    );

    var title = "${content.senderName} (${content.roomName})";
    if (content.isDirectMessage) {
      title = content.senderName;
    }

    var payload = {
      // include default action here as well
      // in some cases it seems `defaultActionName` comes back as null
      // so we can use this as a fallback
      "default_action_id": openRoom,
      "room_id": content.roomId,
      "client_id": content.clientId,
      "event_id": content.eventId,
    };

    var player = NotificationManager.getSoundPlayer(
      roomLocalId: content.roomId,
    );
    player.open(
      Media(
        CustomSoundManager.notificationSoundUri(roomLocalId: content.roomId),
      ),
    );

    final id = notificationId++;
    await flutterLocalNotificationsPlugin?.show(
      id,
      title,
      notificationBody,
      notificationDetails: details,
      payload: jsonEncode(payload),
    );
    _trackNotificationId(
      clientId: content.clientId,
      roomId: content.roomId,
      id: id,
    );
  }

  Future<void> displayCallNotification(CallNotificationContent content) async {
    var client = clientManager?.getClient(content.clientId);
    var room = client?.getRoom(content.roomId);

    if (room == null) {
      return;
    }

    var image = await ShortcutsManager.createAvatarImage(
      placeholderColor: room.getColorOfUser(content.senderId),
      placeholderText: content.roomName,
      imageProvider: content.senderImage,
      doCircleMask: true,
      shouldZoomOut: false,
    );

    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    var details = LinuxNotificationDetails(
      icon: ByteDataLinuxIcon(
        LinuxRawIconData(
          data: data,
          width: image.width,
          height: image.height,
          hasAlpha: true,
          channels: 4,
        ),
      ),
      defaultActionName: openRoom,
      category: LinuxNotificationCategory.imReceived,
      timeout: const LinuxNotificationTimeout.expiresNever(),
      urgency: LinuxNotificationUrgency.critical,
      actions: [
        LinuxNotificationAction(
          key: callAccept,
          label: CommonStrings.promptAccept,
        ),
        LinuxNotificationAction(
          key: callDecline,
          label: CommonStrings.promptDecline,
        ),
      ],
    );

    var payload = {
      // include default action here as well
      // in some cases it seems `defaultActionName` comes back as null
      // so we can use this as a fallback
      "default_action_id": openRoom,
      "room_id": content.roomId,
      "client_id": content.clientId,
      "call_id": content.callId,
    };

    await flutterLocalNotificationsPlugin?.show(
      0,
      content.title,
      content.content,
      notificationDetails: details,
      payload: jsonEncode(payload),
    );
    _trackNotificationId(
      clientId: content.clientId,
      roomId: content.roomId,
      id: 0,
    );
  }

  Future<void> displayRoomMembershipNotification(
    RoomMembershipNotificationContent content,
  ) async {
    final client = clientManager?.getClient(content.clientId);
    final room = client?.getRoom(content.roomId);
    if (room == null) {
      return;
    }

    final image = await ShortcutsManager.createAvatarImage(
      placeholderColor: room.getColorOfUser(content.senderId),
      placeholderText: content.senderName,
      imageProvider: content.senderImage,
      doCircleMask: true,
      shouldZoomOut: false,
    );

    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    final details = LinuxNotificationDetails(
      icon: ByteDataLinuxIcon(
        LinuxRawIconData(
          data: data,
          width: image.width,
          height: image.height,
          hasAlpha: true,
          channels: 4,
        ),
      ),
      defaultActionName: openRoom,
      category: LinuxNotificationCategory.imReceived,
      customHints: [
        notif.LinuxNotificationCustomHint(
          'desktop-entry',
          notif.LinuxHintStringValue("chat.intergalactic.app"),
        ),
      ],
    );

    final payload = {
      "default_action_id": openRoom,
      "room_id": content.roomId,
      "client_id": content.clientId,
      "event_id": content.eventId,
    };

    final player = NotificationManager.getSoundPlayer(
      roomLocalId: content.roomId,
    );
    player.open(
      Media(
        CustomSoundManager.notificationSoundUri(roomLocalId: content.roomId),
      ),
    );

    final id = notificationId++;
    await flutterLocalNotificationsPlugin?.show(
      id,
      '${content.title} (${content.roomName})',
      content.content,
      notificationDetails: details,
      payload: jsonEncode(payload),
    );
    _trackNotificationId(
      clientId: content.clientId,
      roomId: content.roomId,
      id: id,
    );
  }

  Future<void> displayCalendarReminderNotification(
    CalendarReminderNotificationContent content,
  ) async {
    final client = clientManager?.getClient(content.clientId);
    final room = client?.getRoom(content.roomId);
    if (room == null) {
      return;
    }

    final image = await ShortcutsManager.createAvatarImage(
      placeholderColor: room.defaultColor,
      placeholderText: content.roomName,
      imageProvider: await room.getShortcutImage(),
      doCircleMask: true,
      shouldZoomOut: false,
    );

    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    final details = LinuxNotificationDetails(
      icon: ByteDataLinuxIcon(
        LinuxRawIconData(
          data: data,
          width: image.width,
          height: image.height,
          hasAlpha: true,
          channels: 4,
        ),
      ),
      defaultActionName: openRoom,
      category: LinuxNotificationCategory.imReceived,
    );

    final payload = {
      "default_action_id": openRoom,
      "room_id": content.roomId,
      "client_id": content.clientId,
    };

    final id = notificationId++;
    await flutterLocalNotificationsPlugin?.show(
      id,
      content.title,
      content.content,
      notificationDetails: details,
      payload: jsonEncode(payload),
    );
    _trackNotificationId(
      clientId: content.clientId,
      roomId: content.roomId,
      id: id,
    );
  }

  static const _imageLoadTimeout = Duration(seconds: 10);

  Future<ui.Image> determineImage(ImageProvider provider) async {
    if (provider is LODImageProvider) {
      var data = await provider.loadThumbnail?.call();
      var mem = MemoryImage(data!);
      return await ImageUtils.imageProviderToImage(
        mem,
        timeout: _imageLoadTimeout,
      );
    }

    return await ImageUtils.imageProviderToImage(
      provider,
      timeout: _imageLoadTimeout,
    );
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return null;
  }

  @override
  Future<String?> getToken() async {
    return null;
  }

  @override
  bool get needsToken => false;

  @override
  Future<void> clearNotifications(Room room) {
    return clearNotificationsByRoute(
      clientId: room.client.identifier,
      roomId: room.identifier,
    );
  }

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) async {
    final plugin = flutterLocalNotificationsPlugin;
    final ids = _notificationIdsByRoute.remove(
      _notificationRouteKey(clientId: clientId, roomId: roomId),
    );
    if (plugin == null || ids == null || ids.isEmpty) {
      return;
    }

    await Future.wait([for (final id in ids) plugin.cancel(id)]);
  }

  static void _trackNotificationId({
    required String clientId,
    required String roomId,
    required int id,
  }) {
    _notificationIdsByRoute
        .putIfAbsent(
          _notificationRouteKey(clientId: clientId, roomId: roomId),
          () => <int>{},
        )
        .add(id);
  }

  static String _notificationRouteKey({
    required String clientId,
    required String roomId,
  }) {
    return '$clientId\n$roomId';
  }
}
