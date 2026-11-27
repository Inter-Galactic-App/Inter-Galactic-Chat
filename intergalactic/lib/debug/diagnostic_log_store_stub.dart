class DiagnosticLogStore {
  bool get isInitialized => false;

  String? get logDirectoryPath => null;

  Future<void> initialize({
    String? directoryPath,
    int maxFileBytes = 5 * 1024 * 1024,
    int maxFiles = 10,
    int maxTotalBytes = 25 * 1024 * 1024,
    Duration retention = const Duration(days: 14),
  }) async {}

  Future<void> append(String line, {bool flush = false}) async {}

  void appendSync(String line) {}

  Future<void> flush() async {}

  Future<String> recentText({int maxBytes = 200 * 1024}) async {
    return '';
  }

  Future<void> clear() async {}
}
