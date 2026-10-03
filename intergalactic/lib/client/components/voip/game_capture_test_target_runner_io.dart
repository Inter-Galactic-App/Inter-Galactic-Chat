import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/components/voip/stream_test_runner.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:path/path.dart' as path;

GameCaptureTestTargetLauncher createDefaultGameCaptureTestTargetLauncher() {
  return const GameCaptureTestTargetLauncher();
}

/// Converts the process wait result into a truthful diagnostic status.
///
/// A negative exit code is the local timeout sentinel, not confirmation that
/// Windows has stopped the helper process.
({String status, String? reason}) gameCaptureTestTargetStopResult({
  required int exitCode,
  required bool stopRequested,
}) {
  if (exitCode == -1) {
    return (
      status: 'stop_unconfirmed',
      reason:
          'capture target did not exit after stop request; process may still be running',
    );
  }
  if (exitCode != 0) {
    return (
      status: 'stopped',
      reason: 'capture target exited with code $exitCode',
    );
  }
  return (status: stopRequested ? 'stopped' : 'completed', reason: null);
}

class GameCaptureTestTargetLauncher {
  const GameCaptureTestTargetLauncher();

  Future<GameCaptureTestTargetSession> launch(
    GameCaptureTestTargetConfig config,
  ) async {
    if (!config.enabled) {
      return GameCaptureTestTargetSession(
        GameCaptureTestTargetResult.notApplicable(
          config: config,
          reason: 'deterministic capture target was not enabled',
        ),
      );
    }
    if (!Platform.isWindows) {
      return GameCaptureTestTargetSession(
        GameCaptureTestTargetResult.notApplicable(
          config: config,
          reason: 'deterministic D3D11 capture target is Windows-only',
        ),
      );
    }
    final executablePath = await _resolveExecutablePath(
      config.executablePathOverride,
    );
    if (executablePath == null) {
      return GameCaptureTestTargetSession(
        GameCaptureTestTargetResult.unavailable(
          config: config,
          reason: 'InterGalacticCaptureTarget.exe was not found',
        ),
      );
    }

    final outputDirectory = await _resolveOutputDirectory(config);
    await Directory(outputDirectory).create(recursive: true);

    final args = [
      '--width',
      '${config.width}',
      '--height',
      '${config.height}',
      '--mode',
      config.windowMode,
      '--scene',
      config.scene,
      '--fps',
      config.fps,
      '--title',
      config.title,
      '--output-dir',
      outputDirectory,
      if (config.duration.inMilliseconds > 0) ...[
        '--duration-ms',
        '${config.duration.inMilliseconds}',
      ],
    ];

    try {
      final process = await Process.start(executablePath, args);
      // Let the Win32 window and first periodic diagnostic write begin before
      // source enumeration tries to find the window title.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return GameCaptureTestTargetSession._(
        process: process,
        launchResult: GameCaptureTestTargetResult.launched(
          config: config,
          processId: process.pid,
          executablePath: executablePath,
          outputDirectoryPath: outputDirectory,
        ),
      );
    } catch (error) {
      return GameCaptureTestTargetSession(
        GameCaptureTestTargetResult.unavailable(
          config: config,
          reason: 'failed to launch InterGalacticCaptureTarget.exe: $error',
          executablePath: executablePath,
        ),
      );
    }
  }

  Future<String?> _resolveExecutablePath(String? override) async {
    final candidates = <String>[
      if (override != null && override.trim().isNotEmpty) override,
      path.join(
        path.dirname(Platform.resolvedExecutable),
        'InterGalacticCaptureTarget.exe',
      ),
      ..._repoCandidatePaths(Directory.current.path),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Iterable<String> _repoCandidatePaths(String start) sync* {
    var current = Directory(start);
    for (var i = 0; i < 7; i++) {
      yield path.join(
        current.path,
        'tools',
        'game-capture-target',
        'build',
        'Debug',
        'InterGalacticCaptureTarget.exe',
      );
      yield path.join(
        current.path,
        '..',
        '..',
        '..',
        'tools',
        'game-capture-target',
        'build',
        'Debug',
        'InterGalacticCaptureTarget.exe',
      );
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
  }

  Future<String> _resolveOutputDirectory(
    GameCaptureTestTargetConfig config,
  ) async {
    final root = config.outputRootOverride?.trim().isNotEmpty == true
        ? config.outputRootOverride!.trim()
        : path.join(
            await AppConfig.getLogDirectoryPath(),
            'stream-tests',
            'capture-targets',
          );
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return path.join(root, 'capture-target-$stamp');
  }
}

Future<({int exitCode, bool stopRequested})> _waitForExitOrStop(
  Process process,
) async {
  final exitCode = process.exitCode;
  try {
    return (
      exitCode: await exitCode.timeout(const Duration(milliseconds: 250)),
      stopRequested: false,
    );
  } on TimeoutException {
    // Windows ignores the requested signal, so there is no stronger kill step.
    process.kill(ProcessSignal.sigterm);
  }

  try {
    return (
      exitCode: await exitCode.timeout(const Duration(seconds: 2)),
      stopRequested: true,
    );
  } on TimeoutException {
    return (exitCode: -1, stopRequested: true);
  }
}

class GameCaptureTestTargetSession {
  const GameCaptureTestTargetSession(this.launchResult) : _process = null;

  const GameCaptureTestTargetSession._({
    required Process process,
    required this.launchResult,
  }) : _process = process;

  final Process? _process;
  final GameCaptureTestTargetResult launchResult;

  Future<GameCaptureTestTargetResult> refreshDiagnostics() async {
    return launchResult.withDiagnostics(
      await _readDiagnostics(wait: const Duration(milliseconds: 250)),
    );
  }

  Future<GameCaptureTestTargetResult> stopAndCollect() async {
    final beforeStop = await _readDiagnostics(
      wait: const Duration(milliseconds: 700),
    );
    final process = _process;
    if (process == null) {
      return launchResult.withDiagnostics(beforeStop);
    }
    var status = 'completed';
    var reason = launchResult.reason;
    try {
      final exitResult = await _waitForExitOrStop(process);
      final result = gameCaptureTestTargetStopResult(
        exitCode: exitResult.exitCode,
        stopRequested: exitResult.stopRequested,
      );
      status = result.status;
      reason = result.reason ?? reason;
    } catch (error) {
      status = 'stop_failed';
      reason = 'capture target stop failed: $error';
    }
    final afterStop = await _readDiagnostics(
      wait: const Duration(milliseconds: 500),
    );
    return launchResult.withDiagnostics(
      afterStop ?? beforeStop,
      status: status,
      reason: reason,
    );
  }

  Future<Map<String, Object?>?> _readDiagnostics({
    required Duration wait,
  }) async {
    final dir = launchResult.outputDirectoryPath;
    if (dir == null || dir.isEmpty) {
      return null;
    }
    final file = File(path.join(dir, 'capture-target.json'));
    final deadline = DateTime.now().add(wait);
    while (true) {
      if (await file.exists()) {
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, Object?>) {
            return decoded;
          }
          if (decoded is Map) {
            return decoded.map((key, value) => MapEntry(key.toString(), value));
          }
        } catch (_) {
          // The capture target may be mid-write; keep polling until timeout.
        }
      }
      if (!DateTime.now().isBefore(deadline)) {
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
}
