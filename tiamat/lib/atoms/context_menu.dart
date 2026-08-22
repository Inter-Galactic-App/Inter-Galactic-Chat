import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tiamat/atoms/seperator.dart';
import 'package:tiamat/atoms/text.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

@UseCase(name: "Context Menu", type: ContextMenu)
Widget wbContextMenu(BuildContext context) {
  return Tile.low1(
    child: Center(
        child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ContextMenu(
              items: [
                ContextMenuItem(
                    text: "Copy Text",
                    icon: Icons.copy_rounded,
                    onPressed: () {
                      print("Copying text");
                    }),
                ContextMenuItem(
                  text: "Delete Message",
                  icon: Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
              child: const Tile.low3(
                child: SizedBox(
                    width: 500,
                    height: 500,
                    child: Center(
                        child:
                            const tiamat.Text.label("Right Click Somewhere"))),
              ),
            ))),
  );
}

@UseCase(name: "Modal", type: ContextMenu)
Widget wbContextMenuModal(BuildContext context) {
  return Tile.low1(
    child: Center(
        child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          child: ContextMenu(
            modal: true,
            items: [
              ContextMenuItem(
                  text: "Copy Text",
                  icon: Icons.copy_rounded,
                  onPressed: () {
                    print("Copying text");
                  }),
              ContextMenuItem(
                text: "Delete Message",
                icon: Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            child: Padding(
                padding: EdgeInsets.all(8), child: const Icon(Icons.mouse)),
          ),
        ),
      ),
    )),
  );
}

class ContextMenuOverlay extends StatefulWidget {
  const ContextMenuOverlay(
      {super.key, required this.globalOffset, required this.items, this.close});
  final Offset globalOffset;
  final List<ContextMenuItem> items;
  final Function()? close;

  @override
  State<ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<ContextMenuOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 200),
    vsync: this,
  );

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.fastOutSlowIn,
  );

  @override
  void initState() {
    super.initState();
    // The menu no longer has to be built once offstage to be measured, so the
    // reveal can start immediately instead of waiting for that frame.
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Logical pixels. The previous implementation compared this anchor against
    // `view.physicalSize`, mixing units - on any display with a device pixel
    // ratio above 1 the "past the halfway point" test could effectively never
    // fire, so menus opened near the right or bottom edge ran off screen.
    final viewSize = MediaQuery.sizeOf(context);
    final anchor = widget.globalOffset;

    return CustomSingleChildLayout(
      delegate: _ContextMenuLayoutDelegate(
        anchor: anchor,
        // Decided here, from the anchor alone, rather than inside the delegate
        // from the child's size. That keeps the decision stable while
        // SizeTransition animates the menu open; deciding it from the animating
        // size would flip the menu part-way through the reveal.
        leftAlign: anchor.dx > viewSize.width / 2,
        topAlign: anchor.dy > viewSize.height / 2,
      ),
      // IntrinsicWidth has to sit ABOVE SizeTransition, not below it.
      // SizeTransition renders an Align with `widthFactor: null`, which expands
      // to the whole incoming width - so without this the delegate is handed a
      // childSize as wide as the screen, and every menu gets clamped hard
      // against the left edge. Caught by the positioning tests, which is the
      // reason they assert coordinates rather than just "no exception".
      child: IntrinsicWidth(
        child: SizeTransition(
          sizeFactor: _animation,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Tile.low4(
              child: buildMenu(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildMenu(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: widget.items
          .map((e) => e.build(context, () {
                e.onPressed?.call();
                _controller.animateTo(0).then((value) => widget.close?.call());
              }))
          .toList(),
    );
  }
}

/// Positions the context menu from the child's size **during layout**, in a
/// single pass.
///
/// **Why this exists (BUG-298, and BUG-291 before it).** The previous
/// implementation measured the menu by building it twice: once inside an
/// `Offstage` carrying a `GlobalKey`, then - after a post-frame callback read
/// that key's render box and `setState` the size - again *without* the key, in
/// its final position. Removing a GlobalKey-keyed subtree and re-inserting an
/// equivalent elsewhere in the tree makes Flutter **reparent** the element:
/// deactivate, then reactivate. Reactivation walked into an `OverlayPortal`
/// (framework-internal to `SelectionArea`) and re-attached its deferred child to
/// the enclosing `_RenderTheater`, which called `markNeedsLayout` on one
/// `_RenderLayoutBuilder` while another was mid-`performLayout`. Flutter cannot
/// order that, so it threw - and one such throw cascaded into 944 further
/// framework exceptions, leaving the surface unusable until restart.
///
/// A layout delegate is handed the child's size as part of laying it out, so no
/// measuring frame, no `GlobalKey`, and no reparent are needed. The mechanism is
/// removed rather than the symptom suppressed.
class _ContextMenuLayoutDelegate extends SingleChildLayoutDelegate {
  const _ContextMenuLayoutDelegate({
    required this.anchor,
    required this.leftAlign,
    required this.topAlign,
  });

  /// Where the menu was summoned, in this delegate's own coordinate space.
  ///
  /// This is a raw global `PointerEvent.position` used unconverted, which is
  /// sound only because [_ContextMenuState.addOverlay] inserts into the root
  /// [Overlay] (`rootOverlay: true`) - that one fills the view from the origin,
  /// so global and local coincide. The old code called `globalToLocal` against
  /// that same full-screen box, which returned the same value. If the insertion
  /// target ever stops being the root overlay, this anchor must be converted
  /// into that overlay's coordinate space instead.
  final Offset anchor;
  final bool leftAlign;
  final bool topAlign;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // The menu sizes itself to its content; it must not be forced to fill.
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = leftAlign ? anchor.dx - childSize.width : anchor.dx;
    final y = topAlign ? anchor.dy - childSize.height : anchor.dy;

    // Keep the menu on screen even when the anchor sits close to an edge and
    // the flip alone is not enough - a menu taller than the space above and
    // below, say. `clamp` requires max >= min, and a menu larger than the view
    // makes the max negative, so the bound is floored at zero.
    return Offset(
      x.clamp(0.0, math.max(0.0, size.width - childSize.width)),
      y.clamp(0.0, math.max(0.0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_ContextMenuLayoutDelegate oldDelegate) {
    return oldDelegate.anchor != anchor ||
        oldDelegate.leftAlign != leftAlign ||
        oldDelegate.topAlign != topAlign;
  }
}

class ContextMenu extends StatefulWidget {
  const ContextMenu(
      {super.key,
      required this.child,
      this.separator,
      required this.items,
      this.modal = false});

  final Seperator? separator;
  final List<ContextMenuItem> items;
  final Widget child;
  final bool modal;

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<ContextMenu> {
  Offset mousePosition = Offset.zero;
  OverlayEntry? entry;
  bool _overlayInsertScheduled = false;

  void addOverlay() {
    if (entry != null) {
      removeOverlay();
    }

    if (_overlayInsertScheduled) {
      return;
    }

    _overlayInsertScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayInsertScheduled = false;
      if (!mounted || entry != null) {
        return;
      }

      // `rootOverlay: true` is load-bearing, not a preference. The anchor
      // handed to the layout delegate is `PointerEvent.position`, which is a
      // GLOBAL offset, and the delegate consumes it as a local one. That is
      // only correct while the entry lives in an overlay whose box starts at
      // the view origin - the root one. `Overlay.maybeOf` defaults to the
      // *nearest* enclosing overlay, so a ContextMenu placed under any nested
      // Navigator or Overlay (a dialog route, an inline navigator, a
      // side-panel that carries its own) would have anchored the menu at
      // `nestedOrigin + pointer` instead of at the pointer.
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        return;
      }

      entry = OverlayEntry(builder: buildOverlay);
      overlay.insert(entry!);
    });
  }

  void removeOverlay() {
    _overlayInsertScheduled = false;
    entry?.remove();
    entry = null;
  }

  @override
  void dispose() {
    removeOverlay();
    super.dispose();
  }

  Widget buildOverlay(BuildContext overlayContext) {
    if (mounted)
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: removeOverlay,
        child: Stack(
          children: [
            Theme(
              data: Theme.of(context),
              child: ContextMenuOverlay(
                globalOffset: mousePosition,
                items: widget.items,
                close: removeOverlay,
              ),
            ),
          ],
        ),
      );
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        mousePosition = event.position;
      },
      child: widget.modal
          ? InkWell(
              child: widget.child,
              onTap: () => _showMenu(context, mousePosition),
            )
          : GestureDetector(
              onLongPress: () => _showMenu(context, mousePosition),
              onSecondaryTap: () => _showMenu(context, mousePosition),
              child: widget.child,
            ),
    );
  }

  void _showMenu(BuildContext context, Offset mousePosition) {
    addOverlay();
  }
}

class ContextMenuItem {
  const ContextMenuItem(
      {required this.text,
      this.onPressed,
      this.icon,
      this.color,
      this.customBuilder});

  final String text;
  final Function? onPressed;
  final IconData? icon;
  final Color? color;
  final Widget Function(BuildContext context, Function() onClicked)?
      customBuilder;

  Widget build(BuildContext context, Function() onClicked) {
    var c = color ?? Theme.of(context).colorScheme.onSurface;

    if (customBuilder != null) {
      return Material(
          color: Colors.transparent,
          child: customBuilder!.call(context, onClicked));
    }

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(3.0),
        child: InkWell(
            onTap: onClicked,
            borderRadius: BorderRadius.circular(8),
            child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    tiamat.Text(text,
                        type: TextType.body, maxLines: 1, color: c),
                    if (icon != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                        child: Icon(
                          icon,
                          color: c,
                          size: 20,
                        ),
                      )
                  ],
                ))),
      ),
    );
  }
}
