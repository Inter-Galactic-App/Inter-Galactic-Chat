class SoundboardCachePruneResult {
  const SoundboardCachePruneResult({
    required this.scannedFiles,
    required this.deletedFiles,
    required this.deletedBytes,
  });

  const SoundboardCachePruneResult.empty()
      : scannedFiles = 0,
        deletedFiles = 0,
        deletedBytes = 0;

  final int scannedFiles;
  final int deletedFiles;
  final int deletedBytes;

  bool get didDelete => deletedFiles > 0;
}
