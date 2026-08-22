import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomTimelineOverlayButton extends StatelessWidget {
  const RoomTimelineOverlayButton(
      {this.onTap, this.text = "Hello, World!", super.key});
  final void Function()? onTap;
  final String text;

  @override
  Widget build(BuildContext context) {
    var padding = Layout.mobile
        ? const EdgeInsets.fromLTRB(18, 12, 18, 12)
        : const EdgeInsets.fromLTRB(12, 4, 12, 4);
    final radius = Layout.mobile
        ? MobileVisuals.pillBorderRadius
        : BorderRadius.circular(20);

    return Padding(
        padding: const EdgeInsets.all(8.0),
        child: MobileGlassEdgeHighlight(
            enabled: Layout.mobile,
            borderRadius: radius,
            highlighted: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).shadowColor,
                      blurRadius: 5,
                    )
                  ],
                  borderRadius: radius,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      width: 1),
                  color: Layout.mobile
                      ? Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.78)
                      : Theme.of(context).colorScheme.surfaceContainer),
              child: ClipRRect(
                borderRadius: radius,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: padding,
                      child: tiamat.Text.labelLow(
                        text,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            )));
  }
}
