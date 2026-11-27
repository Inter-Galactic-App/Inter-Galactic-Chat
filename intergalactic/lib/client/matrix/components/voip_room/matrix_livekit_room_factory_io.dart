import 'dart:async';
import 'dart:io' as io;

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_client/src/core/engine.dart' as lk_engine;
import 'package:livekit_client/src/core/signal_client.dart' as lk_signal;
import 'package:livekit_client/src/support/websocket.dart' as lk_websocket;

lk.Room createMatrixLivekitRoom({required lk.RoomOptions roomOptions}) {
  // LiveKit exposes connector injection on its internal SignalClient only.
  // Keep this localized so the pinned SDK boundary is explicit and reviewable.
  // ignore: invalid_use_of_internal_member
  final signalClient = lk_signal.SignalClient(_FreshLiveKitWebSocket.connect);
  final engine = lk_engine.Engine(
    connectOptions: const lk.ConnectOptions(),
    roomOptions: roomOptions,
    signalClient: signalClient,
  );
  return lk.Room(roomOptions: roomOptions, engine: engine);
}

/// Owns one HttpClient for one signal socket, so an upgrade cannot reuse an
/// idle connection from Dart's process-wide WebSocket client pool.
class _FreshLiveKitWebSocket extends lk_websocket.LiveKitWebSocket {
  _FreshLiveKitWebSocket._(this._socket, this._httpClient, [this._handlers]) {
    _subscription = _socket.listen(
      (dynamic data) {
        if (isDisposed) {
          return;
        }
        _handlers?.onData?.call(data);
      },
      onDone: () => _handleSocketTerminated(),
      // Without this the stream error is unhandled and, worse, `onDone` may
      // never arrive - leaving SignalClient believing it is still connected on
      // a socket that is finished. An error is a terminal socket event and is
      // treated as one.
      onError: (Object error, StackTrace stackTrace) {
        _handlers?.onError?.call(error);
        _handleSocketTerminated();
      },
    );

    onDispose(() async {
      await _subscription.cancel();
      if (_socket.readyState != io.WebSocket.closed) {
        await _socket.close();
      }
      _httpClient.close(force: true);
    });
  }

  /// Guards the terminal path so it runs exactly once whether the socket
  /// finishes through `onDone`, through `onError`, or both.
  bool _terminated = false;

  void _handleSocketTerminated() {
    if (_terminated) {
      return;
    }
    _terminated = true;
    _handlers?.onDispose?.call();

    // Dispose THIS object, not just notify the SDK's handler. The registered
    // `onDispose` block below is what cancels the subscription, closes the
    // socket, and closes the owned HttpClient - and none of it runs unless
    // `dispose()` is called. Notifying `_handlers.onDispose` only tells
    // SignalClient the socket is gone.
    //
    // That distinction matters most here: this class exists to own a dedicated
    // HttpClient so a signal upgrade cannot borrow a connection from Dart's
    // process-wide pool. Leaking it on a terminal socket event would leak the
    // exact resource the class was written to control.
    if (!isDisposed) {
      unawaited(dispose());
    }
  }

  final io.WebSocket _socket;
  final io.HttpClient _httpClient;
  final lk_websocket.WebSocketEventHandlers? _handlers;
  late final StreamSubscription _subscription;

  /// Upper bound on a single connect attempt.
  ///
  /// `SignalClient` already bounds its await at 10 seconds, but a
  /// `Future.timeout` on the caller's side does not cancel
  /// `io.WebSocket.connect` - the connect keeps running, and with it the
  /// per-attempt [io.HttpClient] this class exists to own. Against an SFU that
  /// accepts the TCP connection and then black-holes the upgrade, every retry
  /// therefore stranded another client. Bounding it HERE is what makes the
  /// cleanup reachable. Slightly under the caller's bound so this path, which
  /// can clean up, is the one that fires.
  static const Duration _connectTimeout = Duration(seconds: 9);

  static Future<_FreshLiveKitWebSocket> connect(
    Uri uri, {
    lk_websocket.WebSocketEventHandlers? options,
    Map<String, String>? headers,
  }) async {
    final httpClient = io.HttpClient();
    final connecting = io.WebSocket.connect(
      uri.toString(),
      headers: headers,
      customClient: httpClient,
    );
    try {
      final socket = await connecting.timeout(_connectTimeout);
      return _FreshLiveKitWebSocket._(socket, httpClient, options);
    } catch (error) {
      // The late-socket closer is registered HERE, on the failure path, and
      // never up front.
      //
      // Callbacks on a Dart future run in registration order, and
      // `connecting.timeout(...)` registers its own listener. A `then` attached
      // before the await therefore runs BEFORE the awaiting code resumes - so a
      // guard keyed on a "handed off" flag set after the await always observed
      // it as false and closed the socket on a perfectly normal connect. That
      // left `send` dropping every frame because the socket was no longer open,
      // which is LiveKit signalling failing on every call. Measured, not
      // reasoned about: a probe confirmed `then` runs first.
      //
      // Only the timeout leaves a socket ownerless, so only the timeout needs
      // the closer. `httpClient.close(force: true)` usually aborts the pending
      // connect outright and the callback never fires; it is registered anyway
      // because "usually" is not a guarantee.
      if (error is TimeoutException) {
        unawaited(
          connecting.then((socket) => socket.close()).catchError((_) {}),
        );
      }
      httpClient.close(force: true);
      rethrow;
    }
  }

  @override
  void send(List<int> data) {
    if (_socket.readyState != io.WebSocket.open) {
      return;
    }
    try {
      _socket.add(data);
    } catch (_) {
      // The owning SignalClient handles the failed connection lifecycle.
    }
  }
}
