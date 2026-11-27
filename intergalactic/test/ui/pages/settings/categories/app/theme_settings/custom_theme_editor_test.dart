import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/custom_theme_editor.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/theme_token_usage_map.dart';
import 'package:tiamat/config/style/theme_aurora.dart';
import 'package:tiamat/config/style/theme_cosmic_stardust.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_dark_lord.dart';
import 'package:tiamat/config/style/theme_dark_matter.dart';
import 'package:tiamat/config/style/theme_grand_master.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview resolver applies unsaved colors without mutating draft', () {
    final draft = _draft(
      colors: {
        'primary': Colors.pink,
        'links': Colors.cyan,
        'foundationColor': Colors.black,
      },
    );

    final theme = previewThemeForCustomDraft(draft);

    expect(theme.colorScheme.primary, Colors.pink);
    expect(theme.extension<ExtraColors>()?.linkColor, Colors.cyan);
    expect(theme.extension<FoundationSettings>()?.color, Colors.black);
    expect(draft.colors['primary'], Colors.pink);
  });

  test('usage map covers all editable theme fields', () {
    final editableIds = editableThemeColorFields
        .map((field) => field.id)
        .toSet();
    final missingIds = editableIds
        .where((id) => (themeTokenUsageMap[id] ?? const []).isEmpty)
        .toList();
    final staleIds = themeTokenUsageMap.keys.where(
      (id) => !editableIds.contains(id),
    );

    expect(missingIds, isEmpty);
    expect(staleIds, isEmpty);
  });

  test('token search matches labels, groups, ids, and usage examples', () {
    final composerResults = filterThemeTokenFields(
      editableThemeColorFields,
      'composer',
    );
    final linkResults = filterThemeTokenFields(
      editableThemeColorFields,
      'link',
    );
    final surfaceResults = filterThemeTokenFields(
      editableThemeColorFields,
      'surfaces',
    );

    expect(composerResults.map((field) => field.id), contains('secondary'));
    expect(linkResults.map((field) => field.id), contains('links'));
    expect(surfaceResults.map((field) => field.id), contains('surface'));
  });

  test('custom theme bases include all default theme starting points', () {
    expect(
      customThemeBaseOptions.map((option) => option.label),
      equals([
        'Sol',
        'Dark Matter',
        'Nebula',
        'Eclipse',
        'Aurora',
        'Cosmic Stardust',
        'Grand Master',
        'Dark Lord',
      ]),
    );

    expect(
      defaultThemeForCustomBase('Dark Matter').colorScheme.primary,
      ThemeDarkMatterColors.primary,
    );
    expect(
      defaultThemeForCustomBase('Aurora').colorScheme.primary,
      ThemeAuroraColors.primary,
    );
    expect(
      defaultThemeForCustomBase('Cosmic Stardust').colorScheme.primary,
      ThemeCosmicStardustColors.primary,
    );
    expect(
      defaultThemeForCustomBase('Light Side').colorScheme.primary,
      ThemeGrandMasterColors.primary,
    );
    expect(normalizeCustomThemeBase('Dark Side'), 'dark_lord');
  });

  testWidgets('base selection warns before replacing token edits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpEditor(tester, draft: _draft(colors: {'primary': Colors.pink}));

    await tester.tap(find.byKey(const ValueKey('theme-base-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sol').last);
    await tester.pumpAndSettle();

    expect(find.text('Save changes first?'), findsOneWidget);
    expect(find.text('Start over'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(find.text('Save changes first?'), findsNothing);
  });

  test(
    'custom theme json preserves base theme settings when omitted',
    () async {
      final theme = await ThemeJsonConverter.fromJson({
        'name': 'Nebula copy',
        'base': 'dark',
        'colorScheme': {'primary': '#ff00ffff'},
      }, null);

      final baseSettings = ThemeDark.theme.extension<ThemeSettings>()!;
      final settings = theme!.extension<ThemeSettings>()!;

      expect(theme.colorScheme.primary, const Color(0xFF00FFFF));
      expect(settings.caulkBorders, baseSettings.caulkBorders);
      expect(settings.caulkBorderRadius, baseSettings.caulkBorderRadius);
      expect(settings.caulkStrokeThickness, baseSettings.caulkStrokeThickness);
    },
  );

  test('custom theme json refreshes full base color snapshot', () async {
    final draft = CustomThemeDraft.fromThemeData(
      name: 'Dark Lord copy',
      base: 'dark_lord',
      theme: ThemeDarkLord.theme,
      sourceJson: {
        'base': 'dark',
        'colorScheme': {
          'surfaceDim': '#ff2b2e31',
          'outlineVariant': '#ff2b2e31',
        },
      },
    );
    final json = draft.toJson();

    expect(
      (json['colorScheme'] as Map)['surfaceDim'],
      colorToHex(ThemeDarkLord.theme.colorScheme.surfaceDim),
    );
    expect(
      (json['colorScheme'] as Map)['outlineVariant'],
      colorToHex(ThemeDarkLord.theme.colorScheme.outlineVariant),
    );

    final theme = await ThemeJsonConverter.fromJson(json, null);

    expect(
      theme!.colorScheme.surfaceDim,
      ThemeDarkLord.theme.colorScheme.surfaceDim,
    );
    expect(
      theme.colorScheme.outlineVariant,
      ThemeDarkLord.theme.colorScheme.outlineVariant,
    );
  });

  testWidgets('desktop editor shows edit pane and live preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpEditor(tester);

    expect(find.text('Create Custom Theme'), findsOneWidget);
    expect(find.text('Theme Workshop'), findsNothing);
    expect(find.byKey(const ValueKey('theme-token-search')), findsOneWidget);
    expect(find.text('Live app preview'), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-token-primary')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('preview-target-primary-button')),
      findsOneWidget,
    );
    expect(find.text('P'), findsWidgets);
  });

  testWidgets('preview target click shows token swatches', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('preview-target-room-header')));
    await tester.pumpAndSettle();

    expect(find.text('Room header swatches'), findsOneWidget);
    expect(find.text('SC3'), findsOneWidget);
    expect(find.text('ST'), findsOneWidget);
  });

  testWidgets('save returns edited draft', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    CustomThemeDraft? savedDraft;
    await _pumpEditor(tester, onSave: (draft) => savedDraft = draft);

    await tester.enterText(
      find.byKey(const ValueKey('theme-token-search')),
      'links',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-token-links')));
    await tester.pump();
    await tester.tap(find.widgetWithText(tiamat.Button, 'Pick').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '#FF00FF00');
    await tester.pump();
    await tester.tap(find.widgetWithText(tiamat.Button, 'Apply').last);
    await tester.pumpAndSettle();

    expect(find.text('#FF00FF00'), findsOneWidget);

    await tester.tap(find.text('Save Theme'));
    await tester.pumpAndSettle();

    expect(savedDraft?.colors['links'], const Color(0xFF00FF00));
  });

  test('contrast warnings name direct text and surface conflicts', () {
    final draft = _draft(
      colors: {
        'onSurface': Colors.white,
        'surfaceContainerLowest': Colors.white,
      },
    );

    final issues = contrastIssuesForCustomThemeDraft(draft);

    expect(
      issues.map((issue) => issue.contextLabel),
      contains('Space rail labels and icons'),
    );
    expect(
      issues
          .firstWhere(
            (issue) => issue.contextLabel == 'Space rail labels and icons',
          )
          .textTokenLabel,
      'Surface Text',
    );
  });

  test('contrast warnings stay quiet for default draft', () {
    expect(contrastIssuesForCustomThemeDraft(_draft()), isEmpty);
  });

  testWidgets('save warns before returning unreadable theme', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    CustomThemeDraft? savedDraft;
    await _pumpEditor(
      tester,
      draft: _draft(
        colors: {
          'onSurface': Colors.white,
          'surfaceContainerLowest': Colors.white,
        },
      ),
      onSave: (draft) => savedDraft = draft,
    );

    await tester.tap(find.text('Save Theme'));
    await tester.pumpAndSettle();

    expect(find.text('Contrast warning'), findsOneWidget);
    expect(find.text('Space rail labels and icons'), findsOneWidget);
    expect(savedDraft, isNull);

    await tester.tap(find.text('Save Anyway'));
    await tester.pumpAndSettle();

    expect(savedDraft, isNotNull);
  });

  testWidgets('cancel does not return a draft', (tester) async {
    var saved = false;
    var canceled = false;
    await _pumpEditor(
      tester,
      onSave: (_) => saved = true,
      onCancel: () => canceled = true,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    expect(canceled, isTrue);
  });

  testWidgets('mobile mode switches between edit and preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpEditor(tester);

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Create Custom Theme'), findsOneWidget);
    expect(find.text('Theme Workshop'), findsNothing);
    expect(find.text('Starting Point'), findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Live app preview'), findsOneWidget);
    expect(find.text('Rooms'), findsWidgets);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('color picker preserves hue and saturation while dimming', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeDark.theme,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showCustomThemeColorPicker(
                      context,
                      title: 'Pick color',
                      initialColor: const HSVColor.fromAHSV(
                        1,
                        210,
                        0.75,
                        0.6,
                      ).toColor(),
                      defaultColor: Colors.blue,
                    );
                  },
                  child: const Text('Open picker'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    final hueBefore = tester.widget<Slider>(find.byType(Slider).at(0)).value;
    final saturationBefore = tester
        .widget<Slider>(find.byType(Slider).at(1))
        .value;

    await tester.drag(find.byType(Slider).at(2), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Slider>(find.byType(Slider).at(0)).value,
      closeTo(hueBefore, 0.001),
    );
    expect(
      tester.widget<Slider>(find.byType(Slider).at(1)).value,
      closeTo(saturationBefore, 0.001),
    );
  });
}

CustomThemeDraft _draft({Map<String, Color> colors = const {}}) {
  return CustomThemeDraft.fromThemeData(
    name: 'Test Theme',
    base: 'dark',
    theme: ThemeDark.theme,
  )..colors.addAll(colors);
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  CustomThemeDraft? draft,
  ValueChanged<CustomThemeDraft>? onSave,
  VoidCallback? onCancel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: CustomThemeEditorPage(
          initialDraft: draft ?? _draft(),
          onSave: onSave,
          onCancel: onCancel,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
