import 'dart:async';

import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The Inbox modes are deliberately room-based. Tagged mode changes the event
/// shown for a room and omits rooms without a structured direct mention.
enum InboxFilter { all, tagged }

/// Supplies memory-only, cached unread data for one room implementation.
///
/// This is intentionally separate from the generic room contract. Background
/// notification rooms are read-only routing adapters and must not load Inbox
/// history.
abstract interface class InboxSnapshotProvider {
  Future<InboxRoomSnapshot?> getInboxSnapshot();

  Future<void> markInboxSnapshotRead(InboxRoomSnapshot snapshot);
}

/// Adds the stable identity and update stream needed by the in-app Inbox.
abstract interface class InboxRoomSource implements InboxSnapshotProvider {
  String get localRoomId;

  Stream<void> get onInboxSourceUpdate;
}

/// Memory-only presentation data for one cached unread Matrix event.
///
/// It intentionally has no serialization API. Inbox data must never become a
/// second local event store, diagnostic payload, or analytics record.
@immutable
class InboxEventSnapshot {
  const InboxEventSnapshot({
    required this.eventId,
    required this.timestamp,
    required this.senderId,
    required this.plainTextBody,
    required this.isDirectMention,
    this.cachedImagePreview,
    this.cachedUrlPreview,
    this.loadUrlPreview,
  });

  final String eventId;
  final DateTime timestamp;
  final String senderId;
  final String plainTextBody;
  final bool isDirectMention;
  final ImageProvider? cachedImagePreview;
  final UrlPreviewData? cachedUrlPreview;

  /// Resolves this event's URL preview only after its Inbox row becomes
  /// visible. The Matrix-backed implementation applies the same room-media and
  /// encrypted-room preview preferences as the conversation timeline.
  ///
  /// Keeping this as a lazy callback prevents a refresh of every Inbox source
  /// from turning into a network fan-out, while allowing a newly opened Inbox
  /// to show useful link context before its room is opened.
  final Future<UrlPreviewData?> Function()? loadUrlPreview;

  /// Matrix structured direct mentions only. Callers must pass the decoded
  /// `m.mentions.user_ids` values; display text and highlight counts are not
  /// valid substitutes.
  static bool isStructuredDirectMention({
    required Iterable<String> mentionedUserIds,
    required String selfId,
  }) => mentionedUserIds.contains(selfId);
}

/// Memory-only Inbox state for one account/room pair.
@immutable
class InboxRoomSnapshot {
  const InboxRoomSnapshot({
    required this.clientIdentifier,
    required this.roomId,
    required this.roomName,
    required this.unreadCount,
    required this.isSidebarEligible,
    required this.readTargetEventId,
    required this.newestUnreadEvent,
    this.newestDirectMention,
  });

  final String clientIdentifier;
  final String roomId;
  final String roomName;
  final int unreadCount;
  final bool isSidebarEligible;

  /// Frozen newest unread event ID used when marking this Inbox row as read.
  /// This can be newer than [newestUnreadEvent] when a state event follows the
  /// last renderable message, which is necessary for badge parity.
  final String readTargetEventId;
  final InboxEventSnapshot newestUnreadEvent;
  final InboxEventSnapshot? newestDirectMention;

  String get localRoomId => '$clientIdentifier:$roomId';
}

/// Pure ordering and filtering for cache-derived room snapshots.
class InboxQuery {
  const InboxQuery._();

  static List<InboxRoomSnapshot> select(
    Iterable<InboxRoomSnapshot> snapshots, {
    InboxFilter filter = InboxFilter.all,
  }) {
    final deduplicated = <String, InboxRoomSnapshot>{};

    for (final snapshot in snapshots) {
      if (!snapshot.isSidebarEligible ||
          (filter == InboxFilter.tagged &&
              snapshot.newestDirectMention == null)) {
        continue;
      }

      final existing = deduplicated[snapshot.localRoomId];
      if (existing == null ||
          eventFor(
            snapshot,
            filter,
          ).timestamp.isAfter(eventFor(existing, filter).timestamp)) {
        deduplicated[snapshot.localRoomId] = snapshot;
      }
    }

    final selected = deduplicated.values.toList()
      ..sort((a, b) {
        final timestampComparison = eventFor(
          b,
          filter,
        ).timestamp.compareTo(eventFor(a, filter).timestamp);
        return timestampComparison != 0
            ? timestampComparison
            : a.localRoomId.compareTo(b.localRoomId);
      });
    return List.unmodifiable(selected);
  }

  /// The event a row should display under [filter].
  ///
  /// `select` filters tagged rows to those that have a mention, but this is
  /// public and a snapshot can go stale between the two calls - `inbox_view`
  /// already carries a fallback for exactly that. Degrading to the unread event
  /// keeps one rule for both callers instead of throwing on the stale path.
  static InboxEventSnapshot eventFor(
    InboxRoomSnapshot snapshot,
    InboxFilter filter,
  ) => filter == InboxFilter.tagged
      ? (snapshot.newestDirectMention ?? snapshot.newestUnreadEvent)
      : snapshot.newestUnreadEvent;
}

@immutable
class InboxReadTarget {
  const InboxReadTarget({required this.provider, required this.snapshot});

  final InboxSnapshotProvider provider;
  final InboxRoomSnapshot snapshot;

  String get localRoomId => snapshot.localRoomId;
}

@immutable
class InboxMarkAllResult {
  const InboxMarkAllResult({
    required this.markedCount,
    required this.failedCount,
    required this.wasCancelled,
  });

  final int markedCount;
  final int failedCount;
  final bool wasCancelled;
}

/// Serializes targeted, visible-set Inbox read operations in memory.
class InboxReadController {
  Future<void> _tail = Future.value();
  final Map<String, InboxReadTarget> _failedTargets = {};

  Future<InboxMarkAllResult> markAll(
    Iterable<InboxReadTarget> targets, {
    bool Function()? isCancelled,
    void Function()? onMarked,
  }) {
    final selected = _deduplicate(targets);
    return _enqueue(() async {
      _failedTargets.clear();
      return _markTargets(
        selected,
        isCancelled: isCancelled,
        onMarked: onMarked,
      );
    });
  }

  Future<InboxMarkAllResult> retryFailures({
    bool Function()? isCancelled,
    void Function()? onMarked,
  }) {
    return _enqueue(() async {
      // Read INSIDE the enqueued closure. Reading at call time observed the
      // state before the operation ahead of this one in the queue had run, so
      // a retry issued while a markAll was still in flight saw an empty map,
      // marked nothing, reported markedCount: 0 - and then cleared the very
      // failures that markAll had just recorded, putting them beyond a second
      // retry as well.
      final failed = _failedTargets.values.toList(growable: false);
      _failedTargets.clear();
      return _markTargets(failed, isCancelled: isCancelled, onMarked: onMarked);
    });
  }

  Future<InboxMarkAllResult> _enqueue(
    Future<InboxMarkAllResult> Function() operation,
  ) {
    final result = _tail.catchError((_) {}).then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  Future<InboxMarkAllResult> _markTargets(
    Iterable<InboxReadTarget> targets, {
    bool Function()? isCancelled,
    void Function()? onMarked,
  }) async {
    var markedCount = 0;
    var wasCancelled = false;
    for (final target in targets) {
      if (isCancelled?.call() ?? false) {
        wasCancelled = true;
        break;
      }
      try {
        await target.provider.markInboxSnapshotRead(target.snapshot);
        markedCount++;
        onMarked?.call();
      } catch (_) {
        _failedTargets[target.localRoomId] = target;
      }
    }
    return InboxMarkAllResult(
      markedCount: markedCount,
      failedCount: _failedTargets.length,
      wasCancelled: wasCancelled,
    );
  }

  List<InboxReadTarget> _deduplicate(Iterable<InboxReadTarget> targets) {
    final selected = <String, InboxReadTarget>{};
    for (final target in targets) {
      selected.putIfAbsent(target.localRoomId, () => target);
    }
    return selected.values.toList(growable: false);
  }
}

@immutable
class InboxState {
  const InboxState({
    required this.filter,
    required this.allSnapshots,
    required this.visibleSnapshots,
    required this.isLoading,
    required this.hasError,
  });

  const InboxState.initial()
    : filter = InboxFilter.all,
      allSnapshots = const [],
      visibleSnapshots = const [],
      isLoading = false,
      hasError = false;

  final InboxFilter filter;
  final List<InboxRoomSnapshot> allSnapshots;
  final List<InboxRoomSnapshot> visibleSnapshots;
  final bool isLoading;
  final bool hasError;

  int get badgeCount => allSnapshots.length;
}

class _InboxSourceRefreshResult {
  const _InboxSourceRefreshResult.success(this.snapshot)
    : sourceId = null,
      failed = false;

  const _InboxSourceRefreshResult.failure(this.sourceId)
    : snapshot = null,
      failed = true;

  final String? sourceId;
  final InboxRoomSnapshot? snapshot;
  final bool failed;
}

/// Owns the cache-only Inbox source subscriptions for one displayed account
/// scope. The caller changes its sources when client/space filtering changes.
class InboxStateController extends ValueNotifier<InboxState> {
  InboxStateController() : super(const InboxState.initial());

  final Map<String, StreamSubscription<void>> _subscriptions = {};
  var _sources = <InboxRoomSource>[];
  var _allSnapshots = <InboxRoomSnapshot>[];
  var _generation = 0;
  var _disposed = false;

  /// Short enough to stay invisible, long enough to absorb one sync's burst of
  /// per-room update events.
  static const Duration _refreshDebounceWindow = Duration(milliseconds: 150);
  Timer? _refreshDebounce;

  Future<void> setSources(Iterable<InboxRoomSource> sources) async {
    final generation = ++_generation;
    await _cancelSubscriptions();
    if (_disposed || generation != _generation) return;

    final deduplicated = <String, InboxRoomSource>{};
    for (final source in sources) {
      deduplicated.putIfAbsent(source.localRoomId, () => source);
    }
    _sources = deduplicated.values.toList(growable: false);
    for (final source in _sources) {
      _subscriptions[source.localRoomId] = source.onInboxSourceUpdate.listen(
        (_) => _scheduleRefresh(),
      );
    }
    await refresh();
  }

  void setFilter(InboxFilter filter) {
    if (_disposed || value.filter == filter) return;
    _publish(
      filter: filter,
      isLoading: value.isLoading,
      hasError: value.hasError,
    );
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    _publish(isLoading: true, hasError: false);
    final results = await Future.wait(
      _sources.map((source) async {
        try {
          return _InboxSourceRefreshResult.success(
            await source.getInboxSnapshot(),
          );
        } catch (_) {
          return _InboxSourceRefreshResult.failure(source.localRoomId);
        }
      }),
    );
    if (_disposed || generation != _generation) return;

    final previousById = {
      for (final snapshot in _allSnapshots) snapshot.localRoomId: snapshot,
    };
    final snapshots = <InboxRoomSnapshot>[];
    var hasError = false;
    for (final result in results) {
      if (result.failed) {
        hasError = true;
        final previous = previousById[result.sourceId];
        if (previous != null) snapshots.add(previous);
      } else if (result.snapshot case final snapshot?) {
        snapshots.add(snapshot);
      }
    }
    _allSnapshots = snapshots;
    _publish(isLoading: false, hasError: hasError);
  }

  /// Collapses a burst of source updates into one refresh pass.
  ///
  /// Every update event used to start a full [refresh], and refresh queries
  /// EVERY registered source - each of which reads up to 250 cached events for
  /// its room. One sync touching N rooms therefore did N passes over N sources,
  /// so the cost of a sync grew with the square of the rooms it touched. The
  /// window is short enough to stay invisible and long enough to absorb a sync.
  void _scheduleRefresh() {
    if (_disposed) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_refreshDebounceWindow, () {
      _refreshDebounce = null;
      if (!_disposed) unawaited(refresh());
    });
  }

  void _publish({
    InboxFilter? filter,
    required bool isLoading,
    required bool hasError,
  }) {
    final nextFilter = filter ?? value.filter;
    final allSnapshots = List<InboxRoomSnapshot>.unmodifiable(_allSnapshots);
    value = InboxState(
      filter: nextFilter,
      allSnapshots: allSnapshots,
      visibleSnapshots: InboxQuery.select(allSnapshots, filter: nextFilter),
      isLoading: isLoading,
      hasError: hasError,
    );
  }

  Future<void> _cancelSubscriptions() async {
    final subscriptions = _subscriptions.values.toList(growable: false);
    _subscriptions.clear();
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}
