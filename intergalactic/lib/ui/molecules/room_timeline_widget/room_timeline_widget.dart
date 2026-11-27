import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:flutter/material.dart';

class RoomTimelineWidget extends StatefulWidget {
  const RoomTimelineWidget({
    required this.timeline,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.isThreadTimeline = false,
    this.clearNotifications,
    this.bottomInset = 0,
    this.keyboardVisible = false,
    this.autoLoadTimelineBoundaries = true,
    this.showTimelineBoundaryLoadingIndicators = true,
    this.onHistoryPageLoaded,
    super.key,
  });
  final Timeline timeline;
  final Function(TimelineEvent? event)? setReplyingEvent;
  final Function(TimelineEvent? event)? setEditingEvent;
  final Function(Room room)? clearNotifications;
  final Future<bool> Function(Timeline timeline)? onHistoryPageLoaded;
  final bool isThreadTimeline;
  final double bottomInset;
  final bool keyboardVisible;
  final bool autoLoadTimelineBoundaries;
  final bool showTimelineBoundaryLoadingIndicators;

  @override
  State<RoomTimelineWidget> createState() => _RoomTimelineWidgetState();
}

class _RoomTimelineWidgetState extends State<RoomTimelineWidget>
    with WidgetsBindingObserver {
  GlobalKey timelineViewKey = GlobalKey();

  StreamSubscription? sub;

  @override
  void initState() {
    sub = widget.timeline.onEventAdded.stream.listen(onEventReceived);
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void onEventReceived(int index) {
    if (index == 0) {
      var state = timelineViewKey.currentState as RoomTimelineWidgetViewState?;
      if (state?.attachedToBottom == true) {
        markAsRead(widget.timeline.events[index]);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      var state = timelineViewKey.currentState as RoomTimelineWidgetViewState?;
      if (state?.attachedToBottom == true) {
        markAsRead(widget.timeline.events.first);
        widget.clearNotifications?.call(widget.timeline.room);
      }
    }

    super.didChangeAppLifecycleState(state);
  }

  Future<void> markAsRead(TimelineEvent event) async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    widget.timeline.markAsRead(event);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = RoomTimelineWidgetView(
      key: timelineViewKey,
      timeline: widget.timeline,
      onAttachedToBottom: onAttachedToBottom,
      isThreadTimeline: widget.isThreadTimeline,
      setReplyingEvent: widget.setReplyingEvent,
      setEditingEvent: widget.setEditingEvent,
      bottomInset: widget.bottomInset,
      keyboardVisible: widget.keyboardVisible,
      autoLoadTimelineBoundaries: widget.autoLoadTimelineBoundaries,
      showTimelineBoundaryLoadingIndicators:
          widget.showTimelineBoundaryLoadingIndicators,
      onHistoryPageLoaded: widget.onHistoryPageLoaded,
      markAsRead: markAsRead,
    );

    if (Layout.desktop) {
      result = SelectionArea(
        child: result,
        contextMenuBuilder: (context, selectableRegionState) {
          return Container();
        },
      );
    }

    return result;
  }

  void onAttachedToBottom() {
    if (widget.timeline.events.isNotEmpty) {
      markAsRead(widget.timeline.events.first);
      widget.clearNotifications?.call(widget.timeline.room);
    }
  }
}
