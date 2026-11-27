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

/// Appends a stop-time status snapshot to the capture's metadata file.
///
/// The start-time metadata necessarily records pre-capture counter values
/// (they read as zero), which made fields like `enhancedHushRecoveryFrames`
/// untrustworthy for QA. The caller passes the status read at the moment the
/// capture stopped, before any processor re-initialization can reset the
/// shared counters.
Future<void> appendNoiseSuppressionDiagnosticStopMetadata({
  required String directoryPath,
  required NoiseSuppressionNativeStatus status,
}) async {
  final file = File(
    '$directoryPath${Platform.pathSeparator}capture-metadata.txt',
  );
  if (!await file.exists()) {
    return;
  }
  final lines = <String>[
    '',
    '# capture-stop status snapshot (read when the capture stopped)',
    'stop.deepFilterNetFramesProcessed: ${status.deepFilterNetFramesProcessed}',
    'stop.deepFilterNetBypassFrames: ${status.deepFilterNetBypassFrames}',
    'stop.deepFilterNetSpeechProtectedFrames: ${status.deepFilterNetSpeechProtectedFrames}',
    'stop.deepFilterNetDryDelayFrames: ${status.deepFilterNetDryDelayFrames}',
    'stop.deepFilterNetWarmupMs: ${status.deepFilterNetWarmupMs}',
    'stop.deepFilterNetPrewarmPendingFrames: ${status.deepFilterNetPrewarmPendingFrames}',
    'stop.deepFilterNetTransientSuppressedFrames: ${status.deepFilterNetTransientSuppressedFrames}',
    'stop.deepFilterNetTransientAdjustedSamples: ${status.deepFilterNetTransientAdjustedSamples}',
    'stop.enhancedHushRecoveryFrames: ${status.deepFilterNetHushRecoveryFrames}',
    'stop.enhancedHushLastRecoveryGain: ${status.deepFilterNetHushLastRecoveryGain}',
    'stop.enhancedHushLastInputRms: ${status.deepFilterNetHushLastInputRms}',
    'stop.enhancedHushLastOutputRms: ${status.deepFilterNetHushLastOutputRms}',
    'stop.deepFilterNetHushWarmupMs: ${status.deepFilterNetHushWarmupMs}',
    'stop.captureGapEvents: ${status.captureGapEvents}',
    'stop.deepFilterNetGapRecoveries: ${status.deepFilterNetGapRecoveries}',
    'stop.callbackMaxProcessingMs: ${status.callbackMaxProcessingMs}',
    'stop.callbackBudgetMisses: ${status.callbackBudgetMisses}',
    'stop.outputLimiterSamples: ${status.outputLimiterSamples}',
  ];
  await file.writeAsString(
    '${lines.join('\n')}\n',
    mode: FileMode.append,
    flush: true,
  );
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
      'type': 'audio_pipeline_diagnostic_wav_set',
      'capture_folder': directoryLabel,
      'created_at_utc': now.toIso8601String(),
      'transport_status': 'missing',
      'message':
          'Audio pipeline diagnostic folder was not found when preparing the report.',
      'files': const <Object?>[],
    };
    return NoiseSuppressionDiagnosticReportBundle(
      directoryPath: directory.path,
      directoryLabel: directoryLabel,
      metadata: metadata,
      attachments: const [],
      userMessage:
          'The audio pipeline WAV folder was not found. Capture a new local WAV set before reviewing audio artifacts.',
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
    'type': 'audio_pipeline_diagnostic_wav_set',
    'legacy_type': 'rnnoise_diagnostic_wav_set',
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
        {'name': file.fileName, 'sizeBytes': file.sizeBytes},
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
  final status = service.status;
  final parts = <String>[
    if (captureLabel != null && captureLabel.trim().isNotEmpty)
      _slug(captureLabel),
    'hook-${_slug(hookMode)}',
    'pipeline-${_slug(status.pipelineMode.statusLabel)}',
    'guard-${_onOff(status.deepFilterNetSpeechProtectHysteresisEnabled)}',
    'click-${_onOff(preferences.voipNoiseSuppressionDeepFilterNetTransientSuppression.value)}',
    'hush-${_onOff(preferences.voipNoiseSuppressionDeepFilterNetHushSuppression.value)}',
    'scenario-${_slug(frontend.tapOrderScenario)}',
    service.desiredEnabled
        ? 'native-${_slug(service.tuningProfile.presetKey)}'
        : 'native-off',
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
      .where(
        (fileName) => _stageFileRequested(
          fileName,
          stageMask: stageMask,
          includeWasapiSidecar: includeWasapiSidecar,
        ),
      )
      .toList(growable: false);
  final stageMaskHex = stageMask.toRadixString(16).padLeft(2, '0');
  final metadata = <String>[
    'timestampUtc: $timestamp',
    'folderLabel: $label',
    'developerHookModePreference: ${preferences.voipNoiseSuppressionHookMode.value}',
    'audioPipelineMode: ${status.pipelineMode.statusLabel}',
    'enhancedClickGuard: ${preferences.voipNoiseSuppressionDeepFilterNetTransientSuppression.value}',
    'enhancedHushSuppression: ${preferences.voipNoiseSuppressionDeepFilterNetHushSuppression.value}',
    'speechProtectHysteresisEnabled: ${status.deepFilterNetSpeechProtectHysteresisEnabled}',
    'enhancedHushRecoveryFrames: ${status.deepFilterNetHushRecoveryFrames}',
    'enhancedHushLastRecoveryGain: ${status.deepFilterNetHushLastRecoveryGain}',
    'enhancedHushLastInputRms: ${status.deepFilterNetHushLastInputRms}',
    'enhancedHushLastOutputRms: ${status.deepFilterNetHushLastOutputRms}',
    'tapOrderScenario: ${frontend.tapOrderScenario}',
    'nativeNoiseSuppressionEnabled: ${service.desiredEnabled}',
    'legacyRnnoiseEnabled: ${service.desiredEnabled}',
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
      'deepfilternet_output.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.deepfilternet_output.wav: DeepFilterNet model output before speech protection, click guard, Hush, and final safety limiting.',
    if (_stageFileRequested(
      'speech_protect_output.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.speech_protect_output.wav: Enhanced output after loud-speech protection wet/dry mixing.',
    if (_stageFileRequested(
      'transient_guard_output.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.transient_guard_output.wav: Enhanced output after the optional keyboard/mouse transient guard.',
    if (_stageFileRequested(
      'hush_input_16k.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.hush_input_16k.wav: post-DeepFilterNet support-layer input resampled for the Hush model.',
    if (_stageFileRequested(
      'hush_output_16k.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.hush_output_16k.wav: Hush model output before resampling back to WebRTC capture rate.',
    if (_stageFileRequested(
      'hush_output.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.hush_output.wav: Hush support-layer output before post-Hush gain recovery.',
    if (_stageFileRequested(
      'final_to_webrtc.wav',
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
    ))
      'stageMeaning.final_to_webrtc.wav: final samples returned to the WebRTC capture pipeline after post-Hush gain recovery and safety limiting.',
    if (includeWasapiSidecar)
      'stageMeaning.device_raw_wasapi.wav: sidecar WASAPI capture from the selected/default communications mic.',
    'note: raw diagnostic audio stays local; bug-report WAV upload is disabled.',
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
    final stageCompare = _diagnosticStageSortIndex(
      a.fileName,
    ).compareTo(_diagnosticStageSortIndex(b.fileName));
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
      'Audio pipeline WAV capture wrote $wavCount local file(s), ${_formatBytes(totalWavBytes)} total. WAV bug-report upload is disabled; use the local folder for review.',
    'empty' =>
      'No audio pipeline WAV files were found in the latest capture folder. Capture a WAV set before reviewing audio artifacts.',
    _ =>
      'Audio pipeline WAV artifacts could not be summarized. Capture a new local WAV set before reviewing audio artifacts.',
  };
}

int _diagnosticStageSortIndex(String fileName) {
  return switch (fileName) {
    'device_raw_wasapi.wav' => 0,
    'webrtc_hook_input.wav' => 1,
    'rnnoise_input_48k.wav' => 2,
    'rnnoise_output_48k.wav' => 3,
    'deepfilternet_output.wav' => 4,
    'speech_protect_output.wav' => 5,
    'transient_guard_output.wav' => 6,
    'hush_input_16k.wav' => 7,
    'hush_output_16k.wav' => 8,
    'hush_output.wav' => 9,
    'final_to_webrtc.wav' => 10,
    _ => 100,
  };
}

String _diagnosticStageKey(String fileName) {
  return switch (fileName) {
    'device_raw_wasapi.wav' => 'device_raw_wasapi',
    'webrtc_hook_input.wav' => 'webrtc_hook_input',
    'rnnoise_input_48k.wav' => 'rnnoise_input_48k',
    'rnnoise_output_48k.wav' => 'rnnoise_output_48k',
    'deepfilternet_output.wav' => 'deepfilternet_output',
    'speech_protect_output.wav' => 'speech_protect_output',
    'transient_guard_output.wav' => 'transient_guard_output',
    'hush_input_16k.wav' => 'hush_input_16k',
    'hush_output_16k.wav' => 'hush_output_16k',
    'hush_output.wav' => 'hush_output',
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
    'deepfilternet_output.wav' => 'DeepFilterNet model output',
    'speech_protect_output.wav' => 'Loud-speech protection output',
    'transient_guard_output.wav' => 'Transient click guard output',
    'hush_input_16k.wav' => 'Hush input at 16 kHz',
    'hush_output_16k.wav' => 'Hush output at 16 kHz',
    'hush_output.wav' => 'Hush output before gain recovery',
    'final_to_webrtc.wav' => 'Final audio returned to WebRTC',
    _ => 'Audio pipeline diagnostic WAV',
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
    case 'deepfilternet_output.wav':
      return (stageMask &
              NoiseSuppressionDiagnosticStageMask.deepFilterNetOutput) !=
          0;
    case 'speech_protect_output.wav':
      return (stageMask &
              NoiseSuppressionDiagnosticStageMask.speechProtectOutput) !=
          0;
    case 'transient_guard_output.wav':
      return (stageMask &
              NoiseSuppressionDiagnosticStageMask.transientGuardOutput) !=
          0;
    case 'hush_input_16k.wav':
      return (stageMask & NoiseSuppressionDiagnosticStageMask.hushInput16k) !=
          0;
    case 'hush_output_16k.wav':
      return (stageMask & NoiseSuppressionDiagnosticStageMask.hushOutput16k) !=
          0;
    case 'hush_output.wav':
      return (stageMask & NoiseSuppressionDiagnosticStageMask.hushOutput) != 0;
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
