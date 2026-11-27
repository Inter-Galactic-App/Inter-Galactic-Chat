class NseBackupVersionEntry {
  const NseBackupVersionEntry({required this.clientId, required this.version});

  final String clientId;
  final String version;
}

class NseBackupVersion {
  NseBackupVersion._();

  static Future<void> synchronize(
    Iterable<Future<NseBackupVersionEntry?>> entries,
  ) async {}
}
