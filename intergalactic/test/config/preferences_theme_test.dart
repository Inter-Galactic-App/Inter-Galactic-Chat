import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/config/theme_config.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_aurora.dart';
import 'package:tiamat/config/style/theme_cosmic_stardust.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_dark_matter.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'ig_preferences_theme_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          return switch (call.method) {
            'getApplicationSupportDirectory' => supportDirectory.path,
            _ => null,
          };
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('new installs default to Dark Matter', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = Preferences();
    await preferences.init();
    final theme = await preferences.resolveTheme();

    expect(preferences.theme.value, 'dark_matter');
    expect(theme.colorScheme.primary, ThemeDarkMatterColors.primary);
  });

  test('legacy theme labels migrate to stable stored ids', () async {
    for (final entry in const {
      'Classic Light': 'light',
      'Sol': 'light',
      'Dark Matter': 'dark_matter',
      'Classic Dark': 'dark',
      'Nebula': 'dark',
      'Arnoled': 'amoled',
      'Amoled': 'amoled',
      'Eclipse': 'amoled',
      'Cosmic Stardust': 'cosmic_stardust',
      'Light Side': 'bundled:jedi',
      'Grand Master': 'bundled:jedi',
      'Dark Side': 'bundled:sith',
      'Dark Lord': 'bundled:sith',
    }.entries) {
      SharedPreferences.setMockInitialValues({'app_theme': entry.key});

      final preferences = Preferences();
      await preferences.init();

      expect(preferences.theme.value, entry.value);
    }
  });

  test('aurora resolves through the stable built-in theme id', () async {
    SharedPreferences.setMockInitialValues({'app_theme': 'Aurora'});

    final preferences = Preferences();
    await preferences.init();
    final theme = await preferences.resolveTheme();

    expect(preferences.theme.value, 'aurora');
    expect(theme.colorScheme.primary, ThemeAuroraColors.primary);
  });

  test(
    'cosmic stardust resolves through the stable built-in theme id',
    () async {
      SharedPreferences.setMockInitialValues({'app_theme': 'Cosmic Stardust'});

      final preferences = Preferences();
      await preferences.init();
      final theme = await preferences.resolveTheme();

      expect(preferences.theme.value, 'cosmic_stardust');
      expect(theme.colorScheme.primary, ThemeCosmicStardustColors.primary);
    },
  );

  test('custom theme selection survives a new built-in id collision', () async {
    final themeDir = Directory(
      path.join(supportDirectory.path, 'theme', 'custom', 'cosmic_stardust'),
    );
    await themeDir.create(recursive: true);
    await File(path.join(themeDir.path, 'theme.json')).writeAsString(
      jsonEncode({
        'name': 'My Cosmic Stardust',
        'base': 'dark',
        'colorScheme': {'primary': '#ff123456'},
      }),
    );
    SharedPreferences.setMockInitialValues({'app_theme': 'cosmic_stardust'});

    final preferences = Preferences();
    await preferences.init();
    final theme = await preferences.resolveTheme();

    expect(
      preferences.theme.value,
      Preferences.customThemeSelectionId('cosmic_stardust'),
    );
    expect(theme.colorScheme.primary, const Color(0xFF123456));
  });

  test('existing built-in theme id collision remains built-in', () async {
    final themeDir = Directory(
      path.join(supportDirectory.path, 'theme', 'custom', 'dark'),
    );
    await themeDir.create(recursive: true);
    await File(path.join(themeDir.path, 'theme.json')).writeAsString(
      jsonEncode({
        'name': 'My Dark',
        'base': 'dark',
        'colorScheme': {'primary': '#ff123456'},
      }),
    );
    SharedPreferences.setMockInitialValues({'app_theme': 'dark'});

    final preferences = Preferences();
    await preferences.init();
    final theme = await preferences.resolveTheme();

    expect(preferences.theme.value, 'dark');
    expect(theme.colorScheme.primary, ThemeDarkColors.primary);
  });

  test(
    'legacy raw custom theme ids stay custom before label migration',
    () async {
      final themeDir = Directory(
        path.join(supportDirectory.path, 'theme', 'custom', 'nebula'),
      );
      await themeDir.create(recursive: true);
      await File(path.join(themeDir.path, 'theme.json')).writeAsString(
        jsonEncode({
          'name': 'My Nebula',
          'base': 'dark',
          'colorScheme': {'primary': '#ff654321'},
        }),
      );
      SharedPreferences.setMockInitialValues({'app_theme': 'nebula'});

      final preferences = Preferences();
      await preferences.init();
      final theme = await preferences.resolveTheme();

      expect(preferences.theme.value, 'nebula');
      expect(
        Preferences.matchesCustomThemeSelection(
          preferences.theme.value,
          'nebula',
        ),
        isTrue,
      );
      expect(theme.colorScheme.primary, const Color(0xFF654321));
    },
  );

  test(
    'legacy imported theme folders resolve and delete by visible id',
    () async {
      final legacyDir = Directory(
        path.join(
          supportDirectory.path,
          'theme',
          'custom',
          'legacy_theme.intergalactic-theme',
        ),
      );
      await legacyDir.create(recursive: true);
      await File(path.join(legacyDir.path, 'theme.json')).writeAsString(
        jsonEncode({
          'name': 'Legacy Theme',
          'base': 'dark',
          'colorScheme': {'primary': '#ff112233'},
        }),
      );

      final customThemes = await ThemeConfig.loadCustomThemes();
      expect(customThemes.map((theme) => theme.id), contains('legacy_theme'));
      expect(await ThemeConfig.getThemeByName('legacy_theme'), isNotNull);

      SharedPreferences.setMockInitialValues({
        'app_theme': Preferences.customThemeSelectionId('legacy_theme'),
      });

      final preferences = Preferences();
      await preferences.init();
      final theme = await preferences.resolveTheme();

      expect(
        preferences.theme.value,
        Preferences.customThemeSelectionId('legacy_theme'),
      );
      expect(theme.colorScheme.primary, const Color(0xFF112233));

      await ThemeConfig.removeTheme('legacy_theme');
      expect(await legacyDir.exists(), isFalse);
    },
  );

  test(
    'theme archive import strips package suffix to canonical folder',
    () async {
      final archiveFile = File(
        path.join(
          supportDirectory.path,
          'packed_theme.intergalactic-theme.zip',
        ),
      );
      final themeBytes = utf8.encode(
        jsonEncode({
          'name': 'Packed Theme',
          'base': 'dark',
          'colorScheme': {'primary': '#ff445566'},
        }),
      );
      final archive = Archive()
        ..addFile(ArchiveFile('theme.json', themeBytes.length, themeBytes));
      await archiveFile.writeAsBytes(ZipEncoder().encode(archive) ?? const []);

      final importedTheme = await ThemeConfig.installThemeFromZip(archiveFile);
      final canonicalDir = Directory(
        path.join(supportDirectory.path, 'theme', 'custom', 'packed_theme'),
      );
      final legacyDir = Directory(
        path.join(
          supportDirectory.path,
          'theme',
          'custom',
          'packed_theme.intergalactic-theme',
        ),
      );

      expect(importedTheme?.id, 'packed_theme');
      expect(await canonicalDir.exists(), isTrue);
      expect(await legacyDir.exists(), isFalse);
      expect(await ThemeConfig.getThemeByName('packed_theme'), isNotNull);
    },
  );
}
