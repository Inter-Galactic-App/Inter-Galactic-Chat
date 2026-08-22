import 'shared_audio_backend.dart';
import 'shared_audio_capability.dart';

/// A concrete alternative the user can be offered after their first choice
/// turns out to be unavailable.
class SharedAudioFallbackOption {
  const SharedAudioFallbackOption({
    required this.mode,
    required this.label,
    this.device,
    this.warning = '',
    this.excludesOwnCallAudio = false,
  });

  final SharedAudioCaptureMode mode;
  final String label;

  /// Set for [SharedAudioCaptureMode.selectedDevice] offers.
  final SharedAudioDevice? device;

  /// Shown before the user commits. Empty when there is nothing to warn about.
  final String warning;

  /// False means starting this option will re-capture Inter Galactic's own
  /// received call audio.
  final bool excludesOwnCallAudio;

  SharedAudioRequest applyTo(SharedAudioRequest request) =>
      request.copyWith(mode: mode, deviceId: device?.id ?? '');
}

/// What the coordinator decided should happen next.
enum SharedAudioPlanKind {
  /// The requested mode is available; start it.
  ready,

  /// The requested mode is not available. [SharedAudioPlan.options] must be
  /// presented and an explicit choice made before anything starts.
  needsUserChoice,

  /// Nothing can carry audio. The share proceeds video-only.
  unavailable,
}

class SharedAudioPlan {
  const SharedAudioPlan({
    required this.kind,
    required this.request,
    required this.report,
    this.blockedReason,
    this.blockedDetail = '',
    this.nativeErrorCode,
    this.failureStage,
    this.options = const [],
    this.warning = '',
  });

  final SharedAudioPlanKind kind;
  final SharedAudioRequest request;
  final SharedAudioCapabilityReport report;

  /// Why the requested mode is not available.
  final SharedAudioUnavailableReason? blockedReason;
  final String blockedDetail;
  final String? nativeErrorCode;
  final String? failureStage;

  /// Alternatives, best first. Always ends with a "no shared audio" option.
  final List<SharedAudioFallbackOption> options;

  /// Warning covering the offered alternatives as a group.
  final String warning;

  bool get isReady => kind == SharedAudioPlanKind.ready;
}

/// Result of a consented start.
class SharedAudioOutcome {
  const SharedAudioOutcome({
    required this.result,
    required this.telemetry,
    this.followUpPlan,
  });

  final SharedAudioStartResult result;
  final SharedAudioTelemetry telemetry;

  /// Populated when the start failed and alternatives remain. Never applied
  /// automatically.
  final SharedAudioPlan? followUpPlan;

  bool get started => result.started;
}

/// Warning shown before any mode that can pick up more than the shared app.
const String kSharedAudioBroadCaptureWarning =
    'This shares every sound playing on your computer, not just the app you '
    'picked. Notifications, other calls, and anything else playing will be '
    'heard by everyone in the call.';

/// Shown when the running capture cannot keep our own call audio out.
const String kSharedAudioEchoWarning =
    'This also re-captures the voices of people in this call, which can cause '
    'echo for them.';

/// Drives shared audio across platforms: probe capabilities, decide whether the
/// requested mode can run, and - when it cannot - produce alternatives for the
/// user to choose from.
///
/// The coordinator never substitutes a mode on the user's behalf. A failed
/// selected-application capture yields a [SharedAudioPlan] with options, and
/// the caller must come back with an explicit choice.
class SharedAudioCoordinator {
  SharedAudioCoordinator({
    required SharedAudioBackend backend,
    void Function(String message)? logSink,
  }) : _backend = backend,
       _logSink = logSink;

  final SharedAudioBackend _backend;
  final void Function(String message)? _logSink;

  SharedAudioCapabilityReport? _lastReport;

  SharedAudioCapabilityReport? get lastReport => _lastReport;

  /// Probes the platform and decides what to do with [request].
  Future<SharedAudioPlan> plan(SharedAudioRequest request) async {
    final report = await _backend.probe(request);
    _lastReport = report;

    if (request.mode == SharedAudioCaptureMode.none) {
      return SharedAudioPlan(
        kind: SharedAudioPlanKind.unavailable,
        request: request,
        report: report,
        blockedReason: SharedAudioUnavailableReason.notRequested,
      );
    }

    final availability = report.availabilityOf(request.mode);
    if (availability.available) {
      return SharedAudioPlan(
        kind: SharedAudioPlanKind.ready,
        request: request,
        report: report,
        warning: _warningFor(availability),
      );
    }

    final options = _buildOptions(report, exclude: request.mode);
    return SharedAudioPlan(
      // A lone "no shared audio" option is not a choice worth interrupting for.
      kind: options.length > 1
          ? SharedAudioPlanKind.needsUserChoice
          : SharedAudioPlanKind.unavailable,
      request: request,
      report: report,
      blockedReason: availability.reason,
      blockedDetail: availability.detail,
      nativeErrorCode: availability.nativeErrorCode,
      failureStage: availability.failureStage,
      options: options,
      warning: options.any((option) => option.warning.isNotEmpty)
          ? kSharedAudioBroadCaptureWarning
          : '',
    );
  }

  /// Starts [request] exactly as given. Call only after [plan] returned
  /// [SharedAudioPlanKind.ready], or after the user picked a
  /// [SharedAudioFallbackOption].
  ///
  /// On failure this returns a [SharedAudioOutcome] whose [
  /// SharedAudioOutcome.followUpPlan] holds the remaining alternatives; it does
  /// not retry in a different mode.
  Future<SharedAudioOutcome> start(SharedAudioRequest request) async {
    final result = await _backend.start(request);
    final report = _lastReport;

    final telemetry = SharedAudioTelemetry(
      platform: _backend.platform,
      backend: result.backend,
      requestedMode: request.mode,
      selectedMode: result.started ? result.mode : null,
      selectedSource: result.selectedSourceLabel,
      fallbackReason: result.started ? null : result.reason,
      nativeErrorCode: result.nativeErrorCode,
      failureStage: result.failureStage,
      osBuildLabel: report?.osBuildLabel ?? '',
    );
    _log(telemetry);

    if (result.started) {
      return SharedAudioOutcome(result: result, telemetry: telemetry);
    }

    // Re-probe: a runtime failure can change what is still on the table.
    final followUp = await plan(request);
    final options = _buildOptions(followUp.report, exclude: request.mode);

    return SharedAudioOutcome(
      result: result,
      telemetry: telemetry,
      followUpPlan: SharedAudioPlan(
        kind: options.length > 1
            ? SharedAudioPlanKind.needsUserChoice
            : SharedAudioPlanKind.unavailable,
        request: request,
        report: followUp.report,
        blockedReason: result.reason,
        blockedDetail: result.detail,
        nativeErrorCode: result.nativeErrorCode,
        failureStage: result.failureStage,
        options: options,
        warning: options.any((option) => option.warning.isNotEmpty)
            ? kSharedAudioBroadCaptureWarning
            : '',
      ),
    );
  }

  Future<void> stop() => _backend.stop();

  Future<void> dispose() => _backend.dispose();

  /// Builds the offer list in preference order: keep as much isolation as
  /// possible first, then broader capture, then virtual routing, then silence.
  List<SharedAudioFallbackOption> _buildOptions(
    SharedAudioCapabilityReport report, {
    required SharedAudioCaptureMode exclude,
  }) {
    final options = <SharedAudioFallbackOption>[];

    for (final mode in const [
      SharedAudioCaptureMode.selectedApplication,
      SharedAudioCaptureMode.desktopAudio,
    ]) {
      if (mode == exclude) {
        continue;
      }

      final availability = report.availabilityOf(mode);
      if (!availability.available) {
        continue;
      }

      options.add(
        SharedAudioFallbackOption(
          mode: mode,
          label: mode == SharedAudioCaptureMode.desktopAudio
              ? 'Share all audio from this computer'
              : mode.label,
          warning: _warningFor(availability),
          excludesOwnCallAudio: availability.canExcludeOwnCallAudio,
        ),
      );
    }

    // Virtual devices are an advanced routing choice, offered only when one is
    // already installed. Inter Galactic never installs or switches devices.
    if (exclude != SharedAudioCaptureMode.selectedDevice &&
        report.isAvailable(SharedAudioCaptureMode.selectedDevice)) {
      final availability = report.availabilityOf(
        SharedAudioCaptureMode.selectedDevice,
      );
      for (final device in report.virtualDevices.where(
        (device) => device.isCapture,
      )) {
        options.add(
          SharedAudioFallbackOption(
            mode: SharedAudioCaptureMode.selectedDevice,
            device: device,
            label: device.virtualFamilyLabel.isEmpty
                ? 'Capture from ${device.name}'
                : 'Capture from ${device.name} (${device.virtualFamilyLabel})',
            warning: _warningFor(availability),
            excludesOwnCallAudio: availability.canExcludeOwnCallAudio,
          ),
        );
      }
    }

    options.add(
      const SharedAudioFallbackOption(
        mode: SharedAudioCaptureMode.none,
        label: 'Continue without shared audio',
        excludesOwnCallAudio: true,
      ),
    );

    return options;
  }

  String _warningFor(SharedAudioModeAvailability availability) {
    final parts = <String>[
      if (availability.mayIncludeOtherApplications)
        kSharedAudioBroadCaptureWarning,
      if (!availability.canExcludeOwnCallAudio &&
          availability.mode != SharedAudioCaptureMode.none)
        kSharedAudioEchoWarning,
    ];
    return parts.join(' ');
  }

  void _log(SharedAudioTelemetry telemetry) {
    _logSink?.call('Shared audio: ${telemetry.toLogLine()}');
  }
}
