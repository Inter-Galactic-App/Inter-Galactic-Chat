import 'intergalactic_noise_suppression_interface.dart';

NoiseSuppressionNativeBinding createNoiseSuppressionNativeBinding() {
  return _StubNoiseSuppressionNativeBinding();
}

class _StubNoiseSuppressionNativeBinding
    implements NoiseSuppressionNativeBinding {
  @override
  bool get isSupported => false;

  @override
  Future<NoiseSuppressionPlatformAudioStatus> getPlatformAudioStatus() async {
    return NoiseSuppressionPlatformAudioStatus.unavailable();
  }

  @override
  Future<NoiseSuppressionNativeStatus> getStatus() async {
    return NoiseSuppressionNativeStatus.unavailable();
  }

  @override
  Future<NoiseSuppressionNativeStatus> initialize({
    required bool enabled,
  }) async {
    return NoiseSuppressionNativeStatus.unavailable(
      requestedEnabled: enabled,
    );
  }

  @override
  Future<NoiseSuppressionNativeStatus> configure(
    NoiseSuppressionNativeConfig config,
  ) async {
    return NoiseSuppressionNativeStatus.unavailable(
      reason: 'unsupported_platform',
    );
  }

  @override
  Future<NoiseSuppressionNativeStatus> setPipelineMode(
    NoiseSuppressionPipelineMode mode,
  ) async {
    return NoiseSuppressionNativeStatus.unavailable(
      reason: 'unsupported_platform',
    );
  }

  @override
  Future<NoiseSuppressionNativeStatus> startDiagnosticCapture({
    required String directoryPath,
    required Duration duration,
    int stageMask = NoiseSuppressionDiagnosticStageMask.all,
    bool includeWasapiSidecar = false,
    String? wasapiDeviceId,
  }) async {
    return NoiseSuppressionNativeStatus.unavailable(
      reason: 'unsupported_platform',
    );
  }

  @override
  Future<NoiseSuppressionNativeStatus> stopDiagnosticCapture() async {
    return NoiseSuppressionNativeStatus.unavailable(
      reason: 'unsupported_platform',
    );
  }

  @override
  Future<NoiseSuppressionNativeStatus> setEnabled(bool enabled) async {
    return NoiseSuppressionNativeStatus.unavailable(
      requestedEnabled: enabled,
    );
  }

  @override
  Future<NoiseSuppressionNativeStatus> shutdown() async {
    return NoiseSuppressionNativeStatus.unavailable();
  }
}
