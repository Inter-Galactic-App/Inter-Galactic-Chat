import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_inventory.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_quarantine_record.dart';

void main() {
  final first = DateTime.utc(2026, 9, 1);
  final now = DateTime.utc(2026, 9, 30);
  DriftQuarantineFileIdentity file({
    int inode = 9007199254740993,
    int generation = 0,
    int seconds = 100,
    int nanos = 0,
    int device = 1,
  }) => DriftQuarantineFileIdentity(
    device: device,
    inode: inode,
    generation: generation,
    birthSeconds: seconds,
    birthNanoseconds: nanos,
  );
  DriftQuarantineNativeIdentity native({int inode = 9007199254740994}) =>
      DriftQuarantineNativeIdentity(
        directory: file(),
        database: file(inode: inode),
      );
  DriftQuarantineCase item({
    DriftQuarantineNativeIdentity? identity,
    String entry = 'fixture',
    String id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    String generation = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    DateTime? detected,
  }) => DriftQuarantineCase(
    caseId: id,
    artifactGeneration: generation,
    relativeEntry: entry,
    firstDetectedUtc: detected ?? first,
    lastObservedUtc: detected ?? first,
    nativeIdentity: identity,
    legacyAgeUnknown: true,
  );
  final invalid = throwsA(isA<DriftQuarantineRecordException>());
  DriftQuarantineRecord reconcile(
    DriftQuarantineCase old,
    DriftQuarantineCase seen,
  ) => reconcileDriftQuarantineInventory(
    committed: DriftQuarantineRecord([old]),
    observations: [seen],
    nowUtc: now,
    stateTrusted: true,
    inventoryTrusted: true,
    clockTrusted: true,
  );

  test(
    'native pair round trips without truncating inode above double precision',
    () {
      final restored = DriftQuarantineRecord.decode(
        DriftQuarantineRecord([item(identity: native())]).encode(),
      ).cases.single;
      expect(restored.nativeIdentity, native());
      expect(restored.nativeIdentity!.database.inode, 9007199254740994);
      expect(
        restored.observe(nowUtc: now).nativeIdentity,
        same(restored.nativeIdentity),
      );
      expect(restored.firstDetectedUtc, first);
    },
  );
  test(
    'v1 record remains unknown identity with original age and notice receipts',
    () {
      final record = DriftQuarantineRecord([
        item().observe(nowUtc: now, recordFirstNotice: true),
      ]);
      final json =
          jsonDecode(utf8.decode(record.encode())) as Map<String, dynamic>;
      json['version'] = 1;
      (json['cases'] as List).single.remove('native_identity');
      final restored = DriftQuarantineRecord.decode(
        utf8.encode(jsonEncode(json)),
      ).cases.single;
      expect(restored.nativeIdentity, isNull);
      expect(restored.firstDetectedUtc, first);
      expect(restored.firstNoticeRecorded, isTrue);
      expect(
        () => reconcile(restored, item(identity: native(), detected: now)),
        invalid,
      );
    },
  );
  test('same opaque token cannot hide replacement native DB identity', () {
    expect(
      () => reconcile(
        item(identity: native()),
        item(identity: native(inode: 9007199254740995), detected: now),
      ),
      invalid,
    );
  });
  test('matching identity preserves detection through observed restart', () {
    final old = DriftQuarantineRecord.decode(
      DriftQuarantineRecord([item(identity: native())]).encode(),
    ).cases.single;
    expect(
      reconcile(
        old,
        item(identity: native(), detected: now),
      ).cases.single.firstDetectedUtc,
      first,
    );
  });
  test('unknown identity cannot qualify even with all trust flags true', () {
    expect(() => reconcile(item(), item()), invalid);
    expect(
      () => reconcileDriftQuarantineInventory(
        committed: DriftQuarantineRecord([]),
        observations: [item(detected: now)],
        nowUtc: now,
        stateTrusted: true,
        inventoryTrusted: true,
        clockTrusted: true,
      ),
      invalid,
    );
  });
  test('duplicate native directory or database rejects', () {
    expect(
      () => DriftQuarantineRecord([
        item(identity: native()),
        item(
          identity: native(),
          entry: 'other',
          id: 'cccccccccccccccccccccccccccccccc',
          generation: 'dddddddddddddddddddddddddddddddd',
        ),
      ]),
      invalid,
    );
    for (final alias in [
      DriftQuarantineNativeIdentity(
        directory: file(),
        database: file(inode: 20),
      ),
      DriftQuarantineNativeIdentity(
        directory: file(inode: 21),
        database: native().database,
      ),
    ]) {
      expect(
        () => DriftQuarantineRecord([
          item(identity: native()),
          item(
            identity: alias,
            entry: 'other',
            id: 'cccccccccccccccccccccccccccccccc',
            generation: 'dddddddddddddddddddddddddddddddd',
          ),
        ]),
        invalid,
      );
    }
  });
  test('directory and database cannot claim the same native identity', () {
    expect(
      () => DriftQuarantineNativeIdentity(directory: file(), database: file()),
      invalid,
    );
  });
  test('numeric native bounds reject unsupported identities generically', () {
    for (final build in <DriftQuarantineFileIdentity Function()>[
      () => file(inode: 0),
      () => file(generation: -1),
      () => file(generation: 0x100000000),
      () => file(device: 0x80000000),
      () => file(device: -0x80000001),
      () => file(seconds: -1),
      () => file(nanos: -1),
      () => file(nanos: 1000000000),
    ]) {
      expect(build, invalid);
    }
  });
  test(
    'nested duplicate unknown or mistyped fields fail canonical validation',
    () {
      final text = utf8.decode(
        DriftQuarantineRecord([item(identity: native())]).encode(),
      );
      for (final altered in [
        text.replaceFirst('"device":1', '"device":1,"device":1'),
        text.replaceFirst('"device":1', '"extra":1,"device":1'),
        text.replaceFirst('"device":1', '"device":1.0'),
        text.replaceFirst('"directory":{', '"directory":null,"unused":{'),
      ]) {
        expect(
          () => DriftQuarantineRecord.decode(utf8.encode(altered)),
          invalid,
        );
      }
    },
  );
  test(
    'v2 missing native field is malformed not an unknown-identity reset',
    () {
      final json =
          jsonDecode(utf8.decode(DriftQuarantineRecord([item()]).encode()))
              as Map<String, dynamic>;
      (json['cases'] as List).single.remove('native_identity');
      expect(
        () => DriftQuarantineRecord.decode(utf8.encode(jsonEncode(json))),
        invalid,
      );
    },
  );
}
