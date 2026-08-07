import 'dart:math' as math;

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/atoms/room_header.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/atoms/space_header.dart';
import 'package:intergalactic/ui/molecules/direct_message_list.dart';
import 'package:intergalactic/ui/molecules/favorite_rooms_list.dart';
import 'package:intergalactic/ui/molecules/space_viewer.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/account_popup/account_popup.dart';
import 'package:intergalactic/ui/organisms/activity/local_activity_panel.dart';
import 'package:intergalactic/ui/organisms/background_task_view/background_task_view_container.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_screen.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu_desktop.dart';
import 'package:intergalactic/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:intergalactic/ui/organisms/sidebar_call_icon/sidebar_calls_list.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_soundboard_panel.dart';
import 'package:intergalactic/ui/organisms/space_summary/space_summary.dart';
import 'package:intergalactic/ui/pages/main/main_page.dart';
import 'package:intergalactic/ui/pages/main/room_primary_view.dart';
import 'package:intergalactic/ui/pages/settings/app_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class MainPageViewDesktop extends StatelessWidget {
  const MainPageViewDesktop(this.state, {super.key});
  final MainPageState state;

  String get directMessagesListHeaderDesktop => Intl.message(
    "Direct Messages",
    desc: "The header for the direct messages list on desktop",
    name: "directMessagesListHeaderDesktop",
  );

  String get favoritesListHeaderDesktop => Intl.message(
    "Favorites",
    desc: "The header for the favorites room list on desktop",
    name: "favoritesListHeaderDesktop",
  );

  String get favoritesEmptyStateDesktop => Intl.message(
    "Star a room from the room list to keep it handy here.",
    desc: "Empty state for the desktop favorites view",
    name: "favoritesEmptyStateDesktop",
  );

  static const EdgeInsets _currentUserListAvatarPadding = EdgeInsets.symmetric(
    vertical: 4,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _DesktopSmallWindowLayout(
          enabled: preferences.desktopSmallWindowMode.value,
          persistentRailLabels: AccessibilityScope.of(
            context,
          ).persistentActionLabels,
          size: constraints.biggest,
        );

        return tiamat.Foundation(
          child: Stack(
            children: [
              Row(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: layout.sidebarWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Tile(
                                caulkPadTop: true,
                                caulkPadRight: true,
                                caulkClipTopRight: true,
                                caulkClipBottomRight: true,
                                caulkBorderRight: true,
                                mode: TileType.surfaceContainerLowest,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    4,
                                    0,
                                    0,
                                  ),
                                  child: ScaledSafeArea(
                                    top: false,
                                    bottom: false,
                                    child: TutorialAnchor(
                                      id: TutorialAnchorIds.spaceRail,
                                      child: SideNavigationBar(
                                        currentUser: state.currentUser,
                                        filterClient: state.filterClient,
                                        width: layout.navigationRailWidth,
                                        buttonSize: layout.navigationButtonSize,
                                        extraEntryBuilders: [
                                          (width) {
                                            return SidebarCallsList(
                                              state.clientManager.callManager,
                                              width,
                                            );
                                          },
                                        ],
                                        onSpaceSelected: (space) {
                                          state.selectSpace(space);
                                        },
                                        onHomeSelected: () {
                                          state.selectHome();
                                        },
                                        onFavoritesSelected: () {
                                          state.selectFavorites();
                                        },
                                        favoritesSelected:
                                            state.currentView ==
                                            MainPageSubView.favorites,
                                        clearSpaceSelection: () {
                                          state.clearSpaceSelection();
                                        },
                                        onDirectMessageSelected: (room) {
                                          state.selectHome();
                                          state.selectRoom(room);
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (!layout.hoverRoomPicker)
                                Flexible(
                                  child: tiamat.Tile.surfaceContainer(
                                    caulkClipBottomLeft: true,
                                    caulkClipTopRight: true,
                                    caulkPadTop: true,
                                    caulkClipBottomRight: true,
                                    caulkClipTopLeft: true,
                                    child: TutorialAnchor(
                                      id: TutorialAnchorIds.roomList,
                                      child: buildRoomPicker(context, layout),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        tiamat.Tile.low(
                          caulkPadTop: true,
                          caulkClipTopRight: true,
                          caulkBorderTop: true,
                          caulkPadRight: Layout.mobile,
                          child: ScaledSafeArea(
                            top: false,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (layout.showAuxiliaryPanels ||
                                    state.forceCallPanelVisible)
                                  CallSoundboardPanel(
                                    callManager:
                                        state.clientManager.callManager,
                                  ),
                                if (layout.showAuxiliaryPanels ||
                                    state.forceActivityPanelVisible)
                                  LocalActivityPanel(
                                    userPanelHeight: layout.userPanelHeight,
                                    service: state.tutorialActivityService,
                                    child: TutorialAnchor(
                                      id: TutorialAnchorIds.accountPanel,
                                      child: currentUserPanel(
                                        state,
                                        context,
                                        height: layout.userPanelHeight,
                                        avatarRadius:
                                            layout.userPanelAvatarRadius,
                                        compactRail: layout.hoverRoomPicker,
                                      ),
                                    ),
                                  )
                                else
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: layout.userPanelHeight,
                                    ),
                                    child: TutorialAnchor(
                                      id: TutorialAnchorIds.accountPanel,
                                      child: currentUserPanel(
                                        state,
                                        context,
                                        height: layout.userPanelHeight,
                                        avatarRadius:
                                            layout.userPanelAvatarRadius,
                                        compactRail: layout.hoverRoomPicker,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  mainView(context, layout),
                ],
              ),
              if (layout.hoverRoomPicker)
                Positioned(
                  left: layout.navigationRailWidth,
                  top: 0,
                  bottom: layout.userPanelHeight,
                  child: _HoverRevealPanel(
                    side: _HoverPanelSide.left,
                    width: layout.roomPickerWidth,
                    icon: Icons.menu_open_rounded,
                    tooltip: "Rooms",
                    child: tiamat.Tile.surfaceContainer(
                      caulkClipBottomLeft: true,
                      caulkClipTopRight: true,
                      caulkPadTop: true,
                      caulkClipBottomRight: true,
                      caulkClipTopLeft: true,
                      child: TutorialAnchor(
                        id: TutorialAnchorIds.roomList,
                        child: buildRoomPicker(context, layout),
                      ),
                    ),
                  ),
                ),
              const BackgroundTaskViewContainer(),
            ],
          ),
        );
      },
    );
  }

  static SidePanelState? _initialRoomSidePanelState(MainPageState state) {
    final explicitState = switch (state.initialSidePanelState) {
      'thread' => SidePanelState.thread,
      'chat' => SidePanelState.chat,
      'defaultView' => SidePanelState.defaultView,
      'search' => SidePanelState.search,
      'pinnedMessages' => SidePanelState.pinnedMessages,
      'calendar' => SidePanelState.calendar,
      'nothing' => SidePanelState.nothing,
      _ => null,
    };

    if (explicitState != null) {
      return explicitState;
    }

    if (!state.forceCallRoomSideRailVisible) {
      return null;
    }

    return switch (state.callRoomSideRailMode) {
      CallRoomSideRailMode.chat => SidePanelState.chat,
      CallRoomSideRailMode.members => SidePanelState.defaultView,
    };
  }

  static Widget currentUserPanel(
    MainPageState state,
    BuildContext context, {
    double height = 50,
    double avatarRadius = 12,
    bool compactRail = false,
  }) {
    return StreamBuilder<Client>(
      stream: state.clientManager.onClientUpdated.stream,
      builder: (context, _) => _currentUserPanelContents(
        state,
        context,
        height: height,
        avatarRadius: avatarRadius,
        compactRail: compactRail,
      ),
    );
  }

  static Widget _currentUserPanelContents(
    MainPageState state,
    BuildContext context, {
    required double height,
    required double avatarRadius,
    required bool compactRail,
  }) {
    final manager = state.clientManager;
    Profile? current = state.currentUser;

    if (manager.clients.length == 1) {
      current = manager.clients.first.self;
    }
    final smallWindowMode = preferences.desktopSmallWindowMode.value;
    final localActivityService =
        state.tutorialActivityService ?? activityService;

    if (compactRail) {
      return _CompactUserRailPanel(
        state: state,
        current: current,
        client: _clientForProfile(current, manager),
        activityService: localActivityService,
        height: height,
        avatarRadius: avatarRadius,
        smallWindowMode: smallWindowMode,
      );
    }

    final popupClient = _clientForProfile(current, manager);

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: popupClient == null
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(
                        Layout.mobile ? 10 : 8,
                        Layout.mobile ? 7 : 8,
                        Layout.mobile ? 6 : 8,
                        Layout.mobile ? 7 : 8,
                      ),
                      child: _buildCurrentUserPanelContent(
                        context: context,
                        current: current,
                        clientManager: manager,
                        avatarRadius: avatarRadius,
                        height: height,
                      ),
                    )
                  : DesktopAccountPopupAnchor(
                      client: popupClient,
                      clientManager: state.clientManager,
                      activityService: localActivityService,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          Layout.mobile ? 10 : 8,
                          Layout.mobile ? 7 : 8,
                          Layout.mobile ? 6 : 8,
                          Layout.mobile ? 7 : 8,
                        ),
                        child: _buildCurrentUserPanelContent(
                          context: context,
                          current: current,
                          clientManager: manager,
                          avatarRadius: avatarRadius,
                          height: height,
                        ),
                      ),
                    ),
            ),
            Row(
              children: [
                if (!Layout.mobile)
                  Tooltip(
                    message: smallWindowMode
                        ? "Exit small-window mode"
                        : "Enter small-window mode",
                    child: SizedBox(
                      width: height,
                      height: height,
                      child: tiamat.IconButton(
                        icon: smallWindowMode
                            ? Icons.open_in_full_rounded
                            : Icons.close_fullscreen_rounded,
                        size: height / 4,
                        iconColor: smallWindowMode
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        onPressed: () {
                          preferences.desktopSmallWindowMode.set(
                            !smallWindowMode,
                          );
                        },
                      ),
                    ),
                  ),
                SizedBox(
                  width: height,
                  height: height,
                  child: tiamat.IconButton(
                    icon: Icons.settings,
                    size: height / 4,
                    onPressed: () {
                      SettingsNavigation.show(context, const AppSettingsPage());
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Client? _clientForProfile(Profile? profile, ClientManager manager) {
    if (manager.clients.isEmpty) {
      return null;
    }

    if (profile == null) {
      return manager.clients.first;
    }

    for (final client in manager.clients) {
      if (client.self?.identifier == profile.identifier) {
        return client;
      }
    }

    return manager.clients.first;
  }

  static Widget _buildCurrentUserPanelContent({
    required BuildContext context,
    required Profile? current,
    required ClientManager clientManager,
    required double avatarRadius,
    required double height,
  }) {
    return Row(
      spacing: 8,
      children: [
        if (current != null)
          tiamat.Avatar(
            key: _avatarKey('current-user', current),
            radius: avatarRadius,
            image: current.avatar,
            placeholderColor: current.defaultColor,
            placeholderText: current.displayName,
          ),
        if (current != null)
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.name(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  color: current.defaultColor,
                  current.displayName,
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Clipboard.setData(
                      ClipboardData(text: current.identifier),
                    ),
                    child: Opacity(
                      opacity: 0.7,
                      child: Text(
                        current.identifier,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFamily: "Code",
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (current == null)
          ...clientManager.clients
              .where((i) => i.self != null)
              .map(
                (i) => Padding(
                  padding: _currentUserListAvatarPadding,
                  // The sidebar footer only guarantees a minimum panel
                  // height, so this row can receive unbounded constraints on
                  // both axes; AspectRatio cannot size itself there and takes
                  // the whole desktop layout down. Size the avatar tiles
                  // explicitly from the panel height instead.
                  child: SizedBox.square(
                    dimension: math.max(
                      avatarRadius * 2,
                      height - _currentUserListAvatarPadding.vertical,
                    ),
                    child: tiamat.Avatar(
                      key: _avatarKey('current-user-list', i.self!),
                      radius: avatarRadius,
                      placeholderColor: i.self!.defaultColor,
                      placeholderText: i.self!.displayName,
                      image: i.self!.avatar,
                    ),
                  ),
                ),
              ),
      ],
    );
  }

  static ValueKey<int> _avatarKey(String prefix, Profile profile) {
    return ValueKey<int>(
      Object.hash(prefix, profile.identifier, profile.avatar),
    );
  }

  SizedBox spaceRoomSelector(
    BuildContext context,
    _DesktopSmallWindowLayout layout,
  ) {
    return SizedBox(
      width: layout.roomPickerWidth,
      child: Column(
        children: [
          SpaceHeader(
            state.currentSpace!,
            onTap: state.clearRoomSelection,
            height: layout.spaceHeaderHeight,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          Expanded(
            child: SpaceViewer(
              state.currentSpace!,
              key: ValueKey("space-view-key-${state.currentSpace!.localId}"),
              onRoomSelected: (room, {bool bypassSpecialRoomType = false}) {
                state.selectRoom(
                  room,
                  bypassSpecialRoomType: bypassSpecialRoomType,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget homeView(BuildContext context, _DesktopSmallWindowLayout layout) {
    return Row(
      children: [
        if (state.currentRoom == null)
          Expanded(
            child: Tile(
              caulkPadLeft: true,
              caulkClipTopLeft: true,
              caulkClipBottomLeft: true,
              caulkPadTop: true,
              caulkPadBottom: true,
              child: ScaledSafeArea(
                child: HomeScreen(
                  clientManager: state.clientManager,
                  filterClient: state.filterClient,
                ),
              ),
            ),
          ),
        if (state.currentRoom != null) roomChatView(context, layout),
      ],
    );
  }

  Widget favoritesView() {
    return Expanded(
      child: Tile(
        caulkPadTop: true,
        caulkPadBottom: true,
        caulkPadLeft: true,
        caulkClipTopLeft: true,
        caulkBorderLeft: true,
        caulkClipBottomLeft: true,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            FavoriteRoomsList(
              clientManager: state.clientManager,
              filterClient: state.filterClient,
              onRoomSelected: (room, {bool bypassSpecialRoomType = false}) {
                state.selectRoom(
                  room,
                  bypassSpecialRoomType: bypassSpecialRoomType,
                );
              },
              showHeader: true,
              header: favoritesListHeaderDesktop,
              emptyMessage: favoritesEmptyStateDesktop,
            ),
          ],
        ),
      ),
    );
  }

  List<RoomQuickAccessMenuEntry> _callRoomSideRailActions() {
    if (!state.isCurrentRoomCallRoom) {
      return const [];
    }

    final mode = state.callRoomSideRailMode;

    return [
      RoomQuickAccessMenuEntry(
        name: "Chat",
        semanticLabel: "Open room chat side rail",
        icon: mode == CallRoomSideRailMode.chat
            ? Icons.chat_bubble_rounded
            : Icons.chat_bubble_outline_rounded,
        selected: mode == CallRoomSideRailMode.chat,
        action: (_) => state.openCallRoomSideRail(CallRoomSideRailMode.chat),
      ),
      RoomQuickAccessMenuEntry(
        name: "Members",
        semanticLabel: "Open room members side rail",
        icon: mode == CallRoomSideRailMode.members
            ? Icons.people_alt_rounded
            : Icons.people_alt_outlined,
        selected: mode == CallRoomSideRailMode.members,
        action: (_) => state.openCallRoomSideRail(CallRoomSideRailMode.members),
      ),
    ];
  }

  Widget roomChatView(BuildContext context, _DesktopSmallWindowLayout layout) {
    final sidePanelInitialState = _initialRoomSidePanelState(state);
    final forceSidePanelVisible =
        state.forceRoomSidePanelVisible || state.forceCallRoomSideRailVisible;

    return Expanded(
      key: ValueKey("room-chat-view-${state.currentRoom!.localId}"),
      child: Column(
        children: [
          Tile.low(
            caulkPadBottom: true,
            caulkPadLeft: true,
            caulkClipBottomLeft: true,
            caulkBorderLeft: true,
            caulkBorderBottom: true,
            child: ScaledSafeArea(
              top: true,
              bottom: false,
              child: SizedBox(
                height: layout.roomHeaderHeight,
                child: RoomHeader(
                  state.currentRoom!,
                  compact: layout.compact,
                  onTap: state.currentRoom?.permissions.canEditAnything == true
                      ? () => state.navigateRoomSettings()
                      : null,
                  menu: RoomQuickAccessMenuViewDesktop(
                    room: state.currentRoom!,
                    actionsAfterInvite: _callRoomSideRailActions(),
                    onTogglePanel: (_) => state.toggleRoomSidePanelFromHeader(),
                    forceSidePanelVisible: forceSidePanelVisible,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Flex(
                  direction: Axis.horizontal,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: Tile(
                        caulkPadLeft: true,
                        caulkClipTopLeft: true,
                        caulkClipTopRight: true,
                        caulkBorderRight: true,
                        caulkPadBottom: true,
                        caulkClipBottomLeft: true,
                        caulkClipBottomRight: true,
                        caulkBorderLeft: true,
                        child: RoomPrimaryView(
                          state.currentRoom!,
                          bypassSpecialRoomTypes: state.showAsTextRoom,
                          forceCallControlsVisible:
                              state.forceCallControlsVisible,
                        ),
                      ),
                    ),
                    if (!layout.hoverRoomSidePanel)
                      RoomSidePanel(
                        key: ValueKey(
                          "room-sidepanel-key-${state.currentRoom!.localId}",
                        ),
                        state: state,
                        compact: layout.compact,
                        hideDefaultPanel: forceSidePanelVisible
                            ? false
                            : layout.collapseDefaultRoomSidePanel,
                        initialState: sidePanelInitialState,
                        initialThreadId: state.initialSidePanelThreadId,
                        forceNicknamesButton:
                            state.initialSidePanelState == 'defaultView',
                        forceDecryptQuickAction:
                            state.forceRoomDecryptQuickAction,
                        builder: (state, child) {
                          if (state == SidePanelState.nothing) {
                            return TutorialAnchor(
                              id: TutorialAnchorIds.roomSidePanel,
                              child: child,
                            );
                          }

                          Widget result = Tile.surfaceContainer(
                            caulkPadLeft: true,
                            caulkPadBottom: true,
                            caulkClipBottomLeft: true,
                            caulkClipTopLeft: true,
                            child: child,
                          );

                          result = TutorialAnchor(
                            id: TutorialAnchorIds.roomSidePanel,
                            child: result,
                          );

                          if (state == SidePanelState.thread ||
                              state == SidePanelState.calendar) {
                            result = Flexible(child: result);
                          }

                          return result;
                        },
                      ),
                  ],
                ),
                if (layout.hoverRoomSidePanel)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: _HoverRevealPanel(
                      side: _HoverPanelSide.right,
                      width: layout.roomSidePanelOverlayWidth,
                      icon: Icons.people_alt_rounded,
                      tooltip: "Room members",
                      forceExpanded: forceSidePanelVisible,
                      child: TutorialAnchor(
                        id: TutorialAnchorIds.roomSidePanel,
                        child: SizedBox(
                          width: layout.roomSidePanelOverlayWidth,
                          child: RoomSidePanel(
                            key: ValueKey(
                              "room-sidepanel-key-${state.currentRoom!.localId}",
                            ),
                            state: state,
                            compact: layout.compact,
                            hideDefaultPanel: false,
                            respectHiddenPreference: false,
                            initialState: sidePanelInitialState,
                            initialThreadId: state.initialSidePanelThreadId,
                            forceNicknamesButton:
                                state.initialSidePanelState == 'defaultView',
                            forceDecryptQuickAction:
                                state.forceRoomDecryptQuickAction,
                            builder: (state, child) {
                              if (state == SidePanelState.nothing) {
                                return child;
                              }

                              return Tile.surfaceContainer(
                                caulkPadLeft: true,
                                caulkPadBottom: true,
                                caulkClipBottomLeft: true,
                                caulkClipTopLeft: true,
                                child: child,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildRoomPicker(
    BuildContext context,
    _DesktopSmallWindowLayout layout,
  ) {
    final headerPadding = layout.compact
        ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
        : const EdgeInsets.all(8.0);

    if (state.currentView == MainPageSubView.home) {
      return ScaledSafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: headerPadding,
                  child: tiamat.Text.labelLow(directMessagesListHeaderDesktop),
                ),
                Padding(
                  padding: headerPadding,
                  child: tiamat.IconButton(
                    icon: Icons.add,
                    onPressed: () {
                      state.searchUserToDm();
                    },
                  ),
                ),
              ],
            ),
            Flexible(
              child: DirectMessageList(
                filterClient: state.filterClient,
                directMessages: state.clientManager.directMessages,
                onSelected: (room) => state.selectRoom(room),
              ),
            ),
          ],
        ),
      );
    } else if (state.currentView == MainPageSubView.favorites) {
      return ScaledSafeArea(
        top: true,
        bottom: false,
        child: FavoriteRoomsList(
          clientManager: state.clientManager,
          filterClient: state.filterClient,
          onRoomSelected: (room, {bool bypassSpecialRoomType = false}) {
            state.selectRoom(
              room,
              bypassSpecialRoomType: bypassSpecialRoomType,
            );
          },
          showHeader: true,
          header: favoritesListHeaderDesktop,
          emptyMessage: favoritesEmptyStateDesktop,
        ),
      );
    } else {
      return spaceRoomSelector(context, layout);
    }
  }

  Widget mainView(BuildContext context, _DesktopSmallWindowLayout layout) {
    if (state.currentView == MainPageSubView.home)
      return Flexible(child: homeView(context, layout));
    if (state.currentView == MainPageSubView.favorites &&
        state.currentRoom == null) {
      return favoritesView();
    }
    if (state.currentRoom != null && state.currentView != MainPageSubView.home)
      return roomChatView(context, layout);
    if (state.currentSpace != null && state.currentRoom == null)
      return Expanded(
        child: Tile(
          caulkPadTop: true,
          caulkPadBottom: true,
          caulkPadLeft: true,
          caulkClipTopLeft: true,
          caulkBorderLeft: true,
          caulkClipBottomLeft: true,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SpaceSummary(
                key: ValueKey(
                  "space-summary-key-${state.currentSpace!.localId}",
                ),
                space: state.currentSpace!,
                onRoomTap: (room) => state.selectRoom(room),
                onSpaceTap: (space) => state.selectSpace(space),
                onLeaveRoom: state.clearRoomSelection,
              ),
            ],
          ),
        ),
      );

    return Placeholder();
  }
}

class _CompactUserRailPanel extends StatefulWidget {
  const _CompactUserRailPanel({
    required this.state,
    required this.current,
    required this.client,
    required this.activityService,
    required this.height,
    required this.avatarRadius,
    required this.smallWindowMode,
  });

  final MainPageState state;
  final Profile? current;
  final Client? client;
  final ActivityService activityService;
  final double height;
  final double avatarRadius;
  final bool smallWindowMode;

  @override
  State<_CompactUserRailPanel> createState() => _CompactUserRailPanelState();
}

class _CompactUserRailPanelState extends State<_CompactUserRailPanel> {
  final LayerLink _activityLayerLink = LayerLink();
  OverlayEntry? _activityOverlay;

  @override
  void dispose() {
    _hideActivityPopover();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: widget.height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: CompositedTransformTarget(
                link: _activityLayerLink,
                child: Tooltip(
                  message: "Account",
                  child: InkResponse(
                    radius: 22,
                    onTap: _toggleActivityPopover,
                    child: widget.current != null
                        ? tiamat.Avatar(
                            radius: widget.avatarRadius,
                            image: widget.current!.avatar,
                            placeholderColor: widget.current!.defaultColor,
                            placeholderText: widget.current!.displayName,
                          )
                        : Icon(
                            Icons.account_circle,
                            size: widget.avatarRadius * 2,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: widget.smallWindowMode
                  ? "Exit small-window mode"
                  : "Enter small-window mode",
              child: SizedBox(
                width: 38,
                height: 38,
                child: tiamat.IconButton(
                  icon: widget.smallWindowMode
                      ? Icons.open_in_full_rounded
                      : Icons.close_fullscreen_rounded,
                  size: 15,
                  iconColor: widget.smallWindowMode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  onPressed: () {
                    preferences.desktopSmallWindowMode.set(
                      !widget.smallWindowMode,
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              width: 38,
              height: 38,
              child: tiamat.IconButton(
                icon: Icons.settings,
                size: 15,
                onPressed: () {
                  SettingsNavigation.show(context, const AppSettingsPage());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleActivityPopover() {
    if (_activityOverlay != null) {
      _hideActivityPopover();
      return;
    }

    if (widget.client == null) {
      return;
    }

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (overlayContext) {
        return _CompactActivityOverlay(
          link: _activityLayerLink,
          client: widget.client!,
          clientManager: widget.state.clientManager,
          activityService: widget.activityService,
          navigationContext: context,
          onDismiss: _hideActivityPopover,
        );
      },
    );
    _activityOverlay = entry;
    overlay.insert(entry);
  }

  void _hideActivityPopover() {
    _activityOverlay?.remove();
    _activityOverlay = null;
  }
}

class _CompactActivityOverlay extends StatelessWidget {
  const _CompactActivityOverlay({
    required this.link,
    required this.client,
    required this.clientManager,
    required this.activityService,
    required this.navigationContext,
    required this.onDismiss,
  });

  final LayerLink link;
  final Client client;
  final ClientManager clientManager;
  final ActivityService activityService;
  final BuildContext navigationContext;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.centerRight,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(10, 6),
          child: Material(
            color: Colors.transparent,
            child: AccountPopup(
              width: 304,
              client: client,
              clientManager: clientManager,
              activityService: activityService,
              navigationContext: navigationContext,
              onDismiss: onDismiss,
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopSmallWindowLayout {
  const _DesktopSmallWindowLayout({
    required this.enabled,
    required this.persistentRailLabels,
    required this.size,
  });

  final bool enabled;
  final bool persistentRailLabels;
  final Size size;

  bool get compact => enabled;

  bool get hoverRoomPicker => compact;

  bool get hoverRoomSidePanel => compact;

  double get sidebarWidth =>
      hoverRoomPicker ? navigationRailWidth : navigationRailWidth + 250;

  double get navigationRailWidth {
    if (!persistentRailLabels) {
      return navigationButtonSize;
    }

    return compact ? 132 : 156;
  }

  double get navigationButtonSize => compact ? 58 : 70;

  double get roomPickerWidth => compact ? 220 : 250;

  double get userPanelHeight => hoverRoomPicker ? 132 : (compact ? 44 : 55);

  double get userPanelAvatarRadius => compact ? 13 : 16;

  double get roomHeaderHeight => compact ? 34 : 50;

  double get spaceHeaderHeight => compact ? 64 : 100;

  double get roomSidePanelOverlayWidth => 280;

  bool get showAuxiliaryPanels => !compact;

  bool get collapseDefaultRoomSidePanel => compact && size.width < 1080;
}

enum _HoverPanelSide { left, right }

class _HoverRevealPanel extends StatefulWidget {
  const _HoverRevealPanel({
    required this.side,
    required this.width,
    required this.icon,
    required this.tooltip,
    required this.child,
    this.forceExpanded = false,
  });

  final _HoverPanelSide side;
  final double width;
  final IconData icon;
  final String tooltip;
  final Widget child;
  final bool forceExpanded;

  @override
  State<_HoverRevealPanel> createState() => _HoverRevealPanelState();
}

class _HoverRevealPanelState extends State<_HoverRevealPanel> {
  static const double _tabWidth = 28;
  bool _hovering = false;
  bool _focused = false;
  bool _pinned = false;

  bool get _expanded =>
      widget.forceExpanded || _hovering || _focused || _pinned;

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.width + _tabWidth;
    final duration = Durations.short3;
    final panelLeft = widget.side == _HoverPanelSide.left
        ? (_expanded ? _tabWidth : -widget.width)
        : null;
    final panelRight = widget.side == _HoverPanelSide.right
        ? (_expanded ? _tabWidth : -widget.width)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        width: _expanded ? totalWidth : _tabWidth,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                top: 0,
                bottom: 0,
                left: panelLeft,
                right: panelRight,
                width: widget.width,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  child: widget.child,
                ),
              ),
              Positioned(
                top: 96,
                left: widget.side == _HoverPanelSide.left ? 0 : null,
                right: widget.side == _HoverPanelSide.right ? 0 : null,
                child: Tooltip(
                  message: widget.tooltip,
                  child: Builder(
                    builder: (context) {
                      final radius = BorderRadius.horizontal(
                        left: Radius.circular(
                          widget.side == _HoverPanelSide.right ? 10 : 0,
                        ),
                        right: Radius.circular(
                          widget.side == _HoverPanelSide.left ? 10 : 0,
                        ),
                      );

                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          borderRadius: radius,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: radius,
                          child: InkWell(
                            borderRadius: radius,
                            focusColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.18),
                            onFocusChange: (hasFocus) =>
                                setState(() => _focused = hasFocus),
                            onTap: () => setState(() => _pinned = !_pinned),
                            child: SizedBox(
                              width: _tabWidth,
                              height: 72,
                              child: Icon(
                                widget.icon,
                                size: 18,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
