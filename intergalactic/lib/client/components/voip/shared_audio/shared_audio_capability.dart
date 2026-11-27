/// Platform-neutral vocabulary for desktop shared-audio capture.
///
/// Nothing in this file names a platform API. The general UI selects a
/// [SharedAudioCaptureMode] and reads [SharedAudioModeAvailability]; which
/// native mechanism serves that mode is a backend concern, surfaced only in
/// diagnostics via [SharedAudioBackendKind].
library;

/// What the user asked to share, in their terms.
enum SharedAudioCaptureMode {
  /// Audio produced by the application being shared, and nothing else.
  selectedApplication,

  /// Everything currently playing on the machine.
  desktopAudio,

  /// A specific audio device the user picked, typically a virtual cable they
  /// have routed themselves.
  selectedDevice,

  /// Screen share carries no audio.
  none,
}

extension SharedAudioCaptureModeLabel on SharedAudioCaptureMode {
  /// Short user-facing label. Deliberately free of platform API names.
  String get label => switch (this) {
    SharedAudioCaptureMode.selectedApplication => 'Selected application audio',
    SharedAudioCaptureMode.desktopAudio => 'Desktop/system audio',
    SharedAudioCaptureMode.selectedDevice => 'Selected audio device',
    SharedAudioCaptureMode.none => 'No shared audio',
  };

  /// True when the mode can pick up sound from applications other than the one
  /// being shared. Drives the pre-fallback warning.
  bool get mayIncludeOtherApplications => switch (this) {
    SharedAudioCaptureMode.desktopAudio => true,
    SharedAudioCaptureMode.selectedDevice => true,
    SharedAudioCaptureMode.selectedApplication => false,
    SharedAudioCaptureMode.none => false,
  };
}

/// Which native mechanism is serving a mode. Diagnostics and logging only -
/// never render this in the general UI.
enum SharedAudioBackendKind {
  none,
  windowsProcessLoopback,
  windowsEndpointLoopback,
  windowsDeviceCapture,
  macosScreenCaptureKit,
  linuxPipeWirePortal,
}

extension SharedAudioBackendKindLabel on SharedAudioBackendKind {
  String get logLabel => switch (this) {
    SharedAudioBackendKind.none => 'none',
    SharedAudioBackendKind.windowsProcessLoopback => 'windows.process_loopback',
    SharedAudioBackendKind.windowsEndpointLoopback =>
      'windows.endpoint_loopback',
    SharedAudioBackendKind.windowsDeviceCapture => 'windows.device_capture',
    SharedAudioBackendKind.macosScreenCaptureKit => 'macos.screencapturekit',
    SharedAudioBackendKind.linuxPipeWirePortal => 'linux.pipewire_portal',
  };
}

/// Structured cause for a mode being unavailable. Callers switch on this rather
/// than matching reason strings.
enum SharedAudioUnavailableReason {
  /// The user did not ask for shared audio.
  notRequested,

  /// No shared-audio backend is implemented for this platform in this build.
  backendNotImplemented,

  /// A backend exists but its native library could not be loaded.
  backendUnavailable,

  /// The OS refused the capture activation at runtime. This is a *measured*
  /// result, never an inference from the OS version.
  osRefusedActivation,

  /// The share target's owning process could not be identified.
  targetProcessUnresolved,

  /// The target runs at a higher integrity level than this app, so the OS
  /// blocks capturing its audio.
  targetNotCapturable,

  /// No usable capture or render endpoint exists.
  noCaptureDevice,

  /// Selected-device mode was offered but nothing resembling a virtual audio
  /// device was found.
  noVirtualDeviceDetected,

  /// The OS consent prompt was denied, or permission was never granted.
  permissionDenied,

  /// The user was offered this mode and turned it down.
  userDeclined,

  unknown,
}

extension SharedAudioUnavailableReasonLabel on SharedAudioUnavailableReason {
  /// Stable snake_case token for logs and bug reports.
  String get logLabel => switch (this) {
    SharedAudioUnavailableReason.notRequested => 'not_requested',
    SharedAudioUnavailableReason.backendNotImplemented =>
      'backend_not_implemented',
    SharedAudioUnavailableReason.backendUnavailable => 'backend_unavailable',
    SharedAudioUnavailableReason.osRefusedActivation => 'os_refused_activation',
    SharedAudioUnavailableReason.targetProcessUnresolved =>
      'target_process_unresolved',
    SharedAudioUnavailableReason.targetNotCapturable => 'target_not_capturable',
    SharedAudioUnavailableReason.noCaptureDevice => 'no_capture_device',
    SharedAudioUnavailableReason.noVirtualDeviceDetected =>
      'no_virtual_device_detected',
    SharedAudioUnavailableReason.permissionDenied => 'permission_denied',
    SharedAudioUnavailableReason.userDeclined => 'user_declined',
    SharedAudioUnavailableReason.unknown => 'unknown',
  };
}

/// A selectable audio endpoint.
class SharedAudioDevice {
  const SharedAudioDevice({
    required this.id,
    required this.name,
    required this.isCapture,
    this.isDefault = false,
    this.isLikelyVirtual = false,
    this.virtualFamily = '',
  });

  final String id;
  final String name;

  /// True for input endpoints. A virtual cable's *output* side is a capture
  /// endpoint, which is what selected-device mode reads from.
  final bool isCapture;

  final bool isDefault;

  /// True when the name matches a known virtual audio cable. Detection is
  /// advisory: it surfaces the device as an advanced routing choice, and never
  /// installs or reconfigures anything.
  final bool isLikelyVirtual;

  /// `vb-cable`, `voicemeeter`, `vac`, or empty.
  final String virtualFamily;

  /// Vendor-facing name for the detected family, for advanced-settings copy.
  String get virtualFamilyLabel => switch (virtualFamily) {
    'vb-cable' => 'VB-CABLE',
    'voicemeeter' => 'VoiceMeeter',
    'vac' => 'Virtual Audio Cable',
    _ => '',
  };
}

/// Whether one mode can run right now, and if not, precisely why.
class SharedAudioModeAvailability {
  const SharedAudioModeAvailability({
    required this.mode,
    required this.available,
    required this.backend,
    this.reason,
    this.detail = '',
    this.nativeErrorCode,
    this.failureStage,
    this.canExcludeOwnCallAudio = false,
  });

  const SharedAudioModeAvailability.unavailable({
    required this.mode,
    required SharedAudioUnavailableReason this.reason,
    this.detail = '',
    this.backend = SharedAudioBackendKind.none,
    this.nativeErrorCode,
    this.failureStage,
  }) : available = false,
       canExcludeOwnCallAudio = false;

  final SharedAudioCaptureMode mode;
  final bool available;

  /// Which mechanism would serve this mode. Diagnostics only.
  final SharedAudioBackendKind backend;

  /// Null when [available] is true.
  final SharedAudioUnavailableReason? reason;

  /// Human-readable elaboration, safe to show in diagnostics.
  final String detail;

  /// Platform error code (`0x887c0004`, an `OSStatus`, an errno name). Recorded
  /// so an unavailability can be attributed without reproducing it.
  final String? nativeErrorCode;

  /// Which step failed, e.g. `activation`, `clientInitialize`.
  final String? failureStage;

  /// True when this mode can keep Inter Galactic's own received call audio out
  /// of the capture. When false, callers must surface the echo/privacy
  /// limitation before starting.
  final bool canExcludeOwnCallAudio;

  /// True when starting this mode would capture sound from applications beyond
  /// the shared one, including notifications and other calls.
  bool get mayIncludeOtherApplications => mode.mayIncludeOtherApplications;
}

/// The full runtime picture for one platform, produced by probing rather than
/// by inspecting an OS name or version.
class SharedAudioCapabilityReport {
  const SharedAudioCapabilityReport({
    required this.platform,
    required this.backend,
    required this.modes,
    this.devices = const [],
    this.osBuildLabel = '',
  });

  /// `windows`, `macos`, `linux`, or `unsupported`.
  final String platform;

  /// The primary backend that answered the probe.
  final SharedAudioBackendKind backend;

  final List<SharedAudioModeAvailability> modes;
  final List<SharedAudioDevice> devices;

  /// Reported for diagnostics only. Never used to decide availability.
  final String osBuildLabel;

  SharedAudioModeAvailability availabilityOf(SharedAudioCaptureMode mode) {
    for (final entry in modes) {
      if (entry.mode == mode) {
        return entry;
      }
    }

    return SharedAudioModeAvailability.unavailable(
      mode: mode,
      reason: SharedAudioUnavailableReason.backendNotImplemented,
      detail: 'No capability was reported for ${mode.label}.',
    );
  }

  bool isAvailable(SharedAudioCaptureMode mode) =>
      availabilityOf(mode).available;

  /// Modes the user can actually pick, in preference order. [
  /// SharedAudioCaptureMode.none] is always last and always present.
  List<SharedAudioCaptureMode> get availableModes => <SharedAudioCaptureMode>[
    for (final mode in const [
      SharedAudioCaptureMode.selectedApplication,
      SharedAudioCaptureMode.desktopAudio,
      SharedAudioCaptureMode.selectedDevice,
    ])
      if (isAvailable(mode)) mode,
    SharedAudioCaptureMode.none,
  ];

  /// Endpoints that look like virtual audio cables, offered as an advanced
  /// routing choice only.
  List<SharedAudioDevice> get virtualDevices =>
      devices.where((device) => device.isLikelyVirtual).toList(growable: false);
}
