import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/atoms/persistent_rail_icon_row.dart';
import 'package:intergalactic/ui/molecules/space_selector.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/animation/ring_shaker.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';

class SidebarCallIconView extends StatelessWidget {
  const SidebarCallIconView(
    this.state, {
    this.avatar,
    this.roomName,
    this.color,
    this.onTap,
    this.audioLevel = 0,
    required this.width,
    super.key,
  });
  final double width;
  final Color? color;
  final String? roomName;
  final ImageProvider? avatar;
  final VoipState state;
  final double audioLevel;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final showPersistentLabel = shouldShowPersistentRailIconLabel(context);
    final iconSize = persistentRailIconSizeFor(
      baseSize: width,
      showPersistentLabel: showPersistentLabel,
    );
    final label = roomName?.trim().isNotEmpty == true
        ? roomName!
        : CommonStrings.labelCall;
    final button = pickAnimation(
      child: Stack(
        alignment: AlignmentGeometry.bottomRight,
        children: [
          ImageButton(
            size: iconSize,
            placeholderColor: color,
            placeholderText: roomName,
            onTap: showPersistentLabel ? null : onTap,
            image: avatar,
            border: Border.all(
              color: getBorderColor(context),
              width: showPersistentLabel ? 5 : 8,
              strokeAlign: BorderSide.strokeAlignCenter,
            ),
          ),
          MouseRegion(
            opaque: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.secondaryContainer,
              ),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(
                  Icons.call,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  size: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final content = showPersistentLabel
        ? PersistentRailIconRow(icon: button, iconSize: iconSize, label: label)
        : AspectRatio(aspectRatio: 1, child: button);

    return Padding(
      padding: SpaceSelector.padding,
      child: AccessibleInteractiveRegion(
        semanticLabel: label,
        semanticHint: 'Open call room',
        onActivate: onTap,
        borderRadius: showPersistentLabel
            ? const BorderRadius.all(Radius.circular(8))
            : BorderRadius.circular(iconSize * 0.34),
        excludeChildSemantics: true,
        child: showPersistentLabel
            ? SizedBox(width: width, child: content)
            : content,
      ),
    );
  }

  Color getBorderColor(BuildContext context) {
    if (state == VoipState.connected) {
      return Color.lerp(
        Theme.of(context).primaryColor,
        Theme.of(context).colorScheme.primary,
        audioLevel,
      )!;
    }

    return Theme.of(context).primaryColor;
  }

  Widget pickAnimation({required Widget child}) {
    if (state == VoipState.incoming) {
      return RingShakerAnimation(child: child);
    }

    return child;
  }
}
