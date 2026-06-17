import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/background_task_view/background_task_view.dart';
import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';

void main() {
  testWidgets('background task rows shrink-wrap in unconstrained overlays',
      (tester) async {
    final manager = BackgroundTaskManager();
    final task = _TestBackgroundTask(
      label: 'Syncing notifications after hot reload',
    );
    manager.addTask(task);
    addTearDown(() {
      if (!task.disposed) {
        manager.removeTask(task);
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnconstrainedBox(
            child: BackgroundTaskView(manager),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Syncing notifications after hot reload'), findsOneWidget);
  });
}

class _TestBackgroundTask implements BackgroundTask {
  _TestBackgroundTask({required this.label});

  final StreamController<void> _statusController = StreamController.broadcast();

  @override
  final String label;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  @override
  Stream<void> get statusChanged => _statusController.stream;

  @override
  bool shouldRemoveTask = false;

  @override
  bool get canCallAction => false;

  @override
  void Function()? action;

  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    _statusController.close();
  }
}
