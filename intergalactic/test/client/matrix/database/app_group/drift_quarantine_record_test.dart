import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_record.dart';

void main() {
  _v4CodecTests();
  final detected = DateTime.utc(2026, 9, 1);
  DriftQuarantineCase sample({String entry = 'synthetic-entry'}) =>
      DriftQuarantineCase(
        caseId: '0123456789abcdef0123456789abcdef',
        artifactGeneration: 'fedcba9876543210fedcba9876543210',
        relativeEntry: entry,
        firstDetectedUtc: detected,
        lastObservedUtc: detected,
        legacyAgeUnknown: true,
      );
  List<int> bytes() => DriftQuarantineRecord([sample()]).encode();
  final invalid = throwsA(isA<DriftQuarantineRecordException>());
  void rejectText(String text) =>
      expect(() => DriftQuarantineRecord.decode(utf8.encode(text)), invalid);

  test('v4 explicit empty candidate round trips without upgrading v3', () {
    final old = DriftQuarantineRecord([], version: 3);
    final original = old.encode();
    final candidate = DriftQuarantineRecord(old.cases, version: 4);
    expect(DriftQuarantineRecord.decode(candidate.encode()).version, 4);
    expect(old.encode(), original);
    expect(DriftQuarantineRecord.decode(original).version, 3);
  });

  test('v4 explicit candidate preserves historical notice and age fields', () {
    final old = DriftQuarantineRecord([
      sample().observe(nowUtc: detected, recordFirstNotice: true),
    ]).version3Candidate();
    final original = old.encode();
    final candidate = DriftQuarantineRecord(old.cases, version: 4);
    final restored = DriftQuarantineRecord.decode(
      candidate.encode(),
    ).cases.single;
    expect(restored.firstDetectedUtc, detected);
    expect(restored.lastObservedUtc, detected);
    expect(restored.firstNoticeRecorded, isTrue);
    expect(
      restored.clockState!.detectionClock,
      old.cases.single.clockState!.detectionClock,
    );
    expect(old.encode(), original);
  });

  test('canonical private state round trips, including unknown mapping', () {
    final parsed = DriftQuarantineRecord.decode(bytes()).cases.single;
    expect(parsed.firstDetectedUtc, detected);
    expect(parsed.activeAccountEntry, isNull);
    expect(parsed.legacyAgeUnknown, isTrue);
  });

  test('repeated observation and restart never renew detection time', () {
    var item = sample();
    for (var day = 2; day < 35; day++) {
      item = item.observe(nowUtc: DateTime.utc(2026, 9, day));
      item = DriftQuarantineRecord.decode(
        DriftQuarantineRecord([item]).encode(),
      ).cases.single;
      expect(item.firstDetectedUtc, detected);
      expect(item.artifactGeneration, sample().artifactGeneration);
    }
  });

  test(
    'pending disposition survives interruption but is not a safety proof',
    () {
      final item = sample().observe(
        nowUtc: DateTime.utc(2026, 10, 1),
        phase: DriftQuarantinePhase.cleanupPending,
        disposition: DriftQuarantineDisposition.expiredOwnerPolicy,
      );
      final restored = DriftQuarantineRecord.decode(
        DriftQuarantineRecord([item]).encode(),
      ).cases.single;
      expect(restored.phase, DriftQuarantinePhase.cleanupPending);
      expect(
        restored.disposition,
        DriftQuarantineDisposition.expiredOwnerPolicy,
      );
      expect(restored.firstDetectedUtc, detected);
    },
  );

  test('notice receipt remains recorded across observations', () {
    final item = sample().observe(nowUtc: detected, recordFirstNotice: true);
    expect(item.observe(nowUtc: detected).firstNoticeRecorded, isTrue);
    expect(
      () => sample().observe(nowUtc: detected, recordDaySevenReminder: true),
      invalid,
    );
  });

  test('rollback and resolved-case reopening are rejected', () {
    expect(
      () => sample().observe(
        nowUtc: detected.subtract(const Duration(seconds: 1)),
      ),
      invalid,
    );
    final resolved = sample().observe(
      nowUtc: detected,
      phase: DriftQuarantinePhase.resolved,
      disposition: DriftQuarantineDisposition.byteEquivalent,
    );
    expect(
      () => resolved.observe(
        nowUtc: detected,
        phase: DriftQuarantinePhase.unresolved,
      ),
      invalid,
    );
  });

  test('duplicate JSON fields, unknown fields and newer schema reject', () {
    final text = utf8.decode(bytes());
    rejectText(text.replaceFirst('"version":2', '"version":3,"version":2'));
    rejectText(text.replaceFirst('"version":2', '"version":3'));
    rejectText(text.replaceFirst('"version":2', '"version":2.0'));
    rejectText(text.replaceFirst('"version":2', '"extra":true,"version":2'));
    rejectText(
      text.replaceFirst(
        '"first_detected_ms":',
        '"first_detected_ms":0,"first_detected_ms":',
      ),
    );
    rejectText(
      text.replaceFirst(
        '"legacy_age_unknown":true',
        '"legacy_age_unknown":"true"',
      ),
    );
    rejectText(
      text.replaceFirst('"phase":"unresolved"', '"phase":"cleanupPending"'),
    );
  });

  test('duplicate case identities or entries are rejected', () {
    expect(() => DriftQuarantineRecord([sample(), sample()]), invalid);
  });

  test('path escapes and controls are rejected without disclosing entry', () {
    for (final entry in [
      '',
      '.',
      '..',
      '../secret',
      '/secret',
      'a/b',
      r'a\b',
      'x\u0000y',
      'x\ny',
    ]) {
      expect(() => sample(entry: entry), invalid);
    }
    expect(
      const DriftQuarantineRecordException().toString(),
      'DriftQuarantineRecordException',
    );
  });

  test('invalid UTF-8, truncation and oversized bytes reject', () {
    expect(() => DriftQuarantineRecord.decode([0xff]), invalid);
    expect(() => DriftQuarantineRecord.decode(bytes().sublist(0, 30)), invalid);
    expect(
      () => DriftQuarantineRecord.decode(
        List.filled(DriftQuarantineRecord.maxBytes + 1, 32),
      ),
      invalid,
    );
  });

  test('missing state is not an empty successful record', () {
    expect(() => DriftQuarantineRecord.decode([]), invalid);
    final empty = DriftQuarantineRecord.decode(
      DriftQuarantineRecord([]).encode(),
    );
    expect(empty.cases, isEmpty);
    expect(() => empty.cases.add(sample()), throwsUnsupportedError);
  });

  for (final version in [1, 2]) {
    test('v$version read preserves bytes; explicit v3 never renews dates', () {
      final old = DriftQuarantineRecord([
        sample().observe(
          nowUtc: detected.add(const Duration(days: 10)),
          recordFirstNotice: true,
          recordDaySevenReminder: true,
          phase: DriftQuarantinePhase.cleanupPending,
          disposition: DriftQuarantineDisposition.expiredOwnerPolicy,
        ),
      ], version: version);
      final original = old.encode();
      final parsed = DriftQuarantineRecord.decode(original);
      expect(parsed.version, version);
      expect(parsed.encode(), original);
      expect(parsed.cases.single.clockState, isNull);
      final upgraded = parsed.version3Candidate();
      expect(parsed.encode(), original);
      expect(upgraded.version, 3);
      final item = DriftQuarantineRecord.decode(upgraded.encode()).cases.single;
      final before = parsed.cases.single;
      expect(item.caseId, before.caseId);
      expect(item.artifactGeneration, before.artifactGeneration);
      expect(item.relativeEntry, before.relativeEntry);
      expect(item.activeAccountEntry, before.activeAccountEntry);
      expect(item.nativeIdentity, before.nativeIdentity);
      expect(item.firstDetectedUtc, before.firstDetectedUtc);
      expect(item.lastObservedUtc, before.lastObservedUtc);
      expect(item.legacyAgeUnknown, before.legacyAgeUnknown);
      expect(item.firstNoticeRecorded, isTrue);
      expect(item.daySevenReminderRecorded, isTrue);
      expect(item.phase, before.phase);
      expect(item.disposition, before.disposition);
      expect(
        item.clockState!.detectionClock,
        DriftQuarantineDetectionClock.observed,
      );
      expect(item.clockState!.lastTrustedObservedUtc, isNull);
      expect(item.clockState!.observedHighWaterUtc, before.lastObservedUtc);
      expect(upgraded.version3Candidate(), same(upgraded));
    });
  }
  test(
    'v3 repeated collision/rollback keeps original anchor and receipt fields',
    () {
      var item = DriftQuarantineRecord([
        sample().observe(nowUtc: detected, recordFirstNotice: true),
      ]).version3Candidate().cases.single;
      for (final day in [10, 5, 40, 0, 41]) {
        item = item.observeDeviceClock(detected.add(Duration(days: day)));
        item = DriftQuarantineRecord.decode(
          DriftQuarantineRecord([item], version: 3).encode(),
        ).cases.single;
        expect(item.firstDetectedUtc, detected);
        expect(item.artifactGeneration, sample().artifactGeneration);
        expect(item.firstNoticeRecorded, isTrue);
      }
      expect(item.lastObservedUtc, detected.add(const Duration(days: 41)));
      final before = item.clockState;
      final receipt = item.observe(
        nowUtc: item.lastObservedUtc,
        recordDaySevenReminder: true,
      );
      expect(receipt.clockState!.detectionClock, before!.detectionClock);
      expect(
        receipt.clockState!.lastTrustedObservedUtc,
        before.lastTrustedObservedUtc,
      );
      expect(
        receipt.clockState!.observedHighWaterUtc,
        before.observedHighWaterUtc,
      );
      expect(receipt.nativeIdentity, item.nativeIdentity);
      expect(receipt.phase, item.phase);
      expect(receipt.disposition, item.disposition);
    },
  );
  test(
    'v3 strict bounds, duplicate fields and invalid provenance fail closed',
    () {
      final text = utf8.decode(
        DriftQuarantineRecord([sample()]).version3Candidate().encode(),
      );
      for (final altered in [
        text.replaceFirst('"version":3', '"version":4'),
        text.replaceFirst(
          '"observed_high_water_ms":',
          '"observed_high_water_ms":0,"observed_high_water_ms":',
        ),
        text.replaceFirst(
          '"detection_clock":"observed"',
          '"detection_clock":"trusted"',
        ),
        text.replaceFirst(
          '"last_trusted_observed_ms":null',
          '"last_trusted_observed_ms":-1',
        ),
        text.replaceFirst(
          '"last_trusted_observed_ms":null',
          '"last_trusted_observed_ms":8640000000000001',
        ),
        text.replaceFirst(
          '"last_trusted_observed_ms":null',
          '"last_trusted_observed_ms":0',
        ),
        text.replaceFirst('"last_trusted_observed_ms":null', '"unknown":null'),
        text.replaceFirst('"version":3', '"version":2'),
      ]) {
        rejectText(altered);
      }
      final value = DriftQuarantineRecord([
        sample(),
      ]).version3Candidate().cases.single;
      expect(() => DriftQuarantineRecord([value]), invalid);
      expect(() => DriftQuarantineRecord([sample()], version: 3), invalid);
      expect(() => value.observeDeviceClock(detected.toLocal()), invalid);
      expect(
        () => value.observeDeviceClock(
          detected.add(const Duration(microseconds: 1)),
        ),
        invalid,
      );
    },
  );

  test('v3 case count and encoded byte limits are runtime checks', () {
    DriftQuarantineCase largeCase(int index) {
      final key = index.toRadixString(16).padLeft(32, '0');
      return DriftQuarantineCase(
        caseId: key,
        artifactGeneration: key,
        relativeEntry: '${'é' * 250}$index',
        activeAccountEntry: 'é' * 255,
        firstDetectedUtc: detected,
        lastObservedUtc: detected,
        clockState: DriftQuarantineClockState(
          detectionClock: DriftQuarantineDetectionClock.observed,
          observedHighWaterUtc: detected,
        ),
      );
    }

    expect(
      () => DriftQuarantineRecord(
        List.generate(DriftQuarantineRecord.maxCases + 1, largeCase),
        version: 3,
      ),
      invalid,
    );
    final oversized = DriftQuarantineRecord(
      List.generate(DriftQuarantineRecord.maxCases, largeCase),
      version: 3,
    );
    expect(oversized.encode, invalid);
  });

  test(
    'v3 high-water cannot differ from legacy observation or precede anchor',
    () {
      final json =
          jsonDecode(
                utf8.decode(
                  DriftQuarantineRecord([
                    sample(),
                  ]).version3Candidate().encode(),
                ),
              )
              as Map<String, dynamic>;
      final item = (json['cases'] as List).single as Map<String, dynamic>;
      for (final highWater in [
        detected.millisecondsSinceEpoch - 1,
        detected.millisecondsSinceEpoch + 1,
        driftQuarantineMaxUtcMilliseconds + 1,
        1.0,
      ]) {
        item['observed_high_water_ms'] = highWater;
        rejectText(jsonEncode(json));
      }
    },
  );
}

void _v4CodecTests() {
  const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const c = 'cccccccccccccccccccccccccccccccc';
  const d = 'dddddddddddddddddddddddddddddddd';
  final first = DateTime.utc(2026, 9, 1);
  final later = first.add(const Duration(days: 100));
  final invalid = throwsA(isA<DriftQuarantineRecordException>());
  DriftQuarantineFileIdentity file(int inode) => DriftQuarantineFileIdentity(
    device: 1,
    inode: inode,
    generation: 2,
    birthSeconds: 3,
    birthNanoseconds: 4,
  );
  final native = DriftQuarantineNativeIdentity(
    directory: file(1),
    database: file(2),
  );
  DriftQuarantineFallbackState fallback({
    DateTime? start,
    String account = c,
    String entry = 'account',
    String caseId = a,
    String artifact = b,
    DriftQuarantineNativeIdentity? identity,
    DriftQuarantineFallbackOrigin origin =
        DriftQuarantineFallbackOrigin.lateObserved,
  }) => DriftQuarantineFallbackState(
    caseId: caseId,
    artifactGeneration: artifact,
    nativeIdentity: identity ?? native,
    accountIdentity: account,
    accountEntry: entry,
    introductionIdentity: d,
    introductionUtc: first,
    startUtc: start ?? later,
    origin: origin,
  );
  DriftQuarantineCase item({DriftQuarantineFallbackState? state}) =>
      DriftQuarantineCase(
        caseId: a,
        artifactGeneration: b,
        relativeEntry: 'fixture',
        activeAccountEntry: 'account',
        nativeIdentity: native,
        firstDetectedUtc: first,
        lastObservedUtc: later,
        clockState: DriftQuarantineClockState(
          detectionClock: DriftQuarantineDetectionClock.corroborated,
          observedHighWaterUtc: later,
          lastTrustedObservedUtc: first,
        ),
        fallbackState: state,
        firstNoticeRecorded: true,
        daySevenReminderRecorded: true,
        phase: DriftQuarantinePhase.safetyBlocked,
        disposition: DriftQuarantineDisposition.byteEquivalent,
      );
  for (final version in [1, 2, 3]) {
    test('v$version stays canonical; v4 upgrade adds no inferred fallback', () {
      final source = item();
      final historical = DriftQuarantineRecord([
        version == 3
            ? source
            : DriftQuarantineCase(
                caseId: source.caseId,
                artifactGeneration: source.artifactGeneration,
                relativeEntry: source.relativeEntry,
                activeAccountEntry: source.activeAccountEntry,
                nativeIdentity: version == 1 ? null : source.nativeIdentity,
                firstDetectedUtc: source.firstDetectedUtc,
                lastObservedUtc: source.lastObservedUtc,
                firstNoticeRecorded: source.firstNoticeRecorded,
                daySevenReminderRecorded: source.daySevenReminderRecorded,
                phase: source.phase,
                disposition: source.disposition,
              ),
      ], version: version);
      final raw = historical.encode();
      final decoded = DriftQuarantineRecord.decode(raw);
      expect(decoded.encode(), raw);
      expect(decoded.version, version);
      final candidate = decoded.version4Candidate();
      expect(decoded.encode(), raw);
      expect(candidate.version, 4);
      final restored = DriftQuarantineRecord.decode(
        candidate.encode(),
      ).cases.single;
      expect(restored.fallbackState, isNull);
      expect(restored.firstDetectedUtc, source.firstDetectedUtc);
      expect(restored.lastObservedUtc, source.lastObservedUtc);
      expect(restored.firstNoticeRecorded, source.firstNoticeRecorded);
      expect(
        restored.daySevenReminderRecorded,
        source.daySevenReminderRecorded,
      );
      expect(restored.disposition, source.disposition);
      expect(restored.phase, source.phase);
      expect(restored.nativeIdentity, historical.cases.single.nativeIdentity);
      if (version == 3) {
        expect(
          restored.clockState!.detectionClock,
          source.clockState!.detectionClock,
        );
        expect(
          restored.clockState!.lastTrustedObservedUtc,
          source.clockState!.lastTrustedObservedUtc,
        );
      }
    });
  }
  test(
    'v4 mapping roundtrip and observations preserve original state and anchor',
    () {
      final original = item(state: fallback());
      var value = original;
      for (final day in [101, 50, 200, 0]) {
        value = value.observeDeviceClock(first.add(Duration(days: day)));
        value = DriftQuarantineRecord.decode(
          DriftQuarantineRecord([value], version: 4).encode(),
        ).cases.single;
        expect(value.fallbackState!.matches(original.fallbackState!), isTrue);
        expect(value.firstDetectedUtc, original.firstDetectedUtc);
        expect(value.firstNoticeRecorded, isTrue);
        expect(value.daySevenReminderRecorded, isTrue);
        expect(value.phase, original.phase);
        expect(value.disposition, original.disposition);
        expect(
          value.clockState!.detectionClock,
          original.clockState!.detectionClock,
        );
      }
      expect(
        value.observe(nowUtc: value.lastObservedUtc).fallbackState,
        same(value.fallbackState),
      );
      expect(
        () => value.fallbackCandidate(
          fallback(start: later.add(const Duration(days: 1))),
        ),
        invalid,
      );
      expect(() => DriftQuarantineRecord([original], version: 3), invalid);
    },
  );
  test(
    'v4 replacement/recycle/account alias cannot reuse serialized anchor',
    () {
      for (final state in [
        fallback(caseId: c),
        fallback(artifact: c),
        fallback(entry: 'other'),
        fallback(
          identity: DriftQuarantineNativeIdentity(
            directory: file(3),
            database: file(2),
          ),
        ),
        fallback(
          identity: DriftQuarantineNativeIdentity(
            directory: file(1),
            database: file(3),
          ),
        ),
      ]) {
        expect(() => item(state: state), invalid);
      }
    },
  );
  test('v4 strict nested fields/duplicates/bounds reject generically', () {
    final text = utf8.decode(
      DriftQuarantineRecord([item(state: fallback())], version: 4).encode(),
    );
    for (final altered in [
      text.replaceFirst('"version":4', '"version":5'),
      text.replaceFirst(
        '"fallback_start":',
        '"fallback_start":null,"fallback_start":',
      ),
      text.replaceFirst('"start_ms":', '"start_ms":0,"start_ms":'),
      text.replaceFirst('"origin":"lateObserved"', '"origin":"trusted"'),
      text.replaceFirst(
        '"origin":"lateObserved"',
        '"extra":true,"origin":"lateObserved"',
      ),
      text.replaceFirst(
        '"start_ms":${later.millisecondsSinceEpoch}',
        '"start_ms":-1',
      ),
      text.replaceFirst(
        '"start_ms":${later.millisecondsSinceEpoch}',
        '"start_ms":8640000000000001',
      ),
      text.replaceFirst(
        '"start_ms":${later.millisecondsSinceEpoch}',
        '"start_ms":1.0',
      ),
      text.replaceFirst('"fallback_start":', '"renamed":'),
      text.replaceFirst('"version":4', '"version":3'),
    ]) {
      expect(() => DriftQuarantineRecord.decode(utf8.encode(altered)), invalid);
    }
    expect(() => fallback(start: later.toLocal()), invalid);
    expect(
      () => fallback(start: later.add(const Duration(microseconds: 1))),
      invalid,
    );
    expect(() => fallback(account: 'PRIVATE'), invalid);
    expect(
      () => fallback(
        start: later,
        origin: DriftQuarantineFallbackOrigin.introductionRoster,
      ),
      invalid,
    );
    expect(
      () => fallback(
        start: first.subtract(const Duration(days: 1)),
        origin: DriftQuarantineFallbackOrigin.newCreation,
      ),
      invalid,
    );
    expect(
      const DriftQuarantineRecordException().toString(),
      'DriftQuarantineRecordException',
    );
  });
}
