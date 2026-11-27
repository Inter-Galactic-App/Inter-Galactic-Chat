import 'dart:convert';

import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_room_component.dart';
import 'package:intergalactic/client/components/activity/activity_room_event.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';

/// Matrix-backed [ActivityRoomComponent].
///
/// Reads members' activity from `space.ourgalaxy.activity` state events and
/// publishes the local user's activity keyed by their user id. Change
/// notifications ride the room's existing update stream, so the component holds
/// no stream of its own to dispose — deliberate, because a VoIP room can be
/// torn down and reopened (mobile background / picture-in-picture) while the
/// call, and thus this component, stays alive.
class MatrixActivityRoomComponent
    extends RoomComponent<MatrixClient, MatrixRoom>
    implements ActivityRoomComponent<MatrixClient, MatrixRoom> {
  MatrixActivityRoomComponent(super.client, super.room);

  String? _lastPublishedContentSignature;

  @override
  Stream<void> get onActivitiesChanged => room.onUpdate;

  @override
  UserActivity? activityForUser(String userId) {
    if (userId.isEmpty) {
      return null;
    }

    final state = room.matrixRoom.getState(activityRoomStateEventType, userId);
    if (state == null) {
      return null;
    }

    // The state key says whose tile this activity renders on; it does not say
    // who wrote it. Matrix auth rules normally stop a user setting a state event
    // keyed to someone else's id, but that is a server-side guarantee we would
    // rather not stake another member's call tile on, so require the sender to
    // match before decoding.
    if (state.senderId != userId) {
      return null;
    }

    return decodeActivityRoomStateContent(state.content);
  }

  @override
  Future<void> publishSelfActivity(UserActivity? activity) async {
    final selfId = client.self?.identifier;
    if (selfId == null || selfId.isEmpty) {
      return;
    }

    final content = encodeActivityRoomStateContent(activity);
    final signature = jsonEncode(content);
    if (signature == _lastPublishedContentSignature) {
      return;
    }

    await room.matrixRoom.client.setRoomStateWithKey(
      room.matrixRoom.id,
      activityRoomStateEventType,
      selfId,
      content,
    );
    _lastPublishedContentSignature = signature;
  }
}
