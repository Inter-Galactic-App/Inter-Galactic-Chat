import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/space_icon.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SideNavigationBarDirectMessages extends StatefulWidget {
  const SideNavigationBarDirectMessages(this.directMessages,
      {super.key, this.onRoomTapped, this.filterClient, this.width = 70});
  final DirectMessagesInterface directMessages;
  final Client? filterClient;
  final double width;

  final void Function(Room room)? onRoomTapped;

  @override
  State<SideNavigationBarDirectMessages> createState() =>
      _SideNavigationBarDirectMessagesState();
}

class _SideNavigationBarDirectMessagesState
    extends State<SideNavigationBarDirectMessages> {
  late List<Room> rooms;
  Client? filterClient;

  late List<StreamSubscription> subscriptions;

  @override
  void initState() {
    super.initState();
    filterClient = widget.filterClient;

    rooms = applyRoomOrder(widget.directMessages.highlightedRoomsList);
    subscriptions = [
      EventBus.setFilterClient.stream.listen(setFilterClient),
      widget.directMessages.onHighlightedRoomsListUpdated.listen(onListUpdated),
    ];
  }

  @override
  void dispose() {
    for (var element in subscriptions) {
      element.cancel();
    }

    super.dispose();
  }

  void setFilterClient(Client? event) {
    setState(() {
      filterClient = event;
    });

    onListUpdated(null);
  }

  void onListUpdated(void event) {
    setState(() {
      var updated = widget.directMessages.highlightedRoomsList;

      if (filterClient != null) {
        updated = updated.where((i) => i.client == filterClient).toList();
      }

      rooms = applyRoomOrder(updated);
    });
  }

  List<Room> applyRoomOrder(List<Room> source) {
    final savedOrder = preferences.getSidebarRoomOrder();
    if (savedOrder.isEmpty) return List<Room>.from(source);

    final roomMap = <String, Room>{
      for (final room in source) room.localId: room,
    };

    final ordered = <Room>[];
    for (final id in savedOrder) {
      final room = roomMap.remove(id);
      if (room != null) ordered.add(room);
    }
    // Append any rooms not yet in the saved order
    ordered.addAll(roomMap.values);
    return ordered;
  }

  Future<void> onRoomsReordered(List<Room> reordered) async {
    setState(() {
      rooms = reordered;
    });

    await preferences.setSidebarRoomOrder(
      reordered.map((room) => room.localId).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool empty = rooms.isEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, empty ? 0 : 4, 0, 0),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.all(0),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rooms.length,
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          final reordered = List<Room>.from(rooms);
          final item = reordered.removeAt(oldIndex);
          reordered.insert(newIndex, item);
          onRoomsReordered(reordered);
        },
        itemBuilder: (context, index) {
          final data = rooms[index];
          final child = SpaceIcon(
            displayName: data.displayName,
            placeholderColor: data.defaultColor,
            spaceId: data.identifier,
            avatar: data.avatar,
            width: widget.width,
            highlightedNotificationCount: data.notificationCount,
            onTap: () => widget.onRoomTapped?.call(data),
          );

          return ReorderableDelayedDragStartListener(
            key: ValueKey(data.localId),
            index: index,
            child: child,
          );
        },
      ),
    );
  }
}
