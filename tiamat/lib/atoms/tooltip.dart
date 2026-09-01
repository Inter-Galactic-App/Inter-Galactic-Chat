import 'package:flutter/material.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

@UseCase(name: "Tooltip", type: Tooltip)
Widget wbTooltip(BuildContext context) {
  return Tile.low1(
    child: const Center(
        child: Padding(
            padding: EdgeInsets.all(8.0),
            child: Tooltip(
              text: "This is a tooltip!",
              child: tiamat.Text.body("Hover me!"),
            ))),
  );
}

class Tooltip extends StatelessWidget {
  const Tooltip(
      {required this.child,
      required this.text,
      this.preferredDirection = AxisDirection.up,
      this.excludeFromSemantics = false,
      super.key});
  final Widget child;
  final String text;
  final AxisDirection preferredDirection;

  /// Suppresses the screen-reader announcement of [text].
  ///
  /// Pass `true` **only** where the same string is already announced by
  /// something else in the subtree, or the reader says it twice. `SpaceIcon`
  /// is the worked example: it wraps its child in an
  /// `AccessibleInteractiveRegion` carrying the same display name, so the rail
  /// passes `true` here.
  ///
  /// Default `false`, matching Material `Tooltip`. Most tooltips in this app
  /// exist *for* accessibility, so silence must be opted into rather than
  /// inherited - see DECISIONS.md 2026-08-18, D7.
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final Widget tooltip = _buildTooltip(context);

    // Matches Material's own rule: no semantics node when there is nothing to
    // say (`raw_tooltip.dart`, which excludes on a null or empty message).
    if (excludeFromSemantics || text.isEmpty) {
      return tooltip;
    }

    // `Semantics(tooltip: ...)` is exactly what Material `Tooltip` emits, so a
    // site migrating from Material keeps the announcement it had. The package
    // underneath this widget emits no semantics of its own - it contains no
    // `Semantics` node anywhere and sets `excludeFromSemantics: true` on its own
    // gesture detector - so without this wrapper the migration would silently
    // delete the announcement.
    return Semantics(tooltip: text, child: tooltip);
  }

  Widget _buildTooltip(BuildContext context) {
    return JustTheTooltip(
        content: ExcludeSemantics(
          child: Theme(
            data: Theme.of(context),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: tiamat.Text(
                text,
                type: tiamat.TextType.body,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        preferredDirection: preferredDirection,
        offset: 5,
        tailLength: 5,
        tailBaseWidth: 5,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: child);
  }
}
