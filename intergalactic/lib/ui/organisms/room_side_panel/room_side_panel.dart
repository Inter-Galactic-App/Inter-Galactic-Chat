import 'dart:async';

import 'package:intergalactic/client/components/calendar_room/calendar_room_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/organisms/chat/chat.dart';
import 'package:intergalactic/ui/organisms/room_event_search/room_event_search_widget.dart';
import 'package:intergalactic/ui/organisms/room_members_list/room_members_list.dart';
import 'package:intergalactic/ui/organisms/photo_albums/photo_album_thread_header.dart';
import 'package:intergalactic/ui/organisms/room_pinned_messages/room_pinned_messages_widget.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu_desktop.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu_mobile.dart';
import 'package:intergalactic/ui/pages/main/main_page.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:commet_calendar_widget/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum SidePanelState {
  defaultView,
  chat,
  thread,
  search,
  pinnedMessages,
  calendar,
  nothing,
}

@visibleForTesting
bool debugShouldSuppressCallRoomSidePanelChatTimelineLoading({
  required SidePanelState sidePanelState,
  required bool isCallRoom,
}) {
  return isCallRoom && sidePanelState == SidePanelState.chat;
}

@visibleForTesting
({bool autoLoadTimelineBoundaries, bool showTimelineBoundaryLoadingIndicators})
debugCallRoomSidePanelChatTimelineBoundaryBehaviorForTesting({
  required SidePanelState sidePanelState,
  required bool isCallRoom,
}) {
  final suppressTimelineBoundaryLoading =
      debugShouldSuppressCallRoomSidePanelChatTimelineLoading(
        sidePanelState: sidePanelState,
        isCallRoom: isCallRoom,
      );

  return (
    autoLoadTimelineBoundaries: true,
    showTimelineBoundaryLoadingIndicators: !suppressTimelineBoundaryLoading,
  );
}

class RoomSidePanel extends StatefulWidget {
  const RoomSidePanel({
    required this.state,
    this.builder,
    this.compact = false,
    this.hideDefaultPanel = false,
    this.respectHiddenPreference = true,
    this.initialState,
    this.initialThreadId,
    this.forceNicknamesButton = false,
    this.forceDecryptQuickAction = false,
    super.key,
  });

  final MainPageState state;
  final bool compact;
  final bool hideDefaultPanel;

  /// Compact hover panels should still show members even when the persistent
  /// desktop side panel is hidden.
  final bool respectHiddenPreference;
  final SidePanelState? initialState;
  final String? initialThreadId;
  final bool forceNicknamesButton;
  final bool forceDecryptQuickAction;

  final Widget Function(SidePanelState state, Widget child)? builder;

  @override
  State<RoomSidePanel> createState() => _RoomSidePanelState();
}

class _RoomSidePanelState extends State<RoomSidePanel> {
  String? _currentThreadId;
  String? get currentThreadId => _currentThreadId;

  late SidePanelState state;

  late List<StreamSubscription> subs;

  String get closeThreadLabel => Intl.message(
    "Close thread",
    name: "closeThreadLabel",
    desc: "Tooltip and accessibility label for closing the thread panel",
  );

  @override
  void initState() {
    _applyInitialState();

    subs = [
      EventBus.openThread.stream.listen(onOpenThreadSignal),
      EventBus.closeThread.stream.listen(onCloseThreadSignal),
      EventBus.startSearch.stream.listen(onStartSearch),
      EventBus.openPinnedMessages.stream.listen(onShowPinnedMessages),
      EventBus.openCalendar.stream.listen(onShowCalendar),
      EventBus.toggleRoomSidePanel.stream.listen(onToggleSidePanel),
    ];
    super.initState();
  }

  @override
  void didUpdateWidget(covariant RoomSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialState != widget.initialState ||
        oldWidget.initialThreadId != widget.initialThreadId) {
      setState(_applyInitialState);
      return;
    }

    if (oldWidget.hideDefaultPanel == widget.hideDefaultPanel &&
        oldWidget.respectHiddenPreference == widget.respectHiddenPreference) {
      return;
    }

    if (_defaultPanelHidden && state == SidePanelState.defaultView) {
      setState(() {
        state = SidePanelState.nothing;
      });
    } else if (!widget.hideDefaultPanel &&
        state == SidePanelState.nothing &&
        !_hiddenByPreference) {
      setState(() {
        state = SidePanelState.defaultView;
      });
    }
  }

  void _applyInitialState() {
    _currentThreadId = widget.initialThreadId;
    state =
        widget.initialState ??
        (_defaultPanelHidden
            ? SidePanelState.nothing
            : SidePanelState.defaultView);
  }

  bool get _hiddenByPreference =>
      widget.respectHiddenPreference &&
      preferences.hideRoomSidePanel.value &&
      Layout.desktop;

  bool get _defaultPanelHidden =>
      _hiddenByPreference || widget.hideDefaultPanel;

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = buildPanelContent(context);

    result = Material(color: Colors.transparent, child: result);

    if (widget.builder != null) {
      result = widget.builder!.call(state, result);
    }

    // if (state == _SidePanelState.thread) {
    //   result = Flexible(child: result);
    // }

    return result;
  }

  Widget buildPanelContent(BuildContext context) {
    switch (state) {
      case SidePanelState.defaultView:
        return buildDefaultView();
      case SidePanelState.chat:
        return buildChat();
      case SidePanelState.thread:
        return buildThread();
      case SidePanelState.search:
        return buildSearch();
      case SidePanelState.pinnedMessages:
        return buildPinnedMessages();
      case SidePanelState.calendar:
        return buildCalendar();
      case SidePanelState.nothing:
        return SizedBox(width: 0);
    }
  }

  void onOpenThreadSignal((String, String, String) event) {
    var clientId = event.$1;
    var roomId = event.$2;
    var threadId = event.$3;

    final currentRoom = widget.state.currentRoom;
    final alreadyInRoom =
        currentRoom?.identifier == roomId &&
        currentRoom?.client.identifier == clientId;

    if (!alreadyInRoom) {
      EventBus.openRoom.add((roomId, clientId));
    }

    setState(() {
      _currentThreadId = threadId;
      state = SidePanelState.thread;
    });
  }

  void onCloseThreadSignal(void event) {
    setState(() {
      _currentThreadId = null;
      state = SidePanelState.defaultView;
    });
  }

  Widget buildDefaultView() {
    return Column(
      children: [
        if (Layout.mobile)
          RoomQuickAccessMenuViewMobile(
            room: widget.state.currentRoom!,
            key: ValueKey(
              "quick_access_menu_${widget.state.currentRoom!.localId}",
            ),
          ),
        if (!Layout.mobile && widget.forceDecryptQuickAction)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
            child: Align(
              alignment: Alignment.centerRight,
              child: RoomQuickAccessMenuViewDesktop(
                room: widget.state.currentRoom!,
                onlyActionName: "Retry Decrypt",
              ),
            ),
          ),
        Flexible(
          // Keep the trailing Nicknames button clear of the Android system
          // navigation bar (native rail). Bottom-only safe area is a no-op on
          // desktop where the inset is zero.
          child: ScaledSafeArea(
            top: false,
            left: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: RoomMembersListWidget(
                widget.state.currentRoom!,
                compact: widget.compact,
                contextSpace: widget.state.currentSpace,
                forceNicknamesButton: widget.forceNicknamesButton,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildChat() {
    final timelineBoundaryBehavior =
        debugCallRoomSidePanelChatTimelineBoundaryBehaviorForTesting(
          sidePanelState: state,
          isCallRoom: widget.state.isCurrentRoomCallRoom,
        );

    return SizedBox(
      width: Layout.desktop ? (widget.compact ? 280 : 340) : null,
      child: Chat(
        widget.state.currentRoom!,
        autoLoadTimelineBoundaries:
            timelineBoundaryBehavior.autoLoadTimelineBoundaries,
        showTimelineBoundaryLoadingIndicators:
            timelineBoundaryBehavior.showTimelineBoundaryLoadingIndicators,
        key: ValueKey(
          "room-sidepanel-chat-key-${widget.state.currentRoom!.localId}",
        ),
      ),
    );
  }

  Widget buildThread() {
    final photoAlbum = widget.state.currentRoom!.getComponent<PhotoAlbumRoom>();

    return Tile(
      caulkPadLeft: true,
      caulkClipTopLeft: true,
      caulkClipBottomLeft: true,
      caulkPadBottom: true,
      child: Column(
        children: [
          if (photoAlbum != null && currentThreadId != null)
            PhotoAlbumThreadHeader(
              component: photoAlbum,
              threadRootEventId: currentThreadId!,
            ),
          Flexible(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Chat(
                    widget.state.currentRoom!,
                    threadId: currentThreadId,
                    key: ValueKey(
                      "room-timeline-key-${widget.state.currentRoom!.localId}_thread_$currentThreadId",
                    ),
                  ),
                ),
                Positioned(
                  top: Layout.mobile ? 8 : 12,
                  right: Layout.mobile ? 8 : 12,
                  child: tiamat.CircleButton(
                    icon: Icons.close_rounded,
                    radius: 15,
                    minimumSize: 40,
                    semanticLabel: closeThreadLabel,
                    tooltip: closeThreadLabel,
                    onPressed: () => EventBus.closeThread.add(null),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSearch() {
    return SizedBox(
      width: Layout.desktop ? (widget.compact ? 240 : 300) : null,
      child: RoomEventSearchWidget(
        room: widget.state.currentRoom!,
        onEventClicked: (eventId) {
          EventBus.jumpToEvent.add(eventId);
          EventBus.focusTimeline.add(null);
        },
        close: () => setState(() {
          state = SidePanelState.defaultView;
        }),
      ),
    );
  }

  void onStartSearch(void event) {
    setState(() {
      if (state == SidePanelState.search) {
        state = SidePanelState.defaultView;
      } else {
        state = SidePanelState.search;
      }
    });
  }

  void onShowPinnedMessages(void event) {
    setState(() {
      if (state == SidePanelState.pinnedMessages) {
        state = SidePanelState.defaultView;
      } else {
        state = SidePanelState.pinnedMessages;
      }
    });
  }

  void onShowCalendar(void event) {
    setState(() {
      if (state == SidePanelState.calendar) {
        state = SidePanelState.defaultView;
      } else {
        state = SidePanelState.calendar;
      }
    });
  }

  Widget buildPinnedMessages() {
    return SizedBox(
      width: Layout.desktop ? (widget.compact ? 240 : 300) : null,
      child: Column(
        children: [
          if (Layout.mobile)
            RoomQuickAccessMenuViewMobile(
              room: widget.state.currentRoom!,
              key: ValueKey(
                "quick_access_menu_${widget.state.currentRoom!.localId}",
              ),
            ),
          Expanded(
            child: RoomPinnedMessagesWidget(
              room: widget.state.currentRoom!,
              onEventClicked: (eventId) {
                EventBus.jumpToEvent.add(eventId);
                EventBus.focusTimeline.add(null);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildCalendar() {
    var calendar = widget.state.currentRoom?.getComponent<CalendarRoom>();
    if (calendar?.hasCalendar != true) {
      return Placeholder();
    }

    var query = MediaQuery.of(context);

    return tiamat.Tile.low(
      child: Column(
        children: [
          if (Layout.mobile)
            RoomQuickAccessMenuViewMobile(
              room: widget.state.currentRoom!,
              key: ValueKey(
                "quick_access_menu_${widget.state.currentRoom!.localId}",
              ),
            ),
          if (Layout.mobile) Divider(height: 2),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                var newQuery = query.copyWith(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                );

                return Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: ScaledSafeArea(
                    top: false,
                    bottom: true,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: MediaQuery(
                        data: newQuery,
                        child: CalendarWidgetView(
                          calendar: calendar!.calendar!,
                          watermark: false,
                          useMobileLayout: Layout.mobile,
                          autoDisposeCalendar: false,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void onToggleSidePanel(void event) {
    preferences.hideRoomSidePanel.set(!preferences.hideRoomSidePanel.value);

    if (_hiddenByPreference) {
      setState(() {
        state = SidePanelState.nothing;
      });
    } else {
      setState(() {
        state = SidePanelState.defaultView;
      });
    }
  }
}
