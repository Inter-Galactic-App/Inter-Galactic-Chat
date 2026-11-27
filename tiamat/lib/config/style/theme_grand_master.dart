import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeGrandMasterColors {
  static const Color primary = Color(0xFF00B4D8);
  static const Color onPrimary = Colors.white;
  static const Color primaryContainer = Color(0xFF0077A8);
  static const Color onPrimaryContainer = Color(0xFFE0F7FF);
  static const Color secondary = Color(0xFF38BDF8);
  static const Color onSecondary = Color(0xFF001824);
  static const Color secondaryContainer = Color(0xFF0369A1);
  static const Color onSecondaryContainer = Color(0xFFE0F2FE);
  static const Color tertiary = Color(0xFF67E8F9);
  static const Color surface = Color(0xFF1B2D4F);
  static const Color onSurface = Color(0xFFE8F0F8);
  static const Color surfaceContainerLowest = Color(0xFF0D1626);
  static const Color surfaceContainerLow = Color(0xFF111E33);
  static const Color surfaceContainer = Color(0xFF162540);
  static const Color surfaceContainerHigh = Color(0xFF213558);
  static const Color surfaceContainerHighest = Color(0xFF274060);
  static const Color outline = Color(0xFF213558);
  static const Color foundation = Color(0xFF080E1A);
}

class ThemeGrandMaster {
  static ThemeData get theme => ThemeBase.theme(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: ThemeGrandMasterColors.primary,
          onPrimary: ThemeGrandMasterColors.onPrimary,
          primaryContainer: ThemeGrandMasterColors.primaryContainer,
          onPrimaryContainer: ThemeGrandMasterColors.onPrimaryContainer,
          secondary: ThemeGrandMasterColors.secondary,
          onSecondary: ThemeGrandMasterColors.onSecondary,
          secondaryContainer: ThemeGrandMasterColors.secondaryContainer,
          onSecondaryContainer: ThemeGrandMasterColors.onSecondaryContainer,
          tertiary: ThemeGrandMasterColors.tertiary,
          onTertiary: Color(0xFF001F27),
          error: Color(0xFFFF8A8A),
          onError: Colors.black,
          surface: ThemeGrandMasterColors.surface,
          onSurface: ThemeGrandMasterColors.onSurface,
          surfaceContainerLowest: ThemeGrandMasterColors.surfaceContainerLowest,
          surfaceContainerLow: ThemeGrandMasterColors.surfaceContainerLow,
          surfaceContainer: ThemeGrandMasterColors.surfaceContainer,
          surfaceContainerHigh: ThemeGrandMasterColors.surfaceContainerHigh,
          surfaceContainerHighest:
              ThemeGrandMasterColors.surfaceContainerHighest,
          outline: ThemeGrandMasterColors.outline,
        ),
      ).copyWith(
        extensions: const [
          ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
          FoundationSettings(color: ThemeGrandMasterColors.foundation),
          ExtraColors(
            codeHighlight: Color(0xFF0EA5E9),
            linkColor: ThemeGrandMasterColors.secondary,
          ),
        ],
      );
}
