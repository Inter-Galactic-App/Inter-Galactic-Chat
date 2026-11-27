import 'dart:convert';

import 'package:intergalactic/client/client.dart' as commet;
import 'package:intergalactic/client/matrix/components/emoticon/matrix_image_pack_compatibility.dart';
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
    Uri uri,
    int width,
    int height,
  ) {
    return getContentThumbnail(
      uri.authority,
      uri.pathSegments.first,
      width,
      height,
    );
  }

  Future<RoomPreview?> getRoomPreview(
    String roomId, {
    List<String>? via,
  }) async {
    var result = await request(
      RequestType.GET,
      "/client/unstable/im.nheko.summary/rooms/${Uri.encodeComponent(roomId)}/summary",
      query: {if (via != null) "via": via.join(",")},
    );

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
      _ => commet.RoomType.defaultRoom,
    };

    var visibility = switch (joinRule) {
      "public" => commet.RoomVisibilityPublic(),
      "knock" => commet.RoomVisibilityKnock(),
      "invite" => commet.RoomVisibilityPrivate(),
      "private" => commet.RoomVisibilityPrivate(),
      "restricted" => commet.RoomVisibilityRestricted([]),
      "knock_restricted" => commet.RoomVisibilityKnockRestricted([]),
      _ => commet.RoomVisibilityPrivate(),
    };

    if (name != null && id != null) {
      ImageProvider? image;
      if (avatar != null) {
        var mxc = Uri.parse(avatar);
        image = MatrixMxcImage(mxc, autoLoadFullRes: false, this);
      }

      return GenericRoomPreview(
        id,
        displayName: name,
        type: type,
        avatar: image,
        numMembers: numMembers,
        visibility: visibility,
        topic: topic,
      );
    }

    return null;
  }

  Future<void> submitMatrixRoomReport(String roomId, {String? reason}) async {
    await request(
      RequestType.POST,
      "/client/v3/rooms/${Uri.encodeComponent(roomId)}/report",
      contentType: "application/json",
      data: jsonEncode({"reason": reason ?? ""}),
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
      data: jsonEncode({"reason": reason ?? ""}),
    );
  }

  Future<void> submitMatrixUserReport(String userId, {String? reason}) async {
    await request(
      RequestType.POST,
      "/client/v3/users/${Uri.encodeComponent(userId)}/report",
      contentType: "application/json",
      data: jsonEncode({"reason": reason ?? ""}),
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
    await _setEmoticonRoomPack(roomId, packKey, true);
  }

  Future<void> removeEmoticonRoomPack(String roomId, String packKey) async {
    await _setEmoticonRoomPack(roomId, packKey, false);
  }

  bool isEmoticonPackGloballyAvailable(String roomId, String packKey) {
    return [
      MatrixImagePackCompatibility.legacyGlobalEventType,
      MatrixImagePackCompatibility.stableGlobalEventType,
    ].any(
      (type) => MatrixImagePackCompatibility.hasGlobalPackReference(
        accountData[type]?.content,
        roomId,
        packKey,
      ),
    );
  }

  Future<void> _setEmoticonRoomPack(
    String roomId,
    String packKey,
    bool enabled,
  ) async {
    // Isolated per event type for the same reason as the room-state writer: a
    // failure on the stable type used to skip the legacy one, leaving the two
    // formats describing different global pack sets.
    // The same guard this file already uses for ignored users, rather than a
    // bare `!`: a null user id here is a state error worth naming, not a cast
    // failure at the call site.
    final matrixUserId = userID;
    if (matrixUserId == null) {
      throw StateError('Cannot update emoticon packs without a Matrix user ID');
    }

    Object? firstError;
    StackTrace? firstStack;
    for (final type in [
      MatrixImagePackCompatibility.stableGlobalEventType,
      MatrixImagePackCompatibility.legacyGlobalEventType,
    ]) {
      try {
        await setAccountData(
          matrixUserId,
          type,
          MatrixImagePackCompatibility.withGlobalPackReference(
            content: accountData[type]?.content,
            roomId: roomId,
            packKey: packKey,
            enabled: enabled,
          ),
        );
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
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
