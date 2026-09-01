import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';
import 'package:intergalactic/client/components/inbound_share/ios_inbound_share_stager.dart';

void main() {
  late Directory session;
  const stager = IosInboundShareStager();
  const token = 'a1b2c3d4e5f60718';

  setUp(() async {
    session = await Directory.systemTemp.createTemp('ios_share_session');
  });
  tearDown(() async {
    if (await session.exists()) await session.delete(recursive: true);
  });

  Future<void> writeManifest(Object? value) async {
    await File(
      '${session.path}${Platform.pathSeparator}${IosInboundShareStager.manifestFileName}',
    ).writeAsString(value is String ? value : jsonEncode(value));
  }

  Future<File> writeItem(String name, List<int> bytes) async {
    final file = File('${session.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('reads text and file items into a payload', () async {
    await writeItem('item_000.bin', List.filled(12, 7));
    await writeManifest({
      'schemaVersion': 1,
      'body': 'look at this',
      'items': [
        {
          'name': 'photo.jpg',
          'file': 'item_000.bin',
          'size': 12,
          'mimeType': 'image/jpeg',
        },
      ],
    });

    final payload = await stager.read(session.path, token: token);
    expect(payload, isNotNull);
    expect(payload!.stagingToken, token);
    expect(payload.body, 'look at this');
    expect(payload.items, hasLength(2));
    expect(payload.items.first.kind, InboundShareItemKind.text);

    final file = payload.items.last.file!;
    expect(file.displayName, 'photo.jpg');
    expect(file.size, 12);
    expect(file.mimeType, 'image/jpeg');
    expect(
      file.stagingPath,
      '${session.path}${Platform.pathSeparator}item_000.bin',
    );
    expect(file.isUsable, isTrue);
  });

  test('surfaces a failed entry alongside usable ones', () async {
    await writeItem('item_000.bin', const [1, 2, 3]);
    await writeManifest({
      'schemaVersion': 1,
      'items': [
        {'name': 'ok.png', 'file': 'item_000.bin', 'size': 3},
        {'name': 'big.mov', 'failure': 'Item exceeded the per-share limit.'},
      ],
    });

    final payload = await stager.read(session.path, token: token);
    // The user should be told something did not come through, rather than the
    // failed item vanishing from a share that otherwise succeeded.
    expect(payload?.items, hasLength(2));
    final failed = payload!.items.last.file!;
    expect(failed.displayName, 'big.mov');
    expect(failed.failure, isNotNull);
    expect(failed.isUsable, isFalse);
    expect(payload.items.first.file!.isUsable, isTrue);
  });

  test('an all-failed share yields nothing to review', () async {
    // Matches AndroidInboundShareStager: a payload with no usable content is
    // dropped rather than opening an empty review sheet.
    await writeManifest({
      'schemaVersion': 1,
      'items': [
        {'name': 'big.mov', 'failure': 'Item exceeded the per-share limit.'},
      ],
    });
    expect(await stager.read(session.path, token: token), isNull);
  });

  test('returns null when there is no manifest', () async {
    expect(await stager.read(session.path, token: token), isNull);
  });

  test('returns null on a truncated manifest', () async {
    // The shape of "the extension was killed mid-write".
    await writeManifest('{"schemaVersion": 1, "items": [');
    expect(await stager.read(session.path, token: token), isNull);
  });

  test('refuses an unknown schema version rather than guessing', () async {
    await writeItem('item_000.bin', const [1]);
    await writeManifest({
      'schemaVersion': 2,
      'items': [
        {'name': 'a', 'file': 'item_000.bin', 'size': 1},
      ],
    });
    expect(await stager.read(session.path, token: token), isNull);
  });

  test('returns null when nothing usable remains', () async {
    await writeManifest({'schemaVersion': 1, 'items': <Object?>[]});
    expect(await stager.read(session.path, token: token), isNull);
    await writeManifest({'schemaVersion': 1, 'body': '   '});
    expect(await stager.read(session.path, token: token), isNull);
  });

  group('file references are confined to the session root', () {
    // The manifest is written by a separate process, so an escaping `file` is
    // the one field here that could reach arbitrary app data.
    for (final escape in <String>[
      '../../../../etc/passwd',
      '..',
      '.',
      'nested/item.bin',
      r'nested\item.bin',
      '/etc/passwd',
      '',
    ]) {
      test('drops "$escape"', () async {
        await writeManifest({
          'schemaVersion': 1,
          'items': [
            {'name': 'x', 'file': escape, 'size': 1},
          ],
        });
        expect(
          await stager.read(session.path, token: token),
          isNull,
          reason: 'escaping reference "$escape" must not resolve',
        );
      });
    }

    test('drops only the escaping entry and keeps the valid one', () async {
      // Every single-item case above returns null for two indistinguishable
      // reasons - the entry was dropped, or the whole manifest was refused. A
      // mixed manifest separates them, so a regression that discards a share
      // because one reference is odd cannot pass silently.
      await writeItem('item_000.bin', const [1, 2, 3]);
      await writeManifest({
        'schemaVersion': 1,
        'items': [
          {'name': 'escape', 'file': '../../../../etc/passwd', 'size': 1},
          {'name': 'ok.png', 'file': 'item_000.bin', 'size': 3},
        ],
      });

      final payload = await stager.read(session.path, token: token);
      expect(payload, isNotNull);
      expect(payload!.items, hasLength(1));
      expect(payload.items.single.file!.displayName, 'ok.png');
      expect(
        payload.items.single.file!.stagingPath,
        '${session.path}${Platform.pathSeparator}item_000.bin',
      );
    });
  });

  test('drops an entry with a missing or negative size', () async {
    await writeItem('item_000.bin', const [1]);
    await writeManifest({
      'schemaVersion': 1,
      'items': [
        {'name': 'a', 'file': 'item_000.bin'},
        {'name': 'b', 'file': 'item_000.bin', 'size': -1},
        {'name': 'c', 'file': 'item_000.bin', 'size': '3'},
      ],
    });
    expect(await stager.read(session.path, token: token), isNull);
  });

  test('falls back to a safe display name', () async {
    await writeItem('item_000.bin', const [1, 2]);
    await writeManifest({
      'schemaVersion': 1,
      'items': [
        {'file': 'item_000.bin', 'size': 2},
      ],
    });
    final payload = await stager.read(session.path, token: token);
    expect(payload!.items.single.file!.displayName, 'shared-file');
  });

  test('ignores non-map entries and a non-list items field', () async {
    await writeItem('item_000.bin', const [1]);
    await writeManifest({
      'schemaVersion': 1,
      'body': 'text survives',
      'items': ['nope', 42, null],
    });
    final payload = await stager.read(session.path, token: token);
    expect(payload!.items, hasLength(1));
    expect(payload.items.single.kind, InboundShareItemKind.text);

    await writeManifest({
      'schemaVersion': 1,
      'body': 'still fine',
      'items': 'oops',
    });
    expect((await stager.read(session.path, token: token))!.body, 'still fine');
  });

  group('preselected conversation', () {
    test('carries conversationId through as preselectedRoomId', () async {
      await writeItem('item_000.bin', const [1, 2, 3]);
      await writeManifest({
        'schemaVersion': 1,
        'conversationId': '!room:example.org',
        'items': [
          {'name': 'a.png', 'file': 'item_000.bin', 'size': 3},
        ],
      });
      final payload = await stager.read(session.path, token: token);
      expect(payload!.preselectedRoomId, '!room:example.org');
    });

    test('is null when the manifest omits it', () async {
      // A manifest written before the field existed must still read cleanly at
      // the same schemaVersion.
      await writeItem('item_000.bin', const [1]);
      await writeManifest({
        'schemaVersion': 1,
        'items': [
          {'name': 'a', 'file': 'item_000.bin', 'size': 1},
        ],
      });
      expect(
        (await stager.read(session.path, token: token))!.preselectedRoomId,
        isNull,
      );
    });

    test('is null when blank or not a string', () async {
      await writeItem('item_000.bin', const [1]);
      for (final bad in <Object?>['', '   ', 42, <String>[]]) {
        await writeManifest({
          'schemaVersion': 1,
          'conversationId': bad,
          'items': [
            {'name': 'a', 'file': 'item_000.bin', 'size': 1},
          ],
        });
        expect(
          (await stager.read(session.path, token: token))!.preselectedRoomId,
          isNull,
          reason: 'conversationId "$bad" must not become a destination',
        );
      }
    });
  });
}
