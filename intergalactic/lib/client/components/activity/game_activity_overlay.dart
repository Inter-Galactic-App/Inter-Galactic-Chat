import 'package:intergalactic/client/components/activity/activity_models.dart';

UserActivity? gameActivityForOverlay(Iterable<UserActivity> activities) {
  for (final activity in activities) {
    if (isGameActivityRenderable(activity)) {
      return activity;
    }
  }

  return null;
}

bool isGameActivityRenderable(UserActivity? activity) {
  return activity != null &&
      activity.kind == ActivityKind.game &&
      activity.isVisible &&
      activity.title.trim().isNotEmpty;
}

String gameActivityTitle(UserActivity activity) {
  return activity.title.trim();
}

// Escaped non-rendering suffix keeps Matrix status text human-readable while
// giving Inter Galactic clients a marker that free-form statuses will not set.
const String _gameActivityPresenceMarker =
    '\u2063\u200B\u200C\u2060\u200D\u2063';

String? formatGameActivityPresenceSummary(String title) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  return 'Playing $trimmed$_gameActivityPresenceMarker';
}

String? gameActivityTitleFromPresenceText(String? statusText) {
  final trimmed = statusText?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final markerStart = trimmed.lastIndexOf(_gameActivityPresenceMarker);
  if (markerStart < 0 ||
      markerStart + _gameActivityPresenceMarker.length != trimmed.length) {
    return null;
  }

  final summary = trimmed.substring(0, markerStart).trim();
  if (!summary.toLowerCase().startsWith('playing ')) {
    return null;
  }

  final title = summary.substring('playing'.length).trim();
  return title.isEmpty ? null : title;
}
