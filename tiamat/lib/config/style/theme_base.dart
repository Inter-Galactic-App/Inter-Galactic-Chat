import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_common.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class ThemeBase {
  static ThemeData theme(ColorScheme scheme) => ThemeData(
        brightness: scheme.brightness,
        fontFamily: "RobotoCustom",
        fontFamilyFallback: ThemeCommon.fontFamilyFallback(),
        useMaterial3: true,
        textTheme: TextTheme(
            headlineLarge: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: "NunitoSans",
              fontSize: 48,
              fontVariations: [
                FontVariation.weight(900),
              ],
            ),
            headlineMedium: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: "NunitoSans",
              fontSize: 38,
              fontVariations: [
                FontVariation.weight(900),
              ],
            ),
            headlineSmall: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: "NunitoSans",
              fontSize: 28,
              fontVariations: [
                FontVariation.weight(900),
              ],
            ),
            titleMedium: TextStyle(
              fontFamily: "NunitoSans",
              fontSize: 20,
              fontVariations: [
                FontVariation.weight(700),
              ],
            ),
            titleSmall: TextStyle(
              fontFamily: "NunitoSans",
              fontSize: 16,
              fontVariations: [
                FontVariation.weight(700),
              ],
            ),
            titleLarge: TextStyle(fontWeight: FontWeight.w800)),
        extensions: const [
          ThemeSettings(caulkBorders: true, caulkBorderRadius: 1),
          ExtraColors(
            codeHighlight: Color(0xffc678dd),
            linkColor: Color.fromARGB(255, 120, 120, 255),
          ),
        ],
        colorScheme: scheme,
        expansionTileTheme: ExpansionTileThemeData(
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        listTileTheme: ListTileThemeData(
          dense: true,
          contentPadding: EdgeInsets.fromLTRB(8, 2, 8, 0),
        ),
        canvasColor: scheme.surface,
        iconTheme: IconThemeData(color: scheme.secondary),
        shadowColor: Colors.black.withAlpha(100),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide.none,
              ),
            ),
          ),
        ),
        dividerTheme: DividerThemeData(color: scheme.surfaceContainerHigh),
        sliderTheme: SliderThemeData(
          inactiveTrackColor: scheme.primary.withAlpha(100),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thickness: const WidgetStatePropertyAll(3.0),
          radius: const Radius.circular(999),
          thumbColor: WidgetStatePropertyAll(
            scheme.onSurfaceVariant.withValues(alpha: 0.42),
          ),
          trackVisibility: const WidgetStatePropertyAll(false),
          crossAxisMargin: 2,
          mainAxisMargin: 4,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: scheme.surface,
          shadowColor: Colors.black,
        ),
        // Until every site is on the house component, most tooltips in the app
        // are still Material ones - 266 of them against 28 themed, and 201 of
        // those are `tooltip:` parameters that never chose Material at all.
        // Nothing had ever set `tooltipTheme`, so they all rendered Flutter's
        // stock white box by omission rather than by decision.
        //
        // These values mirror `tiamat.Tooltip` so the two systems look alike
        // while the migration proceeds. Because they are read from `scheme`,
        // they follow every theme - built-in and custom - and light/dark adapt
        // with no separate variant.
        //
        // This is a floor, not the fix. Material has no side placement at all -
        // `preferBelow` chooses above or below and nothing else - so a tooltip
        // that must sit beside its target still needs the house component. See
        // DECISIONS.md 2026-08-18, D1.
        //
        // Deliberately sets colour only and leaves placement alone. An earlier
        // revision also set `preferBelow: false`, reasoning that D3 makes `up`
        // the default direction - but D3 is about the house component, and
        // applying it here flipped every Material tooltip in the app from below
        // to above. The owner caught it on the home status strip, where the
        // tooltip had been sitting cleanly in the blank space under the avatars
        // and started overlapping the header instead. Flutter's default of below
        // is what these sites were laid out against; the floor should not
        // second-guess it.
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
          padding: const EdgeInsets.all(8),
        ),
        dividerColor: scheme.outline,
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll<OutlinedBorder>(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      );
}
