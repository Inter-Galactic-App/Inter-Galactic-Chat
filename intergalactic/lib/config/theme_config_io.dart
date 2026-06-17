import 'dart:io';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ThemeConfig {
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

    var directories = await dir.list().where((e) => e is Directory).toList();
    return List<Directory>.from(directories);
  }

  static Future<File?> getFileFromThemeDir(Directory dir) async {
    var file = File(path.join(dir.path, "theme.json"));
    if ((await file.exists()) == false) {
      return null;
    }

    return file;
  }

  static Future<File?> getThemeByName(String name) async {
    var dir = await getCustomThemesDir();
    var themeDir = Directory(path.join(dir.path, name));

    return getFileFromThemeDir(themeDir);
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

      final id = path.basenameWithoutExtension(dir.path);
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

      return CustomThemeDefinition.fromJson(name, json);
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to load custom theme "$name"',
      );
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
      final exists = await Directory(path.join(dir.path, candidate)).exists();

      if (matchesCurrent || !exists) {
        return candidate;
      }

      candidate = '${requestedId}_$suffix';
      suffix++;
    }
  }

  static Future<void> removeTheme(Directory directory) async {
    await directory.delete(recursive: true);
  }

  static Future<List<int>> exportThemeToZipBytes(String themeId) async {
    final root = await getCustomThemesDir();
    final themeDir = Directory(path.join(root.path, themeId));
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
      archive.addFile(
        ArchiveFile(normalizedRelativePath, bytes.length, bytes),
      );
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

  static Future<void> installThemeFromZip(File file) async {
    final inputStream = InputFileStream(file.path);

    var dir = await getCustomThemesDir();
    var destination =
        (path.join(dir.path, path.basenameWithoutExtension(file.path)));

    final archive = ZipDecoder().decodeBuffer(inputStream);

    if (!archive.files.any((file) => file.name == "theme.json")) {
      await inputStream.close();
      Log.w("Invalid theme archive: ${file.path}");
      return;
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
      file.writeContent(outputStream);
      outputStream.close();
    }

    await inputStream.close();
  }
}
