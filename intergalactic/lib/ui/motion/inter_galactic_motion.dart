import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';

/// Shared Inter Galactic motion tokens and reduced-motion helpers.
class InterGalacticMotion {
  const InterGalacticMotion._();

  static const Duration instant = Duration.zero;
  static const Duration short = Duration(milliseconds: 140);
  static const Duration shortEmphasis = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration settingsOverlayIn = Duration(milliseconds: 180);
  static const Duration settingsOverlayOut = Duration(milliseconds: 140);
  static const Duration long = Duration(milliseconds: 300);
  static const Duration dropTarget = Duration(milliseconds: 500);
  static const Duration mobileRoute = Duration(milliseconds: 500);

  static const Curve standardOut = Curves.easeOutCubic;
  static const Curve standardIn = Curves.easeInCubic;
  static const Curve emphasis = Curves.fastOutSlowIn;

  static bool shouldReduce(BuildContext context) {
    final accessibilitySettings = AccessibilityScope.maybeOf(context);
    final mediaQuery = MediaQuery.maybeOf(context);
    final disableAnimations = mediaQuery?.disableAnimations ?? false;
    final disableTickers = TickerMode.valuesOf(context).enabled == false;
    return accessibilitySettings?.reduceMotion == true ||
        disableAnimations ||
        disableTickers;
  }

  static Duration duration(
    BuildContext context,
    Duration value,
  ) {
    return shouldReduce(context) ? instant : value;
  }
}
