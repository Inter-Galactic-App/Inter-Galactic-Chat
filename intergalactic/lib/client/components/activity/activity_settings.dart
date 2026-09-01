import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/preferences.dart';

class ActivitySettings {
  const ActivitySettings({
    this.showLocally = false,
    this.showLocalMediaControls = false,
    this.publishBasicStatus = false,
    this.publishRichActivity = false,
    this.showSpotify = false,
    this.showGameActivity = false,
    this.hideCurrentActivity = false,
    this.enableMockActivity = false,
  });

  final bool showLocally;
  final bool showLocalMediaControls;
  final bool publishBasicStatus;
  final bool publishRichActivity;
  final bool showSpotify;
  final bool showGameActivity;
  final bool hideCurrentActivity;
  final bool enableMockActivity;

  static ActivitySettings fromPreferences(Preferences preferences) {
    return ActivitySettings(
      showLocally: preferences.activityShowLocally.value,
      showLocalMediaControls: preferences.activityShowLocalMediaControls.value,
      publishBasicStatus: preferences.activityPublishBasicStatus.value,
      publishRichActivity: preferences.activityPublishRich.value,
      showSpotify: preferences.activityShowSpotify.value,
      showGameActivity: preferences.activityShowGame.value,
      hideCurrentActivity: preferences.activityHideCurrent.value,
      enableMockActivity: preferences.activityMockSourceEnabled.value,
    );
  }

  bool allowsLocalActivity(UserActivity activity) {
    if (hideCurrentActivity || !activity.isVisible) {
      return false;
    }

    if (activity.provider == 'local_media') {
      return showLocalMediaControls;
    }

    if (activity.provider == 'spotify') {
      return showSpotify &&
          (showLocally || BuildConfig.IOS || BuildConfig.ANDROID);
    }

    if (!showLocally) {
      return false;
    }

    if (activity.kind == ActivityKind.game && !showGameActivity) {
      return false;
    }

    return true;
  }

  bool allowsPublishing(UserActivity? activity) {
    if (activity == null || hideCurrentActivity || !activity.isVisible) {
      return false;
    }

    if (activity.provider == 'spotify' && !showSpotify) {
      return false;
    }

    if (activity.kind == ActivityKind.game && !showGameActivity) {
      return false;
    }

    return publishBasicStatus || publishRichActivity;
  }
}
