import 'package:flutter/material.dart' hide Text;
import 'package:intergalactic/client/account_recovery/account_recovery_api_client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/account_recovery_panel.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AccountRecoveryEnrollmentPrompt {
  const AccountRecoveryEnrollmentPrompt._();

  static Future<void> maybeShow(
    BuildContext context, {
    required MatrixClient client,
    AccountRecoveryApiClient? apiClient,
    bool force = false,
  }) async {
    if (!AccountRecoveryEligibility.isLocalMatrixClient(client)) {
      return;
    }

    final promptKey = AccountRecoveryEligibility.promptPreferenceKey(client);
    if (!force && preferences.isAccountRecoveryPromptDismissed(promptKey)) {
      return;
    }

    final api = apiClient ?? AccountRecoveryApiClient();
    final ownsApi = apiClient == null;
    late final AccountRecoveryStatus status;
    try {
      status = await api.getStatus(client: client);
    } catch (_) {
      if (ownsApi) {
        api.close();
      }
      return;
    }

    if (status.recoveryCodes.enrolled) {
      await preferences.setAccountRecoveryPromptDismissed(promptKey, true);
      if (ownsApi) {
        api.close();
      }
      return;
    }

    final result = await AdaptiveDialog.show<_PromptResult>(
      context,
      title: 'Set up account recovery',
      scrollable: true,
      builder: (_) => _AccountRecoveryPromptBody(
        client: client,
        apiClient: api,
        initialStatus: status,
      ),
    );

    if (result == null ||
        result == _PromptResult.dismissed ||
        result == _PromptResult.setUp) {
      await preferences.setAccountRecoveryPromptDismissed(promptKey, true);
    }

    if (ownsApi) {
      api.close();
    }
  }
}

class _AccountRecoveryPromptBody extends StatelessWidget {
  const _AccountRecoveryPromptBody({
    required this.client,
    required this.apiClient,
    required this.initialStatus,
  });

  final MatrixClient client;
  final AccountRecoveryApiClient apiClient;
  final AccountRecoveryStatus initialStatus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.label(
            'This ourgalaxy.space account does not have recovery codes yet. Recovery codes can reset your account password if you forget it; they do not replace your Matrix encrypted history recovery key.',
            softwrap: true,
          ),
          const SizedBox(height: 12),
          tiamat.Text.labelLow(
            'Inter Galactic will show generated codes only once. Save them somewhere private.',
            softwrap: true,
          ),
          const SizedBox(height: 16),
          tiamat.Button(
            text: 'Set up recovery codes',
            onTap: () async {
              final changed = await AccountRecoveryManagementDialog.show(
                context,
                client: client,
                apiClient: apiClient,
                initialStatus: initialStatus,
              );
              if (context.mounted) {
                Navigator.of(context).pop(
                  changed == true
                      ? _PromptResult.setUp
                      : _PromptResult.dismissed,
                );
              }
            },
          ),
          const SizedBox(height: 8),
          tiamat.Button.secondary(
            text: CommonStrings.promptPoliteNo,
            onTap: () => Navigator.of(context).pop(_PromptResult.dismissed),
          ),
        ],
      ),
    );
  }
}

enum _PromptResult { dismissed, setUp }
