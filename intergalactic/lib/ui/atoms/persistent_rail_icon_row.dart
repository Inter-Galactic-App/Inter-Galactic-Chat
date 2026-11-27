import 'dart:math' as math;

import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:flutter/material.dart';

const persistentRailIconLabelWidth = 102.0;
const persistentRailIconMaxSize = 44.0;

bool shouldShowPersistentRailIconLabel(BuildContext context) {
  return Layout.desktop &&
      AccessibilityScope.of(context).persistentActionLabels;
}

double persistentRailIconSizeFor({
  required double baseSize,
  required bool showPersistentLabel,
}) {
  return showPersistentLabel
      ? math.min(baseSize, persistentRailIconMaxSize)
      : baseSize;
}

class PersistentRailIconRow extends StatelessWidget {
  const PersistentRailIconRow({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.label,
    this.selected = false,
  });

  final Widget icon;
  final double iconSize;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = iconSize + persistentRailIconLabelWidth;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;

        return SizedBox(
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? scheme.secondaryContainer.withValues(alpha: 0.58)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(color: scheme.outline.withValues(alpha: 0.28))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 4, 8, 4),
              child: Row(
                children: [
                  SizedBox(width: iconSize, height: iconSize, child: icon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected
                              ? scheme.onSecondaryContainer
                              : scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
