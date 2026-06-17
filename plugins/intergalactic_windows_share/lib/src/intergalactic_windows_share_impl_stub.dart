import 'intergalactic_windows_share_interface.dart';

WindowsShareNativeBinding createWindowsShareNativeBinding() {
  return _StubWindowsShareNativeBinding();
}

class _StubWindowsShareNativeBinding implements WindowsShareNativeBinding {
  @override
  bool get isSupported => false;

  @override
  Future<int> createSession({
    required WindowsShareTargetType targetType,
    required WindowsSharedAudioMode audioMode,
    int? processId,
    required bool requestSharedAudio,
  }) async {
    return 0;
  }

  @override
  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(
      int sessionId) async {
    return WindowsSharedAudioStreamInfo.unavailable(sessionId: sessionId);
  }

  @override
  Future<void> disposeSharedAudioStream(int sessionId) async {}

  @override
  Future<void> disposeSession(int sessionId) async {}

  @override
  Future<WindowsShareCapabilities> getCapabilities() async {
    return WindowsShareCapabilities.unavailable();
  }

  @override
  Future<WindowsShareSessionStatus> getSessionStatus(int sessionId) async {
    return WindowsShareSessionStatus.unavailable(sessionId: sessionId);
  }

  @override
  Future<List<WindowsShareTargetInfo>> listTargets() async {
    return const [];
  }

  @override
  Future<WindowsShareSessionStatus> startSharedAudio(int sessionId) async {
    return WindowsShareSessionStatus.unavailable(sessionId: sessionId);
  }

  @override
  Future<WindowsShareSessionStatus> stopSharedAudio(int sessionId) async {
    return WindowsShareSessionStatus.unavailable(
      sessionId: sessionId,
      reason: 'unsupported_platform',
    );
  }
}
