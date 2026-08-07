enum WindowsShareTargetType {
  display,
  window,
}

enum WindowsSharedAudioMode {
  none,
  processTreeLoopback,
  systemLoopback,
  unavailable,
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
    required this.osBuild,
    required this.reason,
  });

  final bool supported;
  final bool applicationLoopbackSupported;
  final bool processTreeLoopbackSupported;
  final bool wgcSupported;
  final bool pcmBridgeSupported;
  final int osBuild;
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
      osBuild: 0,
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
      osBuild: _parseInt(json['osBuild']),
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
    required this.pcmBridgeSupported,
    required this.wgcReady,
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
  final bool pcmBridgeSupported;
  final bool wgcReady;
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
      pcmBridgeSupported: false,
      wgcReady: false,
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
      pcmBridgeSupported: _parseBool(json['pcmBridgeSupported']),
      wgcReady: _parseBool(json['wgcReady']),
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

  Future<int> createSession({
    required WindowsShareTargetType targetType,
    required WindowsSharedAudioMode audioMode,
    int? processId,
    required bool requestSharedAudio,
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
    _ => WindowsSharedAudioMode.unavailable,
  };
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
