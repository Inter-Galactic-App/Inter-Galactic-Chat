import 'dart:math';

import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/seperator.dart';

class TimelineEventMenuDialog extends StatefulWidget {
  const TimelineEventMenuDialog(
      {required this.event,
      required this.timeline,
      required this.menu,
      super.key});

  final TimelineEvent event;
  final Timeline timeline;

  final TimelineEventMenu menu;

  @override
  State<TimelineEventMenuDialog> createState() =>
      _TimelineEventMenuDialogState();
}

class _TimelineEventMenuDialogState extends State<TimelineEventMenuDialog> {
  bool _showSecondaryActions = false;

  TimelineEvent get event => widget.event;
  Timeline get timeline => widget.timeline;
  TimelineEventMenu get menu => widget.menu;

  @override
  Widget build(BuildContext context) {
    return buildMessageMenu(context, event);
  }

  Widget buildMessageMenu(BuildContext context, TimelineEvent event) {
    final primaryActions = menu.primaryActions
        .where((entry) => entry.destructive == false)
        .toList(growable: false);
    final destructiveActions = [
      ...menu.primaryActions.where((entry) => entry.destructive),
      ...menu.secondaryActions.where((entry) => entry.destructive),
    ];
    final secondaryActions = menu.secondaryActions
        .where((entry) => entry.destructive == false)
        .toList(growable: false);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: ScaledSafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 34,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    _buildCard(
                      context,
                      child: _buildPreviewCard(context, event),
                    ),
                    if (menu.quickReactions.isNotEmpty ||
                        menu.addReactionAction != null) ...[
                      const SizedBox(height: 8),
                      _buildCard(
                        context,
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        child: _buildReactionRow(context, event),
                      ),
                    ],
                    if (primaryActions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildActionGroup(context, primaryActions),
                    ],
                    if (secondaryActions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (!_showSecondaryActions)
                        _buildActionGroup(
                          context,
                          [
                            TimelineEventMenuEntry(
                              name: "More Options",
                              icon: Icons.more_horiz,
                              action: (_) {
                                setState(() {
                                  _showSecondaryActions = true;
                                });
                              },
                            ),
                          ],
                        )
                      else
                        _buildActionGroup(context, secondaryActions),
                    ],
                    if (destructiveActions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildActionGroup(
                        context,
                        destructiveActions,
                        emphasizeDestructive: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context, TimelineEvent event) {
    final eventIndex = timeline.events.indexOf(event);
    final fallbackIndex = eventIndex >= 0
        ? eventIndex
        : timeline.events.indexWhere((entry) => entry.eventId == event.eventId);
    if (fallbackIndex < 0) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: true,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.86, 1.0],
          ).createShader(bounds);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: TimelineViewEntry(
              timeline: timeline,
              singleEvent: true,
              previewMedia: timeline.room.shouldPreviewMedia,
              initialIndex: fallbackIndex,
              showDetailed: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReactionRow(BuildContext context, TimelineEvent event) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;
        final totalRequested = menu.quickReactions.length +
            (menu.addReactionAction != null ? 1 : 0);
        final spacing = totalRequested > 6 ? 4.0 : 6.0;
        final maxSlots = max(
          1,
          ((availableWidth + spacing) / (28.0 + spacing)).floor(),
        );
        final addActionSlots = menu.addReactionAction != null ? 1 : 0;
        final maxReactionSlots = max(0, maxSlots - addActionSlots);
        final hiddenCount = max(
          0,
          menu.quickReactions.length - maxReactionSlots,
        );
        final showOverflowChip = hiddenCount > 0 && maxReactionSlots > 0;
        final visibleReactionCount =
            showOverflowChip ? max(0, maxReactionSlots - 1) : maxReactionSlots;
        final visibleReactions = menu.quickReactions
            .take(visibleReactionCount)
            .toList(growable: false);
        final renderedCount = visibleReactions.length +
            (showOverflowChip ? 1 : 0) +
            addActionSlots;
        if (renderedCount == 0) {
          return const SizedBox.shrink();
        }

        final chipSize =
            ((availableWidth - (spacing * (renderedCount - 1))) / renderedCount)
                .clamp(28.0, 34.0);
        final emojiSize = (chipSize * 0.58).clamp(18.0, 22.0);
        final iconSize = (chipSize * 0.52).clamp(16.0, 20.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < visibleReactions.length; i++) ...[
              if (i != 0) SizedBox(width: spacing),
              _buildReactionChip(
                context,
                size: chipSize,
                child: EmojiWidget(
                  visibleReactions[i],
                  height: emojiSize,
                ),
                onTap: () {
                  timeline.room.addReaction(event, visibleReactions[i]);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
            if (showOverflowChip) ...[
              if (visibleReactions.isNotEmpty) SizedBox(width: spacing),
              _buildReactionChip(
                context,
                size: chipSize,
                child: Text(
                  '+$hiddenCount',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                onTap: () {
                  final addReactionAction = menu.addReactionAction;
                  if (addReactionAction != null) {
                    doAction(addReactionAction, context);
                  }
                },
              ),
            ],
            if (menu.addReactionAction != null) ...[
              if (visibleReactions.isNotEmpty || showOverflowChip)
                SizedBox(width: spacing),
              _buildReactionChip(
                context,
                size: chipSize,
                child: Icon(
                  menu.addReactionAction!.icon,
                  size: iconSize,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onTap: () => doAction(menu.addReactionAction!, context),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildReactionChip(
    BuildContext context, {
    required Widget child,
    required VoidCallback onTap,
    required double size,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(size / 2),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildActionGroup(
    BuildContext context,
    List<TimelineEventMenuEntry> actions, {
    bool emphasizeDestructive = false,
  }) {
    return _buildCard(
      context,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            _buildActionRow(
              context,
              actions[i],
              emphasizeDestructive: emphasizeDestructive,
            ),
            if (i != actions.length - 1) const Seperator(),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    TimelineEventMenuEntry entry, {
    bool emphasizeDestructive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final destructive = emphasizeDestructive || entry.destructive;
    final foregroundColor =
        destructive ? scheme.error : scheme.onSurface.withValues(alpha: 0.96);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => doAction(entry, context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(
                entry.icon,
                size: 19,
                color: foregroundColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (entry.secondaryMenuBuilder != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required Widget child,
    EdgeInsets padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.94),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.24),
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  void doAction(TimelineEventMenuEntry entry, BuildContext context) async {
    if (entry.action != null) {
      entry.action?.call(context);
      return;
    }

    if (entry.secondaryMenuBuilder != null) {
      await showModalBottomSheet(
        context: context,
        builder: (newContext) {
          return entry.secondaryMenuBuilder!.call(newContext, () {
            Navigator.of(newContext).pop();
          });
        },
      );

      if (context.mounted) Navigator.of(context).pop();
    }
  }
}
