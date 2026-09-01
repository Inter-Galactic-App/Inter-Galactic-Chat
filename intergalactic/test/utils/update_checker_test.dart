import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/utils/update_checker_io.dart';

void main() {
  group('UpdateChecker version parsing', () {
    test('treats equal semantic tags as equal', () {
      expect(UpdateChecker.debugCompareVersionTags('v1.2.3', '1.2.3'), 0);
    });

    test('compares numeric build metadata numerically', () {
      expect(
        UpdateChecker.debugCompareVersionTags('v1.2.3+899', 'v1.2.3+898'),
        greaterThan(0),
      );
      expect(
        UpdateChecker.debugCompareBuildMetadata('899', '898'),
        greaterThan(0),
      );
    });

    test('compares mixed build metadata lexically', () {
      expect(
        UpdateChecker.debugCompareVersionTags('v1.2.3+rc2', 'v1.2.3+rc1'),
        greaterThan(0),
      );
      expect(
        UpdateChecker.debugCompareVersionTags('v1.2.3+1a', 'v1.2.3+1'),
        greaterThan(0),
      );
      expect(
        UpdateChecker.debugCompareBuildMetadata('rc1', 'rc2'),
        lessThan(0),
      );
    });

    test('parses semantic parts and build metadata', () {
      final parsed = UpdateChecker.debugParseVersionTag('v1.2.3+898');

      expect(parsed?.parts, [1, 2, 3]);
      expect(parsed?.build, '898');
    });

    test('falls back to build date when version parsing fails', () {
      expect(
        UpdateChecker.debugIsManifestNewer(
          version: 'not-a-version',
          buildDate: BuildConfig.BUILD_DATE.add(const Duration(days: 1)),
        ),
        isTrue,
      );
      expect(
        UpdateChecker.debugIsManifestNewer(
          version: 'not-a-version',
          buildDate: BuildConfig.BUILD_DATE.subtract(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('does not fall back to build date for equal raw invalid tags', () {
      expect(
        UpdateChecker.debugIsManifestNewer(
          version: BuildConfig.VERSION_TAG,
          buildDate: BuildConfig.BUILD_DATE.add(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('cleans release notes for compact update alerts', () {
      expect(
        UpdateChecker.debugCleanReleaseNotes(
          '  \r\n- Fixes Android notifications  \r\n\r\n- Adds release notes  ',
        ),
        '- Fixes Android notifications\n- Adds release notes',
      );
    });

    test('truncates long release notes for update alerts', () {
      final cleaned = UpdateChecker.debugCleanReleaseNotes('a' * 800);

      expect(cleaned, isNotNull);
      expect(cleaned!.length, lessThanOrEqualTo(703));
      expect(cleaned.endsWith('...'), isTrue);
    });

    test('builds post-update dialog with feature notes first', () {
      final markdown = UpdateChecker.debugReleaseNotesDialogMarkdown(
        featureNotes: 'Stories let you share photos for 24 hours.',
        releaseNotes: '- Fixed updater progress\n- Improved notifications',
      );

      expect(markdown, isNotNull);
      expect(
        markdown!.indexOf('Stories let you share photos'),
        lessThan(markdown.indexOf('- Fixed updater progress')),
      );
      expect(markdown, contains('## Featured in this update'));
      expect(markdown, contains('## Release notes'));
    });

    test(
      'post-update dialog can use feature notes without changelog notes',
      () {
        final markdown = UpdateChecker.debugReleaseNotesDialogMarkdown(
          featureNotes: 'Try the new stories composer from Home.',
          releaseNotes: null,
        );

        expect(markdown, contains('Try the new stories composer'));
        expect(markdown, isNot(contains('## Release notes')));
      },
    );

    test('parses release checksum files for Windows installers', () {
      const checksum =
          'SHA256  InterGalactic-Setup-0.7.2+980.exe  '
          '6785E4DA6E930308DE429C210BD72CB46ABC562AB5B697AF7A0038015C862F08';

      expect(
        UpdateChecker.debugParseSha256FromChecksums(
          checksum,
          'InterGalactic-Setup-0.7.2+980.exe',
        ),
        '6785E4DA6E930308DE429C210BD72CB46ABC562AB5B697AF7A0038015C862F08',
      );
    });

    test('parses sha256sum checksum files for Windows installers', () {
      const checksum =
          '6785e4da6e930308de429c210bd72cb46abc562ab5b697af7a0038015c862f08  '
          '*InterGalactic-Setup-0.7.2+980.exe';

      expect(
        UpdateChecker.debugParseSha256FromChecksums(
          checksum,
          'InterGalactic-Setup-0.7.2+980.exe',
        ),
        '6785E4DA6E930308DE429C210BD72CB46ABC562AB5B697AF7A0038015C862F08',
      );
    });

    test('parses unsigned Windows auto-update manifest opt-in', () {
      expect(
        UpdateChecker.debugManifestAllowsUnsignedWindowsAutoUpdate({
          'version': 'v0.7.2+980',
          'build_date_ms': 1744310000000,
          'platforms': {
            'windows': {
              'download_url': 'https://app.ourgalaxy.space/downloads/app.exe',
              'sha256':
                  '6785E4DA6E930308DE429C210BD72CB46ABC562AB5B697AF7A0038015C862F08',
              'auto_update': true,
              'allow_unsigned_auto_update': true,
            },
          },
        }),
        isTrue,
      );
    });

    test('parses custom feature notes manifest url', () {
      expect(
        UpdateChecker.debugManifestFeatureNotesUrl({
          'version': 'v0.7.2+980',
          'build_date_ms': 1744310000000,
          'feature_notes_url':
              'https://app.ourgalaxy.space/updates/features/v0.7.2.md',
        })?.toString(),
        'https://app.ourgalaxy.space/updates/features/v0.7.2.md',
      );
    });

    test('defaults unsigned Windows auto-update opt-in to false', () {
      expect(
        UpdateChecker.debugManifestAllowsUnsignedWindowsAutoUpdate({
          'version': 'v0.7.2+980',
          'build_date_ms': 1744310000000,
          'platforms': {
            'windows': {
              'download_url': 'https://app.ourgalaxy.space/downloads/app.exe',
              'auto_update': true,
            },
          },
        }),
        isFalse,
      );
    });

    test('parses unsigned Windows updater request flag', () {
      final baseArgs = [
        '--intergalactic-updater',
        '--installer-url',
        'https://app.ourgalaxy.space/downloads/app.exe',
        '--version',
        'v0.7.2+980',
        '--app-exe',
        r'<install-dir>\Inter Galactic\InterGalactic.exe',
        '--manifest-url',
        'https://app.ourgalaxy.space/updates/latest.json',
      ];

      expect(
        UpdateChecker.debugWindowsUpdaterRequestAllowsUnsigned(baseArgs),
        isFalse,
      );
      expect(
        UpdateChecker.debugWindowsUpdaterRequestAllowsUnsigned([
          ...baseArgs,
          '--allow-unsigned-auto-update',
        ]),
        isTrue,
      );
    });

    test('passes Windows updater installer path through script file args', () {
      const installerPath = 'test-fixtures/InterGalactic-Setup-0.7.2+980.exe';

      final signatureArgs =
          UpdateChecker.debugWindowsSignatureVerificationPowerShellArgs(
            installerPath,
          );
      final installerArgs =
          UpdateChecker.debugWindowsSilentInstallerPowerShellArgs(
            installerPath,
          );

      for (final args in [signatureArgs, installerArgs]) {
        expect(args[3], "-File");
        expect(args[4], endsWith(".ps1"));
        expect(args.last, installerPath);
        expect(args.join("\n"), isNot(contains(r"$args[0]")));
        expect(args, isNot(contains("-Command")));
      }
    });
  });
}
