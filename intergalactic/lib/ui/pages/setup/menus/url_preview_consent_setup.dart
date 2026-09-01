import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/setup/setup_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UrlPreviewConsentSetup implements SetupMenu {
  final StreamController<SetupMenuState> _controller =
      StreamController<SetupMenuState>.broadcast();

  @override
  Widget builder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.largeTitle('Encrypted chat URL previews'),
        const SizedBox(height: 8),
        tiamat.Text.label(
          'Choose whether Inter Galactic can fetch link previews for encrypted chats on this device.',
        ),
        const SizedBox(height: 16),
        const UrlPreviewE2EEConsentChoice(),
      ],
    );
  }

  @override
  Stream<SetupMenuState> get onStateChanged => _controller.stream;

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  @override
  Future<void> submit() async {
    if (preferences.urlPreviewInE2EEChatConsentCompleted.value) {
      return;
    }

    await preferences.applyUrlPreviewE2EEConsentChoice(allow: false);
  }
}

class UrlPreviewE2EEConsentChoice extends StatefulWidget {
  const UrlPreviewE2EEConsentChoice({
    super.key,
  });

  @override
  State<UrlPreviewE2EEConsentChoice> createState() =>
      _UrlPreviewE2EEConsentChoiceState();
}

class _UrlPreviewE2EEConsentChoiceState
    extends State<UrlPreviewE2EEConsentChoice> {
  bool _isApplying = false;

  bool get _allowPreviews => preferences.urlPreviewInE2EEChat.value;

  Future<void> _choose(bool allow) async {
    if (_isApplying) {
      return;
    }

    setState(() {
      _isApplying = true;
    });

    try {
      await preferences.applyUrlPreviewE2EEConsentChoice(allow: allow);
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
    return RadioGroup<bool>(
      groupValue: _allowPreviews,
      onChanged: (value) {
        if (value != null && !_isApplying) {
          unawaited(_choose(value));
        }
      },
      child: Column(
        children: [
          _UrlPreviewConsentOption(
            value: false,
            groupValue: _allowPreviews,
            icon: Icons.visibility_off_outlined,
            title: 'Keep previews off',
            description:
                'Do not fetch URL previews in encrypted chats unless you turn them on later.',
            enabled: !_isApplying,
            onChanged: _choose,
          ),
          const SizedBox(height: 8),
          _UrlPreviewConsentOption(
            value: true,
            groupValue: _allowPreviews,
            icon: Icons.link_outlined,
            title: 'Allow encrypted previews',
            description:
                'Fetch previews using your homeserver, configured preview service, or supported provider fallback.',
            enabled: !_isApplying,
            onChanged: _choose,
          ),
        ],
      ),
    );
  }
}

class _UrlPreviewConsentOption extends StatelessWidget {
  const _UrlPreviewConsentOption({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool groupValue;
  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final Future<void> Function(bool value) onChanged;

  bool get isSelected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground =
        isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: 0.64);

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
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
              Radio<bool>(
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
