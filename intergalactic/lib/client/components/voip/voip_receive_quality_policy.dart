import 'package:intergalactic/client/components/voip/voip_stream.dart';

enum VoipReceiveVideoQuality {
  low,
  medium,
  high,
}

class VoipReceiveQualityApplication {
  const VoipReceiveQualityApplication({
    required this.requestedPriority,
    required this.liveKitQualityLabel,
    required this.subscribe,
    required this.enable,
    required this.videoQuality,
  });

  final VoipStreamReceivePriority requestedPriority;
  final String liveKitQualityLabel;
  final bool subscribe;
  final bool enable;
  final VoipReceiveVideoQuality? videoQuality;

  static VoipReceiveQualityApplication fromPriority(
    VoipStreamReceivePriority priority,
  ) {
    return switch (priority) {
      VoipStreamReceivePriority.disabled => const VoipReceiveQualityApplication(
          requestedPriority: VoipStreamReceivePriority.disabled,
          liveKitQualityLabel: 'disabled',
          subscribe: false,
          enable: false,
          videoQuality: null,
        ),
      VoipStreamReceivePriority.low => const VoipReceiveQualityApplication(
          requestedPriority: VoipStreamReceivePriority.low,
          liveKitQualityLabel: 'LOW',
          subscribe: true,
          enable: true,
          videoQuality: VoipReceiveVideoQuality.low,
        ),
      VoipStreamReceivePriority.medium => const VoipReceiveQualityApplication(
          requestedPriority: VoipStreamReceivePriority.medium,
          liveKitQualityLabel: 'MEDIUM',
          subscribe: true,
          enable: true,
          videoQuality: VoipReceiveVideoQuality.medium,
        ),
      VoipStreamReceivePriority.high => const VoipReceiveQualityApplication(
          requestedPriority: VoipStreamReceivePriority.high,
          liveKitQualityLabel: 'HIGH',
          subscribe: true,
          enable: true,
          videoQuality: VoipReceiveVideoQuality.high,
        ),
    };
  }
}

class VoipReceiveQualityPolicy {
  const VoipReceiveQualityPolicy._();

  static bool shouldMuteScreenShareAudioForVisibility({
    required VoipStreamDirection direction,
    required bool hasMatchingScreenShareTile,
    required bool screenShareVideoHidden,
  }) {
    if (direction != VoipStreamDirection.incoming) {
      return false;
    }

    return !hasMatchingScreenShareTile || screenShareVideoHidden;
  }

  static bool shouldUnmuteScreenShareAudioForVisibility({
    required VoipStreamDirection direction,
    required bool hasMatchingScreenShareTile,
    required bool screenShareVideoHidden,
    required bool mutedByVisibility,
    required bool locallyMuted,
    required bool mutedByUser,
    required double localVolume,
  }) {
    if (direction != VoipStreamDirection.incoming ||
        !hasMatchingScreenShareTile ||
        screenShareVideoHidden) {
      return false;
    }

    return mutedByVisibility ||
        (!mutedByUser && locallyMuted && localVolume > 0);
  }

  static VoipStreamReceivePriority resolve({
    required VoipStreamType type,
    required VoipStreamDirection direction,
    required bool hidden,
    required bool focused,
    required bool fullscreen,
    required bool poppedOut,
    required int visibleVideoStreamCount,
    required int visibleScreenshareCount,
  }) {
    if (direction == VoipStreamDirection.outgoing ||
        type == VoipStreamType.audio) {
      return VoipStreamReceivePriority.high;
    }

    if (hidden) {
      return VoipStreamReceivePriority.disabled;
    }

    if (focused || fullscreen || poppedOut) {
      return VoipStreamReceivePriority.high;
    }

    if (type == VoipStreamType.screenshare) {
      return visibleScreenshareCount >= 3
          ? VoipStreamReceivePriority.low
          : VoipStreamReceivePriority.medium;
    }

    if (type == VoipStreamType.video) {
      return visibleVideoStreamCount >= 6
          ? VoipStreamReceivePriority.low
          : VoipStreamReceivePriority.medium;
    }

    return VoipStreamReceivePriority.high;
  }
}
