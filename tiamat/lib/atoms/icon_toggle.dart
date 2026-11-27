import 'package:flutter/material.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';
import 'icon_button.dart' as icon;
import 'tooltip.dart' as tiamat_tooltip;

import 'package:flutter/material.dart' as m;

@UseCase(name: 'Default', type: IconToggle)
Widget wbIconToggle(BuildContext context) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
            width: 50,
            height: 50,
            child: Center(
                child: IconToggle(
              icon: Icons.toggle_on,
              state: false,
              size: 20,
            ))),
      ],
    ),
  );
}

@UseCase(name: 'On', type: IconToggle)
Widget wbIconToggleOn(BuildContext context) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
            width: 50,
            height: 50,
            child: Center(
                child: IconToggle(
              icon: Icons.toggle_on,
              state: true,
              size: 20,
            ))),
      ],
    ),
  );
}

class IconToggle extends StatefulWidget {
  const IconToggle({
    super.key,
    this.size = 15,
    required this.icon,
    this.inactiveIcon,
    this.onPressed,
    this.state = false,
    this.backgroundColor = m.Colors.transparent,
    this.activeIconColor,
    this.inactiveIconColor,
    this.semanticLabel,
    this.semanticHint,
    this.tooltip,
    this.tooltipDirection = AxisDirection.up,
    this.onLabel = 'On',
    this.offLabel = 'Off',
    this.minimumSize,
  });

  final double size;
  final Function(bool newState)? onPressed;
  final m.IconData icon;
  final m.IconData? inactiveIcon;
  final m.Color backgroundColor;
  final m.Color? activeIconColor;
  final m.Color? inactiveIconColor;
  final bool state;
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

  final String onLabel;
  final String offLabel;
  final double? minimumSize;

  @override
  State<IconToggle> createState() => _IconToggleState();
}

class _IconToggleState extends State<IconToggle> {
  bool get _enabled => widget.onPressed != null;

  void _activate() {
    if (!_enabled) {
      return;
    }
    widget.onPressed?.call(!widget.state);
  }

  @override
  Widget build(BuildContext context) {
    final theme = m.Theme.of(context);
    final value = widget.state ? widget.onLabel : widget.offLabel;
    final semanticLabel = widget.semanticLabel ??
        widget.tooltip ??
        _defaultToggleLabel(widget.icon);

    final button = icon.IconButton(
      icon: widget.state
          ? widget.icon
          : widget.inactiveIcon ?? _defaultInactiveIcon(widget.icon),
      size: widget.size,
      iconColor: widget.state
          ? widget.activeIconColor ?? theme.colorScheme.primary
          : widget.inactiveIconColor ?? theme.colorScheme.onSurfaceVariant,
      onPressed: _enabled ? _activate : null,
      backgroundColor: widget.backgroundColor,
      minimumSize: widget.minimumSize,
    );

    Widget result = Semantics(
      label: semanticLabel,
      value: value,
      hint: widget.semanticHint,
      toggled: widget.state,
      button: true,
      enabled: _enabled,
      onTap: _enabled ? _activate : null,
      child: ExcludeSemantics(child: button),
    );

    if (widget.tooltip != null) {
      // See tiamat/atoms/icon_button.dart for why excludeFromSemantics is
      // true here: `semanticLabel` above is `semanticLabel ?? tooltip ??
      // default`, the same string, so announcing twice is the risk.
      result = tiamat_tooltip.Tooltip(
        text: widget.tooltip!,
        preferredDirection: widget.tooltipDirection,
        excludeFromSemantics: true,
        child: result,
      );
    }

    return result;
  }
}

m.IconData _defaultInactiveIcon(m.IconData iconData) {
  if (iconData == m.Icons.favorite || iconData == m.Icons.favorite_rounded) {
    return m.Icons.favorite_border;
  }
  if (iconData == m.Icons.public || iconData == m.Icons.public_rounded) {
    return m.Icons.public_off;
  }
  if (iconData == m.Icons.visibility ||
      iconData == m.Icons.visibility_rounded) {
    return m.Icons.visibility_off;
  }
  if (iconData == m.Icons.notifications ||
      iconData == m.Icons.notifications_rounded) {
    return m.Icons.notifications_off;
  }
  if (iconData == m.Icons.volume_up || iconData == m.Icons.volume_up_rounded) {
    return m.Icons.volume_off;
  }
  if (iconData == m.Icons.mic || iconData == m.Icons.mic_rounded) {
    return m.Icons.mic_off;
  }
  if (iconData == m.Icons.videocam || iconData == m.Icons.videocam_rounded) {
    return m.Icons.videocam_off;
  }
  if (iconData == m.Icons.toggle_on) {
    return m.Icons.toggle_off;
  }
  return iconData;
}

String _defaultToggleLabel(m.IconData iconData) {
  if (iconData == m.Icons.favorite ||
      iconData == m.Icons.favorite_rounded ||
      iconData == m.Icons.favorite_border) {
    return 'Favorite';
  }
  if (iconData == m.Icons.public ||
      iconData == m.Icons.public_rounded ||
      iconData == m.Icons.public_off) {
    return 'Public';
  }
  return icon.defaultTiamatIconActionLabel(iconData);
}
