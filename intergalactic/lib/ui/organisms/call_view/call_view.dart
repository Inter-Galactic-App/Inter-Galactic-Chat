import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_diagnostic_directory.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/native_webrtc_diagnostics.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/game_capture_test_target_runner.dart';
import 'package:intergalactic/client/components/voip/game_capture_probe_runner.dart';
import 'package:intergalactic/client/components/voip/stream_test_report_writer.dart';
import 'package:intergalactic/client/components/voip/stream_test_automation_command.dart';
import 'package:intergalactic/client/components/voip/stream_test_runner.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_receive_quality_policy.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/components/voip/webrtc_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/windows_screen_capture_backend.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/call_view/call_diagnostics_path_labels.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_identity.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_fullscreen_stream_view.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_stream_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/report_bug_page.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:intergalactic/utils/list_extension.dart';
import 'package:intergalactic/utils/animation/ring_shaker.dart';
import 'package:intergalactic/utils/animation/ripple.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class _CallControlsVisibility extends StatelessWidget {
  const _CallControlsVisibility({
    required this.visible,
    required this.transparentBackground,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final bool transparentBackground;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (transparentBackground) {
      return visible ? child : const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        child: child,
      ),
    );
  }
}

class _TransparentCallControlButton extends StatelessWidget {
  const _TransparentCallControlButton({
    required this.radius,
    required this.icon,
    this.onPressed,
    this.color,
    this.iconColor,
  });

  final double radius;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = iconColor ??
        (enabled ? Colors.white.withAlpha(232) : Colors.white.withAlpha(112));
    final background = enabled
        ? color ?? Colors.black.withAlpha(160)
        : Colors.black.withAlpha(96);

    final button = Semantics(
      button: true,
      enabled: enabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background,
          border: Border.all(
            color: Colors.white.withAlpha(enabled ? 36 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(72),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: icon == null
              ? null
              : Icon(
                  icon,
                  color: foreground,
                  size: radius,
                ),
        ),
      ),
    );

    if (!enabled) {
      return button;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: button,
      ),
    );
  }
}

class _CallTileData {
  const _CallTileData({
    required this.primaryStream,
    required this.tileId,
    this.audioStream,
    this.volumeStream,
  });

  final VoipStream primaryStream;
  final String tileId;
  final VoipStream? audioStream;
  final VoipStream? volumeStream;

  String get userId => primaryStream.streamUserId;
  bool get hasVisual =>
      primaryStream.type == VoipStreamType.video ||
      primaryStream.type == VoipStreamType.screenshare;
  bool get isScreenshare => primaryStream.type == VoipStreamType.screenshare;
}

class _CallViewLocalState {
  final Set<String> hiddenUserIds = {};
  final Set<String> hiddenScreenshareStreamIds = {};
  final Set<String> shownScreenshareStreamIds = {};
  final Set<String> autoHiddenLocalScreenshareStreamIds = {};
  final Set<String> visibilityMutedAudioStreamIds = {};
  final Map<String, double> participantAudioVolumeOverrides = {};
}

class _StreamTestDialogConfig {
  const _StreamTestDialogConfig({
    required this.presets,
    required this.duration,
    required this.warmup,
    this.windowsCaptureBackendMode,
    this.windowsCaptureBackendModes,
    this.windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    this.windowsWindowGdiCaptureModes,
    this.nativeFramePacingEnabled = false,
    this.dummyNv12LiveSender = false,
    this.captureTestTargetEnabled = false,
    this.captureTestTargetWidth = 1920,
    this.captureTestTargetHeight = 1080,
    this.captureTestTargetMode = 'windowed',
    this.captureTestTargetScene = 'gameplay',
    this.captureTestTargetFps = '60',
    this.automationSourceProcessId,
    this.automationSourceTitle,
    this.gameCaptureProbeEnabled = false,
    this.gameCaptureProofFrames = 0,
  });

  final List<ScreenShareProfileConfig> presets;
  final Duration duration;
  final Duration warmup;
  final WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
  final List<WindowsScreenCaptureBackendMode?>? windowsCaptureBackendModes;
  final WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode;
  final List<WindowsWindowGdiCaptureMode?>? windowsWindowGdiCaptureModes;
  final bool nativeFramePacingEnabled;
  final bool dummyNv12LiveSender;
  final bool captureTestTargetEnabled;
  final int captureTestTargetWidth;
  final int captureTestTargetHeight;
  final String captureTestTargetMode;
  final String captureTestTargetScene;
  final String captureTestTargetFps;
  final int? automationSourceProcessId;
  final String? automationSourceTitle;
  final bool gameCaptureProbeEnabled;
  final int gameCaptureProofFrames;

  GameCaptureTestTargetConfig get captureTestTargetConfig {
    return GameCaptureTestTargetConfig(
      enabled: captureTestTargetEnabled,
      width: captureTestTargetWidth,
      height: captureTestTargetHeight,
      windowMode: captureTestTargetMode,
      scene: captureTestTargetScene,
      fps: captureTestTargetFps,
      title: 'Inter Galactic Capture Target',
    );
  }
}

class _RnnoiseDiagnosticBatchScenario {
  const _RnnoiseDiagnosticBatchScenario({
    required this.scenario,
    required this.hookModePreference,
    required this.noiseSuppressionEnabled,
  });

  final String scenario;
  final String hookModePreference;
  final bool noiseSuppressionEnabled;

  String get label => NoiseSuppressionTapOrderScenario.labelFor(scenario);
}

class _RnnoiseDiagnosticBatchResult {
  const _RnnoiseDiagnosticBatchResult({
    required this.completed,
    required this.writtenFiles,
    required this.canceled,
    required this.failures,
  });

  final int completed;
  final int writtenFiles;
  final bool canceled;
  final List<String> failures;

  String get summary {
    final base = canceled
        ? 'Canceled after $completed capture(s); wrote $writtenFiles WAV files.'
        : 'Completed $completed capture(s); wrote $writtenFiles WAV files.';
    if (failures.isEmpty) {
      return base;
    }
    return '$base ${failures.length} scenario(s) reported no files or errors.';
  }
}

const List<_RnnoiseDiagnosticBatchScenario> _rnnoiseTapOrderBatchScenarios =
    <_RnnoiseDiagnosticBatchScenario>[
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseOffDefault,
    // The off/default comparison still needs the native hook installed so the
    // tap-order WAVs prove what WebRTC hands to the hook before RNNoise runs.
    hookModePreference: 'identity',
    noiseSuppressionEnabled: false,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.identitySameConstraints,
    hookModePreference: 'identity',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseSameConstraints,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseNoVolume,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseNo48k,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseAgcOn,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseAgcOff,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseNsOff,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseAecOff,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.identityMinimalFrontend,
    hookModePreference: 'identity',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseMinimalFrontend,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
];

class _CallViewStreamTestTarget implements StreamTestTarget {
  const _CallViewStreamTestTarget({
    required this.session,
    required this.source,
  });

  final MatrixLivekitVoipSession session;
  final ScreenCaptureSource source;

  @override
  String get label => session.roomName;

  @override
  String get roomId => session.roomId;

  @override
  bool get isSharingScreen => session.isSharingScreen;

  @override
  Future<void> startPreset(
    ScreenShareProfileConfig profile, {
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    bool nativeFramePacingEnabled = false,
    bool dummyNv12LiveSender = false,
  }) {
    return session.setScreenShareForStreamTest(
      source,
      profile,
      windowsCaptureBackendMode: windowsCaptureBackendMode,
      windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
      nativeFramePacingEnabled: nativeFramePacingEnabled,
      dummyNv12LiveSender: dummyNv12LiveSender,
    );
  }

  @override
  Future<void> stopShare() => session.stopScreenshare();

  @override
  Future<VoipCallDiagnosticsSnapshot> collectDiagnostics() {
    return session.collectStreamTestDiagnostics();
  }
}

class CallView extends StatefulWidget {
  const CallView(
    this.currentSession, {
    this.setMicrophoneMute,
    this.pickScreenshareSource,
    this.stopScreenshare,
    this.pickCamera,
    this.disableCamera,
    this.hangUp,
    this.declineCall,
    this.acceptCall,
    this.showSessionPopoutButton = true,
    this.transparentBackground = false,
    this.forceControlsVisible = false,
    super.key,
  });
  final VoipSession currentSession;

  static const Duration volumeAnimationDuration = Duration(milliseconds: 500);

  final Future<void> Function(bool)? setMicrophoneMute;
  final Future<void> Function()? pickScreenshareSource;
  final Future<void> Function()? stopScreenshare;
  final Future<void> Function()? pickCamera;
  final Future<void> Function()? disableCamera;
  final Future<void> Function()? hangUp;
  final Future<void> Function()? declineCall;
  final Future<void> Function()? acceptCall;
  final bool showSessionPopoutButton;
  final bool transparentBackground;
  final bool forceControlsVisible;

  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  static const List<WindowsScreenCaptureBackendMode?>
      _streamTestWindowsCaptureBackendCompareModes = [
    null,
    ...streamTestWindowsCaptureBackendModes,
  ];

  static const int _maxPersistedLocalStateEntries = 12;
  static final Map<String, _CallViewLocalState> _localStateBySession = {};

  StreamSubscription? sub;
  StreamSubscription? _diagnosticsSub;
  StreamSubscription? _participantsSub;
  bool isMouseHovering = false;
  bool showEqualTileLayout = true;
  bool _diagnosticsOverlayVisible = true;
  static const Duration _localScreensharePreviewDuration = Duration(
    seconds: 30,
  );
  static const Duration _streamTestAutoSelectTimeout = Duration(seconds: 8);

  late final String _persistedLocalStateKey;
  late final _CallViewLocalState _localState;
  final Map<String, Timer> _localScreenshareAutoHideTimers = {};
  final Set<String> _restoredScreenshareAudioVolumeKeys = {};
  bool _streamTestRunning = false;
  String? _streamTestProgressLabel;
  StreamTestRunResult? _lastStreamTestResult;
  StreamTestReportWriteResult? _lastStreamTestReportWriteResult;
  Timer? _streamTestAutomationPollTimer;
  bool _streamTestAutomationPollInFlight = false;

  String? focusedTileId;
  late Room room;

  /// User IDs whose camera video is hidden locally.
  Set<String> get _hiddenUserIds => _localState.hiddenUserIds;

  /// Stable screenshare tile IDs explicitly hidden by the local user from the
  /// context menu.
  Set<String> get _hiddenScreenshareStreamIds =>
      _localState.hiddenScreenshareStreamIds;

  /// Stable screenshare tile IDs that the local user has explicitly chosen to
  /// view.  All remote screenshares default to hidden (blank panel) until the
  /// user taps the eye-toggle on that tile.
  Set<String> get _shownScreenshareStreamIds =>
      _localState.shownScreenshareStreamIds;

  Set<String> get _autoHiddenLocalScreenshareStreamIds =>
      _localState.autoHiddenLocalScreenshareStreamIds;

  Set<String> get _visibilityMutedAudioStreamIds =>
      _localState.visibilityMutedAudioStreamIds;

  Map<String, double> get _participantAudioVolumeOverrides =>
      _localState.participantAudioVolumeOverrides;

  @override
  void initState() {
    super.initState();
    _persistedLocalStateKey = _callViewLocalStateKeyFor(
      widget.currentSession,
    );
    if (!_localStateBySession.containsKey(_persistedLocalStateKey) &&
        _localStateBySession.length >= _maxPersistedLocalStateEntries) {
      _localStateBySession.remove(_localStateBySession.keys.first);
    }
    _localState = _localStateBySession.putIfAbsent(
      _persistedLocalStateKey,
      _CallViewLocalState.new,
    );
    _diagnosticsOverlayVisible =
        preferences.callStreamStatsOverlayVisible.value;
    sub = widget.currentSession.onStateChanged.listen((event) {
      if (!mounted) {
        return;
      }
      if (widget.currentSession.state == VoipState.ended) {
        _discardPersistedLocalState();
      }
      _syncLocalScreenshareAutoHideTimers();
      setState(() {});
    });

    room = widget.currentSession.client.getRoom(widget.currentSession.roomId)!;
    _diagnosticsSub = widget.currentSession.onDiagnosticsChanged.listen((
      event,
    ) {
      if (preferences.developerMode.value &&
          preferences.showCallStreamStats.value &&
          mounted) {
        setState(() {});
      }
    });

    // Listen for participant-list changes (e.g. when an admin removes someone
    // from the call) so we can rebuild tiles immediately.
    _participantsSub = _voipRoomComponent?.onParticipantsChanged.listen((_) {
      if (!mounted) {
        return;
      }
      _syncLocalScreenshareAutoHideTimers();
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncLocalScreenshareAutoHideTimers();
      _pollStreamTestAutomationCommand();
    });
    if ((BuildConfig.DEBUG || kDebugMode) && PlatformUtils.isWindows) {
      _streamTestAutomationPollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollStreamTestAutomationCommand(),
      );
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    _diagnosticsSub?.cancel();
    _participantsSub?.cancel();
    _streamTestAutomationPollTimer?.cancel();
    for (final timer in _localScreenshareAutoHideTimers.values) {
      timer.cancel();
    }
    _localScreenshareAutoHideTimers.clear();
    if (widget.currentSession.state == VoipState.ended) {
      _discardPersistedLocalState();
    }
    super.dispose();
  }

  static String _callViewLocalStateKeyFor(VoipSession session) {
    final stableSessionId = session.sessionId.trim().isEmpty
        ? 'no-session-id'
        : session.sessionId.trim();
    return '${session.client.identifier}:${session.roomId}:'
        '$stableSessionId:${identityHashCode(session)}';
  }

  void _discardPersistedLocalState() {
    _localStateBySession.remove(_persistedLocalStateKey);
  }

  // ── Volume / remove helpers ───────────────────────────────────────────────

  /// Returns the `MatrixVoipRoomComponent` for the current room, or null if
  /// the room/session doesn't use the LiveKit/Matrix VoIP stack.
  MatrixVoipRoomComponent? get _voipRoomComponent {
    final r = widget.currentSession.client.getRoom(
      widget.currentSession.roomId,
    );
    final comp = r?.getComponent<VoipRoomComponent>();
    if (comp is MatrixVoipRoomComponent) return comp;
    return null;
  }

  bool get _canRemoveParticipants =>
      _voipRoomComponent?.canRemoveParticipants ?? false;

  /// Local visibility state must outlive LiveKit publication SID refreshes.
  /// Windows fallback/profile changes can republish a screenshare while the
  /// user still considers it the same visible tile.
  String _tileIdForStream(VoipStream stream) {
    return callStreamPopoutIdForStream(stream);
  }

  void _markLocalScreenshareAutoHideHandled(String tileId) {
    _localScreenshareAutoHideTimers.remove(tileId)?.cancel();
    _autoHiddenLocalScreenshareStreamIds.add(tileId);
  }

  double get _defaultParticipantAudioVolume =>
      Preferences.voipSpeakerVolumeToLocalPlayback(
        preferences.voipSpeakerVolume.value,
      );

  bool _supportsLocalPlaybackVolume(VoipStream? stream) {
    return stream is LocalPlaybackVolumeStream &&
        (stream as LocalPlaybackVolumeStream).hasLocalPlaybackAudio;
  }

  VoipStream? _volumeTargetForTile(_CallTileData tile) {
    if (_supportsLocalPlaybackVolume(tile.volumeStream)) {
      return tile.volumeStream;
    }

    final primaryStream = tile.primaryStream;
    if (_supportsLocalPlaybackVolume(primaryStream)) {
      return primaryStream;
    }

    return null;
  }

  VoipStream? _preparedVolumeTargetForTile(_CallTileData tile) {
    final target = _volumeTargetForTile(tile);
    if (target != null) {
      _restoreParticipantAudioVolume(target);
    }
    return target;
  }

  String _participantAudioPreferenceKey(VoipStream stream) {
    return 'participant:${stream.streamUserId}:microphone';
  }

  void _rememberParticipantAudioVolume(
    VoipStream stream,
    double volume,
  ) {
    if (stream is MatrixLivekitVoipStream && !stream.isMicrophoneAudio) {
      return;
    }
    if (stream.type == VoipStreamType.screenshare ||
        stream is! LocalPlaybackVolumeStream) {
      return;
    }
    final volumeTarget = stream as LocalPlaybackVolumeStream;
    if (!volumeTarget.hasLocalPlaybackAudio) {
      return;
    }

    final key = _participantAudioPreferenceKey(stream);
    if ((volume - _defaultParticipantAudioVolume).abs() < 0.001) {
      _participantAudioVolumeOverrides.remove(key);
      volumeTarget.clearLocalPlaybackVolumeOverride();
    } else {
      _participantAudioVolumeOverrides[key] = volume;
    }
  }

  void _restoreParticipantAudioVolume(VoipStream stream) {
    if (stream is MatrixLivekitVoipStream && !stream.isMicrophoneAudio) {
      return;
    }
    if (stream.type == VoipStreamType.screenshare ||
        stream is! LocalPlaybackVolumeStream) {
      return;
    }
    final volumeTarget = stream as LocalPlaybackVolumeStream;
    if (!volumeTarget.hasLocalPlaybackAudio) {
      return;
    }

    final storedVolume = _participantAudioVolumeOverrides[
        _participantAudioPreferenceKey(stream)];
    if (storedVolume == null) {
      return;
    }

    final locallyMuted = storedVolume == 0.0;
    final volumeMatches =
        (volumeTarget.localVolume - storedVolume).abs() < 0.001;
    if (volumeMatches && volumeTarget.locallyMuted == locallyMuted) {
      return;
    }

    unawaited(volumeTarget.setLocalVolume(storedVolume));
  }

  bool _isServerLoopbackStream(VoipStream stream) {
    return stream is MatrixLivekitVoipStream &&
        stream.participantIdentity.contains('_rnnoise_loopback');
  }

  /// Set the local playback volume for the tile's selected audio stream.
  void _setTileVolume(_CallTileData tile, double volume) {
    final target = _volumeTargetForTile(tile);
    if (target == null) {
      return;
    }

    final volumeTarget = target as LocalPlaybackVolumeStream;
    final clampedVolume = Preferences.clampScreenShareAudioVolume(volume);
    unawaited(volumeTarget.setLocalVolume(clampedVolume));
    if (target is MatrixLivekitVoipStream && target.isScreenShareAudio) {
      unawaited(
        preferences.setScreenShareAudioVolume(
          roomLocalId: room.localId,
          streamUserId: target.streamUserId,
          volume: clampedVolume,
        ),
      );
    } else {
      _rememberParticipantAudioVolume(target, clampedVolume);
    }
  }

  void _restoreScreenshareAudioVolume(MatrixLivekitVoipStream stream) {
    if (!stream.isScreenShareAudio) {
      return;
    }

    final storedVolumeKey = Preferences.screenShareAudioVolumeKey(
      roomLocalId: room.localId,
      streamUserId: stream.streamUserId,
    );
    final restoreKey = "$storedVolumeKey|${stream.streamId}";
    if (!_restoredScreenshareAudioVolumeKeys.add(restoreKey)) {
      return;
    }

    final storedVolume = preferences.getScreenShareAudioVolume(
      roomLocalId: room.localId,
      streamUserId: stream.streamUserId,
    );
    if (storedVolume == null) {
      return;
    }

    unawaited(stream.setLocalVolumePreservingMute(storedVolume));
  }

  void _syncHiddenTileAudioMute(List<_CallTileData> tiles) {
    final activeAudioStreamIds = <String>{};

    for (final stream in widget.currentSession.streams) {
      if (stream is! MatrixLivekitVoipStream || !stream.isScreenShareAudio) {
        continue;
      }

      activeAudioStreamIds.add(stream.streamId);
      final matchingTile = tiles.tryFirstWhere(
        (tile) =>
            tile.isScreenshare &&
            _volumeTargetForTile(tile)?.streamId == stream.streamId,
      );
      final hidden = matchingTile == null || _isTileVideoHidden(matchingTile);
      final shouldMute =
          VoipReceiveQualityPolicy.shouldMuteScreenShareAudioForVisibility(
        direction: stream.direction,
        hasMatchingScreenShareTile: matchingTile != null,
        screenShareVideoHidden: hidden,
      );
      final mutedByVisibility = _visibilityMutedAudioStreamIds.contains(
        stream.streamId,
      );
      final shouldUnmute =
          VoipReceiveQualityPolicy.shouldUnmuteScreenShareAudioForVisibility(
        direction: stream.direction,
        hasMatchingScreenShareTile: matchingTile != null,
        screenShareVideoHidden: hidden,
        mutedByVisibility: mutedByVisibility,
        locallyMuted: stream.locallyMuted,
        mutedByUser: stream.localVolume <= 0,
        localVolume: stream.localVolume,
      );

      if (shouldMute && !mutedByVisibility) {
        _visibilityMutedAudioStreamIds.add(stream.streamId);
        _setVisibilityMute(stream, true);
      } else if (!shouldMute && shouldUnmute) {
        if (mutedByVisibility) {
          _visibilityMutedAudioStreamIds.remove(stream.streamId);
        }
        _setVisibilityMute(stream, false);
      }
    }

    for (final streamId in _visibilityMutedAudioStreamIds.toList(
      growable: false,
    )) {
      if (!activeAudioStreamIds.contains(streamId)) {
        _visibilityMutedAudioStreamIds.remove(streamId);
      }
    }
  }

  void _setVisibilityMute(MatrixLivekitVoipStream stream, bool muted) {
    scheduleMicrotask(() {
      unawaited(stream.setLocalMute(muted));
    });
  }

  /// Remove a participant from the call (admin-only).
  Future<void> _removeParticipantFromCall(_CallTileData tile) async {
    await _voipRoomComponent?.removeParticipantFromCall(tile.userId);
  }

  bool get _hasExplicitlyHiddenTiles {
    for (final stream in widget.currentSession.streams) {
      if (stream.type == VoipStreamType.screenshare) {
        if (_hiddenScreenshareStreamIds.contains(_tileIdForStream(stream))) {
          return true;
        }
      } else if (_hiddenUserIds.contains(stream.streamUserId)) {
        return true;
      }
    }

    return false;
  }

  /// Toggle the local context-menu hide state for a tile.
  ///
  /// Camera tiles use the per-user hide set. Screenshare tiles keep a
  /// separate explicit-hide set so incoming auto-hidden screenshares can
  /// remain distinct from user-chosen hide/show state.
  void _toggleTileHidden(_CallTileData tile) {
    final currentlyHidden = _isTileVideoHidden(tile);
    setState(() {
      if (tile.isScreenshare) {
        final local = isLocalTile(tile);
        if (currentlyHidden) {
          _hiddenScreenshareStreamIds.remove(tile.tileId);
          _shownScreenshareStreamIds.add(tile.tileId);
        } else {
          _hiddenScreenshareStreamIds.add(tile.tileId);
        }
        if (local) {
          _markLocalScreenshareAutoHideHandled(tile.tileId);
        }
      } else {
        if (_hiddenUserIds.contains(tile.userId)) {
          _hiddenUserIds.remove(tile.userId);
        } else {
          _hiddenUserIds.add(tile.userId);
        }
      }
    });
  }

  /// Toggle the reveal state for a screenshare tile without changing the
  /// explicit context-menu hide state.
  void _toggleScreenshareVisibility(_CallTileData tile) {
    if (!tile.isScreenshare) return;

    final currentlyHidden = _isTileVideoHidden(tile);
    setState(() {
      final local = isLocalTile(tile);
      if (currentlyHidden) {
        _hiddenScreenshareStreamIds.remove(tile.tileId);
        _shownScreenshareStreamIds.add(tile.tileId);
      } else {
        _hiddenScreenshareStreamIds.remove(tile.tileId);
        _shownScreenshareStreamIds.remove(tile.tileId);
      }
      if (local) {
        _markLocalScreenshareAutoHideHandled(tile.tileId);
      }
    });
  }

  /// Returns true when the video for [tile] should be replaced with the
  /// blank-panel (hidden) overlay.
  ///
  /// - Camera tiles (local and remote): hidden only when explicitly toggled
  ///   via the context menu.
  /// - Remote screenshare tiles: hidden by **default** until the local user
  ///   reveals them, and can also be explicitly re-hidden from the context menu.
  /// - Local screenshare tiles: visible at first so the publisher can verify
  ///   the share, then auto-hidden locally after a short preview window.
  bool _isTileVideoHidden(_CallTileData tile) {
    if (tile.isScreenshare) {
      if (isLocalTile(tile)) {
        // Local screenshares: hidden when explicitly toggled or after the
        // local preview auto-hide timer fires.
        return _hiddenScreenshareStreamIds.contains(tile.tileId);
      }
      // Remote screenshares: hidden by default until revealed.
      return _hiddenScreenshareStreamIds.contains(tile.tileId) ||
          !_shownScreenshareStreamIds.contains(tile.tileId);
    }
    // Camera tiles (local and remote): hidden only when explicitly toggled.
    return _hiddenUserIds.contains(tile.userId);
  }

  void _syncLocalScreenshareAutoHideTimers() {
    final localUserId = widget.currentSession.client.self?.identifier;
    if (localUserId == null) {
      return;
    }

    final localScreenshareIds = widget.currentSession.streams
        .where(
          (stream) =>
              stream.streamUserId == localUserId &&
              stream.type == VoipStreamType.screenshare,
        )
        .map(_tileIdForStream)
        .toSet();

    for (final entry in _localScreenshareAutoHideTimers.entries.toList(
      growable: false,
    )) {
      if (!localScreenshareIds.contains(entry.key)) {
        entry.value.cancel();
        _localScreenshareAutoHideTimers.remove(entry.key);
      }
    }

    _autoHiddenLocalScreenshareStreamIds.removeWhere(
      (streamId) => !localScreenshareIds.contains(streamId),
    );

    if (_streamTestRunning) {
      for (final timer in _localScreenshareAutoHideTimers.values) {
        timer.cancel();
      }
      _localScreenshareAutoHideTimers.clear();
      for (final tileId in localScreenshareIds) {
        _autoHiddenLocalScreenshareStreamIds.remove(tileId);
        _hiddenScreenshareStreamIds.remove(tileId);
        _shownScreenshareStreamIds.add(tileId);
      }
      return;
    }

    for (final tileId in localScreenshareIds) {
      if (_localScreenshareAutoHideTimers.containsKey(tileId) ||
          _autoHiddenLocalScreenshareStreamIds.contains(tileId)) {
        continue;
      }

      _localScreenshareAutoHideTimers[tileId] = Timer(
        _localScreensharePreviewDuration,
        () => _autoHideLocalScreenshare(tileId),
      );
    }
  }

  void _autoHideLocalScreenshare(String tileId) {
    _localScreenshareAutoHideTimers.remove(tileId);

    if (!mounted) {
      return;
    }

    final localUserId = widget.currentSession.client.self?.identifier;
    final stillSharing = widget.currentSession.streams.any(
      (stream) =>
          _tileIdForStream(stream) == tileId &&
          stream.streamUserId == localUserId &&
          stream.type == VoipStreamType.screenshare,
    );
    if (!stillSharing) {
      return;
    }

    setState(() {
      _autoHiddenLocalScreenshareStreamIds.add(tileId);
      _hiddenScreenshareStreamIds.add(tileId);
      _shownScreenshareStreamIds.remove(tileId);
      if (focusedTileId == tileId) {
        focusedTileId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (widget.currentSession.state) {
      VoipState.connected => callConnectedView(),
      VoipState.outgoing => callOutgoingView(),
      VoipState.connecting => callOutgoingView(),
      VoipState.ended => callEndedView(),
      VoipState.incoming => callIncomingView(),
      _ => const Placeholder(),
    };

    if (widget.transparentBackground) {
      return Material(color: Colors.transparent, child: content);
    }

    return tiamat.Tile.lowest(child: content);
  }

  Widget callOutgoingView() {
    return callButtons(
      canHangUp: true,
      canPopOutSession: BuildConfig.DESKTOP && widget.showSessionPopoutButton,
      child: Center(
        child: RippleAnimation(
          ripplesCount: 3,
          scale: 1,
          color: Theme.of(context).colorScheme.primary,
          repeat: true,
          child: Avatar.large(
            image: room.avatar,
            placeholderColor: room.defaultColor,
            placeholderText: room.displayName,
          ),
        ),
      ),
    );
  }

  Color _transparentControlColor(Color color) {
    return Color.alphaBlend(
      color.withAlpha(150),
      Colors.black.withAlpha(150),
    );
  }

  Widget _callControlButton({
    required double radius,
    IconData? icon,
    VoidCallback? onPressed,
    Color? color,
    Color? transparentColor,
    Color? iconColor,
    String? tooltip,
  }) {
    final button = widget.transparentBackground
        ? _TransparentCallControlButton(
            radius: radius,
            icon: icon,
            onPressed: onPressed,
            color: transparentColor,
            iconColor: iconColor,
          )
        : tiamat.CircleButton(
            radius: radius,
            icon: icon,
            onPressed: onPressed,
            color: color,
            iconColor: iconColor,
          );

    if (tooltip == null) {
      return button;
    }

    return _transparentAwareTooltip(message: tooltip, child: button);
  }

  Widget _transparentAwareTooltip({
    required String message,
    required Widget child,
  }) {
    if (!widget.transparentBackground) {
      return Tooltip(message: message, child: child);
    }

    return Tooltip(
      message: message,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      textStyle: const TextStyle(color: Colors.white),
      child: child,
    );
  }

  Widget callButtons({
    bool canMute = false,
    bool canScreenshare = false,
    bool canHangUp = false,
    bool canToggleCamera = false,
    bool canPopOutSession = false,
    bool canHideStreams = false,
    required Widget child,
  }) {
    final buttonRadius = Layout.mobile ? 24.0 : 18.0;
    final sharedAudioIndicator = _sharedAudioStatusIndicator(buttonRadius);
    final serverAudioLoopbackButton = _serverAudioLoopbackButton(buttonRadius);
    return MouseRegion(
      onEnter: (event) {
        setState(() {
          isMouseHovering = true;
        });
      },
      onExit: (event) {
        setState(() {
          isMouseHovering = false;
        });
      },
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          child,
          _CallControlsVisibility(
            visible:
                Layout.mobile || isMouseHovering || widget.forceControlsVisible,
            transparentBackground: widget.transparentBackground,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                spacing: 12,
                children: [
                  if (canPopOutSession)
                    TutorialAnchor(
                      id: TutorialAnchorIds.callPopoutButton,
                      padding: const EdgeInsets.all(8),
                      child: _callControlButton(
                        radius: buttonRadius,
                        icon: Icons.open_in_new_rounded,
                        onPressed: () {
                          callPopoutController.popOutSession(
                            widget.currentSession.sessionId,
                          );
                        },
                      ),
                    ),
                  if (canHideStreams)
                    _callControlButton(
                      radius: buttonRadius,
                      icon: _hasExplicitlyHiddenTiles
                          ? Icons.videocam_off_outlined
                          : Icons.videocam_outlined,
                      onPressed: () {
                        setState(() {
                          if (_hasExplicitlyHiddenTiles) {
                            // Show all — clear every hidden stream.
                            _hiddenUserIds.clear();
                            _hiddenScreenshareStreamIds.clear();
                            final localId =
                                widget.currentSession.client.self?.identifier;
                            for (final stream
                                in widget.currentSession.streams) {
                              if (stream.streamUserId == localId &&
                                  stream.type == VoipStreamType.screenshare) {
                                _markLocalScreenshareAutoHideHandled(
                                  _tileIdForStream(stream),
                                );
                              }
                            }
                          } else {
                            // Hide all remote participants at once.
                            final localId =
                                widget.currentSession.client.self?.identifier;
                            for (final stream
                                in widget.currentSession.streams) {
                              if (stream.streamUserId != localId) {
                                if (stream.type == VoipStreamType.screenshare) {
                                  _hiddenScreenshareStreamIds.add(
                                    _tileIdForStream(stream),
                                  );
                                } else {
                                  _hiddenUserIds.add(stream.streamUserId);
                                }
                              }
                            }
                          }
                        });
                      },
                    ),
                  if (canScreenshare)
                    _callControlButton(
                      radius: buttonRadius,
                      icon: Icons.screen_share_outlined,
                      onPressed: widget.pickScreenshareSource,
                    ),
                  if (sharedAudioIndicator != null) sharedAudioIndicator,
                  if (widget.currentSession.isSharingScreen && canScreenshare)
                    _callControlButton(
                      radius: buttonRadius,
                      icon: Icons.stop_screen_share,
                      onPressed: widget.stopScreenshare,
                    ),
                  if (serverAudioLoopbackButton != null)
                    serverAudioLoopbackButton,
                  if (preferences.developerMode.value)
                    _callControlButton(
                      radius: buttonRadius,
                      icon: Icons.article_outlined,
                      tooltip: 'Call diagnostics logs',
                      onPressed: _openCallDiagnosticsLogMenu,
                    ),
                  if (preferences.developerMode.value &&
                      preferences.showCallStreamStats.value)
                    _callControlButton(
                      radius: buttonRadius,
                      icon: _diagnosticsOverlayVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      tooltip: _diagnosticsOverlayVisible
                          ? 'Hide developer stats overlay'
                          : 'Show developer stats overlay',
                      onPressed: () {
                        final nextVisible = !_diagnosticsOverlayVisible;
                        setState(() {
                          _diagnosticsOverlayVisible = nextVisible;
                        });
                        unawaited(
                          preferences.callStreamStatsOverlayVisible.set(
                            nextVisible,
                          ),
                        );
                      },
                    ),
                  if (canMute)
                    _callControlButton(
                      radius: buttonRadius,
                      icon: widget.currentSession.isMicrophoneMuted
                          ? Icons.mic_off
                          : Icons.mic,
                      onPressed: () async {
                        await widget.setMicrophoneMute?.call(
                          !widget.currentSession.isMicrophoneMuted,
                        );
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                  if (canToggleCamera)
                    _callControlButton(
                      radius: buttonRadius,
                      icon: widget.currentSession.isCameraEnabled
                          ? Icons.no_photography
                          : Icons.camera_alt_outlined,
                      onPressed: widget.currentSession.isCameraEnabled
                          ? widget.disableCamera
                          : widget.pickCamera,
                    ),
                  if (canHangUp)
                    _callControlButton(
                      color: Theme.of(context).colorScheme.errorContainer,
                      transparentColor: _transparentControlColor(
                        Theme.of(context).colorScheme.error,
                      ),
                      iconColor: widget.transparentBackground
                          ? Theme.of(context).colorScheme.onError
                          : null,
                      radius: buttonRadius,
                      icon: Icons.call_end,
                      onPressed: () async {
                        await widget.hangUp?.call();
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _serverAudioLoopbackButton(double buttonRadius) {
    if (!preferences.developerMode.value) {
      return null;
    }

    final session = widget.currentSession;
    if (session is! MatrixLivekitVoipSession) {
      return null;
    }

    final starting = session.isServerAudioLoopbackStarting;
    final active = session.isServerAudioLoopbackEnabled;
    final hasError = session.serverAudioLoopbackError != null;
    final label = starting
        ? 'Starting server audio loopback...'
        : active
            ? 'Stop server audio loopback. You are hearing your mic after it '
                'routes through LiveKit.'
            : hasError
                ? 'Retry server audio loopback: '
                    '${session.serverAudioLoopbackError}'
                : 'Start server audio loopback to hear your mic after it '
                    'routes through LiveKit.';
    final color = active
        ? Theme.of(context).colorScheme.primaryContainer
        : hasError
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer;
    final transparentColor = hasError
        ? _transparentControlColor(Theme.of(context).colorScheme.error)
        : active
            ? _transparentControlColor(Theme.of(context).colorScheme.primary)
            : null;

    return _callControlButton(
      radius: buttonRadius,
      color: color,
      transparentColor: transparentColor,
      icon: starting
          ? Icons.sync
          : active
              ? Icons.hearing
              : Icons.hearing_disabled,
      tooltip: label,
      onPressed: starting
          ? null
          : () async {
              try {
                await session.setServerAudioLoopbackEnabled(!active);
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to toggle server audio loopback',
                );
              } finally {
                if (mounted) {
                  setState(() {});
                }
              }
            },
    );
  }

  Widget? _sharedAudioStatusIndicator(double buttonRadius) {
    final shareSession = widget.currentSession.currentShareSession;
    if (shareSession == null || !shareSession.sharedAudioRequested) {
      return null;
    }

    final (icon, label, color) = switch (shareSession.sharedAudioState) {
      SharedAudioState.active => (
          Icons.volume_up_outlined,
          'Shared audio active',
          Theme.of(context).colorScheme.primaryContainer,
        ),
      SharedAudioState.starting => (
          Icons.sync,
          'Shared audio starting',
          Theme.of(context).colorScheme.secondaryContainer,
        ),
      SharedAudioState.failed || SharedAudioState.unavailable => (
          Icons.volume_off_outlined,
          'Shared audio unavailable',
          Theme.of(context).colorScheme.errorContainer,
        ),
      _ => (
          Icons.volume_off_outlined,
          'Shared audio inactive',
          Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
    };
    final indicatorColor =
        widget.transparentBackground ? _transparentControlColor(color) : color;

    return _transparentAwareTooltip(
      message: label,
      child: Container(
        width: buttonRadius * 2,
        height: buttonRadius * 2,
        decoration:
            BoxDecoration(shape: BoxShape.circle, color: indicatorColor),
        child: Icon(
          icon,
          size: buttonRadius,
          color: widget.transparentBackground ? Colors.white : null,
        ),
      ),
    );
  }

  Widget callConnectedView() {
    final tiles = buildVisibleTiles();
    final hasPoppedStreams = callPopoutController.hasPoppedStreams(
      widget.currentSession.sessionId,
    );
    final focusedTile = resolveFocusedTile(tiles);
    final secondaryTiles = tiles
        .where((tile) => tile.tileId != focusedTile?.tileId)
        .toList(growable: false);
    _applyReceivePriorities(tiles, focusedTile);

    final content = callButtons(
      canMute: true,
      canHangUp: true,
      canScreenshare: widget.currentSession.supportsScreenshare,
      canToggleCamera: true,
      canPopOutSession: BuildConfig.DESKTOP && widget.showSessionPopoutButton,
      canHideStreams: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (tiles.isEmpty) {
            return Center(
              child: tiamat.Text.labelLow(
                hasPoppedStreams
                    ? "All streams are currently popped out."
                    : "Waiting for streams...",
              ),
            );
          }

          if (showEqualTileLayout || focusedTile == null || tiles.length == 1) {
            return buildEqualTileGrid(tiles);
          }

          return DecoratedBox(
            decoration: BoxDecoration(
              color: widget.transparentBackground
                  ? Colors.transparent
                  : const Color(0xFF111214),
              borderRadius: BorderRadius.circular(
                widget.transparentBackground ? 0 : 24,
              ),
            ),
            child: Padding(
              padding: _callTileAreaPadding(constraints),
              child: Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: buildFocusedTile(focusedTile, tiles.length),
                  ),
                  if (secondaryTiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Flexible(
                      flex: 1,
                      child: buildTileRail(secondaryTiles, constraints),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );

    final showDiagnosticsOverlay = preferences.developerMode.value &&
        preferences.showCallStreamStats.value &&
        _diagnosticsOverlayVisible;
    if (!showDiagnosticsOverlay) {
      return content;
    }

    return Stack(
      children: [
        Positioned.fill(child: content),
        Positioned(top: 12, left: 12, child: buildDiagnosticsOverlay()),
      ],
    );
  }

  void _applyReceivePriorities(
    List<_CallTileData> tiles,
    _CallTileData? focusedTile,
  ) {
    _syncHiddenTileAudioMute(tiles);

    final visibleVideoStreamCount = tiles
        .where((tile) => tile.hasVisual && !_isTileVideoHidden(tile))
        .length;
    final visibleScreenshareCount = tiles
        .where((tile) => tile.isScreenshare && !_isTileVideoHidden(tile))
        .length;

    for (final tile in tiles) {
      final priority = VoipReceiveQualityPolicy.resolve(
        type: tile.primaryStream.type,
        direction: tile.primaryStream.direction,
        hidden: _isTileVideoHidden(tile),
        focused: focusedTile?.tileId == tile.tileId && !showEqualTileLayout,
        fullscreen: false,
        poppedOut: false,
        visibleVideoStreamCount: visibleVideoStreamCount,
        visibleScreenshareCount: visibleScreenshareCount,
      );
      unawaited(tile.primaryStream.setReceivePriority(priority));
      final audioStream = tile.audioStream;
      if (audioStream != null) {
        unawaited(
          audioStream.setReceivePriority(VoipStreamReceivePriority.high),
        );
      }
    }
  }

  Widget buildDiagnosticsOverlay() {
    final lines = _redactCallDiagnosticLines(_diagnosticsOverlayLines());

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430, maxHeight: 230),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(190),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: tiamat.IconButton(
                    icon: Icons.copy,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: lines.join('\n')));
                    },
                  ),
                ),
                ...lines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: tiamat.Text.labelLow(line),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _diagnosticsOverlayLines() {
    return <String>[
      ..._routeSfuDiagnosticsLines(includeHeader: false),
      ..._mediaPipelineDiagnosticsLines(includeHeader: false),
    ];
  }

  List<String> _routeSfuDiagnosticsLines({bool includeHeader = true}) {
    final snapshot = widget.currentSession.diagnosticsSnapshot;
    final livekitSession = widget.currentSession is MatrixLivekitVoipSession
        ? widget.currentSession as MatrixLivekitVoipSession
        : null;
    return <String>[
      if (includeHeader) 'Route / SFU:',
      'Adaptive: ${snapshot.adaptiveStreamEnabled ? 'on' : 'off'}  '
          'Dynacast: ${snapshot.dynacastEnabled ? 'on' : 'off'}  '
          'Simulcast: ${snapshot.screenShareSimulcastEnabled ? 'on' : 'off'}',
      if (snapshot.adaptiveFallbackEnabled)
        'Fallback: ${snapshot.adaptiveFallbackReason ?? 'watching'}',
      if (livekitSession != null)
        'Server loopback: ${livekitSession.serverAudioLoopbackDiagnosticLabel}',
      if (snapshot.iceTransportSummary != null)
        'ICE: ${snapshot.iceTransportSummary}',
      if (snapshot.hasParticipants) ...[
        'Clients:',
        ...snapshot.participants.map(_participantDiagnosticLine),
      ],
    ];
  }

  List<String> _mediaPipelineDiagnosticsLines({bool includeHeader = true}) {
    final snapshot = widget.currentSession.diagnosticsSnapshot;
    return <String>[
      if (includeHeader) 'Capture / encode / render:',
      'Profile: ${snapshot.screenShareProfileLabel}',
      if (snapshot.screenShareProfileDetails != null)
        'Profile details: ${snapshot.screenShareProfileDetails}',
      if (snapshot.shareSessionDiagnostics != null)
        ...snapshot.shareSessionDiagnostics!.lines(),
      if (!snapshot.hasTracks) 'No LiveKit stats yet.',
      ...snapshot.tracks.map(_diagnosticLine),
    ];
  }

  NoiseSuppressionPipelineMode? _rnnoisePipelineModeForHookPreference(
    String hookMode,
  ) {
    return switch (hookMode) {
      'identity' => NoiseSuppressionPipelineMode.identity,
      'off' => NoiseSuppressionPipelineMode.off,
      _ => null,
    };
  }

  Future<void> _delayForRnnoiseBatch(
    Duration duration,
    bool Function() isCanceled,
  ) async {
    final deadline = DateTime.now().add(duration);
    while (!isCanceled() && DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 250)
            ? remaining
            : const Duration(milliseconds: 250),
      );
    }
  }

  Future<void> _applyRnnoiseDiagnosticBatchScenario(
    _RnnoiseDiagnosticBatchScenario scenario,
  ) async {
    await preferences.voipAudioCaptureTapOrderScenario.set(scenario.scenario);
    await preferences.voipNoiseSuppressionHookMode
        .set(scenario.hookModePreference);
    await preferences.voipNoiseSuppressionEnabled
        .set(scenario.noiseSuppressionEnabled);
    await NoiseSuppressionService.instance.applyPreference(
      scenario.noiseSuppressionEnabled,
    );
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _rnnoisePipelineModeForHookPreference(scenario.hookModePreference),
    );
    if (scenario.noiseSuppressionEnabled) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
  }

  Future<void> _restoreRnnoiseDiagnosticBatchPreferences({
    required bool originalEnabled,
    required String originalHookMode,
    required String originalScenario,
  }) async {
    await preferences.voipAudioCaptureTapOrderScenario.set(originalScenario);
    await preferences.voipNoiseSuppressionHookMode.set(originalHookMode);
    await preferences.voipNoiseSuppressionEnabled.set(originalEnabled);
    await NoiseSuppressionService.instance.applyPreference(originalEnabled);
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _rnnoisePipelineModeForHookPreference(originalHookMode),
    );
    if (originalEnabled) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
  }

  Future<_RnnoiseDiagnosticBatchResult> _runRnnoiseDiagnosticCaptureBatch({
    required bool Function() isCanceled,
    required void Function(String progress) onProgress,
    Duration captureDuration = const Duration(seconds: 10),
    Duration settleDuration = const Duration(seconds: 2),
  }) async {
    final originalEnabled = preferences.voipNoiseSuppressionEnabled.value;
    final originalHookMode = preferences.voipNoiseSuppressionHookMode.value;
    final originalScenario = preferences.voipAudioCaptureTapOrderScenario.value;
    var completed = 0;
    var writtenFiles = 0;
    final failures = <String>[];

    try {
      onProgress('preparing tap-order capture...');
      await NoiseSuppressionService.instance.stopDiagnosticCapture();
      String? wasapiDeviceId;
      try {
        wasapiDeviceId = await WebrtcDefaultDevices.getDefaultMicrophoneId();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to resolve RNNoise batch WASAPI microphone id',
        );
      }

      for (var index = 0;
          index < _rnnoiseTapOrderBatchScenarios.length;
          index++) {
        if (isCanceled()) {
          break;
        }

        final scenario = _rnnoiseTapOrderBatchScenarios[index];
        final scenarioNumber = index + 1;
        final prefix =
            '$scenarioNumber/${_rnnoiseTapOrderBatchScenarios.length} '
            '${scenario.label}';

        onProgress('$prefix: applying capture profile...');
        await _applyRnnoiseDiagnosticBatchScenario(scenario);

        // LiveKit recreates the microphone track from the changed capture
        // signature. Give that refresh a short window before recording stages.
        await _delayForRnnoiseBatch(settleDuration, isCanceled);
        if (isCanceled()) {
          break;
        }

        final directoryPath = await createNoiseSuppressionDiagnosticDirectory(
          captureLabel: 'call-batch-$scenarioNumber-${scenario.scenario}',
          stageMask: NoiseSuppressionDiagnosticStageMask.all,
          includeWasapiSidecar: true,
        );
        onProgress('$prefix: recording ${captureDuration.inSeconds}s...');
        final result =
            await NoiseSuppressionService.instance.startDiagnosticCapture(
          directoryPath: directoryPath,
          duration: captureDuration,
          stageMask: NoiseSuppressionDiagnosticStageMask.all,
          includeWasapiSidecar: true,
          wasapiDeviceId: wasapiDeviceId,
        );

        if (!result.status.diagnosticCaptureActive) {
          failures.add('$prefix did not start: ${result.status.reason}');
          continue;
        }

        await _delayForRnnoiseBatch(
          captureDuration + const Duration(seconds: 1),
          isCanceled,
        );

        final stoppedStatus =
            await NoiseSuppressionService.instance.stopDiagnosticCapture();
        await collectNoiseSuppressionDiagnosticReportBundle(
          directoryPath: directoryPath,
        );
        completed++;
        writtenFiles += stoppedStatus.diagnosticCaptureWrittenFiles;
        if (stoppedStatus.diagnosticCaptureWrittenFiles == 0) {
          final reason = stoppedStatus.diagnosticCaptureLastError.isEmpty
              ? stoppedStatus.reason
              : stoppedStatus.diagnosticCaptureLastError;
          failures.add('$prefix wrote no files: $reason');
        }

        // Let native WASAPI/hook shutdown settle before switching constraints.
        await _delayForRnnoiseBatch(
            const Duration(milliseconds: 500), isCanceled);
      }
    } finally {
      try {
        await NoiseSuppressionService.instance.stopDiagnosticCapture();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to stop RNNoise capture during batch cleanup',
        );
      }
      try {
        await _restoreRnnoiseDiagnosticBatchPreferences(
          originalEnabled: originalEnabled,
          originalHookMode: originalHookMode,
          originalScenario: originalScenario,
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to restore RNNoise diagnostic batch preferences',
        );
      }
    }

    return _RnnoiseDiagnosticBatchResult(
      completed: completed,
      writtenFiles: writtenFiles,
      canceled: isCanceled(),
      failures: List.unmodifiable(failures),
    );
  }

  void _openCallDiagnosticsLogMenu() {
    var saving = false;
    var reporting = false;
    var rnnoiseDiagnosticCaptureBusy = false;
    var rnnoiseDiagnosticBatchRunning = false;
    var rnnoiseDiagnosticBatchCancelRequested = false;
    String? rnnoiseDiagnosticCaptureMessage;
    var rnnoiseDiagnosticCaptureId = 0;
    var collapsed = false;
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> finishRnnoiseDiagnosticCapture({
              required int captureId,
            }) async {
              if (captureId != rnnoiseDiagnosticCaptureId) {
                return;
              }
              try {
                final status = await NoiseSuppressionService.instance
                    .stopDiagnosticCapture();
                final path = NoiseSuppressionService
                    .instance.diagnosticCaptureDirectoryPath;
                NoiseSuppressionDiagnosticReportBundle? reportBundle;
                if (path != null) {
                  reportBundle =
                      await collectNoiseSuppressionDiagnosticReportBundle(
                    directoryPath: path,
                  );
                }
                if (!dialogContext.mounted) {
                  return;
                }
                if (captureId != rnnoiseDiagnosticCaptureId) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureBusy = false;
                  rnnoiseDiagnosticCaptureMessage = status
                              .diagnosticCaptureWrittenFiles >
                          0
                      ? rnnoiseDiagnosticCaptureCompleteDisplayMessage(
                          writtenFiles: status.diagnosticCaptureWrittenFiles,
                          directoryLabel: reportBundle?.directoryLabel,
                        )
                      : 'No RNNoise diagnostic WAV files were written: '
                          '${status.diagnosticCaptureLastError.isEmpty ? status.reason : status.diagnosticCaptureLastError}.';
                });
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to finish RNNoise diagnostic capture',
                );
                if (!dialogContext.mounted ||
                    captureId != rnnoiseDiagnosticCaptureId) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureBusy = false;
                  rnnoiseDiagnosticCaptureMessage =
                      'RNNoise WAV capture stop failed: $error';
                });
              }
            }

            Future<void> toggleRnnoiseDiagnosticCapture() async {
              if (rnnoiseDiagnosticCaptureBusy ||
                  rnnoiseDiagnosticBatchRunning ||
                  !PlatformUtils.isWindows) {
                return;
              }

              setDialogState(() {
                rnnoiseDiagnosticCaptureBusy = true;
                rnnoiseDiagnosticCaptureMessage = null;
              });

              try {
                final status = NoiseSuppressionService.instance.status;
                if (status.diagnosticCaptureActive) {
                  rnnoiseDiagnosticCaptureId++;
                  final stoppedStatus = await NoiseSuppressionService.instance
                      .stopDiagnosticCapture();
                  final path = NoiseSuppressionService
                      .instance.diagnosticCaptureDirectoryPath;
                  NoiseSuppressionDiagnosticReportBundle? reportBundle;
                  if (path != null) {
                    reportBundle =
                        await collectNoiseSuppressionDiagnosticReportBundle(
                      directoryPath: path,
                    );
                  }
                  if (!dialogContext.mounted) {
                    return;
                  }
                  setDialogState(() {
                    rnnoiseDiagnosticCaptureBusy = false;
                    rnnoiseDiagnosticCaptureMessage = stoppedStatus
                                .diagnosticCaptureWrittenFiles >
                            0
                        ? rnnoiseDiagnosticCaptureCompleteDisplayMessage(
                            writtenFiles:
                                stoppedStatus.diagnosticCaptureWrittenFiles,
                            directoryLabel: reportBundle?.directoryLabel,
                          )
                        : 'No RNNoise diagnostic WAV files were written: '
                            '${stoppedStatus.diagnosticCaptureLastError.isEmpty ? stoppedStatus.reason : stoppedStatus.diagnosticCaptureLastError}.';
                  });
                  return;
                }

                await NoiseSuppressionService.instance.applyDiagnosticHookMode(
                  _rnnoisePipelineModeForHookPreference(
                    preferences.voipNoiseSuppressionHookMode.value,
                  ),
                );
                final directoryPath =
                    await createNoiseSuppressionDiagnosticDirectory(
                  captureLabel: 'call-panel',
                  stageMask: NoiseSuppressionDiagnosticStageMask.all,
                  includeWasapiSidecar: true,
                );
                final microphoneId =
                    await WebrtcDefaultDevices.getDefaultMicrophoneId();
                final result = await NoiseSuppressionService.instance
                    .startDiagnosticCapture(
                  directoryPath: directoryPath,
                  duration: const Duration(seconds: 10),
                  stageMask: NoiseSuppressionDiagnosticStageMask.all,
                  includeWasapiSidecar: true,
                  wasapiDeviceId: microphoneId,
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureBusy = false;
                  rnnoiseDiagnosticCaptureMessage = result
                          .status.diagnosticCaptureActive
                      ? 'Capturing 10 seconds of local tap-order WAV stages; '
                          'files will write automatically.'
                      : 'Could not start RNNoise WAV capture: '
                          '${result.status.reason}.';
                });
                if (result.status.diagnosticCaptureActive) {
                  final captureId = ++rnnoiseDiagnosticCaptureId;
                  unawaited(
                    Future<void>.delayed(
                      const Duration(seconds: 11),
                      () =>
                          finishRnnoiseDiagnosticCapture(captureId: captureId),
                    ),
                  );
                }
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to toggle RNNoise diagnostic capture',
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureBusy = false;
                  rnnoiseDiagnosticCaptureMessage =
                      'RNNoise WAV capture failed: $error';
                });
              }
            }

            Future<void> cancelRnnoiseDiagnosticBatch() async {
              if (!rnnoiseDiagnosticBatchRunning) {
                return;
              }
              rnnoiseDiagnosticBatchCancelRequested = true;
              rnnoiseDiagnosticCaptureId++;
              setDialogState(() {
                rnnoiseDiagnosticCaptureMessage =
                    'Canceling RNNoise WAV capture batch...';
              });
              try {
                await NoiseSuppressionService.instance.stopDiagnosticCapture();
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to stop RNNoise capture during batch cancel',
                );
              }
            }

            Future<void> runRnnoiseDiagnosticCaptureBatch() async {
              if (rnnoiseDiagnosticCaptureBusy || !PlatformUtils.isWindows) {
                return;
              }

              setDialogState(() {
                rnnoiseDiagnosticCaptureBusy = true;
                rnnoiseDiagnosticBatchRunning = true;
                rnnoiseDiagnosticBatchCancelRequested = false;
                rnnoiseDiagnosticCaptureMessage =
                    'Starting RNNoise WAV capture batch...';
              });

              try {
                final result = await _runRnnoiseDiagnosticCaptureBatch(
                  isCanceled: () =>
                      rnnoiseDiagnosticBatchCancelRequested ||
                      !dialogContext.mounted,
                  onProgress: (progress) {
                    if (!dialogContext.mounted) {
                      return;
                    }
                    setDialogState(() {
                      rnnoiseDiagnosticCaptureMessage = progress;
                    });
                  },
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureMessage = result.summary;
                });
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to run RNNoise diagnostic capture batch',
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureMessage =
                      'RNNoise WAV capture batch failed: $error';
                });
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    rnnoiseDiagnosticCaptureBusy = false;
                    rnnoiseDiagnosticBatchRunning = false;
                    rnnoiseDiagnosticBatchCancelRequested = false;
                  });
                }
              }
            }

            final summaryLines =
                _redactCallDiagnosticLines(_callDiagnosticsSummaryLines());
            final routeLines =
                _redactCallDiagnosticLines(_routeSfuDiagnosticsLines());
            final streamLines =
                _redactCallDiagnosticLines(_mediaPipelineDiagnosticsLines());
            final logLines = _redactCallDiagnosticLines(_relatedCallLogLines());
            final rnnoiseStatus = NoiseSuppressionService.instance.status;
            final rnnoiseCaptureRunning = rnnoiseStatus.diagnosticCaptureActive;
            final allLines = <String>[
              'Inter Galactic Call Diagnostics',
              'Collected: ${DateTime.now().toUtc().toIso8601String()}',
              '',
              '== Summary ==',
              ...summaryLines,
              '',
              '== Route / SFU ==',
              ...routeLines,
              '',
              '== Capture / Encode / Render Stats ==',
              ...streamLines,
              '',
              '== Related Logs ==',
              ...logLines,
            ];

            return AlertDialog(
              alignment: collapsed ? Alignment.topRight : Alignment.center,
              insetPadding: collapsed
                  ? const EdgeInsets.all(16)
                  : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              titlePadding: EdgeInsets.fromLTRB(
                collapsed ? 16 : 20,
                collapsed ? 12 : 16,
                12,
                0,
              ),
              contentPadding: EdgeInsets.fromLTRB(
                collapsed ? 16 : 16,
                8,
                collapsed ? 16 : 16,
                collapsed ? 12 : 16,
              ),
              title: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Call Diagnostics',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: collapsed
                        ? 'Expand diagnostics'
                        : 'Collapse diagnostics',
                    icon: Icon(
                      collapsed ? Icons.unfold_more : Icons.unfold_less,
                    ),
                    onPressed: () {
                      setDialogState(() => collapsed = !collapsed);
                    },
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setDialogState(() {}),
                  ),
                  IconButton(
                    tooltip: 'Copy all',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: allLines.join('\n')),
                      );
                    },
                  ),
                  if (widget.currentSession is MatrixLivekitVoipSession)
                    IconButton(
                      tooltip: _streamTestRunning
                          ? 'Stream test running: '
                              '${_streamTestProgressLabel ?? 'preparing...'}'
                          : 'Run stream test',
                      icon: _streamTestRunning
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.speed),
                      onPressed: _streamTestRunning
                          ? null
                          : () async {
                              void updateProgress(String? label) {
                                if (dialogContext.mounted) {
                                  setDialogState(
                                    () => _streamTestProgressLabel = label,
                                  );
                                } else if (mounted) {
                                  setState(
                                    () => _streamTestProgressLabel = label,
                                  );
                                }
                              }

                              setDialogState(() {
                                _streamTestRunning = true;
                                _streamTestProgressLabel = 'preparing...';
                              });
                              try {
                                final result = await _runStreamTestRunner(
                                  onProgress: updateProgress,
                                  onSourceSelectionStarting: () {
                                    if (!dialogContext.mounted) {
                                      return;
                                    }
                                    setDialogState(() => collapsed = true);
                                  },
                                  onSourceSelected: () {
                                    if (!dialogContext.mounted) {
                                      return;
                                    }
                                    setDialogState(() => collapsed = true);
                                  },
                                );
                                if (dialogContext.mounted) {
                                  setDialogState(() {
                                    _lastStreamTestResult = result;
                                    if (result == null) {
                                      _lastStreamTestReportWriteResult = null;
                                    }
                                  });
                                }
                              } finally {
                                if (dialogContext.mounted) {
                                  setDialogState(() {
                                    _streamTestRunning = false;
                                    _streamTestProgressLabel = null;
                                  });
                                } else if (mounted) {
                                  setState(() {
                                    _streamTestRunning = false;
                                    _streamTestProgressLabel = null;
                                  });
                                }
                              }
                            },
                    ),
                  if (PlatformUtils.isWindows)
                    IconButton(
                      tooltip: rnnoiseDiagnosticBatchRunning
                          ? 'Cancel RNNoise WAV batch'
                          : rnnoiseDiagnosticCaptureBusy
                              ? 'Updating RNNoise WAV capture...'
                              : 'Run RNNoise WAV batch',
                      icon: rnnoiseDiagnosticBatchRunning
                          ? const Icon(Icons.stop_circle_outlined)
                          : rnnoiseDiagnosticCaptureBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.playlist_play),
                      onPressed: rnnoiseDiagnosticCaptureBusy &&
                              !rnnoiseDiagnosticBatchRunning
                          ? null
                          : rnnoiseDiagnosticBatchRunning
                              ? cancelRnnoiseDiagnosticBatch
                              : runRnnoiseDiagnosticCaptureBatch,
                    ),
                  if (PlatformUtils.isWindows)
                    IconButton(
                      tooltip: rnnoiseDiagnosticCaptureBusy
                          ? 'Updating RNNoise WAV capture...'
                          : rnnoiseCaptureRunning
                              ? 'Stop RNNoise WAV capture'
                              : 'Capture one RNNoise WAV set',
                      icon: rnnoiseDiagnosticCaptureBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              rnnoiseCaptureRunning
                                  ? Icons.stop_circle_outlined
                                  : Icons.multitrack_audio_outlined,
                            ),
                      onPressed: rnnoiseDiagnosticCaptureBusy
                          ? null
                          : toggleRnnoiseDiagnosticCapture,
                    ),
                  IconButton(
                    tooltip: reporting
                        ? 'Preparing report...'
                        : 'Report stream logs',
                    icon: reporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.outgoing_mail),
                    onPressed: reporting
                        ? null
                        : () async {
                            setDialogState(() => reporting = true);
                            try {
                              await _reportCallDiagnostics(allLines);
                            } finally {
                              if (dialogContext.mounted) {
                                setDialogState(() => reporting = false);
                              }
                            }
                          },
                  ),
                  IconButton(
                    tooltip: saving ? 'Saving...' : 'Save all',
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt),
                    onPressed: saving
                        ? null
                        : () async {
                            setDialogState(() => saving = true);
                            try {
                              await _saveCallDiagnosticsLog(allLines);
                            } finally {
                              if (dialogContext.mounted) {
                                setDialogState(() => saving = false);
                              }
                            }
                          },
                  ),
                ],
              ),
              content: collapsed
                  ? _collapsedCallDiagnosticsSummary()
                  : SizedBox(
                      width: min(MediaQuery.sizeOf(context).width * 0.86, 900),
                      height: min(
                        MediaQuery.sizeOf(context).height * 0.72,
                        620,
                      ),
                      child: DefaultTabController(
                        length: 4,
                        child: Column(
                          children: [
                            if (_streamTestRunning ||
                                _streamTestProgressLabel != null) ...[
                              _streamTestProgressBanner(),
                              const SizedBox(height: 8),
                            ],
                            if (PlatformUtils.isWindows &&
                                (rnnoiseDiagnosticCaptureBusy ||
                                    rnnoiseCaptureRunning ||
                                    rnnoiseDiagnosticCaptureMessage !=
                                        null)) ...[
                              _rnnoiseDiagnosticCaptureBanner(
                                busy: rnnoiseDiagnosticCaptureBusy,
                                running: rnnoiseCaptureRunning,
                                message: rnnoiseDiagnosticCaptureMessage,
                              ),
                              const SizedBox(height: 8),
                            ],
                            const TabBar(
                              tabs: [
                                Tab(text: 'Summary'),
                                Tab(text: 'Route'),
                                Tab(text: 'Stats'),
                                Tab(text: 'Logs'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _diagnosticLogTab(summaryLines),
                                  _diagnosticLogTab(routeLines),
                                  _diagnosticLogTab(streamLines),
                                  _diagnosticLogTab(logLines),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Future<void> _reportCallDiagnostics(List<String> lines) async {
    Log.i(
      'Call diagnostics report snapshot\n'
      '${_redactCallDiagnosticText(lines.join('\n'))}',
      category: LogCategory.webrtc,
      source: 'call-diagnostics-report',
    );

    await showReportBugDialog(
      context,
      template: BugReportTemplate.callStreamLogs,
      includeLogs: true,
      includeDiagnostics: true,
    );
  }

  Future<void> _pollStreamTestAutomationCommand() async {
    if (!(BuildConfig.DEBUG || kDebugMode) ||
        !PlatformUtils.isWindows ||
        _streamTestRunning ||
        widget.currentSession is! MatrixLivekitVoipSession ||
        !mounted) {
      return;
    }
    if (_streamTestAutomationPollInFlight) {
      return;
    }
    _streamTestAutomationPollInFlight = true;
    try {
      await _pollStreamTestAutomationCommandLocked();
    } finally {
      _streamTestAutomationPollInFlight = false;
    }
  }

  Future<void> _pollStreamTestAutomationCommandLocked() async {
    if (_streamTestRunning || !mounted) {
      return;
    }
    final channel = const StreamTestAutomationCommandChannel();
    StreamTestAutomationRequest? request;
    try {
      request = await channel.takePending();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to read stream-test automation command',
      );
      return;
    }
    if (request == null || !mounted || _streamTestRunning) {
      return;
    }

    Log.i(
      'Stream test automation request ${request.id} starting',
      category: LogCategory.webrtc,
      source: 'stream-test-automation',
    );
    setState(() {
      _streamTestRunning = true;
      _streamTestProgressLabel = 'automation ${request!.id}: preparing...';
      _lastStreamTestResult = null;
      _lastStreamTestReportWriteResult = null;
    });

    StreamTestRunResult? result;
    String? error;
    try {
      result = await _runStreamTestRunner(
        automationConfig: _streamTestConfigFromAutomationRequest(request),
        allowManualSourcePicker: false,
        onProgress: (label) {
          if (!mounted) {
            return;
          }
          setState(() {
            _streamTestProgressLabel =
                label == null ? null : 'automation ${request!.id}: $label';
          });
        },
      );
      if (mounted) {
        setState(() {
          _lastStreamTestResult = result;
          if (result == null) {
            _lastStreamTestReportWriteResult = null;
          }
        });
      }
      if (result == null) {
        error = 'stream test automation did not produce a result';
      } else if (result.error != null) {
        error = result.error;
      }
    } catch (exception, stackTrace) {
      error = exception.toString();
      Log.onError(
        exception,
        stackTrace,
        content: 'Stream test automation failed',
      );
    } finally {
      try {
        await channel.complete(
          request,
          reportPath: _lastStreamTestReportWriteResult?.markdownPath ??
              _lastStreamTestReportWriteResult?.jsonPath,
          error: error,
        );
      } catch (completionError, stackTrace) {
        Log.onError(
          completionError,
          stackTrace,
          content: 'Failed to write stream-test automation completion',
        );
      }
      if (mounted) {
        setState(() {
          _streamTestRunning = false;
          _streamTestProgressLabel = null;
        });
      }
    }
  }

  _StreamTestDialogConfig _streamTestConfigFromAutomationRequest(
    StreamTestAutomationRequest request,
  ) {
    final presets = request.presetKeys
        .map(
          (key) => ScreenShareProfileConfig.forPreferenceKey(
            key,
            preferHardwareEncoding: PlatformUtils.isWindows &&
                preferences.streamHardwareEncodingFirst.value,
          ),
        )
        .toList(growable: false);
    final backendMode = _automationBackendMode(request.windowsBackendMode);
    return _StreamTestDialogConfig(
      presets: presets.isEmpty
          ? [
              ScreenShareProfileConfig.forPreferenceKey(
                ScreenShareQualityProfile.smooth.storageKey,
                preferHardwareEncoding: PlatformUtils.isWindows &&
                    preferences.streamHardwareEncodingFirst.value,
              ),
              ScreenShareProfileConfig.forPreferenceKey(
                ScreenShareQualityProfile.balanced.storageKey,
                preferHardwareEncoding: PlatformUtils.isWindows &&
                    preferences.streamHardwareEncodingFirst.value,
              ),
              ScreenShareProfileConfig.forPreferenceKey(
                ScreenShareQualityProfile.highQuality.storageKey,
                preferHardwareEncoding: PlatformUtils.isWindows &&
                    preferences.streamHardwareEncodingFirst.value,
              ),
            ]
          : presets,
      duration: request.duration,
      warmup: request.warmup,
      windowsCaptureBackendMode: backendMode,
      windowsCaptureBackendModes: request.compareWindowsBackends
          ? _streamTestWindowsCaptureBackendCompareModes
          : null,
      windowsCaptureDirtyRegionMode: request.forceFullFrameDirtyRegions
          ? WindowsScreenCaptureDirtyRegionMode.forceFullFrame
          : WindowsScreenCaptureDirtyRegionMode.auto,
      nativeFramePacingEnabled: request.nativeFramePacingEnabled,
      dummyNv12LiveSender: request.dummyNv12LiveSender,
      captureTestTargetEnabled: request.captureTarget.enabled,
      captureTestTargetWidth: request.captureTarget.width,
      captureTestTargetHeight: request.captureTarget.height,
      captureTestTargetMode: request.captureTarget.windowMode,
      captureTestTargetScene: request.captureTarget.scene,
      captureTestTargetFps: request.captureTarget.fps,
      automationSourceProcessId: request.sourceProcessId,
      automationSourceTitle: request.sourceTitle,
    );
  }

  WindowsScreenCaptureBackendMode? _automationBackendMode(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized == 'app-default' ||
        normalized == 'appdefault' ||
        normalized == 'default') {
      return null;
    }
    return WindowsScreenCaptureBackendModeDetails.fromConstraintValue(
      normalized == 'native-default' ? 'default' : normalized,
    );
  }

  Future<String> _streamTestDiagnosticLogText({
    int maxFileBytes = 160 * 1024,
  }) async {
    final appLogs = await Log.recentText(maxFileBytes: maxFileBytes);
    final nativeLogs = await NativeWebrtcDiagnostics.recentText(
      maxFileBytes: maxFileBytes,
    );
    return [
      appLogs,
      nativeLogs,
    ].where((text) => text.trim().isNotEmpty).join('\n');
  }

  Future<StreamTestRunResult?> _runStreamTestRunner({
    void Function(String? label)? onProgress,
    VoidCallback? onSourceSelectionStarting,
    VoidCallback? onSourceSelected,
    _StreamTestDialogConfig? automationConfig,
    bool allowManualSourcePicker = true,
  }) async {
    final session = widget.currentSession;
    if (session is! MatrixLivekitVoipSession) {
      return null;
    }

    onProgress?.call(
      automationConfig == null ? 'choosing presets...' : 'loading command...',
    );
    final runnerConfig =
        automationConfig ?? await _showStreamTestConfigDialog();
    if (runnerConfig == null || runnerConfig.presets.isEmpty || !mounted) {
      return null;
    }

    final captureTargetConfig = runnerConfig.captureTestTargetConfig;
    GameCaptureTestTargetSession? captureTargetSession;
    GameCaptureTestTargetResult? captureTargetResult;
    if (captureTargetConfig.enabled) {
      onProgress?.call('launching capture target...');
      captureTargetSession =
          await createDefaultGameCaptureTestTargetLauncher().launch(
        captureTargetConfig,
      );
      captureTargetResult = captureTargetSession.launchResult;
      if (captureTargetResult.status != 'launched') {
        _showStreamTestSnackBar(
          'Capture target unavailable: '
          '${captureTargetResult.reason ?? captureTargetResult.status}',
        );
      }
    }

    ScreenCaptureSource? source;
    onProgress?.call(
      runnerConfig.dummyNv12LiveSender
          ? 'selecting dummy NV12 source...'
          : 'selecting source...',
    );
    onSourceSelectionStarting?.call();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) {
      if (captureTargetSession != null) {
        await captureTargetSession.stopAndCollect();
      }
      return null;
    }

    Log.i(
      'Stream test source picker opening',
      category: LogCategory.webrtc,
      source: 'stream-test-runner',
    );

    if (runnerConfig.dummyNv12LiveSender) {
      source = await _selectDummyNv12LiveSenderPlaceholderSource();
      if (source != null) {
        Log.i(
          'Stream test automation selected dummy NV12 live-sender '
          'placeholder source',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
      }
    }

    if (source == null && captureTargetResult?.status == 'launched') {
      onProgress?.call('selecting capture target window...');
      try {
        Log.i(
          'Stream test capture-target auto-selection starting '
          'timeout=${_streamTestAutoSelectTimeout.inSeconds}s',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        source = await WebrtcScreencaptureSource.findWindowByTitle(
          captureTargetConfig.title,
          shareAudio: false,
        ).timeout(_streamTestAutoSelectTimeout);
        if (source != null) {
          captureTargetResult =
              captureTargetResult!.withSelection(automatic: true);
          Log.i(
            'Stream test auto-selected D3D11 capture target window',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        } else {
          Log.i(
            'Stream test capture-target auto-selection returned no match',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        }
      } on TimeoutException catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test capture-target auto-selection timed out '
              'after ${_streamTestAutoSelectTimeout.inSeconds}s',
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test capture-target auto-selection failed',
        );
      }
      if (source == null) {
        _showStreamTestSnackBar(
          'Capture target launched; select its window manually.',
        );
      }
    }

    final automationSourceProcessId = runnerConfig.automationSourceProcessId;
    if (source == null &&
        !allowManualSourcePicker &&
        automationSourceProcessId != null &&
        automationSourceProcessId > 0) {
      onProgress?.call('selecting process $automationSourceProcessId...');
      try {
        Log.i(
          'Stream test automation source-process selection starting '
          'pid=$automationSourceProcessId '
          'timeout=${_streamTestAutoSelectTimeout.inSeconds}s',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        source = await WebrtcScreencaptureSource.findWindowByProcessId(
          automationSourceProcessId,
          shareAudio: false,
        ).timeout(_streamTestAutoSelectTimeout);
        if (source != null) {
          Log.i(
            'Stream test automation auto-selected window pid '
            '$automationSourceProcessId',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        } else {
          Log.i(
            'Stream test automation source-process selection returned no '
            'match pid=$automationSourceProcessId',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        }
      } on TimeoutException catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test automation source-process selection timed out '
              'after ${_streamTestAutoSelectTimeout.inSeconds}s '
              'pid=$automationSourceProcessId',
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test automation source-process selection failed',
        );
      }
    }

    final automationSourceTitle = runnerConfig.automationSourceTitle;
    if (source == null &&
        !allowManualSourcePicker &&
        automationSourceTitle != null &&
        automationSourceTitle.trim().isNotEmpty) {
      onProgress?.call('selecting requested automation window...');
      try {
        Log.i(
          'Stream test automation source-title selection starting '
          'timeout=${_streamTestAutoSelectTimeout.inSeconds}s',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        source = await WebrtcScreencaptureSource.findWindowByTitle(
          automationSourceTitle,
          shareAudio: false,
        ).timeout(_streamTestAutoSelectTimeout);
        if (source != null) {
          Log.i(
            'Stream test automation auto-selected window by title',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        } else {
          Log.i(
            'Stream test automation source-title selection returned no match',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        }
      } on TimeoutException catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test automation source-title selection timed out '
              'after ${_streamTestAutoSelectTimeout.inSeconds}s',
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test automation source-title selection failed',
        );
      }
    }

    if (source == null && allowManualSourcePicker) {
      try {
        source = await session.pickScreenCapture(context);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test source picker failed',
        );
        if (mounted) {
          _showStreamTestSnackBar('Stream test source picker failed: $error');
        }
        if (captureTargetSession != null) {
          await captureTargetSession.stopAndCollect();
        }
        return null;
      }
    }
    if (source == null || !mounted) {
      Log.i(
        allowManualSourcePicker
            ? 'Stream test source picker cancelled'
            : 'Stream test automation did not find an auto-selectable source',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      if (captureTargetSession != null) {
        await captureTargetSession.stopAndCollect();
      }
      return null;
    }
    onSourceSelected?.call();
    Log.i(
      'Stream test source picker selected ${source.runtimeType}',
      category: LogCategory.webrtc,
      source: 'stream-test-runner',
    );

    try {
      await NativeWebrtcDiagnostics.clear();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to clear native WebRTC diagnostics sidecar',
      );
    }

    final streamTestTarget = _CallViewStreamTestTarget(
      session: session,
      source: source,
    );
    final streamTestRunConfig = StreamTestRunConfig(
      presets: runnerConfig.presets,
      durationPerPreset: runnerConfig.duration,
      warmupDuration: runnerConfig.warmup,
      scenarioLabel: 'current-call:${session.roomName}',
      sourceMetadata: _streamTestSourceMetadata(source),
      windowsCaptureBackendMode: runnerConfig.windowsCaptureBackendMode,
      windowsCaptureBackendModes: runnerConfig.windowsCaptureBackendModes,
      windowsCaptureDirtyRegionMode: runnerConfig.windowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureModes: runnerConfig.windowsWindowGdiCaptureModes,
      nativeFramePacingEnabled: runnerConfig.nativeFramePacingEnabled,
      dummyNv12LiveSender: runnerConfig.dummyNv12LiveSender,
      gameCaptureTestTarget:
          captureTargetConfig.enabled ? captureTargetConfig : null,
      gameCaptureProbe: runnerConfig.gameCaptureProbeEnabled
          ? GameCaptureProbeConfig(
              enabled: true,
              duration: runnerConfig.duration,
              maxSavedFrames: runnerConfig.gameCaptureProofFrames,
            )
          : null,
    );
    final runnerStartedAt = DateTime.now();
    final runner = StreamTestRunner(
      target: streamTestTarget,
      onProgress: (progress) => onProgress?.call(progress.detailLabel),
      gameCaptureProbeRunner: createDefaultGameCaptureProbeRunner(),
      diagnosticLogProvider: () => _streamTestDiagnosticLogText(),
    );
    StreamTestRunResult result;
    try {
      result = await runner.run(
        streamTestRunConfig,
        gameCaptureTestTargetResult: captureTargetResult,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Stream test runner failed',
      );
      if (captureTargetSession != null) {
        onProgress?.call('stopping capture target...');
        captureTargetResult = await captureTargetSession.stopAndCollect();
      }
      StreamTestRunResult? failureResult;
      try {
        failureResult = await _writeStreamTestFailureReport(
          startedAt: runnerStartedAt,
          target: streamTestTarget,
          config: streamTestRunConfig,
          error: error,
          gameCaptureTestTargetResult: captureTargetResult,
        );
      } catch (reportError, reportStackTrace) {
        Log.onError(
          reportError,
          reportStackTrace,
          content: 'Failed to write stream test failure report',
        );
      }
      if (mounted) {
        final writeResult = _lastStreamTestReportWriteResult;
        if (writeResult != null &&
            writeResult.supported &&
            writeResult.error == null) {
          _showStreamTestSnackBar(
            'Stream test failed; '
            '${_streamTestReportExportLabel(writeResult)}.',
          );
        } else {
          _showStreamTestSnackBar(
            'Stream test failed. Call Diagnostics has details.',
          );
        }
      }
      return failureResult;
    }

    if (captureTargetSession != null) {
      onProgress?.call('stopping capture target...');
      captureTargetResult = await captureTargetSession.stopAndCollect();
      result = result.withGameCaptureTestTargetResult(captureTargetResult);
    }

    final writeResult = await const StreamTestReportWriter().write(result);
    _lastStreamTestReportWriteResult = writeResult;
    final exportLabel = _streamTestReportExportLabel(writeResult);
    final compactResultSummary = result.presetResults.map((presetResult) {
      final summary = presetResult.score.summary;
      return '${presetResult.resultLabel}: '
          'score=${presetResult.score.totalScore}, '
          '${summary.capturePipelineLabel}, '
          'bottleneck=${presetResult.score.bottleneck.label}';
    }).join('\n');
    Log.i(
      'Stream test runner completed\n'
      'Stream test report export: $exportLabel\n'
      'Preset results: ${result.presetResults.length}\n'
      '$compactResultSummary',
      category: LogCategory.webrtc,
      source: 'stream-test-runner',
    );

    if (!mounted) {
      return result;
    }

    if (writeResult.error != null || !writeResult.supported) {
      _showStreamTestSnackBar(
        'Stream test finished; report export failed. '
        'Call Diagnostics has details.',
      );
    } else {
      _showStreamTestSnackBar(
        'Stream test saved; ${_streamTestReportExportLabel(writeResult)}.',
      );
    }

    return result;
  }

  Future<ScreenCaptureSource?>
      _selectDummyNv12LiveSenderPlaceholderSource() async {
    if (!PlatformUtils.isWindows) {
      return null;
    }
    try {
      final source = await WebrtcScreencaptureSource.findAnyWindowPlaceholder(
        timeout: _streamTestAutoSelectTimeout,
      );
      if (source == null) {
        Log.i(
          'Stream test dummy NV12 live-sender found no window source '
          'placeholder',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        return null;
      }
      Log.i(
        'Stream test dummy NV12 live-sender using placeholder window '
        'sourceIdHash=${shortShareSourceIdHash(source.source.id)}',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      return source;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Stream test dummy NV12 live-sender placeholder selection '
            'failed',
      );
      return null;
    }
  }

  Future<StreamTestRunResult> _writeStreamTestFailureReport({
    required DateTime startedAt,
    required StreamTestTarget target,
    required StreamTestRunConfig config,
    required Object error,
    required GameCaptureTestTargetResult? gameCaptureTestTargetResult,
  }) async {
    final result = StreamTestRunResult.failure(
      startedAt: startedAt,
      endedAt: DateTime.now(),
      targetLabel: target.label,
      roomId: target.roomId,
      config: config,
      error: error.toString(),
      diagnosticLogText: await _streamTestDiagnosticLogText(),
      gameCaptureTestTargetResult: gameCaptureTestTargetResult,
    );
    final writeResult = await const StreamTestReportWriter().write(result);
    _lastStreamTestReportWriteResult = writeResult;
    Log.i(
      'Stream test runner failed; failure report export: '
      '${_streamTestReportExportLabel(writeResult)}',
      category: LogCategory.webrtc,
      source: 'stream-test-runner',
    );
    return result;
  }

  void _showStreamTestSnackBar(String message) {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = mounted ? ScaffoldMessenger.maybeOf(context) : null;
      if (!mounted || messenger == null || !messenger.mounted) {
        return;
      }
      if (Scaffold.maybeOf(context) == null) {
        return;
      }
      try {
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(message)));
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to show stream test snackbar',
        );
      }
    });
  }

  String _streamTestReportExportLabel(StreamTestReportWriteResult result) {
    if (!result.supported) {
      return 'unsupported platform';
    }
    if (result.error != null) {
      return 'export failed';
    }

    return streamTestReportExportDisplayLabel(
      markdownPath: result.markdownPath,
      jsonPath: result.jsonPath,
    );
  }

  StreamTestSourceMetadata _streamTestSourceMetadata(
    ScreenCaptureSource source,
  ) {
    if (source is ShareCaptureSource) {
      final summary = source.shareSession.diagnosticsSummary(
        includeTitle: preferences.developerMode.value &&
            preferences.showCallStreamStats.value,
      );
      return StreamTestSourceMetadata(
        sourceType: summary.sourceType.name,
        sourceIdHash: summary.sourceIdHash,
        processId: summary.processId,
        audioRequested: summary.audioRequested,
        audioMode: summary.audioMode.name,
        audioState: summary.audioState.name,
        audioReason: summary.audioReason,
        sourceTitle: summary.sourceTitle,
        sourceRuntimeType: source.videoSource.runtimeType.toString(),
      );
    }

    return StreamTestSourceMetadata(
      sourceType: source.runtimeType.toString(),
      sourceIdHash: 'unknown',
      sourceRuntimeType: source.runtimeType.toString(),
    );
  }

  Future<_StreamTestDialogConfig?> _showStreamTestConfigDialog() {
    final allPresets = [
      ScreenShareProfileConfig.forPreferenceKey(
        ScreenShareQualityProfile.smooth.storageKey,
        preferHardwareEncoding: PlatformUtils.isWindows &&
            preferences.streamHardwareEncodingFirst.value,
      ),
      ScreenShareProfileConfig.forPreferenceKey(
        ScreenShareQualityProfile.balanced.storageKey,
        preferHardwareEncoding: PlatformUtils.isWindows &&
            preferences.streamHardwareEncodingFirst.value,
      ),
      ScreenShareProfileConfig.forPreferenceKey(
        ScreenShareQualityProfile.highQuality.storageKey,
        preferHardwareEncoding: PlatformUtils.isWindows &&
            preferences.streamHardwareEncodingFirst.value,
      ),
    ];
    final selectedKeys =
        allPresets.map((profile) => profile.storageKey).toSet();
    var durationSeconds = 30;
    var warmupSeconds = 5;
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
    var compareWindowsBackends = false;
    var compareWindowGdiMethods = false;
    var forceFullFrameDirtyRegions = false;
    var nativeFramePacingEnabled = PlatformUtils.isWindows;
    var captureTestTargetEnabled = false;
    var captureTestTargetSize = '1920x1080';
    var captureTestTargetMode = 'windowed';
    var captureTestTargetScene = 'gameplay';
    var captureTestTargetFps = '60';
    var gameCaptureProbeEnabled = false;
    var gameCaptureProofFrames = 0;

    return showDialog<_StreamTestDialogConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedPresets = allPresets
                .where((profile) => selectedKeys.contains(profile.storageKey))
                .toList(growable: false);
            return AlertDialog(
              title: const Text('Stream Test Runner'),
              content: SizedBox(
                width: min(MediaQuery.sizeOf(context).width * 0.78, 520),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: min(
                      MediaQuery.sizeOf(context).height * 0.7,
                      620,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final profile in allPresets)
                          CheckboxListTile(
                            value: selectedKeys.contains(profile.storageKey),
                            title: Text(profile.label),
                            subtitle: Text(profile.description),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedKeys.add(profile.storageKey);
                                } else {
                                  selectedKeys.remove(profile.storageKey);
                                }
                              });
                            },
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Duration per preset'),
                            ),
                            DropdownButton<int>(
                              value: durationSeconds,
                              items: const [
                                DropdownMenuItem(
                                  value: 10,
                                  child: Text('10s'),
                                ),
                                DropdownMenuItem(
                                  value: 20,
                                  child: Text('20s'),
                                ),
                                DropdownMenuItem(
                                  value: 30,
                                  child: Text('30s'),
                                ),
                                DropdownMenuItem(
                                  value: 60,
                                  child: Text('60s'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() => durationSeconds = value);
                              },
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Warmup before sampling'),
                            ),
                            DropdownButton<int>(
                              value: warmupSeconds,
                              items: const [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('Off'),
                                ),
                                DropdownMenuItem(
                                  value: 3,
                                  child: Text('3s'),
                                ),
                                DropdownMenuItem(
                                  value: 5,
                                  child: Text('5s'),
                                ),
                                DropdownMenuItem(
                                  value: 10,
                                  child: Text('10s'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() => warmupSeconds = value);
                              },
                            ),
                          ],
                        ),
                        if (PlatformUtils.isWindows) ...[
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: compareWindowsBackends,
                            title: const Text('Compare Windows backends'),
                            subtitle: const Text(
                              'Runs each selected preset with app default, '
                              'native default, WGC only, and DirectX only. '
                              'Crop fallback is disabled in stream tests '
                              'because it can capture the wrong monitor or '
                              'crash on BG3.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => compareWindowsBackends = value ?? false,
                              );
                            },
                          ),
                          Row(
                            children: [
                              const Expanded(
                                child: Text('Windows capture backend'),
                              ),
                              DropdownButton<WindowsScreenCaptureBackendMode?>(
                                value: windowsCaptureBackendMode,
                                onChanged: compareWindowsBackends
                                    ? null
                                    : (value) {
                                        setDialogState(
                                          () =>
                                              windowsCaptureBackendMode = value,
                                        );
                                      },
                                items: [
                                  const DropdownMenuItem<
                                          WindowsScreenCaptureBackendMode?>(
                                      value: null, child: Text('App default')),
                                  for (final mode
                                      in streamTestWindowsCaptureBackendModes)
                                    DropdownMenuItem<
                                            WindowsScreenCaptureBackendMode?>(
                                        value: mode, child: Text(mode.label)),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            compareWindowsBackends
                                ? 'Comparison mode keeps the same source and '
                                    'cycles backend overrides for evidence, '
                                    'not as a global default change.'
                                : windowsCaptureBackendMode?.description ??
                                    'Uses the same backend as normal sharing: '
                                        'the patched native default with no '
                                        'debug override.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          CheckboxListTile(
                            value: compareWindowGdiMethods,
                            title: const Text('Compare window GDI methods'),
                            subtitle: const Text(
                              'Diagnostic only. For window sources on the '
                              'DirectX/window-GDI path, cycles current '
                              'PrintWindow, plain PrintWindow, BitBlt-first, '
                              'and BitBlt-only so reports can prove whether '
                              'the fast path is usable or just black.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => compareWindowGdiMethods = value ?? false,
                              );
                            },
                          ),
                          CheckboxListTile(
                            value: nativeFramePacingEnabled,
                            title: const Text('Enable latest-frame pacer'),
                            subtitle: const Text(
                              'Normal Windows default. Keeps the newest native '
                              'capture frame and submits it on the target '
                              'cadence; turn off only for A/B diagnostics.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => nativeFramePacingEnabled = value ?? false,
                              );
                            },
                          ),
                          CheckboxListTile(
                            value: captureTestTargetEnabled,
                            title: const Text('Launch D3D11 capture target'),
                            subtitle: const Text(
                              'Debug only. Starts a deterministic local D3D11 '
                              'window, auto-selects it when possible, and '
                              'adds its Present cadence to the stream-test '
                              'report. Use BG3 later for stress coverage.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => captureTestTargetEnabled = value ?? false,
                              );
                            },
                          ),
                          if (captureTestTargetEnabled) ...[
                            Row(
                              children: [
                                const Expanded(child: Text('Target size')),
                                DropdownButton<String>(
                                  value: captureTestTargetSize,
                                  items: const [
                                    DropdownMenuItem(
                                      value: '1920x1080',
                                      child: Text('1920x1080'),
                                    ),
                                    DropdownMenuItem(
                                      value: '2560x1440',
                                      child: Text('2560x1440'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => captureTestTargetSize = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Target mode')),
                                DropdownButton<String>(
                                  value: captureTestTargetMode,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'windowed',
                                      child: Text('Windowed'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'borderless',
                                      child: Text('Borderless'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => captureTestTargetMode = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Target scene')),
                                DropdownButton<String>(
                                  value: captureTestTargetScene,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'gameplay',
                                      child: Text('Gameplay'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'high-motion',
                                      child: Text('High motion'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'low-motion',
                                      child: Text('Low motion'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'ui-heavy',
                                      child: Text('UI heavy'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => captureTestTargetScene = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Target FPS')),
                                DropdownButton<String>(
                                  value: captureTestTargetFps,
                                  items: const [
                                    DropdownMenuItem(
                                      value: '30',
                                      child: Text('30'),
                                    ),
                                    DropdownMenuItem(
                                      value: '60',
                                      child: Text('60'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'uncapped',
                                      child: Text('Uncapped'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => captureTestTargetFps = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                          CheckboxListTile(
                            value: forceFullFrameDirtyRegions,
                            title: const Text('Force full-frame dirty regions'),
                            subtitle: const Text(
                              'Diagnostic only. Disables updated-region differ '
                              'wrappers where possible so the next report can '
                              'separate dirty-region starvation from native '
                              'capture acquisition stalls.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () =>
                                    forceFullFrameDirtyRegions = value ?? false,
                              );
                            },
                          ),
                          CheckboxListTile(
                            value: gameCaptureProbeEnabled,
                            title: const Text('Run D3D11 game probe'),
                            subtitle: const Text(
                              'Debug only. Attaches the local D3D11 Present '
                              'probe to the selected window process and writes '
                              'cadence metadata; it does not publish frames to '
                              'LiveKit.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => gameCaptureProbeEnabled = value ?? false,
                              );
                            },
                          ),
                          if (gameCaptureProbeEnabled)
                            Row(
                              children: [
                                const Expanded(
                                  child: Text('Game probe proof frames'),
                                ),
                                DropdownButton<int>(
                                  value: gameCaptureProofFrames,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 0,
                                      child: Text('Off'),
                                    ),
                                    DropdownMenuItem(
                                      value: 5,
                                      child: Text('5 frames'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => gameCaptureProofFrames = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedPresets.isEmpty
                      ? null
                      : () {
                          final targetSizeParts =
                              captureTestTargetSize.split('x');
                          final targetWidth =
                              int.tryParse(targetSizeParts.first) ?? 1920;
                          final targetHeight = targetSizeParts.length > 1
                              ? int.tryParse(targetSizeParts[1]) ?? 1080
                              : 1080;
                          Navigator.of(dialogContext).pop(
                            _StreamTestDialogConfig(
                              presets: selectedPresets,
                              duration: Duration(seconds: durationSeconds),
                              warmup: Duration(seconds: warmupSeconds),
                              windowsCaptureBackendMode: PlatformUtils.isWindows
                                  ? windowsCaptureBackendMode
                                  : null,
                              windowsCaptureBackendModes: PlatformUtils
                                          .isWindows &&
                                      compareWindowsBackends
                                  ? _streamTestWindowsCaptureBackendCompareModes
                                  : null,
                              windowsCaptureDirtyRegionMode: PlatformUtils
                                          .isWindows &&
                                      forceFullFrameDirtyRegions
                                  ? WindowsScreenCaptureDirtyRegionMode
                                      .forceFullFrame
                                  : WindowsScreenCaptureDirtyRegionMode.auto,
                              windowsWindowGdiCaptureModes:
                                  PlatformUtils.isWindows &&
                                          compareWindowGdiMethods
                                      ? streamTestWindowsWindowGdiCaptureModes
                                      : null,
                              nativeFramePacingEnabled:
                                  PlatformUtils.isWindows &&
                                      nativeFramePacingEnabled,
                              captureTestTargetEnabled:
                                  PlatformUtils.isWindows &&
                                      captureTestTargetEnabled,
                              captureTestTargetWidth: targetWidth,
                              captureTestTargetHeight: targetHeight,
                              captureTestTargetMode: captureTestTargetMode,
                              captureTestTargetScene: captureTestTargetScene,
                              captureTestTargetFps: captureTestTargetFps,
                              gameCaptureProbeEnabled:
                                  PlatformUtils.isWindows &&
                                      gameCaptureProbeEnabled,
                              gameCaptureProofFrames: PlatformUtils.isWindows
                                  ? gameCaptureProofFrames
                                  : 0,
                            ),
                          );
                        },
                  child: const Text('Run'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveCallDiagnosticsLog(List<String> lines) async {
    try {
      final data = _redactCallDiagnosticText(lines.join('\n'));
      final bytes = Uint8List.fromList(utf8.encode(data));
      final fileName =
          'inter-galactic-call-diagnostics-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.txt';
      String? destinationPath;

      if (kIsWeb || PlatformUtils.isAndroid || PlatformUtils.isIOS) {
        destinationPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          bytes: bytes,
        );
      } else {
        destinationPath = await FilePicker.platform.saveFile(
          fileName: fileName,
        );
        if (destinationPath != null) {
          await writeLocalFileBytes(destinationPath, bytes);
        }
      }

      if (!mounted || destinationPath == null) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(savedCallDiagnosticsDisplayMessage(destinationPath)),
        ),
      );
    } catch (error, trace) {
      Log.onError(error, trace, content: 'Failed to save call diagnostics');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Failed to save call diagnostics')),
        );
      }
    }
  }

  Widget _diagnosticLogTab(List<String> lines) {
    final text = _redactCallDiagnosticText(lines.join('\n'));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.3),
        ),
      ),
    );
  }

  Widget _streamTestProgressBanner() {
    final theme = Theme.of(context);
    final progress = _streamTestProgressLabel ?? 'preparing...';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Running: $progress',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rnnoiseDiagnosticCaptureBanner({
    required bool busy,
    required bool running,
    required String? message,
  }) {
    final theme = Theme.of(context);
    final directoryPath =
        NoiseSuppressionService.instance.diagnosticCaptureDirectoryPath;
    final statusText = message ??
        (running
            ? 'Capturing 10 seconds of local RNNoise WAV stages.'
            : 'RNNoise WAV capture is ready.');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (busy || running) ...[
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ] else ...[
              Icon(
                Icons.multitrack_audio_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                [
                  statusText,
                  'Local-only. WAV bug-report submission is disabled.',
                  if (directoryPath != null)
                    rnnoiseDiagnosticFolderDisplayLine(directoryPath),
                ].join('\n'),
                style: theme.textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collapsedCallDiagnosticsSummary() {
    final textTheme = Theme.of(context).textTheme;
    final report = _lastStreamTestReportWriteResult;
    final testResult = _lastStreamTestResult;
    final streamTestStatus = _streamTestRunning
        ? 'Stream test: ${_streamTestProgressLabel ?? 'running...'}'
        : testResult == null
            ? 'Stream test: ready'
            : 'Stream test: ${testResult.presetResults.length} presets complete';
    final reportStatus = report == null
        ? 'Report: not saved in this dialog'
        : 'Report: ${_streamTestReportExportLabel(report)}';

    return SizedBox(
      width: min(MediaQuery.sizeOf(context).width * 0.32, 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            streamTestStatus,
            style: textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            reportStatus,
            style: textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  List<String> _callDiagnosticsSummaryLines() {
    final session = widget.currentSession;
    final shareSession = session.currentShareSession;
    final noiseSuppressionService = NoiseSuppressionService.instance;
    final noiseStatus = noiseSuppressionService.status;
    final livekitSession = session is MatrixLivekitVoipSession ? session : null;
    final snapshot = session.diagnosticsSnapshot;
    final streamCounts = <VoipStreamType, int>{};
    for (final stream in session.streams) {
      streamCounts.update(stream.type, (count) => count + 1, ifAbsent: () => 1);
    }
    final participantAudioMutedOverrideCount = _participantAudioVolumeOverrides
        .values
        .where((volume) => volume == 0.0)
        .length;
    final activeStreamTestPrefix =
        _streamTestRunning ? '${_streamTestProgressLabel ?? 'running'}; ' : '';
    final developerStatsOverlayState = !preferences.showCallStreamStats.value
        ? 'off'
        : _diagnosticsOverlayVisible
            ? 'shown'
            : 'hidden locally';

    return <String>[
      'Room: ${session.roomName} (${session.roomId})',
      'State: ${session.state.name}',
      'Session: ${session.sessionId.isEmpty ? 'none' : session.sessionId}',
      'Mic muted: ${session.isMicrophoneMuted}',
      'Camera enabled: ${session.isCameraEnabled}',
      'Sharing screen: ${session.isSharingScreen}',
      'Streams: total=${session.streams.length} '
          'audio=${streamCounts[VoipStreamType.audio] ?? 0} '
          'cam=${streamCounts[VoipStreamType.video] ?? 0} '
          'share=${streamCounts[VoipStreamType.screenshare] ?? 0}',
      'Local participant audio overrides: '
          'participants=${_participantAudioVolumeOverrides.length} '
          'muted=$participantAudioMutedOverrideCount',
      'Developer stats overlay: $developerStatsOverlayState',
      'Profile: ${snapshot.screenShareProfileLabel}',
      if (snapshot.screenShareProfileDetails != null)
        'Profile details: ${snapshot.screenShareProfileDetails}',
      'ICE: ${snapshot.iceTransportSummary ?? 'unknown'}',
      if (livekitSession != null)
        'Server loopback: ${livekitSession.serverAudioLoopbackDiagnosticLabel}',
      if (_lastStreamTestResult == null)
        _streamTestRunning
            ? 'Stream test runner: running '
                '${_streamTestProgressLabel ?? 'unknown preset/backend'}'
            : 'Stream test runner: no run in this diagnostics session'
      else
        'Stream test runner: '
            '$activeStreamTestPrefix'
            '${_lastStreamTestResult!.presetResults.length} presets '
            'last scores=${_lastStreamTestResult!.presetResults.map((result) => '${result.profile.label}:${result.score.totalScore}').join(', ')}',
      if (_lastStreamTestReportWriteResult != null)
        'Stream test report: '
            '${_streamTestReportExportLabel(_lastStreamTestReportWriteResult!)}',
      'RNNoise: reason=${noiseStatus.reason} '
          'available=${noiseStatus.available} '
          'enabled=${noiseStatus.enabled} '
          'active=${noiseStatus.active} '
          'frames=${noiseStatus.framesProcessed} '
          'bypass=${noiseStatus.bypassFrames} '
          'gated=${noiseStatus.gatedFrames} '
          'vad=${noiseStatus.lastVadProbability.toStringAsFixed(2)} '
          'ratio=${noiseStatus.lastOutputRatio.toStringAsFixed(2)} '
          'formatMismatch=${noiseStatus.formatMismatchDetected} '
          'suspicious=${noiseStatus.suspiciousOutputDetected}',
      ...noiseSuppressionService.diagnosticsLines(),
      ..._soundboardSummaryLines(session),
      if (shareSession == null)
        'Share audio: no active share session'
      else
        ..._shareSessionSummaryLines(shareSession),
    ];
  }

  List<String> _soundboardSummaryLines(VoipSession session) {
    final client = session.client;
    if (client is! MatrixClient) {
      return const ['Soundboard: unavailable (non-Matrix client)'];
    }

    final room = client.getRoom(session.roomId);
    if (room is! MatrixRoom) {
      return const ['Soundboard: unavailable (call room not loaded)'];
    }

    MatrixSpace? callSpace;
    for (final space in client.spaces.whereType<MatrixSpace>()) {
      if (space.identifier == room.identifier ||
          space.roomsWithChildren.any(
            (candidate) => candidate.identifier == room.identifier,
          )) {
        callSpace = space;
        break;
      }
    }

    final soundboard = callSpace?.getComponent<SoundboardComponent>();
    if (callSpace == null || soundboard == null) {
      return const ['Soundboard: unavailable (no containing space)'];
    }

    return <String>[
      'Soundboard: space=${callSpace.displayName} sounds=${soundboard.sounds.length} '
          'canUpload=${soundboard.canUploadSound} '
          'memberUploads=${soundboard.memberUploadsEnabled} '
          'canManageUploads=${soundboard.canEnableMemberUploads} '
          'activeCallMatch=${soundboardPlaybackService.hasActiveSessionForRoom(client, room)} '
          'deafened=${soundboardPlaybackService.isDeafened} '
          'localVolume=${preferences.soundboardVolume.value.toStringAsFixed(0)}%',
      'Soundboard upload power: required=${soundboard.soundUploadPowerLevel} '
          'defaultUser=${soundboard.defaultUserPowerLevel} '
          'currentUser=${soundboard.currentUserPowerLevel}',
    ];
  }

  List<String> _shareSessionSummaryLines(ShareSession shareSession) {
    final status = shareSession.sharedAudioStatus;
    final summary = shareSession.diagnosticsSummary(
      includeTitle: preferences.developerMode.value &&
          preferences.showCallStreamStats.value,
    );
    return <String>[
      ...summary.lines(),
      'Share audio format: ${status.sampleRateHz}Hz '
          '${status.numChannels}ch ${status.bitsPerSample}bit '
          'packets=${status.packetsCaptured} '
          'frames=${status.framesCaptured} bytes=${status.bytesCaptured} '
          'pcmBridge=${status.pcmBridgeSupported}',
      'Mic source: enabled=${shareSession.micSource.enabled} '
          'rnnoise=${shareSession.micSource.rnnoiseApplies}',
    ];
  }

  List<String> _relatedCallLogLines() {
    final roomId = widget.currentSession.roomId.toLowerCase();
    final sessionId = widget.currentSession.sessionId.toLowerCase();
    final entries = Log.log.reversed
        .where((entry) {
          final content = _normalizeLogSearchText(entry.content);
          return (roomId.isNotEmpty && content.contains(roomId)) ||
              (sessionId.isNotEmpty && content.contains(sessionId)) ||
              _callLogKeywords.any(
                (keyword) => _matchesCallLogKeyword(content, keyword),
              );
        })
        .take(180)
        .toList(growable: false)
        .reversed;

    final lines = <String>[];
    for (final entry in entries) {
      lines.add(_formatLogEntryForMenu(entry));
    }

    return lines.isEmpty ? ['No related Log entries yet.'] : lines;
  }

  static const List<String> _callLogKeywords = [
    'livekit',
    'matrixrtc',
    'call',
    'voip',
    'webrtc',
    'screen share',
    'screenshare',
    'stream',
    'rnnoise',
    'noise suppression',
    'soundboard',
    'media kit',
    'media_kit',
    'mxc',
    'forbidden',
    'permission',
    'shared-content audio',
    'share audio',
    'sharesession',
    'sfu',
    'ice',
    'turn',
    'microphone',
    'audio loopback',
    'getdisplaymedia',
    'capture',
    'encoder',
    'bitrate',
  ];

  bool _matchesCallLogKeyword(String content, String keyword) {
    final contentTokens = _logSearchTokens(content);
    final keywordTokens = _logSearchTokens(keyword);
    if (contentTokens.length < keywordTokens.length || keywordTokens.isEmpty) {
      return false;
    }

    for (var index = 0;
        index <= contentTokens.length - keywordTokens.length;
        index++) {
      var matches = true;
      for (var keywordIndex = 0;
          keywordIndex < keywordTokens.length;
          keywordIndex++) {
        if (contentTokens[index + keywordIndex] !=
            keywordTokens[keywordIndex]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }

    return false;
  }

  String _formatLogEntryForMenu(LogEntry entry) {
    final buffer = StringBuffer()
      ..writeln(
        '[${entry.time.toUtc().toIso8601String()}] '
        '${entry.type.name.toUpperCase()} x${entry.count}',
      )
      ..writeln(_cleanLogText(entry.content).trim());

    final trace = entry is LogEntryException && entry.trace != null
        ? _cleanLogText(entry.trace.toString()).trim()
        : null;
    if (trace != null && trace.isNotEmpty) {
      buffer
        ..writeln('Stack Trace:')
        ..writeln(trace);
    }

    return buffer.toString().trimRight();
  }

  String _normalizeLogSearchText(String value) {
    return _cleanLogText(value).toLowerCase();
  }

  String _cleanLogText(String value) {
    return value.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }

  String _redactCallDiagnosticText(String value) {
    var redacted = Log.redactSensitiveInfo(value);
    final buildDetails = <String>{
      BuildConfig.forkDeveloper,
      BuildConfig.BUILD_DETAIL.trim(),
      BuildConfig.buildDetailDisplay.trim(),
    }..removeWhere((detail) => detail.isEmpty || detail == 'default');
    for (final detail in buildDetails) {
      redacted = redacted.replaceAll(detail, '[BUILD_DETAIL]');
    }
    return redacted;
  }

  List<String> _redactCallDiagnosticLines(Iterable<String> lines) {
    return _redactCallDiagnosticText(lines.join('\n')).split('\n');
  }

  List<String> _logSearchTokens(String value) {
    return _normalizeLogSearchText(value)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  String _participantDiagnosticLine(VoipParticipantDiagnostics participant) {
    return '${_redactCallDiagnosticText(participant.userId)}: '
        '${_redactCallDiagnosticText(participant.clientLabel)}';
  }

  String _diagnosticLine(VoipTrackDiagnostics track) {
    final direction = track.direction == VoipDiagnosticsTrackDirection.sender
        ? 'send'
        : 'recv';
    final type = switch (track.type) {
      VoipStreamType.audio => 'audio',
      VoipStreamType.video => 'cam',
      VoipStreamType.screenshare => 'share',
    };
    final priority = track.receivePriority == null
        ? ''
        : ' ${track.receivePriority!.name.toUpperCase()}';
    final codec = track.codec == null ? '' : ' ${track.codec}';
    final limitation = track.qualityLimitationReason == null ||
            track.qualityLimitationReason == 'none'
        ? ''
        : ' webrtc_limit:${track.qualityLimitationReason}';
    final engine = track.encoderImplementation ?? track.decoderImplementation;
    final hardware = track.hardwareEncodeActive == null
        ? ''
        : ' hw:${track.hardwareEncodeActive! ? 'yes' : 'no'}';
    final stageSize = track.direction == VoipDiagnosticsTrackDirection.sender
        ? _formatSenderStageSize(track)
        : _formatReceiverStageSize(track);
    return '$direction $type$priority '
        '${_formatRequestedMedia(track)}'
        '${track.resolutionLabel}$stageSize '
        '${_formatFps(track.fps)} '
        '${_formatFpsBreakdown(track)}'
        '${_formatBitrate(track.bitrateBps)}'
        '${_formatTargetBitrate(track)}$codec'
        '${_formatLoss(track.packetLossPercent)}'
        '${_formatPacketCounts(track)}'
        '${_formatJitter(track.jitterMs)}'
        '${_formatMs("rtt", track.roundTripTimeMs)}'
        '${_formatMs("jbuf", track.jitterBufferDelayMs)}'
        '${_formatMs("enc", track.averageEncodeTimeMs)}'
        '${_formatMs("dec", track.averageDecodeTimeMs)}'
        '${_formatLayer(track)}'
        '${_formatCount("sent", track.framesSent)}'
        '${_formatCount("cap", track.framesCaptured)}'
        '${_formatCount("encd", track.framesEncoded)}'
        '${_formatCount("recv", track.framesReceived)}'
        '${_formatCount("drop", track.framesDropped)}'
        '${_formatCount("dropPre", track.framesDroppedBeforeEncode)}'
        '${_formatCount("dropEnc", track.framesDroppedByEncoder)}'
        '${_formatCount("dec", track.framesDecoded)}'
        '${_formatCount("rend", track.framesRendered)}'
        '${_formatCount("nack", track.nackCount)}'
        '${_formatCount("pli", track.pliCount)}'
        '${_formatCount("fir", track.firCount)}'
        '${_formatCount("freeze", track.freezeCount)}'
        '${_formatResolutionMismatch(track)}'
        '${engine == null ? "" : " $engine"}$hardware'
        '$limitation';
  }

  String _formatRequestedMedia(VoipTrackDiagnostics track) {
    if (track.requestedWidth == null && track.requestedHeight == null) {
      return '';
    }
    return 'req:${track.requestedWidth ?? '?'}x${track.requestedHeight ?? '?'} '
        '${_formatFps(track.requestedFps)} '
        '${_formatBitrate(track.requestedBitrateBps)} -> ';
  }

  String _formatSenderStageSize(VoipTrackDiagnostics track) {
    final parts = <String>[
      if (track.preEncodeResolutionLabel != 'unknown')
        'pre:${track.preEncodeResolutionLabel}',
      if (track.resolutionLabel != 'unknown') 'enc:${track.resolutionLabel}',
    ];
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }

  String _formatReceiverStageSize(VoipTrackDiagnostics track) {
    if (track.resolutionLabel == 'unknown') {
      return '';
    }
    return ' recv:${track.resolutionLabel}';
  }

  String _formatResolutionMismatch(VoipTrackDiagnostics track) {
    if (track.direction != VoipDiagnosticsTrackDirection.sender ||
        track.requestedWidth == null ||
        track.requestedHeight == null ||
        track.width == null ||
        track.height == null ||
        track.requestedWidth! <= 0 ||
        track.requestedHeight! <= 0 ||
        track.width! <= 0 ||
        track.height! <= 0) {
      return '';
    }

    final encodedTooWide = track.width! > track.requestedWidth! + 32 &&
        track.width! > track.requestedWidth! * 1.1;
    final encodedTooTall = track.height! > track.requestedHeight! + 18 &&
        track.height! > track.requestedHeight! * 1.1;
    if (!encodedTooWide && !encodedTooTall) {
      return '';
    }

    return ' mismatch:req${track.requestedWidth}x${track.requestedHeight}'
        '/enc${track.width}x${track.height}';
  }

  String _formatFpsBreakdown(VoipTrackDiagnostics track) {
    final parts = <String>[
      if (track.captureFps != null)
        'capfps:${track.captureFps!.toStringAsFixed(0)}',
      if (track.direction == VoipDiagnosticsTrackDirection.sender &&
          track.captureFps != null)
        'prefps:${track.captureFps!.toStringAsFixed(0)}',
      if (track.encodeFps != null)
        'encfps:${track.encodeFps!.toStringAsFixed(0)}',
      if (track.sendFps != null) 'sendfps:${track.sendFps!.toStringAsFixed(0)}',
      if (track.decodeFps != null)
        'decfps:${track.decodeFps!.toStringAsFixed(0)}',
      if (track.renderFps != null)
        'rendfps:${track.renderFps!.toStringAsFixed(0)}',
    ];
    return parts.isEmpty ? '' : '${parts.join(' ')} ';
  }

  String _formatTargetBitrate(VoipTrackDiagnostics track) {
    final parts = <String>[
      if (track.targetBitrateBps != null)
        'target:${_formatBitrateValue(track.targetBitrateBps)}',
      if (track.availableOutgoingBitrateBps != null)
        'availOut:${_formatBitrateValue(track.availableOutgoingBitrateBps)}',
      if (track.availableIncomingBitrateBps != null)
        'availIn:${_formatBitrateValue(track.availableIncomingBitrateBps)}',
      if (track.retransmitBitrateBps != null)
        'reTx:${_formatBitrateValue(track.retransmitBitrateBps)}',
    ];
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }

  String _formatPacketCounts(VoipTrackDiagnostics track) {
    final parts = <String>[
      if (track.packetsSent != null) 'pkts:${track.packetsSent}',
      if (track.packetsReceived != null) 'pktr:${track.packetsReceived}',
      if (track.packetsLost != null) 'pktlost:${track.packetsLost}',
    ];
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }

  String _formatLayer(VoipTrackDiagnostics track) {
    final layer = track.activeLayer ?? track.rid;
    return layer == null ? '' : ' layer:$layer';
  }

  String _formatFps(double? fps) {
    if (fps == null || fps <= 0) {
      return 'fps:?';
    }
    return 'fps:${fps.toStringAsFixed(0)}';
  }

  String _formatBitrate(int? bitrateBps) {
    if (bitrateBps == null || bitrateBps <= 0) {
      return 'rate:?';
    }
    return 'rate:${_formatBitrateValue(bitrateBps)}';
  }

  String _formatBitrateValue(int? bitrateBps) {
    if (bitrateBps == null || bitrateBps <= 0) {
      return '?';
    }
    if (bitrateBps >= 1000000) {
      return '${(bitrateBps / 1000000).toStringAsFixed(1)}Mbps';
    }
    return '${(bitrateBps / 1000).toStringAsFixed(0)}kbps';
  }

  String _formatLoss(double? loss) {
    if (loss == null) {
      return '';
    }
    return ' loss:${loss.toStringAsFixed(1)}%';
  }

  String _formatJitter(double? jitterMs) {
    if (jitterMs == null) {
      return '';
    }
    return ' jitter:${jitterMs.toStringAsFixed(0)}ms';
  }

  String _formatMs(String label, double? value) {
    if (value == null) {
      return '';
    }
    return ' $label:${value.toStringAsFixed(0)}ms';
  }

  String _formatCount(String label, int? value) {
    if (value == null) {
      return '';
    }
    return ' $label:$value';
  }

  Widget buildFocusedTile(_CallTileData tile, int tileCount) {
    final remote = !isLocalTile(tile);
    final volumeTarget = _preparedVolumeTargetForTile(tile);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: SizedBox.expand(
        key: ValueKey("focused_call_tile_${tile.tileId}"),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: VoipStreamView(
            key: ValueKey("call_stage_${tile.tileId}"),
            tile.primaryStream,
            widget.currentSession,
            fit: tile.isScreenshare ? BoxFit.contain : BoxFit.cover,
            isFocused: true,
            isMicrophoneMuted: tile.audioStream?.isMuted ?? false,
            isVideoHidden: _isTileVideoHidden(tile),
            borderColor: Theme.of(context).colorScheme.primary.withAlpha(180),
            onTap: tileCount > 1 ? showEqualLayout : null,
            onPopout: BuildConfig.DESKTOP && widget.showSessionPopoutButton
                ? () => popOutTile(tile)
                : null,
            volumeStream: volumeTarget,
            defaultVolume: _defaultParticipantAudioVolume,
            onFullscreen: () {
              showFullscreenTile(tile);
            },
            onVolumeChanged: remote && volumeTarget != null
                ? (vol) => _setTileVolume(tile, vol)
                : null,
            onRemoveFromCall: remote && _canRemoveParticipants
                ? () => _removeParticipantFromCall(tile)
                : null,
            onVisibilityToggle: tile.isScreenshare && remote
                ? () => _toggleScreenshareVisibility(tile)
                : null,
            onHideToggle: () => _toggleTileHidden(tile),
          ),
        ),
      ),
    );
  }

  Widget buildEqualTileGrid(List<_CallTileData> tiles) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.transparentBackground
            ? Colors.transparent
            : const Color(0xFF111214),
        borderRadius: BorderRadius.circular(
          widget.transparentBackground ? 0 : 24,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          return Padding(
            padding: _callTileAreaPadding(outerConstraints),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final spacing = Layout.mobile ? 8.0 : 12.0;
                final columns = calculateBestGridColumns(
                  itemCount: tiles.length,
                  maxWidth: constraints.maxWidth,
                  maxHeight: constraints.maxHeight,
                );

                return GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tiles.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: calculateGridAspectRatio(
                      columns,
                      tiles.length,
                      constraints,
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final tile = tiles[index];
                    final remote = !isLocalTile(tile);
                    final volumeTarget = _preparedVolumeTargetForTile(tile);
                    return VoipStreamView(
                      key: ValueKey("call_grid_${tile.tileId}"),
                      tile.primaryStream,
                      widget.currentSession,
                      fit: tile.isScreenshare ? BoxFit.contain : BoxFit.cover,
                      isFocused: false,
                      isMicrophoneMuted: tile.audioStream?.isMuted ?? false,
                      isVideoHidden: _isTileVideoHidden(tile),
                      onTap: () => focusTile(tile),
                      onPopout:
                          BuildConfig.DESKTOP && widget.showSessionPopoutButton
                              ? () => popOutTile(tile)
                              : null,
                      volumeStream: volumeTarget,
                      defaultVolume: _defaultParticipantAudioVolume,
                      onFullscreen: () {
                        showFullscreenTile(tile);
                      },
                      onVolumeChanged: remote && volumeTarget != null
                          ? (vol) => _setTileVolume(tile, vol)
                          : null,
                      onRemoveFromCall: remote && _canRemoveParticipants
                          ? () => _removeParticipantFromCall(tile)
                          : null,
                      onVisibilityToggle: tile.isScreenshare && remote
                          ? () => _toggleScreenshareVisibility(tile)
                          : null,
                      onHideToggle: () => _toggleTileHidden(tile),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget buildTileRail(List<_CallTileData> tiles, BoxConstraints constraints) {
    final spacing = Layout.mobile ? 8.0 : 12.0;
    const double aspectRatio = 16.0 / 9.0;
    final tileHeight = _tileRailHeight(constraints);
    final tileWidth = tileHeight * aspectRatio;

    return SizedBox(
      height: tileHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (context, index) {
          final tile = tiles[index];
          final remote = !isLocalTile(tile);
          final volumeTarget = _preparedVolumeTargetForTile(tile);
          return SizedBox(
            width: tileWidth,
            height: tileHeight,
            child: VoipStreamView(
              key: ValueKey("call_rail_${tile.tileId}"),
              tile.primaryStream,
              widget.currentSession,
              fit: tile.isScreenshare ? BoxFit.contain : BoxFit.cover,
              isFocused: false,
              isMicrophoneMuted: tile.audioStream?.isMuted ?? false,
              isVideoHidden: _isTileVideoHidden(tile),
              onTap: () => focusTile(tile),
              onPopout: BuildConfig.DESKTOP && widget.showSessionPopoutButton
                  ? () => popOutTile(tile)
                  : null,
              volumeStream: volumeTarget,
              defaultVolume: _defaultParticipantAudioVolume,
              onFullscreen: () {
                showFullscreenTile(tile);
              },
              onVolumeChanged: remote && volumeTarget != null
                  ? (vol) => _setTileVolume(tile, vol)
                  : null,
              onRemoveFromCall: remote && _canRemoveParticipants
                  ? () => _removeParticipantFromCall(tile)
                  : null,
              onVisibilityToggle: tile.isScreenshare && remote
                  ? () => _toggleScreenshareVisibility(tile)
                  : null,
              onHideToggle: () => _toggleTileHidden(tile),
            ),
          );
        },
      ),
    );
  }

  EdgeInsets _callTileAreaPadding(BoxConstraints constraints) {
    final compactWidth = constraints.maxWidth.isFinite &&
        constraints.maxWidth < (Layout.mobile ? 360 : 440);
    final compactHeight = constraints.maxHeight.isFinite &&
        constraints.maxHeight < (Layout.mobile ? 320 : 360);
    final horizontal = compactWidth ? 8.0 : 16.0;
    final top = compactHeight ? 8.0 : 16.0;
    final bottom = _callControlsReservedInset(constraints.maxHeight);

    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  double _callControlsReservedInset(double maxHeight) {
    const defaultInset = 72.0;
    if (!maxHeight.isFinite) {
      return defaultInset;
    }

    return max(36.0, min(defaultInset, maxHeight * 0.2));
  }

  double _tileRailHeight(BoxConstraints constraints) {
    final defaultHeight = Layout.mobile ? 80.0 : 100.0;
    if (!constraints.maxHeight.isFinite) {
      return defaultHeight;
    }

    return max(56.0, min(defaultHeight, constraints.maxHeight * 0.28));
  }

  bool _isScreenShareAudioStream(VoipStream stream) {
    return stream is MatrixLivekitVoipStream && stream.isScreenShareAudio;
  }

  bool _isMicrophoneAudioStream(VoipStream stream) {
    return stream.type == VoipStreamType.audio &&
        (stream is! MatrixLivekitVoipStream || stream.isMicrophoneAudio);
  }

  VoipStream? _findScreenshareAudioStream(VoipStream screenshareStream) {
    return widget.currentSession.streams.tryFirstWhere(
      (stream) =>
          stream.streamUserId == screenshareStream.streamUserId &&
          _isScreenShareAudioStream(stream),
    );
  }

  List<_CallTileData> buildVisibleTiles() {
    _syncLocalScreenshareAutoHideTimers();

    final participantStreams = <String, List<VoipStream>>{};
    final tiles = <_CallTileData>[];

    // Build the set of Matrix user IDs that are still active call members.
    // If the LiveKit SFU hasn't disconnected a removed user yet, we hide
    // their tiles so the call view stays consistent with the participant list.
    final activeParticipants =
        _voipRoomComponent?.getCurrentParticipants().toSet();
    final localUserId = widget.currentSession.client.self?.identifier;
    final shouldFilterByMembership = activeParticipants != null;

    for (final stream in widget.currentSession.streams) {
      if (_isServerLoopbackStream(stream)) {
        continue;
      }

      if (BuildConfig.DESKTOP &&
          callPopoutController.isStreamPoppedOut(
            widget.currentSession.sessionId,
            _tileIdForStream(stream),
          )) {
        continue;
      }

      // Skip streams from users who have been removed from the call, but
      // always keep the local user's own streams visible.
      if (shouldFilterByMembership &&
          stream.streamUserId != localUserId &&
          !activeParticipants.contains(stream.streamUserId)) {
        continue;
      }

      if (stream.type == VoipStreamType.screenshare) {
        // Always add screenshare tiles to the list; visibility is controlled
        // by isVideoHidden via _isTileVideoHidden().  Remote screenshares
        // default to hidden (blank panel) until the user taps the eye-toggle.
        final audioStream = _findScreenshareAudioStream(stream);
        if (audioStream is MatrixLivekitVoipStream) {
          _restoreScreenshareAudioVolume(audioStream);
        }
        tiles.add(
          _CallTileData(
            primaryStream: stream,
            tileId: _tileIdForStream(stream),
            audioStream: audioStream,
            volumeStream: audioStream,
          ),
        );
        continue;
      }

      if (_isScreenShareAudioStream(stream)) {
        continue;
      }

      participantStreams.putIfAbsent(stream.streamUserId, () => []).add(stream);
    }

    for (final entry in participantStreams.entries) {
      final audioStream = entry.value.tryFirstWhere(_isMicrophoneAudioStream);
      // Always prefer video as the primary stream; VoipStreamView renders a
      // blank dark panel when isVideoHidden is true rather than switching tile
      // type.  No VideoTrackRenderer is created when hidden, so LiveKit's
      // adaptiveStream naturally pauses/reduces the inbound video track.
      final primaryStream = entry.value.tryFirstWhere(
            (stream) => stream.type == VoipStreamType.video,
          ) ??
          audioStream;

      if (primaryStream == null) {
        continue;
      }

      tiles.add(
        _CallTileData(
          primaryStream: primaryStream,
          tileId: _tileIdForStream(primaryStream),
          audioStream: audioStream,
          volumeStream: audioStream,
        ),
      );
    }

    tiles.sort(
      (a, b) => streamSortPriority(a).compareTo(streamSortPriority(b)),
    );
    return tiles;
  }

  void focusTile(_CallTileData tile) {
    setState(() {
      focusedTileId = tile.tileId;
      showEqualTileLayout = false;
    });
  }

  int calculateBestGridColumns({
    required int itemCount,
    required double maxWidth,
    required double maxHeight,
  }) {
    const targetAspect = 16.0 / 9.0;
    var bestColumns = 1;
    var bestScore = double.infinity;

    for (var columns = 1; columns <= itemCount; columns++) {
      final rows = (itemCount / columns).ceil();
      final tileWidth = maxWidth / columns;
      final tileHeight = maxHeight / rows;
      if (tileHeight <= 0) continue;
      final aspect = tileWidth / tileHeight;
      final score = (aspect - targetAspect).abs();

      if (score < bestScore) {
        bestScore = score;
        bestColumns = columns;
      }
    }

    return bestColumns;
  }

  double calculateGridAspectRatio(
    int columns,
    int itemCount,
    BoxConstraints constraints,
  ) {
    final rows = (itemCount / columns).ceil();
    final spacing = Layout.mobile ? 8.0 : 12.0;
    final width = (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
    final height = (constraints.maxHeight - ((rows - 1) * spacing)) / rows;

    if (height <= 0) {
      return 16 / 9;
    }

    return width / height;
  }

  void showEqualLayout() {
    setState(() {
      focusedTileId = null;
      showEqualTileLayout = true;
    });
  }

  void popOutTile(_CallTileData tile) {
    unawaited(
      tile.primaryStream.setReceivePriority(VoipStreamReceivePriority.high),
    );
    callPopoutController.popOutStream(
      widget.currentSession.sessionId,
      tile.tileId,
    );

    setState(() {
      if (focusedTileId == tile.tileId) {
        focusedTileId = null;
      }
      showEqualTileLayout = false;
    });
  }

  void showFullscreenTile(_CallTileData tile) {
    unawaited(
      tile.primaryStream.setReceivePriority(VoipStreamReceivePriority.high),
    );
    unawaited(
      showVoipStreamFullscreen(
        context,
        session: widget.currentSession,
        stream: tile.primaryStream,
      ),
    );
  }

  _CallTileData? resolveFocusedTile(List<_CallTileData> tiles) {
    if (tiles.isEmpty) {
      return null;
    }

    if (focusedTileId != null) {
      final current = tiles.tryFirstWhere(
        (tile) => tile.tileId == focusedTileId,
      );
      if (current != null && !_isTileVideoHidden(current)) {
        return current;
      }
    }

    return tiles.tryFirstWhere(
          (tile) => tile.isScreenshare && !_isTileVideoHidden(tile),
        ) ??
        tiles.tryFirstWhere(
          (tile) =>
              tile.hasVisual && !isLocalTile(tile) && !_isTileVideoHidden(tile),
        ) ??
        tiles.tryFirstWhere((tile) => !_isTileVideoHidden(tile)) ??
        tiles.first;
  }

  int streamSortPriority(_CallTileData tile) {
    var priority = 0;

    if (tile.isScreenshare) {
      priority -= 20;
    } else if (tile.hasVisual) {
      priority -= 10;
    }

    if (isLocalTile(tile)) {
      priority += 5;
    }

    return priority;
  }

  bool isLocalTile(_CallTileData tile) {
    return tile.userId == widget.currentSession.client.self?.identifier;
  }

  Widget callEndedView() {
    return const Center(child: tiamat.Text.label("Call ended"));
  }

  Widget callIncomingView() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Center(
          child: RingShakerAnimation(
            child: Avatar.large(
              image: room.avatar,
              placeholderColor: room.defaultColor,
              placeholderText: room.displayName,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 5,
            children: [
              if (BuildConfig.DESKTOP && widget.showSessionPopoutButton)
                TutorialAnchor(
                  id: TutorialAnchorIds.callPopoutButton,
                  padding: const EdgeInsets.all(8),
                  child: _callControlButton(
                    radius: 15,
                    icon: Icons.open_in_new_rounded,
                    onPressed: () {
                      callPopoutController.popOutSession(
                        widget.currentSession.sessionId,
                      );
                    },
                  ),
                ),
              _callControlButton(
                radius: 15,
                icon: Icons.call,
                transparentColor: _transparentControlColor(
                  Theme.of(context).colorScheme.primary,
                ),
                onPressed: () async {
                  await widget.acceptCall?.call();
                  if (!mounted) return;
                  setState(() {});
                },
              ),
              _callControlButton(
                radius: 15,
                icon: Icons.call_end,
                color: Theme.of(context).colorScheme.errorContainer,
                transparentColor: _transparentControlColor(
                  Theme.of(context).colorScheme.error,
                ),
                iconColor: widget.transparentBackground
                    ? Theme.of(context).colorScheme.onError
                    : null,
                onPressed: () async {
                  await widget.declineCall?.call();
                  if (!mounted) return;
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
