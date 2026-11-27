// Deterministic stand-in for `lk.Room`, plus the event listener it hands out.
//
// Two things this models that the real SDK does and no previous fake could:
//
// 1. **Connection state is controllable.** `livekit_client-2.5.4`
//    `participant/remote.dart:280` only emits `TrackPublishedEvent` when
//    `room.connectionState == ConnectionState.connected`, so a publication
//    that appears while the room is `connecting` or `reconnecting` produces no
//    event at all. [FakeLiveKitRoom.setConnectionState] plus
//    [FakeLiveKitRoom.emitIfConnected] reproduce that drop faithfully.
//
// 2. **Events emitted before a listener is attached are lost.**
//    `MatrixLivekitBackend` enables the microphone before the session object
//    exists, so the first publish event predates the session's room listener.
//    [FakeLiveKitRoom.emit] records any event emitted while no live listener
//    exists in [FakeLiveKitRoom.eventsDroppedWithoutListener] instead of
//    buffering it, which is what the SDK actually does.
//    [FakeLiveKitRoom.replayDroppedEvents] delivers them afterwards so a test
//    can assert the counterfactual ("the session would have handled it").
//
// Events are delivered in exactly the order they are emitted, and `emit`
// completes only after every handler has run, so a test controls ordering
// precisely.

import 'dart:async';
import 'dart:collection';

import 'package:livekit_client/livekit_client.dart' as lk;

class _FakeRoomEventHandler {
  _FakeRoomEventHandler({required this.matches, required this.invoke});

  final bool Function(lk.RoomEvent event) matches;
  final FutureOr<void> Function(lk.RoomEvent event) invoke;
}

/// The listener [FakeLiveKitRoom.createListener] returns.
///
/// Only `on`, `listen` and `dispose` are modelled; everything else routes to
/// `noSuchMethod` and throws.
class FakeRoomEventsListener implements lk.EventsListener<lk.RoomEvent> {
  FakeRoomEventsListener();

  final List<_FakeRoomEventHandler> _handlers = <_FakeRoomEventHandler>[];

  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  final bool synchronized = false;

  /// Number of live handlers. Drops to zero when the session disposes its
  /// listener during teardown.
  int get handlerCount => _handlers.length;

  @override
  lk.CancelListenFunc on<E>(
    FutureOr<void> Function(E) then, {
    bool Function(E)? filter,
  }) {
    final handler = _FakeRoomEventHandler(
      matches: (event) {
        if (event is! E) return false;
        return filter == null || filter(event as E);
      },
      invoke: (event) => then(event as E),
    );
    _handlers.add(handler);
    return () async {
      _handlers.remove(handler);
    };
  }

  @override
  lk.CancelListenFunc listen(FutureOr<void> Function(lk.RoomEvent) onEvent) {
    final handler = _FakeRoomEventHandler(
      matches: (_) => true,
      invoke: onEvent,
    );
    _handlers.add(handler);
    return () async {
      _handlers.remove(handler);
    };
  }

  @override
  Future<void> cancelAll() async => _handlers.clear();

  @override
  Future<bool> dispose() async {
    if (_disposed) return false;
    _disposed = true;
    _handlers.clear();
    return true;
  }

  /// Delivers [event] to every matching handler, in registration order,
  /// awaiting each one.
  Future<void> deliver(lk.RoomEvent event) async {
    if (_disposed) return;
    for (final handler in List<_FakeRoomEventHandler>.of(_handlers)) {
      if (handler.matches(event)) {
        await handler.invoke(event);
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controllable `lk.Room` with a settable connection state, a mutable
/// participant set, and ordered event emission.
class FakeLiveKitRoom implements lk.Room {
  FakeLiveKitRoom({
    lk.ConnectionState connectionState = lk.ConnectionState.connected,
    lk.LocalParticipant? localParticipant,
    List<lk.RemoteParticipant> remoteParticipants = const [],
    this.name = 'fake-room',
  }) : _connectionState = connectionState,
       _localParticipant = localParticipant {
    for (final participant in remoteParticipants) {
      _remoteParticipants[participant.identity] = participant;
    }
  }

  @override
  final String? name;

  lk.ConnectionState _connectionState;
  lk.LocalParticipant? _localParticipant;

  final Map<String, lk.RemoteParticipant> _remoteParticipants =
      <String, lk.RemoteParticipant>{};

  final List<FakeRoomEventsListener> _listeners = <FakeRoomEventsListener>[];

  /// Every event passed to [emit], in order.
  final List<lk.RoomEvent> emittedEvents = <lk.RoomEvent>[];

  /// Events emitted while no live listener existed. The real SDK drops these
  /// on the floor; keeping them makes the drop assertable.
  final List<lk.RoomEvent> eventsDroppedWithoutListener = <lk.RoomEvent>[];

  /// Events [emitIfConnected] refused to emit because the room was not in
  /// `ConnectionState.connected`, mirroring `remote.dart:280`.
  final List<lk.RoomEvent> eventsDroppedWhileNotConnected = <lk.RoomEvent>[];

  int createListenerCount = 0;
  int disconnectCount = 0;
  int disposeCount = 0;

  /// Set to make [disconnect] hang, so a wedged teardown can be tested.
  Completer<void>? disconnectGate;

  /// Set to make [dispose] hang, so the native-dispose timeout can be tested.
  Completer<void>? disposeGate;

  @override
  lk.ConnectionState get connectionState => _connectionState;

  void setConnectionState(lk.ConnectionState value) => _connectionState = value;

  @override
  lk.LocalParticipant? get localParticipant => _localParticipant;

  void setLocalParticipant(lk.LocalParticipant? value) =>
      _localParticipant = value;

  @override
  UnmodifiableMapView<String, lk.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView<String, lk.RemoteParticipant>(_remoteParticipants);

  void addRemoteParticipant(lk.RemoteParticipant participant) =>
      _remoteParticipants[participant.identity] = participant;

  void removeRemoteParticipant(String identity) =>
      _remoteParticipants.remove(identity);

  /// True while at least one listener created by [createListener] is alive.
  bool get hasLiveListener =>
      _listeners.any((listener) => !listener.isDisposed);

  List<FakeRoomEventsListener> get attachedListeners =>
      List<FakeRoomEventsListener>.unmodifiable(_listeners);

  @override
  FakeRoomEventsListener createListener({bool synchronized = false}) {
    createListenerCount++;
    final listener = FakeRoomEventsListener();
    _listeners.add(listener);
    return listener;
  }

  /// Delivers [event] to every live listener, in creation order, awaiting each
  /// listener's handlers. Records the event as dropped when nothing is
  /// listening.
  Future<void> emit(lk.RoomEvent event) async {
    emittedEvents.add(event);
    final live = _listeners
        .where((listener) => !listener.isDisposed)
        .toList(growable: false);
    if (live.isEmpty) {
      eventsDroppedWithoutListener.add(event);
      return;
    }
    for (final listener in live) {
      await listener.deliver(event);
    }
  }

  /// Emits [event] only when the room is `connected`, matching the SDK gate at
  /// `participant/remote.dart:280`. Use this for publish/unpublish events when
  /// the point of the test is the join or reconnect window.
  Future<void> emitIfConnected(lk.RoomEvent event) async {
    if (_connectionState != lk.ConnectionState.connected) {
      eventsDroppedWhileNotConnected.add(event);
      return;
    }
    await emit(event);
  }

  /// Emits several events in the exact order given.
  Future<void> emitAll(Iterable<lk.RoomEvent> events) async {
    for (final event in events) {
      await emit(event);
    }
  }

  /// Re-delivers everything recorded in [eventsDroppedWithoutListener] and
  /// clears it. Lets a test show what the session *would* have done had the
  /// listener existed in time.
  Future<void> replayDroppedEvents() async {
    final pending = List<lk.RoomEvent>.of(eventsDroppedWithoutListener);
    eventsDroppedWithoutListener.clear();
    for (final event in pending) {
      await emit(event);
    }
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    final gate = disconnectGate;
    if (gate != null) {
      await gate.future;
    }
    _connectionState = lk.ConnectionState.disconnected;
  }

  @override
  Future<bool> dispose() async {
    disposeCount++;
    final gate = disposeGate;
    if (gate != null) {
      await gate.future;
    }
    // The listeners the real SDK tears down here have to go, and the room has
    // to stop reporting itself connected. Recording the call and returning
    // left `hasLiveListener` true and kept `emit` delivering to handlers a
    // disposed room would never reach, so a teardown test that emitted after
    // dispose observed handling instead of the drop, and
    // `eventsDroppedWithoutListener` stayed empty.
    for (final listener in _listeners) {
      await listener.dispose();
    }
    _connectionState = lk.ConnectionState.disconnected;
    return true;
  }

  @override
  String toString() => 'FakeLiveKitRoom($name, $_connectionState)';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
