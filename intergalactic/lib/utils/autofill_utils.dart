import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/components/command/command_component.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/matrix/matrix_member.dart';
import 'package:intergalactic/client/matrix/matrix_room_display_name_state.dart';
import 'package:flutter/material.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:intergalactic/utils/mention_search.dart';
import 'package:intergalactic/utils/room_mention_utils.dart';

class AutofillUtils {
  /// Maximum mention suggestions returned in total, across both the ranked
  /// tier and the legacy fuzzy tier. This was the implicit bound before the
  /// ranked tier existed, when one `Fuzzy.search(string, 20)` produced the
  /// whole list.
  static const int _mentionSuggestionLimit = 20;

  static List<AutofillSearchResult> search(
    String string,
    Client client, {
    Room? room,
  }) {
    List<AutofillSearchResult>? results;

    var firstChar = string.characters.first;

    string = string.substring(1);
    switch (firstChar) {
      case "/":
        results = room != null ? searchCommands(string, room) : null;
        string = string.replaceAll("/", "");
        break;
      case "#":
        results = room != null ? searchRooms(string, room) : null;
        break;
      case "@":
        // Mentions do their own matching and ranking across every name a
        // member is known by, so they skip the single-key fuzzy pass below.
        return room != null
            ? searchUsers(string, room)
            : <AutofillSearchResult>[];
      case ":":
        results = searchEmoticon(string, client: client, room: room);
        break;

      default:
        break;
    }

    if (results == null) {
      return [];
    }

    var fuzzy = Fuzzy<AutofillSearchResult>(
      results,
      options: FuzzyOptions(
        keys: [
          WeightedKey(
            name: "result",
            getter: (result) {
              return result.result;
            },
            weight: 1,
          ),
        ],
      ),
    );

    return fuzzy.search(string, 20).map((e) {
      return e.item;
    }).toList();
  }

  static List<AutofillSearchResult> searchCommands(String string, Room room) {
    var component = room.client.getComponent<CommandComponent>();
    if (component != null) {
      var result = component.getCommands();
      return result.map((e) => AutofillSearchResult(e, "/$e")).toList();
    } else {
      return [];
    }
  }

  /// Mention suggestions for [string], the text typed after the `@` trigger.
  ///
  /// A member is found by their room nickname, their username localpart, their
  /// global account display name or their full user id, and is listed once
  /// however many of those matched. The row still shows the nickname.
  ///
  /// This only widens what is findable: the nickname-only fuzzy search it grew
  /// out of still runs as a final tier, so no query that used to offer someone
  /// stops offering them.
  static List<AutofillSearchResult> searchUsers(String string, Room room) {
    final members = room.memberIds
        .map((e) => room.getMemberOrFallback(e))
        .toList();

    final candidates = <String, (Member, MentionSearchCandidate)>{
      for (final member in members)
        member.identifier: (member, mentionCandidateForMember(member)),
    };

    // Insertion ordered, and keyed by user id so that two members sharing a
    // nickname stay two suggestions.
    final suggestions = <String, AutofillSearchResult>{};

    if (mentionQueryMatches(matrixRoomMention, string)) {
      suggestions[matrixRoomMention] = AutofillSearchResultRoomMention();
    }

    final matches = searchMentionCandidates(
      string,
      candidates.values.map((entry) => entry.$2),
      // A bare `@` lists everyone, as it did before this search existed.
      limit: normalizeMentionQuery(string).isEmpty
          ? null
          : _mentionSuggestionLimit,
    );

    for (final match in matches) {
      final entry = candidates[match.userId];
      if (entry == null) continue;
      suggestions.putIfAbsent(
        match.userId,
        () => _avatarResultFor(entry.$1, entry.$2),
      );
    }

    // The combined cap, not a per-tier one. Before the ranked tier existed the
    // whole suggestion list was bounded by a single `Fuzzy.search(string, 20)`;
    // running two tiers without this would let 20 ranked results and 20 legacy
    // results reach the caller.
    if (suggestions.length < _mentionSuggestionLimit) {
      for (final legacy in _legacyMentionSuggestions(
        string,
        candidates,
        limit: _mentionSuggestionLimit - suggestions.length,
      )) {
        suggestions.putIfAbsent(legacy.$1, () => legacy.$2);
        if (suggestions.length >= _mentionSuggestionLimit) {
          break;
        }
      }
    }

    return suggestions.values.toList();
  }

  /// The nickname-only fuzzy search that mention suggestions used before they
  /// became searchable by username and account name, kept as a final tier.
  ///
  /// It is where typo tolerance lives — its bitap matching forgives a
  /// transposed `jhon`, which the exact tiers of [searchMentionCandidates] do
  /// not. Its hits rank below the tiered ones rather than replacing them.
  static List<(String, AutofillSearchResult)> _legacyMentionSuggestions(
    String string,
    Map<String, (Member, MentionSearchCandidate)> candidates, {
    int limit = _mentionSuggestionLimit,
  }) {
    final previous = <(String, AutofillSearchResult)>[
      (matrixRoomMention, AutofillSearchResultRoomMention()),
      for (final entry in candidates.entries)
        (entry.key, _avatarResultFor(entry.value.$1, entry.value.$2)),
    ];

    final fuzzy = Fuzzy<(String, AutofillSearchResult)>(
      previous,
      options: FuzzyOptions(
        keys: [
          WeightedKey(
            name: "result",
            getter: (entry) => entry.$2.result,
            weight: 1,
          ),
        ],
      ),
    );

    return fuzzy.search(string, limit).map((e) => e.item).toList();
  }

  /// Reduces a member to the identity fields the mention search matches.
  ///
  /// [Member.displayName] is already the room nickname when one is set; the
  /// account display name underneath it is only reachable on the Matrix
  /// implementation, the same way the nickname settings page reads it.
  static MentionSearchCandidate mentionCandidateForMember(Member member) {
    return MentionSearchCandidate(
      userId: member.identifier,
      displayName: member.displayName,
      accountDisplayName: member is MatrixMember
          ? member.matrixUser.calcDisplayname()
          : null,
    );
  }

  static AutofillSearchResultAvatar _avatarResultFor(
    Member member,
    MentionSearchCandidate match,
  ) {
    return AutofillSearchResultAvatar(
      match.displayName,
      buildUserMentionSlug(match.displayName, match.userId),
      member.avatar,
      member.defaultColor,
    );
  }

  static List<AutofillSearchResult> searchRooms(String string, Room room) {
    var rooms = List<Room>.empty(growable: true);
    var spaces = room.client.spaces.where(
      (element) => element.containsRoom(room.identifier),
    );
    for (var space in spaces) {
      for (var room in space.rooms) {
        if (!rooms.contains(room)) {
          rooms.add(room);
        }
      }
    }
    var fuzzy = Fuzzy<Room>(
      rooms,
      options: FuzzyOptions(
        keys: [
          WeightedKey(
            name: "displayName",
            getter: (result) {
              return result.displayName;
            },
            weight: 1,
          ),
        ],
      ),
    );

    return fuzzy.search(string, 20).map((e) {
      return AutofillSearchResult(e.item.displayName, e.item.identifier);
    }).toList();
  }

  static List<AutofillSearchResult> searchEmoticon(
    String string, {
    int limit = 20,
    required Client client,
    Room? room,
    double threshold = 0.2,
  }) {
    List<EmoticonPack>? packs;
    if (room != null) {
      var emoticons = room.getComponent<RoomEmoticonComponent>();
      packs = emoticons?.availableEmoji;
    } else {
      var emoticons = client.getComponent<EmoticonComponent>();
      packs = emoticons?.availablePacks;
    }

    if (packs == null) return [];

    var result = List<AutofillSearchResultEmoticon>.empty(growable: true);

    for (var pack in packs) {
      var fuzzy = Fuzzy<Emoticon>(
        pack.emoji,
        options: FuzzyOptions(
          threshold: threshold,
          keys: [
            WeightedKey(
              name: "shortcode",
              getter: (obj) {
                return obj.shortcode ?? "";
              },
              weight: 1,
            ),
          ],
        ),
      );

      var searchResult = fuzzy.search(string, limit);

      result.addAll(
        searchResult.map((e) {
          return AutofillSearchResultEmoticon(
            e.item.shortcode!,
            e.item.slug,
            e.item,
            score: e.score,
          );
        }),
      );

      if (result.length >= limit) {
        break;
      }
    }

    result.sort((a, b) => a.score.compareTo(b.score));

    return result;
  }
}

class AutofillSearchResult {
  String result;
  String slug;
  AutofillSearchResult(this.result, this.slug);
}

class AutofillSearchResultAvatar extends AutofillSearchResult {
  ImageProvider? image;
  Color fallbackColor;

  AutofillSearchResultAvatar(
    super.result,
    super.slug,
    this.image,
    this.fallbackColor,
  );
}

class AutofillSearchResultRoomMention extends AutofillSearchResult {
  AutofillSearchResultRoomMention()
    : super(matrixRoomMention, matrixRoomMention);
}

class AutofillSearchResultEmoticon extends AutofillSearchResult {
  Emoticon emoticon;
  double score;
  AutofillSearchResultEmoticon(
    super.result,
    super.slug,
    this.emoticon, {
    this.score = 0,
  });
}
