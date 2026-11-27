import 'package:intergalactic/client/room_event_settings.dart';
import 'package:intergalactic/client/matrix/matrix_room_display_name_state.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../permissions.dart';

class MatrixRoomPermissions extends Permissions {
  late matrix.Room room;

  MatrixRoomPermissions(this.room);

  bool get _canWriteRoomDisplayNames =>
      room.canChangeStateEvent(matrixRoomDisplayNamesStateEventType) ||
      room.canChangeStateEvent(matrixRoomDisplayNamesLegacyStateEventType);

  @override
  bool get canChangeOwnNickname => _canWriteRoomDisplayNames;

  @override
  bool get canChangeOtherNicknames => _canWriteRoomDisplayNames;

  @override
  bool get canBan => room.canBan;

  @override
  bool get canKick => room.canKick;

  @override
  bool get canSendMessage => room.canSendDefaultMessages;

  @override
  bool get canEditAvatar => room.canChangeStateEvent("m.room.avatar");

  @override
  bool get canEditName => room.canChangeStateEvent("m.room.name");

  @override
  bool get canEditTopic =>
      room.canChangeStateEvent(matrix.EventTypes.RoomTopic);

  @override
  bool get canEditRoomEvents =>
      room.canChangeStateEvent(RoomEventSettings.stateEventType);

  @override
  bool get canEnableE2EE => room.canChangeStateEvent("m.room.encryption");

  @override
  bool get canEditRoomEmoticons => room.canSendDefaultStates;

  @override
  bool get canDeleteOtherUserMessages => room.canRedact;

  @override
  bool get canEditChildren =>
      room.canChangeStateEvent(matrix.EventTypes.SpaceChild);

  @override
  bool get canInviteUser => room.canInvite;

  @override
  bool get canChangeRoles => room.canChangePowerLevel;

  @override
  bool get canChangeVisibility =>
      room.canChangeStateEvent(matrix.EventTypes.RoomJoinRules);
}
