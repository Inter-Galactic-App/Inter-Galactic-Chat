import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeTokenDebugColors {
  static const Color primary = Color(0xFFFF2BD6);
  static const Color onPrimary = Color(0xFF210014);
  static const Color primaryContainer = Color(0xFF651FFF);
  static const Color onPrimaryContainer = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFF00F5FF);
  static const Color onSecondary = Color(0xFF001B1D);
  static const Color secondaryContainer = Color(0xFF00E676);
  static const Color onSecondaryContainer = Color(0xFF001B08);
  static const Color tertiary = Color(0xFFFFD600);
  static const Color onTertiary = Color(0xFF2C2100);
  static const Color tertiaryContainer = Color(0xFFFF6D00);
  static const Color onTertiaryContainer = Color(0xFF2B0E00);
  static const Color surface = Color(0xFF22113A);
  static const Color onSurface = Color(0xFFFFFFFF);
  static const Color surfaceDim = Color(0xFF0D1D36);
  static const Color surfaceBright = Color(0xFF4A3A00);
  static const Color surfaceContainerLowest = Color(0xFF050505);
  static const Color surfaceContainerLow = Color(0xFF102B12);
  static const Color surfaceContainer = Color(0xFF2D1A07);
  static const Color surfaceContainerHigh = Color(0xFF003044);
  static const Color surfaceContainerHighest = Color(0xFF3A0027);
  static const Color onSurfaceVariant = Color(0xFFE7D8FF);
  static const Color outline = Color(0xFFFFFFFF);
  static const Color outlineVariant = Color(0xFF8DFF00);
  static const Color foundation = Color(0xFF10001E);
  static const Color link = Color(0xFF40C4FF);
  static const Color code = Color(0xFFFF4081);
}

class ThemeTokenDebug {
  static ThemeData get theme => ThemeBase.theme(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: ThemeTokenDebugColors.primary,
          onPrimary: ThemeTokenDebugColors.onPrimary,
          primaryContainer: ThemeTokenDebugColors.primaryContainer,
          onPrimaryContainer: ThemeTokenDebugColors.onPrimaryContainer,
          secondary: ThemeTokenDebugColors.secondary,
          onSecondary: ThemeTokenDebugColors.onSecondary,
          secondaryContainer: ThemeTokenDebugColors.secondaryContainer,
          onSecondaryContainer: ThemeTokenDebugColors.onSecondaryContainer,
          tertiary: ThemeTokenDebugColors.tertiary,
          onTertiary: ThemeTokenDebugColors.onTertiary,
          tertiaryContainer: ThemeTokenDebugColors.tertiaryContainer,
          onTertiaryContainer: ThemeTokenDebugColors.onTertiaryContainer,
          error: Color(0xFFFF1744),
          onError: Color(0xFFFFFFFF),
          surface: ThemeTokenDebugColors.surface,
          onSurface: ThemeTokenDebugColors.onSurface,
          surfaceDim: ThemeTokenDebugColors.surfaceDim,
          surfaceBright: ThemeTokenDebugColors.surfaceBright,
          surfaceContainerLowest: ThemeTokenDebugColors.surfaceContainerLowest,
          surfaceContainerLow: ThemeTokenDebugColors.surfaceContainerLow,
          surfaceContainer: ThemeTokenDebugColors.surfaceContainer,
          surfaceContainerHigh: ThemeTokenDebugColors.surfaceContainerHigh,
          surfaceContainerHighest:
              ThemeTokenDebugColors.surfaceContainerHighest,
          onSurfaceVariant: ThemeTokenDebugColors.onSurfaceVariant,
          outline: ThemeTokenDebugColors.outline,
          outlineVariant: ThemeTokenDebugColors.outlineVariant,
        ),
      ).copyWith(
        extensions: const [
          ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
          FoundationSettings(color: ThemeTokenDebugColors.foundation),
          ExtraColors(
            codeHighlight: ThemeTokenDebugColors.code,
            linkColor: ThemeTokenDebugColors.link,
          ),
        ],
      );
}
