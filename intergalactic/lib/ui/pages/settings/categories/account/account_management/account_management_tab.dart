import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/stale_info.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/navigation/adaptive_text_dialog.dart';
import 'package:intergalactic/ui/pages/login/login_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/biometric_recovery_key_logout_prompt.dart';
import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

class AccountManagementSettingsTab extends StatefulWidget {
  const AccountManagementSettingsTab({super.key, required this.clientManager});
  static ValueKey addAccountKey =
      const ValueKey("ACCOUNT_MANAGEMENT_SETTINGS_ADD_ACCOUNT_BUTTON");
  final ClientManager clientManager;
  @override
  State<AccountManagementSettingsTab> createState() =>
      _AccountManagementSettingsTabState();
}

class _AccountManagementSettingsTabState
    extends State<AccountManagementSettingsTab> {
  StreamSubscription<int>? onClientAddedListener;
  StreamSubscription<StalePeerInfo>? onClientRemovedListener;
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late int _numClients;

  String get promptAddAccount => Intl.message("Add Account",
      desc: "Label for button in settings to add another account",
      name: "promptAddAccount");

  String get promptLogoutSingleAccount => Intl.message("Logout",
      desc: "Label for button in settings to log out of an account",
      name: "promptLogoutSingleAccount");

  String get labelCurrentAccountsHeader => Intl.message("Current Accounts",
      desc: "Label for header of accounts list",
      name: "labelCurrentAccountsHeader");

  @override
  Widget build(BuildContext context) {
    return manageAccountsTab(context);
  }

  @override
  void initState() {
    onClientAddedListener =
        widget.clientManager.onClientAdded.stream.listen((index) {
      _listKey.currentState?.insertItem(index);
      setState(() {
        _numClients++;
      });
    });

    onClientRemovedListener =
        widget.clientManager.onClientRemoved.stream.listen((info) {
      _listKey.currentState?.removeItem(
          info.index,
          (context, animation) => SizeTransition(
                sizeFactor: animation,
                child: accountListItem(
                    displayName: info.displayName!,
                    avatar: info.avatar,
                    detail: info.identifier),
              ));
    });

    _numClients = widget.clientManager.clients.length;

    super.initState();
  }

  @override
  void dispose() {
    onClientAddedListener?.cancel();
    onClientRemovedListener?.cancel();
    super.dispose();
  }

  Widget manageAccountsTab(BuildContext context) {
    ClientManager clientManager = Provider.of<ClientManager>(context);

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Panel(
              header: labelCurrentAccountsHeader,
              mode: TileType.surfaceContainerLow,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  accountListBuilder(context, clientManager),
                  addAccountButton(context)
                ],
              ),
            ),
            const SizedBox(height: 12),
            accountDeletionHandoffPanel(context, clientManager),
          ],
        ),
      ),
    );
  }

  Widget accountListBuilder(BuildContext context, ClientManager clientmanager) {
    var clients = clientmanager.clients;

    return AnimatedList(
      initialItemCount: _numClients,
      shrinkWrap: true,
      key: _listKey,
      itemBuilder: (context, index, animation) {
        final client = clients[index];
        return SizeTransition(
          sizeFactor: animation,
          child: accountListItem(
              client: client,
              displayName: client.self!.displayName,
              avatar: client.self!.avatar,
              detail: client.self!.identifier,
              internalId: client.identifier,
              onLogoutClicked: () =>
                  _logoutClient(context, clientmanager, client)),
        );
      },
    );
  }

  Widget accountListItem(
      {required String displayName,
      Client? client,
      ImageProvider? avatar,
      String? detail,
      String? internalId,
      Future<void> Function()? onLogoutClicked}) {
    String detailString = detail ?? "";

    if (preferences.developerMode.value && internalId != null) {
      detailString = "$detail - ($internalId)";
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 4, 12, 4),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(8),
        child: tiamat.ContextMenu(
          modal: true,
          items: client == null
              ? []
              : [
                  if (_numClients > 1)
                    tiamat.ContextMenuItem(
                        text: "Set Prefix",
                        onPressed: () {
                          setPrefixDialog(client);
                        })
                ],
          child: LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 420;
            final userPanel = UserPanelView(
              displayName: displayName,
              avatar: avatar,
              detail: detailString,
            );
            final logoutButton = tiamat.Button.danger(
              text: promptLogoutSingleAccount,
              onTap: () {
                final logout = onLogoutClicked;
                if (logout != null) {
                  unawaited(logout());
                }
              },
            );
            final accountDeletionButton = client == null
                ? null
                : tiamat.Button.secondary(
                    text: "Account deletion",
                    onTap: () => showAccountDeletionHelp(context, client),
                  );
            final actionButtons = <Widget>[
              if (accountDeletionButton != null) accountDeletionButton,
              logoutButton,
            ];

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  userPanel,
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actionButtons,
                  ),
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: userPanel),
                const SizedBox(width: 12),
                Flexible(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: actionButtons,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget accountDeletionHandoffPanel(
    BuildContext context,
    ClientManager clientManager,
  ) {
    return Panel(
      header: "Account deletion",
      mode: TileType.surfaceContainerLow,
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
          const SizedBox(height: 12),
          ...clientManager.clients.map(
            (client) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: accountDeletionHandoffItem(context, client),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logoutClient(
    BuildContext context,
    ClientManager clientManager,
    Client client,
  ) async {
    await BiometricRecoveryKeyLogoutPrompt.logoutClient(
      context: context,
      clientManager: clientManager,
      client: client,
    );
  }

  Widget accountDeletionHandoffItem(BuildContext context, Client client) {
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
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
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

  Future<void> setPrefixDialog(Client client) async {
    final component = client.getComponent<AccountSwitchPrefix>();

    if (component == null) {
      return;
    }

    final newPrefix = await AdaptiveTextDialog.show(
        title: "Set Prefix",
        placeholder: "Enter Prefix",
        description:
            "When more than one of your logged in accounts share the same room, you can type this prefix to quickly send messages from this account",
        context,
        defaultText: component.clientPrefix);
    if (newPrefix == null) {
      return;
    }

    component.setClientPrefix(newPrefix);
  }

  Padding addAccountButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 12, 12),
      child: Align(
          alignment: Alignment.centerRight,
          child: JustTheTooltip(
            content: Padding(
              padding: const EdgeInsets.all(8.0),
              child: tiamat.Text(promptAddAccount),
            ),
            preferredDirection: AxisDirection.down,
            offset: 5,
            tailLength: 5,
            tailBaseWidth: 5,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerLowest,
            child: tiamat.CircleButton(
              key: AccountManagementSettingsTab.addAccountKey,
              icon: Icons.add,
              radius: 20,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LoginPage(
                          canNavigateBack: true,
                          onSuccess: (
                            _,
                          ) {
                            Navigator.of(context).pop();
                          },
                        )));
              },
            ),
          )),
    );
  }
}
