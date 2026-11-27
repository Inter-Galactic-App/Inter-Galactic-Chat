import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

void main() {
  group('MatrixLivekitVoipStream lifecycle', () {
    test('updates local playback state and notifies while active', () async {
      final stream = MatrixLivekitVoipStream(
        const _FakeTrackPublication(kind: lk.TrackType.AUDIO),
        '@alice:example.org',
      );
      addTearDown(stream.dispose);
      final events = <void>[];
      final subscription = stream.onStreamChanged.listen(events.add);
      addTearDown(subscription.cancel);

      await stream.setLocalVolume(0.25);
      await Future<void>.delayed(Duration.zero);

      expect(stream.localVolume, 0.25);
      expect(stream.locallyMuted, isFalse);
      expect(stream.hasLocalPlaybackVolumeOverride, isTrue);
      expect(events, hasLength(1));
    });

    test('ignores local playback and stream updates after dispose', () async {
      final stream = MatrixLivekitVoipStream(
        const _FakeTrackPublication(kind: lk.TrackType.AUDIO),
        '@alice:example.org',
      );
      final events = <void>[];
      final subscription = stream.onStreamChanged.listen(events.add);
      addTearDown(subscription.cancel);

      await stream.setLocalVolume(0.25);
      await Future<void>.delayed(Duration.zero);
      await stream.dispose();
      final eventCountAfterDispose = events.length;

      await stream.setLocalVolume(0.75);
      await stream.setLocalMute(true);
      stream.clearLocalPlaybackVolumeOverride();
      stream.onStreamUpdatedEvent();

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(eventCountAfterDispose));
      expect(stream.localVolume, 0.25);
      expect(stream.locallyMuted, isFalse);
      expect(stream.hasLocalPlaybackVolumeOverride, isTrue);
    });

    test('dispose completes while a call tile subscription is still live', () {
      // `dispose()` used to await `close()` on a broadcast controller. A
      // broadcast `close()` future only completes once every past subscriber
      // has cancelled *after* the close, so with a live subscriber it never
      // completes at all. Every mounted call tile holds exactly such a
      // subscription, so hanging up with the call UI on screen - the normal
      // case - wedged the first step of the session teardown, which then never
      // reached `VoipState.ended` and left every later join holding the dead
      // session.
      //
      // fakeAsync rather than a wall-clock timeout so a regression fails
      // immediately instead of hanging the suite.
      fakeAsync((async) {
        final stream = MatrixLivekitVoipStream(
          const _FakeTrackPublication(kind: lk.TrackType.AUDIO),
          '@alice:example.org',
        );
        final subscription = stream.onStreamChanged.listen((_) {});

        var disposed = false;
        stream.dispose().then((_) => disposed = true);
        async.flushMicrotasks();

        expect(
          disposed,
          isTrue,
          reason:
              'stream disposal must not wait on a broadcast close() that a '
              'live call tile can hold open indefinitely',
        );

        subscription.cancel();
        async.flushMicrotasks();
      });
    });
  });
}

class _FakeTrackPublication implements lk.TrackPublication<lk.Track> {
  const _FakeTrackPublication({required this.kind});

  @override
  final lk.TrackType kind;

  @override
  lk.TrackSource get source => lk.TrackSource.microphone;

  @override
  String get name => 'microphone';

  @override
  String get sid => 'publication-a';

  @override
  lk.Track? get track => null;

  @override
  bool get muted => false;

  @override
  bool get subscribed => false;

  @override
  bool get isScreenShare => false;

  @override
  lk.VideoDimensions? get dimensions => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
