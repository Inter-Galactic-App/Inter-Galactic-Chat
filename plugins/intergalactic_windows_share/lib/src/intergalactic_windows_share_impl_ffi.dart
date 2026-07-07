import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'intergalactic_windows_share_interface.dart';

typedef _GetJsonNative = Pointer<Utf8> Function();
typedef _GetJsonDart = Pointer<Utf8> Function();

typedef _GetSessionJsonNative = Pointer<Utf8> Function(Int32 sessionId);
typedef _GetSessionJsonDart = Pointer<Utf8> Function(int sessionId);

typedef _CreateSessionNative = Int32 Function(
  Int32 targetType,
  Int32 audioMode,
  Uint32 processId,
  Int32 requestSharedAudio,
);
typedef _CreateSessionDart = int Function(
  int targetType,
  int audioMode,
  int processId,
  int requestSharedAudio,
);

typedef _SessionCommandNative = Int32 Function(Int32 sessionId);
typedef _SessionCommandDart = int Function(int sessionId);

WindowsShareNativeBinding createWindowsShareNativeBinding() {
  return _FfiWindowsShareNativeBinding();
}

class _FfiWindowsShareNativeBinding implements WindowsShareNativeBinding {
  DynamicLibrary? _library;
  Object? _loadError;

  late final _GetJsonDart _getCapabilitiesJson;
  late final _GetJsonDart _listTargetsJson;
  late final _CreateSessionDart _createSession;
  late final _SessionCommandDart _startSharedAudio;
  late final _SessionCommandDart _stopSharedAudio;
  late final _GetSessionJsonDart _createSharedAudioStreamJson;
  late final _SessionCommandDart _disposeSharedAudioStream;
  late final _GetSessionJsonDart _getSessionStatusJson;
  late final _SessionCommandDart _disposeSession;

  @override
  bool get isSupported => Platform.isWindows;

  void _ensureLoaded() {
    if (_library != null || _loadError != null || !isSupported) {
      return;
    }

    try {
      _library = DynamicLibrary.open('intergalactic_windows_share_plugin.dll');
      _getCapabilitiesJson =
          _library!.lookupFunction<_GetJsonNative, _GetJsonDart>(
        'intergalactic_windows_share_get_capabilities_json',
      );
      _listTargetsJson = _library!.lookupFunction<_GetJsonNative, _GetJsonDart>(
        'intergalactic_windows_share_list_targets_json',
      );
      _createSession =
          _library!.lookupFunction<_CreateSessionNative, _CreateSessionDart>(
        'intergalactic_windows_share_create_session',
      );
      _startSharedAudio =
          _library!.lookupFunction<_SessionCommandNative, _SessionCommandDart>(
        'intergalactic_windows_share_start_shared_audio',
      );
      _stopSharedAudio =
          _library!.lookupFunction<_SessionCommandNative, _SessionCommandDart>(
        'intergalactic_windows_share_stop_shared_audio',
      );
      _createSharedAudioStreamJson =
          _library!.lookupFunction<_GetSessionJsonNative, _GetSessionJsonDart>(
        'intergalactic_windows_share_create_shared_audio_stream_json',
      );
      _disposeSharedAudioStream =
          _library!.lookupFunction<_SessionCommandNative, _SessionCommandDart>(
        'intergalactic_windows_share_dispose_shared_audio_stream',
      );
      _getSessionStatusJson =
          _library!.lookupFunction<_GetSessionJsonNative, _GetSessionJsonDart>(
        'intergalactic_windows_share_get_session_status_json',
      );
      _disposeSession =
          _library!.lookupFunction<_SessionCommandNative, _SessionCommandDart>(
        'intergalactic_windows_share_dispose_session',
      );
    } catch (error) {
      _library = null;
      _loadError = error;
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
  }) async {
    if (!isSupported) {
      return 0;
    }

    _ensureLoaded();
    if (_library == null) {
      return 0;
    }

    return _createSession(
      targetType.index,
      audioMode.index,
      processId ?? 0,
      requestSharedAudio ? 1 : 0,
    );
  }

  @override
  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(
      int sessionId) async {
    if (!isSupported) {
      return WindowsSharedAudioStreamInfo.unavailable(sessionId: sessionId);
    }

    _ensureLoaded();
    if (_library == null) {
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
    if (_library == null || sessionId <= 0) {
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
    if (_library == null || sessionId <= 0) {
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
    if (_library == null) {
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
          reason: 'status_parse_failed');
    }
  }

  @override
  Future<WindowsShareSessionStatus> getSessionStatus(int sessionId) async {
    if (!isSupported) {
      return WindowsShareSessionStatus.unavailable(sessionId: sessionId);
    }

    _ensureLoaded();
    if (_library == null) {
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
    if (_library == null) {
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
    if (_library == null) {
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
    if (_library == null) {
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
