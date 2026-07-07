import 'dart:html' as html;

import 'package:intergalactic/client/matrix/web/matrix_session_audit.dart';
import 'package:matrix/matrix.dart';

bool _didLogStorageDiagnostics = false;

Future<DatabaseApi> getMatrixDatabaseImplementation(String clientName) async {
  if (!_didLogStorageDiagnostics) {
    final storageDiagnostics = <String, Object?>{
      'navigatorStorageExists': false,
      'persisted': null,
      'persist': null,
    };

    try {
      final storage = html.window.navigator.storage;
      if (storage != null) {
        storageDiagnostics['navigatorStorageExists'] = true;

        try {
          storageDiagnostics['persisted'] = await storage.persisted();
        } catch (error) {
          storageDiagnostics['persisted'] = 'error: $error';
        }

        try {
          storageDiagnostics['persist'] = await storage.persist();
        } catch (error) {
          storageDiagnostics['persist'] = 'error: $error';
        }
      }
    } catch (error) {
      storageDiagnostics['persist'] = 'error: $error';
    }

    MatrixSessionAudit.record(
      'Web storage diagnostics: navigator.storage=${storageDiagnostics['navigatorStorageExists']}, persisted=${storageDiagnostics['persisted']}, persist=${storageDiagnostics['persist']}',
    );
    _didLogStorageDiagnostics = true;
  }

  return MatrixSdkDatabase.init(clientName);
}

Future<DatabaseApi?> getLegacyMatrixDatabaseImplementation(
    String clientName) async {
  return null;
}
