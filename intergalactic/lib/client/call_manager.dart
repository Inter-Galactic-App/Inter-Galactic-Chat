import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_monitor.dart';
import 'package:intergalactic/client/components/voip/audio/windows_call_audio_ducking.dart';
import 'package:intergalactic/client/components/voip/call_local_playback_operation_guard.dart';
import 'package:intergalactic/client/components/voip/mobile_call_background_controller.dart';
import 'package:intergalactic/client/components/voip/voip_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/client/stale_info.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/custom_sound_manager.dart';
import 'package:intergalactic/utils/notifying_list.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/hotkey_display.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/push_to_talk_hotkey_monitor.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
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
    name: "notificationContentUserIsCalling",
  );

  String notificationTitleIncomingCall(String roomName) => Intl.message(
    "Incoming Call! ($roomName)",
    desc: "Notification title for when a call is being received",
    args: [roomName],
    name: "notificationTitleIncomingCall",
  );

  Stream<VoipSession> get onSessionStarted => _onSessionStarted.stream;
  Stream<bool> get onDeafenChanged => _onDeafenChanged.stream;

  NotifyingList<VoipSession> currentSessions = NotifyingList.empty(
    growable: true,
  );

  bool _isDeafened = false;
  bool get isDeafened => _isDeafened;
  bool _pushToTalkPressed = false;
  bool _disposed = false;
  bool _loggedPushToTalkUnavailable = false;
  late final PushToTalkHotkeyMonitor _pushToTalkHotkeyMonitor;
  final List<StreamSubscription> _managerSubscriptions = [];
  final Map<String, List<StreamSubscription>> _clientVoipSubscriptions = {};
  final Map<String, List<StreamSubscription>> _sessionSubscriptions = {};
  final Map<VoipSession, bool> _pushToTalkDesiredMuteBySession = {};
  final Set<VoipSession> _pushToTalkReleaseTrackedSessions = {};
  final Set<VoipSession> _pushToTalkMuteApplyInFlight = {};
  final Map<VoipSession, bool> _manualDesiredMuteBySession = {};
  final Set<VoipSession> _manualMuteApplyInFlight = {};

  CallManager(
    this.clientManager, {
    PushToTalkHotkeyMonitor? pushToTalkHotkeyMonitor,
  }) {
    _pushToTalkHotkeyMonitor =
        pushToTalkHotkeyMonitor ??
        PushToTalkHotkeyMonitor(
          onPressed: pushToTalkStart,
          onReleased: pushToTalkEnd,
        );
    _managerSubscriptions.addAll([
      clientManager.onClientAdded.stream.listen(_onClientAdded),
      clientManager.onClientRemoved.stream.listen(_onClientRemoved),
    ]);
  }

  Player? player;
  Player? muteSoundPlayer;
  Player? unmuteSoundPlayer;
  Player? streamCuePlayer;
  @visibleForTesting
  bool disableSoundEffectsForTesting = false;
  @visibleForTesting
  MobileCallBackgroundController mobileCallBackgroundController =
      MobileCallBackgroundController.instance;

  void _onClientAdded(int index) {
    if (_disposed) {
      return;
    }
    if (index < 0 || index >= clientManager.clients.length) {
      return;
    }

    var client = clientManager.clients[index];

    var voip = client.getComponent<VoipComponent>();
    if (voip == null) {
      return;
    }

    _cancelClientSubscriptions(client.identifier);
    _removeSessionsForClientId(client.identifier, playEndSound: false);
    _clientVoipSubscriptions[client.identifier] = [
      voip.onSessionStarted.listen(onClientSessionStarted),
      voip.onSessionEnded.listen(onSessionEnded),
    ];
  }

  void _onClientRemoved(StalePeerInfo event) {
    final clientId = event.localClientId ?? event.identifier;
    if (clientId == null) {
      return;
    }

    _cancelClientSubscriptions(clientId);
    _removeSessionsForClientId(clientId, playEndSound: false);
  }

  void onClientSessionStarted(VoipSession event) {
    if (_disposed || event.state == VoipState.ended) {
      return;
    }

    var room = event.client.getRoom(event.roomId);
    currentSessions.removeWhere(
      (element) => element.sessionId == event.sessionId,
    );
    currentSessions.add(event);
    // Receiver-side loudness measurement follows the call, not any view. It is
    // inert unless voip_remote_participant_loudness_measurement is on, and it
    // never touches playback.
    _syncLoudnessMeasurementFollow();
    if (!_onSessionStarted.isClosed) {
      _onSessionStarted.add(event);
    }

    if (event.state == VoipState.incoming) {
      startRingtone();

      var member = room?.getMemberOrFallback(event.remoteUserId!);

      NotificationManager.notify(
        CallNotificationContent(
          title: notificationTitleIncomingCall(event.roomName),
          content: notificationContentUserIsCalling(
            event.remoteUserName ?? event.remoteUserId!,
          ),
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
          isDirectMessage:
              event.client
                  .getComponent<DirectMessagesComponent>()
                  ?.isRoomDirectMessage(room!) ==
              true,
        ),
      );
    }

    if (event.state == VoipState.outgoing) {
      startOutgoingTone();
    }

    if (event.state == VoipState.connected) {
      joinCallSound();
      unawaited(soundboardPlaybackService.playJoinSoundForSession(event));
    }

    // The render stream that causes Windows to duck other applications is
    // opened by the ADM when call audio starts, so re-assert the preference
    // here rather than only when the toggle is flipped.
    applyLowerOtherAppVolumesPreference();

    _listenToSession(event);
    _applyDeafenToSession(event);
    _applyPushToTalkToSession(event);
    unawaited(_applySpeakerVolumeToSession(event));
    _syncPushToTalkHotkeyMonitor();
    _syncMobileCallBackground();
  }

  void onSessionEnded(VoipSession event) {
    _removeSession(event, playEndSound: true);
  }

  VoipSession? getCallInRoom(Client client, String roomId) {
    return currentSessions
        .where(
          (element) => element.client == client && element.roomId == roomId,
        )
        .firstOrNull;
  }

  void startRingtone() {
    if (disableSoundEffectsForTesting) {
      return;
    }

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
    if (disableSoundEffectsForTesting) {
      return;
    }

    if (player?.state.playing == true) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media(CustomSoundManager.ringtoneSoundUri(outgoing: true)));
    player?.setPlaylistMode(PlaylistMode.loop);
  }

  void joinCallSound() {
    if (disableSoundEffectsForTesting) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/joined_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  void playStreamStartSound() => _playStreamCue('stream_start.ogg');

  void playStreamEndSound() => _playStreamCue('stream_end.ogg');

  void _playStreamCue(String asset) {
    if (disableSoundEffectsForTesting || _disposed) return;
    streamCuePlayer ??= Player(configuration: PlayerConfiguration());
    streamCuePlayer!.setVolume(preferences.notificationsVolume.value);
    streamCuePlayer!.open(Media('asset:///assets/sound/$asset'));
    streamCuePlayer!.setPlaylistMode(PlaylistMode.none);
  }

  void mute() {
    for (final session in _currentSessionSnapshot()) {
      unawaited(_setMicrophoneMuteForManualAction(session, true, 'mute'));
    }

    playMuteSound();
  }

  /// Mute or unmute one session's microphone through the manual-intent path.
  ///
  /// [mute] and [unmute] act on every current session, which is right for the
  /// global hotkey and wrong for a call surface that shows one session. Call
  /// surfaces used to reach past this and call `session.setMicrophoneMute`
  /// directly, which skipped the intent map and the coalescing drain: rapid
  /// presses could interleave, and a mute applied that way was invisible to
  /// push-to-talk, which reads `_manualDesiredMuteBySession` to decide what to
  /// restore.
  ///
  /// The returned future completes when the drain THIS call started settles.
  /// It is an already-completed future whenever the request was absorbed
  /// instead of starting a drain: the session is not current, the intent
  /// already matched with nothing in flight, or a drain was already running
  /// and will pick up the intent just recorded. A surface must therefore not
  /// treat completion as "the mute is now applied": render the session's own
  /// mute state, which the drain updates, rather than awaiting this to hide a
  /// spinner - that hides it early on exactly the rapid presses the coalescing
  /// drain exists to handle.
  Future<void> setMicrophoneMuteForSession(
    VoipSession session,
    bool muted, {
    String trigger = 'call-surface',
  }) {
    return _setMicrophoneMuteForManualAction(session, muted, trigger);
  }

  bool fakeToggle = false;
  void toggleMute() {
    var session = currentSessions.firstOrNull;

    if (session != null) {
      if (_effectiveManualMuteState(session)) {
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
    if (disableSoundEffectsForTesting) {
      return;
    }

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
      unawaited(_setMicrophoneMuteForManualAction(session, false, 'unmute'));
    }

    playUnmuteSound();
  }

  void pushToTalkStart() {
    if (!_isPushToTalkUsable() || _pushToTalkPressed) {
      return;
    }

    _pushToTalkPressed = true;
    for (final session in _currentSessionSnapshot()) {
      _setMicrophoneMuteForPushToTalk(session, false, 'start');
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
      _setMicrophoneMuteForPushToTalk(session, true, 'end');
    }

    if (currentSessions.isNotEmpty) {
      playMuteSound();
    }
  }

  /// Pushes `voipLowerOtherAppVolumes` into the native Windows render stream.
  ///
  /// No-op off Windows, and on Windows builds whose packaged `libwebrtc.dll`
  /// predates the ducking patch.
  void applyLowerOtherAppVolumesPreference() {
    WindowsCallAudioDucking.setLowerOtherAppVolumes(
      preferences.voipLowerOtherAppVolumes.value,
    );
  }

  void applyPushToTalkPreference() {
    _syncPushToTalkHotkeyMonitor();

    if (!preferences.voipPushToTalkEnabled.value) {
      _loggedPushToTalkUnavailable = false;
      _releasePushToTalkMutes(
        'disabled',
        includeSessionsWithoutPushToTalkState: true,
      );
      return;
    }

    if (!_isPushToTalkUsable()) {
      _releasePushToTalkMutes('unavailable_hotkey');
      return;
    }

    for (final session in _currentSessionSnapshot()) {
      _applyPushToTalkToSession(session);
    }
  }

  void playUnmuteSound() {
    if (disableSoundEffectsForTesting) {
      return;
    }

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
    if (_disposed) {
      Log.w(
        'call_deafen event=set_deafened result=ignored reason=disposed '
        'requested=$value',
        category: LogCategory.webrtc,
        source: 'call-deafen',
      );
      return;
    }

    if (_isDeafened == value) {
      // Not noise. This is the second half of F-06: if something else cleared
      // the local playback mute while `_isDeafened` stayed true, the button
      // reads "deafened", pressing it lands here, and nothing happens. Without
      // this line "deafen stopped responding" is indistinguishable from "the
      // press never arrived".
      Log.i(
        'call_deafen event=set_deafened result=unchanged deafened=$value',
        category: LogCategory.webrtc,
        source: 'call-deafen',
      );
      return;
    }

    _isDeafened = value;
    final routes = _DeafenApplyRoutes();
    final sessions = _currentSessionSnapshot();
    for (final session in sessions) {
      _applyDeafenToSession(session, routes: routes);
      if (!_isDeafened) {
        unawaited(_applySpeakerVolumeToSession(session));
      }
    }
    Log.i(
      'call_deafen event=set_deafened result=changed deafened=$_isDeafened '
      'sessions=${sessions.length} $routes',
      category: LogCategory.webrtc,
      source: 'call-deafen',
    );
    _notifyDeafenChanged();
  }

  void _notifyDeafenChanged() {
    if (_disposed || _onDeafenChanged.isClosed) {
      return;
    }

    _onDeafenChanged.add(_isDeafened);
  }

  void _applyDeafenToSession(
    VoipSession session, {
    _DeafenApplyRoutes? routes,
  }) {
    for (final stream in _streamSnapshot(session)) {
      // `_applyDeafenToStream` is async and awaits `stream.setLocalMute`.
      // Dropping the future let a throwing write escape as an unhandled
      // asynchronous error rather than a recovered warning. Route it through
      // the same guard every other local-playback write uses (see
      // `_applySpeakerVolumeToSession`), and unawait deliberately: this method
      // is called from synchronous listeners, and one failing stream must not
      // stop the remaining streams in the loop from being applied.
      unawaited(
        CallLocalPlaybackOperationGuard.runAsync(
          operation: () => _applyDeafenToStream(stream, routes: routes),
          content: 'Failed to apply call deafen state to a stream',
          source: 'call-manager-deafen',
        ),
      );
    }
  }

  void _applyPushToTalkToSession(VoipSession session) {
    if (!_isPushToTalkUsable() || _pushToTalkPressed) {
      return;
    }

    _setMicrophoneMuteForPushToTalk(session, true, 'enabled');
  }

  void _releasePushToTalkMutes(
    String trigger, {
    bool includeSessionsWithoutPushToTalkState = false,
  }) {
    _pushToTalkPressed = false;
    for (final session in _currentSessionSnapshot()) {
      if (!includeSessionsWithoutPushToTalkState &&
          !_pushToTalkDesiredMuteBySession.containsKey(session) &&
          !_pushToTalkReleaseTrackedSessions.contains(session)) {
        continue;
      }
      _setMicrophoneMuteForPushToTalk(session, false, trigger);
    }
  }

  bool _isPushToTalkUsable() {
    if (!preferences.voipPushToTalkEnabled.value) {
      _loggedPushToTalkUnavailable = false;
      return false;
    }

    if (_pushToTalkBinding == null) {
      _logPushToTalkUnavailable('missing_hotkey');
      return false;
    }

    final binding = _pushToTalkBinding;
    final requiresMonitor =
        PlatformUtils.isWindows || binding?.isMouseButton == true;
    if (requiresMonitor &&
        !_pushToTalkHotkeyMonitor.canMonitorBinding(binding)) {
      _logPushToTalkUnavailable('unreadable_hotkey');
      return false;
    }

    _loggedPushToTalkUnavailable = false;
    return true;
  }

  void _logPushToTalkUnavailable(String reason) {
    if (_loggedPushToTalkUnavailable) {
      return;
    }
    _loggedPushToTalkUnavailable = true;
    final binding = _pushToTalkBinding;
    final hotkeyLabel = binding == null
        ? 'none'
        : HotKeyDisplay.describeBinding(binding);
    Log.w(
      'call_push_to_talk event=unavailable result=ignored '
      'reason=$reason hotkey="$hotkeyLabel"',
      category: LogCategory.webrtc,
      source: 'push-to-talk',
    );
  }

  ShortcutBinding? get _pushToTalkBinding {
    const shortcutKey = SystemWideShortcuts.pushToTalkShortcutKey;
    final shortcut = SystemWideShortcuts.shortcuts[shortcutKey];
    final shortcutBinding = shortcut?.binding;
    if (shortcutBinding != null) {
      return shortcutBinding;
    }

    try {
      return preferences.getSystemShortcutBinding(shortcutKey) ??
          shortcut?.defaultBinding;
    } on TypeError {
      return shortcut?.defaultBinding;
    }
  }

  void _syncPushToTalkHotkeyMonitor() {
    final binding = _pushToTalkBinding;
    _pushToTalkHotkeyMonitor.configure(binding);

    // macOS/Linux Push to Talk uses hotkey_manager callbacks directly.
    // This monitor is the Windows polling fallback for hold-to-talk key-up
    // semantics, where global key-up handling is otherwise unreliable.
    final requiresMonitor =
        PlatformUtils.isWindows || binding?.isMouseButton == true;
    final readableHotkey =
        !requiresMonitor || _pushToTalkHotkeyMonitor.canMonitorBinding(binding);
    final shouldMonitor =
        requiresMonitor &&
        preferences.voipPushToTalkEnabled.value &&
        binding != null &&
        readableHotkey &&
        currentSessions.isNotEmpty;

    if (requiresMonitor &&
        preferences.voipPushToTalkEnabled.value &&
        binding != null &&
        !readableHotkey) {
      _logPushToTalkUnavailable('unreadable_hotkey');
    }

    if (shouldMonitor) {
      _pushToTalkHotkeyMonitor.start();
    } else {
      _pushToTalkHotkeyMonitor.stop();
    }
  }

  void _setMicrophoneMuteForPushToTalk(
    VoipSession session,
    bool muted,
    String trigger,
  ) {
    if (_disposed || !_isCurrentSession(session)) {
      return;
    }

    if (muted) {
      _pushToTalkReleaseTrackedSessions.add(session);
    }

    final previousDesiredMute = _pushToTalkDesiredMuteBySession[session];
    _pushToTalkDesiredMuteBySession[session] = muted;

    if (previousDesiredMute == muted &&
        !_pushToTalkMuteApplyInFlight.contains(session)) {
      return;
    }

    if (_pushToTalkMuteApplyInFlight.contains(session)) {
      return;
    }

    unawaited(_drainPushToTalkMuteForSession(session, trigger));
  }

  Future<void> _setMicrophoneMuteForManualAction(
    VoipSession session,
    bool muted,
    String trigger,
  ) {
    if (_disposed || !_isCurrentSession(session)) {
      return Future<void>.value();
    }

    final previousDesiredMute = _manualDesiredMuteBySession[session];
    _manualDesiredMuteBySession[session] = muted;

    if (previousDesiredMute == muted &&
        !_manualMuteApplyInFlight.contains(session)) {
      return Future<void>.value();
    }

    if (_manualMuteApplyInFlight.contains(session)) {
      // A drain is already running and will pick up the intent just recorded.
      return Future<void>.value();
    }

    return _drainManualMuteForSession(session, trigger);
  }

  Future<void> _drainManualMuteForSession(
    VoipSession session,
    String trigger,
  ) async {
    if (!_manualMuteApplyInFlight.add(session)) {
      return;
    }

    var nextTrigger = trigger;
    try {
      while (!_disposed && _isCurrentSession(session)) {
        final desiredMute = _manualDesiredMuteBySession[session];
        if (desiredMute == null) {
          return;
        }

        final applied = await _setMicrophoneMuteForManualActionSafely(
          session,
          desiredMute,
          nextTrigger,
        );
        final currentDesiredMute = _manualDesiredMuteBySession[session];
        if (!applied) {
          if (currentDesiredMute == desiredMute) {
            _manualDesiredMuteBySession.remove(session);
            return;
          }
          nextTrigger = 'coalesced';
          continue;
        }

        if (currentDesiredMute == desiredMute) {
          _manualDesiredMuteBySession.remove(session);
          return;
        }

        nextTrigger = 'coalesced';
      }
    } finally {
      _manualMuteApplyInFlight.remove(session);
    }
  }

  Future<bool> _setMicrophoneMuteForManualActionSafely(
    VoipSession session,
    bool muted,
    String trigger,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      Log.i(
        'call_manual_mute event=microphone_mute_apply '
        'result=started muted=$muted trigger=$trigger '
        'session_state=${session.state.name}',
        category: LogCategory.webrtc,
        source: 'call-mute',
      );
      await session.setMicrophoneMute(muted);
      stopwatch.stop();
      Log.i(
        'call_manual_mute event=microphone_mute_apply '
        'result=completed muted=$muted trigger=$trigger '
        'elapsed_ms=${stopwatch.elapsedMilliseconds}',
        category: LogCategory.webrtc,
        source: 'call-mute',
      );
      return true;
    } catch (error) {
      stopwatch.stop();
      Log.w(
        'call_manual_mute event=microphone_mute_apply '
        'result=recovered_error muted=$muted trigger=$trigger '
        'elapsed_ms=${stopwatch.elapsedMilliseconds} '
        'error_type=${error.runtimeType}',
        category: LogCategory.webrtc,
        source: 'call-mute',
      );
      return false;
    }
  }

  Future<void> _drainPushToTalkMuteForSession(
    VoipSession session,
    String trigger,
  ) async {
    if (!_pushToTalkMuteApplyInFlight.add(session)) {
      return;
    }

    var nextTrigger = trigger;
    try {
      while (!_disposed && _isCurrentSession(session)) {
        final desiredMute = _pushToTalkDesiredMuteBySession[session];
        if (desiredMute == null) {
          return;
        }

        final applied = await _setMicrophoneMuteForPushToTalkSafely(
          session,
          desiredMute,
          nextTrigger,
        );
        final currentDesiredMute = _pushToTalkDesiredMuteBySession[session];
        if (!applied) {
          if (currentDesiredMute == desiredMute) {
            _pushToTalkDesiredMuteBySession.remove(session);
            return;
          }
          nextTrigger = 'coalesced';
          continue;
        }

        if (currentDesiredMute == desiredMute) {
          if (!desiredMute) {
            _pushToTalkDesiredMuteBySession.remove(session);
            _pushToTalkReleaseTrackedSessions.remove(session);
          }
          return;
        }

        nextTrigger = 'coalesced';
      }
    } finally {
      _pushToTalkMuteApplyInFlight.remove(session);
    }
  }

  Future<bool> _setMicrophoneMuteForPushToTalkSafely(
    VoipSession session,
    bool muted,
    String trigger,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      Log.i(
        'call_push_to_talk event=microphone_mute_apply '
        'result=started muted=$muted trigger=$trigger '
        'session_state=${session.state.name}',
        category: LogCategory.webrtc,
        source: 'push-to-talk',
      );
      await session.setMicrophoneMute(muted, stopOnMute: false);
      stopwatch.stop();
      Log.i(
        'call_push_to_talk event=microphone_mute_apply '
        'result=completed muted=$muted trigger=$trigger '
        'elapsed_ms=${stopwatch.elapsedMilliseconds}',
        category: LogCategory.webrtc,
        source: 'push-to-talk',
      );
      return true;
    } catch (error) {
      stopwatch.stop();
      Log.w(
        'call_push_to_talk event=microphone_mute_apply '
        'result=recovered_error muted=$muted trigger=$trigger '
        'elapsed_ms=${stopwatch.elapsedMilliseconds} '
        'error_type=${error.runtimeType}',
        category: LogCategory.webrtc,
        source: 'push-to-talk',
      );
      return false;
    }
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
      await CallLocalPlaybackOperationGuard.runAsync(
        operation: () => _applySpeakerVolumeToStream(stream),
        content: 'Failed to apply call speaker volume preference',
        source: 'call-manager-speaker-volume',
      );
    }
  }

  List<VoipSession> _currentSessionSnapshot() {
    return List<VoipSession>.of(currentSessions);
  }

  bool _isCurrentSession(VoipSession session) {
    return currentSessions.any((current) => identical(current, session));
  }

  /// Whether [setMicrophoneMuteForSession] would act on a request for
  /// [session], rather than silently absorbing it.
  ///
  /// The manager drops a manual mute request when it has been disposed or when
  /// the session is not current. A surface that plays a click before calling
  /// needs to know that up front: the click IS the confirmation on a mute
  /// control, so playing it for a dropped request tells the user something
  /// happened when nothing did. Kept here rather than reconstructed by each
  /// surface, because `_disposed` is private and a caller checking only session
  /// membership gets the disposed case wrong.
  bool acceptsMuteRequestFor(VoipSession session) =>
      !_disposed && _isCurrentSession(session);

  /// What the user has most recently asked for, which is not the same thing as
  /// what has been applied.
  ///
  /// A mute surface must compute its toggle target from this, never from
  /// `session.isMicrophoneMuted`. While the coalescing drain is applying a
  /// request, the session still reports the OLD applied state, so a second
  /// press computed from it asks for the value already queued - and
  /// [setMicrophoneMuteForSession] correctly absorbs that as a duplicate. The
  /// press then does nothing, which is exactly the "mute button ignores me when
  /// I press it twice quickly" shape the drain was added to fix.
  ///
  /// Falls back to the applied state when no request is in flight, so a surface
  /// reading this outside a drain sees the same answer it always did.
  bool effectiveManualMuteState(VoipSession session) =>
      _effectiveManualMuteState(session);

  bool _effectiveManualMuteState(VoipSession session) {
    return _manualDesiredMuteBySession[session] ?? session.isMicrophoneMuted;
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

    if (stream is MatrixLivekitVoipStream && stream.isScreenShareAudio) {
      return;
    }

    if (stream is LocalPlaybackVolumeStream) {
      final volumeStream = stream as LocalPlaybackVolumeStream;
      // Gate on the publication kind, not on `type`, for the same reason
      // _applyDeafenToStream does. Historically `type` inspected
      // `publication.track` and so reported VoipStreamType.video for an audio
      // publication whose track had not attached yet, and the speaker volume
      // preference was skipped for every participant mid-subscribe.
      // `MatrixLivekitVoipStream.type` now reads `publication.kind` and
      // answers `audio` in that state, so the two agree - but the gate stays
      // on `hasLocalPlaybackAudio` because that is the property this branch
      // actually needs (can local playback gain be applied), not a tile-type
      // classification that could be widened again.
      if (!volumeStream.hasLocalPlaybackAudio) {
        return;
      }
      await volumeStream.setDefaultLocalVolume(volume);
    }
  }

  Future<void> _applyDeafenToStream(
    VoipStream stream, {
    _DeafenApplyRoutes? routes,
  }) async {
    if (stream.direction != VoipStreamDirection.incoming) {
      routes?.outgoing++;
      return;
    }

    if (stream is MatrixLivekitVoipStream && stream.hasLocalPlaybackAudio) {
      // Gate on the publication kind, not on `type`. `type` used to inspect
      // `publication.track` and reported VoipStreamType.video for an audio
      // publication whose track had not attached yet, so deafen silently
      // skipped any participant who was mid-subscribe — including every
      // participant during the reconciler's unsubscribe/subscribe window.
      // `MatrixLivekitVoipStream.type` now reads `publication.kind` itself and
      // no longer diverges, so this is not a workaround any more; it stays
      // because `hasLocalPlaybackAudio` is the property this branch needs and
      // is stable regardless of how tile classification evolves.
      if (!_isDeafened && stream.isScreenShareAudio) {
        routes?.screenshareUndeafenDeferred++;
        // Un-deafen does not own screenshare audio. Its mute belongs to the
        // tile-visibility policy in CallView, which mutes it whenever the
        // matching video tile is hidden; clearing that here made hidden
        // screenshares audible on every session-state event. Deafen still
        // silences it (the branch below runs when _isDeafened is true);
        // CallView restores the correct visibility state on the next build.
        // Muted is the safe default here — it is what the stream constructor
        // asserts for remote screenshare audio in the first place.
        return;
      }
      routes?.livekitPlayback++;
      await stream.setLocalMute(_isDeafened);
      return;
    }

    if (stream is MatrixVoipStream) {
      routes?.directTrack++;
      // Route through the stream's local playback state rather than writing
      // `track.enabled` directly. The direct write bypassed
      // MatrixVoipStreamLocalPlaybackState entirely, so `locallyMuted`
      // reported false while the user was deafened, and the setVolume catch
      // path (`track.enabled = effectiveVolume > 0.0`) re-enabled a deafened
      // track on the next unrelated volume write.
      await stream.setLocalMute(_isDeafened);
      return;
    }

    routes?.noLocalPlayback++;
  }

  void endCallSound() {
    if (disableSoundEffectsForTesting) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/left_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  void stopRingtone() {
    player?.stop();
    unawaited(player?.dispose() ?? Future<void>.value());
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

  void _listenToSession(VoipSession event) {
    _cancelSessionSubscriptions(event.sessionId);
    _sessionSubscriptions[event.sessionId] = [
      event.onConnectionStateChanged.listen((_) => onCallStateChanged(event)),
      event.onStateChanged.listen((_) => _onSessionStateChanged(event)),
    ];
  }

  /// Points the loudness monitor at the call actually worth measuring.
  ///
  /// Recomputed from `currentSessions` on every add, state change and removal,
  /// rather than following whichever session most recently fired an event.
  /// `onClientSessionStarted` runs for `incoming` and `outgoing` sessions too,
  /// and it used to hand each one straight to `followSession` - which detaches
  /// the previously followed session once the identity differs, while
  /// reconciliation only ever attaches a `connected` one. A call ringing during
  /// a measured call therefore killed measurement of the live call, and
  /// declining the ringing call never brought it back.
  ///
  /// Only `connected`, then `connecting`, is a measurement target. When neither
  /// exists but some session is still live, the current follow is left alone:
  /// a ringing session is not a reason to tear down anything, and the monitor's
  /// own reconcile already unfollows a session that starts finishing.
  void _syncLoudnessMeasurementFollow() {
    if (_disposed) {
      return;
    }

    VoipSession? connected;
    VoipSession? connecting;
    for (final session in currentSessions) {
      if (session.state.isFinishing) {
        continue;
      }
      if (connected == null && session.state == VoipState.connected) {
        connected = session;
      } else if (connecting == null && session.state == VoipState.connecting) {
        connecting = session;
      }
    }

    // Unfollow whenever no measurable session exists - not only when NO
    // session exists. Returning while an `incoming` session remained left the
    // monitor attached to whatever it was following before, and the followed
    // session can be REMOVED without any state transition
    // (_removeSessionsForClientId drops a still-`connected` session on client
    // logout), so nothing later would have detached it: its timer and state
    // subscription kept measuring a call that no longer existed. An accepted
    // incoming call re-follows through _onSessionStateChanged the moment it
    // connects.
    final target = connected ?? connecting;
    if (target == null) {
      ParticipantLoudnessMonitor.instance.unfollow();
      return;
    }
    ParticipantLoudnessMonitor.instance.followSession(target);
  }

  void _onSessionStateChanged(VoipSession event) {
    if (_disposed) {
      return;
    }

    if (event.state == VoipState.ended) {
      _removeSession(event, playEndSound: true);
      return;
    }

    // An accepted incoming call reaches `connected` here, not at start, so this
    // is where measurement actually begins for it.
    _syncLoudnessMeasurementFollow();
    _applyDeafenToSession(event);
    _applyPushToTalkToSession(event);
    unawaited(_applySpeakerVolumeToSession(event));
    _syncPushToTalkHotkeyMonitor();
    _syncMobileCallBackground();
  }

  void _removeSessionsForClientId(
    String clientId, {
    required bool playEndSound,
  }) {
    final sessions = currentSessions
        .where((session) => session.client.identifier == clientId)
        .toList(growable: false);
    for (final session in sessions) {
      _removeSession(session, playEndSound: playEndSound);
    }
  }

  void _removeSession(VoipSession event, {required bool playEndSound}) {
    final wasTracked = currentSessions.any(
      (element) => element.sessionId == event.sessionId,
    );
    _pushToTalkDesiredMuteBySession.remove(event);
    _pushToTalkReleaseTrackedSessions.remove(event);
    _pushToTalkMuteApplyInFlight.remove(event);
    _manualDesiredMuteBySession.remove(event);
    _manualMuteApplyInFlight.remove(event);
    currentSessions.removeWhere(
      (element) => element.sessionId == event.sessionId,
    );
    _cancelSessionSubscriptions(event.sessionId);

    if (!wasTracked) {
      return;
    }

    _syncPushToTalkHotkeyMonitor();
    _syncMobileCallBackground();
    // Declining a ringing call that arrived during a live call lands here. This
    // is what restores measurement to the call still in progress.
    _syncLoudnessMeasurementFollow();

    if (currentSessions.where((e) => e.state == VoipState.incoming).isEmpty) {
      stopRingtone();
    }

    if (playEndSound) {
      endCallSound();
    }
  }

  void _cancelClientSubscriptions(String clientId) {
    _cancelSubscriptions(_clientVoipSubscriptions.remove(clientId));
  }

  void _cancelSessionSubscriptions(String sessionId) {
    _cancelSubscriptions(_sessionSubscriptions.remove(sessionId));
  }

  void _cancelSubscriptions(List<StreamSubscription>? subscriptions) {
    if (subscriptions == null) {
      return;
    }

    for (final subscription in subscriptions) {
      unawaited(_cancelSubscription(subscription));
    }
  }

  Future<void> _cancelSubscription(StreamSubscription subscription) async {
    try {
      await subscription.cancel();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered call manager subscription cancel failure',
        category: LogCategory.webrtc,
        source: 'call-manager-subscription',
      );
    }
  }

  void _syncMobileCallBackground() {
    if (_disposed) {
      return;
    }

    unawaited(
      mobileCallBackgroundController.syncSessions(_currentSessionSnapshot()),
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    // The monitor is followed from `onClientSessionStarted` and only detaches
    // itself when the session reaches a finishing state. App shutdown does not
    // go through that path, so without this the reconcile timer, the session
    // listener and every per-track estimator outlive the manager that started
    // them.
    ParticipantLoudnessMonitor.instance.unfollow();

    final subscriptions = <StreamSubscription>[
      ..._managerSubscriptions,
      for (final clientSubscriptions in _clientVoipSubscriptions.values)
        ...clientSubscriptions,
      for (final sessionSubscriptions in _sessionSubscriptions.values)
        ...sessionSubscriptions,
    ];
    _managerSubscriptions.clear();
    _clientVoipSubscriptions.clear();
    _sessionSubscriptions.clear();

    for (final subscription in subscriptions) {
      await _cancelSubscription(subscription);
    }

    await mobileCallBackgroundController.stopForShutdown();
    _pushToTalkHotkeyMonitor.dispose();
    currentSessions.clear();
    _pushToTalkDesiredMuteBySession.clear();
    _pushToTalkReleaseTrackedSessions.clear();
    _pushToTalkMuteApplyInFlight.clear();
    _manualDesiredMuteBySession.clear();
    _manualMuteApplyInFlight.clear();
    currentSessions.close();
    // Broadcast close() futures only complete once every past subscriber has
    // cancelled after close, so awaiting them can hang dispose forever.
    unawaited(_onSessionStarted.close());
    unawaited(_onDeafenChanged.close());

    final players = [
      player,
      muteSoundPlayer,
      unmuteSoundPlayer,
      streamCuePlayer,
    ];
    player = null;
    muteSoundPlayer = null;
    unmuteSoundPlayer = null;
    streamCuePlayer = null;

    for (final soundPlayer in players) {
      try {
        await soundPlayer?.stop();
        await soundPlayer?.dispose();
      } catch (_) {
        // Best-effort app shutdown cleanup.
      }
    }
  }
}

/// Counts which route each stream took while a deafen transition was applied.
///
/// Aggregated rather than logged per stream on purpose: one line per button
/// press carries no user or stream identifiers, stays readable in a capture
/// dominated by volume-apply lines, and still answers the question deafen has
/// never been able to answer - did the press reach any streams at all, and by
/// which path.
class _DeafenApplyRoutes {
  int livekitPlayback = 0;
  int directTrack = 0;
  int screenshareUndeafenDeferred = 0;
  int outgoing = 0;
  int noLocalPlayback = 0;

  @override
  String toString() =>
      'livekit_playback=$livekitPlayback direct_track=$directTrack '
      'screenshare_undeafen_deferred=$screenshareUndeafenDeferred '
      'skipped_outgoing=$outgoing skipped_no_local_playback=$noLocalPlayback';
}
