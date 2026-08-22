import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_message_preview.dart';

/// One rooms-first Inbox row.
///
/// The enclosing page supplies the normal room-selection callback, keeping
/// Inbox presentation independent of main-page navigation ownership.
class InboxRoomCard extends StatelessWidget {
  const InboxRoomCard({
    required this.snapshot,
    required this.event,
    required this.isMasked,
    required this.onOpen,
    super.key,
  });

  final InboxRoomSnapshot snapshot;
  final InboxEventSnapshot event;
  final bool isMasked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(event.timestamp.toLocal()));
    final unreadLabel = snapshot.unreadCount == 1
        ? '1 unread message'
        : '${snapshot.unreadCount} unread messages';

    // `container: true` so the card is one node with an explicit boundary
    // rather than a label that merges into whatever encloses it.
    //
    // Deliberately NOT `excludeSemantics: true`. That would present the card as
    // a single node, which is the tidier tree, but it also erases the message
    // preview text and the "Open full message" button inside
    // [InboxMessagePreview] - real content and a real second action, not
    // decoration. The duplication this row actually had is handled at the two
    // nodes that caused it: the room-name Text and [_UnreadCount] are excluded
    // individually, because those are the only two facts the label above
    // already states.
    return Semantics(
      container: true,
      button: true,
      label: '${snapshot.roomName}, $unreadLabel',
      hint: 'Open newest unread message',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // The row's own Semantics already opens with the room
                    // name; without this the merged announcement says it
                    // twice.
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          snapshot.roomName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(time, style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(width: 8),
                    _UnreadCount(count: snapshot.unreadCount),
                  ],
                ),
                const SizedBox(height: 8),
                if (!isMasked) ...[
                  Text(
                    event.senderId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                ],
                InboxMessagePreview(
                  event: event,
                  isMasked: isMasked,
                  onOpenMessage: onOpen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadCount extends StatelessWidget {
  const _UnreadCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final display = count > 99 ? '99+' : '$count';
    // Purely visual. The enclosing card's Semantics states the count as part
    // of its summary label, and this node used to restate it through a
    // Semantics wrapper of its own - so the merged announcement carried the
    // unread count twice.
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(
            display,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}
