import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_resolver.dart';

class AccessibilityTokens {
  const AccessibilityTokens({
    required this.settings,
    required this.focusRing,
    required this.linkText,
    required this.danger,
    required this.onDanger,
    required this.warning,
    required this.onWarning,
    required this.success,
    required this.onSuccess,
    required this.statusOnline,
    required this.statusBusy,
    required this.statusOffline,
    required this.statusUnknown,
    required this.onStatusOnline,
    required this.onStatusBusy,
    required this.onStatusOffline,
    required this.onStatusUnknown,
    required this.statusForeground,
    required this.storyUnseen,
    required this.storySeen,
    required this.storyPending,
    required this.storyInactive,
    required this.boundary,
    required this.strongBoundary,
    required this.minimumInteractiveDimension,
  });

  final EffectiveAccessibilitySettings settings;
  final Color focusRing;
  final Color linkText;
  final Color danger;
  final Color onDanger;
  final Color warning;
  final Color onWarning;
  final Color success;
  final Color onSuccess;
  final Color statusOnline;
  final Color statusBusy;
  final Color statusOffline;
  final Color statusUnknown;
  final Color onStatusOnline;
  final Color onStatusBusy;
  final Color onStatusOffline;
  final Color onStatusUnknown;
  final Color statusForeground;
  final Color storyUnseen;
  final Color storySeen;
  final Color storyPending;
  final Color storyInactive;
  final Color boundary;
  final Color strongBoundary;
  final double minimumInteractiveDimension;

  static const Color _onlineSeed = Color(0xff00c7a4);
  static const Color _colorSafeOnlineSeed = Color(0xff2f8cff);
  static const Color _busySeed = Color(0xffd89a12);
  static const Color _offlineSeed = Color(0xff8b96a5);
  static const Color _unknownSeed = Color(0xff8e8cff);
  static const Color _storyUnseenSeed = Color(0xff31b7ff);
  static const Color _storySeenSeed = Color(0xff8794a6);
  static const Color _storyInactiveSeed = Color(0xff6c7787);

  static AccessibilityTokens from(
    BuildContext context,
    EffectiveAccessibilitySettings settings,
  ) {
    return fromColorScheme(Theme.of(context).colorScheme, settings);
  }

  static AccessibilityTokens fromColorScheme(
    ColorScheme scheme,
    EffectiveAccessibilitySettings settings,
  ) {
    final onSurface = scheme.onSurface;
    final surface = scheme.surface;
    final focus = _ensureContrast(
      settings.extraHighContrast ? scheme.onSurface : scheme.primary,
      surface,
      settings.extraHighContrast ? 7 : 3,
      fallback: scheme.onSurface,
    );
    final link = _ensureContrast(
      settings.colorSafe ? scheme.secondary : scheme.primary,
      surface,
      settings.extraHighContrast ? 7 : 4.5,
      fallback: scheme.onSurface,
    );
    final danger = _ensureContrast(
      scheme.error,
      surface,
      settings.extraHighContrast ? 7 : 3,
      fallback: scheme.onSurface,
    );
    final warning = _ensureContrast(
      settings.colorSafe ? scheme.tertiary : scheme.tertiaryContainer,
      surface,
      settings.extraHighContrast ? 7 : 3,
      fallback: scheme.onSurface,
    );
    final successBase = settings.colorSafe ? scheme.primary : scheme.secondary;
    final success = _ensureContrast(
      successBase,
      surface,
      settings.extraHighContrast ? 7 : 3,
      fallback: scheme.onSurface,
    );
    final indicatorMinimum = settings.extraHighContrast ? 7.0 : 3.0;
    final online = _indicatorContrast(
      settings.colorSafe ? _colorSafeOnlineSeed : _onlineSeed,
      surface,
      indicatorMinimum,
    );
    final busy = _indicatorContrast(_busySeed, surface, indicatorMinimum);
    final offline = _indicatorContrast(_offlineSeed, surface, indicatorMinimum);
    final unknown = _indicatorContrast(_unknownSeed, surface, indicatorMinimum);
    final storyUnseen = _indicatorContrast(
      _storyUnseenSeed,
      surface,
      indicatorMinimum,
    );
    final storySeen = _indicatorContrast(
      _storySeenSeed,
      surface,
      indicatorMinimum,
    );
    final storyPending = _indicatorContrast(
      _busySeed,
      surface,
      indicatorMinimum,
    );
    final storyInactive = _indicatorContrast(
      _storyInactiveSeed,
      surface,
      indicatorMinimum,
    );

    return AccessibilityTokens(
      settings: settings,
      focusRing: focus,
      linkText: link,
      danger: danger,
      onDanger: _foregroundFor(danger),
      warning: warning,
      onWarning: _foregroundFor(warning),
      success: success,
      onSuccess: _foregroundFor(success),
      statusOnline: online,
      statusBusy: busy,
      statusOffline: offline,
      statusUnknown: unknown,
      onStatusOnline: _foregroundFor(online),
      onStatusBusy: _foregroundFor(busy),
      onStatusOffline: _foregroundFor(offline),
      onStatusUnknown: _foregroundFor(unknown),
      statusForeground: onSurface,
      storyUnseen: storyUnseen,
      storySeen: storySeen,
      storyPending: storyPending,
      storyInactive: storyInactive,
      boundary: scheme.outlineVariant,
      strongBoundary: settings.strongerVisualBoundaries
          ? _ensureContrast(
              scheme.outline,
              surface,
              3,
              fallback: scheme.onSurface,
            )
          : scheme.outline.withValues(alpha: 0.64),
      minimumInteractiveDimension: settings.largerTouchTargets ? 48 : 40,
    );
  }

  Color resolveIdentityTextColor(
    Color? preferred,
    ColorScheme scheme, {
    Color? background,
    double minimumContrast = 3,
  }) {
    final resolvedBackground = background ?? scheme.surface;
    final fallback = _ensureContrast(
      linkText,
      resolvedBackground,
      minimumContrast,
      fallback: scheme.onSurface,
    );
    final preferredColor = preferred ?? fallback;

    if (settings.colorSafe && _isRedOrGreenHue(preferredColor)) {
      return fallback;
    }

    return _ensureContrast(
      preferredColor,
      resolvedBackground,
      minimumContrast,
      fallback: fallback,
    );
  }

  static double contrastRatio(Color foreground, Color background) {
    final l1 = _relativeLuminance(foreground);
    final l2 = _relativeLuminance(background);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color color) {
    double channel(double value) {
      final normalized = value / 255;
      return normalized <= 0.03928
          ? normalized / 12.92
          : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(color.r * 255) +
        0.7152 * channel(color.g * 255) +
        0.0722 * channel(color.b * 255);
  }

  static Color _ensureContrast(
    Color preferred,
    Color background,
    double minimum, {
    required Color fallback,
  }) {
    if (contrastRatio(preferred, background) >= minimum) {
      return preferred;
    }

    if (contrastRatio(fallback, background) >= minimum) {
      return fallback;
    }

    final blackContrast = contrastRatio(Colors.black, background);
    final whiteContrast = contrastRatio(Colors.white, background);
    return blackContrast >= whiteContrast ? Colors.black : Colors.white;
  }

  static Color _indicatorContrast(
    Color seed,
    Color background,
    double minimum,
  ) {
    if (contrastRatio(seed, background) >= minimum) {
      return seed;
    }

    final base = HSLColor.fromColor(seed);
    final saturate = math.max(base.saturation, 0.54).toDouble();
    final backgroundLuminance = _relativeLuminance(background);
    final darken = backgroundLuminance > 0.42;

    for (var step = 1; step <= 12; step++) {
      final delta = step * 0.055;
      final lightness = darken
          ? math.max(0.12, base.lightness - delta)
          : math.min(0.9, base.lightness + delta);
      final candidate = base
          .withSaturation(saturate)
          .withLightness(lightness.toDouble())
          .toColor();
      if (contrastRatio(candidate, background) >= minimum) {
        return candidate;
      }
    }

    return _ensureContrast(
      seed,
      background,
      minimum,
      fallback: _foregroundFor(background),
    );
  }

  static Color _foregroundFor(Color background) {
    return contrastRatio(Colors.black, background) >=
            contrastRatio(Colors.white, background)
        ? Colors.black
        : Colors.white;
  }

  static bool _isRedOrGreenHue(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.28) {
      return false;
    }

    final hue = hsl.hue;
    return hue <= 18 || hue >= 340 || (hue >= 70 && hue <= 170);
  }

  @override
  bool operator ==(Object other) {
    return other is AccessibilityTokens &&
        other.settings == settings &&
        other.focusRing == focusRing &&
        other.linkText == linkText &&
        other.danger == danger &&
        other.onDanger == onDanger &&
        other.warning == warning &&
        other.onWarning == onWarning &&
        other.success == success &&
        other.onSuccess == onSuccess &&
        other.statusOnline == statusOnline &&
        other.statusBusy == statusBusy &&
        other.statusOffline == statusOffline &&
        other.statusUnknown == statusUnknown &&
        other.onStatusOnline == onStatusOnline &&
        other.onStatusBusy == onStatusBusy &&
        other.onStatusOffline == onStatusOffline &&
        other.onStatusUnknown == onStatusUnknown &&
        other.statusForeground == statusForeground &&
        other.storyUnseen == storyUnseen &&
        other.storySeen == storySeen &&
        other.storyPending == storyPending &&
        other.storyInactive == storyInactive &&
        other.boundary == boundary &&
        other.strongBoundary == strongBoundary &&
        other.minimumInteractiveDimension == minimumInteractiveDimension;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      settings,
      focusRing,
      linkText,
      danger,
      onDanger,
      warning,
      onWarning,
      success,
      onSuccess,
      statusOnline,
      statusBusy,
      statusOffline,
      statusUnknown,
      onStatusOnline,
      onStatusBusy,
      onStatusOffline,
      onStatusUnknown,
      statusForeground,
      storyUnseen,
      storySeen,
      storyPending,
      storyInactive,
      boundary,
      strongBoundary,
      minimumInteractiveDimension,
    ]);
  }
}
