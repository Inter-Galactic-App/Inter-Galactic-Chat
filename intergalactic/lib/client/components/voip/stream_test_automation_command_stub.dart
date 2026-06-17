import 'package:intergalactic/client/components/voip/stream_test_runner.dart';

class StreamTestAutomationRequest {
  const StreamTestAutomationRequest({
    required this.id,
    this.presetKeys = const ['smooth', 'balanced', 'highQuality'],
    this.duration = const Duration(seconds: 30),
    this.warmup = const Duration(seconds: 5),
    this.windowsBackendMode,
    this.compareWindowsBackends = false,
    this.forceFullFrameDirtyRegions = false,
    this.nativeFramePacingEnabled = true,
    this.dummyNv12LiveSender = false,
    this.sourceProcessId,
    this.sourceTitle,
    this.captureTarget = const GameCaptureTestTargetConfig(enabled: true),
    this.runningPath,
  });

  final String id;
  final List<String> presetKeys;
  final Duration duration;
  final Duration warmup;
  final String? windowsBackendMode;
  final bool compareWindowsBackends;
  final bool forceFullFrameDirtyRegions;
  final bool nativeFramePacingEnabled;
  final bool dummyNv12LiveSender;
  final int? sourceProcessId;
  final String? sourceTitle;
  final GameCaptureTestTargetConfig captureTarget;
  final String? runningPath;
}

class StreamTestAutomationCommandChannel {
  const StreamTestAutomationCommandChannel();

  Future<StreamTestAutomationRequest?> takePending() async => null;

  Future<void> complete(
    StreamTestAutomationRequest request, {
    String? reportPath,
    String? error,
  }) async {}

  Future<String?> requestFilePath() async => null;
}
