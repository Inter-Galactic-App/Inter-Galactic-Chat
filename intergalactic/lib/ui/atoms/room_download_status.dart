import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';
import 'package:intergalactic/utils/download_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomDownloadStatus extends StatefulWidget {
  const RoomDownloadStatus({required this.room, super.key});

  final Room room;

  @override
  State<RoomDownloadStatus> createState() => _RoomDownloadStatusState();
}

class _RoomDownloadStatusState extends State<RoomDownloadStatus> {
  StreamSubscription? _taskListSubscription;
  final List<StreamSubscription> _taskSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _taskListSubscription = backgroundTaskManager.onListUpdate.listen(
      (_) => _rebindTaskListeners(),
    );
    _rebindTaskListeners();
  }

  @override
  void didUpdateWidget(covariant RoomDownloadStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent that reuses this State for a different room leaves the
    // subscriptions watching the old room's tasks, so the status text keeps
    // reporting a download that belongs somewhere else.
    if (oldWidget.room != widget.room) {
      _rebindTaskListeners();
    }
  }

  @override
  void dispose() {
    _taskListSubscription?.cancel();
    for (final subscription in _taskSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _rebindTaskListeners() {
    for (final subscription in _taskSubscriptions) {
      subscription.cancel();
    }
    _taskSubscriptions
      ..clear()
      ..addAll(
        _roomTasks.map(
          (task) => task.statusChanged.listen((_) {
            if (mounted) {
              setState(() {});
            }
          }),
        ),
      );
    if (mounted) {
      setState(() {});
    }
  }

  Iterable<DownloadFileTask> get _roomTasks => backgroundTaskManager.tasks
      .whereType<DownloadFileTask>()
      .where((task) => task.room == widget.room);

  @override
  Widget build(BuildContext context) {
    final tasks = _roomTasks.toList();
    final task = tasks.isEmpty ? null : tasks.last;
    if (task == null) {
      return const SizedBox.shrink();
    }

    final label = switch (task.status) {
      BackgroundTaskStatus.running => "Saving '${task.filename}'…",
      BackgroundTaskStatus.completed => "Saved '${task.filename}'",
      BackgroundTaskStatus.failed => "Could not save '${task.filename}'",
    };

    return Flexible(
      child: Semantics(
        liveRegion: true,
        label: label,
        child: tiamat.Text.labelLow(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
