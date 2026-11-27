import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/accessibility/accessibility_preferences.dart';
import 'package:intergalactic/ui/accessibility/accessibility_resolver.dart';
import 'package:intergalactic/ui/accessibility/accessibility_tokens.dart';

class AccessibilityScope extends StatefulWidget {
  const AccessibilityScope({
    required this.preferences,
    required this.child,
    super.key,
  });

  final Preferences preferences;
  final Widget child;

  static EffectiveAccessibilitySettings of(BuildContext context) {
    final data =
        context.dependOnInheritedWidgetOfExactType<_AccessibilityData>();
    if (data != null) {
      return data.settings;
    }

    return EffectiveAccessibilitySettings.resolve(
      preferences: const AppAccessibilityPreferences(
        contrast: AccessibilityContrastPreference.system,
        color: AccessibilityColorPreference.system,
        motion: AccessibilityMotionPreference.system,
        textSize: AccessibilityTextSizePreference.system,
        differentiateWithoutColor: AccessibilityTogglePreference.system,
        underlineLinks: AccessibilityTogglePreference.system,
        strongFocusIndicators: AccessibilityTogglePreference.system,
        showOnOffLabels: AccessibilityTogglePreference.system,
        boldText: AccessibilityTogglePreference.system,
        reduceTransparency: AccessibilityTogglePreference.system,
        increaseUiSeparation: AccessibilityTogglePreference.system,
        pauseAnimatedMedia: AccessibilityTogglePreference.system,
        largerTouchTargets: AccessibilityTogglePreference.system,
        persistentActionLabels: AccessibilityTogglePreference.system,
      ),
      platform: AccessibilityPlatformSignals.fromContext(context),
    );
  }

  static EffectiveAccessibilitySettings? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AccessibilityData>()
        ?.settings;
  }

  static AccessibilityTokens tokensOf(BuildContext context) {
    final data =
        context.dependOnInheritedWidgetOfExactType<_AccessibilityData>();
    return data?.tokens ?? AccessibilityTokens.from(context, of(context));
  }

  @override
  State<AccessibilityScope> createState() => _AccessibilityScopeState();
}

class _AccessibilityScopeState extends State<AccessibilityScope> {
  StreamSubscription? _preferenceSubscription;
  EffectiveAccessibilitySettings? _settings;
  AccessibilityTokens? _tokens;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant AccessibilityScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.preferences, widget.preferences)) {
      return;
    }

    _preferenceSubscription?.cancel();
    _subscribe();
  }

  @override
  void dispose() {
    _preferenceSubscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _preferenceSubscription = widget.preferences.onSettingChanged.listen((_) {
      if (!mounted) {
        return;
      }

      final state = _resolve(context);
      if (state.settings == _settings && state.tokens == _tokens) {
        return;
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final state = _resolve(context);
    final settings = state.settings;
    final tokens = state.tokens;
    _settings = settings;
    _tokens = tokens;
    final child = mediaQuery == null
        ? widget.child
        : MediaQuery(
            data: mediaQuery.copyWith(
              boldText: settings.boldText,
              highContrast: settings.highContrast,
              disableAnimations: settings.disableAnimations,
              textScaler: settings.textScaler,
            ),
            child: widget.child,
          );

    return _AccessibilityData(
      settings: settings,
      tokens: tokens,
      child: child,
    );
  }

  _ResolvedAccessibilityState _resolve(BuildContext context) {
    final accessibilityPreferences =
        AppAccessibilityPreferences.fromPreferences(widget.preferences);
    final platform = AccessibilityPlatformSignals.fromContext(context);
    final settings = EffectiveAccessibilitySettings.resolve(
      preferences: accessibilityPreferences,
      platform: platform,
      legacyTextScale: widget.preferences.textScale.value,
    );
    return _ResolvedAccessibilityState(
      settings: settings,
      tokens: AccessibilityTokens.from(context, settings),
    );
  }
}

class _ResolvedAccessibilityState {
  const _ResolvedAccessibilityState({
    required this.settings,
    required this.tokens,
  });

  final EffectiveAccessibilitySettings settings;
  final AccessibilityTokens tokens;
}

class _AccessibilityData extends InheritedWidget {
  const _AccessibilityData({
    required this.settings,
    required this.tokens,
    required super.child,
  });

  final EffectiveAccessibilitySettings settings;
  final AccessibilityTokens tokens;

  @override
  bool updateShouldNotify(covariant _AccessibilityData oldWidget) {
    return settings != oldWidget.settings || tokens != oldWidget.tokens;
  }
}
