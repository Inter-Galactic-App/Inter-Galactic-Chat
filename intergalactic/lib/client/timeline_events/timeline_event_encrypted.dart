import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';

abstract class TimelineEventEncrypted extends TimelineEvent {
  Future<TimelineEvent?> attemptDecrypt(Room room);
}
