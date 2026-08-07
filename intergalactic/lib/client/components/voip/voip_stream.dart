import 'package:flutter/widgets.dart';

enum VoipStreamType { audio, video, screenshare }

enum VoipStreamDirection { incoming, outgoing }

enum VoipStreamReceivePriority { disabled, low, medium, high }

abstract class VoipStream {
  VoipStreamType get type;

  VoipStreamDirection get direction;

  Widget? buildVideoRenderer(BoxFit fit, Key key);

  Stream<void> get onStreamChanged;

  VoipStreamReceivePriority get receivePriority;

  Future<void> setReceivePriority(VoipStreamReceivePriority priority);

  String get streamUserId;

  String get label;

  String get streamId;

  double get audiolevel;

  bool get isMuted;

  double? get aspectRatio;
}

abstract class NativePictureInPictureVideoTarget {
  String get nativePiPMediaStreamId;

  String get nativePiPVideoTrackId;

  String? get nativePiPOwnerTag => null;
}

abstract class LocalPlaybackVolumeStream {
  bool get hasLocalPlaybackAudio => true;

  bool get hasLocalPlaybackVolumeOverride => false;

  double get localVolume;

  bool get locallyMuted;

  Future<void> setLocalVolume(double volume);

  Future<void> setDefaultLocalVolume(double volume) {
    return setLocalVolume(volume);
  }

  void clearLocalPlaybackVolumeOverride() {}
}
