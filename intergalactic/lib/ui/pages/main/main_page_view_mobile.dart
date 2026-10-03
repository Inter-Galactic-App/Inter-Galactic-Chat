import 'dart:async';

import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/atoms/room_header.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/atoms/space_header.dart';
import 'package:intergalactic/ui/molecules/direct_message_list.dart';
import 'package:intergalactic/ui/molecules/favorite_rooms_list.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:intergalactic/ui/molecules/space_viewer.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/activity/local_activity_panel.dart';
import 'package:intergalactic/ui/organisms/background_task_view/background_task_view_container.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_screen.dart';
import 'package:intergalactic/ui/organisms/room_members_list/room_members_list.dart';
import 'package:intergalactic/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:intergalactic/ui/organisms/sidebar_call_icon/sidebar_calls_list.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_soundboard_panel.dart';
import 'package:intergalactic/ui/organisms/space_summary/space_summary.dart';
import 'package:intergalactic/ui/pages/main/main_page.dart';
import 'package:intergalactic/ui/pages/main/main_page_view_desktop.dart';
import 'package:intergalactic/ui/pages/main/room_primary_view.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/scaled_app.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/foundation.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:flutter/material.dart' as material;

@visibleForTesting
bool debugShouldRevealMainWhenRightPanelUnavailable({
  required RevealSide? currentSide,
  required bool hasCurrentRoom,
}) {
  return currentSide == RevealSide.right && !hasCurrentRoom;
}

@visibleForTesting
bool debugShouldDismissForcedCallRoomRailOnMobileSideChange({
  required RevealSide side,
  required bool forcedOpen,
}) {
  return forcedOpen && side != RevealSide.right;
}

class MainPageViewMobile extends StatefulWidget {
  const MainPageViewMobile(this.state, {super.key});
  final MainPageState state;

  @override
  State<MainPageViewMobile> createState() => _MainPageViewMobileState();
}

class _MainPageViewMobileState extends State<MainPageViewMobile> {
  late GlobalKey<OverlappingPanelsState> panelsKey;
  bool shouldMainIgnoreInput = false;
  bool hasLocalActivity = activityService.currentActivity != null;
  double height = -1;
  StreamSubscription<UserActivity?>? localActivitySubscription;
  StreamSubscription? _openThreadSubscription;
  StreamSubscription? _closeThreadSubscription;
  StreamSubscription? _focusTimelineSubscription;
  Timer? _threadRevealTimer;

  String get directMessagesListHeaderMobile => Intl.message(
    "Direct Messages",
    desc: "The header for the direct messages list on desktop",
    name: "directMessagesListHeaderMobile",
  );

  String get favoritesListHeaderMobile => Intl.message(
    "Favorites",
    desc: "The header for the favorites room list on mobile",
    name: "favoritesListHeaderMobile",
  );

  String get favoritesEmptyStateMobile => Intl.message(
    "Star a room from the room list to keep it handy here.",
    desc: "Empty state for the mobile favorites view",
    name: "favoritesEmptyStateMobile",
  );

  GlobalKey mainPanelKey = GlobalKey();

  @override
  void initState() {
    panelsKey = GlobalKey<OverlappingPanelsState>();
    shouldMainIgnoreInput = widget.state.forceCallRoomSideRailVisible;
    _openThreadSubscription = EventBus.openThread.stream.listen((event) {
      revealThreadPanel();
    });
    _closeThreadSubscription = EventBus.closeThread.stream.listen((event) {
      panelsKey.currentState?.reveal(RevealSide.main);
    });

    _focusTimelineSubscription = EventBus.focusTimeline.stream.listen((event) {
      panelsKey.currentState?.reveal(RevealSide.main);
    });

    localActivitySubscription = activityService.onActivityChanged.listen((
      event,
    ) {
      if (!mounted) return;
      setState(() {
        hasLocalActivity = event != null;
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    _threadRevealTimer?.cancel();
    localActivitySubscription?.cancel();
    _openThreadSubscription?.cancel();
    _closeThreadSubscription?.cancel();
    _focusTimelineSubscription?.cancel();
    super.dispose();
  }

  void revealThreadPanel() {
    _threadRevealTimer?.cancel();
    panelsKey.currentState?.reveal(RevealSide.right);

    _threadRevealTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (panelsKey.currentState?.currentSide != RevealSide.right) return;
      panelsKey.currentState?.reveal(RevealSide.right);
    });
  }

  bool canPop() {
    switch (panelsKey.currentState?.currentSide) {
      case RevealSide.right:
        return false;
      case RevealSide.main:
        return false;
      case RevealSide.left:
        return true;
      case null:
        //idk in what case this will ever happen...
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    _queueForcedCallRoomRailReveal();
    _queueMainRevealWhenRightPanelUnavailable();
    return PopScope(
      canPop: canPop(),
      onPopInvokedWithResult: (didPop, result) {
        var event = ScopePopped();
        event.currentMobileSide = panelsKey.currentState?.currentSide;

        EventBus.onPopInvoked.add(event);

        if (event.handled) {
          return;
        }

        if (widget.state.currentView == MainPageSubView.home &&
            widget.state.currentRoom != null) {
          if (widget.state.currentRoom != null) {
            var dm = widget.state.currentRoom!.client
                .getComponent<DirectMessagesComponent>();
            if (dm?.isRoomDirectMessage(widget.state.currentRoom!) == true) {
              panelsKey.currentState?.reveal(RevealSide.left);
              return;
            }
          }

          widget.state.selectHome();

          return;
        }

        switch (panelsKey.currentState?.currentSide) {
          case RevealSide.right:
            panelsKey.currentState?.reveal(RevealSide.main);
          case RevealSide.main:
            panelsKey.currentState?.reveal(RevealSide.left);
          default:
            break;
        }
      },
      child: Foundation(
        child: OverlappingPanels(
          key: panelsKey,
          initialSide: widget.state.forceCallRoomSideRailVisible
              ? RevealSide.right
              : widget.state.initialMobileRevealSide ?? RevealSide.main,
          onSideChange: (side) {
            if (side != RevealSide.main) {
              FocusManager.instance.primaryFocus?.unfocus();
            }

            // Checked for EVERY side, not only `main`. The helper's own rule is
            // `forcedOpen && side != RevealSide.right`, so it is written to fire
            // for `left` too - but as an `else if` on the `main` branch it could
            // never be reached with `left`, and swiping to the navigation pane
            // left the forced-open state set. The helper and its call site
            // disagreed, and the helper is the one with the intent in it.
            if (debugShouldDismissForcedCallRoomRailOnMobileSideChange(
              side: side,
              forcedOpen: widget.state.forceCallRoomSideRailVisible,
            )) {
              // A user-dismissed call-room rail must not be re-opened by the
              // one-shot forced-open reveal scheduled during build.
              widget.state.dismissCallRoomSideRail();
            }

            setState(() {
              shouldMainIgnoreInput = side != RevealSide.main;
            });
          },
          left: navigation(context),
          main: Foundation(
            child: IgnorePointer(
              ignoring: shouldMainIgnoreInput,
              child: Container(key: mainPanelKey, child: mainPanel()),
            ),
          ),
          right: rightPanel(context),
        ),
      ),
    );
  }

  void _queueForcedCallRoomRailReveal() {
    if (!widget.state.forceCallRoomSideRailVisible) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final panels = panelsKey.currentState;
      if (panels?.currentSide == RevealSide.right) {
        return;
      }

      panels?.reveal(RevealSide.right);
    });
  }

  void _queueMainRevealWhenRightPanelUnavailable() {
    if (!debugShouldRevealMainWhenRightPanelUnavailable(
      currentSide: panelsKey.currentState?.currentSide,
      hasCurrentRoom: widget.state.currentRoom != null,
    )) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final panels = panelsKey.currentState;
      if (!debugShouldRevealMainWhenRightPanelUnavailable(
        currentSide: panels?.currentSide,
        hasCurrentRoom: widget.state.currentRoom != null,
      )) {
        return;
      }

      panels?.reveal(RevealSide.main);
      if (shouldMainIgnoreInput) {
        setState(() {
          shouldMainIgnoreInput = false;
        });
      }
    });
  }

  Widget? rightPanel(BuildContext context) {
    if (widget.state.currentRoom != null) {
      return Tile(
        caulkPadLeft: true,
        caulkClipTopLeft: true,
        caulkClipBottomLeft: true,
        child: Column(
          children: [
            Tile.low(
              child: ScaledSafeArea(
                child: Container(),
                bottom: false,
                top: true,
                left: false,
                right: false,
              ),
            ),
            Expanded(
              child: TutorialAnchor(
                id: TutorialAnchorIds.roomSidePanel,
                child: RoomSidePanel(
                  key: ValueKey(
                    "room-side-panel-${widget.state.currentRoom!.localId}",
                  ),
                  state: widget.state,
                  initialState: _initialRoomSidePanelState(widget.state),
                  initialThreadId: widget.state.initialSidePanelThreadId,
                  forceNicknamesButton:
                      widget.state.initialSidePanelState == 'defaultView',
                  forceDecryptQuickAction:
                      widget.state.forceRoomDecryptQuickAction,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return null;
  }

  SidePanelState? _initialRoomSidePanelState(MainPageState state) {
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

  Widget navigation(BuildContext newContext) {
    final scheme = Theme.of(context).colorScheme;
    final sidePanelTopGap = mobileSidePanelTopGap(context);
    final bottomReserve = mobileNavigationBottomReserve(context);

    return Material(
      color: scheme.surfaceDim,
      child: DecoratedBox(
        decoration: mobileSpaceRailBackground(context),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Row(
                  children: [
                    _mobileNavigationRailBackdrop(context),
                    _mobileRoomPanelBackdrop(context, sidePanelTopGap),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              top: 6,
              bottom: bottomReserve,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(MobileVisuals.panelRadius),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: mobileSpaceRailGradient(context),
                      ),
                      child: Tile(
                        caulkPadRight: true,
                        caulkClipTopRight: true,
                        caulkBorderRight: true,
                        mode: TileType.surfaceDim,
                        child: ScaledSafeArea(
                          bottom: false,
                          top: true,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                            child: TutorialAnchor(
                              id: TutorialAnchorIds.spaceRail,
                              child: SideNavigationBar(
                                currentUser: widget.state.getCurrentUser(),
                                filterClient: widget.state.filterClient,
                                onSpaceSelected: (space) {
                                  widget.state.selectSpace(space);
                                },
                                clearSpaceSelection: () {
                                  widget.state.clearSpaceSelection();
                                },
                                onHomeSelected: () {
                                  widget.state.selectHome();
                                },
                                onFavoritesSelected: () {
                                  widget.state.selectFavorites();
                                },
                                favoritesSelected:
                                    widget.state.currentView ==
                                    MainPageSubView.favorites,
                                onDirectMessageSelected: (room) {
                                  widget.state.selectHome();
                                  widget.state.selectRoom(room);
                                  panelsKey.currentState?.reveal(
                                    RevealSide.main,
                                  );
                                },
                                extraEntryBuilders: [
                                  (width) {
                                    return SidebarCallsList(
                                      widget.state.clientManager.callManager,
                                      width,
                                    );
                                  },
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.state.currentView == MainPageSubView.home)
                    directMessagesView(),
                  if (widget.state.currentView == MainPageSubView.favorites)
                    favoritesNavigationView(),
                  if (widget.state.currentView == MainPageSubView.space &&
                      widget.state.currentSpace != null)
                    spaceRoomSelector(newContext),
                  const BackgroundTaskViewContainer(),
                ],
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 0,
              height: mobileUserPanelUnderfillHeight(context),
              child: DecoratedBox(
                decoration: mobileUserPanelUnderfillDecoration(context),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(30),
                ),
                child: tiamat.Tile.low(
                  caulkPadTop: true,
                  caulkClipTopRight: true,
                  caulkClipBottomRight: true,
                  caulkBorderTop: true,
                  caulkBorderRight: true,
                  child: ScaledSafeArea(
                    bottom: true,
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CallSoundboardPanel(
                          callManager: widget.state.clientManager.callManager,
                        ),
                        LocalActivityPanel(
                          userPanelHeight: 68,
                          service: widget.state.tutorialActivityService,
                          child: TutorialAnchor(
                            id: TutorialAnchorIds.accountPanel,
                            child: MainPageViewDesktop.currentUserPanel(
                              widget.state,
                              context,
                              height: 68,
                              avatarRadius: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileNavigationRailBackdrop(BuildContext context) {
    return SizedBox(
      width: 70,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(MobileVisuals.panelRadius),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: mobileSpaceRailGradient(context)),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  BoxDecoration mobileSpaceRailBackground(BuildContext context) {
    return BoxDecoration(gradient: mobileSpaceRailGradient(context));
  }

  LinearGradient mobileSpaceRailGradient(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (PlatformUtils.isIOS) {
      return LinearGradient(
        begin: const Alignment(-0.75, -1),
        end: const Alignment(0.52, 1),
        colors: [
          scheme.surfaceContainerHighest.withValues(alpha: 0.18),
          scheme.surfaceContainerLow.withValues(alpha: 0.24),
          scheme.surfaceDim,
        ],
        stops: const [0, 0.42, 1],
      );
    }

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        scheme.surfaceContainerHighest.withValues(alpha: 0.12),
        scheme.surfaceDim,
      ],
    );
  }

  Widget _mobileRoomPanelBackdrop(
    BuildContext context,
    double sidePanelTopGap,
  ) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, sidePanelTopGap, 0, 0),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(18),
          ),
          child: DecoratedBox(
            decoration: mobileRoomPanelBackdropDecoration(context),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  BoxDecoration mobileRoomPanelBackdropDecoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!PlatformUtils.isIOS) {
      return BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.96),
      );
    }

    return BoxDecoration(
      color: scheme.surfaceContainer.withValues(alpha: 0.9),
      gradient: LinearGradient(
        begin: const Alignment(-0.5, -1),
        end: const Alignment(0.78, 1),
        colors: [
          scheme.surfaceContainerHigh.withValues(alpha: 0.32),
          scheme.surfaceContainer.withValues(alpha: 0.86),
          scheme.surfaceContainerLow.withValues(alpha: 0.76),
        ],
        stops: const [0, 0.54, 1],
      ),
      border: Border(
        left: BorderSide(color: scheme.outline.withValues(alpha: 0.08)),
        top: BorderSide(color: scheme.outline.withValues(alpha: 0.055)),
      ),
    );
  }

  BoxDecoration mobileUserPanelUnderfillDecoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!PlatformUtils.isIOS) {
      return BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.96),
      );
    }

    return BoxDecoration(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.94),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          scheme.surfaceContainerLow.withValues(alpha: 0.92),
          scheme.surfaceDim.withValues(alpha: 0.98),
        ],
      ),
      border: Border(
        top: BorderSide(color: scheme.outline.withValues(alpha: 0.05)),
      ),
    );
  }

  double mobileNavigationBottomReserve(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).scale().padding.bottom;

    return bottomPadding + (hasLocalActivity ? 168 : 96);
  }

  double mobileUserPanelUnderfillHeight(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).scale().padding.bottom;
    return bottomPadding + 24;
  }

  double mobileSidePanelTopGap(BuildContext context) {
    final topGap = MediaQuery.of(context).scale().padding.top - 8;
    return topGap.clamp(32.0, 72.0).toDouble();
  }

  Widget mainPanel() {
    if (widget.state.currentSpace != null && widget.state.currentRoom == null) {
      return Tile(
        child: ScaledSafeArea(
          top: false,
          child: SingleChildScrollView(
            child: SpaceSummary(
              key: ValueKey(
                "space-summary-key-${widget.state.currentSpace!.localId}",
              ),
              space: widget.state.currentSpace!,
              onRoomTap: (room) {
                widget.state.selectRoom(room);
              },
              onSpaceTap: (space) => widget.state.selectSpace(space),
              onLeaveRoom: widget.state.clearRoomSelection,
            ),
          ),
        ),
      );
    }

    if (widget.state.currentRoom != null) {
      var scaledQuery = MediaQuery.of(context).scale();
      var offset = scaledQuery.viewInsets.bottom;
      if (offset == 0) {
        offset = scaledQuery.padding.bottom;
      }
      return Tile(
        key: ValueKey("room-chat-view-${widget.state.currentRoom!.localId}"),
        child: Column(
          children: [
            if (Layout.mobile)
              Tile.low(
                caulkClipBottomRight: true,
                caulkClipBottomLeft: true,
                caulkBorderBottom: true,
                child: ScaledSafeArea(
                  bottom: false,
                  left: false,
                  right: false,
                  child: SizedBox(
                    height: 58,
                    child: RoomHeader(
                      widget.state.currentRoom!,
                      onTap:
                          widget
                                  .state
                                  .currentRoom
                                  ?.permissions
                                  .canEditAnything ==
                              true
                          ? () => widget.state.navigateRoomSettings()
                          : null,
                      menu: Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: tiamat.IconButton(
                            icon: material.Icons.chevron_right,
                            onPressed: () {
                              panelsKey.currentState?.reveal(RevealSide.right);
                            },
                          ),
                        ),
                      ),
                      onBurgerMenuTap: () {
                        panelsKey.currentState?.reveal(RevealSide.left);
                      },
                    ),
                  ),
                ),
              ),
            Expanded(
              child: RoomPrimaryView(
                widget.state.currentRoom!,
                bypassSpecialRoomTypes: widget.state.showAsTextRoom,
                forceCallControlsVisible: widget.state.forceCallControlsVisible,
                inboundShareDraft: widget.state.draftFor(
                  widget.state.currentRoom!,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (widget.state.currentView == MainPageSubView.favorites) {
      return Tile(
        child: ScaledSafeArea(
          top: false,
          child: SingleChildScrollView(
            child: FavoriteRoomsList(
              clientManager: widget.state.clientManager,
              filterClient: widget.state.filterClient,
              onRoomSelected: (room, {bool bypassSpecialRoomType = false}) {
                selectRoom(room, bypassSpecialRoomType: bypassSpecialRoomType);
              },
              showHeader: true,
              layout: FavoriteRoomsListLayout.summary,
              header: favoritesListHeaderMobile,
              emptyMessage: favoritesEmptyStateMobile,
            ),
          ),
        ),
      );
    }

    return Tile(
      child: HomeScreen(
        clientManager: widget.state.clientManager,
        filterClient: widget.state.filterClient,
        onBurgerMenuTap: () {
          panelsKey.currentState?.reveal(RevealSide.left);
        },
      ),
    );
  }

  Widget userList() {
    if (widget.state.currentRoom != null) {
      return Tile.surfaceContainer(
        caulkPadLeft: true,
        caulkClipTopLeft: true,
        caulkClipBottomLeft: true,
        caulkBorderLeft: true,
        caulkBorderTop: true,
        caulkBorderBottom: true,
        child: ScaledSafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: RoomMembersListWidget(
              widget.state.currentRoom!,
              contextSpace: widget.state.currentSpace,
              key: ValueKey(
                "room-participant-list-key-${widget.state.currentRoom!.localId}",
              ),
            ),
          ),
        ),
      );
    }
    return const Placeholder();
  }

  Widget mobileSidePanel({required Widget child}) {
    return Flexible(
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, mobileSidePanelTopGap(context), 0, 0),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(18),
          ),
          child: child,
        ),
      ),
    );
  }

  TextStyle? mobilePanelHeadingStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleSmall?.copyWith(
      fontFamily: "NunitoSans",
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
    );
  }

  Widget directMessagesView() {
    return mobileSidePanel(
      child: TutorialAnchor(
        id: TutorialAnchorIds.roomList,
        child: Tile.surfaceContainer(
          caulkClipTopLeft: true,
          caulkPadRight: true,
          caulkClipTopRight: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 6, 0),
            child: ScaledSafeArea(
              top: false,
              bottom: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                        child: Text(
                          directMessagesListHeaderMobile,
                          style: mobilePanelHeadingStyle(context),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
                        child: tiamat.IconButton(
                          size: 18,
                          icon: Icons.add,
                          onPressed: widget.state.searchUserToDm,
                        ),
                      ),
                    ],
                  ),
                  Flexible(
                    child: DirectMessageList(
                      filterClient: widget.state.filterClient,
                      directMessages: widget.state.clientManager.directMessages,
                      onSelected: (room) {
                        setState(() {
                          selectRoom(room);
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget spaceRoomSelector(BuildContext newContext) {
    return mobileSidePanel(
      child: TutorialAnchor(
        id: TutorialAnchorIds.roomList,
        child: Tile.surfaceContainer(
          caulkClipTopLeft: true,
          caulkPadRight: true,
          caulkClipTopRight: true,
          child: Column(
            children: [
              SpaceHeader(
                widget.state.currentSpace!,
                backgroundColor: material.Theme.of(
                  context,
                ).colorScheme.surfaceContainerLow,
                onTap: clearSelectedRoom,
              ),
              Expanded(
                child: SpaceViewer(
                  widget.state.currentSpace!,
                  key: ValueKey(
                    "space-view-key-${widget.state.currentSpace!.localId}",
                  ),
                  onRoomSelected:
                      (room, {bypassSpecialRoomType = false}) async {
                        selectRoom(
                          room,
                          bypassSpecialRoomType: bypassSpecialRoomType,
                        );
                      },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget favoritesNavigationView() {
    return mobileSidePanel(
      child: TutorialAnchor(
        id: TutorialAnchorIds.roomList,
        child: Tile.surfaceContainer(
          caulkClipTopLeft: true,
          caulkPadRight: true,
          caulkClipTopRight: true,
          child: FavoriteRoomsList(
            clientManager: widget.state.clientManager,
            filterClient: widget.state.filterClient,
            onRoomSelected: (room, {bool bypassSpecialRoomType = false}) {
              selectRoom(room, bypassSpecialRoomType: bypassSpecialRoomType);
            },
            showHeader: true,
            layout: FavoriteRoomsListLayout.mobileSidebar,
            roomIndicatorTrailingInset: 14,
            header: favoritesListHeaderMobile,
            emptyMessage: favoritesEmptyStateMobile,
          ),
        ),
      ),
    );
  }

  void clearSelectedRoom() {
    Future.delayed(const Duration(milliseconds: 125)).then((value) {
      panelsKey.currentState!.reveal(RevealSide.main);
      setState(() {
        shouldMainIgnoreInput = false;
      });
    });
    widget.state.clearRoomSelection();
  }

  void selectRoom(Room room, {bypassSpecialRoomType = false}) {
    panelsKey.currentState!.reveal(RevealSide.main);
    setState(() {
      shouldMainIgnoreInput = false;
    });

    widget.state.selectRoom(room, bypassSpecialRoomType: bypassSpecialRoomType);
  }
}
