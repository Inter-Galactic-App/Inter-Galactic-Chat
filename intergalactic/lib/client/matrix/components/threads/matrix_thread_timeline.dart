import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_timeline.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/timeline_events/local_media_send_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';

import 'package:matrix/matrix.dart' as matrix;

class MatrixThreadTimeline implements Timeline {
  @override
  Client client;

  @override
  late List<TimelineEvent> events;

  @override
  Room room;

  MatrixTimeline mainRoomTimeline;

  ThreadsComponent component;

  String threadRootId;

  @override
  StreamController<int> onChange = StreamController.broadcast(sync: true);

  @override
  StreamController<int> onEventAdded = StreamController.broadcast(sync: true);

  @override
  StreamController<int> onRemove = StreamController.broadcast(sync: true);

  final StreamController<void> _loadingStatusChangedController =
      StreamController.broadcast();

  @override
  Stream<void> get onLoadingStatusChanged =>
      _loadingStatusChangedController.stream;

  late List<StreamSubscription> subs;

  String? nextBatch;
  bool finished = false;

  Future? nextChunkRequest;

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory =>
      !finished && nextBatch != null && nextChunkRequest == null;

  @override
  bool get isLoadingFuture => false;

  @override
  bool isLoadingHistory = false;

  MatrixThreadTimeline({
    required this.client,
    required this.room,
    required this.threadRootId,
    required this.mainRoomTimeline,
    required this.component,
    this.nextBatch,
  }) {
    subs = [
      mainRoomTimeline.onEventAdded.stream.listen(onMainTimelineEventAdded),
      mainRoomTimeline.onChange.stream.listen(onMainTimelineEventChanged),
      mainRoomTimeline.onRemove.stream.listen(onMainTimelineEventRemoved),
    ];

    events = List.empty(growable: true);
  }

  Future<List<TimelineEvent>> getThreadEvents(
      {int limit = 20, String? nextBatch}) async {
    var client = this.client as MatrixClient;
    var room = this.room as MatrixRoom;

    var mx = client.getMatrixClient();
    var roomId = Uri.encodeComponent(room.identifier);
    var rootEventId = Uri.encodeComponent(threadRootId);
    var data = await mx.request(matrix.RequestType.GET,
        "/client/unstable/rooms/$roomId/relations/$rootEventId/m.thread",
        query: {
          "limit": limit.toString(),
          if (nextBatch != null) "from": nextBatch
        });

    var chunk = List<Map<String, dynamic>>.from(data["chunk"] as Iterable);

    var mxevents =
        chunk.map((e) => matrix.Event.fromJson(e, room.matrixRoom)).toList();

    for (var i = 0; i < mxevents.length; i++) {
      var event = mxevents[i];

      if (event.type == "m.room.encrypted") {
        var decrypted = await mx.encryption?.decryptRoomEvent(event);
        if (decrypted != null) {
          mxevents[i] = decrypted;
        }
      }
    }

    for (var event in mxevents) {
      mainRoomTimeline.matrixTimeline?.addAggregatedEvent(event);
    }

    var convertedEvents = mxevents
        .map((e) =>
            room.convertEvent(e, timeline: mainRoomTimeline.matrixTimeline))
        .toList();

    this.nextBatch = data["next_batch"] as String?;

    if (this.nextBatch == null) {
      finished = true;
      var root = data["original_event"] as Map<String, dynamic>?;
      if (root != null) {
        var matrixEvent = matrix.Event.fromJson(root, room.matrixRoom);
        if (matrixEvent.type == "m.room.encrypted") {
          var decrypted = await mx.encryption?.decryptRoomEvent(matrixEvent);
          if (decrypted != null) {
            matrixEvent = decrypted;
          }
        }
        var event = room.convertEvent(matrixEvent);
        convertedEvents.add(event);
      }
    }

    return convertedEvents;
  }

  @override
  bool canDeleteEvent(TimelineEvent event) {
    return mainRoomTimeline.canDeleteEvent(event);
  }

  @override
  Future<void> close() async {
    for (var sub in subs) {
      sub.cancel();
    }
  }

  @override
  void deleteEvent(TimelineEvent event) {
    if (event is LocalMediaSendEvent) {
      unawaited(room.cancelSend(event));
      removeEvent(event.eventId);
      return;
    }

    mainRoomTimeline.deleteEvent(event);
  }

  @override
  Future<TimelineEvent?> fetchEventById(String eventId) {
    return mainRoomTimeline.fetchEventById(eventId);
  }

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) {
    return mainRoomTimeline.fetchEventByIdInternal(eventId);
  }

  @override
  bool hasEvent(String eventId) {
    return events.any((element) => element.eventId == eventId);
  }

  int _indexOfSameEvent(TimelineEvent event) {
    return events.indexWhere((element) {
      if (element.eventId == event.eventId) {
        return true;
      }

      if (element is MatrixTimelineEvent && event is MatrixTimelineEvent) {
        final existingTransactionId = element.event.transactionId;
        final transactionId = event.event.transactionId;
        return transactionId != null &&
            transactionId.isNotEmpty &&
            existingTransactionId != null &&
            existingTransactionId.isNotEmpty &&
            existingTransactionId == transactionId;
      }

      return false;
    });
  }

  bool _isThreadRootEvent(TimelineEvent event) => event.eventId == threadRootId;

  int _resolveInsertIndex(int index, TimelineEvent event) {
    // Thread timelines keep the room timeline's newest-first ordering:
    // index 0 renders on the bottom/latest side, so the root belongs at the
    // far history end where it stays visually pinned to the thread top.
    if (_isThreadRootEvent(event)) {
      return events.length;
    }

    return index.clamp(0, events.length).toInt();
  }

  void _upsertEventAt(int index, TimelineEvent event) {
    final originalIndex = _indexOfSameEvent(event);

    if (originalIndex == -1) {
      insertEvent(index, event);
      return;
    }

    if (_isThreadRootEvent(event) && originalIndex != events.length - 1) {
      onRemove.add(originalIndex);
      events.removeAt(originalIndex);

      final pinnedIndex = _resolveInsertIndex(index, event);
      events.insert(pinnedIndex, event);
      onEventAdded.add(pinnedIndex);
      return;
    }

    events[originalIndex] = event;
    onChange.add(originalIndex);
  }

  @override
  void insertEvent(int index, TimelineEvent event) {
    final safeIndex = _resolveInsertIndex(index, event);
    events.insert(safeIndex, event);
    onEventAdded.add(safeIndex);
  }

  @override
  Future<void> loadMoreHistory() async {
    if (finished) {
      return;
    }

    if (nextChunkRequest != null) {
      return;
    }

    isLoadingHistory = true;
    _loadingStatusChangedController.add(null);

    try {
      nextChunkRequest = getThreadEvents(nextBatch: nextBatch);
      var nextEvents = await nextChunkRequest;

      for (var event in nextEvents) {
        _appendEvent(event);
      }
    } finally {
      nextChunkRequest = null;
      isLoadingHistory = false;
      _loadingStatusChangedController.add(null);
    }
  }

  @override
  Future<void> loadMoreFuture() {
    throw UnimplementedError();
  }

  @override
  void markAsRead(TimelineEvent event) {
    mainRoomTimeline.markAsRead(event);
  }

  @override
  void notifyChanged(int index) {
    if (index < 0 || index >= events.length) {
      return;
    }

    onChange.add(index);
  }

  @override
  bool removeEvent(String eventId) {
    final index = events.indexWhere((event) => event.eventId == eventId);
    if (index == -1) {
      return false;
    }

    onRemove.add(index);
    events.removeAt(index);
    return true;
  }

  @override
  TimelineEvent? tryGetEvent(String eventId) {
    for (final event in events) {
      if (event.eventId == eventId) {
        return event;
      }
    }

    return mainRoomTimeline.tryGetEvent(eventId);
  }

  bool isEventInThisThread(TimelineEvent event) {
    if (event is! MatrixTimelineEvent) {
      return false;
    }

    if (event.eventId == threadRootId) {
      return true;
    }

    var mxEvent = event.event;
    var relation = mxEvent.content["m.relates_to"];
    if (relation == null) {
      return false;
    }

    if (relation is! Map<String, dynamic>) {
      return false;
    }

    if (relation["rel_type"] != matrix.RelationshipTypes.thread) {
      return false;
    }

    if (relation["event_id"] == threadRootId) {
      return true;
    }

    var reply = relation["m.in_reply_to"] as Map<String, dynamic>?;

    if (reply == null) {
      return false;
    }

    var replyingEventID = reply["event_id"];

    if (replyingEventID == threadRootId) {
      return true;
    }

    var replyingEvent = mainRoomTimeline.tryGetEvent(replyingEventID);
    if (replyingEvent != null) {
      return isEventInThisThread(replyingEvent as MatrixTimelineEvent);
    }

    return false;
  }

  void onMainTimelineEventAdded(int index) {
    var event = mainRoomTimeline.events[index];

    if (!isEventInThisThread(event)) {
      return;
    }

    final originalIndex = _indexOfSameEvent(event);
    if (originalIndex != -1) {
      if (_isThreadRootEvent(event) && originalIndex != events.length - 1) {
        _upsertEventAt(events.length, event);
      }
      return;
    }

    if (index == 0) {
      insertEvent(0, event);
    } else {
      // Theres gotta be a smarter way of doing this but whatever
      var copy = List<TimelineEvent>.from(mainRoomTimeline.events);
      copy.removeWhere((element) => !isEventInThisThread(element));

      var newIndex = copy.indexOf(event);
      if (newIndex == -1 || newIndex > events.length) {
        newIndex = events.length;
      }
      insertEvent(newIndex, event);
    }
  }

  void onMainTimelineEventChanged(int index) {
    var event = mainRoomTimeline.events[index];
    var originalIndex = _indexOfSameEvent(event);
    var isTrackedThreadEvent = originalIndex != -1;

    if (isEventInThisThread(event) || isTrackedThreadEvent) {
      var finalIndex = originalIndex;

      if (finalIndex == -1) {
        finalIndex = 0;
      }

      _upsertEventAt(finalIndex, event);
    }
  }

  void onMainTimelineEventRemoved(int index) {
    var event = mainRoomTimeline.events[index];
    if (isEventInThisThread(event)) {
      var index = _indexOfSameEvent(event);

      if (index != -1) {
        onRemove.add(index);
        events.removeAt(index);
      }
    }
  }

  void _appendEvent(TimelineEvent event) {
    final originalIndex = _indexOfSameEvent(event);

    if (originalIndex != -1) {
      if (_isThreadRootEvent(event) && originalIndex != events.length - 1) {
        _upsertEventAt(events.length, event);
      }
      return;
    }

    insertEvent(events.length, event);
  }

  @override
  bool isEventRedacted(TimelineEvent<Client> event) {
    if (event is! MatrixTimelineEvent) {
      return false;
    }

    return event.event
        .getDisplayEvent(mainRoomTimeline.matrixTimeline!)
        .redacted;
  }
}
