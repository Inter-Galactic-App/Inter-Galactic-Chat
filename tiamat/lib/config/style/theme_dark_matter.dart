import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeDarkMatterColors {
  static const Color primary = Color(0xFF25A7F2);
  static const Color onPrimary = Color(0xFF001B2A);
  static const Color primaryContainer = Color(0xFF0B5F8E);
  static const Color onPrimaryContainer = Color(0xFFD9F2FF);
  static const Color secondary = Color(0xFFB7BCC7);
  static const Color onSecondary = Color(0xFF15181D);
  static const Color secondaryContainer = Color(0xFF272B33);
  static const Color onSecondaryContainer = Color(0xFFE6EAF2);
  static const Color tertiary = Color(0xFF4DC9F6);
  static const Color onTertiary = Color(0xFF001E2A);
  static const Color tertiaryContainer = Color(0xFF16465F);
  static const Color onTertiaryContainer = Color(0xFFD7F5FF);
  static const Color surface = Color(0xFF1B1C20);
  static const Color onSurface = Color(0xFFF2F3F5);
  static const Color surfaceDim = Color(0xFF101114);
  static const Color surfaceBright = Color(0xFF33353C);
  static const Color surfaceContainerLowest = Color(0xFF0F1013);
  static const Color surfaceContainerLow = Color(0xFF111215);
  static const Color surfaceContainer = Color(0xFF15151A);
  static const Color surfaceContainerHigh = Color(0xFF282A31);
  static const Color surfaceContainerHighest = Color(0xFF31333B);
  static const Color onSurfaceVariant = Color(0xFFC5C9D3);
  static const Color outline = Color(0xFF3B404A);
  static const Color outlineVariant = Color(0xFF2B2E35);
  static const Color foundation = Color(0xFF0D0E11);
  static const Color link = Color(0xFF45BDF7);
  static const Color code = Color(0xFF58D4FF);
}

class ThemeDarkMatter {
  static ThemeData get theme => ThemeBase.theme(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: ThemeDarkMatterColors.primary,
          onPrimary: ThemeDarkMatterColors.onPrimary,
          primaryContainer: ThemeDarkMatterColors.primaryContainer,
          onPrimaryContainer: ThemeDarkMatterColors.onPrimaryContainer,
          secondary: ThemeDarkMatterColors.secondary,
          onSecondary: ThemeDarkMatterColors.onSecondary,
          secondaryContainer: ThemeDarkMatterColors.secondaryContainer,
          onSecondaryContainer: ThemeDarkMatterColors.onSecondaryContainer,
          tertiary: ThemeDarkMatterColors.tertiary,
          onTertiary: ThemeDarkMatterColors.onTertiary,
          tertiaryContainer: ThemeDarkMatterColors.tertiaryContainer,
          onTertiaryContainer: ThemeDarkMatterColors.onTertiaryContainer,
          error: Color(0xFFFF7F7F),
          onError: Color(0xFF2A0000),
          surface: ThemeDarkMatterColors.surface,
          onSurface: ThemeDarkMatterColors.onSurface,
          surfaceDim: ThemeDarkMatterColors.surfaceDim,
          surfaceBright: ThemeDarkMatterColors.surfaceBright,
          surfaceContainerLowest: ThemeDarkMatterColors.surfaceContainerLowest,
          surfaceContainerLow: ThemeDarkMatterColors.surfaceContainerLow,
          surfaceContainer: ThemeDarkMatterColors.surfaceContainer,
          surfaceContainerHigh: ThemeDarkMatterColors.surfaceContainerHigh,
          surfaceContainerHighest:
              ThemeDarkMatterColors.surfaceContainerHighest,
          onSurfaceVariant: ThemeDarkMatterColors.onSurfaceVariant,
          outline: ThemeDarkMatterColors.outline,
          outlineVariant: ThemeDarkMatterColors.outlineVariant,
        ),
      ).copyWith(
        extensions: const [
          ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
          FoundationSettings(color: ThemeDarkMatterColors.foundation),
          ExtraColors(
            codeHighlight: ThemeDarkMatterColors.code,
            linkColor: ThemeDarkMatterColors.link,
          ),
        ],
      );
}
