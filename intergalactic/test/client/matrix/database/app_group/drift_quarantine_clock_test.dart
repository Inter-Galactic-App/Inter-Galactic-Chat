import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_clock.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_record.dart';

void main() {
  _mappingTests();
  final first = DateTime.utc(2026, 9, 1, 23, 59);
  const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const generation = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const recordGeneration = 'cccccccccccccccccccccccccccccccc';
  const epoch = 'dddddddddddddddddddddddddddddddd';
  const other = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
  DriftQuarantineFileIdentity file(int inode) => DriftQuarantineFileIdentity(
    device: 1,
    inode: inode,
    generation: 1,
    birthSeconds: 100,
    birthNanoseconds: 0,
  );
  final native = DriftQuarantineNativeIdentity(
    directory: file(1),
    database: file(2),
  );
  DriftQuarantineClockBinding binding({
    String caseId = id,
    String artifact = generation,
    String record = recordGeneration,
    String evidenceEpoch = epoch,
    DateTime? anchor,
    DriftQuarantineNativeIdentity? identity,
  }) => DriftQuarantineClockBinding(
    caseId: caseId,
    artifactGeneration: artifact,
    recordGeneration: record,
    originalDetectionUtc: anchor ?? first,
    nativeIdentity: identity ?? native,
    evidenceEpoch: evidenceEpoch,
  );
  DriftQuarantineCase item({
    Duration highWater = const Duration(days: 37),
    bool knownIdentity = true,
    bool version3 = true,
    DriftQuarantineDetectionClock provenance =
        DriftQuarantineDetectionClock.observed,
    DateTime? anchor,
  }) {
    final detected = anchor ?? first;
    final observed = detected.add(highWater);
    return DriftQuarantineCase(
      caseId: id,
      artifactGeneration: generation,
      relativeEntry: 'fixture',
      nativeIdentity: knownIdentity ? native : null,
      firstDetectedUtc: detected,
      lastObservedUtc: observed,
      clockState: version3
          ? DriftQuarantineClockState(
              detectionClock: provenance,
              observedHighWaterUtc: observed,
            )
          : null,
    );
  }

  DriftQuarantineClockVerdict evaluate({
    DriftQuarantineCase? value,
    DriftQuarantineClockBinding? current,
    DriftQuarantineClockBinding? preferredBinding,
    DriftQuarantineClockBinding? commitBinding,
    DriftQuarantinePreferredClock outcome =
        DriftQuarantinePreferredClock.unavailable,
    Duration? trustedElapsed,
    DriftQuarantineOriginalAnchor originalAnchor =
        DriftQuarantineOriginalAnchor.validatedOriginal,
    DriftQuarantineHighWaterCommit commit =
        DriftQuarantineHighWaterCommit.committed,
    bool includeCommit = true,
    DateTime? committedHighWater,
  }) {
    final caseValue = value ?? item();
    return evaluateDriftQuarantineClock(
      item: caseValue,
      currentBinding: current ?? binding(),
      originalAnchor: originalAnchor,
      preferred: DriftQuarantinePreferredClockEvidence(
        binding: preferredBinding ?? binding(),
        outcome: outcome,
        trustedElapsed: trustedElapsed,
      ),
      highWaterCommit: includeCommit
          ? DriftQuarantineHighWaterEvidence(
              binding: commitBinding ?? binding(),
              outcome: commit,
              highWaterUtc: committedHighWater ?? caseValue.lastObservedUtc,
            )
          : null,
    );
  }

  test('exact trusted30 boundary and trusted-under30 defeats wall jump', () {
    final jump = item(highWater: const Duration(days: 1000));
    for (final elapsed in [
      Duration.zero,
      const Duration(days: 29),
      const Duration(days: 30) - const Duration(microseconds: 1),
    ]) {
      expect(
        evaluate(
          value: jump,
          outcome: DriftQuarantinePreferredClock.trustedInterval,
          trustedElapsed: elapsed,
        ).kind,
        DriftQuarantineClockVerdictKind.recoveryWindow,
      );
    }
    expect(
      evaluate(
        outcome: DriftQuarantinePreferredClock.trustedInterval,
        trustedElapsed: const Duration(days: 30),
        includeCommit: false,
      ).kind,
      DriftQuarantineClockVerdictKind.trustedExpiry,
    );
  });
  for (final outcome in [
    DriftQuarantinePreferredClock.unavailable,
    DriftQuarantinePreferredClock.invalid,
  ]) {
    test('exact final37 boundary after $outcome', () {
      expect(
        evaluate(
          value: item(
            highWater:
                const Duration(days: 37) - const Duration(milliseconds: 1),
          ),
          outcome: outcome,
        ).kind,
        DriftQuarantineClockVerdictKind.recoveryWindow,
      );
      final verdict = evaluate(outcome: outcome);
      expect(verdict.kind, DriftQuarantineClockVerdictKind.fallbackExpiry);
      expect(verdict.elapsed, const Duration(days: 37));
    });
  }
  test('interruption blocks despite committed far-future high-water', () {
    expect(
      evaluate(
        value: item(highWater: const Duration(days: 1000)),
        outcome: DriftQuarantinePreferredClock.interrupted,
      ).kind,
      DriftQuarantineClockVerdictKind.interrupted,
    );
  });
  test(
    'fallback requires exact durable CAS claim, never an observe candidate',
    () {
      for (final commit in [
        DriftQuarantineHighWaterCommit.notCommitted,
        DriftQuarantineHighWaterCommit.failed,
      ]) {
        expect(
          evaluate(commit: commit).kind,
          DriftQuarantineClockVerdictKind.unavailable,
        );
      }
      expect(
        evaluate(includeCommit: false).kind,
        DriftQuarantineClockVerdictKind.unavailable,
      );
      expect(
        evaluate(committedHighWater: first.add(const Duration(days: 38))).kind,
        DriftQuarantineClockVerdictKind.unavailable,
      );
    },
  );
  final mismatches = <String, DriftQuarantineClockBinding Function()>{
    'case': () => binding(caseId: other),
    'artifact generation': () => binding(artifact: other),
    'record generation': () => binding(record: other),
    'epoch/reboot': () => binding(evidenceEpoch: other),
    'immutable anchor': () =>
        binding(anchor: first.add(const Duration(milliseconds: 1))),
    'native identity': () => binding(
      identity: DriftQuarantineNativeIdentity(
        directory: file(1),
        database: file(3),
      ),
    ),
  };
  for (final entry in mismatches.entries) {
    test(
      'stale/mismatched ${entry.key} denies trusted and fallback evidence',
      () {
        expect(
          evaluate(
            outcome: DriftQuarantinePreferredClock.trustedInterval,
            trustedElapsed: const Duration(days: 30),
            preferredBinding: entry.value(),
          ).kind,
          DriftQuarantineClockVerdictKind.unavailable,
        );
        expect(
          evaluate(preferredBinding: entry.value()).kind,
          DriftQuarantineClockVerdictKind.unavailable,
        );
        expect(
          evaluate(commitBinding: entry.value()).kind,
          DriftQuarantineClockVerdictKind.unavailable,
        );
      },
    );
  }
  test('replacement/unknown identity and historical schema deny', () {
    expect(
      evaluate(value: item(knownIdentity: false)).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
    expect(
      evaluate(value: item(version3: false)).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
    expect(
      evaluate(current: mismatches['native identity']!()).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
    expect(
      evaluate(current: mismatches['immutable anchor']!()).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
  });
  test('missing record and initial untrusted anchor stay unavailable', () {
    final preferred = DriftQuarantinePreferredClockEvidence(
      binding: binding(),
      outcome: DriftQuarantinePreferredClock.unavailable,
    );
    expect(
      evaluateDriftQuarantineClock(
        item: null,
        currentBinding: binding(),
        preferred: preferred,
      ).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
    for (final provenance in DriftQuarantineDetectionClock.values) {
      expect(
        evaluate(
          value: item(provenance: provenance),
          originalAnchor: DriftQuarantineOriginalAnchor.unavailable,
          outcome: DriftQuarantinePreferredClock.trustedInterval,
          trustedElapsed: const Duration(days: 100),
        ).kind,
        DriftQuarantineClockVerdictKind.unavailable,
      );
      expect(
        evaluate(
          value: item(provenance: provenance),
          originalAnchor: DriftQuarantineOriginalAnchor.unavailable,
        ).kind,
        DriftQuarantineClockVerdictKind.unavailable,
      );
    }
  });
  test(
    'rollback/restart preserve high-water without recreating clock trust',
    () {
      var seen = item().observeDeviceClock(
        first.subtract(const Duration(days: 1)),
      );
      seen = DriftQuarantineRecord.decode(
        DriftQuarantineRecord([seen], version: 3).encode(),
      ).cases.single;
      expect(seen.firstDetectedUtc, first);
      expect(
        evaluate(value: seen, includeCommit: false).kind,
        DriftQuarantineClockVerdictKind.unavailable,
      );
      expect(
        evaluate(value: seen).kind,
        DriftQuarantineClockVerdictKind.fallbackExpiry,
      );
      expect(
        evaluate(
          value: seen,
          preferredBinding: binding(evidenceEpoch: other),
        ).kind,
        DriftQuarantineClockVerdictKind.unavailable,
      );
    },
  );
  test('UTC exact duration ignores civil midnight and timezone is invalid', () {
    expect(
      evaluate(
        value: item(
          highWater: const Duration(days: 36, hours: 23, minutes: 59),
        ),
      ).kind,
      DriftQuarantineClockVerdictKind.recoveryWindow,
    );
    expect(
      () => binding(anchor: first.toLocal()),
      throwsA(isA<DriftQuarantineRecordException>()),
    );
  });
  test('threshold overflow cannot wrap into expiry', () {
    final anchor = DateTime.fromMillisecondsSinceEpoch(
      driftQuarantineMaxUtcMilliseconds -
          const Duration(days: 36).inMilliseconds,
      isUtc: true,
    );
    final seen = item(anchor: anchor, highWater: const Duration(days: 36));
    expect(
      evaluate(
        value: seen,
        current: binding(anchor: anchor),
        preferredBinding: binding(anchor: anchor),
        commitBinding: binding(anchor: anchor),
      ).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
  });
  test('malformed contract data fails at runtime with generic errors', () {
    final invalid = throwsA(isA<DriftQuarantineRecordException>());
    expect(() => binding(evidenceEpoch: 'secret'), invalid);
    expect(
      () => DriftQuarantinePreferredClockEvidence(
        binding: binding(),
        outcome: DriftQuarantinePreferredClock.trustedInterval,
      ),
      invalid,
    );
    expect(
      () => DriftQuarantinePreferredClockEvidence(
        binding: binding(),
        outcome: DriftQuarantinePreferredClock.unavailable,
        trustedElapsed: Duration.zero,
      ),
      invalid,
    );
    expect(
      () => DriftQuarantinePreferredClockEvidence(
        binding: binding(),
        outcome: DriftQuarantinePreferredClock.trustedInterval,
        trustedElapsed: const Duration(microseconds: -1),
      ),
      invalid,
    );
    expect(
      () => DriftQuarantineHighWaterEvidence(
        binding: binding(),
        outcome: DriftQuarantineHighWaterCommit.committed,
        highWaterUtc: first.subtract(const Duration(milliseconds: 1)),
      ),
      invalid,
    );
    expect(
      () => DriftQuarantinePreferredClockEvidence(
        binding: binding(),
        outcome: DriftQuarantinePreferredClock.trustedInterval,
        trustedElapsed: const Duration(days: 100000000),
      ),
      invalid,
    );
  });
}

class _MappingFixture {
  static const a = '11111111111111111111111111111111';
  static const b = '22222222222222222222222222222222';
  static const c = '33333333333333333333333333333333';
  static const d = '44444444444444444444444444444444';
  static const e = '55555555555555555555555555555555';
  static const f = '66666666666666666666666666666666';
  final first = DateTime.utc(2026, 1, 1);
  DriftQuarantineFileIdentity file(int inode) => DriftQuarantineFileIdentity(
    device: 1,
    inode: inode,
    generation: 2,
    birthSeconds: 3,
    birthNanoseconds: 4,
  );
  DriftQuarantineNativeIdentity native({
    int directory = 10,
    int database = 11,
  }) => DriftQuarantineNativeIdentity(
    directory: file(directory),
    database: file(database),
  );
  DriftQuarantineMappingCaseIdentity identity({
    String caseId = a,
    String artifact = b,
    int directory = 10,
    int database = 11,
  }) => DriftQuarantineMappingCaseIdentity(
    caseId: caseId,
    artifactGeneration: artifact,
    nativeIdentity: native(directory: directory, database: database),
  );
  DriftQuarantineCase item({
    DriftQuarantineFallbackState? fallback,
    DateTime? highWater,
    String entry = 'account-one',
  }) => DriftQuarantineCase(
    caseId: a,
    artifactGeneration: b,
    relativeEntry: 'fixture',
    activeAccountEntry: entry,
    nativeIdentity: native(),
    firstDetectedUtc: first,
    lastObservedUtc: highWater ?? first,
    firstNoticeRecorded: true,
    legacyAgeUnknown: true,
    clockState: DriftQuarantineClockState(
      detectionClock: DriftQuarantineDetectionClock.observed,
      observedHighWaterUtc: highWater ?? first,
    ),
    fallbackState: fallback,
  );
  DriftQuarantineRecord record({
    DriftQuarantineFallbackState? fallback,
    DateTime? highWater,
    String entry = 'account-one',
  }) => DriftQuarantineRecord([
    item(fallback: fallback, highWater: highWater, entry: entry),
  ], version: fallback == null ? 3 : 4);
  DriftQuarantineMappingSnapshot snapshot({
    List<int>? bytes,
    bool missing = false,
    List<int>? pending,
    String recordGeneration = c,
    String epoch = d,
    String account = e,
    String entry = 'account-one',
    String introduction = f,
    DateTime? introUtc,
    String? witness = a,
    String? historyGeneration = b,
    DriftQuarantineMappingHistory history =
        DriftQuarantineMappingHistory.intact,
    DriftQuarantinePriorFallback prior =
        DriftQuarantinePriorFallback.provenAbsent,
    DriftQuarantineMappingMembership membership =
        DriftQuarantineMappingMembership.lateObserved,
    List<DriftQuarantineMappingCaseIdentity>? roster,
    DriftQuarantineMappingCaseIdentity? target,
    DateTime? creation,
  }) => DriftQuarantineMappingSnapshot(
    committedBytes: missing ? null : bytes ?? record().encode(),
    pendingBytes: pending,
    recordGeneration: recordGeneration,
    evidenceEpoch: epoch,
    caseIdentity: target ?? identity(),
    accountIdentity: account,
    accountEntry: entry,
    introductionIdentity: introduction,
    introductionUtc: introUtc ?? first,
    witnessGeneration: witness,
    historyGeneration: historyGeneration,
    history: history,
    priorFallback: prior,
    membership: membership,
    introductionRoster: roster ?? [],
    creationObservedUtc: creation,
  );
  DriftQuarantineFallbackCandidate? prepare(
    DriftQuarantineMappingSnapshot value, {
    DriftQuarantineMappingSnapshot? current,
    DateTime? observed,
    bool interrupted = false,
  }) => prepareDriftQuarantineFallback(
    snapshot: value,
    currentSnapshot: current ?? value,
    observedUtc: observed ?? first.add(const Duration(days: 100)),
    interrupted: interrupted,
  );
}

void _mappingTests() {
  final f = _MappingFixture();
  final invalid = throwsA(isA<DriftQuarantineRecordException>());
  test('v4 recycled roster identities cannot acquire a fresh anchor', () {
    for (final member in [
      f.identity(caseId: _MappingFixture.c, artifact: _MappingFixture.d),
      f.identity(
        caseId: _MappingFixture.c,
        artifact: _MappingFixture.d,
        database: 12,
      ),
      f.identity(
        caseId: _MappingFixture.c,
        artifact: _MappingFixture.d,
        directory: 12,
      ),
      f.identity(database: 12, directory: 13),
    ]) {
      for (final membership in [
        DriftQuarantineMappingMembership.lateObserved,
        DriftQuarantineMappingMembership.recordedNewCreation,
      ]) {
        expect(
          f.prepare(
            f.snapshot(
              membership: membership,
              roster: [member],
              creation: f.first.add(const Duration(days: 100)),
            ),
          ),
          isNull,
        );
      }
    }
  });
  test(
    'v4 lateObserved gets fresh immutable start, never old introduction age',
    () {
      final snapshot = f.snapshot();
      final candidate = f.prepare(snapshot)!;
      final item = candidate.record.cases.single;
      expect(
        item.fallbackState!.startUtc,
        f.first.add(const Duration(days: 100)),
      );
      expect(
        item.fallbackState!.origin,
        DriftQuarantineFallbackOrigin.lateObserved,
      );
      expect(item.firstDetectedUtc, f.first);
      expect(item.lastObservedUtc, f.first);
      expect(item.firstNoticeRecorded, isTrue);
      expect(item.legacyAgeUnknown, isTrue);
      expect(candidate.expectedBytes, snapshot.committedBytes);
      expect(candidate.record.version, 4);
      expect(DriftQuarantineRecord.decode(snapshot.committedBytes!).version, 3);
    },
  );
  test('v4 late observation cannot backdate the committed high-water mark', () {
    final highWater = f.first.add(const Duration(days: 120));
    final snapshot = f.snapshot(bytes: f.record(highWater: highWater).encode());
    for (final observed in [
      highWater.subtract(const Duration(days: 20)),
      highWater,
      highWater.add(const Duration(days: 1)),
    ]) {
      final candidate = f.prepare(snapshot, observed: observed)!;
      expect(
        candidate.record.cases.single.fallbackState!.startUtc,
        observed.isAfter(highWater) ? observed : highWater,
      );
      expect(candidate.expectedBytes, snapshot.committedBytes);
      expect(candidate.record.cases.single.lastObservedUtc, highWater);
    }
  });
  test(
    'v4 introduction roster requires exact pair and completed membership',
    () {
      for (final target in [
        f.identity(),
        f.identity(database: 12),
        f.identity(directory: 12),
      ]) {
        final snapshot = f.snapshot(
          membership:
              DriftQuarantineMappingMembership.completeIntroductionRoster,
          roster: [target],
        );
        final candidate = f.prepare(snapshot);
        if (target.matches(f.identity())) {
          expect(
            candidate!.record.cases.single.fallbackState!.startUtc,
            f.first,
          );
        } else {
          expect(candidate, isNull);
        }
      }
      expect(
        f.prepare(
          f.snapshot(
            membership:
                DriftQuarantineMappingMembership.completeIntroductionRoster,
          ),
        ),
        isNull,
      );
      expect(
        f.prepare(
          f.snapshot(
            membership: DriftQuarantineMappingMembership.partialRoster,
            roster: [f.identity()],
          ),
        ),
        isNull,
      );
    },
  );
  test(
    'v4 new creation gets full fresh window and cannot use partial inference',
    () {
      final creation = f.first.add(const Duration(days: 100));
      final candidate = f.prepare(
        f.snapshot(
          membership: DriftQuarantineMappingMembership.recordedNewCreation,
          creation: creation,
        ),
      )!;
      expect(candidate.record.cases.single.fallbackState!.startUtc, creation);
      final clamped = f.prepare(
        f.snapshot(
          membership: DriftQuarantineMappingMembership.recordedNewCreation,
          creation: f.first.subtract(const Duration(days: 1)),
        ),
      )!;
      expect(clamped.record.cases.single.fallbackState!.startUtc, f.first);
      expect(
        f.prepare(
          f.snapshot(
            membership: DriftQuarantineMappingMembership.recordedNewCreation,
          ),
        ),
        isNull,
      );
      expect(
        f.prepare(
          f.snapshot(
            membership: DriftQuarantineMappingMembership.recordedNewCreation,
            creation: creation,
            roster: [f.identity()],
          ),
        ),
        isNull,
      );
    },
  );
  for (final history in DriftQuarantineMappingHistory.values.where(
    (v) => v != DriftQuarantineMappingHistory.intact,
  )) {
    test('v4 $history never repairs history or initializes an anchor', () {
      expect(f.prepare(f.snapshot(history: history)), isNull);
    });
  }
  test('v4 missing fields, witness or history do not prove anchor absence', () {
    for (final value in [
      f.snapshot(prior: DriftQuarantinePriorFallback.unknown),
      f.snapshot(prior: DriftQuarantinePriorFallback.existing),
      f.snapshot(witness: null),
      f.snapshot(historyGeneration: null),
      f.snapshot(missing: true),
      f.snapshot(pending: f.record().encode()),
      f.snapshot(membership: DriftQuarantineMappingMembership.unclassified),
    ]) {
      expect(f.prepare(value), isNull);
    }
  });
  final mismatches = <String, DriftQuarantineMappingSnapshot Function()>{
    'account mapping': () => f.snapshot(account: _MappingFixture.a),
    'account entry': () => f.snapshot(entry: 'other-account'),
    'introduction generation': () =>
        f.snapshot(introduction: _MappingFixture.b),
    'introduction instant': () =>
        f.snapshot(introUtc: f.first.add(const Duration(days: 1))),
    'record generation': () => f.snapshot(recordGeneration: _MappingFixture.a),
    'evidence epoch': () => f.snapshot(epoch: _MappingFixture.a),
    'witness generation': () => f.snapshot(witness: _MappingFixture.c),
    'history generation': () =>
        f.snapshot(historyGeneration: _MappingFixture.c),
    'case replacement': () =>
        f.snapshot(target: f.identity(caseId: _MappingFixture.c)),
    'artifact recycle': () =>
        f.snapshot(target: f.identity(artifact: _MappingFixture.c)),
    'directory identity': () => f.snapshot(target: f.identity(directory: 12)),
    'database identity': () => f.snapshot(target: f.identity(database: 12)),
    'committed bytes': () => f.snapshot(
      bytes: f.record(highWater: f.first.add(const Duration(days: 1))).encode(),
    ),
  };
  for (final entry in mismatches.entries) {
    test(
      'v4 stale ${entry.key} snapshot rejects candidate and CAS receipt',
      () {
        final original = f.snapshot();
        expect(f.prepare(original, current: entry.value()), isNull);
        final candidate = f.prepare(original)!;
        expect(
          candidate.acceptsCommit(
            currentSnapshot: entry.value(),
            expected: candidate.expectedBytes,
            replacement: candidate.replacementBytes,
            outcome: DriftQuarantineHighWaterCommit.committed,
            interrupted: false,
          ),
          isFalse,
        );
      },
    );
  }
  test('v4 target mismatch denies even internally current snapshot', () {
    for (final value in [
      f.snapshot(target: f.identity(database: 12)),
      f.snapshot(target: f.identity(directory: 12)),
      f.snapshot(entry: 'other-account'),
    ]) {
      expect(f.prepare(value), isNull);
    }
  });
  test(
    'v4 repeated discovery/restart/rollback never resets existing start',
    () {
      final candidate = f.prepare(f.snapshot())!;
      for (final day in [101, 0, 200, 50]) {
        final raw = DriftQuarantineRecord.decode(
          candidate.replacementBytes,
        ).encode();
        final value = f.snapshot(
          bytes: raw,
          prior: DriftQuarantinePriorFallback.existing,
        );
        final repeated = f.prepare(
          value,
          observed: f.first.add(Duration(days: day)),
        )!;
        expect(repeated.replacementBytes, candidate.replacementBytes);
        expect(repeated.record.cases.single.firstDetectedUtc, f.first);
        expect(
          repeated.record.cases.single.fallbackState!.startUtc,
          f.first.add(const Duration(days: 100)),
        );
      }
      for (final value in [
        f.snapshot(bytes: candidate.replacementBytes),
        f.snapshot(
          bytes: candidate.replacementBytes,
          prior: DriftQuarantinePriorFallback.unknown,
        ),
        f.snapshot(
          bytes: candidate.replacementBytes,
          prior: DriftQuarantinePriorFallback.existing,
          account: _MappingFixture.a,
        ),
        f.snapshot(
          bytes: candidate.replacementBytes,
          prior: DriftQuarantinePriorFallback.existing,
          introduction: _MappingFixture.a,
        ),
        f.snapshot(
          bytes: candidate.replacementBytes,
          prior: DriftQuarantinePriorFallback.existing,
          introUtc: f.first.add(const Duration(days: 1)),
        ),
      ]) {
        expect(f.prepare(value), isNull);
      }
    },
  );
  test('v4 independent accounts do not share introduction anchor', () {
    final one = f.snapshot(
      membership: DriftQuarantineMappingMembership.completeIntroductionRoster,
      roster: [f.identity()],
    );
    final twoIntro = f.first.add(const Duration(days: 50));
    final two = f.snapshot(
      bytes: f.record(entry: 'account-two').encode(),
      entry: 'account-two',
      account: _MappingFixture.a,
      introduction: _MappingFixture.b,
      introUtc: twoIntro,
      membership: DriftQuarantineMappingMembership.completeIntroductionRoster,
      roster: [f.identity()],
    );
    expect(
      f.prepare(one)!.record.cases.single.fallbackState!.startUtc,
      f.first,
    );
    expect(
      f.prepare(two)!.record.cases.single.fallbackState!.startUtc,
      twoIntro,
    );
  });
  test('v4 interruption, failed/stale CAS and changed replacement deny', () {
    final value = f.snapshot();
    expect(f.prepare(value, interrupted: true), isNull);
    final candidate = f.prepare(value)!;
    for (final outcome in DriftQuarantineHighWaterCommit.values) {
      expect(
        candidate.acceptsCommit(
          currentSnapshot: value,
          expected: candidate.expectedBytes,
          replacement: candidate.replacementBytes,
          outcome: outcome,
          interrupted: false,
        ),
        outcome == DriftQuarantineHighWaterCommit.committed,
      );
    }
    expect(
      candidate.acceptsCommit(
        currentSnapshot: value,
        expected: candidate.expectedBytes,
        replacement: candidate.replacementBytes,
        outcome: DriftQuarantineHighWaterCommit.committed,
        interrupted: true,
      ),
      isFalse,
    );
    expect(
      candidate.acceptsCommit(
        currentSnapshot: value,
        expected: candidate.replacementBytes,
        replacement: candidate.replacementBytes,
        outcome: DriftQuarantineHighWaterCommit.committed,
        interrupted: false,
      ),
      isFalse,
    );
    expect(
      candidate.acceptsCommit(
        currentSnapshot: value,
        expected: candidate.expectedBytes,
        replacement: candidate.expectedBytes,
        outcome: DriftQuarantineHighWaterCommit.committed,
        interrupted: false,
      ),
      isFalse,
    );
  });
  test(
    'v4 bounded snapshots copy bytes and reject invalid data generically',
    () {
      final bytes = f.record().encode();
      final value = f.snapshot(bytes: bytes);
      final original = List<int>.of(bytes);
      bytes[0] = 0;
      expect(value.committedBytes, original);
      expect(() => value.committedBytes![0] = 0, throwsUnsupportedError);
      expect(
        () => value.introductionRoster.add(f.identity()),
        throwsUnsupportedError,
      );
      expect(() => f.snapshot(bytes: [0xff]), invalid);
      expect(
        () => f.snapshot(
          bytes: List.filled(DriftQuarantineRecord.maxBytes + 1, 32),
        ),
        invalid,
      );
      expect(() => f.snapshot(account: 'PRIVATE'), invalid);
      expect(() => f.snapshot(roster: [f.identity(), f.identity()]), invalid);
      expect(() => f.snapshot(roster: List.filled(65, f.identity())), invalid);
      expect(
        () => f.prepare(f.snapshot(), observed: f.first.toLocal()),
        invalid,
      );
      expect(
        () => f.prepare(
          f.snapshot(),
          observed: f.first.add(const Duration(microseconds: 1)),
        ),
        invalid,
      );
    },
  );
  test('v4 mapped clock uses fresh37 and preferred trusted-under30 wins', () {
    final state = f.prepare(f.snapshot())!.record.cases.single.fallbackState!;
    DriftQuarantineClockVerdict evaluate({
      int day = 137,
      int subtractMilliseconds = 0,
      DriftQuarantinePreferredClock outcome =
          DriftQuarantinePreferredClock.unavailable,
      Duration? elapsed,
      bool committed = true,
      bool stale = false,
      DriftQuarantineOriginalAnchor anchor =
          DriftQuarantineOriginalAnchor.unavailable,
    }) {
      final raw = f
          .record(
            fallback: state,
            highWater: f.first
                .add(Duration(days: day))
                .subtract(Duration(milliseconds: subtractMilliseconds)),
          )
          .encode();
      final snapshot = f.snapshot(
        bytes: raw,
        prior: DriftQuarantinePriorFallback.existing,
      );
      return evaluateDriftQuarantineMappedClock(
        currentSnapshot: snapshot,
        preferred: DriftQuarantinePreferredClockEvidence(
          binding: DriftQuarantineClockBinding(
            caseId: _MappingFixture.a,
            artifactGeneration: _MappingFixture.b,
            recordGeneration: _MappingFixture.c,
            originalDetectionUtc: f.first,
            nativeIdentity: f.native(),
            evidenceEpoch: _MappingFixture.d,
          ),
          outcome: outcome,
          trustedElapsed: elapsed,
        ),
        originalAnchor: anchor,
        highWaterCommit: DriftQuarantineFallbackHighWaterEvidence(
          snapshot: stale
              ? f.snapshot(
                  bytes: raw,
                  prior: DriftQuarantinePriorFallback.existing,
                  epoch: _MappingFixture.a,
                )
              : snapshot,
          outcome: committed
              ? DriftQuarantineHighWaterCommit.committed
              : DriftQuarantineHighWaterCommit.failed,
          highWaterUtc: f.first
              .add(Duration(days: day))
              .subtract(Duration(milliseconds: subtractMilliseconds)),
        ),
      );
    }

    expect(
      evaluate(day: 100).kind,
      DriftQuarantineClockVerdictKind.recoveryWindow,
    );
    expect(
      evaluate(day: 136).kind,
      DriftQuarantineClockVerdictKind.recoveryWindow,
    );
    expect(evaluate().kind, DriftQuarantineClockVerdictKind.fallbackExpiry);
    expect(
      evaluate(subtractMilliseconds: 1).kind,
      DriftQuarantineClockVerdictKind.recoveryWindow,
    );
    expect(evaluate(day: 99).kind, DriftQuarantineClockVerdictKind.unavailable);
    expect(evaluate().elapsed, const Duration(days: 37));
    expect(
      evaluate(committed: false).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
    expect(
      evaluate(stale: true).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
    expect(
      evaluate(outcome: DriftQuarantinePreferredClock.interrupted).kind,
      DriftQuarantineClockVerdictKind.interrupted,
    );
    expect(
      evaluate(
        outcome: DriftQuarantinePreferredClock.trustedInterval,
        elapsed: const Duration(days: 29),
        anchor: DriftQuarantineOriginalAnchor.validatedOriginal,
      ).kind,
      DriftQuarantineClockVerdictKind.recoveryWindow,
    );
    expect(
      evaluate(
        outcome: DriftQuarantinePreferredClock.trustedInterval,
        elapsed: const Duration(days: 30),
        anchor: DriftQuarantineOriginalAnchor.validatedOriginal,
      ).kind,
      DriftQuarantineClockVerdictKind.trustedExpiry,
    );
    expect(
      evaluate(
        outcome: DriftQuarantinePreferredClock.trustedInterval,
        elapsed: const Duration(days: 30),
      ).kind,
      DriftQuarantineClockVerdictKind.unavailable,
    );
  });
  test(
    'v4 mapped case cannot inherit legacy first-detection fallback expiry',
    () {
      final value = f.prepare(f.snapshot())!.record.cases.single;
      final binding = DriftQuarantineClockBinding(
        caseId: _MappingFixture.a,
        artifactGeneration: _MappingFixture.b,
        recordGeneration: _MappingFixture.c,
        originalDetectionUtc: f.first,
        nativeIdentity: f.native(),
        evidenceEpoch: _MappingFixture.d,
      );
      final observed = value.observeDeviceClock(
        f.first.add(const Duration(days: 100)),
      );
      expect(
        evaluateDriftQuarantineClock(
          item: observed,
          currentBinding: binding,
          originalAnchor: DriftQuarantineOriginalAnchor.validatedOriginal,
          preferred: DriftQuarantinePreferredClockEvidence(
            binding: binding,
            outcome: DriftQuarantinePreferredClock.unavailable,
          ),
          highWaterCommit: DriftQuarantineHighWaterEvidence(
            binding: binding,
            outcome: DriftQuarantineHighWaterCommit.committed,
            highWaterUtc: observed.lastObservedUtc,
          ),
        ).kind,
        DriftQuarantineClockVerdictKind.unavailable,
      );
    },
  );
}
