import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_sources.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_view.dart';

/// The adaptive route body for Inbox.
///
/// Main-page code supplies [onOpen] so room selection and eventual event-jump
/// stay in the existing lock-aware navigation owner.
class InboxPage extends StatefulWidget {
  const InboxPage({
    required this.clientManager,
    required this.onOpen,
    this.filterClient,
    super.key,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final Future<bool> Function(
    InboxRoomSnapshot snapshot,
    InboxEventSnapshot event,
  )
  onOpen;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  late final InboxStateController _stateController;
  final InboxReadController _readController = InboxReadController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _stateController = InboxStateController();
    _subscribe();
    unawaited(_setSources());
  }

  @override
  void didUpdateWidget(covariant InboxPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clientManager, widget.clientManager) ||
        !identical(oldWidget.filterClient, widget.filterClient)) {
      _cancelSubscriptions();
      _subscribe();
      unawaited(_setSources());
    }
  }

  void _subscribe() {
    _subscriptions.addAll(
      subscribeToInboxSourceChanges(
        widget.clientManager,
        () => unawaited(_setSources()),
      ),
    );
    // Masking, not membership - so it stays here rather than in the shared set.
    _subscriptions.add(
      dmLockController.onChanged.listen((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  /// Rooms by `localId`, rebuilt whenever the source set is.
  ///
  /// `_roomFor` used to scan every room in the manager, and `isMasked` calls it
  /// once per rendered card on every build while `_markAllRead` repeats it per
  /// target - so the cost was O(cards x rooms) per frame. Every mutation that
  /// can change the room set already funnels through `_setSources`, so that is
  /// the one place the index has to be kept honest.
  final Map<String, Room> _roomsByLocalId = <String, Room>{};

  Future<void> _setSources() {
    _roomsByLocalId
      ..clear()
      ..addEntries(
        widget.clientManager.rooms.map(
          (room) => MapEntry<String, Room>(room.localId, room),
        ),
      );
    return _stateController.setSources(
      inboxSourcesFor(widget.clientManager, filterClient: widget.filterClient),
    );
  }

  Room? _roomFor(InboxRoomSnapshot snapshot) =>
      _roomsByLocalId[snapshot.localRoomId];

  bool _isMasked(InboxRoomSnapshot snapshot) {
    final room = _roomFor(snapshot);
    return room == null || dmLockController.shouldMaskRoomPreview(room);
  }

  Future<void> _markAllRead(InboxState state) async {
    final targets = <InboxReadTarget>[];
    for (final snapshot in state.visibleSnapshots) {
      final room = _roomFor(snapshot);
      if (room is InboxSnapshotProvider) {
        targets.add(
          InboxReadTarget(
            provider: room as InboxSnapshotProvider,
            snapshot: snapshot,
          ),
        );
      }
    }
    final result = await _readController.markAll(targets);
    if (!mounted) return;
    await _stateController.refresh();
    if (!mounted || result.failedCount == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.failedCount == 1
              ? 'One conversation could not be marked as read.'
              : '${result.failedCount} conversations could not be marked as read.',
        ),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {
            unawaited(_retryFailedReads());
          },
        ),
      ),
    );
  }

  Future<void> _retryFailedReads() async {
    await _readController.retryFailures();
    if (mounted) await _stateController.refresh();
  }

  Future<void> _open(
    InboxRoomSnapshot snapshot,
    InboxEventSnapshot event,
  ) async {
    final opened = await widget.onOpen(snapshot, event);
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    // Staying open is right - the row is still there to retry - but silence is
    // not. The jump can fail because the room went away, the account switch
    // was superseded, or the timeline listener never arrived, and none of
    // those are visible to someone who just tapped a conversation and saw
    // nothing happen.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not open ${snapshot.roomName}. It may have been left or '
          'archived.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _stateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          IconButton(
            tooltip: 'Close Inbox',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: ValueListenableBuilder<InboxState>(
        valueListenable: _stateController,
        builder: (context, state, _) {
          return InboxView(
            state: state,
            isMasked: _isMasked,
            onFilterChanged: _stateController.setFilter,
            onOpen: (snapshot, event) => unawaited(_open(snapshot, event)),
            onMarkAllRead: () => unawaited(_markAllRead(state)),
            onRetry: _stateController.refresh,
          );
        },
      ),
    );
  }
}
