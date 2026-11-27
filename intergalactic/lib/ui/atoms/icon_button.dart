import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class IconButton extends StatefulWidget {
  const IconButton({
    super.key,
    this.size = 15,
    required this.icon,
    this.onPressed,
    this.semanticLabel,
    this.semanticHint,
    this.tooltip,
    this.tooltipDirection = AxisDirection.up,
    this.persistentLabel,
    this.minimumSize,
  });
  final double size;
  final Function? onPressed;
  final IconData icon;
  final String? semanticLabel;
  final String? semanticHint;
  final String? tooltip;

  /// Side of the button the tooltip prefers to sit on.
  ///
  /// Defaults to `AxisDirection.up` per DECISIONS.md 2026-08-18 D3. Override it
  /// where the geometry needs it - `right` for a vertical rail, `down` for a
  /// control near the top of the window, `left` for a right-aligned one. The
  /// point of the default is that a tooltip should not cover the thing it
  /// describes; where `up` would, say so at the call site.
  final AxisDirection tooltipDirection;

  final String? persistentLabel;
  final double? minimumSize;

  @override
  State<IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<IconButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final onActivate = widget.onPressed == null
        ? null
        : () {
            widget.onPressed?.call();
          };
    final label =
        widget.semanticLabel ?? widget.tooltip ?? _labelForIcon(widget.icon);
    final child = Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onActivate,
        child: MouseRegion(
          onEnter: (event) {
            setState(() {
              hovered = true;
            });
          },
          onExit: (event) {
            setState(() {
              hovered = false;
            });
          },
          cursor: WidgetStateMouseCursor.clickable,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Align(
                alignment: Alignment.center,
                child: Icon(
                  widget.icon,
                  size: widget.size,
                  color: hovered
                      ? Theme.of(context).colorScheme.onPrimary
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final result = AccessibleInteractiveRegion(
      semanticLabel: label,
      semanticHint: widget.semanticHint,
      onActivate: onActivate,
      enabled: onActivate != null,
      excludeChildSemantics: true,
      minimumSize: widget.minimumSize ?? widget.size + 8,
      persistentLabel:
          widget.persistentLabel ?? (label == "Icon action" ? null : label),
      borderRadius: BorderRadius.circular(8),
      child: child,
    );

    if (widget.tooltip == null) {
      return result;
    }

    // House component rather than Material. See DECISIONS.md 2026-08-18.
    //
    // excludeFromSemantics is set where the Material tooltip this replaces had
    // no such flag, which is a fix rather than a change of intent: the
    // AccessibleInteractiveRegion directly below already announces `label`,
    // which is `semanticLabel ?? tooltip ?? _labelForIcon(icon)` - usually the
    // same string - so this atom has been announcing it twice. The two tiamat
    // button atoms already excluded it; this one was the odd one out.
    //
    // It is conditional, not unconditional: when a call site passes a
    // `semanticLabel` that differs from `tooltip`, the two strings say
    // different things and excluding would delete the tooltip announcement
    // outright, leaving assistive technology with only the label. Silence the
    // tooltip only where it would be a verbatim repeat.
    return tiamat.Tooltip(
      text: widget.tooltip!,
      preferredDirection: widget.tooltipDirection,
      excludeFromSemantics: label == widget.tooltip,
      child: result,
    );
  }

  String _labelForIcon(IconData icon) {
    if (icon == Icons.fullscreen || icon == Icons.fullscreen_rounded) {
      return "Enter fullscreen";
    }
    if (icon == Icons.fullscreen_exit ||
        icon == Icons.fullscreen_exit_rounded) {
      return "Exit fullscreen";
    }
    if (icon == Icons.close || icon == Icons.close_rounded) {
      return "Close";
    }
    if (icon == Icons.add || icon == Icons.add_rounded) {
      return "Add";
    }
    if (icon == Icons.edit || icon == Icons.edit_rounded) {
      return "Edit";
    }
    if (icon == Icons.delete || icon == Icons.delete_rounded) {
      return "Delete";
    }
    if (icon == Icons.download || icon == Icons.download_rounded) {
      return "Download";
    }
    if (icon == Icons.save || icon == Icons.save_rounded) {
      return "Save";
    }
    if (icon == Icons.more_vert || icon == Icons.more_horiz) {
      return "More actions";
    }
    return "Icon action";
  }
}
