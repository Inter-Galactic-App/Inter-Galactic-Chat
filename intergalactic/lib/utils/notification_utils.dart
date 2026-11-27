import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/main.dart';

class NotificationUtils {
  static (int, int) getNotificationCounts({Room? excludingRoom}) {
    var highlightedNotificationCount = 0;
    var notificationCount = 0;

    var topLevelSpaces =
        clientManager!.spaces.where((e) => e.isTopLevel).toList();

    for (var i in topLevelSpaces) {
      final rooms = i.roomsWithChildren.where((room) => room != excludingRoom);

      if (i.pushRule != PushRule.dontNotify) {
        highlightedNotificationCount +=
            rooms.where((room) => room.pushRule != PushRule.dontNotify).fold(
                  0,
                  (previousValue, room) =>
                      previousValue + room.highlightedNotificationCount,
                );
      }

      if (i.pushRule == PushRule.notify) {
        notificationCount +=
            rooms.where((room) => room.pushRule == PushRule.notify).fold(
                  0,
                  (previousValue, room) =>
                      previousValue + room.notificationCount,
                );
      }
    }

    for (var dm in clientManager!.directMessages.highlightedRoomsList) {
      if (dm == excludingRoom) {
        continue;
      }

      highlightedNotificationCount += dm.displayNotificationCount;
      notificationCount += dm.displayNotificationCount;
    }

    return (highlightedNotificationCount, notificationCount);
  }
}
