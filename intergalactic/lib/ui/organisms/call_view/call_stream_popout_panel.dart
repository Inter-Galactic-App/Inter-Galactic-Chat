import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/components/voip/call_local_playback_operation_guard.dart';
import 'package:intergalactic/client/components/voip/call_participant_audio_overrides.dart';
import 'package:intergalactic/client/components/voip/call_preference_operation_guard.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_identity.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_fullscreen_stream_view.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_stream_view.dart';

class ResolvedCallStreamPopout {
  const ResolvedCallStreamPopout({
    required this.session,
    required this.stream,
    required this.popoutId,
    this.audioStream,
    this.volumeStream,
  });

  final VoipSession session;
  final VoipStream stream;
  final String popoutId;
  final VoipStream? audioStream;
  final VoipStream? volumeStream;

  bool get isAudio => stream.type == VoipStreamType.audio;
  bool get isScreenshare => stream.type == VoipStreamType.screenshare;

  String get title =>
      isScreenshare ? '${session.roomName} Screen' : session.roomName;
}

ResolvedCallStreamPopout? resolveCallStreamPopout({
  required CallManager callManager,
  required String sessionId,
  required String streamId,
}) {
  return resolveCallStreamPopoutFromSessions(
    sessions: callManager.currentSessions,
    sessionId: sessionId,
    streamId: streamId,
  );
}

ResolvedCallStreamPopout? resolveCallStreamPopoutFromSessions({
  required Iterable<VoipSession> sessions,
  required String sessionId,
  required String streamId,
}) {
  final session = sessions.firstWhereOrNull(
    (session) => session.sessionId == sessionId,
  );
  if (session == null) {
    return null;
  }

  final matchingStreams = session.streams
      .where((item) => callStreamPopoutIdForStream(item) == streamId)
      .toList(growable: false);
  final stream =
      matchingStreams.firstWhereOrNull(
        (item) =>
            item.type == VoipStreamType.video ||
            item.type == VoipStreamType.screenshare,
      ) ??
      matchingStreams.firstOrNull ??
      session.streams.firstWhereOrNull((item) => item.streamId == streamId);
  if (stream == null) {
    return null;
  }

  final popoutId = matchingStreams.isEmpty
      ? streamId
      : callStreamPopoutIdForStream(stream);

  final audioStream = session.streams.firstWhereOrNull(
    (item) =>
        item.streamUserId == stream.streamUserId &&
        item.type == VoipStreamType.audio &&
        (item is! MatrixLivekitVoipStream || item.isMicrophoneAudio),
  );

  return ResolvedCallStreamPopout(
    session: session,
    stream: stream,
    audioStream: audioStream,
    volumeStream: _findVolumeStream(session, stream, audioStream),
    popoutId: popoutId,
  );
}

bool shouldStopDeadLocalScreensharePopoutOnNativeClose({
  required ResolvedCallStreamPopout? popout,
  required String? localUserId,
}) {
  if (popout == null || !popout.isScreenshare) {
    return false;
  }

  if (localUserId == null || popout.stream.streamUserId != localUserId) {
    return false;
  }

  final tracks = popout.session.diagnosticsSnapshot.tracks;
  return tracks.any(
    (track) =>
        track.streamId == popout.stream.streamId &&
        track.type == VoipStreamType.screenshare &&
        track.direction == VoipDiagnosticsTrackDirection.sender &&
        (track.captureFps ?? 1) <= 0.1,
  );
}

@visibleForTesting
({
  EdgeInsets padding,
  bool edgeToEdge,
  bool showTileScrim,
  bool useRootOverlayForMenus,
})
debugResolveCallStreamPopoutSurfaceTreatmentForTesting({
  required bool transparentChrome,
}) {
  return _resolveCallStreamPopoutSurfaceTreatment(
    transparentChrome: transparentChrome,
  );
}

({
  EdgeInsets padding,
  bool edgeToEdge,
  bool showTileScrim,
  bool useRootOverlayForMenus,
})
_resolveCallStreamPopoutSurfaceTreatment({required bool transparentChrome}) {
  return (
    padding: const EdgeInsets.all(8),
    edgeToEdge: false,
    showTileScrim: true,
    useRootOverlayForMenus: !transparentChrome,
  );
}

class CallStreamPopoutContent extends StatefulWidget {
  const CallStreamPopoutContent({
    super.key,
    required this.popout,
    required this.transparentChrome,
  });

  final ResolvedCallStreamPopout popout;
  final bool transparentChrome;

  @override
  State<CallStreamPopoutContent> createState() =>
      _CallStreamPopoutContentState();
}

class _CallStreamPopoutContentState extends State<CallStreamPopoutContent> {
  StreamSubscription<UserActivity?>? _activitySub;
  StreamSubscription? _presenceSub;
  UserActivity? _localGameActivity;
  String? _remoteGameActivityPresenceText;

  double get _defaultParticipantAudioVolume =>
      Preferences.voipSpeakerVolumeToLocalPlayback(
        preferences.voipSpeakerVolume.value,
      );

  @override
  void initState() {
    super.initState();
    _localGameActivity = activityService.currentGameActivity;
    _activitySub = activityService.onActivityChanged.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localGameActivity = activityService.currentGameActivity;
      });
    });
    _initRemotePresenceTracking();
    _applyPoppedOutReceivePriority();
  }

  @override
  void didUpdateWidget(CallStreamPopoutContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.popout.stream != widget.popout.stream ||
        oldWidget.popout.audioStream != widget.popout.audioStream) {
      _applyPoppedOutReceivePriority();
      _localGameActivity = activityService.currentGameActivity;
      _initRemotePresenceTracking();
    }
  }

  @override
  void dispose() {
    final activitySub = _activitySub;
    final presenceSub = _presenceSub;
    _activitySub = null;
    _presenceSub = null;
    unawaited(_cancelCallStreamPopoutSubscription(activitySub));
    unawaited(_cancelCallStreamPopoutSubscription(presenceSub));
    super.dispose();
  }

  void _applyPoppedOutReceivePriority() {
    unawaited(_setPoppedOutReceivePriority(widget.popout.stream));
    final audioStream = widget.popout.audioStream;
    if (audioStream != null) {
      unawaited(_setPoppedOutReceivePriority(audioStream));
    }
  }

  void _initRemotePresenceTracking() {
    final presenceSub = _presenceSub;
    _presenceSub = null;
    unawaited(_cancelCallStreamPopoutSubscription(presenceSub));
    _remoteGameActivityPresenceText = null;

    final userId = widget.popout.stream.streamUserId;
    if (widget.popout.isScreenshare ||
        userId == widget.popout.session.client.self?.identifier) {
      return;
    }

    final presenceComponent = widget.popout.session.client
        .getComponent<UserPresenceComponent>();
    if (presenceComponent == null) {
      return;
    }

    _presenceSub = presenceComponent.onPresenceChanged
        .where((event) => event.$1 == userId)
        .listen((event) {
          if (!mounted || widget.popout.stream.streamUserId != userId) {
            return;
          }
          setState(() {
            _remoteGameActivityPresenceText = event.$2.message?.message;
          });
        });
    unawaited(_loadRemotePresence(presenceComponent, userId));
  }

  Future<void> _loadRemotePresence(
    UserPresenceComponent presenceComponent,
    String userId,
  ) async {
    try {
      final presence = await presenceComponent.getUserPresence(userId);
      if (!mounted || widget.popout.stream.streamUserId != userId) {
        return;
      }
      setState(() {
        _remoteGameActivityPresenceText = presence.message?.message;
      });
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to load panel popout participant presence',
        category: LogCategory.matrix,
        source: 'call-stream-popout',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final popout = widget.popout;
    final stream = popout.stream;
    final session = popout.session;
    final transparentChrome = widget.transparentChrome;
    final surfaceTreatment = _resolveCallStreamPopoutSurfaceTreatment(
      transparentChrome: transparentChrome,
    );

    return Padding(
      padding: surfaceTreatment.padding,
      child: VoipStreamView(
        key: ValueKey('stream-popout-${session.sessionId}-${stream.streamId}'),
        stream,
        session,
        fit: popout.isScreenshare ? BoxFit.contain : BoxFit.cover,
        isFocused: true,
        edgeToEdge: surfaceTreatment.edgeToEdge,
        showTileScrim: surfaceTreatment.showTileScrim,
        isMicrophoneMuted: popout.audioStream?.isMuted ?? false,
        gameActivity: _gameActivityForPopout,
        gameActivityPresenceText: _gameActivityPresenceTextForPopout,
        volumeStream: popout.volumeStream,
        defaultVolume: _defaultParticipantAudioVolume,
        useRootOverlayForMenus: surfaceTreatment.useRootOverlayForMenus,
        onVolumeChanged: _canControlVolume ? (vol) => _setVolume(vol) : null,
        onFullscreen: () {
          unawaited(
            showVoipStreamFullscreen(context, session: session, stream: stream),
          );
        },
      ),
    );
  }

  bool get _canControlVolume =>
      widget.popout.volumeStream is LocalPlaybackVolumeStream &&
      widget.popout.stream.streamUserId !=
          widget.popout.session.client.self?.identifier;

  UserActivity? get _gameActivityForPopout {
    if (widget.popout.isScreenshare ||
        widget.popout.stream.streamUserId !=
            widget.popout.session.client.self?.identifier) {
      return null;
    }

    return _localGameActivity;
  }

  String? get _gameActivityPresenceTextForPopout {
    if (widget.popout.isScreenshare ||
        widget.popout.stream.streamUserId ==
            widget.popout.session.client.self?.identifier) {
      return null;
    }

    return _remoteGameActivityPresenceText;
  }

  void _setVolume(double volume) {
    final target = widget.popout.volumeStream;
    if (target == null) {
      return;
    }
    if (target is! LocalPlaybackVolumeStream) {
      return;
    }
    final volumeTarget = target as LocalPlaybackVolumeStream;

    final clampedVolume = Preferences.clampScreenShareAudioVolume(volume);
    unawaited(
      CallLocalPlaybackOperationGuard.runAsync(
        operation: () => volumeTarget.setLocalVolume(clampedVolume),
        content: 'Recovered panel popout local playback volume failure',
        source: 'call-stream-popout',
      ),
    );
    if (target is MatrixLivekitVoipStream && target.isScreenShareAudio) {
      final room = widget.popout.session.client.getRoom(
        widget.popout.session.roomId,
      );
      if (room != null) {
        unawaited(
          CallPreferenceOperationGuard.run(
            operation: () => preferences.setScreenShareAudioVolume(
              roomLocalId: room.localId,
              streamUserId: target.streamUserId,
              volume: clampedVolume,
            ),
            content:
                'Recovered panel popout screen share audio volume preference failure',
            source: 'call-volume-preference',
          ),
        );
      }
    } else {
      // Write the change back to the same store CallView reads from.
      //
      // Without this the popout applied the volume to the live track and
      // remembered nothing, so the next CallView build restored the stale
      // stored value straight over it - the popout slider "did nothing" as
      // soon as anything rebuilt the call surface. `remember` also owns the
      // back-to-default case: it drops the entry and clears the stream's
      // override flag, which is what the explicit clear here used to do.
      CallLocalPlaybackOperationGuard.runSync(
        operation: () =>
            CallParticipantAudioOverridesStore.forSession(
              widget.popout.session,
            ).remember(
              target,
              volume: clampedVolume,
              defaultVolume: _defaultParticipantAudioVolume,
              isMicrophoneAudio:
                  CallParticipantAudioOverridesStore.isParticipantMicrophoneAudio(
                    target,
                  ),
            ),
        content: 'Recovered panel popout volume override write failure',
        source: 'call-stream-popout',
      );
    }
  }
}

VoipStream? _findVolumeStream(
  VoipSession session,
  VoipStream stream,
  VoipStream? audioStream,
) {
  if (stream.type == VoipStreamType.screenshare) {
    final screenShareAudio = session.streams.firstWhereOrNull(
      (item) =>
          item.streamUserId == stream.streamUserId &&
          item is MatrixLivekitVoipStream &&
          item.isScreenShareAudio,
    );
    if (_supportsLocalPlaybackVolume(screenShareAudio)) {
      return screenShareAudio;
    }
  }

  if (_supportsLocalPlaybackVolume(audioStream)) {
    return audioStream;
  }

  if (_supportsLocalPlaybackVolume(stream)) {
    return stream;
  }

  return null;
}

bool _supportsLocalPlaybackVolume(VoipStream? stream) {
  if (stream == null) {
    return false;
  }
  if (stream is! LocalPlaybackVolumeStream) {
    return false;
  }
  final volumeStream = stream as LocalPlaybackVolumeStream;
  return volumeStream.hasLocalPlaybackAudio;
}

@visibleForTesting
Future<void> debugSetPoppedOutReceivePriorityForTesting(VoipStream stream) {
  return _setPoppedOutReceivePriority(stream);
}

@visibleForTesting
Future<void> debugCancelCallStreamPopoutSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelCallStreamPopoutSubscription(subscription);
}

Future<void> _setPoppedOutReceivePriority(VoipStream stream) async {
  try {
    await stream.setReceivePriority(VoipStreamReceivePriority.high);
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered popped-out call stream priority failure',
      category: LogCategory.media,
      source: 'call-stream-popout',
    );
  }
}

Future<void> _cancelCallStreamPopoutSubscription(
  StreamSubscription? subscription,
) async {
  if (subscription == null) {
    return;
  }

  try {
    await subscription.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered popped-out call stream subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'call-stream-popout',
    );
  }
}
