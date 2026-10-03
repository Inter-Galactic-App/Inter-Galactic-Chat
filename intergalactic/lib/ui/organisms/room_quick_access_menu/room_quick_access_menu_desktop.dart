import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomQuickAccessMenuViewDesktop extends StatefulWidget {
  const RoomQuickAccessMenuViewDesktop({
    required this.room,
    this.onlyActionName,
    this.actionsAfterInvite = const [],
    this.onTogglePanel,
    this.forceSidePanelVisible = false,
    super.key,
  });

  final Room room;
  final String? onlyActionName;
  final List<RoomQuickAccessMenuEntry> actionsAfterInvite;
  final Function(BuildContext context)? onTogglePanel;
  final bool forceSidePanelVisible;

  @override
  State<RoomQuickAccessMenuViewDesktop> createState() =>
      _RoomQuickAccessMenuViewDesktopState();
}

class _RoomQuickAccessMenuViewDesktopState
    extends State<RoomQuickAccessMenuViewDesktop> {
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = preferences.onSettingChanged.listen(onChanged);
    // The Retry Decrypt entry resolves its enabled state from
    // encryptionAvailability when the menu is CONSTRUCTED, below. Without
    // this, a room opened while vodozemac is still initialising renders the
    // padlock disabled and leaves it that way after encryption becomes ready,
    // until some unrelated rebuild happens to run.
    MatrixClient.encryptionAvailability.addListener(_onEncryptionChanged);
  }

  void _onEncryptionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    MatrixClient.encryptionAvailability.removeListener(_onEncryptionChanged);
    unawaited(sub?.cancel() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menu = RoomQuickAccessMenu(
      room: widget.room,
      actionsAfterInvite: widget.actionsAfterInvite,
      onTogglePanel: widget.onTogglePanel,
      forceSidePanelVisible: widget.forceSidePanelVisible,
    );
    final actions = menu.actions
        .where(
          (entry) =>
              widget.onlyActionName == null ||
              entry.name == widget.onlyActionName,
        )
        .toList(growable: false);

    return Row(
      spacing: 4,
      mainAxisSize: MainAxisSize.min,
      children: actions
          .map(
            (e) => _QuickAccessActionButton(
              entry: e,
              // NOT `() => e.action?.call(context)`. That closure is never
              // null, so the button renders and behaves as though it were
              // operable and then does nothing when pressed. A disabled entry
              // has to reach the atom as a null callback, which is what makes
              // it inert and reports it as disabled to assistive technology.
              onPressed: e.action == null
                  ? null
                  : () => e.action!.call(context),
            ),
          )
          .toList(),
    );
  }

  void onChanged(event) {
    if (mounted) setState(() {});
  }
}

class _QuickAccessActionButton extends StatelessWidget {
  const _QuickAccessActionButton({
    required this.entry,
    required this.onPressed,
  });

  final RoomQuickAccessMenuEntry entry;

  /// Null for a disabled entry, and it must stay nullable all the way to
  /// the atom: a non-null wrapper around a null action is exactly how an
  /// inoperable button keeps looking operable.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final button = SizedBox(
      width: 40,
      height: 40,
      child: tiamat.IconButton(
        key: ValueKey("room-quick-access-menu-action-${entry.name}"),
        icon: entry.icon,
        iconColor: entry.selected ? colorScheme.primary : null,
        backgroundColor: entry.selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.42)
            : Colors.transparent,
        semanticLabel: entry.semanticLabel ?? entry.name,
        tooltip: entry.disabledReason ?? entry.name,
        onPressed: onPressed,
      ),
    );

    if (entry.name != retryDecryptActionName) {
      return button;
    }

    return TutorialAnchor(
      id: TutorialAnchorIds.encryptedRoomPadlock,
      padding: const EdgeInsets.all(8),
      child: button,
    );
  }
}
