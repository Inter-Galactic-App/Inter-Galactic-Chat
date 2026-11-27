import 'package:intergalactic/client/components/activity/activity_models.dart';

class ActivityRenderer {
  const ActivityRenderer();

  String compactTitle(UserActivity activity) {
    return switch (activity.kind) {
      ActivityKind.music => activity.status ?? 'Listening',
      ActivityKind.game => activity.status ?? 'Playing',
      ActivityKind.call => activity.status ?? 'In call',
      ActivityKind.screenShare => activity.status ?? 'Sharing',
      ActivityKind.custom => activity.status ?? 'Activity',
    };
  }

  String? compactSubtitle(UserActivity activity) {
    if (activity.subtitle != null && activity.subtitle!.trim().isNotEmpty) {
      return activity.subtitle;
    }

    return activity.details;
  }
}
