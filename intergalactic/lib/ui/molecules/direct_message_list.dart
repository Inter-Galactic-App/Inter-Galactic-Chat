import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/molecules/dm_pin_dialog.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import '../atoms/dot_indicator.dart';

class DirectMessageList extends StatefulWidget {
  const DirectMessageList(
      {required this.directMessages,
      this.onSelected,
      this.filterClient,
      super.key});
  final DirectMessagesInterface directMessages;

  final Client? filterClient;

  @override
  State<DirectMessageList> createState() => _DirectMessageListState();
  final Function(Room room)? onSelected;
}

class _DirectMessageListState extends State<DirectMessageList> {
  int numDMs = 0;
  Room? selectedRoom;
  late List<StreamSubscription> subscriptions;
  late List<Room> rooms;

  Client? filterClient;

  @override
  void initState() {
    filterClient = widget.filterClient;
    subscriptions = [
      widget.directMessages.onRoomsListUpdated.listen(onListUpdated),
      widget.directMessages.onHighlightedRoomsListUpdated.listen(onListUpdated),
      preferences.onSettingChanged.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      EventBus.setFilterClient.stream.listen(setFilterClient),
    ];

    updateRoomsList();

    super.initState();
  }

  void setFilterClient(Client? event) {
    setState(() {
      filterClient = event;
      updateRoomsList();
    });
  }

  @override
  void dispose() {
    for (var element in subscriptions) {
      element.cancel();
    }
    super.dispose();
  }

  void onListUpdated(void event) {
    setState(() {
      updateRoomsList();
    });
  }

  void sortRooms() {
    mergeSort(rooms, compare: (a, b) {
      return b.lastEventTimestamp.compareTo(a.lastEventTimestamp);
    });
  }

  void updateRoomsList() {
    rooms = List.from(widget.directMessages.directMessageRooms);

    if (filterClient != null) {
      rooms.removeWhere((i) => i.client != filterClient);
    }

    sortRooms();
  }

  @override
  Widget build(BuildContext context) {
    return ImplicitlyAnimatedList(
      itemData: rooms,
      initialAnimation: false,
      padding: EdgeInsets.zero,
      itemBuilder: (context, room) {
        final component = room.client.getComponent<DirectMessagesComponent>();
        final id = component?.getDirectMessagePartnerId(room);
        if (id == null) {
          return Container();
        }

        final masked = dmLockController.shouldMaskRoomPreview(room);
        final isLocked = dmLockController.isRoomLocked(room);

        final row = Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 2, 2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 62),
            child: Row(
              children: [
                Expanded(
                  child: UserPanel(
                    userId: id,
                    key: ValueKey("home-screen-direct-message-entry-${id}"),
                    client: room.client,
                    contextRoom: room,
                    detailOverride:
                        masked ? dmLockController.maskedPreviewText : null,
                    isDirectMessage: true,
                    onTap: () => setState(() {
                      selectedRoom = room;
                      widget.onSelected?.call(room);
                    }),
                  ),
                ),
                if (isLocked)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      masked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 16,
                    ),
                  ),
                room.displayNotificationCount > 0
                    ? const Padding(
                        padding: EdgeInsets.all(2.0),
                        child: DotIndicator(),
                      )
                    : Container()
              ],
            ),
          ),
        );

        return AdaptiveContextMenu(
          items: [
            ContextMenuItem(
              text: "Mark as Read",
              icon: Icons.visibility,
              onPressed: () => room.markAsRead(),
            ),
            ..._notificationSnoozeItems(room),
            ContextMenuItem(
              text: isLocked ? "Unlock DM" : "Lock DM",
              icon: isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
              onPressed: () => _toggleRoomLock(context, room, !isLocked),
            ),
          ],
          child: row,
        );
      },
    );
  }

  Future<void> _toggleRoomLock(
    BuildContext context,
    Room room,
    bool shouldLock,
  ) async {
    if (!shouldLock) {
      await dmLockController.setRoomLocked(room, false);
      return;
    }

    if (!dmLockController.isPinConfiguredForClient(room.client)) {
      final result = await AdaptiveDialog.show<DmPinDialogResult>(
        context,
        title: "Set PIN",
        builder: (_) => const DmPinDialog(
          mode: DmPinDialogMode.setPin,
          description:
              "Set a local PIN before locking direct messages on this account.",
          submitLabel: "Save PIN",
        ),
      );

      final newPin = result?.newPin;
      if (newPin == null || newPin.isEmpty) {
        return;
      }

      await dmLockController.setPinForClient(room.client, newPin);
    }

    await dmLockController.setRoomLocked(room, true);
    if (context.mounted) {
      AdaptiveDialog.show(
        context,
        title: "DM Locked",
        builder: (_) => tiamat.Text.label(
          "${room.displayName} now requires your local PIN before it opens.",
        ),
      );
    }
  }

  List<ContextMenuItem> _notificationSnoozeItems(Room room) {
    final snooze = preferences.getRoomNotificationSnooze(
      clientId: room.client.identifier,
      roomId: room.identifier,
    );

    if (snooze != null) {
      return [
        ContextMenuItem(
          text: "Unsnooze notifications",
          icon: Icons.notifications_active_outlined,
          onPressed: () => unawaited(_clearRoomSnooze(room)),
        ),
      ];
    }

    return [
      for (final option in RoomNotificationSnoozeDurationOption.values)
        ContextMenuItem(
          text: option.actionLabel,
          icon: Icons.notifications_paused_outlined,
          onPressed: () => unawaited(_snoozeRoom(room, option)),
        ),
    ];
  }

  Future<void> _snoozeRoom(
    Room room,
    RoomNotificationSnoozeDurationOption option,
  ) async {
    var changed = false;
    await ErrorUtils.tryRun(context, () async {
      await preferences.setRoomNotificationSnooze(
        clientId: room.client.identifier,
        roomId: room.identifier,
        duration: option.duration,
        source: 'dm_context_menu',
      );
      await NotificationManager.clearNotifications(room);
      changed = true;
    });
    if (mounted && changed) {
      setState(() {});
    }
  }

  Future<void> _clearRoomSnooze(Room room) async {
    var changed = false;
    await ErrorUtils.tryRun(context, () async {
      await preferences.clearRoomNotificationSnooze(
        clientId: room.client.identifier,
        roomId: room.identifier,
      );
      changed = true;
    });
    if (mounted && changed) {
      setState(() {});
    }
  }
}
