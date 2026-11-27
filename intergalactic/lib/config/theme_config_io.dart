import 'dart:io';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ThemeConfig {
  static const String _themeArchiveFolderSuffix = '.intergalactic-theme';

  static Future<Directory> getCustomThemesDir() async {
    var dir = await getApplicationSupportDirectory();
    var p = dir.path;

    var directory = Directory(path.join(p, "theme", "custom"));
    var exists = await directory.exists();
    if (!exists) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  static Future<List<Directory>> getCustomThemes() async {
    var dir = await getCustomThemesDir();

    final directories = List<Directory>.from(
      await dir.list().where((e) => e is Directory).toList(),
    );
    final canonicalNames = <String>{};
    for (final directory in directories) {
      final name = path.basename(directory.path);
      if (_isLegacyArchiveFolderName(name)) {
        continue;
      }
      if (await getFileFromThemeDir(directory) != null) {
        canonicalNames.add(name);
      }
    }

    return directories.where((directory) {
      final name = path.basename(directory.path);
      if (!_isLegacyArchiveFolderName(name)) {
        return true;
      }

      return !canonicalNames.contains(_themeIdFromStorageName(name));
    }).toList();
  }

  static Future<File?> getFileFromThemeDir(Directory dir) async {
    var file = File(path.join(dir.path, "theme.json"));
    if ((await file.exists()) == false) {
      return null;
    }

    return file;
  }

  static Future<File?> getThemeByName(String name) async {
    final dir = await getCustomThemesDir();
    for (final themeDir in _themeDirectoryCandidates(dir, name)) {
      final file = await getFileFromThemeDir(themeDir);
      if (file != null) {
        return file;
      }
    }

    return null;
  }

  static Future<CustomThemeDefinition?> loadCustomTheme(Directory dir) async {
    final file = await getFileFromThemeDir(dir);
    if (file == null) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }

      final id = _themeIdFromStorageName(path.basename(dir.path));
      return CustomThemeDefinition.fromJson(id, json);
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to load custom theme from ${dir.path}',
      );
      return null;
    }
  }

  static Future<CustomThemeDefinition?> loadThemeByName(String name) async {
    final file = await getThemeByName(name);
    if (file == null) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }

      return CustomThemeDefinition.fromJson(
        _themeIdFromStorageName(path.basename(path.dirname(file.path))),
        json,
      );
    } catch (error, trace) {
      Log.onError(error, trace, content: 'Failed to load custom theme "$name"');
      return null;
    }
  }

  static Future<List<CustomThemeDefinition>> loadCustomThemes() async {
    final themes = await getCustomThemes();
    final loaded = await Future.wait(themes.map(loadCustomTheme));
    return loaded.whereType<CustomThemeDefinition>().toList();
  }

  static Future<File> saveTheme(CustomThemeDraft draft) async {
    final root = await getCustomThemesDir();
    final id = await uniqueThemeId(
      draft.id ?? sanitizeThemeId(draft.name),
      currentId: draft.id,
    );
    final themeDir = Directory(path.join(root.path, id));
    if ((await themeDir.exists()) == false) {
      await themeDir.create(recursive: true);
    }

    final file = File(path.join(themeDir.path, 'theme.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(draft.toJson())}\n');

    return file;
  }

  static String sanitizeThemeId(String name) {
    final trimmed = name.trim().toLowerCase();
    final cleaned = trimmed
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    return cleaned.isNotEmpty ? cleaned : 'custom_theme';
  }

  static Future<String> uniqueThemeId(
    String requestedId, {
    String? currentId,
  }) async {
    final dir = await getCustomThemesDir();
    var candidate = requestedId;
    var suffix = 2;

    while (true) {
      final matchesCurrent = currentId != null && candidate == currentId;
      final exists = await _themeStorageExists(dir, candidate);

      if (matchesCurrent || !exists) {
        return candidate;
      }

      candidate = '${requestedId}_$suffix';
      suffix++;
    }
  }

  static Future<void> removeTheme(dynamic target) async {
    final directories = await _resolveThemeDirectories(target);
    for (final directory in directories) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  static Future<List<int>> exportThemeToZipBytes(String themeId) async {
    final directories = await _resolveThemeDirectories(themeId);
    if (directories.isEmpty) {
      throw StateError('Custom theme "$themeId" could not be found.');
    }

    final themeDir = directories.first;
    final themeFile = await getFileFromThemeDir(themeDir);

    if (themeFile == null) {
      throw StateError('Custom theme "$themeId" could not be found.');
    }

    final archive = Archive();
    await for (final entity in themeDir.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }

      final relativePath = path.relative(entity.path, from: themeDir.path);
      final normalizedRelativePath = path.normalize(relativePath);
      if (path.isAbsolute(normalizedRelativePath) ||
          normalizedRelativePath.startsWith('..') ||
          normalizedRelativePath.contains('../') ||
          normalizedRelativePath.contains('..\\')) {
        continue;
      }

      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(normalizedRelativePath, bytes.length, bytes));
    }

    return ZipEncoder().encode(archive) ?? const [];
  }

  static Future<void> exportThemeToZip(
    String themeId,
    String destinationPath,
  ) async {
    final bytes = await exportThemeToZipBytes(themeId);
    await File(destinationPath).writeAsBytes(bytes);
  }

  static Future<CustomThemeDefinition?> installThemeFromZip(File file) async {
    final inputStream = InputFileStream(file.path);

    try {
      final dir = await getCustomThemesDir();
      final requestedId = _themeIdFromArchivePath(file.path);
      final themeId = await uniqueThemeId(requestedId);
      final destination = path.join(dir.path, themeId);

      final archive = ZipDecoder().decodeBuffer(inputStream);

      if (!archive.files.any((file) => file.name == "theme.json")) {
        Log.w("Invalid theme archive: ${file.path}");
        return null;
      }

      for (var file in archive.files) {
        if (!file.isFile) {
          continue;
        }

        final normalizedRelativePath = path.normalize(file.name);
        if (path.isAbsolute(normalizedRelativePath) ||
            normalizedRelativePath.startsWith('..') ||
            normalizedRelativePath.contains('../') ||
            normalizedRelativePath.contains('..\\')) {
          Log.w("Skipping unsafe theme archive entry: ${file.name}");
          continue;
        }

        final outputPath = path.normalize(
          path.join(destination, normalizedRelativePath),
        );
        if (!path.isWithin(destination, outputPath) &&
            outputPath != destination) {
          Log.w("Skipping out-of-bounds theme archive entry: ${file.name}");
          continue;
        }

        final parentDirectory = Directory(path.dirname(outputPath));
        if ((await parentDirectory.exists()) == false) {
          await parentDirectory.create(recursive: true);
        }

        final outputStream = OutputFileStream(outputPath);
        try {
          file.writeContent(outputStream);
        } finally {
          outputStream.close();
        }
      }

      return loadCustomTheme(Directory(destination));
    } finally {
      await inputStream.close();
    }
  }

  static String _themeIdFromArchivePath(String filePath) {
    final archiveName = path.basenameWithoutExtension(filePath);
    return _themeIdFromStorageName(archiveName);
  }

  static String _themeIdFromStorageName(String storageName) {
    if (_isLegacyArchiveFolderName(storageName)) {
      return storageName.substring(
        0,
        storageName.length - _themeArchiveFolderSuffix.length,
      );
    }

    return storageName;
  }

  static bool _isLegacyArchiveFolderName(String storageName) {
    return storageName.endsWith(_themeArchiveFolderSuffix) &&
        storageName.length > _themeArchiveFolderSuffix.length;
  }

  static List<Directory> _themeDirectoryCandidates(
    Directory root,
    String themeId,
  ) {
    final trimmed = themeId.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final normalized = _themeIdFromStorageName(trimmed);
    final candidates = <String>[
      path.join(root.path, trimmed),
      if (normalized != trimmed) path.join(root.path, normalized),
      if (!_isLegacyArchiveFolderName(trimmed))
        path.join(root.path, '$trimmed$_themeArchiveFolderSuffix'),
    ];

    return candidates.toSet().map(Directory.new).toList();
  }

  static Future<bool> _themeStorageExists(
    Directory root,
    String themeId,
  ) async {
    for (final directory in _themeDirectoryCandidates(root, themeId)) {
      if (await directory.exists()) {
        return true;
      }
    }

    return false;
  }

  static Future<List<Directory>> _resolveThemeDirectories(
    dynamic target,
  ) async {
    if (target is Directory) {
      if (await target.exists()) {
        return [target];
      }

      final root = target.parent;
      final themeId = _themeIdFromStorageName(path.basename(target.path));
      final directories = <Directory>[];
      for (final candidate in _themeDirectoryCandidates(root, themeId)) {
        if (await candidate.exists()) {
          directories.add(candidate);
        }
      }

      return directories;
    }

    final themeId = switch (target) {
      CustomThemeDefinition definition => definition.id,
      String value => value,
      _ => null,
    };

    if (themeId == null) {
      return const [];
    }

    final root = await getCustomThemesDir();
    final directories = <Directory>[];
    for (final candidate in _themeDirectoryCandidates(root, themeId)) {
      if (await candidate.exists()) {
        directories.add(candidate);
      }
    }

    return directories;
  }
}
