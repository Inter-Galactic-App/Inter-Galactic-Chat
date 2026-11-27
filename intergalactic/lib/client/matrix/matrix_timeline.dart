import 'dart:async';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_timeline_rows.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/timeline_events/local_media_send_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/debug/log.dart';

import '../client.dart';
import 'room_open_decrypt_retry.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixTimeline extends Timeline {
  matrix.Timeline? _matrixTimeline;
  late matrix.Room _matrixRoom;

  late MatrixRoom _room;

  final StreamController<void> _loadingStatusChangedController =
      StreamController.broadcast();

  @override
  Stream<void> get onLoadingStatusChanged =>
      _loadingStatusChangedController.stream;

  matrix.Timeline? get matrixTimeline => _matrixTimeline;

  MatrixTimeline(
    MatrixClient client,
    MatrixRoom room,
    matrix.Room matrixRoom, {
    matrix.Timeline? initialTimeline,
  }) {
    events = List.empty(growable: true);
    _matrixRoom = matrixRoom;
    this.client = client;
    this.room = room;
    _room = room;
    _matrixTimeline = initialTimeline;

    if (_matrixTimeline != null) {
      convertAllTimelineEvents();
    }
  }

  Future<void> initTimeline({String? contextEventId}) async {
    _matrixTimeline = await _matrixRoom.getTimeline(
      onInsert: onEventInserted,
      onChange: onEventChanged,
      onRemove: onEventRemoved,
      eventContextId: contextEventId,
    );

    if (_matrixTimeline?.events.isEmpty == true) {
      await _matrixTimeline?.requestHistory(filter: timelineRowFilter());
    }

    _matrixRoom.postLoad();

    // This could maybe make load times realllly slow if we have a ton of stuff in the cache?
    // Might be better to only convert as many as we would need to display immediately and then convert the rest on demand
    convertAllTimelineEvents();
  }

  void convertAllTimelineEvents() {
    for (final matrixEvent in _matrixTimeline!.events) {
      if (isHiddenTimelineEventType(matrixEvent.type)) {
        continue;
      }
      insertEvent(events.length, _room.convertEvent(matrixEvent));
    }
  }

  void onEventInserted(index) {
    if (_matrixTimeline == null) return;
    final matrixEvent = _matrixTimeline!.events[index];
    if (isHiddenTimelineEventType(matrixEvent.type)) {
      return;
    }

    insertEvent(
      _eventListInsertIndexForMatrixIndex(index),
      _room.convertEvent(matrixEvent),
    );
  }

  void onEventChanged(index) {
    if (_matrixTimeline == null) return;

    if (index < _matrixTimeline!.events.length) {
      final matrixEvent = _matrixTimeline!.events[index];
      if (isHiddenTimelineEventType(matrixEvent.type)) {
        return;
      }

      final eventIndex = _eventListIndexForMatrixIndex(index);
      if (eventIndex == -1) {
        return;
      }

      events[eventIndex] = (room as MatrixRoom).convertEvent(
        matrixEvent,
        timeline: _matrixTimeline,
      );

      notifyChanged(eventIndex);
    }
  }

  void onEventRemoved(index) {
    // The SDK has already taken the event out of its list, so its type cannot
    // be read here. The row that WOULD be its row is found the usual way, then
    // checked against the SDK list: if the SDK still holds that row's event,
    // what was removed had no row, and nothing here should move.
    final eventIndex = _eventListIndexForMatrixIndex(
      index,
      checkTargetHidden: false,
    );
    if (eventIndex == -1) {
      return;
    }

    final rowEventId = events[eventIndex].eventId;
    final stillHeld =
        _matrixTimeline?.events.any(
          (e) => e.matchesEventOrTransactionId(rowEventId),
        ) ??
        false;
    if (stillHeld) {
      return;
    }

    removeEvent(rowEventId);
  }

  bool _matrixEventIsHidden(int matrixIndex) =>
      isHiddenTimelineEventType(_matrixTimeline!.events[matrixIndex].type);

  bool _rowIsMatrixEvent(int row) => events[row] is MatrixTimelineEvent;

  int _eventListInsertIndexForMatrixIndex(int matrixIndex) {
    return rowInsertIndexForMatrixRowNumber(
      matrixRowNumber: visibleMatrixEventsBefore(
        matrixIndex: matrixIndex,
        matrixEventIsHidden: _matrixEventIsHidden,
      ),
      rowCount: events.length,
      rowIsMatrixEvent: _rowIsMatrixEvent,
    );
  }

  int _eventListIndexForMatrixIndex(
    int matrixIndex, {
    bool checkTargetHidden = true,
  }) {
    final matrixEvents = _matrixTimeline!.events;
    if (matrixIndex < 0 || matrixIndex > matrixEvents.length) {
      return -1;
    }
    if (checkTargetHidden &&
        (matrixIndex == matrixEvents.length ||
            _matrixEventIsHidden(matrixIndex))) {
      return -1;
    }

    return rowOfMatrixRowNumber(
      matrixRowNumber: visibleMatrixEventsBefore(
        matrixIndex: matrixIndex,
        matrixEventIsHidden: _matrixEventIsHidden,
      ),
      rowCount: events.length,
      rowIsMatrixEvent: _rowIsMatrixEvent,
    );
  }

  @override
  Future<void> loadMoreHistory() async {
    if (_matrixTimeline?.canRequestHistory == true) {
      var f = _matrixTimeline!.requestHistory(filter: timelineRowFilter());
      _loadingStatusChangedController.add(null);

      await f;
      await roomOpenDecryptRetryCoordinator.maybeRetryForLoadedTimeline(
        this,
        trigger: 'matrix_timeline_history_pagination',
      );
    }
    _loadingStatusChangedController.add(null);
  }

  @override
  bool get canLoadFuture => _matrixTimeline?.canRequestFuture ?? false;

  @override
  bool get canLoadHistory => _matrixTimeline?.canRequestHistory ?? false;

  @override
  bool get isLoadingFuture => _matrixTimeline?.isRequestingFuture ?? false;

  @override
  bool get isLoadingHistory => _matrixTimeline?.isRequestingHistory ?? false;

  @override
  Future<void> loadMoreFuture() async {
    if (canLoadFuture) {
      var f = _matrixTimeline?.requestFuture(filter: timelineRowFilter());

      _loadingStatusChangedController.add(null);
      await f;
    }
  }

  @override
  void markAsRead(TimelineEvent event) async {
    var receipts = room.getComponent<MatrixReadReceiptComponent>();

    // Always send the read marker so the notification badge clears immediately.
    // The badge is server-driven and only resets when the homeserver receives
    // setReadMarker; waiting for a synced/sent event status check meant that
    // rooms whose most recent event is a state event (join, topic change, etc.)
    // never cleared the badge at all.
    try {
      await _matrixTimeline?.setReadMarker(
        public: receipts?.usePublicReadReceiptsForRoom,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to send Matrix read marker',
        category: LogCategory.matrix,
        source: 'read-marker',
      );
    }

    // Only send a full private read receipt for confirmed events (not local
    // echo still in flight) to avoid sending invalid event IDs to the server.
    if (event.status == TimelineEventStatus.synced ||
        event.status == TimelineEventStatus.sent ||
        event.status == TimelineEventStatus.roomState) {
      try {
        receipts?.handleEvent(event.eventId, room.client.self!.identifier);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to update local Matrix read receipt state',
          category: LogCategory.matrix,
          source: 'read-marker',
        );
      }
    }
  }

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async {
    var event = await (client as MatrixClient)
        .runWithSessionRepairOnUnknownToken(
          'fetching timeline event $eventId for ${_matrixRoom.id}',
          () => _matrixRoom.getEventById(eventId),
        );
    if (event == null) return null;
    return _room.convertEvent(event);
  }

  Future<void> removeReaction(
    TimelineEvent reactingTo,
    Emoticon reaction,
  ) async {
    // Prefer fetching from the live timeline (has aggregated events already indexed)
    // so that aggregatedEvents() works correctly without needing a server round-trip.
    var event =
        await _matrixTimeline!.getEventById(reactingTo.eventId) ??
        await _matrixRoom.getEventById(reactingTo.eventId);
    if (event == null) return;

    if (!event.hasAggregatedEvents(
      _matrixTimeline!,
      matrix.RelationshipTypes.reaction,
    ))
      return;

    var events = event
        .aggregatedEvents(_matrixTimeline!, matrix.RelationshipTypes.reaction)
        .where((element) => element.senderId == _matrixRoom.client.userID);

    // Normalize emoji key: strip Unicode variation selectors (U+FE0F / U+FE0E)
    // to handle cases where the reaction was sent with a different form than stored.
    String normalizeKey(String key) =>
        key.replaceAll('\uFE0F', '').replaceAll('\uFE0E', '');
    final targetKey = normalizeKey(reaction.key);

    for (var e in events) {
      if (!e.content.containsKey("m.relates_to")) continue;
      var content = e.content["m.relates_to"] as Map<String, Object?>;

      if (content.containsKey("key")) {
        final eventKey = normalizeKey(content["key"] as String);
        if (eventKey == targetKey) {
          await _matrixRoom.redactEvent(e.eventId);
          return;
        }
      }
    }
  }

  @override
  Future<void> deleteEvent(TimelineEvent event) async {
    if (event is LocalMediaSendEvent) {
      await event.cancelSend();
      removeEvent(event.eventId);
      return;
    }

    var matrixEvent = await _matrixTimeline!.getEventById(event.eventId);
    if (event.status == TimelineEventStatus.error) {
      await matrixEvent?.cancelSend();
    } else {
      await _matrixRoom.redactEvent(event.eventId);
    }
  }

  @override
  bool canDeleteEvent(TimelineEvent event) {
    if (event.senderId != room.client.self!.identifier &&
        room.permissions.canDeleteOtherUserMessages != true)
      return false;

    if (event is TimelineEventMessage) {
      return true;
    }

    if (event is TimelineEventSticker) {
      return true;
    }

    return true;
  }

  @override
  Future<void> close() async {
    _matrixTimeline?.cancelSubscriptions();
    await onEventAdded.close();
    await onChange.close();
    await onRemove.close();
    // Closed with the other three rather than left open: this controller is
    // created for every timeline, so a timeline that is closed correctly still
    // leaked one StreamController until 2026-08-21.
    await _loadingStatusChangedController.close();
  }

  @override
  bool isEventRedacted(TimelineEvent<Client> event) {
    if (event is! MatrixTimelineEvent) {
      return false;
    }

    return event.event.getDisplayEvent(_matrixTimeline!).redacted;
  }
}
