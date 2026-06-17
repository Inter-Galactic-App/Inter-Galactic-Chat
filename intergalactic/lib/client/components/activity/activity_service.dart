import 'dart:async';

import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_publisher.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/activity/activity_source.dart';
import 'package:intergalactic/debug/log.dart';

typedef ActivitySettingsProvider = ActivitySettings Function();

class ActivityService {
  ActivityService({
    ActivitySettingsProvider? settingsProvider,
  }) : _settingsProvider = settingsProvider ?? (() => const ActivitySettings());

  final List<ActivitySource> _sources = [];
  final List<ActivityPublisher> _publishers = [];
  final List<StreamSubscription<UserActivity?>> _sourceSubscriptions = [];
  final StreamController<UserActivity?> _controller =
      StreamController.broadcast();

  ActivitySettingsProvider _settingsProvider;
  UserActivity? _selectedActivity;
  UserActivity? _localActivity;
  List<UserActivity> _localActivities = const [];
  String? _preferredActivityId;
  bool _started = false;
  bool _hasPendingPublish = false;
  bool _publishing = false;
  UserActivity? _pendingPublishActivity;
  Future<void>? _publishDrainFuture;
  String? _lastPublishDecisionLogKey;

  Stream<UserActivity?> get onActivityChanged => _controller.stream;
  ActivitySettings get settings => _settingsProvider();
  UserActivity? get selectedActivity => _selectedActivity;
  UserActivity? get currentActivity => _localActivity;
  List<UserActivity> get currentActivities =>
      List.unmodifiable(_localActivities);
  List<ActivitySource> get sources => List.unmodifiable(_sources);

  void configure({ActivitySettingsProvider? settingsProvider}) {
    if (settingsProvider != null) {
      _settingsProvider = settingsProvider;
    }

    refreshSettings();
  }

  void registerSource(ActivitySource source) {
    if (_sources.any((entry) => entry.id == source.id)) {
      return;
    }

    _sources.add(source);
    if (_started) {
      _listenToSource(source);
      unawaited(source.start());
      refreshSettings();
    }
  }

  void registerPublisher(ActivityPublisher publisher) {
    if (_publishers.any((entry) => entry.id == publisher.id)) {
      return;
    }

    _publishers.add(publisher);
  }

  Future<void> start() async {
    if (_started) {
      refreshSettings();
      return;
    }

    _started = true;
    for (final source in _sources) {
      _listenToSource(source);
      await source.start();
    }

    refreshSettings();
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }

    _started = false;
    for (final subscription in _sourceSubscriptions) {
      await subscription.cancel();
    }
    _sourceSubscriptions.clear();

    for (final source in _sources) {
      await source.stop();
    }

    _selectedActivity = null;
    _preferredActivityId = null;
    _emitLocalState(null, const []);
    try {
      await _requestPublish(null);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to clear activity presence while stopping',
      );
    }
  }

  Future<void> dispose() async {
    await stop();
    for (final source in _sources) {
      await source.dispose();
    }
    await _controller.close();
  }

  void refreshSettings() {
    final active = _activeActivities();
    final selected = _selectActivity(active);
    _selectedActivity = selected;
    _emitLocalState(
      _localFilter(selected),
      active.where(settings.allowsLocalActivity).toList(growable: false),
    );
    unawaited(_requestPublish(selected));
  }

  Future<void> executeControl(ActivityControl control) async {
    final activity = _selectedActivity;
    if (activity == null) {
      return;
    }

    await executeControlForActivity(activity, control);
  }

  Future<void> executeControlForActivity(
    UserActivity activity,
    ActivityControl control,
  ) async {
    if (!control.enabled) {
      return;
    }

    ActivitySource? source;
    for (final entry in _sources) {
      if (entry.id == activity.id) {
        source = entry;
        break;
      }
    }

    await source?.executeControl(control.id);
  }

  void selectNextLocalActivity() {
    if (_localActivities.length < 2) {
      return;
    }

    final current =
        _localActivity ?? _selectedActivity ?? _localActivities.first;
    final currentIndex =
        _localActivities.indexWhere((activity) => activity.id == current.id);
    final nextIndex =
        currentIndex == -1 ? 0 : (currentIndex + 1) % _localActivities.length;
    _preferredActivityId = _localActivities[nextIndex].id;
    refreshSettings();
  }

  void _listenToSource(ActivitySource source) {
    _sourceSubscriptions.add(
      source.onActivityChanged.listen((_) => refreshSettings()),
    );
  }

  List<UserActivity> _activeActivities() {
    final active = _sources
        .map((source) => source.currentActivity)
        .whereType<UserActivity>()
        .where((activity) => activity.isVisible)
        .toList(growable: false);

    active.sort((left, right) {
      final leftPriority = _priority(left.kind);
      final rightPriority = _priority(right.kind);
      if (leftPriority != rightPriority) {
        return rightPriority.compareTo(leftPriority);
      }

      final leftStart = left.startedAt;
      final rightStart = right.startedAt;
      if (leftStart == null && rightStart == null) return 0;
      if (leftStart == null) return 1;
      if (rightStart == null) return -1;
      return rightStart.compareTo(leftStart);
    });

    return active;
  }

  UserActivity? _selectActivity(List<UserActivity> active) {
    if (active.isEmpty) {
      _preferredActivityId = null;
      return null;
    }

    final preferredId = _preferredActivityId;
    if (preferredId != null) {
      for (final activity in active) {
        if (activity.id == preferredId) {
          return activity;
        }
      }

      _preferredActivityId = null;
    }

    return active.first;
  }

  UserActivity? _localFilter(UserActivity? activity) {
    if (activity == null) {
      return null;
    }

    if (!settings.allowsLocalActivity(activity)) {
      return null;
    }

    return activity;
  }

  void _emitLocalState(
    UserActivity? activity,
    List<UserActivity> activities,
  ) {
    if (_sameLocalState(activity, activities)) {
      return;
    }

    _localActivity = activity;
    _localActivities = activities;
    _controller.add(activity);
  }

  bool _sameLocalState(
    UserActivity? activity,
    List<UserActivity> activities,
  ) {
    if (!_sameLocalActivity(activity)) {
      return false;
    }

    if (_localActivities.length != activities.length) {
      return false;
    }

    for (var index = 0; index < activities.length; index++) {
      if (!_sameActivity(_localActivities[index], activities[index])) {
        return false;
      }
    }

    return true;
  }

  bool _sameLocalActivity(UserActivity? activity) {
    if (_localActivity == null || activity == null) {
      return _localActivity == activity;
    }

    return _sameActivity(_localActivity!, activity);
  }

  Future<void> _publish(UserActivity? activity) async {
    if (_publishers.isEmpty) {
      return;
    }

    final currentSettings = settings;
    final publishActivity =
        currentSettings.allowsPublishing(activity) ? activity : null;
    _logPublishDecision(activity, publishActivity, currentSettings);
    for (final publisher in _publishers) {
      await publisher.publish(publishActivity, currentSettings);
    }
  }

  void _logPublishDecision(
    UserActivity? selectedActivity,
    UserActivity? publishActivity,
    ActivitySettings settings,
  ) {
    final selectedKey = _activityLogKey(selectedActivity);
    final publishKey = _activityLogKey(publishActivity);
    final key = [
      selectedKey,
      publishKey,
      settings.publishBasicStatus,
      settings.publishRichActivity,
      settings.showSpotify,
      settings.showGameActivity,
      settings.hideCurrentActivity,
    ].join('|');

    if (_lastPublishDecisionLogKey == key) {
      return;
    }

    _lastPublishDecisionLogKey = key;
    Log.d(
      'Activity publish decision selected=$selectedKey publish=$publishKey '
      'publish_basic=${settings.publishBasicStatus} '
      'publish_rich=${settings.publishRichActivity} '
      'show_spotify=${settings.showSpotify} '
      'show_game=${settings.showGameActivity} '
      'hide_current=${settings.hideCurrentActivity}',
      category: LogCategory.app,
      source: 'activity-service',
    );
  }

  String _activityLogKey(UserActivity? activity) {
    if (activity == null) {
      return 'none';
    }

    final metadataState = activity.metadata['state']?.toString();
    final displayHash = Object.hash(
      activity.title,
      activity.subtitle,
      activity.details,
      activity.status,
      metadataState,
    ).toUnsigned(32).toRadixString(16);
    return '${activity.provider}:${activity.kind.name}:'
        'visible=${activity.isVisible}:id=${activity.id}:'
        'status=${activity.status ?? 'none'}:'
        'state=${metadataState ?? 'none'}:'
        'title_len=${activity.title.length}:'
        'subtitle_len=${activity.subtitle?.length ?? 0}:'
        'display_hash=$displayHash';
  }

  Future<void> _requestPublish(UserActivity? activity) {
    _pendingPublishActivity = activity;
    _hasPendingPublish = true;

    final existingDrain = _publishDrainFuture;
    if (existingDrain != null) {
      return existingDrain;
    }

    final drain = _drainPublishQueue();
    _publishDrainFuture = drain;
    return drain;
  }

  Future<void> _drainPublishQueue() async {
    if (_publishing) {
      return;
    }

    _publishing = true;
    try {
      while (_hasPendingPublish) {
        final activity = _pendingPublishActivity;
        _pendingPublishActivity = null;
        _hasPendingPublish = false;

        try {
          await _publish(activity);
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to publish activity presence',
          );
        }
      }
    } finally {
      _publishing = false;
      _publishDrainFuture = null;

      if (_hasPendingPublish) {
        unawaited(_requestPublish(_pendingPublishActivity));
      }
    }
  }

  int _priority(ActivityKind kind) {
    return switch (kind) {
      ActivityKind.call => 50,
      ActivityKind.screenShare => 45,
      ActivityKind.game => 40,
      ActivityKind.music => 30,
      ActivityKind.custom => 10,
    };
  }
}

bool _sameControls(List<ActivityControl> left, List<ActivityControl> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    final leftControl = left[index];
    final rightControl = right[index];
    if (leftControl.id != rightControl.id ||
        leftControl.kind != rightControl.kind ||
        leftControl.label != rightControl.label ||
        leftControl.state != rightControl.state ||
        leftControl.tooltip != rightControl.tooltip) {
      return false;
    }
  }

  return true;
}

bool _sameActivity(UserActivity left, UserActivity right) {
  return left.id == right.id &&
      left.title == right.title &&
      left.subtitle == right.subtitle &&
      left.details == right.details &&
      left.status == right.status &&
      left.artworkUrl == right.artworkUrl &&
      left.externalUrl == right.externalUrl &&
      left.visibility == right.visibility &&
      _sameControls(left.controls, right.controls);
}
