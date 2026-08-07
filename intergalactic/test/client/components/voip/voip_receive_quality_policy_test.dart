import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_receive_quality_policy.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

void main() {
  group('VoipReceiveQualityPolicy', () {
    test('disables hidden remote screen shares', () {
      final priority = VoipReceiveQualityPolicy.resolve(
        type: VoipStreamType.screenshare,
        direction: VoipStreamDirection.incoming,
        hidden: true,
        focused: false,
        fullscreen: false,
        poppedOut: false,
        visibleVideoStreamCount: 0,
        visibleScreenshareCount: 0,
      );

      expect(priority, VoipStreamReceivePriority.disabled);
    });

    test('keeps focused screen share high quality', () {
      final priority = VoipReceiveQualityPolicy.resolve(
        type: VoipStreamType.screenshare,
        direction: VoipStreamDirection.incoming,
        hidden: false,
        focused: true,
        fullscreen: false,
        poppedOut: false,
        visibleVideoStreamCount: 3,
        visibleScreenshareCount: 3,
      );

      expect(priority, VoipStreamReceivePriority.high);
    });

    test('uses medium for visible non-focused screen shares until crowded', () {
      final medium = VoipReceiveQualityPolicy.resolve(
        type: VoipStreamType.screenshare,
        direction: VoipStreamDirection.incoming,
        hidden: false,
        focused: false,
        fullscreen: false,
        poppedOut: false,
        visibleVideoStreamCount: 2,
        visibleScreenshareCount: 2,
      );
      final low = VoipReceiveQualityPolicy.resolve(
        type: VoipStreamType.screenshare,
        direction: VoipStreamDirection.incoming,
        hidden: false,
        focused: false,
        fullscreen: false,
        poppedOut: false,
        visibleVideoStreamCount: 3,
        visibleScreenshareCount: 3,
      );

      expect(medium, VoipStreamReceivePriority.medium);
      expect(low, VoipStreamReceivePriority.low);
    });

    test('disables hidden cameras without muting audio policy', () {
      final hiddenCamera = VoipReceiveQualityPolicy.resolve(
        type: VoipStreamType.video,
        direction: VoipStreamDirection.incoming,
        hidden: true,
        focused: false,
        fullscreen: false,
        poppedOut: false,
        visibleVideoStreamCount: 1,
        visibleScreenshareCount: 0,
      );
      final audio = VoipReceiveQualityPolicy.resolve(
        type: VoipStreamType.audio,
        direction: VoipStreamDirection.incoming,
        hidden: true,
        focused: false,
        fullscreen: false,
        poppedOut: false,
        visibleVideoStreamCount: 1,
        visibleScreenshareCount: 0,
      );

      expect(hiddenCamera, VoipStreamReceivePriority.disabled);
      expect(audio, VoipStreamReceivePriority.high);
    });

    test('hidden incoming video disables LiveKit subscription application', () {
      final priority = VoipReceiveQualityPolicy.resolve(
        type: VoipStreamType.video,
        direction: VoipStreamDirection.incoming,
        hidden: true,
        focused: false,
        fullscreen: false,
        poppedOut: false,
        visibleVideoStreamCount: 0,
        visibleScreenshareCount: 0,
      );
      final application = VoipReceiveQualityApplication.fromPriority(priority);

      expect(priority, VoipStreamReceivePriority.disabled);
      expect(application.subscribe, isFalse);
      expect(application.enable, isFalse);
      expect(application.videoQuality, isNull);
    });

    test('maps priorities to LiveKit subscription and quality labels', () {
      final disabled = VoipReceiveQualityApplication.fromPriority(
        VoipStreamReceivePriority.disabled,
      );
      final low = VoipReceiveQualityApplication.fromPriority(
        VoipStreamReceivePriority.low,
      );
      final medium = VoipReceiveQualityApplication.fromPriority(
        VoipStreamReceivePriority.medium,
      );
      final high = VoipReceiveQualityApplication.fromPriority(
        VoipStreamReceivePriority.high,
      );

      expect(disabled.liveKitQualityLabel, 'disabled');
      expect(disabled.subscribe, isFalse);
      expect(disabled.enable, isFalse);
      expect(disabled.videoQuality, isNull);
      expect(low.liveKitQualityLabel, 'LOW');
      expect(low.videoQuality, VoipReceiveVideoQuality.low);
      expect(medium.liveKitQualityLabel, 'MEDIUM');
      expect(medium.videoQuality, VoipReceiveVideoQuality.medium);
      expect(high.liveKitQualityLabel, 'HIGH');
      expect(high.subscribe, isTrue);
      expect(high.enable, isTrue);
      expect(high.videoQuality, VoipReceiveVideoQuality.high);
    });

    test('mutes incoming screen-share audio while video is hidden', () {
      expect(
        VoipReceiveQualityPolicy.shouldMuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.incoming,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: true,
        ),
        isTrue,
      );
      expect(
        VoipReceiveQualityPolicy.shouldMuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.incoming,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: false,
        ),
        isFalse,
      );
    });

    test('mutes incoming screen-share audio before matching video exists', () {
      expect(
        VoipReceiveQualityPolicy.shouldMuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.incoming,
          hasMatchingScreenShareTile: false,
          screenShareVideoHidden: true,
        ),
        isTrue,
      );
    });

    test('mutes hidden incoming local playback targets', () {
      expect(
        VoipReceiveQualityPolicy.shouldMuteLocalPlaybackForVisibility(
          direction: VoipStreamDirection.incoming,
          hasVisibleSurface: true,
          streamHidden: true,
        ),
        isTrue,
      );
      expect(
        VoipReceiveQualityPolicy.shouldMuteLocalPlaybackForVisibility(
          direction: VoipStreamDirection.incoming,
          hasVisibleSurface: false,
          streamHidden: false,
        ),
        isTrue,
      );
    });

    test(
      'does not visibility-mute visible or outgoing local playback targets',
      () {
        expect(
          VoipReceiveQualityPolicy.shouldMuteLocalPlaybackForVisibility(
            direction: VoipStreamDirection.incoming,
            hasVisibleSurface: true,
            streamHidden: false,
          ),
          isFalse,
        );
        expect(
          VoipReceiveQualityPolicy.shouldMuteLocalPlaybackForVisibility(
            direction: VoipStreamDirection.outgoing,
            hasVisibleSurface: true,
            streamHidden: true,
          ),
          isFalse,
        );
      },
    );

    test('does not visibility-mute outgoing screen-share audio', () {
      expect(
        VoipReceiveQualityPolicy.shouldMuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.outgoing,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: true,
        ),
        isFalse,
      );
    });

    test('unmutes visible incoming screen-share audio muted by visibility', () {
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.incoming,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: false,
          mutedByVisibility: true,
          locallyMuted: true,
          mutedByUser: false,
          localVolume: 1,
        ),
        isTrue,
      );
    });

    test('unmutes visible incoming local playback muted by visibility', () {
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteLocalPlaybackForVisibility(
          direction: VoipStreamDirection.incoming,
          hasVisibleSurface: true,
          streamHidden: false,
          mutedByVisibility: true,
          locallyMuted: true,
          mutedByUser: false,
          localVolume: 1,
        ),
        isTrue,
      );
    });

    test('unmutes visible incoming screen-share audio after republish', () {
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.incoming,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: false,
          mutedByVisibility: false,
          locallyMuted: true,
          mutedByUser: false,
          localVolume: 0.75,
        ),
        isTrue,
      );
    });

    test('keeps user-muted visible local playback muted', () {
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteLocalPlaybackForVisibility(
          direction: VoipStreamDirection.incoming,
          hasVisibleSurface: true,
          streamHidden: false,
          mutedByVisibility: false,
          locallyMuted: true,
          mutedByUser: true,
          localVolume: 0,
        ),
        isFalse,
      );
    });

    test('keeps user-muted visible screen-share audio muted', () {
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.incoming,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: false,
          mutedByVisibility: false,
          locallyMuted: true,
          mutedByUser: true,
          localVolume: 0,
        ),
        isFalse,
      );
    });

    test('does not unmute hidden or outgoing screen-share audio', () {
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.incoming,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: true,
          mutedByVisibility: true,
          locallyMuted: true,
          mutedByUser: false,
          localVolume: 1,
        ),
        isFalse,
      );
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.outgoing,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: false,
          mutedByVisibility: true,
          locallyMuted: true,
          mutedByUser: false,
          localVolume: 1,
        ),
        isFalse,
      );
    });
  });
}
