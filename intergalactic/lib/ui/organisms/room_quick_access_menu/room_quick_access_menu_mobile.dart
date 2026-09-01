import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomQuickAccessMenuViewMobile extends StatelessWidget {
  const RoomQuickAccessMenuViewMobile({
    required this.room,
    this.actionsAfterInvite = const [],
    super.key,
  });

  final Room room;
  final List<RoomQuickAccessMenuEntry> actionsAfterInvite;

  @override
  Widget build(BuildContext context) {
    final menu = RoomQuickAccessMenu(
      room: room,
      actionsAfterInvite: actionsAfterInvite,
    );
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(MobileVisuals.cardRadius);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: MobileGlassEdgeHighlight(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: scheme.surface.withValues(alpha: 0.7),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: menu.actions
                    .map(
                      (e) => SizedBox(
                        width: 40,
                        height: 40,
                        child: tiamat.IconButton(
                          icon: e.icon,
                          size: 20,
                          onPressed: () => e.action?.call(context),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
