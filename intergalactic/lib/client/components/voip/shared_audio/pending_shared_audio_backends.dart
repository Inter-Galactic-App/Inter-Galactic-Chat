import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'shared_audio_backend.dart';
import 'shared_audio_capability.dart';

/// Base for a platform whose native capture layer is not yet implemented.
///
/// These exist so the coordinator has one uniform contract on every desktop
/// platform, and so the UI shows a structured reason instead of a mode that
/// silently does nothing. They deliberately report unavailability rather than
/// pretending to capture.
///
/// A real implementation replaces the whole class; it must keep [probe]
/// measuring live OS state rather than branching on an OS version.
abstract class UnimplementedSharedAudioBackend implements SharedAudioBackend {
  const UnimplementedSharedAudioBackend();

  /// Human-readable note about what the eventual implementation will use.
  String get plannedMechanism;

  @override
  Future<SharedAudioCapabilityReport> probe(SharedAudioRequest request) async {
    return SharedAudioCapabilityReport(
      platform: platform,
      backend: SharedAudioBackendKind.none,
      modes: [
        for (final mode in const [
          SharedAudioCaptureMode.selectedApplication,
          SharedAudioCaptureMode.desktopAudio,
          SharedAudioCaptureMode.selectedDevice,
        ])
          SharedAudioModeAvailability.unavailable(
            mode: mode,
            reason: SharedAudioUnavailableReason.backendNotImplemented,
            detail:
                'Sharing audio is not available on $platform in this build. '
                'Screen sharing still works without sound.',
          ),
        const SharedAudioModeAvailability(
          mode: SharedAudioCaptureMode.none,
          available: true,
          backend: SharedAudioBackendKind.none,
          canExcludeOwnCallAudio: true,
        ),
      ],
    );
  }

  @override
  Future<SharedAudioStartResult> start(SharedAudioRequest request) async {
    return SharedAudioStartResult.failed(
      mode: request.mode,
      backend: SharedAudioBackendKind.none,
      reason: SharedAudioUnavailableReason.backendNotImplemented,
      detail: 'No shared-audio backend is implemented for $platform.',
    );
  }

  /// Nothing ever captures here, so the snapshot is permanently inactive and a
  /// refresh has nothing to re-read.
  @override
  SharedAudioCaptureStatus get lastStatus => SharedAudioCaptureStatus.inactive(
    reason: SharedAudioUnavailableReason.backendNotImplemented,
    detail: 'No shared-audio backend is implemented for $platform.',
  );

  @override
  Future<SharedAudioCaptureStatus> refreshStatus() async => lastStatus;

  /// Nothing captures, so nothing publishes. Returning null rather than
  /// throwing keeps a caller that publishes unconditionally on the video-only
  /// path instead of failing the whole share.
  @override
  Future<MediaStream?> createPublicationStream() async => null;

  @override
  Future<void> disposePublicationStream() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// macOS placeholder.
///
/// The implementation will use ScreenCaptureKit, whose content filter both
/// selects per-application audio and can exclude our own process - so
/// [SharedAudioModeAvailability.canExcludeOwnCallAudio] should be true for both
/// application and desktop modes once it lands. Availability must come from
/// building a filter and checking recording permission at runtime, not from a
/// macOS version check.
class MacosSharedAudioBackend extends UnimplementedSharedAudioBackend {
  const MacosSharedAudioBackend();

  @override
  SharedAudioBackendKind get kind =>
      SharedAudioBackendKind.macosScreenCaptureKit;

  @override
  String get platform => 'macos';

  @override
  String get plannedMechanism => 'ScreenCaptureKit';
}

/// Linux placeholder.
///
/// The implementation will go through the XDG Desktop Portal ScreenCast
/// interface with PipeWire audio streams, using the portal's own picker as the
/// consent surface. Per-application audio depends on the portal/compositor
/// advertising it, so availability must be read from the live portal
/// capabilities rather than assumed from the desktop environment name.
class LinuxSharedAudioBackend extends UnimplementedSharedAudioBackend {
  const LinuxSharedAudioBackend();

  @override
  SharedAudioBackendKind get kind => SharedAudioBackendKind.linuxPipeWirePortal;

  @override
  String get platform => 'linux';

  @override
  String get plannedMechanism => 'PipeWire via XDG Desktop Portal';
}
