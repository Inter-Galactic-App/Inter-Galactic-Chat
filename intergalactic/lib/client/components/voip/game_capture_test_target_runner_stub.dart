import 'package:intergalactic/client/components/voip/stream_test_runner.dart';

GameCaptureTestTargetLauncher createDefaultGameCaptureTestTargetLauncher() {
  return const GameCaptureTestTargetLauncher();
}

class GameCaptureTestTargetLauncher {
  const GameCaptureTestTargetLauncher();

  Future<GameCaptureTestTargetSession> launch(
    GameCaptureTestTargetConfig config,
  ) async {
    return GameCaptureTestTargetSession(
      GameCaptureTestTargetResult.notApplicable(
        config: config,
        reason: 'D3D11 capture target launcher is only available on Windows',
      ),
    );
  }
}

class GameCaptureTestTargetSession {
  const GameCaptureTestTargetSession(this.launchResult);

  final GameCaptureTestTargetResult launchResult;

  Future<GameCaptureTestTargetResult> refreshDiagnostics() async {
    return launchResult;
  }

  Future<GameCaptureTestTargetResult> stopAndCollect() async {
    return launchResult;
  }
}
