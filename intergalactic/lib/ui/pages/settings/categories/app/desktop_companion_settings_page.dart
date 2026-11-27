import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intl/intl.dart';

class DesktopCompanionSettingsPage extends StatefulWidget {
  const DesktopCompanionSettingsPage({super.key});

  @override
  State<DesktopCompanionSettingsPage> createState() =>
      _DesktopCompanionSettingsPageState();
}

class _DesktopCompanionSettingsPageState
    extends State<DesktopCompanionSettingsPage> {
  static const _lightAvatar = 'app_icon_light_avatar';
  static const _darkAvatar = 'app_icon_dark_avatar';

  StreamSubscription<String>? _avatarSubscription;

  String get notificationCompanionTitle => Intl.message(
        'Notification Companion',
        name: 'notificationCompanionTitle',
        desc: 'Settings section title for the desktop notification companion.',
      );

  String get showCompanionLabel => Intl.message(
        'Show Companion',
        name: 'showCompanionLabel',
        desc: 'Toggle label for showing the desktop notification companion.',
      );

  String get showCompanionDescription => Intl.message(
        'Show an opt-in always-on-top desktop companion for approved message notifications.',
        name: 'showCompanionDescription',
        desc: 'Description for the desktop notification companion toggle.',
      );

  String get companionAvatarLabel => Intl.message(
        'Companion Avatar',
        name: 'companionAvatarLabel',
        desc:
            'Settings row title for choosing the notification companion avatar.',
      );

  String get companionAvatarDescription => Intl.message(
        'Choose the companion avatar shown while no notification is active.',
        name: 'companionAvatarDescription',
        desc: 'Settings row description for choosing the companion avatar.',
      );

  String get companionAvatarLightLabel => Intl.message(
        'Light',
        name: 'companionAvatarLightLabel',
        desc: 'Label for the light notification companion avatar.',
      );

  String get companionAvatarDarkLabel => Intl.message(
        'Dark',
        name: 'companionAvatarDarkLabel',
        desc: 'Label for the dark notification companion avatar.',
      );

  String get behaviorSectionTitle => Intl.message(
        'Behavior',
        name: 'behaviorSectionTitle',
        desc: 'Settings section title for notification companion behavior.',
      );

  String get showPreviewsLabel => Intl.message(
        'Show Companion Previews',
        name: 'showPreviewsLabel',
        desc: 'Toggle label for showing message previews in the companion.',
      );

  String get showPreviewsDescription => Intl.message(
        'Show message body text in the companion when previews are allowed.',
        name: 'showPreviewsDescription',
        desc: 'Description for companion message preview behavior.',
      );

  String get hidePreviewsWhileSharingLabel => Intl.message(
        'Hide Previews While Sharing',
        name: 'hidePreviewsWhileSharingLabel',
        desc:
            'Toggle label for hiding companion previews during screen sharing.',
      );

  String get hidePreviewsWhileSharingDescription => Intl.message(
        'Use a generic new-message state while a local screen share is active.',
        name: 'hidePreviewsWhileSharingDescription',
        desc:
            'Description for hiding companion previews during screen sharing.',
      );

  String get clickToOpenLabel => Intl.message(
        'Click Companion to Open Room',
        name: 'clickToOpenLabel',
        desc:
            'Toggle label for opening the latest notification room from the companion.',
      );

  String get clickToOpenDescription => Intl.message(
        'Open the room for the latest companion notification when clicked.',
        name: 'clickToOpenDescription',
        desc: 'Description for companion click-to-open behavior.',
      );

  String get reducedMotionLabel => Intl.message(
        'Reduced Companion Motion',
        name: 'reducedMotionLabel',
        desc: 'Toggle label for reducing notification companion motion.',
      );

  String get reducedMotionDescription => Intl.message(
        'Disable idle movement and message transition motion in the companion.',
        name: 'reducedMotionDescription',
        desc: 'Description for reduced companion motion behavior.',
      );

  @override
  void initState() {
    super.initState();
    _avatarSubscription =
        preferences.notificationCompanionAvatarVariant.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _avatarSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final companionEnabled = preferences.notificationCompanionEnabled.value;

    return Column(
      children: [
        SettingsSection(
          title: notificationCompanionTitle,
          children: [
            BooleanPreferenceToggle(
              preference: preferences.notificationCompanionEnabled,
              title: showCompanionLabel,
              description: showCompanionDescription,
              onChanged: (_) async => setState(() {}),
            ),
            AnimatedOpacity(
              opacity: companionEnabled ? 1 : 0.36,
              duration: Durations.short4,
              child: IgnorePointer(
                ignoring: !companionEnabled,
                child: SettingsControlRow(
                  title: companionAvatarLabel,
                  description: companionAvatarDescription,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _CompanionAvatarOption(
                        label: companionAvatarLightLabel,
                        value: _lightAvatar,
                        assetPath:
                            'assets/images/notification_companion/app_icon_light_avatar.png',
                        selected: _selectedAvatar == _lightAvatar,
                        onSelected: _setAvatarVariant,
                      ),
                      _CompanionAvatarOption(
                        label: companionAvatarDarkLabel,
                        value: _darkAvatar,
                        assetPath:
                            'assets/images/notification_companion/app_icon_dark_avatar.png',
                        selected: _selectedAvatar == _darkAvatar,
                        onSelected: _setAvatarVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedOpacity(
          opacity: companionEnabled ? 1 : 0.36,
          duration: Durations.short4,
          child: IgnorePointer(
            ignoring: !companionEnabled,
            child: SettingsSection(
              title: behaviorSectionTitle,
              showDivider: false,
              children: [
                BooleanPreferenceToggle(
                  preference: preferences.notificationCompanionShowPreviews,
                  title: showPreviewsLabel,
                  description: showPreviewsDescription,
                  onChanged: (_) => _markNotificationPreviewCustom(),
                ),
                BooleanPreferenceToggle(
                  preference: preferences
                      .notificationCompanionHidePreviewsWhileScreenSharing,
                  title: hidePreviewsWhileSharingLabel,
                  description: hidePreviewsWhileSharingDescription,
                ),
                BooleanPreferenceToggle(
                  preference: preferences.notificationCompanionClickToOpen,
                  title: clickToOpenLabel,
                  description: clickToOpenDescription,
                ),
                BooleanPreferenceToggle(
                  preference: preferences.notificationCompanionReducedMotion,
                  title: reducedMotionLabel,
                  description: reducedMotionDescription,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String get _selectedAvatar =>
      preferences.notificationCompanionAvatarVariant.value == _darkAvatar
          ? _darkAvatar
          : _lightAvatar;

  Future<void> _setAvatarVariant(String value) async {
    await preferences.notificationCompanionAvatarVariant.set(value);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _markNotificationPreviewCustom() async {
    if (preferences.notificationPreviewPrivacyChoiceValue.value ==
        Preferences.notificationPreviewPrivacyChoiceCustom) {
      return;
    }

    await preferences.applyNotificationPreviewPrivacyChoice(
      Preferences.notificationPreviewPrivacyChoiceCustom,
    );
    if (mounted) {
      setState(() {});
    }
  }
}

class _CompanionAvatarOption extends StatelessWidget {
  const _CompanionAvatarOption({
    required this.label,
    required this.value,
    required this.assetPath,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String assetPath;
  final bool selected;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => unawaited(onSelected(value)),
        child: Container(
          width: 178,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.72),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.7,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    color: theme.colorScheme.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: Image.asset(
                      assetPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
