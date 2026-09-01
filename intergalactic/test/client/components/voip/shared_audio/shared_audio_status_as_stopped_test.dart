@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fails when a field is added to `SharedAudioCaptureStatus` and `asStopped()`
/// is not updated to carry it.
///
/// `asStopped()` re-lists all seventeen constructor arguments by hand. Every
/// one of them is optional with a default, so omitting the new one compiles,
/// analyzes clean, and silently returns a stopped status missing part of the
/// diagnosis - which is the exact outcome that method's doc comment says it
/// exists to prevent.
///
/// Expressing `asStopped()` through a `copyWith` was considered and rejected:
/// a hand-written `copyWith` re-lists the same seventeen fields with the same
/// defaults, so it relocates the hazard rather than removing it. Dart has no
/// runtime reflection to enumerate them instead, so this reads the declaration
/// out of the source and checks the body against it. That is coarse - it
/// matches on names, not on data flow, so `sampleRateHz: 0` would satisfy it -
/// but the failure it is built for is an OMITTED field, and it catches that.
void main() {
  test('asStopped carries every constructor field', () {
    final source = File(
      'lib/client/components/voip/shared_audio/shared_audio_backend.dart',
    );
    expect(source.existsSync(), isTrue);
    final text = source.readAsStringSync();

    final constructor = RegExp(
      r'const SharedAudioCaptureStatus\(\{(.*?)\}\);',
      dotAll: true,
    ).firstMatch(text);
    expect(
      constructor,
      isNotNull,
      reason:
          'the primary SharedAudioCaptureStatus constructor was not found - '
          'the declaration moved and this gate is no longer reading it',
    );

    final fields = RegExp(r'this\.(\w+)')
        .allMatches(constructor!.group(1)!)
        .map((match) => match.group(1)!)
        .toSet();
    expect(
      fields.length,
      greaterThanOrEqualTo(17),
      reason:
          'only ${fields.length} fields parsed out of the constructor; the '
          'parse broke and this test would otherwise pass vacuously',
    );

    final body = RegExp(
      r'SharedAudioCaptureStatus asStopped\(\) \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(text);
    expect(body, isNotNull, reason: 'asStopped() was not found');
    final assigned = RegExp(
      r'^\s{6}(\w+):',
      multiLine: true,
    ).allMatches(body!.group(1)!).map((match) => match.group(1)!).toSet();

    final missing = fields.difference(assigned);
    expect(
      missing,
      isEmpty,
      reason:
          'asStopped() does not pass $missing, so a stopped status drops it. '
          'Add each one to the call, or - if it genuinely must reset on stop - '
          'pass it explicitly so the omission is a decision rather than an '
          'oversight.',
    );
  });
}
