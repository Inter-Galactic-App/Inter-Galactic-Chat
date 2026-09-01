import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tiamat/config/config.dart';
import 'package:path/path.dart' as path;

class ThemeJsonConverter {
  static Future<ThemeData?> fromJson(
      Map<String, dynamic> json, File? file) async {
    var base = _normalizeBaseThemeId(json.tryGet<String>("base"));

    var defaultTheme = switch (base) {
      "dark_matter" => ThemeDarkMatter.theme,
      "dark" => ThemeDark.theme,
      "light" => ThemeLight.theme,
      "amoled" => ThemeAmoled.theme,
      "aurora" => ThemeAurora.theme,
      "cosmic_stardust" => ThemeCosmicStardust.theme,
      "grand_master" => ThemeGrandMaster.theme,
      "dark_lord" => ThemeDarkLord.theme,
      "you_light" => await ThemeYou.theme(Brightness.light),
      "you_dark" => await ThemeYou.theme(Brightness.dark),
      _ => ThemeDarkMatter.theme,
    };

    final baseThemeSettings =
        defaultTheme.extension<ThemeSettings>() ?? const ThemeSettings();

    var settings = json.tryGet<Map<String, dynamic>>("settings");

    GlassSettings? glass = defaultTheme.extension<GlassSettings>();

    if (json.containsKey("glass")) {
      var data = json.tryGet<Map<String, dynamic>>("glass");
      if (data != null) {
        glass = (glass ?? const GlassSettings()).copyWith(
          surfaceSigma: data.tryGetDouble("surfaceSigma"),
          surfaceOpacity: data.tryGetDouble("surfaceOpacity"),
          surfaceDimSigma: data.tryGetDouble("surfaceDimSigma"),
          surfaceDimOpacity: data.tryGetDouble("surfaceDimOpacity"),
          surfaceContainerLowestSigma:
              data.tryGetDouble("surfaceContainerLowestSigma"),
          surfaceContainerLowestOpacity:
              data.tryGetDouble("surfaceContainerLowestOpacity"),
          surfaceContainerLowSigma:
              data.tryGetDouble("surfaceContainerLowSigma"),
          surfaceContainerLowOpacity:
              data.tryGetDouble("surfaceContainerLowOpacity"),
          surfaceContainerSigma: data.tryGetDouble("surfaceContainerSigma"),
          surfaceContainerOpacity: data.tryGetDouble("surfaceContainerOpacity"),
          surfaceContainerHighSigma:
              data.tryGetDouble("surfaceContainerHighSigma"),
          surfaceContainerHighOpacity:
              data.tryGetDouble("surfaceContainerHighOpacity"),
          surfaceContainerHighestSigma:
              data.tryGetDouble("surfaceContainerHighestSigma"),
          surfaceContainerHighestOpacity:
              data.tryGetDouble("surfaceContainerHighestOpacity"),
        ) as GlassSettings;
      }
    }

    final themeSettings = ThemeSettings(
      caulkBorders: settings?.tryGet<bool>("caulkBorders") ??
          baseThemeSettings.caulkBorders,
      caulkStrokeThickness: settings?.tryGetDouble("caulkStrokeThickness") ??
          baseThemeSettings.caulkStrokeThickness,
      caulkBorderRadius: settings?.tryGetDouble("caulkBorderRadius") ??
          baseThemeSettings.caulkBorderRadius,
      caulkPadding: settings?.tryGetDouble("caulkPadding") ??
          baseThemeSettings.caulkPadding,
      shadowBlurRadius: settings?.tryGetDouble("shadowBlurRadius") ??
          baseThemeSettings.shadowBlurRadius,
    );

    var schemeData = json.tryGet<Map<String, dynamic>>("colorScheme");

    var colorScheme = defaultTheme.colorScheme;
    var seedColor = schemeData?.tryGetColor("seed");

    if (seedColor != null) {
      DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot;

      var variantJson = schemeData?.tryGet<String>("dynamicSchemeVariant");
      if (variantJson != null) {
        try {
          variant = DynamicSchemeVariant.values.byName(variantJson);
        } catch (_) {}
      }

      colorScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: defaultTheme.brightness,
          dynamicSchemeVariant: variant);
    }

    colorScheme = colorScheme.copyWith(
      primary: schemeData?.tryGetColor("primary"),
      onPrimary: schemeData?.tryGetColor("onPrimary"),
      primaryContainer: schemeData?.tryGetColor("primaryContainer"),
      onPrimaryContainer: schemeData?.tryGetColor("onPrimaryContainer"),
      primaryFixed: schemeData?.tryGetColor("primaryFixed"),
      primaryFixedDim: schemeData?.tryGetColor("primaryFixedDim"),
      onPrimaryFixed: schemeData?.tryGetColor("onPrimaryFixed"),
      onPrimaryFixedVariant: schemeData?.tryGetColor("onPrimaryFixedVariant"),
      secondary: schemeData?.tryGetColor("secondary"),
      onSecondary: schemeData?.tryGetColor("onSecondary"),
      secondaryContainer: schemeData?.tryGetColor("secondaryContainer"),
      onSecondaryContainer: schemeData?.tryGetColor("onSecondaryContainer"),
      secondaryFixed: schemeData?.tryGetColor("secondaryFixed"),
      secondaryFixedDim: schemeData?.tryGetColor("secondaryFixedDim"),
      onSecondaryFixed: schemeData?.tryGetColor("onSecondaryFixed"),
      onSecondaryFixedVariant:
          schemeData?.tryGetColor("onSecondaryFixedVariant"),
      tertiary: schemeData?.tryGetColor("tertiary"),
      onTertiary: schemeData?.tryGetColor("onTertiary"),
      tertiaryContainer: schemeData?.tryGetColor("tertiaryContainer"),
      onTertiaryContainer: schemeData?.tryGetColor("onTertiaryContainer"),
      tertiaryFixed: schemeData?.tryGetColor("tertiaryFixed"),
      tertiaryFixedDim: schemeData?.tryGetColor("tertiaryFixedDim"),
      onTertiaryFixed: schemeData?.tryGetColor("onTertiaryFixed"),
      onTertiaryFixedVariant: schemeData?.tryGetColor("onTertiaryFixedVariant"),
      error: schemeData?.tryGetColor("error"),
      onError: schemeData?.tryGetColor("onError"),
      errorContainer: schemeData?.tryGetColor("errorContainer"),
      onErrorContainer: schemeData?.tryGetColor("onErrorContainer"),
      outline: schemeData?.tryGetColor("outline"),
      outlineVariant: schemeData?.tryGetColor("outlineVariant"),
      surface: schemeData?.tryGetColor("surface"),
      onSurface: schemeData?.tryGetColor("onSurface"),
      surfaceDim: schemeData?.tryGetColor("surfaceDim"),
      surfaceBright: schemeData?.tryGetColor("surfaceBright"),
      surfaceContainerLowest: schemeData?.tryGetColor("surfaceContainerLowest"),
      surfaceContainerLow: schemeData?.tryGetColor("surfaceContainerLow"),
      surfaceContainer: schemeData?.tryGetColor("surfaceContainer"),
      surfaceContainerHigh: schemeData?.tryGetColor("surfaceContainerHigh"),
      surfaceContainerHighest:
          schemeData?.tryGetColor("surfaceContainerHighest"),
      onSurfaceVariant: schemeData?.tryGetColor("onSurfaceVariant"),
      inverseSurface: schemeData?.tryGetColor("inverseSurface"),
      onInverseSurface: schemeData?.tryGetColor("onInverseSurface"),
      inversePrimary: schemeData?.tryGetColor("inversePrimary"),
      shadow: schemeData?.tryGetColor("shadow"),
      scrim: schemeData?.tryGetColor("scrim"),
      surfaceTint: schemeData?.tryGetColor("surfaceTint"),
    );

    var extraColors = defaultTheme.extension<ExtraColors>() ??
        ExtraColors.fromScheme(defaultTheme.colorScheme);

    var codeHighlight = schemeData?.tryGetColor("codeHighlight");
    var linkColor = schemeData?.tryGetColor("links");

    extraColors = extraColors.copyWith(
        codeHighlight: codeHighlight, linkColor: linkColor) as ExtraColors;

    FoundationSettings foundation =
        loadFoundation(defaultTheme, colorScheme, json, file);

    ShadowSettings? shadows =
        loadShadows(json) ?? defaultTheme.extension<ShadowSettings>();

    final extensions = List<ThemeExtension<dynamic>>.of(
      defaultTheme.extensions.values.where(
        (extension) =>
            extension is! ThemeSettings &&
            extension is! GlassSettings &&
            extension is! FoundationSettings &&
            extension is! ShadowSettings &&
            extension is! ExtraColors,
      ),
    )
      ..add(themeSettings)
      ..add(foundation)
      ..add(extraColors);

    if (glass != null) {
      extensions.add(glass);
    }

    if (shadows != null) {
      extensions.add(shadows);
    }

    var data = defaultTheme.copyWith(
      colorScheme: colorScheme,
      extensions: extensions,
    );

    return data;
  }

  static String? _normalizeBaseThemeId(String? base) {
    final normalized = base?.trim().toLowerCase().replaceAll(
          RegExp(r'[\s-]+'),
          '_',
        );

    return switch (normalized) {
      'classic_light' || 'sol' || 'light' => 'light',
      'dark_matter' => 'dark_matter',
      'classic_dark' || 'nebula' || 'dark' => 'dark',
      'arnoled' || 'amoled' || 'eclipse' => 'amoled',
      'aurora' => 'aurora',
      'cosmic_stardust' => 'cosmic_stardust',
      'bundled:jedi' ||
      'jedi' ||
      'light_side' ||
      'grand_master' =>
        'grand_master',
      'bundled:sith' || 'sith' || 'dark_side' || 'dark_lord' => 'dark_lord',
      _ => base,
    };
  }

  static ShadowSettings? loadShadows(Map<String, dynamic> json) {
    var data = json.tryGet<List<dynamic>>("shadows");
    if (data == null) {
      return null;
    }

    List<BoxShadow> shadows = List.empty(growable: true);

    for (var entry in data) {
      if (entry is! Map<String, dynamic>) {
        print("Entry was not a map, continuing");
        continue;
      }

      var color = entry.tryGetColor("color");
      var blurRadius = entry.tryGetDouble("blurRadius");
      var spreadRadius = entry.tryGetDouble("spreadRadius");

      var offsetValues = entry.tryGet<List<dynamic>>("offset");
      Offset? offset;
      if (offsetValues != null) {
        var values = List<num>.from(offsetValues);
        if (values.length >= 2) {
          offset = Offset(values[0].toDouble(), values[1].toDouble());
        }
      }

      shadows.add(BoxShadow(
          color: color ?? Colors.black,
          offset: offset ?? Offset.zero,
          spreadRadius: spreadRadius ?? 0,
          blurRadius: blurRadius ?? 0));
    }
    if (shadows.isNotEmpty) {
      return ShadowSettings(shadows);
    } else {
      return null;
    }
  }

  static FoundationSettings loadFoundation(ThemeData defaultTheme,
      ColorScheme colorScheme, Map<String, dynamic> json, File? file) {
    FoundationSettings foundation =
        defaultTheme.extension<FoundationSettings>() ??
            FoundationSettings(color: colorScheme.surfaceContainerLowest);

    if (json.containsKey("foundation")) {
      var data = json.tryGet<Map<String, dynamic>>("foundation");
      if (data != null) {
        var image = data.tryGet<Map<String, dynamic>>("image");
        if (image != null && file != null) {
          var imageFile = image.tryGet<String>("file");
          if (imageFile != null) {
            var imagePath = path.join(file.parent.path, imageFile);
            foundation = foundation.copyWith(image: FileImage(File(imagePath)))
                as FoundationSettings;
          }
        }

        try {
          foundation = foundation.copyWith(
            imageFit: image != null
                ? BoxFit.values.byName(image.tryGet<String>("fit")!)
                : null,
          ) as FoundationSettings;
        } catch (_) {}

        try {
          foundation = foundation.copyWith(
            stackFit: image != null
                ? StackFit.values.byName(image.tryGet<String>("stackFit")!)
                : null,
          ) as FoundationSettings;
        } catch (_) {}

        foundation = foundation.copyWith(
            imageAlignment: switch (image?.tryGet<String>("alignment")) {
          "topLeft" => Alignment.topLeft,
          "topCenter" => Alignment.topCenter,
          "topRight" => Alignment.topRight,
          "centerLeft" => Alignment.centerLeft,
          "center" => Alignment.center,
          "centerRight" => Alignment.centerRight,
          "bottomLeft" => Alignment.bottomLeft,
          "bottomCenter" => Alignment.bottomCenter,
          "bottomRight" => Alignment.bottomRight,
          _ => Alignment.center,
        }) as FoundationSettings;

        foundation = foundation.copyWith(color: data.tryGetColor("color"))
            as FoundationSettings;
      }
    }
    return foundation;
  }
}

extension ThemeUtils on Map {
  T? tryGet<T>(String key) {
    if (containsKey(key) == false) {
      return null;
    }

    var value = this[key];
    if (value is T) {
      return value;
    } else {
      return null;
    }
  }

  double? tryGetDouble(String key) {
    var d = tryGet<num>(key);
    return d?.toDouble();
  }

  Color? tryGetColor(String key) {
    var hexString = tryGet<String>(key);
    if (hexString == null) return null;

    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
