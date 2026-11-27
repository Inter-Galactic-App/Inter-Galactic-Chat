/// Pure compatibility helpers for Matrix's stable and legacy image-pack data.
class MatrixImagePackCompatibility {
  static const legacyRoomEventType = 'im.ponies.room_emotes';
  static const stableRoomEventType = 'm.room.image_pack';
  static const legacyGlobalEventType = 'im.ponies.emote_rooms';
  static const stableGlobalEventType = 'm.image_pack.rooms';
  static const recentEmojiEventType = 'm.recent_emoji';
  static const pickerOrderEventType = 'org.intergalactic.emoticon_order';
  static const elementRecentEmojiEventType = 'io.element.recent_emoji';
  static const maxRecentEmoji = 100;

  /// Orders known entries by a user-owned list while keeping newly discovered
  /// entries stable at the end. Duplicate stored keys intentionally resolve to
  /// their first occurrence, making malformed account data harmless.
  static List<T> orderByKeys<T>(
    Iterable<T> values,
    Iterable<String> order, {
    required String Function(T value) keyOf,
  }) {
    final index = <String, int>{};
    for (final key in order) {
      if (key.isNotEmpty) index.putIfAbsent(key, () => index.length);
    }
    final indexed = values.indexed.toList();
    indexed.sort((a, b) {
      final aOrder = index[keyOf(a.$2)];
      final bOrder = index[keyOf(b.$2)];
      if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
      if (aOrder != null) return -1;
      if (bOrder != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    return indexed.map((entry) => entry.$2).toList(growable: false);
  }

  /// Rebuilds an image-pack map in the requested order without dropping
  /// entries introduced by another client while the editor was open.
  static Map<String, dynamic> reorderImages(
    Object? images,
    Iterable<String> shortcodes,
  ) {
    if (images is! Map) return <String, dynamic>{};
    final remaining = <String, dynamic>{
      for (final entry in images.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final result = <String, dynamic>{};
    for (final shortcode in shortcodes) {
      final value = remaining.remove(shortcode);
      if (value != null) result[shortcode] = value;
    }
    result.addAll(remaining);
    return result;
  }

  static Map<String, Map<String, dynamic>> mergeRoomPackStates({
    Object? legacy,
    Object? stable,
  }) {
    final result = <String, Map<String, dynamic>>{};
    void add(Object? source) {
      if (source is! Map) return;
      for (final entry in source.entries) {
        if (entry.key is String && entry.value is Map) {
          result[entry.key as String] = Map<String, dynamic>.from(
            entry.value as Map,
          );
        }
      }
    }

    add(legacy);
    add(stable);
    return result;
  }

  static Map<String, dynamic> withGlobalPackReference({
    Object? content,
    required String roomId,
    required String packKey,
    required bool enabled,
  }) {
    final result = content is Map
        ? Map<String, dynamic>.from(content)
        : <String, dynamic>{};
    final sourceRooms = result['rooms'];
    final rooms = <String, dynamic>{};
    if (sourceRooms is Map) {
      for (final entry in sourceRooms.entries) {
        if (entry.key is String) {
          rooms[entry.key as String] = entry.value is Map
              ? Map<String, dynamic>.from(entry.value as Map)
              : entry.value;
        }
      }
    }
    final roomPacks = rooms[roomId] is Map
        ? Map<String, dynamic>.from(rooms[roomId] as Map)
        : <String, dynamic>{};
    if (enabled) {
      roomPacks[packKey] = roomPacks[packKey] ?? <String, dynamic>{};
    } else {
      roomPacks.remove(packKey);
    }
    rooms[roomId] = roomPacks;
    result['rooms'] = rooms;
    return result;
  }

  static bool hasGlobalPackReference(
    Object? content,
    String roomId,
    String packKey,
  ) {
    if (content is! Map || content['rooms'] is! Map) return false;
    final room = (content['rooms'] as Map)[roomId];
    return room is Map && room.containsKey(packKey);
  }

  static Map<String, Map<String, dynamic>> mergeGlobalPackReferences({
    Object? legacy,
    Object? stable,
  }) {
    final result = <String, Map<String, dynamic>>{};
    void add(Object? content) {
      if (content is! Map || content['rooms'] is! Map) return;
      for (final entry in (content['rooms'] as Map).entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        result
            .putIfAbsent(entry.key as String, () => <String, dynamic>{})
            .addAll(Map<String, dynamic>.from(entry.value as Map));
      }
    }

    add(legacy);
    add(stable);
    return result;
  }

  static List<Object?> recordRecentEmoji({
    required Iterable<Object?> existing,
    required String emoji,
  }) {
    Map<String, dynamic>? existingEmoji;
    final retained = <Object?>[];
    for (final entry in existing) {
      // Matched on `emoji` ALONE. Requiring a numeric `total` here meant an
      // existing entry for this emoji with a malformed total was retained AND a
      // fresh entry prepended for the same emoji, so the published list carried
      // two entries for one emoji and every later record repeated it. `total`
      // is read defensively below instead.
      if (entry is Map && entry['emoji'] == emoji) {
        existingEmoji ??= Map<String, dynamic>.from(entry);
        continue;
      }
      retained.add(entry);
    }
    // Read, not cast: the match above no longer requires a numeric total, so a
    // malformed one reaches here and `as num?` would throw on it.
    final rawTotal = existingEmoji?['total'];
    final total = rawTotal is num ? rawTotal.toInt() : 0;
    final updated = <String, dynamic>{
      ...?existingEmoji,
      'emoji': emoji,
      'total': total + 1,
    };
    return [updated, ...retained].take(maxRecentEmoji).toList();
  }

  /// Updates the legacy Element/Cinny tuple form of recent Unicode emoji.
  ///
  /// Returns `List<Object?>` rather than `List<List<Object>>` because entries
  /// this client cannot parse are carried through UNCHANGED. The result
  /// replaces the whole `io.element.recent_emoji` list for every client on the
  /// account, so dropping an entry we do not recognise is not a local parse
  /// decision - it deletes another client's data. We did not write those bytes
  /// and cannot tell a corrupt tuple from a shape some other client is using,
  /// so the only safe thing is to leave them where they are. `recordRecent-
  /// Emoji` already behaves this way for the stable Map form; this is the same
  /// rule applied to the tuple form.
  ///
  /// Recognised entries are still normalised: the tuple is rebuilt as
  /// `[String, int]` so a `num` total does not round-trip as a double.
  static List<Object?> recordElementRecentEmoji({
    required Iterable<Object?> existing,
    required String emoji,
  }) {
    final retained = <Object?>[];
    var total = 0;
    // An explicit flag, not `total == 0`. A first matching tuple that legitimately
    // stores 0 left `total` at its initial value, so a LATER duplicate tuple for
    // the same emoji overwrote it - the first match is supposed to win.
    var seen = false;
    for (final entry in existing) {
      if (entry is! List ||
          entry.length != 2 ||
          entry[0] is! String ||
          entry[1] is! num) {
        retained.add(entry);
        continue;
      }
      final entryEmoji = entry[0] as String;
      final entryTotal = (entry[1] as num).toInt();
      if (entryEmoji == emoji) {
        if (!seen) {
          total = entryTotal;
          seen = true;
        }
        continue;
      }
      retained.add(<Object>[entryEmoji, entryTotal]);
    }
    return <Object?>[
      <Object>[emoji, total + 1],
      ...retained,
    ].take(maxRecentEmoji).toList();
  }

  static List<Map<String, dynamic>> readElementRecentEmoji(Object? content) {
    if (content is! Map || content['recent_emoji'] is! List) return [];
    return (content['recent_emoji'] as List)
        .whereType<List>()
        .where(
          (entry) => entry.length == 2 && entry[0] is String && entry[1] is num,
        )
        .map(
          (entry) => <String, dynamic>{
            'emoji': entry[0] as String,
            'total': (entry[1] as num).toInt(),
          },
        )
        .toList();
  }

  static Map<String, List<List<Object>>> clearElementRecentEmoji() {
    return {'recent_emoji': <List<Object>>[]};
  }

  /// The stable recent-emoji event is a complete list, so clearing it must
  /// publish an empty list rather than leaving the previous account data in
  /// place for the next login to merge back into the legacy stores.
  static Map<String, List<Object?>> clearRecentEmoji() {
    return {'recent_emoji': <Object?>[]};
  }
}
