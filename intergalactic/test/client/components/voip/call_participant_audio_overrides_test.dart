import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_participant_audio_overrides.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

void main() {
  group('CallParticipantAudioOverrides', () {
    test('keys participant audio by stable Matrix user identity', () async {
      final overrides = CallParticipantAudioOverrides();
      final original = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'livekit-audio-sid-1',
        localVolume: 1,
      );
      final replacement = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'livekit-audio-sid-2',
        localVolume: 1,
      );

      overrides.remember(
        original,
        volume: 0.35,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final restored = await overrides.restore(
        replacement,
        isMicrophoneAudio: true,
      );

      expect(restored, isTrue);
      expect(replacement.setVolumes, [0.35]);
      expect(overrides.length, 1);
    });

    test(
      'survives UI rebuild-style helper recreation with retained state',
      () async {
        final retainedState = <String, double>{};
        final firstBuildOverrides = CallParticipantAudioOverrides(
          initialValues: retainedState,
        );
        final rebuiltOverrides = CallParticipantAudioOverrides(
          initialValues: retainedState,
        );
        final original = _FakePlaybackStream(
          streamUserId: '@rebuild:example.org',
          streamId: 'stream-before-rebuild',
          localVolume: 1,
        );
        final replacement = _FakePlaybackStream(
          streamUserId: '@rebuild:example.org',
          streamId: 'stream-after-rebuild',
          localVolume: 1,
        );

        firstBuildOverrides.remember(
          original,
          volume: 0.45,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        final restored = await rebuiltOverrides.restore(
          replacement,
          isMicrophoneAudio: true,
        );

        expect(restored, isTrue);
        expect(replacement.setVolumes, [0.45]);
        expect(firstBuildOverrides.length, 1);
        expect(rebuiltOverrides.length, 1);
      },
    );

    test('metadata updates do not reset a stable-user override', () async {
      final overrides = CallParticipantAudioOverrides();
      final original = _FakePlaybackStream(
        streamUserId: '@renamed:example.org',
        streamId: 'stream-before-metadata',
        label: 'Old display name',
        localVolume: 1,
      );
      final metadataReplacement = _FakePlaybackStream(
        streamUserId: '@renamed:example.org',
        streamId: 'stream-after-metadata',
        label: 'New display name',
        localVolume: 1,
      );

      overrides.remember(
        original,
        volume: 0,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final restored = await overrides.restore(
        metadataReplacement,
        isMicrophoneAudio: true,
      );

      expect(restored, isTrue);
      expect(metadataReplacement.setVolumes, [0]);
      expect(metadataReplacement.locallyMuted, isTrue);
      expect(overrides.length, 1);
    });

    test(
      'shared display metadata does not leak override across users',
      () async {
        final overrides = CallParticipantAudioOverrides();
        final original = _FakePlaybackStream(
          streamUserId: '@alpha:example.org',
          streamId: 'alpha-stream',
          label: 'Shared display name',
          localVolume: 1,
        );
        final differentUser = _FakePlaybackStream(
          streamUserId: '@beta:example.org',
          streamId: 'beta-stream',
          label: 'Shared display name',
          localVolume: 1,
        );

        overrides.remember(
          original,
          volume: 0.3,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        final restored = await overrides.restore(
          differentUser,
          isMicrophoneAudio: true,
        );

        expect(restored, isFalse);
        expect(differentUser.setVolumes, isEmpty);
        expect(overrides.length, 1);
      },
    );

    test(
      'restores independent overrides after participants leave and rejoin',
      () async {
        final overrides = CallParticipantAudioOverrides();
        final alphaBefore = _FakePlaybackStream(
          streamUserId: '@alpha:example.org',
          streamId: 'alpha-before',
          localVolume: 1,
        );
        final betaBefore = _FakePlaybackStream(
          streamUserId: '@beta:example.org',
          streamId: 'beta-before',
          localVolume: 1,
        );
        final alphaAfterRejoin = _FakePlaybackStream(
          streamUserId: '@alpha:example.org',
          streamId: 'alpha-after-rejoin',
          localVolume: 1,
        );
        final betaAfterRejoin = _FakePlaybackStream(
          streamUserId: '@beta:example.org',
          streamId: 'beta-after-rejoin',
          localVolume: 1,
        );

        overrides.remember(
          alphaBefore,
          volume: 0,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );
        overrides.remember(
          betaBefore,
          volume: 0.65,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        expect(
          await overrides.restore(alphaAfterRejoin, isMicrophoneAudio: true),
          isTrue,
        );
        expect(
          await overrides.restore(betaAfterRejoin, isMicrophoneAudio: true),
          isTrue,
        );

        expect(alphaAfterRejoin.setVolumes, [0]);
        expect(alphaAfterRejoin.locallyMuted, isTrue);
        expect(betaAfterRejoin.setVolumes, [0.65]);
        expect(betaAfterRejoin.locallyMuted, isFalse);
        expect(overrides.length, 2);
      },
    );

    test(
      'restores zero volume as a local mute on replacement stream',
      () async {
        final overrides = CallParticipantAudioOverrides();
        final original = _FakePlaybackStream(
          streamUserId: '@muted:example.org',
          streamId: 'stream-before',
          localVolume: 1,
        );
        final replacement = _FakePlaybackStream(
          streamUserId: '@muted:example.org',
          streamId: 'stream-after',
          localVolume: 1,
        );

        overrides.remember(
          original,
          volume: 0,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        final restored = await overrides.restore(
          replacement,
          isMicrophoneAudio: true,
        );

        expect(restored, isTrue);
        expect(replacement.setVolumes, [0]);
        expect(replacement.locallyMuted, isTrue);
      },
    );

    test(
      'reports stale stream restore failure without dropping override',
      () async {
        final overrides = CallParticipantAudioOverrides();
        final original = _FakePlaybackStream(
          streamUserId: '@stale:example.org',
          streamId: 'stream-before',
          localVolume: 1,
        );
        final staleReplacement = _FakePlaybackStream(
          streamUserId: '@stale:example.org',
          streamId: 'stream-stale',
          localVolume: 1,
          throwOnSetLocalVolume: true,
        );
        final healthyReplacement = _FakePlaybackStream(
          streamUserId: '@stale:example.org',
          streamId: 'stream-after',
          localVolume: 1,
        );
        Object? reportedError;
        StackTrace? reportedStackTrace;

        overrides.remember(
          original,
          volume: 0.4,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        final staleRestored = await overrides.restore(
          staleReplacement,
          isMicrophoneAudio: true,
          onError: (error, stackTrace) {
            reportedError = error;
            reportedStackTrace = stackTrace;
          },
        );
        final healthyRestored = await overrides.restore(
          healthyReplacement,
          isMicrophoneAudio: true,
        );

        expect(staleRestored, isFalse);
        expect(reportedError, isA<StateError>());
        expect(reportedStackTrace, isNotNull);
        expect(overrides.length, 1);
        expect(healthyRestored, isTrue);
        expect(healthyReplacement.setVolumes, [0.4]);
      },
    );

    test('clears stored override when volume returns to default', () async {
      final overrides = CallParticipantAudioOverrides();
      final stream = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'livekit-audio-sid',
        localVolume: 0.5,
      );

      overrides.remember(
        stream,
        volume: 0.5,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );
      overrides.remember(
        stream,
        volume: 1,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final restored = await overrides.restore(stream, isMicrophoneAudio: true);

      expect(overrides.length, 0);
      expect(stream.clearOverrideCount, 1);
      expect(restored, isFalse);
    });

    test('ignores screenshare and non-microphone audio streams', () async {
      final overrides = CallParticipantAudioOverrides();
      final screenshare = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'screen',
        type: VoipStreamType.screenshare,
      );
      final sharedAudio = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'screen-audio',
      );

      overrides.remember(
        screenshare,
        volume: 0.2,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );
      overrides.remember(
        sharedAudio,
        volume: 0.2,
        defaultVolume: 1,
        isMicrophoneAudio: false,
      );

      expect(overrides.length, 0);
      expect(
        await overrides.restore(screenshare, isMicrophoneAudio: true),
        isFalse,
      );
      expect(
        await overrides.restore(sharedAudio, isMicrophoneAudio: false),
        isFalse,
      );
      expect(screenshare.setVolumes, isEmpty);
      expect(sharedAudio.setVolumes, isEmpty);
    });

    test('skips restore when the replacement already matches', () async {
      final overrides = CallParticipantAudioOverrides();
      final stream = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'stream',
        localVolume: 0.5,
      );

      overrides.remember(
        stream,
        volume: 0.5,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final restored = await overrides.restore(stream, isMicrophoneAudio: true);

      expect(restored, isFalse);
      expect(stream.setVolumes, isEmpty);
    });
  });
}

class _FakePlaybackStream implements VoipStream, LocalPlaybackVolumeStream {
  _FakePlaybackStream({
    required this.streamUserId,
    required this.streamId,
    this.type = VoipStreamType.audio,
    String? label,
    this.localVolume = 1,
    this.throwOnSetLocalVolume = false,
  }) : label = label ?? streamUserId;

  @override
  final String streamUserId;

  @override
  final String streamId;

  @override
  final VoipStreamType type;

  @override
  double localVolume;

  final bool throwOnSetLocalVolume;
  final List<double> setVolumes = <double>[];
  int clearOverrideCount = 0;

  @override
  bool get hasLocalPlaybackAudio => true;

  @override
  bool get hasLocalPlaybackVolumeOverride => setVolumes.isNotEmpty;

  @override
  bool get locallyMuted => localVolume <= 0;

  @override
  Future<void> setLocalVolume(double volume) async {
    if (throwOnSetLocalVolume) {
      throw StateError('stale playback stream');
    }
    localVolume = volume;
    setVolumes.add(volume);
  }

  @override
  Future<void> setDefaultLocalVolume(double volume) {
    return setLocalVolume(volume);
  }

  @override
  void clearLocalPlaybackVolumeOverride() {
    clearOverrideCount++;
  }

  @override
  double? get aspectRatio => null;

  @override
  double get audiolevel => 0;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  bool get isMuted => locallyMuted;

  @override
  final String label;

  @override
  Stream<void> get onStreamChanged => const Stream<void>.empty();

  @override
  VoipStreamReceivePriority get receivePriority =>
      VoipStreamReceivePriority.high;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {}
}
