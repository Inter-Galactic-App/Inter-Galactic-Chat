import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/components/voip/stream_test_runner.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:path/path.dart' as path;

GameCaptureProbeRunner createDefaultGameCaptureProbeRunner() {
  return const WindowsGameCaptureProbeRunner();
}

class WindowsGameCaptureProbeRunner implements GameCaptureProbeRunner {
  const WindowsGameCaptureProbeRunner();

  @override
  Future<GameCaptureProbeResult> run(GameCaptureProbeConfig config) async {
    if (!config.enabled) {
      return GameCaptureProbeResult.notApplicable(
        config: config,
        reason: 'game-capture probe was not enabled',
      );
    }
    if (!Platform.isWindows) {
      return GameCaptureProbeResult.notApplicable(
        config: config,
        reason: 'D3D11 game-capture probe is Windows-only',
      );
    }
    final pid = config.effectiveTargetProcessId;
    if (pid == null || pid <= 0) {
      return GameCaptureProbeResult.notApplicable(
        config: config,
        reason: 'selected source did not expose a target process id',
      );
    }

    final helperPath = await _resolveHelperPath(config.helperPathOverride);
    if (helperPath == null) {
      return GameCaptureProbeResult.unavailable(
        config: config,
        reason: 'intergalactic_game_capture_helper.exe was not found',
      );
    }

    final outputRoot = await _resolveOutputRoot(config.outputRootOverride);
    await Directory(outputRoot).create(recursive: true);
    final startedAt = DateTime.now();
    final durationMs =
        config.duration.inMilliseconds.clamp(1000, 30000).toInt();
    final maxSavedFrames = config.maxSavedFrames.clamp(0, 30).toInt();
    final hostProofFrames = config.hostProofFrames.clamp(0, 10).toInt();
    final handoffMaxWidth =
        config.publicationHandoffMaxWidth.clamp(2, 7680).toInt();
    final handoffMaxHeight =
        config.publicationHandoffMaxHeight.clamp(2, 4320).toInt();
    final handoffTargetFps =
        config.publicationHandoffTargetFps.clamp(1, 60).toInt();
    final args = [
      '--pid',
      '$pid',
      '--duration-ms',
      '$durationMs',
      '--max-saved-frames',
      '$maxSavedFrames',
      '--host-consume-frames',
      config.hostTextureConsumerEnabled ? 'true' : 'false',
      '--host-proof-frames',
      '$hostProofFrames',
      '--publication-handoff',
      config.publicationHandoffEnabled ? 'true' : 'false',
      '--publication-handoff-max-width',
      '$handoffMaxWidth',
      '--publication-handoff-max-height',
      '$handoffMaxHeight',
      '--publication-handoff-target-fps',
      '$handoffTargetFps',
      '--output-root',
      outputRoot,
    ];

    Process? process;
    var stdoutText = '';
    var stderrText = '';
    try {
      process = await Process.start(helperPath, args);
      final stdoutFuture = utf8.decodeStream(process.stdout);
      final stderrFuture = utf8.decodeStream(process.stderr);
      // The helper waits for the hook duration plus graceful stop/unload and
      // result-file writes. Keep the Dart watchdog outside that native budget
      // so reports are not killed during normal teardown.
      final timeout = Duration(milliseconds: durationMs + 20000);
      final exitCode = await _waitForExitOrTerminate(process, timeout);
      stdoutText = await stdoutFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => '',
      );
      stderrText = await stderrFuture.timeout(
        const Duration(seconds: 2),
        onTimeout: () => '',
      );

      final metadataFile = await _findLatestMetadataFile(
        outputRoot,
        startedAt: startedAt,
      );
      if (metadataFile == null) {
        return GameCaptureProbeResult.missing(
          config: config,
          reason: exitCode == -1
              ? 'helper timed out without writing metadata.json'
              : 'helper exited without writing metadata.json'
                  '${_processTextSuffix(stdoutText, stderrText)}',
          helperPath: helperPath,
          helperExitCode: exitCode,
        );
      }
      final metadata = await _readMetadata(metadataFile);
      return GameCaptureProbeResult.fromMetadata(
        config: config,
        metadata: metadata,
        resultDirectoryPath: metadataFile.parent.path,
        helperPath: helperPath,
        helperExitCode: exitCode,
      );
    } catch (error) {
      return GameCaptureProbeResult.unavailable(
        config: config,
        reason: 'failed to run game-capture helper: $error'
            '${_processTextSuffix(stdoutText, stderrText)}',
        helperPath: helperPath,
      );
    } finally {
      process?.kill(ProcessSignal.sigterm);
    }
  }

  Future<String?> _resolveHelperPath(String? override) async {
    final candidates = <String>[
      if (override != null && override.trim().isNotEmpty) override,
      path.join(
        path.dirname(Platform.resolvedExecutable),
        'intergalactic_game_capture_helper.exe',
      ),
      ..._repoCandidateHelperPaths(Directory.current.path),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Iterable<String> _repoCandidateHelperPaths(String start) sync* {
    var current = Directory(start);
    for (var i = 0; i < 6; i++) {
      yield path.join(
        current.path,
        'plugins',
        'intergalactic_game_capture',
        'windows',
        'build',
        'Debug',
        'intergalactic_game_capture_helper.exe',
      );
      yield path.join(
        current.path,
        '..',
        'plugins',
        'intergalactic_game_capture',
        'windows',
        'build',
        'Debug',
        'intergalactic_game_capture_helper.exe',
      );
      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
  }

  Future<String> _resolveOutputRoot(String? override) async {
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }
    return path.join(
      await AppConfig.getLogDirectoryPath(),
      'stream-tests',
      'game-capture-probes',
    );
  }

  Future<File?> _findLatestMetadataFile(
    String outputRoot, {
    required DateTime startedAt,
  }) async {
    final root = Directory(outputRoot);
    if (!await root.exists()) {
      return null;
    }
    final candidates = <File>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) {
        continue;
      }
      final metadata = File(path.join(entity.path, 'metadata.json'));
      if (!await metadata.exists()) {
        continue;
      }
      final stat = await metadata.stat();
      if (stat.modified
          .isBefore(startedAt.subtract(const Duration(seconds: 2)))) {
        continue;
      }
      candidates.add(metadata);
    }
    candidates.sort((a, b) {
      final aModified = a.statSync().modified;
      final bModified = b.statSync().modified;
      return bModified.compareTo(aModified);
    });
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<Map<String, Object?>> _readMetadata(File metadataFile) async {
    final decoded = jsonDecode(await metadataFile.readAsString());
    final metadata = <String, Object?>{};
    if (decoded is Map<String, Object?>) {
      metadata.addAll(decoded);
    } else if (decoded is Map) {
      metadata
          .addAll(decoded.map((key, value) => MapEntry(key.toString(), value)));
    }
    final hostConsumerFile =
        File(path.join(metadataFile.parent.path, 'host-consumer.json'));
    if (await hostConsumerFile.exists()) {
      final hostDecoded = jsonDecode(await hostConsumerFile.readAsString());
      if (hostDecoded is Map<String, Object?>) {
        metadata['hostConsumer'] = hostDecoded;
      } else if (hostDecoded is Map) {
        metadata['hostConsumer'] = hostDecoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }
    final publicationHandoffFile =
        File(path.join(metadataFile.parent.path, 'publication-handoff.json'));
    if (await publicationHandoffFile.exists()) {
      final handoffDecoded =
          jsonDecode(await publicationHandoffFile.readAsString());
      if (handoffDecoded is Map<String, Object?>) {
        metadata['publicationHandoff'] = handoffDecoded;
      } else if (handoffDecoded is Map) {
        metadata['publicationHandoff'] = handoffDecoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }
    return metadata;
  }
}

Future<int> _waitForExitOrTerminate(Process process, Duration timeout) async {
  final exitCode = process.exitCode;
  try {
    return await exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
  }

  try {
    return await exitCode.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
  }

  try {
    return await exitCode.timeout(const Duration(seconds: 2));
  } on TimeoutException {
    return -1;
  }
}

String _processTextSuffix(String stdoutText, String stderrText) {
  final parts = [
    if (stdoutText.trim().isNotEmpty)
      ' stdout=${_shortProcessText(stdoutText.trim())}',
    if (stderrText.trim().isNotEmpty)
      ' stderr=${_shortProcessText(stderrText.trim())}',
  ];
  return parts.isEmpty ? '' : ';${parts.join(';')}';
}

String _shortProcessText(String value) {
  final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= 240) {
    return singleLine;
  }
  return '${singleLine.substring(0, 240)}...';
}
