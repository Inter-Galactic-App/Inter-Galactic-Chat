import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';

abstract class MessageEffectComponent<T extends Client>
    implements Component<T> {
  void doEffect(TimelineEvent event);

  bool hasEffect(TimelineEvent event);
}
