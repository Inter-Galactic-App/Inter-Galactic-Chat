// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/push_notification/android/android_notifier.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/push_notification_component.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/service/background_service_notifications/background_service_task_notification.dart';

// Manage these to enable / disable firebase
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
dynamic Firebase;
dynamic FirebaseMessaging;
dynamic DefaultFirebaseOptions;
// --------

Future<void> onForegroundMessage(dynamic message) async {
  return AndroidNotifier.onForegroundMessage(message.data);
}

BackgroundNotificationsManager? _fcmBackgroundNotificationManager;
Future<BackgroundNotificationsManager>?
    _fcmBackgroundNotificationManagerLoading;
Future<void> _fcmBackgroundMessageTail = Future<void>.value();
final Map<String, DateTime> _recentFcmMatrixEvents = {};
const _fcmDuplicateEventWindow = Duration(seconds: 30);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(dynamic message) async {
  Log.prefix = "fcm-background";
  Log.i(
    "Got Firebase background message: "
    "${_firebasePayloadSummary(message.data)}",
  );
  isHeadless = true;

  final previous = _fcmBackgroundMessageTail;
  final next = previous.catchError((Object e, StackTrace s) {
    Log.w("Previous Firebase background message failed");
    Log.onError(e, s);
  }).then((_) => _handleFirebaseBackgroundMessage(message.data));
  _fcmBackgroundMessageTail = next;

  await next;
}

Future<void> _handleFirebaseBackgroundMessage(dynamic rawData) async {
  final data = _asFirebaseMessageData(rawData);
  if (data == null) {
    Log.w("Ignoring Firebase push with invalid Matrix message data");
    return;
  }

  if (!data.containsKey("room_id") || !data.containsKey("event_id")) {
    // Ignore Firebase delivery hints and malformed payloads instead of
    // showing raw JSON/code-like diagnostics as user notifications.
    Log.w("Ignoring Firebase push without Matrix room/event identifiers");
    return;
  }

  if (!_claimFirebaseMatrixEvent(data)) {
    Log.i(
      "Ignoring duplicate Firebase push "
      "${_firebasePayloadSummary(data)}",
    );
    return;
  }

  Log.i(
    "Firebase background client manager available: ${clientManager != null}",
  );

  await preferences.init();

  try {
    final notificationManager = await _getFcmBackgroundNotificationManager();

    await notificationManager.handleMessage(data);
  } catch (e, s) {
    Log.e("An error occurred while processing Firebase background message");
    Log.onError(e, s);
    await NotificationManager.notify(ErrorNotificationContent(
        title: "Notification needs attention",
        content: "Open Inter Galactic to view the latest message."));
  }
}

Map<String, dynamic>? _asFirebaseMessageData(dynamic rawData) {
  if (rawData is! Map) {
    return null;
  }

  return rawData.map(
    (key, value) => MapEntry(key.toString(), value),
  );
}

bool _claimFirebaseMatrixEvent(Map<String, dynamic> data) {
  final eventKey = _firebaseMatrixEventKey(data);
  if (eventKey == null) {
    return true;
  }

  final now = DateTime.now();
  _recentFcmMatrixEvents.removeWhere(
    (_, seenAt) => now.difference(seenAt) > _fcmDuplicateEventWindow,
  );

  if (_recentFcmMatrixEvents.containsKey(eventKey)) {
    return false;
  }

  _recentFcmMatrixEvents[eventKey] = now;
  return true;
}

String? _firebaseMatrixEventKey(Map<String, dynamic> data) {
  final roomId = data["room_id"]?.toString();
  final eventId = data["event_id"]?.toString();
  if (roomId == null || eventId == null || roomId.isEmpty || eventId.isEmpty) {
    return null;
  }

  return "$roomId/$eventId";
}

String _firebasePayloadSummary(dynamic rawData) {
  if (rawData is! Map) {
    return "invalid_type=${rawData.runtimeType}";
  }

  final keys = rawData.keys.map((key) => key.toString()).toList()..sort();
  return "keys=${keys.join(',')} "
      "hasRoom=${rawData.containsKey("room_id")} "
      "hasEvent=${rawData.containsKey("event_id")}";
}

Future<BackgroundNotificationsManager>
    _getFcmBackgroundNotificationManager() async {
  final existingManager = _fcmBackgroundNotificationManager;
  if (existingManager != null) {
    return existingManager;
  }

  final loadingManager = _fcmBackgroundNotificationManagerLoading;
  if (loadingManager != null) {
    return loadingManager;
  }

  final managerFuture = () async {
    final manager = BackgroundNotificationsManager(null);
    await manager.init();
    _fcmBackgroundNotificationManager = manager;
    return manager;
  }();

  _fcmBackgroundNotificationManagerLoading = managerFuture;
  try {
    return await managerFuture;
  } finally {
    if (identical(_fcmBackgroundNotificationManagerLoading, managerFuture)) {
      _fcmBackgroundNotificationManagerLoading = null;
    }
  }
}

class FirebasePushNotifier implements Notifier {
  late AndroidNotifier notifier;

  @override
  bool get hasPermission => notifier.hasPermission;

  @override
  bool get needsToken => true;

  FirebasePushNotifier() {
    notifier = AndroidNotifier();
  }

  @override
  bool get enabled => true;

  String? token;

  @override
  Future<void> init() async {
    if (!BuildConfig.ENABLE_GOOGLE_SERVICES) {
      throw StateError(
        "Firebase push notifications require firebase_core/firebase_messaging "
        "to be restored and ENABLE_GOOGLE_SERVICES=true.",
      );
    }

    Log.i("Initializing firebase push notifier");
    await notifier.init();

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    Log.i("Initialized App");
    final messaging = FirebaseMessaging.instance;
    messaging.onTokenRefresh.listen((event) {
      unawaited(_storeToken(event, refreshPushers: true).catchError((e, s) {
        Log.w("Failed to store refreshed Firebase push token");
        Log.onError(e, s);
      }));
    });

    await messaging.setAutoInitEnabled(true);
    await _loadInitialToken();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(onForegroundMessage);
  }

  Future<void> _loadInitialToken() async {
    try {
      final fetchedToken = await FirebaseMessaging.instance.getToken();
      if (fetchedToken is String && fetchedToken.isNotEmpty) {
        await _storeToken(fetchedToken, refreshPushers: false);
      }
    } catch (e, s) {
      Log.w("Failed to fetch initial Firebase push token");
      Log.onError(e, s);
    }
  }

  Future<void> _storeToken(String value, {required bool refreshPushers}) async {
    token = value;
    Log.i("Received Firebase push token");
    await preferences.fcmKey.set(value);
    if (!refreshPushers) {
      await preferences.setPushGateway(BuildConfig.androidPushGatewayHost);
    }

    if (refreshPushers) {
      await PushNotificationComponent.updateAllPushers();
    }
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    notifier.notify(notification);
  }

  @override
  Future<bool> requestPermission() {
    return notifier.requestPermission();
  }

  @override
  Future<String?> getToken() async {
    final storedToken = preferences.fcmKey.value;
    if (storedToken != null && storedToken.isNotEmpty) {
      return storedToken;
    }

    try {
      final fetchedToken = await FirebaseMessaging.instance.getToken();
      if (fetchedToken is String && fetchedToken.isNotEmpty) {
        await _storeToken(fetchedToken, refreshPushers: false);
        return fetchedToken;
      }
    } catch (e, s) {
      Log.w("Failed to fetch Firebase push token");
      Log.onError(e, s);
    }

    return null;
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return {
      "type": "fcm",
      "transport": "fcm",
      "provider": "firebase",
      "format": "data_only",
    };
  }

  @override
  Future<void> clearNotifications(Room room) {
    return notifier.clearNotifications(room);
  }

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) {
    return notifier.clearNotificationsByRoute(
      clientId: clientId,
      roomId: roomId,
    );
  }
}
