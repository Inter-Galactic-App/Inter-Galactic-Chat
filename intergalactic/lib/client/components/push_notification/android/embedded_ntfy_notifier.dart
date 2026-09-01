import 'package:intergalactic/client/components/push_notification/android/android_notifier.dart';
import 'package:intergalactic/client/components/push_notification/android/embedded_ntfy_sse_listener.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/push_notification_component.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/service/background_service.dart';
import 'package:uuid/uuid.dart';

class EmbeddedNtfyNotifier implements Notifier {
  static const String _ntfyBase = BuildConfig.androidEmbeddedNtfyBaseUrl;

  late AndroidNotifier _notifier;
  bool _isInit = false;
  bool _usesBackgroundService = false;
  final EmbeddedNtfySseListener _foregroundListener = EmbeddedNtfySseListener();

  EmbeddedNtfyNotifier() {
    _notifier = AndroidNotifier();
  }

  String _getOrCreateTopic() {
    var existing = preferences.embeddedNtfyTopic.value;
    if (existing != null && existing.isNotEmpty) return existing;
    final topic = const Uuid().v4();
    preferences.embeddedNtfyTopic.set(topic);
    return topic;
  }

  String get topic => _getOrCreateTopic();

  String get endpoint => '$_ntfyBase/$topic';

  @override
  bool get needsToken => true;

  @override
  bool get enabled => true; // Always enabled — no user toggle needed

  @override
  bool get hasPermission => _notifier.hasPermission;

  @override
  Future<void> init() async {
    if (_isInit) return;
    await _notifier.init();
    final activeTopic = topic;
    _usesBackgroundService = await ensureEmbeddedPushBackgroundService();
    if (!_usesBackgroundService) {
      _startForegroundSseListener();
    }
    _isInit = true;
    Log.i(
        "EmbeddedNtfyNotifier: initialized, topicAvailable=${activeTopic.isNotEmpty}, background service: $_usesBackgroundService");
  }

  @override
  Future<String?> getToken() async {
    // This URL is registered as the Matrix pusher endpoint.
    // matrix-push-gateway will POST to: https://push.ourgalaxy.space/{topic}
    return endpoint;
  }

  void _startForegroundSseListener() {
    _foregroundListener.start(
      topic: topic,
      onNotification: AndroidNotifier.onForegroundMessage,
      logPrefix: "EmbeddedNtfyNotifier",
    );
  }

  Future<void> resetTopic() async {
    final newTopic = const Uuid().v4();
    await preferences.embeddedNtfyTopic.set(newTopic);

    if (_isInit) {
      if (_usesBackgroundService) {
        await restartEmbeddedPushBackgroundService();
      } else {
        _startForegroundSseListener();
      }
    }

    await PushNotificationComponent.updateAllPushers();
    Log.i(
        "EmbeddedNtfyNotifier: reset topic, topicAvailable=${newTopic.isNotEmpty}");
  }

  @override
  Future<void> notify(NotificationContent notification) =>
      _notifier.notify(notification);

  @override
  Future<bool> requestPermission() => _notifier.requestPermission();

  @override
  Map<String, dynamic>? extraRegistrationData() => {
        "type": "ntfy",
        "transport": "embedded_ntfy",
        "provider": "ntfy",
      };

  @override
  Future<void> clearNotifications(Room room) =>
      _notifier.clearNotifications(room);

  @override
  Future<void> clearNotificationsByRoute({
    required String clientId,
    required String roomId,
  }) =>
      _notifier.clearNotificationsByRoute(
        clientId: clientId,
        roomId: roomId,
      );
}
