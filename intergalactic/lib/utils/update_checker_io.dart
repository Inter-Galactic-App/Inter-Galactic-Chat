import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

class _UpdatePlatformInfo {
  final Uri? downloadUrl;
  final Uri? releaseUrl;
  final Uri? checksumUrl;
  final String? sha256;
  final int? sizeBytes;
  final bool canAutoUpdate;
  final bool allowUnsignedAutoUpdate;

  const _UpdatePlatformInfo({
    this.downloadUrl,
    this.releaseUrl,
    this.checksumUrl,
    this.sha256,
    this.sizeBytes,
    required this.canAutoUpdate,
    this.allowUnsignedAutoUpdate = false,
  });

  factory _UpdatePlatformInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const _UpdatePlatformInfo(canAutoUpdate: false);
    }

    return _UpdatePlatformInfo(
      downloadUrl: _UpdateManifest.parseUri(json["download_url"]),
      releaseUrl: _UpdateManifest.parseUri(json["release_url"]),
      checksumUrl: _UpdateManifest.parseUri(json["checksum_url"]),
      sha256: _UpdateManifest.parseText(json["sha256"]),
      sizeBytes: _UpdateManifest.parseInt(json["size_bytes"]),
      canAutoUpdate: json["auto_update"] == true,
      allowUnsignedAutoUpdate: json["allow_unsigned_auto_update"] == true,
    );
  }
}

class _UpdateManifest {
  final String version;
  final DateTime buildDate;
  final Uri? releaseUrl;
  final Uri? checksumsUrl;
  final String? notes;
  final Uri? notesUrl;
  final String? featureNotes;
  final Uri? featureNotesUrl;
  final Map<String, _UpdatePlatformInfo> platforms;

  const _UpdateManifest({
    required this.version,
    required this.buildDate,
    required this.releaseUrl,
    required this.checksumsUrl,
    required this.notes,
    required this.notesUrl,
    required this.featureNotes,
    required this.featureNotesUrl,
    required this.platforms,
  });

  static String? parseText(dynamic value) {
    if (value is! String) {
      return null;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  static Uri? parseUri(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    return Uri.tryParse(value);
  }

  static int? parseInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  static int parseBuildDateMs(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is String) {
      return int.parse(value);
    }

    throw const FormatException("Missing or invalid build_date_ms");
  }

  factory _UpdateManifest.fromJson(Map<String, dynamic> json) {
    final rawPlatforms = json["platforms"];
    final platformMap = <String, _UpdatePlatformInfo>{};

    if (rawPlatforms is Map) {
      for (final entry in rawPlatforms.entries) {
        if (entry.key is String && entry.value is Map<String, dynamic>) {
          platformMap[entry.key as String] =
              _UpdatePlatformInfo.fromJson(entry.value as Map<String, dynamic>);
        } else if (entry.key is String && entry.value is Map) {
          platformMap[entry.key as String] = _UpdatePlatformInfo.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    return _UpdateManifest(
      version: json["version"] as String? ?? "unknown",
      buildDate: DateTime.fromMillisecondsSinceEpoch(
        parseBuildDateMs(json["build_date_ms"]),
      ),
      releaseUrl: parseUri(json["release_url"]),
      checksumsUrl: parseUri(json["checksums_url"] ?? json["checksum_url"]),
      notes: parseText(json["notes"]) ?? parseText(json["release_notes"]),
      notesUrl: parseUri(json["notes_url"]),
      featureNotes: parseText(json["feature_notes"]) ??
          parseText(json["feature_highlights"]) ??
          parseText(json["announcement_notes"]) ??
          parseText(json["announcement"]),
      featureNotesUrl: parseUri(
        json["feature_notes_url"] ??
            json["feature_highlights_url"] ??
            json["announcement_notes_url"] ??
            json["announcement_url"],
      ),
      platforms: platformMap,
    );
  }

  _UpdatePlatformInfo? get currentPlatform {
    if (PlatformUtils.isWindows) {
      return platforms["windows"];
    }

    if (PlatformUtils.isLinux) {
      return platforms["linux"];
    }

    if (PlatformUtils.isAndroid) {
      return platforms["android"];
    }

    return null;
  }
}

class UpdateChecker {
  static const String _windowsUpdaterArg = "--intergalactic-updater";
  static const String _updateAlertId = "update_available";
  static const String _releaseNotesAlertId = "release_notes_current_version";
  static const int _maxReleaseNotesChars = 700;
  static const int _maxDialogMarkdownChars = 8000;
  static const Duration _periodicUpdateCheckInterval = Duration(hours: 1);
  static const String _windowsSignatureVerificationScript = r'''
param([Parameter(Mandatory=$true)][string] $InstallerPath)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
  Write-Error 'Installer path was not provided.'
  exit 1
}
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
  Write-Error ("Installer path was not found: " + $InstallerPath)
  exit 1
}
$sig = Get-AuthenticodeSignature -LiteralPath $InstallerPath
Write-Output ("status=" + [string]$sig.Status)
if ($sig.StatusMessage) {
  Write-Output ("status_message=" + [string]$sig.StatusMessage)
}
if ($sig.SignerCertificate) {
  Write-Output ("signer_subject=" + [string]$sig.SignerCertificate.Subject)
}
if ($sig.Status -eq 'Valid') { exit 0 }
exit 2
''';
  static const String _windowsSilentInstallerScript = r'''
param([Parameter(Mandatory=$true)][string] $InstallerPath)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
  Write-Error 'Installer path was not provided.'
  exit 1
}
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
  Write-Error ("Installer path was not found: " + $InstallerPath)
  exit 1
}
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS')
$process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru
if ($null -eq $process.ExitCode) { exit 0 }
exit $process.ExitCode
''';
  static bool foundUpdate = false;
  static Timer? _periodicUpdateCheckTimer;

  static String get labelUpdateAvailable => Intl.message("Update Available",
      name: "labelUpdateAvailable",
      desc: "Label for the the info popup when an update is available");

  static String descriptionUpdateAvailable(
    String version,
    String? notes,
  ) {
    final base = Intl.message(
        "There is a newer version of Inter Galactic available: ${version}",
        name: "descriptionUpdateAvailable",
        args: [version],
        desc:
            "describes the update, showing the version code for the available update");
    final releaseNotes = _cleanReleaseNotes(notes);
    if (releaseNotes == null) {
      return base;
    }

    return "$base\n\n$releaseNotes";
  }

  static String titleReleaseNotes(String version) => Intl.message(
        "What's New in Inter Galactic ${version}",
        name: "titleReleaseNotes",
        args: [version],
        desc: "Title for the one-time post-update release notes alert",
      );

  static String descriptionReleaseNotes(String version, String notes) =>
      Intl.message(
        "You are now running Inter Galactic ${version}.\n\n${notes}",
        name: "descriptionReleaseNotes",
        args: [version, notes],
        desc: "One-time post-update summary of release notes",
      );

  static bool isWindowsUpdaterInvocation(List<String> args) {
    return args.contains(_windowsUpdaterArg);
  }

  static Future<bool> maybeRunWindowsUpdater(List<String> args) async {
    if (!PlatformUtils.isWindows || !isWindowsUpdaterInvocation(args)) {
      return false;
    }

    final _WindowsUpdaterRequest request;
    try {
      request = _WindowsUpdaterRequest.fromArgs(args);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Ignoring malformed Windows updater invocation',
        source: 'windows-updater',
      );
      return false;
    }
    await _configureWindowsUpdaterWindow();
    runApp(_WindowsUpdaterApp(request: request));
    return true;
  }

  static Future<bool> checkForStartupUpdate() async {
    if (!PlatformUtils.isWindows || !shouldCheckForUpdates) {
      return false;
    }

    if (!preferences.isInit) {
      await preferences.init();
    }

    if (preferences.checkForUpdates.value == false) {
      return false;
    }

    final update = await _fetchUpdateManifest();
    if (update == null) {
      return false;
    }

    final platformInfo = update.manifest.currentPlatform ??
        const _UpdatePlatformInfo(canAutoUpdate: false);
    if (!_isManifestNewer(update.manifest)) {
      return false;
    }

    if (!_canRunWindowsAutoUpdate(
      update.manifest,
      platformInfo,
      manifestUri: update.manifestUri,
    )) {
      Log.w(
        "Windows update ${update.manifest.version} is available, but "
        "auto_update is not enabled or update metadata is incomplete",
      );
      return false;
    }

    return _launchWindowsUpdaterHelper(
      update.manifest,
      platformInfo,
      manifestUri: update.manifestUri,
      trigger: "startup",
    );
  }

  static void startPeriodicChecks() {
    if (!shouldCheckForUpdates || _periodicUpdateCheckTimer != null) {
      return;
    }

    _periodicUpdateCheckTimer = Timer.periodic(
      _periodicUpdateCheckInterval,
      (_) => unawaited(checkForUpdates()),
    );
  }

  static void stopPeriodicChecks() {
    _periodicUpdateCheckTimer?.cancel();
    _periodicUpdateCheckTimer = null;
  }

  static Future<void> checkForUpdates() async {
    if (!shouldCheckForUpdates) {
      return;
    }

    if (preferences.checkForUpdates.value != true) {
      return;
    }

    final update = await _fetchUpdateManifest();
    if (update == null) {
      return;
    }

    final parsedManifestUrl = update.manifestUri;
    final manifest = update.manifest;
    final platformInfo = manifest.currentPlatform ??
        const _UpdatePlatformInfo(canAutoUpdate: false);

    if (platformInfo.downloadUrl == null &&
        platformInfo.releaseUrl == null &&
        manifest.releaseUrl == null) {
      Log.i("No update channel configured for the current platform");
      return;
    }

    Log.i("Got update manifest for ${manifest.version}");

    if (_isManifestNewer(manifest)) {
      foundUpdate = true;
      clientManager!.alertManager.addAlert(Alert(AlertType.info,
          id: _updateAlertId,
          messageGetter: () =>
              descriptionUpdateAvailable(manifest.version, manifest.notes),
          titleGetter: () => labelUpdateAvailable,
          action: (context) => doUpdateAction(context, manifest)));
      return;
    }

    _clearUpdateAlert();
    await _maybeShowCurrentReleaseNotes(manifest, parsedManifestUrl);

    Log.i(
        "Found update manifest, but it is not newer than the current build. current: ${BuildConfig.BUILD_DATE} remote: ${manifest.buildDate}");
  }

  static bool _isManifestNewer(_UpdateManifest manifest) {
    if (manifest.version.trim() == BuildConfig.VERSION_TAG.trim()) {
      return false;
    }

    final versionComparison =
        _compareVersionTags(manifest.version, BuildConfig.VERSION_TAG);
    if (versionComparison != null) {
      return versionComparison > 0;
    }

    return manifest.buildDate.isAfter(BuildConfig.BUILD_DATE);
  }

  static bool debugIsManifestNewer({
    required String version,
    required DateTime buildDate,
  }) {
    return _isManifestNewer(_UpdateManifest(
      version: version,
      buildDate: buildDate,
      releaseUrl: null,
      checksumsUrl: null,
      notes: null,
      notesUrl: null,
      featureNotes: null,
      featureNotesUrl: null,
      platforms: const {},
    ));
  }

  static String? debugCleanReleaseNotes(String? notes) {
    return _cleanReleaseNotes(notes);
  }

  static String? debugReleaseNotesDialogMarkdown({
    String? featureNotes,
    String? releaseNotes,
  }) {
    return _buildReleaseNotesDialogMarkdown(
      featureNotes: featureNotes,
      releaseNotes: releaseNotes,
    );
  }

  static Uri? debugManifestFeatureNotesUrl(Map<String, dynamic> json) {
    return _UpdateManifest.fromJson(json).featureNotesUrl;
  }

  static int? debugCompareVersionTags(String remote, String current) {
    return _compareVersionTags(remote, current);
  }

  static ({List<int> parts, String? build})? debugParseVersionTag(
    String version,
  ) {
    return _parseVersionTag(version);
  }

  static int debugCompareBuildMetadata(String? remote, String? current) {
    return _compareBuildMetadata(remote, current);
  }

  static String? debugParseSha256FromChecksums(
    String checksums,
    String fileName,
  ) {
    return _parseSha256FromChecksums(checksums, fileName);
  }

  static bool debugManifestAllowsUnsignedWindowsAutoUpdate(
    Map<String, dynamic> json,
  ) {
    return _UpdateManifest.fromJson(json)
            .platforms["windows"]
            ?.allowUnsignedAutoUpdate ??
        false;
  }

  static bool debugWindowsUpdaterRequestAllowsUnsigned(
    List<String> args,
  ) {
    return _WindowsUpdaterRequest.fromArgs(args).allowUnsignedAutoUpdate;
  }

  static List<String> debugWindowsSignatureVerificationPowerShellArgs(
    String installerPath,
  ) {
    return _windowsPowerShellFileArgs(
      path.join(
        Directory.systemTemp.path,
        "intergalactic-updater-signature.ps1",
      ),
      installerPath,
    );
  }

  static List<String> debugWindowsSilentInstallerPowerShellArgs(
    String installerPath,
  ) {
    return _windowsPowerShellFileArgs(
      path.join(
        Directory.systemTemp.path,
        "intergalactic-updater-install.ps1",
      ),
      installerPath,
    );
  }

  static int? _compareVersionTags(String remote, String current) {
    final remoteTag = _parseVersionTag(remote);
    final currentTag = _parseVersionTag(current);
    if (remoteTag == null || currentTag == null) {
      return null;
    }

    final remoteParts = remoteTag.parts;
    final currentParts = currentTag.parts;
    final maxLength = remoteParts.length > currentParts.length
        ? remoteParts.length
        : currentParts.length;
    for (var i = 0; i < maxLength; i++) {
      final remotePart = i < remoteParts.length ? remoteParts[i] : 0;
      final currentPart = i < currentParts.length ? currentParts[i] : 0;
      if (remotePart != currentPart) {
        return remotePart.compareTo(currentPart);
      }
    }

    return _compareBuildMetadata(remoteTag.build, currentTag.build);
  }

  static ({List<int> parts, String? build})? _parseVersionTag(String version) {
    final match = RegExp(r'^v?(\d+(?:\.\d+)*)(?:\+([A-Za-z0-9.-]+))?$')
        .firstMatch(version.trim());
    if (match == null) {
      return null;
    }

    return (
      parts: match.group(1)!.split('.').map(int.parse).toList(growable: false),
      build: match.group(2),
    );
  }

  static int _compareBuildMetadata(String? remote, String? current) {
    if (remote == current) {
      return 0;
    }
    if (remote == null) {
      return -1;
    }
    if (current == null) {
      return 1;
    }

    final remoteNumber = int.tryParse(remote);
    final currentNumber = int.tryParse(current);
    if (remoteNumber != null && currentNumber != null) {
      return remoteNumber.compareTo(currentNumber);
    }

    return remote.compareTo(current);
  }

  static void _clearUpdateAlert() {
    foundUpdate = false;
    clientManager?.alertManager.clearAlertsById(_updateAlertId);
  }

  static Future<void> _maybeShowCurrentReleaseNotes(
    _UpdateManifest manifest,
    Uri manifestUri,
  ) async {
    if (!_isCurrentManifestVersion(manifest)) {
      return;
    }

    final version = _canonicalVersionTag(manifest.version);
    if (preferences.lastSeenReleaseNotesVersion.value == version) {
      return;
    }

    final featureNotes = await _loadFeatureNotes(manifest, manifestUri);
    final dialogMarkdown = _buildReleaseNotesDialogMarkdown(
      featureNotes: featureNotes,
      releaseNotes: manifest.notes,
    );
    if (dialogMarkdown == null) {
      return;
    }

    final releaseNotes = _cleanReleaseNotes(manifest.notes);
    final featureSummary = _cleanReleaseNotes(featureNotes);
    final alertSummary = featureSummary ??
        releaseNotes ??
        "Tap to see what changed in this Inter Galactic update.";
    await preferences.lastSeenReleaseNotesVersion.set(version);

    final notesUrl = _trustedNotesUri(manifestUri, manifest.notesUrl);
    final context = navigator.currentContext;
    if (context != null && context.mounted) {
      await _showReleaseNotesDialog(
        context,
        version: version,
        markdown: dialogMarkdown,
        notesUrl: notesUrl,
      );
      return;
    }

    clientManager?.alertManager.addAlert(
      Alert(
        AlertType.info,
        id: _releaseNotesAlertId,
        messageGetter: () => descriptionReleaseNotes(version, alertSummary),
        titleGetter: () => titleReleaseNotes(version),
        action: (context) async {
          clientManager?.alertManager.clearAlertsById(_releaseNotesAlertId);
          await _showReleaseNotesDialog(
            context,
            version: version,
            markdown: dialogMarkdown,
            notesUrl: notesUrl,
          );
        },
      ),
    );
  }

  static Future<String?> _loadFeatureNotes(
    _UpdateManifest manifest,
    Uri manifestUri,
  ) async {
    final inlineNotes = _cleanDialogMarkdown(manifest.featureNotes);
    if (inlineNotes != null) {
      return inlineNotes;
    }

    final featureNotesUri =
        _trustedNotesUri(manifestUri, manifest.featureNotesUrl);
    if (featureNotesUri == null) {
      return null;
    }

    try {
      final response = await http.get(featureNotesUri);
      if (response.statusCode != 200) {
        Log.w(
          "Failed to fetch update feature notes from $featureNotesUri: "
          "${response.statusCode}",
        );
        return null;
      }

      return _cleanDialogMarkdown(response.body);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to fetch update feature notes",
        source: "update-checker",
      );
      return null;
    }
  }

  static String? _buildReleaseNotesDialogMarkdown({
    required String? featureNotes,
    required String? releaseNotes,
  }) {
    final featureMarkdown = _cleanDialogMarkdown(featureNotes);
    final releaseMarkdown = _cleanDialogMarkdown(releaseNotes);
    final sections = <String>[
      if (featureMarkdown != null)
        "## Featured in this update\n\n$featureMarkdown",
      if (releaseMarkdown != null) "## Release notes\n\n$releaseMarkdown",
    ];

    if (sections.isEmpty) {
      return null;
    }

    return sections.join("\n\n");
  }

  static String? _cleanDialogMarkdown(String? notes) {
    if (notes == null) {
      return null;
    }

    final normalized = LineSplitter.split(notes.replaceAll('\r\n', '\n'))
        .map((line) => line.trimRight())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.length <= _maxDialogMarkdownChars) {
      return normalized;
    }

    return "${normalized.substring(0, _maxDialogMarkdownChars).trimRight()}\n\n...";
  }

  static Future<void> _showReleaseNotesDialog(
    BuildContext context, {
    required String version,
    required String markdown,
    required Uri? notesUrl,
  }) {
    return AdaptiveDialog.show<void>(
      context,
      title: titleReleaseNotes(version),
      initialHeightMobile: 0.75,
      builder: (dialogContext) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Markdown(
                data: markdown,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                styleSheet: MarkdownStyleSheet.fromTheme(
                  Theme.of(dialogContext),
                ).copyWith(
                  codeblockPadding: const EdgeInsets.all(8),
                  code: Theme.of(dialogContext)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFamily: "Code"),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (notesUrl != null)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text("Full release notes"),
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        await LinkUtils.open(notesUrl, context: context);
                      },
                    ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text("Close"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static bool _isCurrentManifestVersion(_UpdateManifest manifest) {
    if (manifest.version.trim() == BuildConfig.VERSION_TAG.trim()) {
      return true;
    }

    return _compareVersionTags(manifest.version, BuildConfig.VERSION_TAG) == 0;
  }

  static String _canonicalVersionTag(String version) {
    final parsed = _parseVersionTag(version);
    if (parsed == null) {
      return version.trim();
    }

    final base = parsed.parts.join(".");
    final build = parsed.build;
    return build == null ? base : "$base+$build";
  }

  static String? _cleanReleaseNotes(String? notes) {
    if (notes == null) {
      return null;
    }

    final normalized = LineSplitter.split(notes.replaceAll('\r\n', '\n'))
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .join('\n')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.length <= _maxReleaseNotesChars) {
      return normalized;
    }

    return "${normalized.substring(0, _maxReleaseNotesChars).trimRight()}...";
  }

  static bool get shouldCheckForUpdates {
    if (PlatformUtils.isWeb) {
      return false;
    }

    if (BuildConfig.VERSION_TAG == "v0.0.0-artifact") {
      return false;
    }

    if (BuildConfig.UPDATE_MANIFEST_URL.isEmpty) {
      return false;
    }

    return true;
  }

  static Future<void> doUpdateAction(
      BuildContext context, _UpdateManifest manifest) async {
    final platformInfo = manifest.currentPlatform;
    final resolvedPlatformInfo =
        platformInfo ?? const _UpdatePlatformInfo(canAutoUpdate: false);

    if (PlatformUtils.isWindows) {
      await windowsUpdateAction(
          context, resolvedPlatformInfo, manifest.releaseUrl, manifest);
      return;
    }

    final destination = resolvedPlatformInfo.downloadUrl ??
        resolvedPlatformInfo.releaseUrl ??
        manifest.releaseUrl;

    if (destination != null) {
      await LinkUtils.open(destination, context: context);
    }
  }

  static Future<void> windowsUpdateAction(
      BuildContext context,
      _UpdatePlatformInfo platformInfo,
      Uri? releaseUrl,
      _UpdateManifest manifest) async {
    final autoUpdateSource = platformInfo.downloadUrl;
    final destination =
        autoUpdateSource ?? platformInfo.releaseUrl ?? releaseUrl;
    final manifestUri = Uri.tryParse(BuildConfig.UPDATE_MANIFEST_URL);
    final canAutoUpdate = manifestUri != null &&
        _canRunWindowsAutoUpdate(
          manifest,
          platformInfo,
          manifestUri: manifestUri,
        );
    var launchedUpdater = false;

    if (canAutoUpdate) {
      final confirmation = await AdaptiveDialog.confirmation(context,
          prompt: "Update and restart Inter Galactic now?");

      if (confirmation == true) {
        await ErrorUtils.tryRun(context, () async {
          launchedUpdater = await _launchWindowsUpdaterHelper(
            manifest,
            platformInfo,
            manifestUri: manifestUri,
            trigger: "runtime",
          );

          if (launchedUpdater) {
            Log.i("Launching Windows updater helper for ${manifest.version}");
            for (final client in clientManager!.clients) {
              await client.close();
            }
            await Future.delayed(const Duration(milliseconds: 500));
          }
        });

        if (launchedUpdater) {
          exit(0);
        }
      }

      if (confirmation == null) {
        return;
      }
    }

    if (destination != null && _isTrustedUpdateAssetUri(destination)) {
      await LinkUtils.open(destination, context: context);
    }
  }

  static String _normalizeWindowsInstallerVersion(String version) {
    return version.replaceFirst(RegExp(r'^v'), '');
  }

  static String _windowsInstallerFileName(String manifestVersion) {
    final normalizedVersion =
        _normalizeWindowsInstallerVersion(manifestVersion);
    return "InterGalactic-Setup-$normalizedVersion.exe";
  }

  static Future<({Uri manifestUri, _UpdateManifest manifest})?>
      _fetchUpdateManifest() async {
    final manifestUrl = BuildConfig.UPDATE_MANIFEST_URL;
    if (manifestUrl.isEmpty) {
      Log.i("Skipping update check because UPDATE_MANIFEST_URL is not set");
      return null;
    }

    final parsedManifestUrl = Uri.tryParse(manifestUrl);
    if (!_isTrustedManifestUri(parsedManifestUrl)) {
      Log.w("Skipping update check because UPDATE_MANIFEST_URL is not trusted");
      return null;
    }

    try {
      final response = await http.get(parsedManifestUrl!);
      if (response.statusCode != 200) {
        Log.w(
          "Failed to fetch update manifest from $manifestUrl: "
          "${response.statusCode}",
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        Log.w("Failed to parse update manifest: expected a JSON object");
        return null;
      }

      final fields = Map<String, dynamic>.from(decoded);
      final manifest = _UpdateManifest.fromJson(fields);
      final platformInfo = manifest.currentPlatform ??
          const _UpdatePlatformInfo(canAutoUpdate: false);

      if (!_hasTrustedUpdateDestination(
        parsedManifestUrl,
        manifest,
        platformInfo,
      )) {
        Log.w(
          "Skipping update prompt because manifest destinations are not trusted",
        );
        return null;
      }

      return (manifestUri: parsedManifestUrl, manifest: manifest);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to fetch or parse update manifest from $manifestUrl',
        source: 'update-checker',
      );
      return null;
    }
  }

  static bool _canRunWindowsAutoUpdate(
    _UpdateManifest manifest,
    _UpdatePlatformInfo platformInfo, {
    required Uri manifestUri,
  }) {
    if (!PlatformUtils.isWindows ||
        !platformInfo.canAutoUpdate ||
        platformInfo.downloadUrl == null) {
      return false;
    }

    if (!_isTrustedUpdateAssetUri(
      platformInfo.downloadUrl,
      manifestUri: manifestUri,
    )) {
      return false;
    }

    final checksumUrl = _resolveChecksumUrl(manifest, platformInfo);
    final hasTrustedChecksumUrl = checksumUrl != null &&
        _isTrustedUpdateAssetUri(checksumUrl, manifestUri: manifestUri);
    final hasInlineChecksum = _normalizeSha256(platformInfo.sha256) != null;

    return hasInlineChecksum || hasTrustedChecksumUrl;
  }

  static Uri? _resolveChecksumUrl(
    _UpdateManifest manifest,
    _UpdatePlatformInfo platformInfo,
  ) {
    return platformInfo.checksumUrl ?? manifest.checksumsUrl;
  }

  static Future<bool> _launchWindowsUpdaterHelper(
    _UpdateManifest manifest,
    _UpdatePlatformInfo platformInfo, {
    required Uri manifestUri,
    required String trigger,
  }) async {
    final downloadUrl = platformInfo.downloadUrl;
    if (downloadUrl == null ||
        !_canRunWindowsAutoUpdate(
          manifest,
          platformInfo,
          manifestUri: manifestUri,
        )) {
      return false;
    }

    final helperExe = await _createWindowsUpdaterRuntime();
    if (helperExe == null) {
      return false;
    }

    final checksumUrl = _resolveChecksumUrl(manifest, platformInfo);
    final args = <String>[
      _windowsUpdaterArg,
      "--installer-url",
      downloadUrl.toString(),
      "--version",
      manifest.version,
      "--app-exe",
      Platform.resolvedExecutable,
      "--manifest-url",
      manifestUri.toString(),
      "--trigger",
      trigger,
      if (platformInfo.sha256 != null) ...[
        "--sha256",
        platformInfo.sha256!,
      ],
      if (platformInfo.sizeBytes != null) ...[
        "--size-bytes",
        platformInfo.sizeBytes.toString(),
      ],
      if (checksumUrl != null) ...[
        "--checksum-url",
        checksumUrl.toString(),
      ],
      if (platformInfo.allowUnsignedAutoUpdate) "--allow-unsigned-auto-update",
    ];

    await Process.start(
      helperExe,
      args,
      workingDirectory: path.dirname(helperExe),
      runInShell: false,
    );
    return true;
  }

  static Future<String?> _createWindowsUpdaterRuntime() async {
    if (path.basename(Platform.resolvedExecutable).toLowerCase() !=
        "intergalactic.exe") {
      Log.w(
        "Skipping Windows updater helper launch because the current "
        "executable is not the packaged InterGalactic.exe",
        source: "windows-updater",
      );
      return null;
    }

    final installDir = Directory(path.dirname(Platform.resolvedExecutable));
    if (!await installDir.exists()) {
      return null;
    }

    unawaited(_cleanupOldWindowsUpdaterRuntimes());

    final runtimeDir = await Directory.systemTemp.createTemp(
      "intergalactic-updater-runtime-",
    );
    await for (final entity in installDir.list(recursive: true)) {
      final relativePath = path.relative(entity.path, from: installDir.path);
      final targetPath = path.join(runtimeDir.path, relativePath);

      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(path.dirname(targetPath)).create(recursive: true);
        await entity.copy(targetPath);
      }
    }

    final helperExe = path.join(
      runtimeDir.path,
      path.basename(Platform.resolvedExecutable),
    );
    return await File(helperExe).exists() ? helperExe : null;
  }

  static Future<void> _cleanupOldWindowsUpdaterRuntimes() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 2));
      await for (final entity in Directory.systemTemp.list()) {
        if (entity is! Directory) {
          continue;
        }

        if (!path.basename(entity.path).startsWith(
              "intergalactic-updater-runtime-",
            )) {
          continue;
        }

        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to clean old updater runtimes",
        source: "windows-updater",
      );
    }
  }

  static Future<void> _configureWindowsUpdaterWindow() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle("Updating Inter Galactic");
      await windowManager.setMinimumSize(const Size(420, 260));
      await windowManager.setSize(const Size(520, 300));
      await windowManager.center();
      await windowManager.show();
      await windowManager.focus();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to configure updater window",
        source: "windows-updater",
      );
    }
  }

  static bool _isTrustedManifestUri(Uri? uri) {
    return uri != null && uri.scheme == "https" && uri.host.isNotEmpty;
  }

  static bool _isTrustedUpdateAssetUri(Uri? uri, {Uri? manifestUri}) {
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) {
      return false;
    }

    if (manifestUri == null) {
      return true;
    }

    // Allow github.com asset/release URLs when the manifest is hosted on
    // raw.githubusercontent.com — both are within the same GitHub trust
    // boundary and controlled by the same repository.
    if (manifestUri.host == "raw.githubusercontent.com" &&
        (uri.host == "github.com" || uri.host == "raw.githubusercontent.com")) {
      return true;
    }

    return uri.host == manifestUri.host;
  }

  static bool _hasTrustedUpdateDestination(
    Uri manifestUri,
    _UpdateManifest manifest,
    _UpdatePlatformInfo platformInfo,
  ) {
    final destinations = <Uri?>[
      manifest.releaseUrl,
      manifest.checksumsUrl,
      platformInfo.releaseUrl,
      platformInfo.downloadUrl,
      platformInfo.checksumUrl,
    ];

    return destinations.whereType<Uri>().every(
        (uri) => _isTrustedUpdateAssetUri(uri, manifestUri: manifestUri));
  }

  static String? _normalizeSha256(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-F0-9]{64}$').hasMatch(normalized)) {
      return null;
    }

    return normalized;
  }

  static String? _parseSha256FromChecksums(
    String checksums,
    String fileName,
  ) {
    for (final line in LineSplitter.split(checksums)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final releaseFormat = RegExp(
        r'^SHA256\s+(.+?)\s+([A-Fa-f0-9]{64})$',
      ).firstMatch(trimmed);
      if (releaseFormat != null && releaseFormat.group(1) == fileName) {
        return _normalizeSha256(releaseFormat.group(2));
      }

      final sha256sumFormat = RegExp(
        r'^([A-Fa-f0-9]{64})\s+\*?(.+)$',
      ).firstMatch(trimmed);
      if (sha256sumFormat != null &&
          sha256sumFormat.group(2)?.trim() == fileName) {
        return _normalizeSha256(sha256sumFormat.group(1));
      }
    }

    return null;
  }

  static Uri? _trustedNotesUri(Uri manifestUri, Uri? notesUri) {
    if (notesUri == null) {
      return null;
    }

    if (_isTrustedUpdateAssetUri(notesUri, manifestUri: manifestUri)) {
      return notesUri;
    }

    Log.w("Ignoring untrusted update notes URL: $notesUri");
    return null;
  }

  static Future<ProcessResult> _runWindowsPowerShellInstallerScript({
    required String scriptName,
    required String script,
    required String installerPath,
  }) async {
    final scriptDir = await Directory.systemTemp.createTemp(
      "intergalactic-updater-powershell-",
    );
    final scriptFile = File(path.join(scriptDir.path, scriptName));

    try {
      await scriptFile.writeAsString(script, flush: true);
      // Keep the temp script alive until powershell.exe has opened and run it.
      final result = await Process.run(
        "powershell.exe",
        _windowsPowerShellFileArgs(scriptFile.path, installerPath),
      );
      return result;
    } finally {
      try {
        if (await scriptDir.exists()) {
          await scriptDir.delete(recursive: true);
        }
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: "Failed to clean updater PowerShell script",
          source: "windows-updater",
        );
      }
    }
  }

  static List<String> _windowsPowerShellFileArgs(
    String scriptPath,
    String installerPath,
  ) {
    return [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
      installerPath,
    ];
  }
}

class _WindowsInstallerSignatureCheck {
  final bool isValid;
  final bool canAskForUnsignedApproval;
  final String status;
  final String details;

  const _WindowsInstallerSignatureCheck({
    required this.isValid,
    required this.canAskForUnsignedApproval,
    required this.status,
    required this.details,
  });

  String get summary {
    if (details.isEmpty) {
      return "status=$status";
    }

    return "status=$status; $details";
  }

  factory _WindowsInstallerSignatureCheck.fromProcessResult(
    ProcessResult result,
  ) {
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();
    final fields = <String, String>{};

    for (final line in LineSplitter.split(stdout.replaceAll('\r\n', '\n'))) {
      final separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }

      fields[line.substring(0, separator).trim()] =
          line.substring(separator + 1).trim();
    }

    final hasSignatureStatus = fields["status"] != null;
    final status =
        fields["status"] ?? (result.exitCode == 0 ? "Valid" : "Unknown");
    final statusMessage = fields["status_message"];
    final signerSubject = fields["signer_subject"];
    final detailParts = <String>[
      if (statusMessage != null && statusMessage.isNotEmpty)
        "message=$statusMessage",
      if (signerSubject != null && signerSubject.isNotEmpty)
        "signer=$signerSubject",
      if (stderr.isNotEmpty) stderr,
      if (fields.isEmpty && stdout.isNotEmpty) stdout,
    ];

    return _WindowsInstallerSignatureCheck(
      isValid: result.exitCode == 0 && status.toLowerCase() == "valid",
      canAskForUnsignedApproval: hasSignatureStatus && result.exitCode != 0,
      status: status,
      details: detailParts.join("; "),
    );
  }
}

class _WindowsUpdaterRequest {
  final Uri installerUrl;
  final String version;
  final String appExe;
  final Uri? manifestUrl;
  final Uri? checksumUrl;
  final String? sha256;
  final int? sizeBytes;
  final String trigger;
  final bool allowUnsignedAutoUpdate;

  const _WindowsUpdaterRequest({
    required this.installerUrl,
    required this.version,
    required this.appExe,
    required this.trigger,
    required this.allowUnsignedAutoUpdate,
    this.manifestUrl,
    this.checksumUrl,
    this.sha256,
    this.sizeBytes,
  });

  bool get hasTrustedDestinations {
    final manifest = manifestUrl;
    if (manifest == null || !UpdateChecker._isTrustedManifestUri(manifest)) {
      return false;
    }

    if (!UpdateChecker._isTrustedUpdateAssetUri(
      installerUrl,
      manifestUri: manifest,
    )) {
      return false;
    }

    final checksum = checksumUrl;
    if (checksum != null &&
        !UpdateChecker._isTrustedUpdateAssetUri(
          checksum,
          manifestUri: manifest,
        )) {
      return false;
    }

    return true;
  }

  factory _WindowsUpdaterRequest.fromArgs(List<String> args) {
    final installerUrl = _argUri(args, "--installer-url");
    final version = _argValue(args, "--version");
    final appExe = _argValue(args, "--app-exe");
    final sizeBytes = int.tryParse(_argValue(args, "--size-bytes") ?? "");

    if (installerUrl == null || version == null || appExe == null) {
      throw const FormatException("Missing Windows updater arguments");
    }

    return _WindowsUpdaterRequest(
      installerUrl: installerUrl,
      version: version,
      appExe: appExe,
      manifestUrl: _argUri(args, "--manifest-url"),
      checksumUrl: _argUri(args, "--checksum-url"),
      sha256: _argValue(args, "--sha256"),
      sizeBytes: sizeBytes,
      trigger: _argValue(args, "--trigger") ?? "unknown",
      allowUnsignedAutoUpdate: args.contains("--allow-unsigned-auto-update"),
    );
  }

  static Uri? _argUri(List<String> args, String name) {
    final value = _argValue(args, name);
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return Uri.tryParse(value);
  }

  static String? _argValue(List<String> args, String name) {
    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == name && index + 1 < args.length) {
        return args[index + 1];
      }

      final prefix = "$name=";
      if (arg.startsWith(prefix)) {
        return arg.substring(prefix.length);
      }
    }

    return null;
  }
}

class _WindowsUpdaterApp extends StatelessWidget {
  final _WindowsUpdaterRequest request;

  const _WindowsUpdaterApp({required this.request});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Updating Inter Galactic",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF66E0C2),
          secondary: Color(0xFF8FB7FF),
          surface: Color(0xFF151A24),
        ),
        scaffoldBackgroundColor: const Color(0xFF0E1117),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF66E0C2),
          linearTrackColor: Color(0xFF2D3545),
        ),
      ),
      home: _WindowsUpdaterPage(request: request),
    );
  }
}

class _WindowsUpdaterPage extends StatefulWidget {
  final _WindowsUpdaterRequest request;

  const _WindowsUpdaterPage({required this.request});

  @override
  State<_WindowsUpdaterPage> createState() => _WindowsUpdaterPageState();
}

class _WindowsUpdaterPageState extends State<_WindowsUpdaterPage> {
  double? _progress;
  String _status = "Preparing update";
  String? _details;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_runUpdate());
  }

  Future<void> _runUpdate() async {
    try {
      Log.i(
        "Starting Windows updater helper "
        "version=${widget.request.version} "
        "trigger=${widget.request.trigger} "
        "manifest=${widget.request.manifestUrl}",
        source: "windows-updater",
      );
      if (!widget.request.hasTrustedDestinations) {
        throw StateError("Updater URLs are not trusted.");
      }

      _setProgress("Downloading update", 0);
      final installer = await _downloadInstaller();

      _setProgress("Verifying checksum", null);
      await _verifyExpectedSize(installer);
      await _verifyChecksum(installer);

      _setProgress("Checking installer signature", null);
      final signatureCheck = await _checkAuthenticodeSignature(installer);
      if (!signatureCheck.isValid) {
        if (!widget.request.allowUnsignedAutoUpdate ||
            !signatureCheck.canAskForUnsignedApproval) {
          throw StateError(
            "Installer signature verification failed: "
            "${signatureCheck.summary}",
          );
        }

        final approved = await _confirmUnsignedInstaller(signatureCheck);
        if (!approved) {
          _setProgress("Starting Inter Galactic", null);
          await _restartApp();
          exit(0);
        }
      }

      _setProgress("Installing update", null);
      await _runInstaller(installer);

      _setProgress("Restarting Inter Galactic", null);
      await _restartApp();
      exit(0);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Windows updater failed",
        source: "windows-updater",
        flush: true,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _failed = true;
        _progress = null;
        _status = "Update failed";
        _details = error.toString();
      });
    }
  }

  Future<File> _downloadInstaller() async {
    final installerFileName =
        UpdateChecker._windowsInstallerFileName(widget.request.version);
    final tempDir = await Directory.systemTemp.createTemp(
      "intergalactic-update-installer-",
    );
    final installerPath = path.join(tempDir.path, installerFileName);
    final client = http.Client();
    IOSink? sink;

    try {
      final request = http.Request("GET", widget.request.installerUrl);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException(
          "Failed to download Windows installer: ${response.statusCode}",
          uri: widget.request.installerUrl,
        );
      }

      final file = File(installerPath);
      sink = file.openWrite();
      var receivedBytes = 0;
      final totalBytes = response.contentLength;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes != null && totalBytes > 0) {
          _setProgress("Downloading update", receivedBytes / totalBytes);
        }
      }

      await sink.close();
      sink = null;
      return file;
    } finally {
      await sink?.close();
      client.close();
    }
  }

  Future<void> _verifyExpectedSize(File installer) async {
    final expectedSize = widget.request.sizeBytes;
    if (expectedSize == null) {
      return;
    }

    final actualSize = await installer.length();
    if (actualSize != expectedSize) {
      throw StateError(
        "Installer size mismatch. Expected $expectedSize bytes, "
        "downloaded $actualSize bytes.",
      );
    }
  }

  Future<void> _verifyChecksum(File installer) async {
    final expected = await _expectedSha256(installer);
    final actualDigest = await crypto.sha256.bind(installer.openRead()).first;
    final actual = actualDigest.toString().toUpperCase();

    if (actual != expected) {
      throw StateError(
        "Installer checksum mismatch. Expected $expected, got $actual.",
      );
    }
  }

  Future<String> _expectedSha256(File installer) async {
    final inline = UpdateChecker._normalizeSha256(widget.request.sha256);
    if (inline != null) {
      return inline;
    }

    final checksumUrl = widget.request.checksumUrl;
    if (checksumUrl == null) {
      throw StateError("No checksum source was provided for the installer.");
    }

    final response = await http.get(checksumUrl);
    if (response.statusCode != 200) {
      throw HttpException(
        "Failed to fetch checksum file: ${response.statusCode}",
        uri: checksumUrl,
      );
    }

    final expected = UpdateChecker._parseSha256FromChecksums(
      response.body,
      path.basename(installer.path),
    );
    if (expected == null) {
      throw StateError("Checksum file does not contain this installer.");
    }

    return expected;
  }

  Future<_WindowsInstallerSignatureCheck> _checkAuthenticodeSignature(
    File installer,
  ) async {
    final result = await UpdateChecker._runWindowsPowerShellInstallerScript(
      scriptName: "verify-installer-signature.ps1",
      script: UpdateChecker._windowsSignatureVerificationScript,
      installerPath: installer.path,
    );

    return _WindowsInstallerSignatureCheck.fromProcessResult(result);
  }

  Future<bool> _confirmUnsignedInstaller(
    _WindowsInstallerSignatureCheck signatureCheck,
  ) async {
    if (!mounted) {
      return false;
    }

    _setProgress("Waiting for update approval", null);
    final details = signatureCheck.details;
    final scrollController = ScrollController();

    try {
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 16,
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: const Text("Checksum-Verified Update"),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Inter Galactic's open-source desktop updates can be "
                        "unsigned by design. Windows may warn that the "
                        "publisher cannot be verified because this release "
                        "path does not rely on a paid Windows code-signing "
                        "certificate. Before showing this prompt, Inter "
                        "Galactic verified that the downloaded installer "
                        "matches the SHA-256 checksum from the trusted update "
                        "manifest. Continue only if you trust this Inter "
                        "Galactic update source and are ready to approve the "
                        "Windows prompt.",
                      ),
                      const SizedBox(height: 12),
                      const Text("Checksum verification: passed"),
                      Text(
                        "Windows certificate status: ${signatureCheck.status}",
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          details,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Continue"),
            ),
          ],
        ),
      );

      return approved == true;
    } finally {
      scrollController.dispose();
    }
  }

  Future<void> _runInstaller(File installer) async {
    final result = await UpdateChecker._runWindowsPowerShellInstallerScript(
      scriptName: "run-installer.ps1",
      script: UpdateChecker._windowsSilentInstallerScript,
      installerPath: installer.path,
    );

    if (result.exitCode != 0) {
      throw StateError(
        "Installer exited with code ${result.exitCode}: "
        "${result.stderr}${result.stdout}",
      );
    }
  }

  Future<void> _restartApp() async {
    await Process.start(
      widget.request.appExe,
      const [],
      workingDirectory: path.dirname(widget.request.appExe),
      runInShell: false,
    );
    await Future.delayed(const Duration(milliseconds: 750));
  }

  Future<void> _openManualDownload() async {
    await Process.start(
      "rundll32.exe",
      ["url.dll,FileProtocolHandler", widget.request.installerUrl.toString()],
      runInShell: true,
    );
  }

  void _setProgress(String status, double? progress) {
    if (!mounted) {
      return;
    }

    setState(() {
      _status = status;
      _progress = progress;
      _details = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2E3747)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Updating Inter Galactic",
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    Text(_status, style: statusStyle),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(value: _progress),
                    if (_details != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _details!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (_failed) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => exit(1),
                            child: const Text("Close"),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => unawaited(_openManualDownload()),
                            child: const Text("Open download"),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
