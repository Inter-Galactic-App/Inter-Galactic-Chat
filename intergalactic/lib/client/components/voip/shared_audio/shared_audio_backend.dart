import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'shared_audio_capability.dart';

/// What the caller wants to capture, before any capability check.
class SharedAudioRequest {
  const SharedAudioRequest({
    required this.mode,
    this.targetProcessId,
    this.targetTitle = '',
    this.deviceId = '',
    this.sharingWholeScreen = false,
  });

  final SharedAudioCaptureMode mode;

  /// Owning process of the shared window, when known.
  final int? targetProcessId;

  final String targetTitle;

  /// Endpoint for [SharedAudioCaptureMode.selectedDevice].
  final String deviceId;

  /// True when the video share is a whole display rather than one window.
  final bool sharingWholeScreen;

  SharedAudioRequest copyWith({
    SharedAudioCaptureMode? mode,
    String? deviceId,
  }) {
    return SharedAudioRequest(
      mode: mode ?? this.mode,
      targetProcessId: targetProcessId,
      targetTitle: targetTitle,
      deviceId: deviceId ?? this.deviceId,
      sharingWholeScreen: sharingWholeScreen,
    );
  }
}

/// Outcome of actually starting a capture.
class SharedAudioStartResult {
  const SharedAudioStartResult({
    required this.started,
    required this.mode,
    required this.backend,
    this.reason,
    this.detail = '',
    this.nativeErrorCode,
    this.failureStage,
    this.selectedSourceLabel = '',
    this.excludesOwnCallAudio = false,
  });

  const SharedAudioStartResult.failed({
    required this.mode,
    required this.backend,
    required SharedAudioUnavailableReason this.reason,
    this.detail = '',
    this.nativeErrorCode,
    this.failureStage,
    this.selectedSourceLabel = '',
  }) : started = false,
       excludesOwnCallAudio = false;

  final bool started;
  final SharedAudioCaptureMode mode;
  final SharedAudioBackendKind backend;
  final SharedAudioUnavailableReason? reason;
  final String detail;
  final String? nativeErrorCode;
  final String? failureStage;

  /// Which window, display, or device the capture bound to.
  final String selectedSourceLabel;

  /// True when the running capture keeps our own received call audio out.
  final bool excludesOwnCallAudio;
}

/// Where a capture is in its lifecycle.
///
/// Kept as a distinct state rather than a boolean because callers distinguish
/// "never asked for", "asked for and refused", "broke", and "ended cleanly" -
/// collapsing those loses the difference between a capture that failed and one
/// the user turned off.
enum SharedAudioCaptureState {
  /// Audio was not requested.
  disabled,

  /// Requested and coming up.
  starting,

  /// Running.
  active,

  /// The platform cannot serve this request at all.
  unavailable,

  /// It was attempted and broke.
  failed,

  /// It ran and has been stopped.
  stopped,
}

/// What a capture is doing right now, as raw facts rather than as advice.
///
/// The backend reports observations; deciding what to tell the user about them
/// stays with the caller, so a platform backend never has to carry user-facing
/// copy. Everything needed to derive the existing shared-audio advisories is
/// here: whether the target can be captured at all, and whether a running
/// capture is producing anything audible.
class SharedAudioCaptureStatus {
  const SharedAudioCaptureStatus({
    required this.mode,
    required this.backend,
    required this.state,
    this.reason,
    this.nativeReason = '',
    this.detail = '',
    this.nativeErrorCode,
    this.failureStage,
    this.sampleRateHz = 0,
    this.numChannels = 0,
    this.bitsPerSample = 0,
    this.packetsCaptured = 0,
    this.framesCaptured = 0,
    this.bytesCaptured = 0,
    this.nonsilentBytesCaptured = 0,
    this.targetNotCapturable = false,
    this.targetCapturabilityKnown = false,
    this.canPublish = false,
  });

  /// Nothing is capturing and nothing failed - the state before a first start
  /// and after a clean stop.
  const SharedAudioCaptureStatus.inactive({
    this.mode = SharedAudioCaptureMode.none,
    this.backend = SharedAudioBackendKind.none,
    this.state = SharedAudioCaptureState.disabled,
    this.reason,
    this.nativeReason = '',
    this.detail = '',
  }) : nativeErrorCode = null,
       failureStage = null,
       sampleRateHz = 0,
       numChannels = 0,
       bitsPerSample = 0,
       packetsCaptured = 0,
       framesCaptured = 0,
       bytesCaptured = 0,
       nonsilentBytesCaptured = 0,
       targetNotCapturable = false,
       targetCapturabilityKnown = false,
       canPublish = false;

  final SharedAudioCaptureMode mode;
  final SharedAudioBackendKind backend;
  final SharedAudioCaptureState state;

  /// True only while the capture is running.
  bool get capturing => state == SharedAudioCaptureState.active;

  /// Why the capture is not running, as a structured cause.
  final SharedAudioUnavailableReason? reason;

  /// The platform's own reason token, verbatim.
  ///
  /// Carried alongside [reason] rather than folded into it because callers
  /// match on the exact platform string - the shared-audio advisory keys off
  /// `process_loopback_activation_failed` - and a structured enum cannot round
  /// trip a token the platform may add tomorrow.
  final String nativeReason;

  final String detail;
  final String? nativeErrorCode;
  final String? failureStage;

  /// Negotiated capture format, reported in the developer diagnostics panel.
  final int sampleRateHz;
  final int numChannels;
  final int bitsPerSample;

  /// Buffers delivered by the capture so far.
  final int packetsCaptured;
  final int framesCaptured;
  final int bytesCaptured;

  /// Of those, the bytes that were not flagged silent. Staying at zero while
  /// [packetsCaptured] climbs is the signature of a capture that is running but
  /// hearing nothing.
  final int nonsilentBytesCaptured;

  /// The OS will not let us capture this target's audio - on Windows, a target
  /// running at a higher integrity level than we are.
  final bool targetNotCapturable;

  /// Whether [targetNotCapturable] was positively determined. False means it is
  /// a best-effort default and callers should rely on the silence signal.
  final bool targetCapturabilityKnown;

  /// Whether this capture can be published to the call.
  final bool canPublish;

  /// The same observation, with the capture no longer running.
  ///
  /// Keeps the diagnosis - why it stopped, whether the target was capturable,
  /// what the platform said - because that is exactly what the UI still needs
  /// to show after a capture is torn down. Only [capturing] changes.
  SharedAudioCaptureStatus asStopped() {
    return SharedAudioCaptureStatus(
      mode: mode,
      backend: backend,
      // A capture that never got past starting ended without running; one that
      // was active ended cleanly. Anything already terminal keeps its state.
      state: switch (state) {
        SharedAudioCaptureState.active ||
        SharedAudioCaptureState.starting => SharedAudioCaptureState.stopped,
        final terminal => terminal,
      },
      reason: reason,
      nativeReason: nativeReason,
      detail: detail,
      nativeErrorCode: nativeErrorCode,
      failureStage: failureStage,
      sampleRateHz: sampleRateHz,
      numChannels: numChannels,
      bitsPerSample: bitsPerSample,
      packetsCaptured: packetsCaptured,
      framesCaptured: framesCaptured,
      bytesCaptured: bytesCaptured,
      nonsilentBytesCaptured: nonsilentBytesCaptured,
      targetNotCapturable: targetNotCapturable,
      targetCapturabilityKnown: targetCapturabilityKnown,
      canPublish: canPublish,
    );
  }

  /// True once enough buffers have arrived, all of them silent, to conclude the
  /// source's audio is not reaching us.
  ///
  /// Requires [packetsCaptured] to have accumulated, so it is only meaningful
  /// against a status refreshed some way into the capture - the snapshot taken
  /// at start time will never satisfy it.
  bool get isCapturingOnlySilence =>
      capturing &&
      packetsCaptured >= kSharedAudioSilenceEvidencePackets &&
      nonsilentBytesCaptured == 0;
}

/// How many buffers must arrive, all silent, before a running capture is
/// treated as hearing nothing. At ~44.1kHz with event-driven ~10ms buffers this
/// is roughly two seconds - long enough to ride out a momentarily quiet source.
const int kSharedAudioSilenceEvidencePackets = 200;

/// One platform's shared-audio implementation.
///
/// Backends answer two questions: what can this machine do *right now*
/// ([probe]), and start exactly the mode that was asked for ([start]). A
/// backend must never substitute a different mode than the one requested -
/// choosing a fallback is the coordinator's job, and requires user consent.
abstract class SharedAudioBackend {
  SharedAudioBackendKind get kind;

  /// `windows`, `macos`, `linux`.
  String get platform;

  /// Measures what this machine can do. Implementations must attempt the real
  /// operation (or query live OS state); inferring support from an OS name or
  /// version string is not acceptable.
  Future<SharedAudioCapabilityReport> probe(SharedAudioRequest request);

  /// Starts capture in exactly [request]'s mode.
  Future<SharedAudioStartResult> start(SharedAudioRequest request);

  /// Last known state of the capture, without touching the platform.
  ///
  /// Synchronous because the call UI reads it while building a frame. It is a
  /// snapshot: it changes when the backend does something ([start], [stop],
  /// [dispose]) or when [refreshStatus] is called, never on its own.
  SharedAudioCaptureStatus get lastStatus;

  /// Re-reads the capture's state from the platform and updates [lastStatus].
  ///
  /// Nothing calls this on a timer today, which is why an observation that
  /// needs elapsed capture - such as
  /// [SharedAudioCaptureStatus.isCapturingOnlySilence] - cannot be true of the
  /// snapshot taken at start. A caller that wants those has to refresh.
  Future<SharedAudioCaptureStatus> refreshStatus();

  /// The media stream that publishes the running capture, or null when there is
  /// nothing to publish.
  ///
  /// The publication stream belongs to the capture session, not to the caller:
  /// a backend must tie it to the session [start] opened, and must tear it down
  /// as part of releasing that session. Returning a stream that can outlive its
  /// native session is the defect this contract exists to prevent - the stream
  /// would reference a disposed capture.
  ///
  /// Repeat calls while one capture is running return the same stream rather
  /// than opening a second.
  Future<MediaStream?> createPublicationStream();

  /// Releases the publication stream without ending the capture.
  ///
  /// Safe to call when none was created. Releasing the session releases the
  /// stream too, so callers do not have to sequence the two.
  Future<void> disposePublicationStream();

  Future<void> stop();

  Future<void> dispose();
}

/// One structured line describing a shared-audio decision.
///
/// Every field the audit asks to be logged lives here, so a capture attempt can
/// be reconstructed from a single record.
class SharedAudioTelemetry {
  const SharedAudioTelemetry({
    required this.platform,
    required this.backend,
    required this.requestedMode,
    this.selectedMode,
    this.selectedSource = '',
    this.fallbackReason,
    this.nativeErrorCode,
    this.failureStage,
    this.osBuildLabel = '',
  });

  final String platform;
  final SharedAudioBackendKind backend;
  final SharedAudioCaptureMode requestedMode;

  /// Null until a mode is actually running.
  final SharedAudioCaptureMode? selectedMode;

  /// Window title, display name, or device name the capture bound to.
  final String selectedSource;

  /// Why the selected mode differs from the requested one.
  final SharedAudioUnavailableReason? fallbackReason;

  /// HRESULT / OSStatus / errno reported by the platform.
  final String? nativeErrorCode;

  final String? failureStage;
  final String osBuildLabel;

  /// Single-line, grep-friendly rendering. Source labels can carry a window
  /// title, so they are quoted rather than left to run into the next field.
  String toLogLine() {
    final parts = <String>[
      'platform=$platform',
      'backend=${backend.logLabel}',
      'requestedMode=${requestedMode.name}',
      'selectedMode=${selectedMode?.name ?? 'none'}',
      'selectedSource="${_sanitizedSource()}"',
      'fallbackReason=${fallbackReason?.logLabel ?? 'none'}',
      'nativeError=${nativeErrorCode ?? 'none'}',
      'failureStage=${failureStage ?? 'none'}',
      if (osBuildLabel.isNotEmpty) 'osBuild=$osBuildLabel',
    ];
    return parts.join(' ');
  }

  /// A window title is user content: it can contain a document name, a URL, a
  /// contact's name, or an embedded quote or newline that breaks the one-line,
  /// quoted shape the rest of this format relies on. Bounded and escaped so a
  /// diagnostics log stays parseable and does not carry more than it needs to.
  String _sanitizedSource() {
    const maximumLength = 96;
    final collapsed = selectedSource
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll('"', "'")
        .trim();
    if (collapsed.length <= maximumLength) {
      return collapsed;
    }
    return '${collapsed.substring(0, maximumLength)}...';
  }
}
