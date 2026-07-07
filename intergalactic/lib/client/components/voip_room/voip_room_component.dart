import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';

abstract class VoipRoomComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  List<String> getCurrentParticipants();

  Stream<void> get onParticipantsChanged;

  VoipSession? get currentSession;

  bool get canJoinCall;

  Future<VoipSession?> joinCall();

  Future<String?> getCallServerUrl();

  Future<void> clearAllCallMembershipStatus();
}
