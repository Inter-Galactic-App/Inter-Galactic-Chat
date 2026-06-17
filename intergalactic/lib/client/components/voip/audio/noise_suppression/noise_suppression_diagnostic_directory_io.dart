import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';
import 'package:path_provider/path_provider.dart';

const String noiseSuppressionDiagnosticManifestFileName =
    'capture-manifest.json';

class NoiseSuppressionDiagnosticReportBundle {
  const NoiseSuppressionDiagnosticReportBundle({
    required this.directoryPath,
    required this.directoryLabel,
    required this.metadata,
    required this.attachments,
    required this.userMessage,
    required this.hasWavArtifacts,
    required this.allWavArtifactsAttached,
    required this.totalWavBytes,
    required this.estimatedEncodedWavBytes,
  });

  final String directoryPath;
  final String directoryLabel;
  final Map<String, Object?> metadata;
  final List<BugReportAttachmentSummary> attachments;
  final String userMessage;
  final bool hasWavArtifacts;
  final bool allWavArtifactsAttached;
  final int totalWavBytes;
  final int estimatedEncodedWavBytes;
}

Future<String> createNoiseSuppressionDiagnosticDirectory({
  String? captureLabel,
  int stageMask = NoiseSuppressionDiagnosticStageMask.all,
  bool includeWasapiSidecar = true,
}) async {
  final supportDir = await getApplicationSupportDirectory();
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final label = _diagnosticCaptureLabel(captureLabel: captureLabel);
  final directory = Directory(
    '${supportDir.path}${Platform.pathSeparator}rnnoise-diagnostics'
    '${Platform.pathSeparator}$timestamp-$label',
  );
  await directory.create(recursive: true);
  await _writeDiagnosticCaptureMetadata(
    directory: directory,
    timestamp: timestamp,
    label: label,
    stageMask: stageMask,
    includeWasapiSidecar: includeWasapiSidecar,
  );
  return directory.path;
}

Future<NoiseSuppressionDiagnosticReportBundle>
    collectNoiseSuppressionDiagnosticReportBundle({
  required String directoryPath,
}) async {
  final directory = Directory(directoryPath);
  final directoryLabel = _pathBasename(directory.path);
  final exists = await directory.exists();
  final now = DateTime.now().toUtc();

  if (!exists) {
    final metadata = <String, Object?>{
      'schema_version': 1,
      'type': 'rnnoise_diagnostic_wav_set',
      'capture_folder': directoryLabel,
      'created_at_utc': now.toIso8601String(),
      'transport_status': 'missing',
      'message':
          'RNNoise diagnostic folder was not found when preparing the report.',
      'files': const <Object?>[],
    };
    return NoiseSuppressionDiagnosticReportBundle(
      directoryPath: directory.path,
      directoryLabel: directoryLabel,
      metadata: metadata,
      attachments: const [],
      userMessage:
          'The RNNoise WAV folder was not found. Capture a new local WAV set before reviewing audio artifacts.',
      hasWavArtifacts: false,
      allWavArtifactsAttached: false,
      totalWavBytes: 0,
      estimatedEncodedWavBytes: 0,
    );
  }

  final wavFiles = await _diagnosticWavFiles(directory);
  final metadataFiles = await _diagnosticMetadataFiles(directory);
  final totalWavBytes = wavFiles.fold<int>(
    0,
    (total, file) => total + file.sizeBytes,
  );
  const estimatedEncodedWavBytes = 0;
  const attachments = <BugReportAttachmentSummary>[];

  final transportStatus = wavFiles.isEmpty ? 'empty' : 'local_only';
  final transportMessage = _reportTransportMessage(
    transportStatus: transportStatus,
    wavCount: wavFiles.length,
    totalWavBytes: totalWavBytes,
  );
  final userMessage = transportStatus == 'local_only'
      ? '$transportMessage Folder: ${directory.path}'
      : transportMessage;
  final metadata = <String, Object?>{
    'schema_version': 1,
    'type': 'rnnoise_diagnostic_wav_set',
    'capture_folder': directoryLabel,
    'created_at_utc': now.toIso8601String(),
    'transport_status': transportStatus,
    'transport_message': transportMessage,
    'wav_bug_report_submission_supported': false,
    'total_wav_bytes': totalWavBytes,
    'wav_count': wavFiles.length,
    'attached_wav_count': 0,
    'omitted_wav_count': wavFiles.length,
    'files': [
      for (final file in wavFiles)
        {
          'name': file.fileName,
          'stage': file.stageKey,
          'stage_label': file.stageLabel,
          'sizeBytes': file.sizeBytes,
          'attached': false,
          'omitted_reason': 'bug_report_audio_upload_removed',
        },
    ],
    'metadata_files': [
      for (final file in metadataFiles)
        {
          'name': file.fileName,
          'sizeBytes': file.sizeBytes,
        },
    ],
  };

  await _writeDiagnosticManifest(directory, metadata);

  return NoiseSuppressionDiagnosticReportBundle(
    directoryPath: directory.path,
    directoryLabel: directoryLabel,
    metadata: metadata,
    attachments: attachments,
    userMessage: userMessage,
    hasWavArtifacts: wavFiles.isNotEmpty,
    allWavArtifactsAttached: false,
    totalWavBytes: totalWavBytes,
    estimatedEncodedWavBytes: estimatedEncodedWavBytes,
  );
}

String _diagnosticCaptureLabel({String? captureLabel}) {
  final service = NoiseSuppressionService.instance;
  final frontend = NoiseSuppressionCaptureProfile.captureFrontendOptions();
  final hookMode = preferences.voipNoiseSuppressionHookMode.value;
  final parts = <String>[
    if (captureLabel != null && captureLabel.trim().isNotEmpty)
      _slug(captureLabel),
    'hook-${_slug(hookMode)}',
    'scenario-${_slug(frontend.tapOrderScenario)}',
    service.desiredEnabled
        ? 'rnnoise-${_slug(service.tuningProfile.presetKey)}'
        : 'rnnoise-off',
    frontend.debugOverrideActive ? 'override-on' : 'override-off',
    'aec-${_onOff(frontend.echoCancellation)}',
    'ns-${_onOff(frontend.noiseSuppression)}',
    'agc-${_onOff(frontend.autoGainControl)}',
    'hp-${_onOff(frontend.highPassFilter)}',
    'typing-${_onOff(frontend.typingNoiseDetection)}',
    '48k-${_onOff(frontend.requestRnnoiseReferenceFormat)}',
    'volume-${_onOff(frontend.includeVolumeConstraint)}',
  ];
  final label = parts.join('__');
  if (label.length <= 96) {
    return label;
  }
  return label.substring(0, 96).replaceAll(RegExp(r'[_-]+$'), '');
}

Future<void> _writeDiagnosticCaptureMetadata({
  required Directory directory,
  required String timestamp,
  required String label,
  required int stageMask,
  required bool includeWasapiSidecar,
}) async {
  final service = NoiseSuppressionService.instance;
  final status = service.status;
  final tuning = service.tuningProfile;
  final frontend = NoiseSuppressionCaptureProfile.captureFrontendOptions();
  final stageFiles = status.diagnosticCaptureStageFileNames
      .where((fileName) => _stageFileRequested(
            fileName,
            stageMask: stageMask,
            includeWasapiSidecar: includeWasapiSidecar,
          ))
      .toList(growable: false);
  final stageMaskHex = stageMask.toRadixString(16).padLeft(2, '0');
  final metadata = <String>[
    'timestampUtc: $timestamp',
    'folderLabel: $label',
    'developerHookModePreference: ${preferences.voipNoiseSuppressionHookMode.value}',
    'tapOrderScenario: ${frontend.tapOrderScenario}',
    'rnnoiseEnabled: ${service.desiredEnabled}',
    'nativeHookEnabled: ${status.enabled}',
    'nativeRequestedEnabled: ${status.requestedEnabled}',
    'rnnoisePreset: ${tuning.presetKey}',
    'rnnoiseVadThreshold: ${tuning.vadThreshold}',
    'rnnoiseSpeechGraceFrames: ${tuning.speechGraceFrames}',
    'rnnoiseClosedGain: ${tuning.closedGain}',
    'rnnoiseTransientSensitivity: ${tuning.transientSensitivity}',
    'rnnoiseFastCloseEnabled: ${tuning.fastCloseEnabled}',
    'rnnoisePipelineMode: ${status.pipelineMode.statusLabel}',
    'rnnoiseNativeReason: ${status.reason}',
    'captureFrontend: ${NoiseSuppressionCaptureProfile.captureFrontendSummary()}',
    'debugOverrideActive: ${frontend.debugOverrideActive}',
    'echoCancellation: ${frontend.echoCancellation}',
    'webrtcNoiseSuppression: ${frontend.noiseSuppression}',
    'autoGainControl: ${frontend.autoGainControl}',
    'highPassFilter: ${frontend.highPassFilter}',
    'typingNoiseDetection: ${frontend.typingNoiseDetection}',
    'request48kMono: ${frontend.requestRnnoiseReferenceFormat}',
    'includeVolumeConstraint: ${frontend.includeVolumeConstraint}',
    'stageMask: 0x$stageMaskHex',
    'wasapiSidecarRequested: $includeWasapiSidecar',
    'stageFiles: ${stageFiles.join(', ')}',
    if (_stageFileRequested(
      'webrtc_hook_input.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.webrtc_hook_input.wav: audio at the WebRTC capture hook input; this is not raw device capture.',
    if (_stageFileRequested(
      'rnnoise_input_48k.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.rnnoise_input_48k.wav: hook audio after conversion into RNNoise 48 kHz mono blocks.',
    if (_stageFileRequested(
      'rnnoise_output_48k.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.rnnoise_output_48k.wav: RNNoise output before conversion back to the hook format.',
    if (_stageFileRequested(
      'final_to_webrtc.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.final_to_webrtc.wav: final samples returned to the WebRTC capture pipeline.',
    if (includeWasapiSidecar)
      'stageMeaning.device_raw_wasapi.wav: sidecar WASAPI capture from the selected/default communications mic.',
    'note: raw diagnostic audio stays local; bug-report WAV submission is disabled.',
    '',
  ].join('\n');

  await File(
    '${directory.path}${Platform.pathSeparator}capture-metadata.txt',
  ).writeAsString(metadata);
}

class _DiagnosticFileInfo {
  const _DiagnosticFileInfo({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    required this.stageKey,
    required this.stageLabel,
  });

  final File file;
  final String fileName;
  final int sizeBytes;
  final String stageKey;
  final String stageLabel;
}

Future<List<_DiagnosticFileInfo>> _diagnosticWavFiles(
  Directory directory,
) async {
  final files = <_DiagnosticFileInfo>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File ||
        !_pathBasename(entity.path).toLowerCase().endsWith('.wav')) {
      continue;
    }
    final fileName = _pathBasename(entity.path);
    final sizeBytes = await entity.length();
    files.add(
      _DiagnosticFileInfo(
        file: entity,
        fileName: fileName,
        sizeBytes: sizeBytes,
        stageKey: _diagnosticStageKey(fileName),
        stageLabel: _diagnosticStageLabel(fileName),
      ),
    );
  }
  files.sort((a, b) {
    final stageCompare = _diagnosticStageSortIndex(a.fileName).compareTo(
      _diagnosticStageSortIndex(b.fileName),
    );
    if (stageCompare != 0) {
      return stageCompare;
    }
    return a.fileName.compareTo(b.fileName);
  });
  return files;
}

Future<List<_DiagnosticFileInfo>> _diagnosticMetadataFiles(
  Directory directory,
) async {
  final files = <_DiagnosticFileInfo>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final fileName = _pathBasename(entity.path);
    if (!const {
      'capture-metadata.txt',
      noiseSuppressionDiagnosticManifestFileName,
    }.contains(fileName)) {
      continue;
    }
    files.add(
      _DiagnosticFileInfo(
        file: entity,
        fileName: fileName,
        sizeBytes: await entity.length(),
        stageKey: 'metadata',
        stageLabel: 'Capture metadata',
      ),
    );
  }
  files.sort((a, b) => a.fileName.compareTo(b.fileName));
  return files;
}

Future<void> _writeDiagnosticManifest(
  Directory directory,
  Map<String, Object?> metadata,
) async {
  const encoder = JsonEncoder.withIndent('  ');
  await File(
    '${directory.path}${Platform.pathSeparator}'
    '$noiseSuppressionDiagnosticManifestFileName',
  ).writeAsString('${encoder.convert(metadata)}\n');
}

String _reportTransportMessage({
  required String transportStatus,
  required int wavCount,
  required int totalWavBytes,
}) {
  return switch (transportStatus) {
    'local_only' =>
      'RNNoise WAV capture wrote $wavCount local file(s), ${_formatBytes(totalWavBytes)} total. WAV bug-report submission is disabled.',
    'empty' =>
      'No RNNoise WAV files were found in the latest capture folder. Capture a WAV set before reviewing audio artifacts.',
    _ =>
      'RNNoise WAV artifacts could not be summarized. Capture a new local WAV set before reviewing audio artifacts.',
  };
}

int _diagnosticStageSortIndex(String fileName) {
  return switch (fileName) {
    'device_raw_wasapi.wav' => 0,
    'webrtc_hook_input.wav' => 1,
    'rnnoise_input_48k.wav' => 2,
    'rnnoise_output_48k.wav' => 3,
    'final_to_webrtc.wav' => 4,
    _ => 100,
  };
}

String _diagnosticStageKey(String fileName) {
  return switch (fileName) {
    'device_raw_wasapi.wav' => 'device_raw_wasapi',
    'webrtc_hook_input.wav' => 'webrtc_hook_input',
    'rnnoise_input_48k.wav' => 'rnnoise_input_48k',
    'rnnoise_output_48k.wav' => 'rnnoise_output_48k',
    'final_to_webrtc.wav' => 'final_to_webrtc',
    _ => fileName.replaceAll(RegExp(r'\.wav$'), ''),
  };
}

String _diagnosticStageLabel(String fileName) {
  return switch (fileName) {
    'device_raw_wasapi.wav' => 'Raw microphone sidecar capture',
    'webrtc_hook_input.wav' => 'WebRTC hook input',
    'rnnoise_input_48k.wav' => 'RNNoise 48 kHz input',
    'rnnoise_output_48k.wav' => 'RNNoise 48 kHz output',
    'final_to_webrtc.wav' => 'Final audio returned to WebRTC',
    _ => 'RNNoise diagnostic WAV',
  };
}

String _pathBasename(String path) {
  final normalized = path.replaceAll('\\', Platform.pathSeparator);
  final parts = normalized.split(Platform.pathSeparator);
  return parts.isEmpty ? path : parts.last;
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

bool _stageFileRequested(
  String fileName, {
  required int stageMask,
  required bool includeWasapiSidecar,
}) {
  switch (fileName) {
    case 'webrtc_hook_input.wav':
      return (stageMask &
              NoiseSuppressionDiagnosticStageMask.webrtcHookInput) !=
          0;
    case 'rnnoise_input_48k.wav':
      return (stageMask &
              NoiseSuppressionDiagnosticStageMask.rnnoiseInput48k) !=
          0;
    case 'rnnoise_output_48k.wav':
      return (stageMask &
              NoiseSuppressionDiagnosticStageMask.rnnoiseOutput48k) !=
          0;
    case 'final_to_webrtc.wav':
      return (stageMask & NoiseSuppressionDiagnosticStageMask.finalToWebrtc) !=
          0;
    case 'device_raw_wasapi.wav':
      return includeWasapiSidecar;
    default:
      return true;
  }
}

String _onOff(bool value) => value ? 'on' : 'off';

String _slug(String value) {
  final sanitized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (sanitized.isEmpty) {
    return 'capture';
  }
  return sanitized.length <= 32 ? sanitized : sanitized.substring(0, 32);
}
