import 'dart:convert';
import 'dart:io';

String? getArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }

  return args[index + 1];
}

Uri? parseUriArg(List<String> args, String name) {
  final value = getArg(args, name);
  if (value == null || value.isEmpty) {
    return null;
  }

  return Uri.tryParse(value);
}

bool parseBoolArg(List<String> args, String name, {bool fallback = false}) {
  final value = getArg(args, name);
  if (value == null) {
    return fallback;
  }

  return value.toLowerCase() == 'true';
}

({String versionName, int buildNumber}) parseVersionTag(String versionTag) {
  final match = RegExp(r'^v?(\d+\.\d+\.\d+)\+(\d+)$').firstMatch(versionTag);
  if (match == null) {
    stderr.writeln(
      'Expected --version_tag to use full pubspec identity, for example v0.7.0+968.',
    );
    exit(1);
  }

  return (
    versionName: match[1]!,
    buildNumber: int.parse(match[2]!),
  );
}

Map<String, dynamic>? buildPlatform(
  List<String> args, {
  required String name,
  required bool includeAutoUpdate,
}) {
  final downloadUrl = parseUriArg(args, '--${name}_download_url');
  final releaseUrl = parseUriArg(args, '--${name}_release_url');

  if (downloadUrl == null && releaseUrl == null && !includeAutoUpdate) {
    return null;
  }

  final data = <String, dynamic>{};
  if (downloadUrl != null) {
    data['download_url'] = downloadUrl.toString();
  }
  if (releaseUrl != null) {
    data['release_url'] = releaseUrl.toString();
  }
  if (includeAutoUpdate) {
    data['auto_update'] = parseBoolArg(args, '--${name}_auto_update');
  }

  return data;
}

void main(List<String> args) {
  final outputPath = getArg(args, '--output');
  final versionTag = getArg(args, '--version_tag');
  final versionName = getArg(args, '--version_name');
  final buildNumber = getArg(args, '--build_number');
  final buildDateMs = getArg(args, '--build_date_ms');
  final notes = getArg(args, '--notes');
  final notesUrl = parseUriArg(args, '--notes_url');
  final featureNotes = getArg(args, '--feature_notes');
  final featureNotesUrl = parseUriArg(args, '--feature_notes_url');
  final parsedBuildNumber =
      buildNumber == null ? null : int.tryParse(buildNumber);
  final parsedBuildDateMs =
      buildDateMs == null ? null : int.tryParse(buildDateMs);

  if (outputPath == null ||
      versionTag == null ||
      buildDateMs == null ||
      parsedBuildDateMs == null ||
      (buildNumber != null && parsedBuildNumber == null)) {
    stderr.writeln(
      'Usage: dart run scripts/generate_update_manifest.dart '
      '--output <path> --version_tag <tag> --build_date_ms <epoch_ms> '
      '[--version_name <semver>] [--build_number <number>] '
      '[--notes <summary>] [--notes_url <url>] '
      '[--feature_notes <markdown>] [--feature_notes_url <url>] '
      '[--release_url <url>] [--windows_download_url <url>] '
      '[--linux_download_url <url>] [--android_download_url <url>]',
    );
    exit(1);
  }

  final identity = parseVersionTag(versionTag);

  if (versionName != null && versionName != identity.versionName) {
    stderr.writeln(
      '--version_name "$versionName" does not match --version_tag "$versionTag".',
    );
    exit(1);
  }

  if (parsedBuildNumber != null && parsedBuildNumber != identity.buildNumber) {
    stderr.writeln(
      '--build_number "$buildNumber" does not match --version_tag "$versionTag".',
    );
    exit(1);
  }

  final releaseUrl = parseUriArg(args, '--release_url');

  final platforms = <String, dynamic>{};
  final windows = buildPlatform(args, name: 'windows', includeAutoUpdate: true);
  final linux = buildPlatform(args, name: 'linux', includeAutoUpdate: false);
  final android =
      buildPlatform(args, name: 'android', includeAutoUpdate: false);

  if (windows != null) {
    platforms['windows'] = windows;
  }
  if (linux != null) {
    platforms['linux'] = linux;
  }
  if (android != null) {
    platforms['android'] = android;
  }

  final manifest = <String, dynamic>{
    'version': versionTag,
    'version_name': versionName ?? identity.versionName,
    'build_number': parsedBuildNumber ?? identity.buildNumber,
    'build_date_ms': parsedBuildDateMs,
    if (releaseUrl != null) 'release_url': releaseUrl.toString(),
    if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    if (notesUrl != null) 'notes_url': notesUrl.toString(),
    if (featureNotes != null && featureNotes.trim().isNotEmpty)
      'feature_notes': featureNotes.trim(),
    if (featureNotesUrl != null)
      'feature_notes_url': featureNotesUrl.toString(),
    'platforms': platforms,
  };

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
}
