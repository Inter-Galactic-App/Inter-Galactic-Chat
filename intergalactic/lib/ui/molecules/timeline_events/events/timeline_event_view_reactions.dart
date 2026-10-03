import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/atoms/emoji_reaction.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';

import 'package:flutter/material.dart' as material;

class TimelineEventViewReactions extends StatefulWidget {
  const TimelineEventViewReactions({
    required this.index,
    required this.timeline,
    this.updateRevision = 0,
    super.key,
  });

  final int index;

  /// Bumped by the owning timeline entry whenever the event at [index] is
  /// refreshed in place - a reaction added to an already-reacted message
  /// changes the event, not its index.
  final int updateRevision;
  final Timeline timeline;

  @override
  State<TimelineEventViewReactions> createState() =>
      _TimelineEventViewReactionsState();
}

class _TimelineEventViewReactionsState
    extends State<TimelineEventViewReactions> {
  Map<Emoticon, Set<String>>? reactions;

  /// Which reaction chips are highlighted as ours. Deliberately not `final`:
  /// this widget accepts a replacement timeline, and a replacement timeline may
  /// belong to a different client, in which case "us" is a different user.
  String? currentUserIdentifier;
  late TimelineEvent event;

  @override
  void initState() {
    currentUserIdentifier = widget.timeline.client.self?.identifier;
    setStateFromIndex(widget.index);
    super.initState();
  }

  @override
  void didUpdateWidget(TimelineEventViewReactions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.timeline != oldWidget.timeline) {
      currentUserIdentifier = widget.timeline.client.self?.identifier;
    }
    if (widget.index != oldWidget.index ||
        widget.updateRevision != oldWidget.updateRevision ||
        widget.timeline != oldWidget.timeline) {
      setStateFromIndex(widget.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (reactions == null) {
      return Container();
    }

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      direction: material.Axis.horizontal,
      children: reactions!.keys.map((key) {
        final reactionEvent = event;
        var value = reactions![key]!;
        final members =
            value
                .map(widget.timeline.room.getMemberOrFallback)
                .toList(growable: false)
              ..sort((a, b) => a.displayName.compareTo(b.displayName));

        final reactionChip = EmojiReaction(
          emoji: key,
          onTapped: (emote) => onReactionTapped(reactionEvent, emote),
          onLongPressed: Layout.mobile
              ? (_) => showReactionUsers(context, key, members)
              : null,
          numReactions: value.length,
          highlighted: value.contains(currentUserIdentifier),
        );

        if (Layout.mobile) {
          return reactionChip;
        }

        return JustTheTooltip(
          preferredDirection: AxisDirection.up,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          tailLength: 10,
          tailBaseWidth: 14,
          offset: 6,
          triggerMode: TooltipTriggerMode.longPress,
          content: _ReactionUsersTooltip(emoji: key, members: members),
          child: reactionChip,
        );
      }).toList(),
    );
  }

  void showReactionUsers(
    BuildContext context,
    Emoticon emoji,
    List<Member> members,
  ) {
    showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      elevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: _ReactionUsersTooltip(emoji: emoji, members: members),
        ),
      ),
    );
  }

  void onReactionTapped(TimelineEvent targetEvent, Emoticon emote) {
    if (reactions == null) {
      return;
    }

    if (reactions![emote]?.contains(currentUserIdentifier) == true) {
      widget.timeline.room.removeReaction(targetEvent, emote);
    } else {
      widget.timeline.room.addReaction(targetEvent, emote);
    }
  }

  void setStateFromIndex(int index) {
    if (!mounted) return;
    if (index < 0 || index >= widget.timeline.events.length) {
      setState(() {
        reactions = null;
      });
      return;
    }

    setState(() {
      final currentEvent = widget.timeline.events[index];
      event = currentEvent;
      if (currentEvent is TimelineEventFeatureReactions) {
        reactions = (currentEvent as TimelineEventFeatureReactions)
            .getReactions(widget.timeline);
      } else {
        reactions = null;
      }
    });
  }
}

class _ReactionUsersTooltip extends StatelessWidget {
  const _ReactionUsersTooltip({required this.emoji, required this.members});

  final Emoticon emoji;
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 280),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmojiWidget(emoji, height: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${members.length} ${members.length == 1 ? "reaction" : "reactions"}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: members
                        .map(
                          (member) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: UserPanelView(
                              avatar: member.avatar,
                              avatarColor: member.defaultColor,
                              nameColor: member.defaultColor,
                              displayName: member.displayName,
                              detail: member.identifier,
                              avatarSize: 14,
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
