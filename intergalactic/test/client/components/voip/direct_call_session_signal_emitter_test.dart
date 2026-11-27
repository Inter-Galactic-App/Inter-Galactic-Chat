import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_session_signal_emitter.dart';

void main() {
  group('DirectCallSessionSignalEmitter', () {
    test('emits direct call session start and end while active', () async {
      final emitter = DirectCallSessionSignalEmitter();
      addTearDown(emitter.dispose);

      final startedSession = _FakeVoipSession('started-session');
      final endedSession = _FakeVoipSession('ended-session');
      final started = emitter.onSessionStarted.first;
      final ended = emitter.onSessionEnded.first;

      expect(emitter.notifySessionStarted(startedSession), isTrue);
      expect(emitter.notifySessionEnded(endedSession), isTrue);

      expect(await started, same(startedSession));
      expect(await ended, same(endedSession));
    });

    test('ignores direct call session signals after dispose', () async {
      final emitter = DirectCallSessionSignalEmitter();
      final started = <VoipSession>[];
      final ended = <VoipSession>[];
      final startedSubscription = emitter.onSessionStarted.listen(started.add);
      final endedSubscription = emitter.onSessionEnded.listen(ended.add);
      addTearDown(startedSubscription.cancel);
      addTearDown(endedSubscription.cancel);

      await emitter.dispose();

      expect(emitter.canNotifySessionStarted, isFalse);
      expect(emitter.canNotifySessionEnded, isFalse);
      expect(
        emitter.notifySessionStarted(_FakeVoipSession('late-start')),
        isFalse,
      );
      expect(emitter.notifySessionEnded(_FakeVoipSession('late-end')), isFalse);

      await Future<void>.delayed(Duration.zero);
      expect(started, isEmpty);
      expect(ended, isEmpty);
    });

    test('dispose is idempotent', () async {
      final emitter = DirectCallSessionSignalEmitter();

      await emitter.dispose();

      expect(emitter.dispose(), completes);
    });
  });
}

class _FakeVoipSession implements VoipSession {
  const _FakeVoipSession(this.sessionId);

  @override
  final String sessionId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
