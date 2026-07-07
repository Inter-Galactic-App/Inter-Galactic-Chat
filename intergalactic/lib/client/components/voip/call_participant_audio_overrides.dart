import 'package:intergalactic/client/components/voip/voip_stream.dart';

class CallParticipantAudioOverrides {
  CallParticipantAudioOverrides({Map<String, double>? initialValues})
    : _values = initialValues ?? <String, double>{};

  static const double _volumeMatchTolerance = 0.001;

  final Map<String, double> _values;

  int get length => _values.length;

  Iterable<double> get storedVolumes => _values.values;

  static String keyForUser(String userId) {
    return 'participant:$userId:microphone';
  }

  String keyForStream(VoipStream stream) {
    return keyForUser(stream.streamUserId);
  }

  bool supportsStream(VoipStream stream, {required bool isMicrophoneAudio}) {
    if (!isMicrophoneAudio ||
        stream.type == VoipStreamType.screenshare ||
        stream is! LocalPlaybackVolumeStream) {
      return false;
    }

    final volumeStream = stream as LocalPlaybackVolumeStream;
    return volumeStream.hasLocalPlaybackAudio;
  }

  void remember(
    VoipStream stream, {
    required double volume,
    required double defaultVolume,
    required bool isMicrophoneAudio,
  }) {
    if (!supportsStream(stream, isMicrophoneAudio: isMicrophoneAudio)) {
      return;
    }

    final volumeTarget = stream as LocalPlaybackVolumeStream;
    final key = keyForStream(stream);
    if ((volume - defaultVolume).abs() < _volumeMatchTolerance) {
      _values.remove(key);
      volumeTarget.clearLocalPlaybackVolumeOverride();
      return;
    }

    _values[key] = volume;
  }

  Future<bool> restore(
    VoipStream stream, {
    required bool isMicrophoneAudio,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (!supportsStream(stream, isMicrophoneAudio: isMicrophoneAudio)) {
      return false;
    }

    final storedVolume = _values[keyForStream(stream)];
    if (storedVolume == null) {
      return false;
    }

    final volumeTarget = stream as LocalPlaybackVolumeStream;
    final locallyMuted = storedVolume == 0.0;
    final volumeMatches =
        (volumeTarget.localVolume - storedVolume).abs() < _volumeMatchTolerance;
    if (volumeMatches && volumeTarget.locallyMuted == locallyMuted) {
      return false;
    }

    try {
      await volumeTarget.setLocalVolume(storedVolume);
      return true;
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      return false;
    }
  }
}
