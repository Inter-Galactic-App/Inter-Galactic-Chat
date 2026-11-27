import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeDarkColors {
  static const Color surfaceContainerHigh = Color.fromARGB(255, 47, 51, 55);
  static const Color secondary = Color.fromARGB(255, 128, 128, 128);
  static const Color primary = Color(0xFF0B7FAE);
  static const Color surface = Color.fromARGB(255, 43, 46, 49);
  static const Color surfaceContainer = Color.fromARGB(255, 38, 41, 44);
  static const Color surfaceContainerLow = Color.fromARGB(255, 30, 34, 37);
  static const Color surfaceLow3 = Color.fromARGB(255, 25, 28, 31);
  static const Color surfaceContainerLowest = Color.fromARGB(255, 19, 21, 22);
  static const Color onSurface = Colors.white;
  static const Color highlightColor = Colors.white10;
  static const Color outlineColor = Color.fromARGB(255, 30, 34, 37);
}

class ThemeDark {
  static ThemeData get theme {
    var scheme = ColorScheme.fromSeed(
        seedColor: ThemeDarkColors.surface,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
        primary: ThemeDarkColors.primary,
        onPrimary: Colors.white,
        surface: ThemeDarkColors.surface,
        surfaceContainer: ThemeDarkColors.surfaceContainer,
        surfaceContainerLow: ThemeDarkColors.surfaceContainerLow,
        surfaceContainerLowest: ThemeDarkColors.surfaceContainerLowest,
        primaryContainer: ThemeDarkColors.primary,
        brightness: Brightness.dark,
        outline: ThemeDarkColors.surfaceContainerHigh);

    return ThemeBase.theme(scheme).copyWith(extensions: [
      const ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
      FoundationSettings(color: scheme.surfaceDim),
      const ExtraColors(
          codeHighlight: Color(0xFF22A6C8), linkColor: Color(0xFF2394C7))
    ]);
  }
}
