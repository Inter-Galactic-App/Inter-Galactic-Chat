import 'dart:async';

import 'package:intergalactic/client/components/voip/voip_component.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/account_state/account_state_tab.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/notification_settings/notification_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/voip_settings/voip_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/developer/developer_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/developer/log_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key});

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  StreamSubscription? _preferencesSub;

  String get labelSettingsDeveloperMode => Intl.message("Developer mode",
      desc: "Header for the settings to enable developer mode",
      name: "labelSettingsDeveloperMode");

  String get labelSettingsDeveloperModeExplanation =>
      Intl.message("Shows extra information, useful for developers",
          desc: "Explains what developer mode does",
          name: "labelSettingsDeveloperModeExplanation");

  @override
  void initState() {
    super.initState();
    _preferencesSub = preferences.onSettingChanged.listen((event) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _preferencesSub?.cancel();
    super.dispose();
  }

  bool get _hasVoipSettings =>
      clientManager?.clients
          .any((client) => client.getComponent<VoipComponent>() != null) ==
      true;

  bool get _showVoipDeveloperSettings =>
      preferences.developerMode.value && _hasVoipSettings;

  bool get _showDeveloperContent => preferences.developerMode.value;

  bool get _hasAccounts => clientManager?.clients.isNotEmpty == true;

  String get labelSettingsVoiceAndVideoDeveloper =>
      Intl.message("Voice and Video Developer Settings",
          desc: "Header for the moved voice/video developer settings",
          name: "labelSettingsVoiceAndVideoDeveloper");

  String get labelSettingsVoiceAndVideoDeveloperDescription => Intl.message(
      "Advanced call connection, diagnostics, and stream override controls.",
      desc: "Explanation for developer-only voice and video settings",
      name: "labelSettingsVoiceAndVideoDeveloperDescription");

  @override
  Widget build(BuildContext context) {
    final developerPanels = <Widget>[
      _DeveloperExpansionCard(
        icon: Icons.text_snippet_outlined,
        title: 'Logs',
        description:
            'View, copy, clear, open, and save diagnostic runtime logs.',
        child: const SizedBox(
          height: 540,
          child: LogPage(),
        ),
      ),
      if (_hasAccounts)
        _DeveloperExpansionCard(
          icon: Icons.data_object_rounded,
          title: 'Account state JSON',
          description:
              'Inspect the selected account state payload for debugging.',
          child: AccountStateTab(clientManager: clientManager!),
        ),
      _DeveloperExpansionCard(
        icon: Icons.notifications_outlined,
        title: 'Notification Developer Settings',
        description:
            'Push transport, gateway, and registered pusher diagnostics.',
        child: const NotificationDeveloperSettings(),
      ),
      if (_showVoipDeveloperSettings)
        _DeveloperExpansionCard(
          icon: Icons.call_outlined,
          title: labelSettingsVoiceAndVideoDeveloper,
          description: labelSettingsVoiceAndVideoDeveloperDescription,
          child: const VoipDeveloperSettings(),
        ),
      const _DeveloperExpansionCard(
        icon: Icons.bug_report_outlined,
        title: 'Developer Utils',
        description:
            'Manual diagnostics, stress tools, test notifications, window sizing, and debug-only utilities.',
        child: DeveloperSettingsPage(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: labelSettingsDeveloperMode,
          children: [
            BooleanPreferenceToggle(
              preference: preferences.developerMode,
              title: labelSettingsDeveloperMode,
              description: labelSettingsDeveloperModeExplanation,
            ),
          ],
        ),
        if (_showDeveloperContent && developerPanels.isNotEmpty)
          SettingsSection(
            title: 'Developer tools',
            showDivider: false,
            children: developerPanels,
          ),
      ],
    );
  }
}

class _DeveloperExpansionCard extends StatelessWidget {
  const _DeveloperExpansionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.72),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExpansionTile(
            leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            title: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
            subtitle: Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [child],
          ),
        ),
      ),
    );
  }
}
