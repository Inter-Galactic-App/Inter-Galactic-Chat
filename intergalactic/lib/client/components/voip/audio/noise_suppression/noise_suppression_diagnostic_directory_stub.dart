import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';

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
  int stageMask = 0x3ff,
  bool includeWasapiSidecar = true,
}) {
  throw UnsupportedError(
    'Audio pipeline diagnostic WAV capture is Windows-only.',
  );
}

Future<NoiseSuppressionDiagnosticReportBundle>
collectNoiseSuppressionDiagnosticReportBundle({required String directoryPath}) {
  throw UnsupportedError(
    'Audio pipeline diagnostic WAV capture is Windows-only.',
  );
}

Future<void> appendNoiseSuppressionDiagnosticStopMetadata({
  required String directoryPath,
  required NoiseSuppressionNativeStatus status,
}) async {
  // Diagnostic WAV capture is Windows-only; stopping a capture that never
  // started has nothing to annotate.
}
