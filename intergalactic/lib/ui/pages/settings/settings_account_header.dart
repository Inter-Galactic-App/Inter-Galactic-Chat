import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SettingsAccountHeader extends StatelessWidget {
  const SettingsAccountHeader({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contextClient = SettingsContextAccountScope.maybeOf(context);
    final controller = SettingsAccountScope.maybeOf(context);
    final manager =
        controller?.clientManager ??
        _providedClientManager(context) ??
        clientManager;
    final clients = manager?.clients ?? const <Client>[];
    final selectedClient =
        contextClient ??
        controller?.selectedClient ??
        SettingsAccountController.resolvePreferredClient(manager);
    final canChoose =
        contextClient == null && controller != null && clients.length > 1;
    final profile = selectedClient?.self;
    final title =
        profile?.displayName ?? selectedClient?.identifier ?? "Inter Galactic";
    final subtitle =
        profile?.identifier ?? selectedClient?.identifier ?? "Settings";

    final child = _HeaderContent(
      title: title,
      subtitle: subtitle,
      avatar: profile?.avatar,
      placeholderColor:
          profile?.defaultColor ?? theme.colorScheme.surfaceContainerHigh,
      compact: compact,
      showChevron: canChoose,
    );

    if (!canChoose) {
      return child;
    }

    return PopupMenuButton<Client>(
      tooltip: "Choose settings account",
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
      onSelected: controller.selectClient,
      itemBuilder: (context) {
        return [
          for (final client in clients)
            PopupMenuItem<Client>(
              value: client,
              child: SizedBox(
                width: 300,
                child: UserPanelView(
                  displayName: client.self?.displayName ?? client.identifier,
                  detail: client.self?.identifier ?? client.identifier,
                  avatar: client.self?.avatar,
                ),
              ),
            ),
        ];
      },
      child: child,
    );
  }
}

class _HeaderContent extends StatelessWidget {
  const _HeaderContent({
    required this.title,
    required this.subtitle,
    required this.avatar,
    required this.placeholderColor,
    required this.compact,
    required this.showChevron,
  });

  final String title;
  final String subtitle;
  final ImageProvider? avatar;
  final Color placeholderColor;
  final bool compact;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(compact ? 999 : 10);

    return Material(
      color: showChevron
          ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.32)
          : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 0,
            compact ? 6 : 0,
            compact ? 10 : 0,
            compact ? 6 : 0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              tiamat.Avatar(
                radius: compact ? 15 : 18,
                image: avatar,
                placeholderColor: placeholderColor,
                placeholderText: title,
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tiamat.Text.labelEmphasised(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 1),
                      tiamat.Text.labelLow(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron) ...[
                SizedBox(width: compact ? 4 : 6),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: compact ? 18 : 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

ClientManager? _providedClientManager(BuildContext context) {
  try {
    return Provider.of<ClientManager>(context, listen: false);
  } catch (_) {
    return null;
  }
}
