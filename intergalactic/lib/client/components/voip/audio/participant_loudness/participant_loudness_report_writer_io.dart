import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_report.dart';
import 'package:path_provider/path_provider.dart';

/// Folder under the application support directory that holds exported
/// measurement sessions.
const String participantLoudnessReportFolderName = 'participant-loudness';

/// Writes a sanitized measurement-session report and returns its path.
///
/// The report contains derived statistics and hashed keys only — no audio, no
/// raw identifiers — so it is safe to hand to another agent for review.
/// Returns null if the report could not be written.
Future<String?> writeParticipantLoudnessSessionReport(
  ParticipantLoudnessSessionReport report,
) async {
  try {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}'
      '$participantLoudnessReportFolderName',
    );
    await directory.create(recursive: true);

    const encoder = JsonEncoder.withIndent('  ');
    final file = File(
      '${directory.path}${Platform.pathSeparator}${report.suggestedFileName}',
    );
    await file.writeAsString('${encoder.convert(report.toJson())}\n');
    return file.path;
  } catch (_) {
    // Diagnostics export is best-effort; a failure here must never disturb a
    // call. The caller surfaces the null as "export failed" in the dev UI.
    return null;
  }
}
