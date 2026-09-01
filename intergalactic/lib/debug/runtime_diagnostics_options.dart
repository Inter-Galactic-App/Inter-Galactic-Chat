class RuntimeDiagnosticsOptions {
  const RuntimeDiagnosticsOptions({
    this.debugLogs = false,
    this.webrtcStats = false,
  });

  final bool debugLogs;
  final bool webrtcStats;

  static RuntimeDiagnosticsOptions fromArgs(List<String> args) {
    return RuntimeDiagnosticsOptions(
      debugLogs: args.contains('--ig-debug-logs'),
      webrtcStats: args.contains('--ig-webrtc-stats'),
    );
  }
}
