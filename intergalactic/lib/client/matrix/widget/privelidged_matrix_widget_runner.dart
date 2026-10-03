import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:matrix_widget_api/capabilities.dart';
import 'package:matrix_widget_api/matrix_widget_api.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_widget_api/types.dart';

/// Local runner for the first-party calendar widget protocol.
///
/// It deliberately grants and enforces only the narrow calendar capability set;
/// user-configured widgets require a separate origin and capability model.
class PrivelidgedMatrixWidgetRunner implements MatrixWidgetApi {
  static const _calendarEventStateType = 'chat.commet.calendar_event';
  static const _calendarRegistryStateType = 'chat.commet.calendars';
  static const _calendarCreateEventType = 'chat.commet.calendar_create';
  static const _calendarEventType = 'chat.commet.calendar_events';
  static const _attendanceEventType = 'chat.intergalactic.calendar_attendance';
  static const _redactionEventType = 'm.room.redaction';
  static const _referenceRelationType = 'm.reference';
  static const _maxRelationLimit = 100;
  matrix.Client client;
  matrix.Room room;

  bool running = false;

  PrivelidgedMatrixWidgetRunner(this.client, this.room);

  List<String> grantedCapabilities = List.empty(growable: true);
  final Map<String, (String eventId, String eventType, String relationType)>
  _relationPagination = {};
  Set<String>? _confirmedCalendarRegistryIds;
  final Set<String> _createdCalendarRootIds = {};

  Map<String, Function(Map<String, dynamic> data)> actionListeners = {};

  StreamSubscription? syncStreamSub;

  @override
  void onAction(
    String toWidgetAction,
    Map<String, dynamic>? Function(Map<String, dynamic> data) callback, {
    preventDefaultHandler = false,
  }) {
    actionListeners[toWidgetAction] = callback;
  }

  @override
  Future<void> requestCapabilities(List<String> capabilities) async {
    Log.i("Widget requested capabilities count=${capabilities.length}");

    for (var capability in capabilities) {
      if (!_isApprovedCapability(capability) ||
          grantedCapabilities.contains(capability)) {
        continue;
      }

      grantedCapabilities.add(capability);
      onCapabilityGranted(capability);
    }
  }

  void onCapabilityGranted(String capability) {
    if (capability.startsWith("org.matrix.msc2762.receive.state_event:")) {
      var state = capability.replaceFirst(
        "org.matrix.msc2762.receive.state_event:",
        "",
      );
      Log.i("Sending widget state events type=$state");
      sendExistingStateEvents(state);
    }
  }

  void sendExistingStateEvents(String stateType) async {
    await room.postLoad();

    var states = room.states[stateType];
    Log.i("Found widget states type=$stateType count=${states?.length ?? 0}");
    if (states == null) {
      return;
    }

    var result = {
      "data": {"state": states.values.map((i) => i.toJson())},
    };

    Function(Map<String, dynamic>)? callback = actionListeners["update_state"];

    callback?.call(result);
  }

  @override
  Future<Map<String, dynamic>> sendAction(
    String fromWidgetAction,
    Map<String, dynamic> data,
  ) async {
    Log.i("[${_roomLogLabel()}] Action requested: $fromWidgetAction");

    if (fromWidgetAction == FromWidgetAction.sendEvent) {
      return handleSendEvent(data);
    }

    if (fromWidgetAction == FromWidgetAction.readRelations) {
      return handleReadRelations(data);
    }

    Log.w(
      "[${_roomLogLabel()}] Ignoring unsupported widget action "
      "'$fromWidgetAction'",
    );
    return {
      "error": {
        "action": fromWidgetAction,
        "message": "Unsupported widget action",
      },
    };
  }

  @override
  void start() {
    if (running) {
      return;
    }

    Log.i("Starting Widget Runner: ${_roomLogLabel()}");
    syncStreamSub = client.onSync.stream.listen(onSync);
    client.onTimelineEvent.stream
        .where((event) => event.roomId == room.id)
        .listen(onEvent);
    running = true;
    _onReady.add(());
  }

  @override
  void stop() {
    Log.i("Stopping Widget Runner: ${_roomLogLabel()}");
    syncStreamSub?.cancel();
    actionListeners.clear();
    _relationPagination.clear();
    _confirmedCalendarRegistryIds = null;
    _createdCalendarRootIds.clear();
    running = false;
  }

  @override
  String get userId => client.userID!;

  Future<Map<String, dynamic>> handleSendEvent(
    Map<String, dynamic> data,
  ) async {
    final type = data['type'];
    final stateKey = data['state_key'];
    final rawContent = data['content'];

    if (type is! String ||
        rawContent is! Map ||
        !_hasOnlyKeys(
          data,
          stateKey == null
              ? const {'type', 'content'}
              : const {'type', 'content', 'state_key'},
        )) {
      return _rejected();
    }
    final content = jsonDecode(jsonEncode(rawContent));
    if (content is! Map<String, dynamic>) {
      return _rejected();
    }

    String? eventId;
    Log.i(
      "Handling widget send event type=$type "
      "stateKeyPresent=${stateKey != null} "
      "contentKeys=${_mapKeysForLog(content)}",
    );
    if (stateKey != null) {
      if (stateKey is! String ||
          !await _canWriteState(type, stateKey, content)) {
        return _rejected();
      }
      eventId = await client.setRoomStateWithKey(
        room.id,
        type,
        stateKey,
        content,
      );
      if (type == _calendarRegistryStateType && stateKey.isEmpty) {
        _confirmedCalendarRegistryIds = _calendarIdsFromRegistryContent(
          content,
        );
      }

      Log.i("Sent widget state event idAvailable=true");

      var stateResult = {
        "data": {
          "state": [
            {
              "type": type,
              "content": content,
              "sender": client.userID!,
              "state_key": stateKey,
              "event_id": eventId,
            },
          ],
        },
      };

      if (grantedCapabilities.contains(MatrixCapability.getRoomState(type))) {
        Function(Map<String, dynamic>)? callback =
            actionListeners[ToWidgetAction.updateState];

        try {
          callback?.call(stateResult);
        } catch (e) {}
      }
    } else {
      if (type == _redactionEventType) {
        final redacts = content['redacts'];
        if (redacts is! String ||
            !_hasCapability(MatrixCapability.sendEvent(type)) ||
            !await _canRedactCalendarEvent(redacts)) {
          return _rejected();
        }
        eventId = await room.redactEvent(redacts);
      } else {
        if (!await _canSendTimelineEvent(type, content)) {
          return _rejected();
        }
        eventId = await room.sendEvent(content, type: type);
        if (type == _calendarCreateEventType &&
            eventId != null &&
            eventId.isNotEmpty) {
          _createdCalendarRootIds.add(eventId);
        }
      }

      var eventResult = {
        "data": {
          "type": type,
          "content": content,
          "sender": client.userID!,
          "state_key": stateKey,
          "event_id": eventId,
        },
      };

      if (grantedCapabilities.contains(MatrixCapability.receiveEvent(type))) {
        Function(Map<String, dynamic>)? callback =
            actionListeners[ToWidgetAction.sendEvent];

        try {
          callback?.call(eventResult);
        } catch (e) {}
      }
    }

    Log.i("Handled send event");

    return {"room_id": room.id, "event_id": eventId};
  }

  void onSync(matrix.SyncUpdate event) async {
    var thisRoom = event.rooms?.join?[room.id];
    if (thisRoom == null) {
      return;
    }

    for (final stateEvent in thisRoom.state ?? const <matrix.MatrixEvent>[]) {
      _observeCalendarRegistryEvent(stateEvent);
    }

    var events = thisRoom.timeline?.events;
    if (events == null) {
      return;
    }

    for (final timelineEvent in events) {
      _observeCalendarRegistryEvent(timelineEvent);
    }

    var readableStateEvents = events
        .where((i) => i.stateKey != null && canWidgetReadStateEventType(i.type))
        .toList();

    final readableEvents = <matrix.MatrixEvent>[];
    for (final timelineEvent in events) {
      if (timelineEvent.eventId.startsWith("\$") &&
          await _canWidgetReceiveEvent(timelineEvent)) {
        readableEvents.add(timelineEvent);
      }
    }

    if (readableStateEvents.isNotEmpty) {
      Log.i(
        "[${_roomLogLabel()}] Sending "
        "${readableStateEvents.length} readable state events",
      );

      var currentStates = readableStateEvents
          .map((i) => room.getState(i.type, i.stateKey ?? ""))
          .nonNulls
          .toList();

      var result = {
        "data": {"state": currentStates.map((i) => i.toJson()).toList()},
      };

      Function(Map<String, dynamic>)? callback =
          actionListeners["update_state"];

      callback?.call(result);
    }

    if (readableEvents.isNotEmpty) {
      Log.i(
        "[${_roomLogLabel()}] Sending "
        "${readableEvents.length} readable timeline events",
      );

      for (var event in readableEvents) {
        var eventResult = {
          "data": {
            "type": event.type,
            "content": event.content,
            "sender": event.senderId,
            "event_id": event.eventId,
          },
        };

        Function(Map<String, dynamic>)? callback =
            actionListeners[ToWidgetAction.sendEvent];

        try {
          callback?.call(eventResult);
        } catch (e) {}
      }
    }
  }

  void onEvent(matrix.Event event) async {
    if (event.status != matrix.EventStatus.synced) return;
    _observeCalendarRegistryEvent(event);
    if (!await _canWidgetReceiveEvent(event)) return;

    var eventResult = {
      "data": {
        "type": event.type,
        "content": event.content,
        "sender": event.senderId,
        "event_id": event.eventId,
      },
    };

    Function(Map<String, dynamic>)? callback =
        actionListeners[ToWidgetAction.sendEvent];

    try {
      callback?.call(eventResult);
    } catch (e) {}
  }

  bool canWidgetReadStateEventType(String type) {
    return grantedCapabilities.contains(MatrixCapability.getRoomState(type));
  }

  bool canWidgetReceiveEventType(String type) {
    return grantedCapabilities.contains(MatrixCapability.receiveEvent(type));
  }

  StreamController _onReady = StreamController.broadcast();

  @override
  Stream<void> get onReady => _onReady.stream;

  Future<Map<String, dynamic>> handleReadRelations(
    Map<String, dynamic> data,
  ) async {
    Log.i("Handling read relations");

    final eventId = data['event_id'];
    final eventType = data['event_type'];
    final limit = data['limit'];
    final relType = data['rel_type'];
    final from = data['from'];

    if (eventId is! String ||
        eventType is! String ||
        limit is! int ||
        relType is! String ||
        (from != null && from is! String) ||
        !_hasOnlyKeys(data, const {
          'event_id',
          'event_type',
          'limit',
          'rel_type',
          'from',
        }) ||
        !await _canReadRelations(eventId, eventType, relType, limit, from)) {
      return _rejected();
    }

    List<matrix.MatrixEvent>? chunk;
    String? nextBatch;

    try {
      if (room.encrypted) {
        var related = await client.getRelatingEventsWithRelType(
          room.id,
          eventId,
          relType,
          from: from,
          limit: limit,
        );
        nextBatch = related.nextBatch;

        final decrypted = await decryptAndFilterWidgetRelationEvents(
          related.chunk,
          eventType,
          tryDecryptEvent,
        );

        _recordRelationPagination(nextBatch, eventId, eventType, relType);
        return {
          "chunk": decrypted.nonNulls.map((i) => i.toJson()).toList(),
          if (nextBatch != null) "next_batch": nextBatch,
        };
      }

      var relatedEvents = await client.getRelatingEventsWithRelTypeAndEventType(
        room.id,
        eventId,
        relType,
        eventType,
        from: from,
        limit: limit,
      );

      chunk = relatedEvents.chunk;
      nextBatch = relatedEvents.nextBatch;

      _recordRelationPagination(nextBatch, eventId, eventType, relType);
      return {
        "chunk": chunk.map((i) => i.toJson()).toList(),
        if (nextBatch != null) "next_batch": nextBatch,
      };
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to read Matrix widget relation events',
        category: LogCategory.matrix,
        source: 'matrix-widget',
      );
      return const {"chunk": []};
    }
  }

  Future<matrix.Event?> tryDecryptEvent(matrix.MatrixEvent event) async {
    try {
      return client.encryption!.decryptRoomEvent(
        matrix.Event.fromMatrixEvent(event, room),
      );
    } catch (e, _) {
      return null;
    }
  }

  String _roomLogLabel() {
    return Log.redactSensitiveInfo(room.id);
  }

  String _mapKeysForLog(dynamic value) {
    if (value is! Map) {
      return "none";
    }
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return keys.join(",");
  }

  bool _isApprovedCapability(String capability) => {
    MatrixCapability.getRoomState(_calendarEventStateType),
    MatrixCapability.setRoomState(_calendarEventStateType, stateKey: userId),
    MatrixCapability.getRoomState(_calendarRegistryStateType),
    MatrixCapability.setRoomState(_calendarRegistryStateType),
    MatrixCapability.sendEvent(_calendarCreateEventType),
    MatrixCapability.sendEvent(_calendarEventType),
    MatrixCapability.receiveEvent(_calendarEventType),
    MatrixCapability.sendEvent(_attendanceEventType),
    MatrixCapability.receiveEvent(_attendanceEventType),
    MatrixCapability.sendEvent(_redactionEventType),
    MatrixCapability.receiveEvent(_redactionEventType),
  }.contains(capability);

  bool _hasCapability(String capability) =>
      grantedCapabilities.contains(capability);

  Future<bool> _canWriteState(
    String type,
    String stateKey,
    Map<String, dynamic> content,
  ) async {
    if (type == _calendarEventStateType) {
      return stateKey == userId &&
          _hasCapability(
            MatrixCapability.setRoomState(type, stateKey: stateKey),
          );
    }
    if (type != _calendarRegistryStateType ||
        stateKey.isNotEmpty ||
        !_hasCapability(MatrixCapability.setRoomState(type)) ||
        content.length != 1) {
      return false;
    }
    final calendars = content['calendars'];
    if (calendars is! List ||
        !calendars.every((id) => id is String && id.isNotEmpty)) {
      return false;
    }
    for (final id in calendars.cast<String>()) {
      if (!await _isCalendarRoot(id)) return false;
    }
    return true;
  }

  Future<bool> _canSendTimelineEvent(
    String type,
    Map<String, dynamic> content,
  ) async {
    if (!_hasCapability(MatrixCapability.sendEvent(type))) return false;
    if (type == _calendarCreateEventType) return content.isEmpty;
    if (type != _calendarEventType && type != _attendanceEventType)
      return false;
    final relatesTo = content['m.relates_to'];
    if (relatesTo is! Map ||
        relatesTo['rel_type'] != _referenceRelationType ||
        relatesTo['event_id'] is! String) {
      return false;
    }
    final rootId = relatesTo['event_id'] as String;
    return _registeredCalendarIds.contains(rootId) &&
        await _isCalendarRoot(rootId) &&
        _registeredCalendarIds.contains(rootId);
  }

  Future<bool> _canRedactCalendarEvent(String eventId) =>
      _isCalendarTimelineEvent(eventId, requireCurrentUser: true);

  Future<bool> _canWidgetReceiveEvent(matrix.MatrixEvent event) async {
    if (!canWidgetReceiveEventType(event.type)) return false;
    if (event.type != _redactionEventType) return true;

    final redacts = event.redacts ?? event.content['redacts'];
    return redacts is String && await _isCalendarTimelineEvent(redacts);
  }

  Future<bool> _isCalendarTimelineEvent(
    String eventId, {
    bool requireCurrentUser = false,
  }) async {
    try {
      final event = await room.getEventById(eventId);
      return event != null &&
          event.eventId == eventId &&
          event.roomId == room.id &&
          (!requireCurrentUser || event.senderId == userId) &&
          (event.type == _calendarEventType ||
              event.type == _attendanceEventType);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canReadRelations(
    String eventId,
    String eventType,
    String relType,
    int limit,
    String? from,
  ) async =>
      limit > 0 &&
      limit <= _maxRelationLimit &&
      relType == _referenceRelationType &&
      (eventType == _calendarEventType || eventType == _attendanceEventType) &&
      _hasCapability(MatrixCapability.receiveEvent(eventType)) &&
      _registeredCalendarIds.contains(eventId) &&
      await _isCalendarRoot(eventId) &&
      _registeredCalendarIds.contains(eventId) &&
      (from == null ||
          _relationPagination[from] == (eventId, eventType, relType));

  Future<bool> _isCalendarRoot(String eventId) async {
    if (_createdCalendarRootIds.contains(eventId)) return true;
    try {
      final event = await room.getEventById(eventId);
      return event != null &&
          event.eventId == eventId &&
          event.roomId == room.id &&
          event.type == _calendarCreateEventType;
    } catch (_) {
      return false;
    }
  }

  void _recordRelationPagination(
    String? nextBatch,
    String eventId,
    String eventType,
    String relationType,
  ) {
    if (nextBatch == null) return;
    if (_relationPagination.length >= _maxRelationLimit) {
      _relationPagination.remove(_relationPagination.keys.first);
    }
    _relationPagination[nextBatch] = (eventId, eventType, relationType);
  }

  Set<String> get _registeredCalendarIds {
    return _confirmedCalendarRegistryIds ??
        _calendarIdsFromRegistryContent(
          room.getState(_calendarRegistryStateType)?.content,
        );
  }

  void _observeCalendarRegistryEvent(matrix.MatrixEvent event) {
    if (event.type != _calendarRegistryStateType || event.stateKey != '') {
      return;
    }
    _confirmedCalendarRegistryIds = _calendarIdsFromRegistryContent(
      event.content,
    );
  }

  Set<String> _calendarIdsFromRegistryContent(Object? content) {
    if (content is! Map) return const {};
    final calendars = content['calendars'];
    return calendars is List
        ? calendars.whereType<String>().where((id) => id.isNotEmpty).toSet()
        : const {};
  }

  bool _hasOnlyKeys(Map<String, dynamic> data, Set<String> allowed) =>
      data.keys.every(allowed.contains);

  Map<String, dynamic> _rejected() => const {
    'error': {'message': 'Widget action rejected'},
  };
}

/// The encrypted Matrix event envelope does not reveal its plaintext type.
/// Call this only after authorizing the relation query; it emits only plaintext
/// events of the authorized type.
@visibleForTesting
Future<List<matrix.Event>> decryptAndFilterWidgetRelationEvents(
  Iterable<matrix.MatrixEvent> events,
  String eventType,
  Future<matrix.Event?> Function(matrix.MatrixEvent event) decrypt,
) async {
  final decrypted = await Future.wait<matrix.Event?>([
    for (final event in events) decrypt(event),
  ]);
  return decrypted
      .whereType<matrix.Event>()
      .where((event) => event.type == eventType)
      .toList();
}
