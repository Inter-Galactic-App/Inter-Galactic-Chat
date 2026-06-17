import 'dart:convert';

import 'package:intergalactic/client/client.dart' as commet;
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/room_preview.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/fixed_model.dart';

const String matrixIgnoredUserListAccountDataType = "m.ignored_user_list";

extension MatrixExtensions on Client {
  Future<FileResponse> getContentFromUri(Uri uri) {
    return getContent(uri.authority, uri.pathSegments.first);
  }

  Future<FileResponse> getContentThumbnailFromUri(
      Uri uri, int width, int height) {
    return getContentThumbnail(
        uri.authority, uri.pathSegments.first, width, height);
  }

  Future<RoomPreview?> getRoomPreview(String roomId,
      {List<String>? via}) async {
    var result = await request(RequestType.GET,
        "/client/unstable/im.nheko.summary/rooms/${Uri.encodeComponent(roomId)}/summary",
        query: {
          if (via != null) "via": via.join(","),
        });

    var name = result["name"] as String?;
    var id = result["room_id"] as String?;
    var avatar = result["avatar_url"] as String?;
    var topic = result["topic"] as String?;
    var numMembers = result["num_joined_members"] as int?;
    var joinRule = result["join_rule"] as String?;

    var type = switch (result["room_type"]) {
      "m.space" => commet.RoomType.space,
      "chat.commet.calendar" => commet.RoomType.calendar,
      "chat.commet.photo_album" => commet.RoomType.photoAlbum,
      "org.matrix.msc3417.call" => commet.RoomType.voipRoom,
      _ => commet.RoomType.defaultRoom
    };

    var visibility = switch (joinRule) {
      "public" => commet.RoomVisibilityPublic(),
      "knock" => commet.RoomVisibilityPrivate(),
      "invite" => commet.RoomVisibilityPrivate(),
      "private" => commet.RoomVisibilityPrivate(),
      "restricted" => commet.RoomVisibilityRestricted([]),
      _ => commet.RoomVisibilityPrivate(),
    };

    if (name != null && id != null) {
      ImageProvider? image;
      if (avatar != null) {
        var mxc = Uri.parse(avatar);
        image = MatrixMxcImage(mxc, autoLoadFullRes: false, this);
      }

      return GenericRoomPreview(id,
          displayName: name,
          type: type,
          avatar: image,
          numMembers: numMembers,
          visibility: visibility,
          topic: topic);
    }

    return null;
  }

  Future<void> submitMatrixRoomReport(String roomId, {String? reason}) async {
    await request(
      RequestType.POST,
      "/client/v3/rooms/${Uri.encodeComponent(roomId)}/report",
      contentType: "application/json",
      data: jsonEncode({
        "reason": reason ?? "",
      }),
    );
  }

  Future<void> submitMatrixEventReport(
    String roomId,
    String eventId, {
    String? reason,
  }) async {
    await request(
      RequestType.POST,
      "/client/v3/rooms/${Uri.encodeComponent(roomId)}/report/${Uri.encodeComponent(eventId)}",
      contentType: "application/json",
      data: jsonEncode({
        "reason": reason ?? "",
      }),
    );
  }

  Future<void> submitMatrixUserReport(String userId, {String? reason}) async {
    await request(
      RequestType.POST,
      "/client/v3/users/${Uri.encodeComponent(userId)}/report",
      contentType: "application/json",
      data: jsonEncode({
        "reason": reason ?? "",
      }),
    );
  }

  Set<String> matrixIgnoredUserIds() {
    var state = accountData[matrixIgnoredUserListAccountDataType]?.content;
    return _readIgnoredUsers(state).keys.toSet();
  }

  bool isMatrixUserIgnored(String userId) {
    return matrixIgnoredUserIds().contains(userId);
  }

  Future<void> setMatrixUserIgnored(String userId, bool ignored) async {
    var current = <String, dynamic>{};
    var accountDataContent =
        accountData[matrixIgnoredUserListAccountDataType]?.content;

    if (accountDataContent != null) {
      current = Map<String, dynamic>.from(accountDataContent);
    }

    var ignoredUsers = _readIgnoredUsers(current);

    if (ignored) {
      ignoredUsers[userId] = <String, dynamic>{};
    } else {
      ignoredUsers.remove(userId);
    }

    current["ignored_users"] = ignoredUsers;
    current.remove("users");

    var matrixUserId = userID;
    if (matrixUserId == null) {
      throw StateError("Cannot update ignored users without a Matrix user ID");
    }

    await setAccountData(
      matrixUserId,
      matrixIgnoredUserListAccountDataType,
      current,
    );
  }

  Map<String, dynamic> _readIgnoredUsers(Object? content) {
    if (content is! Map) {
      return <String, dynamic>{};
    }

    var ignoredUsers = content["ignored_users"];

    if (ignoredUsers is! Map) {
      ignoredUsers = content["users"];
    }

    if (ignoredUsers is! Map) {
      return <String, dynamic>{};
    }

    return Map<String, dynamic>.from(ignoredUsers);
  }

  Future<void> addEmoticonRoomPack(String roomId, String packKey) async {
    var state = BasicEvent(
        type: MatrixEmoticonComponent.globalEmoteRoomsStateKey, content: {});

    if (accountData
        .containsKey(MatrixEmoticonComponent.globalEmoteRoomsStateKey)) {
      state = accountData[MatrixEmoticonComponent.globalEmoteRoomsStateKey]!;
    }

    if (!state.content.containsKey("rooms")) {
      state.content['rooms'] = {};
    }

    var rooms = state.content['rooms'] as Map;
    if (!rooms.containsKey(roomId)) {
      rooms[roomId] = {};
    }

    var roomPacks = rooms[roomId] as Map;
    roomPacks[packKey] = {};

    await setAccountData(userID!,
        MatrixEmoticonComponent.globalEmoteRoomsStateKey, state.content);
  }

  Future<void> removeEmoticonRoomPack(String roomId, String packKey) async {
    var state = BasicEvent(
        type: MatrixEmoticonComponent.globalEmoteRoomsStateKey, content: {});

    if (accountData
        .containsKey(MatrixEmoticonComponent.globalEmoteRoomsStateKey)) {
      state = accountData[MatrixEmoticonComponent.globalEmoteRoomsStateKey]!;
    }

    if (!state.content.containsKey("rooms")) {
      state.content['rooms'] = {};
    }

    var rooms = state.content['rooms'] as Map;
    if (!rooms.containsKey(roomId)) {
      rooms[roomId] = {};
    }

    var roomPacks = rooms[roomId] as Map;
    roomPacks.remove(packKey);

    await setAccountData(userID!,
        MatrixEmoticonComponent.globalEmoteRoomsStateKey, state.content);
  }

  bool isEmoticonPackGloballyAvailable(String roomId, String packKey) {
    if (!accountData
        .containsKey(MatrixEmoticonComponent.globalEmoteRoomsStateKey)) {
      return false;
    }

    var state =
        accountData[MatrixEmoticonComponent.globalEmoteRoomsStateKey]!.content;
    if (!state.containsKey("rooms")) {
      return false;
    }

    var rooms = state["rooms"] as Map;
    if (!rooms.containsKey(roomId)) {
      return false;
    }

    var roomData = rooms[roomId] as Map;

    return roomData.containsKey(packKey);
  }

  // This is stupid, is there a better way to do this?
  Future<bool> isRoomAliasAvailable(String alias) async {
    try {
      await request(
        RequestType.GET,
        '/client/v3/directory/room/${Uri.encodeComponent(alias)}',
      );
      return false;
    } catch (exception) {
      if (exception is MatrixException) {
        if (exception.error == MatrixError.M_NOT_FOUND) {
          return true;
        }
      }
      return false;
    }
  }
}
