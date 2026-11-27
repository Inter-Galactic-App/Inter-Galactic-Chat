import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_inventory.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_record.dart';

void main() {
  _schemaCompatibilityTests();
  final first = DateTime.utc(2026, 9, 1);
  final now = DateTime.utc(2026, 9, 30);
  final identity = DriftQuarantineNativeIdentity(
    directory: DriftQuarantineFileIdentity(
      device: 1,
      inode: 10,
      generation: 0,
      birthSeconds: 100,
      birthNanoseconds: 0,
    ),
    database: DriftQuarantineFileIdentity(
      device: 1,
      inode: 11,
      generation: 0,
      birthSeconds: 100,
      birthNanoseconds: 0,
    ),
  );
  DriftQuarantineCase item({
    String id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    String generation = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    String entry = 'fixture-1',
    String? account,
    DateTime? detected,
    bool notice = false,
    DriftQuarantinePhase phase = DriftQuarantinePhase.unresolved,
    DriftQuarantineDisposition disposition = DriftQuarantineDisposition.none,
  }) => DriftQuarantineCase(
    caseId: id,
    artifactGeneration: generation,
    relativeEntry: entry,
    activeAccountEntry: account,
    nativeIdentity: identity,
    firstDetectedUtc: detected ?? now,
    lastObservedUtc: detected ?? now,
    legacyAgeUnknown: true,
    firstNoticeRecorded: notice,
    phase: phase,
    disposition: disposition,
  );
  DriftQuarantineRecord run(
    List<DriftQuarantineCase> old,
    List<DriftQuarantineCase> scan,
  ) => reconcileDriftQuarantineInventory(
    committed: DriftQuarantineRecord(old),
    observations: scan,
    nowUtc: now,
    stateTrusted: true,
    inventoryTrusted: true,
    clockTrusted: true,
  );
  final invalid = throwsA(isA<DriftQuarantineRecordException>());
  test('defaults fail closed', () {
    expect(
      () => reconcileDriftQuarantineInventory(
        committed: DriftQuarantineRecord([]),
        observations: [],
        nowUtc: now,
      ),
      invalid,
    );
  });
  test(
    'adopts legacy only at current detection without suffix association',
    () {
      final record = run([], [item()]);
      final restored = DriftQuarantineRecord.decode(
        record.encode(),
      ).cases.single;
      expect(restored.firstDetectedUtc, now);
      expect(restored.activeAccountEntry, isNull);
    },
  );
  test('repeated scan preserves age notices and interrupted cleanup', () {
    final record = run(
      [
        item(
          detected: first,
          notice: true,
          phase: DriftQuarantinePhase.cleanupPending,
          disposition: DriftQuarantineDisposition.expiredOwnerPolicy,
        ),
      ],
      [item()],
    );
    final restored = DriftQuarantineRecord.decode(record.encode()).cases.single;
    expect(restored.firstDetectedUtc, first);
    expect(restored.firstNoticeRecorded, isTrue);
    expect(restored.phase, DriftQuarantinePhase.cleanupPending);
    expect(restored.disposition, DriftQuarantineDisposition.expiredOwnerPolicy);
    expect(restored.lastObservedUtc, now);
  });
  test('absence does not resolve or discard pending history', () {
    final previous = item(detected: first);
    expect(run([previous], []).cases.single, same(previous));
  });
  test('replacement collision cannot reset detection', () {
    expect(
      () => run(
        [item(detected: first)],
        [item(generation: 'cccccccccccccccccccccccccccccccc')],
      ),
      invalid,
    );
    expect(
      () => run(
        [item(detected: first)],
        [item(id: 'cccccccccccccccccccccccccccccccc')],
      ),
      invalid,
    );
  });
  test('association mismatch and resolved resurrection reject', () {
    expect(
      () => run([item(detected: first, account: 'explicit')], [item()]),
      invalid,
    );
    expect(
      () => run(
        [
          item(
            detected: first,
            phase: DriftQuarantinePhase.resolved,
            disposition: DriftQuarantineDisposition.byteEquivalent,
          ),
        ],
        [item()],
      ),
      invalid,
    );
  });
  test('backdated adoption and inferred account reject', () {
    expect(() => run([], [item(detected: first)]), invalid);
    expect(() => run([], [item(account: 'fixture')]), invalid);
  });
  test('duplicate inventory and clock rollback reject', () {
    expect(() => run([], [item(), item()]), invalid);
    expect(
      () => run([item(detected: now.add(const Duration(days: 1)))], []),
      invalid,
    );
  });
  test('bounded inventory rejects excess before reconciliation', () {
    expect(() => run([], List.generate(65, (_) => item())), invalid);
  });
}

void _schemaCompatibilityTests() {
  const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const generation = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const other = 'cccccccccccccccccccccccccccccccc';
  final first = DateTime.utc(2026, 9, 1);
  final now = DateTime.utc(2026, 9, 30);
  final invalid = throwsA(isA<DriftQuarantineRecordException>());
  DriftQuarantineFileIdentity file(int inode) => DriftQuarantineFileIdentity(
    device: 1,
    inode: inode,
    generation: 2,
    birthSeconds: 3,
    birthNanoseconds: 4,
  );
  DriftQuarantineNativeIdentity native(int inode) =>
      DriftQuarantineNativeIdentity(
        directory: file(inode),
        database: file(inode + 1),
      );
  DriftQuarantineCase raw({
    String caseId = id,
    String artifact = generation,
    String entry = 'fixture',
    String? account = 'explicit',
    int inode = 10,
  }) => DriftQuarantineCase(
    caseId: caseId,
    artifactGeneration: artifact,
    relativeEntry: entry,
    activeAccountEntry: account,
    nativeIdentity: native(inode),
    firstDetectedUtc: now,
    lastObservedUtc: now,
    legacyAgeUnknown: true,
  );
  DriftQuarantineCase historical(
    int version, {
    DateTime? observed,
    String entry = 'fixture',
    String caseId = id,
    String artifact = generation,
    int inode = 10,
  }) => DriftQuarantineCase(
    caseId: caseId,
    artifactGeneration: artifact,
    relativeEntry: entry,
    activeAccountEntry: 'explicit',
    nativeIdentity: native(inode),
    firstDetectedUtc: first,
    lastObservedUtc: observed ?? first,
    legacyAgeUnknown: true,
    firstNoticeRecorded: true,
    daySevenReminderRecorded: true,
    phase: DriftQuarantinePhase.cleanupPending,
    disposition: DriftQuarantineDisposition.expiredOwnerPolicy,
    clockState: DriftQuarantineClockState(
      detectionClock: DriftQuarantineDetectionClock.corroborated,
      observedHighWaterUtc: observed ?? first,
      lastTrustedObservedUtc: first,
    ),
    fallbackState: version == 4
        ? DriftQuarantineFallbackState(
            caseId: caseId,
            artifactGeneration: artifact,
            nativeIdentity: native(inode),
            accountIdentity: id,
            accountEntry: 'explicit',
            introductionIdentity: generation,
            introductionUtc: first,
            startUtc: first.add(const Duration(days: 2)),
            origin: DriftQuarantineFallbackOrigin.lateObserved,
          )
        : null,
  );
  DriftQuarantineRecord run(
    DriftQuarantineRecord old,
    List<DriftQuarantineCase> scan,
  ) => reconcileDriftQuarantineInventory(
    committed: old,
    observations: scan,
    nowUtc: now,
    stateTrusted: true,
    inventoryTrusted: true,
    clockTrusted: true,
  );
  for (final version in [3, 4]) {
    for (final present in [true, false]) {
      test(
        'v$version ${present ? "present" : "missing"} case preserves schema and all history',
        () {
          final previous = historical(version);
          final old = DriftQuarantineRecord([previous], version: version);
          final before = old.encode();
          final result = run(old, present ? [raw()] : []);
          expect(result.version, version);
          final restored = DriftQuarantineRecord.decode(
            result.encode(),
          ).cases.single;
          expect(old.encode(), before);
          expect(restored.caseId, previous.caseId);
          expect(restored.artifactGeneration, previous.artifactGeneration);
          expect(restored.activeAccountEntry, previous.activeAccountEntry);
          expect(restored.nativeIdentity, previous.nativeIdentity);
          expect(restored.firstDetectedUtc, previous.firstDetectedUtc);
          expect(restored.legacyAgeUnknown, previous.legacyAgeUnknown);
          expect(restored.firstNoticeRecorded, isTrue);
          expect(restored.daySevenReminderRecorded, isTrue);
          expect(restored.phase, previous.phase);
          expect(restored.disposition, previous.disposition);
          expect(
            restored.clockState!.detectionClock,
            previous.clockState!.detectionClock,
          );
          expect(restored.clockState!.lastTrustedObservedUtc, first);
          expect(restored.lastObservedUtc, present ? now : first);
          expect(
            restored.clockState!.observedHighWaterUtc,
            present ? now : first,
          );
          if (version == 4) {
            expect(
              restored.fallbackState!.matches(previous.fallbackState!),
              isTrue,
            );
          } else {
            expect(restored.fallbackState, isNull);
          }
          if (!present)
            expect(result.encode(), before); // Missing is not resolved.
        },
      );
    }
    test(
      'v$version new raw observation stays unmapped with observed-only clock',
      () {
        final original = DriftQuarantineRecord([
          historical(version),
        ], version: version);
        final result = run(original, [
          raw(
            caseId: other,
            artifact: other,
            entry: 'new',
            account: null,
            inode: 20,
          ),
        ]);
        expect(result.version, version);
        final restored = DriftQuarantineRecord.decode(result.encode());
        final added = restored.cases.last;
        expect(added.firstDetectedUtc, now);
        expect(added.lastObservedUtc, now);
        expect(added.activeAccountEntry, isNull);
        expect(
          added.fallbackState,
          isNull,
        ); // Unknown, not proof of prior absence.
        expect(
          added.clockState!.detectionClock,
          DriftQuarantineDetectionClock.observed,
        );
        expect(added.clockState!.lastTrustedObservedUtc, isNull);
        expect(added.firstNoticeRecorded, isFalse);
        expect(added.daySevenReminderRecorded, isFalse);
        expect(added.phase, DriftQuarantinePhase.unresolved);
        expect(added.disposition, DriftQuarantineDisposition.none);
        expect(restored.cases.first.firstDetectedUtc, first);
        if (version == 4)
          expect(
            restored.cases.first.fallbackState!.startUtc,
            original.cases.first.fallbackState!.startUtc,
          );
      },
    );
    test('v$version replacement/native/account mismatch and rollback deny', () {
      final original = DriftQuarantineRecord([
        historical(version),
      ], version: version);
      for (final observation in [
        raw(caseId: other),
        raw(artifact: other),
        raw(inode: 30),
        raw(account: 'other'),
      ]) {
        expect(() => run(original, [observation]), invalid);
      }
      final future = DriftQuarantineRecord([
        historical(version, observed: now.add(const Duration(days: 1))),
      ], version: version);
      expect(() => run(future, []), invalid);
    });
    test(
      'v$version scan cannot import clock/fallback claims or inferred mapping',
      () {
        final empty = DriftQuarantineRecord([], version: version);
        expect(() => run(empty, [historical(version)]), invalid);
        expect(() => run(empty, [raw()]), invalid);
        expect(
          () => run(empty, [raw(account: null), raw(account: null)]),
          invalid,
        );
        expect(
          () => run(empty, List.generate(65, (_) => raw(account: null))),
          invalid,
        );
      },
    );
  }
  test('v1 and v2 empty snapshots are not silently upgraded', () {
    for (final version in [1, 2]) {
      final record = DriftQuarantineRecord([], version: version);
      expect(run(record, []).encode(), record.encode());
    }
  });
  test('v4 encoded result bounds are enforced before return', () {
    final oversized = DriftQuarantineRecord(
      List.generate(
        64,
        (index) => historical(
          4,
          caseId: index.toRadixString(16).padLeft(32, '0'),
          artifact: index.toRadixString(16).padLeft(32, '0'),
          entry: '${'é' * 250}$index',
          inode: 100 + index * 2,
        ),
      ),
      version: 4,
    );
    expect(() => run(oversized, []), invalid);
  });
}
