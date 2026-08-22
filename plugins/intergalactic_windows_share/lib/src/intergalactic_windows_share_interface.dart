enum WindowsShareTargetType {
  display,
  window,
}

/// Declaration order is the FFI wire format: each value's `index` is passed to
/// `intergalactic_windows_share_create_session`. Append only.
enum WindowsSharedAudioMode {
  none,
  processTreeLoopback,
  systemLoopback,
  unavailable,
  endpointLoopback,
  deviceCapture,
}

/// Where a shared-audio attempt stopped. Mirrors `SharedAudioFailureStage` in
/// the native layer.
enum WindowsSharedAudioFailureStage {
  none,
  comInitialization,
  activation,
  clientInitialize,
  serviceAcquire,
  eventHandle,
  start,
  capture,
  deviceEnumeration,
  deviceNotFound,
  activationTimeout,
}

/// A render or capture endpoint reported by the native device enumerator.
class WindowsAudioEndpointInfo {
  const WindowsAudioEndpointInfo({
    required this.id,
    required this.name,
    required this.isCapture,
    required this.isDefault,
    required this.isLikelyVirtual,
    required this.virtualFamily,
  });

  final String id;
  final String name;
  final bool isCapture;
  final bool isDefault;

  /// True when the endpoint name matches a known virtual audio cable.
  final bool isLikelyVirtual;

  /// `vb-cable`, `voicemeeter`, `vac`, or empty when not virtual.
  final String virtualFamily;

  factory WindowsAudioEndpointInfo.fromJson(Map<String, dynamic> json) {
    return WindowsAudioEndpointInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isCapture: _parseBool(json['isCapture']),
      isDefault: _parseBool(json['isDefault']),
      isLikelyVirtual: _parseBool(json['isLikelyVirtual']),
      virtualFamily: json['virtualFamily'] as String? ?? '',
    );
  }
}

enum WindowsSharedAudioState {
  inactive,
  starting,
  active,
  unavailable,
  failed,
  stopped,
}

class WindowsShareCapabilities {
  const WindowsShareCapabilities({
    required this.supported,
    required this.applicationLoopbackSupported,
    required this.processTreeLoopbackSupported,
    required this.wgcSupported,
    required this.pcmBridgeSupported,
    required this.endpointLoopbackSupported,
    required this.deviceCaptureSupported,
    required this.hasVirtualAudioDevice,
    required this.osBuild,
    required this.documentedProcessLoopbackBuild,
    required this.processLoopbackHresult,
    required this.processLoopbackStage,
    required this.reason,
  });

  final bool supported;

  /// Result of an *actual* process-loopback activation attempt in the native
  /// layer. It is never inferred from [osBuild]: the API activates on Windows
  /// 10 builds below Microsoft's documented 20348 minimum, and can fail on
  /// builds above it.
  final bool applicationLoopbackSupported;
  final bool processTreeLoopbackSupported;
  final bool wgcSupported;
  final bool pcmBridgeSupported;

  /// Classic WASAPI render-endpoint loopback. Captures the whole endpoint mix,
  /// so it cannot exclude other applications or our own call audio.
  final bool endpointLoopbackSupported;

  /// Capture from a chosen capture endpoint, used for virtual audio cables.
  final bool deviceCaptureSupported;

  /// At least one endpoint looks like a virtual audio cable.
  final bool hasVirtualAudioDevice;

  final int osBuild;

  /// Microsoft's documented minimum build for process loopback. Diagnostics
  /// only - it must not be used to decide whether to attempt capture.
  final int documentedProcessLoopbackBuild;

  /// HRESULT from the process-loopback probe, as `0x...`, for logs and reports.
  final String processLoopbackHresult;

  /// Stage the process-loopback probe failed at.
  final WindowsSharedAudioFailureStage processLoopbackStage;

  final String reason;

  factory WindowsShareCapabilities.unavailable({
    String reason = 'unsupported_platform',
  }) {
    return WindowsShareCapabilities(
      supported: false,
      applicationLoopbackSupported: false,
      processTreeLoopbackSupported: false,
      wgcSupported: false,
      pcmBridgeSupported: false,
      endpointLoopbackSupported: false,
      deviceCaptureSupported: false,
      hasVirtualAudioDevice: false,
      osBuild: 0,
      documentedProcessLoopbackBuild: 0,
      processLoopbackHresult: '',
      processLoopbackStage: WindowsSharedAudioFailureStage.none,
      reason: reason,
    );
  }

  factory WindowsShareCapabilities.fromJson(Map<String, dynamic> json) {
    return WindowsShareCapabilities(
      supported: _parseBool(json['supported']),
      applicationLoopbackSupported:
          _parseBool(json['applicationLoopbackSupported']),
      processTreeLoopbackSupported:
          _parseBool(json['processTreeLoopbackSupported']),
      wgcSupported: _parseBool(json['wgcSupported']),
      pcmBridgeSupported: _parseBool(json['pcmBridgeSupported']),
      endpointLoopbackSupported: _parseBool(json['endpointLoopbackSupported']),
      deviceCaptureSupported: _parseBool(json['deviceCaptureSupported']),
      hasVirtualAudioDevice: _parseBool(json['hasVirtualAudioDevice']),
      osBuild: _parseInt(json['osBuild']),
      documentedProcessLoopbackBuild:
          _parseInt(json['documentedProcessLoopbackBuild']),
      processLoopbackHresult: json['processLoopbackHresult'] as String? ?? '',
      processLoopbackStage: _parseFailureStage(json['processLoopbackStage']),
      reason: json['reason'] as String? ?? 'unknown',
    );
  }
}

class WindowsShareTargetInfo {
  const WindowsShareTargetInfo({
    required this.windowHandle,
    required this.processId,
    required this.title,
  });

  final int windowHandle;
  final int processId;
  final String title;

  factory WindowsShareTargetInfo.fromJson(Map<String, dynamic> json) {
    return WindowsShareTargetInfo(
      windowHandle: _parseInt(json['windowHandle']),
      processId: _parseInt(json['processId']),
      title: json['title'] as String? ?? '',
    );
  }
}

class WindowsShareSessionStatus {
  const WindowsShareSessionStatus({
    required this.sessionId,
    required this.supported,
    required this.requestedAudio,
    required this.targetType,
    required this.audioMode,
    required this.audioState,
    required this.active,
    required this.sampleRateHz,
    required this.numChannels,
    required this.bitsPerSample,
    required this.packetsCaptured,
    required this.framesCaptured,
    required this.bytesCaptured,
    required this.nonsilentBytesCaptured,
    required this.targetElevated,
    required this.targetElevationKnown,
    required this.pcmBridgeSupported,
    required this.wgcReady,
    required this.lastHresult,
    required this.failureStage,
    required this.selectedDeviceId,
    required this.reason,
  });

  final int sessionId;
  final bool supported;
  final bool requestedAudio;
  final WindowsShareTargetType targetType;
  final WindowsSharedAudioMode audioMode;
  final WindowsSharedAudioState audioState;
  final bool active;
  final int sampleRateHz;
  final int numChannels;
  final int bitsPerSample;
  final int packetsCaptured;
  final int framesCaptured;
  final int bytesCaptured;

  /// Bytes captured that were NOT flagged silent by the loopback graph. When a
  /// session is [active] with [packetsCaptured] climbing but this stays 0, the
  /// capture is hearing only silence — the hallmark of an elevated target.
  final int nonsilentBytesCaptured;

  /// True when the process-tree loopback target runs at a higher integrity
  /// level than this app (elevated / anti-cheat-protected), which Windows
  /// process-loopback cannot capture audio from.
  final bool targetElevated;

  /// True when the native layer could positively determine the target's
  /// elevation relative to this process; false means [targetElevated] is a
  /// best-effort default and callers should rely on the silence heuristic.
  final bool targetElevationKnown;

  final bool pcmBridgeSupported;
  final bool wgcReady;

  /// Native HRESULT of the last state transition, as `0x...`. Empty when the
  /// native layer reported none.
  final String lastHresult;

  /// Stage the capture stopped at, so a failure can be attributed without
  /// reading native logs.
  final WindowsSharedAudioFailureStage failureStage;

  /// Endpoint the capture is bound to for the endpointLoopback and
  /// deviceCapture modes. Empty means the default endpoint.
  final String selectedDeviceId;

  final String reason;

  factory WindowsShareSessionStatus.unavailable({
    int sessionId = 0,
    bool requestedAudio = false,
    WindowsShareTargetType targetType = WindowsShareTargetType.display,
    WindowsSharedAudioMode audioMode = WindowsSharedAudioMode.unavailable,
    String reason = 'unsupported_platform',
  }) {
    return WindowsShareSessionStatus(
      sessionId: sessionId,
      supported: false,
      requestedAudio: requestedAudio,
      targetType: targetType,
      audioMode: audioMode,
      audioState: WindowsSharedAudioState.unavailable,
      active: false,
      sampleRateHz: 0,
      numChannels: 0,
      bitsPerSample: 0,
      packetsCaptured: 0,
      framesCaptured: 0,
      bytesCaptured: 0,
      nonsilentBytesCaptured: 0,
      targetElevated: false,
      targetElevationKnown: false,
      pcmBridgeSupported: false,
      wgcReady: false,
      lastHresult: '',
      failureStage: WindowsSharedAudioFailureStage.none,
      selectedDeviceId: '',
      reason: reason,
    );
  }

  factory WindowsShareSessionStatus.fromJson(Map<String, dynamic> json) {
    return WindowsShareSessionStatus(
      sessionId: _parseInt(json['sessionId']),
      supported: _parseBool(json['supported']),
      requestedAudio: _parseBool(json['requestedAudio']),
      targetType: _parseTargetType(json['targetType']),
      audioMode: _parseAudioMode(json['audioMode']),
      audioState: _parseAudioState(json['audioState']),
      active: _parseBool(json['active']),
      sampleRateHz: _parseInt(json['sampleRateHz']),
      numChannels: _parseInt(json['numChannels']),
      bitsPerSample: _parseInt(json['bitsPerSample']),
      packetsCaptured: _parseInt(json['packetsCaptured']),
      framesCaptured: _parseInt(json['framesCaptured']),
      bytesCaptured: _parseInt(json['bytesCaptured']),
      nonsilentBytesCaptured: _parseInt(json['nonsilentBytesCaptured']),
      targetElevated: _parseBool(json['targetElevated']),
      targetElevationKnown: _parseBool(json['targetElevationKnown']),
      pcmBridgeSupported: _parseBool(json['pcmBridgeSupported']),
      wgcReady: _parseBool(json['wgcReady']),
      lastHresult: json['lastHresult'] as String? ?? '',
      failureStage: _parseFailureStage(json['failureStage']),
      selectedDeviceId: json['selectedDeviceId'] as String? ?? '',
      reason: json['reason'] as String? ?? 'unknown',
    );
  }
}

class WindowsSharedAudioTrackInfo {
  const WindowsSharedAudioTrackInfo({
    required this.id,
    required this.label,
    required this.kind,
    required this.enabled,
    required this.settings,
  });

  final String id;
  final String label;
  final String kind;
  final bool enabled;
  final Map<String, dynamic> settings;

  factory WindowsSharedAudioTrackInfo.fromJson(Map<String, dynamic> json) {
    final settings = json['settings'];
    return WindowsSharedAudioTrackInfo(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      kind: json['kind'] as String? ?? 'audio',
      enabled: _parseBool(json['enabled']),
      settings: settings is Map<String, dynamic>
          ? settings
          : settings is Map
              ? Map<String, dynamic>.from(settings)
              : const {},
    );
  }

  Map<String, dynamic> toMediaTrackMap() {
    return {
      'id': id,
      'label': label,
      'kind': kind,
      'enabled': enabled,
      'settings': settings,
    };
  }
}

class WindowsSharedAudioStreamInfo {
  const WindowsSharedAudioStreamInfo({
    required this.sessionId,
    required this.supported,
    required this.streamId,
    required this.trackId,
    required this.ownerTag,
    required this.sampleRateHz,
    required this.numChannels,
    required this.bitsPerSample,
    required this.audioTracks,
    required this.videoTracks,
    required this.reason,
  });

  final int sessionId;
  final bool supported;
  final String streamId;
  final String trackId;
  final String ownerTag;
  final int sampleRateHz;
  final int numChannels;
  final int bitsPerSample;
  final List<WindowsSharedAudioTrackInfo> audioTracks;
  final List<WindowsSharedAudioTrackInfo> videoTracks;
  final String reason;

  factory WindowsSharedAudioStreamInfo.unavailable({
    int sessionId = 0,
    String reason = 'unsupported_platform',
  }) {
    return WindowsSharedAudioStreamInfo(
      sessionId: sessionId,
      supported: false,
      streamId: '',
      trackId: '',
      ownerTag: 'local',
      sampleRateHz: 0,
      numChannels: 0,
      bitsPerSample: 0,
      audioTracks: const [],
      videoTracks: const [],
      reason: reason,
    );
  }

  factory WindowsSharedAudioStreamInfo.fromJson(Map<String, dynamic> json) {
    return WindowsSharedAudioStreamInfo(
      sessionId: _parseInt(json['sessionId']),
      supported: _parseBool(json['supported']),
      streamId: json['streamId'] as String? ?? '',
      trackId: json['trackId'] as String? ?? '',
      ownerTag: json['ownerTag'] as String? ?? 'local',
      sampleRateHz: _parseInt(json['sampleRateHz']),
      numChannels: _parseInt(json['numChannels']),
      bitsPerSample: _parseInt(json['bitsPerSample']),
      audioTracks: _parseTrackInfoList(json['audioTracks']),
      videoTracks: _parseTrackInfoList(json['videoTracks']),
      reason: json['reason'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toMediaStreamMap() {
    return {
      'streamId': streamId,
      'ownerTag': ownerTag,
      'audioTracks':
          audioTracks.map((track) => track.toMediaTrackMap()).toList(),
      'videoTracks':
          videoTracks.map((track) => track.toMediaTrackMap()).toList(),
    };
  }
}

abstract class WindowsShareNativeBinding {
  bool get isSupported;

  Future<WindowsShareCapabilities> getCapabilities();

  Future<List<WindowsShareTargetInfo>> listTargets();

  /// Render and capture endpoints, annotated with virtual-device detection.
  Future<List<WindowsAudioEndpointInfo>> listAudioEndpoints();

  Future<int> createSession({
    required WindowsShareTargetType targetType,
    required WindowsSharedAudioMode audioMode,
    int? processId,
    required bool requestSharedAudio,
    String deviceId = '',
  });

  Future<WindowsShareSessionStatus> startSharedAudio(int sessionId);

  Future<WindowsShareSessionStatus> stopSharedAudio(int sessionId);

  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(int sessionId);

  Future<void> disposeSharedAudioStream(int sessionId);

  Future<WindowsShareSessionStatus> getSessionStatus(int sessionId);

  Future<void> disposeSession(int sessionId);
}

bool _parseBool(Object? value) => value == true || value == 1;

int _parseInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value) ?? 0;
  }

  return 0;
}

WindowsShareTargetType _parseTargetType(Object? value) {
  return switch (value) {
    'window' || 1 => WindowsShareTargetType.window,
    _ => WindowsShareTargetType.display,
  };
}

WindowsSharedAudioMode _parseAudioMode(Object? value) {
  return switch (value) {
    'none' || 0 => WindowsSharedAudioMode.none,
    'processTreeLoopback' || 1 => WindowsSharedAudioMode.processTreeLoopback,
    'systemLoopback' || 2 => WindowsSharedAudioMode.systemLoopback,
    'endpointLoopback' || 4 => WindowsSharedAudioMode.endpointLoopback,
    'deviceCapture' || 5 => WindowsSharedAudioMode.deviceCapture,
    _ => WindowsSharedAudioMode.unavailable,
  };
}

WindowsSharedAudioFailureStage _parseFailureStage(Object? value) {
  return switch (value) {
    'comInitialization' => WindowsSharedAudioFailureStage.comInitialization,
    'activation' => WindowsSharedAudioFailureStage.activation,
    'clientInitialize' => WindowsSharedAudioFailureStage.clientInitialize,
    'serviceAcquire' => WindowsSharedAudioFailureStage.serviceAcquire,
    'eventHandle' => WindowsSharedAudioFailureStage.eventHandle,
    'start' => WindowsSharedAudioFailureStage.start,
    'capture' => WindowsSharedAudioFailureStage.capture,
    'deviceEnumeration' => WindowsSharedAudioFailureStage.deviceEnumeration,
    'deviceNotFound' => WindowsSharedAudioFailureStage.deviceNotFound,
    'activationTimeout' => WindowsSharedAudioFailureStage.activationTimeout,
    _ => WindowsSharedAudioFailureStage.none,
  };
}

List<WindowsAudioEndpointInfo> parseAudioEndpointList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map<String, dynamic>>()
      .map(WindowsAudioEndpointInfo.fromJson)
      .toList(growable: false);
}

WindowsSharedAudioState _parseAudioState(Object? value) {
  return switch (value) {
    'inactive' || 0 => WindowsSharedAudioState.inactive,
    'starting' || 1 => WindowsSharedAudioState.starting,
    'active' || 2 => WindowsSharedAudioState.active,
    'failed' || 4 => WindowsSharedAudioState.failed,
    'stopped' || 5 => WindowsSharedAudioState.stopped,
    _ => WindowsSharedAudioState.unavailable,
  };
}

List<WindowsSharedAudioTrackInfo> _parseTrackInfoList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map<String, dynamic>>()
      .map(WindowsSharedAudioTrackInfo.fromJson)
      .toList(growable: false);
}
