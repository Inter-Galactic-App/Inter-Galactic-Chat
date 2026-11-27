import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/bug_report/pending_native_call_crash_guard.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report_store.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_backend.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_capability.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_coordinator.dart';
import 'package:intergalactic/client/components/voip/shared_audio/windows_shared_audio_backend.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

enum ShareTargetType { display, window }

/// Legacy per-session audio mode, superseded by `SharedAudioCaptureMode` in
/// `shared_audio/`. Kept in step with the native `WindowsSharedAudioMode` so
/// the endpoint-loopback and device-capture backends are not flattened into
/// `systemLoopback`, which would hide that they cannot exclude our own call
/// audio.
enum SharedAudioMode {
  none,
  processTreeLoopback,
  systemLoopback,
  unavailable,
  endpointLoopback,
  deviceCapture,
}

enum SharedAudioState {
  disabled,
  starting,
  active,
  unavailable,
  failed,
  stopped,

  /// The requested capture cannot run, but alternatives exist and are waiting
  /// on an explicit choice. Distinct from [unavailable], which means there is
  /// nothing to offer: collapsing the two is what let the offers go unread.
  ///
  /// Nothing starts in this state. The share runs video-only until the user
  /// picks an option or declines.
  needsChoice,
}

enum ShareSessionLifecycle {
  idle,
  starting,
  sharing,
  videoOnly,
  stopping,
  stopped,
  failed,
}

class ShareTarget {
  const ShareTarget({
    required this.type,
    required this.sourceId,
    required this.title,
    this.processId,
  });

  final ShareTargetType type;
  final String sourceId;
  final String title;
  final int? processId;
}

class ShareSessionDiagnosticSummary {
  const ShareSessionDiagnosticSummary({
    required this.sourceType,
    required this.sourceIdHash,
    required this.processId,
    required this.audioRequested,
    required this.audioMode,
    required this.audioState,
    required this.audioReason,
    this.lifecycle,
    this.sourceTitle,
  });

  factory ShareSessionDiagnosticSummary.fromSession(
    ShareSession session, {
    bool includeTitle = false,
  }) {
    final status = session.sharedAudioStatus;
    return ShareSessionDiagnosticSummary(
      sourceType: session.target.type,
      sourceIdHash: shortShareSourceIdHash(session.target.sourceId),
      processId: session.target.processId,
      audioRequested: session.sharedAudioRequested,
      audioMode: status.mode,
      audioState: status.state,
      audioReason: status.reason,
      lifecycle: session.lifecycle,
      sourceTitle: includeTitle
          ? truncateShareSourceTitle(session.target.title)
          : null,
    );
  }

  final ShareTargetType sourceType;
  final String sourceIdHash;
  final int? processId;
  final bool audioRequested;
  final SharedAudioMode audioMode;
  final SharedAudioState audioState;
  final String audioReason;
  final ShareSessionLifecycle? lifecycle;
  final String? sourceTitle;

  String get sourceLine {
    final title = sourceTitle == null ? '' : ' title="$sourceTitle"';
    return 'sourceType=${sourceType.name} sourceIdHash=$sourceIdHash '
        'pid=${processId ?? '?'}$title';
  }

  String get audioLine {
    return 'audioRequested=$audioRequested mode=${audioMode.name} '
        'state=${audioState.name} reason=$audioReason';
  }

  List<String> lines() {
    return <String>[
      'Share source: $sourceLine',
      if (lifecycle != null) 'Share lifecycle: ${lifecycle!.name}',
      'Share audio: $audioLine',
    ];
  }

  String toLogLine() {
    final lifecycleLabel = lifecycle == null
        ? ''
        : ' lifecycle=${lifecycle!.name}';
    return '$sourceLine$lifecycleLabel $audioLine';
  }
}

String shortShareSourceIdHash(String sourceId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in sourceId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String truncateShareSourceTitle(String title, {int maxLength = 80}) {
  final normalized = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= maxLength) {
    return normalized;
  }

  return '${normalized.substring(0, maxLength - 3)}...';
}

abstract class ScreenVideoSource {
  ShareTarget get target;
}

class WebrtcScreenVideoSource implements ScreenVideoSource {
  const WebrtcScreenVideoSource({required this.target, required this.source});

  @override
  final ShareTarget target;

  final DesktopCapturerSource source;
}

class MicSource {
  const MicSource({this.enabled = true, this.rnnoiseApplies = true});

  final bool enabled;
  final bool rnnoiseApplies;
}

/// How much captured audio we require before concluding a still-active session
/// is delivering only silence. At ~44.1kHz with event-driven ~10ms buffers this
/// is roughly two seconds, long enough to ride out a momentarily-quiet source.
const int kSharedAudioSilenceEvidencePackets = 200;

/// Native reason emitted when Windows refuses the process-loopback activation
/// at runtime.
///
/// This is a *measured* refusal, not a version check: the native layer attempts
/// the activation on every build and reports the HRESULT it got back. Windows
/// 10 build 19045 frequently activates successfully despite being below
/// Microsoft's documented 20348 minimum, so the old
/// `process_loopback_requires_windows_10_20348` reason (and the "update
/// Windows" advice that went with it) was wrong on exactly the machines it
/// most affected.
const String kSharedAudioProcessLoopbackUnsupportedReason =
    'process_loopback_activation_failed';

enum SharedAudioAdvisoryKind {
  /// Nothing to warn about.
  none,

  /// The window-share target runs elevated; process-loopback cannot hear it.
  targetElevated,

  /// The session is active but has captured only silence so far.
  capturingSilence,

  /// Windows refused per-application audio capture on this machine. Whole-
  /// screen (desktop) audio may still be available through endpoint loopback,
  /// so this is an offer to choose, not a dead end. Video sharing is
  /// unaffected.
  processLoopbackRefused,
}

/// A user-facing hint about why shared audio may not be reaching listeners,
/// with an actionable remedy. Derived purely from a [SharedAudioStatus] so it
/// can be unit-tested without any native layer.
class SharedAudioAdvisory {
  const SharedAudioAdvisory(this.kind, this.title, this.detail);

  final SharedAudioAdvisoryKind kind;
  final String title;
  final String detail;

  bool get hasAdvisory => kind != SharedAudioAdvisoryKind.none;

  static const SharedAudioAdvisory none = SharedAudioAdvisory(
    SharedAudioAdvisoryKind.none,
    '',
    '',
  );
}

class SharedAudioStatus {
  const SharedAudioStatus({
    required this.state,
    required this.mode,
    required this.reason,
    this.sampleRateHz = 0,
    this.numChannels = 0,
    this.bitsPerSample = 0,
    this.packetsCaptured = 0,
    this.framesCaptured = 0,
    this.bytesCaptured = 0,
    this.nonsilentBytesCaptured = 0,
    this.targetProcessElevated = false,
    this.targetElevationKnown = false,
    this.pcmBridgeSupported = false,
  });

  final SharedAudioState state;
  final SharedAudioMode mode;
  final String reason;
  final int sampleRateHz;
  final int numChannels;
  final int bitsPerSample;
  final int packetsCaptured;
  final int framesCaptured;
  final int bytesCaptured;

  /// Bytes captured that were not flagged silent by the loopback graph. Stays 0
  /// when the target produces no audible output or capture is blocked.
  final int nonsilentBytesCaptured;

  /// True when the process-tree loopback target runs at a higher integrity
  /// level than this app (an elevated / anti-cheat-protected game).
  final bool targetProcessElevated;

  /// True when the native layer positively determined the target's elevation.
  final bool targetElevationKnown;

  final bool pcmBridgeSupported;

  /// True once the session is active and has captured enough packets, all of
  /// which were silent — a strong sign the source's audio isn't reaching us.
  bool get isCapturingOnlySilence =>
      state == SharedAudioState.active &&
      packetsCaptured >= kSharedAudioSilenceEvidencePackets &&
      nonsilentBytesCaptured == 0;

  /// A user-facing advisory explaining why shared audio may be missing.
  /// Elevation (deterministic) takes priority over the silence heuristic.
  SharedAudioAdvisory get advisory {
    if (targetProcessElevated) {
      return const SharedAudioAdvisory(
        SharedAudioAdvisoryKind.targetElevated,
        "Can't capture this game's audio",
        'The shared window runs as administrator, so Windows blocks audio '
            'capture. Run Inter Galactic as administrator, or share your whole '
            'screen instead of the game window, to include its sound.',
      );
    }

    if (reason == kSharedAudioProcessLoopbackUnsupportedReason) {
      return const SharedAudioAdvisory(
        SharedAudioAdvisoryKind.processLoopbackRefused,
        "Can't share this app's sound on its own",
        'Windows would not let Inter Galactic capture audio from just this '
            'app. You can instead share all sound from this computer - which '
            'also shares notifications, other apps, and this call - or carry '
            'on without sound. Video sharing is unaffected.',
      );
    }

    if (isCapturingOnlySilence) {
      return const SharedAudioAdvisory(
        SharedAudioAdvisoryKind.capturingSilence,
        'No audio detected from this share',
        "The shared source isn't producing sound, or its audio is blocked. If "
            "it's a game, try running Inter Galactic as administrator or "
            'sharing your whole screen instead.',
      );
    }

    return SharedAudioAdvisory.none;
  }
}

abstract class SharedAudioSource {
  bool get requested;
  SharedAudioMode get mode;
  SharedAudioState get state;
  SharedAudioStatus get status;

  Future<SharedAudioStatus> start();
  Future<SharedAudioStatus> stop();
  Future<void> dispose();
}

abstract class SharedAudioPublicationSource {
  Future<MediaStream?> createPublicationStream();

  Future<void> disposePublicationStream();
}

/// A source that can offer alternatives when the requested capture is refused.
///
/// Separate from [SharedAudioSource] for the same reason
/// [SharedAudioPublicationSource] is: a source with nothing to offer - the
/// disabled one, and every non-Windows source - should not have to implement
/// a choice it can never present.
///
/// The contract is that nothing here ever starts a capture on the user's
/// behalf. [pendingFallbackOptions] is non-empty only while a choice is
/// outstanding, and it is cleared by [applyFallbackOption] or
/// [declineFallback] - never by a retry this layer decided to make.
abstract class SharedAudioFallbackSource {
  /// Alternatives awaiting an explicit choice, best first. Empty when no
  /// choice is outstanding.
  List<SharedAudioFallbackOption> get pendingFallbackOptions;

  /// Warning covering the offered alternatives as a group. Empty when there is
  /// nothing to warn about, or when no choice is outstanding.
  String get pendingFallbackWarning;

  /// Starts the capture the user picked. Only valid while
  /// [pendingFallbackOptions] is non-empty; the option must be one of them.
  ///
  /// A start that is itself refused can leave a further choice outstanding,
  /// so callers must re-read [pendingFallbackOptions] after this returns.
  Future<SharedAudioStatus> applyFallbackOption(
    SharedAudioFallbackOption option,
  );

  /// Records that the user declined every alternative. The share continues
  /// video-only and nothing is offered again for this session.
  Future<SharedAudioStatus> declineFallback();
}

class DisabledSharedAudioSource implements SharedAudioSource {
  const DisabledSharedAudioSource({this.reason = 'shared_audio_not_requested'});

  final String reason;

  @override
  bool get requested => false;

  @override
  SharedAudioMode get mode => SharedAudioMode.none;

  @override
  SharedAudioState get state => SharedAudioState.disabled;

  @override
  SharedAudioStatus get status =>
      SharedAudioStatus(state: state, mode: mode, reason: reason);

  @override
  Future<void> dispose() async {}

  @override
  Future<SharedAudioStatus> start() async => status;

  @override
  Future<SharedAudioStatus> stop() async => status;
}

/// Windows shared audio, owned by [WindowsSharedAudioBackend].
///
/// This class keeps the [SharedAudioSource] surface its callers already use -
/// `call_view` renders the in-call indicator from [SharedAudioStatus.advisory],
/// and the diagnostics summary reads the same object - while the native session
/// and publication stream are owned by the backend. It holds no session id and
/// no stream of its own: two wrappers with independent lifecycle state is the
/// defect this migration exists to remove.
///
/// Its job is translation. The backend speaks the platform-neutral vocabulary
/// in `shared_audio/`; this maps a request into it and maps the resulting
/// observation back, verbatim where callers match on exact values.
class WindowsSharedAudioSource
    implements
        SharedAudioSource,
        SharedAudioPublicationSource,
        SharedAudioFallbackSource {
  WindowsSharedAudioSource({
    required WindowsShareNativeBinding nativeBinding,
    required this.target,
    required this.requested,
    required this.mode,
    SharedAudioBackend? backend,
    SharedAudioCoordinator? coordinator,
  }) : _backend = backend ?? WindowsSharedAudioBackend(binding: nativeBinding) {
    _coordinator = coordinator ?? SharedAudioCoordinator(backend: _backend);
  }

  final SharedAudioBackend _backend;

  /// Decides whether the requested mode can run and, when it cannot, produces
  /// the alternatives. It never substitutes a mode on its own, which is the
  /// property this route depends on: a refused process-loopback capture must
  /// reach the user as a choice, not as a quietly different capture.
  late final SharedAudioCoordinator _coordinator;

  /// The choice outstanding right now, or null when there is none.
  SharedAudioPlan? _pendingPlan;

  /// Set once the user has declined, so a later start cannot re-offer what
  /// they already turned down.
  bool _fallbackDeclined = false;

  final ShareTarget target;

  SharedAudioStatus _status = const SharedAudioStatus(
    state: SharedAudioState.stopped,
    mode: SharedAudioMode.none,
    reason: 'not_started',
  );

  @override
  final bool requested;

  @override
  final SharedAudioMode mode;

  @override
  SharedAudioState get state => _status.state;

  @override
  SharedAudioStatus get status => _status;

  @override
  Future<SharedAudioStatus> start() async {
    if (!requested) {
      _status = const SharedAudioStatus(
        state: SharedAudioState.disabled,
        mode: SharedAudioMode.none,
        reason: 'shared_audio_not_requested',
      );
      return _status;
    }

    // Resolved before the backend is asked: "we could not work out what to
    // capture" is not a question the platform can answer.
    if (mode == SharedAudioMode.unavailable) {
      _status = SharedAudioStatus(
        state: SharedAudioState.unavailable,
        mode: mode,
        reason:
            target.processId == null && target.type == ShareTargetType.window
            ? 'target_process_unresolved'
            : 'shared_audio_unavailable',
      );
      return _status;
    }

    try {
      // Ask before starting. The refusal this exists for is measured, not
      // predicted: the platform can only be asked by probing, so a mode that
      // looks supported can still be refused at activation.
      final plan = await _coordinator.plan(_request);

      if (plan.kind == SharedAudioPlanKind.needsUserChoice) {
        if (!_fallbackDeclined) {
          return _awaitChoice(plan);
        }

        // Re-offering what they already turned down is the silent retry in
        // slow motion. Falling through to start the planned request would be
        // worse still: the plan says that mode cannot run, so this would ask
        // the platform to do the thing it just refused.
        _pendingPlan = null;
        _status = SharedAudioStatus(
          state: SharedAudioState.unavailable,
          mode: mode,
          reason: SharedAudioUnavailableReason.userDeclined.logLabel,
        );
        return _status;
      }

      if (plan.kind == SharedAudioPlanKind.unavailable) {
        _pendingPlan = null;
        _status = SharedAudioStatus(
          state: SharedAudioState.unavailable,
          mode: mode,
          reason: plan.blockedReason?.logLabel ?? 'shared_audio_unavailable',
        );
        return _status;
      }

      // The plan is ready. Start exactly what was planned - never a
      // substituted mode.
      return _startPlanned(plan.request);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to start Windows shared-content audio',
      );
      _status = SharedAudioStatus(
        state: SharedAudioState.failed,
        mode: mode,
        reason: 'native_start_failed',
      );
      return _status;
    }
  }

  /// Holds the offers and starts nothing.
  ///
  /// The status carries the reason the requested mode was refused, not a
  /// generic one, because that reason is what the user is being asked to
  /// decide about.
  SharedAudioStatus _awaitChoice(SharedAudioPlan plan) {
    _pendingPlan = plan;
    _status = SharedAudioStatus(
      state: SharedAudioState.needsChoice,
      mode: mode,
      reason: plan.blockedReason?.logLabel ?? 'shared_audio_needs_choice',
    );
    Log.i(
      'Shared audio needs a choice: refused=${_status.reason} '
      'options=${plan.options.length}',
    );
    return _status;
  }

  /// Runs a capture that was either planned ready or explicitly chosen.
  ///
  /// A start can be refused even after a clean plan, so the outcome's
  /// follow-up offers are surfaced the same way the initial ones are rather
  /// than being retried here.
  Future<SharedAudioStatus> _startPlanned(SharedAudioRequest request) async {
    final outcome = await _coordinator.start(request);

    if (!outcome.started && !_fallbackDeclined) {
      final followUp = outcome.followUpPlan;
      if (followUp != null &&
          followUp.kind == SharedAudioPlanKind.needsUserChoice) {
        return _awaitChoice(followUp);
      }
    }

    _pendingPlan = null;
    _status = _statusFrom(_backend.lastStatus);
    return _status;
  }

  @override
  List<SharedAudioFallbackOption> get pendingFallbackOptions =>
      _pendingPlan?.options ?? const <SharedAudioFallbackOption>[];

  @override
  String get pendingFallbackWarning => _pendingPlan?.warning ?? '';

  @override
  Future<SharedAudioStatus> applyFallbackOption(
    SharedAudioFallbackOption option,
  ) async {
    final plan = _pendingPlan;
    if (plan == null) {
      // Not an error worth failing the share over, but it must not start
      // anything: an option applied with no outstanding choice is a caller
      // bug, and starting it would be the silent substitution this route
      // exists to prevent.
      Log.w('Shared-audio fallback chosen with no choice outstanding; ignored');
      return _status;
    }

    // A capture is running in the mode the user just replaced, if a follow-up
    // choice came from a start that had already partially succeeded.
    try {
      await _backend.stop();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop shared-content audio before applying choice',
      );
    }

    _pendingPlan = null;

    try {
      return await _startPlanned(option.applyTo(plan.request));
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to start chosen Windows shared-content audio',
      );
      _status = SharedAudioStatus(
        state: SharedAudioState.failed,
        mode: mode,
        reason: 'native_start_failed',
      );
      return _status;
    }
  }

  @override
  Future<SharedAudioStatus> declineFallback() async {
    _pendingPlan = null;
    _fallbackDeclined = true;
    try {
      await _backend.stop();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop shared-content audio after declining choice',
      );
    }
    // The platform's refusal is not the reason any more - the user is. Keeping
    // the original block reason here would record a decision they made as a
    // failure the machine had.
    _status = SharedAudioStatus(
      state: SharedAudioState.unavailable,
      mode: mode,
      reason: SharedAudioUnavailableReason.userDeclined.logLabel,
    );
    Log.i('Shared audio declined by user: reason=${_status.reason}');
    return _status;
  }

  @override
  Future<SharedAudioStatus> stop() async {
    if (!requested) {
      _status = const SharedAudioStatus(
        state: SharedAudioState.disabled,
        mode: SharedAudioMode.none,
        reason: 'shared_audio_not_requested',
      );
      return _status;
    }

    try {
      await _backend.stop();
      _status = _statusFrom(_backend.lastStatus);
      return _status;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop Windows shared-content audio',
      );
      _status = SharedAudioStatus(
        state: SharedAudioState.failed,
        mode: mode,
        reason: 'native_stop_failed',
      );
      return _status;
    }
  }

  @override
  Future<MediaStream?> createPublicationStream() async {
    if (!requested) {
      return null;
    }

    try {
      return await _backend.createPublicationStream();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to create Windows shared-content audio track',
      );
      return null;
    }
  }

  @override
  Future<void> disposePublicationStream() async {
    try {
      await _backend.disposePublicationStream();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to dispose Windows shared-content audio track',
      );
    }
  }

  @override
  Future<void> dispose() => _backend.dispose();

  SharedAudioRequest get _request => SharedAudioRequest(
    mode: _toCaptureMode(mode),
    targetProcessId: target.processId,
    targetTitle: target.title,
    sharingWholeScreen: target.type == ShareTargetType.display,
  );

  /// Maps the backend's observation back onto the status callers already read.
  ///
  /// [SharedAudioCaptureStatus.nativeReason] is used verbatim for the reason
  /// because the advisory string-matches the platform's own token; normalising
  /// it is what would silently stop the refusal advisory firing.
  ///
  /// When the platform produced no token at all - an attempt that never reached
  /// the native layer - the fallback is the structured cause's own snake_case
  /// label, never `detail`. Both this field and `detail` end up in
  /// `_audioEvidenceLine` and `ShareSessionDiagnosticSummary.audioLine`, which
  /// are space-separated `key=value` records, so a free-text sentence in
  /// `reason=` runs into the next field and breaks every parse of the line.
  SharedAudioStatus _statusFrom(SharedAudioCaptureStatus observed) {
    return SharedAudioStatus(
      state: _toLegacyState(observed.state),
      mode: _toLegacyMode(observed),
      // With no platform token, fall back to the structured cause's own label
      // rather than to `detail`: `detail` is a user-facing sentence, and it is
      // emitted as the `reason=` field of a space-separated `key=value`
      // evidence line, which a sentence breaks.
      reason: observed.nativeReason.isEmpty
          ? (observed.reason?.logLabel ?? '')
          : observed.nativeReason,
      sampleRateHz: observed.sampleRateHz,
      numChannels: observed.numChannels,
      bitsPerSample: observed.bitsPerSample,
      packetsCaptured: observed.packetsCaptured,
      framesCaptured: observed.framesCaptured,
      bytesCaptured: observed.bytesCaptured,
      nonsilentBytesCaptured: observed.nonsilentBytesCaptured,
      targetProcessElevated: observed.targetNotCapturable,
      targetElevationKnown: observed.targetCapturabilityKnown,
      pcmBridgeSupported: observed.canPublish,
    );
  }
}

SharedAudioCaptureMode _toCaptureMode(SharedAudioMode mode) {
  return switch (mode) {
    SharedAudioMode.processTreeLoopback =>
      SharedAudioCaptureMode.selectedApplication,
    // Both whole-computer routes are the same user-facing mode; which mechanism
    // serves it is the backend's choice, not this layer's.
    SharedAudioMode.systemLoopback ||
    SharedAudioMode.endpointLoopback => SharedAudioCaptureMode.desktopAudio,
    SharedAudioMode.deviceCapture => SharedAudioCaptureMode.selectedDevice,
    SharedAudioMode.none ||
    SharedAudioMode.unavailable => SharedAudioCaptureMode.none,
  };
}

/// Recovers the legacy mode from the mode asked for plus the mechanism that
/// served it, so a desktop capture still reports whether it ran on process
/// loopback or on endpoint loopback - the two differ in whether our own call
/// audio is excluded.
SharedAudioMode _toLegacyMode(SharedAudioCaptureStatus observed) {
  return switch (observed.mode) {
    SharedAudioCaptureMode.selectedApplication =>
      SharedAudioMode.processTreeLoopback,
    SharedAudioCaptureMode.desktopAudio =>
      observed.backend == SharedAudioBackendKind.windowsEndpointLoopback
          ? SharedAudioMode.endpointLoopback
          : SharedAudioMode.systemLoopback,
    SharedAudioCaptureMode.selectedDevice => SharedAudioMode.deviceCapture,
    SharedAudioCaptureMode.none => SharedAudioMode.none,
  };
}

SharedAudioState _toLegacyState(SharedAudioCaptureState state) {
  return switch (state) {
    SharedAudioCaptureState.disabled => SharedAudioState.disabled,
    SharedAudioCaptureState.starting => SharedAudioState.starting,
    SharedAudioCaptureState.active => SharedAudioState.active,
    SharedAudioCaptureState.unavailable => SharedAudioState.unavailable,
    SharedAudioCaptureState.failed => SharedAudioState.failed,
    SharedAudioCaptureState.stopped => SharedAudioState.stopped,
  };
}

class ShareSession {
  ShareSession({
    required this.target,
    required this.videoSource,
    required this.sharedAudioSource,
    this.micSource = const MicSource(),
    PendingCrashReportStore crashReportStore = const PendingCrashReportStore(),
    bool? isWindowsPlatform,
  }) : _crashReportStore = crashReportStore,
       _isWindowsPlatform = isWindowsPlatform ?? PlatformUtils.isWindows;

  final ShareTarget target;
  final ScreenVideoSource videoSource;
  final SharedAudioSource sharedAudioSource;
  final MicSource micSource;
  final PendingCrashReportStore _crashReportStore;
  final bool _isWindowsPlatform;

  ShareSessionLifecycle lifecycle = ShareSessionLifecycle.idle;
  PendingNativeCallCrashGuard? _nativeSharedAudioCrashGuard;

  bool get _usesNativeWindowsSharedAudio =>
      _isWindowsPlatform &&
      sharedAudioSource is WindowsSharedAudioSource &&
      sharedAudioSource.requested;

  Future<PendingNativeCallCrashGuard?> _recordNativeSharedAudioAction() =>
      PendingNativeCallCrashGuard.recordAction(
        source:
            'share-session-native-shared-audio-'
            '${shortShareSourceIdHash(target.sourceId)}',
        actionKind: 'Windows display-share audio capture',
        store: _crashReportStore,
      );

  bool get sharedAudioRequested => sharedAudioSource.requested;
  SharedAudioState get sharedAudioState => sharedAudioSource.state;
  SharedAudioStatus get sharedAudioStatus => sharedAudioSource.status;

  ShareSessionDiagnosticSummary diagnosticsSummary({
    bool includeTitle = false,
  }) {
    return ShareSessionDiagnosticSummary.fromSession(
      this,
      includeTitle: includeTitle,
    );
  }

  Future<SharedAudioStatus> startSharedAudio() async {
    lifecycle = ShareSessionLifecycle.starting;
    await _nativeSharedAudioCrashGuard?.clear();
    _nativeSharedAudioCrashGuard = null;
    final nativeCrashGuard = _usesNativeWindowsSharedAudio
        ? await _recordNativeSharedAudioAction()
        : null;

    late final SharedAudioStatus status;
    try {
      status = await sharedAudioSource.start();
    } catch (error, stackTrace) {
      await nativeCrashGuard?.clear();
      Log.onError(
        error,
        stackTrace,
        content: 'Shared-content audio start failed',
      );
      lifecycle = ShareSessionLifecycle.videoOnly;
      return SharedAudioStatus(
        state: SharedAudioState.failed,
        mode: sharedAudioSource.mode,
        reason: 'shared_audio_start_failed',
      );
    }

    lifecycle = status.state == SharedAudioState.active
        ? ShareSessionLifecycle.sharing
        : ShareSessionLifecycle.videoOnly;
    if (status.state == SharedAudioState.active) {
      _nativeSharedAudioCrashGuard = nativeCrashGuard;
    } else {
      await nativeCrashGuard?.clear();
    }

    // Emitted for success as well as failure. A capture that starts cleanly
    // used to log nothing at all, which made a live smoke impossible to
    // evidence from logs alone - the only proof was a listener saying they
    // could hear it.
    Log.i('Shared audio start: ${_audioEvidenceLine(status)}');

    if (sharedAudioSource.requested &&
        status.state == SharedAudioState.needsChoice) {
      // Deliberately not the "unavailable" line below. This share is
      // video-only for now and can still get audio, and a log saying
      // otherwise is what would make an unanswered choice look like a
      // finished failure.
      Log.w(
        'Shared-content audio for ${target.title} needs a choice: '
        '${status.reason}; '
        '${pendingSharedAudioOptions.length} option(s) offered, '
        'video-only until one is picked.',
      );
    } else if (sharedAudioSource.requested &&
        status.state != SharedAudioState.active) {
      Log.w(
        'Shared-content audio unavailable for ${target.title}: '
        '${status.reason}; continuing with video-only screenshare.',
      );
    }

    // Elevated targets report an "active" capture that only ever yields
    // silence, so surface that distinct, actionable case separately.
    final advisory = status.advisory;
    if (advisory.hasAdvisory) {
      Log.w(
        'Shared-content audio for ${target.title}: ${advisory.title} '
        '(${advisory.kind.name}); ${advisory.detail}',
      );
    }

    return status;
  }

  /// Alternatives waiting on an explicit choice, best first.
  ///
  /// Non-empty only while [sharedAudioState] is
  /// [SharedAudioState.needsChoice]. Presenting these is the caller's job;
  /// nothing starts until one is passed back to
  /// [chooseSharedAudioFallback].
  List<SharedAudioFallbackOption> get pendingSharedAudioOptions {
    final source = sharedAudioSource;
    if (source is! SharedAudioFallbackSource) {
      return const <SharedAudioFallbackOption>[];
    }

    return (source as SharedAudioFallbackSource).pendingFallbackOptions;
  }

  /// Warning covering the offered alternatives as a group, or empty.
  String get pendingSharedAudioWarning {
    final source = sharedAudioSource;
    if (source is! SharedAudioFallbackSource) {
      return '';
    }

    return (source as SharedAudioFallbackSource).pendingFallbackWarning;
  }

  /// Starts the alternative the user picked.
  ///
  /// The picked option can itself be refused, so callers must re-read
  /// [pendingSharedAudioOptions] afterwards rather than assuming this settled
  /// the question.
  Future<SharedAudioStatus> chooseSharedAudioFallback(
    SharedAudioFallbackOption option,
  ) async {
    final source = sharedAudioSource;
    if (source is! SharedAudioFallbackSource) {
      return sharedAudioStatus;
    }

    final fallbackSource = source as SharedAudioFallbackSource;
    final nativeCrashGuard =
        _usesNativeWindowsSharedAudio &&
            fallbackSource.pendingFallbackOptions.isNotEmpty
        ? await _recordNativeSharedAudioAction()
        : null;
    late final SharedAudioStatus status;
    try {
      status = await fallbackSource.applyFallbackOption(option);
    } catch (_) {
      await nativeCrashGuard?.clear();
      rethrow;
    }
    if (nativeCrashGuard != null) {
      if (status.state == SharedAudioState.active) {
        _nativeSharedAudioCrashGuard = nativeCrashGuard;
      } else {
        await nativeCrashGuard.clear();
      }
    }
    lifecycle = status.state == SharedAudioState.active
        ? ShareSessionLifecycle.sharing
        : ShareSessionLifecycle.videoOnly;
    Log.i('Shared audio choice applied: ${_audioEvidenceLine(status)}');
    return status;
  }

  /// Records that the user wants none of the alternatives. The share stays
  /// video-only and nothing is offered again for this session.
  Future<SharedAudioStatus> declineSharedAudioFallback() async {
    final source = sharedAudioSource;
    if (source is! SharedAudioFallbackSource) {
      return sharedAudioStatus;
    }

    final status = await (source as SharedAudioFallbackSource)
        .declineFallback();
    lifecycle = ShareSessionLifecycle.videoOnly;
    Log.i('Shared audio choice declined: ${_audioEvidenceLine(status)}');
    return status;
  }

  Future<MediaStream?> createSharedAudioPublicationStream() async {
    final source = sharedAudioSource;
    if (source is! SharedAudioPublicationSource) {
      return null;
    }

    return (source as SharedAudioPublicationSource).createPublicationStream();
  }

  Future<void> disposeSharedAudioPublicationStream() async {
    final source = sharedAudioSource;
    if (source is SharedAudioPublicationSource) {
      await (source as SharedAudioPublicationSource).disposePublicationStream();
    }
  }

  /// Ends the share and records what the capture did.
  ///
  /// The dispose is contained because it can throw: the Windows backend's
  /// `dispose()` reports a failed native session release rather than swallowing
  /// it, and letting that escape here left `lifecycle` stuck at
  /// [ShareSessionLifecycle.stopping] and dropped the stop evidence line
  /// entirely - losing the record of a capture that had already stopped
  /// cleanly. The teardown error is still reported, just not in place of the
  /// evidence.
  Future<void> stop() async {
    lifecycle = ShareSessionLifecycle.stopping;
    final status = await sharedAudioSource.stop();
    try {
      await sharedAudioSource.dispose();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Shared-content audio dispose failed during share stop',
      );
    } finally {
      await _nativeSharedAudioCrashGuard?.clear();
      _nativeSharedAudioCrashGuard = null;
      lifecycle = ShareSessionLifecycle.stopped;
      Log.i('Shared audio stop: ${_audioEvidenceLine(status)}');
    }
  }

  /// One redacted line carrying everything a live smoke has to record.
  ///
  /// Source identity is the hash, never the window title: titles routinely
  /// carry document names, and this line is meant to be pasted into a durable
  /// QA record.
  String _audioEvidenceLine(SharedAudioStatus status) {
    return 'sourceType=${target.type.name} '
        'sourceIdHash=${shortShareSourceIdHash(target.sourceId)} '
        'pid=${target.processId ?? '?'} '
        'requested=${sharedAudioSource.requested} '
        'mode=${status.mode.name} state=${status.state.name} '
        'reason=${status.reason} '
        'format=${status.sampleRateHz}Hz/${status.numChannels}ch/'
        '${status.bitsPerSample}bit '
        'packets=${status.packetsCaptured} '
        'nonsilentBytes=${status.nonsilentBytesCaptured} '
        'elevated=${status.targetProcessElevated} '
        'elevationKnown=${status.targetElevationKnown} '
        'pcmBridge=${status.pcmBridgeSupported} '
        'lifecycle=${lifecycle.name}';
  }

  static Future<ShareSession> forDesktopCapturerSource(
    DesktopCapturerSource source, {
    required bool shareAudio,
    WindowsShareNativeBinding? nativeBinding,
  }) async {
    final binding = nativeBinding ?? IntergalacticWindowsShare.instance.binding;
    final target = await resolveShareTargetForDesktopSource(
      source,
      nativeBinding: binding,
    );
    final sharedAudioSupported = shareAudio && binding.isSupported;
    final mode = sharedAudioSupported
        ? _resolveAudioMode(target, shareAudio)
        : SharedAudioMode.none;

    final videoSource = WebrtcScreenVideoSource(target: target, source: source);

    final sharedAudioSource = sharedAudioSupported
        ? WindowsSharedAudioSource(
            nativeBinding: binding,
            target: target,
            requested: true,
            mode: mode,
          )
        : DisabledSharedAudioSource(
            reason: shareAudio
                ? 'windows_share_unsupported'
                : 'shared_audio_not_requested',
          );

    return ShareSession(
      target: target,
      videoSource: videoSource,
      sharedAudioSource: sharedAudioSource,
    );
  }
}

Future<ShareTarget> resolveShareTargetForDesktopSource(
  DesktopCapturerSource source, {
  WindowsShareNativeBinding? nativeBinding,
}) async {
  final binding = nativeBinding ?? IntergalacticWindowsShare.instance.binding;
  return binding.isSupported
      ? _ShareTargetResolver(binding).resolve(source)
      : _ShareTargetResolver.resolveVideoTarget(source);
}

class _ShareTargetResolver {
  const _ShareTargetResolver(this.nativeBinding);

  final WindowsShareNativeBinding nativeBinding;

  static ShareTarget resolveVideoTarget(DesktopCapturerSource source) {
    return ShareTarget(
      type: source.type == SourceType.Window
          ? ShareTargetType.window
          : ShareTargetType.display,
      sourceId: source.id,
      title: source.name,
    );
  }

  Future<ShareTarget> resolve(DesktopCapturerSource source) async {
    final type = source.type == SourceType.Window
        ? ShareTargetType.window
        : ShareTargetType.display;

    int? processId;
    if (type == ShareTargetType.window) {
      processId = await _resolveWindowProcessId(source);
    }

    return ShareTarget(
      type: type,
      sourceId: source.id,
      title: source.name,
      processId: processId,
    );
  }

  Future<int?> _resolveWindowProcessId(DesktopCapturerSource source) async {
    try {
      final targets = await nativeBinding.listTargets();
      if (targets.isEmpty) {
        return null;
      }

      final sourceHandle = _parseWindowHandle(source.id);
      if (sourceHandle != null) {
        for (final target in targets) {
          if (target.windowHandle == sourceHandle) {
            return target.processId;
          }
        }
      }

      final normalizedSourceName = _normalizeTitle(source.name);
      final exactMatches = targets
          .where(
            (target) => _normalizeTitle(target.title) == normalizedSourceName,
          )
          .toList(growable: false);
      if (exactMatches.length == 1) {
        return exactMatches.single.processId;
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to resolve shared-content window process',
      );
    }

    return null;
  }

  int? _parseWindowHandle(String sourceId) {
    final candidates = RegExp(
      r'0x[0-9a-fA-F]+|\d+',
    ).allMatches(sourceId).map((match) => match.group(0)).whereType<String>();

    for (final candidate in candidates) {
      final value = candidate.startsWith('0x')
          ? int.tryParse(candidate.substring(2), radix: 16)
          : int.tryParse(candidate);
      if (value != null && value > 0) {
        return value;
      }
    }

    return null;
  }

  String _normalizeTitle(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

SharedAudioMode _resolveAudioMode(ShareTarget target, bool shareAudio) {
  if (!shareAudio) {
    return SharedAudioMode.none;
  }

  return switch (target.type) {
    ShareTargetType.display => SharedAudioMode.systemLoopback,
    ShareTargetType.window =>
      target.processId == null
          ? SharedAudioMode.unavailable
          : SharedAudioMode.processTreeLoopback,
  };
}
