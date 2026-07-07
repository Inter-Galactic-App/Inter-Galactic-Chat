import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:intergalactic/client/components/push_notification/android/embedded_ntfy_sse_listener.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/service/background_service_notifications/background_service_task_notification.dart';
import 'package:intergalactic/service/background_service_notifications/background_service_task_notification2.dart';
import 'package:intergalactic/service/background_service_task.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  "background_service",
  "Background Updates",
  description: 'Manages tasks in the background.',
  importance: Importance.low,
);

FlutterBackgroundService? _service;
bool isReady = false;
bool _serviceInitStarted = false;
BackgroundNotificationsManager2? _embeddedPushNotificationManager;
EmbeddedNtfySseListener? _embeddedPushListener;
StreamSubscription? _readySubscription;
const String _androidNotificationIcon = "ig_notification_icon";

List<BackgroundServiceTask> _taskQueue = List.empty(growable: true);

bool get _shouldUseEmbeddedPushBackgroundService =>
    BuildConfig.ANDROID && !BuildConfig.ENABLE_GOOGLE_SERVICES;

Future<bool> ensureEmbeddedPushBackgroundService() async {
  if (!_shouldUseEmbeddedPushBackgroundService) {
    return false;
  }

  return initBackgroundService(keepAliveForEmbeddedPush: true);
}

Future<void> restartEmbeddedPushBackgroundService() async {
  if (!_shouldUseEmbeddedPushBackgroundService) {
    return;
  }

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke("restart_embedded_push");
    return;
  }

  await initBackgroundService(keepAliveForEmbeddedPush: true);
}

Future<void> stopEmbeddedPushBackgroundServiceIfDisabled() async {
  if (!BuildConfig.ANDROID || !BuildConfig.ENABLE_GOOGLE_SERVICES) {
    return;
  }

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    Log.i("Stopping embedded push background service for FCM build");
    service.invoke("stop_service");
  }
}

Future<void> doBackgroundServiceTask(BackgroundServiceTask task) async {
  Log.i("Service: $_service");
  bool isRunning = false;
  if (_service != null) {
    isRunning = await _service!.isRunning();
  }

  Log.i("Running: $isRunning");

  if (isRunning == false) {
    _taskQueue.add(task);
    Log.i("Creating new service");
    await initBackgroundService();
  } else {
    Log.i("Service already existed, reusing");
    handleTask(task, _service!);
  }
}

void handleTask(BackgroundServiceTask task, FlutterBackgroundService service) {
  if (task is BackgroundServiceTaskNotification) {
    Log.i("Handling task: ${task.eventId} ${task.hashCode}");

    FlutterBackgroundService().invoke("on_message_received",
        {"event_id": task.eventId, "room_id": task.roomId});
  }
}

Future<bool> initBackgroundService(
    {bool keepAliveForEmbeddedPush = false}) async {
  Log.w("Init background service");
  _service = FlutterBackgroundService();

  var id = 888;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  try {
    final isPersistentPushService =
        keepAliveForEmbeddedPush && _shouldUseEmbeddedPushBackgroundService;

    _service!.configure(
        iosConfiguration: IosConfiguration(),
        androidConfiguration: AndroidConfiguration(
            onStart: onServiceStarted,
            isForegroundMode: true,
            autoStart: isPersistentPushService,
            autoStartOnBoot: isPersistentPushService,
            initialNotificationTitle: isPersistentPushService
                ? "Inter Galactic notifications"
                : "Updating Notifications",
            initialNotificationContent: isPersistentPushService
                ? "Listening for message notifications"
                : "Updating Notifications",
            notificationChannelId: channel.id,
            foregroundServiceNotificationId: id));

    await _service!.startService();

    FlutterBackgroundService().invoke("init", {
      "keep_alive_for_embedded_push": isPersistentPushService,
    });
    Log.i("Invoking background service init");

    await _readySubscription?.cancel();
    _readySubscription = _service!.on("ready").take(1).listen((event) {
      var num = _taskQueue.length;

      for (var i = 0; i < num; i++) {
        var task = _taskQueue[0];
        _taskQueue.removeAt(0);

        handleTask(task, _service!);
      }
    });

    return true;
  } catch (exception) {
    if (exception is MissingPluginException) {
      Log.w(
          "Failed to start background service due to missing implementation. This wont show the banner, ${Isolate.current.debugName}");
    } else {
      Log.w(
          "Failed to start background service!, ${Isolate.current.debugName}");
    }
    return false;
  }
}

ServiceInstance? instance;
Future<void> onServiceInit(Map<String, dynamic>? data) async {
  final keepAliveForEmbeddedPush = _shouldUseEmbeddedPushBackgroundService &&
      data?["keep_alive_for_embedded_push"] != false;

  if (_serviceInitStarted) {
    if (keepAliveForEmbeddedPush && _embeddedPushNotificationManager != null) {
      _startEmbeddedPushListener(_embeddedPushNotificationManager!);
    }
    instance?.invoke("ready");
    return;
  }

  _serviceInitStarted = true;

  if (!preferences.isInit) {
    await preferences.init();
  }

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (instance is AndroidServiceInstance) {
    if (await (instance as AndroidServiceInstance).isForegroundService()) {
      flutterLocalNotificationsPlugin.show(
        888,
        keepAliveForEmbeddedPush
            ? "Inter Galactic notifications"
            : "Updating Notifications",
        keepAliveForEmbeddedPush ? "Listening for message notifications" : null,
        NotificationDetails(
          android: AndroidNotificationDetails(channel.id, channel.name,
              category: AndroidNotificationCategory.service,
              icon: _androidNotificationIcon,
              ongoing: true,
              showProgress: !keepAliveForEmbeddedPush,
              silent: true,
              maxProgress: 100,
              indeterminate: !keepAliveForEmbeddedPush),
        ),
      );
    }
  }

  if (!keepAliveForEmbeddedPush &&
      preferences.useLegacyNotificationHandler.value) {
    Log.i("Using legacy background notification handler");
    var notificationManager = BackgroundNotificationsManager(instance!);

    instance!.on("on_message_received").listen(notificationManager.onReceived);
    await notificationManager.init();

    await Future.delayed(const Duration(milliseconds: 200));
    notificationManager.flushQueueLoop();
  } else {
    Log.i("Using new background handler");
    var notificationManager = BackgroundNotificationsManager2(
      instance!,
      stopServiceWhenIdle: !keepAliveForEmbeddedPush,
    );
    if (keepAliveForEmbeddedPush) {
      _embeddedPushNotificationManager = notificationManager;
    }

    instance!.on("on_message_received").listen(notificationManager.onReceived);

    await notificationManager.init();

    if (keepAliveForEmbeddedPush) {
      _startEmbeddedPushListener(notificationManager);
    }

    await Future.delayed(const Duration(milliseconds: 200));
    notificationManager.flushQueueLoop();
  }

  instance?.invoke("ready");
}

void _startEmbeddedPushListener(
    BackgroundNotificationsManager2 notificationManager) {
  final topic = preferences.embeddedNtfyTopic.value;
  if (topic == null || topic.isEmpty) {
    Log.w("Embedded push background service: no ntfy topic is configured");
    return;
  }

  _embeddedPushListener ??= EmbeddedNtfySseListener();
  _embeddedPushListener!.start(
    topic: topic,
    onNotification: notificationManager.handleMessage,
    logPrefix: "EmbeddedPushBackgroundService",
  );
}

@pragma('vm:entry-point')
void onServiceStarted(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  Log.prefix = "background-service";
  Log.i("Hello from background service, ${Isolate.current.debugName}");
  isHeadless = true;
  instance = service;

  service.on("init").listen((event) {
    unawaited(onServiceInit(event));
  });

  service.on("restart_embedded_push").listen((event) {
    final notificationManager = _embeddedPushNotificationManager;
    if (notificationManager == null) {
      Log.w(
        "Embedded push background service restart requested before notification manager was ready.",
      );
      return;
    }
    _startEmbeddedPushListener(notificationManager);
  });

  service.on("stop_service").listen((event) {
    Log.i("Stopping background service by request");
    service.stopSelf();
  });

  if (_shouldUseEmbeddedPushBackgroundService) {
    unawaited(onServiceInit({
      "keep_alive_for_embedded_push": true,
    }));
  }
}
