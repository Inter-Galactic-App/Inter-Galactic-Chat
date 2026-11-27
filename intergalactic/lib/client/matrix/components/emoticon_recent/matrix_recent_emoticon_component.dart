import 'dart:async';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_image_pack_compatibility.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/debounce.dart';
import 'package:intergalactic/utils/emoji/unicode_emoji.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix_api_lite/model/basic_event.dart';

class MatrixRecentEmoticonComponent
    implements
        RecentEmoticonComponent<MatrixClient>,
        NeedsPostLoginInit,
        DisposableComponent {
  MatrixRecentEmoticonComponent(this.client) {
    _syncSubscription = client.matrixClient.onSync.stream.listen((update) {
      if (update.accountData?.any(
            (event) =>
                event.type == standardRecentKey ||
                event.type ==
                    MatrixImagePackCompatibility.elementRecentEmojiEventType,
          ) ==
          true) {
        _loadRecentEmoji();
      }
    });
  }

  List<RecentEmoji> _reactionEmoji = List.empty(growable: true);
  List<RecentEmoji> _typedEmoji = List.empty(growable: true);
  List<RecentEmoji> _quickReactionEmoji = List.empty(growable: true);
  List<RecentEmoji> _stickerEmoji = List.empty(growable: true);

  Debouncer reactionDebouncer = Debouncer(delay: const Duration(seconds: 5));
  Debouncer typedDebouncer = Debouncer(delay: const Duration(seconds: 5));
  StreamSubscription? _syncSubscription;

  static const String reactionsKey = "chat.commet.recent_reaction_emoji";
  static const String typedKey = "chat.commet.recent_emoji";
  static const String standardRecentKey =
      MatrixImagePackCompatibility.recentEmojiEventType;
  static const String quickReactionsKey =
      "chat.intergalactic.quick_reaction_emoji";
  static const List<String> _defaultQuickReactionKeys = [
    "❤️",
    "😂",
    "😮",
    "😢",
    "👍",
  ];

  @override
  MatrixClient client;

  @override
  List<Emoticon> getRecentReactionEmoticon(Room room) {
    return toEmoticons(room, _reactionEmoji);
  }

  @override
  List<Emoticon> getRecentTypedEmoticon(Room? room) {
    return toEmoticons(room, _typedEmoji);
  }

  @override
  List<Emoticon> getRecentStickerEmoticon(Room? room) {
    return toEmoticons(
      room,
      _stickerEmoji,
      sortByCount: false,
      addFallbackUnicode: false,
    );
  }

  @override
  List<Emoticon> getQuickReactionEmoticon(Room? room) {
    return normalizeQuickReactionEmoticons(
      toEmoticons(
        room,
        _quickReactionEmoji,
        sortByCount: false,
        addFallbackUnicode: false,
      ),
    );
  }

  @override
  void postLoginInit() {
    _loadRecentEmoji();
    _loadRecentStickers();
  }

  void _loadRecentStickers() {
    _stickerEmoji = preferences
        .getRecentStickers(client.identifier)
        .map(RecentEmoji.fromjson)
        .whereType<RecentEmoji>()
        .toList();
  }

  void _loadRecentEmoji() {
    // Stores are written on a 5 s debounce, so anything used in the last few
    // seconds exists only in memory. This runs on every sync carrying a
    // recent-emoji account-data change - including one written by another
    // client - so replacing outright would drop those pending entries from the
    // picker and then persist the reduced list when the debouncer fires.
    // Retaining them is safe against `clear()`, which empties both lists before
    // it writes.
    final pendingReactions = _reactionEmoji;
    final pendingTyped = _typedEmoji;

    var data = client.matrixClient.accountData[reactionsKey];
    if (data != null) {
      _reactionEmoji = toRecentsList(data);
      Log.i("Got ${_reactionEmoji.length} recent reaction emoji");
    }

    var typedData = client.matrixClient.accountData[typedKey];
    if (typedData != null) {
      _typedEmoji = toRecentsList(typedData);
      Log.i("Got ${_typedEmoji.length} recently typed emoji");
    }

    final standardRecents = _standardRecents(
      client.matrixClient.accountData[standardRecentKey]?.content,
    );
    final elementRecents = _elementRecents(
      client
          .matrixClient
          .accountData[MatrixImagePackCompatibility.elementRecentEmojiEventType]
          ?.content,
    );
    final resolved = resolveRecentEmojiLists(
      storedReactions: _reactionEmoji,
      pendingReactions: pendingReactions,
      storedTyped: _typedEmoji,
      pendingTyped: pendingTyped,
      standard: standardRecents,
      element: elementRecents,
    );
    _reactionEmoji = resolved.reactions;
    _typedEmoji = resolved.typed;

    var quickData = client.matrixClient.accountData[quickReactionsKey];
    if (quickData != null) {
      _quickReactionEmoji = normalizeQuickReactionRecents(
        toRecentsList(quickData),
      );
      Log.i("Got ${_quickReactionEmoji.length} quick reactions");
    } else {
      _quickReactionEmoji = normalizeQuickReactionRecents([]);
    }
  }

  List<Emoticon> toEmoticons(
    Room? room,
    List<RecentEmoji> emojis, {
    bool sortByCount = true,
    bool addFallbackUnicode = true,
  }) {
    var result = List<Emoticon>.empty(growable: true);
    var storedEmojis = List<RecentEmoji>.from(emojis);

    var comp = room?.getComponent<RoomEmoticonComponent>();

    var availablePacks =
        comp?.availablePacks ??
        client.getComponent<EmoticonComponent>()?.availablePacks;

    if (availablePacks == null) return [];

    if (sortByCount) {
      storedEmojis.sort((a, b) => b.count.compareTo(a.count));
    }

    for (var emote in storedEmojis) {
      if (emote.customPackId == null && emote.customPackRoomId == null) {
        result.add(UnicodeEmoticon(emote.key));
      }

      if (emote.customPackId != null) {
        for (var pack in availablePacks) {
          // this is a custom pack, it cant be in unicode
          if (pack is UnicodeEmoticonPack) continue;

          if (emote.customPackRoomId != null) {
            if (pack.ownerId != emote.customPackRoomId) continue;
          }

          if (pack.identifier == emote.customPackId) {
            var emoticon = pack.getByShortcode(emote.key);
            if (emoticon != null) {
              result.add(emoticon);
            }
          }
        }
      }
    }

    if (addFallbackUnicode) {
      "❤️👍👎😂🔥😭🤣✨🙏💀😍🥺🥰😊😵‍💫😵🤩😎😘😅👏😁🤠💔💖💙🩷🤍💕😢🤔😆🙄💪😉☺️👌🤗"
          .characters
          .map((i) => UnicodeEmoticon(i.toString()))
          .forEach((i) {
            if (result.contains(i) == false) {
              result.add(i);
            }
          });
    }

    return result;
  }

  RecentEmoji? toRecentEmoji(Room? room, Emoticon emoticon) {
    var availablePacks =
        room?.getComponent<RoomEmoticonComponent>()?.availablePacks ??
        client.getComponent<EmoticonComponent>()?.availablePacks;
    return toRecentEmojiFromPacks(emoticon, availablePacks);
  }

  RecentEmoji? toRecentEmojiFromPacks(
    Emoticon emoticon,
    List<EmoticonPack>? availablePacks,
  ) {
    String? customPackid;
    String? customPackRoomId;
    String key = emoticon.key;

    if (emoticon is UnicodeEmoticon) {
      return RecentEmoji(key: key);
    }

    if (emoticon is MatrixEmoticon) {
      if (emoticon.shortcode != null) {
        key = emoticon.shortcode!;
      }
      if (availablePacks == null) {
        return null;
      }

      for (var pack in availablePacks) {
        if (pack is DynamicEmoticonPack) continue;

        if (pack.emotes.contains(emoticon)) {
          customPackid = pack.identifier;
          if (customPackid != "im.ponies.user_emotes")
            customPackRoomId = pack.ownerId;
          break;
        }
      }

      if (customPackid == null) {
        return null;
      }
    }

    return RecentEmoji(
      key: key,
      customPackId: customPackid,
      customPackRoomId: customPackRoomId,
    );
  }

  static List<RecentEmoji> defaultQuickReactionRecents() {
    return _defaultQuickReactionKeys.map((i) => RecentEmoji(key: i)).toList();
  }

  static RecentEmoji cloneRecentEmoji(RecentEmoji emoji) {
    return RecentEmoji(
      key: emoji.key,
      customPackId: emoji.customPackId,
      customPackRoomId: emoji.customPackRoomId,
      count: emoji.count,
    );
  }

  static List<RecentEmoji> normalizeQuickReactionRecents(
    List<RecentEmoji> emojis,
  ) {
    var result = List<RecentEmoji>.empty(growable: true);

    for (var emoji in emojis) {
      result.add(cloneRecentEmoji(emoji));
      if (result.length >= RecentEmoticonComponent.quickReactionCount) {
        return result;
      }
    }

    for (var emoji in defaultQuickReactionRecents()) {
      if (result.contains(emoji)) continue;

      result.add(emoji);
      if (result.length >= RecentEmoticonComponent.quickReactionCount) {
        break;
      }
    }

    return result;
  }

  List<Emoticon> normalizeQuickReactionEmoticons(List<Emoticon> emojis) {
    var result = List<Emoticon>.from(emojis);

    for (var emoji in _defaultQuickReactionKeys.map(
      (i) => UnicodeEmoticon(i),
    )) {
      if (result.length >= RecentEmoticonComponent.quickReactionCount) {
        break;
      }

      if (result.contains(emoji) == false) {
        result.add(emoji);
      }
    }

    if (result.length > RecentEmoticonComponent.quickReactionCount) {
      return result.sublist(0, RecentEmoticonComponent.quickReactionCount);
    }

    return result;
  }

  @override
  Future<void> reactedEmoticon(Room room, Emoticon emoticon) async {
    var emoji = toRecentEmoji(room, emoticon);
    if (emoji == null || emoji.key == "") return;

    _reactionEmoji = addToList(emoji, _reactionEmoji);
    reactionDebouncer.run(() => storeRecentReactions(emoji));
  }

  @override
  Future<void> typedEmoticon(Room room, Emoticon emoticon) async {
    var emoji = toRecentEmoji(room, emoticon);
    if (emoji == null) return;

    _typedEmoji = addToList(emoji, _typedEmoji);
    typedDebouncer.run(() => storeRecentlyTyped(emoji));
  }

  @override
  Future<void> stickerEmoticon(Room room, Emoticon emoticon) async {
    final sticker = toRecentEmoji(room, emoticon);
    if (sticker == null || !emoticon.isSticker) return;

    _stickerEmoji = recordRecentSticker(
      existing: _stickerEmoji,
      sticker: sticker,
    );
    await preferences.setRecentStickers(
      client.identifier,
      _stickerEmoji.map((entry) => entry.toJson()).toList(),
    );
  }

  @visibleForTesting
  static List<RecentEmoji> recordRecentSticker({
    required Iterable<RecentEmoji> existing,
    required RecentEmoji sticker,
  }) {
    final updated = existing
        .where((entry) => entry != sticker)
        .map(cloneRecentEmoji)
        .toList();
    updated.insert(0, cloneRecentEmoji(sticker));
    return updated.take(30).toList();
  }

  @override
  Future<void> setQuickReactionEmoticon(
    int index,
    Emoticon emoticon, {
    Room? room,
  }) async {
    if (index < 0 || index >= RecentEmoticonComponent.quickReactionCount) {
      return;
    }

    var emoji = toRecentEmoji(room, emoticon);
    if (emoji == null || emoji.key == "") return;

    var quickReactions = normalizeQuickReactionRecents(_quickReactionEmoji);
    quickReactions[index] = emoji;

    _quickReactionEmoji = normalizeQuickReactionRecents(quickReactions);
    await storeQuickReactions();
  }

  List<RecentEmoji> addToList(RecentEmoji emoji, List<RecentEmoji> list) {
    const maxLen = 30;

    if (list.length > maxLen) {
      list = list.sublist(0, maxLen);
    }

    var existing = list.firstWhereOrNull(
      (i) =>
          i.customPackId == emoji.customPackId &&
          i.customPackRoomId == emoji.customPackRoomId &&
          i.key == emoji.key,
    );

    if (existing != null) {
      existing.count++;
    } else {
      list.insert(0, emoji);
    }

    return list;
  }

  Future<void> storeRecentReactions([RecentEmoji? standardEmoji]) async {
    var content = {
      "recent_emoji": _reactionEmoji.map((i) => i.toJson()).toList(),
    };
    await client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      reactionsKey,
      content,
    );
    await _storeStandardRecent(standardEmoji);
  }

  Future<void> storeRecentlyTyped([RecentEmoji? standardEmoji]) async {
    var content = {"recent_emoji": _typedEmoji.map((i) => i.toJson()).toList()};

    await client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      typedKey,
      content,
    );
    await _storeStandardRecent(standardEmoji);
  }

  static List<RecentEmoji> _standardRecents(Object? content) {
    if (content is! Map || content['recent_emoji'] is! List) return [];
    return (content['recent_emoji'] as List)
        .whereType<Map>()
        .map(
          (entry) => RecentEmoji(
            key: entry['emoji'] as String? ?? '',
            count: (entry['total'] as num?)?.toInt() ?? 1,
          ),
        )
        .where((emoji) => emoji.key.isNotEmpty)
        .toList();
  }

  static List<RecentEmoji> _elementRecents(Object? content) {
    return MatrixImagePackCompatibility.readElementRecentEmoji(content)
        .map(
          (entry) => RecentEmoji(
            key: entry['emoji'] as String,
            count: entry['total'] as int,
          ),
        )
        .toList();
  }

  /// Composes one recent-emoji list for a reload.
  ///
  /// [pending] is the in-memory list being replaced. It is folded back in
  /// because the stores are written on a 5 s debounce, so a just-used emoji
  /// exists nowhere else yet. Dropping it here removes it from the picker and
  /// then persists the reduced list when the debouncer fires.
  ///
  /// This is the whole reload composition rather than a single merge, so a
  /// change that stops retaining [pending] fails its test.
  /// Routes each source to the list it belongs to.
  ///
  /// The interop sources feed the TYPED list only. `m.recent_emoji` (MSC4356)
  /// and `io.element.recent_emoji` are the cross-client *recently used emoji*
  /// concept, which is this app's `chat.commet.recent_emoji` - not its separate
  /// `chat.commet.recent_reaction_emoji`.
  ///
  /// Merging them into both was self-reinforcing rather than merely untidy:
  /// `reactedEmoticon` writes the whole reaction list back to `reactionsKey`
  /// and `typedEmoticon` writes the whole typed list back to `typedKey`, so
  /// after a few reload cycles the two account-data keys converged on their
  /// union. The reaction picker and the typed picker then showed the same
  /// content and the per-list ordering by count was gone.
  ///
  /// Extracted so the ROUTING is testable, not only the merge: a test of
  /// `resolveRecentEmoji` alone stays green with both lists fed from both
  /// sources.
  @visibleForTesting
  static ({List<RecentEmoji> reactions, List<RecentEmoji> typed})
  resolveRecentEmojiLists({
    required List<RecentEmoji> storedReactions,
    required List<RecentEmoji> pendingReactions,
    required List<RecentEmoji> storedTyped,
    required List<RecentEmoji> pendingTyped,
    required List<RecentEmoji> standard,
    required List<RecentEmoji> element,
  }) => (
    reactions: mergeRecentEmoji(storedReactions, pendingReactions),
    typed: resolveRecentEmoji(
      stored: storedTyped,
      pending: pendingTyped,
      standard: standard,
      element: element,
    ),
  );

  @visibleForTesting
  static List<RecentEmoji> resolveRecentEmoji({
    required List<RecentEmoji> stored,
    required List<RecentEmoji> pending,
    required List<RecentEmoji> standard,
    required List<RecentEmoji> element,
  }) {
    var result = mergeRecentEmoji(stored, pending);
    result = mergeRecentEmoji(result, standard);
    return mergeRecentEmoji(result, element);
  }

  /// Unions [standard] into [legacy], keeping the higher count per emoji.
  ///
  /// Public so the retention property can be asserted directly: a reload must
  /// not drop an entry that exists only in the in-memory list.
  @visibleForTesting
  static List<RecentEmoji> mergeRecentEmoji(
    List<RecentEmoji> legacy,
    List<RecentEmoji> standard,
  ) {
    final result = legacy.map(cloneRecentEmoji).toList();
    for (final emoji in standard) {
      final existing = result.firstWhereOrNull((entry) => entry == emoji);
      if (existing == null) {
        result.add(cloneRecentEmoji(emoji));
      } else if (emoji.count > existing.count) {
        existing.count = emoji.count;
      }
    }
    return result;
  }

  Future<void> _storeStandardRecent(RecentEmoji? emoji) async {
    if (emoji == null || emoji.customPackId != null) return;
    final content = client.matrixClient.accountData[standardRecentKey]?.content;
    final recentEntries = content?['recent_emoji'];
    final existing = recentEntries is List
        ? List<Object?>.from(recentEntries)
        : <Object?>[];
    await client.matrixClient
        .setAccountData(client.matrixClient.userID!, standardRecentKey, {
          'recent_emoji': MatrixImagePackCompatibility.recordRecentEmoji(
            existing: existing,
            emoji: emoji.key,
          ),
        });
    await _storeElementRecent(emoji);
  }

  Future<void> _storeElementRecent(RecentEmoji? emoji) async {
    if (emoji == null ||
        emoji.customPackId != null ||
        emoji.customPackRoomId != null) {
      return;
    }
    final content = client
        .matrixClient
        .accountData[MatrixImagePackCompatibility.elementRecentEmojiEventType]
        ?.content;
    final recentEntries = content?['recent_emoji'];
    final existing = recentEntries is List
        ? List<Object?>.from(recentEntries)
        : <Object?>[];
    await client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      MatrixImagePackCompatibility.elementRecentEmojiEventType,
      {
        'recent_emoji': MatrixImagePackCompatibility.recordElementRecentEmoji(
          existing: existing,
          emoji: emoji.key,
        ),
      },
    );
  }

  Future<void> _clearStandardRecents() {
    return client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      standardRecentKey,
      MatrixImagePackCompatibility.clearRecentEmoji(),
    );
  }

  Future<void> _clearElementRecents() {
    return client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      MatrixImagePackCompatibility.elementRecentEmojiEventType,
      MatrixImagePackCompatibility.clearElementRecentEmoji(),
    );
  }

  Future<void> storeQuickReactions() async {
    var content = {
      "recent_emoji": _quickReactionEmoji.map((i) => i.toJson()).toList(),
    };

    await client.matrixClient.setAccountData(
      client.matrixClient.userID!,
      quickReactionsKey,
      content,
    );
  }

  List<RecentEmoji> toRecentsList(BasicEvent data) {
    var content = data.content;
    var list = content["recent_emoji"] as List<dynamic>?;
    if (list == null) return [];

    return list
        .map((i) => RecentEmoji.fromjson(i))
        .nonNulls
        .where((i) => i.key != "")
        .toList();
  }

  @override
  Future<void> clear() async {
    _reactionEmoji = List.empty(growable: true);
    _typedEmoji = List.empty(growable: true);
    _stickerEmoji = List.empty(growable: true);
    _quickReactionEmoji = normalizeQuickReactionRecents([]);

    await storeRecentReactions();
    await storeRecentlyTyped();
    await storeQuickReactions();
    await preferences.setRecentStickers(client.identifier, const []);
    await _clearStandardRecents();
    await _clearElementRecents();
  }

  @override
  Future<void> dispose() async {
    await _syncSubscription?.cancel();
    _syncSubscription = null;
  }
}

class RecentEmoji {
  RecentEmoji({
    required this.key,
    this.customPackId,
    this.customPackRoomId,
    this.count = 1,
  });

  String key;
  String? customPackId;
  String? customPackRoomId;
  int count;

  Map<String, dynamic> toJson() {
    return {
      "key": key,
      if (customPackId != null) "state_key": customPackId,
      if (customPackRoomId != null) "room_id": customPackRoomId,
      "count": count,
    };
  }

  static RecentEmoji? fromjson(Map<String, dynamic> data) {
    var key = data["key"] as String?;
    var packId = data["state_key"] as String?;
    var customPackRoomId = data["room_id"] as String?;
    var count = data["count"] as int? ?? 1;
    if (key == null) return null;
    return RecentEmoji(
      key: data["key"],
      customPackId: packId,
      customPackRoomId: customPackRoomId,
      count: count,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! RecentEmoji) {
      return false;
    }

    return other.customPackId == customPackId &&
        other.customPackRoomId == customPackRoomId &&
        other.key == key;
  }

  @override
  int get hashCode {
    return "${key}_${customPackId}_${customPackRoomId}".hashCode;
  }
}
