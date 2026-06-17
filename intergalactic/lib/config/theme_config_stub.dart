import 'package:intergalactic/config/custom_theme_definition.dart';

class ThemeConfig {
  static Future<dynamic> getCustomThemesDir() async {
    return null;
  }

  static Future<List<dynamic>> getCustomThemes() async {
    return const [];
  }

  static Future<dynamic> getFileFromThemeDir(dynamic dir) async {
    return null;
  }

  static Future<dynamic> getThemeByName(String name) async {
    return null;
  }

  static Future<CustomThemeDefinition?> loadCustomTheme(dynamic dir) async {
    return null;
  }

  static Future<CustomThemeDefinition?> loadThemeByName(String name) async {
    return null;
  }

  static Future<List<CustomThemeDefinition>> loadCustomThemes() async {
    return const [];
  }

  static Future<dynamic> saveTheme(CustomThemeDraft draft) async {
    return null;
  }

  static String sanitizeThemeId(String name) {
    return 'custom_theme';
  }

  static Future<String> uniqueThemeId(String requestedId,
      {String? currentId}) async {
    return requestedId;
  }

  static Future<void> removeTheme(dynamic directory) async {}

  static Future<List<int>> exportThemeToZipBytes(String themeId) async {
    return const [];
  }

  static Future<void> exportThemeToZip(
    String themeId,
    String destinationPath,
  ) async {}

  static Future<void> installThemeFromZip(dynamic file) async {}
}
