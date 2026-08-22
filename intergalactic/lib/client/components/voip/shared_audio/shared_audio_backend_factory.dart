import 'dart:io';

import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

import 'pending_shared_audio_backends.dart';
import 'shared_audio_backend.dart';
import 'shared_audio_capability.dart';
import 'windows_shared_audio_backend.dart';

/// Platform with no desktop capture surface at all (mobile, web).
class UnsupportedPlatformSharedAudioBackend
    extends UnimplementedSharedAudioBackend {
  const UnsupportedPlatformSharedAudioBackend(this.platform);

  @override
  final String platform;

  @override
  SharedAudioBackendKind get kind => SharedAudioBackendKind.none;

  @override
  String get plannedMechanism => 'none';
}

/// Selects the backend for the running platform.
///
/// This is the only place the platform is branched on, and it chooses *which
/// backend answers*, never whether a mode is supported - that is always the
/// backend's runtime probe.
SharedAudioBackend createSharedAudioBackend({
  WindowsShareNativeBinding? windowsBinding,
}) {
  if (Platform.isWindows) {
    return WindowsSharedAudioBackend(
      binding: windowsBinding ?? IntergalacticWindowsShare.instance.binding,
    );
  }

  if (Platform.isMacOS) {
    return const MacosSharedAudioBackend();
  }

  if (Platform.isLinux) {
    return const LinuxSharedAudioBackend();
  }

  return UnsupportedPlatformSharedAudioBackend(Platform.operatingSystem);
}
