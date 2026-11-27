import 'dart:async';

import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_source.dart';

class MockActivitySource implements ActivitySource {
  MockActivitySource({
    required this.id,
    required this.kind,
    required this.activityBuilder,
    required bool Function() enabled,
  }) : _enabled = enabled;

  factory MockActivitySource.music({required bool Function() enabled}) {
    return MockActivitySource(
      id: 'demo.music',
      kind: ActivityKind.music,
      enabled: enabled,
      activityBuilder: () => UserActivity(
        id: 'demo.music',
        kind: ActivityKind.music,
        provider: 'demo',
        title: 'Inter Galactic Theme',
        subtitle: 'Demo Source',
        status: 'Listening',
        details: 'Controls unavailable until Spotify is connected',
        startedAt: DateTime.now(),
        visibility: ActivityVisibility.selfOnly,
        controls: const [
          ActivityControl(
            id: 'previous',
            kind: ActivityControlKind.previous,
            label: 'Previous',
            state: ActivityControlState.disabled,
            tooltip: 'Spotify controls are not connected',
          ),
          ActivityControl(
            id: 'play_pause',
            kind: ActivityControlKind.playPause,
            label: 'Play/Pause',
            state: ActivityControlState.disabled,
            tooltip: 'Spotify controls are not connected',
          ),
          ActivityControl(
            id: 'next',
            kind: ActivityControlKind.next,
            label: 'Next',
            state: ActivityControlState.disabled,
            tooltip: 'Spotify controls are not connected',
          ),
        ],
      ),
    );
  }

  final UserActivity Function() activityBuilder;
  final bool Function() _enabled;
  final StreamController<UserActivity?> _controller =
      StreamController.broadcast();
  bool _running = false;

  @override
  final String id;

  @override
  final ActivityKind kind;

  @override
  UserActivity? get currentActivity =>
      _running && _enabled() ? activityBuilder() : null;

  @override
  Stream<UserActivity?> get onActivityChanged => _controller.stream;

  @override
  Future<void> start() async {
    _running = true;
    _controller.add(currentActivity);
  }

  @override
  Future<void> stop() async {
    _running = false;
    _controller.add(null);
  }

  @override
  Future<void> dispose() async {
    if (_controller.isClosed) {
      return;
    }

    await stop();
    await _controller.close();
  }

  @override
  Future<void> executeControl(String controlId) async {}

  void notifySettingsChanged() {
    if (!_running || _controller.isClosed) {
      return;
    }

    _controller.add(currentActivity);
  }
}
