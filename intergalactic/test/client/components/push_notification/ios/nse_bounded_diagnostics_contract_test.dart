import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sourceFile = [
    File('ios/InterGalactic Notification Extension/NotificationService.swift'),
    File(
      'intergalactic/ios/InterGalactic Notification Extension/NotificationService.swift',
    ),
  ].firstWhere((file) => file.existsSync());
  final source = sourceFile.readAsStringSync();

  test('event fetch count is bridged only in Developer Mode', () {
    expect(
      source,
      contains(
        'if rendering.developerMode { eventFetchAttempts = fetch.eventAttempts }',
      ),
    );
    expect(source, contains('eventAttempts += 1\n    task.resume()'));
    expect(source, contains('attempts=\\(fetchAttempts, privacy: .public)'));
  });

  test('unsupported-event family is a Developer Mode closed set', () {
    expect(
      source,
      contains(
        'rendering.developerMode\n          ? NSERender.unsupportedFamily(type: effectiveType)\n          : "unsupported_type"',
      ),
    );
    final family = source.substring(
      source.indexOf('static func unsupportedFamily(type:'),
      source.indexOf('/// The text presentation of a message'),
    );
    expect(
      family,
      contains('default: return type.hasPrefix("m.call.") ? "call" : "other"'),
    );
    expect(family, isNot(contains('logger.')));
  });

  test('backup prerequisite diagnostics remain behind Developer Mode', () {
    final decrypt = source.substring(
      source.indexOf(
        'guard developerMode else {\n      return .failure(NSEFailure(reason: "session_missing"',
      ),
      source.indexOf('defer { wipe(&privateKey) }'),
    );
    expect(decrypt, contains('backup_event_oversize'));
    expect(decrypt, contains('backup_version_unavailable'));
    expect(decrypt, contains('backup_key_unavailable'));
  });
}
