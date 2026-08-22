import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:universal_html/html.dart' as html;

class ThemeConfig {
  static const String _storageKey = 'intergalactic.custom_themes';

  static Future<dynamic> getCustomThemesDir() async {
    return null;
  }

  static Future<List<dynamic>> getCustomThemes() async {
    return loadCustomThemes();
  }

  static Future<dynamic> getFileFromThemeDir(dynamic dir) async {
    return null;
  }

  static Future<dynamic> getThemeByName(String name) async {
    return loadThemeByName(name);
  }

  static Future<CustomThemeDefinition?> loadCustomTheme(dynamic dir) async {
    if (dir is CustomThemeDefinition) {
      return dir;
    }

    if (dir is Map<String, dynamic>) {
      final id = dir['id'];
      final data = dir['json'];
      if (id is String && data is Map<String, dynamic>) {
        return CustomThemeDefinition.fromJson(id, data);
      }
    }

    return null;
  }

  static Future<CustomThemeDefinition?> loadThemeByName(String name) async {
    final stored = _readStoredThemes();
    final json = stored[name];
    return json != null ? CustomThemeDefinition.fromJson(name, json) : null;
  }

  static Future<List<CustomThemeDefinition>> loadCustomThemes() async {
    final stored = _readStoredThemes();
    return stored.entries
        .map((entry) => CustomThemeDefinition.fromJson(entry.key, entry.value))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  static Future<CustomThemeDefinition> saveTheme(CustomThemeDraft draft) async {
    final stored = _readStoredThemes();
    final id = await uniqueThemeId(
      draft.id ?? sanitizeThemeId(draft.name),
      currentId: draft.id,
    );
    final json = draft.toJson();
    stored[id] = json;
    _writeStoredThemes(stored);
    return CustomThemeDefinition.fromJson(id, json);
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
    final stored = _readStoredThemes();
    var candidate = requestedId;
    var suffix = 2;

    while (true) {
      final matchesCurrent = currentId != null && candidate == currentId;
      final exists = stored.containsKey(candidate);

      if (matchesCurrent || !exists) {
        return candidate;
      }

      candidate = '${requestedId}_$suffix';
      suffix++;
    }
  }

  static Future<void> removeTheme(dynamic directory) async {
    final stored = _readStoredThemes();
    final id = switch (directory) {
      CustomThemeDefinition definition => definition.id,
      String value => value,
      _ => null,
    };

    if (id == null) {
      return;
    }

    stored.remove(id);
    _writeStoredThemes(stored);
  }

  static Future<List<int>> exportThemeToZipBytes(String themeId) async {
    final stored = _readStoredThemes();
    final json = stored[themeId];
    if (json == null) {
      throw StateError('Custom theme "$themeId" could not be found.');
    }

    const encoder = JsonEncoder.withIndent('  ');
    final bytes = utf8.encode('${encoder.convert(json)}\n');
    final archive = Archive()
      ..addFile(ArchiveFile('theme.json', bytes.length, bytes));
    return ZipEncoder().encode(archive) ?? const [];
  }

  static Future<void> exportThemeToZip(
    String themeId,
    String destinationPath,
  ) async {
    await exportThemeToZipBytes(themeId);
  }

  static Future<CustomThemeDefinition?> installThemeFromZip(
    dynamic file,
  ) async {
    Log.w('Theme archive import is not available in the web build.');
    return null;
  }

  static Map<String, Map<String, dynamic>> _readStoredThemes() {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.isEmpty) {
      return <String, Map<String, dynamic>>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, Map<String, dynamic>>{};
      }

      final result = <String, Map<String, dynamic>>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! Map) {
          continue;
        }

        result[key] = Map<String, dynamic>.from(value);
      }

      return result;
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to read stored custom web themes',
      );
      return <String, Map<String, dynamic>>{};
    }
  }

  static void _writeStoredThemes(Map<String, Map<String, dynamic>> themes) {
    html.window.localStorage[_storageKey] = jsonEncode(themes);
  }
}
