import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_image_pack_compatibility.dart';

void main() {
  group('MatrixImagePackCompatibility', () {
    test(
      'keeps legacy-only room packs while stable state wins on duplicates',
      () {
        final states = MatrixImagePackCompatibility.mergeRoomPackStates(
          legacy: {
            'legacy-only': {
              'pack': {'display_name': 'Legacy'},
            },
            'shared': {
              'pack': {'display_name': 'Legacy copy'},
            },
          },
          stable: {
            'stable-only': {
              'pack': {'display_name': 'Stable'},
            },
            'shared': {
              'pack': {'display_name': 'Stable copy'},
            },
          },
        );

        expect(
          states.keys,
          containsAll(['legacy-only', 'stable-only', 'shared']),
        );
        expect(states['shared']!['pack']['display_name'], 'Stable copy');
      },
    );

    test('adds a global reference without dropping opaque room data', () {
      final updated = MatrixImagePackCompatibility.withGlobalPackReference(
        content: {
          'rooms': {
            '!existing:example.org': {
              'existing-pack': {'future_property': 'preserve'},
            },
          },
          'future_top_level': {'preserve': true},
        },
        roomId: '!new:example.org',
        packKey: 'new-pack',
        enabled: true,
      );

      expect(updated['rooms']['!existing:example.org']['existing-pack'], {
        'future_property': 'preserve',
      });
      expect(updated['rooms']['!new:example.org']['new-pack'], isEmpty);
      expect(updated['future_top_level'], {'preserve': true});
    });

    test('removes a global reference and leaves the other packs alone', () {
      // Only the enabled: true branch was covered, yet removeEmoticonRoomPack
      // in matrix_client_extensions.dart depends on this one - so the removal
      // path shipped with no test at all.
      final updated = MatrixImagePackCompatibility.withGlobalPackReference(
        content: {
          'rooms': {
            '!room:example.org': {
              'keep-me': {'future_property': 'preserve'},
              'drop-me': <String, dynamic>{},
            },
            '!other:example.org': {'untouched': <String, dynamic>{}},
          },
        },
        roomId: '!room:example.org',
        packKey: 'drop-me',
        enabled: false,
      );

      expect(updated['rooms']['!room:example.org'], {
        'keep-me': {'future_property': 'preserve'},
      });
      expect(updated['rooms']['!other:example.org'], {
        'untouched': <String, dynamic>{},
      });
    });

    test(
      'removing the last pack leaves an empty room map, not a missing one',
      () {
        // The room key survives with an empty map. Recorded because a reader
        // could reasonably expect the room to disappear, and callers must not
        // treat "present but empty" as "still has packs".
        final updated = MatrixImagePackCompatibility.withGlobalPackReference(
          content: {
            'rooms': {
              '!room:example.org': {'only-pack': <String, dynamic>{}},
            },
          },
          roomId: '!room:example.org',
          packKey: 'only-pack',
          enabled: false,
        );

        expect(updated['rooms'].containsKey('!room:example.org'), isTrue);
        expect(updated['rooms']['!room:example.org'], isEmpty);
        expect(
          MatrixImagePackCompatibility.hasGlobalPackReference(
            updated,
            '!room:example.org',
            'only-pack',
          ),
          isFalse,
        );
      },
    );

    test('hasGlobalPackReference finds a pack held in only one format', () {
      const Map<String, dynamic> content = {
        'rooms': {
          '!room:example.org': {'present': <String, dynamic>{}},
        },
      };

      expect(
        MatrixImagePackCompatibility.hasGlobalPackReference(
          content,
          '!room:example.org',
          'present',
        ),
        isTrue,
      );
      expect(
        MatrixImagePackCompatibility.hasGlobalPackReference(
          content,
          '!room:example.org',
          'absent',
        ),
        isFalse,
      );
      expect(
        MatrixImagePackCompatibility.hasGlobalPackReference(
          content,
          '!other:example.org',
          'present',
        ),
        isFalse,
      );
      // Malformed content must answer false rather than throw: these two keys
      // are read straight from account data.
      expect(
        MatrixImagePackCompatibility.hasGlobalPackReference(
          {'rooms': 'not-a-map'},
          '!room:example.org',
          'present',
        ),
        isFalse,
      );
    });

    test('mergeGlobalPackReferences unions the legacy and stable keys', () {
      final merged = MatrixImagePackCompatibility.mergeGlobalPackReferences(
        legacy: {
          'rooms': {
            '!shared:example.org': {'legacy-pack': <String, dynamic>{}},
            '!legacy-only:example.org': {'a': <String, dynamic>{}},
          },
        },
        stable: {
          'rooms': {
            '!shared:example.org': {'stable-pack': <String, dynamic>{}},
            '!stable-only:example.org': {'b': <String, dynamic>{}},
          },
        },
      );

      expect(
        merged.keys,
        containsAll([
          '!shared:example.org',
          '!legacy-only:example.org',
          '!stable-only:example.org',
        ]),
      );
      expect(merged, hasLength(3));
      // A room named by both formats keeps BOTH packs; stable must not shadow
      // the legacy reference, or enabling a pack under one key would silently
      // disable it under the other.
      expect(
        merged['!shared:example.org']!.keys,
        containsAll(['legacy-pack', 'stable-pack']),
      );
    });

    test('updates standard recents while preserving unknown entries', () {
      final updated = MatrixImagePackCompatibility.recordRecentEmoji(
        existing: [
          {'emoji': '👍', 'total': 4, 'future_property': 'preserve'},
          {'unrecognised': 'opaque'},
          'opaque entry',
        ],
        emoji: '👍',
      );

      expect(updated.first, {
        'emoji': '👍',
        'total': 5,
        'future_property': 'preserve',
      });
      expect(updated.skip(1), [
        {'unrecognised': 'opaque'},
        'opaque entry',
      ]);
    });

    test('caps standard recents at one hundred entries after recording', () {
      final updated = MatrixImagePackCompatibility.recordRecentEmoji(
        existing: List<Object?>.generate(
          100,
          (index) => {'emoji': 'emoji-$index', 'total': index + 1},
        ),
        emoji: 'new-emoji',
      );

      expect(updated, hasLength(100));
      expect(updated.first, {'emoji': 'new-emoji', 'total': 1});
      expect(updated.last, {'emoji': 'emoji-98', 'total': 99});
    });

    test(
      'updates Cinny recent emoji tuples without dropping other entries',
      () {
        final updated = MatrixImagePackCompatibility.recordElementRecentEmoji(
          existing: [
            ['👍', 4],
            ['👋', 2],
          ],
          emoji: '👍',
        );

        expect(updated, [
          ['👍', 5],
          ['👋', 2],
        ]);
      },
    );

    test(
      'reads Cinny recent emoji tuples while ignoring malformed entries',
      () {
        expect(
          MatrixImagePackCompatibility.readElementRecentEmoji({
            'recent_emoji': [
              ['👍', 4],
              ['invalid-count', 'four'],
              {'not': 'a tuple'},
            ],
          }),
          [
            {'emoji': '👍', 'total': 4},
          ],
        );
      },
    );

    test('clears Cinny recent tuples with an explicit empty list', () {
      expect(MatrixImagePackCompatibility.clearElementRecentEmoji(), {
        'recent_emoji': <List<Object>>[],
      });
    });

    test('clears standard recents with an explicit empty list', () {
      expect(MatrixImagePackCompatibility.clearRecentEmoji(), {
        'recent_emoji': <Object?>[],
      });
    });

    test('orders saved picker keys and retains new packs at the end', () {
      final ordered = MatrixImagePackCompatibility.orderByKeys(
        ['new', 'second', 'first', 'also-new'],
        ['first', 'second', 'first'],
        keyOf: (value) => value,
      );

      expect(ordered, ['first', 'second', 'new', 'also-new']);
    });

    test('reorders pack images without deleting concurrent additions', () {
      final images = MatrixImagePackCompatibility.reorderImages(
        {
          'first': {'url': 'mxc://example/first'},
          'second': {'url': 'mxc://example/second'},
          'remote-new': {'url': 'mxc://example/new'},
        },
        ['second', 'first'],
      );

      expect(images.keys, ['second', 'first', 'remote-new']);
      expect(images['remote-new'], {'url': 'mxc://example/new'});
    });
  });

  group('recent-emoji record defects', () {
    test(
      'an existing entry with a malformed total is replaced, not duplicated',
      () {
        // The match used to require a numeric `total`, so an entry with a
        // malformed one was RETAINED while a fresh entry was prepended for the
        // same emoji - two entries for one emoji, repeated on every later record.
        final updated = MatrixImagePackCompatibility.recordRecentEmoji(
          existing: [
            {'emoji': '🔥', 'total': 'not-a-number'},
            {'emoji': '👍', 'total': 2},
          ],
          emoji: '🔥',
        );

        final entries = updated.whereType<Map<String, dynamic>>().toList();
        final recorded = entries.where((e) => e['emoji'] == '🔥').toList();
        expect(recorded, hasLength(1));
        // The absent duplicate is only half of it: the surviving entry has to
        // carry the COERCED count. `'not-a-number'` normalises to 0, so this
        // record writes 1. Without this the defensive read could regress to
        // rethrowing or to carrying the string through and the test above
        // would still be green.
        expect(recorded.single['total'], 1);
        expect(entries.map((e) => e['emoji']), containsAll(['🔥', '👍']));
      },
    );

    test('the first Element tuple wins even when its count is zero', () {
      // `total == 0 ? entryTotal : total` could not tell "not seen yet" from
      // "seen, and the count really was 0", so a later duplicate overwrote it.
      final updated = MatrixImagePackCompatibility.recordElementRecentEmoji(
        existing: [
          ['🎉', 0],
          ['🎉', 9],
        ],
        emoji: '🎉',
      );

      expect((updated.first! as List)[0], '🎉');
      expect(
        (updated.first! as List)[1],
        1,
        reason: 'first match (0) + 1, not 9 + 1',
      );
    });

    test('an unparseable Element entry is carried through, not deleted', () {
      // The result replaces the whole `io.element.recent_emoji` list for every
      // client on the account, so an entry this client cannot read is another
      // client's data, not garbage to discard. Dropping it was a silent
      // cross-client delete on every recent-emoji record.
      final foreign = <String, Object>{'shape': 'not-a-tuple'};
      final updated = MatrixImagePackCompatibility.recordElementRecentEmoji(
        existing: [
          foreign,
          ['👍', 4],
          ['too', 'many', 'fields'],
        ],
        emoji: '🔥',
      );

      expect(
        updated,
        containsAll(<Object?>[
          foreign,
          ['too', 'many', 'fields'],
        ]),
        reason: 'entries this client cannot parse must survive the write',
      );
      expect((updated.first! as List)[0], '🔥');
      expect(
        updated.whereType<List<Object>>().map((e) => e[0]),
        contains('👍'),
        reason: 'the recognised tuple is still normalised',
      );
    });
  });
}
