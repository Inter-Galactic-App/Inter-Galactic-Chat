import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_base.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_dark.dart';

/// `TooltipThemeData` had never been set anywhere in the app, so all 266
/// Material tooltip sites rendered Flutter's stock defaults by omission. Most of
/// them are `tooltip:` parameters that never chose Material in the first place.
///
/// The floor lives in `ThemeBase.theme`, the single constructor every theme goes
/// through, so it reaches built-in and custom themes alike and follows the
/// colour scheme rather than hard-coding light and dark variants.
///
/// See DECISIONS.md 2026-08-18, D1.
void main() {
  testWidgets('a stock Material tooltip picks up app surface colours', (
    tester,
  ) async {
    final theme = ThemeLight.theme;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: Tooltip(
              message: 'Mute',
              child: SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    // The widget itself sets nothing - it inherits, which is the whole point.
    expect(tooltip.decoration, isNull);

    final resolved = TooltipTheme.of(tester.element(find.byType(Tooltip)));
    final decoration = resolved.decoration as BoxDecoration?;

    expect(
      decoration?.color,
      theme.colorScheme.surfaceContainerLowest,
      reason: 'Material tooltips must use the app surface, not the stock white',
    );
    expect(resolved.textStyle?.color, theme.colorScheme.onSurface);

    // Colour is not the whole floor. The shape and the text size are what make
    // a Material tooltip read as the same object as `tiamat.Tooltip` sitting
    // next to it, and they are the parts that can be dropped from
    // `ThemeBase.theme` without any colour assertion noticing.
    expect(
      decoration?.borderRadius,
      BorderRadius.circular(4),
      reason: 'the floor mirrors the house tooltip corner radius',
    );
    expect(
      resolved.padding,
      const EdgeInsets.all(8),
      reason: 'the floor mirrors the house tooltip padding',
    );
    expect(
      resolved.textStyle?.fontSize,
      14,
      reason: 'the floor mirrors the house tooltip body text size',
    );
  });

  test('every theme carries the tooltip floor, light and dark alike', () {
    for (final entry in <String, ThemeData>{
      'light': ThemeLight.theme,
      'dark': ThemeDark.theme,
    }.entries) {
      final decoration = entry.value.tooltipTheme.decoration as BoxDecoration?;
      expect(
        decoration?.color,
        entry.value.colorScheme.surfaceContainerLowest,
        reason:
            '${entry.key} theme lost the tooltip floor - it is set in '
            'ThemeBase.theme so every theme should inherit it',
      );
    }
  });

  test('the floor sets colour only and leaves placement alone', () {
    // An earlier revision set preferBelow:false here, reasoning that D3 makes
    // `up` the default direction. D3 is about the house component; applying it
    // to the Material floor flipped every tooltip in the app from below to
    // above, and the owner caught it on the home status strip where the tooltip
    // then overlapped the section header instead of sitting in the blank space
    // under the avatars.
    //
    // These sites were laid out against Flutter's default. The floor must not
    // second-guess it - when a surface genuinely needs a different direction,
    // that belongs at the call site on the house component, not app-wide here.
    expect(
      ThemeLight.theme.tooltipTheme.preferBelow,
      isNull,
      reason: 'the compatibility floor must not override Material placement',
    );
    expect(ThemeDark.theme.tooltipTheme.preferBelow, isNull);
  });

  test('the floor is derived from the scheme, not hard-coded', () {
    // Two schemes in, two different tooltip colours out. A hard-coded colour
    // would make this fail, and would silently break custom themes.
    final a = ThemeBase.theme(
      ColorScheme.fromSeed(seedColor: const Color(0xFF112233)),
    );
    final b = ThemeBase.theme(
      ColorScheme.fromSeed(
        seedColor: const Color(0xFFAA5500),
        brightness: Brightness.dark,
      ),
    );

    final colorA = (a.tooltipTheme.decoration as BoxDecoration?)?.color;
    final colorB = (b.tooltipTheme.decoration as BoxDecoration?)?.color;

    expect(colorA, a.colorScheme.surfaceContainerLowest);
    expect(colorB, b.colorScheme.surfaceContainerLowest);
    expect(colorA, isNot(colorB));
  });
}
