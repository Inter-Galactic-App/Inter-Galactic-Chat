import 'src/intergalactic_windows_share_impl_stub.dart'
    if (dart.library.ffi) 'src/intergalactic_windows_share_impl_ffi.dart';
import 'src/intergalactic_windows_share_interface.dart';

export 'src/intergalactic_windows_share_interface.dart';

class IntergalacticWindowsShare {
  IntergalacticWindowsShare._(this._binding);

  static final IntergalacticWindowsShare instance = IntergalacticWindowsShare._(
    createWindowsShareNativeBinding(),
  );

  final WindowsShareNativeBinding _binding;

  WindowsShareNativeBinding get binding => _binding;

  bool get isSupported => _binding.isSupported;

  Future<WindowsShareCapabilities> getCapabilities() {
    return _binding.getCapabilities();
  }

  Future<List<WindowsShareTargetInfo>> listTargets() {
    return _binding.listTargets();
  }

  Future<int> createSession({
    required WindowsShareTargetType targetType,
    required WindowsSharedAudioMode audioMode,
    int? processId,
    required bool requestSharedAudio,
  }) {
    return _binding.createSession(
      targetType: targetType,
      audioMode: audioMode,
      processId: processId,
      requestSharedAudio: requestSharedAudio,
    );
  }

  Future<WindowsShareSessionStatus> startSharedAudio(int sessionId) {
    return _binding.startSharedAudio(sessionId);
  }

  Future<WindowsShareSessionStatus> stopSharedAudio(int sessionId) {
    return _binding.stopSharedAudio(sessionId);
  }

  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(int sessionId) {
    return _binding.createSharedAudioStream(sessionId);
  }

  Future<void> disposeSharedAudioStream(int sessionId) {
    return _binding.disposeSharedAudioStream(sessionId);
  }

  Future<WindowsShareSessionStatus> getSessionStatus(int sessionId) {
    return _binding.getSessionStatus(sessionId);
  }

  Future<void> disposeSession(int sessionId) {
    return _binding.disposeSession(sessionId);
  }
}
