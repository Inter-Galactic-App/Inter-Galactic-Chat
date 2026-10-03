import 'drift_quarantine_record.dart';

/// Pure reconciliation, not a native inventory or a cleanup capability.
/// Inputs are sensitive and must not be logged. The coordinator must separately
/// prove complete confined inventory, stable identity and trustworthy time.
DriftQuarantineRecord reconcileDriftQuarantineInventory({
  required DriftQuarantineRecord committed,
  required Iterable<DriftQuarantineCase> observations,
  required DateTime nowUtc,
  bool stateTrusted = false,
  bool inventoryTrusted = false,
  bool clockTrusted = false,
}) {
  void invalid() => throw const DriftQuarantineRecordException();
  if (!stateTrusted || !inventoryTrusted || !clockTrusted || !nowUtc.isUtc) {
    invalid();
  }
  // Bound iteration before building/validating the observation record.
  final bounded = <DriftQuarantineCase>[];
  for (final observation in observations) {
    if (bounded.length == DriftQuarantineRecord.maxCases) invalid();
    bounded.add(observation);
  }
  // Inventory observations are raw v2-shaped identity data, not imported
  // clock/fallback/history attestations. Reject such claims rather than using
  // them to replace an existing case or fabricate a newly mapped anchor.
  final scanned = DriftQuarantineRecord(bounded, version: 2);
  final remaining = {
    for (final item in scanned.cases) item.relativeEntry: item,
  };
  final result = <DriftQuarantineCase>[];
  for (final previous in committed.cases) {
    if (nowUtc.isBefore(previous.lastObservedUtc)) invalid();
    final observed = remaining.remove(previous.relativeEntry);
    if (observed == null) {
      // Missing from even a complete scan is not verified cleanup under the
      // writer gate. Keep history and pending attempts; never resolve here.
      result.add(previous);
      continue;
    }
    if (previous.caseId != observed.caseId ||
        previous.artifactGeneration != observed.artifactGeneration ||
        previous.activeAccountEntry != observed.activeAccountEntry ||
        previous.nativeIdentity == null ||
        previous.nativeIdentity != observed.nativeIdentity ||
        previous.phase == DriftQuarantinePhase.resolved) {
      invalid();
    }
    // Inventory must not replace age, notice receipts or cleanup disposition.
    result.add(previous.observe(nowUtc: nowUtc));
  }
  for (final observed in remaining.values) {
    // Legacy adoption begins now, not at mtime or a name-derived date. An
    // explicit new-migration mapping needs a separate reviewed transition.
    if (observed.firstDetectedUtc != nowUtc ||
        observed.lastObservedUtc != nowUtc ||
        !observed.legacyAgeUnknown ||
        observed.nativeIdentity == null ||
        observed.activeAccountEntry != null ||
        observed.firstNoticeRecorded ||
        observed.daySevenReminderRecorded ||
        observed.phase != DriftQuarantinePhase.unresolved ||
        observed.disposition != DriftQuarantineDisposition.none) {
      invalid();
    }
    // Higher-schema records require clock-shaped data even for a newly seen
    // unmapped case. The explicit pure conversion preserves observation age
    // and adds observed-only provenance, NOT trusted time or prior-anchor
    // absence. In v4 the fallback remains null/unknown; no start is minted.
    result.add(
      committed.version >= 3
          ? DriftQuarantineRecord([
              observed,
            ], version: 2).version3Candidate().cases.single
          : observed,
    );
  }
  final record = DriftQuarantineRecord(result, version: committed.version);
  record.encode(); // Also enforce total encoded-byte bounds before persistence.
  return record;
}
