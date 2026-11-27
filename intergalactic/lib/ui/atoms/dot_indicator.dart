import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';

class DotIndicator extends StatelessWidget {
  const DotIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AccessibilityScope.tokensOf(context);
    final nonColorCue = tokens.settings.nonColorStateCues;

    return SizedBox(
      width: 10,
      height: 10,
      child: Transform.rotate(
        angle: nonColorCue ? 0.7853981634 : 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.success,
            borderRadius: BorderRadius.circular(nonColorCue ? 2 : 5),
            border: Border.all(color: tokens.strongBoundary),
          ),
        ),
      ),
    );
  }
}
