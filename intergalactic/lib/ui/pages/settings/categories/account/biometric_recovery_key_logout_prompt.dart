import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/matrix/biometric_recovery_key_store.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class BiometricRecoveryKeyLogoutPrompt {
  const BiometricRecoveryKeyLogoutPrompt._();

  static Future<bool> logoutClient({
    required BuildContext context,
    required ClientManager clientManager,
    required Client client,
    BiometricRecoveryKeyStore? store,
  }) async {
    if (client is! MatrixClient) {
      await clientManager.logoutClient(client);
      return true;
    }

    final resolvedStore = store ?? BiometricRecoveryKeyStore.instance;
    final status = await resolvedStore.statusForClientIncludingLegacy(client);
    if (!context.mounted) {
      return false;
    }

    String? failureMessage;
    final completed = await BiometricRecoveryKeyLogoutFlow.runForStatus(
      status: status,
      requestChoice: (status) {
        if (!context.mounted) {
          return Future.value(BiometricRecoveryKeyLogoutChoice.cancel);
        }
        return show(context: context, status: status);
      },
      ensureKeyPrepared: () =>
          resolvedStore.ensureAccountScopedCopyForLogout(client),
      deleteKey: () => resolvedStore.deleteForClientIncludingLegacy(client),
      logout: () => clientManager.logoutClient(client),
      onStorageFailure: (choice, error, __) {
        if (choice == BiometricRecoveryKeyLogoutChoice.keep) {
          failureMessage = error is BiometricRecoveryKeyStoreException
              ? error.message
              : 'Stored recovery key was not prepared for sign-in. Sign-out was cancelled.';
          return;
        }
        failureMessage =
            'Stored recovery key could not be deleted. Sign-out was cancelled.';
      },
    );

    if (failureMessage != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: tiamat.Text.body(failureMessage!, softwrap: true),
        ),
      );
    }

    return completed;
  }

  static Future<BiometricRecoveryKeyLogoutChoice?> show({
    required BuildContext context,
    required BiometricRecoveryKeyStatus status,
  }) {
    final canKeepStoredKey = status.canRead;
    return AdaptiveDialog.show<BiometricRecoveryKeyLogoutChoice>(
      context,
      title: 'Sign out of this account?',
      builder: (dialogContext) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              tiamat.Text.body(
                canKeepStoredKey
                    ? 'A Matrix recovery key is stored on this device behind ${status.promptLabel}. Keeping it lets you unlock recovery after signing back in, even if Matrix creates a new device session.'
                    : 'A Matrix recovery key is stored on this device, but it cannot currently be unlocked with ${status.promptLabel}. Delete it before signing out, or cancel and fix biometric access first.',
                softwrap: true,
              ),
              const SizedBox(height: 8),
              const tiamat.Text.body(
                'Delete it if this is a shared or handoff device. Inter Galactic cannot recover the local copy after deletion.',
                softwrap: true,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (canKeepStoredKey)
                    tiamat.Button(
                      text: 'Keep key and sign out',
                      onTap: () => Navigator.of(dialogContext)
                          .pop(BiometricRecoveryKeyLogoutChoice.keep),
                    ),
                  tiamat.Button.danger(
                    text: 'Delete key and sign out',
                    onTap: () => Navigator.of(dialogContext)
                        .pop(BiometricRecoveryKeyLogoutChoice.delete),
                  ),
                  tiamat.Button.secondary(
                    text: 'Cancel',
                    onTap: () => Navigator.of(dialogContext)
                        .pop(BiometricRecoveryKeyLogoutChoice.cancel),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
