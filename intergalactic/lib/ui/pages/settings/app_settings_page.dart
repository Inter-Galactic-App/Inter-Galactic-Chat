import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/about/settings_category_about.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/biometric_recovery_key_logout_prompt.dart';
import 'package:intergalactic/ui/pages/settings/categories/discover/settings_category_discover.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/settings_category_help.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/settings/settings_button.dart';
import 'package:intergalactic/ui/pages/settings/settings_page.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'categories/account/settings_category_account.dart';
import 'categories/app/settings_category_app.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({
    this.initialTabId,
    this.includeTutorialPreviewTabs = false,
    super.key,
  });

  final String? initialTabId;
  final bool includeTutorialPreviewTabs;

  String get promptLogoutFailedTitle => Intl.message(
        "Logout failed",
        name: "promptLogoutFailedTitle",
        desc: "Title shown when logging out of an account fails",
      );

  String get promptLogoutFailedDescription => Intl.message(
        "Couldn't log out this account. Please try again.",
        name: "promptLogoutFailedDescription",
        desc: "Error text shown when logging out of an account fails",
      );

  @override
  Widget build(BuildContext context) {
    final manager = _providedClientManager(context) ?? clientManager;
    final initialSelectedAccount =
        SettingsAccountController.resolvePreferredClient(manager);
    final logoutButtons = manager != null && manager.clients.isNotEmpty
        ? [
            SettingsButton(
              label: "Logout",
              icon: Icons.logout_rounded,
              color: Theme.of(context).colorScheme.error,
              onPress: () => _confirmLogout(context, manager),
            ),
          ]
        : null;

    return SettingsPage(
      settings: [
        if (manager != null && manager.clients.isNotEmpty)
          SettingsCategoryAccount(),
        if (manager != null && manager.clients.isNotEmpty)
          SettingsCategoryDiscover(),
        SettingsCategoryApp(
          overrideClientManager: manager,
          includeTutorialPreviewTabs: includeTutorialPreviewTabs,
        ),
        SettingsCategoryHelp(),
        SettingsCategoryAbout(),
      ],
      buttons: logoutButtons,
      initialTabId: initialTabId,
      accountClientManager: manager,
      initialSelectedAccount: initialSelectedAccount,
    );
  }

  Future<void> _confirmLogout(
    BuildContext context,
    ClientManager manager,
  ) async {
    final initialClient =
        SettingsAccountScope.maybeRead(context)?.selectedClient ??
            SettingsAccountController.resolvePreferredClient(manager);
    final selectedClient = await AdaptiveDialog.show<Client>(
      context,
      title: "Are you sure you want to log out?",
      scrollable: false,
      builder: (dialogContext) {
        return _LogoutDialog(
          clientManager: manager,
          initialClient: initialClient,
        );
      },
    );

    if (selectedClient == null) return;

    bool completed;
    try {
      completed = await BiometricRecoveryKeyLogoutPrompt.logoutClient(
        context: context,
        clientManager: manager,
        client: selectedClient,
      );
    } catch (_) {
      if (!context.mounted) return;
      await AdaptiveDialog.show<void>(
        context,
        title: promptLogoutFailedTitle,
        builder: (_) => tiamat.Text.label(promptLogoutFailedDescription),
      );
      return;
    }

    if (!completed) return;
    if (!context.mounted) return;
    if (manager.clients.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }
}

ClientManager? _providedClientManager(BuildContext context) {
  try {
    return Provider.of<ClientManager>(context, listen: false);
  } catch (_) {
    return null;
  }
}

class _LogoutDialog extends StatefulWidget {
  const _LogoutDialog({
    required this.clientManager,
    this.initialClient,
  });

  final ClientManager clientManager;
  final Client? initialClient;

  @override
  State<_LogoutDialog> createState() => _LogoutDialogState();
}

class _LogoutDialogState extends State<_LogoutDialog> {
  Client? _selectedClient;

  @override
  void initState() {
    super.initState();
    if (widget.clientManager.clients.isNotEmpty) {
      _selectedClient = widget.clientManager.clients.contains(
        widget.initialClient,
      )
          ? widget.initialClient
          : SettingsAccountController.resolvePreferredClient(
              widget.clientManager,
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = widget.clientManager.clients;
    final validatedSelectedClient = clients.contains(_selectedClient)
        ? _selectedClient
        : clients.isNotEmpty
            ? clients.first
            : null;

    return SizedBox(
      width: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Choose which signed-in account to log out.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          if (clients.isNotEmpty && validatedSelectedClient != null)
            tiamat.DropdownSelector<Client>(
              items: clients,
              value: validatedSelectedClient,
              itemHeight: 68,
              onItemSelected: (client) {
                if (client == null) return;
                setState(() {
                  _selectedClient = client;
                });
              },
              itemBuilder: (client) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: UserPanelView(
                    displayName: client.self?.displayName ?? client.identifier,
                    detail: client.self?.identifier ?? client.identifier,
                    avatar: client.self?.avatar,
                  ),
                );
              },
            )
          else
            const tiamat.Text.labelLow("No active accounts"),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: tiamat.Button.secondary(
                  text: "Cancel",
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: tiamat.Button.danger(
                  text: "Logout",
                  onTap: validatedSelectedClient == null
                      ? null
                      : () =>
                          Navigator.of(context).pop(validatedSelectedClient),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
