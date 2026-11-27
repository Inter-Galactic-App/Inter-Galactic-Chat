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
          deafened: false,
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
          deafened: false,
        ),
        isTrue,
      );
    });

    // F-06. This is the recovery branch for a republished screen-share audio
    // stream: the stream constructor asserts the mute, and CallView has no
    // record of having muted it, so `mutedByVisibility` is false and only the
    // "silent but not user-muted" disjunct can make it audible again.
    //
    // Deafen lands in *exactly* that state - `setLocalMute(true)` sets the mute
    // bit and leaves `_localVolume` alone - so before `deafened` existed this
    // branch cleared the deafen on the next build of a visible screen share.
    // The pair below is the only evidence this mechanism will ever have: it is
    // confirmed in source but produced zero log output across the entire
    // recovered capture corpus, so keep both halves.
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
          deafened: false,
        ),
        isTrue,
      );
    });

    test(
      'does not unmute visible incoming screen-share audio while deafened',
      () {
        expect(
          VoipReceiveQualityPolicy.shouldUnmuteScreenShareAudioForVisibility(
            direction: VoipStreamDirection.incoming,
            hasMatchingScreenShareTile: true,
            screenShareVideoHidden: false,
            mutedByVisibility: false,
            locallyMuted: true,
            mutedByUser: false,
            localVolume: 0.75,
            deafened: true,
          ),
          isFalse,
        );
      },
    );

    test('does not unmute local playback while deafened', () {
      // Same shape as 'unmutes visible incoming local playback muted by
      // visibility' above, deafened. Deafen outranks a visibility unmute too:
      // CallView clears the mute through `setLocalMute(false)`, which is the
      // same single bit deafen asserted, so *any* unmute here undoes deafen.
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteLocalPlaybackForVisibility(
          direction: VoipStreamDirection.incoming,
          hasVisibleSurface: true,
          streamHidden: false,
          mutedByVisibility: true,
          locallyMuted: true,
          mutedByUser: false,
          localVolume: 1,
          deafened: true,
        ),
        isFalse,
      );
    });

    test('does not unmute silent local playback while deafened', () {
      // The SECOND disjunct. `shouldUnmuteLocalPlaybackForVisibility` can reach
      // an unmute two ways - `mutedByVisibility`, or silent-but-not-user-muted
      // - and the test above pins only the first. Because `mutedByVisibility:
      // true` short-circuits, a deafen guard placed inside that branch alone
      // would let a deafened stream with `mutedByVisibility: false` unmute, and
      // the suite would stay green. The screen-share function has this case;
      // local playback did not.
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteLocalPlaybackForVisibility(
          direction: VoipStreamDirection.incoming,
          hasVisibleSurface: true,
          streamHidden: false,
          mutedByVisibility: false,
          locallyMuted: true,
          mutedByUser: false,
          localVolume: 0.75,
          deafened: true,
        ),
        isFalse,
      );
    });

    test('resumes the visibility unmute once deafen is released', () {
      // Un-deafen does not re-open screen-share audio itself
      // (CallManager._applyDeafenToStream deliberately returns early for it),
      // so this branch firing again is what makes the stream audible. If this
      // ever goes false the symptom is permanently silent screen-share audio
      // after a deafen/undeafen cycle.
      expect(
        VoipReceiveQualityPolicy.shouldUnmuteScreenShareAudioForVisibility(
          direction: VoipStreamDirection.incoming,
          hasMatchingScreenShareTile: true,
          screenShareVideoHidden: false,
          mutedByVisibility: false,
          locallyMuted: true,
          mutedByUser: false,
          localVolume: 1,
          deafened: false,
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
          deafened: false,
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
          deafened: false,
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
          deafened: false,
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
          deafened: false,
        ),
        isFalse,
      );
    });
  });
}
