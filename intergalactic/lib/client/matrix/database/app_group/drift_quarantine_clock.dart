import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_record.dart';

/// Explicit INPUT claims only. No enum, tuple or token validates native state.
enum DriftQuarantineMappingHistory {
  intact,
  missing,
  corrupt,
  pending,
  wholeStateLost,
  conflicting,
}

enum DriftQuarantinePriorFallback { unknown, provenAbsent, existing }

enum DriftQuarantineMappingMembership {
  completeIntroductionRoster,
  recordedNewCreation,
  lateObserved,
  partialRoster,
  unclassified,
}

bool _mappingOpaque(String value) => RegExp(r'^[0-9a-f]{32}$').hasMatch(value);
bool _mappingTime(DateTime value) =>
    value.isUtc &&
    value.millisecondsSinceEpoch >= 0 &&
    value.millisecondsSinceEpoch <= driftQuarantineMaxUtcMilliseconds &&
    value.microsecondsSinceEpoch % 1000 == 0;
Never _mappingInvalid() => throw const DriftQuarantineRecordException();
List<int>? _mappingBytes(List<int>? bytes) {
  if (bytes == null) return null;
  if (bytes.length > DriftQuarantineRecord.maxBytes) _mappingInvalid();
  final copy = List<int>.unmodifiable(bytes);
  DriftQuarantineRecord.decode(copy);
  return copy;
}

List<DriftQuarantineMappingCaseIdentity> _mappingRoster(
  Iterable<DriftQuarantineMappingCaseIdentity> entries,
) {
  final copy = <DriftQuarantineMappingCaseIdentity>[];
  for (final entry in entries) {
    if (copy.length == DriftQuarantineRecord.maxCases) _mappingInvalid();
    copy.add(entry);
  }
  return List.unmodifiable(copy);
}

bool _mappingBytesEqual(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class DriftQuarantineMappingCaseIdentity {
  DriftQuarantineMappingCaseIdentity({
    required this.caseId,
    required this.artifactGeneration,
    required this.nativeIdentity,
  }) {
    if (!_mappingOpaque(caseId) || !_mappingOpaque(artifactGeneration)) {
      _mappingInvalid();
    }
  }
  final String caseId;
  final String artifactGeneration;
  final DriftQuarantineNativeIdentity nativeIdentity;
  bool matches(DriftQuarantineMappingCaseIdentity other) =>
      caseId == other.caseId &&
      artifactGeneration == other.artifactGeneration &&
      nativeIdentity == other.nativeIdentity;
  bool matchesCase(DriftQuarantineCase item) =>
      caseId == item.caseId &&
      artifactGeneration == item.artifactGeneration &&
      nativeIdentity == item.nativeIdentity;
}

/// Bounded, immutable representation of ONE claimed protected snapshot.
/// A future separately reviewed binder must prove each value under exclusion;
/// a caller constructing this object has obtained NO runtime capability.
class DriftQuarantineMappingSnapshot {
  DriftQuarantineMappingSnapshot({
    required List<int>? committedBytes,
    required List<int>? pendingBytes,
    required this.recordGeneration,
    required this.evidenceEpoch,
    required this.caseIdentity,
    required this.accountIdentity,
    required this.accountEntry,
    required this.introductionIdentity,
    required this.introductionUtc,
    required this.witnessGeneration,
    required this.historyGeneration,
    required this.history,
    required this.priorFallback,
    required this.membership,
    required Iterable<DriftQuarantineMappingCaseIdentity> introductionRoster,
    this.creationObservedUtc,
  }) : committedBytes = _mappingBytes(committedBytes),
       pendingBytes = _mappingBytes(pendingBytes),
       introductionRoster = _mappingRoster(introductionRoster) {
    if (![
          recordGeneration,
          evidenceEpoch,
          accountIdentity,
          introductionIdentity,
        ].every(_mappingOpaque) ||
        (witnessGeneration != null && !_mappingOpaque(witnessGeneration!)) ||
        (historyGeneration != null && !_mappingOpaque(historyGeneration!)) ||
        accountEntry.isEmpty ||
        accountEntry.length > 255 ||
        accountEntry == '.' ||
        accountEntry == '..' ||
        RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(accountEntry) ||
        !_mappingTime(introductionUtc) ||
        (creationObservedUtc != null && !_mappingTime(creationObservedUtc!)) ||
        this.introductionRoster.length > DriftQuarantineRecord.maxCases) {
      _mappingInvalid();
    }
    final ids = <String>{};
    final generations = <String>{};
    final directories = <DriftQuarantineFileIdentity>{};
    final databases = <DriftQuarantineFileIdentity>{};
    for (final entry in this.introductionRoster) {
      if (!ids.add(entry.caseId) ||
          !generations.add(entry.artifactGeneration) ||
          !directories.add(entry.nativeIdentity.directory) ||
          !databases.add(entry.nativeIdentity.database))
        _mappingInvalid();
    }
  }
  final List<int>? committedBytes;
  final List<int>? pendingBytes;
  final String recordGeneration;
  final String evidenceEpoch;
  final DriftQuarantineMappingCaseIdentity caseIdentity;
  final String accountIdentity;
  final String accountEntry;
  final String introductionIdentity;
  final DateTime introductionUtc;
  final String? witnessGeneration;
  final String? historyGeneration;
  final DriftQuarantineMappingHistory history;
  // Missing serialized fields MUST NOT produce provenAbsent.
  final DriftQuarantinePriorFallback priorFallback;
  final DriftQuarantineMappingMembership membership;
  final List<DriftQuarantineMappingCaseIdentity> introductionRoster;
  final DateTime? creationObservedUtc;

  bool matches(DriftQuarantineMappingSnapshot other) {
    if (!_mappingBytesEqual(committedBytes, other.committedBytes) ||
        !_mappingBytesEqual(pendingBytes, other.pendingBytes) ||
        recordGeneration != other.recordGeneration ||
        evidenceEpoch != other.evidenceEpoch ||
        !caseIdentity.matches(other.caseIdentity) ||
        accountIdentity != other.accountIdentity ||
        accountEntry != other.accountEntry ||
        introductionIdentity != other.introductionIdentity ||
        introductionUtc != other.introductionUtc ||
        witnessGeneration != other.witnessGeneration ||
        historyGeneration != other.historyGeneration ||
        history != other.history ||
        priorFallback != other.priorFallback ||
        membership != other.membership ||
        creationObservedUtc != other.creationObservedUtc ||
        introductionRoster.length != other.introductionRoster.length)
      return false;
    for (var i = 0; i < introductionRoster.length; i++) {
      if (!introductionRoster[i].matches(other.introductionRoster[i]))
        return false;
    }
    return true;
  }

  DriftQuarantineCase? get boundCase {
    if (committedBytes == null ||
        pendingBytes != null ||
        history != DriftQuarantineMappingHistory.intact ||
        witnessGeneration == null ||
        historyGeneration == null)
      return null;
    final record = DriftQuarantineRecord.decode(committedBytes!);
    for (final item in record.cases) {
      if (caseIdentity.matchesCase(item) &&
          item.activeAccountEntry == accountEntry &&
          item.clockState != null &&
          item.phase != DriftQuarantinePhase.cleanupPending &&
          item.phase != DriftQuarantinePhase.resolved)
        return item;
    }
    return null;
  }
}

/// Expected and replacement bytes for a future exact-byte CAS. No write occurs.
class DriftQuarantineFallbackCandidate {
  DriftQuarantineFallbackCandidate._(this.snapshot, this.record)
    : expectedBytes = List.unmodifiable(snapshot.committedBytes!),
      replacementBytes = List.unmodifiable(record.encode());
  final DriftQuarantineMappingSnapshot snapshot;
  final DriftQuarantineRecord record;
  final List<int> expectedBytes;
  final List<int> replacementBytes;

  /// Checks a supplied CAS receipt, NOT a native CAS implementation/proof.
  bool acceptsCommit({
    required DriftQuarantineMappingSnapshot currentSnapshot,
    required List<int> expected,
    required List<int> replacement,
    required DriftQuarantineHighWaterCommit outcome,
    required bool interrupted,
  }) =>
      !interrupted &&
      outcome == DriftQuarantineHighWaterCommit.committed &&
      snapshot.matches(currentSnapshot) &&
      _mappingBytesEqual(expectedBytes, expected) &&
      _mappingBytesEqual(replacementBytes, replacement);
}

/// Pure v4 mapping candidate. No decoding default proves prior-anchor absence.
DriftQuarantineFallbackCandidate? prepareDriftQuarantineFallback({
  required DriftQuarantineMappingSnapshot snapshot,
  required DriftQuarantineMappingSnapshot currentSnapshot,
  required DateTime observedUtc,
  required bool interrupted,
}) {
  if (!_mappingTime(observedUtc)) _mappingInvalid();
  if (interrupted || !snapshot.matches(currentSnapshot)) return null;
  final item = snapshot.boundCase;
  if (item == null) return null;
  final existing = item.fallbackState;
  final original = DriftQuarantineRecord.decode(snapshot.committedBytes!);
  if (existing != null) {
    if (snapshot.priorFallback != DriftQuarantinePriorFallback.existing ||
        existing.accountIdentity != snapshot.accountIdentity ||
        existing.introductionIdentity != snapshot.introductionIdentity ||
        existing.introductionUtc != snapshot.introductionUtc)
      return null;
    // Never renew on discovery, rollback, restart, sign-in or a later update.
    return DriftQuarantineFallbackCandidate._(snapshot, original);
  }
  if (snapshot.priorFallback != DriftQuarantinePriorFallback.provenAbsent)
    return null;
  late DriftQuarantineFallbackOrigin origin;
  late DateTime start;
  final rosterAlias = snapshot.introductionRoster.any(
    (entry) =>
        entry.caseId == item.caseId ||
        entry.artifactGeneration == item.artifactGeneration ||
        entry.nativeIdentity.directory == item.nativeIdentity!.directory ||
        entry.nativeIdentity.database == item.nativeIdentity!.database,
  );
  switch (snapshot.membership) {
    case DriftQuarantineMappingMembership.completeIntroductionRoster:
      if (!snapshot.introductionRoster.any(snapshot.caseIdentity.matches))
        return null;
      origin = DriftQuarantineFallbackOrigin.introductionRoster;
      start = snapshot.introductionUtc;
    case DriftQuarantineMappingMembership.recordedNewCreation:
      final creation = snapshot.creationObservedUtc;
      if (creation == null || rosterAlias) return null;
      origin = DriftQuarantineFallbackOrigin.newCreation;
      start = creation.isAfter(snapshot.introductionUtc)
          ? creation
          : snapshot.introductionUtc;
    case DriftQuarantineMappingMembership.lateObserved:
      if (rosterAlias) return null;
      origin = DriftQuarantineFallbackOrigin.lateObserved;
      final highWater = item.clockState!.observedHighWaterUtc;
      start = observedUtc.isAfter(highWater) ? observedUtc : highWater;
    case DriftQuarantineMappingMembership.partialRoster:
    case DriftQuarantineMappingMembership.unclassified:
      return null;
  }
  final state = DriftQuarantineFallbackState(
    caseId: item.caseId,
    artifactGeneration: item.artifactGeneration,
    nativeIdentity: item.nativeIdentity!,
    accountIdentity: snapshot.accountIdentity,
    accountEntry: snapshot.accountEntry,
    introductionIdentity: snapshot.introductionIdentity,
    introductionUtc: snapshot.introductionUtc,
    startUtc: start,
    origin: origin,
  );
  final v4 = original.version4Candidate();
  return DriftQuarantineFallbackCandidate._(
    snapshot,
    DriftQuarantineRecord(
      v4.cases.map(
        (value) => value.caseId == item.caseId
            ? value.fallbackCandidate(state)
            : value,
      ),
      version: 4,
    ),
  );
}

class DriftQuarantineFallbackHighWaterEvidence {
  DriftQuarantineFallbackHighWaterEvidence({
    required this.snapshot,
    required this.outcome,
    required this.highWaterUtc,
  }) {
    if (!_mappingTime(highWaterUtc)) _mappingInvalid();
  }
  final DriftQuarantineMappingSnapshot snapshot;
  final DriftQuarantineHighWaterCommit outcome;
  final DateTime highWaterUtc;
}

/// Separate inactive v4 clock route. A committed mapping does not attest a
/// trusted original anchor. All non-clock policy/runtime gates remain external.
DriftQuarantineClockVerdict evaluateDriftQuarantineMappedClock({
  required DriftQuarantineMappingSnapshot currentSnapshot,
  required DriftQuarantinePreferredClockEvidence preferred,
  required DriftQuarantineOriginalAnchor originalAnchor,
  required DriftQuarantineFallbackHighWaterEvidence? highWaterCommit,
}) {
  const unavailable = DriftQuarantineClockVerdict._(
    DriftQuarantineClockVerdictKind.unavailable,
  );
  final item = currentSnapshot.boundCase;
  final state = item?.fallbackState;
  if (item == null ||
      state == null ||
      currentSnapshot.priorFallback != DriftQuarantinePriorFallback.existing ||
      state.accountIdentity != currentSnapshot.accountIdentity ||
      state.introductionIdentity != currentSnapshot.introductionIdentity ||
      state.introductionUtc != currentSnapshot.introductionUtc ||
      !preferred.binding.matchesCase(item) ||
      preferred.binding.recordGeneration != currentSnapshot.recordGeneration ||
      preferred.binding.evidenceEpoch != currentSnapshot.evidenceEpoch)
    return unavailable;
  if (preferred.outcome == DriftQuarantinePreferredClock.interrupted) {
    return const DriftQuarantineClockVerdict._(
      DriftQuarantineClockVerdictKind.interrupted,
    );
  }
  if (preferred.outcome == DriftQuarantinePreferredClock.trustedInterval) {
    if (originalAnchor != DriftQuarantineOriginalAnchor.validatedOriginal)
      return unavailable;
    final elapsed = preferred.trustedElapsed!;
    return DriftQuarantineClockVerdict._(
      elapsed >= const Duration(days: 30)
          ? DriftQuarantineClockVerdictKind.trustedExpiry
          : DriftQuarantineClockVerdictKind.recoveryWindow,
      elapsed,
    );
  }
  final commit = highWaterCommit;
  const graceMs = 37 * 24 * 60 * 60 * 1000;
  if (commit == null ||
      commit.outcome != DriftQuarantineHighWaterCommit.committed ||
      !currentSnapshot.matches(commit.snapshot) ||
      commit.highWaterUtc != item.clockState!.observedHighWaterUtc ||
      state.startUtc.millisecondsSinceEpoch >
          driftQuarantineMaxUtcMilliseconds - graceMs) {
    return unavailable;
  }
  final elapsed = commit.highWaterUtc.difference(state.startUtc);
  if (elapsed.isNegative) return unavailable;
  return DriftQuarantineClockVerdict._(
    elapsed >= const Duration(days: 37)
        ? DriftQuarantineClockVerdictKind.fallbackExpiry
        : DriftQuarantineClockVerdictKind.recoveryWindow,
    elapsed,
  );
}

/// Pure contract data, NOT validated runtime capabilities. There is no provider,
/// boot clock, persistence, network, deletion or production caller here. A future
/// reviewed coordinator must acquire/revalidate every claim under its own gate.
enum DriftQuarantineOriginalAnchor { unavailable, validatedOriginal }

enum DriftQuarantinePreferredClock {
  trustedInterval,
  unavailable,
  invalid,
  interrupted,
}

enum DriftQuarantineHighWaterCommit { notCommitted, failed, committed }

enum DriftQuarantineClockVerdictKind {
  unavailable,
  interrupted,
  recoveryWindow,
  trustedExpiry,
  fallbackExpiry,
}

class DriftQuarantineClockBinding {
  DriftQuarantineClockBinding({
    required this.caseId,
    required this.artifactGeneration,
    required this.recordGeneration,
    required this.originalDetectionUtc,
    required this.nativeIdentity,
    required this.evidenceEpoch,
  }) {
    final opaque = RegExp(r'^[0-9a-f]{32}$');
    if (![
          caseId,
          artifactGeneration,
          recordGeneration,
          evidenceEpoch,
        ].every(opaque.hasMatch) ||
        !originalDetectionUtc.isUtc ||
        originalDetectionUtc.millisecondsSinceEpoch < 0 ||
        originalDetectionUtc.microsecondsSinceEpoch % 1000 != 0) {
      throw const DriftQuarantineRecordException();
    }
  }

  final String caseId;
  final String artifactGeneration;
  // Opaque current committed-record generation; not a serialized trust label.
  final String recordGeneration;
  final DateTime originalDetectionUtc;
  final DriftQuarantineNativeIdentity nativeIdentity;
  final String evidenceEpoch;

  bool matches(DriftQuarantineClockBinding other) =>
      caseId == other.caseId &&
      artifactGeneration == other.artifactGeneration &&
      recordGeneration == other.recordGeneration &&
      originalDetectionUtc == other.originalDetectionUtc &&
      nativeIdentity == other.nativeIdentity &&
      evidenceEpoch == other.evidenceEpoch;

  bool matchesCase(DriftQuarantineCase item) =>
      caseId == item.caseId &&
      artifactGeneration == item.artifactGeneration &&
      originalDetectionUtc == item.firstDetectedUtc &&
      nativeIdentity == item.nativeIdentity;
}

class DriftQuarantinePreferredClockEvidence {
  DriftQuarantinePreferredClockEvidence({
    required this.binding,
    required this.outcome,
    this.trustedElapsed,
  }) {
    if ((outcome == DriftQuarantinePreferredClock.trustedInterval) !=
            (trustedElapsed != null) ||
        (trustedElapsed != null &&
            (trustedElapsed!.isNegative ||
                trustedElapsed!.inMicroseconds >
                    (driftQuarantineMaxUtcMilliseconds -
                            binding
                                .originalDetectionUtc
                                .millisecondsSinceEpoch) *
                        1000))) {
      throw const DriftQuarantineRecordException();
    }
  }

  final DriftQuarantineClockBinding binding;
  final DriftQuarantinePreferredClock outcome;
  // Already-acquired interval from this exact original anchor. Historical
  // timestamps/provenance cannot synthesize this ephemeral input after reboot.
  final Duration? trustedElapsed;
}

class DriftQuarantineHighWaterEvidence {
  DriftQuarantineHighWaterEvidence({
    required this.binding,
    required this.outcome,
    required this.highWaterUtc,
  }) {
    if (!highWaterUtc.isUtc ||
        highWaterUtc.isBefore(binding.originalDetectionUtc) ||
        highWaterUtc.microsecondsSinceEpoch % 1000 != 0) {
      throw const DriftQuarantineRecordException();
    }
  }

  final DriftQuarantineClockBinding binding;
  final DriftQuarantineHighWaterCommit outcome;
  // Claim of successful exact-byte CAS for this generation/epoch/value, not
  // an in-memory observe candidate. The actual store is deliberately untouched.
  final DateTime highWaterUtc;
}

class DriftQuarantineClockVerdict {
  const DriftQuarantineClockVerdict._(this.kind, [this.elapsed]);
  final DriftQuarantineClockVerdictKind kind;
  // For fallback this is observed UTC difference, NOT proven real elapsed time.
  final Duration? elapsed;
}

/// Proposed exact30/37*24h policy. S&C alignment remains an activation gate.
/// Unknown original anchor, identity or evidence binding denies; observed-first
/// bootstrap is unavailable. No serialized field recreates a trusted interval.
DriftQuarantineClockVerdict evaluateDriftQuarantineClock({
  required DriftQuarantineCase? item,
  required DriftQuarantineClockBinding currentBinding,
  required DriftQuarantinePreferredClockEvidence preferred,
  DriftQuarantineOriginalAnchor originalAnchor =
      DriftQuarantineOriginalAnchor.unavailable,
  DriftQuarantineHighWaterEvidence? highWaterCommit,
}) {
  const unavailable = DriftQuarantineClockVerdict._(
    DriftQuarantineClockVerdictKind.unavailable,
  );
  if (item == null ||
      item.clockState == null ||
      // Separately bound v4 windows must use their own snapshot/anchor route,
      // never inherit this legacy first-detection fallback deadline.
      item.fallbackState != null ||
      item.nativeIdentity == null ||
      originalAnchor != DriftQuarantineOriginalAnchor.validatedOriginal ||
      !currentBinding.matchesCase(item) ||
      !currentBinding.matches(preferred.binding)) {
    return unavailable;
  }
  if (preferred.outcome == DriftQuarantinePreferredClock.interrupted) {
    return const DriftQuarantineClockVerdict._(
      DriftQuarantineClockVerdictKind.interrupted,
    );
  }
  if (preferred.outcome == DriftQuarantinePreferredClock.trustedInterval) {
    final elapsed = preferred.trustedElapsed!;
    // Trusted-under30 must defeat even a durably observed forward wall jump.
    return DriftQuarantineClockVerdict._(
      elapsed >= const Duration(days: 30)
          ? DriftQuarantineClockVerdictKind.trustedExpiry
          : DriftQuarantineClockVerdictKind.recoveryWindow,
      elapsed,
    );
  }
  final commit = highWaterCommit;
  if (commit == null ||
      commit.outcome != DriftQuarantineHighWaterCommit.committed ||
      !currentBinding.matches(commit.binding) ||
      commit.highWaterUtc != item.clockState!.observedHighWaterUtc) {
    return unavailable;
  }
  final anchorMs = item.firstDetectedUtc.millisecondsSinceEpoch;
  const graceMs = 37 * 24 * 60 * 60 * 1000;
  if (anchorMs > driftQuarantineMaxUtcMilliseconds - graceMs) {
    return unavailable;
  }
  final elapsed = commit.highWaterUtc.difference(item.firstDetectedUtc);
  return DriftQuarantineClockVerdict._(
    elapsed >= const Duration(days: 37)
        ? DriftQuarantineClockVerdictKind.fallbackExpiry
        : DriftQuarantineClockVerdictKind.recoveryWindow,
    elapsed,
  );
}
