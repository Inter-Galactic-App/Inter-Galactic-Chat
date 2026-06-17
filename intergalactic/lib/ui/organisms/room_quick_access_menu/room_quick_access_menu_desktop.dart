import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomQuickAccessMenuViewDesktop extends StatefulWidget {
  const RoomQuickAccessMenuViewDesktop({
    required this.room,
    this.onlyActionName,
    super.key,
  });

  final Room room;
  final String? onlyActionName;

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
  }

  @override
  void dispose() {
    unawaited(sub?.cancel() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menu = RoomQuickAccessMenu(room: widget.room);
    final actions = menu.actions
        .where((entry) =>
            widget.onlyActionName == null ||
            entry.name == widget.onlyActionName)
        .toList(growable: false);

    return Row(
      spacing: 4,
      mainAxisSize: MainAxisSize.min,
      children: actions
          .map((e) => _QuickAccessActionButton(
                entry: e,
                onPressed: () => e.action?.call(context),
              ))
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: 40,
      height: 40,
      child: tiamat.IconButton(
        key: ValueKey("room-quick-access-menu-action-${entry.name}"),
        icon: entry.icon,
        onPressed: onPressed,
      ),
    );

    if (entry.name != "Retry Decrypt") {
      return button;
    }

    return TutorialAnchor(
      id: TutorialAnchorIds.encryptedRoomPadlock,
      padding: const EdgeInsets.all(8),
      child: button,
    );
  }
}
