// Deterministic stand-ins for the LiveKit `Track` hierarchy and the two
// flutter_webrtc objects a `Track` is built around.
//
// The point of these fakes is that `Track.muted` is a *separate* variable from
// `TrackPublication.muted` in the real SDK, and the two can legally disagree.
// `Track.updateMuted` is edge-triggered (`if (_muted == muted) return;`,
// livekit_client-2.5.4 `track/track.dart:203`) and only the resulting event
// writes `TrackPublication._metadataMuted`, so once they drift apart nothing
// pulls them back together. Reproducing that drift is the whole reason these
// fakes model mute at both levels independently.
//
// Use [FakeLiveKitTrack.setMuted] to force a track-level mute without going
// through the edge-triggered path, and [FakeLiveKitTrack.updateMuted] to
// exercise the edge-triggered path itself.

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

/// Minimal [rtc.MediaStreamTrack] with a stable id and a settable `enabled`.
///
/// `enabled` matters because the app's fallback path in
/// `MatrixLivekitVoipStream._applyLocalPlaybackVolume` calls
/// `track.enable()`/`track.disable()` when `Helper.setVolume` fails, which it
/// always does under test (no platform channel).
class FakeMediaStreamTrack implements rtc.MediaStreamTrack {
  FakeMediaStreamTrack({
    this.id = 'media-track',
    this.kind = 'audio',
    this.label = 'fake-media-track',
    bool enabled = true,
  }) : _enabled = enabled;

  @override
  final String? id;

  @override
  final String? kind;

  @override
  final String? label;

  bool _enabled;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) => _enabled = value;

  @override
  bool? get muted => null;

  @override
  Future<void> stop() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal [rtc.RTCRtpSender] with a settable track and a recording
/// `replaceTrack`.
///
/// This is the object the whole silent-mic defect turns on. The app mutes on
/// Windows with `sender.replaceTrack(null)`, which LiveKit never records, so
/// sender attachment is real state that no SDK field reflects. Modelling it
/// separately from `publication.muted` is what makes "publication says live,
/// sender carries nothing" expressible.
class FakeRtpSender implements rtc.RTCRtpSender {
  FakeRtpSender({rtc.MediaStreamTrack? track}) : _track = track;

  rtc.MediaStreamTrack? _track;

  /// Every `replaceTrack` argument in call order. `null` is a detach.
  final List<rtc.MediaStreamTrack?> replaceTrackCalls =
      <rtc.MediaStreamTrack?>[];

  int get detachCount =>
      replaceTrackCalls.where((track) => track == null).length;

  int get reattachCount =>
      replaceTrackCalls.where((track) => track != null).length;

  @override
  rtc.MediaStreamTrack? get track => _track;

  /// When set, [replaceTrack] throws it after recording the call, so tests
  /// can drive the sender gate's recovery branch (which must return false
  /// rather than let the error escape onto the call-control path).
  Object? replaceTrackError;

  @override
  Future<void> replaceTrack(rtc.MediaStreamTrack? track) async {
    replaceTrackCalls.add(track);
    final error = replaceTrackError;
    if (error != null) {
      throw error;
    }
    _track = track;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal [rtc.MediaStream]. Only `id`/`ownerTag` are read by the app (the
/// native picture-in-picture handoff in `MatrixLivekitVoipStream`).
class FakeMediaStream implements rtc.MediaStream {
  FakeMediaStream({this.id = 'media-stream', this.ownerTag = 'fake-owner'});

  @override
  final String id;

  @override
  final String ownerTag;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Shared state for every fake LiveKit track.
///
/// Subclasses attach the concrete LiveKit interface (`RemoteAudioTrack`,
/// `LocalAudioTrack`, ...). Members that are not modelled fall through to
/// [noSuchMethod] and throw, so an untested code path fails loudly instead of
/// silently reading a plausible default.
abstract class FakeLiveKitTrack {
  FakeLiveKitTrack({
    required this.kind,
    required this.source,
    String mediaTrackId = 'media-track',
    this.sid,
    bool muted = false,
    bool active = true,
  }) : _muted = muted,
       _active = active,
       mediaStreamTrack = FakeMediaStreamTrack(
         id: mediaTrackId,
         kind: kind == lk.TrackType.AUDIO ? 'audio' : 'video',
       ),
       mediaStream = FakeMediaStream(id: '$mediaTrackId-stream');

  final lk.TrackType kind;
  final lk.TrackSource source;

  final rtc.MediaStreamTrack mediaStreamTrack;
  final rtc.MediaStream mediaStream;

  String? sid;

  /// Real RTP sender state.
  ///
  /// In the SDK this is `transceiver?.sender` (`track/track.dart:61`) and is
  /// null until the track is negotiated, which is why the app must treat "no
  /// sender" as *undecidable* rather than as detached. Left null by default so
  /// tests that do not care about sender attachment keep the undecidable
  /// state.
  FakeRtpSender? _sender;

  rtc.RTCRtpSender? get sender => _sender;

  /// Attaches a sender already carrying this track's media - the state a
  /// healthy published microphone is in.
  FakeRtpSender attachSender() {
    final sender = FakeRtpSender(track: mediaStreamTrack);
    _sender = sender;
    return sender;
  }

  /// Attaches a sender carrying nothing - the state `replaceTrack(null)`
  /// leaves behind, and the one LiveKit has no field for.
  FakeRtpSender attachDetachedSender() {
    final sender = FakeRtpSender();
    _sender = sender;
    return sender;
  }

  bool _muted;
  bool _active;

  /// Every `updateMuted` argument in call order, including the ones the
  /// edge-trigger swallowed. A swallowed call is exactly the P0-4 mechanism:
  /// the app believes it published a mute, and no event was ever emitted.
  final List<bool> updateMutedCalls = <bool>[];

  /// Number of `updateMuted` calls that actually changed `muted` and would
  /// therefore have emitted `InternalTrackMuteUpdatedEvent` in the real SDK -
  /// the only thing that writes `TrackPublication.muted`.
  int mutedChangeNotifications = 0;

  /// Invoked when a real mute change would have propagated to a publication.
  /// Wire this to a [FakeRemoteTrackPublication]/[FakeLocalTrackPublication]
  /// when a test wants the two to stay in sync.
  void Function(bool muted)? onMutedChanged;

  bool get muted => _muted;

  bool get isActive => _active;

  /// Forces the track-level mute bit without going through the edge-triggered
  /// path, and without notifying anything. This is how a test reaches the
  /// P0-4 steady state: `track.muted == true` while `publication.muted` is
  /// still `false`.
  void setMuted(bool value) => _muted = value;

  void setActive(bool value) => _active = value;

  // `Track.updateMuted` is `@internal` in livekit_client; the app already
  // calls it directly with the same ignore.
  // ignore: invalid_use_of_internal_member
  void updateMuted(
    bool muted, {
    bool shouldNotify = true,
    bool shouldSendSignal = false,
  }) {
    updateMutedCalls.add(muted);
    if (_muted == muted) {
      // Real behaviour: `track.dart:203` early-returns here. No event, so a
      // publication rebuilt around this track keeps its stale `muted`.
      return;
    }
    _muted = muted;
    if (shouldNotify) {
      mutedChangeNotifications++;
      onMutedChanged?.call(muted);
    }
  }

  rtc.RTCRtpMediaType get mediaType => kind == lk.TrackType.VIDEO
      ? rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo
      : rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio;

  String getCid() => mediaStreamTrack.id ?? 'fake-cid';

  Future<bool> start() async {
    if (_active) return false;
    _active = true;
    return true;
  }

  Future<bool> stop() async {
    if (!_active) return false;
    _active = false;
    return true;
  }

  Future<void> enable() async {
    mediaStreamTrack.enabled = true;
  }

  Future<void> disable() async {
    mediaStreamTrack.enabled = false;
  }

  int disposeCount = 0;

  Future<bool> dispose() async {
    disposeCount++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Remote microphone / screen-share audio track.
///
/// `getReceiverStats()` is deliberately not modelled: its return type lives in
/// an unexported `livekit_client` source file, so it cannot be named here. The
/// call therefore routes to [noSuchMethod] and throws, which the session
/// already treats as "stats unavailable" (`_sampleRemoteAudioFlow` catches it
/// and records `packetsReceived: null`, which never counts as a stall).
class FakeRemoteAudioTrack extends FakeLiveKitTrack
    implements lk.RemoteAudioTrack {
  FakeRemoteAudioTrack({
    super.mediaTrackId = 'remote-audio-track',
    super.sid,
    super.muted,
    super.active,
    lk.TrackSource source = lk.TrackSource.microphone,
  }) : super(kind: lk.TrackType.AUDIO, source: source);
}

/// Remote camera / screen-share video track.
class FakeRemoteVideoTrack extends FakeLiveKitTrack
    implements lk.RemoteVideoTrack {
  FakeRemoteVideoTrack({
    super.mediaTrackId = 'remote-video-track',
    super.sid,
    super.muted,
    super.active,
    lk.TrackSource source = lk.TrackSource.camera,
  }) : super(kind: lk.TrackType.VIDEO, source: source);
}

/// Local microphone track. This is the one that carries the P0-4 defect:
/// the Windows mute path hand-writes the flag onto the track with
/// `updateMuted`, never through the publication.
class FakeLocalAudioTrack extends FakeLiveKitTrack
    implements lk.LocalAudioTrack {
  FakeLocalAudioTrack({
    super.mediaTrackId = 'local-audio-track',
    super.sid,
    super.muted,
    super.active,
    lk.TrackSource source = lk.TrackSource.microphone,
  }) : super(kind: lk.TrackType.AUDIO, source: source);
}

/// Local camera / screen-share video track.
class FakeLocalVideoTrack extends FakeLiveKitTrack
    implements lk.LocalVideoTrack {
  FakeLocalVideoTrack({
    super.mediaTrackId = 'local-video-track',
    super.sid,
    super.muted,
    super.active,
    lk.TrackSource source = lk.TrackSource.camera,
  }) : super(kind: lk.TrackType.VIDEO, source: source);
}
