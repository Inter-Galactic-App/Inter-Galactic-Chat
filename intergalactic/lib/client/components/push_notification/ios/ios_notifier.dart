import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intergalactic/client/components/push_notification/ios/ios_remote_wake.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_identity.dart';
import 'package:intergalactic/client/components/push_notification/notification_response_handler.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/push_notification_component.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/components/push_notification/ios/ios_notification_preview.dart';
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
  static const String _richMessageCategoryId =
      "chat.intergalactic.rich_message.v1";
  static const Duration _remoteRegistrationCooldown = Duration(seconds: 30);
  static const Duration _pusherRefreshCooldown = Duration(seconds: 5);
  // How often an app-resume is allowed to trigger a background pusher
  // reconcile. This is the watchdog that self-heals a stale APNs pusher (e.g.
  // after the OS rotated the device token) the next time the user opens the
  // app, without re-validating on every single foreground.
  static const Duration _resumeReconcileInterval = Duration(hours: 6);
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
    DarwinNotificationCategory(
      _richMessageCategoryId,
      actions: [
        DarwinNotificationAction.text(
          richNotificationReplyActionId,
          'Reply',
          buttonTitle: 'Send',
          placeholder: 'Message',
        ),
        DarwinNotificationAction.plain(
          roomNotificationSnoozePickerActionId,
          'Mute',
          options: {DarwinNotificationActionOption.foreground},
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
  DateTime? _lastReconcileAt;
  bool? _lastReconcileSucceeded;
  bool _pusherRefreshDroppedBeforeClientReady = false;
  Future<void>? _reconcileInFlight;
  Future<void>? _remoteWakeInFlight;

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

  /// Event ids of remote notifications the extension has delivered and the
  /// user has not yet cleared. Empty on any failure: the caller's fallback is
  /// to show its own notification, which is the pre-extension behaviour.
  static Future<Set<String>> deliveredRemoteEventIds() async {
    try {
      final ids = await _channel.invokeMethod<List<Object?>>(
        "deliveredRemoteEventIds",
      );
      return {
        for (final id in ids ?? const <Object?>[])
          if (id is String && id.isNotEmpty) id,
      };
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  /// Removes the extension's notification for [eventId], rendered or
  /// generic, because the app is about to post its own. The generic case is
  /// the one that matters: a push the extension could not decrypt (no room
  /// key yet) shows the gateway's fallback, and once the app has the key its
  /// decrypted notification should replace that, not sit beside it.
  static Future<void> removeDeliveredRemoteNotification(String eventId) async {
    try {
      await _channel.invokeMethod<bool>("removeDeliveredRemoteNotification", {
        "event_id": eventId,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  /// Clears extension-rendered and generic APNs alerts for one exact account
  /// and room after that room is read. Other rooms remain in Notification Center.
  static Future<void> removeDeliveredRemoteNotificationsForRoom({
    required String clientId,
    required String roomId,
  }) async {
    if (clientId.isEmpty || roomId.isEmpty) return;
    try {
      await _channel.invokeMethod<int>(
        "removeDeliveredRemoteNotificationsForRoom",
        {"client_id": clientId, "room_id": roomId},
      );
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
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

      return const JsonEncoder.withIndent(
        '  ',
      ).convert(_jsonSafePlatformValue(payload));
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
        (key, entry) => MapEntry(key.toString(), _jsonSafePlatformValue(entry)),
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
    unawaited(_drainPendingRemoteWake());
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
      // Non-blocking so it does not delay `notifierLoading` completion (which
      // post-login pusher updates await).
      unawaited(_reconcileAfterVersionChange());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queuePendingPlatformNotificationResponseDrain("ios-app-resumed");
      _retryPendingPusherRefreshIfReady();
      _maybeReconcileOnResume();
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
    // A forced registration must still re-ask iOS even when a token is already
    // cached: after an app update the OS can rotate the APNs device token, and
    // re-registering is how we receive the new one via `pushTokenUpdated`.
    if (!force && hasRemoteToken) {
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
      // The Matrix clients are not loaded yet (common when an early APNs
      // token callback arrives before app startup finishes). Remember that a
      // refresh is owed so it is retried once the clients are ready instead of
      // being silently dropped until a manual refresh.
      _pusherRefreshDroppedBeforeClientReady = true;
      Log.d(
        "Deferred Matrix pusher refresh until clients are ready: $reason",
        category: LogCategory.notifications,
        source: 'ios-notifier',
      );
      return;
    }
    _pusherRefreshDroppedBeforeClientReady = false;

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
      refresh
          .then((_) {
            _lastReconcileAt = DateTime.now();
            _lastReconcileSucceeded = true;
          })
          .catchError((Object error, StackTrace stackTrace) {
            _lastReconcileSucceeded = false;
            Log.onError(
              error,
              stackTrace,
              content:
                  "Failed to refresh Matrix pushers after iOS notification "
                  "state changed",
              category: LogCategory.notifications,
              source: 'ios-notifier',
            );
          })
          .whenComplete(() {
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

  /// Full re-validation of the iOS push registration: refresh permission and
  /// APNs environment, (re)register for remote notifications, refresh the
  /// token, then reconcile the Matrix pusher. This mirrors what the manual
  /// "Refresh iPhone Notifications" control does, so it can run automatically.
  Future<void> _reconcilePushRegistration(String reason, {bool force = false}) {
    final inFlight = _reconcileInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _runReconcilePushRegistration(reason, force: force);
    _reconcileInFlight = future;
    return future.whenComplete(() {
      if (identical(_reconcileInFlight, future)) {
        _reconcileInFlight = null;
      }
    });
  }

  Future<void> _runReconcilePushRegistration(
    String reason, {
    required bool force,
  }) async {
    await _refreshPermissionStatus();
    if (!hasPermission) {
      return;
    }
    await _refreshApnsEnvironment();
    await _ensureRemoteNotificationsRegistered(force: force);
    await _refreshPushToken(waitForRegistration: true);
    _queuePusherRefresh(reason, force: true);
  }

  /// Watchdog invoked on app resume. Re-validates the push registration when
  /// the last reconcile failed, has not happened this process, or is older
  /// than [_resumeReconcileInterval]. This is what automatically clears a
  /// stale pusher the next time the user opens the app.
  void _maybeReconcileOnResume() {
    if (!hasPermission) {
      return;
    }

    final now = DateTime.now();
    final last = _lastReconcileAt;
    final due =
        last == null ||
        _lastReconcileSucceeded == false ||
        now.difference(last) >= _resumeReconcileInterval;
    if (!due) {
      return;
    }

    unawaited(_reconcilePushRegistration("ios-app-resumed", force: true));
  }

  /// Retry a pusher refresh that was dropped because the Matrix clients were
  /// not ready when an early APNs token callback arrived.
  void _retryPendingPusherRefreshIfReady() {
    if (!_pusherRefreshDroppedBeforeClientReady) {
      return;
    }
    if (clientManager == null) {
      return;
    }
    _queuePusherRefresh("ios-pending-pusher-refresh-retry", force: true);
  }

  /// Force a one-time full reconcile after the app version/build changes.
  /// iOS may rotate the APNs device token on update, leaving the previously
  /// registered pusher pointing at a dead token; this refreshes it once per
  /// new version without requiring the user to tap "Refresh iPhone
  /// Notifications".
  Future<void> _reconcileAfterVersionChange() async {
    if (!hasPermission) {
      return;
    }

    final currentVersion = BuildConfig.VERSION_TAG;
    final lastVersion = preferences.iosLastPushReconcileVersion;
    if (lastVersion == currentVersion) {
      return;
    }

    Log.i(
      "iOS app version changed since last push reconcile "
      "(was ${lastVersion ?? 'unset'}); forcing pusher refresh",
      category: LogCategory.notifications,
      source: 'ios-notifier',
    );

    await _reconcilePushRegistration("ios-app-version-changed", force: true);
    if (_lastReconcileSucceeded == true) {
      await preferences.setIosLastPushReconcileVersion(currentVersion);
    }
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
      case "remoteWakeReceived":
        final wakeId = (call.arguments as Map?)?['wake_id'];
        if (wakeId is String && wakeId.isNotEmpty) {
          await _runRemoteWake(
            wakeId,
            nativeElapsed: IosRemoteWake.nativeElapsedFrom(call.arguments),
            route: IosRemoteWakeRoute.fromPlatformPayload(
              (call.arguments as Map?)?['route'],
            ),
          );
        }
        break;
      default:
        break;
    }
  }

  /// A wake iOS handed to native before this engine was listening (a cold
  /// background launch): take it now, once the client manager exists.
  Future<void> _drainPendingRemoteWake() async {
    try {
      final pending = await _channel.invokeMapMethod<String, Object?>(
        "takePendingRemoteWake",
      );
      final wakeId = pending?['wake_id'];
      if (wakeId is String && wakeId.isNotEmpty) {
        // This is the path the elapsed value exists for: native has been
        // holding the wake since before the engine started.
        await _runRemoteWake(
          wakeId,
          nativeElapsed: IosRemoteWake.nativeElapsedFrom(pending),
          route: IosRemoteWakeRoute.fromPlatformPayload(pending?['route']),
        );
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// One catch-up owns the database at a time.
  ///
  /// Two callers can arrive here together: `init()` starts
  /// `_drainPendingRemoteWake()` unawaited, and a `remoteWakeReceived`
  /// callback is awaited only inside `_handlePlatformCallbacks`. Overlapping
  /// runs each drive resume/sync/suspend on the shared
  /// [DatabaseReleaseTrigger], so the first run's release lands while the
  /// second is still syncing - the 0xdead10cc case [RemoteWakeCatchUp]
  /// documents. It also repeats the same work inside native's deadline.
  Future<void> _runRemoteWake(
    String wakeId, {
    Duration nativeElapsed = Duration.zero,
    IosRemoteWakeRoute? route,
  }) async {
    final inFlight = _remoteWakeInFlight;
    if (inFlight != null) {
      // Wait it out, then still answer native for THIS wake id - the in-flight
      // run only completes its own, and an unanswered wake holds the
      // background assertion until the deadline expires.
      await inFlight;
      await _completeRemoteWake(wakeId, "no_data");
      return;
    }

    final run = _runRemoteWakeInternal(
      wakeId,
      nativeElapsed: nativeElapsed,
      route: route,
    );
    _remoteWakeInFlight = run;
    try {
      await run;
    } finally {
      if (identical(_remoteWakeInFlight, run)) {
        _remoteWakeInFlight = null;
      }
    }
  }

  Future<void> _runRemoteWakeInternal(
    String wakeId, {
    Duration nativeElapsed = Duration.zero,
    IosRemoteWakeRoute? route,
  }) async {
    var result = "no_data";
    // Started BEFORE init, not before the catch-up. A cold background launch
    // spends the expensive part here, and native's deadline is running the
    // whole time.
    final sinceWake = Stopwatch()..start();
    var spentBeforeDart = nativeElapsed;
    try {
      ensureBindingInit();
      // Ask native how long it has ACTUALLY been holding this wake, now that
      // Dart is here. The number that arrived with the wake was measured when
      // native sent it, and on a cold launch Flutter buffers that message
      // until this handler exists - so the engine boot sits between the two
      // and would otherwise be charged to neither. Native's own answer covers
      // everything up to this round trip, so the stopwatch restarts from here
      // rather than counting the same milliseconds twice.
      final queried = await _remoteWakeElapsedFromNative(wakeId);
      if (queried != null && queried > spentBeforeDart) {
        spentBeforeDart = queried;
        sinceWake.reset();
      }
      loading ??= initNecessary();
      await loading;
      final manager = clientManager;
      if (manager != null) {
        final outcome = await IosRemoteWake.handle(
          manager: manager,
          budget: IosRemoteWake.syncBudgetAfter(
            spentBeforeDart + sinceWake.elapsed,
          ),
          // Two different quantities on purpose: `nativeElapsed` is native's
          // share, reported in the log so a capture can tell the halves
          // apart, while `spent` is the whole of the deadline already gone,
          // which is what the release window has to be measured against.
          nativeElapsed: spentBeforeDart,
          spent: spentBeforeDart + sinceWake.elapsed,
          route: route,
        );
        result = switch (outcome) {
          RemoteWakeOutcome.caughtUp => "new_data",
          RemoteWakeOutcome.failed => "failed",
          _ => "no_data",
        };
      }
    } catch (error) {
      result = "failed";
      Log.w(
        'remote_wake handler error=${error.runtimeType}',
        category: LogCategory.notifications,
        source: 'ios-notifier',
      );
    } finally {
      await _completeRemoteWake(wakeId, result);
    }
  }

  /// Native's elapsed time for [wakeId], measured when it answers. `null`
  /// when native has no such wake any more (it completed on the deadline or
  /// the assertion expired) or the platform has no such method, in which case
  /// the caller keeps the value the wake arrived with.
  Future<Duration?> _remoteWakeElapsedFromNative(String wakeId) async {
    try {
      final raw = await _channel.invokeMethod<Object?>("remoteWakeElapsed", {
        "wake_id": wakeId,
      });
      return IosRemoteWake.clampNativeElapsed(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _completeRemoteWake(String wakeId, String result) async {
    try {
      await _channel.invokeMethod<bool>("completeRemoteWake", {
        "wake_id": wakeId,
        "result": result,
      });
    } on MissingPluginException {
      // Nothing to complete on this platform.
    } on PlatformException {
      // Native already completed it (deadline or expiry).
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
        final isRichPreview = notification.allowsRichActions;
        final attachmentType = notification.attachmentPresentation?.type;
        final attachment =
            isRichPreview &&
                (attachmentType == NotificationAttachmentType.image ||
                    attachmentType == NotificationAttachmentType.gif ||
                    attachmentType == NotificationAttachmentType.sticker)
            ? await _prepareRichImageAttachment(notification.attachedImage)
            : null;
        // The dedupe modifier let this through, so either the extension never
        // delivered this event or it delivered the generic fallback; in the
        // second case the app's copy replaces it.
        await removeDeliveredRemoteNotification(notification.eventId);
        return _showNotification(
          id: NotificationIdentity.messageNotificationId(notification),
          title: notification.senderName,
          body:
              notification.attachmentPresentation?.displayText ??
              notification.content,
          subtitle: notification.roomName,
          payload: OpenRoomURI(
            roomId: notification.roomId,
            clientId: notification.clientId,
          ).toString(),
          threadIdentifier: NotificationIdentity.roomKeyForMessage(
            notification,
          ),
          categoryIdentifier: isRichPreview
              ? _richMessageCategoryId
              : _roomSnoozeCategoryId,
          attachments: attachment == null ? null : [attachment],
        );
      case StoryNotificationContent _:
        // An encrypted story event can reach the NSE before the host sync has
        // resolved story policy and content. Once the policy-approved story
        // notification is ready, replace that remote generic for the same
        // event instead of leaving both in Notification Center.
        await removeDeliveredRemoteNotification(notification.eventId);
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
    List<DarwinNotificationAttachment>? attachments,
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
      attachments: attachments,
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

  Future<DarwinNotificationAttachment?> _prepareRichImageAttachment(
    ImageProvider? imageProvider,
  ) async {
    if (imageProvider == null) {
      return null;
    }
    final path = await prepareIosNotificationPreview(
      imageProvider,
      _protectPreviewFile,
    );
    return path == null ? null : DarwinNotificationAttachment(path);
  }

  Future<bool> _protectPreviewFile(String path) async {
    try {
      return await _channel.invokeMethod<bool>(
            'protectNotificationPreviewFile',
            {'path': path},
          ) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
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
        // Record this as a successful reconcile so the resume watchdog and the
        // post-update forced refresh treat the registration as current.
        _lastReconcileAt = DateTime.now();
        _lastReconcileSucceeded = true;
        await preferences.setIosLastPushReconcileVersion(
          BuildConfig.VERSION_TAG,
        );
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
    await removeDeliveredRemoteNotificationsForRoom(
      clientId: room.client.identifier,
      roomId: room.identifier,
    );
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
    await removeDeliveredRemoteNotificationsForRoom(
      clientId: clientId,
      roomId: roomId,
    );
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
