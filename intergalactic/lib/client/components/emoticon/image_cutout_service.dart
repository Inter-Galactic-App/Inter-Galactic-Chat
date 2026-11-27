import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

enum ImageCutoutBackendType {
  appleVisionSubjectLift,
  androidMlKitSubjectSegmentation,
  onnxBackgroundRemoval,
  localEdgeSegmentation,
  unsupported,
}

enum ImageCutoutFailureCode {
  unsupportedPlatform,
  unsupportedOsVersion,
  modelNotAvailable,
  modelDownloadRequired,
  modelDownloadFailed,
  imageDecodeFailed,
  noSubjectFound,
  multipleSubjectsDetected,
  processingFailed,
  outputWriteFailed,
}

enum ImageCutoutHostPlatform { apple, android, desktop, web, other }

enum CutoutBrushMode { erase, restore }

enum ImageCutoutOperation { generate, render }

typedef ImageCutoutDiagnosticsSink =
    void Function(ImageCutoutDiagnosticEvent event);

class ImageCutoutException implements Exception {
  const ImageCutoutException(this.code, this.message);

  final ImageCutoutFailureCode code;
  final String message;

  @override
  String toString() => 'ImageCutoutException(${code.name}, $message)';
}

class CutoutSettings {
  const CutoutSettings({
    this.backgroundTolerance = 58,
    this.edgeSoftness = 2,
    this.edgeExpansion = 0,
    this.paddingFraction = 0.14,
    this.squareCanvas = true,
    this.outlineWidth = 0,
    this.outlineColor = 0xffffffff,
    this.shadow = false,
    this.maxProcessingDimension = 640,
    this.maxOutputDimension = 512,
  });

  final int backgroundTolerance;
  final int edgeSoftness;
  final int edgeExpansion;
  final double paddingFraction;
  final bool squareCanvas;
  final int outlineWidth;
  final int outlineColor;
  final bool shadow;
  final int maxProcessingDimension;
  final int maxOutputDimension;

  CutoutSettings copyWith({
    int? backgroundTolerance,
    int? edgeSoftness,
    int? edgeExpansion,
    double? paddingFraction,
    bool? squareCanvas,
    int? outlineWidth,
    int? outlineColor,
    bool? shadow,
    int? maxProcessingDimension,
    int? maxOutputDimension,
  }) {
    return CutoutSettings(
      backgroundTolerance: backgroundTolerance ?? this.backgroundTolerance,
      edgeSoftness: edgeSoftness ?? this.edgeSoftness,
      edgeExpansion: edgeExpansion ?? this.edgeExpansion,
      paddingFraction: paddingFraction ?? this.paddingFraction,
      squareCanvas: squareCanvas ?? this.squareCanvas,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      outlineColor: outlineColor ?? this.outlineColor,
      shadow: shadow ?? this.shadow,
      maxProcessingDimension:
          maxProcessingDimension ?? this.maxProcessingDimension,
      maxOutputDimension: maxOutputDimension ?? this.maxOutputDimension,
    );
  }
}

class CutoutMask {
  const CutoutMask({
    required this.width,
    required this.height,
    required this.alpha,
  });

  final int width;
  final int height;
  final Uint8List alpha;

  /// Applies a soft-edged brush dab to the mask.
  ///
  /// [strength] (0..1) scales how far each pixel moves toward the brush target
  /// (fully erased or fully restored) in a single dab, so a partial-opacity
  /// brush builds up gradually over repeated strokes. A strength of 1 keeps the
  /// original full-strength behaviour.
  CutoutMask applyBrush({
    required double normalizedX,
    required double normalizedY,
    required double radiusFraction,
    required CutoutBrushMode mode,
    double strength = 1.0,
  }) {
    final clampedStrength = strength.clamp(0.0, 1.0).toDouble();
    if (clampedStrength <= 0) {
      return this;
    }
    final next = Uint8List.fromList(alpha);
    final centerX = (normalizedX.clamp(0, 1) * (width - 1)).round();
    final centerY = (normalizedY.clamp(0, 1) * (height - 1)).round();
    final radius = math.max(2, (math.min(width, height) * radiusFraction));
    final radiusSquared = radius * radius;
    final minX = math.max(0, (centerX - radius).floor());
    final maxX = math.min(width - 1, (centerX + radius).ceil());
    final minY = math.max(0, (centerY - radius).floor());
    final maxY = math.min(height - 1, (centerY + radius).ceil());

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        final distanceSquared = dx * dx + dy * dy;
        if (distanceSquared > radiusSquared) {
          continue;
        }

        final falloff = 1 - (math.sqrt(distanceSquared) / radius).clamp(0, 1);
        final weight = falloff * clampedStrength;
        final index = y * width + x;
        final current = next[index];
        // Move the pixel toward the target (255 restore / 0 erase) by the
        // brush weight so opacity builds up instead of snapping.
        final target = mode == CutoutBrushMode.restore ? 255 : 0;
        final blended = (current + (target - current) * weight).round().clamp(
          0,
          255,
        );
        next[index] = mode == CutoutBrushMode.restore
            ? math.max(current, blended)
            : math.min(current, blended);
      }
    }

    return CutoutMask(width: width, height: height, alpha: next);
  }
}

class CutoutIntRect {
  const CutoutIntRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left + 1;
  int get height => bottom - top + 1;
}

class CutoutResult {
  const CutoutResult({
    required this.pngBytes,
    required this.thumbnailBytes,
    required this.mask,
    required this.backend,
    required this.subjectBounds,
    required this.cropBounds,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.width,
    required this.height,
    required this.processingDuration,
  });

  final Uint8List pngBytes;
  final Uint8List thumbnailBytes;
  final CutoutMask mask;
  final ImageCutoutBackendType backend;
  final CutoutIntRect subjectBounds;
  final CutoutIntRect cropBounds;
  final int sourceWidth;
  final int sourceHeight;
  final int width;
  final int height;
  final Duration processingDuration;

  CutoutResult copyWith({
    Uint8List? pngBytes,
    Uint8List? thumbnailBytes,
    CutoutMask? mask,
    ImageCutoutBackendType? backend,
    CutoutIntRect? subjectBounds,
    CutoutIntRect? cropBounds,
    int? sourceWidth,
    int? sourceHeight,
    int? width,
    int? height,
    Duration? processingDuration,
  }) {
    return CutoutResult(
      pngBytes: pngBytes ?? this.pngBytes,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      mask: mask ?? this.mask,
      backend: backend ?? this.backend,
      subjectBounds: subjectBounds ?? this.subjectBounds,
      cropBounds: cropBounds ?? this.cropBounds,
      sourceWidth: sourceWidth ?? this.sourceWidth,
      sourceHeight: sourceHeight ?? this.sourceHeight,
      width: width ?? this.width,
      height: height ?? this.height,
      processingDuration: processingDuration ?? this.processingDuration,
    );
  }
}

class ImageCutoutDiagnosticEvent {
  const ImageCutoutDiagnosticEvent({
    required this.operation,
    required this.hostPlatform,
    required this.preferredBackend,
    required this.selectedBackend,
    required this.backend,
    required this.usesFallback,
    required this.preferredBackendAvailable,
    required this.selectedBackendAvailable,
    required this.requiresNativeBridge,
    required this.requiresModelArtifact,
    required this.success,
    required this.duration,
    required this.inputByteCount,
    this.failureCode,
    this.sourceWidth,
    this.sourceHeight,
    this.outputWidth,
    this.outputHeight,
    this.maskWidth,
    this.maskHeight,
    this.outputPngByteCount,
    this.thumbnailByteCount,
  });

  final ImageCutoutOperation operation;
  final ImageCutoutHostPlatform hostPlatform;
  final ImageCutoutBackendType preferredBackend;
  final ImageCutoutBackendType selectedBackend;
  final ImageCutoutBackendType backend;
  final bool usesFallback;
  final bool preferredBackendAvailable;
  final bool selectedBackendAvailable;
  final bool requiresNativeBridge;
  final bool requiresModelArtifact;
  final bool success;
  final ImageCutoutFailureCode? failureCode;
  final Duration duration;
  final int inputByteCount;
  final int? sourceWidth;
  final int? sourceHeight;
  final int? outputWidth;
  final int? outputHeight;
  final int? maskWidth;
  final int? maskHeight;
  final int? outputPngByteCount;
  final int? thumbnailByteCount;
}

class ImageCutoutBackendAvailability {
  const ImageCutoutBackendAvailability({
    required this.type,
    required this.isAvailable,
    required this.canRunLocally,
    this.failureCode,
    this.message,
    this.requiresNativeBridge = false,
    this.requiresModelArtifact = false,
  });

  final ImageCutoutBackendType type;
  final bool isAvailable;
  final bool canRunLocally;
  final ImageCutoutFailureCode? failureCode;
  final String? message;
  final bool requiresNativeBridge;
  final bool requiresModelArtifact;

  ImageCutoutBackendAvailability copyWith({
    bool? isAvailable,
    bool? canRunLocally,
    ImageCutoutFailureCode? failureCode,
    bool clearFailureCode = false,
    String? message,
    bool clearMessage = false,
    bool? requiresNativeBridge,
    bool? requiresModelArtifact,
  }) {
    return ImageCutoutBackendAvailability(
      type: type,
      isAvailable: isAvailable ?? this.isAvailable,
      canRunLocally: canRunLocally ?? this.canRunLocally,
      failureCode: clearFailureCode ? null : failureCode ?? this.failureCode,
      message: clearMessage ? null : message ?? this.message,
      requiresNativeBridge: requiresNativeBridge ?? this.requiresNativeBridge,
      requiresModelArtifact:
          requiresModelArtifact ?? this.requiresModelArtifact,
    );
  }
}

class ImageCutoutBackendSelection {
  const ImageCutoutBackendSelection({
    required this.hostPlatform,
    required this.preferredType,
    required this.selectedType,
    required this.preferredAvailability,
    required this.selectedAvailability,
  });

  factory ImageCutoutBackendSelection.explicit(ImageCutoutBackendType type) {
    final availability = ImageCutoutBackendSelector.describe(type);
    return ImageCutoutBackendSelection(
      hostPlatform: ImageCutoutHostPlatform.other,
      preferredType: type,
      selectedType: type,
      preferredAvailability: availability,
      selectedAvailability: availability,
    );
  }

  final ImageCutoutHostPlatform hostPlatform;
  final ImageCutoutBackendType preferredType;
  final ImageCutoutBackendType selectedType;
  final ImageCutoutBackendAvailability preferredAvailability;
  final ImageCutoutBackendAvailability selectedAvailability;

  bool get usesFallback => preferredType != selectedType;

  ImageCutoutFailureCode? get fallbackReasonCode =>
      usesFallback ? preferredAvailability.failureCode : null;
}

class ImageCutoutBackendSelector {
  const ImageCutoutBackendSelector._();

  static const backendAvailability = <ImageCutoutBackendAvailability>[
    ImageCutoutBackendAvailability(
      type: ImageCutoutBackendType.appleVisionSubjectLift,
      isAvailable: false,
      canRunLocally: true,
      failureCode: ImageCutoutFailureCode.unsupportedPlatform,
      message:
          'Apple Vision subject lifting is not registered in this build yet.',
      requiresNativeBridge: true,
    ),
    ImageCutoutBackendAvailability(
      type: ImageCutoutBackendType.androidMlKitSubjectSegmentation,
      isAvailable: false,
      canRunLocally: true,
      failureCode: ImageCutoutFailureCode.modelNotAvailable,
      message:
          'Android ML Kit subject segmentation is not registered in this build yet.',
      requiresNativeBridge: true,
      requiresModelArtifact: true,
    ),
    ImageCutoutBackendAvailability(
      type: ImageCutoutBackendType.onnxBackgroundRemoval,
      isAvailable: false,
      canRunLocally: true,
      failureCode: ImageCutoutFailureCode.modelNotAvailable,
      message:
          'Desktop ONNX background removal has no reviewed model artifact in this build.',
      requiresModelArtifact: true,
    ),
    ImageCutoutBackendAvailability(
      type: ImageCutoutBackendType.localEdgeSegmentation,
      isAvailable: true,
      canRunLocally: true,
    ),
    ImageCutoutBackendAvailability(
      type: ImageCutoutBackendType.unsupported,
      isAvailable: false,
      canRunLocally: false,
      failureCode: ImageCutoutFailureCode.unsupportedPlatform,
      message: 'Background removal is not available on this platform yet.',
    ),
  ];

  static ImageCutoutHostPlatform currentHostPlatform() {
    if (kIsWeb) {
      return ImageCutoutHostPlatform.web;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => ImageCutoutHostPlatform.apple,
      TargetPlatform.android => ImageCutoutHostPlatform.android,
      TargetPlatform.windows ||
      TargetPlatform.linux => ImageCutoutHostPlatform.desktop,
      TargetPlatform.fuchsia => ImageCutoutHostPlatform.other,
    };
  }

  static Set<ImageCutoutBackendType> defaultRegisteredBackendsForRuntime({
    ImageCutoutHostPlatform? explicitHostPlatform,
  }) {
    if (explicitHostPlatform != null || kIsWeb) {
      return const {};
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => const {
        ImageCutoutBackendType.appleVisionSubjectLift,
      },
      TargetPlatform.android => const {
        ImageCutoutBackendType.androidMlKitSubjectSegmentation,
      },
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => const {},
    };
  }

  static ImageCutoutBackendAvailability describe(ImageCutoutBackendType type) {
    return switch (type) {
      ImageCutoutBackendType.appleVisionSubjectLift => _registeredAvailability(
        ImageCutoutBackendType.appleVisionSubjectLift,
      ),
      ImageCutoutBackendType.androidMlKitSubjectSegmentation =>
        _registeredAvailability(
          ImageCutoutBackendType.androidMlKitSubjectSegmentation,
        ),
      ImageCutoutBackendType.onnxBackgroundRemoval => _registeredAvailability(
        ImageCutoutBackendType.onnxBackgroundRemoval,
      ),
      ImageCutoutBackendType.localEdgeSegmentation => _registeredAvailability(
        ImageCutoutBackendType.localEdgeSegmentation,
      ),
      ImageCutoutBackendType.unsupported => _registeredAvailability(
        ImageCutoutBackendType.unsupported,
      ),
    };
  }

  static ImageCutoutBackendAvailability _registeredAvailability(
    ImageCutoutBackendType type,
  ) {
    for (final backend in backendAvailability) {
      if (backend.type == type) {
        return backend;
      }
    }

    throw StateError('No image cutout backend availability registered: $type');
  }

  static ImageCutoutBackendType preferredTypeForHost(
    ImageCutoutHostPlatform hostPlatform,
  ) {
    return switch (hostPlatform) {
      ImageCutoutHostPlatform.apple =>
        ImageCutoutBackendType.appleVisionSubjectLift,
      ImageCutoutHostPlatform.android =>
        ImageCutoutBackendType.androidMlKitSubjectSegmentation,
      ImageCutoutHostPlatform.desktop =>
        ImageCutoutBackendType.onnxBackgroundRemoval,
      ImageCutoutHostPlatform.web ||
      ImageCutoutHostPlatform.other => ImageCutoutBackendType.unsupported,
    };
  }

  static ImageCutoutBackendSelection selectForHost({
    ImageCutoutHostPlatform? hostPlatform,
    bool allowLocalFallback = true,
    Set<ImageCutoutBackendType> registeredBackends = const {},
  }) {
    final host = hostPlatform ?? currentHostPlatform();
    final preferredType = preferredTypeForHost(host);
    final preferred = _availabilityForSelection(
      preferredType,
      registeredBackends,
    );
    if (preferred.isAvailable) {
      return ImageCutoutBackendSelection(
        hostPlatform: host,
        preferredType: preferredType,
        selectedType: preferredType,
        preferredAvailability: preferred,
        selectedAvailability: preferred,
      );
    }

    final local = describe(ImageCutoutBackendType.localEdgeSegmentation);
    if (allowLocalFallback && local.isAvailable) {
      return ImageCutoutBackendSelection(
        hostPlatform: host,
        preferredType: preferredType,
        selectedType: local.type,
        preferredAvailability: preferred,
        selectedAvailability: local,
      );
    }

    return ImageCutoutBackendSelection(
      hostPlatform: host,
      preferredType: preferredType,
      selectedType: preferredType,
      preferredAvailability: preferred,
      selectedAvailability: preferred,
    );
  }

  static ImageCutoutBackend createBackend(
    ImageCutoutBackendSelection selection, {
    ImageCutoutPlatform? platform,
  }) {
    if (selection.selectedType ==
            ImageCutoutBackendType.localEdgeSegmentation &&
        selection.selectedAvailability.isAvailable) {
      return const LocalEdgeSegmentationCutoutBackend();
    }

    if (selection.selectedAvailability.isAvailable &&
        _usesNativeOrModelBackend(selection.selectedType)) {
      return NativeImageCutoutBackend(
        backendType: selection.selectedType,
        platform: platform ?? const MethodChannelImageCutoutPlatform(),
      );
    }

    return UnsupportedImageCutoutBackend(
      backendType: selection.selectedType,
      failureCode:
          selection.selectedAvailability.failureCode ??
          ImageCutoutFailureCode.unsupportedPlatform,
      message:
          selection.selectedAvailability.message ??
          'Background removal is not available on this platform yet.',
    );
  }

  static ImageCutoutBackendAvailability _availabilityForSelection(
    ImageCutoutBackendType type,
    Set<ImageCutoutBackendType> registeredBackends,
  ) {
    final availability = describe(type);
    if (!registeredBackends.contains(type) ||
        !_usesNativeOrModelBackend(type)) {
      return availability;
    }

    return availability.copyWith(
      isAvailable: true,
      clearFailureCode: true,
      clearMessage: true,
    );
  }

  static bool _usesNativeOrModelBackend(ImageCutoutBackendType type) {
    return switch (type) {
      ImageCutoutBackendType.appleVisionSubjectLift ||
      ImageCutoutBackendType.androidMlKitSubjectSegmentation ||
      ImageCutoutBackendType.onnxBackgroundRemoval => true,
      ImageCutoutBackendType.localEdgeSegmentation ||
      ImageCutoutBackendType.unsupported => false,
    };
  }
}

abstract class ImageCutoutBackend {
  ImageCutoutBackendType get type;

  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  });

  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  });
}

abstract class ImageCutoutPlatform {
  Future<CutoutMask> generateMask({
    required ImageCutoutBackendType backendType,
    required Uint8List imageBytes,
    required CutoutSettings settings,
  });
}

class MethodChannelImageCutoutPlatform implements ImageCutoutPlatform {
  const MethodChannelImageCutoutPlatform({
    MethodChannel channel = const MethodChannel(
      'chat.intergalactic.app/image_cutout',
    ),
  }) : _channel = channel;

  static const Duration _platformMaskTimeout = Duration(seconds: 15);

  final MethodChannel _channel;

  @override
  Future<CutoutMask> generateMask({
    required ImageCutoutBackendType backendType,
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    try {
      final response = await _channel
          .invokeMethod<Map<dynamic, dynamic>>(
            'generateMask',
            <String, Object?>{
              'backend': backendType.name,
              'imageBytes': imageBytes,
              'settings': _settingsPlatformMap(settings),
            },
          )
          .timeout(_platformMaskTimeout);
      return _maskFromPlatformResponse(response, backendType);
    } on MissingPluginException {
      final availability = ImageCutoutBackendSelector.describe(backendType);
      throw ImageCutoutException(
        availability.failureCode ?? ImageCutoutFailureCode.unsupportedPlatform,
        availability.message ??
            'The native background-removal backend is not registered.',
      );
    } on PlatformException catch (error) {
      throw ImageCutoutException(
        _failureCodeFromPlatformCode(error.code, backendType),
        _messageForPlatformFailure(error.code, backendType),
      );
    } on TimeoutException {
      throw const ImageCutoutException(
        ImageCutoutFailureCode.processingFailed,
        'Background removal took too long to respond.',
      );
    }
  }

  static Map<String, Object?> _settingsPlatformMap(CutoutSettings settings) {
    return <String, Object?>{
      'backgroundTolerance': settings.backgroundTolerance,
      'edgeSoftness': settings.edgeSoftness,
      'edgeExpansion': settings.edgeExpansion,
      'paddingFraction': settings.paddingFraction,
      'squareCanvas': settings.squareCanvas,
      'outlineWidth': settings.outlineWidth,
      'outlineColor': settings.outlineColor,
      'shadow': settings.shadow,
      'maxProcessingDimension': settings.maxProcessingDimension,
      'maxOutputDimension': settings.maxOutputDimension,
    };
  }

  static CutoutMask _maskFromPlatformResponse(
    Map<dynamic, dynamic>? response,
    ImageCutoutBackendType backendType,
  ) {
    final width = response?['width'];
    final height = response?['height'];
    final alpha = _alphaBytesFromPlatformValue(response?['alpha']);
    if (width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0 ||
        alpha == null ||
        alpha.length != width * height) {
      throw ImageCutoutException(
        _failureCodeFromPlatformCode('processing_failed', backendType),
        _messageForPlatformFailure('processing_failed', backendType),
      );
    }

    return CutoutMask(width: width, height: height, alpha: alpha);
  }

  static Uint8List? _alphaBytesFromPlatformValue(Object? value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is ByteData) {
      return value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);
    }
    if (value is List) {
      final bytes = Uint8List(value.length);
      for (var i = 0; i < value.length; i++) {
        final byte = value[i];
        if (byte is! int || byte < 0 || byte > 255) {
          return null;
        }
        bytes[i] = byte;
      }
      return bytes;
    }
    return null;
  }

  static ImageCutoutFailureCode _failureCodeFromPlatformCode(
    String? code,
    ImageCutoutBackendType backendType,
  ) {
    final normalized = (code ?? '')
        .replaceAll(RegExp('[-_]'), '')
        .toLowerCase();
    return switch (normalized) {
      'unsupportedplatform' => ImageCutoutFailureCode.unsupportedPlatform,
      'unsupportedosversion' => ImageCutoutFailureCode.unsupportedOsVersion,
      'modelnotavailable' => ImageCutoutFailureCode.modelNotAvailable,
      'modeldownloadrequired' => ImageCutoutFailureCode.modelDownloadRequired,
      'modeldownloadfailed' => ImageCutoutFailureCode.modelDownloadFailed,
      'imagedecodefailed' => ImageCutoutFailureCode.imageDecodeFailed,
      'nosubjectfound' => ImageCutoutFailureCode.noSubjectFound,
      'multiplesubjectsdetected' =>
        ImageCutoutFailureCode.multipleSubjectsDetected,
      'outputwritefailed' => ImageCutoutFailureCode.outputWriteFailed,
      'processingfailed' => ImageCutoutFailureCode.processingFailed,
      _ =>
        ImageCutoutBackendSelector.describe(backendType).failureCode ??
            ImageCutoutFailureCode.processingFailed,
    };
  }

  static String _messageForPlatformFailure(
    String? code,
    ImageCutoutBackendType backendType,
  ) {
    final failureCode = _failureCodeFromPlatformCode(code, backendType);
    return switch (failureCode) {
      ImageCutoutFailureCode.unsupportedPlatform =>
        'Background removal is not available on this platform yet.',
      ImageCutoutFailureCode.unsupportedOsVersion =>
        'This OS version does not support the selected background-removal backend.',
      ImageCutoutFailureCode.modelNotAvailable =>
        'The background-removal model is not available in this build yet.',
      ImageCutoutFailureCode.modelDownloadRequired =>
        'The background-removal model must be prepared before this image can be processed.',
      ImageCutoutFailureCode.modelDownloadFailed =>
        'The background-removal model could not be prepared.',
      ImageCutoutFailureCode.imageDecodeFailed =>
        'The selected image could not be decoded.',
      ImageCutoutFailureCode.noSubjectFound =>
        'No distinct foreground subject was found.',
      ImageCutoutFailureCode.multipleSubjectsDetected =>
        'Multiple foreground subjects were detected and this backend could not choose one.',
      ImageCutoutFailureCode.outputWriteFailed =>
        'The transparent PNG could not be written.',
      ImageCutoutFailureCode.processingFailed =>
        'Background removal could not process this image.',
    };
  }
}

class ImageCutoutService {
  factory ImageCutoutService({
    ImageCutoutBackend? backend,
    ImageCutoutHostPlatform? hostPlatform,
    bool allowLocalFallback = true,
    ImageCutoutPlatform? platform,
    Set<ImageCutoutBackendType>? registeredBackends,
    ImageCutoutDiagnosticsSink? onDiagnostics,
  }) {
    if (backend != null) {
      return ImageCutoutService._(
        backend: backend,
        selection: ImageCutoutBackendSelection.explicit(backend.type),
        onDiagnostics: onDiagnostics,
      );
    }

    final selection = ImageCutoutBackendSelector.selectForHost(
      hostPlatform: hostPlatform,
      allowLocalFallback: allowLocalFallback,
      registeredBackends:
          registeredBackends ??
          ImageCutoutBackendSelector.defaultRegisteredBackendsForRuntime(
            explicitHostPlatform: hostPlatform,
          ),
    );
    final selectedBackend = ImageCutoutBackendSelector.createBackend(
      selection,
      platform: platform,
    );
    return ImageCutoutService._(
      backend:
          allowLocalFallback &&
              selection.selectedType !=
                  ImageCutoutBackendType.localEdgeSegmentation &&
              selection.selectedAvailability.canRunLocally
          ? LocalFallbackImageCutoutBackend(
              primary: selectedBackend,
              fallback: const LocalEdgeSegmentationCutoutBackend(),
            )
          : selectedBackend,
      selection: selection,
      onDiagnostics: onDiagnostics,
    );
  }

  ImageCutoutService._({
    required this.backend,
    required this.selection,
    this.onDiagnostics,
  });

  final ImageCutoutBackend backend;
  final ImageCutoutBackendSelection selection;
  final ImageCutoutDiagnosticsSink? onDiagnostics;

  ImageCutoutService withAdditionalDiagnostics(
    ImageCutoutDiagnosticsSink diagnostics,
  ) {
    final existingDiagnostics = onDiagnostics;
    return ImageCutoutService._(
      backend: backend,
      selection: selection,
      onDiagnostics: (event) {
        existingDiagnostics?.call(event);
        diagnostics(event);
      },
    );
  }

  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    CutoutSettings settings = const CutoutSettings(),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await backend.generate(
        imageBytes: imageBytes,
        settings: settings,
      );
      _emitDiagnostics(
        operation: ImageCutoutOperation.generate,
        duration: result.processingDuration,
        fallbackDuration: stopwatch.elapsed,
        inputByteCount: imageBytes.length,
        result: result,
      );
      return result;
    } on ImageCutoutException catch (error) {
      _emitDiagnostics(
        operation: ImageCutoutOperation.generate,
        duration: stopwatch.elapsed,
        inputByteCount: imageBytes.length,
        failureCode: error.code,
      );
      rethrow;
    } catch (_) {
      _emitDiagnostics(
        operation: ImageCutoutOperation.generate,
        duration: stopwatch.elapsed,
        inputByteCount: imageBytes.length,
        failureCode: ImageCutoutFailureCode.processingFailed,
      );
      rethrow;
    }
  }

  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    CutoutSettings settings = const CutoutSettings(),
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await backend.render(
        imageBytes: imageBytes,
        mask: mask,
        settings: settings,
      );
      _emitDiagnostics(
        operation: ImageCutoutOperation.render,
        duration: result.processingDuration,
        fallbackDuration: stopwatch.elapsed,
        inputByteCount: imageBytes.length,
        inputMask: mask,
        result: result,
      );
      return result;
    } on ImageCutoutException catch (error) {
      _emitDiagnostics(
        operation: ImageCutoutOperation.render,
        duration: stopwatch.elapsed,
        inputByteCount: imageBytes.length,
        inputMask: mask,
        failureCode: error.code,
      );
      rethrow;
    } catch (_) {
      _emitDiagnostics(
        operation: ImageCutoutOperation.render,
        duration: stopwatch.elapsed,
        inputByteCount: imageBytes.length,
        inputMask: mask,
        failureCode: ImageCutoutFailureCode.processingFailed,
      );
      rethrow;
    }
  }

  void _emitDiagnostics({
    required ImageCutoutOperation operation,
    required Duration duration,
    required int inputByteCount,
    Duration? fallbackDuration,
    CutoutMask? inputMask,
    CutoutResult? result,
    ImageCutoutFailureCode? failureCode,
  }) {
    final sink = onDiagnostics;
    if (sink == null) {
      return;
    }

    sink(
      ImageCutoutDiagnosticEvent(
        operation: operation,
        hostPlatform: selection.hostPlatform,
        preferredBackend: selection.preferredType,
        selectedBackend: selection.selectedType,
        backend: result?.backend ?? selection.selectedType,
        usesFallback:
            selection.usesFallback ||
            (result != null && result.backend != selection.selectedType),
        preferredBackendAvailable: selection.preferredAvailability.isAvailable,
        selectedBackendAvailable: selection.selectedAvailability.isAvailable,
        requiresNativeBridge:
            selection.selectedAvailability.requiresNativeBridge,
        requiresModelArtifact:
            selection.selectedAvailability.requiresModelArtifact,
        success: result != null && failureCode == null,
        failureCode: failureCode,
        duration: duration == Duration.zero
            ? fallbackDuration ?? Duration.zero
            : duration,
        inputByteCount: inputByteCount,
        sourceWidth: result?.sourceWidth,
        sourceHeight: result?.sourceHeight,
        outputWidth: result?.width,
        outputHeight: result?.height,
        maskWidth: result?.mask.width ?? inputMask?.width,
        maskHeight: result?.mask.height ?? inputMask?.height,
        outputPngByteCount: result?.pngBytes.length,
        thumbnailByteCount: result?.thumbnailBytes.length,
      ),
    );
  }
}

class NativeImageCutoutBackend implements ImageCutoutBackend {
  const NativeImageCutoutBackend({
    required this.backendType,
    this.platform = const MethodChannelImageCutoutPlatform(),
  });

  final ImageCutoutBackendType backendType;
  final ImageCutoutPlatform platform;

  @override
  ImageCutoutBackendType get type => backendType;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    final stopwatch = Stopwatch()..start();
    final mask = await platform.generateMask(
      backendType: type,
      imageBytes: imageBytes,
      settings: settings,
    );
    final refinedMask = _applyNativeMaskSettings(mask, settings);
    final result = await compute(
      _renderCutoutInBackground,
      _RenderCutoutRequest(imageBytes, refinedMask, settings, type),
    );
    stopwatch.stop();
    return result.copyWith(processingDuration: stopwatch.elapsed);
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) {
    return compute(
      _renderCutoutInBackground,
      _RenderCutoutRequest(imageBytes, mask, settings, type),
    );
  }
}

class LocalFallbackImageCutoutBackend implements ImageCutoutBackend {
  const LocalFallbackImageCutoutBackend({
    required this.primary,
    required this.fallback,
  });

  final ImageCutoutBackend primary;
  final ImageCutoutBackend fallback;

  @override
  ImageCutoutBackendType get type => primary.type;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    try {
      return await primary.generate(imageBytes: imageBytes, settings: settings);
    } on ImageCutoutException catch (error) {
      if (!_shouldUseLocalFallback(error.code)) {
        rethrow;
      }
      return fallback.generate(imageBytes: imageBytes, settings: settings);
    }
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) {
    return primary.render(
      imageBytes: imageBytes,
      mask: mask,
      settings: settings,
    );
  }

  static bool _shouldUseLocalFallback(ImageCutoutFailureCode code) {
    return switch (code) {
      ImageCutoutFailureCode.unsupportedPlatform ||
      ImageCutoutFailureCode.unsupportedOsVersion ||
      ImageCutoutFailureCode.modelNotAvailable ||
      ImageCutoutFailureCode.modelDownloadRequired ||
      ImageCutoutFailureCode.modelDownloadFailed => true,
      ImageCutoutFailureCode.imageDecodeFailed ||
      ImageCutoutFailureCode.noSubjectFound ||
      ImageCutoutFailureCode.multipleSubjectsDetected ||
      ImageCutoutFailureCode.processingFailed ||
      ImageCutoutFailureCode.outputWriteFailed => false,
    };
  }
}

class UnsupportedImageCutoutBackend implements ImageCutoutBackend {
  const UnsupportedImageCutoutBackend({
    this.backendType = ImageCutoutBackendType.unsupported,
    this.failureCode = ImageCutoutFailureCode.unsupportedPlatform,
    this.message = 'Background removal is not available on this platform yet.',
  });

  final ImageCutoutBackendType backendType;
  final ImageCutoutFailureCode failureCode;
  final String message;

  @override
  ImageCutoutBackendType get type => backendType;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    throw ImageCutoutException(failureCode, message);
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) async {
    throw ImageCutoutException(failureCode, message);
  }
}

class LocalEdgeSegmentationCutoutBackend implements ImageCutoutBackend {
  const LocalEdgeSegmentationCutoutBackend();

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) {
    return compute(
      _generateCutoutInBackground,
      _GenerateCutoutRequest(imageBytes, settings),
    );
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) {
    return compute(
      _renderCutoutInBackground,
      _RenderCutoutRequest(imageBytes, mask, settings, type),
    );
  }
}

class _GenerateCutoutRequest {
  const _GenerateCutoutRequest(this.imageBytes, this.settings);

  final Uint8List imageBytes;
  final CutoutSettings settings;
}

class _RenderCutoutRequest {
  const _RenderCutoutRequest(
    this.imageBytes,
    this.mask,
    this.settings,
    this.backend,
  );

  final Uint8List imageBytes;
  final CutoutMask mask;
  final CutoutSettings settings;
  final ImageCutoutBackendType backend;
}

CutoutResult _generateCutoutInBackground(_GenerateCutoutRequest request) {
  final stopwatch = Stopwatch()..start();
  final source = _decodeSource(request.imageBytes);
  final working = _resizeForProcessing(
    source,
    request.settings.maxProcessingDimension,
  );
  final mask = _buildConnectedBackgroundMask(working, request.settings);

  return _renderCutout(
    source: source,
    mask: mask,
    settings: request.settings,
    stopwatch: stopwatch,
    backend: ImageCutoutBackendType.localEdgeSegmentation,
  );
}

CutoutResult _renderCutoutInBackground(_RenderCutoutRequest request) {
  final stopwatch = Stopwatch()..start();
  final source = _decodeSource(request.imageBytes);

  return _renderCutout(
    source: source,
    mask: request.mask,
    settings: request.settings,
    stopwatch: stopwatch,
    backend: request.backend,
  );
}

img.Image _decodeSource(Uint8List imageBytes) {
  try {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw const ImageCutoutException(
        ImageCutoutFailureCode.imageDecodeFailed,
        'The selected image could not be decoded.',
      );
    }

    return img.bakeOrientation(decoded).convert(numChannels: 4);
  } on ImageCutoutException {
    rethrow;
  } catch (_) {
    throw const ImageCutoutException(
      ImageCutoutFailureCode.imageDecodeFailed,
      'The selected image could not be decoded.',
    );
  }
}

img.Image _resizeForProcessing(img.Image source, int maxDimension) {
  return _scaleToMaxDimension(source, maxDimension);
}

img.Image _scaleToMaxDimension(img.Image source, int maxDimension) {
  final maxSide = math.max(source.width, source.height);
  if (maxSide <= maxDimension) {
    return source;
  }

  final scale = maxDimension / maxSide;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
  );
}

CutoutMask _buildConnectedBackgroundMask(
  img.Image source,
  CutoutSettings settings,
) {
  final width = source.width;
  final height = source.height;
  final background = Uint8List(width * height);
  final queue = ListQueue<int>();
  final average = _averageBorderColor(source);
  final tolerance = settings.backgroundTolerance;

  void enqueueIfBackgroundLike(int x, int y, [_Rgb? previous]) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return;
    }

    final index = y * width + x;
    if (background[index] != 0) {
      return;
    }

    final color = _pixelRgb(source, x, y);
    final alpha = source.getPixel(x, y).a;
    final closeToBorder = _colorDistance(color, average) <= tolerance;
    final closeToPrevious =
        previous == null ||
        _colorDistance(color, previous) <= (tolerance * 0.78).round();

    if (alpha <= 8 || (closeToBorder && closeToPrevious)) {
      background[index] = 1;
      queue.add(index);
    }
  }

  for (var x = 0; x < width; x++) {
    enqueueIfBackgroundLike(x, 0);
    enqueueIfBackgroundLike(x, height - 1);
  }
  for (var y = 0; y < height; y++) {
    enqueueIfBackgroundLike(0, y);
    enqueueIfBackgroundLike(width - 1, y);
  }

  while (queue.isNotEmpty) {
    final index = queue.removeFirst();
    final x = index % width;
    final y = index ~/ width;
    final current = _pixelRgb(source, x, y);
    enqueueIfBackgroundLike(x + 1, y, current);
    enqueueIfBackgroundLike(x - 1, y, current);
    enqueueIfBackgroundLike(x, y + 1, current);
    enqueueIfBackgroundLike(x, y - 1, current);
  }

  final alpha = Uint8List(width * height);
  var foregroundCount = 0;
  for (var i = 0; i < alpha.length; i++) {
    if (background[i] == 0) {
      alpha[i] = 255;
      foregroundCount++;
    }
  }

  final foregroundRatio = foregroundCount / alpha.length;
  if (foregroundRatio < 0.012 || foregroundRatio > 0.995) {
    throw const ImageCutoutException(
      ImageCutoutFailureCode.noSubjectFound,
      'No distinct foreground subject was found.',
    );
  }

  var mask = CutoutMask(width: width, height: height, alpha: alpha);
  mask = _shiftMaskEdges(mask, settings.edgeExpansion);
  for (var i = 0; i < settings.edgeSoftness.clamp(0, 4); i++) {
    mask = _boxBlurAlpha(mask);
  }
  return mask;
}

CutoutResult _renderCutout({
  required img.Image source,
  required CutoutMask mask,
  required CutoutSettings settings,
  required Stopwatch stopwatch,
  required ImageCutoutBackendType backend,
}) {
  final bounds = _subjectBounds(source, mask);
  if (bounds == null) {
    throw const ImageCutoutException(
      ImageCutoutFailureCode.noSubjectFound,
      'No foreground pixels were available after refinement.',
    );
  }

  final longestSubjectSide = math.max(bounds.width, bounds.height);
  final padding = math.max(
    0,
    (longestSubjectSide * settings.paddingFraction).round(),
  );
  var cropLeft = bounds.left - padding;
  var cropTop = bounds.top - padding;
  var cropRight = bounds.right + padding;
  var cropBottom = bounds.bottom + padding;

  if (settings.squareCanvas) {
    final side = math.max(cropRight - cropLeft + 1, cropBottom - cropTop + 1);
    final centerX = (bounds.left + bounds.right) / 2;
    final centerY = (bounds.top + bounds.bottom) / 2;
    cropLeft = (centerX - side / 2).floor();
    cropTop = (centerY - side / 2).floor();
    cropRight = cropLeft + side - 1;
    cropBottom = cropTop + side - 1;
  }

  final canvasWidth = math.max(1, cropRight - cropLeft + 1);
  final canvasHeight = math.max(1, cropBottom - cropTop + 1);
  final cropBounds = CutoutIntRect(
    left: cropLeft,
    top: cropTop,
    right: cropRight,
    bottom: cropBottom,
  );
  final subjectAlpha = Uint8List(canvasWidth * canvasHeight);
  final canvas = img.Image(
    width: canvasWidth,
    height: canvasHeight,
    numChannels: 4,
  )..clear(img.ColorRgba8(0, 0, 0, 0));

  for (var y = 0; y < canvasHeight; y++) {
    for (var x = 0; x < canvasWidth; x++) {
      final sourceX = cropLeft + x;
      final sourceY = cropTop + y;
      final alpha = _alphaAtSource(mask, source, sourceX, sourceY);
      subjectAlpha[y * canvasWidth + x] = alpha;
    }
  }

  if (settings.shadow) {
    _paintShadow(canvas, subjectAlpha);
  }
  if (settings.outlineWidth > 0) {
    _paintOutline(canvas, subjectAlpha, settings);
  }
  _paintSubject(canvas, source, subjectAlpha, cropLeft, cropTop);

  final output = _resizeOutput(canvas, settings.maxOutputDimension);
  final thumbnail = img.copyResize(
    output,
    width: 96,
    height: output.width == 0
        ? 96
        : math.max(1, (96 * output.height / output.width).round()),
  );
  stopwatch.stop();

  return CutoutResult(
    pngBytes: Uint8List.fromList(img.encodePng(output)),
    thumbnailBytes: Uint8List.fromList(img.encodePng(thumbnail)),
    mask: mask,
    backend: backend,
    subjectBounds: bounds,
    cropBounds: cropBounds,
    sourceWidth: source.width,
    sourceHeight: source.height,
    width: output.width,
    height: output.height,
    processingDuration: stopwatch.elapsed,
  );
}

CutoutMask _applyNativeMaskSettings(CutoutMask mask, CutoutSettings settings) {
  var refined = _shiftMaskEdges(mask, settings.edgeExpansion);
  for (var i = 0; i < settings.edgeSoftness.clamp(0, 4); i++) {
    refined = _boxBlurAlpha(refined);
  }
  return refined;
}

CutoutMask _shiftMaskEdges(CutoutMask mask, int amount) {
  final clampedAmount = amount.clamp(-4, 4);
  if (clampedAmount == 0) {
    return mask;
  }

  var shifted = mask;
  for (var i = 0; i < clampedAmount.abs(); i++) {
    shifted = clampedAmount > 0 ? _dilateAlpha(shifted) : _erodeAlpha(shifted);
  }
  return shifted;
}

CutoutMask _dilateAlpha(CutoutMask mask) {
  final next = Uint8List(mask.alpha.length);
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      var strongest = 0;
      for (
        var yy = math.max(0, y - 1);
        yy <= math.min(mask.height - 1, y + 1);
        yy++
      ) {
        for (
          var xx = math.max(0, x - 1);
          xx <= math.min(mask.width - 1, x + 1);
          xx++
        ) {
          strongest = math.max(strongest, mask.alpha[yy * mask.width + xx]);
        }
      }
      next[y * mask.width + x] = strongest;
    }
  }
  return CutoutMask(width: mask.width, height: mask.height, alpha: next);
}

CutoutMask _erodeAlpha(CutoutMask mask) {
  final next = Uint8List(mask.alpha.length);
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      var weakest = 255;
      for (var yy = y - 1; yy <= y + 1; yy++) {
        for (var xx = x - 1; xx <= x + 1; xx++) {
          if (xx < 0 || yy < 0 || xx >= mask.width || yy >= mask.height) {
            weakest = 0;
            continue;
          }
          weakest = math.min(weakest, mask.alpha[yy * mask.width + xx]);
        }
      }
      next[y * mask.width + x] = weakest;
    }
  }
  return CutoutMask(width: mask.width, height: mask.height, alpha: next);
}

CutoutMask _boxBlurAlpha(CutoutMask mask) {
  final next = Uint8List(mask.alpha.length);
  for (var y = 0; y < mask.height; y++) {
    for (var x = 0; x < mask.width; x++) {
      var total = 0;
      var count = 0;
      for (
        var yy = math.max(0, y - 1);
        yy <= math.min(mask.height - 1, y + 1);
        yy++
      ) {
        for (
          var xx = math.max(0, x - 1);
          xx <= math.min(mask.width - 1, x + 1);
          xx++
        ) {
          total += mask.alpha[yy * mask.width + xx];
          count++;
        }
      }
      next[y * mask.width + x] = (total / count).round();
    }
  }
  return CutoutMask(width: mask.width, height: mask.height, alpha: next);
}

CutoutIntRect? _subjectBounds(img.Image source, CutoutMask mask) {
  var left = source.width;
  var top = source.height;
  var right = -1;
  var bottom = -1;

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final alpha = _alphaAtSource(mask, source, x, y);
      if (alpha <= 18) {
        continue;
      }
      left = math.min(left, x);
      top = math.min(top, y);
      right = math.max(right, x);
      bottom = math.max(bottom, y);
    }
  }

  if (right < left || bottom < top) {
    return null;
  }

  return CutoutIntRect(left: left, top: top, right: right, bottom: bottom);
}

int _alphaAtSource(CutoutMask mask, img.Image source, int x, int y) {
  if (x < 0 || y < 0 || x >= source.width || y >= source.height) {
    return 0;
  }

  final maskX = ((x / math.max(1, source.width - 1)) * (mask.width - 1))
      .round();
  final maskY = ((y / math.max(1, source.height - 1)) * (mask.height - 1))
      .round();
  return mask.alpha[maskY * mask.width + maskX];
}

void _paintSubject(
  img.Image canvas,
  img.Image source,
  Uint8List subjectAlpha,
  int cropLeft,
  int cropTop,
) {
  for (var y = 0; y < canvas.height; y++) {
    for (var x = 0; x < canvas.width; x++) {
      final sourceX = cropLeft + x;
      final sourceY = cropTop + y;
      if (sourceX < 0 ||
          sourceY < 0 ||
          sourceX >= source.width ||
          sourceY >= source.height) {
        continue;
      }

      final alpha = subjectAlpha[y * canvas.width + x];
      if (alpha <= 0) {
        continue;
      }

      final pixel = source.getPixel(sourceX, sourceY);
      canvas.setPixelRgba(
        x,
        y,
        pixel.r,
        pixel.g,
        pixel.b,
        (pixel.a * alpha / 255).round(),
      );
    }
  }
}

void _paintOutline(
  img.Image canvas,
  Uint8List subjectAlpha,
  CutoutSettings settings,
) {
  final color = settings.outlineColor;
  final r = (color >> 16) & 0xff;
  final g = (color >> 8) & 0xff;
  final b = color & 0xff;
  final radius = settings.outlineWidth.clamp(1, 16);

  for (var y = 0; y < canvas.height; y++) {
    for (var x = 0; x < canvas.width; x++) {
      final index = y * canvas.width + x;
      if (subjectAlpha[index] > 24) {
        continue;
      }

      var nearSubject = false;
      for (
        var yy = math.max(0, y - radius);
        yy <= math.min(canvas.height - 1, y + radius);
        yy++
      ) {
        for (
          var xx = math.max(0, x - radius);
          xx <= math.min(canvas.width - 1, x + radius);
          xx++
        ) {
          if (subjectAlpha[yy * canvas.width + xx] > 96) {
            nearSubject = true;
            break;
          }
        }
        if (nearSubject) {
          break;
        }
      }

      if (nearSubject) {
        canvas.setPixelRgba(x, y, r, g, b, 220);
      }
    }
  }
}

void _paintShadow(img.Image canvas, Uint8List subjectAlpha) {
  final offset = math.max(
    2,
    (math.min(canvas.width, canvas.height) * 0.025).round(),
  );
  for (var y = 0; y < canvas.height; y++) {
    for (var x = 0; x < canvas.width; x++) {
      final sourceX = x - offset;
      final sourceY = y - offset;
      if (sourceX < 0 || sourceY < 0) {
        continue;
      }
      final alpha = subjectAlpha[sourceY * canvas.width + sourceX];
      if (alpha <= 24 || subjectAlpha[y * canvas.width + x] > 0) {
        continue;
      }
      canvas.setPixelRgba(x, y, 0, 0, 0, (alpha * 0.28).round());
    }
  }
}

img.Image _resizeOutput(img.Image source, int maxDimension) {
  return _scaleToMaxDimension(source, maxDimension);
}

_Rgb _averageBorderColor(img.Image source) {
  var r = 0;
  var g = 0;
  var b = 0;
  var count = 0;
  final step = math.max(1, math.min(source.width, source.height) ~/ 48);

  void add(int x, int y) {
    final color = _pixelRgb(source, x, y);
    r += color.r;
    g += color.g;
    b += color.b;
    count++;
  }

  for (var x = 0; x < source.width; x += step) {
    add(x, 0);
    add(x, source.height - 1);
  }
  for (var y = 0; y < source.height; y += step) {
    add(0, y);
    add(source.width - 1, y);
  }

  return _Rgb((r / count).round(), (g / count).round(), (b / count).round());
}

_Rgb _pixelRgb(img.Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  return _Rgb(pixel.r.round(), pixel.g.round(), pixel.b.round());
}

int _colorDistance(_Rgb a, _Rgb b) {
  final dr = a.r - b.r;
  final dg = a.g - b.g;
  final db = a.b - b.b;
  return math.sqrt(dr * dr + dg * dg + db * db).round();
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
}

@visibleForTesting
bool transparentPngHasAlpha(Uint8List pngBytes) {
  final image = img.decodePng(pngBytes);
  if (image == null) {
    return false;
  }
  for (final pixel in image) {
    if (pixel.a < 255) {
      return true;
    }
  }
  return false;
}
