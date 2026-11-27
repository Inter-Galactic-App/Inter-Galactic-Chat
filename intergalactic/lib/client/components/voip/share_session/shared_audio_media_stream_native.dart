// ignore_for_file: implementation_imports

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_webrtc/src/native/media_stream_impl.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

MediaStream? windowsSharedAudioStreamInfoToMediaStream(
  WindowsSharedAudioStreamInfo info,
) {
  if (!info.supported || info.streamId.isEmpty || info.audioTracks.isEmpty) {
    return null;
  }

  return MediaStreamNative.fromMap(info.toMediaStreamMap());
}
