import 'package:flutter_test/flutter_test.dart';

import '../../scripts/build_release.dart' as buildRelease;

void main() {
  group('getAndroidTargetPlatform', () {
    test('defaults to the supported universal phone ABI set', () {
      expect(
        buildRelease.getAndroidTargetPlatform(
          const [],
          environment: const <String, String>{},
        ),
        'android-arm,android-arm64',
      );
    });

    test('accepts the explicit supported ABI set in both argument forms', () {
      expect(
        buildRelease.getAndroidTargetPlatform(
          const ['--target_platform=android-arm,android-arm64'],
          environment: const <String, String>{
            'INTERGALACTIC_ANDROID_TARGET_PLATFORM': 'android-arm64',
          },
        ),
        'android-arm,android-arm64',
      );
      expect(
        buildRelease.getAndroidTargetPlatform(
          const ['--target_platform', 'android-arm,android-arm64'],
          environment: const <String, String>{
            'INTERGALACTIC_ANDROID_TARGET_PLATFORM': 'android-arm64',
          },
        ),
        'android-arm,android-arm64',
      );
    });

    test('accepts only the supported environment ABI set', () {
      expect(
        buildRelease.getAndroidTargetPlatform(
          const [],
          environment: const <String, String>{
            'INTERGALACTIC_ANDROID_TARGET_PLATFORM':
                'android-arm,android-arm64',
          },
        ),
        'android-arm,android-arm64',
      );
      expect(
        () => buildRelease.getAndroidTargetPlatform(
          const [],
          environment: const <String, String>{
            'INTERGALACTIC_ANDROID_TARGET_PLATFORM': 'android-arm64',
          },
        ),
        throwsArgumentError,
      );
    });

    test('rejects unsupported single-ABI and emulator release artifacts', () {
      expect(
        () => buildRelease.getAndroidTargetPlatform(const [
          '--target_platform=android-arm64',
        ]),
        throwsArgumentError,
      );
      expect(
        () => buildRelease.getAndroidTargetPlatform(const [
          '--target_platform=android-x64',
        ]),
        throwsArgumentError,
      );
    });
  });

  group('getVersionTag', () {
    test('reads the tag in both argument forms', () {
      expect(
        buildRelease.getVersionTag(const ['--version_tag=v0.8.1+1003']),
        'v0.8.1+1003',
      );
      expect(
        buildRelease.getVersionTag(const ['--version_tag', 'v0.8.1+1003']),
        'v0.8.1+1003',
      );
    });

    // The regression this guards: the missing flag used to return "v0.0.0+0",
    // and an iOS build then wrote that placeholder into the Broadcast
    // Extension fields in project.pbxproj and archived it. A release candidate
    // that carries 0.0.0+0 must not be producible by forgetting an argument.
    test('refuses to default when the flag is absent', () {
      expect(() => buildRelease.getVersionTag(const []), throwsArgumentError);
      expect(
        () => buildRelease.getVersionTag(const ['--platform', 'ios']),
        throwsArgumentError,
      );
    });

    test('names the flag in the failure message', () {
      expect(
        () => buildRelease.getVersionTag(const []),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(contains('--version_tag'), isNot(contains('0.0.0'))),
          ),
        ),
      );
    });
  });

  group('getEnableNativeDetachedCallWindows', () {
    test('defaults to true with no argument and no environment', () {
      expect(
        buildRelease.getEnableNativeDetachedCallWindows(
          const [],
          environment: const <String, String>{},
        ),
        'true',
      );
    });

    test('accepts an explicit false in both argument forms', () {
      expect(
        buildRelease.getEnableNativeDetachedCallWindows(const [
          '--enable_native_detached_call_windows=false',
        ], environment: const <String, String>{}),
        'false',
      );
      // The space-separated branch of the shared parser, asserted separately
      // so a regression there cannot hide behind a green `=` form.
      expect(
        buildRelease.getEnableNativeDetachedCallWindows(const [
          '--enable_native_detached_call_windows',
          'false',
        ], environment: const <String, String>{}),
        'false',
      );
    });

    test('the CLI argument wins over the environment', () {
      expect(
        buildRelease.getEnableNativeDetachedCallWindows(
          const ['--enable_native_detached_call_windows=false'],
          environment: const <String, String>{
            'ENABLE_NATIVE_DETACHED_CALL_WINDOWS': 'true',
          },
        ),
        'false',
      );
    });

    test('reads the environment when no argument is given', () {
      expect(
        buildRelease.getEnableNativeDetachedCallWindows(
          const [],
          environment: const <String, String>{
            'ENABLE_NATIVE_DETACHED_CALL_WINDOWS': 'false',
          },
        ),
        'false',
      );
    });

    // The whole point of validating. The value becomes a --dart-define, and
    // bool.fromEnvironment reads anything that is not exactly "true" as false -
    // so every one of these would previously have shipped a release with the
    // feature silently off.
    // An empty value is deliberately absent from this list: `getArg` rejects
    // `--flag=` itself, with `exit(64)`, before this validator is reached. That
    // is the right behaviour for a CLI and the wrong thing to assert here -
    // calling it kills the test process, taking the rest of the file with it.
    test('rejects anything that is not exactly true or false', () {
      for (final bad in const ['1', '0', 'ture', 'True', 'FALSE', ' true']) {
        expect(
          () => buildRelease.getEnableNativeDetachedCallWindows([
            '--enable_native_detached_call_windows=$bad',
          ], environment: const <String, String>{}),
          throwsArgumentError,
          reason: 'value "$bad" must be rejected',
        );
      }
    });

    test('rejects a bad environment value too', () {
      expect(
        () => buildRelease.getEnableNativeDetachedCallWindows(
          const [],
          environment: const <String, String>{
            'ENABLE_NATIVE_DETACHED_CALL_WINDOWS': 'yes',
          },
        ),
        throwsArgumentError,
      );
    });
  });
}
