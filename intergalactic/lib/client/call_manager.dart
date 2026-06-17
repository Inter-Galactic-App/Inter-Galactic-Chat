import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/voip/voip_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/client/stale_info.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/custom_sound_manager.dart';
import 'package:intergalactic/utils/notifying_list.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';

class CallManager {
  ClientManager clientManager;
  final StreamController<VoipSession> _onSessionStarted =
      StreamController.broadcast();
  final StreamController<bool> _onDeafenChanged = StreamController.broadcast();

  String notificationContentUserIsCalling(String user) => Intl.message(
      "$user is calling!",
      desc:
          "Notification body content for when receiving an incoming call from another user",
      args: [user],
      name: "notificationContentUserIsCalling");

  String notificationTitleIncomingCall(String roomName) =>
      Intl.message("Incoming Call! ($roomName)",
          desc: "Notification title for when a call is being received",
          args: [roomName],
          name: "notificationTitleIncomingCall");

  Stream<VoipSession> get onSessionStarted => _onSessionStarted.stream;
  Stream<bool> get onDeafenChanged => _onDeafenChanged.stream;

  NotifyingList<VoipSession> currentSessions =
      NotifyingList.empty(growable: true);

  bool _isDeafened = false;
  bool get isDeafened => _isDeafened;
  bool _pushToTalkPressed = false;

  CallManager(this.clientManager) {
    clientManager.onClientAdded.stream.listen(_onClientAdded);
    clientManager.onClientRemoved.stream.listen(_onClientRemoved);
  }

  Player? player;
  Player? muteSoundPlayer;
  Player? unmuteSoundPlayer;

  void _onClientAdded(int index) {
    var client = clientManager.clients[index];

    var voip = client.getComponent<VoipComponent>();
    if (voip == null) {
      return;
    }

    voip.onSessionStarted.listen(onClientSessionStarted);
    voip.onSessionEnded.listen(onSessionEnded);
  }

  void _onClientRemoved(StalePeerInfo event) {}

  void onClientSessionStarted(VoipSession event) {
    var room = event.client.getRoom(event.roomId);
    currentSessions.add(event);

    if (event.state == VoipState.incoming) {
      startRingtone();

      var member = room?.getMemberOrFallback(event.remoteUserId!);

      NotificationManager.notify(CallNotificationContent(
          title: notificationTitleIncomingCall(event.roomName),
          content: notificationContentUserIsCalling(
              event.remoteUserName ?? event.remoteUserId!),
          roomId: event.roomId,
          roomName: event.roomName,
          senderName: member?.displayName ?? event.remoteUserId!,
          roomImage: room?.avatar,
          callId: event.sessionId,
          senderId: event.remoteUserId!,
          senderImage: member?.avatar,
          senderImageId: member?.avatarId,
          roomImageId: room?.avatarId,
          clientId: event.client.identifier,
          isDirectMessage: event.client
                  .getComponent<DirectMessagesComponent>()
                  ?.isRoomDirectMessage(room!) ==
              true));
    }

    if (event.state == VoipState.outgoing) {
      startOutgoingTone();
    }

    if (event.state == VoipState.connected) {
      joinCallSound();
      unawaited(soundboardPlaybackService.playJoinSoundForSession(event));
    }

    event.onConnectionStateChanged.listen((_) => onCallStateChanged(event));
    event.onStateChanged.listen((_) {
      _applyDeafenToSession(event);
      _applyPushToTalkToSession(event);
      unawaited(_applySpeakerVolumeToSession(event));
    });
    _applyDeafenToSession(event);
    _applyPushToTalkToSession(event);
    unawaited(_applySpeakerVolumeToSession(event));
  }

  void onSessionEnded(VoipSession event) {
    currentSessions
        .removeWhere((element) => element.sessionId == event.sessionId);

    if (currentSessions.where((e) => e.state == VoipState.incoming).isEmpty) {
      stopRingtone();
    }

    endCallSound();
  }

  VoipSession? getCallInRoom(Client client, String roomId) {
    return currentSessions
        .where(
            (element) => element.client == client && element.roomId == roomId)
        .firstOrNull;
  }

  void startRingtone() {
    // Let push notifications do the ringtone
    if (PlatformUtils.isAndroid) {
      return;
    }

    if (player?.state.playing == true) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media(CustomSoundManager.ringtoneSoundUri()));
  }

  void startOutgoingTone() {
    if (player?.state.playing == true) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media(CustomSoundManager.ringtoneSoundUri(outgoing: true)));
    player?.setPlaylistMode(PlaylistMode.loop);
  }

  void joinCallSound() {
    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/joined_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  void mute() {
    for (final session in _currentSessionSnapshot()) {
      session.setMicrophoneMute(true);
    }

    playMuteSound();
  }

  bool fakeToggle = false;
  void toggleMute() {
    var session = currentSessions.firstOrNull;

    if (session != null) {
      if (session.isMicrophoneMuted) {
        unmute();
      } else {
        mute();
      }
    } else {
      fakeToggle = !fakeToggle;

      // just to give user feedback when not in a call
      if (fakeToggle) {
        playMuteSound();
      } else {
        playUnmuteSound();
      }
    }
  }

  void playMuteSound() {
    if (muteSoundPlayer == null) {
      muteSoundPlayer ??= Player(configuration: PlayerConfiguration());
      muteSoundPlayer?.open(Media("asset:///assets/sound/muted.ogg"));
      muteSoundPlayer?.setPlaylistMode(PlaylistMode.none);
    }

    muteSoundPlayer!.setVolume(preferences.notificationsVolume.value);
    muteSoundPlayer?.seek(Duration.zero);
    muteSoundPlayer?.play();
  }

  void unmute() {
    for (final session in _currentSessionSnapshot()) {
      session.setMicrophoneMute(false);
    }

    playUnmuteSound();
  }

  void pushToTalkStart() {
    if (!preferences.voipPushToTalkEnabled.value || _pushToTalkPressed) {
      return;
    }

    _pushToTalkPressed = true;
    for (final session in _currentSessionSnapshot()) {
      session.setMicrophoneMute(false);
    }

    if (currentSessions.isNotEmpty) {
      playUnmuteSound();
    }
  }

  void pushToTalkEnd() {
    if (!_pushToTalkPressed) {
      return;
    }

    _pushToTalkPressed = false;

    for (final session in _currentSessionSnapshot()) {
      session.setMicrophoneMute(true);
    }

    if (currentSessions.isNotEmpty) {
      playMuteSound();
    }
  }

  void applyPushToTalkPreference() {
    if (!preferences.voipPushToTalkEnabled.value) {
      _pushToTalkPressed = false;
      for (final session in _currentSessionSnapshot()) {
        unawaited(session.setMicrophoneMute(false));
      }
      return;
    }

    for (final session in _currentSessionSnapshot()) {
      _applyPushToTalkToSession(session);
    }
  }

  void playUnmuteSound() {
    if (unmuteSoundPlayer == null) {
      unmuteSoundPlayer ??= Player(configuration: PlayerConfiguration());
      unmuteSoundPlayer?.open(Media("asset:///assets/sound/unmuted.ogg"));
      unmuteSoundPlayer?.setPlaylistMode(PlaylistMode.none);
    }

    unmuteSoundPlayer!.setVolume(preferences.notificationsVolume.value);
    unmuteSoundPlayer?.seek(Duration.zero);
    unmuteSoundPlayer?.play();
  }

  void toggleDeafen() {
    setDeafened(!_isDeafened);
  }

  void setDeafened(bool value) {
    if (_isDeafened == value) {
      return;
    }

    _isDeafened = value;
    for (final session in _currentSessionSnapshot()) {
      _applyDeafenToSession(session);
      if (!_isDeafened) {
        unawaited(_applySpeakerVolumeToSession(session));
      }
    }
    _onDeafenChanged.add(_isDeafened);
  }

  void _applyDeafenToSession(VoipSession session) {
    for (final stream in _streamSnapshot(session)) {
      _applyDeafenToStream(stream);
    }
  }

  void _applyPushToTalkToSession(VoipSession session) {
    if (!preferences.voipPushToTalkEnabled.value || _pushToTalkPressed) {
      return;
    }

    unawaited(session.setMicrophoneMute(true));
  }

  Future<void> applySpeakerVolumePreference() async {
    for (final session in _currentSessionSnapshot()) {
      await _applySpeakerVolumeToSession(session);
    }
  }

  @visibleForTesting
  Future<void> applySpeakerVolumeToSessionForTesting(VoipSession session) {
    return _applySpeakerVolumeToSession(session);
  }

  Future<void> _applySpeakerVolumeToSession(VoipSession session) async {
    for (final stream in _streamSnapshot(session)) {
      await _applySpeakerVolumeToStream(stream);
    }
  }

  List<VoipSession> _currentSessionSnapshot() {
    return List<VoipSession>.of(currentSessions);
  }

  List<VoipStream> _streamSnapshot(VoipSession session) {
    return List<VoipStream>.of(session.streams);
  }

  Future<void> _applySpeakerVolumeToStream(VoipStream stream) async {
    if (_isDeafened || stream.direction != VoipStreamDirection.incoming) {
      return;
    }

    final volume = Preferences.voipSpeakerVolumeToLocalPlayback(
      preferences.voipSpeakerVolume.value,
    );

    if (stream.type != VoipStreamType.audio) {
      return;
    }

    if (stream is MatrixLivekitVoipStream && stream.isScreenShareAudio) {
      return;
    }

    if (stream is LocalPlaybackVolumeStream) {
      await (stream as LocalPlaybackVolumeStream).setDefaultLocalVolume(volume);
    }
  }

  Future<void> _applyDeafenToStream(VoipStream stream) async {
    if (stream.direction != VoipStreamDirection.incoming) {
      return;
    }

    if (stream is MatrixLivekitVoipStream &&
        stream.type == VoipStreamType.audio) {
      await stream.setLocalMute(_isDeafened);
      return;
    }

    if (stream is MatrixVoipStream) {
      final tracks = stream.stream.stream?.getAudioTracks() ?? const [];
      for (final track in tracks) {
        track.enabled = !_isDeafened;
      }
    }
  }

  void endCallSound() {
    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/left_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  void stopRingtone() {
    player?.stop();
    player?.dispose();
    player = null;
  }

  void onCallStateChanged(VoipSession event) {
    if (event.state == VoipState.connected ||
        event.state == VoipState.connecting) {
      stopRingtone();
    }

    if (event.state == VoipState.connected) {
      joinCallSound();
      unawaited(soundboardPlaybackService.playJoinSoundForSession(event));
    }
  }

  Player getSoundPlayer() {
    player ??= Player(configuration: PlayerConfiguration());
    player!.setVolume(preferences.notificationsVolume.value);

    return player!;
  }
}
