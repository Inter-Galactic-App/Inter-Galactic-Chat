class NoiseSuppressionNativeConfig {
  const NoiseSuppressionNativeConfig({
    required this.vadThreshold,
    required this.speechGraceFrames,
    required this.closedGain,
    required this.transientSensitivity,
    required this.fastCloseEnabled,
  });

  final double vadThreshold;
  final int speechGraceFrames;
  final double closedGain;
  final double transientSensitivity;
  final bool fastCloseEnabled;
}

abstract final class NoiseSuppressionDiagnosticStageMask {
  static const int webrtcHookInput = 1 << 0;
  static const int rnnoiseInput48k = 1 << 1;
  static const int rnnoiseOutput48k = 1 << 2;
  static const int finalToWebrtc = 1 << 3;
  static const int all =
      webrtcHookInput | rnnoiseInput48k | rnnoiseOutput48k | finalToWebrtc;
  static const int hookInputAndFinal = webrtcHookInput | finalToWebrtc;
}

enum NoiseSuppressionPipelineMode {
  off(0, 'off'),
  cleanRnnoise(1, 'clean_rnnoise'),
  tunedGate(2, 'tuned_gate'),
  identity(3, 'identity');

  const NoiseSuppressionPipelineMode(this.nativeValue, this.statusLabel);

  final int nativeValue;
  final String statusLabel;

  static NoiseSuppressionPipelineMode fromStatusLabel(String value) {
    return NoiseSuppressionPipelineMode.values.firstWhere(
      (mode) => mode.statusLabel == value,
      orElse: () => NoiseSuppressionPipelineMode.cleanRnnoise,
    );
  }
}

class NoiseSuppressionNativeStatus {
  const NoiseSuppressionNativeStatus({
    required this.supported,
    required this.available,
    required this.requestedEnabled,
    required this.enabled,
    required this.active,
    required this.formatMismatchDetected,
    required this.suspiciousOutputDetected,
    required this.formatMismatchReason,
    required this.sampleRateHz,
    required this.numChannels,
    required this.expectedFramesPer10ms,
    required this.lastNumBands,
    required this.lastNumFrames,
    required this.lastBufferSize,
    required this.framesProcessed,
    required this.bypassFrames,
    required this.gatedFrames,
    required this.resamplerUses,
    required this.resamplerInputUnderruns,
    required this.resamplerOutputUnderruns,
    required this.resamplerOverruns,
    required this.resamplerMode,
    required this.resamplerInputFrames,
    required this.resamplerOutputFrames,
    required this.resamplerSourceRateHz,
    required this.resamplerTargetRateHz,
    required this.pipelineMode,
    required this.vadLowFrames,
    required this.vadMidFrames,
    required this.vadHighFrames,
    required this.referenceVadThreshold,
    required this.recentVadAverage,
    required this.speechGraceRemainingFrames,
    required this.referenceSpeechGraceFrames,
    required this.noiseGateClosedGain,
    required this.transientSensitivity,
    required this.fastCloseEnabled,
    required this.lastGateReason,
    required this.lastGateGain,
    required this.lastInputScaleFactor,
    required this.lastVadProbability,
    required this.lastInputRms,
    required this.lastOutputRms,
    required this.lastOutputRatio,
    required this.lastInputPeak,
    required this.lastOutputPeak,
    required this.lastInputMin,
    required this.lastInputMax,
    required this.lastOutputMin,
    required this.lastOutputMax,
    required this.lastInputMaxDelta,
    required this.lastOutputMaxDelta,
    required this.processingApplied,
    required this.identityFrames,
    required this.clippingSamples,
    required this.inputClippingSamples,
    required this.outputClippingSamples,
    required this.outputLimiterSamples,
    required this.outputAntiAliasUses,
    required this.nonFiniteSamples,
    required this.callbackAverageProcessingMs,
    required this.callbackMaxProcessingMs,
    required this.callbackBudgetMisses,
    required this.rnnoiseStateResets,
    required this.diagnosticCaptureActive,
    required this.diagnosticCaptureFrames,
    required this.diagnosticCaptureDroppedFrames,
    required this.diagnosticCaptureWrittenFiles,
    required this.diagnosticCaptureLastError,
    required this.diagnosticCaptureStageFiles,
    required this.wasapiSidecarActive,
    required this.wasapiSidecarFrames,
    required this.wasapiSidecarDroppedPackets,
    required this.wasapiSidecarWrittenFiles,
    required this.wasapiSidecarSampleRateHz,
    required this.wasapiSidecarChannels,
    required this.wasapiSidecarDeviceResolution,
    required this.wasapiSidecarLastError,
    required this.reason,
  });

  final bool supported;
  final bool available;
  final bool requestedEnabled;
  final bool enabled;
  final bool active;
  final bool formatMismatchDetected;
  final bool suspiciousOutputDetected;
  final String formatMismatchReason;
  final int sampleRateHz;
  final int numChannels;
  final int expectedFramesPer10ms;
  final int lastNumBands;
  final int lastNumFrames;
  final int lastBufferSize;
  final int framesProcessed;
  final int bypassFrames;
  final int gatedFrames;
  final int resamplerUses;
  final int resamplerInputUnderruns;
  final int resamplerOutputUnderruns;
  final int resamplerOverruns;
  final String resamplerMode;
  final int resamplerInputFrames;
  final int resamplerOutputFrames;
  final int resamplerSourceRateHz;
  final int resamplerTargetRateHz;
  final NoiseSuppressionPipelineMode pipelineMode;
  final int vadLowFrames;
  final int vadMidFrames;
  final int vadHighFrames;
  final double referenceVadThreshold;
  final double recentVadAverage;
  final int speechGraceRemainingFrames;
  final int referenceSpeechGraceFrames;
  final double noiseGateClosedGain;
  final double transientSensitivity;
  final bool fastCloseEnabled;
  final String lastGateReason;
  final double lastGateGain;
  final double lastInputScaleFactor;
  final double lastVadProbability;
  final double lastInputRms;
  final double lastOutputRms;
  final double lastOutputRatio;
  final double lastInputPeak;
  final double lastOutputPeak;
  final double lastInputMin;
  final double lastInputMax;
  final double lastOutputMin;
  final double lastOutputMax;
  final double lastInputMaxDelta;
  final double lastOutputMaxDelta;
  final bool processingApplied;
  final int identityFrames;
  final int clippingSamples;
  final int inputClippingSamples;
  final int outputClippingSamples;
  final int outputLimiterSamples;
  final int outputAntiAliasUses;
  final int nonFiniteSamples;
  final double callbackAverageProcessingMs;
  final double callbackMaxProcessingMs;
  final int callbackBudgetMisses;
  final int rnnoiseStateResets;
  final bool diagnosticCaptureActive;
  final int diagnosticCaptureFrames;
  final int diagnosticCaptureDroppedFrames;
  final int diagnosticCaptureWrittenFiles;
  final String diagnosticCaptureLastError;
  final String diagnosticCaptureStageFiles;
  final bool wasapiSidecarActive;
  final int wasapiSidecarFrames;
  final int wasapiSidecarDroppedPackets;
  final int wasapiSidecarWrittenFiles;
  final int wasapiSidecarSampleRateHz;
  final int wasapiSidecarChannels;
  final String wasapiSidecarDeviceResolution;
  final String wasapiSidecarLastError;
  final String reason;

  String get inputScaleLabel =>
      lastInputScaleFactor > 1000 ? 'pcm16-float' : 'normalized-float';

  List<String> get diagnosticCaptureStageFileNames =>
      diagnosticCaptureStageFiles
          .split(',')
          .map((fileName) => fileName.trim())
          .where((fileName) => fileName.isNotEmpty)
          .toList(growable: false);

  factory NoiseSuppressionNativeStatus.unavailable({
    String reason = 'unsupported_platform',
    bool supported = false,
    bool requestedEnabled = false,
  }) {
    return NoiseSuppressionNativeStatus(
      supported: supported,
      available: false,
      requestedEnabled: requestedEnabled,
      enabled: false,
      active: false,
      formatMismatchDetected: false,
      suspiciousOutputDetected: false,
      formatMismatchReason: 'none',
      sampleRateHz: 0,
      numChannels: 0,
      expectedFramesPer10ms: 0,
      lastNumBands: 0,
      lastNumFrames: 0,
      lastBufferSize: 0,
      framesProcessed: 0,
      bypassFrames: 0,
      gatedFrames: 0,
      resamplerUses: 0,
      resamplerInputUnderruns: 0,
      resamplerOutputUnderruns: 0,
      resamplerOverruns: 0,
      resamplerMode: 'none',
      resamplerInputFrames: 0,
      resamplerOutputFrames: 0,
      resamplerSourceRateHz: 0,
      resamplerTargetRateHz: 0,
      pipelineMode: NoiseSuppressionPipelineMode.cleanRnnoise,
      vadLowFrames: 0,
      vadMidFrames: 0,
      vadHighFrames: 0,
      referenceVadThreshold: 0.9,
      recentVadAverage: 0,
      speechGraceRemainingFrames: 0,
      referenceSpeechGraceFrames: 20,
      noiseGateClosedGain: 0.03,
      transientSensitivity: 0,
      fastCloseEnabled: false,
      lastGateReason: 'pass',
      lastGateGain: 1,
      lastInputScaleFactor: 1,
      lastVadProbability: 0,
      lastInputRms: 0,
      lastOutputRms: 0,
      lastOutputRatio: 1,
      lastInputPeak: 0,
      lastOutputPeak: 0,
      lastInputMin: 0,
      lastInputMax: 0,
      lastOutputMin: 0,
      lastOutputMax: 0,
      lastInputMaxDelta: 0,
      lastOutputMaxDelta: 0,
      processingApplied: false,
      identityFrames: 0,
      clippingSamples: 0,
      inputClippingSamples: 0,
      outputClippingSamples: 0,
      outputLimiterSamples: 0,
      outputAntiAliasUses: 0,
      nonFiniteSamples: 0,
      callbackAverageProcessingMs: 0,
      callbackMaxProcessingMs: 0,
      callbackBudgetMisses: 0,
      rnnoiseStateResets: 0,
      diagnosticCaptureActive: false,
      diagnosticCaptureFrames: 0,
      diagnosticCaptureDroppedFrames: 0,
      diagnosticCaptureWrittenFiles: 0,
      diagnosticCaptureLastError: '',
      diagnosticCaptureStageFiles: '',
      wasapiSidecarActive: false,
      wasapiSidecarFrames: 0,
      wasapiSidecarDroppedPackets: 0,
      wasapiSidecarWrittenFiles: 0,
      wasapiSidecarSampleRateHz: 0,
      wasapiSidecarChannels: 0,
      wasapiSidecarDeviceResolution: 'not_started',
      wasapiSidecarLastError: '',
      reason: reason,
    );
  }

  factory NoiseSuppressionNativeStatus.fromJson(Map<String, dynamic> json) {
    bool parseBool(Object? value) => value == true || value == 1;

    int parseInt(Object? value, {int fallback = 0}) {
      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      return fallback;
    }

    double parseDouble(Object? value, {double fallback = 0}) {
      if (value is num) {
        return value.toDouble();
      }

      return fallback;
    }

    return NoiseSuppressionNativeStatus(
      supported: parseBool(json['supported']),
      available: parseBool(json['available']),
      requestedEnabled: parseBool(json['requestedEnabled']),
      enabled: parseBool(json['enabled']),
      active: parseBool(json['active']),
      formatMismatchDetected: parseBool(json['formatMismatchDetected']),
      suspiciousOutputDetected: parseBool(json['suspiciousOutputDetected']),
      formatMismatchReason: json['formatMismatchReason'] as String? ?? 'none',
      sampleRateHz: parseInt(json['sampleRateHz']),
      numChannels: parseInt(json['numChannels']),
      expectedFramesPer10ms: parseInt(json['expectedFramesPer10ms']),
      lastNumBands: parseInt(json['lastNumBands']),
      lastNumFrames: parseInt(json['lastNumFrames']),
      lastBufferSize: parseInt(json['lastBufferSize']),
      framesProcessed: parseInt(json['framesProcessed']),
      bypassFrames: parseInt(json['bypassFrames']),
      gatedFrames: parseInt(json['gatedFrames']),
      resamplerUses: parseInt(json['resamplerUses']),
      resamplerInputUnderruns: parseInt(json['resamplerInputUnderruns']),
      resamplerOutputUnderruns: parseInt(json['resamplerOutputUnderruns']),
      resamplerOverruns: parseInt(json['resamplerOverruns']),
      resamplerMode: json['resamplerMode'] as String? ?? 'none',
      resamplerInputFrames: parseInt(json['resamplerInputFrames']),
      resamplerOutputFrames: parseInt(json['resamplerOutputFrames']),
      resamplerSourceRateHz: parseInt(json['resamplerSourceRateHz']),
      resamplerTargetRateHz: parseInt(json['resamplerTargetRateHz']),
      pipelineMode: NoiseSuppressionPipelineMode.fromStatusLabel(
        json['pipelineMode'] as String? ?? 'clean_rnnoise',
      ),
      vadLowFrames: parseInt(json['vadLowFrames']),
      vadMidFrames: parseInt(json['vadMidFrames']),
      vadHighFrames: parseInt(json['vadHighFrames']),
      referenceVadThreshold: parseDouble(
        json['referenceVadThreshold'],
        fallback: 0.9,
      ),
      recentVadAverage: parseDouble(json['recentVadAverage']),
      speechGraceRemainingFrames: parseInt(json['speechGraceRemainingFrames']),
      referenceSpeechGraceFrames: parseInt(
        json['referenceSpeechGraceFrames'],
        fallback: 20,
      ),
      noiseGateClosedGain: parseDouble(
        json['noiseGateClosedGain'],
        fallback: 0.03,
      ),
      transientSensitivity: parseDouble(json['transientSensitivity']),
      fastCloseEnabled: parseBool(json['fastCloseEnabled']),
      lastGateReason: json['lastGateReason'] as String? ?? 'pass',
      lastGateGain: parseDouble(json['lastGateGain'], fallback: 1),
      lastInputScaleFactor: parseDouble(
        json['lastInputScaleFactor'],
        fallback: 1,
      ),
      lastVadProbability: parseDouble(json['lastVadProbability']),
      lastInputRms: parseDouble(json['lastInputRms']),
      lastOutputRms: parseDouble(json['lastOutputRms']),
      lastOutputRatio: parseDouble(json['lastOutputRatio'], fallback: 1),
      lastInputPeak: parseDouble(json['lastInputPeak']),
      lastOutputPeak: parseDouble(json['lastOutputPeak']),
      lastInputMin: parseDouble(json['lastInputMin']),
      lastInputMax: parseDouble(json['lastInputMax']),
      lastOutputMin: parseDouble(json['lastOutputMin']),
      lastOutputMax: parseDouble(json['lastOutputMax']),
      lastInputMaxDelta: parseDouble(json['lastInputMaxDelta']),
      lastOutputMaxDelta: parseDouble(json['lastOutputMaxDelta']),
      processingApplied: parseBool(json['processingApplied']),
      identityFrames: parseInt(json['identityFrames']),
      clippingSamples: parseInt(json['clippingSamples']),
      inputClippingSamples: parseInt(json['inputClippingSamples']),
      outputClippingSamples: parseInt(json['outputClippingSamples']),
      outputLimiterSamples: parseInt(json['outputLimiterSamples']),
      outputAntiAliasUses: parseInt(json['outputAntiAliasUses']),
      nonFiniteSamples: parseInt(json['nonFiniteSamples']),
      callbackAverageProcessingMs: parseDouble(
        json['callbackAverageProcessingMs'],
      ),
      callbackMaxProcessingMs: parseDouble(json['callbackMaxProcessingMs']),
      callbackBudgetMisses: parseInt(json['callbackBudgetMisses']),
      rnnoiseStateResets: parseInt(json['rnnoiseStateResets']),
      diagnosticCaptureActive: parseBool(json['diagnosticCaptureActive']),
      diagnosticCaptureFrames: parseInt(json['diagnosticCaptureFrames']),
      diagnosticCaptureDroppedFrames:
          parseInt(json['diagnosticCaptureDroppedFrames']),
      diagnosticCaptureWrittenFiles:
          parseInt(json['diagnosticCaptureWrittenFiles']),
      diagnosticCaptureLastError:
          json['diagnosticCaptureLastError'] as String? ?? '',
      diagnosticCaptureStageFiles:
          json['diagnosticCaptureStageFiles'] as String? ?? '',
      wasapiSidecarActive: parseBool(json['wasapiSidecarActive']),
      wasapiSidecarFrames: parseInt(json['wasapiSidecarFrames']),
      wasapiSidecarDroppedPackets:
          parseInt(json['wasapiSidecarDroppedPackets']),
      wasapiSidecarWrittenFiles: parseInt(json['wasapiSidecarWrittenFiles']),
      wasapiSidecarSampleRateHz: parseInt(json['wasapiSidecarSampleRateHz']),
      wasapiSidecarChannels: parseInt(json['wasapiSidecarChannels']),
      wasapiSidecarDeviceResolution:
          json['wasapiSidecarDeviceResolution'] as String? ?? 'unknown',
      wasapiSidecarLastError: json['wasapiSidecarLastError'] as String? ?? '',
      reason: json['reason'] as String? ?? 'unknown',
    );
  }
}

abstract class NoiseSuppressionNativeBinding {
  bool get isSupported;

  Future<NoiseSuppressionNativeStatus> initialize({required bool enabled});

  Future<NoiseSuppressionNativeStatus> configure(
    NoiseSuppressionNativeConfig config,
  );

  Future<NoiseSuppressionNativeStatus> setPipelineMode(
    NoiseSuppressionPipelineMode mode,
  );

  Future<NoiseSuppressionNativeStatus> startDiagnosticCapture({
    required String directoryPath,
    required Duration duration,
    int stageMask = NoiseSuppressionDiagnosticStageMask.all,
    bool includeWasapiSidecar = false,
    String? wasapiDeviceId,
  });

  Future<NoiseSuppressionNativeStatus> stopDiagnosticCapture();

  Future<NoiseSuppressionNativeStatus> setEnabled(bool enabled);

  Future<NoiseSuppressionNativeStatus> getStatus();

  Future<NoiseSuppressionNativeStatus> shutdown();
}
