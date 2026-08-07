import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/message_input.dart'
    show ComposerPopupCard;
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_connection_health_indicator.dart';
import 'package:intergalactic/ui/organisms/soundboard/soundboard_emoji_view.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_soundboard_settings_page.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CallSoundboardPanel extends StatefulWidget {
  const CallSoundboardPanel({required this.callManager, super.key});

  final CallManager callManager;

  @override
  State<CallSoundboardPanel> createState() => _CallSoundboardPanelState();
}

class _CallSoundboardPanelState extends State<CallSoundboardPanel> {
  final List<StreamSubscription> _subscriptions = [];
  final List<StreamSubscription> _sessionSubscriptions = [];
  final LayerLink _soundboardLayerLink = LayerLink();
  OverlayEntry? _soundboardOverlay;
  String? _soundboardOverlaySessionKey;

  @override
  void initState() {
    super.initState();
    _bindCallManager(widget.callManager);
  }

  @override
  void didUpdateWidget(covariant CallSoundboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.callManager, widget.callManager)) {
      _cancelSubscriptions();
      _bindCallManager(widget.callManager);
    }
  }

  void _bindCallManager(CallManager callManager) {
    _subscriptions.add(
      callManager.currentSessions.onListUpdated.listen((_) {
        _bindSessionSubscriptions(callManager);
        _rebuild();
      }),
    );
    _subscriptions.add(callManager.onDeafenChanged.listen((_) => _rebuild()));
    _subscriptions.add(
      preferences.voipNoiseSuppressionEnabled.onChanged.listen((_) {
        _rebuild();
      }),
    );
    _subscriptions.add(
      preferences.voipNoiseSuppressionPreset.onChanged.listen((_) {
        _rebuild();
      }),
    );
    _subscriptions.add(
      preferences.developerMode.onChanged.listen((_) {
        _rebuild();
      }),
    );
    _bindSessionSubscriptions(callManager);
  }

  void _bindSessionSubscriptions(CallManager callManager) {
    for (final subscription in _sessionSubscriptions) {
      unawaited(subscription.cancel());
    }
    _sessionSubscriptions.clear();

    for (final session in callManager.currentSessions) {
      _sessionSubscriptions.add(
        session.onStateChanged.listen((_) => _rebuild()),
      );
      _sessionSubscriptions.add(
        session.onConnectionStateChanged.listen((_) => _rebuild()),
      );
      _sessionSubscriptions.add(
        session.onDiagnosticsChanged.listen((_) => _rebuild()),
      );
    }
  }

  void _rebuild() {
    final overlaySessionKey = _sessionKey(_activeSession);
    if (_soundboardOverlay != null &&
        _soundboardOverlaySessionKey != overlaySessionKey) {
      unawaited(_hideSoundboardOverlay());
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final subscription in _sessionSubscriptions) {
      unawaited(subscription.cancel());
    }
    _sessionSubscriptions.clear();
  }

  @override
  void dispose() {
    unawaited(_hideSoundboardOverlay());
    _cancelSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _activeSession;
    if (session == null) {
      return const SizedBox.shrink();
    }

    final room = session.client.getRoom(session.roomId);
    final soundboard = _soundboardFor(session);
    final canOpenSoundboard = room != null && soundboard != null;
    final scheme = Theme.of(context).colorScheme;
    final noiseSuppressionPresetLabel = _noiseSuppressionPresetLabel(
      preferences.voipNoiseSuppressionPreset.value,
    );

    return TutorialAnchor(
      id: TutorialAnchorIds.callPanel,
      padding: const EdgeInsets.all(4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CallConnectionHealthIndicator(
                  snapshot: session.diagnosticsSnapshot.callHealth,
                  developerMode: preferences.developerUiVisible,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.call, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Voice Connected',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          Text(
                            session.roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    _CallPanelIconButton(
                      tooltip: session.isMicrophoneMuted
                          ? 'Unmute. Right-click or long-press to choose microphone.'
                          : 'Mute. Right-click or long-press to choose microphone.',
                      icon: session.isMicrophoneMuted
                          ? Icons.mic_off
                          : Icons.mic,
                      selected: session.isMicrophoneMuted,
                      onPressed: () {
                        widget.callManager.toggleMute();
                        _rebuild();
                      },
                      onAlternatePressed: () =>
                          unawaited(_showAudioInputPicker(context)),
                    ),
                    if (PlatformUtils.isWindows)
                      _CallPanelIconButton(
                        tooltip: preferences.voipNoiseSuppressionEnabled.value
                            ? 'Turn noise suppression off. Right-click or long-press to choose preset ($noiseSuppressionPresetLabel).'
                            : 'Turn noise suppression on. Right-click or long-press to choose preset ($noiseSuppressionPresetLabel).',
                        icon: preferences.voipNoiseSuppressionEnabled.value
                            ? Icons.hearing
                            : Icons.hearing_disabled,
                        selected: preferences.voipNoiseSuppressionEnabled.value,
                        selectedColor: scheme.primary,
                        onPressed: () => unawaited(_toggleNoiseSuppression()),
                        onAlternatePressed: () => unawaited(
                          _showNoiseSuppressionPresetPicker(context),
                        ),
                      ),
                    _CallPanelIconButton(
                      tooltip: widget.callManager.isDeafened
                          ? 'Undeafen. Right-click or long-press to choose speaker.'
                          : 'Deafen. Right-click or long-press to choose speaker.',
                      icon: widget.callManager.isDeafened
                          ? Icons.volume_off
                          : Icons.headphones,
                      selected: widget.callManager.isDeafened,
                      onPressed: () {
                        widget.callManager.toggleDeafen();
                        _rebuild();
                      },
                      onAlternatePressed: () =>
                          unawaited(_showAudioOutputPicker(context)),
                    ),
                    TutorialAnchor(
                      id: TutorialAnchorIds.callSoundboardButton,
                      padding: const EdgeInsets.all(3),
                      child: CompositedTransformTarget(
                        link: _soundboardLayerLink,
                        child: _CallPanelIconButton(
                          tooltip: canOpenSoundboard
                              ? 'Soundboard'
                              : 'No soundboard found',
                          icon: Icons.graphic_eq,
                          selected: false,
                          onPressed: canOpenSoundboard
                              ? () => _showSoundboard(
                                  context,
                                  session,
                                  soundboard,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleNoiseSuppression() async {
    final previous = preferences.voipNoiseSuppressionEnabled.value;
    final next = !preferences.voipNoiseSuppressionEnabled.value;
    await preferences.voipNoiseSuppressionEnabled.set(next);
    try {
      await NoiseSuppressionService.instance.applyPreference(
        next,
        tuningProfile: _noiseSuppressionTuningProfile(),
      );
    } catch (error, stackTrace) {
      await preferences.voipNoiseSuppressionEnabled.set(previous);
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to toggle RNNoise from call panel',
      );
      _showSnack(context, 'Could not change noise suppression.');
      return;
    }
    if (next) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
    _rebuild();
  }

  Future<void> _showNoiseSuppressionPresetPicker(BuildContext context) async {
    final selectedPresetKey = preferences.voipNoiseSuppressionPreset.value;
    final presetKey = await AdaptiveDialog.pickOne<String>(
      context,
      title: 'Noise Suppression Preset',
      items: _noiseSuppressionPresetKeys(selectedPresetKey),
      itemBuilder: (dialogContext, presetKey, callback) {
        final isSelected = presetKey == selectedPresetKey;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
          ),
          title: Text(_noiseSuppressionPresetLabel(presetKey)),
          onTap: callback,
        );
      },
    );

    if (presetKey == null || !context.mounted) {
      return;
    }

    await _applyNoiseSuppressionPreset(context, presetKey);
  }

  Future<void> _applyNoiseSuppressionPreset(
    BuildContext context,
    String presetKey,
  ) async {
    final previousPresetKey = preferences.voipNoiseSuppressionPreset.value;
    await preferences.voipNoiseSuppressionPreset.set(presetKey);
    try {
      await NoiseSuppressionService.instance.applyPreference(
        preferences.voipNoiseSuppressionEnabled.value,
        tuningProfile: _noiseSuppressionTuningProfile(presetKey: presetKey),
      );
    } catch (error, stackTrace) {
      await preferences.voipNoiseSuppressionPreset.set(previousPresetKey);
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to switch RNNoise preset from call panel',
      );
      _showSnack(context, 'Could not switch noise suppression preset.');
      return;
    }

    if (preferences.voipNoiseSuppressionEnabled.value) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
    _showSnack(
      context,
      'Noise suppression set to ${_noiseSuppressionPresetLabel(presetKey)}.',
    );
    _rebuild();
  }

  NoiseSuppressionTuningProfile _noiseSuppressionTuningProfile({
    String? presetKey,
  }) {
    return NoiseSuppressionTuningProfile.fromPreferenceValues(
      presetKey: presetKey ?? preferences.voipNoiseSuppressionPreset.value,
      customVadThreshold: preferences.voipNoiseSuppressionVadThreshold.value,
      customSpeechGraceMs: preferences.voipNoiseSuppressionSpeechGraceMs.value,
      customClosedGainPercent:
          preferences.voipNoiseSuppressionClosedGainPercent.value,
      customTransientSensitivityPercent:
          preferences.voipNoiseSuppressionTransientSensitivity.value,
    );
  }

  List<String> _noiseSuppressionPresetKeys(String selectedPresetKey) {
    final options = NoiseSuppressionTuningProfile.presetKeys
        .where(
          (presetKey) => presetKey != NoiseSuppressionTuningProfile.customKey,
        )
        .toList();
    if (preferences.developerUiVisible ||
        selectedPresetKey == NoiseSuppressionTuningProfile.customKey) {
      options.add(NoiseSuppressionTuningProfile.customKey);
    }
    return options;
  }

  String _noiseSuppressionPresetLabel(String presetKey) {
    return switch (presetKey) {
      NoiseSuppressionTuningProfile.gentleKey => 'Gentle',
      NoiseSuppressionTuningProfile.strongKey => 'Strong',
      NoiseSuppressionTuningProfile.customKey => 'Custom',
      _ => 'Balanced',
    };
  }

  VoipSession? get _activeSession {
    return widget.callManager.currentSessions.firstWhereOrNull((session) {
      return session.state == VoipState.connected ||
          session.state == VoipState.connecting ||
          session.state == VoipState.outgoing;
    });
  }

  SoundboardComponent? _soundboardFor(VoipSession session) {
    final space = session.client.spaces.firstWhereOrNull((space) {
      return space.roomsWithChildren.any(
        (room) => room.identifier == session.roomId,
      );
    });
    return space?.getComponent<SoundboardComponent>();
  }

  String? _sessionKey(VoipSession? session) {
    if (session == null) {
      return null;
    }
    return [
      session.client.identifier,
      session.roomId,
      session.sessionId,
    ].join('|');
  }

  Future<void> _showSoundboard(
    BuildContext context,
    VoipSession session,
    SoundboardComponent soundboard,
  ) async {
    if (Layout.desktop) {
      await _showDesktopSoundboard(context, session, soundboard);
      return;
    }

    await _showSoundboardDialog(context, soundboard);
  }

  Future<void> _showSoundboardDialog(
    BuildContext context,
    SoundboardComponent soundboard,
  ) async {
    await AdaptiveDialog.show(
      context,
      title: 'Soundboard',
      builder: (dialogContext) {
        return SizedBox(
          width: 520,
          child: CallSoundboardMenu(
            soundboard: soundboard,
            onAddSoundPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_showAddSoundDialog(context, soundboard));
            },
            onSoundPressed: (sound) =>
                unawaited(_playSoundForCurrentSession(dialogContext, sound)),
          ),
        );
      },
    );
  }

  Future<void> _showAddSoundDialog(
    BuildContext context,
    SoundboardComponent soundboard,
  ) async {
    await _hideSoundboardOverlay();
    final space = soundboard.space;
    if (space is! MatrixSpace || !context.mounted) {
      return;
    }

    await AdaptiveDialog.show(
      context,
      title: 'Add Sound',
      initialHeightMobile: 0.86,
      builder: (dialogContext) {
        return SizedBox(
          width: Layout.desktop ? 640 : double.infinity,
          child: SpaceSoundboardSettingsPage(space: space),
        );
      },
    );
  }

  Future<void> _showAudioInputPicker(BuildContext context) async {
    if (PlatformUtils.isAndroid) {
      _showSnack(context, 'Microphone selection is not available on Android.');
      return;
    }

    await _showAudioDevicePicker(
      context,
      title: 'Choose Microphone',
      kind: 'audioinput',
      selectedDeviceId: preferences.voipDefaultAudioInput.value,
      onSelected: (device) async {
        final previousDeviceId = preferences.voipDefaultAudioInput.value;
        await preferences.voipDefaultAudioInput.set(device?.deviceId);
        try {
          await WebrtcDefaultDevices.selectInputDevice();
        } catch (error, stackTrace) {
          await preferences.voipDefaultAudioInput.set(previousDeviceId);
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to switch microphone device',
          );
          _showSnack(context, 'Could not switch microphone.');
          return;
        }
        _showSnack(context, 'Microphone set to ${_deviceLabel(device)}.');
      },
    );
  }

  Future<void> _showAudioOutputPicker(BuildContext context) async {
    await _showAudioDevicePicker(
      context,
      title: 'Choose Speaker',
      kind: 'audiooutput',
      selectedDeviceId: preferences.voipDefaultAudioOutput.value,
      onSelected: (device) async {
        final previousDeviceId = preferences.voipDefaultAudioOutput.value;
        await preferences.voipDefaultAudioOutput.set(device?.deviceId);
        try {
          await WebrtcDefaultDevices.selectOutputDevice();
        } catch (error, stackTrace) {
          await preferences.voipDefaultAudioOutput.set(previousDeviceId);
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to switch speaker device',
          );
          _showSnack(context, 'Could not switch speaker.');
          return;
        }
        _showSnack(context, 'Speaker set to ${_deviceLabel(device)}.');
      },
    );
  }

  Future<void> _showAudioDevicePicker(
    BuildContext context, {
    required String title,
    required String kind,
    required String? selectedDeviceId,
    required Future<void> Function(webrtc.MediaDeviceInfo? device) onSelected,
  }) async {
    final List<webrtc.MediaDeviceInfo> devices;
    try {
      devices = (await webrtc.navigator.mediaDevices.enumerateDevices())
          .where((device) => device.kind == kind)
          .toList();
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: 'Failed to enumerate devices');
      _showSnack(context, 'Could not load audio devices.');
      return;
    }

    if (!context.mounted) {
      return;
    }

    if (devices.isEmpty) {
      _showSnack(context, 'No audio devices found.');
      return;
    }

    final choice = await AdaptiveDialog.pickOne<_AudioDeviceChoice>(
      context,
      title: title,
      items: [
        const _AudioDeviceChoice(null),
        ...devices.map(_AudioDeviceChoice.new),
      ],
      itemBuilder: (dialogContext, choice, callback) {
        final isSelected = _isSelectedDevice(choice.device, selectedDeviceId);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
          ),
          title: Text(_deviceLabel(choice.device)),
          onTap: callback,
        );
      },
    );

    if (choice == null || !context.mounted) {
      return;
    }

    await onSelected(choice.device);
  }

  bool _isSelectedDevice(
    webrtc.MediaDeviceInfo? device,
    String? selectedDeviceId,
  ) {
    if (device == null) {
      return selectedDeviceId == null;
    }
    return device.deviceId == selectedDeviceId ||
        device.label == selectedDeviceId;
  }

  String _deviceLabel(webrtc.MediaDeviceInfo? device) {
    if (device == null) {
      return 'System default';
    }
    final label = device.label.trim();
    return label.isEmpty ? 'Unnamed device' : label;
  }

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDesktopSoundboard(
    BuildContext context,
    VoipSession session,
    SoundboardComponent soundboard,
  ) async {
    if (_soundboardOverlay != null) {
      await _hideSoundboardOverlay();
      return;
    }
    if (!mounted) {
      return;
    }

    final overlay = Overlay.of(context);
    final overlaySessionKey = _sessionKey(session);
    late final OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return _DesktopSoundboardOverlay(
          link: _soundboardLayerLink,
          onDismiss: () => unawaited(_hideSoundboardOverlay()),
          child: CallSoundboardMenu(
            soundboard: soundboard,
            compact: true,
            onAddSoundPressed: () =>
                unawaited(_showAddSoundDialog(context, soundboard)),
            onSoundPressed: (sound) =>
                unawaited(_playSoundForCurrentSession(context, sound)),
          ),
        );
      },
    );
    _soundboardOverlay = overlayEntry;
    _soundboardOverlaySessionKey = overlaySessionKey;
    overlay.insert(overlayEntry);
  }

  Future<void> _hideSoundboardOverlay() async {
    _soundboardOverlay?.remove();
    _soundboardOverlay = null;
    _soundboardOverlaySessionKey = null;
  }

  Future<void> _playSoundForCurrentSession(
    BuildContext context,
    SoundboardSound sound,
  ) async {
    final session = _activeSession;
    if (session == null) {
      await _hideSoundboardOverlay();
      return;
    }

    final room = session.client.getRoom(session.roomId);
    final soundboard = _soundboardFor(session);
    final currentSound = soundboard?.sounds.firstWhereOrNull(
      (candidate) => candidate.id == sound.id && candidate.isAvailable,
    );
    if (room == null || soundboard == null || currentSound == null) {
      await _hideSoundboardOverlay();
      return;
    }

    await _playSound(context, soundboard, currentSound, room, session);
  }

  Future<void> _playSound(
    BuildContext context,
    SoundboardComponent soundboard,
    SoundboardSound sound,
    Room room,
    VoipSession session,
  ) async {
    try {
      await soundboard.playSound(sound, room, callSessionId: session.sessionId);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to play call soundboard sound',
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Failed to play soundboard sound')),
      );
    }
  }
}

class _DesktopSoundboardOverlay extends StatelessWidget {
  const _DesktopSoundboardOverlay({
    required this.link,
    required this.onDismiss,
    required this.child,
  });

  final LayerLink link;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.of(context).size.height - 96)
        .clamp(280.0, 430.0)
        .toDouble();

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onDismiss,
            ),
          ),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: const Offset(0, -8),
            child: Material(
              color: Colors.transparent,
              child: ComposerPopupCard(
                preferredWidth: 560,
                maxHeight: maxHeight,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CallSoundboardMenu extends StatefulWidget {
  const CallSoundboardMenu({
    required this.soundboard,
    required this.onSoundPressed,
    this.onAddSoundPressed,
    this.compact = false,
  });

  final SoundboardComponent soundboard;
  final ValueChanged<SoundboardSound> onSoundPressed;
  final VoidCallback? onAddSoundPressed;
  final bool compact;

  @override
  State<CallSoundboardMenu> createState() => _SoundboardMenuState();
}

class _SoundboardMenuState extends State<CallSoundboardMenu> {
  static const double _gridSpacing = 8;
  static const int _visibleSoundRows = 7;
  static const EdgeInsets _contentPadding = EdgeInsets.all(10);
  static const double _headerHeight = 54;

  String query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sounds = widget.soundboard.sounds.where((sound) {
      return sound.name.toLowerCase().contains(query.toLowerCase()) ||
          sound.emoji.contains(query);
    }).toList();
    final emojiPacks = soundboardEmojiPacksForSpace(widget.soundboard.space);
    final soundTileHeight = widget.compact ? 42.0 : 48.0;
    final maxGridHeight =
        soundTileHeight * _visibleSoundRows +
        _gridSpacing * (_visibleSoundRows - 1);
    final menuHeight = _headerHeight + maxGridHeight + _contentPadding.vertical;

    return SizedBox(
      height: menuHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SoundboardHeaderRail(
            onAddSoundPressed: widget.onAddSoundPressed,
            onSearchChanged: (value) {
              setState(() => query = value);
            },
          ),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SoundboardSourceRail(soundboard: widget.soundboard),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: scheme.surfaceContainer),
                    child: Padding(
                      padding: _contentPadding,
                      child: sounds.isEmpty
                          ? _SoundboardEmptyState(
                              hasSounds: widget.soundboard.sounds.isNotEmpty,
                              hasAddAction: widget.onAddSoundPressed != null,
                              isSearching: query.trim().isNotEmpty,
                            )
                          : GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisExtent: soundTileHeight,
                                    crossAxisSpacing: _gridSpacing,
                                    mainAxisSpacing: _gridSpacing,
                                  ),
                              itemCount: sounds.length,
                              itemBuilder: (context, index) {
                                final sound = sounds[index];
                                return _SoundboardTile(
                                  sound: sound,
                                  emojiPacks: emojiPacks,
                                  compact: widget.compact,
                                  onPressed: () => widget.onSoundPressed(sound),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundboardHeaderRail extends StatelessWidget {
  const _SoundboardHeaderRail({
    required this.onSearchChanged,
    this.onAddSoundPressed,
  });

  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onAddSoundPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.44),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(child: _SoundboardSearchField(onChanged: onSearchChanged)),
            if (onAddSoundPressed != null) ...[
              const SizedBox(width: 8),
              _SoundboardAddButton(onPressed: onAddSoundPressed!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SoundboardAddButton extends StatelessWidget {
  const _SoundboardAddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.outline.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.42)),
        ),
        child: Tooltip(
          message: 'Add sound',
          child: IconButton(
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 20),
            color: scheme.onSurface,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _SoundboardSourceRail extends StatelessWidget {
  const _SoundboardSourceRail({required this.soundboard});

  static const double _railWidth = 46;
  static const double _sourceButtonSize = 36;

  final SoundboardComponent soundboard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final space = soundboard.space;

    return SizedBox(
      width: _railWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(
            right: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 6, 5, 6),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _SoundboardSourceButton(
                  soundboardName: space.displayName,
                  image: space.avatar,
                  placeholderColor: scheme.primaryContainer,
                  size: _sourceButtonSize,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundboardSourceButton extends StatelessWidget {
  const _SoundboardSourceButton({
    required this.soundboardName,
    required this.image,
    required this.placeholderColor,
    required this.size,
  });

  final String soundboardName;
  final ImageProvider? image;
  final Color placeholderColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: tiamat.Tooltip(
        text: soundboardName,
        preferredDirection: AxisDirection.right,
        child: Semantics(
          selected: true,
          label: '$soundboardName soundboard source',
          child: tiamat.ImageButton(
            size: size,
            image: image,
            placeholderText: soundboardName,
            placeholderColor: placeholderColor,
            backgroundColor: scheme.surfaceContainerHigh,
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.82),
              width: 2,
            ),
            onTap: () {},
          ),
        ),
      ),
    );
  }
}

class _SoundboardSearchField extends StatelessWidget {
  const _SoundboardSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.36),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 1),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.2),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.only(bottom: 2),
                    hintText: 'Find the perfect sound',
                    hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoundboardEmptyState extends StatelessWidget {
  const _SoundboardEmptyState({
    required this.hasSounds,
    required this.hasAddAction,
    required this.isSearching,
  });

  final bool hasSounds;
  final bool hasAddAction;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final message = hasSounds || isSearching
        ? 'No matching sounds'
        : hasAddAction
        ? 'No sounds yet. Use + to add one.'
        : 'No sounds have been uploaded yet';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}

class _CallPanelIconButton extends StatelessWidget {
  const _CallPanelIconButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.onAlternatePressed,
    this.selectedColor,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;
  final VoidCallback? onAlternatePressed;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onAlternatePressed == null
          ? null
          : (_) => onAlternatePressed?.call(),
      onLongPress: onAlternatePressed,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon),
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          color: selected ? selectedColor ?? scheme.error : scheme.secondary,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _AudioDeviceChoice {
  const _AudioDeviceChoice(this.device);

  final webrtc.MediaDeviceInfo? device;
}

class _SoundboardTile extends StatelessWidget {
  const _SoundboardTile({
    required this.sound,
    required this.emojiPacks,
    required this.onPressed,
    this.compact = false,
  });

  final SoundboardSound sound;
  final List<EmoticonPack> emojiPacks;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);

    return Semantics(
      button: true,
      label: 'Play ${sound.name}',
      child: Material(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.62),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 5 : 6,
            ),
            child: Row(
              children: [
                SoundboardEmojiView(
                  value: sound.emoji,
                  packs: emojiPacks,
                  size: compact ? 22 : 24,
                  textStyle: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(width: compact ? 7 : 8),
                Expanded(
                  child: Text(
                    sound.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
