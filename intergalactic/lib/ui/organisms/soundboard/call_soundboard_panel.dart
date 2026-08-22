import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_library_component.dart';
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
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/molecules/message_input.dart'
    show ComposerPopupCard;
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_connection_health_indicator.dart';
import 'package:intergalactic/ui/organisms/soundboard/soundboard_emoji_view.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_soundboard_settings_page.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// One pack offered in the call picker, together with the component that must
/// perform the play.
///
/// [owner] is the crucial field. A pack enabled from another space is played by
/// the SOURCE space's component, not the destination's: that component holds
/// the account-scoped authority client and is where the cross-space
/// authorization is minted. Routing a foreign sound through the destination
/// component would find no such sound and silently do nothing.
class SoundboardCallPack {
  const SoundboardCallPack({
    required this.owner,
    required this.pack,
    required this.sounds,
    required this.isExternal,
    this.sourceSpaceName,
  });

  final SoundboardComponent owner;
  final SoundboardPack pack;
  final List<SoundboardSound> sounds;

  /// True when this pack comes from a space other than the one hosting the
  /// call, so the play will need a signed cross-space authorization.
  final bool isExternal;

  /// Display name of the source space, shown on the header so a member can tell
  /// where a sound came from. Null when the source space has no readable name.
  final String? sourceSpaceName;

  /// The space this pack lives in. Grouping is by id rather than by name
  /// because two spaces may legitimately share a display name.
  String get sourceSpaceId => owner.space.identifier;

  /// Identity within the picker. Pack ids are only unique WITHIN a space, and a
  /// legacy pack's id is deterministic (legacyIdForUploader), so the member's
  /// own legacy pack in this space and their legacy pack in another space share
  /// the same pack id. Keying by (space, pack) keeps them distinct for both
  /// dedup and collapse state; keying by pack id alone dropped the foreign one.
  ///
  /// The separator is the escape \u0000, never a literal NUL
  /// byte: a raw NUL in the source makes git classify this file as binary,
  /// which silently stops it producing diffs and stops `git grep` matching
  /// it at all.
  String get identityKey => '$sourceSpaceId\u0000${pack.id}';
}

/// One entry in the picker's left rail: a space contributing packs to this
/// call, either the space hosting it or a source of globally enabled packs.
class SoundboardCallSource {
  const SoundboardCallSource({
    required this.spaceId,
    required this.name,
    required this.avatar,
    required this.isExternal,
  });

  final String spaceId;
  final String name;
  final ImageProvider? avatar;

  /// False for the space hosting the call, which always sorts first.
  final bool isExternal;
}

/// The rail's spaces, in body order: the call's own space first, then each
/// space contributing external packs, once each.
///
/// Derived from the packs rather than from the joined-space list, so a space
/// whose packs were all filtered out (policy, staleness, empty) contributes no
/// rail button the member could select to reach nothing.
@visibleForTesting
List<SoundboardCallSource> collectCallSoundboardSources({
  required SoundboardComponent destination,
  required List<SoundboardCallPack> packs,
}) {
  final sources = <SoundboardCallSource>[
    SoundboardCallSource(
      spaceId: destination.space.identifier,
      name: destination.space.displayName,
      avatar: destination.space.avatar,
      isExternal: false,
    ),
  ];
  final seen = <String>{destination.space.identifier};
  for (final pack in packs) {
    if (!seen.add(pack.sourceSpaceId)) {
      continue;
    }
    sources.add(
      SoundboardCallSource(
        spaceId: pack.sourceSpaceId,
        name: pack.sourceSpaceName ?? pack.owner.space.displayName,
        avatar: pack.owner.space.avatar,
        isExternal: true,
      ),
    );
  }
  return sources;
}

/// Builds the pack list for an in-call picker: the destination space's own
/// active packs, followed by the account's globally enabled packs from other
/// spaces (U5 + U7).
///
/// External packs are gated on the DESTINATION space's policy through the same
/// evaluator the receiver uses, so a space that blocks external packs never
/// offers them in its own picker either. That keeps the sender from composing a
/// play that every receiver — including the sender's own client — would refuse.
@visibleForTesting
List<SoundboardCallPack> collectCallSoundboardPacks({
  required SoundboardComponent destination,
  SoundboardLibraryComponent? library,
}) {
  final destinationSpaceId = destination.space.identifier;
  final packs = <SoundboardCallPack>[];

  // The member's own active packs in this space, exactly as before: the picker
  // is personal, so discoverable-but-inactive packs stay out (R9).
  final soundsByPack = <String, List<SoundboardSound>>{};
  for (final sound in destination.activeSounds) {
    (soundsByPack[destination.effectivePackIdFor(sound)] ??= []).add(sound);
  }
  for (final pack in destination.packs) {
    if (!pack.isAvailable || !destination.activePackIds.contains(pack.id)) {
      continue;
    }
    packs.add(
      SoundboardCallPack(
        owner: destination,
        pack: pack,
        sounds: soundsByPack[pack.id] ?? const <SoundboardSound>[],
        isExternal: false,
      ),
    );
  }

  if (library == null) {
    return packs;
  }

  final external = <SoundboardCallPack>[];
  for (final entry in library.usableEntries) {
    final sourceSpaceId = entry.reference.sourceSpaceId;
    // A globally enabled pack that happens to live in THIS space is already
    // covered above; listing it again would show the same pack twice and route
    // it through a needless cross-space authorization.
    if (sourceSpaceId == destinationSpaceId) {
      continue;
    }

    // The destination administrator's switch, evaluated with the shared
    // evaluator rather than a second copy of the rule.
    final evaluation = SoundboardExternalPackEvaluation.evaluate(
      sourceSpaceId: sourceSpaceId,
      destinationSpaceId: destinationSpaceId,
      destinationPolicy: destination.destinationPolicy,
    );
    if (evaluation.isBlocked) {
      continue;
    }

    final pack = entry.pack;
    if (pack == null || !pack.isAvailable) {
      continue;
    }
    // Resolve the component that owns the sounds. Without it there is nothing
    // to play through, so the pack is not offered at all rather than offered
    // and then failing on tap.
    final sourceSpace = destination.client.spaces.firstWhereOrNull(
      (space) => space.identifier == sourceSpaceId,
    );
    final owner = sourceSpace?.getComponent<SoundboardComponent>();
    if (owner == null) {
      continue;
    }
    final sounds = entry.sounds
        .where((sound) => sound.isAvailable)
        .toList(growable: false);
    if (sounds.isEmpty) {
      continue;
    }
    // NO dedup against local pack ids here. Pack ids are unique only within a
    // space, and a legacy pack id is deterministic, so the member's own legacy
    // pack in this space and their legacy pack in the source space share an id
    // - dropping the foreign one on that collision is exactly why an enabled
    // legacy pack never appeared in the picker. The two are distinct content
    // under distinct rail entries; both belong. References are unique per
    // (source space, pack), so the external set has no true duplicates.
    external.add(
      SoundboardCallPack(
        owner: owner,
        pack: pack,
        sounds: sounds,
        isExternal: true,
        sourceSpaceName: entry.sourceSpaceName,
      ),
    );
  }

  // Stable ordering so the picker does not reshuffle between opens.
  external.sort((a, b) {
    final bySpace = (a.sourceSpaceName ?? '').compareTo(
      b.sourceSpaceName ?? '',
    );
    return bySpace != 0
        ? bySpace
        : soundboardPackDisplayName(
            a.pack,
            a.owner.packs,
          ).compareTo(soundboardPackDisplayName(b.pack, b.owner.packs));
  });

  return [...packs, ...external];
}

/// Re-resolves the tapped [sound] against the component that OWNS it, at the
/// moment of the tap.
///
/// The picker holds a snapshot of sounds from when it was built; by tap time a
/// sound may have been removed or replaced. Resolving against [owner] (the
/// source space's component for an external pack, NOT the destination's) is
/// what makes a cross-space play work at all — resolving against the
/// destination would find nothing and drop the tap silently. Returns null when
/// the sound is no longer present or available, in which case the caller must
/// not play.
@visibleForTesting
SoundboardSound? resolveOwnedPlaySound(
  SoundboardComponent owner,
  SoundboardSound sound,
) => owner.sounds.firstWhereOrNull(
  (candidate) => candidate.id == sound.id && candidate.isAvailable,
);

/// The user-facing text for a refused play.
///
/// The service/policy message is ALWAYS preserved. It is the only account of
/// what actually happened, and no refusal here can positively identify the
/// "authority service is not in the sound's source space" condition — the wire
/// contract has no code or detail field naming it (see
/// `_crossSpaceRefusalReason`). [SoundboardPlayRefusal.sourceSpaceUnavailable]
/// therefore means "consistent with that condition", not "is that condition".
///
/// So the hint is APPENDED after the service message and phrased as a
/// possibility, never as an instruction that replaces it. An earlier revision
/// replaced the message, which meant a deleted sound, a deleted pack, a caller
/// without source-space access and a blocked destination were all told to go
/// enable sound protection — wrong advice, and it put an optional space feature
/// into product copy as if it were a prerequisite
/// (`docs/DECISIONS.md`, 2026-08-08 "Cross-Space Soundboard Playback Must Not
/// Require Enhanced Protection"). [sourceSpaceName] is named so a call carrying
/// packs from several spaces stays unambiguous.
/// Matches a service message that already ends a sentence, so the appended
/// hint never welds a second period onto it. Top-level so a refused play does
/// not recompile the pattern.
final RegExp _terminalPunctuationPattern = RegExp(r'[.!?…]$');

@visibleForTesting
String soundboardPlayFailureMessage({
  required SoundboardPlayRefusal? reason,
  required String? serviceMessage,
  required String sourceSpaceName,
}) {
  final trimmedService = serviceMessage?.trim() ?? '';
  final message = trimmedService.isEmpty
      ? 'Failed to play soundboard sound'
      : trimmedService;
  if (reason != SoundboardPlayRefusal.sourceSpaceUnavailable) {
    return message;
  }
  final trimmedName = sourceSpaceName.trim();
  final name = trimmedName.isEmpty ? 'that space' : trimmedName;
  // Only add a sentence break when the service message did not end one, so the
  // appended hint never reads as part of the service's own sentence. The
  // ellipsis is in the pattern because a truncated or trailing-off service
  // message is exactly the shape that would otherwise get a period welded on.
  final lead = _terminalPunctuationPattern.hasMatch(message)
      ? message
      : '$message.';
  // The name is quoted because it is arbitrary user-supplied text. A space
  // called "My Space." rendered as `if My Space. is not set up`, which reads as
  // a sentence that ended and then kept going. Quoting also makes it obvious
  // where the name stops when it contains spaces or punctuation of its own.
  return '$lead This can happen if "$name" is not set up to share its sounds '
      'with other spaces yet; a space admin can check its soundboard settings.';
}

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
  OverlayEntry? _playbackFailureEntry;
  Timer? _playbackFailureTimer;

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
    _dismissPlaybackFailure();
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
                    // Gated on "has a native suppression backend", not on
                    // Windows. This was hard-coded to isWindows and so the
                    // in-call toggle was missing on Android, which runs the
                    // DeepFilterNet backend - the third hand-copied version of
                    // this platform check, and the same mistake the service's
                    // isNativeSuppressionPlatform doc comment records having
                    // already hidden the entire settings section once.
                    if (showNoiseSuppressionToggle)
                      _CallPanelIconButton(
                        tooltip: _noiseSuppressionTooltip(
                          noiseSuppressionPresetLabel,
                        ),
                        icon: preferences.voipNoiseSuppressionEnabled.value
                            ? Icons.hearing
                            : Icons.hearing_disabled,
                        selected: preferences.voipNoiseSuppressionEnabled.value,
                        selectedColor: scheme.primary,
                        onPressed: () => unawaited(_toggleNoiseSuppression()),
                        // Presets are RNNoise parameters. Android's backend
                        // answers `configure` with
                        // android_configuration_unsupported and has no presets
                        // to offer, so it gets the toggle without the picker.
                        onAlternatePressed: showNoiseSuppressionPresets
                            ? () => unawaited(
                                _showNoiseSuppressionPresetPicker(context),
                              )
                            : null,
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

  /// Whether this platform has a native suppression backend, and so should
  /// offer the in-call toggle. Delegates to the service rather than keeping a
  /// local copy - a local copy is exactly how this control came to be missing
  /// on Android.
  bool get showNoiseSuppressionToggle =>
      NoiseSuppressionService.isNativeSuppressionPlatform;

  /// Whether the backend accepts RNNoise presets. Android's does not, so it
  /// gets the toggle without the long-press preset picker.
  bool get showNoiseSuppressionPresets =>
      NoiseSuppressionService.supportsRnnoiseTuning;

  /// The tooltip has to describe only the gestures the button actually has:
  /// promising a preset picker on a platform that has no presets is worse than
  /// saying nothing about them.
  String _noiseSuppressionTooltip(String presetLabel) {
    final action = preferences.voipNoiseSuppressionEnabled.value
        ? 'Turn noise suppression off'
        : 'Turn noise suppression on';
    if (!showNoiseSuppressionPresets) {
      return '$action.';
    }
    return '$action. Right-click or long-press to choose preset '
        '($presetLabel).';
  }

  VoipSession? get _activeSession {
    return widget.callManager.currentSessions.firstWhereOrNull((session) {
      return session.state == VoipState.connected ||
          session.state == VoipState.connecting ||
          session.state == VoipState.outgoing;
    });
  }

  /// The account-global library for the client that owns this call. Read from
  /// the destination component's own client, never a manager-wide lookup — the
  /// library is per-account, and mixing accounts here is exactly the class of
  /// bug BUG-285 was.
  SoundboardLibraryComponent? _libraryFor(SoundboardComponent soundboard) =>
      soundboard.client.getComponent<SoundboardLibraryComponent>();

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

  /// Records which space/component the picker resolved for this call, so a
  /// pack that is active in Space Settings but missing here can be traced to
  /// the surfaces reading different soundboards rather than to activation
  /// state. `space_candidates` above 1 means the call room belongs to several
  /// spaces and `_soundboardFor` picked the first one.
  void _logPickerOpened(VoipSession session, SoundboardComponent soundboard) {
    final candidates = session.client.spaces
        .where(
          (space) => space.roomsWithChildren.any(
            (room) => room.identifier == session.roomId,
          ),
        )
        .length;
    final packs = soundboard.packs.where((pack) => pack.isAvailable).toList();
    final activeIds = soundboard.activePackIds;

    Log.i(
      'soundboard event=picker_opened '
      'room_hash=${soundboardLogHash(session.roomId)} '
      'space_hash=${soundboardLogHash(soundboard.space.identifier)} '
      'space_candidates=$candidates '
      'component=${identityHashCode(soundboard)} '
      'client_hash=${soundboardLogHash(session.client.identifier)} '
      'available_packs=${packs.length} '
      'active_packs=${activeIds.length} '
      'active_sounds=${soundboard.activeSounds.length}',
    );
  }

  Future<void> _showSoundboard(
    BuildContext context,
    VoipSession session,
    SoundboardComponent soundboard,
  ) async {
    _logPickerOpened(session, soundboard);
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
            library: _libraryFor(soundboard),
            onAddSoundPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_showAddSoundDialog(context, soundboard));
            },
            onSoundPressed: (owner, sound) => unawaited(
              _playSoundForCurrentSession(dialogContext, owner, sound),
            ),
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
            library: _libraryFor(soundboard),
            compact: true,
            onAddSoundPressed: () =>
                unawaited(_showAddSoundDialog(context, soundboard)),
            onSoundPressed: (owner, sound) =>
                unawaited(_playSoundForCurrentSession(context, owner, sound)),
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
    SoundboardComponent owner,
    SoundboardSound sound,
  ) async {
    final session = _activeSession;
    if (session == null) {
      await _hideSoundboardOverlay();
      return;
    }

    final room = session.client.getRoom(session.roomId);
    final currentSound = resolveOwnedPlaySound(owner, sound);
    if (room == null || currentSound == null) {
      await _hideSoundboardOverlay();
      return;
    }

    await _playSound(context, owner, currentSound, room, session);
  }

  Future<void> _playSound(
    BuildContext context,
    SoundboardComponent soundboard,
    SoundboardSound sound,
    Room room,
    VoipSession session,
  ) async {
    // playSound reports a refusal as an outcome, not a throw, so every refusal
    // path (no session, blocked policy, service refusal, failed send) surfaces
    // the same way here instead of some throwing and some silently succeeding.
    final outcome = await soundboard.playSound(
      sound,
      room,
      callSessionId: session.sessionId,
    );
    if (outcome.started || !context.mounted) {
      return;
    }
    _showPlaybackFailure(
      context,
      soundboardPlayFailureMessage(
        reason: outcome.reason,
        serviceMessage: outcome.message,
        // The owner is the source-space component on the cross-space path, so
        // its space is the one the member must ask an admin to enrol.
        sourceSpaceName: soundboard.space.displayName,
      ),
    );
  }

  /// Surfaces a refused or failed play.
  ///
  /// The picker lives in an [Overlay] whose route has no [Scaffold], and
  /// `showSnackBar` ASSERTS when its messenger has no descendant Scaffold to
  /// present in. So the failure toast was itself throwing: a refused play left
  /// no snack bar, no error, and a button that simply did nothing. Anything
  /// reporting failure from inside this overlay has to work without a Scaffold.
  void _showPlaybackFailure(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null && Scaffold.maybeOf(context) != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    _showOverlayMessage(context, message);
  }

  /// A transient banner inserted straight into the overlay — the fallback for
  /// the Scaffold-less call surface.
  void _showOverlayMessage(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 24,
        right: 24,
        bottom: 96,
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: scheme.inverseSurface,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                // A live region, because this overlay is the ONLY feedback a
                // refused play gives. The SnackBar path announces itself; a
                // bare Text inside IgnorePointer does not, so without this a
                // screen-reader user gets exactly the "the button did nothing"
                // experience the refusal contract exists to remove.
                child: Semantics(
                  liveRegion: true,
                  container: true,
                  child: Text(
                    message,
                    key: const ValueKey('soundboard-play-failure'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onInverseSurface),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _dismissPlaybackFailure();
    overlay.insert(entry);
    _playbackFailureEntry = entry;
    _playbackFailureTimer = Timer(
      const Duration(seconds: 4),
      _dismissPlaybackFailure,
    );
  }

  void _dismissPlaybackFailure() {
    _playbackFailureTimer?.cancel();
    _playbackFailureTimer = null;
    _playbackFailureEntry?.remove();
    _playbackFailureEntry = null;
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
    this.library,
  });

  final SoundboardComponent soundboard;

  /// Receives the pack's OWNING component alongside the sound, because an
  /// external pack must be played through the space that owns it.
  final void Function(SoundboardComponent owner, SoundboardSound sound)
  onSoundPressed;
  final VoidCallback? onAddSoundPressed;
  final bool compact;

  /// The account-global library, when the client exposes one. Supplies the
  /// externally enabled packs; null simply means no external packs are offered.
  final SoundboardLibraryComponent? library;

  @override
  State<CallSoundboardMenu> createState() => _SoundboardMenuState();
}

class _SoundboardMenuState extends State<CallSoundboardMenu> {
  static const double _gridSpacing = 8;
  static const int _visibleSoundRows = 7;
  static const EdgeInsets _contentPadding = EdgeInsets.all(10);
  static const double _headerHeight = 54;

  StreamSubscription? _soundboardSubscription;
  StreamSubscription? _librarySubscription;
  String query = '';

  /// Packs the member collapsed in this picker. Sections are expanded until
  /// collapsed, and a search temporarily expands every matching section so
  /// results are never hidden behind a collapsed header.
  final Set<String> _collapsedPackIds = {};

  /// The rail space whose packs the body is showing. Null means the space
  /// hosting the call, which is also the fallback whenever the selected space
  /// stops contributing packs (pack deleted, access lost, policy flipped).
  String? _selectedSourceSpaceId;

  @override
  void initState() {
    super.initState();
    _bindSoundboard();
  }

  @override
  void didUpdateWidget(covariant CallSoundboardMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.soundboard, widget.soundboard) ||
        !identical(oldWidget.library, widget.library)) {
      // The rail selection belongs to the soundboard being replaced. The
      // build-time fallback only rescues the case where the selected space no
      // longer contributes packs; if the same space id contributes to both, a
      // picker rebound to a different call would keep showing the old call's
      // selection. Cleared here so the new binding picks its own default.
      _selectedSourceSpaceId = null;
      _bindSoundboard();
    }
  }

  void _bindSoundboard() {
    unawaited(_soundboardSubscription?.cancel());
    unawaited(_librarySubscription?.cancel());
    // Keep the open picker current when packs/sounds change (uploads from
    // the + dialog, personal pack activation from settings).
    _soundboardSubscription = widget.soundboard.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    // ...and when the account's global library changes, so enabling a pack on
    // another device shows up here without reopening the picker.
    _librarySubscription = widget.library?.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    unawaited(_soundboardSubscription?.cancel());
    unawaited(_librarySubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final soundboard = widget.soundboard;
    // The picker is personal (R9) and now spans spaces: this space's active
    // packs, then the account's globally enabled packs from elsewhere.
    final callPacks = collectCallSoundboardPacks(
      destination: soundboard,
      library: widget.library,
    );
    final isSearching = query.trim().isNotEmpty;
    final sources = collectCallSoundboardSources(
      destination: soundboard,
      packs: callPacks,
    );
    final selectedSourceId =
        sources.any((source) => source.spaceId == _selectedSourceSpaceId)
        ? _selectedSourceSpaceId!
        : soundboard.space.identifier;
    // A search spans every space. Confining it to the selected rail entry
    // would hide matches behind a rail button the member has no reason to
    // suspect - the same rule that force-expands collapsed sections.
    final sourcePacks = isSearching
        ? callPacks
        : callPacks
              .where((callPack) => callPack.sourceSpaceId == selectedSourceId)
              .toList(growable: false);
    bool matchesQuery(SoundboardSound sound) =>
        sound.name.toLowerCase().contains(query.toLowerCase()) ||
        sound.emoji.contains(query);
    // While searching, a pack with no match drops out entirely rather than
    // leaving an empty header behind.
    final visiblePacks = <SoundboardCallPack>[];
    var totalSounds = 0;
    for (final callPack in sourcePacks) {
      final matching = isSearching
          ? callPack.sounds.where(matchesQuery).toList(growable: false)
          : callPack.sounds;
      totalSounds += matching.length;
      if (matching.isEmpty) {
        continue;
      }
      visiblePacks.add(
        SoundboardCallPack(
          owner: callPack.owner,
          pack: callPack.pack,
          sounds: matching,
          isExternal: callPack.isExternal,
          sourceSpaceName: callPack.sourceSpaceName,
        ),
      );
    }
    // A temporary hint (2026-07-29): a sound from another space rides a v2
    // authorized play event that only U7+ clients can parse, so participants on
    // older builds silently do not hear it. This warns the sender whenever the
    // packs on screen include an external one.
    //
    // REMOVE IN 0.8.2, NOT 0.8.1. The minimum-version floor is 0.8.1 and takes
    // effect at that release, so "remove once the floor exists" would delete
    // this a release early - which is the mistake this note exists to stop. The
    // owner kept it for the whole 0.8.1 window deliberately: the user base is
    // small and updates take weeks, so 0.8.1 is when people actually migrate
    // and the warning is still true for most receivers. Decision:
    // "Cross-Space Soundboard: 0.8.1 Floor, Warning Removed at 0.8.2",
    // 2026-08-17, in the workspace DECISIONS.md.
    final hasExternalVisible = visiblePacks.any((pack) => pack.isExternal);
    final emojiPacks = soundboardEmojiPacksForSpace(soundboard.space);
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
                _SoundboardSourceRail(
                  sources: sources,
                  selectedSpaceId: selectedSourceId,
                  onSelected: (spaceId) {
                    setState(() => _selectedSourceSpaceId = spaceId);
                  },
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: scheme.surfaceContainer),
                    child: Padding(
                      padding: _contentPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (hasExternalVisible)
                            const _SoundboardCrossSpaceHint(),
                          Expanded(
                            child: totalSounds == 0
                                ? _SoundboardEmptyState(
                                    hasSounds: callPacks.isNotEmpty,
                                    hasDiscoverablePacks:
                                        soundboard.packs.isNotEmpty &&
                                        callPacks.isEmpty,
                                    hasAddAction:
                                        widget.onAddSoundPressed != null,
                                    isSearching: isSearching,
                                  )
                                : CustomScrollView(
                                    slivers: [
                                      for (final callPack in visiblePacks)
                                        ..._packSlivers(
                                          callPack: callPack,
                                          emojiPacks: emojiPacks,
                                          soundTileHeight: soundTileHeight,
                                          isSearching: isSearching,
                                        ),
                                    ],
                                  ),
                          ),
                        ],
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

  /// One collapsible pack section: a header naming the pack, then its sounds.
  List<Widget> _packSlivers({
    required SoundboardCallPack callPack,
    required List<EmoticonPack> emojiPacks,
    required double soundTileHeight,
    required bool isSearching,
  }) {
    final pack = callPack.pack;
    final sounds = callPack.sounds;
    final displayName = soundboardPackDisplayName(pack, callPack.owner.packs);
    // Keyed by (space, pack): a local and a foreign legacy pack can share a
    // pack id and both be on screen during a search, so collapsing one must not
    // collapse the other.
    final collapseKey = callPack.identityKey;
    final collapsed = !isSearching && _collapsedPackIds.contains(collapseKey);

    return [
      SliverToBoxAdapter(
        child: _SoundboardPackHeader(
          pack: pack,
          displayName: displayName,
          emojiPacks: emojiPacks,
          soundCount: sounds.length,
          sourceSpaceName: callPack.isExternal
              ? callPack.sourceSpaceName
              : null,
          collapsed: collapsed,
          // A search force-expands sections, so the header is not a toggle
          // while the results it reveals depend on it.
          onToggle: isSearching
              ? null
              : () {
                  setState(() {
                    if (!_collapsedPackIds.remove(collapseKey)) {
                      _collapsedPackIds.add(collapseKey);
                    }
                  });
                },
        ),
      ),
      if (!collapsed)
        SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: soundTileHeight,
            crossAxisSpacing: _gridSpacing,
            mainAxisSpacing: _gridSpacing,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final sound = sounds[index];
            return _SoundboardTile(
              sound: sound,
              emojiPacks: emojiPacks,
              compact: widget.compact,
              onPressed: () => widget.onSoundPressed(callPack.owner, sound),
            );
          }, childCount: sounds.length),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: _gridSpacing)),
    ];
  }
}

/// Temporary sender-side notice shown while any external (cross-space) pack is
/// on screen: those sounds ride a v2 authorized play event that pre-U7 clients
/// cannot parse, so participants on older builds do not hear them.
///
/// **Remove in 0.8.2, together with its scoped widget coverage - not in 0.8.1.**
/// The floor is 0.8.1 and is effective at that release, so removing this when
/// the floor "exists" takes it out a release too early.
class _SoundboardCrossSpaceHint extends StatelessWidget {
  const _SoundboardCrossSpaceHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: tiamat.Text.labelLow(
                  'Sounds from other spaces may not be heard by everyone in '
                  'the call yet.',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsible section header naming one pack in the call picker body.
class _SoundboardPackHeader extends StatelessWidget {
  const _SoundboardPackHeader({
    required this.pack,
    required this.displayName,
    required this.emojiPacks,
    required this.soundCount,
    required this.collapsed,
    required this.onToggle,
    this.sourceSpaceName,
  });

  final SoundboardPack pack;
  final String displayName;
  final List<EmoticonPack> emojiPacks;
  final int soundCount;
  final bool collapsed;
  final VoidCallback? onToggle;

  /// Set only for a pack borrowed from another space. Names that space, so a
  /// member can tell at a glance which sounds leave this space when played.
  final String? sourceSpaceName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = InterGalacticMotion.duration(
      context,
      InterGalacticMotion.standard,
    );
    final radius = BorderRadius.circular(6);

    return Padding(
      padding: const EdgeInsets.only(bottom: _SoundboardMenuState._gridSpacing),
      child: AccessibleInteractiveRegion(
        semanticLabel: displayName,
        semanticValue: collapsed ? 'Collapsed' : 'Expanded',
        semanticHint: collapsed ? 'Expand sound pack' : 'Collapse sound pack',
        semanticOnTapHint: collapsed ? 'Expand pack' : 'Collapse pack',
        expanded: !collapsed,
        enabled: onToggle != null,
        excludeChildSemantics: true,
        borderRadius: radius,
        onActivate: onToggle,
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            excludeFromSemantics: true,
            canRequestFocus: false,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(
                      child: pack.emoji != null && pack.emoji!.isNotEmpty
                          ? SoundboardEmojiView(
                              value: pack.emoji!,
                              packs: emojiPacks,
                              size: 16,
                              textStyle: Theme.of(
                                context,
                              ).textTheme.labelMedium,
                            )
                          : Icon(
                              pack.isLegacy
                                  ? Icons.folder_outlined
                                  : Icons.library_music_outlined,
                              size: 16,
                              color: scheme.secondary,
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (sourceSpaceName != null &&
                            sourceSpaceName!.isNotEmpty)
                          Text(
                            'from $sourceSpaceName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '$soundCount',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (onToggle != null) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: collapsed ? 0 : 0.5,
                      duration: duration,
                      curve: InterGalacticMotion.standardOut,
                      child: Icon(
                        Icons.expand_more,
                        size: 18,
                        color: scheme.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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

/// The source rail lists spaces, not packs: packs are grouped as collapsible
/// sections in the body instead.
/// The picker's left rail: one button per space contributing packs, selecting
/// which space's packs the body shows.
class _SoundboardSourceRail extends StatelessWidget {
  const _SoundboardSourceRail({
    required this.sources,
    required this.selectedSpaceId,
    required this.onSelected,
  });

  static const double _railWidth = 46;
  static const double _sourceButtonSize = 36;

  final List<SoundboardCallSource> sources;
  final String selectedSpaceId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
              key: const ValueKey('soundboard-space-source-rail'),
              padding: EdgeInsets.zero,
              children: [
                for (final source in sources)
                  _SoundboardSourceButton(
                    key: ValueKey('soundboard-space-source-${source.spaceId}'),
                    soundboardName: source.name,
                    image: source.avatar,
                    placeholderColor: source.isExternal
                        ? scheme.secondaryContainer
                        : scheme.primaryContainer,
                    size: _sourceButtonSize,
                    selected: source.spaceId == selectedSpaceId,
                    onPressed: () => onSelected(source.spaceId),
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
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String soundboardName;
  final ImageProvider? image;
  final Color placeholderColor;
  final double size;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: tiamat.Tooltip(
        text: soundboardName,
        preferredDirection: AxisDirection.right,
        child: Semantics(
          selected: selected,
          button: true,
          label: '$soundboardName soundboard source',
          child: tiamat.ImageButton(
            size: size,
            onTap: onPressed,
            image: image,
            placeholderText: soundboardName,
            placeholderColor: placeholderColor,
            backgroundColor: scheme.surfaceContainerHigh,
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outline.withValues(alpha: 0.82),
              width: 2,
            ),
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
    required this.hasDiscoverablePacks,
    required this.hasAddAction,
    required this.isSearching,
  });

  final bool hasSounds;
  final bool hasDiscoverablePacks;
  final bool hasAddAction;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final message = hasSounds || isSearching
        ? 'No matching sounds'
        : hasDiscoverablePacks && hasAddAction
        ? 'No active sound packs. Use + to browse this space’s packs and '
              'turn some on.'
        : hasDiscoverablePacks
        ? 'No active sound packs. Turn some on in this space’s '
              'soundboard settings.'
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
