import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';

enum TutorialArrowDirection { none, left, right, up, down }

class TutorialFocusSpec {
  const TutorialFocusSpec({
    required this.alignment,
    required this.width,
    required this.height,
    this.margin = EdgeInsets.zero,
    this.radius = 18,
    this.arrowDirection = TutorialArrowDirection.none,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.anchorId,
    this.anchorPadding = EdgeInsets.zero,
  });

  final Alignment alignment;
  final double width;
  final double height;
  final EdgeInsets margin;
  final double radius;
  final TutorialArrowDirection arrowDirection;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final String? anchorId;
  final EdgeInsets anchorPadding;
}

class TutorialFocusOverlay extends StatelessWidget {
  const TutorialFocusOverlay({required this.focus, super.key});

  final TutorialFocusSpec focus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final registry = TutorialAnchorScope.maybeOf(context);

    if (registry == null) {
      return _TutorialFocusLayout(focus: focus, scheme: scheme);
    }

    return AnimatedBuilder(
      animation: registry,
      builder: (context, _) {
        return _TutorialFocusLayout(
          focus: focus,
          scheme: scheme,
          measuredRect: focus.anchorId == null
              ? null
              : registry.rectFor(focus.anchorId!),
        );
      },
    );
  }
}

class _TutorialFocusLayout extends StatelessWidget {
  const _TutorialFocusLayout({
    required this.focus,
    required this.scheme,
    this.measuredRect,
  });

  final TutorialFocusSpec focus;
  final ColorScheme scheme;
  final Rect? measuredRect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvas = Size(constraints.maxWidth, constraints.maxHeight);
          final measured = measuredRect == null
              ? null
              : _withPadding(measuredRect!);

          // Anchored scenes wait for their concrete surface to report a
          // rectangle. Falling back to static mobile geometry while a panel is
          // animating produces a visibly wrong spotlight, which is worse than
          // one frame without a highlight.
          if (focus.anchorId != null && measured == null) {
            return const SizedBox.expand();
          }

          final rect = measured == null
              ? _rectForFocus(canvas, focus)
              : _clampRectToCanvas(measured, canvas);

          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _TutorialFocusPainter(
                  rect: rect,
                  radius: focus.radius,
                  scrim: scheme.scrim.withValues(alpha: 0.48),
                  outline: scheme.outline,
                  glow: scheme.outline.withValues(alpha: 0.26),
                ),
              ),
              if (focus.arrowDirection != TutorialArrowDirection.none)
                _TutorialArrow(
                  direction: focus.arrowDirection,
                  target: rect,
                  canvas: canvas,
                ),
            ],
          );
        },
      ),
    );
  }

  Rect _withPadding(Rect rect) {
    final padding = focus.anchorPadding;

    return Rect.fromLTRB(
      rect.left - padding.left,
      rect.top - padding.top,
      rect.right + padding.right,
      rect.bottom + padding.bottom,
    );
  }

  Rect _clampRectToCanvas(Rect rect, Size canvas) {
    final left = rect.left.clamp(0.0, canvas.width).toDouble();
    final top = rect.top.clamp(0.0, canvas.height).toDouble();
    final right = rect.right.clamp(left, canvas.width).toDouble();
    final bottom = rect.bottom.clamp(top, canvas.height).toDouble();

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _rectForFocus(Size canvas, TutorialFocusSpec spec) {
    final horizontal = _axisForFocus(
      canvasExtent: canvas.width,
      start: spec.left,
      end: spec.right,
      marginStart: spec.margin.left,
      marginEnd: spec.margin.right,
      extent: spec.width,
      alignment: spec.alignment.x,
    );
    final vertical = _axisForFocus(
      canvasExtent: canvas.height,
      start: spec.top,
      end: spec.bottom,
      marginStart: spec.margin.top,
      marginEnd: spec.margin.bottom,
      extent: spec.height,
      alignment: spec.alignment.y,
    );

    return Rect.fromLTWH(
      horizontal.$1,
      vertical.$1,
      horizontal.$2,
      vertical.$2,
    );
  }

  (double, double) _axisForFocus({
    required double canvasExtent,
    required double? start,
    required double? end,
    required double marginStart,
    required double marginEnd,
    required double extent,
    required double alignment,
  }) {
    final hasStart = start != null;
    final hasEnd = end != null;

    if (hasStart || hasEnd) {
      final resolvedStart = start ?? marginStart;
      final resolvedEnd = end ?? marginEnd;
      final available = math.max(
        0.0,
        canvasExtent - resolvedStart - resolvedEnd,
      );
      final resolvedExtent = hasStart && hasEnd
          ? available
          : math.min(extent, available);
      final offset = hasStart
          ? resolvedStart
          : math.max(0.0, canvasExtent - resolvedEnd - resolvedExtent);

      return (offset, resolvedExtent);
    }

    final available = math.max(0.0, canvasExtent - marginStart - marginEnd);
    final resolvedExtent = math.min(extent, available);
    final offset =
        marginStart + (available - resolvedExtent) * ((alignment + 1) / 2);

    return (offset, resolvedExtent);
  }
}

class _TutorialFocusPainter extends CustomPainter {
  const _TutorialFocusPainter({
    required this.rect,
    required this.radius,
    required this.scrim,
    required this.outline,
    required this.glow,
  });

  final Rect rect;
  final double radius;
  final Color scrim;
  final Color outline;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final cutout = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cutout);

    canvas.drawPath(overlay, Paint()..color = scrim);

    canvas.drawRRect(
      cutout,
      Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.drawRRect(
      cutout,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TutorialFocusPainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.radius != radius ||
        oldDelegate.scrim != scrim ||
        oldDelegate.outline != outline ||
        oldDelegate.glow != glow;
  }
}

class _TutorialArrow extends StatelessWidget {
  const _TutorialArrow({
    required this.direction,
    required this.target,
    required this.canvas,
  });

  final TutorialArrowDirection direction;
  final Rect target;
  final Size canvas;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (direction) {
      TutorialArrowDirection.left => Icons.arrow_back_rounded,
      TutorialArrowDirection.right => Icons.arrow_forward_rounded,
      TutorialArrowDirection.up => Icons.arrow_upward_rounded,
      TutorialArrowDirection.down => Icons.arrow_downward_rounded,
      TutorialArrowDirection.none => Icons.arrow_forward_rounded,
    };
    final position = _clampToCanvas(_positionForDirection(direction, target));

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer.withValues(alpha: 0.94),
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outline),
          boxShadow: [
            BoxShadow(
              color: scheme.scrim.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: scheme.onSurface, size: 28),
        ),
      ),
    );
  }

  Offset _positionForDirection(TutorialArrowDirection direction, Rect rect) {
    return switch (direction) {
      TutorialArrowDirection.left => Offset(
        rect.right + 14,
        rect.center.dy - 22,
      ),
      TutorialArrowDirection.right => Offset(
        rect.left - 58,
        rect.center.dy - 22,
      ),
      TutorialArrowDirection.up => Offset(
        rect.center.dx - 22,
        rect.bottom + 14,
      ),
      TutorialArrowDirection.down => Offset(rect.center.dx - 22, rect.top - 58),
      TutorialArrowDirection.none => Offset(
        rect.right + 14,
        rect.center.dy - 22,
      ),
    };
  }

  Offset _clampToCanvas(Offset offset) {
    const arrowExtent = 52.0;
    final maxX = math.max(8.0, canvas.width - arrowExtent);
    final maxY = math.max(8.0, canvas.height - arrowExtent);

    return Offset(
      offset.dx.clamp(8.0, maxX).toDouble(),
      offset.dy.clamp(8.0, maxY).toDouble(),
    );
  }
}
