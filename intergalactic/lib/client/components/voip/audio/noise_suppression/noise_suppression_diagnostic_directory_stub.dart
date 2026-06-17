import 'package:intergalactic/client/bug_report/bug_report_models.dart';

const String noiseSuppressionDiagnosticManifestFileName =
    'capture-manifest.json';

class NoiseSuppressionDiagnosticReportBundle {
  const NoiseSuppressionDiagnosticReportBundle({
    required this.directoryPath,
    required this.directoryLabel,
    required this.metadata,
    required this.attachments,
    required this.userMessage,
    required this.hasWavArtifacts,
    required this.allWavArtifactsAttached,
    required this.totalWavBytes,
    required this.estimatedEncodedWavBytes,
  });

  final String directoryPath;
  final String directoryLabel;
  final Map<String, Object?> metadata;
  final List<BugReportAttachmentSummary> attachments;
  final String userMessage;
  final bool hasWavArtifacts;
  final bool allWavArtifactsAttached;
  final int totalWavBytes;
  final int estimatedEncodedWavBytes;
}

Future<String> createNoiseSuppressionDiagnosticDirectory({
  String? captureLabel,
  int stageMask = 0x0f,
  bool includeWasapiSidecar = true,
}) {
  throw UnsupportedError('RNNoise diagnostic WAV capture is Windows-only.');
}

Future<NoiseSuppressionDiagnosticReportBundle>
    collectNoiseSuppressionDiagnosticReportBundle({
  required String directoryPath,
}) {
  throw UnsupportedError('RNNoise diagnostic WAV capture is Windows-only.');
}
