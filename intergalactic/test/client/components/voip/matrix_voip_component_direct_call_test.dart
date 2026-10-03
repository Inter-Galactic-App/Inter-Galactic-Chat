// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_session_owner.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as mx;
import 'package:matrix/src/voip/models/voip_id.dart';

void main() {
  test(
    'emits and releases the started direct-call wrapper when the call ends',
    () async {
      final call = _FakeCallSession();
      final wrapper = _CountedDirectCallSession();
      final component = MatrixVoipComponent(
        _FakeMatrixClient(),
        voip: _FakeVoIP(),
        sessionFactory: (_, _) => wrapper,
      );

      final started = component.onSessionStarted.first;
      final ended = component.onSessionEnded.first;

      await component.handleNewCall(call);
      expect(await started, same(wrapper));

      await component.handleCallEnded(call);

      expect(await ended, same(wrapper));
      expect(wrapper.disposeCalls, 1);

      await component.dispose();
      expect(wrapper.disposeCalls, 1);
    },
  );
}

class _FakeCallSession implements mx.CallSession {
  @override
  String get callId => 'call-1';

  @override
  mx.Room get room => _FakeRoom();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements mx.Room {
  @override
  String get id => '!direct:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoIP implements mx.VoIP {
  @override
  final Map<VoipId, mx.CallSession> calls = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountedDirectCallSession implements DirectCallSession {
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
