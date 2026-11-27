import 'noise_suppression_enhanced_backend_status.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';

class NoiseSuppressionEnhancedBackendResolver {
  const NoiseSuppressionEnhancedBackendResolver._();

  static Future<NoiseSuppressionEnhancedBackendStatus> resolve({
    required bool requested,
    required bool developerModeEnabled,
    NoiseSuppressionNativeStatus? nativeStatus,
    String? modelDirectoryOverride,
    String? hushModelDirectoryOverride,
    bool hushSupportRequested = false,
  }) async {
    final modelDirectoryConfigured =
        modelDirectoryOverride != null && modelDirectoryOverride.isNotEmpty;
    final supportModelDirectoryConfigured =
        hushModelDirectoryOverride != null &&
        hushModelDirectoryOverride.isNotEmpty;
    if (!requested) {
      return NoiseSuppressionEnhancedBackendStatus.notRequested(
        modelDirectoryConfigured: modelDirectoryConfigured,
      );
    }

    const reason =
        NoiseSuppressionEnhancedBackendConstants.platformUnsupportedReason;

    return NoiseSuppressionEnhancedBackendStatus(
      requested: true,
      developerModeAllowed: true,
      platformSupported: false,
      available: false,
      backendKey: NoiseSuppressionEnhancedBackendConstants.backendKey,
      runtimeKey: 'unsupported',
      reason: reason,
      fallbackMode:
          NoiseSuppressionEnhancedBackendConstants.standardFallbackKey,
      modelDirectoryConfigured: modelDirectoryConfigured,
      modelPresent: false,
      missingModelFiles: const <String>[],
      supportBackendKey:
          NoiseSuppressionEnhancedBackendConstants.supportBackendKey,
      supportLayerRequested: hushSupportRequested,
      supportRuntimeKey:
          NoiseSuppressionEnhancedBackendConstants.hushRuntimeKey,
      supportModelDirectoryConfigured: supportModelDirectoryConfigured,
      supportModelPresent: false,
      missingSupportModelFiles: const <String>[],
      runtimeAvailable: false,
      appIntegrated: false,
      callbackBufferingProven: false,
      livekitLoopbackProven: false,
      callRoomProcessingReady: false,
      productionDefaultChanged: false,
      failureLabels: <String>[
        NoiseSuppressionEnhancedBackendConstants.platformUnsupportedReason,
        'enhanced_runtime_unavailable',
        'enhanced_fallback_to_standard',
      ],
    );
  }
}
