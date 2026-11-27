import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/room_component.dart';

/// Room component exposing each member's shared rich [UserActivity], read from
/// the room's [activityRoomStateEventType] state events, and letting the local
/// user publish (or clear) their own into this room.
abstract class ActivityRoomComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  /// The most recent visible activity [userId] has shared in this room, or null
  /// when they have none (or their client does not share activity).
  UserActivity? activityForUser(String userId);

  /// Fires when any member's shared activity in this room may have changed.
  /// Listeners should re-read [activityForUser] for the users they display.
  Stream<void> get onActivitiesChanged;

  /// Publishes the local user's [activity] as a state event in this room, or
  /// clears it when [activity] is null. Safe to call repeatedly; it no-ops when
  /// the encoded content matches what was last published from this component.
  Future<void> publishSelfActivity(UserActivity? activity);
}
