import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/stream_lifecycle_cue.dart';

void main() {
  test('protocol accepts only its versioned topic and fixed cue names', () {
    for (final cue in StreamLifecycleCue.values) {
      expect(
        StreamLifecycleCueProtocol.decode(
          StreamLifecycleCueProtocol.topic,
          StreamLifecycleCueProtocol.encode(cue),
        ),
        cue,
      );
    }
    expect(
      StreamLifecycleCueProtocol.decode('other', [115, 116, 97, 114, 116]),
      isNull,
    );
    expect(
      StreamLifecycleCueProtocol.decode(StreamLifecycleCueProtocol.topic, [
        0xff,
      ]),
      isNull,
    );
    expect(
      StreamLifecycleCueProtocol.decode(StreamLifecycleCueProtocol.topic, [
        115,
        116,
        111,
        112,
      ]),
      isNull,
    );
  });

  test('remote cues play once per deliberate active interval', () {
    final state = RemoteStreamLifecycleCueState();
    expect(state.shouldPlay('alice', StreamLifecycleCue.start), isTrue);
    expect(state.shouldPlay('alice', StreamLifecycleCue.start), isFalse);
    expect(state.shouldPlay('alice', StreamLifecycleCue.end), isTrue);
    expect(state.shouldPlay('alice', StreamLifecycleCue.end), isFalse);
    expect(state.shouldPlay('alice', StreamLifecycleCue.start), isTrue);
  });

  test('existing shares and participant departure do not replay start', () {
    final state = RemoteStreamLifecycleCueState()..seedActive('alice');
    expect(state.shouldPlay('alice', StreamLifecycleCue.start), isFalse);
    expect(state.shouldPlay('alice', StreamLifecycleCue.end), isTrue);
    state.seedActive('alice');
    state.participantLeft('alice');
    expect(state.shouldPlay('alice', StreamLifecycleCue.end), isFalse);
    expect(state.shouldPlay('bob', StreamLifecycleCue.start), isTrue);
  });

  test('failed capture refresh ends a previously announced share once', () {
    final local = LocalStreamLifecycleCueState();
    final remote = RemoteStreamLifecycleCueState();
    expect(local.onDeliberateStart(shareActive: true), isTrue);
    expect(remote.shouldPlay('alice', StreamLifecycleCue.start), isTrue);

    // Replacement unpublishes the old video before its new capturer fails.
    expect(local.onShareOperationFinished(shareActive: false), isTrue);
    expect(remote.shouldPlay('alice', StreamLifecycleCue.end), isTrue);
    expect(local.onShareOperationFinished(shareActive: false), isFalse);

    expect(local.onDeliberateStart(shareActive: true), isTrue);
    expect(remote.shouldPlay('alice', StreamLifecycleCue.start), isTrue);
  });

  test('successful internal capture fallback does not replay cues', () {
    final local = LocalStreamLifecycleCueState();
    expect(local.onDeliberateStart(shareActive: true), isTrue);
    // An unpublished old track is a temporary gap, not the final outcome.
    expect(local.onShareOperationFinished(shareActive: true), isFalse);
    expect(local.onDeliberateStart(shareActive: true), isFalse);
    expect(local.onShareOperationFinished(shareActive: false), isTrue);
  });

  test(
    'failed game-capture watchdog fallback sends end and rearms start',
    () async {
      final local = LocalStreamLifecycleCueState();
      final remote = RemoteStreamLifecycleCueState();
      var videoPublished = true;
      var endCount = 0;
      expect(local.onDeliberateStart(shareActive: videoPublished), isTrue);
      expect(remote.shouldPlay('alice', StreamLifecycleCue.start), isTrue);

      await expectLater(
        runScreenShareFallbackWithCueReconciliation(
          fallback: () async {
            videoPublished = false;
            throw StateError('fallback publish failed');
          },
          cueState: local,
          shareActive: () => videoPublished,
          announceEnd: () {
            endCount++;
            expect(remote.shouldPlay('alice', StreamLifecycleCue.end), isTrue);
          },
        ),
        throwsStateError,
      );
      expect(endCount, 1);
      expect(local.onDeliberateStart(shareActive: true), isTrue);
      expect(remote.shouldPlay('alice', StreamLifecycleCue.start), isTrue);
    },
  );

  test('successful game-capture watchdog fallback keeps cue active', () async {
    final local = LocalStreamLifecycleCueState();
    var videoPublished = true;
    var endCount = 0;
    expect(local.onDeliberateStart(shareActive: true), isTrue);
    await runScreenShareFallbackWithCueReconciliation(
      fallback: () async {
        videoPublished = false;
        videoPublished = true;
      },
      cueState: local,
      shareActive: () => videoPublished,
      announceEnd: () => endCount++,
    );
    expect(endCount, 0);
    expect(local.onDeliberateStart(shareActive: true), isFalse);
  });
}
