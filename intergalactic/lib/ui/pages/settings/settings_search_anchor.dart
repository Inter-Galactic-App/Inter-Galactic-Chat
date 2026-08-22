import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';

class SettingsSearchHighlightController extends ChangeNotifier {
  String? _anchorId;
  int _generation = 0;

  String? get anchorId => _anchorId;
  int get generation => _generation;

  void highlight(String anchorId) {
    _anchorId = anchorId;
    _generation += 1;
    notifyListeners();
  }

  void clear({String? anchorId, int? generation}) {
    if (anchorId != null && _anchorId != anchorId) {
      return;
    }
    if (generation != null && _generation != generation) {
      return;
    }
    if (_anchorId == null) {
      return;
    }

    _anchorId = null;
    notifyListeners();
  }
}

class SettingsSearchHighlightScope extends InheritedWidget {
  const SettingsSearchHighlightScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final SettingsSearchHighlightController controller;

  static SettingsSearchHighlightController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SettingsSearchHighlightScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(SettingsSearchHighlightScope oldWidget) {
    return !identical(controller, oldWidget.controller);
  }
}

class SettingsSearchHighlightTarget extends StatefulWidget {
  const SettingsSearchHighlightTarget({
    required this.anchorId,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    super.key,
  });

  final String anchorId;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<SettingsSearchHighlightTarget> createState() =>
      _SettingsSearchHighlightTargetState();
}

class _SettingsSearchHighlightTargetState
    extends State<SettingsSearchHighlightTarget> {
  static const _highlightHoldDuration = Duration(milliseconds: 1500);
  static const _reducedMotionHighlightHoldDuration =
      Duration(milliseconds: 700);

  SettingsSearchHighlightController? _controller;
  Timer? _clearTimer;
  Timer? _scrollCorrectionTimer;
  bool _highlighted = false;
  int _seenGeneration = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SettingsSearchHighlightScope.maybeOf(context);
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_handleControllerChanged);
      _controller = controller;
      _controller?.addListener(_handleControllerChanged);
    }
    _handleControllerChanged();
  }

  @override
  void didUpdateWidget(covariant SettingsSearchHighlightTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchorId != widget.anchorId) {
      _seenGeneration = -1;
      _handleControllerChanged();
    }
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _scrollCorrectionTimer?.cancel();
    _controller?.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller == null ||
        controller.anchorId != widget.anchorId ||
        controller.generation == _seenGeneration) {
      return;
    }

    final anchorId = controller.anchorId;
    final generation = controller.generation;
    _seenGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _controller?.anchorId != anchorId ||
          _controller?.generation != generation) {
        return;
      }
      _activateHighlight(generation);
    });
  }

  void _activateHighlight(int generation) {
    _clearTimer?.cancel();
    _scrollCorrectionTimer?.cancel();
    if (mounted) {
      setState(() {
        _highlighted = true;
      });
    }

    final reduceMotion = InterGalacticMotion.shouldReduce(context);
    final scrollDuration = InterGalacticMotion.duration(
      context,
      InterGalacticMotion.standard,
    );
    _ensureVisible(duration: scrollDuration);
    if (scrollDuration > Duration.zero) {
      _scrollCorrectionTimer = Timer(scrollDuration, () {
        if (!mounted ||
            _controller?.anchorId != widget.anchorId ||
            _controller?.generation != generation) {
          return;
        }
        _ensureVisible(duration: Duration.zero);
      });
    }

    _clearTimer = Timer(
      reduceMotion
          ? _reducedMotionHighlightHoldDuration
          : _highlightHoldDuration,
      () => _releaseHighlight(generation),
    );
  }

  void _ensureVisible({required Duration duration}) {
    Scrollable.ensureVisible(
      context,
      alignment: 0.18,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: duration,
      curve: InterGalacticMotion.standardOut,
    );
  }

  void _releaseHighlight(int generation) {
    if (!mounted) {
      return;
    }

    setState(() {
      _highlighted = false;
    });
    _controller?.clear(anchorId: widget.anchorId, generation: generation);
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return widget.child;
    }

    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: InterGalacticMotion.duration(
        context,
        InterGalacticMotion.shortEmphasis,
      ),
      curve: InterGalacticMotion.standardOut,
      decoration: BoxDecoration(
        color: _highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: _highlighted
              ? theme.colorScheme.primary.withValues(alpha: 0.52)
              : Colors.transparent,
        ),
      ),
      child: widget.child,
    );
  }
}
