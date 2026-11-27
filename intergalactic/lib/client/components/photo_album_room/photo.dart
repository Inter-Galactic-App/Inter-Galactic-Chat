import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/timeline.dart';

abstract class Photo {
  Attachment? get attachment;

  PhotoStackMetadata? get stack;

  bool get isThreadReply;

  int get threadReplyCount;

  TimelineEventStatus get status;

  String get id;

  double? get width;
  double? get height;
}
