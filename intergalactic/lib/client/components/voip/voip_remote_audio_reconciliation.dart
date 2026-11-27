import 'dart:async';

/// Which remote publication a reconciliation is about.
///
/// The policy in this file started as microphone-audio only. It now covers
/// every remote publication kind, because remote camera video, screen-share
/// video and screen-share audio had no desired-vs-actual reconciliation at any
/// point in a session's life and depend entirely on SDK events that are
/// provably dropped (P0-3): `TrackPublishedEvent` is emitted only while the
/// room is `connected`, the join path discards the publications it creates for
/// participants already in the room, and mute/unmute is emitted from a
/// track-level listener that does not exist while `publication.track` is null.
enum VoipRemoteMediaKind {
  microphoneAudio,
  screenShareAudio,
  cameraVideo,
  screenShareVideo;

  bool get isVideo =>
      this == VoipRemoteMediaKind.cameraVideo ||
      this == VoipRemoteMediaKind.screenShareVideo;

  bool get isScreenShare =>
      this == VoipRemoteMediaKind.screenShareAudio ||
      this == VoipRemoteMediaKind.screenShareVideo;

  /// Log/reason token. `microphoneAudio` keeps the historical `audio` token so
  /// existing captures and reason strings stay greppable.
  String get reasonToken {
    switch (this) {
      case VoipRemoteMediaKind.microphoneAudio:
        return 'audio';
      case VoipRemoteMediaKind.screenShareAudio:
        return 'screenshare_audio';
      case VoipRemoteMediaKind.cameraVideo:
        return 'video';
      case VoipRemoteMediaKind.screenShareVideo:
        return 'screenshare_video';
    }
  }
}

enum VoipRemoteAudioRepairAction {
  none,
  subscribe,
  resubscribe,
  rebuildStreamOrSink,
  restoreLocalPlayback,

  /// Drop a stream object whose publication says it should not be rendered.
  ///
  /// Only reachable for video: a remote camera or screen share that muted
  /// while its track was detached emits no `TrackMutedEvent`, so the tile
  /// survives with nothing behind it.
  removeStream,
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
    this.kind = VoipRemoteMediaKind.microphoneAudio,
    this.subscriptionPermitted = true,
    this.receiveDisabled = false,
    this.mediaAttachStalled = false,
  });

  final bool participantConnected;

  /// A publication of [kind] exists on the remote participant.
  final bool audioPublicationExists;
  final bool publicationMuted;

  /// The **control plane** believes this client is receiving the publication.
  ///
  /// This must NOT be fed `livekit_client`'s `RemoteTrackPublication.subscribed`
  /// getter. That getter is defined as `subscriptionAllowed && track != null`
  /// (`publication/remote.dart:68-72` over `publication/track_publication.dart:59`),
  /// so it is *guaranteed* false at `TrackPublishedEvent` time and a
  /// `!trackSubscribed -> subscribe` rule fed from it restates a definition
  /// rather than detecting a fault. Feed `publication.enabled` — the app's own
  /// receive switch, the only bit that can actually diverge from intent.
  final bool trackSubscribed;
  final bool streamObjectExists;

  /// The media sink is attached (`publication.track != null`). Named for the
  /// audio-only original; it means the same thing for video.
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

  final VoipRemoteMediaKind kind;

  /// The server permits subscription (`publication.subscriptionAllowed`). This
  /// is written only by `updateSubscriptionAllowed`, i.e. by the server, so a
  /// false value is a permission decision and not a client fault to repair.
  final bool subscriptionPermitted;

  /// The app itself does not want this media right now — the hidden-tile
  /// receive-quality policy disables and unsubscribes off-screen screen shares
  /// by default. Reconciling that state back to "subscribed" would fight the
  /// app's own bandwidth policy, so it outranks every repair below it.
  final bool receiveDisabled;

  /// The sink has been missing for longer than the attach grace window while
  /// the app wanted the media (see [VoipRemoteMediaAttachMonitor]). This is the
  /// non-tautological form of "not subscribed": it is a *duration*, not a
  /// restatement of `track == null`.
  final bool mediaAttachStalled;
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

  /// Locally silent because some owner asserted a mute. Not a fault, and not
  /// repairable until the mute records which owner asserted it.
  static const locallyMuted = 'locally_muted';

  /// The app's own receive-quality policy disabled this publication.
  static const receiveDisabled = 'receive_disabled_by_app';

  /// The server refused the subscription. Not a client-side fault.
  static const subscriptionNotPermitted = 'subscription_not_permitted';

  /// A video tile exists for a publication that says it is muted.
  static const staleVideoStream = 'remote_video_stream_stale';

  /// No media sink attached for longer than the attach grace window.
  static const mediaAttachStalled = 'remote_media_attach_stalled';
}

/// What a repair step did, when the step can tell the difference.
///
/// WHY THIS EXISTS. `repair` used to record `repaired: true` for any step that
/// returned without throwing, which conflates "the step RAN" with "the fault is
/// FIXED". Those came apart in the field: the `rebuildStreamOrSink` step for a
/// missing audio sink reaches an early return that only notifies listeners,
/// changes nothing, and cannot fail - so a participant stayed inaudible until a
/// rejoin while every log line said the repair had been applied. A
/// self-describing failure that does not self-repair is worse than an
/// undiagnosed one, because the log looks like the system handling it.
///
/// Returning null keeps the old meaning: the step has no opinion and running
/// without throwing counts as a repair. Only a step that can DETECT it did
/// nothing should say so.
typedef VoipRemoteAudioRepairStep = FutureOr<void> Function();

/// Asked, after a step has run without throwing, whether it changed anything.
///
/// A REPORTER RATHER THAN A RETURN VALUE, deliberately. Making steps return an
/// outcome types the distinction at every step site, but it also makes every
/// void-bodied step - which is nearly all of them, in production and in tests -
/// an analyzer warning for completing without returning a value, and the CI
/// gate treats warnings as fatal. So the one step that can detect it did
/// nothing reports through this, and the other four are untouched.
///
/// Only consulted on the success path. A step that threw is a failure, and a
/// step that never ran was never attempted; neither is this.
typedef VoipRemoteAudioRepairIneffective = bool Function();
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
    this.ineffective = false,
    this.inactive = false,
    this.error,
    this.stackTrace,
  });

  final VoipRemoteAudioRepairAction action;
  final String reason;
  final bool attempted;
  final bool repaired;

  /// The step ran to completion and reported that it changed nothing. Distinct
  /// from [failed] (which threw) and from `attempted == false` (which never
  /// ran), because this is the case that used to be indistinguishable from
  /// success.
  final bool ineffective;
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
    VoipRemoteAudioRepairStep? removeStream,
    VoipRemoteAudioRepairIsActive? isActive,
    VoipRemoteAudioRepairErrorHandler? onError,
    VoipRemoteAudioRepairIneffective? stepWasIneffective,
  }) async {
    final step = _stepForAction(
      reconciliation.action,
      subscribe: subscribe,
      resubscribe: resubscribe,
      rebuildStreamOrSink: rebuildStreamOrSink,
      restoreLocalPlayback: restoreLocalPlayback,
      removeStream: removeStream,
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
      // No reporter means the old answer: a step that ran without throwing
      // counts as a repair. Only a step that can DETECT it did nothing says so.
      final ineffective = stepWasIneffective?.call() ?? false;
      return VoipRemoteAudioRepairResult(
        action: reconciliation.action,
        reason: reconciliation.reason,
        attempted: true,
        repaired: !ineffective,
        ineffective: ineffective,
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
    required VoipRemoteAudioRepairStep? removeStream,
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
      case VoipRemoteAudioRepairAction.removeStream:
        return removeStream;
    }
  }
}

/// Tracks how long a wanted remote publication has gone without a media sink.
///
/// This exists because `RemoteTrackPublication.subscribed` is *defined* as
/// `subscriptionAllowed && track != null`, so "not subscribed" is guaranteed
/// true the instant a publication appears and carries no information. Every
/// repair the audio reconciler was ever observed to perform in the field was
/// triggered by that tautology.
///
/// A duration does carry information. A publication is only reported stalled
/// once the app has wanted it, uninterrupted, for [attachWindow] without a
/// sink ever attaching. Any observation where the sink is present or the app
/// does not want the media resets the window - and the caller folds mute into
/// wanted, per [recordObservation] - so the normal subscribe handshake never
/// trips it. Repairs are capped and cooled down per publication so a genuinely
/// dead sender cannot produce a resubscribe loop.
class VoipRemoteMediaAttachMonitor {
  VoipRemoteMediaAttachMonitor({
    this.attachWindow = const Duration(seconds: 8),
    this.repairCooldown = const Duration(seconds: 30),
    this.maxRepairs = 3,
  });

  final Duration attachWindow;
  final Duration repairCooldown;
  final int maxRepairs;

  final Map<String, _VoipRemoteMediaAttachEntry> _entries = {};

  /// Records one observation for [sid] and returns true when the missing sink
  /// should be treated as a fault.
  ///
  /// [wanted] is the app's desired state for the publication: false whenever
  /// the media is muted, receive-disabled, or not permitted, which are all
  /// legitimate reasons for a sink to be absent.
  bool recordObservation({
    required String sid,
    required bool wanted,
    required bool sinkAttached,
    required DateTime now,
  }) {
    final entry = _entries.putIfAbsent(
      sid,
      () => _VoipRemoteMediaAttachEntry(firstWantedAt: now),
    );

    if (!wanted || sinkAttached) {
      // WHICH of the two restarted the window is the question a capture cannot
      // answer without being told. The 2026-09-07 field case arrived under a
      // publication that never changed - no republish, no new SID - so
      // `!wanted` and `sinkAttached` are different stories about it: the first
      // means the app stopped wanting the media (a mute, or its own
      // receive-priority policy dropping an off-screen tile), the second means
      // the sink was attaching and detaching under a publication that looked
      // stable. Recording the reason is the difference between one capture
      // deciding it and another round of inference.
      entry.lastRestartReason = wanted ? 'sink_attached' : 'not_wanted';
      // Restart the attach window, but KEEP the entry. Removing it discarded
      // `repairCount` and `lastRepairAt` too, so a publication that alternates
      // between wanted and unwanted - exactly the hidden screen-share tile,
      // which flips `receiveDisabled` every time it scrolls off and back on -
      // was handed a fresh `maxRepairs` allowance and a cleared cooldown on
      // every transition. `retainOnly` is what drops entries for publications
      // that no longer exist. Matches VoipRemoteAudioFlowMonitor.
      entry.firstWantedAt = now;
      return false;
    }

    if (now.difference(entry.firstWantedAt) < attachWindow) {
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

  /// The three gate values behind [recordObservation]'s answer, for logging.
  ///
  /// WHY THIS IS A DIAGNOSTIC AND NOT A GETTER PER FIELD. When an escalation to
  /// `resubscribe` does not happen, exactly one of three gates held it back -
  /// still inside [attachWindow], [maxRepairs] spent, or inside
  /// [repairCooldown] - and a capture that reports only the chosen action
  /// cannot say which. That happened on the owner's 2026-09-07 capture and left
  /// three live hypotheses where the log could have left none. Emitting all
  /// three together is what makes one capture decisive.
  ///
  /// Returns null when [sid] has never been observed.
  String? describeGateState(String sid, DateTime now) {
    final entry = _entries[sid];
    if (entry == null) {
      return null;
    }
    final lastRepairAt = entry.lastRepairAt;
    final sinceRepair = lastRepairAt == null
        ? 'never'
        : '${now.difference(lastRepairAt).inSeconds}s';
    return 'wanted_for=${now.difference(entry.firstWantedAt).inSeconds}s '
        'attach_window=${attachWindow.inSeconds}s '
        'window_restart=${entry.lastRestartReason ?? 'none'} '
        'repairs=${entry.repairCount}/$maxRepairs '
        'since_repair=$sinceRepair '
        'cooldown=${repairCooldown.inSeconds}s';
  }

  /// Marks that a repair ran for [sid] and restarts its observation window.
  void recordRepair(String sid, DateTime now) {
    final entry = _entries[sid];
    if (entry == null) {
      return;
    }
    entry.repairCount += 1;
    entry.lastRepairAt = now;
    entry.firstWantedAt = now;
    entry.lastRestartReason = 'repair';
  }

  /// Drops tracking for publications that no longer exist.
  void retainOnly(Set<String> liveSids) {
    _entries.removeWhere((sid, _) => !liveSids.contains(sid));
  }

  void reset() => _entries.clear();
}

class _VoipRemoteMediaAttachEntry {
  _VoipRemoteMediaAttachEntry({required this.firstWantedAt});

  DateTime firstWantedAt;
  int repairCount = 0;
  DateTime? lastRepairAt;

  /// Why [firstWantedAt] was last moved forward: `not_wanted`, `sink_attached`
  /// or `repair`. Null until something has restarted it.
  String? lastRestartReason;
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
    final kind = state.kind;

    if (!state.participantConnected) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: 'participant_disconnected',
      );
    }

    if (!state.audioPublicationExists) {
      return VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: 'no_remote_${kind.reasonToken}_publication',
      );
    }

    // The app's own bandwidth policy outranks every repair below. CallView
    // disables and unsubscribes off-screen screen shares by default, which is
    // precisely the `track == null` state in which the SDK stops emitting
    // mute/unmute. Reconciling it back to "subscribed" would resubscribe every
    // hidden screen share on every sweep.
    if (state.receiveDisabled) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: VoipRemoteAudioReasons.receiveDisabled,
      );
    }

    // Written only by the server (`updateSubscriptionAllowed`), so this is a
    // permission decision, not client drift.
    if (!state.subscriptionPermitted) {
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: VoipRemoteAudioReasons.subscriptionNotPermitted,
      );
    }

    if (state.publicationMuted) {
      // A remote camera or screen share that muted while its track was
      // detached emits no TrackMutedEvent, so the tile the session built
      // earlier survives with nothing behind it. Audio tiles stay: a muted
      // participant still has a tile, and removing it would drop the volume
      // and mute state the user set on them.
      if (kind.isVideo && state.streamObjectExists) {
        return const VoipRemoteAudioReconciliation(
          audible: false,
          action: VoipRemoteAudioRepairAction.removeStream,
          reason: VoipRemoteAudioReasons.staleVideoStream,
        );
      }
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: 'remote_publication_muted',
      );
    }

    if (!state.trackSubscribed) {
      return VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.subscribe,
        reason: 'remote_${kind.reasonToken}_unsubscribed',
      );
    }

    // Split from the sink check below: a publication with no stream object is
    // an unrendered participant and must be built immediately, whereas a
    // stream whose sink has not arrived yet is the normal subscribe handshake
    // and must be given time.
    if (!state.streamObjectExists) {
      return VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.rebuildStreamOrSink,
        reason: 'remote_${kind.reasonToken}_stream_missing',
      );
    }

    if (!state.audioSinkAttached) {
      if (state.mediaAttachStalled) {
        return const VoipRemoteAudioReconciliation(
          audible: false,
          action: VoipRemoteAudioRepairAction.resubscribe,
          reason: VoipRemoteAudioReasons.mediaAttachStalled,
        );
      }
      return VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.rebuildStreamOrSink,
        // Kind-specific like the two branches above. The constant token made a
        // camera publication with no sink report an `audio` reason, which is
        // the one thing `reasonToken` exists to prevent. `microphoneAudio`
        // still resolves to `audio`, so existing captures stay greppable.
        reason: 'remote_${kind.reasonToken}_sink_missing',
      );
    }

    // Video has no local playback state: once the sink is attached and the
    // stream object exists, the tile renders.
    if (kind.isVideo) {
      return const VoipRemoteAudioReconciliation(
        audible: true,
        action: VoipRemoteAudioRepairAction.none,
        reason: 'rendered',
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
      // Silent on purpose, and the reconciler cannot tell whose purpose.
      //
      // `locallyMuted` is a single untagged bit asserted by four independent
      // owners: deafen (CallManager._applyDeafenToStream), the screenshare
      // tile-visibility policy (CallView._syncHiddenTileAudioMute), the
      // MatrixLivekitVoipStream constructor's screenshare gate, and a
      // volume-zero user mute. `userMuted` only recognises the last of those,
      // because it requires `localVolume <= 0` and the other three leave the
      // volume untouched. So this branch used to prescribe
      // `restoreLocalPlayback` for a deafen, the repair ran with
      // preserveMute:false, and deafen was cleared roughly ten seconds after
      // the user pressed it (observed 2026-08-02T01:38:32.503Z; see BUG-282).
      //
      // Until a mute carries its owner, "muted for a reason we cannot read" is
      // not a fault to repair. Detecting a *genuine* lost mute needs the
      // desired-vs-applied split described in
      // docs/plans/local-playback-mute-ownership-structural-plan.md; this
      // branch is where that check belongs once that lands, and
      // VoipRemoteAudioRepairAction.restoreLocalPlayback is deliberately kept
      // (currently unreachable from this policy) for it.
      return const VoipRemoteAudioReconciliation(
        audible: false,
        action: VoipRemoteAudioRepairAction.none,
        reason: VoipRemoteAudioReasons.locallyMuted,
      );
    }

    return const VoipRemoteAudioReconciliation(
      audible: true,
      action: VoipRemoteAudioRepairAction.none,
      reason: 'audible',
    );
  }
}
