class StreamTestLoadedLibwebrtcArtifact {
  const StreamTestLoadedLibwebrtcArtifact({
    required this.fileName,
    required this.location,
    required this.sha256,
    required this.sizeBytes,
    required this.modifiedAtUtc,
  });

  final String fileName;
  final String location;
  final String sha256;
  final int sizeBytes;
  final DateTime modifiedAtUtc;

  String get shortSha256 {
    if (sha256.length <= 12) {
      return sha256;
    }
    return sha256.substring(0, 12);
  }

  String get diagnosticLabel =>
      '$fileName digest=$shortSha256 size=$sizeBytes bytes source=$location';

  Map<String, Object?> toJson() {
    return {
      'fileName': fileName,
      'location': location,
      'sha256': sha256,
      'shortSha256': shortSha256,
      'sizeBytes': sizeBytes,
      'modifiedAt': modifiedAtUtc.toIso8601String(),
    };
  }
}
