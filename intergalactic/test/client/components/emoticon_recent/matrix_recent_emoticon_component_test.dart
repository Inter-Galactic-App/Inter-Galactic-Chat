import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/emoticon_recent/matrix_recent_emoticon_component.dart';

void main() {
  test(
    'sticker recents move the selected sticker to the front and bound the list',
    () {
      final existing = List.generate(
        30,
        (index) => RecentEmoji(key: 'sticker-$index'),
      );

      final updated = MatrixRecentEmoticonComponent.recordRecentSticker(
        existing: existing,
        sticker: RecentEmoji(key: 'sticker-12'),
      );

      expect(updated, hasLength(30));
      expect(updated.first.key, 'sticker-12');
      expect(updated.where((entry) => entry.key == 'sticker-12'), hasLength(1));
      expect(updated.last.key, 'sticker-29');
    },
  );

  test('quick reaction normalization preserves duplicate slot values', () {
    final reactions =
        MatrixRecentEmoticonComponent.normalizeQuickReactionRecents([
          RecentEmoji(key: '❤️'),
          RecentEmoji(key: '😂'),
          RecentEmoji(key: '❤️'),
          RecentEmoji(key: '👍'),
        ]);

    expect(
      reactions.take(4).map((reaction) => reaction.key),
      equals(['❤️', '😂', '❤️', '👍']),
    );
  });

  group('resolveRecentEmoji', () {
    test('retains a pending entry the stores do not have yet', () {
      // The reload composition itself, so removing the pending merge fails
      // here rather than leaving a green suite behind a dropped emoji.
      final resolved = MatrixRecentEmoticonComponent.resolveRecentEmoji(
        stored: [RecentEmoji(key: '👍', count: 3)],
        pending: [
          RecentEmoji(key: '👍', count: 3),
          RecentEmoji(key: '🔥'),
        ],
        standard: [RecentEmoji(key: '😂', count: 2)],
        element: const [],
      );

      // containsAll proves presence only. It cannot see a duplicate, a wrong
      // length, or a clobbered count - and 👍 arrives from BOTH stored and
      // pending here, so a merge that appended instead of deduplicating would
      // have passed.
      expect(resolved.map((e) => e.key), containsAll(['👍', '🔥', '😂']));
      expect(resolved, hasLength(3));
      expect(resolved.firstWhere((e) => e.key == '👍').count, 3);
    });

    test('keeps the higher count when a source disagrees', () {
      // mergeRecentEmoji takes the larger count rather than last-write-wins,
      // so a stale store cannot walk a total backwards.
      final resolved = MatrixRecentEmoticonComponent.resolveRecentEmoji(
        stored: [RecentEmoji(key: '👍', count: 7)],
        pending: [RecentEmoji(key: '👍', count: 2)],
        standard: const [],
        element: const [],
      );

      expect(resolved, hasLength(1));
      expect(resolved.single.count, 7);
    });

    test('is uncapped, unlike addToList', () {
      // addToList trims to 30 because it writes back to account data.
      // resolveRecentEmoji is the READ path and must not silently drop
      // entries the stores still hold - bounding it here would make emoji
      // vanish from the picker rather than from storage.
      final resolved = MatrixRecentEmoticonComponent.resolveRecentEmoji(
        stored: List<RecentEmoji>.generate(
          40,
          (i) => RecentEmoji(key: 'stored-$i', count: 1),
        ),
        pending: const [],
        standard: [RecentEmoji(key: 'standard', count: 1)],
        element: const [],
      );

      expect(resolved, hasLength(41));
    });

    test('still merges the standard and Element sources', () {
      final resolved = MatrixRecentEmoticonComponent.resolveRecentEmoji(
        stored: const [],
        pending: const [],
        standard: [RecentEmoji(key: '😂', count: 2)],
        element: [RecentEmoji(key: '🎉', count: 5)],
      );

      expect(resolved.map((e) => e.key), containsAll(['😂', '🎉']));
      expect(resolved, hasLength(2));
      expect(resolved.firstWhere((e) => e.key == '🎉').count, 5);
    });
  });

  group('resolveRecentEmojiLists', () {
    test('the interop sources reach the typed list and NOT the reactions', () {
      // Both lists are written straight back to their own account-data keys, so
      // feeding the interop sources into both made the two converge on their
      // union after a few reload cycles - the two pickers then showed the same
      // content. A test of resolveRecentEmoji alone cannot catch that; it is
      // the ROUTING that was wrong.
      final resolved = MatrixRecentEmoticonComponent.resolveRecentEmojiLists(
        storedReactions: [RecentEmoji(key: '👍', count: 4)],
        pendingReactions: const [],
        storedTyped: [RecentEmoji(key: '🙂', count: 1)],
        pendingTyped: const [],
        standard: [RecentEmoji(key: '😂', count: 2)],
        element: [RecentEmoji(key: '🎉', count: 5)],
      );

      expect(resolved.typed.map((e) => e.key), containsAll(['🙂', '😂', '🎉']));
      expect(resolved.reactions.map((e) => e.key), ['👍']);
      expect(resolved.reactions.map((e) => e.key), isNot(contains('😂')));
      expect(resolved.reactions.map((e) => e.key), isNot(contains('🎉')));
    });

    test('a pending reaction still survives the reload', () {
      final resolved = MatrixRecentEmoticonComponent.resolveRecentEmojiLists(
        storedReactions: [RecentEmoji(key: '👍', count: 4)],
        pendingReactions: [RecentEmoji(key: '🔥')],
        storedTyped: const [],
        pendingTyped: const [],
        standard: const [],
        element: const [],
      );

      expect(resolved.reactions.map((e) => e.key), containsAll(['👍', '🔥']));
    });
  });

  group('mergeRecentEmoji', () {
    test('retains an entry that exists only in the in-memory list', () {
      // A reload triggered by another client's sync must not drop an emoji
      // used in the last few seconds, which the 5 s debounce has not yet
      // written to account data.
      final stored = [RecentEmoji(key: '👍', count: 3)];
      final pending = [
        RecentEmoji(key: '👍', count: 3),
        RecentEmoji(key: '🔥'),
      ];

      final merged = MatrixRecentEmoticonComponent.mergeRecentEmoji(
        stored,
        pending,
      );

      expect(merged.map((e) => e.key), containsAll(['👍', '🔥']));
      expect(merged.where((e) => e.key == '🔥'), hasLength(1));
    });

    test('keeps the higher count and does not duplicate', () {
      final merged = MatrixRecentEmoticonComponent.mergeRecentEmoji(
        [RecentEmoji(key: '😂', count: 2)],
        [RecentEmoji(key: '😂', count: 9)],
      );

      expect(merged, hasLength(1));
      expect(merged.single.count, 9);
    });

    test('does not mutate the source lists', () {
      final stored = [RecentEmoji(key: '😂', count: 2)];
      final pending = [RecentEmoji(key: '😂', count: 9)];

      MatrixRecentEmoticonComponent.mergeRecentEmoji(stored, pending);

      expect(stored.single.count, 2);
      expect(pending.single.count, 9);
    });
  });
}
