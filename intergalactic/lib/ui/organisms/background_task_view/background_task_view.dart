import 'dart:async';
import 'dart:math' as math;

import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';
import 'package:intergalactic/utils/download_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const double _maxFloatingTaskWidth = 320;
const double _minFloatingTaskWidth = 180;

class BackgroundTaskView extends StatefulWidget {
  const BackgroundTaskView(this.manager, {super.key});
  final BackgroundTaskManager manager;

  @override
  State<BackgroundTaskView> createState() => _BackgroundTaskViewState();
}

class _BackgroundTaskViewState extends State<BackgroundTaskView> {
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = widget.manager.onListUpdate.listen(onTaskListUpdated);
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final safeHorizontalPadding = mediaQuery?.padding.horizontal ?? 0;
    final availableWidth = math.max(
      0.0,
      (mediaQuery?.size.width ?? _maxFloatingTaskWidth) -
          safeHorizontalPadding -
          20,
    );
    // Never force the panel wider than the space that actually exists
    // (split-screen, folded, or otherwise very narrow displays).
    final width = math
        .min(
          availableWidth,
          availableWidth.clamp(_minFloatingTaskWidth, _maxFloatingTaskWidth),
        )
        .toDouble();

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(blurRadius: 4, color: Theme.of(context).shadowColor),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.manager.tasks
                    .where((task) => task is! DownloadFileTask)
                    .map(
                      (e) => _SingleBackgroundTaskView(
                        e,
                        key: ValueKey("task-display${e.hashCode}"),
                        onDismiss: () => widget.manager.removeTask(e),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void onTaskListUpdated(event) {
    if (!mounted) {
      return;
    }

    setState(() {});
  }
}

class _SingleBackgroundTaskView extends StatefulWidget {
  const _SingleBackgroundTaskView(this.task, {super.key, this.onDismiss});
  final BackgroundTask task;
  final VoidCallback? onDismiss;

  @override
  State<_SingleBackgroundTaskView> createState() =>
      __SingleBackgroundTaskViewState();
}

class __SingleBackgroundTaskViewState extends State<_SingleBackgroundTaskView> {
  StreamSubscription? progressSubscription;
  StreamSubscription? completeSubscription;
  double? progress;
  late BackgroundTaskStatus status;

  @override
  void initState() {
    status = widget.task.status;
    completeSubscription = widget.task.statusChanged.listen((event) {
      onTaskComplete();
    });
    if (widget.task is BackgroundTaskWithIntegerProgress) {
      var progressTask = (widget.task as BackgroundTaskWithIntegerProgress);
      progressSubscription = progressTask.onProgress.listen(onTaskProgressed);

      progress = progressTask.current / progressTask.total;
    }

    if (widget.task is BackgroundTaskWithOptionalProgress) {
      var task = (widget.task as BackgroundTaskWithOptionalProgress);
      progress = task.progress;
      progressSubscription = task.statusChanged.listen(onOptionalProgress);
    }
    super.initState();
  }

  @override
  void dispose() {
    progressSubscription?.cancel();
    completeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = tiamat.Text.tiny(
      widget.task.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final content = Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
            child: SizedBox(
              width: 10,
              height: 10,
              child: status == BackgroundTaskStatus.completed
                  ? const Icon(Icons.check, color: Colors.greenAccent, size: 10)
                  : status == BackgroundTaskStatus.failed
                  ? Icon(
                      Icons.error,
                      color: Theme.of(context).colorScheme.error,
                      size: 10,
                    )
                  : CircularProgressIndicator(strokeWidth: 2, value: progress),
            ),
          ),
          Expanded(child: label),
          if (status == BackgroundTaskStatus.failed && widget.onDismiss != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: widget.task.canCallAction
          ? InkWell(onTap: widget.task.action, child: content)
          : content,
    );
  }

  void onTaskComplete() {
    if (!mounted) {
      return;
    }

    setState(() {
      status = widget.task.status;
    });
  }

  void onTaskProgressed(int event) {
    if (!mounted) {
      return;
    }

    setState(() {
      progress =
          event / (widget.task as BackgroundTaskWithIntegerProgress).total;
    });
  }

  void onOptionalProgress(void event) {
    if (!mounted) {
      return;
    }

    setState(() {
      progress = (widget.task as BackgroundTaskWithOptionalProgress).progress;
    });
  }
}
