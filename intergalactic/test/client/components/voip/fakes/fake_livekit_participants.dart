// Deterministic stand-ins for `lk.LocalParticipant` and `lk.RemoteParticipant`.
//
// A room can hold several of each, and each participant can hold several
// publications of different kinds at once (microphone + camera + screen-share
// video + screen-share audio), which is what the session's per-participant
// reconciliation and the one-tile-per-user tile selection actually walk.

import 'package:collection/collection.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Remote participant holding an arbitrary set of remote publications.
class FakeRemoteParticipant implements lk.RemoteParticipant {
  FakeRemoteParticipant({
    required this.identity,
    String? sid,
    String? name,
    lk.ConnectionQuality connectionQuality = lk.ConnectionQuality.excellent,
    List<lk.RemoteTrackPublication> publications = const [],
    // Distinct prefix from FakeLocalParticipant. `operator ==` on both is
    // "any lk.Participant with the same sid", so a local and a remote fake
    // sharing an identity used to compare equal and collide in a Set or a Map
    // key - which is never true of the real SDK.
  }) : sid = sid ?? 'remote-sid-$identity',
       _name = name ?? identity,
       _connectionQuality = connectionQuality {
    for (final publication in publications) {
      trackPublications[publication.sid] = publication;
    }
  }

  @override
  final String identity;

  @override
  final String sid;

  final String _name;

  lk.ConnectionQuality _connectionQuality;

  @override
  final Map<String, lk.RemoteTrackPublication> trackPublications =
      <String, lk.RemoteTrackPublication>{};

  @override
  String get name => _name;

  @override
  lk.ConnectionQuality get connectionQuality => _connectionQuality;

  void setConnectionQuality(lk.ConnectionQuality value) =>
      _connectionQuality = value;

  void addPublication(lk.RemoteTrackPublication publication) =>
      trackPublications[publication.sid] = publication;

  void removePublication(String sid) => trackPublications.remove(sid);

  @override
  List<lk.RemoteTrackPublication<lk.RemoteAudioTrack>>
  get audioTrackPublications {
    _assertPublicationBucketsMatchKind();
    return trackPublications.values
        .whereType<lk.RemoteTrackPublication<lk.RemoteAudioTrack>>()
        .toList(growable: false);
  }

  @override
  List<lk.RemoteTrackPublication<lk.RemoteVideoTrack>>
  get videoTrackPublications {
    _assertPublicationBucketsMatchKind();
    return trackPublications.values
        .whereType<lk.RemoteTrackPublication<lk.RemoteVideoTrack>>()
        .toList(growable: false);
  }

  /// Fails loudly when a publication's `kind` disagrees with the bucket its
  /// Dart type ARGUMENT puts it in.
  ///
  /// `whereType` selects on the type argument, not on `kind`, so
  /// `FakeRemoteTrackPublication(sid: ..., kind: lk.TrackType.AUDIO)` written
  /// without an explicit type argument defaults to the bound
  /// (`lk.RemoteTrack`) and lands in NEITHER list. `isMuted`, `hasAudio` and
  /// `hasVideo` then answer from the empty-list defaults and the test passes
  /// for the wrong reason. The real SDK selects on `kind`, so a disagreement
  /// here is always a fixture bug and must not be silent.
  void _assertPublicationBucketsMatchKind() {
    for (final publication in trackPublications.values) {
      final expectedBucket = switch (publication.kind) {
        lk.TrackType.AUDIO => 'audioTrackPublications',
        lk.TrackType.VIDEO => 'videoTrackPublications',
        _ => null,
      };
      if (expectedBucket == null) {
        continue;
      }
      final classified = switch (publication.kind) {
        lk.TrackType.AUDIO =>
          publication is lk.RemoteTrackPublication<lk.RemoteAudioTrack>,
        _ => publication is lk.RemoteTrackPublication<lk.RemoteVideoTrack>,
      };
      if (!classified) {
        throw StateError(
          'FakeRemoteParticipant($identity): publication '
          '${publication.sid} declares kind=${publication.kind} but its Dart '
          'type argument keeps it out of $expectedBucket. Construct it with '
          'the matching type argument, e.g. '
          'FakeRemoteTrackPublication<lk.RemoteAudioTrack>(...).',
        );
      }
    }
  }

  @override
  List<lk.RemoteTrackPublication> get subscribedTracks => trackPublications
      .values
      .where((publication) => publication.subscribed)
      .toList(growable: false);

  @override
  bool get isMuted => audioTrackPublications.firstOrNull?.muted ?? true;

  @override
  bool get hasAudio => audioTrackPublications.isNotEmpty;

  @override
  bool get hasVideo => videoTrackPublications.isNotEmpty;

  @override
  lk.RemoteTrackPublication? getTrackPublicationBySource(
    lk.TrackSource source,
  ) {
    return trackPublications.values.firstWhereOrNull(
      (publication) => publication.source == source,
    );
  }

  @override
  lk.RemoteTrackPublication? getTrackPublicationByName(String name) {
    return trackPublications.values.firstWhereOrNull(
      (publication) => publication.name == name,
    );
  }

  @override
  bool isCameraEnabled() =>
      !(getTrackPublicationBySource(lk.TrackSource.camera)?.muted ?? true);

  @override
  bool isMicrophoneEnabled() =>
      !(getTrackPublicationBySource(lk.TrackSource.microphone)?.muted ?? true);

  @override
  bool isScreenShareEnabled() =>
      !(getTrackPublicationBySource(lk.TrackSource.screenShareVideo)?.muted ??
          true);

  @override
  bool isScreenShareAudioEnabled() =>
      !(getTrackPublicationBySource(lk.TrackSource.screenShareAudio)?.muted ??
          true);

  @override
  Future<bool> dispose() async => true;

  @override
  int get hashCode => sid.hashCode;

  @override
  bool operator ==(Object other) => other is lk.Participant && sid == other.sid;

  @override
  String toString() => 'FakeRemoteParticipant($identity)';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Local participant holding an arbitrary set of local publications.
class FakeLocalParticipant implements lk.LocalParticipant {
  FakeLocalParticipant({
    required this.identity,
    String? sid,
    String? name,
    lk.ConnectionQuality connectionQuality = lk.ConnectionQuality.excellent,
    List<lk.LocalTrackPublication> publications = const [],
    // See FakeRemoteParticipant: the two default prefixes must differ.
  }) : sid = sid ?? 'local-sid-$identity',
       _name = name ?? identity,
       _connectionQuality = connectionQuality {
    for (final publication in publications) {
      trackPublications[publication.sid] = publication;
    }
  }

  @override
  final String identity;

  @override
  final String sid;

  final String _name;

  lk.ConnectionQuality _connectionQuality;

  @override
  final Map<String, lk.LocalTrackPublication> trackPublications =
      <String, lk.LocalTrackPublication>{};

  @override
  String get name => _name;

  @override
  lk.ConnectionQuality get connectionQuality => _connectionQuality;

  void setConnectionQuality(lk.ConnectionQuality value) =>
      _connectionQuality = value;

  void addPublication(lk.LocalTrackPublication publication) =>
      trackPublications[publication.sid] = publication;

  void removePublication(String sid) => trackPublications.remove(sid);

  /// Answers [publishAudioTrack]. Left null by default so an unmodelled
  /// publish still fails loudly, per the barrel's rule.
  ///
  /// The handler owns the whole publish, including WHEN the publication
  /// becomes visible to [getTrackPublicationBySource]: the real
  /// `publishAudioTrack` calls `addTrackPublication` partway through
  /// (livekit_client-2.5.4 `participant/local.dart:187`) and then keeps
  /// awaiting `onPublish`, `applyAudioSpeakerSettings` and `track.start()`,
  /// so "publication registered, publish still running" is a reachable state
  /// and a test that wants it calls [addPublication] from inside the handler.
  Future<lk.LocalTrackPublication<lk.LocalAudioTrack>> Function(
    lk.LocalAudioTrack track,
  )?
  onPublishAudioTrack;

  /// Every `removePublishedTrack` sid in call order.
  final List<String> removePublishedTrackCalls = <String>[];

  /// When set, [removePublishedTrack] throws it AFTER recording the call, so
  /// a test can drive a rollback whose unpublish failed.
  Object? removePublishedTrackError;

  @override
  Future<lk.LocalTrackPublication<lk.LocalAudioTrack>> publishAudioTrack(
    lk.LocalAudioTrack track, {
    lk.AudioPublishOptions? publishOptions,
  }) {
    final handler = onPublishAudioTrack;
    if (handler == null) {
      throw UnimplementedError(
        'FakeLocalParticipant($identity).publishAudioTrack was called without '
        'onPublishAudioTrack being set.',
      );
    }
    return handler(track);
  }

  @override
  Future<void> removePublishedTrack(
    String trackSid, {
    bool notify = true,
  }) async {
    removePublishedTrackCalls.add(trackSid);
    final error = removePublishedTrackError;
    if (error != null) {
      throw error;
    }
    trackPublications.remove(trackSid);
  }

  @override
  List<lk.LocalTrackPublication<lk.LocalAudioTrack>>
  get audioTrackPublications => trackPublications.values
      .whereType<lk.LocalTrackPublication<lk.LocalAudioTrack>>()
      .toList(growable: false);

  @override
  List<lk.LocalTrackPublication<lk.LocalVideoTrack>>
  get videoTrackPublications => trackPublications.values
      .whereType<lk.LocalTrackPublication<lk.LocalVideoTrack>>()
      .toList(growable: false);

  /// Mirrors the real derivation, which is why `isMicrophoneMuted` on the
  /// session reads *publication* state and not the user's intent: it is
  /// `participant.isMuted` -> `audioTrackPublications.first.muted`.
  @override
  bool get isMuted => audioTrackPublications.firstOrNull?.muted ?? true;

  @override
  bool get hasAudio => audioTrackPublications.isNotEmpty;

  @override
  bool get hasVideo => videoTrackPublications.isNotEmpty;

  @override
  lk.LocalTrackPublication? getTrackPublicationBySource(lk.TrackSource source) {
    return trackPublications.values.firstWhereOrNull(
      (publication) => publication.source == source,
    );
  }

  @override
  lk.LocalTrackPublication? getTrackPublicationByName(String name) {
    return trackPublications.values.firstWhereOrNull(
      (publication) => publication.name == name,
    );
  }

  @override
  bool isCameraEnabled() =>
      !(getTrackPublicationBySource(lk.TrackSource.camera)?.muted ?? true);

  @override
  bool isMicrophoneEnabled() =>
      !(getTrackPublicationBySource(lk.TrackSource.microphone)?.muted ?? true);

  @override
  bool isScreenShareEnabled() =>
      !(getTrackPublicationBySource(lk.TrackSource.screenShareVideo)?.muted ??
          true);

  @override
  bool isScreenShareAudioEnabled() =>
      !(getTrackPublicationBySource(lk.TrackSource.screenShareAudio)?.muted ??
          true);

  @override
  Future<bool> dispose() async => true;

  @override
  int get hashCode => sid.hashCode;

  @override
  bool operator ==(Object other) => other is lk.Participant && sid == other.sid;

  @override
  String toString() => 'FakeLocalParticipant($identity)';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
