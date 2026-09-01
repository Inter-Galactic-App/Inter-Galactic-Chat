// ignore_for_file: avoid_print

import 'dart:io';

const defaultManagedGifRelayBaseUrl = "https://api.ourgalaxy.space/klipy";

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
  final match = RegExp(
    r'^v?(\d+\.\d+\.\d+)\+(\d+)$',
  ).firstMatch(versionTag.trim());
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

  // No default. This used to fall back to "v0.0.0+0", which every caller
  // masked because release.bat, build.bat and build_android.bat all derive the
  // tag from pubspec.yaml and pass it. A hand-run iOS build does not, so on
  // 2026-08-19 a 0.8.1+1003 archive was produced carrying 0.0.0+0 and having
  // rewritten MARKETING_VERSION/CURRENT_PROJECT_VERSION in project.pbxproj to
  // match - a release candidate that looked real and was not, caught only by
  // reading the printed header.
  //
  // Deriving from pubspec.yaml instead was considered and rejected: the
  // desktop auto-update test deliberately builds a version LOWER than pubspec
  // (tools/desktop-auto-update-test/Build-DesktopAutoUpdatePreviousPackage.ps1),
  // so pubspec is not always the answer, and a second derivation path inside
  // this script would bypass verify_release_identity.ps1 rather than agree
  // with it. The caller states the identity; this script only refuses to guess.
  throw ArgumentError(
    "--version_tag is required and has no default. Pass the full pubspec "
    "identity, for example --version_tag v0.7.0+968. Read it from the "
    "'version: X.Y.Z+build' line in intergalactic/pubspec.yaml, or let "
    "release.bat / build.bat / build_android.bat derive and verify it.",
  );
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

bool usesDesktopFlutterWindowing(String platform) {
  return platform == "windows" || platform == "macos" || platform == "linux";
}

void enableDesktopFlutterWindowingIfNeeded({
  required String flutterExecutable,
  required String platform,
}) {
  if (!usesDesktopFlutterWindowing(platform)) {
    return;
  }

  final process = Process.runSync(flutterExecutable, [
    "config",
    "--enable-windowing",
  ], runInShell: true);
  if (process.stdout.toString().trim().isNotEmpty) {
    print(process.stdout);
  }
  if (process.stderr.toString().trim().isNotEmpty) {
    stderr.write(process.stderr);
  }
  if (process.exitCode != 0) {
    exit(process.exitCode);
  }
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
        RegExp(
          r"// ignore_for_file: type=lint\s*/\*",
          multiLine: true,
        ).hasMatch(content);

    if (!entry.value.hasMatch(content) || isFirebaseOptionsCommented) {
      missing.add(entry.key);
    }
  }

  if (missing.isEmpty) {
    return;
  }

  stderr.writeln(
    "Google Services build requested, but Firebase source toggles are not active.",
  );
  stderr.writeln(
    "Run `scripts/set_google_services.ps1 enable` after staging owner-local "
    "Firebase config before building the FCM APK.",
  );
  stderr.writeln("Missing active markers in:");
  for (final file in missing) {
    stderr.writeln("- $file");
  }
  exit(65);
}

String getEnableNativeDetachedCallWindows(
  List<String> args, {
  Map<String, String>? environment,
}) {
  final raw =
      getArg(args, "--enable_native_detached_call_windows") ??
      (environment ??
          Platform.environment)["ENABLE_NATIVE_DETACHED_CALL_WINDOWS"] ??
      "true";

  // Validated rather than passed through. The value becomes a `--dart-define`,
  // and `bool.fromEnvironment` treats anything that is not exactly "true" as
  // false - so a typo like `ture`, or a shell that supplied `1`, silently
  // shipped a release build with native detached call windows OFF and no
  // diagnostic anywhere. Fail the build instead; that is recoverable, a quietly
  // wrong release is not.
  //
  // Throws rather than calling `exit`, matching `getAndroidTargetPlatform`:
  // an `exit` inside a resolver cannot be tested without killing the test
  // process, so the rule would have gone unverified.
  if (raw != "true" && raw != "false") {
    throw ArgumentError.value(
      raw,
      "enable_native_detached_call_windows",
      'Expected exactly "true" or "false".',
    );
  }
  return raw;
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
  final configured =
      getArg(args, "--gif_api_base_url") ??
      Platform.environment["GIF_API_BASE_URL"];
  if (configured != null) {
    return configured;
  }
  if (getDisableManagedGifRelay(args)) {
    return "";
  }
  return defaultManagedGifRelayBaseUrl;
}

bool getDisableManagedGifRelay(List<String> args) {
  return args.contains("--disable_managed_gif_relay") ||
      Platform.environment["DISABLE_MANAGED_GIF_RELAY"] == "1";
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

/// Maps a resolver's [ArgumentError] onto the documented exit code.
///
/// The validating resolvers throw so they can be tested (an `exit` inside a
/// resolver kills the test process), but build-signing.md documents exit 64
/// for every invalid value - an uncaught throw exits 255. This is the thin
/// untestable shell that restores the contract at the boundary.
T requireValidReleaseConfig<T>(T Function() read) {
  try {
    return read();
  } on ArgumentError catch (error) {
    stderr.writeln(error.toString());
    exit(64);
  }
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

/// ABI set for the distributed Android release APK.
///
/// Flutter's default for a release APK is all three of `android-arm`,
/// `android-arm64`, `android-x64` (build_apk.dart `_kDefaultAotArchs`), and the
/// result is one universal APK. Measured on `0.8.1+1001`: x86_64 was 94.9 MB of
/// a 294.7 MB artifact — 32% of a manually-downloaded APK spent on an emulator
/// architecture that no phone uses.
///
/// This only narrows the RELEASE artifact. `build_android.bat --debug` calls
/// `flutter build apk --debug` directly and is untouched, so the debug APK still
/// carries all three ABIs — that is what emulator smoke installs, and
/// `docs/release/test-matrix.md` names an emulator as the preferred extra
/// Android target. Decision and reasoning: `docs/DECISIONS.md`, 2026-08-05.
///
/// Pass `--target_platform` to override for a one-off build. `--split-per-abi`
/// is deliberately NOT used: `generate_update_manifest.dart` publishes a single
/// `--android_download_url`, so a per-ABI set has nowhere to be published.
String getAndroidTargetPlatform(
  List<String> args, {
  Map<String, String>? environment,
}) {
  final targetPlatform =
      getArg(args, "--target_platform") ??
      (environment ??
          Platform.environment)["INTERGALACTIC_ANDROID_TARGET_PLATFORM"] ??
      "android-arm,android-arm64";
  if (targetPlatform != "android-arm,android-arm64") {
    throw ArgumentError.value(
      targetPlatform,
      "target_platform",
      "Android release artifacts must target android-arm,android-arm64.",
    );
  }
  return targetPlatform;
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
  // Only refresh explicitly pinned numeric versions (the Broadcast
  // Extension). Runner targets must keep the $(FLUTTER_BUILD_NUMBER)
  // placeholder or verify_release_identity.ps1 fails the release gate.
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
  String version = requireValidReleaseConfig(() => getVersionTag(args));
  final releaseIdentity = parseReleaseIdentity(version);
  version = releaseIdentity.tag;
  String platform = getPlatform(args);
  String hash = getHash(args);
  String enableGoogleServices = getEnableGoogleServices(args);
  validateGoogleServicesBuild(platform, enableGoogleServices);
  String enableNativeDetachedCallWindows = requireValidReleaseConfig(
    () => getEnableNativeDetachedCallWindows(args),
  );
  String iosExportMethod = getIosExportMethod(args);
  String updateManifestUrl = getUpdateManifestUrl(args);
  String klipyApiKey = getKlipyApiKey(args).trim();
  bool disableManagedGifRelay = getDisableManagedGifRelay(args);
  String gifApiBaseUrl = getGifApiBaseUrl(args).trim();
  String intergalacticUrlPreviewEndpoint = getIntergalacticUrlPreviewEndpoint(
    args,
  ).trim();
  String intergalacticUrlPreviewAllowedHomeservers =
      getIntergalacticUrlPreviewAllowedHomeservers(args).trim();
  validateIntergalacticUrlPreviewConfig(
    endpoint: intergalacticUrlPreviewEndpoint,
    allowedHomeservers: intergalacticUrlPreviewAllowedHomeservers,
  );
  String spotifyClientId = getSpotifyClientId(args).trim();
  String spotifyRedirectUri = getSpotifyRedirectUri(args).trim();
  String steamActivityApiBaseUrl = getSteamActivityApiBaseUrl(args).trim();
  String? androidTargetPlatform;
  if (platform == "android") {
    androidTargetPlatform = requireValidReleaseConfig(
      () => getAndroidTargetPlatform(args),
    );
  }
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
  if (usesDesktopFlutterWindowing(platform)) {
    print("Flutter windowing:\t'enabled via flutter config'");
  }
  print("GIF relay:\t'${gifApiBaseUrl.isEmpty ? "disabled" : gifApiBaseUrl}'");
  print(
    "Inter Galactic URL preview:\t'${intergalacticUrlPreviewEndpoint.isEmpty ? "disabled" : "configured"}'",
  );
  final embedsKlipyApiKey = allowDirectKlipyApiKey && klipyApiKey.isNotEmpty;
  if (klipyApiKey.isNotEmpty && !allowDirectKlipyApiKey) {
    stderr.writeln(
      "KLIPY_API_KEY is set but will not be embedded. Release builds use the managed GIF relay unless GIF_API_BASE_URL overrides it.",
    );
  }
  print(
    "KLIPY API:\t'${embedsKlipyApiKey
        ? "configured"
        : klipyApiKey.isNotEmpty
        ? "ignored"
        : "disabled"}'",
  );
  print(
    "Spotify:\t'${spotifyClientId.isNotEmpty && spotifyRedirectUri.isNotEmpty ? "configured" : "disabled"}'",
  );
  print(
    "Steam activity proxy:\t'${describeSteamActivityApiBaseUrl(steamActivityApiBaseUrl)}'",
  );
  print("Flutter pub:\t'${skipFlutterPub ? "skipped" : "default"}'");
  if (platform == "android") {
    print("Android ABIs:\t'$androidTargetPlatform'");
  }
  if (platform == "ios") {
    print("iOS export:\t'$iosExportMethod'");
  }

  if (buildDetail != null) {
    print("Detail:\t\t'$buildDetail'");
  }
  print("Google Services:\t'$enableGoogleServices'");

  if (platform == "ios" && !Platform.isMacOS) {
    stderr.writeln(
      "iOS IPA export requires a macOS host with Xcode and signing assets.",
    );
    exit(1);
  }

  if (platform == "ios") {
    syncIosBroadcastExtensionVersion(releaseIdentity);
  }

  final flutterExecutable = Platform.environment["FLUTTER_EXE"] ?? "flutter";
  enableDesktopFlutterWindowingIfNeeded(
    flutterExecutable: flutterExecutable,
    platform: platform,
  );

  var process = Process.runSync(flutterExecutable, [
    "build",
    flutterPlatform,
    "--build-name=$buildVersion",
    if (platform == "android" || platform == "ios")
      "--build-number=${releaseIdentity.buildNumber}",
    "--release",
    if (platform == "android") "--target-platform=$androidTargetPlatform",
    if (skipFlutterPub) "--no-pub",
    "--dart-define=BUILD_MODE=release",
    "--dart-define=PLATFORM=$platform",
    "--dart-define=GIT_HASH=$hash",
    "--dart-define=VERSION_TAG=$version",
    "--dart-define=ENABLE_GOOGLE_SERVICES=$enableGoogleServices",
    "--dart-define=ENABLE_NATIVE_DETACHED_CALL_WINDOWS=$enableNativeDetachedCallWindows",
    if (embedsKlipyApiKey && klipyApiKey.isNotEmpty)
      "--dart-define=KLIPY_API_KEY=$klipyApiKey",
    if (gifApiBaseUrl.isNotEmpty || disableManagedGifRelay)
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
    if (platform == "web") "--dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/",
    if (platform == "web") "--source-maps",
  ], runInShell: true);

  print(process.stdout);
  print(process.stderr);
  exit(process.exitCode);
}
