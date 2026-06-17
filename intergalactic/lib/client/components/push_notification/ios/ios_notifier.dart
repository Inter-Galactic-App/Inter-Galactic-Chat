import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_identity.dart';
import 'package:intergalactic/client/components/push_notification/notification_response_handler.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/push_notification_component.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/custom_uri.dart';
import 'package:intergalactic/utils/notification_utils.dart';

class IosNotifier with WidgetsBindingObserver implements Notifier {
  static const MethodChannel _channel = MethodChannel(
    "chat.intergalactic.app/ios_notifications",
  );
  static const String _roomSnoozeCategoryId =
      "chat.intergalactic.room_snooze.v1";
  static const Duration _remoteRegistrationCooldown = Duration(seconds: 30);
  static const Duration _pusherRefreshCooldown = Duration(seconds: 5);
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
  String _permissionStatus = "not_determined";
  String? _apnsEnvironment;
  String? _cachedPushToken;
  DateTime? _lastRemoteRegistrationAttemptAt;
  Future<bool>? _remoteRegistrationInFlight;
  DateTime? _lastPusherRefreshAt;
  Future<void>? _pusherRefreshInFlight;
  String? _pendingPusherRefreshReason;
  Future<void>? _pendingNotificationResponseDrain;
  bool _lifecycleObserverRegistered = false;

  @override
  bool get hasPermission =>
      _permissionStatus == "authorized" ||
      _permissionStatus == "provisional" ||
      _permissionStatus == "ephemeral";

  String get permissionStatus => _permissionStatus;

  bool get hasRemoteToken => _cachedPushToken?.isNotEmpty == true;

  @override
  bool get needsToken => true;

  @override
  bool get enabled => true;

  static void onResponse(NotificationResponse details) {
    unawaited(NotificationResponseHandler.handle(details));
  }

  static Future<bool> replaySavedApnsPayloadForDebug(String payload) async {
    if (!(BuildConfig.DEBUG || kDebugMode) || !BuildConfig.IOS) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            "debugReplayNotificationResponse",
            {"payload": payload},
          ) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> replayLastCapturedApnsPayloadForDebug() async {
    if (!(BuildConfig.DEBUG || kDebugMode) || !BuildConfig.IOS) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(
            "debugReplayLastNotificationResponse",
          ) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String?> lastCapturedApnsPayloadForDebug() async {
    if (!(BuildConfig.DEBUG || kDebugMode) || !BuildConfig.IOS) {
      return null;
    }

    try {
      final payload = await _channel.invokeMethod<Object?>(
        "debugGetLastNotificationUserInfo",
      );
      if (payload == null) {
        return null;
      }

      return const JsonEncoder.withIndent('  ').convert(
        _jsonSafePlatformValue(payload),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on JsonUnsupportedObjectError {
      return null;
    }
  }

  static Object? _jsonSafePlatformValue(Object? value) {
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(
          key.toString(),
          _jsonSafePlatformValue(entry),
        ),
      );
    }

    if (value is Iterable) {
      return value.map(_jsonSafePlatformValue).toList();
    }

    return value;
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

    final settings = InitializationSettings(iOS: darwinSettings);

    await _plugin?.initialize(
      settings,
      onDidReceiveNotificationResponse: IosNotifier.onResponse,
      onDidReceiveBackgroundNotificationResponse:
          onBackgroundNotificationResponse,
    );

    if (!_lifecycleObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleObserverRegistered = true;
    }
    _channel.setMethodCallHandler(_handlePlatformCallbacks);
    await _handleNotificationLaunchDetails();
    await _handlePendingPlatformNotificationResponse();
    await _refreshPermissionStatus();
    await _refreshApnsEnvironment();
    if (_permissionStatus == "not_determined") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(requestPermission());
      });
    }
    if (hasPermission) {
      await _ensureRemoteNotificationsRegistered();
    }
    await _refreshPushToken(waitForRegistration: hasPermission);
    if (hasPermission) {
      _queuePusherRefresh("ios-notifier-init", force: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queuePendingPlatformNotificationResponseDrain("ios-app-resumed");
    }
  }

  Future<void> _refreshPermissionStatus() async {
    try {
      _permissionStatus =
          await _channel.invokeMethod<String>("getPermissionStatus") ??
              "unknown";
    } on MissingPluginException {
      _permissionStatus = "unknown";
    } on PlatformException {
      _permissionStatus = "unknown";
    }
  }

  Future<void> _refreshApnsEnvironment() async {
    try {
      _apnsEnvironment = await _channel.invokeMethod<String>(
        "getApnsEnvironment",
      );
    } on MissingPluginException {
      _apnsEnvironment = null;
    } on PlatformException {
      _apnsEnvironment = null;
    }
  }

  Future<bool> _registerForRemoteNotifications() async {
    try {
      return await _channel.invokeMethod<bool>(
            "registerForRemoteNotifications",
          ) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> _ensureRemoteNotificationsRegistered({
    bool force = false,
  }) async {
    if (hasRemoteToken) {
      return true;
    }

    final registrationInFlight = _remoteRegistrationInFlight;
    if (registrationInFlight != null) {
      return registrationInFlight;
    }

    final now = DateTime.now();
    if (!force &&
        _lastRemoteRegistrationAttemptAt != null &&
        now.difference(_lastRemoteRegistrationAttemptAt!) <
            _remoteRegistrationCooldown) {
      return false;
    }

    _lastRemoteRegistrationAttemptAt = now;
    final registrationFuture = _registerForRemoteNotifications();
    _remoteRegistrationInFlight = registrationFuture;

    try {
      return await registrationFuture;
    } finally {
      if (identical(_remoteRegistrationInFlight, registrationFuture)) {
        _remoteRegistrationInFlight = null;
      }
    }
  }

  Future<bool> _refreshPushToken({required bool waitForRegistration}) async {
    final attempts = waitForRegistration ? 20 : 1;
    final previousToken = _cachedPushToken;
    for (var i = 0; i < attempts; i++) {
      try {
        final token = await _channel.invokeMethod<String>("getPushToken");
        if (token != null && token.isNotEmpty) {
          _cachedPushToken = token;
          return previousToken != token;
        }
        _cachedPushToken = null;
      } on MissingPluginException {
        _cachedPushToken = null;
        break;
      } on PlatformException {
        _cachedPushToken = null;
        break;
      }

      if (i < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return previousToken != _cachedPushToken;
  }

  void _queuePusherRefresh(String reason, {bool force = false}) {
    if (clientManager == null) {
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastPusherRefreshAt != null &&
        now.difference(_lastPusherRefreshAt!) < _pusherRefreshCooldown) {
      return;
    }

    final inFlight = _pusherRefreshInFlight;
    if (inFlight != null) {
      if (force) {
        _pendingPusherRefreshReason = reason;
      }
      return;
    }

    _lastPusherRefreshAt = now;
    Log.i(
      "Refreshing Matrix pushers after iOS notification state changed: $reason",
      category: LogCategory.notifications,
      source: 'ios-notifier',
    );

    final refresh = PushNotificationComponent.updateAllPushers();
    _pusherRefreshInFlight = refresh;
    unawaited(
      refresh.catchError((Object error, StackTrace stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: "Failed to refresh Matrix pushers after iOS notification "
              "state changed",
          category: LogCategory.notifications,
          source: 'ios-notifier',
        );
      }).whenComplete(() {
        if (identical(_pusherRefreshInFlight, refresh)) {
          _pusherRefreshInFlight = null;
        }
        final pendingReason = _pendingPusherRefreshReason;
        if (pendingReason != null) {
          _pendingPusherRefreshReason = null;
          _queuePusherRefresh(pendingReason, force: true);
        }
      }),
    );
  }

  Future<void> _handlePlatformCallbacks(MethodCall call) async {
    switch (call.method) {
      case "pushTokenUpdated":
        final token = call.arguments as String?;
        if (token != null && token.isNotEmpty) {
          _cachedPushToken = token;
          _queuePusherRefresh("ios-push-token-updated", force: true);
        }
        break;
      case "pushTokenRegistrationFailed":
        _cachedPushToken = null;
        _queuePusherRefresh("ios-push-token-registration-failed", force: true);
        break;
      case "notificationResponseReceived":
        await NotificationResponseHandler.handleRemotePayload(
          call.arguments,
          source: _sourceFromPayload(call.arguments) ?? "ios apns callback",
          acknowledgeResponse: _acknowledgePlatformNotificationResponse,
        );
        break;
      default:
        break;
    }
  }

  void _queuePendingPlatformNotificationResponseDrain(String reason) {
    if (_pendingNotificationResponseDrain != null) {
      return;
    }

    final drain = Future<void>.delayed(Duration.zero, () async {
      Log.d(
        "Checking for pending iOS notification response after $reason",
        category: LogCategory.notifications,
        source: 'ios-notifier',
      );
      await _handlePendingPlatformNotificationResponse();
    });

    _pendingNotificationResponseDrain = drain;
    unawaited(
      drain.whenComplete(() {
        if (identical(_pendingNotificationResponseDrain, drain)) {
          _pendingNotificationResponseDrain = null;
        }
      }),
    );
  }

  Future<void> _acknowledgePlatformNotificationResponse(
    String responseId,
  ) async {
    try {
      await _channel.invokeMethod<bool>("acknowledgeNotificationResponse", {
        "response_id": responseId,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  String? _sourceFromPayload(Object? payload) {
    if (payload is! Map) {
      return null;
    }

    final value = payload["source"];
    if (value == null) {
      return null;
    }

    final source = value.toString().trim();
    if (source.isEmpty) {
      return null;
    }

    return "ios $source";
  }

  Future<void> _handlePendingPlatformNotificationResponse() async {
    try {
      final payload = await _channel.invokeMethod<Object?>(
        "takePendingNotificationResponse",
      );
      if (payload == null) {
        return;
      }
      await NotificationResponseHandler.handleRemotePayload(
        payload,
        source: _sourceFromPayload(payload) ?? "ios pending apns response",
        acknowledgeResponse: _acknowledgePlatformNotificationResponse,
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
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

  @override
  Future<void> notify(NotificationContent notification) async {
    switch (notification) {
      case MessageNotificationContent _:
        return _showNotification(
          id: NotificationIdentity.messageNotificationId(notification),
          title: notification.senderName,
          body: notification.content,
          subtitle: notification.roomName,
          payload: OpenRoomURI(
            roomId: notification.roomId,
            clientId: notification.clientId,
          ).toString(),
          threadIdentifier: NotificationIdentity.roomKeyForMessage(
            notification,
          ),
          categoryIdentifier: _roomSnoozeCategoryId,
        );
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
      case CalendarReminderNotificationContent _:
        return _showNotification(
          id: NotificationIdentity.calendarReminderNotificationId(notification),
          title: notification.title,
          body: notification.content,
          payload: OpenRoomURI(
            roomId: notification.roomId,
            clientId: notification.clientId,
          ).toString(),
          threadIdentifier: NotificationIdentity.roomKeyForCalendar(
            notification,
          ),
          categoryIdentifier: _roomSnoozeCategoryId,
        );
      default:
        return;
    }
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
  }) async {
    final badgeCount = _currentBadgeCount();
    final details = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: presentSound,
      presentBanner: true,
      presentList: true,
      badgeNumber: badgeCount,
      subtitle: subtitle,
      threadIdentifier: threadIdentifier,
      categoryIdentifier: categoryIdentifier,
    );

    await _plugin?.show(
      id,
      title,
      body,
      NotificationDetails(iOS: details),
      payload: payload,
    );
    await _setBadgeCount(badgeCount);
  }

  int _currentBadgeCount({Room? excludingRoom}) {
    final counts = NotificationUtils.getNotificationCounts(
      excludingRoom: excludingRoom,
    );
    return counts.$2;
  }

  Future<void> _setBadgeCount(int count) async {
    try {
      await _channel.invokeMethod<bool>("setBadgeCount", {
        "count": count < 0 ? 0 : count,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<String?> getToken() async {
    await _refreshPermissionStatus();
    await _refreshApnsEnvironment();
    if (hasPermission && !hasRemoteToken) {
      await _ensureRemoteNotificationsRegistered();
    }
    await _refreshPushToken(waitForRegistration: hasPermission);
    return _cachedPushToken;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>("requestPermissions") == true;
      await _refreshPermissionStatus();
      if (granted) {
        await _ensureRemoteNotificationsRegistered(force: true);
        await _refreshPushToken(waitForRegistration: true);
        await PushNotificationComponent.updateAllPushers();
      }
      return granted;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openSystemSettings() async {
    try {
      return await _channel.invokeMethod<bool>("openAppSettings") == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return <String, dynamic>{
      "platform": "ios",
      "app_id": BuildConfig.iosPushAppId,
      "push_app_id": BuildConfig.iosPushAppId,
      "bundle_id": BuildConfig.iosBundleId,
      "apns_topic": BuildConfig.iosBundleId,
      if (_apnsEnvironment != null) "apns_environment": _apnsEnvironment,
      if (_apnsEnvironment != null) "apns_env": _apnsEnvironment,
      "push_provider": "apns",
    };
  }

  @override
  Future<void> clearNotifications(Room room) async {
    final notifications = await _plugin?.getActiveNotifications() ?? const [];

    for (final notification in notifications) {
      if (notification.id == null) {
        continue;
      }

      if (!NotificationIdentity.matchesPayloadRoom(
        notification.payload,
        room,
      )) {
        continue;
      }

      await _plugin?.cancel(notification.id!);
    }

    await _setBadgeCount(_currentBadgeCount(excludingRoom: room));
  }

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) async {
    final notifications = await _plugin?.getActiveNotifications() ?? const [];

    for (final notification in notifications) {
      if (notification.id == null) {
        continue;
      }

      if (!NotificationIdentity.matchesPayloadRoute(
        notification.payload,
        clientId: clientId,
        roomId: roomId,
      )) {
        continue;
      }

      await _plugin?.cancel(notification.id!);
    }

    await _setBadgeCount(_currentBadgeCount());
  }
}
