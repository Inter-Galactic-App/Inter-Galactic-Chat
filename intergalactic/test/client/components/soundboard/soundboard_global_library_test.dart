import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';

/// U5 (account-global soundboard library) reference-document semantics.
///
/// The document lives in account data, so every device on the account writes
/// the same key. These tests pin the properties that keep concurrent devices
/// from destroying each other's entries, and that keep the library a set of
/// references rather than a copy of anyone's sounds.
void main() {
  SoundboardGlobalPackReference ref(
    String space,
    String pack, {
    DateTime? at,
  }) => SoundboardGlobalPackReference(
    sourceSpaceId: space,
    packId: pack,
    enabledAt: at,
  );

  group('reference parsing', () {
    test('round-trips through account-data content', () {
      final original = ref(
        '!a:example.org',
        'pack-1',
        at: DateTime.utc(2026, 7, 20),
      );
      final parsed = SoundboardGlobalPackReference.fromContent(
        original.toContent(),
      );

      expect(parsed, isNotNull);
      expect(parsed!.sourceSpaceId, '!a:example.org');
      expect(parsed.packId, 'pack-1');
      expect(parsed.enabledAt, DateTime.utc(2026, 7, 20));
    });

    test('a reference carries no sounds, only the source coordinates', () {
      expect(ref('!a:example.org', 'pack-1').toContent().keys, [
        'source_space_id',
        'pack_id',
      ]);
    });

    test('entries missing either coordinate are rejected, not guessed', () {
      expect(
        SoundboardGlobalPackReference.fromContent({'pack_id': 'pack-1'}),
        isNull,
      );
      expect(
        SoundboardGlobalPackReference.fromContent({
          'source_space_id': '!a:example.org',
        }),
        isNull,
      );
      expect(
        SoundboardGlobalPackReference.fromContent({
          'source_space_id': '',
          'pack_id': 'pack-1',
        }),
        isNull,
      );
      expect(SoundboardGlobalPackReference.fromContent('nonsense'), isNull);
    });

    test('one malformed entry does not discard the readable ones', () {
      final library = SoundboardGlobalLibrary.fromContent({
        'packs': [
          {'source_space_id': '!a:example.org', 'pack_id': 'pack-1'},
          'garbage',
          {'pack_id': 'no-space'},
          {'source_space_id': '!b:example.org', 'pack_id': 'pack-2'},
        ],
      });

      expect(library.references.map((r) => r.key), [
        '["!a:example.org","pack-1"]',
        '["!b:example.org","pack-2"]',
      ]);
    });

    test('a missing or malformed document reads as empty, never throws', () {
      expect(SoundboardGlobalLibrary.fromContent(null).references, isEmpty);
      expect(SoundboardGlobalLibrary.fromContent({}).references, isEmpty);
      expect(
        SoundboardGlobalLibrary.fromContent({'packs': 'nope'}).references,
        isEmpty,
      );
    });

    test('duplicate entries collapse to one', () {
      final library = SoundboardGlobalLibrary.fromContent({
        'packs': [
          {'source_space_id': '!a:example.org', 'pack_id': 'pack-1'},
          {'source_space_id': '!a:example.org', 'pack_id': 'pack-1'},
        ],
      });

      expect(library.references, hasLength(1));
    });

    test('the same pack id in two spaces is two distinct references', () {
      final library = const SoundboardGlobalLibrary()
          .withReference(ref('!a:example.org', 'pack-1'))
          .withReference(ref('!b:example.org', 'pack-1'));

      expect(library.references, hasLength(2));
      expect(library.contains('!a:example.org', 'pack-1'), isTrue);
      expect(library.contains('!b:example.org', 'pack-1'), isTrue);
    });

    test('reference keys cannot collide across coordinate boundaries', () {
      final first = ref('!a:example.org', 'pack|part');
      final second = ref('!a:example.org|pack', 'part');

      expect(first.key, isNot(second.key));
      expect(
        const SoundboardGlobalLibrary()
            .withReference(first)
            .withReference(second)
            .references,
        hasLength(2),
      );
    });
  });

  group('reference lifecycle', () {
    test('disabling one pack preserves every unrelated reference', () {
      final library = const SoundboardGlobalLibrary()
          .withReference(ref('!a:example.org', 'pack-1'))
          .withReference(ref('!a:example.org', 'pack-2'))
          .withReference(ref('!b:example.org', 'pack-3'));

      final after = library.withoutReference('!a:example.org', 'pack-2');

      expect(after.references.map((r) => r.key), [
        '["!a:example.org","pack-1"]',
        '["!b:example.org","pack-3"]',
      ]);
    });

    test('re-enabling a pack replaces rather than duplicates it', () {
      final library = const SoundboardGlobalLibrary()
          .withReference(
            ref('!a:example.org', 'pack-1', at: DateTime.utc(2026, 1, 1)),
          )
          .withReference(
            ref('!a:example.org', 'pack-1', at: DateTime.utc(2026, 7, 1)),
          );

      expect(library.references, hasLength(1));
      expect(library.references.single.enabledAt, DateTime.utc(2026, 7, 1));
    });

    test('referencesFor scopes to one source space', () {
      final library = const SoundboardGlobalLibrary()
          .withReference(ref('!a:example.org', 'pack-1'))
          .withReference(ref('!b:example.org', 'pack-2'));

      expect(library.referencesFor('!a:example.org').map((r) => r.packId), [
        'pack-1',
      ]);
    });
  });

  group('concurrent device merge', () {
    test(
      'a write rebased on newer account data keeps the other device\'s entry',
      () {
        // This device read a document with pack-1 and enabled pack-2...
        final added = ref('!a:example.org', 'pack-2');
        final local = const SoundboardGlobalLibrary()
            .withReference(ref('!a:example.org', 'pack-1'))
            .withReference(added);

        // ...while another device independently enabled pack-3.
        final latest = const SoundboardGlobalLibrary()
            .withReference(ref('!a:example.org', 'pack-1'))
            .withReference(ref('!c:example.org', 'pack-3'));

        final merged = local.mergeWith(latest, added: [added]);

        expect(merged.references.map((r) => r.key).toList()..sort(), [
          '["!a:example.org","pack-1"]',
          '["!a:example.org","pack-2"]',
          '["!c:example.org","pack-3"]',
        ]);
      },
    );

    test('a disable survives a rebase without resurrecting the entry', () {
      final latest = const SoundboardGlobalLibrary()
          .withReference(ref('!a:example.org', 'pack-1'))
          .withReference(ref('!a:example.org', 'pack-2'));

      final merged = const SoundboardGlobalLibrary().mergeWith(
        latest,
        removedKeys: [
          SoundboardGlobalPackReference.keyFor('!a:example.org', 'pack-1'),
        ],
      );

      expect(merged.references.map((r) => r.key), [
        '["!a:example.org","pack-2"]',
      ]);
    });

    test(
      'interleaved enable and disable from two devices both take effect',
      () {
        // Another device disabled pack-1 and enabled pack-3 since our read.
        final latest = const SoundboardGlobalLibrary().withReference(
          ref('!c:example.org', 'pack-3'),
        );

        // We are enabling pack-2 and disabling nothing.
        final added = ref('!a:example.org', 'pack-2');
        final merged = const SoundboardGlobalLibrary().mergeWith(
          latest,
          added: [added],
        );

        // Their disable of pack-1 is respected (it is absent from latest) and
        // their enable of pack-3 survives alongside our pack-2.
        expect(merged.contains('!a:example.org', 'pack-1'), isFalse);
        expect(merged.contains('!c:example.org', 'pack-3'), isTrue);
        expect(merged.contains('!a:example.org', 'pack-2'), isTrue);
      },
    );

    test('a stale rebase never drops entries it does not know about', () {
      // Worst case: this device read an empty document, then three unrelated
      // references landed. Merging an unrelated addition must not clear them.
      final latest = const SoundboardGlobalLibrary()
          .withReference(ref('!a:example.org', 'pack-1'))
          .withReference(ref('!b:example.org', 'pack-2'))
          .withReference(ref('!c:example.org', 'pack-3'));

      final merged = const SoundboardGlobalLibrary().mergeWith(
        latest,
        added: [ref('!d:example.org', 'pack-4')],
      );

      expect(merged.references, hasLength(4));
    });

    test('merging changes nothing when this device changed nothing', () {
      final latest = const SoundboardGlobalLibrary()
          .withReference(ref('!a:example.org', 'pack-1'))
          .withReference(ref('!b:example.org', 'pack-2'));

      final merged = const SoundboardGlobalLibrary().mergeWith(latest);

      expect(merged.references.map((r) => r.key).toList()..sort(), [
        '["!a:example.org","pack-1"]',
        '["!b:example.org","pack-2"]',
      ]);
    });
  });

  test('the serialized document survives a full write/read cycle', () {
    final library = const SoundboardGlobalLibrary()
        .withReference(
          ref('!a:example.org', 'pack-1', at: DateTime.utc(2026, 7, 20)),
        )
        .withReference(ref('!b:example.org', 'pack-2'));

    final reparsed = SoundboardGlobalLibrary.fromContent(library.toContent());

    expect(reparsed.references.map((r) => r.key).toList()..sort(), [
      '["!a:example.org","pack-1"]',
      '["!b:example.org","pack-2"]',
    ]);
    expect(
      reparsed.references.firstWhere((r) => r.packId == 'pack-1').enabledAt,
      DateTime.utc(2026, 7, 20),
    );
  });
}
