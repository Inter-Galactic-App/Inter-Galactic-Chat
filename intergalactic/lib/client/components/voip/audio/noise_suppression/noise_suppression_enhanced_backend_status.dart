class NoiseSuppressionEnhancedBackendConstants {
  const NoiseSuppressionEnhancedBackendConstants._();

  static const String preferenceKey = 'enhanced_deepfilternet';
  static const String backendKey = 'deepfilternet';
  static const String supportBackendKey = 'hush';
  static const String windowsRuntimeKey = 'deepfilternet-native';
  static const String hushRuntimeKey = 'hush-onnx';
  static const String macosRuntimeKey = 'deepfilternet-coreml';
  static const String standardFallbackKey = 'standard';
  static const String developerModeRequiredReason =
      'enhanced_developer_mode_required';
  static const String platformUnsupportedReason =
      'enhanced_platform_unsupported';
  static const String modelDirectoryEnvironment =
      'INTERGALACTIC_ENHANCED_NOISE_SUPPRESSION_MODEL_DIR';
  static const String hushModelDirectoryEnvironment =
      'INTERGALACTIC_ENHANCED_NOISE_SUPPRESSION_HUSH_MODEL_DIR';

  static const List<String> bundledModelFiles = <String>[
    'DeepFilterNet3_onnx.tar.gz',
  ];

  static const List<String> hushModelFiles = <String>[
    'onnx/advanced_dfnet16k_model_best_onnx.tar.gz',
  ];
}

class NoiseSuppressionEnhancedBackendStatus {
  const NoiseSuppressionEnhancedBackendStatus({
    required this.requested,
    required this.developerModeAllowed,
    required this.platformSupported,
    required this.available,
    required this.backendKey,
    required this.runtimeKey,
    required this.reason,
    required this.fallbackMode,
    required this.modelDirectoryConfigured,
    required this.modelPresent,
    required this.missingModelFiles,
    required this.supportBackendKey,
    required this.supportLayerRequested,
    required this.supportRuntimeKey,
    required this.supportModelDirectoryConfigured,
    required this.supportModelPresent,
    required this.missingSupportModelFiles,
    required this.runtimeAvailable,
    required this.appIntegrated,
    required this.callbackBufferingProven,
    required this.livekitLoopbackProven,
    required this.callRoomProcessingReady,
    required this.productionDefaultChanged,
    required this.failureLabels,
  });

  factory NoiseSuppressionEnhancedBackendStatus.notRequested({
    bool modelDirectoryConfigured = false,
  }) {
    return NoiseSuppressionEnhancedBackendStatus(
      requested: false,
      developerModeAllowed: false,
      platformSupported: false,
      available: false,
      backendKey: NoiseSuppressionEnhancedBackendConstants.backendKey,
      runtimeKey: 'none',
      reason: 'not_requested',
      fallbackMode:
          NoiseSuppressionEnhancedBackendConstants.standardFallbackKey,
      modelDirectoryConfigured: modelDirectoryConfigured,
      modelPresent: false,
      missingModelFiles: const <String>[],
      supportBackendKey:
          NoiseSuppressionEnhancedBackendConstants.supportBackendKey,
      supportLayerRequested: false,
      supportRuntimeKey:
          NoiseSuppressionEnhancedBackendConstants.hushRuntimeKey,
      supportModelDirectoryConfigured: false,
      supportModelPresent: false,
      missingSupportModelFiles: const <String>[],
      runtimeAvailable: false,
      appIntegrated: false,
      callbackBufferingProven: false,
      livekitLoopbackProven: false,
      callRoomProcessingReady: false,
      productionDefaultChanged: false,
      failureLabels: const <String>[],
    );
  }

  final bool requested;
  final bool developerModeAllowed;
  final bool platformSupported;
  final bool available;
  final String backendKey;
  final String runtimeKey;
  final String reason;
  final String fallbackMode;
  final bool modelDirectoryConfigured;
  final bool modelPresent;
  final List<String> missingModelFiles;
  final String supportBackendKey;
  final bool supportLayerRequested;
  final String supportRuntimeKey;
  final bool supportModelDirectoryConfigured;
  final bool supportModelPresent;
  final List<String> missingSupportModelFiles;
  final bool runtimeAvailable;
  final bool appIntegrated;
  final bool callbackBufferingProven;
  final bool livekitLoopbackProven;
  final bool callRoomProcessingReady;
  final bool productionDefaultChanged;
  final List<String> failureLabels;

  bool get fallbackActive => requested && !available;

  String get statusLabel {
    if (!requested) {
      return 'not requested';
    }
    if (available) {
      return 'available';
    }
    return 'fallback to Standard';
  }

  String get modelDirectoryLabel =>
      modelDirectoryConfigured ? 'configured' : 'not configured';

  List<String> get diagnosticsLines {
    final lines = <String>[
      'Enhanced backend: $statusLabel; requested=$requested; '
          'backend=$backendKey; runtime=$runtimeKey; reason=$reason',
      'Enhanced model: directory=$modelDirectoryLabel; '
          'present=$modelPresent; '
          'missing=${missingModelFiles.isEmpty ? 'none' : missingModelFiles.join(', ')}',
      'Enhanced support: backend=$supportBackendKey; '
          'requested=$supportLayerRequested; '
          'runtime=$supportRuntimeKey; '
          'directory=${supportModelDirectoryConfigured ? 'configured' : 'not configured'}; '
          'present=$supportModelPresent; '
          'missing=${missingSupportModelFiles.isEmpty ? 'none' : missingSupportModelFiles.join(', ')}',
      'Enhanced gates: runtime=$runtimeAvailable; '
          'appIntegrated=$appIntegrated; '
          'callbackBuffering=$callbackBufferingProven; '
          'livekitLoopback=$livekitLoopbackProven; '
          'callRoomProcessing=$callRoomProcessingReady; '
          'productionDefaultChanged=$productionDefaultChanged',
    ];
    if (failureLabels.isNotEmpty) {
      lines.add('Enhanced labels: ${failureLabels.join(', ')}');
    }
    if (fallbackActive) {
      lines.add(
        'Enhanced fallback: calls continue on $fallbackMode; native audio remains fail-open.',
      );
    }
    if (requested && !callRoomProcessingReady) {
      lines.add(
        'Enhanced call-room test: DeepFilterNet is bundled for the live microphone callback. Start a call and speak to prove callRoomProcessing=true.',
      );
    }
    return lines;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requested': requested,
      'developerModeAllowed': developerModeAllowed,
      'platformSupported': platformSupported,
      'available': available,
      'backendKey': backendKey,
      'runtimeKey': runtimeKey,
      'reason': reason,
      'fallbackMode': fallbackMode,
      'modelDirectoryConfigured': modelDirectoryConfigured,
      'modelPresent': modelPresent,
      'missingModelFiles': missingModelFiles,
      'supportBackendKey': supportBackendKey,
      'supportLayerRequested': supportLayerRequested,
      'supportRuntimeKey': supportRuntimeKey,
      'supportModelDirectoryConfigured': supportModelDirectoryConfigured,
      'supportModelPresent': supportModelPresent,
      'missingSupportModelFiles': missingSupportModelFiles,
      'runtimeAvailable': runtimeAvailable,
      'appIntegrated': appIntegrated,
      'callbackBufferingProven': callbackBufferingProven,
      'livekitLoopbackProven': livekitLoopbackProven,
      'callRoomProcessingReady': callRoomProcessingReady,
      'productionDefaultChanged': productionDefaultChanged,
      'failureLabels': failureLabels,
    };
  }
}
