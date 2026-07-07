import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/accessibility/accessibility_preferences.dart';
import 'package:intergalactic/ui/accessibility/accessibility_resolver.dart';
import 'package:intergalactic/ui/accessibility/accessibility_tokens.dart';

void main() {
  group('EffectiveAccessibilitySettings', () {
    test('follows platform signals by default', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(),
        platform: AccessibilityPlatformSignals(
          highContrast: true,
          boldText: true,
          disableAnimations: true,
          accessibleNavigation: true,
          onOffSwitchLabels: true,
          textScaler: TextScaler.linear(1.25),
        ),
        legacyTextScale: 1.2,
      );

      expect(settings.highContrast, isTrue);
      expect(settings.boldText, isTrue);
      expect(settings.reduceMotion, isTrue);
      expect(settings.showOnOffLabels, isTrue);
      expect(settings.strongFocusIndicators, isTrue);
      expect(settings.largerTouchTargets, isTrue);
      expect(settings.reduceTransparency, isTrue);
      expect(settings.textScaler.scale(10), closeTo(15, 0.01));
    });

    test('manual overrides win over platform signals', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(
          contrast: AccessibilityContrastPreference.normal,
          motion: AccessibilityMotionPreference.normal,
          boldText: AccessibilityTogglePreference.off,
          showOnOffLabels: AccessibilityTogglePreference.off,
          largerTouchTargets: AccessibilityTogglePreference.off,
          reduceTransparency: AccessibilityTogglePreference.off,
        ),
        platform: AccessibilityPlatformSignals(
          highContrast: true,
          boldText: true,
          disableAnimations: true,
          accessibleNavigation: true,
          onOffSwitchLabels: true,
        ),
      );

      expect(settings.highContrast, isFalse);
      expect(settings.boldText, isFalse);
      expect(settings.reduceMotion, isFalse);
      expect(settings.disableAnimations, isFalse);
      expect(settings.showOnOffLabels, isFalse);
      expect(settings.largerTouchTargets, isFalse);
      expect(settings.reduceTransparency, isFalse);
    });

    test('color-safe and high contrast add non-color cues', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(
          color: AccessibilityColorPreference.colorSafe,
          contrast: AccessibilityContrastPreference.high,
        ),
        platform: const AccessibilityPlatformSignals(),
      );

      expect(settings.colorSafe, isTrue);
      expect(settings.highContrast, isTrue);
      expect(settings.nonColorStateCues, isTrue);
      expect(settings.underlineLinks, isTrue);
      expect(settings.differentiateWithoutColor, isTrue);
    });

    test('none motion disables animations and pauses media', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(motion: AccessibilityMotionPreference.none),
        platform: const AccessibilityPlatformSignals(),
      );

      expect(settings.reduceMotion, isTrue);
      expect(settings.disableAnimations, isTrue);
      expect(settings.pauseAnimatedMedia, isTrue);
    });

    test('manual accessibility text size ignores legacy appearance scale', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(
          textSize: AccessibilityTextSizePreference.huge,
        ),
        platform: AccessibilityPlatformSignals(
          textScaler: TextScaler.linear(1.25),
        ),
        legacyTextScale: 1.4,
      );

      expect(settings.textScaleMultiplier, closeTo(1.6, 0.01));
      expect(settings.textScaler.scale(10), closeTo(20, 0.01));
    });

    test('app text-size multiplier preserves nonlinear platform scaling', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(
          textSize: AccessibilityTextSizePreference.large,
        ),
        platform: const AccessibilityPlatformSignals(
          textScaler: _NonlinearTestTextScaler(),
        ),
      );

      expect(settings.textScaleMultiplier, closeTo(1.15, 0.01));
      expect(settings.textScaler.scale(10), closeTo(23, 0.01));
      expect(settings.textScaler.scale(30), closeTo(51.75, 0.01));
    });

    test('text scaler clamp applies to multiplied nonlinear output', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(
          textSize: AccessibilityTextSizePreference.large,
        ),
        platform: const AccessibilityPlatformSignals(
          textScaler: _NonlinearTestTextScaler(),
        ),
      );

      final capped = settings.textScaler.clamp(maxScaleFactor: 1.75);
      expect(capped.scale(1), closeTo(1.75, 0.01));
      expect(capped.scale(10), closeTo(17.5, 0.01));

      final floored = settings.textScaler.clamp(minScaleFactor: 2.0);
      expect(floored.scale(30), closeTo(60, 0.01));
    });
  });

  group('AccessibilityTokens', () {
    test('keeps important color pairs above minimum contrast', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(
          contrast: AccessibilityContrastPreference.extraHigh,
          color: AccessibilityColorPreference.colorSafe,
        ),
        platform: const AccessibilityPlatformSignals(),
      );
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xff20d6d2),
        brightness: Brightness.dark,
      );
      final tokens = AccessibilityTokens.fromColorScheme(scheme, settings);

      expect(
        AccessibilityTokens.contrastRatio(tokens.focusRing, scheme.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        AccessibilityTokens.contrastRatio(tokens.linkText, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        AccessibilityTokens.contrastRatio(tokens.danger, scheme.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        AccessibilityTokens.contrastRatio(tokens.statusOffline, scheme.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        AccessibilityTokens.contrastRatio(tokens.statusUnknown, scheme.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        AccessibilityTokens.contrastRatio(tokens.storyUnseen, scheme.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        AccessibilityTokens.contrastRatio(tokens.storySeen, scheme.surface),
        greaterThanOrEqualTo(3),
      );
      expect(tokens.statusOnline, isNot(equals(tokens.danger)));
      expect(tokens.minimumInteractiveDimension, 40.0);
    });

    test('presence and story indicators do not inherit editable surfaces', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(),
        platform: const AccessibilityPlatformSignals(),
      );
      const customSurface = Color(0xff12333a);
      const scheme = ColorScheme.dark(
        surface: customSurface,
        onSurface: Colors.white,
        primary: customSurface,
        secondary: customSurface,
        tertiary: customSurface,
        tertiaryContainer: customSurface,
        error: Color(0xffffb4ab),
        outline: customSurface,
        outlineVariant: customSurface,
      );
      final tokens = AccessibilityTokens.fromColorScheme(scheme, settings);
      final indicatorColors = [
        tokens.statusOnline,
        tokens.statusBusy,
        tokens.statusOffline,
        tokens.statusUnknown,
        tokens.storyUnseen,
        tokens.storySeen,
        tokens.storyPending,
        tokens.storyInactive,
      ];

      for (final color in indicatorColors) {
        expect(color, isNot(equals(customSurface)));
        expect(
          AccessibilityTokens.contrastRatio(color, customSurface),
          greaterThanOrEqualTo(3),
        );
      }
      expect(tokens.statusOnline, isNot(equals(tokens.statusOffline)));
      expect(tokens.storyUnseen, isNot(equals(tokens.storySeen)));
    });

    test('color-safe online status uses a blue indicator', () {
      const scheme = ColorScheme.dark(
        surface: Color(0xff05080d),
        onSurface: Colors.white,
        primary: Color(0xff00c7a4),
        secondary: Color(0xff00c7a4),
        tertiary: Color(0xffd89a12),
        tertiaryContainer: Color(0xffd89a12),
        error: Color(0xffffb4ab),
        outline: Color(0xff45505f),
        outlineVariant: Color(0xff2a3340),
      );
      final standardTokens = AccessibilityTokens.fromColorScheme(
        scheme,
        EffectiveAccessibilitySettings.resolve(
          preferences: _preferences(
            color: AccessibilityColorPreference.standard,
          ),
          platform: const AccessibilityPlatformSignals(),
        ),
      );
      final colorSafeTokens = AccessibilityTokens.fromColorScheme(
        scheme,
        EffectiveAccessibilitySettings.resolve(
          preferences: _preferences(
            color: AccessibilityColorPreference.colorSafe,
          ),
          platform: const AccessibilityPlatformSignals(),
        ),
      );
      final standardHue = HSLColor.fromColor(standardTokens.statusOnline).hue;
      final colorSafeHue = HSLColor.fromColor(colorSafeTokens.statusOnline).hue;

      expect(standardHue, inInclusiveRange(130, 190));
      expect(colorSafeHue, inInclusiveRange(190, 260));
      expect(
        colorSafeTokens.statusOnline,
        isNot(equals(standardTokens.statusOnline)),
      );
    });

    test('larger touch target mode increases shared density token', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(
          largerTouchTargets: AccessibilityTogglePreference.on,
        ),
        platform: const AccessibilityPlatformSignals(),
      );
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
      final tokens = AccessibilityTokens.fromColorScheme(scheme, settings);

      expect(tokens.minimumInteractiveDimension, 48);
    });

    test('color-safe identity text avoids red and green name colors', () {
      final settings = EffectiveAccessibilitySettings.resolve(
        preferences: _preferences(
          color: AccessibilityColorPreference.colorSafe,
        ),
        platform: const AccessibilityPlatformSignals(),
      );
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      final tokens = AccessibilityTokens.fromColorScheme(scheme, settings);
      final redName = tokens.resolveIdentityTextColor(Colors.redAccent, scheme);
      final greenName = tokens.resolveIdentityTextColor(
        Colors.greenAccent,
        scheme,
      );

      expect(redName, equals(tokens.linkText));
      expect(greenName, equals(tokens.linkText));
      expect(
        AccessibilityTokens.contrastRatio(redName, scheme.surface),
        greaterThanOrEqualTo(3),
      );
    });
  });
}

class _NonlinearTestTextScaler extends TextScaler {
  const _NonlinearTestTextScaler();

  @override
  double scale(double fontSize) {
    return fontSize < 20 ? fontSize * 2 : fontSize * 1.5;
  }

  @override
  double get textScaleFactor => 2;
}

AppAccessibilityPreferences _preferences({
  AccessibilityContrastPreference contrast =
      AccessibilityContrastPreference.system,
  AccessibilityColorPreference color = AccessibilityColorPreference.system,
  AccessibilityMotionPreference motion = AccessibilityMotionPreference.system,
  AccessibilityTextSizePreference textSize =
      AccessibilityTextSizePreference.system,
  AccessibilityTogglePreference differentiateWithoutColor =
      AccessibilityTogglePreference.system,
  AccessibilityTogglePreference underlineLinks =
      AccessibilityTogglePreference.system,
  AccessibilityTogglePreference strongFocusIndicators =
      AccessibilityTogglePreference.system,
  AccessibilityTogglePreference showOnOffLabels =
      AccessibilityTogglePreference.system,
  AccessibilityTogglePreference boldText = AccessibilityTogglePreference.system,
  AccessibilityTogglePreference reduceTransparency =
      AccessibilityTogglePreference.system,
  AccessibilityTogglePreference increaseUiSeparation =
      AccessibilityTogglePreference.system,
  AccessibilityTogglePreference pauseAnimatedMedia =
      AccessibilityTogglePreference.system,
  AccessibilityTogglePreference largerTouchTargets =
      AccessibilityTogglePreference.system,
  AccessibilityTogglePreference persistentActionLabels =
      AccessibilityTogglePreference.system,
}) {
  return AppAccessibilityPreferences(
    contrast: contrast,
    color: color,
    motion: motion,
    textSize: textSize,
    differentiateWithoutColor: differentiateWithoutColor,
    underlineLinks: underlineLinks,
    strongFocusIndicators: strongFocusIndicators,
    showOnOffLabels: showOnOffLabels,
    boldText: boldText,
    reduceTransparency: reduceTransparency,
    increaseUiSeparation: increaseUiSeparation,
    pauseAnimatedMedia: pauseAnimatedMedia,
    largerTouchTargets: largerTouchTargets,
    persistentActionLabels: persistentActionLabels,
  );
}
