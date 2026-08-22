import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';

/// Process-lifetime home for per-participant playback volumes.
///
/// The overrides used to live on a per-`CallView` state object keyed partly on
/// `identityHashCode(session)`. That key is correct for transient view state -
/// which tiles are hidden, which screen shares have been revealed - because
/// those should not carry across a rejoin. It is wrong for volumes: leaving and
/// rejoining produces a fresh session object, so the map came back empty and
/// every per-participant volume the user had set was gone. Screen-share audio
/// volume already survived, because it persists to disk; microphone volume did
/// not, and the difference was never a stated decision. This closes the gap for
/// the lifetime of the process.
///
/// The key deliberately omits both the identity hash and the session id. It is
/// client + room, which is exactly the grain wanted here: the same room, from
/// the same account, restores the same volumes. Nothing in this store is keyed
/// on a session object, so a dead session is not retained.
///
/// Session id was tried and is wrong. It is spelled differently by the two
/// session types and only one of them is stable: `MatrixLivekitVoipSession`
/// gives `client_room_stateKey`, but `MatrixVoipSession` gives
/// `client_callId`, and the SDK generates a fresh `callId` per direct call -
/// so 1:1 calls silently kept re-keying and losing exactly the volumes this
/// store exists to preserve.
///
/// The per-user key inside [CallParticipantAudioOverrides] is unchanged and
/// must stay the Matrix user ID.
class CallParticipantAudioOverridesStore {
  CallParticipantAudioOverridesStore._();

  /// Bounded for the same reason the view-state map was: a long-lived client
  /// can visit many rooms. Volumes are small, so this is generous.
  static const int maxRetainedCalls = 24;

  static final Map<String, CallParticipantAudioOverrides> _byCall =
      <String, CallParticipantAudioOverrides>{};

  /// [sessionId] is optional and defaults to absent.
  ///
  /// [keyForSession] no longer supplies one - see the note there on why a
  /// session id is the wrong grain - but the parameter is kept so a caller with
  /// a genuinely stable identifier can still narrow the key, and so the
  /// existing key-shape tests keep exercising that branch.
  static String keyFor({
    required String clientIdentifier,
    required String roomId,
    String sessionId = '',
  }) {
    final trimmedSessionId = sessionId.trim();
    return '$clientIdentifier:$roomId:'
        '${trimmedSessionId.isEmpty ? 'no-session-id' : trimmedSessionId}';
  }

  /// Deliberately does NOT pass `session.sessionId`.
  ///
  /// The two session types spell `sessionId` differently and only one of them
  /// is stable across calls. `MatrixLivekitVoipSession` returns
  /// `client_room_stateKey`, which is stable per room and device;
  /// `MatrixVoipSession` returns `client_callId`, and `callId` is generated
  /// fresh by the SDK for every direct call. Keying on it meant a 1:1 call
  /// selected a new store entry each time, so the per-participant volumes a
  /// user set were gone on the next call to the same person - the exact defect
  /// this store was created to fix, still present on the direct-call path.
  ///
  /// Client + room is the grain the class doc claims and the grain that is
  /// actually wanted: same room, same device, same volumes. This is a
  /// process-lifetime in-memory store, so there is no second device to
  /// disambiguate.
  static String keyForSession(VoipSession session) {
    return keyFor(
      clientIdentifier: session.client.identifier,
      roomId: session.roomId,
    );
  }

  static CallParticipantAudioOverrides forSession(VoipSession session) {
    return forKey(keyForSession(session));
  }

  /// Eviction is FIFO by insertion order, not least-recently-used.
  ///
  /// Deliberate, and named here because it is not the obvious choice:
  /// `_byCall.keys.first` is the oldest INSERTED key, and this method is also
  /// reached from read paths, so a read does not renew an entry. The trade is
  /// that a long-idle call still ages out on schedule rather than being held
  /// alive by the diagnostics summary polling it; the cost is that a call read
  /// but never re-entered can be evicted while a newer, idler one survives.
  /// `evicts the oldest INSERTED call once the cap is reached` in
  /// `call_participant_audio_overrides_test.dart` pins this and will fail if
  /// someone converts it to LRU without deciding to.
  static CallParticipantAudioOverrides forKey(String key) {
    if (!_byCall.containsKey(key) && _byCall.length >= maxRetainedCalls) {
      _byCall.remove(_byCall.keys.first);
    }
    return _byCall.putIfAbsent(key, CallParticipantAudioOverrides.new);
  }

  static void reset() {
    _byCall.clear();
  }

  /// Whether [stream] is the participant microphone audio this store keys on.
  ///
  /// Lives next to the store rather than on each surface. `call_view.dart` and
  /// `call_stream_popout_panel.dart` each carried an identical private copy
  /// and both feed the same [CallParticipantAudioOverrides.remember] and
  /// [CallParticipantAudioOverrides.restore] calls, so a change to one copy
  /// would have made the popout and the call surface classify the same stream
  /// differently and the stored volume would silently stop matching.
  ///
  /// Non-LiveKit streams count as microphone audio: they have no screen-share
  /// concept, so the whole stream is the participant's voice.
  static bool isParticipantMicrophoneAudio(VoipStream stream) {
    return stream is! MatrixLivekitVoipStream || stream.isMicrophoneAudio;
  }
}

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
    final volumeMatches =
        (volumeTarget.localVolume - storedVolume).abs() < _volumeMatchTolerance;
    // Compare the current volume against the stored volume only. The previous
    // guard also required `volumeTarget.locallyMuted == (storedVolume == 0.0)`,
    // which derived an *expected mute* from the remembered number. A deafened
    // participant keeps its volume (deafen sets the mute bit, not the volume),
    // so a stream with a stored 1.10 that was just deafened reported
    // locallyMuted == true, failed that comparison, and got "restored" —
    // meaning restore fired precisely *because* the user had deafened. Since
    // `restore` runs from the call-tile build path, that re-opened the audio on
    // the very next frame. See BUG-282 (2026-08-02).
    if (volumeMatches) {
      return false;
    }

    try {
      // Preserving-mute write: this is a restore, not a user gesture, so it may
      // correct the volume but must never clear a mute it does not own.
      await volumeTarget.setLocalVolumePreservingMute(storedVolume);
      return true;
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      return false;
    }
  }
}
