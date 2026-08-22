import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/calendar_room/calendar_room_component.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/event_search/event_search_component.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:intergalactic/client/components/voip/voip_component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/invitation_view/send_invitation.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';

@visibleForTesting
IconData debugRoomQuickAccessPanelToggleIconForTesting({
  required bool hideSidePanel,
  required bool forceSidePanelVisible,
}) {
  return _roomQuickAccessPanelToggleIcon(
    hideSidePanel: hideSidePanel,
    forceSidePanelVisible: forceSidePanelVisible,
  );
}

IconData _roomQuickAccessPanelToggleIcon({
  required bool hideSidePanel,
  required bool forceSidePanelVisible,
}) {
  final sidePanelVisible = forceSidePanelVisible || !hideSidePanel;
  return sidePanelVisible ? Icons.chevron_right : Icons.chevron_left;
}

class RoomQuickAccessMenu {
  final Room room;
  final List<RoomQuickAccessMenuEntry> actionsAfterInvite;
  final Function(BuildContext context)? onTogglePanel;
  final bool forceSidePanelVisible;
  late final List<RoomQuickAccessMenuEntry> actions;

  RoomQuickAccessMenu({
    required this.room,
    this.actionsAfterInvite = const [],
    this.onTogglePanel,
    this.forceSidePanelVisible = false,
  }) {
    final bool canSearch =
        room.client.getComponent<EventSearchComponent>() != null;

    final invitation = room.client.getComponent<InvitationComponent>();

    final bool supportsPinnedMessages =
        room.getComponent<PinnedMessagesComponent>() != null;

    final calls = room.client.getComponent<VoipComponent>();
    final direct = room.client.getComponent<DirectMessagesComponent>();
    final calendar = room.getComponent<CalendarRoom>();
    final bool canCall =
        calls != null && direct?.isRoomDirectMessage(room) == true;

    final bool hasEncryptedEvents =
        room.timeline?.events.any((e) => e is TimelineEventEncrypted) == true;
    actions = [
      if (hasEncryptedEvents)
        RoomQuickAccessMenuEntry(
          name: "Retry Decrypt",
          icon: Icons.lock_open,
          action: (context) => room.retryDecryptAll(),
        ),
      if (invitation != null)
        RoomQuickAccessMenuEntry(
          name: "Invite",
          action: (context) => AdaptiveDialog.show(
            context,
            builder: (context) => SendInvitationWidget(
              room.client,
              invitation,
              roomId: room.identifier,
              displayName: room.displayName,
              existingMembers: room.memberIds,
              room: room,
            ),
            title: "Invite",
          ),
          icon: Icons.person_add,
        ),
      ...actionsAfterInvite,
      if (canCall)
        RoomQuickAccessMenuEntry(
          name: "Call",
          action: (context) => calls.startCall(room.identifier, CallType.voice),
          icon: Icons.call,
        ),
      if (!preferences.hideRoomSidePanel.value) ...[
        if (calendar?.hasCalendar == true && calendar?.isCalendarRoom == false)
          RoomQuickAccessMenuEntry(
            name: "Calendar",
            action: (context) => EventBus.openCalendar.add(null),
            icon: Icons.calendar_month,
          ),
        if (supportsPinnedMessages)
          RoomQuickAccessMenuEntry(
            name: "Pinned Messages",
            action: (context) => EventBus.openPinnedMessages.add(null),
            icon: Icons.push_pin,
          ),
        if (canSearch)
          RoomQuickAccessMenuEntry(
            name: CommonStrings.promptSearch,
            action: (context) => EventBus.startSearch.add(null),
            icon: Icons.search,
          ),
      ],
      if (Layout.desktop)
        RoomQuickAccessMenuEntry(
          name: "Toggle Panel",
          action:
              onTogglePanel ??
              (context) => EventBus.toggleRoomSidePanel.add(null),
          icon: _roomQuickAccessPanelToggleIcon(
            hideSidePanel: preferences.hideRoomSidePanel.value,
            forceSidePanelVisible: forceSidePanelVisible,
          ),
        ),
    ];
  }
}

class RoomQuickAccessMenuEntry {
  final String name;
  final Function(BuildContext context)? action;
  final IconData icon;
  final bool selected;
  final String? semanticLabel;

  RoomQuickAccessMenuEntry({
    required this.name,
    required this.action,
    required this.icon,
    this.selected = false,
    this.semanticLabel,
  });
}
