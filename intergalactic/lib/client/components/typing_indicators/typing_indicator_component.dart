import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';

abstract class TypingIndicatorComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  Stream<void> get onTypingUsersUpdated;

  bool? get typingIndicatorEnabledForRoom;
  Future<void> setTypingIndicatorEnabledForRoom(bool? value);

  List<Member> get typingUsers;

  Future<void> setTypingStatus(bool status);
}
