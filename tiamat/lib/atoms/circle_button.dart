import 'package:flutter/material.dart';
import 'package:tiamat/atoms/tooltip.dart' as tiamat_tooltip;
import 'package:flutter/services.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

import 'icon_button.dart';
import '../config/style/theme_extensions.dart';

@UseCase(name: 'Default', type: CircleButton)
Widget wbcircleButton(BuildContext context) {
  return const Center(
      child: CircleButton(
    radius: 25,
    icon: Icons.add,
  ));
}

class CircleButton extends StatefulWidget {
  const CircleButton({
    super.key,
    this.radius = 15,
    this.icon,
    this.onPressed,
    this.color,
    this.iconColor,
    this.semanticLabel,
    this.semanticHint,
    this.tooltip,
    this.tooltipDirection = AxisDirection.up,
    this.minimumSize,
  });

  final double radius;
  final Function? onPressed;
  final IconData? icon;
  final Color? color;
  final Color? iconColor;
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

  final double? minimumSize;

  @override
  State<CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<CircleButton> {
  bool focused = false;

  bool get enabled => widget.onPressed != null;

  void _activate() {
    if (!enabled) {
      return;
    }
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    var shadows = Theme.of(context).extension<ShadowSettings>();
    final theme = Theme.of(context);
    final visualSize = widget.radius * 2;
    final resolvedMinimumSize = widget.minimumSize ?? visualSize;
    final minimumSize =
        resolvedMinimumSize > defaultTiamatMinimumInteractiveDimension
            ? resolvedMinimumSize
            : defaultTiamatMinimumInteractiveDimension;
    final label = widget.semanticLabel ??
        widget.tooltip ??
        defaultTiamatIconActionLabel(widget.icon);

    final button = Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              _activate();
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onShowFocusHighlight: (value) {
            setState(() {
              focused = value;
            });
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minimumSize,
              minHeight: minimumSize,
            ),
            child: Center(
              child: SizedBox(
                width: minimumSize,
                height: minimumSize,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    canRequestFocus: false,
                    customBorder: const CircleBorder(),
                    splashColor: theme.colorScheme.onSecondaryContainer,
                    onTap: enabled ? _activate : null,
                    child: Center(
                      child: Ink(
                        width: visualSize,
                        height: visualSize,
                        decoration: BoxDecoration(
                          color: widget.color ??
                              theme.colorScheme.secondaryContainer,
                          shape: BoxShape.circle,
                          boxShadow: shadows?.shadows,
                          border: focused
                              ? Border.all(
                                  color: theme.colorScheme.outline,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: widget.icon != null
                            ? Align(
                                alignment: Alignment.center,
                                child: Icon(
                                  color: widget.iconColor ??
                                      theme.colorScheme.secondary,
                                  widget.icon,
                                  size: widget.radius,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final result = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: widget.semanticHint,
      onTap: enabled ? _activate : null,
      child: ExcludeSemantics(child: button),
    );

    if (widget.tooltip == null) {
      return result;
    }

    // House component rather than Material: app-surface colour, real
    // directional placement, and off OverlayPortal. See DECISIONS.md
    // 2026-08-18.
    //
    // excludeFromSemantics stays true and must. The Semantics wrapper directly
    // above already carries `label`, which is `semanticLabel ?? tooltip ??
    // default` - the same string the tooltip shows - so announcing it here too
    // would make a reader say it twice.
    return tiamat_tooltip.Tooltip(
      text: widget.tooltip!,
      preferredDirection: widget.tooltipDirection,
      excludeFromSemantics: true,
      child: result,
    );
  }
}
