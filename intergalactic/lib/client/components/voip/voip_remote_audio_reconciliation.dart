import 'dart:async';

enum VoipRemoteAudioRepairAction {
  none,
  subscribe,
  rebuildStreamOrSink,
  restoreLocalPlayback,
}

class VoipRemoteAudioState {
  const VoipRemoteAudioState({
    required this.participantConnected,
    required this.audioPublicationExists,
    required this.publicationMuted,
    required this.trackSubscribed,
    required this.streamObjectExists,
    required this.audioSinkAttached,
    required this.localVolume,
    required this.locallyMuted,
    required this.userMuted,
  });

  final bool participantConnected;
  final bool audioPublicationExists;
  final bool publicationMuted;
  final bool trackSubscribed;
  final bool streamObjectExists;
  final bool audioSinkAttached;
  final double localVolume;
  final bool locallyMuted;
  final bool userMuted;
}

class VoipRemoteAudioReconciliation {
  const VoipRemoteAudioReconciliation({
    required this.audible,
    required this.action,
    required this.reason,
  });

  final bool audible;
  final VoipRemoteAudioRepairAction action;
  final String reason;
}

class VoipRemoteAudioReasons {
  const VoipRemoteAudioReasons._();

  static const localPlaybackMuteDrift = 'local_playback_mute_drift';
}

typedef VoipRemoteAudioRepairStep = FutureOr<void> Function();
typedef VoipRemoteAudioRepairIsActive = bool Function();
typedef VoipRemoteAudioRepairErrorHandler =
    void Function(
      Object error,
      StackTrace stackTrace,
      VoipRemoteAudioReconciliation reconciliation,
    );

class VoipRemoteAudioRepairResult {
  const VoipRemoteAudioRepairResult({
    required this.action,
    required this.reason,
    required this.attempted,
    required this.repaired,
    this.inactive = false,
    this.error,
    this.stackTrace,
  });

  final VoipRemoteAudioRepairAction action;
  final String reason;
  final bool attempted;
  final bool repaired;
  final bool inactive;
  final Object? error;
  final StackTrace? stackTrace;

  bool get failed => error != null;
}

class VoipRemoteAudioReconciler {
  const VoipRemoteAudioReconciler._();

  static Future<VoipRemoteAudioRepairResult> repair(
    VoipRemoteAudioReconciliation reconciliation, {
    VoipRemoteAudioRepairStep? subscribe,
    VoipRemoteAudioRepairStep? rebuildStreamOrSink,
    VoipRemoteAudioRepairStep? restoreLocalPlayback,
    VoipRemoteAudioRepairIsActive? isActive,
    VoipRemoteAudioRepairErrorHandler? onError,
  }) async {
    final step = _stepForAction(
      reconciliation.action,
      subscribe: subscribe,
      rebuildStreamOrSink: rebuildStreamOrSink,
      restoreLocalPlayback: restoreLocalPlayback,
    );

    if (step == null) {
      return VoipRemoteAudioRepairResult(
        action: reconciliation.action,
        reason: reconciliation.reason,
        attempted: false,
        repaired: false,
      );
    }

    if (!_isActive(isActive)) {
      return VoipRemoteAudioRepairResult(
        action: reconciliation.action,
        reason: reconciliation.reason,
        attempted: false,
        repaired: false,
        inactive: true,
      );
    }

    try {
      await Future<void>.sync(step);
      if (!_isActive(isActive)) {
        return VoipRemoteAudioRepairResult(
          action: reconciliation.action,
          reason: reconciliation.reason,
          attempted: true,
          repaired: false,
          inactive: true,
        );
      }
      return VoipRemoteAudioRepairResult(
        action: reconciliation.action,
        reason: reconciliation.reason,
        attempted: true,
        repaired: true,
      );
    } catch (error, stackTrace) {
      if (!_isActive(isActive)) {
        return VoipRemoteAudioRepairResult(
          action: reconciliation.action,
          reason: reconciliation.reason,
          attempted: true,
          repaired: false,
          inactive: true,
        );
      }

      onError?.call(error, stackTrace, reconciliation);
      return VoipRemoteAudioRepairResult(
        action: reconciliation.action,
        reason: reconciliation.reason,
        attempted: true,
        repaired: false,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static bool _isActive(VoipRemoteAudioRepairIsActive? isActive) {
    return isActive?.call() ?? true;
  }

  static VoipRemoteAudioRepairStep? _stepForAction(
    VoipRemoteAudioRepairAction action, {
    required VoipRemoteAudioRepairStep? subscribe,
    required VoipRemoteAudioRepairStep? rebuildStreamOrSink,
    required VoipRemoteAudioRepairStep? restoreLocalPlayback,
  }) {
    switch (action) {
      case VoipRemoteAudioRepairAction.none:
        return null;
      case VoipRemoteAudioRepairAction.subscribe:
        return subscribe;
      case VoipRemoteAudioRepairAction.rebuildStreamOrSink:
        return rebuildStreamOrSink;
      case VoipRemoteAudioRepairAction.restoreLocalPlayback:
        return restoreLocalPlayback;
    }
  }
}

class VoipRemoteAudioReconciliationPolicy {
  const VoipRemoteAudioReconciliationPolicy._();

  static VoipRemoteAudioReconciliation evaluate(VoipRemoteAudioState state) {
    if (!state.participantConnected) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: 'participant_disconnected',
      );
    }

    if (!state.audioPublicationExists) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: 'no_remote_audio_publication',
      );
    }

    if (state.publicationMuted) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: 'remote_publication_muted',
      );
    }

    if (!state.trackSubscribed) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.subscribe,
        reason: 'remote_audio_unsubscribed',
      );
    }

    if (!state.streamObjectExists || !state.audioSinkAttached) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.rebuildStreamOrSink,
        reason: 'remote_audio_sink_missing',
      );
    }

    if (state.userMuted || state.localVolume <= 0) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: 'locally_user_muted',
      );
    }

    if (state.locallyMuted) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.restoreLocalPlayback,
        reason: VoipRemoteAudioReasons.localPlaybackMuteDrift,
      );
    }

    return const VoipRemoteAudioReconciliation(
      audible: true,
      action: VoipRemoteAudioRepairAction.none,
      reason: 'audible',
    );
  }
}
