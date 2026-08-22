import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';

enum NotificationBadgeTone { neutral, accent, warning, danger }

class NotificationBadge extends StatelessWidget {
  const NotificationBadge(
    this.count, {
    super.key,
    this.size = 15,
    this.exclamation = false,
    this.tone,
    this.animateChanges = true,
    this.maxDisplayCount = 9,
  }) : assert(
         maxDisplayCount >= 1 && maxDisplayCount <= maxSupportedDisplayCount,
         'maxDisplayCount must be 1..$maxSupportedDisplayCount: the badge sizes '
         'itself from the label length, and a caller-chosen bound with no ceiling '
         'produces a label wider than any badge belongs in a rail. Clamp the count '
         'you pass, or widen this ceiling deliberately and check the layouts.',
       );

  /// The largest [maxDisplayCount] this badge will lay out.
  ///
  /// The width rule below is unbounded on purpose - every extra character gets
  /// its own advance, so no label is ever drawn in a box sized for a shorter
  /// one. That only stays sane because the LABEL is bounded here instead: five
  /// characters at most (`9999+`). A ceiling on the width instead of on the
  /// count is the bug this widget has now had twice - it silently mis-sizes the
  /// labels past the cap rather than telling the caller the count is
  /// unsupported.
  static const int maxSupportedDisplayCount = 9999;

  /// [maxDisplayCount] reduced to a value this badge can actually lay out.
  ///
  /// The assert above is debug-only, so on its own it left RELEASE builds with
  /// no ceiling at all and the unbounded width rule running free. This is the
  /// release half: a count outside the supported range is clamped rather than
  /// thrown on, because a badge is decoration on someone else's screen and
  /// taking down a `build()` over one is worse than the thing it prevents.
  ///
  /// Clamping the COUNT is not the mistake this widget keeps making. Clamping
  /// the WIDTH silently mis-draws a label the caller legitimately asked for -
  /// box and label disagree. Clamping the count keeps them consistent: the
  /// label becomes the ceiling the caller was told about, and the width still
  /// measures exactly that label.
  static int effectiveMaxDisplayCount(int requested) =>
      requested.clamp(1, maxSupportedDisplayCount);

  /// The exact string [build] renders, for a given set of inputs.
  ///
  /// Extracted so the release-only behaviour is directly observable. The
  /// constructor assert fires in debug, which is the only mode a widget test
  /// runs in, so NO amount of pumping can watch an out-of-range
  /// [maxDisplayCount] reach the label. Going through this function can.
  ///
  /// It is also the single place the label is formed, so the clamp cannot be
  /// skipped by [build] reading the raw field - the earlier version of this
  /// widget kept the formatting inline and a test that only checked
  /// [effectiveMaxDisplayCount] passed while `build` still used the unclamped
  /// value.
  static String displayLabelFor({
    required int count,
    required int maxDisplayCount,
    required bool exclamation,
  }) {
    if (exclamation) return "!";
    final cap = effectiveMaxDisplayCount(maxDisplayCount);
    return count > cap ? "$cap+" : count.toString();
  }

  final double size;
  final int count;
  final bool exclamation;
  final NotificationBadgeTone? tone;
  final bool animateChanges;
  final int maxDisplayCount;

  @override
  Widget build(BuildContext context) {
    final effectiveTone =
        tone ??
        (exclamation
            ? NotificationBadgeTone.warning
            : NotificationBadgeTone.danger);
    final colors = NotificationBadgeColors.from(context, effectiveTone);
    final displayText = displayLabelFor(
      count: count,
      maxDisplayCount: maxDisplayCount,
      exclamation: exclamation,
    );
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
    // Linear in the character count, and deliberately NOT clamped. Every
    // bucketed rule this widget has had collapsed lengths that need different
    // room: `length > 2 ? size * 1.7 : size` gave one and two characters the
    // SAME width then jumped 70% at three; the graduated `<=1 / 2 / _` that
    // followed fixed two digits but still handed `999+` the box sized for
    // `99+`; and a `.clamp(0, 8)` here was the same defect at a politer
    // threshold, mis-sizing anything past nine characters. A ceiling on the
    // WIDTH is always wrong, because the label it silently mis-draws is one
    // the caller legitimately asked for. The ceiling belongs on the count, and
    // it is asserted at the constructor.
    //
    // The multipliers are the ones the old buckets already used - 1, 1.35, 1.7
    // for one, two and three characters - which is exactly `size` plus
    // `0.35 * size` per character beyond the first, so every width that was
    // correct before is unchanged.
    const advancePerCharacter = 0.35;
    final width = size * (1 + advancePerCharacter * (displayText.length - 1));

    return SizedBox(
      width: width,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size / 2),
          color: colors.background,
          border: colors.border == null
              ? null
              : Border.all(color: colors.border!),
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
