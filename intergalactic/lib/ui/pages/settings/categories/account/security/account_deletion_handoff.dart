import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/public_release_links.dart';
import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AccountDeletionHandoffPanel extends StatelessWidget {
  const AccountDeletionHandoffPanel({required this.client, super.key});

  final Client client;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const tiamat.Text.body(
            "Inter Galactic can remove an account from this device, but Matrix account deletion or deactivation is handled by the selected homeserver.",
            softwrap: true,
          ),
          const SizedBox(height: 8),
          const tiamat.Text.body(
            "Use the handoff below to identify the account and open the homeserver. If the homeserver does not publish an account page, contact that homeserver's administrator or support contact.",
            softwrap: true,
          ),
          const SizedBox(height: 8),
          const tiamat.Text.body(
            "Inter Galactic's account-deletion guide explains what the app can remove locally and what the selected Matrix homeserver still controls.",
            softwrap: true,
          ),
          const SizedBox(height: 12),
          _AccountDeletionHandoffItem(client: client),
        ],
      ),
    );
  }
}

class _AccountDeletionHandoffItem extends StatelessWidget {
  const _AccountDeletionHandoffItem({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    final homeserver = homeserverWebsiteFor(client);
    final homeserverLabel = homeserver == null
        ? "No homeserver website available"
        : homeserver.toString();

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.hardEdge,
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        final userPanel = UserPanelView(
          displayName: client.self?.displayName ?? client.identifier,
          avatar: client.self?.avatar,
          detail:
              "${client.self?.identifier ?? client.identifier} - $homeserverLabel",
        );
        final handoffButton = tiamat.Button.secondary(
          text: "Deletion help",
          onTap: () => showAccountDeletionHelp(context, client),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              userPanel,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: handoffButton,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: userPanel),
            const SizedBox(width: 12),
            handoffButton,
          ],
        );
      }),
    );
  }
}

Uri? homeserverWebsiteFor(Client client) {
  if (client is! MatrixClient) {
    return null;
  }

  final homeserver =
      client.getMatrixClient().homeserver ?? client.getMatrixClient().baseUri;
  if (homeserver == null || homeserver.host.isEmpty) {
    return null;
  }

  final scheme = homeserver.scheme.isEmpty ? "https" : homeserver.scheme;
  if (scheme != "http" && scheme != "https") {
    return null;
  }

  return Uri(
    scheme: scheme,
    host: homeserver.host,
    port: homeserver.hasPort ? homeserver.port : null,
  );
}

Future<void> showAccountDeletionHelp(
  BuildContext context,
  Client client,
) {
  final homeserver = homeserverWebsiteFor(client);
  final userId = client.self?.identifier ?? client.identifier;
  final homeserverLabel = homeserver == null
      ? "No homeserver website available"
      : homeserver.toString();

  return AdaptiveDialog.show(
    context,
    title: "Account deletion",
    builder: (dialogContext) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const tiamat.Text.body(
              "Inter Galactic can sign this account out and remove local app data from this device. It cannot delete or deactivate a Matrix account from a homeserver it does not operate.",
              softwrap: true,
            ),
            const SizedBox(height: 12),
            const tiamat.Text.labelLow("Matrix account"),
            tiamat.Text.label(userId, softwrap: true),
            const SizedBox(height: 8),
            const tiamat.Text.labelLow("Homeserver"),
            tiamat.Text.label(homeserverLabel, softwrap: true),
            const SizedBox(height: 12),
            const tiamat.Text.body(
              "To delete or deactivate the Matrix account, use the homeserver's account-management page or contact that homeserver's administrator. The homeserver controls identity checks, retention, and whether deactivation is available.",
              softwrap: true,
            ),
            const SizedBox(height: 8),
            const tiamat.Text.body(
              "Deleting Inter Galactic, signing out, or clearing local app data does not delete the Matrix account. Messages and media already delivered to other users, devices, homeservers, backups, bridges, or room history may not be fully removable.",
              softwrap: true,
            ),
            const SizedBox(height: 8),
            const tiamat.Text.body(
              "Inter Galactic's hosted account-deletion guide summarizes this handoff for app review and public support.",
              softwrap: true,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                tiamat.Button.secondary(
                  text: "Open Guide",
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    await LinkUtils.open(
                      PublicReleaseLinks.accountDeletion.uri,
                      context: context,
                    );
                  },
                ),
                if (homeserver != null)
                  tiamat.Button(
                    text: "Open Homeserver",
                    onTap: () async {
                      Navigator.of(dialogContext).pop();
                      await LinkUtils.open(homeserver, context: context);
                    },
                  ),
                tiamat.Button.secondary(
                  text: "Close",
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
