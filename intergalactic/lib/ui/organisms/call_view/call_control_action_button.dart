import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CallControlActionButton extends StatelessWidget {
  const CallControlActionButton({
    required this.icon,
    required this.semanticLabel,
    this.tooltip,
    this.persistentLabel,
    this.onPressed,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final String? tooltip;
  final String? persistentLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final settings = AccessibilityScope.of(context);
    final enabled = onPressed != null;
    final borderRadius = BorderRadius.circular(12);
    final compactLabel = persistentLabel?.trim();
    final showPersistentLabel =
        settings.persistentActionLabels &&
        compactLabel != null &&
        compactLabel.isNotEmpty;

    Widget visual = _IconSurface(
      icon: icon,
      enabled: enabled,
      borderRadius: borderRadius,
    );

    if (showPersistentLabel) {
      visual = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PersistentLabel(compactLabel),
          const SizedBox(width: 8),
          visual,
        ],
      );
    }

    Widget region = AccessibleInteractiveRegion(
      semanticLabel: semanticLabel,
      onActivate: onPressed,
      enabled: enabled,
      excludeChildSemantics: true,
      borderRadius: borderRadius,
      minimumSize: 44,
      focusPadding: const EdgeInsets.all(2),
      child: visual,
    );

    return tiamat.Tooltip(text: tooltip ?? semanticLabel, child: region);
  }
}

class _IconSurface extends StatelessWidget {
  const _IconSurface({
    required this.icon,
    required this.enabled,
    required this.borderRadius,
  });

  final IconData icon;
  final bool enabled;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(enabled ? 110 : 65),
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 18,
          color: Colors.white.withAlpha(enabled ? 230 : 125),
        ),
      ),
    );
  }
}

class _PersistentLabel extends StatelessWidget {
  const _PersistentLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;

    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 118),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(118),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style:
                  style?.copyWith(
                    color: Colors.white.withAlpha(232),
                    fontWeight: FontWeight.w600,
                  ) ??
                  TextStyle(
                    color: Colors.white.withAlpha(232),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
