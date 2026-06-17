import 'package:flutter/material.dart';

const String settingsFontFamily = 'RobotoCustom';

class SettingsTypography extends StatelessWidget {
  const SettingsTypography({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsTheme = theme.copyWith(
      textTheme: _regularTextTheme(theme.textTheme),
      primaryTextTheme: _regularTextTheme(theme.primaryTextTheme),
    );

    return Theme(
      data: settingsTheme,
      child: Builder(
        builder: (context) {
          final bodyStyle = Theme.of(context).textTheme.bodyMedium;

          return DefaultTextStyle.merge(
            style: _regularStyle(bodyStyle) ??
                const TextStyle(
                  fontFamily: settingsFontFamily,
                  fontWeight: FontWeight.w400,
                ),
            child: child,
          );
        },
      ),
    );
  }
}

TextTheme _regularTextTheme(TextTheme textTheme) {
  return textTheme.copyWith(
    displayLarge: _regularStyle(textTheme.displayLarge),
    displayMedium: _regularStyle(textTheme.displayMedium),
    displaySmall: _regularStyle(textTheme.displaySmall),
    headlineLarge: _regularStyle(textTheme.headlineLarge),
    headlineMedium: _regularStyle(textTheme.headlineMedium),
    headlineSmall: _regularStyle(textTheme.headlineSmall),
    titleLarge: _regularStyle(textTheme.titleLarge),
    titleMedium: _regularStyle(textTheme.titleMedium),
    titleSmall: _regularStyle(textTheme.titleSmall),
    bodyLarge: _regularStyle(textTheme.bodyLarge),
    bodyMedium: _regularStyle(textTheme.bodyMedium),
    bodySmall: _regularStyle(textTheme.bodySmall),
    labelLarge: _regularStyle(textTheme.labelLarge),
    labelMedium: _regularStyle(textTheme.labelMedium),
    labelSmall: _regularStyle(textTheme.labelSmall),
  );
}

TextStyle? _regularStyle(TextStyle? style) {
  return style?.copyWith(
    fontFamily: settingsFontFamily,
    fontVariations: const [FontVariation.weight(400)],
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );
}
