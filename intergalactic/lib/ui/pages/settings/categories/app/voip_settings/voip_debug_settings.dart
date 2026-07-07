import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/voip_settings/voip_debug_matrix_client.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:flutter/material.dart';

class VoipDebugSettings extends StatelessWidget {
  const VoipDebugSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = clientManager;
    final selectedClient = manager == null
        ? null
        : SettingsAccountScope.selectedClientOf(context, manager);

    return Column(
      children: [
        if (selectedClient is MatrixClient)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: VoipDebugMatrixClient(
              selectedClient,
              key: ValueKey(selectedClient.identifier),
            ),
          )
      ],
    );
  }
}
