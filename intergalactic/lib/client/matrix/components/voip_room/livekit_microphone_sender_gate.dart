import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:intergalactic/debug/log.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Whether the local microphone RTP sender is actually carrying the
/// publication's media track.
///
/// This exists because `sender.replaceTrack(null)` - the Windows mute path -
/// is invisible to LiveKit. The SDK never records that the sender was
/// detached, so `publication.muted` becomes the only proxy for it, and the SDK
/// is free to clear that proxy without reattaching anything:
///
/// * `skipStopForTrackMute()` is **true on Windows**
///   (`livekit_client-2.5.4 support/platform.dart:42-44`), so
///   `LocalTrack.unmute()` (`track/local/local.dart:120-129`) skips
///   `restartTrack()` unconditionally there and only calls `enable()` +
///   `updateMuted(false)`. The sender is never reattached.
/// * Every SDK-native unmute reaches that method:
///   `LocalParticipant.setMicrophoneEnabled(true)` ->
///   `setSourceEnabled` -> `publication.unmute()`
///   (`participant/local.dart:669-703`).
///
/// The result is a publication that reports `muted == false` while the sender
/// carries nothing: the UI shows a live mic and remote participants receive
/// silence. Reading real sender state instead of the publication flag is the
/// only way to tell those two states apart.
enum LivekitMicrophoneSenderAttachment {
  /// The sender is carrying this publication's media track.
  attached,

  /// The sender exists but carries nothing (or carries a different track).
  detached,

  /// There is no track or no sender yet, so attachment is not yet decidable.
  /// Never treat this as `detached`: it is also the normal state while a
  /// publication is still being negotiated.
  unknown,
}

/// Single implementation of the Windows microphone sender detach/reattach.
///
/// Two divergent copies of this used to exist - one in
/// `MatrixLivekitVoipSession` and one in `MatrixLivekitBackend` - and they had
/// drifted: the backend copy could only detach, and its "already in the target
/// state" guard did not consider whether the sender was carrying *this*
/// publication's track.
class LivekitMicrophoneSenderGate {
  const LivekitMicrophoneSenderGate._();

  /// Resolves real sender attachment for [publication].
  static LivekitMicrophoneSenderAttachment attachmentOf(
    lk.LocalTrackPublication publication,
  ) {
    final track = publication.track;
    if (track == null) {
      return LivekitMicrophoneSenderAttachment.unknown;
    }

    final rtc.RTCRtpSender? sender = track.sender;
    if (sender == null) {
      return LivekitMicrophoneSenderAttachment.unknown;
    }

    final senderTrack = sender.track;
    if (senderTrack == null) {
      return LivekitMicrophoneSenderAttachment.detached;
    }

    return senderTrack.id == track.mediaStreamTrack.id
        ? LivekitMicrophoneSenderAttachment.attached
        : LivekitMicrophoneSenderAttachment.detached;
  }

  /// True only when the sender is *known* to be carrying nothing.
  ///
  /// [LivekitMicrophoneSenderAttachment.unknown] deliberately answers false so
  /// a publication that has not finished negotiating is not mistaken for a
  /// silently detached one.
  static bool isDetached(lk.LocalTrackPublication publication) =>
      attachmentOf(publication) == LivekitMicrophoneSenderAttachment.detached;

  /// Detaches or reattaches the microphone sender and republishes the muted
  /// metadata to match.
  ///
  /// Returns true when the sender was actually moved.
  ///
  /// [source] is the log source of the calling lane so the existing
  /// `matrix-livekit-session` / `matrix-livekit-backend` log shapes are
  /// preserved.
  static Future<bool> setDetached(
    lk.LocalTrackPublication publication, {
    required bool detached,
    required String reason,
    required String source,
  }) async {
    final action = detached ? 'detach' : 'reattach';
    final track = publication.track;
    if (track == null) {
      Log.w(
        'LiveKit Windows microphone sender $action skipped: '
        'reason=$reason missing_track=true',
        category: LogCategory.livekit,
        source: source,
      );
      return false;
    }

    final sender = track.sender;
    if (sender == null) {
      Log.w(
        'LiveKit Windows microphone sender $action skipped: '
        'reason=$reason missing_sender=true',
        category: LogCategory.livekit,
        source: source,
      );
      // With no sender there is nothing to move, but the muted metadata is
      // still the only thing remote participants can see, so keep it truthful
      // in BOTH directions. Correcting only the detach direction left the
      // reattach case stuck: unmuting while the sender was still absent kept
      // `publication.muted` true, and nothing else on this path ever cleared
      // it, so remote participants saw a muted microphone for the rest of the
      // call. This mirrors the already-attached branch below.
      if (detached != publication.muted) {
        // ignore: invalid_use_of_internal_member
        track.updateMuted(detached, shouldSendSignal: true);
      }
      return false;
    }

    final attachment = attachmentOf(publication);
    final alreadyDetached =
        attachment == LivekitMicrophoneSenderAttachment.detached;
    final alreadyAttached =
        attachment == LivekitMicrophoneSenderAttachment.attached;

    // The guard is on sender state, not on `publication.muted`. The whole
    // point of this class is that the two can disagree, and when they do the
    // sender is the one that decides whether audio actually flows.
    if (detached && alreadyDetached) {
      Log.d(
        'LiveKit Windows microphone sender detach skipped: '
        'reason=$reason already_detached=true '
        'publication_muted=${publication.muted}',
        category: LogCategory.livekit,
        source: source,
      );
      // Sender already correct; only the metadata may still be stale.
      if (!publication.muted) {
        // ignore: invalid_use_of_internal_member
        track.updateMuted(true, shouldSendSignal: true);
      }
      return false;
    }
    if (!detached && alreadyAttached) {
      Log.d(
        'LiveKit Windows microphone sender reattach skipped: '
        'reason=$reason already_attached=true '
        'publication_muted=${publication.muted}',
        category: LogCategory.livekit,
        source: source,
      );
      if (publication.muted) {
        // ignore: invalid_use_of_internal_member
        track.updateMuted(false, shouldSendSignal: true);
      }
      return false;
    }

    Log.i(
      'LiveKit Windows microphone sender $action starting: '
      'reason=$reason publication_muted=${publication.muted} '
      'sender_attachment=${attachment.name}',
      category: LogCategory.livekit,
      source: source,
    );
    try {
      if (detached) {
        await sender.replaceTrack(null);
      } else {
        await sender.replaceTrack(track.mediaStreamTrack);
      }
    } catch (error, stackTrace) {
      // The method reports success through its `bool` return, so an escaping
      // exception left the caller unable to tell "sender not moved" from
      // "threw", and surfaced on the call-control path as an unhandled error
      // rather than a visible mute failure. `updateMuted` below is skipped
      // deliberately: the sender did not move, so claiming the new mute state
      // in metadata would make the signal disagree with what actually flows.
      Log.onError(
        error,
        stackTrace,
        content:
            'Recovered LiveKit Windows microphone sender $action failure: '
            'reason=$reason',
        category: LogCategory.livekit,
        source: source,
      );
      return false;
    }
    // LiveKit's normal mute path toggles MediaStreamTrack.enabled on Windows,
    // which is the native boundary implicated by the submitted crash reports,
    // and its unpublish path removes/disposes native track state. Keep the
    // local track alive and only update the LiveKit metadata signal.
    // ignore: invalid_use_of_internal_member
    track.updateMuted(detached, shouldSendSignal: true);
    Log.i(
      'LiveKit Windows microphone sender $action completed: '
      'reason=$reason muted=$detached',
      category: LogCategory.livekit,
      source: source,
    );
    return true;
  }
}
