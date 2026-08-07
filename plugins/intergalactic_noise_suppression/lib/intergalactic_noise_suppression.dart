import 'src/intergalactic_noise_suppression_impl_stub.dart'
    if (dart.library.ffi) 'src/intergalactic_noise_suppression_impl_ffi.dart';
import 'src/intergalactic_noise_suppression_interface.dart';

export 'src/intergalactic_noise_suppression_interface.dart';

class IntergalacticNoiseSuppression {
  IntergalacticNoiseSuppression._(this._binding);

  static final IntergalacticNoiseSuppression instance =
      IntergalacticNoiseSuppression._(
    createNoiseSuppressionNativeBinding(),
  );

  final NoiseSuppressionNativeBinding _binding;

  bool get isSupported => _binding.isSupported;

  Future<NoiseSuppressionNativeStatus> initialize({required bool enabled}) {
    return _binding.initialize(enabled: enabled);
  }

  Future<NoiseSuppressionNativeStatus> configure(
    NoiseSuppressionNativeConfig config,
  ) {
    return _binding.configure(config);
  }

  Future<NoiseSuppressionNativeStatus> setPipelineMode(
    NoiseSuppressionPipelineMode mode,
  ) {
    return _binding.setPipelineMode(mode);
  }

  Future<NoiseSuppressionNativeStatus> startDiagnosticCapture({
    required String directoryPath,
    required Duration duration,
    int stageMask = NoiseSuppressionDiagnosticStageMask.all,
    bool includeWasapiSidecar = false,
    String? wasapiDeviceId,
  }) {
    return _binding.startDiagnosticCapture(
      directoryPath: directoryPath,
      duration: duration,
      stageMask: stageMask,
      includeWasapiSidecar: includeWasapiSidecar,
      wasapiDeviceId: wasapiDeviceId,
    );
  }

  Future<NoiseSuppressionNativeStatus> stopDiagnosticCapture() {
    return _binding.stopDiagnosticCapture();
  }

  Future<NoiseSuppressionNativeStatus> setEnabled(bool enabled) {
    return _binding.setEnabled(enabled);
  }

  Future<NoiseSuppressionNativeStatus> getStatus() {
    return _binding.getStatus();
  }

  Future<NoiseSuppressionNativeStatus> shutdown() {
    return _binding.shutdown();
  }
}
