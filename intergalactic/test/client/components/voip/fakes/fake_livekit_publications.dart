// Deterministic stand-ins for `lk.TrackPublication` and its two subclasses.
//
// The one publication fake that existed before this library
// (`matrix_livekit_voip_stream_lifecycle_test.dart`) returned constant
// `track => null`, `subscribed => false`, `muted => false`. That made
// subscribe -> unsubscribe -> resubscribe unrepresentable, and forced
// `audioSinkAttached` (computed as `publication.track is lk.AudioTrack`) to be
// permanently false, so the entire remote-audio reconciliation policy could
// only ever be exercised in one state.
//
// Here `muted`, `subscribed` and `track` are three independent, settable bits:
//
// * `muted` - the publication's own `_metadataMuted`, which in the real SDK is
//   written only by a track mute *event*, never by the app.
// * `track` - the attached media, i.e. `audioSinkAttached`.
// * `subscribed` - defaults to the real derivation
//   (`subscriptionAllowed && track != null`) but can be overridden outright
//   with [setSubscribed], which is how "subscribed at the control plane but no
//   sink attached" gets expressed.

import 'package:livekit_client/livekit_client.dart' as lk;

import 'fake_livekit_tracks.dart';

/// Operations a test can assert were requested on a publication.
class FakePublicationOperations {
  final List<String> calls = <String>[];

  int get subscribeCount => calls.where((c) => c == 'subscribe').length;
  int get unsubscribeCount => calls.where((c) => c == 'unsubscribe').length;
  int get enableCount => calls.where((c) => c == 'enable').length;
  int get disableCount => calls.where((c) => c == 'disable').length;

  void record(String call) => calls.add(call);

  void clear() => calls.clear();
}

String _defaultPublicationName(lk.TrackSource source) {
  switch (source) {
    case lk.TrackSource.microphone:
      return 'microphone';
    case lk.TrackSource.camera:
      return 'camera';
    case lk.TrackSource.screenShareVideo:
      return 'screenShareVideo';
    case lk.TrackSource.screenShareAudio:
      return 'screenShareAudio';
    case lk.TrackSource.unknown:
      return 'unknown';
  }
}

/// A remote publication with independently settable `muted`, `subscribed` and
/// `track`.
class FakeRemoteTrackPublication<T extends lk.RemoteTrack>
    implements lk.RemoteTrackPublication<T> {
  FakeRemoteTrackPublication({
    required this.sid,
    required this.kind,
    this.source = lk.TrackSource.microphone,
    String? name,
    T? track,
    bool muted = false,
    bool? subscribed,
    bool subscriptionAllowed = true,
    bool enabled = true,
    this.dimensions,
    this.simulcasted = false,
    this.mimeType = 'audio/opus',
    this.propagateTrackMute = true,
    this.trackAttachedOnSubscribe,
    this.onSubscribe,
  }) : name = name ?? _defaultPublicationName(source),
       _track = track,
       _muted = muted,
       _subscribedOverride = subscribed,
       _subscriptionAllowed = subscriptionAllowed,
       _enabled = enabled {
    _bindTrackMuteUpdates(_track);
  }

  /// Convenience constructor for the common remote-microphone case.
  factory FakeRemoteTrackPublication.microphone({
    required String sid,
    T? track,
    bool muted = false,
    bool? subscribed,
    bool propagateTrackMute = true,
    T? trackAttachedOnSubscribe,
  }) {
    return FakeRemoteTrackPublication<T>(
      sid: sid,
      kind: lk.TrackType.AUDIO,
      track: track,
      muted: muted,
      subscribed: subscribed,
      propagateTrackMute: propagateTrackMute,
      trackAttachedOnSubscribe: trackAttachedOnSubscribe,
    );
  }

  @override
  final String sid;

  @override
  final String name;

  @override
  final lk.TrackType kind;

  @override
  final lk.TrackSource source;

  @override
  final lk.VideoDimensions? dimensions;

  @override
  final bool simulcasted;

  @override
  final String mimeType;

  /// When true, a track-level mute change that actually fires (i.e. one the
  /// edge-trigger did not swallow) writes this publication's `muted`, the way
  /// the SDK's internal track listener does. Set false to model a publication
  /// rebuilt around an already-muted track by `rePublishAllTracks`.
  final bool propagateTrackMute;

  /// Track attached when [subscribe] is called. Null - the default - models
  /// the real SDK, where `subscribe()` only sends a request and the media
  /// arrives later as a separate `TrackSubscribedEvent`.
  final T? trackAttachedOnSubscribe;

  /// Runs inside `subscribe()`, before the track is attached. Models what the
  /// room can do to this publication WHILE a repair is awaiting it - an
  /// unpublish landing mid-repair, above all (BUG-321).
  final Future<void> Function()? onSubscribe;

  final FakePublicationOperations operations = FakePublicationOperations();

  T? _track;
  bool _muted;
  bool? _subscribedOverride;
  bool _subscriptionAllowed;
  bool _enabled;
  lk.VideoQuality _videoQuality = lk.VideoQuality.HIGH;
  lk.StreamState _streamState = lk.StreamState.active;

  @override
  T? get track => _track;

  @override
  bool get muted => _muted;

  @override
  bool get subscribed =>
      _subscribedOverride ?? (_subscriptionAllowed && _track != null);

  @override
  bool get subscriptionAllowed => _subscriptionAllowed;

  @override
  bool get enabled => _enabled;

  @override
  lk.VideoQuality get videoQuality => _videoQuality;

  @override
  lk.StreamState get streamState => _streamState;

  @override
  bool get isScreenShare =>
      kind == lk.TrackType.VIDEO && source == lk.TrackSource.screenShareVideo;

  @override
  lk.TrackSubscriptionState get subscriptionState {
    if (!_subscriptionAllowed) return lk.TrackSubscriptionState.notAllowed;
    return subscribed
        ? lk.TrackSubscriptionState.subscribed
        : lk.TrackSubscriptionState.unsubscribed;
  }

  /// Sets the publication-level mute bit. Independent of `track.muted` on
  /// purpose - see P0-4.
  void setMuted(bool value) => _muted = value;

  /// Attaches or detaches the media sink.
  void setTrack(T? value) {
    _unbindTrackMuteUpdates(_track);
    _track = value;
    _bindTrackMuteUpdates(value);
  }

  /// Overrides the derived `subscribed`. Pass null to go back to the real
  /// derivation (`subscriptionAllowed && track != null`).
  void setSubscribed(bool? value) => _subscribedOverride = value;

  void setSubscriptionAllowed(bool value) => _subscriptionAllowed = value;

  void setStreamState(lk.StreamState value) => _streamState = value;

  void _bindTrackMuteUpdates(T? value) {
    if (!propagateTrackMute) return;
    // Promote through Object? rather than testing `value` directly: `value` is
    // typed by the publication's track type variable, and FakeLiveKitTrack is
    // not provably a subtype of it, so the analyser refuses to promote and
    // resolves `onMutedChanged` against the SDK type instead.
    final Object? track = value;
    if (track is FakeLiveKitTrack) {
      track.onMutedChanged = setMuted;
    }
  }

  /// Releases the previous track's callback before a new one is bound.
  ///
  /// Without this, `setTrack(null)` from `unsubscribe()` left the detached
  /// track still writing THIS publication's `muted` on any later
  /// `updateMuted`, and one track attached to two publications silently
  /// stopped updating the first. The remote-audio reconciliation tests read
  /// `publication.muted` together with `publication.track`, so a stale write
  /// changes what they observe.
  void _unbindTrackMuteUpdates(T? value) {
    if (!propagateTrackMute) return;
    final Object? track = value;
    // `==`, not `identical`: Dart guarantees instance-method tear-offs of the
    // same method on the same object compare equal, not that they are the same
    // object. Comparing at all matters - if the track was rebound to another
    // publication, that publication owns the callback now.
    if (track is FakeLiveKitTrack && track.onMutedChanged == setMuted) {
      track.onMutedChanged = null;
    }
  }

  @override
  Future<void> subscribe() async {
    operations.record('subscribe');
    // Deliberately does NOT grant itself permission. The real
    // `subscribe()` (`publication/remote.dart:254-260`) early-returns when
    // `!_subscriptionAllowed` and never writes that field; its only writer is
    // the server-driven `updateSubscriptionAllowed` at `:312-313`. A fake that
    // set it here would let "subscribe() recovers from a server denial" pass in
    // tests and fail in production. Use `setSubscriptionAllowed(true)` to model
    // the server changing its mind.
    if (!_subscriptionAllowed) {
      return;
    }
    await onSubscribe?.call();
    final attach = trackAttachedOnSubscribe;
    if (attach != null) {
      setTrack(attach);
    }
  }

  @override
  Future<void> unsubscribe() async {
    operations.record('unsubscribe');
    // Mirrors the SDK's guard at `publication/remote.dart:262-265`.
    if (!_subscriptionAllowed) {
      return;
    }
    setTrack(null);
    _subscribedOverride = null;
  }

  @override
  Future<void> enable() async {
    operations.record('enable');
    _enabled = true;
  }

  @override
  Future<void> disable() async {
    operations.record('disable');
    _enabled = false;
  }

  @override
  Future<void> setVideoQuality(lk.VideoQuality newValue) async {
    operations.record('setVideoQuality:${newValue.name}');
    _videoQuality = newValue;
  }

  @override
  Future<bool> dispose() async => true;

  @override
  int get hashCode => sid.hashCode;

  @override
  bool operator ==(Object other) =>
      other is lk.TrackPublication && sid == other.sid;

  @override
  String toString() => 'FakeRemoteTrackPublication($sid, $kind, $source)';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A local publication with independently settable `muted` and `track`.
class FakeLocalTrackPublication<T extends lk.LocalTrack>
    implements lk.LocalTrackPublication<T> {
  FakeLocalTrackPublication({
    required this.sid,
    required this.kind,
    this.source = lk.TrackSource.microphone,
    String? name,
    T? track,
    bool muted = false,
    bool? subscribed,
    this.dimensions,
    this.simulcasted = false,
    this.mimeType = 'audio/opus',
    this.propagateTrackMute = true,
  }) : name = name ?? _defaultPublicationName(source),
       _track = track,
       _muted = muted,
       _subscribedOverride = subscribed {
    _bindTrackMuteUpdates(_track);
  }

  @override
  final String sid;

  @override
  final String name;

  @override
  final lk.TrackType kind;

  @override
  final lk.TrackSource source;

  @override
  final lk.VideoDimensions? dimensions;

  @override
  final bool simulcasted;

  @override
  final String mimeType;

  final bool propagateTrackMute;

  final FakePublicationOperations operations = FakePublicationOperations();

  T? _track;
  bool _muted;
  bool? _subscribedOverride;

  @override
  T? get track => _track;

  @override
  bool get muted => _muted;

  @override
  bool get subscribed => _subscribedOverride ?? (_track != null);

  @override
  bool get isScreenShare =>
      kind == lk.TrackType.VIDEO && source == lk.TrackSource.screenShareVideo;

  /// Sets the publication-level mute bit without touching `track.muted`.
  ///
  /// The P0-4 steady state is reached by leaving this `false` while the
  /// attached track reports `muted == true`.
  void setMuted(bool value) => _muted = value;

  void setTrack(T? value) {
    _unbindTrackMuteUpdates(_track);
    _track = value;
    _bindTrackMuteUpdates(value);
  }

  void setSubscribed(bool? value) => _subscribedOverride = value;

  void _bindTrackMuteUpdates(T? value) {
    if (!propagateTrackMute) return;
    // Promote through Object? rather than testing `value` directly: `value` is
    // typed by the publication's track type variable, and FakeLiveKitTrack is
    // not provably a subtype of it, so the analyser refuses to promote and
    // resolves `onMutedChanged` against the SDK type instead.
    final Object? track = value;
    if (track is FakeLiveKitTrack) {
      track.onMutedChanged = setMuted;
    }
  }

  /// Releases the previous track's callback before a new one is bound.
  ///
  /// Without this, `setTrack(null)` from `unsubscribe()` left the detached
  /// track still writing THIS publication's `muted` on any later
  /// `updateMuted`, and one track attached to two publications silently
  /// stopped updating the first. The remote-audio reconciliation tests read
  /// `publication.muted` together with `publication.track`, so a stale write
  /// changes what they observe.
  void _unbindTrackMuteUpdates(T? value) {
    if (!propagateTrackMute) return;
    final Object? track = value;
    // `==`, not `identical`: Dart guarantees instance-method tear-offs of the
    // same method on the same object compare equal, not that they are the same
    // object. Comparing at all matters - if the track was rebound to another
    // publication, that publication owns the callback now.
    if (track is FakeLiveKitTrack && track.onMutedChanged == setMuted) {
      track.onMutedChanged = null;
    }
  }

  @override
  Future<void> mute({bool stopOnMute = true}) async {
    operations.record('mute');
    _muted = true;
  }

  @override
  Future<void> unmute({bool stopOnMute = true}) async {
    operations.record('unmute');
    _muted = false;
  }

  @override
  Future<bool> dispose() async => true;

  @override
  int get hashCode => sid.hashCode;

  @override
  bool operator ==(Object other) =>
      other is lk.TrackPublication && sid == other.sid;

  @override
  String toString() => 'FakeLocalTrackPublication($sid, $kind, $source)';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
