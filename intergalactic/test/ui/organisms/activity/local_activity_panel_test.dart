import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/activity/activity_source.dart';
import 'package:intergalactic/ui/organisms/activity/local_activity_panel.dart';

void main() {
  testWidgets('renders local music activity with disabled controls',
      (tester) async {
    final source = _FakeActivitySource(id: 'demo', kind: ActivityKind.music)
      ..setActivity(
        const UserActivity(
          id: 'demo',
          kind: ActivityKind.music,
          provider: 'demo',
          title: 'Inter Galactic Theme',
          subtitle: 'Demo Source',
          status: 'Listening',
          visibility: ActivityVisibility.selfOnly,
          controls: [
            ActivityControl(
              id: 'play_pause',
              kind: ActivityControlKind.playPause,
              label: 'Play/Pause',
              state: ActivityControlState.disabled,
            ),
          ],
        ),
      );
    final service = ActivityService(
      settingsProvider: () => const ActivitySettings(showLocally: true),
    )..registerSource(source);
    await service.start();

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: LocalActivityPanel(
            service: service,
            userPanelHeight: 40,
            onHideActivity: () {},
            child: const Text('Current User'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('local-activity-card')), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Inter Galactic Theme'), findsOneWidget);
    expect(find.text('Demo Source'), findsOneWidget);
    expect(find.text('Current User'), findsOneWidget);
  });

  testWidgets('does not render activity card when local visibility is off',
      (tester) async {
    final source = _FakeActivitySource(id: 'demo', kind: ActivityKind.music)
      ..setActivity(
        const UserActivity(
          id: 'demo',
          kind: ActivityKind.music,
          title: 'Hidden Song',
          visibility: ActivityVisibility.selfOnly,
        ),
      );
    final service = ActivityService()..registerSource(source);
    await service.start();

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: LocalActivityPanel(
            service: service,
            userPanelHeight: 40,
            onHideActivity: () {},
            child: const Text('Current User'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('local-activity-card')), findsNothing);
    expect(find.text('Hidden Song'), findsNothing);
    expect(find.text('Current User'), findsOneWidget);
  });
}

class _FakeActivitySource implements ActivitySource {
  _FakeActivitySource({required this.id, required this.kind});

  final StreamController<UserActivity?> _controller =
      StreamController.broadcast();

  @override
  final String id;

  @override
  final ActivityKind kind;

  @override
  UserActivity? currentActivity;

  @override
  Stream<UserActivity?> get onActivityChanged => _controller.stream;

  void setActivity(UserActivity? activity) {
    currentActivity = activity;
    _controller.add(activity);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Future<void> executeControl(String controlId) async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
