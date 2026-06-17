import 'dart:async';

import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_session.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/list_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart';

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
  VoipStreamReceivePriority _receivePriority = VoipStreamReceivePriority.high;
  double _localVolume = 1.0;
  bool _locallyMuted = false;
  bool _hasLocalPlaybackVolumeOverride = false;

  @override
  Stream<void> get onStreamChanged => _onChanged.stream;

  @override
  VoipStreamReceivePriority get receivePriority => _receivePriority;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {
    if (_receivePriority == priority) {
      return;
    }

    // Direct Matrix/WebRTC calls do not expose receiver-side quality controls
    // like LiveKit does; keep the requested state for shared UI consistency.
    _receivePriority = priority;
    _notifyChanged();
  }

  MatrixVoipStream(this.stream, this.session) {
    unawaited(initRenderer());
    _streamSubscription =
        stream.onStreamChanged.stream.listen(_onStreamChanged);
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

    if (renderer != null) {
      renderer!.srcObject = event;
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
    final initialization = _initRenderer(videoTrackSignature);
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

    r.srcObject = mediaStream;
    renderer = r;
    _rendererInitializationError = null;
    _notifyChanged();
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
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    final activeRenderer = renderer;
    renderer = null;
    if (activeRenderer != null) {
      await _disposeRendererQuietly(activeRenderer);
    }
    await _onChanged.close();
  }

  @override
  double get localVolume => _localVolume;

  @override
  bool get locallyMuted => _locallyMuted || _localVolume <= 0.0;

  @override
  bool get hasLocalPlaybackAudio =>
      stream.stream?.getAudioTracks().isNotEmpty == true;

  @override
  bool get hasLocalPlaybackVolumeOverride => _hasLocalPlaybackVolumeOverride;

  @override
  Future<void> setLocalVolume(double volume) async {
    _hasLocalPlaybackVolumeOverride = true;
    _localVolume = volume.clamp(0.0, 2.0).toDouble();
    _locallyMuted = _localVolume == 0.0;
    await _applyLocalPlaybackVolume();
    _notifyChanged();
  }

  @override
  Future<void> setDefaultLocalVolume(double volume) async {
    if (_hasLocalPlaybackVolumeOverride) {
      return;
    }
    _localVolume = volume.clamp(0.0, 2.0).toDouble();
    _locallyMuted = _localVolume == 0.0;
    await _applyLocalPlaybackVolume();
    _notifyChanged();
  }

  @override
  void clearLocalPlaybackVolumeOverride() {
    _hasLocalPlaybackVolumeOverride = false;
  }

  Future<void> _applyLocalPlaybackVolume() async {
    final effectiveVolume = _locallyMuted ? 0.0 : _localVolume;
    final tracks = stream.stream?.getAudioTracks() ?? const [];

    for (final track in tracks) {
      try {
        await Helper.setVolume(effectiveVolume, track);
      } catch (_) {
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
          aspectRatio: aspectRatio ?? 1, child: RTCVideoView(renderer!));
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
