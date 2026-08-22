import 'dart:async';

import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/floating_tile.dart';
import 'package:intergalactic/ui/organisms/background_task_view/background_task_view.dart';
import 'package:intergalactic/utils/download_utils.dart';
import 'package:flutter/material.dart';

class BackgroundTaskViewContainer extends StatefulWidget {
  const BackgroundTaskViewContainer({super.key});

  @override
  State<BackgroundTaskViewContainer> createState() =>
      _BackgroundTaskViewContainerState();
}

class _BackgroundTaskViewContainerState
    extends State<BackgroundTaskViewContainer> {
  StreamSubscription? sub;

  @override
  void initState() {
    sub = backgroundTaskManager.onListUpdate.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFloatingTask = backgroundTaskManager.tasks.any(
      (task) => task is! DownloadFileTask,
    );
    if (!hasFloatingTask) {
      return Container();
    }

    return FloatingTile(child: BackgroundTaskView(backgroundTaskManager));
  }
}
