@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the iOS app-extension version fields tied to `pubspec.yaml`.
///
/// The Runner target derives its build number from `$(FLUTTER_BUILD_NUMBER)`,
/// so it cannot drift. Every app extension (share, notification service)
/// hardcodes `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` instead, and an
/// appex whose build number disagrees with the host app is rejected at
/// submission - after the upload, not at build time.
///
/// `intergalactic/scripts/verify_release_identity.ps1` already checks this, but
/// nothing invokes it: it is not referenced by any workflow in
/// `.github/workflows/`, so it only runs when a release operator remembers.
/// This runs with the ordinary suite instead, and needs no CI minutes.
void main() {
  test('iOS project version fields match pubspec', () {
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue);

    final versionLine = pubspec.readAsLinesSync().firstWhere(
      (line) => line.startsWith('version:'),
    );
    final version = versionLine.split(':')[1].trim();
    final parts = version.split('+');
    expect(
      parts,
      hasLength(2),
      reason: 'pubspec version "$version" is not name+build',
    );
    final versionName = parts[0];
    final buildNumber = parts[1];

    final project = File('ios/Runner.xcodeproj/project.pbxproj');
    expect(project.existsSync(), isTrue);
    final text = project.readAsStringSync();

    final buildNumbers = RegExp(r'CURRENT_PROJECT_VERSION = ([^;]+);')
        .allMatches(text)
        .map((m) => m.group(1)!.trim().replaceAll('"', ''))
        .toList();
    expect(
      buildNumbers,
      isNotEmpty,
      reason:
          'no CURRENT_PROJECT_VERSION found - the project format changed '
          'and this test would otherwise pass vacuously',
    );
    for (final value in buildNumbers) {
      if (value == r'$(FLUTTER_BUILD_NUMBER)') continue;
      expect(
        value,
        buildNumber,
        reason:
            'a hardcoded CURRENT_PROJECT_VERSION is $value but pubspec '
            'says $buildNumber. Run scripts/verify_release_identity.ps1 '
            '-SyncIosProject, or bump it here.',
      );
    }

    final marketing = RegExp(
      r'MARKETING_VERSION = "([^"]+)";',
    ).allMatches(text).map((m) => m.group(1)!).toSet();
    expect(marketing, isNotEmpty);
    for (final value in marketing) {
      expect(
        value,
        versionName,
        reason: 'MARKETING_VERSION $value does not match pubspec $versionName',
      );
    }
  });
}
