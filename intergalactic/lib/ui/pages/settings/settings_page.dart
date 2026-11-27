import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/pages/settings/mobile_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/settings/settings_button.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:flutter/material.dart';

import 'desktop_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    this.buttons,
    this.initialTabId,
    this.initialTabInline = false,
    this.accountClientManager,
    this.initialSelectedAccount,
    this.contextAccount,
    super.key,
  });
  final List<SettingsCategory> settings;
  final List<SettingsButton>? buttons;
  final String? initialTabId;
  final bool initialTabInline;
  final ClientManager? accountClientManager;
  final Client? initialSelectedAccount;
  final Client? contextAccount;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsAccountController? _accountController;

  @override
  void initState() {
    super.initState();
    _syncAccountController();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.accountClientManager,
      widget.accountClientManager,
    )) {
      _syncAccountController();
    }
  }

  @override
  void dispose() {
    _accountController?.dispose();
    super.dispose();
  }

  void _syncAccountController() {
    final manager = widget.accountClientManager;
    if (manager == null) {
      _accountController?.dispose();
      _accountController = null;
      return;
    }

    _accountController?.dispose();
    _accountController = SettingsAccountController(
      clientManager: manager,
      initialClient: widget.initialSelectedAccount,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = pickChatView(context);
    final accountController = _accountController;

    if (accountController != null) {
      content = SettingsAccountScope(
        controller: accountController,
        child: content,
      );
    }

    final contextAccount = widget.contextAccount;
    if (contextAccount != null) {
      content = SettingsContextAccountScope(
        client: contextAccount,
        child: content,
      );
    }

    return content;
  }

  Widget pickChatView(BuildContext context) {
    if (Layout.desktop) {
      return DesktopSettingsPage(
        settings: widget.settings,
        buttons: widget.buttons,
        initialTabId: widget.initialTabId,
      );
    }
    if (Layout.mobile) {
      return MobileSettingsPage(
        settings: widget.settings,
        buttons: widget.buttons,
        initialTabId: widget.initialTabId,
        initialTabInline: widget.initialTabInline,
      );
    }

    throw Exception(
      "No SettingsPage has been defined for the current build config",
    );
  }
}
