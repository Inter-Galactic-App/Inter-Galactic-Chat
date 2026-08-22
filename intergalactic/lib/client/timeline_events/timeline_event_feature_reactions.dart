import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/timeline.dart';

abstract class TimelineEventFeatureReactions {
  bool hasReactions(Timeline timeline);

  Map<Emoticon, Set<String>> getReactions(Timeline timeline);
}
