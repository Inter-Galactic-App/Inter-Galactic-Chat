import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/main.dart';

class NotificationPreviewPrivacyChoice extends StatefulWidget {
  const NotificationPreviewPrivacyChoice({
    this.onChanged,
    super.key,
  });

  final FutureOr<void> Function(String value)? onChanged;

  @override
  State<NotificationPreviewPrivacyChoice> createState() =>
      _NotificationPreviewPrivacyChoiceState();
}

class _NotificationPreviewPrivacyChoiceState
    extends State<NotificationPreviewPrivacyChoice> {
  bool _isApplying = false;

  String get _selectedValue =>
      preferences.notificationPreviewPrivacyChoiceValue.value;

  Future<void> _choose(String value) async {
    if (_isApplying || value == _selectedValue) {
      return;
    }

    setState(() {
      _isApplying = true;
    });

    try {
      await preferences.applyNotificationPreviewPrivacyChoice(value);
      await widget.onChanged?.call(value);
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RadioGroup<String>(
      groupValue: _selectedValue,
      onChanged: (value) {
        if (value != null && !_isApplying) {
          unawaited(_choose(value));
        }
      },
      child: Column(
        children: [
          if (_selectedValue ==
              Preferences.notificationPreviewPrivacyChoiceCustom) ...[
            _NotificationPreviewPrivacyOption(
              value: Preferences.notificationPreviewPrivacyChoiceCustom,
              groupValue: _selectedValue,
              icon: Icons.tune,
              title: 'Custom settings',
              description:
                  'Use the detailed preview switches already set on this device.',
              enabled: !_isApplying,
              onChanged: _choose,
            ),
            const SizedBox(height: 8),
          ],
          _NotificationPreviewPrivacyOption(
            value: Preferences.notificationPreviewPrivacyChoicePrivate,
            groupValue: _selectedValue,
            icon: Icons.visibility_off_outlined,
            title: 'Private notifications',
            description:
                'Show generic message alerts and keep taps working without message, sender, room, media, URL, or companion previews.',
            enabled: !_isApplying,
            onChanged: _choose,
          ),
          const SizedBox(height: 8),
          _NotificationPreviewPrivacyOption(
            value: Preferences.notificationPreviewPrivacyChoiceRich,
            groupValue: _selectedValue,
            icon: Icons.chat_bubble_outline,
            title: 'Rich previews',
            description:
                'Show sender, room, message text, media, URL, and companion previews when the current device settings allow them.',
            enabled: !_isApplying,
            onChanged: _choose,
          ),
        ],
      ),
    );
  }
}

class _NotificationPreviewPrivacyOption extends StatelessWidget {
  const _NotificationPreviewPrivacyOption({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final String groupValue;
  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final Future<void> Function(String value) onChanged;

  bool get isSelected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground =
        isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: 0.64);
    final backgroundColor = isSelected
        ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.78)
        : theme.colorScheme.surfaceContainerLow;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => onChanged(value) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Radio<String>(
                value: value,
                enabled: enabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
