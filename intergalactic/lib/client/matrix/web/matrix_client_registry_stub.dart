class MatrixClientRegistryPlatform {
  static Future<void> upsert(Map<String, dynamic> record) async {}

  static Future<void> remove(String clientId) async {}

  static Future<List<Map<String, dynamic>>> getStoredClients() async =>
      const <Map<String, dynamic>>[];

  static Future<Map<String, dynamic>> collectStorageDiagnostics() async => {
        'storageBackend': 'stub',
        'indexedDbAvailable': false,
        'navigatorStorageExists': false,
        'persisted': null,
        'persist': null,
      };
}
