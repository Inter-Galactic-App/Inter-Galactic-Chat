import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_io.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';

void main() {
  test(
    'draft store saves, loads, reads, and deletes local PNG drafts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'intergalactic-emoticon-drafts-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final store = createEmoticonDraftStore(rootDirectory: directory);
      final bytes = _transparentPng();
      final draft = await store.saveDraft(
        shortcode: 'party',
        pngBytes: bytes,
        thumbnailBytes: bytes,
        backend: ImageCutoutBackendType.localEdgeSegmentation,
        width: 8,
        height: 8,
        sourceImageHash: 'source-hash',
        packId: 'personal',
      );

      expect(await File(draft.outputPngPath).exists(), isTrue);
      expect(await File(draft.thumbnailPath).exists(), isTrue);
      expect(draft.sourceImageHash, 'source-hash');
      expect(draft.packId, 'personal');

      final drafts = await store.listDrafts();
      expect(drafts, hasLength(1));
      expect(drafts.single.shortcode, 'party');

      final loaded = await store.loadDraft(draft.id);
      expect(loaded, isNotNull);
      expect(loaded!.draft.id, draft.id);
      expect(loaded.pngBytes, bytes);
      expect(loaded.thumbnailBytes, bytes);

      expect(await store.readDraftPng(draft.id), bytes);
      expect(await store.readDraftThumbnail(draft.id), bytes);
      expect(await store.loadDraft('../${draft.id}'), isNull);
      expect(await store.readDraftPng('../${draft.id}'), isNull);
      expect(await store.readDraftThumbnail('../${draft.id}'), isNull);

      await store.deleteDraft('');
      await store.deleteDraft('../${draft.id}');
      expect(await store.listDrafts(), hasLength(1));

      await store.deleteDraft(draft.id);
      expect(await store.listDrafts(), isEmpty);
      expect(await store.loadDraft(draft.id), isNull);
      expect(await store.readDraftPng(draft.id), isNull);
      expect(await store.readDraftThumbnail(draft.id), isNull);
    },
  );

  test('draft deletion does not remove overlapping draft ids', () async {
    final directory = await Directory.systemTemp.createTemp(
      'intergalactic-emoticon-drafts-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final store = createEmoticonDraftStore(rootDirectory: directory);
    final abcFiles = [
      File('${directory.path}/abc.json'),
      File('${directory.path}/abc-party.png'),
      File('${directory.path}/abc-party-thumb.png'),
    ];
    final abcdFiles = [
      File('${directory.path}/abcd.json'),
      File('${directory.path}/abcd-party.png'),
      File('${directory.path}/abcd-party-thumb.png'),
    ];

    for (final file in [...abcFiles, ...abcdFiles]) {
      await file.writeAsString('draft');
    }

    await store.deleteDraft('abc');

    for (final file in abcFiles) {
      expect(await file.exists(), isFalse);
    }
    for (final file in abcdFiles) {
      expect(await file.exists(), isTrue);
    }
  });
}

Uint8List _transparentPng() {
  final image = img.Image(width: 8, height: 8, numChannels: 4)
    ..clear(img.ColorRgba8(0, 0, 0, 0));
  for (var y = 2; y < 6; y++) {
    for (var x = 2; x < 6; x++) {
      image.setPixelRgba(x, y, 255, 0, 0, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
