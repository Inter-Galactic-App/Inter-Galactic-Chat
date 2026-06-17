import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/components/voip/share_session/shared_audio_media_stream.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

enum ShareTargetType {
  display,
  window,
}

enum SharedAudioMode {
  none,
  processTreeLoopback,
  systemLoopback,
  unavailable,
}

enum SharedAudioState {
  disabled,
  starting,
  active,
  unavailable,
  failed,
  stopped,
}

enum ShareSessionLifecycle {
  idle,
  starting,
  sharing,
  videoOnly,
  stopping,
  stopped,
  failed,
}

const _sharedAudioStartPollInterval = Duration(milliseconds: 75);
const _sharedAudioStartTimeout = Duration(seconds: 3);

class ShareTarget {
  const ShareTarget({
    required this.type,
    required this.sourceId,
    required this.title,
    this.processId,
  });

  final ShareTargetType type;
  final String sourceId;
  final String title;
  final int? processId;
}

class ShareSessionDiagnosticSummary {
  const ShareSessionDiagnosticSummary({
    required this.sourceType,
    required this.sourceIdHash,
    required this.processId,
    required this.audioRequested,
    required this.audioMode,
    required this.audioState,
    required this.audioReason,
    this.lifecycle,
    this.sourceTitle,
  });

  factory ShareSessionDiagnosticSummary.fromSession(
    ShareSession session, {
    bool includeTitle = false,
  }) {
    final status = session.sharedAudioStatus;
    return ShareSessionDiagnosticSummary(
      sourceType: session.target.type,
      sourceIdHash: shortShareSourceIdHash(session.target.sourceId),
      processId: session.target.processId,
      audioRequested: session.sharedAudioRequested,
      audioMode: status.mode,
      audioState: status.state,
      audioReason: status.reason,
      lifecycle: session.lifecycle,
      sourceTitle:
          includeTitle ? truncateShareSourceTitle(session.target.title) : null,
    );
  }

  final ShareTargetType sourceType;
  final String sourceIdHash;
  final int? processId;
  final bool audioRequested;
  final SharedAudioMode audioMode;
  final SharedAudioState audioState;
  final String audioReason;
  final ShareSessionLifecycle? lifecycle;
  final String? sourceTitle;

  String get sourceLine {
    final title = sourceTitle == null ? '' : ' title="$sourceTitle"';
    return 'sourceType=${sourceType.name} sourceIdHash=$sourceIdHash '
        'pid=${processId ?? '?'}$title';
  }

  String get audioLine {
    return 'audioRequested=$audioRequested mode=${audioMode.name} '
        'state=${audioState.name} reason=$audioReason';
  }

  List<String> lines() {
    return <String>[
      'Share source: $sourceLine',
      if (lifecycle != null) 'Share lifecycle: ${lifecycle!.name}',
      'Share audio: $audioLine',
    ];
  }

  String toLogLine() {
    final lifecycleLabel =
        lifecycle == null ? '' : ' lifecycle=${lifecycle!.name}';
    return '$sourceLine$lifecycleLabel $audioLine';
  }
}

String shortShareSourceIdHash(String sourceId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in sourceId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String truncateShareSourceTitle(String title, {int maxLength = 80}) {
  final normalized = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= maxLength) {
    return normalized;
  }

  return '${normalized.substring(0, maxLength - 3)}...';
}

abstract class ScreenVideoSource {
  ShareTarget get target;
}

class WebrtcScreenVideoSource implements ScreenVideoSource {
  const WebrtcScreenVideoSource({
    required this.target,
    required this.source,
  });

  @override
  final ShareTarget target;

  final DesktopCapturerSource source;
}

class MicSource {
  const MicSource({
    this.enabled = true,
    this.rnnoiseApplies = true,
  });

  final bool enabled;
  final bool rnnoiseApplies;
}

class SharedAudioStatus {
  const SharedAudioStatus({
    required this.state,
    required this.mode,
    required this.reason,
    this.sampleRateHz = 0,
    this.numChannels = 0,
    this.bitsPerSample = 0,
    this.packetsCaptured = 0,
    this.framesCaptured = 0,
    this.bytesCaptured = 0,
    this.pcmBridgeSupported = false,
  });

  final SharedAudioState state;
  final SharedAudioMode mode;
  final String reason;
  final int sampleRateHz;
  final int numChannels;
  final int bitsPerSample;
  final int packetsCaptured;
  final int framesCaptured;
  final int bytesCaptured;
  final bool pcmBridgeSupported;
}

abstract class SharedAudioSource {
  bool get requested;
  SharedAudioMode get mode;
  SharedAudioState get state;
  SharedAudioStatus get status;

  Future<SharedAudioStatus> start();
  Future<SharedAudioStatus> stop();
  Future<void> dispose();
}

abstract class SharedAudioPublicationSource {
  Future<MediaStream?> createPublicationStream();

  Future<void> disposePublicationStream();
}

class DisabledSharedAudioSource implements SharedAudioSource {
  const DisabledSharedAudioSource({
    this.reason = 'shared_audio_not_requested',
  });

  final String reason;

  @override
  bool get requested => false;

  @override
  SharedAudioMode get mode => SharedAudioMode.none;

  @override
  SharedAudioState get state => SharedAudioState.disabled;

  @override
  SharedAudioStatus get status => SharedAudioStatus(
        state: state,
        mode: mode,
        reason: reason,
      );

  @override
  Future<void> dispose() async {}

  @override
  Future<SharedAudioStatus> start() async => status;

  @override
  Future<SharedAudioStatus> stop() async => status;
}

class WindowsSharedAudioSource
    implements SharedAudioSource, SharedAudioPublicationSource {
  WindowsSharedAudioSource({
    required WindowsShareNativeBinding nativeBinding,
    required this.target,
    required this.requested,
    required this.mode,
  }) : _nativeBinding = nativeBinding;

  final WindowsShareNativeBinding _nativeBinding;
  final ShareTarget target;
  int? _nativeSessionId;
  MediaStream? _publicationStream;
  SharedAudioStatus _status = const SharedAudioStatus(
    state: SharedAudioState.stopped,
    mode: SharedAudioMode.none,
    reason: 'not_started',
  );

  @override
  final bool requested;

  @override
  final SharedAudioMode mode;

  @override
  SharedAudioState get state => _status.state;

  @override
  SharedAudioStatus get status => _status;

  @override
  Future<SharedAudioStatus> start() async {
    if (!requested) {
      _status = const SharedAudioStatus(
        state: SharedAudioState.disabled,
        mode: SharedAudioMode.none,
        reason: 'shared_audio_not_requested',
      );
      return _status;
    }

    if (mode == SharedAudioMode.unavailable) {
      _status = SharedAudioStatus(
        state: SharedAudioState.unavailable,
        mode: mode,
        reason:
            target.processId == null && target.type == ShareTargetType.window
                ? 'target_process_unresolved'
                : 'shared_audio_unavailable',
      );
      return _status;
    }

    try {
      _nativeSessionId ??= await _nativeBinding.createSession(
        targetType: _toWindowsTargetType(target.type),
        audioMode: _toWindowsAudioMode(mode),
        processId: target.processId,
        requestSharedAudio: requested,
      );

      if (_nativeSessionId == null || _nativeSessionId! <= 0) {
        _status = SharedAudioStatus(
          state: SharedAudioState.unavailable,
          mode: mode,
          reason: 'native_session_unavailable',
        );
        return _status;
      }

      var nativeStatus =
          await _nativeBinding.startSharedAudio(_nativeSessionId!);
      nativeStatus = await _waitForNativeStartResult(
        _nativeSessionId!,
        nativeStatus,
      );
      _status = _fromNativeStatus(nativeStatus);
      return _status;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to start Windows shared-content audio',
      );
      _status = SharedAudioStatus(
        state: SharedAudioState.failed,
        mode: mode,
        reason: 'native_start_failed',
      );
      return _status;
    }
  }

  Future<WindowsShareSessionStatus> _waitForNativeStartResult(
    int sessionId,
    WindowsShareSessionStatus initialStatus,
  ) async {
    var status = initialStatus;
    if (status.audioState != WindowsSharedAudioState.starting) {
      return status;
    }

    final deadline = DateTime.now().add(_sharedAudioStartTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_sharedAudioStartPollInterval);
      status = await _nativeBinding.getSessionStatus(sessionId);
      if (status.audioState != WindowsSharedAudioState.starting) {
        return status;
      }
    }

    return status;
  }

  @override
  Future<SharedAudioStatus> stop() async {
    final sessionId = _nativeSessionId;
    if (sessionId == null || sessionId <= 0) {
      _status = SharedAudioStatus(
        state: requested ? SharedAudioState.stopped : SharedAudioState.disabled,
        mode: mode,
        reason: requested ? 'stopped' : 'shared_audio_not_requested',
      );
      return _status;
    }

    try {
      await disposePublicationStream();
      final nativeStatus = await _nativeBinding.stopSharedAudio(sessionId);
      _status = _fromNativeStatus(nativeStatus);
      return _status;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop Windows shared-content audio',
      );
      _status = SharedAudioStatus(
        state: SharedAudioState.failed,
        mode: mode,
        reason: 'native_stop_failed',
      );
      return _status;
    }
  }

  @override
  Future<MediaStream?> createPublicationStream() async {
    final existing = _publicationStream;
    if (existing != null) {
      return existing;
    }

    final sessionId = _nativeSessionId;
    if (!requested || sessionId == null || sessionId <= 0) {
      return null;
    }

    if (_status.state != SharedAudioState.active ||
        !_status.pcmBridgeSupported) {
      return null;
    }

    try {
      final streamInfo =
          await _nativeBinding.createSharedAudioStream(sessionId);
      if (!streamInfo.supported) {
        Log.w(
          'Windows shared-content audio publication unavailable for '
          '${target.title}: ${streamInfo.reason}; continuing video-only.',
        );
        return null;
      }

      _publicationStream =
          windowsSharedAudioStreamInfoToMediaStream(streamInfo);
      return _publicationStream;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to create Windows shared-content audio track',
      );
      return null;
    }
  }

  @override
  Future<void> disposePublicationStream() async {
    _publicationStream = null;

    final sessionId = _nativeSessionId;
    if (sessionId == null || sessionId <= 0) {
      return;
    }

    try {
      await _nativeBinding.disposeSharedAudioStream(sessionId);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to dispose Windows shared-content audio track',
      );
    }
  }

  @override
  Future<void> dispose() async {
    final sessionId = _nativeSessionId;
    if (sessionId == null || sessionId <= 0) {
      return;
    }

    await disposePublicationStream();
    _nativeSessionId = null;
    await _nativeBinding.disposeSession(sessionId);
  }
}

class ShareSession {
  ShareSession({
    required this.target,
    required this.videoSource,
    required this.sharedAudioSource,
    this.micSource = const MicSource(),
  });

  final ShareTarget target;
  final ScreenVideoSource videoSource;
  final SharedAudioSource sharedAudioSource;
  final MicSource micSource;

  ShareSessionLifecycle lifecycle = ShareSessionLifecycle.idle;

  bool get sharedAudioRequested => sharedAudioSource.requested;
  SharedAudioState get sharedAudioState => sharedAudioSource.state;
  SharedAudioStatus get sharedAudioStatus => sharedAudioSource.status;

  ShareSessionDiagnosticSummary diagnosticsSummary({
    bool includeTitle = false,
  }) {
    return ShareSessionDiagnosticSummary.fromSession(
      this,
      includeTitle: includeTitle,
    );
  }

  Future<SharedAudioStatus> startSharedAudio() async {
    lifecycle = ShareSessionLifecycle.starting;

    late final SharedAudioStatus status;
    try {
      status = await sharedAudioSource.start();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Shared-content audio start failed',
      );
      lifecycle = ShareSessionLifecycle.videoOnly;
      return SharedAudioStatus(
        state: SharedAudioState.failed,
        mode: sharedAudioSource.mode,
        reason: 'shared_audio_start_failed',
      );
    }

    lifecycle = status.state == SharedAudioState.active
        ? ShareSessionLifecycle.sharing
        : ShareSessionLifecycle.videoOnly;

    if (sharedAudioSource.requested &&
        status.state != SharedAudioState.active) {
      Log.w(
        'Shared-content audio unavailable for ${target.title}: '
        '${status.reason}; continuing with video-only screenshare.',
      );
    }

    return status;
  }

  Future<MediaStream?> createSharedAudioPublicationStream() async {
    final source = sharedAudioSource;
    if (source is! SharedAudioPublicationSource) {
      return null;
    }

    return (source as SharedAudioPublicationSource).createPublicationStream();
  }

  Future<void> disposeSharedAudioPublicationStream() async {
    final source = sharedAudioSource;
    if (source is SharedAudioPublicationSource) {
      await (source as SharedAudioPublicationSource).disposePublicationStream();
    }
  }

  Future<void> stop() async {
    lifecycle = ShareSessionLifecycle.stopping;
    await sharedAudioSource.stop();
    await sharedAudioSource.dispose();
    lifecycle = ShareSessionLifecycle.stopped;
  }

  static Future<ShareSession> forDesktopCapturerSource(
    DesktopCapturerSource source, {
    required bool shareAudio,
    WindowsShareNativeBinding? nativeBinding,
  }) async {
    final binding = nativeBinding ?? IntergalacticWindowsShare.instance.binding;
    final target = await resolveShareTargetForDesktopSource(
      source,
      nativeBinding: binding,
    );
    final sharedAudioSupported = shareAudio && binding.isSupported;
    final mode = sharedAudioSupported
        ? _resolveAudioMode(target, shareAudio)
        : SharedAudioMode.none;

    final videoSource = WebrtcScreenVideoSource(
      target: target,
      source: source,
    );

    final sharedAudioSource = sharedAudioSupported
        ? WindowsSharedAudioSource(
            nativeBinding: binding,
            target: target,
            requested: true,
            mode: mode,
          )
        : DisabledSharedAudioSource(
            reason: shareAudio
                ? 'windows_share_unsupported'
                : 'shared_audio_not_requested',
          );

    return ShareSession(
      target: target,
      videoSource: videoSource,
      sharedAudioSource: sharedAudioSource,
    );
  }
}

Future<ShareTarget> resolveShareTargetForDesktopSource(
  DesktopCapturerSource source, {
  WindowsShareNativeBinding? nativeBinding,
}) async {
  final binding = nativeBinding ?? IntergalacticWindowsShare.instance.binding;
  return binding.isSupported
      ? _ShareTargetResolver(binding).resolve(source)
      : _ShareTargetResolver.resolveVideoTarget(source);
}

class _ShareTargetResolver {
  const _ShareTargetResolver(this.nativeBinding);

  final WindowsShareNativeBinding nativeBinding;

  static ShareTarget resolveVideoTarget(DesktopCapturerSource source) {
    return ShareTarget(
      type: source.type == SourceType.Window
          ? ShareTargetType.window
          : ShareTargetType.display,
      sourceId: source.id,
      title: source.name,
    );
  }

  Future<ShareTarget> resolve(DesktopCapturerSource source) async {
    final type = source.type == SourceType.Window
        ? ShareTargetType.window
        : ShareTargetType.display;

    int? processId;
    if (type == ShareTargetType.window) {
      processId = await _resolveWindowProcessId(source);
    }

    return ShareTarget(
      type: type,
      sourceId: source.id,
      title: source.name,
      processId: processId,
    );
  }

  Future<int?> _resolveWindowProcessId(DesktopCapturerSource source) async {
    try {
      final targets = await nativeBinding.listTargets();
      if (targets.isEmpty) {
        return null;
      }

      final sourceHandle = _parseWindowHandle(source.id);
      if (sourceHandle != null) {
        for (final target in targets) {
          if (target.windowHandle == sourceHandle) {
            return target.processId;
          }
        }
      }

      final normalizedSourceName = _normalizeTitle(source.name);
      final exactMatches = targets
          .where(
              (target) => _normalizeTitle(target.title) == normalizedSourceName)
          .toList(growable: false);
      if (exactMatches.length == 1) {
        return exactMatches.single.processId;
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to resolve shared-content window process',
      );
    }

    return null;
  }

  int? _parseWindowHandle(String sourceId) {
    final candidates = RegExp(r'0x[0-9a-fA-F]+|\d+')
        .allMatches(sourceId)
        .map((match) => match.group(0))
        .whereType<String>();

    for (final candidate in candidates) {
      final value = candidate.startsWith('0x')
          ? int.tryParse(candidate.substring(2), radix: 16)
          : int.tryParse(candidate);
      if (value != null && value > 0) {
        return value;
      }
    }

    return null;
  }

  String _normalizeTitle(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

SharedAudioMode _resolveAudioMode(ShareTarget target, bool shareAudio) {
  if (!shareAudio) {
    return SharedAudioMode.none;
  }

  return switch (target.type) {
    ShareTargetType.display => SharedAudioMode.systemLoopback,
    ShareTargetType.window => target.processId == null
        ? SharedAudioMode.unavailable
        : SharedAudioMode.processTreeLoopback,
  };
}

WindowsShareTargetType _toWindowsTargetType(ShareTargetType type) {
  return switch (type) {
    ShareTargetType.display => WindowsShareTargetType.display,
    ShareTargetType.window => WindowsShareTargetType.window,
  };
}

WindowsSharedAudioMode _toWindowsAudioMode(SharedAudioMode mode) {
  return switch (mode) {
    SharedAudioMode.none => WindowsSharedAudioMode.none,
    SharedAudioMode.processTreeLoopback =>
      WindowsSharedAudioMode.processTreeLoopback,
    SharedAudioMode.systemLoopback => WindowsSharedAudioMode.systemLoopback,
    SharedAudioMode.unavailable => WindowsSharedAudioMode.unavailable,
  };
}

SharedAudioStatus _fromNativeStatus(WindowsShareSessionStatus status) {
  return SharedAudioStatus(
    state: _fromNativeState(status.audioState),
    mode: _fromNativeMode(status.audioMode),
    reason: status.reason,
    sampleRateHz: status.sampleRateHz,
    numChannels: status.numChannels,
    bitsPerSample: status.bitsPerSample,
    packetsCaptured: status.packetsCaptured,
    framesCaptured: status.framesCaptured,
    bytesCaptured: status.bytesCaptured,
    pcmBridgeSupported: status.pcmBridgeSupported,
  );
}

SharedAudioMode _fromNativeMode(WindowsSharedAudioMode mode) {
  return switch (mode) {
    WindowsSharedAudioMode.none => SharedAudioMode.none,
    WindowsSharedAudioMode.processTreeLoopback =>
      SharedAudioMode.processTreeLoopback,
    WindowsSharedAudioMode.systemLoopback => SharedAudioMode.systemLoopback,
    WindowsSharedAudioMode.unavailable => SharedAudioMode.unavailable,
  };
}

SharedAudioState _fromNativeState(WindowsSharedAudioState state) {
  return switch (state) {
    WindowsSharedAudioState.inactive => SharedAudioState.disabled,
    WindowsSharedAudioState.starting => SharedAudioState.starting,
    WindowsSharedAudioState.active => SharedAudioState.active,
    WindowsSharedAudioState.failed => SharedAudioState.failed,
    WindowsSharedAudioState.stopped => SharedAudioState.stopped,
    WindowsSharedAudioState.unavailable => SharedAudioState.unavailable,
  };
}
