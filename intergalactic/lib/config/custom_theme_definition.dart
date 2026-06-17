import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_aurora.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_dark_lord.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_grand_master.dart';
import 'package:tiamat/config/style/theme_light.dart';

class CustomThemeColorField {
  const CustomThemeColorField({
    required this.id,
    required this.group,
    required this.label,
    required this.section,
    required this.jsonKey,
    required this.themeColor,
  });

  final String id;
  final String group;
  final String label;
  final String section;
  final String jsonKey;
  final Color Function(ThemeData theme) themeColor;

  Color? readFromJson(Map<String, dynamic> json) {
    final sectionData = json[section];
    if (sectionData is! Map) {
      return null;
    }

    final value = sectionData[jsonKey];
    if (value is! String) {
      return null;
    }

    return parseHexColor(value);
  }

  void writeToJson(Map<String, dynamic> json, Color color) {
    final sectionData = Map<String, dynamic>.from(
      json[section] as Map? ?? const <String, dynamic>{},
    );

    sectionData[jsonKey] = colorToHex(color);
    json[section] = sectionData;
  }
}

final List<CustomThemeColorField> editableThemeColorFields = [
  CustomThemeColorField(
    id: 'primary',
    group: 'Accent',
    label: 'Primary',
    section: 'colorScheme',
    jsonKey: 'primary',
    themeColor: (theme) => theme.colorScheme.primary,
  ),
  CustomThemeColorField(
    id: 'onPrimary',
    group: 'Accent',
    label: 'Primary Accents',
    section: 'colorScheme',
    jsonKey: 'onPrimary',
    themeColor: (theme) => theme.colorScheme.onPrimary,
  ),
  CustomThemeColorField(
    id: 'primaryContainer',
    group: 'Accent',
    label: 'Primary Container',
    section: 'colorScheme',
    jsonKey: 'primaryContainer',
    themeColor: (theme) => theme.colorScheme.primaryContainer,
  ),
  CustomThemeColorField(
    id: 'onPrimaryContainer',
    group: 'Accent',
    label: 'Primary Container Accents',
    section: 'colorScheme',
    jsonKey: 'onPrimaryContainer',
    themeColor: (theme) => theme.colorScheme.onPrimaryContainer,
  ),
  CustomThemeColorField(
    id: 'secondary',
    group: 'Accent',
    label: 'Secondary',
    section: 'colorScheme',
    jsonKey: 'secondary',
    themeColor: (theme) => theme.colorScheme.secondary,
  ),
  CustomThemeColorField(
    id: 'onSecondary',
    group: 'Accent',
    label: 'Secondary Accents',
    section: 'colorScheme',
    jsonKey: 'onSecondary',
    themeColor: (theme) => theme.colorScheme.onSecondary,
  ),
  CustomThemeColorField(
    id: 'secondaryContainer',
    group: 'Accent',
    label: 'Secondary Container',
    section: 'colorScheme',
    jsonKey: 'secondaryContainer',
    themeColor: (theme) => theme.colorScheme.secondaryContainer,
  ),
  CustomThemeColorField(
    id: 'onSecondaryContainer',
    group: 'Accent',
    label: 'Secondary Container Accents',
    section: 'colorScheme',
    jsonKey: 'onSecondaryContainer',
    themeColor: (theme) => theme.colorScheme.onSecondaryContainer,
  ),
  CustomThemeColorField(
    id: 'tertiary',
    group: 'Accent',
    label: 'Tertiary',
    section: 'colorScheme',
    jsonKey: 'tertiary',
    themeColor: (theme) => theme.colorScheme.tertiary,
  ),
  CustomThemeColorField(
    id: 'links',
    group: 'Extras',
    label: 'Links',
    section: 'colorScheme',
    jsonKey: 'links',
    themeColor: (theme) => theme.extension<ExtraColors>()!.linkColor,
  ),
  CustomThemeColorField(
    id: 'codeHighlight',
    group: 'Extras',
    label: 'Code Highlight',
    section: 'colorScheme',
    jsonKey: 'codeHighlight',
    themeColor: (theme) => theme.extension<ExtraColors>()!.codeHighlight,
  ),
  CustomThemeColorField(
    id: 'surface',
    group: 'Surfaces',
    label: 'Surface',
    section: 'colorScheme',
    jsonKey: 'surface',
    themeColor: (theme) => theme.colorScheme.surface,
  ),
  CustomThemeColorField(
    id: 'onSurface',
    group: 'Surfaces',
    label: 'Surface Text',
    section: 'colorScheme',
    jsonKey: 'onSurface',
    themeColor: (theme) => theme.colorScheme.onSurface,
  ),
  CustomThemeColorField(
    id: 'surfaceContainerLowest',
    group: 'Surfaces',
    label: 'Surface Container Lowest',
    section: 'colorScheme',
    jsonKey: 'surfaceContainerLowest',
    themeColor: (theme) => theme.colorScheme.surfaceContainerLowest,
  ),
  CustomThemeColorField(
    id: 'surfaceContainerLow',
    group: 'Surfaces',
    label: 'Surface Container Low',
    section: 'colorScheme',
    jsonKey: 'surfaceContainerLow',
    themeColor: (theme) => theme.colorScheme.surfaceContainerLow,
  ),
  CustomThemeColorField(
    id: 'surfaceContainer',
    group: 'Surfaces',
    label: 'Surface Container',
    section: 'colorScheme',
    jsonKey: 'surfaceContainer',
    themeColor: (theme) => theme.colorScheme.surfaceContainer,
  ),
  CustomThemeColorField(
    id: 'surfaceContainerHigh',
    group: 'Surfaces',
    label: 'Surface Container High',
    section: 'colorScheme',
    jsonKey: 'surfaceContainerHigh',
    themeColor: (theme) => theme.colorScheme.surfaceContainerHigh,
  ),
  CustomThemeColorField(
    id: 'surfaceContainerHighest',
    group: 'Surfaces',
    label: 'Surface Container Highest',
    section: 'colorScheme',
    jsonKey: 'surfaceContainerHighest',
    themeColor: (theme) => theme.colorScheme.surfaceContainerHighest,
  ),
  CustomThemeColorField(
    id: 'outline',
    group: 'Surfaces',
    label: 'Outline',
    section: 'colorScheme',
    jsonKey: 'outline',
    themeColor: (theme) => theme.colorScheme.outline,
  ),
  CustomThemeColorField(
    id: 'foundationColor',
    group: 'Background',
    label: 'Foundation Background',
    section: 'foundation',
    jsonKey: 'color',
    themeColor: (theme) =>
        theme.extension<FoundationSettings>()?.color ??
        theme.colorScheme.surfaceContainerLowest,
  ),
];

class CustomThemeDefinition {
  const CustomThemeDefinition({
    required this.id,
    required this.displayName,
    required this.base,
    required this.json,
  });

  final String id;
  final String displayName;
  final String base;
  final Map<String, dynamic> json;

  factory CustomThemeDefinition.fromJson(
    String id,
    Map<String, dynamic> json,
  ) {
    final name = (json['name'] as String?)?.trim();
    final base = (json['base'] as String?)?.trim();

    return CustomThemeDefinition(
      id: id,
      displayName: name?.isNotEmpty == true ? name! : id,
      base: base?.isNotEmpty == true ? base! : 'dark',
      json: Map<String, dynamic>.from(json),
    );
  }
}

class CustomThemeDraft {
  CustomThemeDraft({
    this.id,
    required this.name,
    required this.base,
    required this.colors,
    Map<String, dynamic>? sourceJson,
  }) : sourceJson =
            sourceJson != null ? deepCopyJson(sourceJson) : <String, dynamic>{};

  final String? id;
  String name;
  String base;
  final Map<String, Color> colors;
  final Map<String, dynamic> sourceJson;

  factory CustomThemeDraft.fromThemeData({
    String? id,
    required String name,
    required String base,
    required ThemeData theme,
    Map<String, dynamic>? sourceJson,
  }) {
    final colors = <String, Color>{};
    for (final field in editableThemeColorFields) {
      colors[field.id] = field.themeColor(theme);
    }

    return CustomThemeDraft(
      id: id,
      name: name,
      base: normalizeCustomThemeBase(base),
      colors: colors,
      sourceJson: sourceJson,
    );
  }

  factory CustomThemeDraft.fromDefinition(CustomThemeDefinition definition) {
    final baseTheme = defaultThemeForCustomBase(definition.base);
    final colors = <String, Color>{};

    for (final field in editableThemeColorFields) {
      colors[field.id] =
          field.readFromJson(definition.json) ?? field.themeColor(baseTheme);
    }

    return CustomThemeDraft(
      id: definition.id,
      name: definition.displayName,
      base: normalizeCustomThemeBase(definition.base),
      colors: colors,
      sourceJson: definition.json,
    );
  }

  Map<String, dynamic> toJson() {
    final json = deepCopyJson(sourceJson);
    json['name'] = name.trim();
    json['base'] = base;

    writeBaseThemeSnapshotToJson(json, defaultThemeForCustomBase(base));

    for (final field in editableThemeColorFields) {
      final color = colors[field.id];
      if (color != null) {
        field.writeToJson(json, color);
      }
    }

    return json;
  }
}

void writeBaseThemeSnapshotToJson(
  Map<String, dynamic> json,
  ThemeData theme,
) {
  final colorSchemeData = Map<String, dynamic>.from(
    json['colorScheme'] as Map? ?? const <String, dynamic>{},
  );
  final scheme = theme.colorScheme;

  void writeColor(String key, Color color) {
    colorSchemeData[key] = colorToHex(color);
  }

  writeColor('primary', scheme.primary);
  writeColor('onPrimary', scheme.onPrimary);
  writeColor('primaryContainer', scheme.primaryContainer);
  writeColor('onPrimaryContainer', scheme.onPrimaryContainer);
  writeColor('primaryFixed', scheme.primaryFixed);
  writeColor('primaryFixedDim', scheme.primaryFixedDim);
  writeColor('onPrimaryFixed', scheme.onPrimaryFixed);
  writeColor('onPrimaryFixedVariant', scheme.onPrimaryFixedVariant);
  writeColor('secondary', scheme.secondary);
  writeColor('onSecondary', scheme.onSecondary);
  writeColor('secondaryContainer', scheme.secondaryContainer);
  writeColor('onSecondaryContainer', scheme.onSecondaryContainer);
  writeColor('secondaryFixed', scheme.secondaryFixed);
  writeColor('secondaryFixedDim', scheme.secondaryFixedDim);
  writeColor('onSecondaryFixed', scheme.onSecondaryFixed);
  writeColor('onSecondaryFixedVariant', scheme.onSecondaryFixedVariant);
  writeColor('tertiary', scheme.tertiary);
  writeColor('onTertiary', scheme.onTertiary);
  writeColor('tertiaryContainer', scheme.tertiaryContainer);
  writeColor('onTertiaryContainer', scheme.onTertiaryContainer);
  writeColor('tertiaryFixed', scheme.tertiaryFixed);
  writeColor('tertiaryFixedDim', scheme.tertiaryFixedDim);
  writeColor('onTertiaryFixed', scheme.onTertiaryFixed);
  writeColor('onTertiaryFixedVariant', scheme.onTertiaryFixedVariant);
  writeColor('error', scheme.error);
  writeColor('onError', scheme.onError);
  writeColor('errorContainer', scheme.errorContainer);
  writeColor('onErrorContainer', scheme.onErrorContainer);
  writeColor('outline', scheme.outline);
  writeColor('outlineVariant', scheme.outlineVariant);
  writeColor('surface', scheme.surface);
  writeColor('onSurface', scheme.onSurface);
  writeColor('surfaceDim', scheme.surfaceDim);
  writeColor('surfaceBright', scheme.surfaceBright);
  writeColor('surfaceContainerLowest', scheme.surfaceContainerLowest);
  writeColor('surfaceContainerLow', scheme.surfaceContainerLow);
  writeColor('surfaceContainer', scheme.surfaceContainer);
  writeColor('surfaceContainerHigh', scheme.surfaceContainerHigh);
  writeColor('surfaceContainerHighest', scheme.surfaceContainerHighest);
  writeColor('onSurfaceVariant', scheme.onSurfaceVariant);
  writeColor('inverseSurface', scheme.inverseSurface);
  writeColor('onInverseSurface', scheme.onInverseSurface);
  writeColor('inversePrimary', scheme.inversePrimary);
  writeColor('shadow', scheme.shadow);
  writeColor('scrim', scheme.scrim);
  writeColor('surfaceTint', scheme.surfaceTint);

  final extraColors =
      theme.extension<ExtraColors>() ?? ExtraColors.fromScheme(scheme);
  writeColor('links', extraColors.linkColor);
  writeColor('codeHighlight', extraColors.codeHighlight);
  json['colorScheme'] = colorSchemeData;

  final foundation = theme.extension<FoundationSettings>();
  if (foundation?.color != null) {
    final foundationData = Map<String, dynamic>.from(
      json['foundation'] as Map? ?? const <String, dynamic>{},
    );
    foundationData['color'] = colorToHex(foundation!.color!);
    json['foundation'] = foundationData;
  }
}

class CustomThemeBaseOption {
  const CustomThemeBaseOption({
    required this.id,
    required this.label,
    required this.theme,
  });

  final String id;
  final String label;
  final ThemeData Function() theme;
}

final List<CustomThemeBaseOption> customThemeBaseOptions = [
  CustomThemeBaseOption(
    id: 'light',
    label: 'Sol',
    theme: () => ThemeLight.theme,
  ),
  CustomThemeBaseOption(
    id: 'dark',
    label: 'Nebula',
    theme: () => ThemeDark.theme,
  ),
  CustomThemeBaseOption(
    id: 'amoled',
    label: 'Eclipse',
    theme: () => ThemeAmoled.theme,
  ),
  CustomThemeBaseOption(
    id: 'aurora',
    label: 'Aurora',
    theme: () => ThemeAurora.theme,
  ),
  CustomThemeBaseOption(
    id: 'grand_master',
    label: 'Grand Master',
    theme: () => ThemeGrandMaster.theme,
  ),
  CustomThemeBaseOption(
    id: 'dark_lord',
    label: 'Dark Lord',
    theme: () => ThemeDarkLord.theme,
  ),
];

CustomThemeBaseOption? customThemeBaseOptionFor(String base) {
  final normalized = _recognizedCustomThemeBase(base);
  if (normalized == null) {
    return null;
  }

  for (final option in customThemeBaseOptions) {
    if (option.id == normalized) {
      return option;
    }
  }

  return null;
}

ThemeData defaultThemeForCustomBase(String base) {
  return customThemeBaseOptionFor(base)?.theme() ?? ThemeDark.theme;
}

String normalizeCustomThemeBase(String base) {
  return _recognizedCustomThemeBase(base) ?? 'dark';
}

String labelForCustomThemeBase(String base) {
  return customThemeBaseOptionFor(base)?.label ?? 'Nebula';
}

String? _recognizedCustomThemeBase(String base) {
  final normalized = base.trim().toLowerCase().replaceAll(
        RegExp(r'[\s-]+'),
        '_',
      );

  return switch (normalized) {
    'classic_light' || 'sol' || 'light' => 'light',
    'classic_dark' || 'nebula' || 'dark' => 'dark',
    'arnoled' || 'amoled' || 'eclipse' => 'amoled',
    'aurora' => 'aurora',
    'bundled:jedi' ||
    'jedi' ||
    'light_side' ||
    'grand_master' =>
      'grand_master',
    'bundled:sith' || 'sith' || 'dark_side' || 'dark_lord' => 'dark_lord',
    _ => null,
  };
}

String colorToHex(Color color) {
  final argb = color.toARGB32();
  return '#${argb.toRadixString(16).padLeft(8, '0')}';
}

Color? parseHexColor(String value) {
  final normalized = value.trim().replaceFirst('#', '');
  if (normalized.length != 6 && normalized.length != 8) {
    return null;
  }

  final buffer = StringBuffer();
  if (normalized.length == 6) {
    buffer.write('ff');
  }
  buffer.write(normalized);

  try {
    return Color(int.parse(buffer.toString(), radix: 16));
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> deepCopyJson(Map<String, dynamic> source) {
  return Map<String, dynamic>.from(
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>,
  );
}

ThemeData previewThemeForCustomDraft(CustomThemeDraft draft) {
  final baseTheme = defaultThemeForCustomBase(draft.base);
  final colorScheme = baseTheme.colorScheme.copyWith(
    primary: draft.colors['primary'],
    onPrimary: draft.colors['onPrimary'],
    primaryContainer: draft.colors['primaryContainer'],
    onPrimaryContainer: draft.colors['onPrimaryContainer'],
    secondary: draft.colors['secondary'],
    onSecondary: draft.colors['onSecondary'],
    secondaryContainer: draft.colors['secondaryContainer'],
    onSecondaryContainer: draft.colors['onSecondaryContainer'],
    tertiary: draft.colors['tertiary'],
    surface: draft.colors['surface'],
    onSurface: draft.colors['onSurface'],
    surfaceContainerLowest: draft.colors['surfaceContainerLowest'],
    surfaceContainerLow: draft.colors['surfaceContainerLow'],
    surfaceContainer: draft.colors['surfaceContainer'],
    surfaceContainerHigh: draft.colors['surfaceContainerHigh'],
    surfaceContainerHighest: draft.colors['surfaceContainerHighest'],
    outline: draft.colors['outline'],
  );

  final baseExtraColors = baseTheme.extension<ExtraColors>() ??
      ExtraColors.fromScheme(baseTheme.colorScheme);
  final extraColors = baseExtraColors.copyWith(
    linkColor: draft.colors['links'],
    codeHighlight: draft.colors['codeHighlight'],
  ) as ExtraColors;

  final baseFoundation = baseTheme.extension<FoundationSettings>() ??
      FoundationSettings(color: baseTheme.colorScheme.surfaceContainerLowest);
  final foundation = baseFoundation.copyWith(
    color: draft.colors['foundationColor'],
  ) as FoundationSettings;

  final extensions = List<ThemeExtension<dynamic>>.of(
    baseTheme.extensions.values.where(
      (extension) =>
          extension is! ExtraColors && extension is! FoundationSettings,
    ),
  )
    ..add(extraColors)
    ..add(foundation);

  return baseTheme.copyWith(
    colorScheme: colorScheme,
    extensions: extensions,
  );
}
