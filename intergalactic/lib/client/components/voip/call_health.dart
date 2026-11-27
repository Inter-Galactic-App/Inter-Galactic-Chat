import 'dart:async';

import 'package:intergalactic/client/components/voip/voip_remote_audio_reconciliation.dart';

enum CallConnectionLifecycle {
  unknown,
  connecting,
  connected,
  reconnecting,
  disconnected,
  ended,
}

enum CallConnectionQuality { unknown, excellent, good, fair, poor, lost }

enum CallConnectionHealthState {
  unknown,
  good,
  fair,
  poor,
  connecting,
  reconnecting,
  disconnected,
  appIssueSuspected,
}

class CallHealthIssueCodes {
  const CallHealthIssueCodes._();

  static const callConnecting = 'call_connecting';
  static const roomReconnecting = 'room_reconnecting';
  static const roomDisconnected = 'room_disconnected';
  static const localConnectionFair = 'local_connection_fair';
  static const localConnectionPoor = 'local_connection_poor';
  static const localConnectionLost = 'local_connection_lost';
  static const remoteConnectionFair = 'remote_connection_fair';
  static const remoteConnectionPoor = 'remote_connection_poor';
  static const remoteConnectionLost = 'remote_connection_lost';
  static const remoteAudioPublicationMissing =
      'remote_audio_publication_missing';
  static const remoteAudioPublicationMuted = 'remote_audio_publication_muted';
  static const remoteAudioUnsubscribed = 'remote_audio_unsubscribed';
  static const remoteAudioSinkMissing = 'remote_audio_sink_missing';
  static const remoteAudioLocallyMuted = 'remote_audio_locally_muted';
  static const remoteAudioVolumeZero = 'remote_audio_volume_zero';
  static const localPlaybackMuteDrift =
      VoipRemoteAudioReasons.localPlaybackMuteDrift;
  static const muteStateMismatch = 'mute_state_mismatch';

  static const Set<String> appIssueCodes = {
    remoteAudioPublicationMissing,
    remoteAudioUnsubscribed,
    remoteAudioSinkMissing,
    localPlaybackMuteDrift,
    muteStateMismatch,
  };
}

extension CallConnectionHealthStateLabels on CallConnectionHealthState {
  String get summaryLabel {
    return switch (this) {
      CallConnectionHealthState.good => 'Strong connection',
      CallConnectionHealthState.fair => 'Call slightly unstable',
      CallConnectionHealthState.poor => 'Someone has a poor connection',
      CallConnectionHealthState.connecting => 'Connecting...',
      CallConnectionHealthState.reconnecting => 'Reconnecting...',
      CallConnectionHealthState.disconnected => 'Call disconnected',
      CallConnectionHealthState.appIssueSuspected => 'Audio issue detected',
      CallConnectionHealthState.unknown => 'Call status unknown',
    };
  }
}

extension CallConnectionQualityLabels on CallConnectionQuality {
  String get label {
    return switch (this) {
      CallConnectionQuality.excellent => 'Excellent',
      CallConnectionQuality.good => 'Good',
      CallConnectionQuality.fair => 'Fair',
      CallConnectionQuality.poor => 'Poor',
      CallConnectionQuality.lost => 'Lost',
      CallConnectionQuality.unknown => 'Unknown',
    };
  }

  bool get isGood =>
      this == CallConnectionQuality.good ||
      this == CallConnectionQuality.excellent;

  bool get isFair => this == CallConnectionQuality.fair;

  bool get isPoor =>
      this == CallConnectionQuality.poor || this == CallConnectionQuality.lost;

  int get signalStrengthBars {
    return switch (this) {
      CallConnectionQuality.excellent => 4,
      CallConnectionQuality.good => 3,
      CallConnectionQuality.fair => 2,
      CallConnectionQuality.poor => 1,
      CallConnectionQuality.lost || CallConnectionQuality.unknown => 0,
    };
  }
}

class CallHealthParticipantSnapshot {
  const CallHealthParticipantSnapshot({
    required this.sanitizedId,
    required this.label,
    required this.isLocal,
    this.userId,
    this.connectionQuality = CallConnectionQuality.unknown,
    this.hasExpectedMicrophoneAudio = false,
    this.audioPublicationExists = false,
    this.audioPublicationMuted = false,
    this.audioTrackSubscribed = false,
    this.audioSinkAttached = false,
    this.effectiveVolume,
    this.locallyMuted = false,
    this.userMuted = false,
    this.muteStateMismatch = false,
    this.remoteAudioAudible,
    this.remoteAudioReason,
  });

  final String sanitizedId;
  final String label;
  final bool isLocal;

  /// Raw Matrix user ID for in-memory UI matching. Do not serialize.
  final String? userId;
  final CallConnectionQuality connectionQuality;
  final bool hasExpectedMicrophoneAudio;
  final bool audioPublicationExists;
  final bool audioPublicationMuted;
  final bool audioTrackSubscribed;
  final bool audioSinkAttached;
  final double? effectiveVolume;
  final bool locallyMuted;
  final bool userMuted;
  final bool muteStateMismatch;
  final bool? remoteAudioAudible;
  final String? remoteAudioReason;

  bool get hasVolumeOverride =>
      userMuted || (effectiveVolume != null && effectiveVolume != 1.0);

  bool get hasAppAudioIssue {
    return issueCodes.any(CallHealthIssueCodes.appIssueCodes.contains);
  }

  List<String> get issueCodes {
    final issues = <String>{};
    switch (connectionQuality) {
      case CallConnectionQuality.lost:
        issues.add(
          isLocal
              ? CallHealthIssueCodes.localConnectionLost
              : CallHealthIssueCodes.remoteConnectionLost,
        );
        break;
      case CallConnectionQuality.poor:
        issues.add(
          isLocal
              ? CallHealthIssueCodes.localConnectionPoor
              : CallHealthIssueCodes.remoteConnectionPoor,
        );
        break;
      case CallConnectionQuality.fair:
        issues.add(
          isLocal
              ? CallHealthIssueCodes.localConnectionFair
              : CallHealthIssueCodes.remoteConnectionFair,
        );
        break;
      case CallConnectionQuality.unknown:
      case CallConnectionQuality.good:
      case CallConnectionQuality.excellent:
        break;
    }

    if (muteStateMismatch) {
      issues.add(CallHealthIssueCodes.muteStateMismatch);
    }

    if (hasExpectedMicrophoneAudio) {
      if (!audioPublicationExists) {
        issues.add(CallHealthIssueCodes.remoteAudioPublicationMissing);
      } else if (audioPublicationMuted) {
        issues.add(CallHealthIssueCodes.remoteAudioPublicationMuted);
      } else {
        if (!audioTrackSubscribed) {
          issues.add(CallHealthIssueCodes.remoteAudioUnsubscribed);
        }
        if (!audioSinkAttached) {
          issues.add(CallHealthIssueCodes.remoteAudioSinkMissing);
        }
        if (userMuted || locallyMuted) {
          issues.add(CallHealthIssueCodes.remoteAudioLocallyMuted);
        }
        if (effectiveVolume != null && effectiveVolume! <= 0) {
          issues.add(CallHealthIssueCodes.remoteAudioVolumeZero);
        }
        if (remoteAudioReason ==
            VoipRemoteAudioReasons.localPlaybackMuteDrift) {
          issues.add(CallHealthIssueCodes.localPlaybackMuteDrift);
        }
      }
    }

    return List.unmodifiable(issues);
  }

  String get connectionStatusLabel {
    if (connectionQuality == CallConnectionQuality.unknown) {
      return 'Connection unknown';
    }
    return '${connectionQuality.label} connection';
  }

  String get audioStatusLabel {
    if (!hasExpectedMicrophoneAudio) {
      return 'No remote microphone expected';
    }
    if (!audioPublicationExists) {
      return 'No microphone publication';
    }
    if (audioPublicationMuted) {
      return 'Microphone muted';
    }
    if (!audioTrackSubscribed) {
      return 'Microphone unsubscribed';
    }
    if (!audioSinkAttached) {
      return 'Audio sink missing';
    }
    if (remoteAudioReason == VoipRemoteAudioReasons.localPlaybackMuteDrift) {
      return 'Local playback muted unexpectedly';
    }
    if (userMuted || locallyMuted || effectiveVolume == 0) {
      return 'Local volume override active';
    }
    return 'Audio ready';
  }

  Map<String, Object?> toDiagnosticsJson() {
    return {
      'id': sanitizedId,
      'label': isLocal ? label : sanitizedId,
      'role': isLocal ? 'local' : 'remote',
      'connectionQuality': connectionQuality.name,
      'issueCodes': issueCodes,
      'audio': {
        'expected': hasExpectedMicrophoneAudio,
        'publicationExists': audioPublicationExists,
        'publicationMuted': audioPublicationMuted,
        'trackSubscribed': audioTrackSubscribed,
        'sinkAttached': audioSinkAttached,
        'effectiveVolume': effectiveVolume,
        'locallyMuted': locallyMuted,
        'userMuted': userMuted,
        'audible': remoteAudioAudible,
        'reason': remoteAudioReason,
      },
    };
  }
}

class CallHealthSnapshot {
  const CallHealthSnapshot({
    required this.collectedAt,
    required this.lifecycle,
    required this.state,
    this.participants = const [],
    this.issueCodes = const [],
  });

  const CallHealthSnapshot.unknown()
    : collectedAt = null,
      lifecycle = CallConnectionLifecycle.unknown,
      state = CallConnectionHealthState.unknown,
      participants = const [],
      issueCodes = const [];

  factory CallHealthSnapshot.derive({
    required DateTime collectedAt,
    required CallConnectionLifecycle lifecycle,
    Iterable<CallHealthParticipantSnapshot> participants = const [],
  }) {
    final participantList = List<CallHealthParticipantSnapshot>.unmodifiable(
      participants,
    );
    final issues = <String>{};

    switch (lifecycle) {
      case CallConnectionLifecycle.connecting:
        issues.add(CallHealthIssueCodes.callConnecting);
        break;
      case CallConnectionLifecycle.reconnecting:
        issues.add(CallHealthIssueCodes.roomReconnecting);
        break;
      case CallConnectionLifecycle.disconnected:
      case CallConnectionLifecycle.ended:
        issues.add(CallHealthIssueCodes.roomDisconnected);
        break;
      case CallConnectionLifecycle.unknown:
      case CallConnectionLifecycle.connected:
        break;
    }

    for (final participant in participantList) {
      issues.addAll(participant.issueCodes);
    }

    final state = _deriveState(lifecycle, participantList, issues);
    return CallHealthSnapshot(
      collectedAt: collectedAt,
      lifecycle: lifecycle,
      state: state,
      participants: participantList,
      issueCodes: List.unmodifiable(issues),
    );
  }

  final DateTime? collectedAt;
  final CallConnectionLifecycle lifecycle;
  final CallConnectionHealthState state;
  final List<CallHealthParticipantSnapshot> participants;
  final List<String> issueCodes;

  String get summaryLabel => state.summaryLabel;

  CallHealthParticipantSnapshot? get localParticipant {
    for (final participant in participants) {
      if (participant.isLocal) {
        return participant;
      }
    }
    return null;
  }

  Iterable<CallHealthParticipantSnapshot> get remoteParticipants {
    return participants.where((participant) => !participant.isLocal);
  }

  bool get hasAppIssue => state == CallConnectionHealthState.appIssueSuspected;

  bool get hasVolumeOverrides {
    return participants.any((participant) => participant.hasVolumeOverride);
  }

  String get reconnectStatusLabel {
    return switch (lifecycle) {
      CallConnectionLifecycle.reconnecting => 'Reconnecting',
      CallConnectionLifecycle.connecting => 'Connecting',
      CallConnectionLifecycle.disconnected => 'Disconnected',
      CallConnectionLifecycle.ended => 'Ended',
      CallConnectionLifecycle.connected => 'Connected',
      CallConnectionLifecycle.unknown => 'Unknown',
    };
  }

  String get audioStatusLabel {
    if (participants.any((participant) => participant.hasAppAudioIssue)) {
      return 'Audio path needs attention';
    }
    final expectedAudioCount = participants
        .where((participant) => participant.hasExpectedMicrophoneAudio)
        .length;
    if (expectedAudioCount == 0) {
      return 'No remote microphones published';
    }
    final mutedCount = participants
        .where(
          (participant) =>
              participant.hasExpectedMicrophoneAudio &&
              (participant.audioPublicationMuted ||
                  participant.userMuted ||
                  participant.locallyMuted ||
                  participant.effectiveVolume == 0),
        )
        .length;
    if (mutedCount > 0) {
      return '$mutedCount audio mute or volume override';
    }
    return '$expectedAudioCount audio track${expectedAudioCount == 1 ? '' : 's'} ready';
  }

  String get volumeOverrideStatusLabel {
    final count = participants
        .where((participant) => participant.hasVolumeOverride)
        .length;
    if (count == 0) {
      return 'No local overrides';
    }
    return '$count local override${count == 1 ? '' : 's'} active';
  }

  Map<String, Object?> toDiagnosticsJson() {
    return {
      'collectedAt': collectedAt?.toIso8601String(),
      'state': state.name,
      'summary': summaryLabel,
      'lifecycle': lifecycle.name,
      'issueCodes': issueCodes,
      'participants': [
        for (final participant in participants) participant.toDiagnosticsJson(),
      ],
    };
  }

  static CallConnectionHealthState _deriveState(
    CallConnectionLifecycle lifecycle,
    List<CallHealthParticipantSnapshot> participants,
    Set<String> issueCodes,
  ) {
    if (lifecycle == CallConnectionLifecycle.disconnected ||
        lifecycle == CallConnectionLifecycle.ended) {
      return CallConnectionHealthState.disconnected;
    }
    if (lifecycle == CallConnectionLifecycle.reconnecting) {
      return CallConnectionHealthState.reconnecting;
    }
    if (lifecycle == CallConnectionLifecycle.connecting ||
        issueCodes.contains(CallHealthIssueCodes.callConnecting)) {
      return CallConnectionHealthState.connecting;
    }
    if (issueCodes.any(CallHealthIssueCodes.appIssueCodes.contains)) {
      return CallConnectionHealthState.appIssueSuspected;
    }
    if (participants.any(
      (participant) => participant.connectionQuality.isPoor,
    )) {
      return CallConnectionHealthState.poor;
    }
    if (participants.any(
      (participant) => participant.connectionQuality.isFair,
    )) {
      return CallConnectionHealthState.fair;
    }
    if (lifecycle == CallConnectionLifecycle.connected) {
      return CallConnectionHealthState.good;
    }
    return CallConnectionHealthState.unknown;
  }
}

class CallHealthController {
  CallHealthSnapshot _snapshot = const CallHealthSnapshot.unknown();
  final StreamController<CallHealthSnapshot> _onChanged =
      StreamController.broadcast();
  bool _disposed = false;

  CallHealthSnapshot get snapshot => _snapshot;

  Stream<CallHealthSnapshot> get onChanged => _onChanged.stream;

  void update(CallHealthSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    _snapshot = snapshot;
    _onChanged.add(snapshot);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _onChanged.close();
  }
}
