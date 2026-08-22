import 'package:intergalactic/client/components/activity/activity_models.dart';

/// Custom Matrix room state event that carries a member's rich [UserActivity]
/// (game / music / etc.) so other Inter Galactic clients can render it on call
/// tiles and status surfaces.
///
/// Unlike the plain-text presence `status_msg` fallback, this state event is not
/// subject to synapse presence rate limits and keeps the activity as structured
/// data. Non-Inter-Galactic clients ignore the unknown state event, so the
/// human-readable presence status remains their graceful fallback.
const String activityRoomStateEventType = 'space.ourgalaxy.activity';

/// Schema version for [activityRoomStateEventType] content. Bump when the wire
/// shape changes so a client reading a newer (or older) event can reject
/// content it does not understand instead of mis-parsing it.
const int activityRoomStateSchemaVersion = 1;

/// Encodes [activity] into state-event content.
///
/// Returns an empty map when there is nothing to share (null or hidden
/// activity); writing empty content clears the sender's existing state event.
Map<String, Object?> encodeActivityRoomStateContent(UserActivity? activity) {
  if (activity == null || !activity.isVisible) {
    return const <String, Object?>{};
  }

  return {'v': activityRoomStateSchemaVersion, 'activity': activity.toJson()};
}

/// Decodes [content] from an [activityRoomStateEventType] state event.
///
/// Returns null for cleared (empty), version-mismatched, hidden, or malformed
/// content so callers uniformly treat those as "no shared activity".
UserActivity? decodeActivityRoomStateContent(Map<String, Object?>? content) {
  if (content == null || content.isEmpty) {
    return null;
  }

  final version = content['v'];
  if (version is! int || version != activityRoomStateSchemaVersion) {
    return null;
  }

  final activityJson = content['activity'];
  if (activityJson is! Map) {
    return null;
  }

  final activity = UserActivity.fromJson(
    activityJson.map((key, value) => MapEntry(key.toString(), value)),
  );

  if (!activity.isVisible || (activity.id.isEmpty && activity.title.isEmpty)) {
    return null;
  }

  return activity;
}
