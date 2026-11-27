import 'package:webrtc_interface/webrtc_interface.dart';

typedef DirectCallCameraReleaseErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
  String content,
);

class DirectCallCameraOperationQueue {
  Future<void> _operation = Future<void>.value();

  Future<void> run(Future<void> Function() operation) {
    final queued = _operation.then(
      (_) => operation(),
      onError: (Object _, StackTrace __) => operation(),
    );
    _operation = queued.catchError((Object _) {});
    return queued;
  }
}

Future<int> stopAndRemoveDirectCallCameraTracks(
  MediaStream stream, {
  DirectCallCameraReleaseErrorHandler? onError,
}) async {
  final videoTracks = stream.getVideoTracks().toList(growable: false);

  for (final track in videoTracks) {
    try {
      await stream.removeTrack(track);
    } catch (error, stackTrace) {
      onError?.call(
        error,
        stackTrace,
        'Failed to remove direct-call camera track from local stream',
      );
      try {
        await stream.removeTrack(track, removeFromNative: false);
      } catch (fallbackError, fallbackStackTrace) {
        onError?.call(
          fallbackError,
          fallbackStackTrace,
          'Failed to remove direct-call camera track from local stream only',
        );
      }
    }

    try {
      await track.stop();
    } catch (error, stackTrace) {
      onError?.call(
        error,
        stackTrace,
        'Failed to stop direct-call camera track',
      );
    }
  }

  return videoTracks.length;
}
