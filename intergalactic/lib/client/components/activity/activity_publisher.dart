import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';

abstract class ActivityPublisher {
  String get id;
  Future<void> publish(UserActivity? activity, ActivitySettings settings);
}

class ActivityPresenceSummaryFormatter {
  const ActivityPresenceSummaryFormatter();

  String? format(UserActivity? activity, ActivitySettings settings) {
    if (activity == null) {
      return null;
    }

    if (!settings.publishBasicStatus || !settings.allowsPublishing(activity)) {
      return null;
    }

    return switch (activity.kind) {
      ActivityKind.music => _music(activity),
      ActivityKind.game => 'Playing ${activity.title}',
      ActivityKind.call => activity.status ?? 'In a call',
      ActivityKind.screenShare => activity.status ?? 'Sharing screen',
      ActivityKind.custom => activity.status ?? activity.title,
    };
  }

  String? _music(UserActivity activity) {
    if (activity.provider == 'spotify') {
      final state = activity.metadata['state'];
      if (state != 'playing' && state != 'paused') {
        return null;
      }
    }

    if (activity.title.trim().isEmpty) {
      return null;
    }

    final artist = activity.subtitle;
    if (artist == null || artist.trim().isEmpty) {
      return 'Listening to ${activity.title}';
    }

    return 'Listening to $artist - ${activity.title}';
  }
}
