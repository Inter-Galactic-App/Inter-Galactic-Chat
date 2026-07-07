import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/atoms/floating_tile.dart';
import 'package:intergalactic/ui/organisms/background_task_view/background_task_view.dart';
import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';

void main() {
  testWidgets(
    'floating tile keeps background task overlay stable during mouse hover',
    (tester) async {
      final manager = BackgroundTaskManager();
      final task = _TestBackgroundTask(
        label: 'Uploading crash diagnostics',
        canCallAction: true,
      );
      task.action = () {};
      manager.addTask(task);
      addTearDown(() {
        if (!task.disposed) {
          manager.removeTask(task);
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingTile(child: BackgroundTaskView(manager)),
          ),
        ),
      );

      await tester.pump();
      await tester.sendEventToBinding(
        const PointerHoverEvent(position: Offset(790, 16)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(tester.takeException(), isNull);
      expect(find.text('Uploading crash diagnostics'), findsOneWidget);
    },
  );
}

class _TestBackgroundTask implements BackgroundTask {
  _TestBackgroundTask({required this.label, this.canCallAction = false});

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
  final bool canCallAction;

  @override
  void Function()? action;

  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    _statusController.close();
  }
}
