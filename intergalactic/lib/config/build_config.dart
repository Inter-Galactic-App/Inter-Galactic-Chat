// ignore_for_file: constant_identifier_names

import 'package:flutter/foundation.dart';

class BuildConfig {
  static const String _buildMode = String.fromEnvironment(
    'BUILD_MODE',
    defaultValue: _Constants.release,
  );

  static const String PLATFORM = String.fromEnvironment(
    'PLATFORM',
    defaultValue: _Constants._desktop,
  );

  /// Whether the build actually declared `--dart-define=PLATFORM=...`.
  ///
  /// Release builds always do. Ad-hoc `flutter run` / `flutter build apk`
  /// invocations do not, and [PLATFORM] then falls back to its `desktop`
  /// default - which silently produced Android builds that reported
  /// `platform=desktop`, laid themselves out as a desktop app, and skipped
  /// every `BuildConfig.ANDROID` code path.
  static const bool _platformDeclared = bool.hasEnvironment('PLATFORM');

  /// The platform this build is actually running on, used only when the build
  /// did not declare one. An explicit define always wins, so release behaviour
  /// is unchanged and a build can still be told to pretend.
  static String get _detectedPlatform {
    if (kIsWeb) return _Constants._web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _Constants._android,
      TargetPlatform.iOS => _Constants._ios,
      TargetPlatform.windows => _Constants._windows,
      TargetPlatform.linux => _Constants._linux,
      TargetPlatform.macOS => _Constants._macos,
      TargetPlatform.fuchsia => _Constants._desktop,
    };
  }

  /// The effective platform: the declared one when present, otherwise the real
  /// one. Prefer this over [PLATFORM] for behaviour and for reporting.
  static String get resolvedPlatform =>
      _platformDeclared ? PLATFORM : _detectedPlatform;

  static const String GIT_HASH = String.fromEnvironment(
    'GIT_HASH',
    defaultValue: "unknown",
  );

  static const String VERSION_TAG = String.fromEnvironment(
    'VERSION_TAG',
    defaultValue: "development",
  );

  // Details about build, like "flatpak", "fdroid"
  static const String BUILD_DETAIL = String.fromEnvironment(
    'BUILD_DETAIL',
    defaultValue: "default",
  );

  static const bool ENABLE_GOOGLE_SERVICES = bool.fromEnvironment(
    "ENABLE_GOOGLE_SERVICES",
    defaultValue: false,
  );

  static const bool ENABLE_NATIVE_DETACHED_CALL_WINDOWS = bool.fromEnvironment(
    "ENABLE_NATIVE_DETACHED_CALL_WINDOWS",
    defaultValue: true,
  );

  static const String WEB_PUSH_VAPID_PUBLIC_KEY = String.fromEnvironment(
    "WEB_PUSH_VAPID_PUBLIC_KEY",
    defaultValue: "",
  );

  static const String KLIPY_API_KEY = String.fromEnvironment(
    "KLIPY_API_KEY",
    defaultValue: "",
  );

  static const String defaultGifApiBaseUrl =
      "https://api.ourgalaxy.space/klipy";

  static const String GIF_API_BASE_URL = String.fromEnvironment(
    "GIF_API_BASE_URL",
    defaultValue: defaultGifApiBaseUrl,
  );

  static const String INTERGALACTIC_URL_PREVIEW_ENDPOINT =
      String.fromEnvironment(
        "INTERGALACTIC_URL_PREVIEW_ENDPOINT",
        defaultValue: "",
      );

  static const String INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS =
      String.fromEnvironment(
        "INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS",
        defaultValue: "ourgalaxy.space,matrix.ourgalaxy.space",
      );

  static const String INTERGALACTIC_ACCOUNT_RECOVERY_ENDPOINT =
      String.fromEnvironment(
        "INTERGALACTIC_ACCOUNT_RECOVERY_ENDPOINT",
        defaultValue:
            "https://ourgalaxy.space/api/intergalactic/account-recovery",
      );

  static const String INTERGALACTIC_SOUNDBOARD_AUTHORITY_ENDPOINT =
      String.fromEnvironment(
        "INTERGALACTIC_SOUNDBOARD_AUTHORITY_ENDPOINT",
        defaultValue: "https://ourgalaxy.space/api/intergalactic/soundboard/v1",
      );

  static const String INTERGALACTIC_ACCOUNT_RECOVERY_ALLOWED_HOMESERVERS =
      String.fromEnvironment(
        "INTERGALACTIC_ACCOUNT_RECOVERY_ALLOWED_HOMESERVERS",
        defaultValue: "ourgalaxy.space,matrix.ourgalaxy.space",
      );

  static const String SPOTIFY_CLIENT_ID = String.fromEnvironment(
    "SPOTIFY_CLIENT_ID",
    defaultValue: "",
  );

  static const String SPOTIFY_REDIRECT_URI = String.fromEnvironment(
    "SPOTIFY_REDIRECT_URI",
    defaultValue: "",
  );

  static const String STEAM_ACTIVITY_API_BASE_URL = String.fromEnvironment(
    "STEAM_ACTIVITY_API_BASE_URL",
    defaultValue: "",
  );

  static const String UPDATE_MANIFEST_URL = String.fromEnvironment(
    "UPDATE_MANIFEST_URL",
    defaultValue: "",
  );

  static const bool DEBUG = _buildMode == _Constants._debug;

  static const bool RELEASE = _buildMode == _Constants.release;

  // WEB stays a compile-time constant: kIsWeb already answers it correctly
  // without a define, so it needs no runtime fallback and conditional code can
  // keep relying on it being const.
  static const bool WEB = PLATFORM == _Constants._web || kIsWeb;

  // The native platform flags resolve at runtime so that a build which forgot
  // the PLATFORM define still behaves as the platform it is actually running
  // on. An explicit define still wins via resolvedPlatform.
  static bool get DESKTOP =>
      !WEB &&
      (resolvedPlatform == _Constants._desktop ||
          resolvedPlatform == _Constants._linux ||
          resolvedPlatform == _Constants._windows ||
          resolvedPlatform == _Constants._macos);

  static bool get MOBILE =>
      !WEB &&
      (resolvedPlatform == _Constants._mobile ||
          resolvedPlatform == _Constants._android ||
          resolvedPlatform == _Constants._ios);

  static bool get ANDROID => resolvedPlatform == _Constants._android;

  static bool get WINDOWS => resolvedPlatform == _Constants._windows;

  static bool get LINUX => resolvedPlatform == _Constants._linux;

  static const bool IS_FLATPAK = BUILD_DETAIL == "flatpak";

  static bool get MAC => resolvedPlatform == _Constants._macos;

  static bool get IOS => resolvedPlatform == _Constants._ios;

  static const bool SUPPORTS_CACHE = !WEB;

  static const String app = "Inter Galactic";

  static const String originalApp = "Commet";

  static const String originalCreator = "commetchat";

  static const String forkDeveloper = "Nick Towle";

  static const String originalSourceUrl =
      "https://github.com/commetchat/commet";

  static const String originalWebsiteUrl = "https://commet.chat";

  static const String licenseName = "GNU AGPL v3.0";

  static const String forkNoticeDate = "2026-04-09";

  static const String appSchema = "space.ourgalaxy";

  static const String androidPushGatewayHost = "push.ourgalaxy.space";

  static const String androidEmbeddedNtfyBaseUrl =
      "https://$androidPushGatewayHost";

  static const String androidPushAppId = "chat.intergalactic.app.android";

  static const String iosBundleId = "chat.intergalactic.app";

  static const String iosPushAppId = "chat.intergalactic.app.ios";

  static const String iosBroadcastExtensionBundleId =
      "chat.intergalactic.app.broadcast";

  static const String iosAppGroupId = "group.chat.intergalactic.app";

  static const String webPushAppId = "chat.intergalactic.app.web";

  static const String windowsAumId = "chat.intergalactic.app.windows-832a9c4f";

  static const String windowsToastClsid =
      "A1F4D8E2-44E5-4A0A-8B91-8D2B18B9D832";

  static const String windowsTempNamespace = "chat.intergalactic.app";

  static const bool ALLOW_UNVERIFIED_WINDOWS_UPDATER = bool.fromEnvironment(
    "ALLOW_UNVERIFIED_WINDOWS_UPDATER",
    defaultValue: false,
  );

  static const String _BUILD_DATE = String.fromEnvironment(
    'BUILD_DATE',
    defaultValue: "0",
  );

  static final DateTime _fallbackBuildDate = DateTime.now();

  static DateTime get BUILD_DATE {
    final timestamp = int.tryParse(_BUILD_DATE) ?? 0;
    if (timestamp <= 0) {
      return _fallbackBuildDate;
    }

    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  static String get buildDetailDisplay {
    final detail = BUILD_DETAIL.trim();
    if (detail.isEmpty || detail == "default") {
      return forkDeveloper;
    }

    return detail;
  }

  static String get buildSummaryDisplay {
    final parts = <String>[
      if (GIT_HASH != "unknown" && GIT_HASH.length >= 7)
        GIT_HASH.substring(0, 7),
      buildDetailDisplay,
    ];

    return parts.join(" ");
  }

  static String get platformDisplay {
    if (WEB) return _Constants._web;
    if (ANDROID) return _Constants._android;
    if (IOS) return _Constants._ios;
    if (WINDOWS) return _Constants._windows;
    if (LINUX) return _Constants._linux;
    if (MAC) return _Constants._macos;
    return resolvedPlatform;
  }

  static String get buildFingerprintDisplay {
    return [VERSION_TAG, buildSummaryDisplay, platformDisplay].join(" · ");
  }

  // IM SO SORRY
  static String get appName => MOBILE
      ? (ANDROID
            ? "$app for Android"
            : (IOS ? "$app for iOS" : "$app for Mobile"))
      : (DESKTOP
            ? (WINDOWS
                  ? "$app for Windows"
                  : LINUX
                  ? "$app for Linux"
                  : MAC
                  ? "$app for MacOS"
                  : "$app for Desktop")
            : WEB
            ? "$app for Web"
            : app);

  static String get matrixDeviceDisplayName => "$appName $VERSION_TAG";

  static String get matrixUserAgent {
    return "InterGalactic/$VERSION_TAG ($platformDisplay; $buildSummaryDisplay)";
  }

  static String get matrixClientDiagnosticsLabel {
    return "$appName $buildFingerprintDisplay";
  }

  static Map<String, dynamic> get matrixClientMetadata => {
    "app": app,
    "app_name": appName,
    "version": VERSION_TAG,
    "platform": platformDisplay,
    "build_detail": BUILD_DETAIL,
    "git_hash": GIT_HASH,
    "device_display_name": matrixDeviceDisplayName,
    "user_agent": matrixUserAgent,
    "diagnostics_label": matrixClientDiagnosticsLabel,
  };
}

class _Constants {
  static const String _debug = "debug";

  static const String release = "release";

  static const String _desktop = "desktop";

  static const String _linux = "linux";

  static const String _windows = "windows";

  static const String _macos = "macos";

  static const String _ios = "ios";

  static const String _android = "android";

  static const String _mobile = "mobile";

  static const String _web = "web";
}
