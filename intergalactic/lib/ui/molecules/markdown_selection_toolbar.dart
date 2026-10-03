import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MarkdownSelectionToolbarAction {
  const MarkdownSelectionToolbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class MarkdownSelectionToolbar extends StatelessWidget {
  const MarkdownSelectionToolbar({
    required this.anchors,
    this.formattingActions = const <MarkdownSelectionToolbarAction>[],
    this.standardActions = const <MarkdownSelectionToolbarAction>[],
    super.key,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<MarkdownSelectionToolbarAction> formattingActions;
  final List<MarkdownSelectionToolbarAction> standardActions;

  @override
  Widget build(BuildContext context) {
    final hasActions =
        formattingActions.isNotEmpty || standardActions.isNotEmpty;
    if (!hasActions) {
      return const SizedBox.shrink();
    }

    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: (_, child) => child,
      children: [
        _MarkdownSelectionToolbarBubble(
          formattingActions: formattingActions,
          standardActions: standardActions,
        ),
      ],
    );
  }
}

class _MarkdownSelectionToolbarBubble extends StatelessWidget {
  const _MarkdownSelectionToolbarBubble({
    required this.formattingActions,
    required this.standardActions,
  });

  final List<MarkdownSelectionToolbarAction> formattingActions;
  final List<MarkdownSelectionToolbarAction> standardActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = Color.alphaBlend(
      scheme.surfaceTint.withValues(alpha: 0.08),
      scheme.surfaceContainerHighest.withValues(alpha: 0.97),
    );

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final action in formattingActions)
                _MarkdownSelectionToolbarButton(action: action),
              if (formattingActions.isNotEmpty && standardActions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    width: 1,
                    height: 28,
                    color: scheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              for (final action in standardActions)
                _MarkdownSelectionToolbarButton(action: action),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkdownSelectionToolbarButton extends StatelessWidget {
  const _MarkdownSelectionToolbarButton({required this.action});

  final MarkdownSelectionToolbarAction action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return tiamat.Tooltip(
      text: action.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: action.onPressed,
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(action.icon, size: 18, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}
