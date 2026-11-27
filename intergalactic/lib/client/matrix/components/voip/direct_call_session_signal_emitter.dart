import 'dart:async';

import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_media_operation_gate.dart';

class DirectCallSessionSignalEmitter {
  final StreamController<VoipSession> _onSessionStarted =
      StreamController.broadcast();
  final StreamController<VoipSession> _onSessionEnded =
      StreamController.broadcast();
  bool _disposed = false;

  Stream<VoipSession> get onSessionStarted => _onSessionStarted.stream;

  Stream<VoipSession> get onSessionEnded => _onSessionEnded.stream;

  bool get canNotifySessionStarted => DirectCallMediaOperationGate.shouldNotify(
    disposed: _disposed,
    closed: _onSessionStarted.isClosed,
  );

  bool get canNotifySessionEnded => DirectCallMediaOperationGate.shouldNotify(
    disposed: _disposed,
    closed: _onSessionEnded.isClosed,
  );

  bool notifySessionStarted(VoipSession session) {
    if (!canNotifySessionStarted) {
      return false;
    }

    _onSessionStarted.add(session);
    return true;
  }

  bool notifySessionEnded(VoipSession session) {
    if (!canNotifySessionEnded) {
      return false;
    }

    _onSessionEnded.add(session);
    return true;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await Future.wait([_onSessionStarted.close(), _onSessionEnded.close()]);
  }
}
