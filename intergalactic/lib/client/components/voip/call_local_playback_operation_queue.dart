/// Serializes local playback writes for one VoIP stream.
///
/// Volume, mute, and track lifecycle callbacks can otherwise race and leave a
/// stale mute/volume write as the last operation applied to the remote track.
class CallLocalPlaybackOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
