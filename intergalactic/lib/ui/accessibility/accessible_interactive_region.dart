import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';

class AccessibleInteractiveRegion extends StatefulWidget {
  const AccessibleInteractiveRegion({
    required this.child,
    this.onActivate,
    this.semanticLabel,
    this.semanticHint,
    this.semanticValue,
    this.semanticOnTapHint,
    this.toggled,
    this.expanded,
    this.selected = false,
    this.enabled = true,
    this.button = true,
    this.excludeChildSemantics = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.minimumSize,
    this.enforceLargeTarget = true,
    this.focusPadding = EdgeInsets.zero,
    this.persistentLabel,
    this.persistentLabelSpacing = 6,
    this.persistentLabelMaxWidth = 160,
    super.key,
  });

  final Widget child;
  final VoidCallback? onActivate;
  final String? semanticLabel;
  final String? semanticHint;
  final String? semanticValue;
  final String? semanticOnTapHint;
  final bool? toggled;
  final bool? expanded;
  final bool selected;
  final bool enabled;
  final bool button;
  final bool excludeChildSemantics;
  final BorderRadiusGeometry borderRadius;
  final double? minimumSize;
  final bool enforceLargeTarget;
  final EdgeInsetsGeometry focusPadding;
  final String? persistentLabel;
  final double persistentLabelSpacing;
  final double persistentLabelMaxWidth;

  @override
  State<AccessibleInteractiveRegion> createState() =>
      _AccessibleInteractiveRegionState();
}

class _AccessibleInteractiveRegionState
    extends State<AccessibleInteractiveRegion> {
  bool _focused = false;

  bool get _canActivate => widget.enabled && widget.onActivate != null;

  @override
  Widget build(BuildContext context) {
    final settings = AccessibilityScope.of(context);
    final tokens = AccessibilityScope.tokensOf(context);
    final minimumSize = widget.enforceLargeTarget && settings.largerTouchTargets
        ? math.max(
            widget.minimumSize ?? 0,
            tokens.minimumInteractiveDimension,
          )
        : widget.minimumSize;
    final showFocus = _focused;
    final focusWidth = settings.strongFocusIndicators ? 3.0 : 2.0;
    final duration = settings.reduceMotion
        ? Duration.zero
        : InterGalacticMotion.duration(context, InterGalacticMotion.short);

    Widget visualChild = widget.child;
    final persistentLabel = widget.persistentLabel?.trim();

    if (settings.persistentActionLabels &&
        persistentLabel != null &&
        persistentLabel.isNotEmpty) {
      visualChild = _PersistentActionLabel(
        label: persistentLabel,
        spacing: widget.persistentLabelSpacing,
        maxWidth: widget.persistentLabelMaxWidth,
        child: visualChild,
      );
    }

    Widget result = Padding(
      padding: widget.focusPadding,
      child: AnimatedContainer(
        duration: duration,
        curve: InterGalacticMotion.standardOut,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: showFocus
              ? Border.all(
                  color: tokens.focusRing,
                  width: focusWidth,
                  strokeAlign: BorderSide.strokeAlignOutside,
                )
              : null,
        ),
        child: minimumSize == null
            ? visualChild
            : ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: minimumSize,
                  minHeight: minimumSize,
                ),
                child: Align(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: visualChild,
                ),
              ),
      ),
    );

    if (widget.onActivate != null ||
        widget.semanticLabel != null ||
        widget.semanticHint != null ||
        widget.semanticValue != null ||
        widget.toggled != null ||
        widget.expanded != null ||
        widget.selected ||
        !widget.enabled ||
        widget.semanticOnTapHint != null) {
      result = Semantics(
        label: widget.semanticLabel,
        hint: widget.semanticHint,
        value: widget.semanticValue,
        onTapHint: widget.semanticOnTapHint,
        toggled: widget.toggled,
        expanded: widget.expanded,
        button: widget.button,
        selected: widget.selected,
        enabled: widget.enabled,
        onTap: _canActivate ? widget.onActivate : null,
        container: true,
        excludeSemantics: widget.excludeChildSemantics,
        child: result,
      );
    }

    if (!_canActivate) {
      return result;
    }

    result = GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: widget.onActivate,
      child: result,
    );

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onActivate?.call();
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          enabled: widget.enabled,
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (focused) {
            if (mounted) {
              setState(() => _focused = focused);
            }
          },
          child: result,
        ),
      ),
    );
  }
}

class _PersistentActionLabel extends StatelessWidget {
  const _PersistentActionLabel({
    required this.child,
    required this.label,
    required this.spacing,
    required this.maxWidth,
  });

  final Widget child;
  final String label;
  final double spacing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        child,
        SizedBox(width: spacing),
        ExcludeSemantics(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
