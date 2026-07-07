import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_generic.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:flutter/material.dart';

class TimelineEventViewSingle extends StatelessWidget {
  const TimelineEventViewSingle(
      {required this.room, required this.event, super.key});

  final TimelineEvent event;
  final Room room;

  @override
  Widget build(BuildContext context) {
    final type = TimelineViewEntryState.eventToDisplayType(event, room: room);
    if (type == TimelineEventWidgetDisplayType.message) {
      return TimelineEventViewMessage(
        room: room,
        overrideShowSender: true,
        initialIndex: 0,
        detailed: true,
        initialEvent: event,
        previewMedia: room.shouldPreviewMedia,
      );
    }
    if (type == TimelineEventWidgetDisplayType.generic) {
      return TimelineEventViewGeneric(
        initialIndex: 0,
        initialEvent: event,
        room: room,
      );
    }

    return Container();
  }
}
