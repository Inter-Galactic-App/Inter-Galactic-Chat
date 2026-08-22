class RoomEventSettings {
  static const String stateEventType = "chat.intergalactic.room_events";

  final bool showJoinEvents;
  final bool showLeaveEvents;
  final bool showInviteEvents;
  final bool showProfileAccountUpdates;

  const RoomEventSettings({
    this.showJoinEvents = true,
    this.showLeaveEvents = true,
    this.showInviteEvents = true,
    this.showProfileAccountUpdates = false,
  });

  factory RoomEventSettings.fromStateContent(Map<String, dynamic>? content) {
    if (content == null) {
      return const RoomEventSettings();
    }

    final showJoinEvents = content["show_join_events"];
    final showLeaveEvents = content["show_leave_events"];
    final showInviteEvents = content["show_invite_events"];
    final showProfileAccountUpdates = content["show_profile_account_updates"];

    return RoomEventSettings(
      showJoinEvents: showJoinEvents is bool ? showJoinEvents : true,
      showLeaveEvents: showLeaveEvents is bool ? showLeaveEvents : true,
      showInviteEvents: showInviteEvents is bool
          ? showInviteEvents
          : showJoinEvents is bool
              ? showJoinEvents
              : true,
      showProfileAccountUpdates:
          showProfileAccountUpdates is bool ? showProfileAccountUpdates : false,
    );
  }

  RoomEventSettings copyWith({
    bool? showJoinEvents,
    bool? showLeaveEvents,
    bool? showInviteEvents,
    bool? showProfileAccountUpdates,
  }) {
    return RoomEventSettings(
      showJoinEvents: showJoinEvents ?? this.showJoinEvents,
      showLeaveEvents: showLeaveEvents ?? this.showLeaveEvents,
      showInviteEvents: showInviteEvents ?? this.showInviteEvents,
      showProfileAccountUpdates:
          showProfileAccountUpdates ?? this.showProfileAccountUpdates,
    );
  }

  Map<String, dynamic> toStateContent() {
    return {
      "show_join_events": showJoinEvents,
      "show_leave_events": showLeaveEvents,
      "show_invite_events": showInviteEvents,
      "show_profile_account_updates": showProfileAccountUpdates,
    };
  }
}
