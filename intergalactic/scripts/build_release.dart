// ignore_for_file: avoid_print

import 'dart:io';

String? getArg(List<String> args, String name) {
  final inlinePrefix = "$name=";
  for (final arg in args) {
    if (arg.startsWith(inlinePrefix)) {
      final value = arg.substring(inlinePrefix.length);
      if (value.isEmpty) {
        stderr.writeln("Missing value for $name.");
        exit(64);
      }

      return value;
    }
  }

  int index = args.indexOf(name);
  if (index == -1) return null;

  if (index >= args.length - 1 || args[index + 1].startsWith("--")) {
    stderr.writeln("Missing value for $name.");
    exit(64);
  }

  return args[index + 1];
}

class ReleaseIdentity {
  const ReleaseIdentity({
    required this.tag,
    required this.versionName,
    required this.buildNumber,
  });

  final String tag;
  final String versionName;
  final String buildNumber;
}

ReleaseIdentity parseReleaseIdentity(String versionTag) {
  final match =
      RegExp(r'^v?(\d+\.\d+\.\d+)\+(\d+)$').firstMatch(versionTag.trim());
  if (match == null) {
    stderr.writeln(
      "Release version tag must use full pubspec identity, for example v0.7.0+968.",
    );
    stderr.writeln("Received: '$versionTag'");
    exit(64);
  }

  return ReleaseIdentity(
    tag: "v${match[1]}+${match[2]}",
    versionName: match[1]!,
    buildNumber: match[2]!,
  );
}

String getVersionTag(List<String> args) {
  var tag = getArg(args, "--version_tag");
  if (tag != null) {
    return tag;
  }

  return "v0.0.0+0";
}

String getPlatform(List<String> args) {
  return getArg(args, "--platform")!;
}

String getHash(List<String> args) {
  return getArg(args, "--git_hash") ?? "unknown";
}

String getEnableGoogleServices(List<String> args) {
  return getArg(args, "--enable_google_services") ?? "false";
}

void validateGoogleServicesBuild(String platform, String enableGoogleServices) {
  if (platform != "android") {
    return;
  }

  if (enableGoogleServices.toLowerCase() != "true") {
    return;
  }

  final requiredMarkers = {
    "pubspec.yaml": RegExp(r"^\s*firebase_core:", multiLine: true),
    "android/app/build.gradle": RegExp(
      r"^\s*id 'com\.google\.gms\.google-services'",
      multiLine: true,
    ),
    "android/settings.gradle": RegExp(
      r'^\s*id "com\.google\.gms\.google-services"',
      multiLine: true,
    ),
    "lib/client/components/push_notification/android/firebase_push_notifier.dart":
        RegExp(
      r"^import 'package:firebase_core/firebase_core\.dart';",
      multiLine: true,
    ),
    "lib/firebase_options.dart": RegExp(
      r"^import 'package:firebase_core/firebase_core\.dart' show FirebaseOptions;",
      multiLine: true,
    ),
  };

  final missing = <String>[];
  for (final entry in requiredMarkers.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      missing.add(entry.key);
      continue;
    }

    final content = file.readAsStringSync();
    final isFirebaseOptionsCommented =
        entry.key == "lib/firebase_options.dart" &&
            RegExp(r"// ignore_for_file: type=lint\s*/\*", multiLine: true)
                .hasMatch(content);

    if (!entry.value.hasMatch(content) || isFirebaseOptionsCommented) {
      missing.add(entry.key);
    }
  }

  if (missing.isEmpty) {
    return;
  }

  stderr.writeln(
      "Google Services build requested, but Firebase source toggles are not active.");
  stderr.writeln(
      "Run `scripts/set_google_services.ps1 enable` after staging owner-local "
      "Firebase config before building the FCM APK.");
  stderr.writeln("Missing active markers in:");
  for (final file in missing) {
    stderr.writeln("- $file");
  }
  exit(65);
}

String getEnableNativeDetachedCallWindows(List<String> args) {
  return getArg(args, "--enable_native_detached_call_windows") ??
      Platform.environment["ENABLE_NATIVE_DETACHED_CALL_WINDOWS"] ??
      "true";
}

String getIosExportMethod(List<String> args) {
  return getArg(args, "--ios_export_method") ?? "app-store";
}

String getUpdateManifestUrl(List<String> args) {
  return getArg(args, "--update_manifest_url") ??
      Platform.environment["UPDATE_MANIFEST_URL"] ??
      "";
}

String getKlipyApiKey(List<String> args) {
  return getArg(args, "--klipy_api_key") ??
      Platform.environment["KLIPY_API_KEY"] ??
      "";
}

String getGifApiBaseUrl(List<String> args) {
  return getArg(args, "--gif_api_base_url") ??
      Platform.environment["GIF_API_BASE_URL"] ??
      "";
}

String getIntergalacticUrlPreviewEndpoint(List<String> args) {
  return getArg(args, "--intergalactic_url_preview_endpoint") ??
      Platform.environment["INTERGALACTIC_URL_PREVIEW_ENDPOINT"] ??
      "";
}

String getIntergalacticUrlPreviewAllowedHomeservers(List<String> args) {
  return getArg(args, "--intergalactic_url_preview_allowed_homeservers") ??
      Platform.environment["INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS"] ??
      "";
}

void failReleaseConfig(String message) {
  stderr.writeln(message);
  exit(64);
}

void validateIntergalacticUrlPreviewConfig({
  required String endpoint,
  required String allowedHomeservers,
}) {
  if (endpoint.isNotEmpty) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) {
      failReleaseConfig(
        "INTERGALACTIC_URL_PREVIEW_ENDPOINT must be an absolute HTTPS URL.",
      );
    }
  }

  if (allowedHomeservers.isNotEmpty && endpoint.isEmpty) {
    failReleaseConfig(
      "INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS requires INTERGALACTIC_URL_PREVIEW_ENDPOINT.",
    );
  }

  for (final entry
      in allowedHomeservers.split(',').map((value) => value.trim())) {
    if (entry.isEmpty) {
      continue;
    }
    if (!_isValidAllowedHomeserverEntry(entry)) {
      failReleaseConfig(
        "Invalid INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS entry: '$entry'. Use hostnames or HTTPS origins.",
      );
    }
  }
}

bool _isValidAllowedHomeserverEntry(String entry) {
  final uri = entry.contains("://")
      ? Uri.tryParse(entry)
      : Uri.tryParse("https://$entry");
  if (uri == null || uri.host.isEmpty) {
    return false;
  }
  if (entry.contains("://") && uri.scheme != "https") {
    return false;
  }
  if (uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != "/")) {
    return false;
  }
  return _isValidHostname(uri.host);
}

bool _isValidHostname(String host) {
  final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (normalized.isEmpty ||
      normalized.length > 253 ||
      normalized.contains(RegExp(r'\s'))) {
    return false;
  }

  final labels = normalized.split('.');
  return labels.every(
    (label) =>
        label.isNotEmpty &&
        label.length <= 63 &&
        RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
  );
}

String getSpotifyClientId(List<String> args) {
  return getArg(args, "--spotify_client_id") ??
      Platform.environment["SPOTIFY_CLIENT_ID"] ??
      "";
}

String getSpotifyRedirectUri(List<String> args) {
  return getArg(args, "--spotify_redirect_uri") ??
      Platform.environment["SPOTIFY_REDIRECT_URI"] ??
      "";
}

String getSteamActivityApiBaseUrl(List<String> args) {
  return getArg(args, "--steam_activity_api_base_url") ??
      Platform.environment["STEAM_ACTIVITY_API_BASE_URL"] ??
      "";
}

bool getSkipFlutterPub(List<String> args) {
  return args.contains("--skip_flutter_pub") ||
      args.contains("--no_pub") ||
      args.contains("--no-pub") ||
      Platform.environment["INTERGALACTIC_BUILD_RELEASE_NO_PUB"] == "1";
}

bool getAllowDirectKlipyApiKey(List<String> args) {
  return args.contains("--allow_direct_klipy_api_key") ||
      Platform.environment["ALLOW_DIRECT_KLIPY_API_KEY"] == "1";
}

String getBuildVersion(String versionTag) {
  var regex = RegExp(r"\d+(\.\d+)+");
  var match = regex.firstMatch(versionTag);
  return match![0]!;
}

void syncIosBroadcastExtensionVersion(ReleaseIdentity identity) {
  final projectFile = File("ios/Runner.xcodeproj/project.pbxproj");
  if (!projectFile.existsSync()) {
    stderr.writeln(
      "iOS project file was not found; cannot sync Broadcast Extension version.",
    );
    exit(66);
  }

  var content = projectFile.readAsStringSync();
  final original = content;
  content = content.replaceAllMapped(
    RegExp(r'CURRENT_PROJECT_VERSION = \d+;'),
    (_) => 'CURRENT_PROJECT_VERSION = ${identity.buildNumber};',
  );
  content = content.replaceAllMapped(
    RegExp(r'MARKETING_VERSION = "[^"]+";'),
    (_) => 'MARKETING_VERSION = "${identity.versionName}";',
  );

  if (content != original) {
    projectFile.writeAsStringSync(content);
    print(
      "Synced iOS Broadcast Extension version to ${identity.versionName}+${identity.buildNumber}.",
    );
  }
}

String describeSteamActivityApiBaseUrl(String value) {
  if (value.isEmpty) {
    return "disabled";
  }

  final uri = Uri.tryParse(value);
  if (uri == null || !uri.queryParameters.containsKey("key")) {
    return value;
  }

  final parameters = Map<String, String>.from(uri.queryParameters);
  parameters["key"] = "***";
  return uri.replace(queryParameters: parameters).toString();
}

String getFlutterPlatformName(String platform) {
  if (platform == "android") {
    return "apk";
  }

  if (platform == "ios") {
    return "ipa";
  }

  return platform;
}

Future<void> main(List<String> args) async {
  String version = getVersionTag(args);
  final releaseIdentity = parseReleaseIdentity(version);
  version = releaseIdentity.tag;
  String platform = getPlatform(args);
  String hash = getHash(args);
  String enableGoogleServices = getEnableGoogleServices(args);
  validateGoogleServicesBuild(platform, enableGoogleServices);
  String enableNativeDetachedCallWindows =
      getEnableNativeDetachedCallWindows(args);
  String iosExportMethod = getIosExportMethod(args);
  String updateManifestUrl = getUpdateManifestUrl(args);
  String klipyApiKey = getKlipyApiKey(args).trim();
  String gifApiBaseUrl = getGifApiBaseUrl(args).trim();
  String intergalacticUrlPreviewEndpoint =
      getIntergalacticUrlPreviewEndpoint(args).trim();
  String intergalacticUrlPreviewAllowedHomeservers =
      getIntergalacticUrlPreviewAllowedHomeservers(args).trim();
  validateIntergalacticUrlPreviewConfig(
    endpoint: intergalacticUrlPreviewEndpoint,
    allowedHomeservers: intergalacticUrlPreviewAllowedHomeservers,
  );
  String spotifyClientId = getSpotifyClientId(args).trim();
  String spotifyRedirectUri = getSpotifyRedirectUri(args).trim();
  String steamActivityApiBaseUrl = getSteamActivityApiBaseUrl(args).trim();
  bool skipFlutterPub = getSkipFlutterPub(args);
  bool allowDirectKlipyApiKey = getAllowDirectKlipyApiKey(args);
  String buildVersion = getBuildVersion(version);
  String flutterPlatform = getFlutterPlatformName(platform);
  String? buildDetail = getArg(args, "--build_detail");
  print("Building release:");
  print("Version:\t'$version'");
  print("Build Version:\t'$buildVersion'");
  print("Platform:\t'$platform' / '$flutterPlatform' ");
  print("Hash:\t\t'$hash'");
  if (platform == "windows") {
    print("Detached windows:\t'$enableNativeDetachedCallWindows'");
  }
  print("GIF relay:\t'${gifApiBaseUrl.isEmpty ? "disabled" : gifApiBaseUrl}'");
  print(
    "Inter Galactic URL preview:\t'${intergalacticUrlPreviewEndpoint.isEmpty ? "disabled" : "configured"}'",
  );
  final embedsKlipyApiKey = allowDirectKlipyApiKey && klipyApiKey.isNotEmpty;
  if (klipyApiKey.isNotEmpty && !allowDirectKlipyApiKey) {
    stderr.writeln(
      "KLIPY_API_KEY is set but will not be embedded. Configure GIF_API_BASE_URL or let users set their own GIF setup in the app.",
    );
  }
  print(
    "KLIPY API:\t'${embedsKlipyApiKey ? "configured" : klipyApiKey.isNotEmpty ? "ignored" : "disabled"}'",
  );
  print(
      "Spotify:\t'${spotifyClientId.isNotEmpty && spotifyRedirectUri.isNotEmpty ? "configured" : "disabled"}'");
  print(
      "Steam activity proxy:\t'${describeSteamActivityApiBaseUrl(steamActivityApiBaseUrl)}'");
  print("Flutter pub:\t'${skipFlutterPub ? "skipped" : "default"}'");
  if (platform == "ios") {
    print("iOS export:\t'$iosExportMethod'");
  }

  if (buildDetail != null) {
    print("Detail:\t\t'$buildDetail'");
  }
  print("Google Services:\t'$enableGoogleServices'");

  if (platform == "ios" && !Platform.isMacOS) {
    stderr.writeln(
        "iOS IPA export requires a macOS host with Xcode and signing assets.");
    exit(1);
  }

  if (platform == "ios") {
    syncIosBroadcastExtensionVersion(releaseIdentity);
  }

  final flutterExecutable = Platform.environment["FLUTTER_EXE"] ?? "flutter";

  var process = Process.runSync(
    flutterExecutable,
    [
      "build",
      flutterPlatform,
      "--build-name=$buildVersion",
      if (platform == "android" || platform == "ios")
        "--build-number=${releaseIdentity.buildNumber}",
      "--release",
      if (skipFlutterPub) "--no-pub",
      "--dart-define=BUILD_MODE=release",
      "--dart-define=PLATFORM=$platform",
      "--dart-define=GIT_HASH=$hash",
      "--dart-define=VERSION_TAG=$version",
      "--dart-define=ENABLE_GOOGLE_SERVICES=$enableGoogleServices",
      "--dart-define=ENABLE_NATIVE_DETACHED_CALL_WINDOWS=$enableNativeDetachedCallWindows",
      if (embedsKlipyApiKey && klipyApiKey.isNotEmpty)
        "--dart-define=KLIPY_API_KEY=$klipyApiKey",
      if (gifApiBaseUrl.isNotEmpty)
        "--dart-define=GIF_API_BASE_URL=$gifApiBaseUrl",
      if (intergalacticUrlPreviewEndpoint.isNotEmpty)
        "--dart-define=INTERGALACTIC_URL_PREVIEW_ENDPOINT=$intergalacticUrlPreviewEndpoint",
      if (intergalacticUrlPreviewAllowedHomeservers.isNotEmpty)
        "--dart-define=INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS=$intergalacticUrlPreviewAllowedHomeservers",
      if (updateManifestUrl.isNotEmpty)
        "--dart-define=UPDATE_MANIFEST_URL=$updateManifestUrl",
      if (spotifyClientId.isNotEmpty)
        "--dart-define=SPOTIFY_CLIENT_ID=$spotifyClientId",
      if (spotifyRedirectUri.isNotEmpty)
        "--dart-define=SPOTIFY_REDIRECT_URI=$spotifyRedirectUri",
      if (steamActivityApiBaseUrl.isNotEmpty)
        "--dart-define=STEAM_ACTIVITY_API_BASE_URL=$steamActivityApiBaseUrl",
      "--dart-define=BUILD_DATE=${DateTime.now().millisecondsSinceEpoch}",
      if (platform == "ios") "--export-method=$iosExportMethod",
      if (buildDetail != null) "--dart-define=BUILD_DETAIL=$buildDetail",
      if (platform == "web")
        "--dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/",
      if (platform == "web") "--source-maps",
    ],
    runInShell: true,
  );

  print(process.stdout);
  print(process.stderr);
  exit(process.exitCode);
}
