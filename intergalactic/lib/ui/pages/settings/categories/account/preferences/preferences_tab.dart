import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/preferences/preferences_chat_privacy.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/preferences/preferences_dm_lock.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:flutter/material.dart';

class AccountSettingsTab extends StatelessWidget {
  const AccountSettingsTab({required this.clientManager, super.key});
  final ClientManager clientManager;

  @override
  Widget build(BuildContext context) {
    final selectedClient = SettingsAccountScope.selectedClientOf(
      context,
      clientManager,
    );

    if (selectedClient == null) {
      return const Text('No account selected');
    }

    return Column(
      children: [
        ChatPrivacyPreferences(
            client: selectedClient,
            key: ValueKey(
                "chat-privacy-preferences_${selectedClient.identifier}")),
        const SizedBox(height: 8),
        DmLockPreferences(
            client: selectedClient,
            key: ValueKey("dm-lock-preferences_${selectedClient.identifier}")),
      ],
    );
  }
}
