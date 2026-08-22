import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeCosmicStardustColors {
  static const Color primary = Color(0xFF83D8FF);
  static const Color onPrimary = Color(0xFF001B2A);
  static const Color primaryContainer = Color(0xFF255A87);
  static const Color onPrimaryContainer = Color(0xFFE4F6FF);
  static const Color secondary = Color(0xFFB59BFF);
  static const Color onSecondary = Color(0xFF1C1032);
  static const Color secondaryContainer = Color(0xFF40306D);
  static const Color onSecondaryContainer = Color(0xFFF0E9FF);
  static const Color tertiary = Color(0xFFF27AE6);
  static const Color onTertiary = Color(0xFF2D0030);
  static const Color tertiaryContainer = Color(0xFF6D2D74);
  static const Color onTertiaryContainer = Color(0xFFFFE5FA);
  static const Color surface = Color(0xFF121523);
  static const Color onSurface = Color(0xFFF3EAFF);
  static const Color surfaceDim = Color(0xFF050610);
  static const Color surfaceBright = Color(0xFF2E294D);
  static const Color surfaceContainerLowest = Color(0xFF060711);
  static const Color surfaceContainerLow = Color(0xFF0A0D19);
  static const Color surfaceContainer = Color(0xFF0F121E);
  static const Color surfaceContainerHigh = Color(0xFF1A1D32);
  static const Color surfaceContainerHighest = Color(0xFF272440);
  static const Color onSurfaceVariant = Color(0xFFD7CDEF);
  static const Color outline = Color(0xFF504978);
  static const Color outlineVariant = Color(0xFF2C2F4B);
  static const Color foundation = Color(0xFF03040C);
  static const Color link = Color(0xFF84D6FF);
  static const Color code = Color(0xFFD490FF);
}

class ThemeCosmicStardust {
  static ThemeData get theme => ThemeBase.theme(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: ThemeCosmicStardustColors.primary,
          onPrimary: ThemeCosmicStardustColors.onPrimary,
          primaryContainer: ThemeCosmicStardustColors.primaryContainer,
          onPrimaryContainer: ThemeCosmicStardustColors.onPrimaryContainer,
          secondary: ThemeCosmicStardustColors.secondary,
          onSecondary: ThemeCosmicStardustColors.onSecondary,
          secondaryContainer: ThemeCosmicStardustColors.secondaryContainer,
          onSecondaryContainer: ThemeCosmicStardustColors.onSecondaryContainer,
          tertiary: ThemeCosmicStardustColors.tertiary,
          onTertiary: ThemeCosmicStardustColors.onTertiary,
          tertiaryContainer: ThemeCosmicStardustColors.tertiaryContainer,
          onTertiaryContainer: ThemeCosmicStardustColors.onTertiaryContainer,
          error: Color(0xFFFF8A9A),
          onError: Color(0xFF2A0008),
          surface: ThemeCosmicStardustColors.surface,
          onSurface: ThemeCosmicStardustColors.onSurface,
          surfaceDim: ThemeCosmicStardustColors.surfaceDim,
          surfaceBright: ThemeCosmicStardustColors.surfaceBright,
          surfaceContainerLowest:
              ThemeCosmicStardustColors.surfaceContainerLowest,
          surfaceContainerLow: ThemeCosmicStardustColors.surfaceContainerLow,
          surfaceContainer: ThemeCosmicStardustColors.surfaceContainer,
          surfaceContainerHigh: ThemeCosmicStardustColors.surfaceContainerHigh,
          surfaceContainerHighest:
              ThemeCosmicStardustColors.surfaceContainerHighest,
          onSurfaceVariant: ThemeCosmicStardustColors.onSurfaceVariant,
          outline: ThemeCosmicStardustColors.outline,
          outlineVariant: ThemeCosmicStardustColors.outlineVariant,
        ),
      ).copyWith(
        extensions: const [
          ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
          FoundationSettings(color: ThemeCosmicStardustColors.foundation),
          ExtraColors(
            codeHighlight: ThemeCosmicStardustColors.code,
            linkColor: ThemeCosmicStardustColors.link,
          ),
        ],
      );
}
