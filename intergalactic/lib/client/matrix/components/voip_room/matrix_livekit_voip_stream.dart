import 'dart:async';
import 'dart:convert';

import 'package:intergalactic/client/components/voip/voip_receive_quality_policy.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

bool isLiveKitAudioVisualizerPluginError(Object error) {
  if (error is! MissingPluginException && error is! PlatformException) {
    return false;
  }

  return error.toString().contains('io.livekit.audio.visualizer');
}

class MatrixLivekitVoipStream implements VoipStream, LocalPlaybackVolumeStream {
  TrackPublication publication;
  String userId;

  AudioVisualizer? visualizer;
  EventsListener<AudioVisualizerEvent>? _visualizerListener;
  Future<void>? _visualizerStartFuture;

  /// Local-only mute state (does not signal anything to the remote participant).
  bool _locallyMuted = false;
  bool get locallyMuted => _locallyMuted || _localVolume <= 0.0;

  /// Local volume level (0.0 = silent, 1.0 = normal, >1.0 = boost).
  double _localVolume = 1.0;
  double get localVolume => _localVolume;
  bool _hasLocalPlaybackVolumeOverride = false;

  @override
  bool get hasLocalPlaybackAudio => publication.kind == TrackType.AUDIO;

  @override
  bool get hasLocalPlaybackVolumeOverride => _hasLocalPlaybackVolumeOverride;

  final StreamController<void> _onChanged = StreamController.broadcast();
  VoipStreamReceivePriority _receivePriority = VoipStreamReceivePriority.high;
  String? _receiveQualityLabel = VoipReceiveQualityApplication.fromPriority(
    VoipStreamReceivePriority.high,
  ).liveKitQualityLabel;
  Future<void> _priorityUpdate = Future<void>.value();
  bool _disposed = false;

  bool get isScreenShareAudio =>
      publication.source == TrackSource.screenShareAudio ||
      publication.name == 'screenShareAudio';

  bool get isMicrophoneAudio =>
      publication.kind == TrackType.AUDIO && !isScreenShareAudio;

  @override
  Stream<void> get onStreamChanged => _onChanged.stream;

  @override
  VoipStreamReceivePriority get receivePriority => _receivePriority;

  String? get receiveQualityLabel => _receiveQualityLabel;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) {
    _priorityUpdate = _priorityUpdate.catchError((_) {}).then((_) async {
      if (_disposed || _receivePriority == priority) {
        return;
      }

      final application = VoipReceiveQualityApplication.fromPriority(priority);
      var appliedQualityLabel = application.liveKitQualityLabel;
      final remotePublication = publication;
      if (remotePublication is RemoteTrackPublication &&
          remotePublication.kind == TrackType.VIDEO) {
        switch (application.videoQuality) {
          case null:
            await remotePublication.disable();
            await remotePublication.unsubscribe();
            break;
          case VoipReceiveVideoQuality.low:
            await remotePublication.subscribe();
            await remotePublication.enable();
            await remotePublication.setVideoQuality(VideoQuality.LOW);
            break;
          case VoipReceiveVideoQuality.medium:
            await remotePublication.subscribe();
            await remotePublication.enable();
            await remotePublication.setVideoQuality(VideoQuality.MEDIUM);
            break;
          case VoipReceiveVideoQuality.high:
            await remotePublication.subscribe();
            await remotePublication.enable();
            await remotePublication.setVideoQuality(VideoQuality.HIGH);
            break;
        }
        _logReceivePriorityTransition(priority, application);
      }

      if (_disposed) {
        return;
      }

      _receivePriority = priority;
      _receiveQualityLabel = appliedQualityLabel;
      _notifyChanged();
    });

    return _priorityUpdate;
  }

  void _logReceivePriorityTransition(
    VoipStreamReceivePriority priority,
    VoipReceiveQualityApplication application,
  ) {
    if (!preferences.showCallStreamStats.value) {
      return;
    }

    final redactedUserId =
        sha256.convert(utf8.encode(streamUserId)).toString().substring(0, 12);

    Log.i(
      'LiveKit receive priority applied: '
      'stream=$streamId user=$redactedUserId '
      'source=${publication.source} name=${publication.name} '
      'requested=${priority.name} '
      'quality=${application.liveKitQualityLabel} '
      'subscribed=${application.subscribe} enabled=${application.enable}',
    );
  }

  MatrixLivekitVoipStream(
    this.publication,
    this.userId, {
    String? participantIdentity,
  }) : participantIdentity = participantIdentity ?? userId {
    if (publication is RemoteTrackPublication && isScreenShareAudio) {
      _locallyMuted = true;
      unawaited(_applyLocalPlaybackVolume());
    }

    if (publication.track is AudioTrack) {
      _startAudioVisualizer(publication.track as AudioTrack);
    }
  }

  @override
  double audiolevel = 0.0;

  final String participantIdentity;

  void setAudioLevel(AudioVisualizerEvent e) {
    audiolevel = (e.event[0] as double) > 0.5 ? 1 : 0;
  }

  void onStreamUpdatedEvent() {
    if (publication.kind == TrackType.AUDIO) {
      unawaited(_applyLocalPlaybackVolume());
    }
    _notifyChanged();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _disposeAudioVisualizer();
    if (!_onChanged.isClosed) {
      await _onChanged.close();
    }
  }

  void _startAudioVisualizer(AudioTrack track) {
    try {
      final nextVisualizer = createVisualizer(
        track,
        options: AudioVisualizerOptions(
          barCount: 1,
          smoothTransition: false,
        ),
      );
      final nextListener = nextVisualizer.createListener();
      nextListener.on<AudioVisualizerEvent>(setAudioLevel);

      visualizer = nextVisualizer;
      _visualizerListener = nextListener;
      _visualizerStartFuture = nextVisualizer.start().catchError(
        (Object error, StackTrace _) {
          _logAudioVisualizerWarning(
            error,
            action: 'start',
          );
        },
      );
    } catch (error, _) {
      _logAudioVisualizerWarning(
        error,
        action: 'create',
      );
    }
  }

  Future<void> _disposeAudioVisualizer() async {
    final startFuture = _visualizerStartFuture;
    _visualizerStartFuture = null;
    if (startFuture != null) {
      await _runAudioVisualizerStep('start completion', () => startFuture);
    }

    final listener = _visualizerListener;
    _visualizerListener = null;
    await _runAudioVisualizerStep('listener dispose', listener?.dispose);

    final activeVisualizer = visualizer;
    visualizer = null;
    await _runAudioVisualizerStep('stop', activeVisualizer?.stop);
    await _runAudioVisualizerStep('dispose', activeVisualizer?.dispose);
  }

  Future<void> _runAudioVisualizerStep(
    String action,
    Future<void> Function()? step,
  ) async {
    if (step == null) {
      return;
    }

    try {
      await step();
    } catch (error, _) {
      _logAudioVisualizerWarning(
        error,
        action: action,
      );
    }
  }

  void _logAudioVisualizerWarning(
    Object error, {
    required String action,
  }) {
    final expectedPluginError = isLiveKitAudioVisualizerPluginError(error);
    Log.w(
      'LiveKit audio visualizer $action failed; call audio remains active '
      '(${expectedPluginError ? 'plugin teardown' : error.runtimeType}: '
      '$error)',
      category: LogCategory.livekit,
      source: 'audio-visualizer',
    );
  }

  /// Mute or unmute this stream locally (only affects what the local user
  /// hears — does not send any signal to the remote participant).
  Future<void> setLocalMute(bool muted) async {
    _locallyMuted = muted;
    await _applyLocalPlaybackVolume();
    _notifyChanged();
  }

  Future<void> _applyLocalPlaybackVolume() async {
    final track = publication.track;
    if (track != null) {
      final effectiveVolume = _locallyMuted ? 0.0 : _localVolume;
      try {
        await rtc.Helper.setVolume(
          effectiveVolume,
          track.mediaStreamTrack,
        );
      } catch (_) {
        // Fall back to enable/disable if setVolume is unavailable.
        if (effectiveVolume == 0.0) {
          await track.disable();
        } else {
          await track.enable();
        }
      }
    }
  }

  /// Set the local playback volume for this stream (0.0–2.0).
  /// This only affects what the local user hears.
  Future<void> setLocalVolume(double volume) {
    return _setLocalVolume(
      volume,
      preserveMute: false,
      userOverride: true,
    );
  }

  @override
  Future<void> setDefaultLocalVolume(double volume) {
    if (_hasLocalPlaybackVolumeOverride) {
      return Future<void>.value();
    }
    return _setLocalVolume(
      volume,
      preserveMute: false,
      userOverride: false,
    );
  }

  @override
  void clearLocalPlaybackVolumeOverride() {
    _hasLocalPlaybackVolumeOverride = false;
  }

  /// Restore a saved playback volume without clearing a visibility mute.
  ///
  /// Remote screenshare audio starts muted while the matching video tile is
  /// hidden. Restoring the user's saved volume must not briefly reopen that
  /// audio before the tile reveal policy has a chance to run.
  Future<void> setLocalVolumePreservingMute(double volume) {
    return _setLocalVolume(
      volume,
      preserveMute: true,
      userOverride: true,
    );
  }

  Future<void> _setLocalVolume(
    double volume, {
    required bool preserveMute,
    required bool userOverride,
  }) async {
    if (userOverride) {
      _hasLocalPlaybackVolumeOverride = true;
    }
    _localVolume = volume.clamp(0.0, 2.0);
    if (_localVolume == 0.0) {
      _locallyMuted = true;
    } else if (!preserveMute) {
      _locallyMuted = false;
    }

    await _applyLocalPlaybackVolume();
    _notifyChanged();
  }

  void _notifyChanged() {
    if (_disposed || _onChanged.isClosed) {
      return;
    }

    try {
      _onChanged.add(());
    } catch (_) {
      // Stream updates can race with call teardown.
    }
  }

  @override
  double? get aspectRatio {
    if (publication.dimensions == null) {
      return null;
    }
    return publication.dimensions!.width.toDouble() /
        publication.dimensions!.height.toDouble();
  }

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) {
    if (publication.track is VideoTrack) {
      return VideoTrackRenderer(
        publication.track as VideoTrack,
        key: key,
        fit: fit == BoxFit.cover ? VideoViewFit.cover : VideoViewFit.contain,
      );
    }

    return null;
  }

  @override
  VoipStreamDirection get direction => publication is LocalTrackPublication
      ? VoipStreamDirection.outgoing
      : VoipStreamDirection.incoming;

  @override
  String get label => "label";

  @override
  String get streamId => publication.sid;

  @override
  String get streamUserId => userId;

  @override
  VoipStreamType get type {
    if (publication.track is AudioTrack) {
      return VoipStreamType.audio;
    }

    if (publication.isScreenShare) {
      return VoipStreamType.screenshare;
    }

    return VoipStreamType.video;
  }

  @override
  bool get isMuted => publication.track?.muted ?? false;
}
