import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/gif/gif_search_result.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';

abstract class GifComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  Future<List<GifSearchResult>> search(String query);

  Future<TimelineEvent?> sendGif(
    GifSearchResult gif,
    TimelineEvent? inReplyTo, {
    String? threadRootEventId,
    String? threadLastEventId,
  });

  String get searchPlaceholder;
}
