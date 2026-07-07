import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DragDropFileTarget extends StatefulWidget {
  const DragDropFileTarget({super.key, this.onDropComplete, this.child});
  final Function(DropDoneDetails details)? onDropComplete;
  final Widget? child;
  @override
  State<DragDropFileTarget> createState() => _DragDropFileTargetState();
}

class _DragDropFileTargetState extends State<DragDropFileTarget> {
  bool isFileHovered = false;

  String get fileDragDropPrompt => Intl.message("Drop a file to upload...",
      name: "fileDragDropPrompt",
      desc: "Text that is shown when a user is dragging a file");

  @override
  Widget build(BuildContext context) {
    if (widget.child != null) {
      return _buildWithChild();
    }
    return _buildOverlay();
  }

  /// Wraps a child widget with a drop target and shows the overlay on hover.
  Widget _buildWithChild() {
    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          isFileHovered = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          isFileHovered = false;
        });
      },
      onDragDone: (detail) {
        setState(() {
          isFileHovered = false;
        });
        widget.onDropComplete?.call(detail);
      },
      child: Stack(
        children: [
          widget.child!,
          Positioned.fill(child: _buildDropAffordance(context)),
        ],
      ),
    );
  }

  /// Legacy full-screen overlay mode (no child).
  Widget _buildOverlay() {
    return IgnorePointer(
      child: DropTarget(
          onDragEntered: (_) {
            setState(() {
              isFileHovered = true;
            });
          },
          onDragExited: (_) {
            setState(() {
              isFileHovered = false;
            });
          },
          onDragDone: (detail) {
            setState(() {
              isFileHovered = false;
            });
            widget.onDropComplete?.call(detail);
          },
          child: _buildDropAffordance(context)),
    );
  }

  Widget _buildDropAffordance(BuildContext context) {
    final duration = InterGalacticMotion.duration(
      context,
      InterGalacticMotion.dropTarget,
    );
    final curve = isFileHovered
        ? InterGalacticMotion.standardOut
        : InterGalacticMotion.standardIn;

    return IgnorePointer(
      child: ExcludeSemantics(
        excluding: !isFileHovered,
        child: Stack(
          children: [
            AnimatedOpacity(
              duration: duration,
              curve: curve,
              opacity: isFileHovered ? 0.5 : 0,
              child: Container(color: Colors.black),
            ),
            AnimatedOpacity(
              duration: duration,
              curve: curve,
              opacity: isFileHovered ? 1 : 0,
              child: Align(
                alignment: Alignment.center,
                child: tiamat.Text.largeTitle(fileDragDropPrompt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
