import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_room_card.dart';

/// Responsive Inbox content shared by the desktop overlay and mobile page.
class InboxView extends StatelessWidget {
  const InboxView({
    required this.state,
    required this.isMasked,
    required this.onFilterChanged,
    required this.onOpen,
    required this.onMarkAllRead,
    required this.onRetry,
    super.key,
  });

  final InboxState state;
  final bool Function(InboxRoomSnapshot snapshot) isMasked;
  final ValueChanged<InboxFilter> onFilterChanged;
  final void Function(InboxRoomSnapshot snapshot, InboxEventSnapshot event)
  onOpen;
  final VoidCallback onMarkAllRead;

  /// Awaitable on purpose. RefreshIndicator keeps its spinner up until this
  /// future completes, so a fire-and-forget callback would dismiss the spinner
  /// the instant the gesture ended and report success before the refresh had
  /// run.
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final snapshots = state.visibleSnapshots;
    final tagged = state.filter == InboxFilter.tagged;
    final markAllLabel = tagged ? 'Mark tagged as read' : 'Mark all as read';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              SegmentedButton<InboxFilter>(
                segments: const [
                  ButtonSegment(
                    value: InboxFilter.all,
                    label: Text('All'),
                    icon: Icon(Icons.inbox_outlined),
                  ),
                  ButtonSegment(
                    value: InboxFilter.tagged,
                    label: Text('Tagged me'),
                    icon: Icon(Icons.alternate_email_rounded),
                  ),
                ],
                selected: {state.filter},
                onSelectionChanged: (selection) =>
                    onFilterChanged(selection.single),
              ),
              Tooltip(
                message: tagged
                    ? 'Marks only the displayed direct mentions as read'
                    : 'Marks every displayed Inbox conversation as read',
                child: FilledButton.icon(
                  onPressed: snapshots.isEmpty ? null : onMarkAllRead,
                  icon: const Icon(Icons.done_all_rounded),
                  label: Text(markAllLabel),
                ),
              ),
            ],
          ),
        ),
        if (state.hasError) _InboxErrorBanner(onRetry: onRetry),
        if (state.isLoading && snapshots.isEmpty)
          const Expanded(child: _InboxLoadingState())
        else if (snapshots.isEmpty)
          Expanded(child: _InboxEmptyState(isTagged: tagged))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRetry,
              child: ListView.separated(
                key: PageStorageKey<String>('inbox-${state.filter.name}'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                itemCount: snapshots.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final snapshot = snapshots[index];
                  // InboxQuery only keeps Tagged rows that have a direct
                  // mention. Retaining this fallback keeps a transient/stale
                  // view-model from crashing while its source refreshes.
                  final event = state.filter == InboxFilter.tagged
                      ? snapshot.newestDirectMention ??
                            snapshot.newestUnreadEvent
                      : snapshot.newestUnreadEvent;
                  return InboxRoomCard(
                    key: ValueKey(snapshot.localRoomId),
                    snapshot: snapshot,
                    event: event,
                    isMasked: isMasked(snapshot),
                    onOpen: () => onOpen(snapshot, event),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _InboxLoadingState extends StatelessWidget {
  const _InboxLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Loading Inbox',
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _InboxEmptyState extends StatelessWidget {
  const _InboxEmptyState({required this.isTagged});

  final bool isTagged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              isTagged ? 'No unread direct mentions' : 'Your Inbox is clear',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              isTagged
                  ? 'Room-wide alerts remain in the sidebar.'
                  : 'Unread rooms and direct messages will appear here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxErrorBanner extends StatelessWidget {
  const _InboxErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Inbox could not refresh. Your current list is still available.',
                ),
              ),
              TextButton(
                onPressed: () => unawaited(onRetry()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
