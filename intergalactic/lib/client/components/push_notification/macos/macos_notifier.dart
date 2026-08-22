import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intergalactic/client/components/push_notification/notification_companion_controller.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_identity.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/notification_response_handler.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/custom_sound_manager.dart';
import 'package:intergalactic/utils/custom_uri.dart';
import 'package:intergalactic/utils/notification_utils.dart';
import 'package:media_kit/media_kit.dart';

class MacosNotifier implements Notifier {
  static const String _roomSnoozeCategoryId =
      "chat.intergalactic.room_snooze.v1";
  static final List<DarwinNotificationCategory> _notificationCategories = [
    DarwinNotificationCategory(
      _roomSnoozeCategoryId,
      actions: [
        for (final option in RoomNotificationSnoozeDurationOption.values)
          DarwinNotificationAction.plain(
            option.notificationActionId,
            option.actionLabel,
          ),
      ],
    ),
  ];

  FlutterLocalNotificationsPlugin? _plugin;
  String _permissionStatus = "unknown";

  @override
  bool get hasPermission =>
      _permissionStatus == "authorized" || _permissionStatus == "provisional";

  String get permissionStatus => _permissionStatus;

  @override
  bool get needsToken => false;

  @override
  bool get enabled => true;

  MacOSFlutterLocalNotificationsPlugin? get _macosPlugin => _plugin
      ?.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin
      >();

  static void onResponse(NotificationResponse details) {
    unawaited(NotificationResponseHandler.handle(details));
  }

  @override
  Future<void> init() async {
    _plugin = FlutterLocalNotificationsPlugin();

    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
      notificationCategories: _notificationCategories,
    );

    await _plugin?.initialize(
      InitializationSettings(macOS: darwinSettings),
      onDidReceiveNotificationResponse: MacosNotifier.onResponse,
      onDidReceiveBackgroundNotificationResponse:
          onBackgroundNotificationResponse,
    );

    await _handleNotificationLaunchDetails();
    await _refreshPermissionStatus();
    if (!hasPermission) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(requestPermission());
      });
    }
  }

  Future<void> _handleNotificationLaunchDetails() async {
    try {
      final launchDetails = await _plugin?.getNotificationAppLaunchDetails();
      final response = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true && response != null) {
        unawaited(NotificationResponseHandler.handle(response));
      }
    } on PlatformException {
      return;
    }
  }

  Future<void> _refreshPermissionStatus() async {
    try {
      final permissions = await _macosPlugin?.checkPermissions();
      _permissionStatus = _permissionStatusFromOptions(permissions);
    } on MissingPluginException {
      _permissionStatus = "unavailable";
    } on PlatformException {
      _permissionStatus = "unknown";
    }
  }

  String _permissionStatusFromOptions(NotificationsEnabledOptions? options) {
    if (options == null) {
      return "unknown";
    }
    if (options.isProvisionalEnabled) {
      return "provisional";
    }
    if (options.isEnabled) {
      return "authorized";
    }
    return "denied_or_not_requested";
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final granted =
          await _macosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ==
          true;
      await _refreshPermissionStatus();
      return granted || hasPermission;
    } on MissingPluginException {
      _permissionStatus = "unavailable";
      return false;
    } on PlatformException {
      await _refreshPermissionStatus();
      return false;
    }
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    switch (notification) {
      case MessageNotificationContent _:
        return _showMessageNotification(notification);
      case StoryNotificationContent _:
        return _showNotification(
          id: NotificationIdentity.storyNotificationId(notification),
          title: notification.title,
          body: notification.content,
          subtitle: notification.roomName,
          payload: OpenStoryURI(
            roomId: notification.roomId,
            clientId: notification.clientId,
            storySenderId: notification.storySenderId,
            storyId: notification.storyId,
            storyEventId: notification.storyEventId,
          ).toString(),
          threadIdentifier: NotificationIdentity.roomKeyForStory(notification),
          presentSound: notification.playSound,
          categoryIdentifier: _roomSnoozeCategoryId,
        );
      case RoomMembershipNotificationContent _:
        return _showNotification(
          id: NotificationIdentity.membershipNotificationId(notification),
          title: notification.title,
          body: notification.content,
          subtitle: notification.roomName,
          payload: OpenRoomURI(
            roomId: notification.roomId,
            clientId: notification.clientId,
          ).toString(),
          threadIdentifier: NotificationIdentity.roomKeyForMembership(
            notification,
          ),
        );
      case CallNotificationContent _:
        return _showNotification(
          id: NotificationIdentity.callNotificationId(notification),
          title: notification.title,
          body: notification.content,
          subtitle: notification.roomName,
          payload: OpenRoomURI(
            roomId: notification.roomId,
            clientId: notification.clientId,
          ).toString(),
          threadIdentifier: NotificationIdentity.roomKeyForCall(notification),
        );
      case CalendarReminderNotificationContent _:
        return _showNotification(
          id: NotificationIdentity.calendarReminderNotificationId(notification),
          title: notification.title,
          body: notification.content,
          subtitle: notification.roomName,
          payload: OpenRoomURI(
            roomId: notification.roomId,
            clientId: notification.clientId,
          ).toString(),
          threadIdentifier: NotificationIdentity.roomKeyForCalendar(
            notification,
          ),
          categoryIdentifier: _roomSnoozeCategoryId,
        );
      case ErrorNotificationContent _:
        return _showNotification(
          id: Random().nextInt(1000000),
          title: notification.title,
          body: notification.content,
        );
      case GenericRoomInviteNotificationContent _:
        return _showNotification(
          id: Random().nextInt(1000000),
          title: notification.title,
          body: notification.content,
        );
      default:
        return;
    }
  }

  Future<void> _showMessageNotification(
    MessageNotificationContent notification,
  ) async {
    if (NotificationCompanionController
        .instance
        .shouldMuteNativeDesktopMessageNotifications) {
      Log.d(
        "Suppressing macOS notification because notification companion is enabled",
        category: LogCategory.notifications,
        source: "macos-notifier",
      );
      return;
    }

    if (!await _ensureCanDeliver()) {
      return;
    }

    _playRoomNotificationSound(notification.roomId);
    await _showNotification(
      id: NotificationIdentity.messageNotificationId(notification),
      title: notification.senderName,
      body: notification.content,
      subtitle: notification.roomName,
      payload: OpenRoomURI(
        roomId: notification.roomId,
        clientId: notification.clientId,
      ).toString(),
      threadIdentifier: NotificationIdentity.roomKeyForMessage(notification),
      categoryIdentifier: _roomSnoozeCategoryId,
      presentSound: false,
      checkCanDeliver: false,
    );
  }

  void _playRoomNotificationSound(String roomId) {
    final player = NotificationManager.getSoundPlayer(roomLocalId: roomId);
    player.setPlaylistMode(PlaylistMode.none);
    unawaited(
      player.open(
        Media(CustomSoundManager.notificationSoundUri(roomLocalId: roomId)),
      ),
    );
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? subtitle,
    String? payload,
    String? threadIdentifier,
    String? categoryIdentifier,
    bool presentSound = true,
    bool checkCanDeliver = true,
  }) async {
    if (checkCanDeliver && !await _ensureCanDeliver()) {
      return;
    }

    final details = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: presentSound,
      presentBanner: true,
      presentList: true,
      badgeNumber: _currentBadgeCount(),
      subtitle: subtitle,
      threadIdentifier: threadIdentifier,
      categoryIdentifier: categoryIdentifier,
    );

    await _plugin?.show(
      id,
      title,
      body,
      NotificationDetails(macOS: details),
      payload: payload,
    );
  }

  Future<bool> _ensureCanDeliver() async {
    await _refreshPermissionStatus();
    if (hasPermission) {
      return true;
    }
    return requestPermission();
  }

  int _currentBadgeCount({Room? excludingRoom}) {
    final counts = NotificationUtils.getNotificationCounts(
      excludingRoom: excludingRoom,
    );
    return counts.$2;
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
  Future<void> clearNotifications(Room room) async {
    final notifications = await _activeNotifications();
    for (final notification in notifications) {
      final id = notification.id;
      if (id == null) {
        continue;
      }

      if (!NotificationIdentity.matchesPayloadRoom(
        notification.payload,
        room,
      )) {
        continue;
      }

      await _plugin?.cancel(id);
    }
  }

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) async {
    final notifications = await _activeNotifications();
    for (final notification in notifications) {
      final id = notification.id;
      if (id == null) {
        continue;
      }

      if (!NotificationIdentity.matchesPayloadRoute(
        notification.payload,
        clientId: clientId,
        roomId: roomId,
      )) {
        continue;
      }

      await _plugin?.cancel(id);
    }
  }

  Future<List<ActiveNotification>> _activeNotifications() async {
    try {
      return await _plugin?.getActiveNotifications() ?? const [];
    } on PlatformException {
      return const [];
    }
  }
}
