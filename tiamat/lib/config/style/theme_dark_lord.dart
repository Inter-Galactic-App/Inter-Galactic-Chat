import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeDarkLordColors {
  static const Color primary = Color(0xFFDC2626);
  static const Color onPrimary = Colors.white;
  static const Color primaryContainer = Color(0xFF7F1D1D);
  static const Color onPrimaryContainer = Color(0xFFFEE2E2);
  static const Color secondary = Color(0xFFEF4444);
  static const Color onSecondary = Color(0xFF1C0000);
  static const Color secondaryContainer = Color(0xFF450A0A);
  static const Color onSecondaryContainer = Color(0xFFFCA5A5);
  static const Color tertiary = Color(0xFFF87171);
  static const Color surface = Color(0xFF1F1F1F);
  static const Color onSurface = Color(0xFFF5F5F5);
  static const Color surfaceContainerLowest = Color(0xFF0A0A0A);
  static const Color surfaceContainerLow = Color(0xFF111111);
  static const Color surfaceContainer = Color(0xFF1A1A1A);
  static const Color surfaceContainerHigh = Color(0xFF252525);
  static const Color surfaceContainerHighest = Color(0xFF2D2D2D);
  static const Color outline = Color(0xFF2D2D2D);
  static const Color foundation = Color(0xFF050505);
}

class ThemeDarkLord {
  static ThemeData get theme => ThemeBase.theme(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: ThemeDarkLordColors.primary,
          onPrimary: ThemeDarkLordColors.onPrimary,
          primaryContainer: ThemeDarkLordColors.primaryContainer,
          onPrimaryContainer: ThemeDarkLordColors.onPrimaryContainer,
          secondary: ThemeDarkLordColors.secondary,
          onSecondary: ThemeDarkLordColors.onSecondary,
          secondaryContainer: ThemeDarkLordColors.secondaryContainer,
          onSecondaryContainer: ThemeDarkLordColors.onSecondaryContainer,
          tertiary: ThemeDarkLordColors.tertiary,
          onTertiary: Color(0xFF250000),
          error: Color(0xFFFF8A8A),
          onError: Colors.black,
          surface: ThemeDarkLordColors.surface,
          onSurface: ThemeDarkLordColors.onSurface,
          surfaceContainerLowest: ThemeDarkLordColors.surfaceContainerLowest,
          surfaceContainerLow: ThemeDarkLordColors.surfaceContainerLow,
          surfaceContainer: ThemeDarkLordColors.surfaceContainer,
          surfaceContainerHigh: ThemeDarkLordColors.surfaceContainerHigh,
          surfaceContainerHighest: ThemeDarkLordColors.surfaceContainerHighest,
          outline: ThemeDarkLordColors.outline,
        ),
      ).copyWith(
        extensions: const [
          ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
          FoundationSettings(color: ThemeDarkLordColors.foundation),
          ExtraColors(
            codeHighlight: ThemeDarkLordColors.primary,
            linkColor: ThemeDarkLordColors.tertiary,
          ),
        ],
      );
}
