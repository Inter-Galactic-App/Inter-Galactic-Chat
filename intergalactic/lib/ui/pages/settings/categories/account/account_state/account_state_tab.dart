import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:flutter/material.dart';

class AccountStateTab extends StatelessWidget {
  const AccountStateTab(
      {required this.clientManager, this.selectedClientIndex = 0, super.key});
  final ClientManager clientManager;
  final int selectedClientIndex;

  @override
  Widget build(BuildContext context) {
    final selectedClient = SettingsAccountScope.selectedClientOf(
          context,
          clientManager,
        ) ??
        _indexedClient;

    if (selectedClient == null) {
      return const Text('No account selected');
    }

    return selectedClient.buildDebugInfo();
  }

  Client? get _indexedClient {
    final clients = clientManager.clients;
    if (clients.isEmpty) {
      return null;
    }
    if (selectedClientIndex >= 0 && selectedClientIndex < clients.length) {
      return clients[selectedClientIndex];
    }
    return clients.first;
  }
}
