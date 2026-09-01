import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'intergalactic_windows_share_interface.dart';

typedef _GetJsonNative = Pointer<Utf8> Function();
typedef WindowsShareGetJsonFunction = Pointer<Utf8> Function();

typedef _GetSessionJsonNative = Pointer<Utf8> Function(Int32 sessionId);
typedef WindowsShareGetSessionJsonFunction = Pointer<Utf8> Function(
    int sessionId);

typedef _CreateSessionNative = Int32 Function(
  Int32 targetType,
  Int32 audioMode,
  Uint32 processId,
  Int32 requestSharedAudio,
  Pointer<Utf8> deviceId,
);
typedef WindowsShareCreateSessionFunction = int Function(
  int targetType,
  int audioMode,
  int processId,
  int requestSharedAudio,
  Pointer<Utf8> deviceId,
);

typedef _SessionCommandNative = Int32 Function(Int32 sessionId);
typedef WindowsShareSessionCommandFunction = int Function(int sessionId);

abstract class WindowsShareNativeSymbolLookup {
  WindowsShareGetJsonFunction lookupGetJson(String symbol);

  WindowsShareGetSessionJsonFunction lookupGetSessionJson(String symbol);

  WindowsShareCreateSessionFunction lookupCreateSession(String symbol);

  WindowsShareSessionCommandFunction lookupSessionCommand(String symbol);
}

WindowsShareNativeBinding createWindowsShareNativeBinding() {
  return _FfiWindowsShareNativeBinding();
}

WindowsShareNativeBinding createWindowsShareNativeBindingForTesting({
  required WindowsShareNativeSymbolLookup symbolLookup,
  bool isSupported = true,
}) {
  return _FfiWindowsShareNativeBinding(
    symbolLookup: symbolLookup,
    isSupportedOverride: isSupported,
  );
}

class _FfiWindowsShareNativeBinding implements WindowsShareNativeBinding {
  _FfiWindowsShareNativeBinding({
    WindowsShareNativeSymbolLookup? symbolLookup,
    bool? isSupportedOverride,
  })  : _symbolLookup = symbolLookup,
        _isSupportedOverride = isSupportedOverride;

  final WindowsShareNativeSymbolLookup? _symbolLookup;
  final bool? _isSupportedOverride;

  DynamicLibrary? _library;
  bool _loaded = false;
  Object? _loadError;

  late final WindowsShareGetJsonFunction _getCapabilitiesJson;
  late final WindowsShareGetJsonFunction _listTargetsJson;
  WindowsShareGetJsonFunction? _listAudioEndpointsJson;
  late final WindowsShareCreateSessionFunction _createSession;
  late final WindowsShareSessionCommandFunction _startSharedAudio;
  late final WindowsShareSessionCommandFunction _stopSharedAudio;
  late final WindowsShareGetSessionJsonFunction _createSharedAudioStreamJson;
  late final WindowsShareSessionCommandFunction _disposeSharedAudioStream;
  late final WindowsShareGetSessionJsonFunction _getSessionStatusJson;
  late final WindowsShareSessionCommandFunction _disposeSession;

  @override
  bool get isSupported => _isSupportedOverride ?? Platform.isWindows;

  bool get _isLoaded => _loaded && _loadError == null;

  void _ensureLoaded() {
    if (_loaded || _loadError != null || !isSupported) {
      return;
    }

    try {
      final symbolLookup = _symbolLookup;
      if (symbolLookup == null) {
        _library = DynamicLibrary.open(
          'intergalactic_windows_share_plugin.dll',
        );
      }
      _loadSymbols(
        symbolLookup ?? _DynamicLibraryWindowsShareSymbolLookup(_library!),
      );
      _loaded = true;
    } catch (error) {
      _library = null;
      _loaded = false;
      _loadError = error;
    }
  }

  void _loadSymbols(WindowsShareNativeSymbolLookup symbolLookup) {
    // Core session/capture exports are intentionally all-or-nothing. Missing
    // one means the DLL is ABI-mismatched and the plugin must fail closed.
    _getCapabilitiesJson = symbolLookup.lookupGetJson(
      'intergalactic_windows_share_get_capabilities_json',
    );
    _listTargetsJson = symbolLookup.lookupGetJson(
      'intergalactic_windows_share_list_targets_json',
    );
    _listAudioEndpointsJson = _lookupOptionalGetJson(
      symbolLookup,
      'intergalactic_windows_share_list_audio_endpoints_json',
    );
    _createSession = symbolLookup.lookupCreateSession(
      'intergalactic_windows_share_create_session',
    );
    _startSharedAudio = symbolLookup.lookupSessionCommand(
      'intergalactic_windows_share_start_shared_audio',
    );
    _stopSharedAudio = symbolLookup.lookupSessionCommand(
      'intergalactic_windows_share_stop_shared_audio',
    );
    _createSharedAudioStreamJson = symbolLookup.lookupGetSessionJson(
      'intergalactic_windows_share_create_shared_audio_stream_json',
    );
    _disposeSharedAudioStream = symbolLookup.lookupSessionCommand(
      'intergalactic_windows_share_dispose_shared_audio_stream',
    );
    _getSessionStatusJson = symbolLookup.lookupGetSessionJson(
      'intergalactic_windows_share_get_session_status_json',
    );
    _disposeSession = symbolLookup.lookupSessionCommand(
      'intergalactic_windows_share_dispose_session',
    );
  }

  WindowsShareGetJsonFunction? _lookupOptionalGetJson(
    WindowsShareNativeSymbolLookup symbolLookup,
    String symbol,
  ) {
    try {
      return symbolLookup.lookupGetJson(symbol);
    } catch (_) {
      return null;
    }
  }

  String get _loadFailureReason => _loadError == null
      ? 'native_library_unavailable'
      : 'native_library_load_failed';

  Map<String, dynamic>? _decodeObject(Pointer<Utf8> pointer) {
    if (pointer.address == 0) {
      return null;
    }

    final raw = pointer.toDartString();
    if (raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return null;
  }

  List<dynamic>? _decodeList(Pointer<Utf8> pointer) {
    if (pointer.address == 0) {
      return null;
    }

    final raw = pointer.toDartString();
    if (raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is List<dynamic>) {
      return decoded;
    }

    return null;
  }

  @override
  Future<int> createSession({
    required WindowsShareTargetType targetType,
    required WindowsSharedAudioMode audioMode,
    int? processId,
    required bool requestSharedAudio,
    String deviceId = '',
  }) async {
    if (!isSupported) {
      return 0;
    }

    _ensureLoaded();
    if (!_isLoaded) {
      return 0;
    }

    final nativeDeviceId = deviceId.toNativeUtf8();
    try {
      return _createSession(
        targetType.index,
        audioMode.index,
        processId ?? 0,
        requestSharedAudio ? 1 : 0,
        nativeDeviceId,
      );
    } finally {
      // `toNativeUtf8()` allocates with `malloc`, so it must be released with
      // `malloc.free`. The two allocators happen to share libc's `free` today,
      // which is why the mismatched pair never crashed - but that is an
      // implementation detail of package:ffi, not a guarantee.
      malloc.free(nativeDeviceId);
    }
  }

  @override
  Future<List<WindowsAudioEndpointInfo>> listAudioEndpoints() async {
    if (!isSupported) {
      return const [];
    }

    _ensureLoaded();
    if (!_isLoaded) {
      return const [];
    }

    final listAudioEndpointsJson = _listAudioEndpointsJson;
    if (listAudioEndpointsJson == null) {
      return const [];
    }

    try {
      return parseAudioEndpointList(_decodeList(listAudioEndpointsJson()));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(
    int sessionId,
  ) async {
    if (!isSupported) {
      return WindowsSharedAudioStreamInfo.unavailable(sessionId: sessionId);
    }

    _ensureLoaded();
    if (!_isLoaded) {
      return WindowsSharedAudioStreamInfo.unavailable(
        sessionId: sessionId,
        reason: _loadFailureReason,
      );
    }

    try {
      final decoded = _decodeObject(_createSharedAudioStreamJson(sessionId));
      if (decoded == null) {
        return WindowsSharedAudioStreamInfo.unavailable(
          sessionId: sessionId,
          reason: 'stream_info_empty',
        );
      }

      return WindowsSharedAudioStreamInfo.fromJson(decoded);
    } catch (_) {
      return WindowsSharedAudioStreamInfo.unavailable(
        sessionId: sessionId,
        reason: 'stream_info_parse_failed',
      );
    }
  }

  @override
  Future<void> disposeSharedAudioStream(int sessionId) async {
    if (!isSupported) {
      return;
    }

    _ensureLoaded();
    if (!_isLoaded || sessionId <= 0) {
      return;
    }

    _disposeSharedAudioStream(sessionId);
  }

  @override
  Future<void> disposeSession(int sessionId) async {
    if (!isSupported) {
      return;
    }

    _ensureLoaded();
    if (!_isLoaded || sessionId <= 0) {
      return;
    }

    _disposeSession(sessionId);
  }

  @override
  Future<WindowsShareCapabilities> getCapabilities() async {
    if (!isSupported) {
      return WindowsShareCapabilities.unavailable();
    }

    _ensureLoaded();
    if (!_isLoaded) {
      return WindowsShareCapabilities.unavailable(reason: _loadFailureReason);
    }

    try {
      final decoded = _decodeObject(_getCapabilitiesJson());
      if (decoded == null) {
        return WindowsShareCapabilities.unavailable(reason: 'status_empty');
      }

      return WindowsShareCapabilities.fromJson(decoded);
    } catch (_) {
      return WindowsShareCapabilities.unavailable(
        reason: 'status_parse_failed',
      );
    }
  }

  @override
  Future<WindowsShareSessionStatus> getSessionStatus(int sessionId) async {
    if (!isSupported) {
      return WindowsShareSessionStatus.unavailable(sessionId: sessionId);
    }

    _ensureLoaded();
    if (!_isLoaded) {
      return WindowsShareSessionStatus.unavailable(
        sessionId: sessionId,
        reason: _loadFailureReason,
      );
    }

    return _readSessionStatus(sessionId);
  }

  @override
  Future<List<WindowsShareTargetInfo>> listTargets() async {
    if (!isSupported) {
      return const [];
    }

    _ensureLoaded();
    if (!_isLoaded) {
      return const [];
    }

    try {
      final decoded = _decodeList(_listTargetsJson()) ?? const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(WindowsShareTargetInfo.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<WindowsShareSessionStatus> startSharedAudio(int sessionId) async {
    if (!isSupported) {
      return WindowsShareSessionStatus.unavailable(sessionId: sessionId);
    }

    _ensureLoaded();
    if (!_isLoaded) {
      return WindowsShareSessionStatus.unavailable(
        sessionId: sessionId,
        reason: _loadFailureReason,
      );
    }

    _startSharedAudio(sessionId);
    return _readSessionStatus(sessionId);
  }

  @override
  Future<WindowsShareSessionStatus> stopSharedAudio(int sessionId) async {
    if (!isSupported) {
      return WindowsShareSessionStatus.unavailable(sessionId: sessionId);
    }

    _ensureLoaded();
    if (!_isLoaded) {
      return WindowsShareSessionStatus.unavailable(
        sessionId: sessionId,
        reason: _loadFailureReason,
      );
    }

    _stopSharedAudio(sessionId);
    return _readSessionStatus(sessionId);
  }

  WindowsShareSessionStatus _readSessionStatus(int sessionId) {
    try {
      final decoded = _decodeObject(_getSessionStatusJson(sessionId));
      if (decoded == null) {
        return WindowsShareSessionStatus.unavailable(
          sessionId: sessionId,
          reason: 'status_empty',
        );
      }

      return WindowsShareSessionStatus.fromJson(decoded);
    } catch (_) {
      return WindowsShareSessionStatus.unavailable(
        sessionId: sessionId,
        reason: 'status_parse_failed',
      );
    }
  }
}

class _DynamicLibraryWindowsShareSymbolLookup
    implements WindowsShareNativeSymbolLookup {
  const _DynamicLibraryWindowsShareSymbolLookup(this.library);

  final DynamicLibrary library;

  @override
  WindowsShareGetJsonFunction lookupGetJson(String symbol) {
    return library.lookupFunction<_GetJsonNative, WindowsShareGetJsonFunction>(
      symbol,
    );
  }

  @override
  WindowsShareGetSessionJsonFunction lookupGetSessionJson(String symbol) {
    return library.lookupFunction<_GetSessionJsonNative,
        WindowsShareGetSessionJsonFunction>(symbol);
  }

  @override
  WindowsShareCreateSessionFunction lookupCreateSession(String symbol) {
    return library.lookupFunction<_CreateSessionNative,
        WindowsShareCreateSessionFunction>(symbol);
  }

  @override
  WindowsShareSessionCommandFunction lookupSessionCommand(String symbol) {
    return library.lookupFunction<_SessionCommandNative,
        WindowsShareSessionCommandFunction>(symbol);
  }
}
