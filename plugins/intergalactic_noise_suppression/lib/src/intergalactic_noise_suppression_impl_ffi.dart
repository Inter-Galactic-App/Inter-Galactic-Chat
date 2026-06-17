import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'intergalactic_noise_suppression_interface.dart';

typedef _InitializeNative = Int32 Function();
typedef _InitializeDart = int Function();

typedef _ConfigureNative = Int32 Function(
  Double vadThreshold,
  Int32 speechGraceFrames,
  Double closedGain,
  Double transientSensitivity,
  Int32 fastCloseEnabled,
);
typedef _ConfigureDart = int Function(
  double vadThreshold,
  int speechGraceFrames,
  double closedGain,
  double transientSensitivity,
  int fastCloseEnabled,
);

typedef _SetPipelineModeNative = Int32 Function(Int32 mode);
typedef _SetPipelineModeDart = int Function(int mode);

typedef _StartDiagnosticCaptureNative = Int32 Function(
  Pointer<Utf8> directory,
  Int32 durationMs,
  Int32 stageMask,
);
typedef _StartDiagnosticCaptureDart = int Function(
  Pointer<Utf8> directory,
  int durationMs,
  int stageMask,
);

typedef _StartTapOrderCaptureNative = Int32 Function(
  Pointer<Utf8> directory,
  Int32 durationMs,
  Int32 stageMask,
  Int32 includeWasapiSidecar,
  Pointer<Utf8> wasapiDeviceId,
);
typedef _StartTapOrderCaptureDart = int Function(
  Pointer<Utf8> directory,
  int durationMs,
  int stageMask,
  int includeWasapiSidecar,
  Pointer<Utf8> wasapiDeviceId,
);

typedef _StopDiagnosticCaptureNative = Int32 Function();
typedef _StopDiagnosticCaptureDart = int Function();

typedef _SetEnabledNative = Int32 Function(Int32 enabled);
typedef _SetEnabledDart = int Function(int enabled);

typedef _GetStatusJsonNative = Pointer<Utf8> Function();
typedef _GetStatusJsonDart = Pointer<Utf8> Function();

typedef _ShutdownNative = Int32 Function();
typedef _ShutdownDart = int Function();

NoiseSuppressionNativeBinding createNoiseSuppressionNativeBinding() {
  return _FfiNoiseSuppressionNativeBinding();
}

class _FfiNoiseSuppressionNativeBinding
    implements NoiseSuppressionNativeBinding {
  DynamicLibrary? _library;
  Object? _loadError;

  late final _InitializeDart _initialize;
  _ConfigureDart? _configure;
  _SetPipelineModeDart? _setPipelineMode;
  _StartDiagnosticCaptureDart? _startDiagnosticCapture;
  _StartTapOrderCaptureDart? _startTapOrderCapture;
  _StopDiagnosticCaptureDart? _stopDiagnosticCapture;
  late final _SetEnabledDart _setEnabled;
  late final _GetStatusJsonDart _getStatusJson;
  late final _ShutdownDart _shutdown;

  @override
  bool get isSupported => Platform.isWindows;

  void _ensureLoaded() {
    if (_library != null || _loadError != null || !isSupported) {
      return;
    }

    try {
      _library = DynamicLibrary.open(
        'intergalactic_noise_suppression_plugin.dll',
      );
      _initialize =
          _library!.lookupFunction<_InitializeNative, _InitializeDart>(
        'intergalactic_noise_suppression_initialize',
      );
      try {
        _configure = _library!.lookupFunction<_ConfigureNative, _ConfigureDart>(
          'intergalactic_noise_suppression_configure',
        );
      } catch (_) {
        _configure = null;
      }
      try {
        _setPipelineMode = _library!
            .lookupFunction<_SetPipelineModeNative, _SetPipelineModeDart>(
          'intergalactic_noise_suppression_set_pipeline_mode',
        );
      } catch (_) {
        _setPipelineMode = null;
      }
      try {
        _startDiagnosticCapture = _library!.lookupFunction<
            _StartDiagnosticCaptureNative, _StartDiagnosticCaptureDart>(
          'intergalactic_noise_suppression_start_diagnostic_capture',
        );
      } catch (_) {
        _startDiagnosticCapture = null;
      }
      try {
        _startTapOrderCapture = _library!.lookupFunction<
            _StartTapOrderCaptureNative, _StartTapOrderCaptureDart>(
          'intergalactic_noise_suppression_start_tap_order_capture',
        );
      } catch (_) {
        _startTapOrderCapture = null;
      }
      try {
        _stopDiagnosticCapture = _library!.lookupFunction<
            _StopDiagnosticCaptureNative, _StopDiagnosticCaptureDart>(
          'intergalactic_noise_suppression_stop_diagnostic_capture',
        );
      } catch (_) {
        _stopDiagnosticCapture = null;
      }
      _setEnabled =
          _library!.lookupFunction<_SetEnabledNative, _SetEnabledDart>(
        'intergalactic_noise_suppression_set_enabled',
      );
      _getStatusJson =
          _library!.lookupFunction<_GetStatusJsonNative, _GetStatusJsonDart>(
        'intergalactic_noise_suppression_get_status_json',
      );
      _shutdown = _library!.lookupFunction<_ShutdownNative, _ShutdownDart>(
        'intergalactic_noise_suppression_shutdown',
      );
    } catch (error) {
      _loadError = error;
    }
  }

  NoiseSuppressionNativeStatus _loadFailureStatus({
    bool requestedEnabled = false,
  }) {
    return NoiseSuppressionNativeStatus.unavailable(
      supported: isSupported,
      requestedEnabled: requestedEnabled,
      reason: _loadError == null
          ? 'native_library_unavailable'
          : 'native_library_load_failed',
    );
  }

  NoiseSuppressionNativeStatus _readStatus({bool requestedEnabled = false}) {
    _ensureLoaded();
    if (_library == null) {
      return _loadFailureStatus(requestedEnabled: requestedEnabled);
    }

    final statusPointer = _getStatusJson();
    if (statusPointer.address == 0) {
      return NoiseSuppressionNativeStatus.unavailable(
        supported: true,
        requestedEnabled: requestedEnabled,
        reason: 'status_pointer_unavailable',
      );
    }

    final rawStatus = statusPointer.toDartString();
    if (rawStatus.isEmpty) {
      return NoiseSuppressionNativeStatus.unavailable(
        supported: true,
        requestedEnabled: requestedEnabled,
        reason: 'status_empty',
      );
    }

    try {
      final decoded = jsonDecode(rawStatus) as Map<String, dynamic>;
      return NoiseSuppressionNativeStatus.fromJson(decoded);
    } catch (_) {
      return NoiseSuppressionNativeStatus.unavailable(
        supported: true,
        requestedEnabled: requestedEnabled,
        reason: 'status_parse_failed',
      );
    }
  }

  @override
  Future<NoiseSuppressionNativeStatus> getStatus() async {
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable();
    }

    return _readStatus();
  }

  @override
  Future<NoiseSuppressionNativeStatus> initialize({
    required bool enabled,
  }) async {
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable(
        requestedEnabled: enabled,
      );
    }

    _ensureLoaded();
    if (_library == null) {
      return _loadFailureStatus(requestedEnabled: enabled);
    }

    _initialize();
    _setEnabled(enabled ? 1 : 0);
    return _readStatus(requestedEnabled: enabled);
  }

  @override
  Future<NoiseSuppressionNativeStatus> configure(
    NoiseSuppressionNativeConfig config,
  ) async {
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable();
    }

    _ensureLoaded();
    if (_library == null) {
      return _loadFailureStatus();
    }

    final configure = _configure;
    if (configure == null) {
      return _readStatus();
    }

    configure(
      config.vadThreshold,
      config.speechGraceFrames,
      config.closedGain,
      config.transientSensitivity,
      config.fastCloseEnabled ? 1 : 0,
    );
    return _readStatus();
  }

  @override
  Future<NoiseSuppressionNativeStatus> setPipelineMode(
    NoiseSuppressionPipelineMode mode,
  ) async {
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable();
    }

    _ensureLoaded();
    if (_library == null) {
      return _loadFailureStatus();
    }

    final setPipelineMode = _setPipelineMode;
    if (setPipelineMode == null) {
      return _readStatus();
    }

    setPipelineMode(mode.nativeValue);
    return _readStatus();
  }

  @override
  Future<NoiseSuppressionNativeStatus> startDiagnosticCapture({
    required String directoryPath,
    required Duration duration,
    int stageMask = NoiseSuppressionDiagnosticStageMask.all,
    bool includeWasapiSidecar = false,
    String? wasapiDeviceId,
  }) async {
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable();
    }

    _ensureLoaded();
    if (_library == null) {
      return _loadFailureStatus();
    }

    final startTapOrderCapture = _startTapOrderCapture;
    final startDiagnosticCapture = _startDiagnosticCapture;
    if (startTapOrderCapture == null && startDiagnosticCapture == null) {
      return NoiseSuppressionNativeStatus.unavailable(
        supported: true,
        reason: 'diagnostic_capture_unavailable',
      );
    }

    final nativePath = directoryPath.toNativeUtf8();
    final nativeDeviceId = (wasapiDeviceId ?? '').toNativeUtf8();
    try {
      if (startTapOrderCapture != null) {
        startTapOrderCapture(
          nativePath,
          duration.inMilliseconds,
          stageMask,
          includeWasapiSidecar ? 1 : 0,
          nativeDeviceId,
        );
      } else {
        startDiagnosticCapture!(
          nativePath,
          duration.inMilliseconds,
          stageMask,
        );
      }
    } finally {
      malloc.free(nativePath);
      malloc.free(nativeDeviceId);
    }
    return _readStatus();
  }

  @override
  Future<NoiseSuppressionNativeStatus> stopDiagnosticCapture() async {
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable();
    }

    _ensureLoaded();
    if (_library == null) {
      return _loadFailureStatus();
    }

    final stopDiagnosticCapture = _stopDiagnosticCapture;
    if (stopDiagnosticCapture == null) {
      return NoiseSuppressionNativeStatus.unavailable(
        supported: true,
        reason: 'diagnostic_capture_unavailable',
      );
    }

    stopDiagnosticCapture();
    return _readStatus();
  }

  @override
  Future<NoiseSuppressionNativeStatus> setEnabled(bool enabled) async {
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable(
        requestedEnabled: enabled,
      );
    }

    _ensureLoaded();
    if (_library == null) {
      return _loadFailureStatus(requestedEnabled: enabled);
    }

    _setEnabled(enabled ? 1 : 0);
    return _readStatus(requestedEnabled: enabled);
  }

  @override
  Future<NoiseSuppressionNativeStatus> shutdown() async {
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable();
    }

    _ensureLoaded();
    if (_library == null) {
      return _loadFailureStatus();
    }

    _shutdown();
    return _readStatus();
  }
}
