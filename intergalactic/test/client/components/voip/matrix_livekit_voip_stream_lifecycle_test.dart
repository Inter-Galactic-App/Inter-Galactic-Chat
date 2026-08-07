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
