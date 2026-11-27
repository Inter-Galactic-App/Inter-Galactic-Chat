import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/web/web_push_subscription.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:web/web.dart' as web;

class WebPushNotifier implements Notifier {
  static const String serviceWorkerPath =
      'intergalactic_push_service_worker.js';
  static const String serviceWorkerScope = 'push-notifications/';

  WebPushSubscriptionData? _subscription;
  String _permissionState = 'default';
  String? _lastError;
  web.ServiceWorkerRegistration? _registration;
  final Map<String, List<web.Notification>> _notificationsByRoute = {};

  bool get isSupported {
    return _notificationsSupported &&
        _serviceWorkersSupported &&
        web.window.has('PushManager');
  }

  String get permissionState => _permissionState;

  String? get lastError => _lastError;

  WebPushSubscriptionData? get subscription => _subscription;

  bool get _notificationsSupported => web.window.has('Notification');

  bool get _serviceWorkersSupported =>
      web.window.navigator.has('serviceWorker');

  @override
  bool get hasPermission => _permissionState == 'granted';

  @override
  bool get needsToken => true;

  @override
  bool get enabled => true;

  @override
  Future<void> init() async {
    await _restoreStoredSubscription();
    await _refreshPermissionState();

    if (!isSupported) {
      _lastError ??= 'Web push is not supported in this browser.';
      return;
    }

    await _getPushWorkerRegistration();

    if (hasPermission) {
      await _refreshSubscription();
    }
  }

  @override
  Future<void> notify(NotificationContent notification) async {
    if (!hasPermission || !_notificationsSupported) {
      return;
    }

    final browserNotification = web.Notification(
      notification.title,
      web.NotificationOptions(
        body: notification.content,
        icon: 'icons/Icon-192.png',
        badge: 'icons/Icon-192.png',
        tag: _notificationTag(notification),
        data: _notificationData(notification).jsify(),
      ),
    );

    final routeKey = _notificationRouteKeyForContent(notification);
    if (routeKey != null) {
      _notificationsByRoute
          .putIfAbsent(routeKey, () => <web.Notification>[])
          .add(browserNotification);
    }
  }

  @override
  Future<bool> requestPermission() async {
    await _refreshPermissionState();

    if (!isSupported) {
      _lastError = 'Web push is not supported in this browser.';
      return false;
    }

    if (_permissionState != 'granted') {
      try {
        final result = await web.Notification.requestPermission().toDart;
        _permissionState = result.toDart;
        await preferences.webPushPermissionState.set(_permissionState);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to request browser notification permission',
        );
        _lastError = 'Failed to request browser notification permission.';
        return false;
      }
    }

    if (_permissionState != 'granted') {
      _lastError = _permissionState == 'denied'
          ? 'Browser notification permission was denied.'
          : null;
      await _persistSubscription(null);
      return false;
    }

    final subscription = await _ensureSubscription();
    return subscription != null;
  }

  @override
  Future<String?> getToken() async {
    final currentSubscription = await _refreshSubscription();
    if (currentSubscription != null) {
      return currentSubscription.endpoint;
    }

    await _restoreStoredSubscription();
    return _subscription?.endpoint;
  }

  @override
  Map<String, dynamic>? extraRegistrationData() {
    return _subscription?.toRegistrationData();
  }

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
    final notifications = _notificationsByRoute.remove(
      _notificationRouteKey(clientId: clientId, roomId: roomId),
    );
    if (notifications == null) {
      return;
    }

    for (final notification in notifications) {
      notification.close();
    }
  }

  Future<void> _refreshPermissionState() async {
    if (!_notificationsSupported) {
      _permissionState = 'unsupported';
      await preferences.webPushPermissionState.set(null);
      return;
    }

    _permissionState = web.Notification.permission;
    await preferences.webPushPermissionState.set(_permissionState);
  }

  Future<void> _restoreStoredSubscription() async {
    final raw = preferences.webPushSubscription.value;
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _subscription = WebPushSubscriptionData.fromJson(json);
    } catch (_) {
      await preferences.webPushSubscription.set(null);
      _subscription = null;
    }
  }

  Future<void> _persistSubscription(
      WebPushSubscriptionData? subscription) async {
    _subscription = subscription;

    if (subscription == null) {
      await preferences.webPushSubscription.set(null);
      return;
    }

    await preferences.webPushSubscription
        .set(jsonEncode(subscription.toJson()));
  }

  Future<web.ServiceWorkerRegistration?> _getPushWorkerRegistration() async {
    if (_registration != null) {
      return _awaitActiveRegistration(_registration!);
    }

    if (!_serviceWorkersSupported) {
      _lastError = 'Service workers are not available in this browser.';
      return null;
    }

    final container = web.window.navigator.serviceWorker;

    try {
      final existing =
          await container.getRegistration(serviceWorkerScope).toDart;

      if (existing != null) {
        _registration = existing;
        return _awaitActiveRegistration(existing);
      }
    } catch (_) {
      // Fall through to explicit registration.
    }

    try {
      _registration = await container
          .register(
            serviceWorkerPath.toJS,
            web.RegistrationOptions(scope: serviceWorkerScope),
          )
          .toDart;
      if (_registration == null) {
        return null;
      }
      return _awaitActiveRegistration(_registration!);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to register Inter Galactic web push service worker',
      );
      _lastError = 'Failed to register the web push service worker.';
      return null;
    }
  }

  Future<web.ServiceWorkerRegistration> _awaitActiveRegistration(
    web.ServiceWorkerRegistration registration,
  ) async {
    for (var i = 0; i < 25; i++) {
      if (registration.active != null) {
        return registration;
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    return registration;
  }

  Future<WebPushSubscriptionData?> _refreshSubscription() async {
    final registration = await _getPushWorkerRegistration();
    if (registration == null) {
      return _subscription;
    }

    final pushManager = registration.pushManager;

    try {
      final subscriptionObject = await pushManager.getSubscription().toDart;

      if (subscriptionObject == null) {
        await _persistSubscription(null);
        return null;
      }

      final parsed = _decodeSubscription(subscriptionObject);
      await _persistSubscription(parsed);
      return parsed;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to refresh the current web push subscription',
      );
      _lastError = 'Failed to read the current web push subscription: $error';
      return _subscription;
    }
  }

  Future<WebPushSubscriptionData?> _ensureSubscription() async {
    final currentSubscription = await _refreshSubscription();
    if (currentSubscription != null) {
      _lastError = null;
      return currentSubscription;
    }

    final registration = await _getPushWorkerRegistration();
    if (registration == null) {
      return null;
    }

    final vapidKey = BuildConfig.WEB_PUSH_VAPID_PUBLIC_KEY.trim();
    if (vapidKey.isEmpty) {
      _lastError = 'WEB_PUSH_VAPID_PUBLIC_KEY is not set for this build.';
      return null;
    }

    final options = web.PushSubscriptionOptionsInit(
      userVisibleOnly: true,
      applicationServerKey: _urlBase64ToUint8List(vapidKey).toJS,
    );
    final pushManager = registration.pushManager;

    try {
      final subscriptionObject = await pushManager.subscribe(options).toDart;

      final parsed = _decodeSubscription(subscriptionObject);
      await _persistSubscription(parsed);
      _lastError = null;
      return parsed;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to create a web push subscription',
      );
      _lastError = error.toString();
      return null;
    }
  }

  WebPushSubscriptionData? _decodeSubscription(
    web.PushSubscription? subscriptionObject,
  ) {
    if (subscriptionObject == null) {
      return null;
    }

    final dartValue = subscriptionObject.toJSON().dartify();
    if (dartValue is! Map) {
      return null;
    }

    return WebPushSubscriptionData.fromJson(
      Map<String, dynamic>.from(dartValue),
    );
  }

  Uint8List _urlBase64ToUint8List(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }

    return Uint8List.fromList(base64Decode(normalized));
  }

  String _notificationTag(NotificationContent notification) {
    if (notification is MessageNotificationContent) {
      return notification.roomId;
    }

    if (notification is CallNotificationContent) {
      return 'call:${notification.roomId}';
    }

    return notification.title;
  }

  String? _notificationRouteKeyForContent(NotificationContent notification) {
    if (notification is MessageNotificationContent) {
      return _notificationRouteKey(
        clientId: notification.clientId,
        roomId: notification.roomId,
      );
    }

    if (notification is StoryNotificationContent) {
      return _notificationRouteKey(
        clientId: notification.clientId,
        roomId: notification.roomId,
      );
    }

    if (notification is CallNotificationContent) {
      return _notificationRouteKey(
        clientId: notification.clientId,
        roomId: notification.roomId,
      );
    }

    if (notification is CalendarReminderNotificationContent) {
      return _notificationRouteKey(
        clientId: notification.clientId,
        roomId: notification.roomId,
      );
    }

    return null;
  }

  String _notificationRouteKey({
    required String clientId,
    required String roomId,
  }) {
    return '$clientId\n$roomId';
  }

  Map<String, dynamic> _notificationData(NotificationContent notification) {
    if (notification is MessageNotificationContent) {
      return {
        'room_id': notification.roomId,
        'client_id': notification.clientId,
        'event_id': notification.eventId,
      };
    }

    if (notification is StoryNotificationContent) {
      return {
        'room_id': notification.roomId,
        'client_id': notification.clientId,
        'event_id': notification.eventId,
        'story_sender_id': notification.storySenderId,
        'story_id': notification.storyId,
        if (notification.storyEventId != null)
          'story_event_id': notification.storyEventId,
      };
    }

    if (notification is CallNotificationContent) {
      return {
        'room_id': notification.roomId,
        'client_id': notification.clientId,
        'call_id': notification.callId,
      };
    }

    return {};
  }
}
