import 'dart:async';

import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/invitation/invitation.dart';
import 'package:intergalactic/client/favorite_rooms.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/atoms/favorite_room_actions.dart';
import 'package:intergalactic/ui/atoms/room_panel.dart';
import 'package:intergalactic/ui/molecules/alert_view.dart';
import 'package:intergalactic/ui/molecules/invitation_display.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_status_strip.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:flutter/material.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HomeScreenView extends StatelessWidget {
  final ClientManager clientManager;
  final Client? filterClient;
  final List<Room>? rooms;
  final List<Room>? recentActivity;
  final List<Invitation>? invitations;
  final Function(Room room)? onRoomClicked;
  final Future<void> Function(Invitation invite)? acceptInvite;
  final Future<void> Function(Invitation invite)? rejectInvite;
  final Future<void> Function(Client client, String address)? joinRoom;
  final Future<void> Function(Client client, CreateRoomArgs args)? createRoom;

  const HomeScreenView({
    super.key,
    required this.clientManager,
    this.filterClient,
    this.rooms,
    this.recentActivity,
    this.onRoomClicked,
    this.acceptInvite,
    this.rejectInvite,
    this.joinRoom,
    this.createRoom,
    this.invitations,
  });

  String get labelHomeRecentActivity => Intl.message(
    "Recent Activity",
    name: "labelHomeRecentActivity",
    desc: "Short label for header of recent room activity",
  );

  String get labelHomeAlerts => Intl.message(
    "Alerts",
    name: "labelHomeAlerts",
    desc: "Short label for header of alerts",
  );

  String get labelHomeRoomsList => Intl.message(
    "Rooms",
    name: "labelHomeRoomsList",
    desc: "Short label for header of rooms list",
  );

  String get labelHomeInvitations => Intl.message(
    "Invitations",
    name: "labelHomeInvitations",
    desc: "Short label for header of invitations list",
  );

  String get labelHomeMarkAsRead => Intl.message(
    "Mark as Read",
    name: "labelHomeMarkAsRead",
    desc: "Context menu action that marks a room as read",
  );

  String get labelHomeAddFavorite => Intl.message(
    "Add to Favorites",
    name: "labelHomeAddFavorite",
    desc: "Context menu action that adds a room to the favorites list",
  );

  String get labelHomeRemoveFavorite => Intl.message(
    "Remove from Favorites",
    name: "labelHomeRemoveFavorite",
    desc: "Context menu action that removes a room from the favorites list",
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HomeAlertsSection(
          alertManager: clientManager.alertManager,
          header: labelHomeAlerts,
        ),
        HomeStatusStrip(
          clientManager: clientManager,
          filterClient: filterClient,
          onRoomClicked: onRoomClicked,
        ),
        if (invitations?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            child: invitationsList(),
          ),
        if (recentActivity?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            child: recentRooms(),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: roomsList(context),
        ),
      ],
    );
  }

  Widget recentRooms() {
    return Panel(
      mode: TileType.surface,
      header: labelHomeRecentActivity,
      child: ImplicitlyAnimatedList(
        shrinkWrap: true,
        padding: EdgeInsetsGeometry.zero,
        itemData: recentActivity!,
        initialAnimation: false,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, room) {
          final masked = dmLockController.shouldMaskRoomPreview(room);
          return withRoomPanelMenu(
            context,
            room,
            RoomPanel(
              displayName: room.displayName,
              avatar: room.avatar,
              color: room.defaultColor,
              body: masked
                  ? dmLockController.maskedPreviewText
                  : room.lastEvent?.plainTextBody,
              recentEventSender: !masked && room.lastEvent != null
                  ? room
                        .getMemberOrFallback(room.lastEvent!.senderId)
                        .displayName
                  : null,
              recentEventSenderColor: !masked && room.lastEvent != null
                  ? room.getColorOfUser(room.lastEvent!.senderId)
                  : null,
              onTap: () => onRoomClicked?.call(room),
              showUserAvatar:
                  clientManager.rooms
                      .where((element) => element.identifier == room.identifier)
                      .length >
                  1,
              userAvatar: room.client.self!.avatar,
              userDisplayName: room.client.self!.displayName,
              userColor: room.client.self!.defaultColor,
            ),
          );
        },
      ),
    );
  }

  Widget roomsList(BuildContext context) {
    return Panel(
      mode: TileType.surface,
      header: labelHomeRoomsList,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ImplicitlyAnimatedList(
            padding: EdgeInsetsGeometry.zero,
            physics: const NeverScrollableScrollPhysics(),
            initialAnimation: false,
            shrinkWrap: true,
            itemData: rooms!,
            itemBuilder: (context, room) {
              final masked = dmLockController.shouldMaskRoomPreview(room);
              return withRoomPanelMenu(
                context,
                room,
                RoomPanel(
                  displayName: room.displayName,
                  avatar: room.avatar,
                  color: room.defaultColor,
                  body: masked
                      ? dmLockController.maskedPreviewText
                      : room.lastEvent?.plainTextBody,
                  recentEventSender: !masked && room.lastEvent != null
                      ? room
                            .getMemberOrFallback(room.lastEvent!.senderId)
                            .displayName
                      : null,
                  recentEventSenderColor: !masked && room.lastEvent != null
                      ? room.getColorOfUser(room.lastEvent!.senderId)
                      : null,
                  onTap: () => onRoomClicked?.call(room),
                  showUserAvatar:
                      clientManager.rooms
                          .where(
                            (element) => element.identifier == room.identifier,
                          )
                          .length >
                      1,
                  userAvatar: room.client.self!.avatar,
                  userDisplayName: room.client.self!.displayName,
                  userColor: room.client.self!.defaultColor,
                ),
              );
            },
          ),
          tiamat.CircleButton(
            radius: BuildConfig.MOBILE ? 24 : 16,
            icon: Icons.add,
            onPressed: () => addRoomDialog(context),
          ),
        ],
      ),
    );
  }

  Widget invitationsList() {
    return Panel(
      mode: TileType.surfaceContainer,
      header: labelHomeInvitations,
      child: ImplicitlyAnimatedList(
        padding: EdgeInsetsGeometry.zero,
        physics: const NeverScrollableScrollPhysics(),
        initialAnimation: false,
        shrinkWrap: true,
        itemData: invitations!,
        itemBuilder: (context, invitation) {
          return InvitationDisplay(
            invitation,
            acceptInvitation: acceptInvite,
            rejectInvitation: rejectInvite,
          );
        },
      ),
    );
  }

  Widget withRoomPanelMenu(BuildContext context, Room room, Widget child) {
    final isFavorite = favoriteRoomStore.isFavorite(room);

    return AdaptiveContextMenu(
      items: [
        ContextMenuItem(
          text: labelHomeMarkAsRead,
          icon: Icons.visibility,
          onPressed: () => room.markAsRead(),
        ),
        ContextMenuItem(
          text: isFavorite ? labelHomeRemoveFavorite : labelHomeAddFavorite,
          icon: isFavorite ? Icons.star_outline : Icons.star,
          onPressed: () async {
            await runFavoriteWrite(
              context,
              favoriteRoomStore.setFavorite(
                room,
                !favoriteRoomStore.isFavorite(room),
              ),
            );
          },
        ),
      ],
      child: child,
    );
  }

  void addRoomDialog(BuildContext context) {
    GetOrCreateRoom.show(
      null,
      context,
      pickExisting: false,
      showAllRoomTypes: true,
    );
  }
}

class _HomeAlertsSection extends StatefulWidget {
  const _HomeAlertsSection({required this.alertManager, required this.header});

  final AlertManager alertManager;
  final String header;

  @override
  State<_HomeAlertsSection> createState() => _HomeAlertsSectionState();
}

class _HomeAlertsSectionState extends State<_HomeAlertsSection> {
  late final List<StreamSubscription<int>> _subscriptions;

  @override
  void initState() {
    super.initState();
    _subscriptions = [
      widget.alertManager.onAlertAdded.listen((_) => _onAlertsChanged()),
      widget.alertManager.onAlertRemoved.listen((_) => _onAlertsChanged()),
    ];
  }

  void _onAlertsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alertManager.alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Panel(
        mode: TileType.surfaceContainerLow,
        header: widget.header,
        child: AlertListView(
          widget.alertManager,
          padding: EdgeInsetsGeometry.zero,
          physics: const NeverScrollableScrollPhysics(),
        ),
      ),
    );
  }
}
