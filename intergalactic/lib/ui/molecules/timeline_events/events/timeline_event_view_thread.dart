import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/ui/atoms/thread_reply_footer.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';

class TimelineEventViewThread extends StatefulWidget {
  const TimelineEventViewThread(
      {super.key,
      required this.initialIndex,
      required this.timeline,
      required this.component,
      this.alignRight = false});

  final int initialIndex;
  final Timeline timeline;
  final ThreadsComponent component;
  final bool alignRight;

  @override
  State<TimelineEventViewThread> createState() =>
      _TimelineEventViewThreadState();
}

class _TimelineEventViewThreadState extends State<TimelineEventViewThread> {
  String? senderName;
  String? body;
  ImageProvider? senderAvatar;
  Color? senderColor;

  late String threadEventId;

  @override
  void initState() {
    getStateFromIndex(widget.initialIndex);
    super.initState();
  }

  void getStateFromIndex(int index) {
    var event = widget.timeline.events[index];
    threadEventId = event.eventId;
    var threadEvent =
        widget.component.getFirstReplyToThread(event, widget.timeline);
    if (threadEvent == null) {
      return;
    }

    var sender = widget.timeline.room.getMemberOrFallback(threadEvent.senderId);

    if (threadEvent is TimelineEventMessage) {
      body = threadEvent.body;
    } else if (threadEvent is TimelineEventSticker) {
      body = threadEvent.stickerName;
    }

    senderName = sender.displayName;
    senderAvatar = sender.avatar;
    senderColor = sender.defaultColor;
  }

  @override
  Widget build(BuildContext context) {
    return ThreadReplyFooter(
      body: body ?? "",
      senderName: senderName ?? "Unknown Sender",
      senderAvatar: senderAvatar,
      senderColor: senderColor,
      alignRight: widget.alignRight,
      onTap: () {
        EventBus.openThread.add((
          widget.timeline.client.identifier,
          widget.timeline.room.identifier,
          threadEventId
        ));
        OverlappingPanels.of(context)?.reveal(RevealSide.right);
      },
    );
  }
}
