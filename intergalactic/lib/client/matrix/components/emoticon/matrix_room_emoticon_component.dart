import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/matrix/components/emoticon/canonical_space_ancestry.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_state_manager.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_space_emoticon_component.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_file_provider.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/client/matrix/matrix_space_link_validation.dart';
import 'package:intergalactic/client/matrix/matrix_timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/emoji/unicode_emoji.dart';
import 'package:intergalactic/utils/image_utils.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixRoomEmoticonComponent extends MatrixEmoticonComponent
    implements RoomEmoticonComponent<MatrixClient, MatrixRoom> {
  @override
  MatrixRoom room;

  MatrixRoomEmoticonComponent(MatrixClient client, this.room)
    : super(client, MatrixEmoticonRoomStateManager(room.matrixRoom));

  @override
  List<EmoticonPack> get availableEmoji => _getAvailablePacks(
    includeUnicode: true,
  ).where((element) => element.emoji.isNotEmpty).toList();

  @override
  List<EmoticonPack> get availableStickers => _getAvailablePacks(
    includeUnicode: false,
  ).where((element) => element.stickers.isNotEmpty).toList();

  @override
  bool get canCreatePack => room.permissions.canEditRoomEmoticons;

  @override
  String get ownerId => room.identifier;

  @override
  String get ownerDisplayName => room.displayName;

  @override
  List<EmoticonPack> get availablePacks {
    List<EmoticonPack> packs = List.from(ownedPacks, growable: true);

    for (final space in canonicalSpaceAncestors()) {
      var component = space.getComponent<SpaceEmoticonComponent>();
      if (component == null) continue;
      packs.addAll(component.ownedPacks);
    }

    var component = room.client.getComponent<EmoticonComponent>();

    if (component == null) return packs;

    packs.addAll(
      component.globalPacks().where((element) => !packs.contains(element)),
    );

    packs.addAll(
      component.ownedPacks.where((element) => !packs.contains(element)),
    );

    return orderPacks(packs);
  }

  @override
  Future<TimelineEvent?> sendSticker(
    Emoticon sticker,
    TimelineEvent? inReplyTo,
  ) async {
    if (sticker is! MatrixEmoticon) return null;

    var image = await ImageUtils.imageProviderToImage(sticker.image);

    matrix.Event? replyingTo;

    if (inReplyTo != null) {
      replyingTo = await room.matrixRoom.getEventById(inReplyTo.eventId);
    }
    String? mimeType;
    if (sticker.image is MatrixMxcImage) {
      mimeType = (sticker.image as MatrixMxcImage).mimeType;
    }

    // Sometimes MatrixMxcImage doesnt have mimetype loaded, so we need to look it up manually
    if (mimeType == null) {
      var provider = MxcFileProvider(
        client.getMatrixClient(),
        sticker.emojiUrl,
      );
      var data = await provider.getFileData();
      mimeType = Mime.lookupType("", data: data);
    }

    var extension = "";

    // element web wont render images if the body doesnt have an extension
    if (mimeType != null) {
      extension = ".${mimeType.split("/").last}";
    }

    var content = {
      "body": sticker.shortcode! + extension,
      "url": sticker.emojiUrl.toString(),
      if (preferences.stickerCompatibilityMode.value) "msgtype": "m.image",
      if (preferences.stickerCompatibilityMode.value)
        "chat.commet.type": "chat.commet.sticker",
      "info": {
        "w": image.width,
        "h": image.height,
        if (mimeType != null) "mimetype": mimeType,
      },
    };

    var id = await room.matrixRoom.sendEvent(
      content,
      type: preferences.stickerCompatibilityMode.value
          ? matrix.EventTypes.Message
          : matrix.EventTypes.Sticker,
      inReplyTo: replyingTo,
    );

    if (id != null) {
      var event = await room.matrixRoom.getEventById(id);
      return room.convertEvent(
        event!,
        timeline: (room.timeline as MatrixTimeline?)?.matrixTimeline,
      );
    }

    return null;
  }

  List<EmoticonPack> _getAvailablePacks({bool includeUnicode = false}) {
    var result = List<EmoticonPack>.of(ownedPacks);

    for (final space in canonicalSpaceAncestors()) {
      var component = space.getComponent<MatrixSpaceEmoticonComponent>();
      if (component != null) {
        result.addAll(component.ownedPacks.where((e) => !result.contains(e)));
      }
    }

    var globalComponent = room.client.getComponent<EmoticonComponent>();
    if (globalComponent != null) {
      for (var pack in globalComponent.globalPacks()) {
        if (!result.contains(pack)) {
          result.add(pack);
        }
      }
    }

    if (globalComponent != null) {
      result.addAll(
        globalComponent.ownedPacks.where((e) => !result.contains(e)),
      );
    }

    if (includeUnicode) result.addAll(UnicodeEmojis.packs!);

    return orderPacks(result);
  }

  /// The Spaces this room inherits image packs from, canonical ancestry first.
  ///
  /// MSC2545 scopes Space packs to this exact hierarchy. Room-local and
  /// account-global packs are added by the callers above and are deliberately
  /// outside this selection rule. A parent must have usable `via` data and
  /// either reciprocate the child link or authorize the parent-link sender.
  @visibleForTesting
  Iterable<MatrixSpace> canonicalSpaceAncestors() {
    final allSpaces = room.client.spaces.whereType<MatrixSpace>().toList(
      growable: false,
    );
    final spacesById = <String, MatrixSpace>{
      for (final space in allSpaces) space.identifier: space,
    };

    final ancestorIds = canonicalSpaceAncestorIds(
      roomId: room.identifier,
      canonicalParentIdsFor: (roomId) {
        final matrixRoom = roomId == room.identifier
            ? room.matrixRoom
            : spacesById[roomId]?.matrixRoom;
        return canonicalSpaceParentIds(
          parentState: matrixRoom?.states[matrix.EventTypes.SpaceParent],
          isCanonical: (state) => state.content['canonical'] == true,
          hasValidVia: (state) => hasValidSpaceVia(state.content['via']),
          isLegitimateParent: (parentId, state) {
            final parent = spacesById[parentId]?.matrixRoom;
            if (parent == null) return false;

            final childLink = parent.getState(
              matrix.EventTypes.SpaceChild,
              roomId,
            );
            if (hasValidSpaceVia(childLink?.content['via'])) return true;

            final senderId = state.senderId;
            final membership = parent.getState(
              matrix.EventTypes.RoomMember,
              senderId,
            );
            if (membership?.content['membership'] != 'join') return false;
            return parent.getPowerLevelByUserId(senderId) >=
                parent.powerForChangingStateEvent(matrix.EventTypes.SpaceChild);
          },
        );
      },
    );

    return ancestorIds
        .map((identifier) => spacesById[identifier])
        .whereType<MatrixSpace>();
  }

  @override
  bool isGloballyAvailable(String packId) {
    return room.matrixRoom.client.isEmoticonPackGloballyAvailable(
      room.matrixRoom.id,
      packId,
    );
  }

  Future<void> markAsGlobal(bool isGlobal, String packKey) async {
    if (isGlobal)
      return room.matrixRoom.client.addEmoticonRoomPack(
        room.matrixRoom.id,
        packKey,
      );

    return room.matrixRoom.client.removeEmoticonRoomPack(
      room.matrixRoom.id,
      packKey,
    );
  }

  Map<String, Map<String, String>> getEmotePacksFlat(
    matrix.ImagePackUsage emoticon,
  ) {
    var packs = availablePacks;

    var result = <String, Map<String, String>>{};

    for (var pack in packs) {
      var key = "${pack.displayName}-${pack.hashCode}";
      result[key] = <String, String>{};
      for (var emote in pack.emotes) {
        result[key]![emote.shortcode!] = (emote as MatrixEmoticon).emojiUrl
            .toString();
      }
    }

    return result;
  }
}
