import 'package:intergalactic/config/preferences.dart';

enum AccessibilityTogglePreference {
  system('system', 'System'),
  off('off', 'Off'),
  on('on', 'On');

  const AccessibilityTogglePreference(this.value, this.label);

  final String value;
  final String label;

  static AccessibilityTogglePreference from(String value) {
    return AccessibilityTogglePreference.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AccessibilityTogglePreference.system,
    );
  }
}

enum AccessibilityContrastPreference {
  system('system', 'System'),
  normal('normal', 'Normal'),
  high('high', 'High'),
  extraHigh('extra_high', 'Extra high');

  const AccessibilityContrastPreference(this.value, this.label);

  final String value;
  final String label;

  static AccessibilityContrastPreference from(String value) {
    return AccessibilityContrastPreference.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AccessibilityContrastPreference.system,
    );
  }
}

enum AccessibilityColorPreference {
  system('system', 'System'),
  standard('standard', 'Standard'),
  colorSafe('color_safe', 'Color-safe');

  const AccessibilityColorPreference(this.value, this.label);

  final String value;
  final String label;

  static AccessibilityColorPreference from(String value) {
    return AccessibilityColorPreference.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AccessibilityColorPreference.system,
    );
  }
}

enum AccessibilityMotionPreference {
  system('system', 'System'),
  normal('normal', 'Normal'),
  reduced('reduced', 'Reduced'),
  none('none', 'None');

  const AccessibilityMotionPreference(this.value, this.label);

  final String value;
  final String label;

  static AccessibilityMotionPreference from(String value) {
    return AccessibilityMotionPreference.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AccessibilityMotionPreference.system,
    );
  }
}

enum AccessibilityTextSizePreference {
  system('system', 'System'),
  normal('normal', 'Normal'),
  large('large', 'Large'),
  extraLarge('extra_large', 'Extra large'),
  huge('huge', 'Huge');

  const AccessibilityTextSizePreference(this.value, this.label);

  final String value;
  final String label;

  static AccessibilityTextSizePreference from(String value) {
    return AccessibilityTextSizePreference.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AccessibilityTextSizePreference.system,
    );
  }

  double get multiplier {
    return switch (this) {
      AccessibilityTextSizePreference.system ||
      AccessibilityTextSizePreference.normal =>
        1.0,
      AccessibilityTextSizePreference.large => 1.15,
      AccessibilityTextSizePreference.extraLarge => 1.3,
      AccessibilityTextSizePreference.huge => 1.6,
    };
  }
}

class AppAccessibilityPreferences {
  const AppAccessibilityPreferences({
    required this.contrast,
    required this.color,
    required this.motion,
    required this.textSize,
    required this.differentiateWithoutColor,
    required this.underlineLinks,
    required this.strongFocusIndicators,
    required this.showOnOffLabels,
    required this.boldText,
    required this.reduceTransparency,
    required this.increaseUiSeparation,
    required this.pauseAnimatedMedia,
    required this.largerTouchTargets,
    required this.persistentActionLabels,
  });

  final AccessibilityContrastPreference contrast;
  final AccessibilityColorPreference color;
  final AccessibilityMotionPreference motion;
  final AccessibilityTextSizePreference textSize;
  final AccessibilityTogglePreference differentiateWithoutColor;
  final AccessibilityTogglePreference underlineLinks;
  final AccessibilityTogglePreference strongFocusIndicators;
  final AccessibilityTogglePreference showOnOffLabels;
  final AccessibilityTogglePreference boldText;
  final AccessibilityTogglePreference reduceTransparency;
  final AccessibilityTogglePreference increaseUiSeparation;
  final AccessibilityTogglePreference pauseAnimatedMedia;
  final AccessibilityTogglePreference largerTouchTargets;
  final AccessibilityTogglePreference persistentActionLabels;

  static AppAccessibilityPreferences fromPreferences(Preferences preferences) {
    return AppAccessibilityPreferences(
      contrast: AccessibilityContrastPreference.from(
        preferences.accessibilityContrast.value,
      ),
      color: AccessibilityColorPreference.from(
        preferences.accessibilityColor.value,
      ),
      motion: AccessibilityMotionPreference.from(
        preferences.accessibilityMotion.value,
      ),
      textSize: AccessibilityTextSizePreference.from(
        preferences.accessibilityTextSize.value,
      ),
      differentiateWithoutColor: AccessibilityTogglePreference.from(
        preferences.accessibilityDifferentiateWithoutColor.value,
      ),
      underlineLinks: AccessibilityTogglePreference.from(
        preferences.accessibilityUnderlineLinks.value,
      ),
      strongFocusIndicators: AccessibilityTogglePreference.from(
        preferences.accessibilityStrongFocusIndicators.value,
      ),
      showOnOffLabels: AccessibilityTogglePreference.from(
        preferences.accessibilityShowOnOffLabels.value,
      ),
      boldText: AccessibilityTogglePreference.from(
        preferences.accessibilityBoldText.value,
      ),
      reduceTransparency: AccessibilityTogglePreference.from(
        preferences.accessibilityReduceTransparency.value,
      ),
      increaseUiSeparation: AccessibilityTogglePreference.from(
        preferences.accessibilityIncreaseUiSeparation.value,
      ),
      pauseAnimatedMedia: AccessibilityTogglePreference.from(
        preferences.accessibilityPauseAnimatedMedia.value,
      ),
      largerTouchTargets: AccessibilityTogglePreference.from(
        preferences.accessibilityLargerTouchTargets.value,
      ),
      persistentActionLabels: AccessibilityTogglePreference.from(
        preferences.accessibilityPersistentActionLabels.value,
      ),
    );
  }

  static Future<void> resetToSystemDefaults(Preferences preferences) async {
    await preferences.accessibilityContrast.set(
      AccessibilityContrastPreference.system.value,
    );
    await preferences.accessibilityColor.set(
      AccessibilityColorPreference.system.value,
    );
    await preferences.accessibilityMotion.set(
      AccessibilityMotionPreference.system.value,
    );
    await preferences.accessibilityTextSize.set(
      AccessibilityTextSizePreference.system.value,
    );
    await preferences.textScale.set(1.0);
    await preferences.accessibilityDifferentiateWithoutColor.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityUnderlineLinks.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityStrongFocusIndicators.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityShowOnOffLabels.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityBoldText.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityReduceTransparency.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityIncreaseUiSeparation.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityPauseAnimatedMedia.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityLargerTouchTargets.set(
      AccessibilityTogglePreference.system.value,
    );
    await preferences.accessibilityPersistentActionLabels.set(
      AccessibilityTogglePreference.system.value,
    );
  }
}
