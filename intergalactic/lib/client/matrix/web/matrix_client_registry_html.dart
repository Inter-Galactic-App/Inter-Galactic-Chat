import 'dart:async';
import 'dart:html' as html;

class MatrixClientRegistryPlatform {
  static const String _dbName = 'commet_client_registry';
  static const String _storeName = 'clients';
  static const int _dbVersion = 1;

  static Future<dynamic> _openDatabaseOrNull() async {
    final factory = html.window.indexedDB;
    if (factory == null) {
      return null;
    }

    return await factory.open(
      _dbName,
      version: _dbVersion,
      onUpgradeNeeded: (event) {
        final database = (event.target as dynamic).result;
        if (database.objectStoreNames?.contains(_storeName) != true) {
          database.createObjectStore(_storeName, keyPath: 'clientId');
        }
      },
    );
  }

  static Future<void> upsert(Map<String, dynamic> record) async {
    final database = await _openDatabaseOrNull();
    if (database == null) {
      return;
    }

    try {
      final transaction = database.transaction(_storeName, 'readwrite');
      final completed = _awaitTransaction(transaction);
      transaction.objectStore(_storeName).put(Map<String, dynamic>.from(record));
      await completed;
    } finally {
      database.close();
    }
  }

  static Future<void> remove(String clientId) async {
    final database = await _openDatabaseOrNull();
    if (database == null) {
      return;
    }

    try {
      final transaction = database.transaction(_storeName, 'readwrite');
      final completed = _awaitTransaction(transaction);
      transaction.objectStore(_storeName).delete(clientId);
      await completed;
    } finally {
      database.close();
    }
  }

  static Future<List<Map<String, dynamic>>> getStoredClients() async {
    final database = await _openDatabaseOrNull();
    if (database == null) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final transaction = database.transaction(_storeName, 'readonly');
      final completed = _awaitTransaction(transaction);
      final records = <Map<String, dynamic>>[];
      await for (final cursor
          in transaction.objectStore(_storeName).openCursor(autoAdvance: true)) {
        final record = _normalizeMap(cursor.value);
        if (record.isNotEmpty) {
          records.add(record);
        }
      }
      await completed;
      return records;
    } finally {
      database.close();
    }
  }

  static Future<Map<String, dynamic>> collectStorageDiagnostics() async {
    final diagnostics = <String, dynamic>{
      'storageBackend': 'indexeddb',
      'indexedDbAvailable': html.window.indexedDB != null,
      'navigatorStorageExists': false,
      'persisted': null,
      'persist': null,
      'registryDatabaseOpened': false,
    };

    try {
      final storage = html.window.navigator.storage;
      if (storage != null) {
        diagnostics['navigatorStorageExists'] = true;

        try {
          diagnostics['persisted'] = await storage.persisted();
        } catch (error) {
          diagnostics['persistedError'] = error.toString();
        }

        try {
          diagnostics['persist'] = await storage.persist();
        } catch (error) {
          diagnostics['persistError'] = error.toString();
        }
      }
    } catch (error) {
      diagnostics['storageError'] = error.toString();
    }

    try {
      final database = await _openDatabaseOrNull();
      diagnostics['registryDatabaseOpened'] = database != null;
      database?.close();
    } catch (error) {
      diagnostics['registryDatabaseError'] = error.toString();
    }

    return diagnostics;
  }

  static Future<void> _awaitTransaction(dynamic transaction) {
    final completer = Completer<void>();
    StreamSubscription? completeSubscription;
    StreamSubscription? errorSubscription;
    StreamSubscription? abortSubscription;

    Object _transactionError(String fallback) {
      try {
        final error = transaction.error;
        if (error != null) {
          return StateError(error.toString());
        }
      } catch (_) {}

      return StateError(fallback);
    }

    void cleanup() {
      completeSubscription?.cancel();
      errorSubscription?.cancel();
      abortSubscription?.cancel();
    }

    completeSubscription = transaction.onComplete.listen((_) {
      if (completer.isCompleted) {
        return;
      }

      cleanup();
      completer.complete();
    });

    errorSubscription = transaction.onError.listen((_) {
      if (completer.isCompleted) {
        return;
      }

      cleanup();
      completer.completeError(
        _transactionError('IndexedDB transaction failed.'),
      );
    });

    abortSubscription = transaction.onAbort.listen((_) {
      if (completer.isCompleted) {
        return;
      }

      cleanup();
      completer.completeError(
        _transactionError('IndexedDB transaction was aborted.'),
      );
    });

    return completer.future;
  }

  static Map<String, dynamic> _normalizeMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    return {};
  }
}
