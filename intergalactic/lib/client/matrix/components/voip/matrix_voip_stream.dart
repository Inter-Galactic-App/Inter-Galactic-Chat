import 'dart:async';

import 'package:intergalactic/client/components/voip/call_local_playback_operation_queue.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_session.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/list_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart';

typedef MatrixVoipStreamLocalPlaybackApplier =
    Future<void> Function(double effectiveVolume);
typedef MatrixVoipStreamLocalPlaybackNotifier = void Function();
typedef MatrixVoipStreamRendererOperation = Future<void> Function();

@visibleForTesting
Future<void> debugCancelDirectCallStreamSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelDirectCallStreamSubscription(subscription);
}

Future<void> _cancelDirectCallStreamSubscription(
  StreamSubscription? subscription,
) async {
  try {
    await subscription?.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered direct-call stream subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'direct-call-stream-subscription',
    );
  }
}

@visibleForTesting
Future<void> debugRunDirectCallRendererOperationForTesting(
  MatrixVoipStreamRendererOperation rendererOperation,
) {
  return _runDirectCallRendererOperation(
    operation: 'test',
    rendererOperation: rendererOperation,
  );
}

Future<void> _runDirectCallRendererOperation({
  required String operation,
  required MatrixVoipStreamRendererOperation rendererOperation,
  void Function(Object error)? onRecovered,
}) async {
  try {
    await rendererOperation();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered direct-call renderer $operation failure',
      category: LogCategory.webrtc,
      source: 'direct-call-renderer-operation',
    );
    onRecovered?.call(error);
  }
}

@visibleForTesting
class MatrixVoipStreamLocalPlaybackState {
  MatrixVoipStreamLocalPlaybackState({
    required MatrixVoipStreamLocalPlaybackApplier applyVolume,
    required MatrixVoipStreamLocalPlaybackNotifier notifyChanged,
  }) : _applyVolume = applyVolume,
       _notifyChanged = notifyChanged;

  final MatrixVoipStreamLocalPlaybackApplier _applyVolume;
  final MatrixVoipStreamLocalPlaybackNotifier _notifyChanged;

  /// Serializes every native playback write on this stream.
  ///
  /// `setLocalMute` and `_setLocalVolume` both mutate state and then *await*
  /// `_applyVolume`. Without a queue a later request can finish first and the
  /// earlier native write lands last, leaving the track at a volume the user
  /// no longer asked for — the exact failure after rapid deafen/unmute/volume
  /// actions. The LiveKit stream has always had this queue; the direct-call
  /// path did not, which is the same divergence between the two playback
  /// implementations that D-3 describes.
  final CallLocalPlaybackOperationQueue _playbackQueue =
      CallLocalPlaybackOperationQueue();

  bool _disposed = false;
  double _localVolume = 1.0;
  bool _locallyMuted = false;
  bool _hasLocalPlaybackVolumeOverride = false;

  double get localVolume => _localVolume;

  bool get locallyMuted => _locallyMuted || _localVolume <= 0.0;

  bool get hasLocalPlaybackVolumeOverride => _hasLocalPlaybackVolumeOverride;

  Future<void> setLocalVolume(double volume) {
    return _setLocalVolume(volume, userOverride: true);
  }

  Future<void> setLocalVolumePreservingMute(double volume) {
    return _setLocalVolume(volume, userOverride: true, preserveMute: true);
  }

  /// Assert or clear a local-only mute without touching the stored volume.
  ///
  /// Deafen used to write `track.enabled` directly on the direct-call path,
  /// which left this object reporting `locallyMuted == false` while the user
  /// was deafened, and let the `Helper.setVolume` catch path below re-enable a
  /// deafened track on the next unrelated volume write. Routing through here
  /// gives the direct-call path the same single source of truth the LiveKit
  /// path already has.
  Future<void> setLocalMute(bool muted) {
    // Only disposal short-circuits before the queue. Comparing against
    // `_locallyMuted` here would compare the APPLIED state, not the latest
    // requested one: during mute -> unmute -> mute the third request would
    // early-return because the first mute is still applied, the queued unmute
    // would run last, and playback would be left unmuted.
    if (_disposed) {
      return Future<void>.value();
    }

    return _playbackQueue.run(() async {
      // The equality check belongs here, where `_locallyMuted` reflects every
      // operation that has already run.
      if (_disposed || _locallyMuted == muted) {
        return;
      }

      _locallyMuted = muted;
      await _applyVolume(locallyMuted ? 0.0 : _localVolume);
      if (_disposed) {
        return;
      }

      _notifyChanged();
    });
  }

  Future<void> setDefaultLocalVolume(double volume) {
    if (_disposed) {
      return Future<void>.value();
    }

    // The override check runs INSIDE the queue, as the LiveKit implementation
    // does. Checking it here reads the flag before queued writes ahead of us
    // - including a queued override clear - have run, so a default-volume
    // apply issued in the same frame as the clear would be dropped against
    // stale state.
    return _playbackQueue.run(() async {
      if (_disposed || _hasLocalPlaybackVolumeOverride) {
        return;
      }
      await _setLocalVolumeQueued(volume, userOverride: false);
    });
  }

  void clearLocalPlaybackVolumeOverride() {
    if (_disposed) {
      return;
    }

    // Through the queue, exactly as the LiveKit implementation does. The
    // slider surfaces queue setLocalVolume and then call this SYNCHRONOUSLY in
    // the same frame - a synchronous clear here runs before that queued write,
    // whose `userOverride: true` then re-latches the flag. The stuck flag
    // makes setDefaultLocalVolume a silent no-op for this participant for the
    // rest of the call.
    unawaited(
      _playbackQueue.run(() async {
        if (_disposed) {
          return;
        }
        _hasLocalPlaybackVolumeOverride = false;
        _notifyChanged();
      }),
    );
  }

  void dispose() {
    _disposed = true;
  }

  Future<void> _setLocalVolume(
    double volume, {
    required bool userOverride,
    bool preserveMute = false,
  }) {
    if (_disposed) {
      return Future<void>.value();
    }

    return _playbackQueue.run(
      () => _setLocalVolumeQueued(
        volume,
        userOverride: userOverride,
        preserveMute: preserveMute,
      ),
    );
  }

  Future<void> _setLocalVolumeQueued(
    double volume, {
    required bool userOverride,
    bool preserveMute = false,
  }) async {
    if (_disposed) {
      return;
    }

    if (userOverride) {
      _hasLocalPlaybackVolumeOverride = true;
    }
    _localVolume = volume.clamp(0.0, 2.0).toDouble();
    // Equivalent to the previous `_locallyMuted = _localVolume == 0.0` when
    // preserveMute is false. A restore (preserveMute: true) may raise the
    // volume without clearing a mute another owner asserted.
    if (_localVolume == 0.0) {
      _locallyMuted = true;
    } else if (!preserveMute) {
      _locallyMuted = false;
    }

    await _applyVolume(_locallyMuted ? 0.0 : _localVolume);
    if (_disposed) {
      return;
    }

    _notifyChanged();
  }
}

@visibleForTesting
class MatrixVoipStreamReceivePriorityState {
  MatrixVoipStreamReceivePriorityState({
    required MatrixVoipStreamLocalPlaybackNotifier notifyChanged,
  }) : _notifyChanged = notifyChanged;

  final MatrixVoipStreamLocalPlaybackNotifier _notifyChanged;
  bool _disposed = false;
  VoipStreamReceivePriority _receivePriority = VoipStreamReceivePriority.high;

  VoipStreamReceivePriority get receivePriority => _receivePriority;

  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {
    if (_disposed || _receivePriority == priority) {
      return;
    }

    // Direct Matrix/WebRTC calls do not expose receiver-side quality controls
    // like LiveKit does; keep the requested state for shared UI consistency.
    _receivePriority = priority;
    if (_disposed) {
      return;
    }

    _notifyChanged();
  }

  void dispose() {
    _disposed = true;
  }
}

class MatrixVoipStream implements VoipStream, LocalPlaybackVolumeStream {
  WrappedMediaStream stream;
  MatrixVoipSession session;

  RTCVideoRenderer? renderer;
  StreamSubscription? _streamSubscription;
  bool _disposed = false;
  Future<void>? _rendererInitialization;
  String? _rendererVideoTrackSignature;
  Object? _rendererInitializationError;

  final StreamController<void> _onChanged = StreamController.broadcast();
  late final MatrixVoipStreamReceivePriorityState _receivePriorityState;
  late final MatrixVoipStreamLocalPlaybackState _localPlayback;

  @override
  Stream<void> get onStreamChanged => _onChanged.stream;

  @override
  VoipStreamReceivePriority get receivePriority =>
      _receivePriorityState.receivePriority;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) {
    return _receivePriorityState.setReceivePriority(priority);
  }

  MatrixVoipStream(this.stream, this.session) {
    _receivePriorityState = MatrixVoipStreamReceivePriorityState(
      notifyChanged: _notifyChanged,
    );
    _localPlayback = MatrixVoipStreamLocalPlaybackState(
      applyVolume: _applyLocalPlaybackVolume,
      notifyChanged: _notifyChanged,
    );
    unawaited(initRenderer());
    _streamSubscription = stream.onStreamChanged.stream.listen(
      _onStreamChanged,
    );
  }

  void _onStreamChanged(MediaStream event) {
    if (_disposed) {
      return;
    }

    final videoTrackSignature = _videoTrackSignature;
    if (_rendererVideoTrackSignature != videoTrackSignature) {
      _rendererInitializationError = null;
      _rendererVideoTrackSignature = videoTrackSignature;
    }

    final activeRenderer = renderer;
    if (activeRenderer != null) {
      if (!_assignRendererStream(activeRenderer, event)) {
        return;
      }
    } else {
      unawaited(initRenderer());
    }

    _notifyChanged();
  }

  Future<void> initRenderer() {
    if (_disposed) {
      return Future<void>.value();
    }

    final videoTrackSignature = _videoTrackSignature;
    if (videoTrackSignature == null) {
      final activeRenderer = renderer;
      renderer = null;
      _rendererVideoTrackSignature = null;
      _rendererInitializationError = null;
      if (activeRenderer != null) {
        unawaited(_disposeRendererQuietly(activeRenderer));
        _notifyChanged();
      }
      return Future<void>.value();
    }

    if (_rendererInitializationError != null &&
        _rendererVideoTrackSignature == videoTrackSignature) {
      return Future<void>.value();
    }

    final existingInitialization = _rendererInitialization;
    if (existingInitialization != null) {
      return existingInitialization;
    }

    _rendererVideoTrackSignature = videoTrackSignature;
    final initialization = _runDirectCallRendererOperation(
      operation: 'initialization',
      rendererOperation: () => _initRenderer(videoTrackSignature),
      onRecovered: (error) {
        if (_disposed) {
          return;
        }
        if (_rendererVideoTrackSignature == videoTrackSignature) {
          _rendererInitializationError = error;
          _notifyChanged();
        }
      },
    );
    _rendererInitialization = initialization;
    return initialization.whenComplete(() {
      if (identical(_rendererInitialization, initialization)) {
        _rendererInitialization = null;
      }
    });
  }

  Future<void> _initRenderer(String videoTrackSignature) async {
    final mediaStream = stream.stream;
    if (mediaStream == null || mediaStream.getVideoTracks().isEmpty) {
      return;
    }

    final r = RTCVideoRenderer();
    try {
      await r.initialize();
    } catch (error) {
      await _disposeRendererQuietly(r);
      if (_disposed) {
        return;
      }

      _rendererInitializationError = error;
      Log.w(
        'Direct Matrix call video renderer initialization failed; '
        'continuing without a video renderer (${error.runtimeType}: $error)',
        category: LogCategory.webrtc,
        source: 'direct-call-renderer',
      );
      _notifyChanged();
      return;
    }

    if (_disposed) {
      await _disposeRendererQuietly(r);
      return;
    }

    if (_rendererVideoTrackSignature != videoTrackSignature) {
      await _disposeRendererQuietly(r);
      _rendererInitialization = null;
      unawaited(initRenderer());
      return;
    }

    if (!_assignRendererStream(r, mediaStream)) {
      return;
    }
    renderer = r;
    _rendererInitializationError = null;
    _notifyChanged();
  }

  bool _assignRendererStream(
    RTCVideoRenderer activeRenderer,
    MediaStream mediaStream,
  ) {
    try {
      activeRenderer.srcObject = mediaStream;
      return true;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered direct-call renderer stream assignment failure',
        category: LogCategory.webrtc,
        source: 'direct-call-renderer-operation',
      );
      _rendererInitializationError = error;
      if (identical(renderer, activeRenderer)) {
        renderer = null;
      }
      unawaited(_disposeRendererQuietly(activeRenderer));
      if (!_disposed) {
        _notifyChanged();
      }
      return false;
    }
  }

  String? get _videoTrackSignature {
    final tracks = stream.stream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) {
      return null;
    }

    return tracks.map((track) => track.id).join('|');
  }

  Future<void> _disposeRendererQuietly(RTCVideoRenderer renderer) async {
    try {
      await renderer.dispose();
    } catch (_) {
      // Renderer disposal can race with native WebRTC teardown.
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _receivePriorityState.dispose();
    _localPlayback.dispose();
    await _cancelDirectCallStreamSubscription(_streamSubscription);
    _streamSubscription = null;
    final activeRenderer = renderer;
    renderer = null;
    if (activeRenderer != null) {
      await _disposeRendererQuietly(activeRenderer);
    }
    await _onChanged.close();
  }

  @override
  double get localVolume => _localPlayback.localVolume;

  @override
  bool get locallyMuted => _localPlayback.locallyMuted;

  @override
  bool get hasLocalPlaybackAudio =>
      stream.stream?.getAudioTracks().isNotEmpty == true;

  @override
  bool get hasLocalPlaybackVolumeOverride =>
      _localPlayback.hasLocalPlaybackVolumeOverride;

  @override
  Future<void> setLocalVolume(double volume) {
    return _localPlayback.setLocalVolume(volume);
  }

  @override
  Future<void> setLocalVolumePreservingMute(double volume) {
    return _localPlayback.setLocalVolumePreservingMute(volume);
  }

  /// Mute or unmute this stream locally. Mirrors
  /// `MatrixLivekitVoipStream.setLocalMute` so deafen has one shape across
  /// both call backends.
  Future<void> setLocalMute(bool muted) {
    return _localPlayback.setLocalMute(muted);
  }

  @override
  Future<void> setDefaultLocalVolume(double volume) {
    return _localPlayback.setDefaultLocalVolume(volume);
  }

  @override
  void clearLocalPlaybackVolumeOverride() {
    _localPlayback.clearLocalPlaybackVolumeOverride();
  }

  Future<void> _applyLocalPlaybackVolume(double effectiveVolume) async {
    if (_disposed) {
      return;
    }

    final tracks = stream.stream?.getAudioTracks() ?? const [];

    for (final track in tracks) {
      if (_disposed) {
        return;
      }

      try {
        await Helper.setVolume(effectiveVolume, track);
      } catch (_) {
        if (_disposed) {
          return;
        }

        track.enabled = effectiveVolume > 0.0;
      }
    }
  }

  void _notifyChanged() {
    if (_disposed || _onChanged.isClosed) {
      return;
    }

    try {
      _onChanged.add(());
    } catch (_) {
      // Stream callbacks can race with direct-call teardown.
    }
  }

  @override
  VoipStreamType get type {
    if (stream.purpose == SDPStreamMetadataPurpose.Screenshare) {
      return VoipStreamType.screenshare;
    }

    if (stream.videoMuted) {
      return VoipStreamType.audio;
    } else {
      return VoipStreamType.video;
    }
  }

  @override
  String get streamUserId => stream.participant.userId;

  @override
  String get label => stream.stream?.getTracks().first.label ?? "";

  @override
  double get audiolevel {
    var tracks = stream.stream?.getAudioTracks();
    var track = tracks?.firstOrNull;

    if (track == null) {
      return 0;
    }

    var stats = session.stats;

    if (stats == null) {
      return 0;
    }

    var stat = stats.tryFirstWhere((element) {
      if (element.values.containsKey("trackIdentifier") == false) {
        return false;
      }

      if (element.values.containsKey("audioLevel") == false) {
        return false;
      }

      return element.values["trackIdentifier"] == track.id;
    });

    if (stat == null) return 0;
    return stat.values["audioLevel"] > 0.2 ? 1.0 : 0;
  }

  @override
  double? get aspectRatio {
    if (renderer != null) {
      final width = renderer!.videoWidth;
      final height = renderer!.videoHeight;
      if (width > 0 && height > 0) {
        var ratio = renderer!.videoWidth / renderer!.videoHeight;
        return ratio;
      }
    }

    return 1;
  }

  @override
  String get streamId => stream.stream?.id ?? "UNKNOWN_STREAM_ID";

  @override
  bool operator ==(Object other) {
    if (other is! MatrixVoipStream) return false;
    return streamId == other.streamId;
  }

  @override
  int get hashCode => streamId.hashCode;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) {
    if (_rendererInitializationError != null) {
      return null;
    }

    if (renderer == null) {
      return CircularProgressIndicator();
    }

    if (fit == BoxFit.contain) {
      return AspectRatio(
        aspectRatio: aspectRatio ?? 1,
        child: RTCVideoView(renderer!),
      );
    } else {
      if (renderer!.textureId != null) {
        return RTCVideoView(
          key: key,
          renderer!,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
      }
    }

    return null;
  }

  @override
  VoipStreamDirection get direction => stream.isLocal()
      ? VoipStreamDirection.outgoing
      : VoipStreamDirection.incoming;

  @override
  bool get isMuted => stream.audioMuted;
}
