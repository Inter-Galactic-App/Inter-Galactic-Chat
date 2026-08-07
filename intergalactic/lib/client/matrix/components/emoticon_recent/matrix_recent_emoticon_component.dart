import 'package:collection/collection.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/debounce.dart';
import 'package:intergalactic/utils/emoji/unicode_emoji.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix_api_lite/model/basic_event.dart';

class MatrixRecentEmoticonComponent
    implements RecentEmoticonComponent<MatrixClient>, NeedsPostLoginInit {
  MatrixRecentEmoticonComponent(this.client);

  List<RecentEmoji> _reactionEmoji = List.empty(growable: true);
  List<RecentEmoji> _typedEmoji = List.empty(growable: true);
  List<RecentEmoji> _quickReactionEmoji = List.empty(growable: true);

  Debouncer reactionDebouncer = Debouncer(delay: const Duration(seconds: 5));
  Debouncer typedDebouncer = Debouncer(delay: const Duration(seconds: 5));

  static const String reactionsKey = "chat.commet.recent_reaction_emoji";
  static const String typedKey = "chat.commet.recent_emoji";
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
  List<Emoticon> getQuickReactionEmoticon(Room? room) {
    return normalizeQuickReactionEmoticons(
      toEmoticons(room, _quickReactionEmoji,
          sortByCount: false, addFallbackUnicode: false),
    );
  }

  @override
  void postLoginInit() {
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

    var quickData = client.matrixClient.accountData[quickReactionsKey];
    if (quickData != null) {
      _quickReactionEmoji =
          normalizeQuickReactionRecents(toRecentsList(quickData));
      Log.i("Got ${_quickReactionEmoji.length} quick reactions");
    } else {
      _quickReactionEmoji = normalizeQuickReactionRecents([]);
    }
  }

  List<Emoticon> toEmoticons(Room? room, List<RecentEmoji> emojis,
      {bool sortByCount = true, bool addFallbackUnicode = true}) {
    var result = List<Emoticon>.empty(growable: true);
    var storedEmojis = List<RecentEmoji>.from(emojis);

    var comp = room?.getComponent<RoomEmoticonComponent>();

    var availablePacks = comp?.availablePacks ??
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
      Emoticon emoticon, List<EmoticonPack>? availablePacks) {
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
        customPackRoomId: customPackRoomId);
  }

  List<RecentEmoji> defaultQuickReactionRecents() {
    return _defaultQuickReactionKeys.map((i) => RecentEmoji(key: i)).toList();
  }

  RecentEmoji cloneRecentEmoji(RecentEmoji emoji) {
    return RecentEmoji(
      key: emoji.key,
      customPackId: emoji.customPackId,
      customPackRoomId: emoji.customPackRoomId,
      count: emoji.count,
    );
  }

  List<RecentEmoji> normalizeQuickReactionRecents(List<RecentEmoji> emojis) {
    var result = List<RecentEmoji>.empty(growable: true);

    for (var emoji in emojis) {
      if (result.contains(emoji)) continue;

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

    for (var emoji
        in _defaultQuickReactionKeys.map((i) => UnicodeEmoticon(i))) {
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
    reactionDebouncer.run(() => storeRecentReactions());
  }

  @override
  Future<void> typedEmoticon(Room room, Emoticon emoticon) async {
    var emoji = toRecentEmoji(room, emoticon);
    if (emoji == null) return;

    _typedEmoji = addToList(emoji, _typedEmoji);
    typedDebouncer.run(() => storeRecentlyTyped());
  }

  @override
  Future<void> setQuickReactionEmoticon(int index, Emoticon emoticon,
      {Room? room}) async {
    if (index < 0 || index >= RecentEmoticonComponent.quickReactionCount) {
      return;
    }

    var emoji = toRecentEmoji(room, emoticon);
    if (emoji == null || emoji.key == "") return;

    var quickReactions = normalizeQuickReactionRecents(_quickReactionEmoji);
    var existingIndex = quickReactions.indexWhere((i) => i == emoji);

    if (existingIndex != -1 && existingIndex != index) {
      var previous = quickReactions[index];
      quickReactions[index] = emoji;
      quickReactions[existingIndex] = previous;
    } else {
      quickReactions[index] = emoji;
    }

    _quickReactionEmoji = normalizeQuickReactionRecents(quickReactions);
    await storeQuickReactions();
  }

  List<RecentEmoji> addToList(RecentEmoji emoji, List<RecentEmoji> list) {
    const maxLen = 30;

    if (list.length > maxLen) {
      list = list.sublist(0, maxLen);
    }

    var existing = list.firstWhereOrNull((i) =>
        i.customPackId == emoji.customPackId &&
        i.customPackRoomId == emoji.customPackRoomId &&
        i.key == emoji.key);

    if (existing != null) {
      existing.count++;
    } else {
      list.insert(0, emoji);
    }

    return list;
  }

  Future<void> storeRecentReactions() async {
    var content = {
      "recent_emoji": _reactionEmoji.map((i) => i.toJson()).toList()
    };
    client.matrixClient
        .setAccountData(client.matrixClient.userID!, reactionsKey, content);
  }

  Future<void> storeRecentlyTyped() async {
    var content = {"recent_emoji": _typedEmoji.map((i) => i.toJson()).toList()};

    await client.matrixClient
        .setAccountData(client.matrixClient.userID!, typedKey, content);
  }

  Future<void> storeQuickReactions() async {
    var content = {
      "recent_emoji": _quickReactionEmoji.map((i) => i.toJson()).toList()
    };

    await client.matrixClient.setAccountData(
        client.matrixClient.userID!, quickReactionsKey, content);
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
    _quickReactionEmoji = normalizeQuickReactionRecents([]);

    await storeRecentReactions();
    await storeRecentlyTyped();
    await storeQuickReactions();
  }
}

class RecentEmoji {
  RecentEmoji(
      {required this.key,
      this.customPackId,
      this.customPackRoomId,
      this.count = 1});

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
        count: count);
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
