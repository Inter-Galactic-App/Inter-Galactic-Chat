import 'package:intergalactic/client/bug_report/pending_crash_report.dart';

class PendingCrashReportStore {
  const PendingCrashReportStore();

  Future<void> record(
    PendingCrashReport report, {
    String? directoryPath,
  }) async {}

  void recordSync(
    PendingCrashReport report, {
    String? directoryPath,
  }) {}

  Future<PendingCrashReport?> readPending({String? directoryPath}) async {
    return null;
  }

  Future<void> clearPending({String? directoryPath}) async {}
}
