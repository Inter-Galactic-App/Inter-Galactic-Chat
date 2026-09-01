import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_report.dart';

/// Web builds have no writable diagnostics folder, so the export is reported
/// as unsupported rather than silently doing nothing.
Future<String?> writeParticipantLoudnessSessionReport(
  ParticipantLoudnessSessionReport report,
) async {
  return null;
}
