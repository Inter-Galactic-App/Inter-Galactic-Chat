/// Pure B3 policy only. Not a filesystem capability or proof of safety.
///
/// The eventual coordinator must persist detection/notice state and prove the
/// predicates under one exclusion gate, then revalidate before native cleanup.
/// Nothing in this file opens a database, deletes data, logs, or accesses keys.
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_clock.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_record.dart';

enum DriftQuarantineAction { retain, attemptCleanup, resolved }

enum DriftQuarantineNotice { none, firstForeground, daySevenReminder }

enum DriftQuarantineReason {
  notForeground,
  untrustedState,
  untrustedClock,
  safetyBlocked,
  recoveryWindow,
  byteEquivalent,
  expiredOwnerPolicy,
  fallbackOwnerPolicy,
  absenceVerified,
}

/// New pure preparation only. Unlike the legacy civil-date helper below, this
/// route has no clockTrusted override. All time claims must bind the exact case
/// and current epoch; they are still contract data, not runtime capabilities.
DriftQuarantineDecision evaluateDriftQuarantineWithClock({
  required DriftQuarantineCase? item,
  required DriftQuarantineClockBinding currentBinding,
  required DriftQuarantinePreferredClockEvidence preferred,
  required DriftQuarantineSafety safety,
  DriftQuarantineOriginalAnchor originalAnchor =
      DriftQuarantineOriginalAnchor.unavailable,
  DriftQuarantineHighWaterEvidence? highWaterCommit,
  bool foreground = false,
  bool stateTrusted = false,
  bool absenceVerifiedUnderSameGate = false,
}) {
  DriftQuarantineDecision retain(
    DriftQuarantineReason reason, [
    DriftQuarantineNotice notice = DriftQuarantineNotice.none,
  ]) => DriftQuarantineDecision(DriftQuarantineAction.retain, reason, notice);
  if (!foreground) return retain(DriftQuarantineReason.notForeground);
  if (!stateTrusted || item == null) {
    return retain(DriftQuarantineReason.untrustedState);
  }
  // Interruption forbids presentation/acknowledgement even when its evidence
  // binding is stale and the pure clock evaluator would classify unavailable.
  if (preferred.outcome == DriftQuarantinePreferredClock.interrupted) {
    return retain(DriftQuarantineReason.untrustedClock);
  }
  // A generic first warning needs a valid record/usable account, not an elapsed
  // interval. Unknown timing must not hide the retained-data uncertainty notice.
  final firstNotice =
      safety.associatedAccountUsable && !item.firstNoticeRecorded
      ? DriftQuarantineNotice.firstForeground
      : DriftQuarantineNotice.none;
  final clock = evaluateDriftQuarantineClock(
    item: item,
    currentBinding: currentBinding,
    preferred: preferred,
    originalAnchor: originalAnchor,
    highWaterCommit: highWaterCommit,
  );
  if (clock.kind == DriftQuarantineClockVerdictKind.interrupted) {
    return retain(DriftQuarantineReason.untrustedClock);
  }
  if (clock.kind == DriftQuarantineClockVerdictKind.unavailable) {
    // No day-seven elapsed claim, absence resolution or cleanup eligibility.
    return retain(DriftQuarantineReason.untrustedClock, firstNotice);
  }
  final notice = !safety.associatedAccountUsable
      ? DriftQuarantineNotice.none
      : !item.firstNoticeRecorded
      ? DriftQuarantineNotice.firstForeground
      : preferred.outcome == DriftQuarantinePreferredClock.trustedInterval &&
            clock.elapsed! >= const Duration(days: 7) &&
            !item.daySevenReminderRecorded
      ? DriftQuarantineNotice.daySevenReminder
      : DriftQuarantineNotice.none;
  if (!safety.permitsAttempt) {
    return DriftQuarantineDecision(
      DriftQuarantineAction.retain,
      DriftQuarantineReason.safetyBlocked,
      notice,
    );
  }
  if (absenceVerifiedUnderSameGate) {
    return const DriftQuarantineDecision(
      DriftQuarantineAction.resolved,
      DriftQuarantineReason.absenceVerified,
      DriftQuarantineNotice.none,
    );
  }
  if (clock.kind == DriftQuarantineClockVerdictKind.trustedExpiry ||
      clock.kind == DriftQuarantineClockVerdictKind.fallbackExpiry) {
    return DriftQuarantineDecision(
      DriftQuarantineAction.attemptCleanup,
      clock.kind == DriftQuarantineClockVerdictKind.trustedExpiry
          ? DriftQuarantineReason.expiredOwnerPolicy
          : DriftQuarantineReason.fallbackOwnerPolicy,
      notice,
    );
  }
  if (safety.byteEquivalentUnderSameGate) {
    return DriftQuarantineDecision(
      DriftQuarantineAction.attemptCleanup,
      DriftQuarantineReason.byteEquivalent,
      notice,
    );
  }
  return DriftQuarantineDecision(
    DriftQuarantineAction.retain,
    DriftQuarantineReason.recoveryWindow,
    notice,
  );
}

/// Evidence supplied by a future confined I/O coordinator. Defaults deny.
/// Booleans are not themselves evidence and must never come from UI/preferences.
class DriftQuarantineSafety {
  const DriftQuarantineSafety({
    this.associatedActiveDatabaseOpen = false,
    this.associatedAccountUsable = false,
    this.exactArtifactIdentity = false,
    this.confinedSingleDatabaseFileSet = false,
    this.nativeProtectionVerified = false,
    this.writersAndMigrationQuiescent = false,
    this.byteEquivalentUnderSameGate = false,
  });

  final bool associatedActiveDatabaseOpen;
  final bool associatedAccountUsable;
  final bool exactArtifactIdentity;
  final bool confinedSingleDatabaseFileSet;
  final bool nativeProtectionVerified;
  final bool writersAndMigrationQuiescent;
  final bool byteEquivalentUnderSameGate;

  bool get permitsAttempt =>
      associatedActiveDatabaseOpen &&
      associatedAccountUsable &&
      exactArtifactIdentity &&
      confinedSingleDatabaseFileSet &&
      nativeProtectionVerified &&
      writersAndMigrationQuiescent;
}

class DriftQuarantineDecision {
  const DriftQuarantineDecision(this.action, this.reason, this.notice);

  final DriftQuarantineAction action;
  final DriftQuarantineReason reason;
  final DriftQuarantineNotice notice;
}

/// Calendar-day model: UTC civil dates, independent of device timezone/DST.
/// [firstDetectedUtc] is immutable first trustworthy detection, never file mtime.
/// Unknown legacy age must be adopted once by the future durable-state layer.
/// A caller must establish clock trust separately: monotonic comparisons cannot
/// detect an arbitrary forward wall-clock jump. These pure inputs do not do so.
DriftQuarantineDecision evaluateDriftQuarantine({
  required DateTime firstDetectedUtc,
  required DateTime lastObservedUtc,
  required DateTime nowUtc,
  required DriftQuarantineSafety safety,
  bool foreground = false,
  bool stateTrusted = false,
  bool clockTrusted = false,
  bool absenceVerifiedUnderSameGate = false,
  bool firstNoticeRecorded = false,
  bool daySevenReminderRecorded = false,
}) {
  DriftQuarantineDecision retain(DriftQuarantineReason reason) =>
      DriftQuarantineDecision(
        DriftQuarantineAction.retain,
        reason,
        DriftQuarantineNotice.none,
      );

  if (!foreground) return retain(DriftQuarantineReason.notForeground);
  if (!stateTrusted) return retain(DriftQuarantineReason.untrustedState);
  if (!clockTrusted ||
      !firstDetectedUtc.isUtc ||
      !lastObservedUtc.isUtc ||
      !nowUtc.isUtc ||
      lastObservedUtc.isBefore(firstDetectedUtc) ||
      nowUtc.isBefore(lastObservedUtc)) {
    return retain(DriftQuarantineReason.untrustedClock);
  }

  // Absence must be proved for this case under the confined gate, not inferred
  // from a persisted "resolved" or migration "complete" label.
  if (absenceVerifiedUnderSameGate) {
    return const DriftQuarantineDecision(
      DriftQuarantineAction.resolved,
      DriftQuarantineReason.absenceVerified,
      DriftQuarantineNotice.none,
    );
  }

  DateTime civilDate(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  final days = civilDate(nowUtc).difference(civilDate(firstDetectedUtc)).inDays;
  final notice = !safety.associatedAccountUsable
      ? DriftQuarantineNotice.none
      : !firstNoticeRecorded
      ? DriftQuarantineNotice.firstForeground
      : days >= 7 && !daySevenReminderRecorded
      ? DriftQuarantineNotice.daySevenReminder
      : DriftQuarantineNotice.none;

  if (!safety.permitsAttempt) {
    return DriftQuarantineDecision(
      DriftQuarantineAction.retain,
      DriftQuarantineReason.safetyBlocked,
      notice,
    );
  }
  // Expiry is mandatory, including divergent data; reevaluation retries until
  // verified absent. No "pending"/dismissed flag can suppress or bypass it.
  if (days >= 30) {
    return DriftQuarantineDecision(
      DriftQuarantineAction.attemptCleanup,
      DriftQuarantineReason.expiredOwnerPolicy,
      notice,
    );
  }
  if (safety.byteEquivalentUnderSameGate) {
    return DriftQuarantineDecision(
      DriftQuarantineAction.attemptCleanup,
      DriftQuarantineReason.byteEquivalent,
      notice,
    );
  }
  return DriftQuarantineDecision(
    DriftQuarantineAction.retain,
    DriftQuarantineReason.recoveryWindow,
    notice,
  );
}
