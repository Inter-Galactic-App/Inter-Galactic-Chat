import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_preferences.dart';

class AccessibilityPlatformSignals {
  const AccessibilityPlatformSignals({
    this.highContrast = false,
    this.boldText = false,
    this.disableAnimations = false,
    this.accessibleNavigation = false,
    this.onOffSwitchLabels = false,
    this.invertColors = false,
    this.textScaler = TextScaler.noScaling,
  });

  final bool highContrast;
  final bool boldText;
  final bool disableAnimations;
  final bool accessibleNavigation;
  final bool onOffSwitchLabels;
  final bool invertColors;
  final TextScaler textScaler;

  static AccessibilityPlatformSignals fromContext(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);

    if (mediaQuery == null) {
      return const AccessibilityPlatformSignals();
    }

    return AccessibilityPlatformSignals(
      highContrast: mediaQuery.highContrast,
      boldText: mediaQuery.boldText,
      disableAnimations: mediaQuery.disableAnimations,
      accessibleNavigation: mediaQuery.accessibleNavigation,
      onOffSwitchLabels: mediaQuery.onOffSwitchLabels,
      invertColors: mediaQuery.invertColors,
      textScaler: mediaQuery.textScaler,
    );
  }
}

class EffectiveAccessibilitySettings {
  const EffectiveAccessibilitySettings({
    required this.highContrast,
    required this.extraHighContrast,
    required this.colorSafe,
    required this.differentiateWithoutColor,
    required this.underlineLinks,
    required this.strongFocusIndicators,
    required this.showOnOffLabels,
    required this.boldText,
    required this.reduceTransparency,
    required this.increaseUiSeparation,
    required this.reduceMotion,
    required this.disableAnimations,
    required this.pauseAnimatedMedia,
    required this.largerTouchTargets,
    required this.persistentActionLabels,
    required this.textScaler,
    required this.textScaleMultiplier,
  });

  final bool highContrast;
  final bool extraHighContrast;
  final bool colorSafe;
  final bool differentiateWithoutColor;
  final bool underlineLinks;
  final bool strongFocusIndicators;
  final bool showOnOffLabels;
  final bool boldText;
  final bool reduceTransparency;
  final bool increaseUiSeparation;
  final bool reduceMotion;
  final bool disableAnimations;
  final bool pauseAnimatedMedia;
  final bool largerTouchTargets;
  final bool persistentActionLabels;
  final TextScaler textScaler;
  final double textScaleMultiplier;

  bool get strongerVisualBoundaries =>
      highContrast || extraHighContrast || increaseUiSeparation;

  bool get nonColorStateCues =>
      colorSafe || differentiateWithoutColor || highContrast;

  static EffectiveAccessibilitySettings resolve({
    required AppAccessibilityPreferences preferences,
    required AccessibilityPlatformSignals platform,
    double legacyTextScale = 1.0,
  }) {
    final contrast = preferences.contrast;
    final highContrast = switch (contrast) {
      AccessibilityContrastPreference.system => platform.highContrast,
      AccessibilityContrastPreference.normal => false,
      AccessibilityContrastPreference.high ||
      AccessibilityContrastPreference.extraHigh =>
        true,
    };
    final extraHighContrast =
        contrast == AccessibilityContrastPreference.extraHigh;
    final colorSafe = switch (preferences.color) {
      AccessibilityColorPreference.system => platform.invertColors,
      AccessibilityColorPreference.standard => false,
      AccessibilityColorPreference.colorSafe => true,
    };
    final motion = preferences.motion;
    final platformReducedMotion =
        platform.disableAnimations || platform.accessibleNavigation;
    final reduceMotion = switch (motion) {
      AccessibilityMotionPreference.system => platformReducedMotion,
      AccessibilityMotionPreference.normal => false,
      AccessibilityMotionPreference.reduced ||
      AccessibilityMotionPreference.none =>
        true,
    };
    final disableAnimations = switch (motion) {
      AccessibilityMotionPreference.system => platform.disableAnimations,
      AccessibilityMotionPreference.normal ||
      AccessibilityMotionPreference.reduced =>
        false,
      AccessibilityMotionPreference.none => true,
    };
    final textSizeMultiplier = preferences.textSize.multiplier;
    final legacyTextScaleMultiplier =
        preferences.textSize == AccessibilityTextSizePreference.system
            ? math.max(0.8, legacyTextScale)
            : 1.0;
    final effectiveTextScaleMultiplier =
        legacyTextScaleMultiplier * textSizeMultiplier;

    return EffectiveAccessibilitySettings(
      highContrast: highContrast,
      extraHighContrast: extraHighContrast,
      colorSafe: colorSafe,
      differentiateWithoutColor: _resolveToggle(
        preferences.differentiateWithoutColor,
        systemValue: colorSafe || highContrast,
      ),
      underlineLinks: _resolveToggle(
        preferences.underlineLinks,
        systemValue: colorSafe || highContrast,
      ),
      strongFocusIndicators: _resolveToggle(
        preferences.strongFocusIndicators,
        systemValue: highContrast || platform.accessibleNavigation,
      ),
      showOnOffLabels: _resolveToggle(
        preferences.showOnOffLabels,
        systemValue: platform.onOffSwitchLabels,
      ),
      boldText: _resolveToggle(
        preferences.boldText,
        systemValue: platform.boldText,
      ),
      reduceTransparency: _resolveToggle(
        preferences.reduceTransparency,
        systemValue: highContrast || platform.accessibleNavigation,
      ),
      increaseUiSeparation: _resolveToggle(
        preferences.increaseUiSeparation,
        systemValue: highContrast,
      ),
      reduceMotion: reduceMotion,
      disableAnimations: disableAnimations,
      pauseAnimatedMedia: _resolveToggle(
        preferences.pauseAnimatedMedia,
        systemValue: platformReducedMotion || reduceMotion,
      ),
      largerTouchTargets: _resolveToggle(
        preferences.largerTouchTargets,
        systemValue: platform.accessibleNavigation,
      ),
      persistentActionLabels: _resolveToggle(
        preferences.persistentActionLabels,
        systemValue: platform.accessibleNavigation,
      ),
      textScaler: _MultipliedTextScaler(
        platform.textScaler,
        effectiveTextScaleMultiplier,
      ),
      textScaleMultiplier: effectiveTextScaleMultiplier,
    );
  }

  static bool _resolveToggle(
    AccessibilityTogglePreference preference, {
    required bool systemValue,
  }) {
    return switch (preference) {
      AccessibilityTogglePreference.system => systemValue,
      AccessibilityTogglePreference.off => false,
      AccessibilityTogglePreference.on => true,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is EffectiveAccessibilitySettings &&
        other.highContrast == highContrast &&
        other.extraHighContrast == extraHighContrast &&
        other.colorSafe == colorSafe &&
        other.differentiateWithoutColor == differentiateWithoutColor &&
        other.underlineLinks == underlineLinks &&
        other.strongFocusIndicators == strongFocusIndicators &&
        other.showOnOffLabels == showOnOffLabels &&
        other.boldText == boldText &&
        other.reduceTransparency == reduceTransparency &&
        other.increaseUiSeparation == increaseUiSeparation &&
        other.reduceMotion == reduceMotion &&
        other.disableAnimations == disableAnimations &&
        other.pauseAnimatedMedia == pauseAnimatedMedia &&
        other.largerTouchTargets == largerTouchTargets &&
        other.persistentActionLabels == persistentActionLabels &&
        other.textScaler == textScaler &&
        other.textScaleMultiplier == textScaleMultiplier;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      highContrast,
      extraHighContrast,
      colorSafe,
      differentiateWithoutColor,
      underlineLinks,
      strongFocusIndicators,
      showOnOffLabels,
      boldText,
      reduceTransparency,
      increaseUiSeparation,
      reduceMotion,
      disableAnimations,
      pauseAnimatedMedia,
      largerTouchTargets,
      persistentActionLabels,
      textScaler,
      textScaleMultiplier,
    ]);
  }
}

class _MultipliedTextScaler extends TextScaler {
  const _MultipliedTextScaler(
    this.base,
    this.multiplier, {
    this.minScaleFactor = 0,
    this.maxScaleFactor = double.infinity,
  });

  final TextScaler base;
  final double multiplier;
  final double minScaleFactor;
  final double maxScaleFactor;

  @override
  double scale(double fontSize) {
    final scaledSize = base.scale(fontSize) * multiplier;
    final minSize = fontSize * minScaleFactor;
    final maxSize = fontSize * maxScaleFactor;
    return scaledSize.clamp(minSize, maxSize).toDouble();
  }

  @override
  double get textScaleFactor {
    // Keep legacy readers approximate while scale() preserves nonlinear base
    // behavior for actual text layout.
    return (base.scale(1) * multiplier)
        .clamp(minScaleFactor, maxScaleFactor)
        .toDouble();
  }

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) {
    return _MultipliedTextScaler(
      base,
      multiplier,
      minScaleFactor: math.max(this.minScaleFactor, minScaleFactor),
      maxScaleFactor: math.min(this.maxScaleFactor, maxScaleFactor),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _MultipliedTextScaler &&
        other.base == base &&
        other.multiplier == multiplier &&
        other.minScaleFactor == minScaleFactor &&
        other.maxScaleFactor == maxScaleFactor;
  }

  @override
  int get hashCode =>
      Object.hash(base, multiplier, minScaleFactor, maxScaleFactor);
}
