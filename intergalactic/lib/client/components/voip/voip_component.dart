import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';

enum CallType { voice, video }

abstract class VoipComponent<T extends Client> implements Component<T> {
  Stream<VoipSession> get onSessionStarted;
  Stream<VoipSession> get onSessionEnded;

  List<VoipSession> getSessionsInRoom(String roomId);

  Future<void> startCall(String roomId, CallType type, {String? userId});

  bool canCallRoom(String roomId);
}
