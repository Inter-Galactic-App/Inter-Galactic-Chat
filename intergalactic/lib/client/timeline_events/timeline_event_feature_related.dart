import 'package:intergalactic/client/timeline.dart';

abstract class TimelineEventFeatureRelated {
  EventRelationshipType? get relationshipType;

  String? get relatedEventId;
}
