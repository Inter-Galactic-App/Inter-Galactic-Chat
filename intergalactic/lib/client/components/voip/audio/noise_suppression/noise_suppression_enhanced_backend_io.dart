import 'dart:io';

import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';

import 'noise_suppression_enhanced_backend_status.dart';

class NoiseSuppressionEnhancedBackendResolver {
  const NoiseSuppressionEnhancedBackendResolver._();

  static const String _compileTimeModelDirectory = String.fromEnvironment(
    NoiseSuppressionEnhancedBackendConstants.modelDirectoryEnvironment,
    defaultValue: '',
  );
  static const String _compileTimeHushModelDirectory = String.fromEnvironment(
    NoiseSuppressionEnhancedBackendConstants.hushModelDirectoryEnvironment,
    defaultValue: '',
  );

  static Future<NoiseSuppressionEnhancedBackendStatus> resolve({
    required bool requested,
    required bool developerModeEnabled,
    NoiseSuppressionNativeStatus? nativeStatus,
    String? modelDirectoryOverride,
    String? hushModelDirectoryOverride,
    bool hushSupportRequested = false,
  }) async {
    final configuredDirectory = _configuredModelDirectory(
      modelDirectoryOverride,
    );
    final configuredHushDirectory = _configuredHushModelDirectory(
      hushModelDirectoryOverride,
      configuredDirectory,
    );
    final modelDirectoryConfigured = configuredDirectory != null;
    final hushModelDirectoryConfigured = configuredHushDirectory != null;

    if (!requested) {
      return NoiseSuppressionEnhancedBackendStatus.notRequested(
        modelDirectoryConfigured: modelDirectoryConfigured,
      );
    }

    if (!_isSupportedPlatform) {
      return _blocked(
        requested: true,
        developerModeAllowed: developerModeEnabled,
        platformSupported: false,
        runtimeKey: 'unsupported',
        reason:
            NoiseSuppressionEnhancedBackendConstants.platformUnsupportedReason,
        modelDirectoryConfigured: modelDirectoryConfigured,
        supportModelDirectoryConfigured: hushModelDirectoryConfigured,
        supportLayerRequested: hushSupportRequested,
        failureLabels: const <String>[
          'enhanced_runtime_unavailable',
          'enhanced_fallback_to_standard',
        ],
      );
    }

    if (PlatformUtils.isMacOS) {
      return _blocked(
        requested: true,
        developerModeAllowed: developerModeEnabled,
        platformSupported: true,
        runtimeKey: NoiseSuppressionEnhancedBackendConstants.macosRuntimeKey,
        reason: 'enhanced_coreml_app_backend_not_implemented',
        modelDirectoryConfigured: modelDirectoryConfigured,
        supportModelDirectoryConfigured: hushModelDirectoryConfigured,
        supportLayerRequested: hushSupportRequested,
        failureLabels: const <String>[
          'enhanced_runtime_unavailable',
          'app_integrated_unproven',
          'enhanced_fallback_to_standard',
        ],
      );
    }

    final hushModelDirectory = configuredHushDirectory == null
        ? null
        : await _resolveHushModelDirectory(Directory(configuredHushDirectory));
    final missingHushFiles = hushModelDirectory == null
        ? const <String>[]
        : await _missingHushModelFiles(hushModelDirectory);

    final nativePipelineSelected =
        nativeStatus?.pipelineMode ==
        NoiseSuppressionPipelineMode.deepFilterNet;
    final runtimeAvailable =
        nativeStatus?.deepFilterNetRuntimeAvailable ?? false;
    final hushRuntimeAvailable =
        nativeStatus?.deepFilterNetHushRuntimeAvailable ?? false;
    final hushAttempted =
        ((nativeStatus?.deepFilterNetHushFramesProcessed ?? 0) > 0) ||
        ((nativeStatus?.deepFilterNetHushBypassFrames ?? 0) > 0);
    final hushModelMissingAfterAttempt =
        hushAttempted &&
        (nativeStatus?.deepFilterNetHushReason ==
            'deepfilternet_model_missing');
    final callbackProcessed =
        (nativeStatus?.deepFilterNetFramesProcessed ?? 0) > 0;
    final callRoomProcessingReady =
        nativePipelineSelected && runtimeAvailable && callbackProcessed;
    final reason =
        nativeStatus?.deepFilterNetReason ??
        (nativePipelineSelected
            ? 'deepfilternet_waiting_for_audio'
            : 'deepfilternet_mode_not_selected');

    return NoiseSuppressionEnhancedBackendStatus(
      requested: true,
      developerModeAllowed: developerModeEnabled || PlatformUtils.isWindows,
      platformSupported: true,
      available: nativePipelineSelected,
      backendKey: NoiseSuppressionEnhancedBackendConstants.backendKey,
      runtimeKey: NoiseSuppressionEnhancedBackendConstants.windowsRuntimeKey,
      reason: reason,
      fallbackMode:
          NoiseSuppressionEnhancedBackendConstants.standardFallbackKey,
      modelDirectoryConfigured: true,
      modelPresent: true,
      missingModelFiles: const <String>[],
      supportBackendKey:
          NoiseSuppressionEnhancedBackendConstants.supportBackendKey,
      supportLayerRequested: hushSupportRequested,
      supportRuntimeKey:
          NoiseSuppressionEnhancedBackendConstants.hushRuntimeKey,
      supportModelDirectoryConfigured: hushModelDirectoryConfigured,
      supportModelPresent:
          hushRuntimeAvailable ||
          (hushModelDirectory != null && missingHushFiles.isEmpty),
      missingSupportModelFiles: missingHushFiles,
      runtimeAvailable: runtimeAvailable,
      appIntegrated: true,
      callbackBufferingProven: callbackProcessed,
      livekitLoopbackProven: callRoomProcessingReady,
      callRoomProcessingReady: callRoomProcessingReady,
      productionDefaultChanged: PlatformUtils.isWindows,
      failureLabels: <String>[
        if (!nativePipelineSelected) 'enhanced_mode_not_selected',
        if (!nativePipelineSelected) 'enhanced_fallback_to_standard',
        if (nativePipelineSelected && !runtimeAvailable)
          'enhanced_runtime_waiting_or_unavailable',
        if (nativePipelineSelected && runtimeAvailable && !callbackProcessed)
          'enhanced_waiting_for_audio',
        if (hushSupportRequested &&
            !hushRuntimeAvailable &&
            (missingHushFiles.isNotEmpty || hushModelMissingAfterAttempt))
          'hush_support_not_bundled',
      ],
    );
  }

  static bool get _isSupportedPlatform =>
      PlatformUtils.isWindows || PlatformUtils.isMacOS;

  static String? _configuredModelDirectory(String? override) {
    final candidates = <String?>[
      override,
      _compileTimeModelDirectory,
      PlatformUtils.environmentVariable(
        NoiseSuppressionEnhancedBackendConstants.modelDirectoryEnvironment,
      ),
    ];

    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String? _configuredHushModelDirectory(
    String? override,
    String? sharedModelDirectory,
  ) {
    final candidates = <String?>[
      override,
      _compileTimeHushModelDirectory,
      PlatformUtils.environmentVariable(
        NoiseSuppressionEnhancedBackendConstants.hushModelDirectoryEnvironment,
      ),
      sharedModelDirectory,
    ];

    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static Future<Directory?> _resolveHushModelDirectory(
    Directory configured,
  ) async {
    final candidates = <Directory>[
      configured,
      Directory('${configured.path}${Platform.pathSeparator}hush'),
    ];

    for (final candidate in candidates) {
      final missingFiles = await _missingHushModelFiles(candidate);
      if (missingFiles.isEmpty) {
        return candidate;
      }
    }
    return candidates.first;
  }

  static Future<List<String>> _missingHushModelFiles(
    Directory? modelDirectory,
  ) async {
    if (modelDirectory == null) {
      return NoiseSuppressionEnhancedBackendConstants.hushModelFiles;
    }

    final missingFiles = <String>[];
    for (final fileName
        in NoiseSuppressionEnhancedBackendConstants.hushModelFiles) {
      final exists = await File(
        '${modelDirectory.path}${Platform.pathSeparator}'
        '${fileName.replaceAll('/', Platform.pathSeparator)}',
      ).exists();
      if (!exists) {
        missingFiles.add(fileName);
      }
    }
    return missingFiles;
  }

  static NoiseSuppressionEnhancedBackendStatus _blocked({
    required bool requested,
    required bool developerModeAllowed,
    required bool platformSupported,
    required String runtimeKey,
    required String reason,
    required bool modelDirectoryConfigured,
    bool modelPresent = false,
    List<String> missingModelFiles = const <String>[],
    bool supportModelDirectoryConfigured = false,
    bool supportLayerRequested = false,
    bool supportModelPresent = false,
    List<String> missingSupportModelFiles = const <String>[],
    required List<String> failureLabels,
  }) {
    return NoiseSuppressionEnhancedBackendStatus(
      requested: requested,
      developerModeAllowed: developerModeAllowed,
      platformSupported: platformSupported,
      available: false,
      backendKey: NoiseSuppressionEnhancedBackendConstants.backendKey,
      runtimeKey: runtimeKey,
      reason: reason,
      fallbackMode:
          NoiseSuppressionEnhancedBackendConstants.standardFallbackKey,
      modelDirectoryConfigured: modelDirectoryConfigured,
      modelPresent: modelPresent,
      missingModelFiles: missingModelFiles,
      supportBackendKey:
          NoiseSuppressionEnhancedBackendConstants.supportBackendKey,
      supportLayerRequested: supportLayerRequested,
      supportRuntimeKey:
          NoiseSuppressionEnhancedBackendConstants.hushRuntimeKey,
      supportModelDirectoryConfigured: supportModelDirectoryConfigured,
      supportModelPresent: supportModelPresent,
      missingSupportModelFiles: missingSupportModelFiles,
      runtimeAvailable: false,
      appIntegrated: false,
      callbackBufferingProven: false,
      livekitLoopbackProven: false,
      callRoomProcessingReady: false,
      productionDefaultChanged: PlatformUtils.isWindows,
      failureLabels: failureLabels,
    );
  }
}
