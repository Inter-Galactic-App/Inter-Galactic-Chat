import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_policy.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_clock.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_record.dart';

void main() {
  final first = DateTime.utc(2026, 9, 1, 23, 59);
  const safe = DriftQuarantineSafety(
    associatedActiveDatabaseOpen: true,
    associatedAccountUsable: true,
    exactArtifactIdentity: true,
    confinedSingleDatabaseFileSet: true,
    nativeProtectionVerified: true,
    writersAndMigrationQuiescent: true,
  );

  DriftQuarantineDecision evaluate({
    int days = 30,
    DriftQuarantineSafety safety = safe,
    bool foreground = true,
    bool stateTrusted = true,
    bool clockTrusted = true,
    bool absent = false,
    bool noticed = true,
    bool reminded = true,
    DateTime? last,
    DateTime? now,
  }) => evaluateDriftQuarantine(
    firstDetectedUtc: first,
    lastObservedUtc: last ?? first,
    nowUtc: now ?? DateTime.utc(2026, 9, 1 + days),
    safety: safety,
    foreground: foreground,
    stateTrusted: stateTrusted,
    clockTrusted: clockTrusted,
    absenceVerifiedUnderSameGate: absent,
    firstNoticeRecorded: noticed,
    daySevenReminderRecorded: reminded,
  );

  test('divergent day 29 retains; day 30 must attempt without equivalence', () {
    expect(evaluate(days: 29).action, DriftQuarantineAction.retain);
    expect(evaluate().action, DriftQuarantineAction.attemptCleanup);
    expect(evaluate().reason, DriftQuarantineReason.expiredOwnerPolicy);
  });

  test('safe interrupted expiry retries until absence is verified', () {
    for (final days in [30, 30, 31, 40]) {
      expect(evaluate(days: days).action, DriftQuarantineAction.attemptCleanup);
    }
    expect(evaluate(absent: true).action, DriftQuarantineAction.resolved);
  });

  test('retry rechecks safety rather than trusting a prior attempt', () {
    expect(evaluate().action, DriftQuarantineAction.attemptCleanup);
    expect(
      evaluate(safety: const DriftQuarantineSafety()).action,
      DriftQuarantineAction.retain,
    );
  });

  for (var missing = 0; missing < 6; missing++) {
    test('each failed safety predicate $missing forbids expiry', () {
      final safety = DriftQuarantineSafety(
        associatedActiveDatabaseOpen: missing != 0,
        associatedAccountUsable: missing != 1,
        exactArtifactIdentity: missing != 2,
        confinedSingleDatabaseFileSet: missing != 3,
        nativeProtectionVerified: missing != 4,
        writersAndMigrationQuiescent: missing != 5,
        byteEquivalentUnderSameGate: true,
      );
      for (final days in [5, 30, 60]) {
        expect(
          evaluate(days: days, safety: safety).action,
          DriftQuarantineAction.retain,
        );
      }
    });
  }

  test('background cannot attempt cleanup or emit foreground notice', () {
    final result = evaluate(foreground: false, noticed: false);
    expect(result.action, DriftQuarantineAction.retain);
    expect(result.notice, DriftQuarantineNotice.none);
  });

  test('untrusted state or clock blocks cleanup including absence claims', () {
    expect(
      evaluate(stateTrusted: false, absent: true).action,
      DriftQuarantineAction.retain,
    );
    expect(
      evaluate(clockTrusted: false, absent: true).action,
      DriftQuarantineAction.retain,
    );
    expect(
      evaluate(now: first.subtract(const Duration(seconds: 1))).reason,
      DriftQuarantineReason.untrustedClock,
    );
    expect(
      evaluate(last: DateTime.utc(2026, 10, 2)).reason,
      DriftQuarantineReason.untrustedClock,
    );
    expect(
      evaluate(last: first.subtract(const Duration(seconds: 1))).reason,
      DriftQuarantineReason.untrustedClock,
    );
    expect(
      evaluate(now: DateTime(2026, 10, 1)).reason,
      DriftQuarantineReason.untrustedClock,
    );
  });

  test(
    'first usable notice precedes day-seven reminder; expiry is independent',
    () {
      expect(
        evaluate(days: 0, now: first, noticed: false).notice,
        DriftQuarantineNotice.firstForeground,
      );
      expect(
        evaluate(days: 6, reminded: false).notice,
        DriftQuarantineNotice.none,
      );
      expect(
        evaluate(days: 7, reminded: false).notice,
        DriftQuarantineNotice.daySevenReminder,
      );
      expect(
        evaluate(noticed: false, reminded: false).action,
        DriftQuarantineAction.attemptCleanup,
      );
    },
  );

  test('unusable associated account receives no usable-foreground notice', () {
    expect(
      evaluate(safety: const DriftQuarantineSafety(), noticed: false).notice,
      DriftQuarantineNotice.none,
    );
  });

  test('early cleanup requires equality under the same safe gate', () {
    const equivalent = DriftQuarantineSafety(
      associatedActiveDatabaseOpen: true,
      associatedAccountUsable: true,
      exactArtifactIdentity: true,
      confinedSingleDatabaseFileSet: true,
      nativeProtectionVerified: true,
      writersAndMigrationQuiescent: true,
      byteEquivalentUnderSameGate: true,
    );
    expect(
      evaluate(days: 1, safety: equivalent).reason,
      DriftQuarantineReason.byteEquivalent,
    );
  });

  test('UTC calendar boundary crosses month independent of elapsed hours', () {
    expect(
      evaluate(now: DateTime.utc(2026, 9, 30, 23, 59)).action,
      DriftQuarantineAction.retain,
    );
    expect(
      evaluate(now: DateTime.utc(2026, 10, 1)).action,
      DriftQuarantineAction.attemptCleanup,
    );
  });

  test('new legacy detection does not inherit old filesystem age', () {
    final detected = DateTime.utc(2026, 9, 30);
    final result = evaluateDriftQuarantine(
      firstDetectedUtc: detected,
      lastObservedUtc: detected,
      nowUtc: detected,
      safety: safe,
      foreground: true,
      stateTrusted: true,
      clockTrusted: true,
    );
    expect(result.action, DriftQuarantineAction.retain);
  });

  group('bound pure clock policy', () {
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
      String evidenceEpoch = 'dddddddddddddddddddddddddddddddd',
    }) => DriftQuarantineClockBinding(
      caseId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      artifactGeneration: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      recordGeneration: 'cccccccccccccccccccccccccccccccc',
      evidenceEpoch: evidenceEpoch,
      originalDetectionUtc: first,
      nativeIdentity: native,
    );
    DriftQuarantineDecision decide({
      DriftQuarantineSafety safety = safe,
      DriftQuarantinePreferredClock outcome =
          DriftQuarantinePreferredClock.unavailable,
      Duration? elapsed,
      int wallDays = 37,
      bool foreground = true,
      bool stateTrusted = true,
      bool missingRecord = false,
      bool absent = false,
      bool anchored = true,
      bool committed = true,
      bool includeCommit = true,
      String? preferredEpoch,
      bool noticed = true,
      bool reminded = true,
    }) {
      final observed = first.add(Duration(days: wallDays));
      final item = DriftQuarantineCase(
        caseId: binding().caseId,
        artifactGeneration: binding().artifactGeneration,
        relativeEntry: 'fixture',
        nativeIdentity: native,
        firstDetectedUtc: first,
        lastObservedUtc: observed,
        clockState: DriftQuarantineClockState(
          detectionClock: DriftQuarantineDetectionClock.observed,
          observedHighWaterUtc: observed,
        ),
        firstNoticeRecorded: noticed,
        daySevenReminderRecorded: noticed && reminded,
      );
      return evaluateDriftQuarantineWithClock(
        item: missingRecord ? null : item,
        currentBinding: binding(),
        originalAnchor: anchored
            ? DriftQuarantineOriginalAnchor.validatedOriginal
            : DriftQuarantineOriginalAnchor.unavailable,
        preferred: DriftQuarantinePreferredClockEvidence(
          binding: preferredEpoch == null
              ? binding()
              : binding(evidenceEpoch: preferredEpoch),
          outcome: outcome,
          trustedElapsed: elapsed,
        ),
        highWaterCommit: !includeCommit
            ? null
            : DriftQuarantineHighWaterEvidence(
                binding: binding(),
                outcome: committed
                    ? DriftQuarantineHighWaterCommit.committed
                    : DriftQuarantineHighWaterCommit.failed,
                highWaterUtc: observed,
              ),
        safety: safety,
        foreground: foreground,
        stateTrusted: stateTrusted,
        absenceVerifiedUnderSameGate: absent,
      );
    }

    final firstWarningCases = <String, DriftQuarantineDecision Function()>{
      'unavailable without CAS evidence': () =>
          decide(noticed: false, reminded: false, includeCommit: false),
      'unanchored': () =>
          decide(noticed: false, reminded: false, anchored: false),
      'failed high-water CAS': () =>
          decide(noticed: false, reminded: false, committed: false),
      'invalid preferred clock': () => decide(
        noticed: false,
        reminded: false,
        includeCommit: false,
        outcome: DriftQuarantinePreferredClock.invalid,
      ),
    };
    for (final entry in firstWarningCases.entries) {
      test('first usable warning survives ${entry.key} while retaining', () {
        final result = entry.value();
        expect(result.action, DriftQuarantineAction.retain);
        expect(result.reason, DriftQuarantineReason.untrustedClock);
        expect(result.notice, DriftQuarantineNotice.firstForeground);
      });
    }
    test(
      'unknown clock cannot emit day7 or repeat a recorded first warning',
      () {
        for (final result in [
          decide(anchored: false, reminded: false),
          decide(committed: false, reminded: false),
          decide(includeCommit: false, reminded: false),
        ]) {
          expect(result.action, DriftQuarantineAction.retain);
          expect(result.notice, DriftQuarantineNotice.none);
        }
        // Durable observed UTC can qualify final fallback, not prove seven
        // actual elapsed days for a timed reminder.
        for (final wallDays in [7, 37]) {
          expect(
            decide(wallDays: wallDays, reminded: false).notice,
            DriftQuarantineNotice.none,
          );
        }
      },
    );
    test(
      'background/interruption/invalid state or unusable account never warn',
      () {
        for (final result in [
          decide(noticed: false, reminded: false, foreground: false),
          decide(noticed: false, reminded: false, stateTrusted: false),
          decide(noticed: false, reminded: false, missingRecord: true),
          decide(
            noticed: false,
            reminded: false,
            safety: const DriftQuarantineSafety(),
          ),
          decide(
            noticed: false,
            reminded: false,
            outcome: DriftQuarantinePreferredClock.interrupted,
          ),
          decide(
            noticed: false,
            reminded: false,
            outcome: DriftQuarantinePreferredClock.interrupted,
            preferredEpoch: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          ),
        ]) {
          expect(result.action, DriftQuarantineAction.retain);
          expect(result.notice, DriftQuarantineNotice.none);
        }
      },
    );

    test('ordinary30 and final37 differ; no trusted-under30 wall fallback', () {
      expect(decide(wallDays: 36).action, DriftQuarantineAction.retain);
      expect(decide().reason, DriftQuarantineReason.fallbackOwnerPolicy);
      expect(
        decide(
          outcome: DriftQuarantinePreferredClock.trustedInterval,
          elapsed: const Duration(days: 30),
          committed: false,
        ).reason,
        DriftQuarantineReason.expiredOwnerPolicy,
      );
      expect(
        decide(
          outcome: DriftQuarantinePreferredClock.trustedInterval,
          elapsed: const Duration(days: 29),
          wallDays: 100,
        ).action,
        DriftQuarantineAction.retain,
      );
    });
    for (var missing = 0; missing < 6; missing++) {
      test('clock verdict cannot override false non-clock gate $missing', () {
        final blocked = DriftQuarantineSafety(
          associatedActiveDatabaseOpen: missing != 0,
          associatedAccountUsable: missing != 1,
          exactArtifactIdentity: missing != 2,
          confinedSingleDatabaseFileSet: missing != 3,
          nativeProtectionVerified: missing != 4,
          writersAndMigrationQuiescent: missing != 5,
          byteEquivalentUnderSameGate: true,
        );
        for (final outcome in [
          DriftQuarantinePreferredClock.trustedInterval,
          DriftQuarantinePreferredClock.unavailable,
        ]) {
          expect(
            decide(
              safety: blocked,
              outcome: outcome,
              elapsed: outcome == DriftQuarantinePreferredClock.trustedInterval
                  ? const Duration(days: 100)
                  : null,
              absent: true,
            ).action,
            DriftQuarantineAction.retain,
          );
        }
      });
    }
    test('unanchored, uncommitted, interruption and background deny', () {
      for (final verdict in [
        decide(anchored: false),
        decide(committed: false),
        decide(outcome: DriftQuarantinePreferredClock.interrupted),
        decide(foreground: false),
        decide(stateTrusted: false),
      ]) {
        expect(verdict.action, DriftQuarantineAction.retain);
        expect(verdict.notice, DriftQuarantineNotice.none);
      }
    });
    test(
      'eligible safe expiry retries despite receipts, resolves only with proof',
      () {
        expect(
          decide(noticed: false, reminded: false).action,
          DriftQuarantineAction.attemptCleanup,
        );
        expect(decide().action, DriftQuarantineAction.attemptCleanup);
        expect(decide(absent: true).action, DriftQuarantineAction.resolved);
        expect(
          decide(safety: const DriftQuarantineSafety()).action,
          DriftQuarantineAction.retain,
        );
      },
    );
    test('first notice then exact day7 reminder does not alter expiry', () {
      expect(
        decide(noticed: false, reminded: false).notice,
        DriftQuarantineNotice.firstForeground,
      );
      expect(
        decide(
          outcome: DriftQuarantinePreferredClock.trustedInterval,
          elapsed: const Duration(days: 6),
          reminded: false,
        ).notice,
        DriftQuarantineNotice.none,
      );
      expect(
        decide(
          outcome: DriftQuarantinePreferredClock.trustedInterval,
          elapsed: const Duration(days: 7),
          reminded: false,
        ).notice,
        DriftQuarantineNotice.daySevenReminder,
      );
    });
  });
}
