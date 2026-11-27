import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_mixin_reactions.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_mixin_related.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:flutter/material.dart';

class MatrixTimelineEventSticker extends MatrixTimelineEvent
    with MatrixTimelineEventRelated, MatrixTimelineEventReactions
    implements TimelineEventSticker, TimelineEventAnimatedSticker {
  MatrixTimelineEventSticker(super.event, {required super.client}) {
    String? uri;
    final url = event.content['url'];
    if (url is String) {
      uri = url;
    } else {
      final file = event.content['file'];
      if (file is Map && file['url'] is String) {
        uri = file['url'] as String;
      }
    }
    // A remote m.sticker carrying neither key - or a non-string in one of them
    // - is malformed, and this constructor runs while the timeline is being
    // built. Throwing here took the whole timeline down for one bad event, so
    // an unresolvable sticker becomes an image that will not load instead.
    stickerImage = MatrixMxcImage(
      Uri.tryParse(uri ?? '') ?? Uri(),
      client.getMatrixClient(),
      matrixEvent: event,
    );

    stickerName = event.body;
  }

  @override
  late ImageProvider<Object> stickerImage;

  @override
  late String stickerName;

  @override
  bool get isAnimatedSticker =>
      timelineStickerIsAnimated(event.content, stickerName);

  @override
  String get plainTextBody => stickerName;
}
