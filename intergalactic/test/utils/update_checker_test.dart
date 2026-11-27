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

    test('never opens the manual download through a shell', () {
      final launch = UpdateChecker.debugWindowsManualDownloadLaunch(
        Uri.parse('https://app.ourgalaxy.space/downloads/app.exe'),
      )!;

      // runInShell would make Windows run this as `cmd.exe /c ...`, which
      // interprets shell metacharacters in the installer URL.
      expect(launch.runInShell, isFalse);
      expect(launch.executable, 'rundll32.exe');
      expect(launch.arguments.first, 'url.dll,FileProtocolHandler');
    });

    test('passes a metacharacter installer url as one literal argument', () {
      // `&` survives Uri normalisation (unlike `|`, `<` or `^`, which are
      // percent-encoded), and the URL has no whitespace, so Dart would not
      // quote it for cmd.exe: under runInShell it would start a second
      // command.
      const hostile = r'https://app.ourgalaxy.space/downloads/app.exe&calc.exe';
      final url = Uri.parse(hostile);
      expect(url.toString(), hostile, reason: 'Uri must not neutralise `&`');

      final launch = UpdateChecker.debugWindowsManualDownloadLaunch(url)!;

      // The assertion this test was missing. Everything below proves the `&`
      // is not SPLIT into a second argument; none of it proves the argument
      // is not handed to a shell in the first place. A URL-specific branch -
      // "this one looks odd, run it through cmd so the quoting is handled" -
      // would satisfy every other expectation here and reopen exactly the
      // injection #342 closed, because `&calc.exe` only becomes a second
      // command once cmd.exe parses it.
      expect(
        launch.runInShell,
        isFalse,
        reason:
            'the safe-URL test pins runInShell; without the same pin here the '
            'hostile input is the one input allowed to reach a shell',
      );
      expect(launch.arguments.length, 2);
      expect(launch.arguments.last, hostile);
      expect(launch.executable, isNot(contains('cmd')));
      expect(launch.executable, isNot(contains(hostile)));
    });

    test('refuses to launch an installer url that is not https', () {
      // The manual-download button is reachable when the updater already
      // rejected the URLs as untrusted, so the installer URL here is remote
      // input. `url.dll,FileProtocolHandler` resolves whatever scheme it is
      // handed - a `file:` UNC path or any registered third-party protocol
      // handler - so anything that is not an https web address must produce
      // no launch configuration at all, and therefore no button.
      const rejected = [
        r'file://attacker.example/share/payload.exe',
        r'\\attacker.example\share\payload.exe',
        'ms-settings:',
        'javascript:alert(1)',
        'http://app.ourgalaxy.space/downloads/app.exe',
        'https:///downloads/app.exe',
      ];

      for (final url in rejected) {
        expect(
          UpdateChecker.debugWindowsManualDownloadLaunch(Uri.parse(url)),
          isNull,
          reason: '$url must never reach FileProtocolHandler',
        );
      }

      // Guards the assertions above against a launch helper that returns null
      // for everything: the legitimate case must still be launchable.
      expect(
        UpdateChecker.debugWindowsManualDownloadLaunch(
          Uri.parse('https://app.ourgalaxy.space/downloads/app.exe'),
        ),
        isNotNull,
      );
    });

    // The two gates are independent and neither subsumes the other, so each
    // one is asserted with the OTHER passing - otherwise a test would go on
    // passing after its own gate was deleted, which is exactly how the
    // untrusted-destination hole survived the first fix.
    test('an untrusted manifest gets no manual download even over https', () {
      expect(
        UpdateChecker.manualDownloadLaunch(
          installerUrl: Uri.parse('https://evil.example/InterGalactic.exe'),
          hasTrustedDestinations: false,
        ),
        isNull,
        reason:
            'the updater refused to download from this address moments '
            'earlier; offering one click to open it undoes that refusal',
      );
    });

    test('a trusted manifest still cannot smuggle a non-https scheme', () {
      for (final url in const [
        r'file://attacker.example/share/InterGalactic.exe',
        'ms-settings:',
        'http://app.ourgalaxy.space/downloads/app.exe',
      ]) {
        expect(
          UpdateChecker.manualDownloadLaunch(
            installerUrl: Uri.parse(url),
            hasTrustedDestinations: true,
          ),
          isNull,
          reason: '$url passed the manifest gate but must fail the scheme one',
        );
      }
    });

    test('both gates passing still yields a launch', () {
      // Vacuity guard. Without it, a `manualDownloadLaunch` hard-wired to
      // return null passes both tests above.
      expect(
        UpdateChecker.manualDownloadLaunch(
          installerUrl: Uri.parse(
            'https://app.ourgalaxy.space/downloads/app.exe',
          ),
          hasTrustedDestinations: true,
        ),
        isNotNull,
      );
    });
  });
}
