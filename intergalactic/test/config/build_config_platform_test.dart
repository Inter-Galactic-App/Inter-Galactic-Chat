import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/build_config.dart';

/// These tests run without `--dart-define=PLATFORM=...`, which is exactly the
/// case that used to break: `PLATFORM` fell back to its `desktop` default, so an
/// Android build reported `platform=desktop`, laid itself out as a desktop app
/// (`Layout.desktop` reads `BuildConfig.DESKTOP`), and skipped every
/// `BuildConfig.ANDROID` branch.
void main() {
  group('BuildConfig platform resolution without a PLATFORM define', () {
    test('resolves to the platform actually being run on', () {
      final expected = switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        TargetPlatform.windows => 'windows',
        TargetPlatform.linux => 'linux',
        TargetPlatform.macOS => 'macos',
        // Fuchsia is not a target this app ships, and BuildConfig has no
        // mapping for it, so the desktop default is the honest answer rather
        // than a claim about Fuchsia.
        TargetPlatform.fuchsia => 'desktop',
      };
      expect(BuildConfig.resolvedPlatform, expected);

      // The regression this file exists for: a real mobile target must never
      // report desktop. Asserted against the target rather than unconditionally
      // - the blanket isNot('desktop') contradicted the fuchsia arm above and
      // would have failed by construction if that arm were ever reached.
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        expect(BuildConfig.resolvedPlatform, isNot('desktop'));
      }
    });

    test('exactly one platform family is reported', () {
      final flags = [
        BuildConfig.ANDROID,
        BuildConfig.IOS,
        BuildConfig.WINDOWS,
        BuildConfig.LINUX,
        BuildConfig.MAC,
      ];
      expect(flags.where((flag) => flag).length, 1);
    });

    test('mobile and desktop are mutually exclusive and one is set', () {
      expect(BuildConfig.MOBILE && BuildConfig.DESKTOP, isFalse);
      expect(BuildConfig.MOBILE || BuildConfig.DESKTOP, isTrue);
    });

    test('platformDisplay agrees with the resolved platform', () {
      expect(BuildConfig.platformDisplay, BuildConfig.resolvedPlatform);
    });

    test('appName follows the resolved platform rather than the default', () {
      // The old const chain pinned this to "for Desktop" on every build that
      // omitted the define, including Android ones.
      expect(BuildConfig.appName, contains(BuildConfig.app));
      if (BuildConfig.ANDROID) {
        expect(BuildConfig.appName, contains('Android'));
      }
      if (BuildConfig.WINDOWS) {
        expect(BuildConfig.appName, contains('Windows'));
      }
    });
  });
}
