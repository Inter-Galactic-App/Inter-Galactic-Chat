import 'dart:async';

enum VoipRemoteAudioRepairAction {
  none,
  subscribe,
  resubscribe,
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
    this.mediaStalled = false,
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

  /// True when the subscription looks healthy at the control-plane level but
  /// the receiver has not produced any RTP packets for the whole observation
  /// window (see [VoipRemoteAudioFlowMonitor]). This is the "joined an
  /// ongoing call but nobody can hear them until everyone rejoins" failure:
  /// only a fresh subscription fixes it, so the repair is a resubscribe.
  final bool mediaStalled;
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
  static const mediaStalled = 'remote_audio_media_stalled';
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
    VoipRemoteAudioRepairStep? resubscribe,
    VoipRemoteAudioRepairStep? rebuildStreamOrSink,
    VoipRemoteAudioRepairStep? restoreLocalPlayback,
    VoipRemoteAudioRepairIsActive? isActive,
    VoipRemoteAudioRepairErrorHandler? onError,
  }) async {
    final step = _stepForAction(
      reconciliation.action,
      subscribe: subscribe,
      resubscribe: resubscribe,
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
    required VoipRemoteAudioRepairStep? resubscribe,
    required VoipRemoteAudioRepairStep? rebuildStreamOrSink,
    required VoipRemoteAudioRepairStep? restoreLocalPlayback,
  }) {
    switch (action) {
      case VoipRemoteAudioRepairAction.none:
        return null;
      case VoipRemoteAudioRepairAction.subscribe:
        return subscribe;
      case VoipRemoteAudioRepairAction.resubscribe:
        return resubscribe;
      case VoipRemoteAudioRepairAction.rebuildStreamOrSink:
        return rebuildStreamOrSink;
      case VoipRemoteAudioRepairAction.restoreLocalPlayback:
        return restoreLocalPlayback;
    }
  }
}

/// Tracks whether a subscribed remote audio publication has ever delivered
/// RTP packets, so the reconciler can detect subscriptions that are healthy
/// at the control-plane level but silently dead at the media level.
///
/// The stall signal is deliberately conservative: a publication is only
/// stalled when it has been observed for at least [neverReceivedWindow] and
/// the receiver's cumulative `packetsReceived` is still zero. Opus DTX pauses
/// packet flow during silence, so "packets stopped advancing" is NOT treated
/// as a stall - only "never received anything since (re)subscribing" is.
/// Repairs are limited per publication with a cooldown to avoid resubscribe
/// loops against a genuinely broken sender.
class VoipRemoteAudioFlowMonitor {
  VoipRemoteAudioFlowMonitor({
    this.neverReceivedWindow = const Duration(seconds: 12),
    this.repairCooldown = const Duration(seconds: 30),
    this.maxRepairs = 3,
  });

  final Duration neverReceivedWindow;
  final Duration repairCooldown;
  final int maxRepairs;

  final Map<String, _VoipRemoteAudioFlowEntry> _entries = {};

  /// Records a stats sample for [sid] and returns true when the publication
  /// should be treated as media-stalled. [packetsReceived] null means stats
  /// were unavailable; that never counts as a stall.
  bool recordSample({
    required String sid,
    required num? packetsReceived,
    required DateTime now,
  }) {
    final entry = _entries.putIfAbsent(
      sid,
      () => _VoipRemoteAudioFlowEntry(firstObservedAt: now),
    );

    if (packetsReceived == null) {
      return false;
    }

    if (packetsReceived > 0) {
      entry.hasReceivedPackets = true;
      return false;
    }

    if (entry.hasReceivedPackets) {
      // Zero after previously seeing packets means the counter reset with a
      // new receiver; start a fresh observation window.
      entry.hasReceivedPackets = false;
      entry.firstObservedAt = now;
      return false;
    }

    if (now.difference(entry.firstObservedAt) < neverReceivedWindow) {
      return false;
    }

    if (entry.repairCount >= maxRepairs) {
      return false;
    }
    final lastRepairAt = entry.lastRepairAt;
    if (lastRepairAt != null && now.difference(lastRepairAt) < repairCooldown) {
      return false;
    }

    return true;
  }

  /// Marks that a resubscribe repair ran for [sid] and restarts its
  /// observation window.
  void recordRepair(String sid, DateTime now) {
    final entry = _entries[sid];
    if (entry == null) {
      return;
    }
    entry.repairCount += 1;
    entry.lastRepairAt = now;
    entry.firstObservedAt = now;
    entry.hasReceivedPackets = false;
  }

  /// Drops tracking for publications that no longer exist.
  void retainOnly(Set<String> liveSids) {
    _entries.removeWhere((sid, _) => !liveSids.contains(sid));
  }

  void reset() {
    _entries.clear();
  }
}

class _VoipRemoteAudioFlowEntry {
  _VoipRemoteAudioFlowEntry({required this.firstObservedAt});

  DateTime firstObservedAt;
  bool hasReceivedPackets = false;
  int repairCount = 0;
  DateTime? lastRepairAt;
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

    if (state.mediaStalled) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.resubscribe,
        reason: VoipRemoteAudioReasons.mediaStalled,
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
