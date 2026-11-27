import 'package:meta/meta.dart';

/// Rides out single-frame gaps in screenshare-audio tile visibility.
///
/// `CallView._syncHiddenTileAudioMute` decides whether remote screenshare audio
/// should be muted from whether a matching screenshare *video* tile is present
/// in the tile list. A tile leaves that list for reasons that have nothing to do
/// with visibility - a publish/unpublish, a popout transition, a membership
/// refresh, or the layout-slot key change that tears every `VoipStreamView` down
/// and rebuilds it. Each of those flips the verdict to hidden for one frame and
/// back on the next, and each flip is a real mute/unmute on the track: 666
/// audible episodes at a median of 18 ms in the 2026-08-02 capture (BUG-282),
/// heard as clicking rather than as a clean mute.
///
/// This holds the previous verdict for [window] after a real surface disappears.
///
/// ## The invariant that makes it terminate
///
/// The grace timestamp records the last moment a **real** surface existed. It is
/// never written from a grace-held verdict. Refreshing it from the effective
/// verdict renews the window on every rebuild, and an active call rebuilds
/// constantly - so a genuinely hidden screenshare would stay audible forever
/// instead of muting after [window]. That defect existed in the first version of
/// this fix and was caught in review; [resolve] is written the way it is
/// specifically to prevent it, and `screenshare_audio_visibility_grace_test.dart`
/// hammers repeated in-window evaluations to prove it terminates.
class ScreenshareAudioVisibilityGrace {
  ScreenshareAudioVisibilityGrace({
    this.window = const Duration(milliseconds: 600),
  });

  /// How long a stream keeps its last real verdict after the surface goes away.
  /// Only has to outlast a teardown/rebuild, not a user action.
  final Duration window;

  final Map<String, DateTime> _lastRealVisibleAt = <String, DateTime>{};

  /// Effective visibility for [streamId].
  ///
  /// [realVisible] is whether a genuine tile or popout surface exists right now.
  /// Returns true when the stream should be treated as visible, either because
  /// it really is or because it is still inside the grace window.
  bool resolve({
    required String streamId,
    required bool realVisible,
    required DateTime now,
  }) {
    if (realVisible) {
      _lastRealVisibleAt[streamId] = now;
      return true;
    }

    final lastRealVisibleAt = _lastRealVisibleAt[streamId];
    if (lastRealVisibleAt != null &&
        now.difference(lastRealVisibleAt) < window) {
      // Grace-held. Deliberately does NOT touch the timestamp - see the class
      // doc. The window must keep counting from the last REAL sighting.
      return true;
    }

    // Either the grace expired or the surface was never seen. Drop the mark so
    // a later gap cannot resurrect a stale sighting.
    _lastRealVisibleAt.remove(streamId);
    return false;
  }

  /// Time left before [streamId]'s grace expires, or null when it is not being
  /// held. Used to schedule the one re-evaluation that applies the mute when
  /// nothing else rebuilds the view.
  Duration? graceRemaining(String streamId, DateTime now) {
    final lastRealVisibleAt = _lastRealVisibleAt[streamId];
    if (lastRealVisibleAt == null) {
      return null;
    }
    final remaining = window - now.difference(lastRealVisibleAt);
    return remaining > Duration.zero ? remaining : null;
  }

  /// Drops bookkeeping for streams that no longer exist.
  void retainOnly(Set<String> liveStreamIds) {
    _lastRealVisibleAt.removeWhere((id, _) => !liveStreamIds.contains(id));
  }

  void reset() {
    _lastRealVisibleAt.clear();
  }

  @visibleForTesting
  int get trackedCount => _lastRealVisibleAt.length;
}
