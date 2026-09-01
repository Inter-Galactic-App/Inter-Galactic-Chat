import 'package:intergalactic/client/bug_report/pending_crash_report.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report_store.dart';
import 'package:intergalactic/config/platform_utils.dart';

class PendingNativeCallCrashGuard {
  const PendingNativeCallCrashGuard._({
    required this.source,
    required this.store,
  });

  final String source;
  final PendingCrashReportStore store;

  static Future<PendingNativeCallCrashGuard?> record({
    required String source,
    required String callKind,
    PendingCrashReportStore store = const PendingCrashReportStore(),
  }) async {
    if (PlatformUtils.isWeb) {
      return null;
    }

    await store.record(
      PendingCrashReport.nativeCallJoinGuard(
        source: source,
        callKind: callKind,
      ),
    );
    return PendingNativeCallCrashGuard._(source: source, store: store);
  }

  static Future<PendingNativeCallCrashGuard?> recordAction({
    required String source,
    required String actionKind,
    PendingCrashReportStore store = const PendingCrashReportStore(),
  }) async {
    if (PlatformUtils.isWeb) {
      return null;
    }

    await store.record(
      PendingCrashReport.nativeCallActionGuard(
        source: source,
        actionKind: actionKind,
      ),
    );
    return PendingNativeCallCrashGuard._(source: source, store: store);
  }

  Future<void> clear() {
    return store.clearPendingFromSource(source);
  }
}
