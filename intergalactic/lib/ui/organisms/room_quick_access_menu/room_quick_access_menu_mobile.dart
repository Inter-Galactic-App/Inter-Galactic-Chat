import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/vodozemac_single_flight.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
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
    // The Retry Decrypt entry resolves its enabled state from
    // encryptionAvailability when the menu is CONSTRUCTED, below. This widget
    // is stateless and nothing else here listens, so without rebuilding on the
    // notifier a room opened while vodozemac is still initialising keeps a
    // disabled padlock after encryption becomes ready.
    return ValueListenableBuilder<EncryptionAvailability>(
      valueListenable: MatrixClient.encryptionAvailability,
      builder: (context, _, _) => _buildMenu(context),
    );
  }

  Widget _buildMenu(BuildContext context) {
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
                children: menu.actions.map((e) => _action(context, e)).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(BuildContext context, RoomQuickAccessMenuEntry entry) {
    final button = SizedBox(
      width: 40,
      height: 40,
      child: tiamat.IconButton(
        icon: entry.icon,
        size: 20,
        // A disabled entry reaches the atom as null, or it renders operable
        // and silently does nothing.
        onPressed: entry.action == null
            ? null
            : () => entry.action!.call(context),
        semanticLabel: entry.semanticLabel ?? entry.name,
      ),
    );

    if (entry.name != retryDecryptActionName) {
      return button;
    }

    // Mirrors the desktop menu's registration so the mobile tutorial measures
    // the padlock from the control that visually owns it.
    return TutorialAnchor(
      id: TutorialAnchorIds.encryptedRoomPadlock,
      padding: const EdgeInsets.all(8),
      child: button,
    );
  }
}
