import 'package:flutter/material.dart';
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

    return Tooltip(
      message: widget.tooltip!,
      excludeFromSemantics: true,
      child: result,
    );
  }
}
