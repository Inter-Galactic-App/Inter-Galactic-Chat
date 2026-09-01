import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

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
  Int32 deepFilterNetTransientSuppressionEnabled,
  Int32 deepFilterNetHushSuppressionEnabled,
);
typedef _ConfigureDart = int Function(
  double vadThreshold,
  int speechGraceFrames,
  double closedGain,
  double transientSensitivity,
  int fastCloseEnabled,
  int deepFilterNetTransientSuppressionEnabled,
  int deepFilterNetHushSuppressionEnabled,
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
  static const MethodChannel _androidChannel =
      MethodChannel('intergalactic_noise_suppression/android');
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
  bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isAndroid;

  void _ensureLoaded() {
    if (_library != null ||
        _loadError != null ||
        !isSupported ||
        Platform.isAndroid) {
      return;
    }

    Object? lastError;
    for (final openLibrary in _libraryOpeners()) {
      try {
        final library = openLibrary();
        _bindLibrary(library);
        _library = library;
        _loadError = null;
        return;
      } catch (error) {
        lastError = error;
      }
    }

    _loadError = lastError ?? 'native_library_unavailable';
  }

  List<DynamicLibrary Function()> _libraryOpeners() {
    if (Platform.isWindows) {
      return <DynamicLibrary Function()>[
        () => DynamicLibrary.open(
              'intergalactic_noise_suppression_plugin.dll',
            ),
      ];
    }

    if (Platform.isMacOS) {
      return <DynamicLibrary Function()>[
        () => DynamicLibrary.process(),
        () => DynamicLibrary.open(
              'intergalactic_noise_suppression.framework/'
              'intergalactic_noise_suppression',
            ),
        () => DynamicLibrary.open(
              '@rpath/intergalactic_noise_suppression.framework/'
              'intergalactic_noise_suppression',
            ),
      ];
    }

    return const <DynamicLibrary Function()>[];
  }

  void _bindLibrary(DynamicLibrary library) {
    final initialize =
        library.lookupFunction<_InitializeNative, _InitializeDart>(
      'intergalactic_noise_suppression_initialize',
    );
    _ConfigureDart? configure;
    _SetPipelineModeDart? setPipelineMode;
    _StartDiagnosticCaptureDart? startDiagnosticCapture;
    _StartTapOrderCaptureDart? startTapOrderCapture;
    _StopDiagnosticCaptureDart? stopDiagnosticCapture;
    final setEnabled =
        library.lookupFunction<_SetEnabledNative, _SetEnabledDart>(
      'intergalactic_noise_suppression_set_enabled',
    );
    final getStatusJson =
        library.lookupFunction<_GetStatusJsonNative, _GetStatusJsonDart>(
      'intergalactic_noise_suppression_get_status_json',
    );
    final shutdown = library.lookupFunction<_ShutdownNative, _ShutdownDart>(
      'intergalactic_noise_suppression_shutdown',
    );

    try {
      configure = library.lookupFunction<_ConfigureNative, _ConfigureDart>(
        'intergalactic_noise_suppression_configure',
      );
    } catch (_) {
      configure = null;
    }
    try {
      setPipelineMode =
          library.lookupFunction<_SetPipelineModeNative, _SetPipelineModeDart>(
        'intergalactic_noise_suppression_set_pipeline_mode',
      );
    } catch (_) {
      setPipelineMode = null;
    }
    try {
      startDiagnosticCapture = library.lookupFunction<
          _StartDiagnosticCaptureNative, _StartDiagnosticCaptureDart>(
        'intergalactic_noise_suppression_start_diagnostic_capture',
      );
    } catch (_) {
      startDiagnosticCapture = null;
    }
    try {
      startTapOrderCapture = library.lookupFunction<_StartTapOrderCaptureNative,
          _StartTapOrderCaptureDart>(
        'intergalactic_noise_suppression_start_tap_order_capture',
      );
    } catch (_) {
      startTapOrderCapture = null;
    }
    try {
      stopDiagnosticCapture = library.lookupFunction<
          _StopDiagnosticCaptureNative, _StopDiagnosticCaptureDart>(
        'intergalactic_noise_suppression_stop_diagnostic_capture',
      );
    } catch (_) {
      stopDiagnosticCapture = null;
    }

    _initialize = initialize;
    _configure = configure;
    _setPipelineMode = setPipelineMode;
    _startDiagnosticCapture = startDiagnosticCapture;
    _startTapOrderCapture = startTapOrderCapture;
    _stopDiagnosticCapture = stopDiagnosticCapture;
    _setEnabled = setEnabled;
    _getStatusJson = getStatusJson;
    _shutdown = shutdown;
  }

  Future<NoiseSuppressionNativeStatus> _readAndroidStatus(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      final result = await _androidChannel.invokeMethod<Map<dynamic, dynamic>>(
        method,
        arguments,
      );
      return NoiseSuppressionNativeStatus.fromJson(
        Map<String, dynamic>.from(result ?? const <dynamic, dynamic>{}),
      );
    } on MissingPluginException {
      return NoiseSuppressionNativeStatus.unavailable(
        supported: true,
        requestedEnabled: arguments?['enabled'] == true,
        reason: 'android_plugin_unavailable',
      );
    } on PlatformException {
      return NoiseSuppressionNativeStatus.unavailable(
        supported: true,
        requestedEnabled: arguments?['enabled'] == true,
        reason: 'android_channel_error',
      );
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
  Future<NoiseSuppressionPlatformAudioStatus> getPlatformAudioStatus() async {
    if (Platform.isAndroid) {
      try {
        final result =
            await _androidChannel.invokeMethod<Map<dynamic, dynamic>>(
          'getPlatformAudioStatus',
        );
        return NoiseSuppressionPlatformAudioStatus.fromJson(
          Map<String, dynamic>.from(result ?? const <dynamic, dynamic>{}),
        );
      } on MissingPluginException {
        return NoiseSuppressionPlatformAudioStatus.unavailable(
          platform: 'android',
        );
      } on PlatformException {
        return NoiseSuppressionPlatformAudioStatus.unavailable(
          platform: 'android',
        );
      }
    }
    return NoiseSuppressionPlatformAudioStatus.unavailable(
      platform: Platform.operatingSystem,
    );
  }

  @override
  Future<NoiseSuppressionNativeStatus> getStatus() async {
    if (Platform.isAndroid) {
      return _readAndroidStatus('getStatus');
    }
    if (!isSupported) {
      return NoiseSuppressionNativeStatus.unavailable();
    }

    return _readStatus();
  }

  @override
  Future<NoiseSuppressionNativeStatus> initialize({
    required bool enabled,
  }) async {
    if (Platform.isAndroid) {
      return _readAndroidStatus(
          'initialize', <String, dynamic>{'enabled': enabled});
    }
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
    if (Platform.isAndroid) {
      return _readAndroidStatus('configure');
    }
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
      config.deepFilterNetTransientSuppressionEnabled ? 1 : 0,
      config.deepFilterNetHushSuppressionEnabled ? 1 : 0,
    );
    return _readStatus();
  }

  @override
  Future<NoiseSuppressionNativeStatus> setPipelineMode(
    NoiseSuppressionPipelineMode mode,
  ) async {
    if (Platform.isAndroid) {
      return _readAndroidStatus(
          'setPipelineMode', <String, dynamic>{'mode': mode.nativeValue});
    }
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
    if (Platform.isAndroid) {
      return _readAndroidStatus(
          'setEnabled', <String, dynamic>{'enabled': enabled});
    }
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
    if (Platform.isAndroid) {
      return _readAndroidStatus('shutdown');
    }
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
