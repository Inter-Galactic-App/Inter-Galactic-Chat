import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/local_media/local_media_controls_bridge.dart';
import 'package:intergalactic/debug/log.dart';

class LocalMediaActivitySource implements MusicActivitySource {
  LocalMediaActivitySource({
    LocalMediaControlsBridge? bridge,
    Duration pollInterval = const Duration(seconds: 5),
    bool Function()? enabled,
  })  : _bridge = bridge ?? LocalMediaControlsBridge(),
        _pollInterval = pollInterval,
        _enabled = enabled ?? (() => true);

  final LocalMediaControlsBridge _bridge;
  final Duration _pollInterval;
  final bool Function() _enabled;
  final StreamController<UserActivity?> _controller =
      StreamController.broadcast();

  Timer? _timer;
  UserActivity? _activity;
  bool _running = false;
  bool _disposed = false;
  bool _polling = false;
  bool _authorizationRequested = false;
  int _generation = 0;

  @override
  String get id => 'local_media';

  @override
  ActivityKind get kind => ActivityKind.music;

  @override
  UserActivity? get currentActivity => _running ? _activity : null;

  @override
  Stream<UserActivity?> get onActivityChanged => _controller.stream;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('Cannot restart a disposed LocalMediaActivitySource');
    }

    _running = true;
    _generation++;
    final generation = _generation;
    await refresh();
    if (!_running || _disposed || !_isCurrentGeneration(generation)) {
      return;
    }
    _timer ??= Timer.periodic(_pollInterval, (_) {
      unawaited(refresh());
    });
  }

  @override
  Future<void> stop() async {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _activity = null;
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
    _generation++;
    await _controller.close();
  }

  @override
  Future<void> executeControl(String controlId) async {
    if (!_running || _disposed || !_enabled()) {
      return;
    }

    final action = switch (controlId) {
      'previous' => LocalMediaControlAction.skipPrevious,
      'play_pause' => LocalMediaControlAction.togglePlayPause,
      'next' => LocalMediaControlAction.skipNext,
      _ => null,
    };

    if (action == null) {
      return;
    }

    final executed = await _executeBridgeAction(action);
    if (executed) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await refresh();
    }
  }

  Future<void> refresh() async {
    final generation = _generation;
    if (!_running || _disposed || _polling) {
      return;
    }

    if (!_enabled()) {
      _setActivity(null);
      return;
    }

    _polling = true;
    try {
      await _requestAuthorizationIfNeeded(generation);
      if (!_isCurrentGeneration(generation)) {
        return;
      }

      final LocalMediaPlaybackSnapshot snapshot;
      try {
        snapshot = await _bridge.getSnapshot();
      } on MissingPluginException catch (e, s) {
        _logBridgeError("Failed to read local media playback state", e, s);
        return;
      } on PlatformException catch (e, s) {
        _logBridgeError("Failed to read local media playback state", e, s);
        return;
      } on Exception catch (e, s) {
        _logBridgeError("Failed to read local media playback state", e, s);
        return;
      }

      if (!_isCurrentGeneration(generation)) {
        return;
      }

      _setActivity(_activityFromSnapshot(snapshot));
    } finally {
      _polling = false;
    }
  }

  Future<void> _requestAuthorizationIfNeeded(int generation) async {
    if (_authorizationRequested || !_isCurrentGeneration(generation)) {
      return;
    }

    _authorizationRequested = true;
    await _bridge.requestAuthorization();
  }

  Future<bool> _executeBridgeAction(LocalMediaControlAction action) async {
    try {
      return await _bridge.execute(action);
    } on MissingPluginException catch (e, s) {
      _logBridgeError("Failed to execute local media control", e, s);
      return false;
    } on PlatformException catch (e, s) {
      _logBridgeError("Failed to execute local media control", e, s);
      return false;
    } on Exception catch (e, s) {
      _logBridgeError("Failed to execute local media control", e, s);
      return false;
    }
  }

  void notifySettingsChanged() {
    if (!_running || _controller.isClosed) {
      return;
    }

    unawaited(refresh());
  }

  UserActivity? _activityFromSnapshot(LocalMediaPlaybackSnapshot snapshot) {
    if (!snapshot.hasPlayableItem) {
      return null;
    }

    final playing = snapshot.state == LocalMediaPlaybackState.playing;
    final title = snapshot.title ?? 'Device music';
    final artist = snapshot.artist ?? 'Device media player';

    return UserActivity(
      id: id,
      kind: ActivityKind.music,
      provider: 'local_media',
      title: title,
      subtitle: artist,
      details: snapshot.album,
      status: playing ? 'Listening' : 'Paused',
      artworkUrl: snapshot.artworkUrl,
      visibility: ActivityVisibility.selfOnly,
      metadata: {
        'state': playing ? 'playing' : 'paused',
        if (snapshot.authorizationStatus != null)
          'authorization_status': snapshot.authorizationStatus,
        if (snapshot.durationMs != null) 'duration_ms': snapshot.durationMs,
      },
      controls: _controls(playing: playing),
    );
  }

  List<ActivityControl> _controls({required bool playing}) {
    return [
      const ActivityControl(
        id: 'previous',
        kind: ActivityControlKind.previous,
        label: 'Previous',
        state: ActivityControlState.available,
      ),
      ActivityControl(
        id: 'play_pause',
        kind: ActivityControlKind.playPause,
        label: playing ? 'Pause' : 'Play',
        state: ActivityControlState.available,
        metadata: {'action': playing ? 'pause' : 'play'},
      ),
      const ActivityControl(
        id: 'next',
        kind: ActivityControlKind.next,
        label: 'Next',
        state: ActivityControlState.available,
      ),
    ];
  }

  void _setActivity(UserActivity? activity) {
    if (!_isValidState() || _sameActivity(activity)) {
      return;
    }

    _activity = activity;
    _controller.add(currentActivity);
  }

  bool _isCurrentGeneration(int generation) {
    return _isValidState() && generation == _generation;
  }

  bool _isValidState() {
    return _running && !_disposed && !_controller.isClosed;
  }

  void _logBridgeError(String message, Object error, StackTrace stackTrace) {
    Log.w(message);
    Log.onError(error, stackTrace);
  }

  bool _sameActivity(UserActivity? activity) {
    if (_activity == null || activity == null) {
      return _activity == activity;
    }

    return _activity!.title == activity.title &&
        _activity!.subtitle == activity.subtitle &&
        _activity!.status == activity.status &&
        _activity!.details == activity.details &&
        _activity!.artworkUrl == activity.artworkUrl &&
        mapEquals(_activity!.metadata, activity.metadata) &&
        _sameControls(_activity!.controls, activity.controls);
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
        leftControl.tooltip != rightControl.tooltip ||
        !mapEquals(leftControl.metadata, rightControl.metadata)) {
      return false;
    }
  }

  return true;
}
