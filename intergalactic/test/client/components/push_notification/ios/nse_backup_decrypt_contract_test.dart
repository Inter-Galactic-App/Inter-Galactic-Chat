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

  test(
    'backup recovery is ordered after local session miss and developer gate',
    () {
      final decrypt = source.substring(source.indexOf('enum NSEDecrypt'));
      final localLookup = decrypt.indexOf('database.sessionPickle(');
      final developerGate = decrypt.indexOf('guard developerMode else');
      final keyRead = decrypt.indexOf('database.backupPrivateKey()');
      final backupFetch = decrypt.indexOf('fetch.backupSession(');

      expect(localLookup, greaterThanOrEqualTo(0));
      expect(developerGate, greaterThan(localLookup));
      expect(keyRead, greaterThan(developerGate));
      expect(backupFetch, greaterThan(keyRead));
    },
  );

  test('SSSS read is exact and the account database remains read only', () {
    expect(
      source,
      contains('SELECT content FROM s_s_s_s_cache_data WHERE type = ? LIMIT 2'),
    );
    expect(source, contains('sqlite3_bind_text(stmt, 1, "m.megolm_backup.v1"'));
    expect(source, contains('SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX'));
    expect(
      source,
      isNot(contains('SELECT content FROM s_s_s_s_cache_data LIMIT')),
    );
  });

  test('backup request is the single bounded E1-E4 endpoint', () {
    expect(
      source,
      contains('"/_matrix/client/v3/room_keys/keys/\\(room)/\\(session)"'),
    );
    expect(
      source,
      contains(
        'components.queryItems = [URLQueryItem(name: "version", value: version)]',
      ),
    );
    expect(source, isNot(contains('/_matrix/client/v3/room_keys/version')));
    expect(
      source,
      contains('private static let maxBackupBodyBytes = 64 * 1024'),
    );
    expect(source, contains('URLSessionConfiguration.ephemeral'));
    expect(source, contains('configuration.httpShouldSetCookies = false'));
    expect(source, contains('configuration.urlCache = nil'));
    expect(source, contains('backupFetchFailureClass(failure)'));
    expect(source, contains('return "backup_fetch_http"'));
    expect(source, contains('return "backup_fetch_body"'));
    expect(source, contains('return "backup_fetch_transport"'));
    expect(source, contains('return "backup_fetch_budget"'));
    expect(source, contains('return "backup_fetch_failed"'));
    expect(
      source,
      contains('NSEFailure(reason: backupFetchFailureClass(failure), code: 0)'),
    );
  });

  test(
    'combined wrapper ABI returns only event plaintext and is always freed',
    () {
      expect(source, contains('ios_decrypt_backup_event_v1('));
      expect(source, contains('ios_backup_event_decrypt_result_free(result)'));
      expect(
        source,
        contains('result.plaintext_len <= maxEventPlaintextBytes'),
      );
      expect(source, isNot(contains('ios_decrypt_backup_v1(')));
    },
  );

  test('success provenance is identifier free and distinguishes the path', () {
    expect(source, contains('enum Source: String'));
    expect(source, contains('source: .local'));
    expect(source, contains('source: .backup'));
    expect(source, contains('decryptSource = decrypted.source.rawValue'));
    expect(source, contains(r'decrypt=\(decryptSource, privacy: .public)'));
  });
}
