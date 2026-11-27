import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:flutter/material.dart';

import 'account_deletion_handoff.dart';
import 'account_recovery_panel.dart';
import 'demo_security_tab.dart';
import 'matrix/matrix_security_tab.dart';

class SecuritySettingsTab extends StatelessWidget {
  const SecuritySettingsTab({required this.clientManager, super.key});
  final ClientManager clientManager;

  @override
  Widget build(BuildContext context) {
    final selectedClient = SettingsAccountScope.selectedClientOf(
      context,
      clientManager,
    );

    if (selectedClient == null) {
      return SettingsSection(
        title: 'Account security',
        showDivider: false,
        children: const [
          SettingsControlRow(
            title: 'No account selected',
            description:
                'Sign in to manage password, recovery, encryption, and session security settings.',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pickSecurityPage(selectedClient),
        SettingsSection(
          title: "Account Deletion",
          showDivider: false,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: AccountDeletionHandoffPanel(client: selectedClient),
            ),
          ],
        ),
      ],
    );
  }

  Widget pickSecurityPage(Client client) {
    if (client is MatrixClient) {
      return MatrixSecurityTab(
        client,
        key: client.key,
        accountRecoveryControls: AccountRecoverySettingsSection(
          client: client,
          includeSection: false,
          usePanel: false,
        ),
      );
    }

    if (client is DemoClient) {
      return DemoSecuritySettingsTab(client);
    }

    return SettingsSection(
      title: 'Cross Signing & Backup',
      children: const [
        SettingsControlRow(
          title: 'Security tools unavailable',
          description:
              'This account type does not expose Matrix security controls in Inter Galactic.',
        ),
      ],
    );
  }
}
