import 'dart:async';

import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_publisher.dart';
import 'package:intergalactic/client/components/activity/activity_room_component.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/debug/log.dart';

typedef ActivityRoomTargetProvider = List<ActivityRoomComponent> Function();

/// Publishes the local user's rich activity into the rooms of any active calls,
/// as a `space.ourgalaxy.activity` state event, so remote participants can
/// render it on their call tiles.
///
/// This is the structured, rate-limit-immune counterpart to the presence
/// publisher, and it is gated on the `publishRichActivity` setting. Presence
/// text remains the human-readable fallback for non-Inter-Galactic clients.
class MatrixActivityRoomPublisher implements ActivityPublisher {
  MatrixActivityRoomPublisher({
    required ActivityRoomTargetProvider targetProvider,
  }) : _targetProvider = targetProvider;

  /// Enumerates the activity component of every room the user is currently in a
  /// call in. Only VoIP rooms carry the component, which naturally scopes the
  /// broadcast to calls rather than fanning out to every shared room.
  factory MatrixActivityRoomPublisher.forClientManager(
    ClientManager? Function() clientManagerProvider,
  ) {
    return MatrixActivityRoomPublisher(
      targetProvider: () {
        final manager = clientManagerProvider();
        if (manager == null) {
          return const [];
        }

        final components = <ActivityRoomComponent>[];
        for (final session in manager.callManager.currentSessions) {
          if (session.state.isFinishing) {
            continue;
          }

          final room = session.client.getRoom(session.roomId);
          final component = room?.getComponent<ActivityRoomComponent>();
          if (component != null) {
            components.add(component);
          }
        }

        return components;
      },
    );
  }

  final ActivityRoomTargetProvider _targetProvider;
  final Set<ActivityRoomComponent> _ownedTargets =
      Set<ActivityRoomComponent>.identity();
  Future<void> _publishChain = Future<void>.value();

  @override
  String get id => 'matrix_activity_room';

  @override
  Future<void> publish(UserActivity? activity, ActivitySettings settings) {
    _publishChain = _publishChain
        .catchError((_) {})
        .then((_) => _publishInternal(activity, settings));
    return _publishChain;
  }

  Future<void> _publishInternal(
    UserActivity? activity,
    ActivitySettings settings,
  ) async {
    final richActivity =
        settings.publishRichActivity && settings.allowsPublishing(activity)
        ? activity
        : null;

    // Enumerating targets walks live call sessions and room components, so a
    // torn-down session can make it throw synchronously. Treat that the way
    // _safePublish treats a failed publish -- log and skip -- because this
    // future is returned to callers that do not always await it, and an
    // unguarded throw would surface as an unhandled exception rather than a
    // skipped publish.
    final List<ActivityRoomComponent> targets;
    try {
      targets = _targetProvider();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to enumerate Matrix activity room publish targets',
        category: LogCategory.matrix,
        source: 'activity-room',
      );
      return;
    }

    final activeTargets = Set<ActivityRoomComponent>.identity()
      ..addAll(targets);

    // Clear rooms we previously published into but that are no longer active
    // (e.g. the call ended), so a stale activity does not linger there.
    for (final stale in _ownedTargets.difference(activeTargets).toList()) {
      await _safePublish(stale, null);
      _ownedTargets.remove(stale);
    }

    for (final target in targets) {
      await _safePublish(target, richActivity);
      if (richActivity != null) {
        _ownedTargets.add(target);
      } else {
        _ownedTargets.remove(target);
      }
    }
  }

  Future<void> _safePublish(
    ActivityRoomComponent target,
    UserActivity? activity,
  ) async {
    try {
      await target.publishSelfActivity(activity);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to publish Matrix activity room state',
        category: LogCategory.matrix,
        source: 'activity-room',
      );
    }
  }
}
