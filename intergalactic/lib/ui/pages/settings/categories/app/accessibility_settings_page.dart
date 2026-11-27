import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/config/preferences/string_preference.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessibility_preferences.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/accessibility/accessibility_tokens.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AccessibilitySettingsPage extends StatefulWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  State<AccessibilitySettingsPage> createState() =>
      _AccessibilitySettingsPageState();
}

class _AccessibilitySettingsPageState extends State<AccessibilitySettingsPage> {
  StreamSubscription? _preferenceSubscription;

  String get labelAccessibilityPresets => Intl.message(
        "Recommended presets",
        name: "labelAccessibilityPresets",
        desc: "Section title for accessibility preset controls",
      );

  String get labelAccessibilityVision => Intl.message(
        "Vision",
        name: "labelAccessibilityVision",
        desc: "Section title for accessibility vision controls",
      );

  String get labelAccessibilityText => Intl.message(
        "Text and readability",
        name: "labelAccessibilityText",
        desc: "Section title for accessibility text controls",
      );

  String get labelAccessibilityMotion => Intl.message(
        "Motion and media",
        name: "labelAccessibilityMotion",
        desc: "Section title for accessibility motion controls",
      );

  String get labelAccessibilityInput => Intl.message(
        "Input",
        name: "labelAccessibilityInput",
        desc: "Section title for accessibility input controls",
      );

  String get labelAccessibilityPreview => Intl.message(
        "Live preview",
        name: "labelAccessibilityPreview",
        desc: "Section title for accessibility preview controls",
      );

  @override
  void initState() {
    super.initState();
    _preferenceSubscription = preferences.onSettingChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _preferenceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsSection(
          title: labelAccessibilityPresets,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _AccessibilityPresetGrid(
                onSystem: () async {
                  await AppAccessibilityPreferences.resetToSystemDefaults(
                    preferences,
                  );
                },
                onColorSafe: () async {
                  await preferences.accessibilityColor
                      .set(AccessibilityColorPreference.colorSafe.value);
                  await preferences.accessibilityDifferentiateWithoutColor
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityUnderlineLinks
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityShowOnOffLabels
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityStrongFocusIndicators
                      .set(AccessibilityTogglePreference.on.value);
                },
                onHighContrast: () async {
                  await preferences.accessibilityContrast
                      .set(AccessibilityContrastPreference.high.value);
                  await preferences.accessibilityDifferentiateWithoutColor
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityStrongFocusIndicators
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityReduceTransparency
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityIncreaseUiSeparation
                      .set(AccessibilityTogglePreference.on.value);
                },
                onLowMotion: () async {
                  await preferences.accessibilityMotion
                      .set(AccessibilityMotionPreference.reduced.value);
                  await preferences.accessibilityPauseAnimatedMedia
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityReduceTransparency
                      .set(AccessibilityTogglePreference.on.value);
                },
                onReadableText: () async {
                  await preferences.accessibilityTextSize
                      .set(AccessibilityTextSizePreference.large.value);
                  await preferences.accessibilityBoldText
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityPersistentActionLabels
                      .set(AccessibilityTogglePreference.on.value);
                  await preferences.accessibilityLargerTouchTargets
                      .set(AccessibilityTogglePreference.on.value);
                },
              ),
            ),
          ],
        ),
        SettingsSection(
          title: labelAccessibilityVision,
          children: [
            _PreferenceDropdown<AccessibilityContrastPreference>(
              preference: preferences.accessibilityContrast,
              title: "Contrast",
              description:
                  "Follow system contrast or increase contrast for text, controls, and state indicators.",
              values: AccessibilityContrastPreference.values,
              fromValue: AccessibilityContrastPreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityColorPreference>(
              preference: preferences.accessibilityColor,
              title: "Color mode",
              description:
                  "Use a color-safe semantic palette that avoids red/green-only status meaning.",
              values: AccessibilityColorPreference.values,
              fromValue: AccessibilityColorPreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityDifferentiateWithoutColor,
              title: "Differentiate without color",
              description:
                  "Add icon, shape, and text cues so status and alerts do not depend on color alone.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityUnderlineLinks,
              title: "Underline links",
              description:
                  "Keep links recognizable when color alone is not enough.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityStrongFocusIndicators,
              title: "Strong focus indicators",
              description:
                  "Use a higher-contrast focus ring for keyboard and switch navigation.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityShowOnOffLabels,
              title: "Show On/Off labels",
              description:
                  "Display switch state with text instead of relying on position or color.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityReduceTransparency,
              title: "Reduce transparency",
              description:
                  "Prefer solid surfaces over translucent, glass, and blurred layers.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityIncreaseUiSeparation,
              title: "Increase UI separation",
              description:
                  "Strengthen borders and dividers around controls and grouped surfaces.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
          ],
        ),
        SettingsSection(
          title: labelAccessibilityText,
          children: [
            _PreferenceDropdown<AccessibilityTextSizePreference>(
              preference: preferences.accessibilityTextSize,
              title: "Text size",
              description:
                  "Combine platform text scaling with an Inter Galactic readability preset.",
              values: AccessibilityTextSizePreference.values,
              fromValue: AccessibilityTextSizePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityBoldText,
              title: "Bold text",
              description:
                  "Follow the system bold-text request or force heavier text in the app.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityPersistentActionLabels,
              title: "Persistent action labels",
              description:
                  "Show labels beside important icon-only actions where shared components support it.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
          ],
        ),
        SettingsSection(
          title: labelAccessibilityMotion,
          children: [
            _PreferenceDropdown<AccessibilityMotionPreference>(
              preference: preferences.accessibilityMotion,
              title: "Motion",
              description:
                  "Follow system reduced motion or reduce decorative movement in app components.",
              values: AccessibilityMotionPreference.values,
              fromValue: AccessibilityMotionPreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityPauseAnimatedMedia,
              title: "Pause animated media",
              description:
                  "Stop autoplaying animated media where Inter Galactic controls playback.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
          ],
        ),
        SettingsSection(
          title: labelAccessibilityInput,
          children: [
            _PreferenceDropdown<AccessibilityTogglePreference>(
              preference: preferences.accessibilityLargerTouchTargets,
              title: "Larger touch targets",
              description:
                  "Use roomier targets for shared controls that opt into accessibility density.",
              values: AccessibilityTogglePreference.values,
              fromValue: AccessibilityTogglePreference.from,
              toValue: (value) => value.value,
              labelFor: (value) => value.label,
            ),
          ],
        ),
        SettingsSection(
          title: labelAccessibilityPreview,
          showDivider: false,
          children: const [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _AccessibilityPreview(),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccessibilityPresetGrid extends StatelessWidget {
  const _AccessibilityPresetGrid({
    required this.onSystem,
    required this.onColorSafe,
    required this.onHighContrast,
    required this.onLowMotion,
    required this.onReadableText,
  });

  final Future<void> Function() onSystem;
  final Future<void> Function() onColorSafe;
  final Future<void> Function() onHighContrast;
  final Future<void> Function() onLowMotion;
  final Future<void> Function() onReadableText;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _PresetButton(
          icon: Icons.settings_suggest_rounded,
          label: "Follow system",
          onPressed: onSystem,
        ),
        _PresetButton(
          icon: Icons.visibility_rounded,
          label: "Color-safe",
          onPressed: onColorSafe,
        ),
        _PresetButton(
          icon: Icons.contrast_rounded,
          label: "High contrast",
          onPressed: onHighContrast,
        ),
        _PresetButton(
          icon: Icons.motion_photos_pause_rounded,
          label: "Low motion",
          onPressed: onLowMotion,
        ),
        _PresetButton(
          icon: Icons.format_size_rounded,
          label: "Readable text",
          onPressed: onReadableText,
        ),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

class _PreferenceDropdown<T extends Object> extends StatelessWidget {
  const _PreferenceDropdown({
    required this.preference,
    required this.title,
    required this.description,
    required this.values,
    required this.fromValue,
    required this.toValue,
    required this.labelFor,
  });

  final StringPreference preference;
  final String title;
  final String description;
  final List<T> values;
  final T Function(String value) fromValue;
  final String Function(T value) toValue;
  final String Function(T value) labelFor;

  @override
  Widget build(BuildContext context) {
    return SettingsControlRow(
      title: title,
      description: description,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240, minWidth: 180),
        child: tiamat.DropdownSelector<T>(
          value: fromValue(preference.value),
          items: values,
          itemBuilder: (value) => Text(labelFor(value)),
          onItemSelected: (value) async {
            if (value == null) {
              return;
            }

            await preference.set(toValue(value));
          },
        ),
      ),
    );
  }
}

class _AccessibilityPreview extends StatelessWidget {
  const _AccessibilityPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AccessibilityScope.of(context);
    final tokens = AccessibilityScope.tokensOf(context);
    final previewBorder = settings.strongerVisualBoundaries
        ? tokens.strongBoundary
        : theme.colorScheme.outlineVariant;

    return Semantics(
      label:
          "Accessibility preview showing message, status, call, story, link, and error states",
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: settings.reduceTransparency
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: previewBorder, width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreviewMessage(tokens: tokens),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PreviewStatus(
                    icon: settings.nonColorStateCues
                        ? Icons.check_circle_rounded
                        : Icons.circle,
                    label: "Online",
                    color: tokens.statusOnline,
                  ),
                  _PreviewStatus(
                    icon: settings.nonColorStateCues
                        ? Icons.schedule_rounded
                        : Icons.circle,
                    label: "Busy",
                    color: tokens.statusBusy,
                  ),
                  _PreviewStatus(
                    icon: settings.nonColorStateCues
                        ? Icons.radio_button_unchecked_rounded
                        : Icons.circle,
                    label: "Offline",
                    color: tokens.statusOffline,
                  ),
                  _PreviewStatus(
                    icon: settings.nonColorStateCues
                        ? Icons.help_outline_rounded
                        : Icons.circle,
                    label: "Unknown",
                    color: tokens.statusUnknown,
                  ),
                  _PreviewStoryState(tokens: tokens),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PreviewAction(
                    icon: Icons.mic_off_rounded,
                    label: "Muted",
                    selected: true,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.videocam_rounded,
                    label: settings.persistentActionLabels ? "Camera" : null,
                    selected: false,
                    tokens: tokens,
                    semanticLabel: "Camera on",
                  ),
                  _PreviewAction(
                    icon: Icons.ios_share_rounded,
                    label: settings.persistentActionLabels ? "Share" : null,
                    selected: false,
                    tokens: tokens,
                    semanticLabel: "Screen share",
                  ),
                  _PreviewAction(
                    icon: Icons.title_rounded,
                    label: "Story text",
                    selected: false,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.play_circle_outline_rounded,
                    label: "Video",
                    selected: false,
                    tokens: tokens,
                    semanticLabel: "Video preview control",
                  ),
                  _PreviewAction(
                    icon: Icons.emoji_emotions_rounded,
                    label: "Sticker",
                    selected: false,
                    tokens: tokens,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PreviewAction(
                    icon: Icons.settings_rounded,
                    label: "Settings",
                    selected: false,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.person_add_alt_1_rounded,
                    label: "Invite",
                    selected: false,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.push_pin_rounded,
                    label: "Pins",
                    selected: false,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.search_rounded,
                    label: "Search",
                    selected: false,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.add_rounded,
                    label: "Add",
                    selected: false,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.palette_rounded,
                    label: "Color",
                    selected: false,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.open_in_new_rounded,
                    label: "Popout",
                    selected: false,
                    tokens: tokens,
                  ),
                  _PreviewAction(
                    icon: Icons.keyboard_rounded,
                    label: "PgDn",
                    selected: false,
                    tokens: tokens,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: "Links remain visible: "),
                    TextSpan(
                      text: "intergalactic.chat",
                      style: TextStyle(
                        color: tokens.linkText,
                        decoration: settings.underlineLinks
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _PreviewAlert(tokens: tokens),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.tokens});

  final AccessibilityTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AccessibilityScope.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: settings.strongerVisualBoundaries
              ? tokens.strongBoundary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: tokens.success,
              child: Text(
                "N",
                style: TextStyle(color: tokens.onSuccess),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Nick",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight:
                          settings.boldText ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                      "Message sent. Delivery state uses text and icon."),
                ],
              ),
            ),
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: tokens.success,
              semanticLabel: "Sent",
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Chip(
        avatar: Icon(icon, color: color, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _PreviewStoryState extends StatelessWidget {
  const _PreviewStoryState({required this.tokens});

  final AccessibilityTokens tokens;

  @override
  Widget build(BuildContext context) {
    final settings = AccessibilityScope.of(context);

    return Semantics(
      label: "Unseen story",
      child: Chip(
        avatar: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: tokens.storyUnseen,
              width: 2,
            ),
          ),
          child: SizedBox(
            width: 18,
            height: 18,
            child: settings.nonColorStateCues
                ? Icon(
                    Icons.auto_stories_rounded,
                    color: tokens.storyUnseen,
                    size: 13,
                  )
                : null,
          ),
        ),
        label: const Text("Story"),
      ),
    );
  }
}

class _PreviewAction extends StatelessWidget {
  const _PreviewAction({
    required this.icon,
    required this.selected,
    required this.tokens,
    this.label,
    this.semanticLabel,
  });

  final IconData icon;
  final String? label;
  final String? semanticLabel;
  final bool selected;
  final AccessibilityTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = semanticLabel ?? label ?? "Action";

    return Semantics(
      container: true,
      label: selected ? "$labelText, active preview sample" : labelText,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? tokens.danger.withValues(alpha: 0.16)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? tokens.danger : tokens.strongBoundary,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? tokens.danger : theme.colorScheme.onSurface,
                ),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(label!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewAlert extends StatelessWidget {
  const _PreviewAlert({required this.tokens});

  final AccessibilityTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: "Warning: encryption needs attention",
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.warning, width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(
                Icons.warning_rounded,
                color: tokens.warning,
                semanticLabel: "Warning",
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Warning states use an icon, border, and text.",
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
