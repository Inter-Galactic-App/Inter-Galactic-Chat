import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeAuroraColors {
  static const Color primary = Color(0xFF1FD5D0);
  static const Color onPrimary = Color(0xFF001E22);
  static const Color primaryContainer = Color(0xFF0E777B);
  static const Color onPrimaryContainer = Color(0xFFD7FFFB);
  static const Color secondary = Color(0xFF21B7A3);
  static const Color onSecondary = Color(0xFF001F1C);
  static const Color secondaryContainer = Color(0xFF0C3F45);
  static const Color onSecondaryContainer = Color(0xFFBAFFF2);
  static const Color tertiary = Color(0xFF5CF28A);
  static const Color onTertiary = Color(0xFF062111);
  static const Color tertiaryContainer = Color(0xFF16482C);
  static const Color onTertiaryContainer = Color(0xFFC9FFD9);
  static const Color surface = Color(0xFF071016);
  static const Color onSurface = Color(0xFFE4F8FB);
  static const Color surfaceContainerLowest = Color(0xFF02060A);
  static const Color surfaceContainerLow = Color(0xFF07111B);
  static const Color surfaceContainer = Color(0xFF0B1B28);
  static const Color surfaceContainerHigh = Color(0xFF102C3A);
  static const Color surfaceContainerHighest = Color(0xFF163A46);
  static const Color outline = Color(0xFF1A4551);
  static const Color foundation = Color(0xFF020509);
  static const Color link = Color(0xFF28CFE7);
  static const Color code = Color(0xFF45E0B8);
}

class ThemeAurora {
  static ThemeData get theme => ThemeBase.theme(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: ThemeAuroraColors.primary,
          onPrimary: ThemeAuroraColors.onPrimary,
          primaryContainer: ThemeAuroraColors.primaryContainer,
          onPrimaryContainer: ThemeAuroraColors.onPrimaryContainer,
          secondary: ThemeAuroraColors.secondary,
          onSecondary: ThemeAuroraColors.onSecondary,
          secondaryContainer: ThemeAuroraColors.secondaryContainer,
          onSecondaryContainer: ThemeAuroraColors.onSecondaryContainer,
          tertiary: ThemeAuroraColors.tertiary,
          onTertiary: ThemeAuroraColors.onTertiary,
          tertiaryContainer: ThemeAuroraColors.tertiaryContainer,
          onTertiaryContainer: ThemeAuroraColors.onTertiaryContainer,
          error: Color(0xFFFF8A8A),
          onError: Colors.black,
          surface: ThemeAuroraColors.surface,
          onSurface: ThemeAuroraColors.onSurface,
          surfaceContainerLowest: ThemeAuroraColors.surfaceContainerLowest,
          surfaceContainerLow: ThemeAuroraColors.surfaceContainerLow,
          surfaceContainer: ThemeAuroraColors.surfaceContainer,
          surfaceContainerHigh: ThemeAuroraColors.surfaceContainerHigh,
          surfaceContainerHighest: ThemeAuroraColors.surfaceContainerHighest,
          outline: ThemeAuroraColors.outline,
        ),
      ).copyWith(
        extensions: const [
          ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
          FoundationSettings(color: ThemeAuroraColors.foundation),
          ExtraColors(
            codeHighlight: ThemeAuroraColors.code,
            linkColor: ThemeAuroraColors.link,
          ),
        ],
      );
}
