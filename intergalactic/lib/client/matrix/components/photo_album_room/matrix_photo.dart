import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/components/photo_album_room/photo.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_event_extensions.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:intergalactic/client/timeline.dart';

class MatrixPhoto implements Photo {
  final MatrixTimelineEvent event;

  Attachment? get attachment =>
      (event as MatrixTimelineEventMessage).attachments?.firstOrNull;

  @override
  PhotoStackMetadata? get stack => PhotoStackMetadata.fromContent(
        event.event.content[PhotoStackMetadata.eventContentKey],
      );

  @override
  bool get isThreadReply {
    final relation = event.event.content['m.relates_to'];
    if (relation is! Map<String, dynamic>) {
      return false;
    }

    return relation['rel_type'] == 'm.thread';
  }

  @override
  int get threadReplyCount {
    final unsigned = event.event.unsigned;
    if (unsigned == null) {
      return 0;
    }

    final relations = unsigned['m.relations'];
    if (relations is! Map<String, dynamic>) {
      return 0;
    }

    final thread = relations['m.thread'];
    if (thread is! Map<String, dynamic>) {
      return 0;
    }

    final count = thread['count'];
    if (count is int) {
      return count;
    }

    if (count is num) {
      return count.toInt();
    }

    return 0;
  }

  MatrixPhoto(
    this.event,
  );

  @override
  double? get height =>
      (event as MatrixTimelineEventMessage).event.attachmentHeight;

  @override
  double? get width =>
      (event as MatrixTimelineEventMessage).event.attachmentWidth;

  @override
  TimelineEventStatus get status => event.status;

  @override
  String get id => event.eventId;
}
