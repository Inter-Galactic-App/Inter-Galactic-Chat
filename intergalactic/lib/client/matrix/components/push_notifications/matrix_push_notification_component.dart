import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/push_notification_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:matrix/matrix.dart';

class MatrixPushNotificationComponent
    implements PushNotificationComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixPushNotificationComponent(this.client);

  static const String? desiredPushFormat = null;
  // Fork-specific Android FCM pushers use Matrix pusher data.format as the
  // gateway contract for data-only wake notifications.
  static const String androidFcmDesiredPushFormat = "data_only";
  static const String androidFcmPusherSchema =
      "android_fcm_lightweight_background_v2";

  static const Set<String> legacyAndroidPushAppIds = {
    "chat.commet.commetapp.android",
    "chat.commet.app.android",
  };
  static const Set<String> legacyIosPushAppIds = {
    "chat.commet.commetapp.ios",
    "chat.commet.app.ios",
  };

  static bool isLegacyAndroidPushAppId(String appId) =>
      legacyAndroidPushAppIds.contains(appId);
  static bool isLegacyIosPushAppId(String appId) =>
      legacyIosPushAppIds.contains(appId);

  String get pushAppId {
    if (BuildConfig.WEB) {
      return BuildConfig.webPushAppId;
    }

    if (BuildConfig.IOS) {
      return BuildConfig.iosPushAppId;
    }

    return BuildConfig.androidPushAppId;
  }

  @override
  Future<void> ensurePushNotificationsRegistered(
    String pushKey,
    Uri pushServer,
    String deviceName, {
    Map<String, dynamic>? extraData,
  }) async {
    var matrixClient = client.getMatrixClient();
    var appId = pushAppId;
    final desiredFormat = _desiredPushFormat(extraData);

    Log.i(
      "Current push key: ${_pushKeyDiagnostic(pushKey)}",
      category: LogCategory.notifications,
      source: 'matrix-pusher',
    );

    var pushers = await matrixClient.getPushers();

    if (pushers != null &&
        pushers.any(
          (element) => _isMatchingPusher(
            element,
            appId: appId,
            pushKey: pushKey,
            pushServer: pushServer,
            desiredFormat: desiredFormat,
            extraData: extraData,
          ),
        )) {
      Log.i(
        "Matrix pusher already matches current push registration",
        category: LogCategory.notifications,
        source: 'matrix-pusher',
      );
      return;
    }

    var pusher = Pusher(
      appId: appId,
      pushkey: pushKey,
      appDisplayName: BuildConfig.appName,
      data: PusherData(
        format: desiredFormat,
        url: pushServer,
        additionalProperties: extraData ?? {},
      ),
      deviceDisplayName: deviceName,
      kind: "http",
      lang: "en",
    );

    Log.i(
      "Registering Matrix pusher ${pusher.appId} "
      "format=${_formatDiagnostic(desiredFormat)} "
      "gateway=${pushServer.host} metadata=${_metadataDiagnostic(extraData)}",
      category: LogCategory.notifications,
      source: 'matrix-pusher',
    );
    await matrixClient.postPusher(pusher, append: true);
  }

  Future<void> cleanOldPushers(
    String? currentPushKey,
    String deviceName,
    Uri pushGateway, {
    Map<String, dynamic>? extraData,
  }) async {
    var matrixClient = client.getMatrixClient();
    var pushers = await matrixClient.getPushers();
    var currentAppId = pushAppId;

    // Check for stale pushers
    if (pushers != null) {
      for (var pusher in pushers) {
        final staleReason = _stalePusherReason(
          pusher,
          currentAppId: currentAppId,
          currentPushKey: currentPushKey,
          deviceName: deviceName,
          pushGateway: pushGateway,
          extraData: extraData,
        );

        _logPusherComparison(
          pusher,
          currentAppId: currentAppId,
          currentPushKey: currentPushKey,
          deviceName: deviceName,
          pushGateway: pushGateway,
          extraData: extraData,
          staleReason: staleReason,
        );

        if (staleReason != null) {
          Log.i(
            "Deleting stale pusher ${pusher.appId}: $staleReason",
            category: LogCategory.notifications,
            source: 'matrix-pusher',
          );
          await matrixClient.deletePusher(pusher);
        }
      }
    }
  }

  String? _stalePusherReason(
    Pusher pusher, {
    required String currentAppId,
    required String? currentPushKey,
    required String deviceName,
    required Uri pushGateway,
    Map<String, dynamic>? extraData,
  }) {
    return stalePusherReasonForTesting(
      pusher,
      currentAppId: currentAppId,
      currentPushKey: currentPushKey,
      deviceName: deviceName,
      pushGateway: pushGateway,
      extraData: extraData,
      isAndroid: BuildConfig.ANDROID,
      isIos: BuildConfig.IOS,
      googleServicesEnabled: BuildConfig.ENABLE_GOOGLE_SERVICES,
    );
  }

  @visibleForTesting
  static String? stalePusherReasonForTesting(
    Pusher pusher, {
    required String currentAppId,
    required String? currentPushKey,
    required String deviceName,
    required Uri pushGateway,
    Map<String, dynamic>? extraData,
    required bool isAndroid,
    required bool isIos,
    required bool googleServicesEnabled,
  }) {
    final currentDeviceId = extraData?['device_id'];

    final globallyStaleAndroidReason = _globallyStaleAndroidPusherReason(
      pusher,
      currentAppId: currentAppId,
      isAndroid: isAndroid,
      googleServicesEnabled: googleServicesEnabled,
    );
    if (globallyStaleAndroidReason != null) {
      return globallyStaleAndroidReason;
    }

    final globallyStaleIosReason = _globallyStaleIosPusherReason(
      pusher,
      currentAppId: currentAppId,
      isIos: isIos,
    );
    if (globallyStaleIosReason != null) {
      return globallyStaleIosReason;
    }

    if (!_isSameInstallPusher(
      pusher,
      currentAppId: currentAppId,
      currentPushKey: currentPushKey,
      currentDeviceId: currentDeviceId,
      deviceName: deviceName,
      isAndroid: isAndroid,
      isIos: isIos,
    )) {
      return null;
    }

    if (pusher.deviceDisplayName != deviceName) {
      return "different device display name";
    }

    if (pusher.appId != currentAppId) {
      return "different app id";
    }

    if (currentPushKey == null) {
      return null;
    }

    if (pusher.pushkey != currentPushKey) {
      return "different push key";
    }

    final desiredFormat = _desiredPushFormat(
      extraData,
      isAndroid: isAndroid,
      googleServicesEnabled: googleServicesEnabled,
    );
    if (!_pushFormatMatches(
      pusher.data.format,
      desiredFormat,
      extraData: extraData,
      isAndroid: isAndroid,
      googleServicesEnabled: googleServicesEnabled,
    )) {
      return "different push format "
          "(actual=${_formatDiagnostic(pusher.data.format)}, "
          "expected=${_formatDiagnostic(desiredFormat)})";
    }

    if (pusher.data.url != pushGateway) {
      return "different push gateway";
    }

    if (!_hasExpectedExtraData(pusher, extraData)) {
      return "different push metadata";
    }

    return null;
  }

  static String? _globallyStaleIosPusherReason(
    Pusher pusher, {
    required String currentAppId,
    required bool isIos,
  }) {
    if (!isIos) {
      return null;
    }

    if (isLegacyIosPushAppId(pusher.appId)) {
      return "legacy iOS app id";
    }

    return null;
  }

  static String? _globallyStaleAndroidPusherReason(
    Pusher pusher, {
    required String currentAppId,
    required bool isAndroid,
    required bool googleServicesEnabled,
  }) {
    if (!isAndroid) {
      return null;
    }

    if (isLegacyAndroidPushAppId(pusher.appId)) {
      return "legacy Android app id";
    }

    if (googleServicesEnabled &&
        _isKnownAndroidPushAppId(pusher.appId, currentAppId: currentAppId) &&
        _isUrlPushKey(pusher.pushkey)) {
      return "Android FCM build cannot use URL push key";
    }

    return null;
  }

  static bool _isKnownAndroidPushAppId(
    String appId, {
    required String currentAppId,
  }) {
    return appId == currentAppId ||
        appId == BuildConfig.androidPushAppId ||
        isLegacyAndroidPushAppId(appId);
  }

  static bool _isKnownIosPushAppId(
    String appId, {
    required String currentAppId,
  }) {
    return appId == currentAppId ||
        appId == BuildConfig.iosPushAppId ||
        isLegacyIosPushAppId(appId);
  }

  static bool _isSameInstallPusher(
    Pusher pusher, {
    required String currentAppId,
    required String? currentPushKey,
    required Object? currentDeviceId,
    required String deviceName,
    bool isAndroid = BuildConfig.ANDROID,
    bool isIos = BuildConfig.IOS,
  }) {
    final pusherDeviceId = pusher.data.additionalProperties['device_id'];
    if (_isNonEmptyString(currentDeviceId) &&
        _isNonEmptyString(pusherDeviceId) &&
        pusherDeviceId == currentDeviceId) {
      return true;
    }

    if (isAndroid &&
        currentPushKey != null &&
        currentPushKey.isNotEmpty &&
        pusher.pushkey == currentPushKey &&
        _isKnownAndroidPushAppId(pusher.appId, currentAppId: currentAppId)) {
      return true;
    }

    if (isIos &&
        currentPushKey != null &&
        currentPushKey.isNotEmpty &&
        pusher.pushkey == currentPushKey &&
        _isKnownIosPushAppId(pusher.appId, currentAppId: currentAppId)) {
      return true;
    }

    return pusher.deviceDisplayName == deviceName;
  }

  static bool _isNonEmptyString(Object? value) {
    return value is String && value.isNotEmpty;
  }

  bool _isMatchingPusher(
    Pusher pusher, {
    required String appId,
    required String pushKey,
    required Uri pushServer,
    required String? desiredFormat,
    Map<String, dynamic>? extraData,
  }) {
    return pusher.pushkey == pushKey &&
        pusher.appId == appId &&
        _pushFormatMatches(
          pusher.data.format,
          desiredFormat,
          extraData: extraData,
        ) &&
        pusher.data.url == pushServer &&
        _hasExpectedExtraData(pusher, extraData);
  }

  static String? _desiredPushFormat(
    Map<String, dynamic>? extraData, {
    bool isAndroid = BuildConfig.ANDROID,
    bool googleServicesEnabled = BuildConfig.ENABLE_GOOGLE_SERVICES,
  }) {
    if (_isAndroidFcmRegistration(
      extraData,
      isAndroid: isAndroid,
      googleServicesEnabled: googleServicesEnabled,
    )) {
      return androidFcmDesiredPushFormat;
    }

    return desiredPushFormat;
  }

  static bool _isAndroidFcmRegistration(
    Map<String, dynamic>? extraData, {
    bool isAndroid = BuildConfig.ANDROID,
    bool googleServicesEnabled = BuildConfig.ENABLE_GOOGLE_SERVICES,
  }) {
    return isAndroid &&
        googleServicesEnabled &&
        extraData?['registration_schema'] == androidFcmPusherSchema;
  }

  static bool _pushFormatMatches(
    String? actual,
    String? expected, {
    required Map<String, dynamic>? extraData,
    bool isAndroid = BuildConfig.ANDROID,
    bool googleServicesEnabled = BuildConfig.ENABLE_GOOGLE_SERVICES,
  }) {
    if (actual == expected) {
      return true;
    }

    if (_isAndroidFcmRegistration(
      extraData,
      isAndroid: isAndroid,
      googleServicesEnabled: googleServicesEnabled,
    )) {
      return false;
    }

    return false;
  }

  static bool _hasExpectedExtraData(
    Pusher pusher,
    Map<String, dynamic>? expectedExtraData,
  ) {
    if (expectedExtraData == null || expectedExtraData.isEmpty) {
      return true;
    }

    final data = pusher.data.toJson();
    for (final entry in expectedExtraData.entries) {
      if (!data.containsKey(entry.key)) {
        return false;
      }

      if (_jsonComparable(data[entry.key]) != _jsonComparable(entry.value)) {
        return false;
      }
    }

    return true;
  }

  static String _jsonComparable(dynamic value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  void _logPusherComparison(
    Pusher pusher, {
    required String currentAppId,
    required String? currentPushKey,
    required String deviceName,
    required Uri pushGateway,
    required Map<String, dynamic>? extraData,
    required String? staleReason,
  }) {
    final currentDeviceId = extraData?['device_id'];
    final pusherDeviceId = pusher.data.additionalProperties['device_id'];
    final deviceIdsMatch = _isNonEmptyString(currentDeviceId) &&
        _isNonEmptyString(pusherDeviceId) &&
        pusherDeviceId == currentDeviceId;
    final desiredFormat = _desiredPushFormat(extraData);
    final message = "Matrix pusher comparison "
        "sameInstall=${_isSameInstallPusher(pusher, currentAppId: currentAppId, currentPushKey: currentPushKey, currentDeviceId: currentDeviceId, deviceName: deviceName)} "
        "appIdMatches=${pusher.appId == currentAppId} "
        "pushKeyMatches=${currentPushKey != null && pusher.pushkey == currentPushKey} "
        "deviceNameMatches=${pusher.deviceDisplayName == deviceName} "
        "deviceIdMatches=$deviceIdsMatch "
        "format=${_formatDiagnostic(pusher.data.format)} "
        "expectedFormat=${_formatDiagnostic(desiredFormat)} "
        "formatMatches=${_pushFormatMatches(pusher.data.format, desiredFormat, extraData: extraData)} "
        "gatewayMatches=${pusher.data.url == pushGateway} "
        "metadataMatches=${_hasExpectedExtraData(pusher, extraData)} "
        "pushKey=${_pushKeyDiagnostic(pusher.pushkey)} "
        "currentPushKey=${_pushKeyDiagnostic(currentPushKey)} "
        "metadata=${_metadataDiagnostic(extraData)} "
        "staleReason=${staleReason ?? 'none'}";

    if (staleReason == null) {
      Log.d(
        message,
        category: LogCategory.notifications,
        source: 'matrix-pusher',
      );
      return;
    }

    Log.w(
      message,
      category: LogCategory.notifications,
      source: 'matrix-pusher',
    );
  }

  String _pushKeyDiagnostic(String? pushKey) {
    if (pushKey == null) {
      return "none";
    }

    if (pushKey.isEmpty) {
      return "empty";
    }

    final uri = Uri.tryParse(pushKey);
    if (uri != null &&
        (uri.scheme == "http" || uri.scheme == "https") &&
        uri.hasAuthority) {
      return "url(host=${uri.host}, length=${pushKey.length})";
    }

    return "token(length=${pushKey.length})";
  }

  static String _formatDiagnostic(String? format) {
    return format == null || format.isEmpty ? "default" : format;
  }

  String _metadataDiagnostic(Map<String, dynamic>? extraData) {
    if (extraData == null || extraData.isEmpty) {
      return "none";
    }

    final parts = <String>[];
    for (final key in [
      'type',
      'transport',
      'provider',
      'format',
      'registration_schema',
    ]) {
      final value = extraData[key];
      if (value != null) {
        parts.add('$key=$value');
      }
    }

    for (final key in ['device_id', 'client_id']) {
      if (_isNonEmptyString(extraData[key])) {
        parts.add('$key=present');
      }
    }

    const knownMetadataKeys = {
      'type',
      'transport',
      'provider',
      'format',
      'registration_schema',
      'device_id',
      'client_id',
    };
    final extraKeys = extraData.keys
        .where((key) => !knownMetadataKeys.contains(key))
        .toList()
      ..sort();
    if (extraKeys.isNotEmpty) {
      parts.add('extraKeys=${extraKeys.join(",")}');
    }

    return parts.isEmpty ? "keys=${extraData.keys.length}" : parts.join(';');
  }

  static bool _isUrlPushKey(String pushKey) {
    final uri = Uri.tryParse(pushKey);
    return uri != null &&
        (uri.scheme == "http" || uri.scheme == "https") &&
        uri.hasAuthority;
  }

  @override
  Future<void> updatePushers() async {
    if (NotificationManager.notifierLoading != null) {
      await NotificationManager.notifierLoading!.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException("Push notifier initialization timed out");
        },
      );
    }
    var notifier = NotificationManager.notifier;
    if (notifier == null) {
      throw StateError("Push notifier is not initialized");
    }
    String? key;
    Object? tokenError;
    StackTrace? tokenStackTrace;

    try {
      key = await notifier.getToken().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException("Push token fetch timed out");
        },
      );
    } catch (e, s) {
      tokenError = e;
      tokenStackTrace = s;
      Log.w("Failed to fetch push notification token");
      Log.onError(e, s);
    }

    var mxClient = client.getMatrixClient();
    var extraData = <String, dynamic>{
      ...?notifier.extraRegistrationData(),
      if (mxClient.deviceID != null) "device_id": mxClient.deviceID,
      "client_id": client.identifier,
    };
    if (BuildConfig.ANDROID && BuildConfig.ENABLE_GOOGLE_SERVICES) {
      extraData["registration_schema"] = androidFcmPusherSchema;
    }
    var name = mxClient.clientName;

    var uri = Uri.parse(preferences.pushGateway);
    if (uri.hasScheme == false) {
      uri = Uri.https(preferences.pushGateway);
    }

    uri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.port,
      path: "/_matrix/push/v1/notify",
    );

    if (key == null) {
      await cleanOldPushers(key, name, uri, extraData: extraData);

      if (!notifier.needsToken) {
        Log.w("Push notifier does not use remote Matrix push tokens");
        return;
      }

      if (tokenError != null) {
        Error.throwWithStackTrace(
          StateError("Push notifier did not provide a token: $tokenError"),
          tokenStackTrace ?? StackTrace.current,
        );
      }

      throw StateError("Push notifier did not provide a token");
    }

    await cleanOldPushers(key, name, uri, extraData: extraData);

    await ensurePushNotificationsRegistered(
      key,
      uri,
      name,
      extraData: extraData,
    );
  }

  @override
  void postLoginInit() async {
    try {
      await updatePushers();
    } catch (e, s) {
      Log.w("Failed to refresh pushers after login");
      Log.onError(e, s);
    }
  }
}
