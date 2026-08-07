import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';

enum NotificationBadgeTone {
  neutral,
  accent,
  warning,
  danger,
}

class NotificationBadge extends StatelessWidget {
  const NotificationBadge(
    this.count, {
    super.key,
    this.size = 15,
    this.exclamation = false,
    this.tone,
    this.animateChanges = true,
  });

  final double size;
  final int count;
  final bool exclamation;
  final NotificationBadgeTone? tone;
  final bool animateChanges;

  @override
  Widget build(BuildContext context) {
    final effectiveTone = tone ??
        (exclamation
            ? NotificationBadgeTone.warning
            : NotificationBadgeTone.danger);
    final colors = NotificationBadgeColors.from(context, effectiveTone);
    final displayText = exclamation
        ? "!"
        : count > 9
            ? "9+"
            : count.toString();
    final text = Text(
      displayText,
      key: ValueKey<String>(displayText),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: size <= 16 ? 10 : 11,
            color: colors.foreground,
            height: 1,
          ),
    );
    final shouldReduce = InterGalacticMotion.shouldReduce(context);

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size / 2),
          color: colors.background,
          border:
              colors.border == null ? null : Border.all(color: colors.border!),
        ),
        child: Center(
          child: animateChanges && !shouldReduce
              ? AnimatedSwitcher(
                  duration: InterGalacticMotion.duration(
                    context,
                    InterGalacticMotion.short,
                  ),
                  switchInCurve: InterGalacticMotion.standardOut,
                  switchOutCurve: InterGalacticMotion.standardIn,
                  transitionBuilder: (child, animation) {
                    final scale = Tween<double>(begin: 0.9, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: InterGalacticMotion.standardOut,
                      ),
                    );

                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: scale, child: child),
                    );
                  },
                  child: text,
                )
              : text,
        ),
      ),
    );
  }
}

class NotificationBadgeColors {
  const NotificationBadgeColors({
    required this.background,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color foreground;
  final Color? border;

  static NotificationBadgeColors from(
    BuildContext context,
    NotificationBadgeTone tone,
  ) {
    final tokens = AccessibilityScope.tokensOf(context);

    return switch (tone) {
      NotificationBadgeTone.neutral => NotificationBadgeColors(
          background: tokens.settings.highContrast
              ? tokens.boundary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          foreground: tokens.statusForeground,
          border: tokens.strongBoundary,
        ),
      NotificationBadgeTone.accent => NotificationBadgeColors(
          background: tokens.success,
          foreground: tokens.onSuccess,
          border: tokens.settings.strongerVisualBoundaries
              ? tokens.strongBoundary
              : null,
        ),
      NotificationBadgeTone.warning => NotificationBadgeColors(
          background: tokens.warning,
          foreground: tokens.onWarning,
          border: tokens.settings.strongerVisualBoundaries
              ? tokens.strongBoundary
              : null,
        ),
      NotificationBadgeTone.danger => NotificationBadgeColors(
          background: tokens.danger,
          foreground: tokens.onDanger,
          border: tokens.settings.strongerVisualBoundaries
              ? tokens.strongBoundary
              : null,
        ),
    };
  }
}
