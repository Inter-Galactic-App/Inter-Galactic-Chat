import 'dart:convert';

import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/config/theme_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/custom_theme_editor.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:universal_html/html.dart' as html;

class ThemeListWidget extends StatefulWidget {
  const ThemeListWidget({super.key});

  @override
  State<ThemeListWidget> createState() => _ThemeListWidgetState();
}

class _ThemeEntry {
  const _ThemeEntry({
    required this.id,
    required this.name,
    required this.swatchColors,
    required this.apply,
    this.customTheme,
    this.isBundled = false,
  });

  final String id;
  final String name;
  final List<Color> swatchColors;
  final Future<void> Function(BuildContext context) apply;
  final CustomThemeDefinition? customTheme;
  final bool isBundled;

  bool get isCustom => customTheme != null && !isBundled;
}

/// Bundled theme IDs and asset paths shipped inside the app.
const Map<String, String> _bundledThemeAssets = {
  'jedi': 'assets/themes/jedi.json',
  'sith': 'assets/themes/sith.json',
};

class _ThemeListWidgetState extends State<ThemeListWidget> {
  late List<_ThemeEntry> entries;

  List<_ThemeEntry> get defaultThemes => [
        _ThemeEntry(
          id: 'light',
          name: labelForCustomThemeBase('light'),
          swatchColors: _defaultThemeSwatches('light'),
          apply: (BuildContext context) async {
            preferences.theme.set('light');
            final theme = await preferences.resolveTheme(
              overrideBrightness: Brightness.light,
            );
            if (context.mounted) {
              ThemeChanger.setTheme(context, theme);
            }
          },
        ),
        _ThemeEntry(
          id: 'dark',
          name: labelForCustomThemeBase('dark'),
          swatchColors: _defaultThemeSwatches('dark'),
          apply: (BuildContext context) async {
            preferences.theme.set('dark');
            final theme = await preferences.resolveTheme(
              overrideBrightness: Brightness.dark,
            );
            if (context.mounted) {
              ThemeChanger.setTheme(context, theme);
            }
          },
        ),
        _ThemeEntry(
          id: 'amoled',
          name: labelForCustomThemeBase('amoled'),
          swatchColors: _defaultThemeSwatches('amoled'),
          apply: (BuildContext context) async {
            preferences.theme.set('amoled');
            final theme = await preferences.resolveTheme(
              overrideBrightness: Brightness.dark,
            );
            if (context.mounted) {
              ThemeChanger.setTheme(context, theme);
            }
          },
        ),
        _ThemeEntry(
          id: 'aurora',
          name: labelForCustomThemeBase('aurora'),
          swatchColors: _defaultThemeSwatches('aurora'),
          apply: (BuildContext context) async {
            preferences.theme.set('aurora');
            final theme = await preferences.resolveTheme(
              overrideBrightness: Brightness.dark,
            );
            if (context.mounted) {
              ThemeChanger.setTheme(context, theme);
            }
          },
        ),
      ];

  @override
  void initState() {
    super.initState();
    entries = List.from(defaultThemes);
    initBundledThemes();
    loadCustomThemes();
  }

  void initBundledThemes() async {
    final bundled = <_ThemeEntry>[];

    for (final entry in _bundledThemeAssets.entries) {
      final id = 'bundled:${entry.key}';
      final assetPath = entry.value;
      try {
        final raw = await rootBundle.loadString(assetPath);
        final json = jsonDecode(raw);
        if (json is! Map<String, dynamic>) {
          continue;
        }

        final name = (json['name'] as String?)?.trim() ?? assetPath;

        bundled.add(_ThemeEntry(
          id: id,
          name: name,
          isBundled: true,
          swatchColors: _swatchesFromThemeJson(
            json,
            fallback: _defaultThemeSwatches(id),
          ),
          apply: (context) async {
            final themeData = await ThemeJsonConverter.fromJson(json, null);
            if (themeData != null && context.mounted) {
              ThemeChanger.setTheme(context, themeData);
            }
            preferences.theme.set(id);
          },
        ));
      } catch (_) {
        continue;
      }
    }

    if (!mounted || bundled.isEmpty) return;

    setState(() {
      final defaults =
          entries.where((e) => !e.isCustom && !e.isBundled).toList();
      final customs = entries.where((e) => e.isCustom).toList();
      entries = [...defaults, ...bundled, ...customs];
    });
  }

  Future<void> loadCustomThemes() async {
    final themes = await ThemeConfig.loadCustomThemes();

    final customEntries = themes.map((theme) {
      return _ThemeEntry(
        id: theme.id,
        name: theme.displayName,
        customTheme: theme,
        swatchColors: _swatchesFromThemeJson(
          theme.json,
          fallback: _defaultThemeSwatches(theme.base),
        ),
        apply: (context) async {
          final definition = await ThemeConfig.loadThemeByName(theme.id);
          if (definition == null) {
            return;
          }

          final themeData =
              await ThemeJsonConverter.fromJson(definition.json, null);
          if (themeData != null && context.mounted) {
            ThemeChanger.setTheme(context, themeData);
          }
          preferences.theme.set(theme.id);
        },
      );
    });

    if (!mounted) {
      return;
    }

    setState(() {
      final bundledEntries = entries.where((e) => e.isBundled).toList();
      entries = [
        ...defaultThemes,
        ...bundledEntries,
        ...customEntries,
      ];
    });
  }

  String get activeThemeId => preferences.theme.value;

  CustomThemeDefinition? get activeCustomTheme {
    for (final entry in entries) {
      if (entry.id == activeThemeId && entry.isCustom) {
        return entry.customTheme;
      }
    }

    return null;
  }

  String inferBaseTheme() {
    final selectedBase = customThemeBaseOptionFor(preferences.theme.value);
    if (selectedBase != null) {
      return selectedBase.id;
    }

    return ThemeChanger.currentTheme(context).brightness == Brightness.light
        ? 'light'
        : 'dark';
  }

  Future<void> createCustomTheme() async {
    final currentTheme = ThemeChanger.currentTheme(context);
    final draft = CustomThemeDraft.fromThemeData(
      name: 'New Theme',
      base: inferBaseTheme(),
      theme: currentTheme,
    );

    final result = await showCustomThemeEditor(context, draft: draft);
    if (result == null) {
      return;
    }

    final definition = await ThemeConfig.saveTheme(result);
    final themeData = await ThemeJsonConverter.fromJson(definition.json, null);
    preferences.theme.set(definition.id);

    if (mounted && themeData != null) {
      ThemeChanger.setTheme(context, themeData);
    }

    await loadCustomThemes();
  }

  Future<void> editCustomTheme(CustomThemeDefinition definition) async {
    final draft = CustomThemeDraft.fromDefinition(definition);
    final result = await showCustomThemeEditor(context, draft: draft);
    if (result == null) {
      return;
    }

    final saved = await ThemeConfig.saveTheme(result);
    final themeData = await ThemeJsonConverter.fromJson(saved.json, null);
    preferences.theme.set(saved.id);

    if (mounted && themeData != null) {
      ThemeChanger.setTheme(context, themeData);
    }

    await loadCustomThemes();
  }

  Future<void> deleteCustomTheme(CustomThemeDefinition definition) async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: definition.displayName,
      prompt: 'Delete this custom theme?',
      dangerous: true,
    );

    if (confirmed != true) {
      return;
    }

    await ThemeConfig.removeTheme(definition);

    if (activeThemeId == definition.id) {
      preferences.theme.set('dark');
      final fallback = await preferences.resolveTheme(
        overrideBrightness: Brightness.dark,
      );
      if (mounted) {
        ThemeChanger.setTheme(context, fallback);
      }
    }

    await loadCustomThemes();
  }

  Future<void> exportThemeArchive(CustomThemeDefinition definition) async {
    final fileName =
        '${ThemeConfig.sanitizeThemeId(definition.displayName)}.intergalactic-theme.zip';
    final bytes = Uint8List.fromList(
      await ThemeConfig.exportThemeToZipBytes(definition.id),
    );
    final blob = html.Blob([bytes], 'application/zip');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = fileName
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final activeCustomTheme = this.activeCustomTheme;

    return Column(
      spacing: 14,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThemeEntryGrid(
          entries: entries,
          activeThemeId: activeThemeId,
          onApply: (entry) => entry.apply(context),
          onEdit: (entry) => editCustomTheme(entry.customTheme!),
          onExport: (entry) => exportThemeArchive(entry.customTheme!),
          onDelete: (entry) => deleteCustomTheme(entry.customTheme!),
        ),
        if (entries.any((e) => e.isBundled))
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'Grand Master and Dark Lord are built-in themes and cannot be edited.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        if (entries.any((entry) => entry.isCustom))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Custom themes are stored in this web app container and stay selectable alongside the built-in themes.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        Row(
          spacing: 8,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: tiamat.Button.secondary(
                text: 'Create Custom Theme',
                onTap: createCustomTheme,
              ),
            ),
            Tooltip(
              message: 'Import is not available in the web build',
              child: const tiamat.CircleButton(
                icon: Icons.upload_file,
                onPressed: null,
              ),
            ),
            Tooltip(
              message: activeCustomTheme == null
                  ? 'Select a custom theme to export'
                  : 'Export Theme Archive',
              child: tiamat.CircleButton(
                icon: Icons.download,
                onPressed: activeCustomTheme == null
                    ? null
                    : () => exportThemeArchive(activeCustomTheme),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

List<Color> _defaultThemeSwatches(String id) {
  return switch (id) {
    'light' => const [
        Color(0xFF0EA5E9),
        Color(0xFF38BDF8),
        Color(0xFFE9EFF0),
        Color(0xFFFFFFFF),
      ],
    'dark' => const [
        Color(0xFF0B7FAE),
        Color(0xFF2F3337),
        Color(0xFF26292C),
        Color(0xFF131516),
      ],
    'amoled' => const [
        Color(0xFF000000),
        Color(0xFF050505),
        Color(0xFF151515),
        Color(0xFF0F766E),
      ],
    'aurora' => const [
        Color(0xFF1FD5D0),
        Color(0xFF21B7A3),
        Color(0xFF0B1B28),
        Color(0xFF020509),
      ],
    'bundled:jedi' || 'jedi' => const [
        Color(0xFF00B4D8),
        Color(0xFF38BDF8),
        Color(0xFF162540),
        Color(0xFF080E1A),
      ],
    'bundled:sith' || 'sith' => const [
        Color(0xFFDC2626),
        Color(0xFFEF4444),
        Color(0xFF1A1A1A),
        Color(0xFF050505),
      ],
    _ => const [
        Color(0xFF0B7FAE),
        Color(0xFF38BDF8),
        Color(0xFF26292C),
        Color(0xFF131516),
      ],
  };
}

List<Color> _swatchesFromThemeJson(
  Map<String, dynamic> json, {
  required List<Color> fallback,
}) {
  final colorScheme = json['colorScheme'];
  final foundation = json['foundation'];
  final colors = <Color>[
    if (colorScheme is Map && _parseSwatch(colorScheme['primary']) != null)
      _parseSwatch(colorScheme['primary'])!,
    if (colorScheme is Map && _parseSwatch(colorScheme['secondary']) != null)
      _parseSwatch(colorScheme['secondary'])!,
    if (colorScheme is Map &&
        _parseSwatch(colorScheme['surfaceContainer']) != null)
      _parseSwatch(colorScheme['surfaceContainer'])!,
    if (foundation is Map && _parseSwatch(foundation['color']) != null)
      _parseSwatch(foundation['color'])!,
  ];

  return colors.isEmpty ? fallback : colors;
}

Color? _parseSwatch(Object? value) {
  return value is String ? parseHexColor(value) : null;
}

class _ThemeEntryGrid extends StatelessWidget {
  const _ThemeEntryGrid({
    required this.entries,
    required this.activeThemeId,
    required this.onApply,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
  });

  final List<_ThemeEntry> entries;
  final String activeThemeId;
  final ValueChanged<_ThemeEntry> onApply;
  final ValueChanged<_ThemeEntry> onEdit;
  final ValueChanged<_ThemeEntry> onExport;
  final ValueChanged<_ThemeEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 700;
        if (twoColumns) {
          final splitIndex = (entries.length / 2).ceil();
          final leftEntries = entries.take(splitIndex);
          final rightEntries = entries.skip(splitIndex);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ThemeEntryColumn(
                  entries: leftEntries,
                  activeThemeId: activeThemeId,
                  onApply: onApply,
                  onEdit: onEdit,
                  onExport: onExport,
                  onDelete: onDelete,
                ),
              ),
              const SizedBox(width: 72),
              Expanded(
                child: _ThemeEntryColumn(
                  entries: rightEntries,
                  activeThemeId: activeThemeId,
                  onApply: onApply,
                  onEdit: onEdit,
                  onExport: onExport,
                  onDelete: onDelete,
                ),
              ),
            ],
          );
        }

        return _ThemeEntryColumn(
          entries: entries,
          activeThemeId: activeThemeId,
          onApply: onApply,
          onEdit: onEdit,
          onExport: onExport,
          onDelete: onDelete,
        );
      },
    );
  }
}

class _ThemeEntryColumn extends StatelessWidget {
  const _ThemeEntryColumn({
    required this.entries,
    required this.activeThemeId,
    required this.onApply,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
  });

  final Iterable<_ThemeEntry> entries;
  final String activeThemeId;
  final ValueChanged<_ThemeEntry> onApply;
  final ValueChanged<_ThemeEntry> onEdit;
  final ValueChanged<_ThemeEntry> onExport;
  final ValueChanged<_ThemeEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        for (final entry in entries)
          _ThemeEntryRow(
            entry: entry,
            selected: activeThemeId == entry.id,
            onApply: () => onApply(entry),
            onEdit: entry.isCustom ? () => onEdit(entry) : null,
            onExport: entry.isCustom ? () => onExport(entry) : null,
            onDelete: entry.isCustom ? () => onDelete(entry) : null,
          ),
      ],
    );
  }
}

class _ThemeEntryRow extends StatelessWidget {
  const _ThemeEntryRow({
    required this.entry,
    required this.selected,
    required this.onApply,
    this.onEdit,
    this.onExport,
    this.onDelete,
  });

  final _ThemeEntry entry;
  final bool selected;
  final VoidCallback onApply;
  final VoidCallback? onEdit;
  final VoidCallback? onExport;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: Text(
            entry.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
          ),
        ),
        const SizedBox(width: 12),
        _ThemeSwatchButton(
          colors: entry.swatchColors,
          selected: selected,
          onTap: onApply,
        ),
        if (entry.isCustom) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: CommonStrings.promptEdit,
            child: tiamat.CircleButton(
              icon: Icons.edit,
              onPressed: onEdit,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Export Theme Archive',
            child: tiamat.CircleButton(
              icon: Icons.download,
              onPressed: onExport,
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: CommonStrings.promptDelete,
            child: tiamat.CircleButton(
              icon: Icons.delete,
              onPressed: onDelete,
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeSwatchButton extends StatelessWidget {
  const _ThemeSwatchButton({
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fallback = Theme.of(context).colorScheme.primary;
    final swatches = colors.isEmpty ? [fallback] : colors;

    return Tooltip(
      message: 'Select theme',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: swatches,
              ),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline.withAlpha(90),
                width: selected ? 2.2 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withAlpha(35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    color: Colors.white,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                      ),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
