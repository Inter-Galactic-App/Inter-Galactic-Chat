import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

class CallStreamBugReportDiagnostics {
  CallStreamBugReportDiagnostics(
    CallManager callManager, {
    DateTime Function()? clock,
  }) : this.fromSources(
         sessions: () => callManager.currentSessions,
         isDeafened: () => callManager.isDeafened,
         clock: clock,
       );

  CallStreamBugReportDiagnostics.fromSources({
    required Iterable<VoipSession> Function() sessions,
    required bool Function() isDeafened,
    DateTime Function()? clock,
  }) : _sessions = sessions,
       _isDeafened = isDeafened,
       _clock = clock ?? DateTime.now;

  static const int _maxSessions = 4;
  static const int _maxTracksPerSession = 16;
  static const int _maxParticipantsPerSession = 16;

  final Iterable<VoipSession> Function() _sessions;
  final bool Function() _isDeafened;
  final DateTime Function() _clock;

  Future<BugReportFeatureDiagnostics?> collect(BugReportInput input) async {
    if (!input.requestsCallStreamDiagnostics) {
      return null;
    }

    final collectedAt = _clock().toUtc();
    final allSessions = List<VoipSession>.of(_sessions());
    final activeSessions = allSessions
        .take(_maxSessions)
        .toList(growable: false);
    final sessionEntries = <Map<String, Object?>>[];
    for (var index = 0; index < activeSessions.length; index++) {
      sessionEntries.add(
        _sessionEntry(
          activeSessions[index],
          index: index,
          collectedAt: collectedAt,
        ),
      );
    }

    final totalSessionCount = allSessions.length;
    final deafened = _isDeafened();
    final category = input.category?.id;
    final data = <String, Object?>{
      'collected_at': collectedAt.toIso8601String(),
      'status': totalSessionCount == 0 ? 'no_active_call' : 'active_call',
      'requested_category': category ?? input.template.tag,
      'active_session_count': totalSessionCount,
      'deafened': deafened,
      'sessions': sessionEntries,
      if (totalSessionCount > sessionEntries.length)
        'sessions_omitted_count': totalSessionCount - sessionEntries.length,
      'privacy': const {
        'identifiers_omitted': true,
        'media_capture_included': false,
      },
    };

    final states = sessionEntries
        .map((entry) => entry['state'])
        .whereType<String>()
        .join(',');
    final logSummary =
        'scope=call_stream category=${category ?? input.template.tag} '
        'active_sessions=$totalSessionCount '
        'states=${states.isEmpty ? 'none' : states} '
        'deafened=$deafened';

    return BugReportFeatureDiagnostics(
      scope: 'call_stream',
      data: data,
      logSummary: logSummary,
    );
  }

  Map<String, Object?> _sessionEntry(
    VoipSession session, {
    required int index,
    required DateTime collectedAt,
  }) {
    try {
      final diagnostics = session.diagnosticsSnapshot;
      return {
        'session_index': index + 1,
        'implementation': session.runtimeType.toString(),
        'state': session.state.name,
        'microphone_muted': session.isMicrophoneMuted,
        'camera_enabled': session.isCameraEnabled,
        'screen_sharing': session.isSharingScreen,
        'screen_share_supported': session.supportsScreenshare,
        'stream_summary': _streamSummary(session.streams),
        'diagnostics': _diagnosticsEntry(diagnostics, collectedAt),
      };
    } catch (error) {
      return {
        'session_index': index + 1,
        'snapshot_status': 'unavailable',
        'error_type': error.runtimeType.toString(),
      };
    }
  }

  Map<String, Object?> _streamSummary(List<VoipStream> streams) {
    final byType = <String, int>{};
    final byDirection = <String, int>{};
    var mutedCount = 0;
    for (final stream in streams) {
      byType.update(stream.type.name, (count) => count + 1, ifAbsent: () => 1);
      byDirection.update(
        stream.direction.name,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (stream.isMuted) {
        mutedCount++;
      }
    }
    return {
      'total': streams.length,
      'by_type': byType,
      'by_direction': byDirection,
      'muted_count': mutedCount,
    };
  }

  Map<String, Object?> _diagnosticsEntry(
    VoipCallDiagnosticsSnapshot snapshot,
    DateTime collectedAt,
  ) {
    final tracks = snapshot.tracks.take(_maxTracksPerSession).toList();
    final trackEntries = <Map<String, Object?>>[];
    for (var index = 0; index < tracks.length; index++) {
      trackEntries.add(_trackEntry(tracks[index], index));
    }

    final snapshotAgeMs = collectedAt
        .difference(snapshot.collectedAt.toUtc())
        .inMilliseconds;
    return {
      'snapshot_collected_at': snapshot.collectedAt.toUtc().toIso8601String(),
      'snapshot_age_ms': snapshotAgeMs < 0 ? 0 : snapshotAgeMs,
      'participant_count': snapshot.participants.length,
      'track_count': snapshot.tracks.length,
      'screen_share_profile': snapshot.screenShareProfileLabel,
      if (snapshot.screenShareProfileDetails != null)
        'screen_share_profile_details': snapshot.screenShareProfileDetails,
      'adaptive_stream_enabled': snapshot.adaptiveStreamEnabled,
      'dynacast_enabled': snapshot.dynacastEnabled,
      'screen_share_simulcast_enabled': snapshot.screenShareSimulcastEnabled,
      'adaptive_fallback_enabled': snapshot.adaptiveFallbackEnabled,
      if (snapshot.adaptiveFallbackReason != null)
        'adaptive_fallback_reason': snapshot.adaptiveFallbackReason,
      if (snapshot.iceTransportSummary != null)
        'ice_transport_summary': snapshot.iceTransportSummary,
      'call_health': _callHealthEntry(snapshot),
      if (snapshot.shareSessionDiagnostics != null)
        'share_session': _shareSessionEntry(snapshot),
      'tracks': trackEntries,
      if (snapshot.tracks.length > trackEntries.length)
        'tracks_omitted_count': snapshot.tracks.length - trackEntries.length,
    };
  }

  Map<String, Object?> _callHealthEntry(VoipCallDiagnosticsSnapshot snapshot) {
    final health = snapshot.callHealth;
    // Sessions and tracks are already capped. Participants were not, so a large
    // call could push feature_diagnostics past the payload limit -- and the
    // service drops the ENTIRE diagnostics map when that happens, losing every
    // diagnostic in exactly the busy-call case this collector exists for.
    final totalParticipants = health.participants.length;
    final listedParticipants = health.participants
        .take(_maxParticipantsPerSession)
        .toList();
    final participants = <Map<String, Object?>>[];
    for (var index = 0; index < listedParticipants.length; index++) {
      final participant = listedParticipants[index];
      participants.add({
        'participant_index': index + 1,
        'role': participant.isLocal ? 'local' : 'remote',
        'connection_quality': participant.connectionQuality.name,
        'issue_codes': participant.issueCodes,
        'audio': {
          'expected': participant.hasExpectedMicrophoneAudio,
          'publication_exists': participant.audioPublicationExists,
          'publication_muted': participant.audioPublicationMuted,
          'track_subscribed': participant.audioTrackSubscribed,
          'sink_attached': participant.audioSinkAttached,
          'effective_volume': participant.effectiveVolume,
          'locally_muted': participant.locallyMuted,
          'user_muted': participant.userMuted,
          'audible': participant.remoteAudioAudible,
          'reason': participant.remoteAudioReason,
        },
      });
    }
    return {
      'collected_at': health.collectedAt?.toUtc().toIso8601String(),
      'lifecycle': health.lifecycle.name,
      'state': health.state.name,
      'issue_codes': health.issueCodes,
      'participants': participants,
      if (totalParticipants > participants.length)
        'participants_omitted_count': totalParticipants - participants.length,
    };
  }

  Map<String, Object?> _shareSessionEntry(
    VoipCallDiagnosticsSnapshot snapshot,
  ) {
    final share = snapshot.shareSessionDiagnostics!;
    return {
      'source_type': share.sourceType.name,
      'audio_requested': share.audioRequested,
      'audio_mode': share.audioMode.name,
      'audio_state': share.audioState.name,
      'audio_reason': share.audioReason,
      'lifecycle': share.lifecycle?.name,
    };
  }

  Map<String, Object?> _trackEntry(VoipTrackDiagnostics track, int index) {
    return {
      'track_index': index + 1,
      'type': track.type.name,
      'direction': track.direction.name,
      'receive_priority': track.receivePriority?.name,
      'requested_width': track.requestedWidth,
      'requested_height': track.requestedHeight,
      'requested_fps': track.requestedFps,
      'requested_bitrate_bps': track.requestedBitrateBps,
      'pre_encode_width': track.preEncodeWidth,
      'pre_encode_height': track.preEncodeHeight,
      'width': track.width,
      'height': track.height,
      'capture_fps': track.captureFps,
      'encode_fps': track.encodeFps,
      'send_fps': track.sendFps,
      'decode_fps': track.decodeFps,
      'render_fps': track.renderFps,
      'bitrate_bps': track.bitrateBps,
      'target_bitrate_bps': track.targetBitrateBps,
      'available_outgoing_bitrate_bps': track.availableOutgoingBitrateBps,
      'available_incoming_bitrate_bps': track.availableIncomingBitrateBps,
      'packets_lost': track.packetsLost,
      'packets_sent': track.packetsSent,
      'packets_received': track.packetsReceived,
      'packet_loss_percent': track.packetLossPercent,
      'jitter_ms': track.jitterMs,
      'round_trip_time_ms': track.roundTripTimeMs,
      'codec': track.codec,
      'quality_limitation_reason': track.qualityLimitationReason,
      'frames_captured': track.framesCaptured,
      'frames_encoded': track.framesEncoded,
      'frames_received': track.framesReceived,
      'frames_decoded': track.framesDecoded,
      'frames_rendered': track.framesRendered,
      'frames_dropped': track.framesDropped,
      'freeze_count': track.freezeCount,
      'pause_count': track.pauseCount,
      'encoder_implementation': track.encoderImplementation,
      'decoder_implementation': track.decoderImplementation,
      'hardware_encode_active': track.hardwareEncodeActive,
      'remote_audio_audible': track.remoteAudioAudible,
      'remote_audio_repair_action': track.remoteAudioRepairAction?.name,
      'remote_audio_reason': track.remoteAudioReason,
    };
  }
}
