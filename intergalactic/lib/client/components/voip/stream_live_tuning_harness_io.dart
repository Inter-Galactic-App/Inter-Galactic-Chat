import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/stream_live_tuning_harness_base.dart';
import 'package:intergalactic/client/components/voip/stream_test_runner.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';

class StreamLiveTuningHarness {
  StreamLiveTuningHarness._();

  static final instance = StreamLiveTuningHarness._();

  static const _defaultLabDirectoryPath = r'runtime\stream-lab';

  static final labDirectoryPath = _resolveLabDirectoryPath();
  static final configFilePath = _labFilePath('stream-lab-config.json');
  static final statusFilePath = _labFilePath('stream-lab-status.json');
  static final statsFilePath = _labFilePath('live-stream-stats.jsonl');

  bool get isSupported => !kReleaseMode && Platform.isWindows;

  Future<StreamLiveTuningConfig> readConfig() async {
    if (!isSupported) {
      return StreamLiveTuningConfig.disabled();
    }
    final file = File(configFilePath);
    if (!await file.exists()) {
      return StreamLiveTuningConfig.disabled();
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return StreamLiveTuningConfig.disabled(
          loadError: 'config root must be a JSON object',
        );
      }
      return StreamLiveTuningConfig.fromJson(
        decoded.cast<String, Object?>(),
      );
    } catch (error) {
      return StreamLiveTuningConfig.disabled(loadError: error.toString());
    }
  }

  Future<void> writeStatus({
    required StreamLiveTuningConfig config,
    required bool activeScreenShare,
    required List<String> applicationNotes,
    ScreenShareProfileConfig? activeProfile,
    String? windowsCaptureBackendLabel,
  }) async {
    if (!isSupported) {
      return;
    }
    await _ensureLabDirectory();
    final status = {
      'schema': 'intergalactic.streamLiveTuningStatus.v1',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'supported': isSupported,
      'activeScreenShare': activeScreenShare,
      'windowsCaptureBackend': windowsCaptureBackendLabel,
      'applicationNotes': applicationNotes,
      'config': config.toJson(),
      'activeProfile': activeProfile == null
          ? null
          : screenShareProfileToJson(activeProfile),
    };
    await File(statusFilePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(status),
      flush: true,
    );
  }

  Future<void> appendSnapshot({
    required StreamLiveTuningConfig config,
    required VoipCallDiagnosticsSnapshot snapshot,
    required ScreenShareProfileConfig activeProfile,
    required bool activeScreenShare,
    required String windowsCaptureBackendLabel,
    required List<String> applicationNotes,
    String? nativeDiagnosticLogText,
  }) async {
    if (!isSupported || !config.enabled) {
      return;
    }
    await _ensureLabDirectory();
    final nativeDiagnostics = _nativeDiagnosticsFromText(
      nativeDiagnosticLogText,
    );
    final record = streamLiveTuningSnapshotToJson(
      config: config,
      snapshot: snapshot,
      activeProfile: activeProfile,
      activeScreenShare: activeScreenShare,
      windowsCaptureBackendLabel: windowsCaptureBackendLabel,
      applicationNotes: applicationNotes,
      nativeDiagnostics: nativeDiagnostics,
    );
    await File(statsFilePath).writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _ensureLabDirectory() async {
    final directory = Directory(labDirectoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  static String _resolveLabDirectoryPath() {
    final configured =
        Platform.environment['INTERGALACTIC_STREAM_LAB_DIR']?.trim();
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    return _defaultLabDirectoryPath;
  }

  static String _labFilePath(String fileName) {
    final base = labDirectoryPath;
    if (base.endsWith('/') || base.endsWith(r'\')) {
      return '$base$fileName';
    }
    return '$base${Platform.pathSeparator}$fileName';
  }

  Map<String, Object?>? _nativeDiagnosticsFromText(String? text) {
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    final markers = const LineSplitter()
        .convert(text)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (markers.isEmpty) {
      return null;
    }
    return StreamTestNativeDiagnostics.fromMarkers(markers).toJson();
  }
}
