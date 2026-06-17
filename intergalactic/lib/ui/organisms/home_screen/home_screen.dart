import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/room_header.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/navigation/quick_switcher.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_screen_view.dart';
import 'package:intergalactic/utils/update_checker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HomeScreen extends StatefulWidget {
  final ClientManager clientManager;
  final Client? filterClient;
  final int numRecentRooms;
  final void Function()? onBurgerMenuTap;
  const HomeScreen({
    super.key,
    required this.clientManager,
    this.filterClient,
    this.onBurgerMenuTap,
    this.numRecentRooms = 5,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late List<Room> recentActivity;

  Client? filterClient;

  late List<StreamSubscription> subscriptions;
  Timer? _syncRefreshTimer;

  @override
  void initState() {
    filterClient = widget.filterClient;

    subscriptions = [
      widget.clientManager.onSync.stream.listen(onSync),
      widget.clientManager.onClientRemoved.stream.listen((_) {
        if (!mounted) return;
        setState(() {
          updateRecent();
        });
      }),
      preferences.onSettingChanged.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      EventBus.setFilterClient.stream.listen(setFilterClient),
    ];

    if (preferences.checkForUpdates.value == true) {
      UpdateChecker.checkForUpdates();
    }

    updateRecent();
    super.initState();
  }

  @override
  void dispose() {
    _syncRefreshTimer?.cancel();
    for (var element in subscriptions) {
      element.cancel();
    }

    super.dispose();
  }

  void onSync(void event) {
    _syncRefreshTimer?.cancel();
    _syncRefreshTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        updateRecent();
      });
    });
  }

  void updateRecent() {
    recentActivity =
        List.from(filterClient?.rooms ?? widget.clientManager.rooms);

    recentActivity.removeWhere((element) => element.lastEvent == null);

    mergeSort(recentActivity, compare: (a, b) {
      return b.lastEventTimestamp.compareTo(a.lastEventTimestamp);
    });

    if (recentActivity.length > widget.numRecentRooms) {
      recentActivity = recentActivity.sublist(0, widget.numRecentRooms);
    }
  }

  @override
  Widget build(BuildContext context) {
    // On mobile show all non-DM rooms (including space rooms) so users can
    // reach every room from the home screen, not just orphan (non-space) rooms.
    // On desktop keep singleRooms() which is the correct home-panel behaviour.
    final List<Room> homeRooms;
    if (Layout.mobile) {
      final dmIds = widget.clientManager.directMessages.directMessageRooms
          .map((r) => r.identifier)
          .toSet();
      homeRooms = (filterClient?.rooms ?? widget.clientManager.rooms)
          .where((r) => !dmIds.contains(r.identifier))
          .toList();
    } else {
      homeRooms = widget.clientManager.singleRooms(filterClient: filterClient);
    }

    return Column(
      children: [
        if (Layout.mobile)
          tiamat.Tile.low(
            caulkClipBottomRight: true,
            caulkClipBottomLeft: true,
            caulkBorderBottom: true,
            child: ScaledSafeArea(
              bottom: false,
              left: false,
              right: false,
              child: SizedBox(
                height: 50,
                child: HeaderView(
                  showBurger: Layout.mobile,
                  onBurgerMenuTap: widget.onBurgerMenuTap,
                  text: CommonStrings.promptHome,
                  menu: SizedBox(
                      width: 50,
                      height: 50,
                      child: tiamat.IconButton(
                        icon: Icons.search,
                        onPressed: () => QuickSwitcher.show(context),
                      )),
                ),
              ),
            ),
          ),
        if (Layout.desktop)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(8),
              color: ColorScheme.of(context).surfaceContainerLow,
              child: InkWell(
                onTap: () => QuickSwitcher.show(context),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(spacing: 8, children: [
                        Icon(Icons.search),
                        tiamat.Text.labelLow(CommonStrings.promptSearch),
                      ]),
                      if (Layout.desktop)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                          child: tiamat.Text.labelLow("Ctrl + K"),
                        )
                    ],
                  ),
                ),
              ),
            ),
          ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.all(0),
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    HomeScreenView(
                      clientManager: widget.clientManager,
                      filterClient: filterClient,
                      rooms: homeRooms,
                      recentActivity: recentActivity,
                      onRoomClicked: (room) => EventBus.openRoom
                          .add((room.identifier, room.client.identifier)),
                      joinRoom: joinRoom,
                      createRoom: createRoom,
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Future<void> joinRoom(Client client, String address) async {
    await client.joinRoom(address);
  }

  Future<void> createRoom(Client client, CreateRoomArgs args) async {
    await client.createRoom(args);
  }

  void setFilterClient(Client? event) {
    if (!mounted) return;
    setState(() {
      filterClient = event;
      updateRecent();
    });
  }
}
