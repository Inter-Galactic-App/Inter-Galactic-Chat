import 'dart:async';

import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/organisms/activity/game_activity_overlay_pill.dart';
import 'package:intergalactic/ui/organisms/call_view/call_control_action_button.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class VoipStreamView extends StatefulWidget {
  const VoipStreamView(
    this.stream,
    this.session, {
    super.key,
    this.fit = BoxFit.cover,
    this.borderColor,
    this.canFullscreen = true,
    this.isFocused = false,
    this.edgeToEdge = false,
    this.showTileChrome = true,
    this.showTileScrim = true,
    this.isMicrophoneMuted = false,
    this.isVideoHidden = false,
    this.localPreviewAutoPaused = false,
    this.showLocalPreviewPerformanceWarning = false,
    this.onFullscreen,
    this.onTap,
    this.onDoubleTap,
    this.onPopout,
    this.gameActivity,
    this.gameActivityPresenceText,
    this.volumeStream,
    this.defaultVolume = 1.0,
    this.forceActionButtonsVisible = false,
    this.onVolumeChanged,
    this.onVisibilityToggle,
    this.onRemoveFromCall,
    this.onHideToggle,
    this.onStopStreaming,
    this.streamQualityProfiles = const [],
    this.selectedStreamQualityProfile,
    this.streamAdvancedOverrideEnabled = false,
    this.onStreamQualitySelected,
    this.shareStreamAudio,
    this.canChangeShareStreamAudio = false,
    this.onShareStreamAudioChanged,
    this.useRootOverlayForMenus = true,
  });
  final VoipStream stream;
  final VoipSession session;
  final BoxFit fit;
  final Function()? onFullscreen;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onPopout;
  final UserActivity? gameActivity;
  final String? gameActivityPresenceText;
  final Color? borderColor;
  final bool canFullscreen;
  final bool isFocused;
  final bool edgeToEdge;
  final bool showTileChrome;
  final bool showTileScrim;
  final bool isMicrophoneMuted;
  final VoipStream? volumeStream;
  final double defaultVolume;
  final bool forceActionButtonsVisible;

  /// Whether this stream's visual content is currently hidden behind the
  /// blank reveal panel.
  final bool isVideoHidden;

  /// Whether a hidden local screenshare tile was paused by the automatic
  /// sender-preview performance guard rather than a direct user hide action.
  final bool localPreviewAutoPaused;

  /// Whether a manually revealed local sender preview should warn that keeping
  /// the preview visible can cost capture/render performance.
  final bool showLocalPreviewPerformanceWarning;

  /// Called when the user toggles the tile's reveal state directly from the
  /// tile itself. Used by screenshares so BUG-018's reveal/hide flow stays
  /// separate from the context-menu hide action.
  final VoidCallback? onVisibilityToggle;

  /// Called when the user adjusts the local playback volume for this tile's
  /// selected audio stream (0.0-2.0). Only provided for remote streams.
  final void Function(double volume)? onVolumeChanged;

  /// Called when an admin/moderator chooses to remove this participant from
  /// the call.  Only provided for remote participants when the local user has
  /// the required permissions.
  final VoidCallback? onRemoveFromCall;

  /// Called when the user toggles the per-stream video hide from the context
  /// menu for any participant tile, including the local participant.
  final VoidCallback? onHideToggle;

  /// Called from the local screenshare tile menu when the publisher stops the
  /// active stream.
  final VoidCallback? onStopStreaming;

  /// User-facing screenshare quality presets shown in the local stream menu.
  final List<ScreenShareQualityProfile> streamQualityProfiles;

  /// The persisted preset currently selected for new/republished streams.
  final ScreenShareQualityProfile? selectedStreamQualityProfile;

  /// Whether developer advanced override is active instead of a normal preset.
  final bool streamAdvancedOverrideEnabled;

  /// Called when the local publisher selects a stream quality preset.
  final ValueChanged<ScreenShareQualityProfile>? onStreamQualitySelected;

  /// Whether shared-content audio is currently requested for the local stream.
  final bool? shareStreamAudio;

  /// Whether the current local stream can be republished with another shared
  /// audio setting without reopening the source picker.
  final bool canChangeShareStreamAudio;

  /// Called when the local publisher toggles shared-content audio.
  final ValueChanged<bool>? onShareStreamAudioChanged;

  /// Whether stream menus should escape to the app root overlay.
  ///
  /// Detached transparent windows provide a local Overlay boundary so menu
  /// surfaces stay inside the transparent Flutter view instead of compositing
  /// against the root app overlay.
  final bool useRootOverlayForMenus;

  @override
  State<VoipStreamView> createState() => _VoipStreamViewState();
}

@visibleForTesting
Future<void> debugCancelVoipStreamViewSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelVoipStreamViewSubscription(
    subscription,
    content: 'Recovered call tile stream subscription cancel failure',
  );
}

@visibleForTesting
Widget? debugGameActivityPillForTesting({
  UserActivity? activity,
  String? presenceText,
  bool compact = true,
  double maxWidth = 180,
  bool overlay = true,
}) {
  return _buildGameActivityPill(
    activity: activity,
    presenceText: presenceText,
    compact: compact,
    maxWidth: maxWidth,
    overlay: overlay,
  );
}

Widget? _buildGameActivityPill({
  required UserActivity? activity,
  required String? presenceText,
  required bool compact,
  required double maxWidth,
  required bool overlay,
}) {
  return GameActivityOverlayPill.maybeFromActivity(
        activity,
        compact: compact,
        maxWidth: maxWidth,
        overlay: overlay,
      ) ??
      GameActivityOverlayPill.maybeFromPresenceText(
        presenceText,
        compact: compact,
        maxWidth: maxWidth,
        overlay: overlay,
      );
}

@visibleForTesting
bool debugShouldShowLocalStreamOptionsMenuForTesting({
  required bool isLocalUser,
  required VoipStreamType streamType,
  required bool isVideoHidden,
  required bool hasStopStreaming,
  required bool hasQualitySelection,
  required bool hasAudioSharingSelection,
}) {
  return _shouldShowLocalStreamOptionsMenu(
    isLocalUser: isLocalUser,
    streamType: streamType,
    isVideoHidden: isVideoHidden,
    hasStopStreaming: hasStopStreaming,
    hasQualitySelection: hasQualitySelection,
    hasAudioSharingSelection: hasAudioSharingSelection,
  );
}

@visibleForTesting
bool debugShouldKeepStreamTileActionsVisibleForTesting({
  required bool mobile,
  required bool hovering,
  required bool streamMenuOpen,
  required bool forceActionButtonsVisible,
}) {
  return mobile || hovering || streamMenuOpen || forceActionButtonsVisible;
}

@visibleForTesting
bool debugShouldUseStreamMenuRootOverlayForTesting({
  required bool useRootOverlayForMenus,
}) {
  return _shouldUseStreamMenuRootOverlay(
    useRootOverlayForMenus: useRootOverlayForMenus,
  );
}

@visibleForTesting
String debugHiddenPreviewStateLabelForTesting({
  required VoipStreamType streamType,
  bool localPreviewAutoPaused = false,
}) {
  return _hiddenPreviewStateLabelFor(
    streamType: streamType,
    localPreviewAutoPaused: localPreviewAutoPaused,
  );
}

@visibleForTesting
String debugHiddenPreviewActionLabelForTesting({
  required VoipStreamType streamType,
  required bool canReveal,
  bool localPreviewAutoPaused = false,
}) {
  return _hiddenPreviewActionLabelFor(
    streamType: streamType,
    localPreviewAutoPaused: localPreviewAutoPaused,
    canReveal: canReveal,
  );
}

@visibleForTesting
String? debugHiddenPreviewDetailLabelForTesting({
  bool localPreviewAutoPaused = false,
}) {
  return _hiddenPreviewDetailLabelFor(
    localPreviewAutoPaused: localPreviewAutoPaused,
  );
}

@visibleForTesting
bool debugShouldShowLocalPreviewPerformanceWarningForTesting({
  required bool isLocalUser,
  required VoipStreamType streamType,
  required bool isVideoHidden,
  required bool showLocalPreviewPerformanceWarning,
}) {
  return _shouldShowLocalPreviewPerformanceWarning(
    isLocalUser: isLocalUser,
    streamType: streamType,
    isVideoHidden: isVideoHidden,
    showLocalPreviewPerformanceWarning: showLocalPreviewPerformanceWarning,
  );
}

String _hiddenPreviewStateLabelFor({
  required VoipStreamType streamType,
  required bool localPreviewAutoPaused,
}) {
  if (localPreviewAutoPaused) {
    return 'Stream preview paused';
  }

  return streamType == VoipStreamType.screenshare
      ? 'Screen share hidden'
      : 'Video hidden';
}

String _hiddenPreviewActionLabelFor({
  required VoipStreamType streamType,
  required bool localPreviewAutoPaused,
  required bool canReveal,
}) {
  if (!canReveal) {
    return 'Hidden';
  }
  if (localPreviewAutoPaused) {
    return 'Show preview';
  }

  return streamType == VoipStreamType.screenshare
      ? 'Show screen share'
      : 'Show video';
}

String? _hiddenPreviewDetailLabelFor({required bool localPreviewAutoPaused}) {
  if (!localPreviewAutoPaused) {
    return null;
  }

  return 'Paused to save performance. Viewers still receive the stream.';
}

bool _shouldShowLocalPreviewPerformanceWarning({
  required bool isLocalUser,
  required VoipStreamType streamType,
  required bool isVideoHidden,
  required bool showLocalPreviewPerformanceWarning,
}) {
  return isLocalUser &&
      streamType == VoipStreamType.screenshare &&
      !isVideoHidden &&
      showLocalPreviewPerformanceWarning;
}

bool _shouldShowLocalStreamOptionsMenu({
  required bool isLocalUser,
  required VoipStreamType streamType,
  required bool isVideoHidden,
  required bool hasStopStreaming,
  required bool hasQualitySelection,
  required bool hasAudioSharingSelection,
}) {
  return isLocalUser &&
      !isVideoHidden &&
      streamType == VoipStreamType.screenshare &&
      (hasStopStreaming || hasQualitySelection || hasAudioSharingSelection);
}

bool _shouldUseStreamMenuRootOverlay({required bool useRootOverlayForMenus}) {
  return useRootOverlayForMenus;
}

Future<void> _cancelVoipStreamViewSubscription(
  StreamSubscription? subscription, {
  required String content,
}) async {
  if (subscription == null) {
    return;
  }

  try {
    await subscription.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: content,
      category: LogCategory.webrtc,
      source: 'voip-stream-view',
    );
  }
}

class _VoipStreamViewState extends State<VoipStreamView>
    with TickerProviderStateMixin {
  final MenuController _streamOptionsMenuController = MenuController();
  final MenuController _streamQualityMenuController = MenuController();
  late Member user;

  late AnimationController audioLevel;
  late List<StreamSubscription> subs;
  StreamSubscription? _volumeStreamSub;

  late GlobalKey rendererKey = GlobalKey();
  bool _isHovering = false;
  bool _streamOptionsMenuOpen = false;

  @override
  void initState() {
    super.initState();
    Log.d("Initializing stream view!");
    final room = widget.session.client.getRoom(widget.session.roomId)!;
    subs = [];
    _subscribeToStreamSignals();
    user = room.getMemberOrFallback(widget.stream.streamUserId);

    audioLevel = AnimationController(
      vsync: this,
      duration: CallView.volumeAnimationDuration,
    );
    _subscribeToVolumeStream();
  }

  @override
  void didUpdateWidget(covariant VoipStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream ||
        oldWidget.session != widget.session) {
      _cancelStreamSignalSubscriptions();
      _subscribeToStreamSignals();
      final room = widget.session.client.getRoom(widget.session.roomId)!;
      user = room.getMemberOrFallback(widget.stream.streamUserId);
    }
    if (oldWidget.volumeStream != widget.volumeStream ||
        oldWidget.stream != widget.stream) {
      _cancelVolumeStreamSubscription();
      _subscribeToVolumeStream();
    }
  }

  @override
  void dispose() {
    audioLevel.stop();
    audioLevel.dispose();
    _cancelVolumeStreamSubscription();
    _cancelStreamSignalSubscriptions();
    super.dispose();
  }

  void _handleStreamOptionsMenuOpen() {
    if (!mounted || _streamOptionsMenuOpen) {
      return;
    }
    setState(() => _streamOptionsMenuOpen = true);
  }

  void _handleStreamOptionsMenuClose() {
    _streamQualityMenuController.close();
    if (!mounted || !_streamOptionsMenuOpen) {
      return;
    }
    setState(() => _streamOptionsMenuOpen = false);
  }

  void _handleTileHoverExit() {
    if (_streamOptionsMenuOpen) {
      return;
    }
    setState(() => _isHovering = false);
  }

  void _subscribeToStreamSignals() {
    subs = [
      widget.stream.onStreamChanged.listen(onStreamChanged),
      widget.session.onUpdateVolumeVisualizers.listen((_) => timer()),
    ];
  }

  void _cancelStreamSignalSubscriptions() {
    final subscriptions = subs;
    subs = [];
    for (final sub in subscriptions) {
      _cancelStreamSubscription(
        sub,
        content: 'Recovered call tile stream subscription cancel failure',
      );
    }
  }

  void _cancelVolumeStreamSubscription() {
    final subscription = _volumeStreamSub;
    _volumeStreamSub = null;
    _cancelStreamSubscription(
      subscription,
      content: 'Recovered call tile volume subscription cancel failure',
    );
  }

  void _cancelStreamSubscription(
    StreamSubscription? subscription, {
    required String content,
  }) {
    unawaited(
      _cancelVoipStreamViewSubscription(subscription, content: content),
    );
  }

  void timer() {
    if (!mounted) {
      return;
    }

    audioLevel.animateTo(widget.stream.audiolevel);
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  bool get isLocalUser =>
      widget.stream.streamUserId == widget.session.client.self?.identifier;

  /// Whether a context menu should be shown for this tile.
  /// Volume and admin items are only wired for remote participants; for the
  /// local tile the menu still appears when onHideToggle is provided so the
  /// user can hide/show their own video to save on render cost.
  bool get _hasContextMenu =>
      widget.onVolumeChanged != null ||
      widget.onRemoveFromCall != null ||
      widget.onHideToggle != null;

  double get _currentVolume {
    final stream = widget.volumeStream ?? widget.stream;
    if (stream is LocalPlaybackVolumeStream) {
      return (stream as LocalPlaybackVolumeStream).localVolume;
    }
    return 1.0;
  }

  bool get _currentlyLocallyMuted {
    final stream = widget.volumeStream ?? widget.stream;
    if (stream is LocalPlaybackVolumeStream) {
      return (stream as LocalPlaybackVolumeStream).locallyMuted;
    }
    return false;
  }

  bool get _supportsHiddenPreview =>
      widget.stream.type == VoipStreamType.video ||
      widget.stream.type == VoipStreamType.screenshare;

  String get _hiddenPreviewStateLabel => _hiddenPreviewStateLabelFor(
    streamType: widget.stream.type,
    localPreviewAutoPaused: widget.localPreviewAutoPaused,
  );

  String _hiddenPreviewActionLabel(bool canReveal) =>
      _hiddenPreviewActionLabelFor(
        streamType: widget.stream.type,
        localPreviewAutoPaused: widget.localPreviewAutoPaused,
        canReveal: canReveal,
      );

  String? get _hiddenPreviewDetailLabel => _hiddenPreviewDetailLabelFor(
    localPreviewAutoPaused: widget.localPreviewAutoPaused,
  );

  bool get _showsLocalPreviewPerformanceWarning =>
      _shouldShowLocalPreviewPerformanceWarning(
        isLocalUser: isLocalUser,
        streamType: widget.stream.type,
        isVideoHidden: widget.isVideoHidden,
        showLocalPreviewPerformanceWarning:
            widget.showLocalPreviewPerformanceWarning,
      );

  void _subscribeToVolumeStream() {
    final volumeStream = widget.volumeStream;
    if (volumeStream == null || identical(volumeStream, widget.stream)) {
      return;
    }

    _volumeStreamSub = volumeStream.onStreamChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  VoidCallback? get _tapAction {
    if (widget.isVideoHidden) {
      return widget.onVisibilityToggle ?? widget.onHideToggle ?? widget.onTap;
    }

    return widget.onTap;
  }

  List<tiamat.ContextMenuItem> _buildContextMenuItems() {
    final items = <tiamat.ContextMenuItem>[];

    if (widget.onVolumeChanged != null) {
      // Mute / unmute toggle
      final muted = _currentlyLocallyMuted;
      items.add(
        tiamat.ContextMenuItem(
          text: muted ? "Unmute" : "Mute",
          icon: muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          onPressed: () {
            final newVolume = muted ? widget.defaultVolume : 0.0;
            widget.onVolumeChanged?.call(newVolume);
            setState(() {});
          },
        ),
      );

      // Volume slider — desktop only.  The mobile bottom sheet renders items
      // via TextButton and ignores customBuilder, so the slider would be
      // invisible on mobile; the mute toggle above is sufficient there.
      if (Layout.desktop)
        items.add(
          tiamat.ContextMenuItem(
            text: "Volume",
            customBuilder: (context, close) => StatefulBuilder(
              builder: (context, setSliderState) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_down_rounded, size: 18),
                    Expanded(
                      child: Slider(
                        value: _currentVolume,
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        onChanged: (val) {
                          setSliderState(() {});
                          widget.onVolumeChanged?.call(val);
                        },
                      ),
                    ),
                    const Icon(Icons.volume_up_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
        );
    }

    if (widget.onHideToggle != null) {
      items.add(
        tiamat.ContextMenuItem(
          text: widget.isVideoHidden ? "Show video" : "Hide video",
          icon: widget.isVideoHidden
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
          onPressed: widget.onHideToggle,
        ),
      );
    }

    if (widget.onRemoveFromCall != null) {
      items.add(
        tiamat.ContextMenuItem(
          text: "Remove from call",
          icon: Icons.phone_disabled_rounded,
          color: Colors.red,
          onPressed: widget.onRemoveFromCall,
        ),
      );
    }

    return items;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: audioLevel,
      builder: (context, child) {
        final borderRadius = BorderRadius.circular(widget.edgeToEdge ? 0 : 22);
        final baseBorderColor =
            widget.borderColor ??
            Theme.of(context).colorScheme.outlineVariant.withAlpha(
              widget.isFocused ? 220 : 110,
            );
        final boxShadow = widget.edgeToEdge
            ? const <BoxShadow>[]
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(widget.isFocused ? 70 : 30),
                  blurRadius: widget.isFocused ? 24 : 12,
                  offset: const Offset(0, 10),
                ),
              ];

        Widget tile = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tapAction,
          onDoubleTap: widget.isVideoHidden ? null : widget.onDoubleTap,
          child: AnimatedContainer(
            duration: InterGalacticMotion.duration(
              context,
              InterGalacticMotion.shortEmphasis,
            ),
            curve: InterGalacticMotion.standardOut,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: widget.edgeToEdge
                  ? null
                  : Border.all(
                      color: baseBorderColor,
                      width: widget.isFocused ? 2 : 1,
                    ),
              boxShadow: boxShadow,
            ),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  Positioned.fill(child: buildDefault(context)),
                  if (widget.showTileChrome && widget.showTileScrim)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withAlpha(50),
                              Colors.black.withAlpha(180),
                            ],
                            stops: const [0.45, 0.7, 1.0],
                          ),
                        ),
                      ),
                    ),
                  if (widget.isVideoHidden && _supportsHiddenPreview)
                    Center(child: buildHiddenPreview(context)),
                  if (_showsLocalPreviewPerformanceWarning)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: buildLocalPreviewPerformanceWarning(context),
                      ),
                    ),
                  if (widget.showTileChrome &&
                      _showsActionButtons &&
                      debugShouldKeepStreamTileActionsVisibleForTesting(
                        mobile: Layout.mobile,
                        hovering: _isHovering,
                        streamMenuOpen: _streamOptionsMenuOpen,
                        forceActionButtonsVisible:
                            widget.forceActionButtonsVisible,
                      ))
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_showsVisibilityButton)
                            buildActionButton(
                              icon: Icons.visibility_off_rounded,
                              semanticLabel: 'Hide screen share',
                              persistentLabel: 'Hide',
                              onPressed: widget.onVisibilityToggle,
                            ),
                          if (_showsVolumeButton)
                            Padding(
                              padding: EdgeInsets.only(
                                top: _showsVisibilityButton ? 8 : 0,
                              ),
                              child: buildActionButton(
                                icon: _currentlyLocallyMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                semanticLabel: _currentlyLocallyMuted
                                    ? 'Unmute participant audio'
                                    : 'Mute participant audio',
                                persistentLabel: _currentlyLocallyMuted
                                    ? 'Unmute'
                                    : 'Mute',
                                onPressed: () {
                                  final newVolume = _currentlyLocallyMuted
                                      ? widget.defaultVolume
                                      : 0.0;
                                  widget.onVolumeChanged?.call(newVolume);
                                  setState(() {});
                                },
                              ),
                            ),
                          if (widget.onPopout != null)
                            Padding(
                              padding: EdgeInsets.only(
                                top:
                                    _showsVisibilityButton || _showsVolumeButton
                                    ? 8
                                    : 0,
                              ),
                              child: buildActionButton(
                                icon: Icons.open_in_new_rounded,
                                semanticLabel: 'Pop stream out',
                                persistentLabel: 'Pop out',
                                onPressed: widget.onPopout,
                              ),
                            ),
                          if (_canShowFullscreen)
                            Padding(
                              padding: EdgeInsets.only(
                                top:
                                    widget.onPopout != null ||
                                        _showsVisibilityButton ||
                                        _showsVolumeButton
                                    ? 8
                                    : 0,
                              ),
                              child: buildActionButton(
                                icon: Icons.fullscreen,
                                semanticLabel: 'Open fullscreen',
                                persistentLabel: 'Full',
                                onPressed: widget.onFullscreen,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (widget.showTileChrome && _showsStreamOptionsMenu)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: buildStreamOptionsMenuButton(context),
                    ),
                  if (widget.showTileChrome)
                    Positioned(
                      left: 12,
                      right: _showsStreamOptionsMenu ? 64 : 12,
                      bottom: 12,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(child: buildNamePill(context)),
                          if (_gameActivityPill != null) ...[
                            const SizedBox(width: 8),
                            Flexible(child: _gameActivityPill!),
                          ],
                          const SizedBox(width: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: buildStatusBadges(context),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        if (_hasContextMenu) {
          tile = AdaptiveContextMenu(
            items: _buildContextMenuItems(),
            child: tile,
          );
        }

        if (Layout.desktop) {
          tile = MouseRegion(
            onEnter: (_) => setState(() => _isHovering = true),
            onExit: (_) => _handleTileHoverExit(),
            child: tile,
          );
        }

        return tile;
      },
    );
  }

  bool get _canShowFullscreen =>
      !widget.isVideoHidden &&
      widget.canFullscreen &&
      (widget.stream.type == VoipStreamType.video ||
          widget.stream.type == VoipStreamType.screenshare);

  bool get _showsVisibilityButton =>
      !widget.isVideoHidden &&
      widget.stream.type == VoipStreamType.screenshare &&
      widget.onVisibilityToggle != null;

  bool get _showsVolumeButton =>
      !widget.isVideoHidden && !isLocalUser && widget.onVolumeChanged != null;

  bool get _showsActionButtons =>
      !widget.isVideoHidden &&
      (_showsVisibilityButton ||
          _showsVolumeButton ||
          _canShowFullscreen ||
          widget.onPopout != null);

  bool get _hasStreamQualitySelection =>
      widget.onStreamQualitySelected != null &&
      widget.streamQualityProfiles.isNotEmpty;

  bool get _hasShareStreamAudioSelection =>
      widget.onShareStreamAudioChanged != null &&
      widget.shareStreamAudio != null;

  bool get _showsStreamOptionsMenu {
    return _shouldShowLocalStreamOptionsMenu(
      isLocalUser: isLocalUser,
      streamType: widget.stream.type,
      isVideoHidden: widget.isVideoHidden,
      hasStopStreaming: widget.onStopStreaming != null,
      hasQualitySelection: _hasStreamQualitySelection,
      hasAudioSharingSelection: _hasShareStreamAudioSelection,
    );
  }

  MenuStyle _streamMenuStyle(BuildContext context, {double maxWidth = 240}) {
    final colorScheme = Theme.of(context).colorScheme;
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll<Color?>(
        colorScheme.surfaceContainer,
      ),
      surfaceTintColor: const WidgetStatePropertyAll<Color?>(
        Colors.transparent,
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(vertical: 5),
      ),
      maximumSize: WidgetStatePropertyAll<Size?>(Size(maxWidth, 360)),
      side: WidgetStatePropertyAll<BorderSide?>(
        BorderSide(color: colorScheme.outlineVariant.withAlpha(120)),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder?>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  ButtonStyle _streamMenuItemStyle(BuildContext context, {double width = 220}) {
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size?>(Size(width, 44)),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder?>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _closeStreamQualitySubmenuOnHover(Widget child) {
    return MouseRegion(
      onEnter: (_) => _streamQualityMenuController.close(),
      child: child,
    );
  }

  Widget buildStreamOptionsMenuButton(BuildContext context) {
    final menuStyle = _streamMenuStyle(context);
    final itemStyle = _streamMenuItemStyle(context);
    return MenuAnchor(
      controller: _streamOptionsMenuController,
      style: menuStyle,
      alignmentOffset: const Offset(0, -8),
      consumeOutsideTap: true,
      useRootOverlay: _shouldUseStreamMenuRootOverlay(
        useRootOverlayForMenus: widget.useRootOverlayForMenus,
      ),
      onOpen: _handleStreamOptionsMenuOpen,
      onClose: _handleStreamOptionsMenuClose,
      menuChildren: [
        if (widget.onStopStreaming != null)
          _closeStreamQualitySubmenuOnHover(
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(
                Icons.stop_screen_share_rounded,
                size: 18,
              ),
              onPressed: () {
                _streamOptionsMenuController.close();
                widget.onStopStreaming?.call();
              },
              child: const SizedBox(width: 164, child: Text('Stop streaming')),
            ),
          ),
        if (_hasStreamQualitySelection)
          SubmenuButton(
            controller: _streamQualityMenuController,
            style: itemStyle,
            menuStyle: _streamMenuStyle(context, maxWidth: 250),
            trailingIcon: const SizedBox.shrink(),
            menuChildren: [
              for (final profile in widget.streamQualityProfiles)
                _buildStreamQualityMenuItem(context, profile),
            ],
            child: const SizedBox(width: 164, child: Text('Stream quality')),
          ),
        if (_hasShareStreamAudioSelection)
          _closeStreamQualitySubmenuOnHover(
            CheckboxMenuButton(
              style: itemStyle,
              value: widget.shareStreamAudio ?? false,
              onChanged: widget.canChangeShareStreamAudio
                  ? (value) {
                      _streamOptionsMenuController.close();
                      widget.onShareStreamAudioChanged?.call(value ?? false);
                    }
                  : null,
              child: const SizedBox(
                width: 164,
                child: Text('Share stream audio'),
              ),
            ),
          ),
      ],
      builder: (context, controller, child) {
        return CallControlActionButton(
          icon: Icons.more_horiz_rounded,
          semanticLabel: 'Open stream options',
          tooltip: 'Stream options',
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }

  Widget _buildStreamQualityMenuItem(
    BuildContext context,
    ScreenShareQualityProfile profile,
  ) {
    final selected =
        !widget.streamAdvancedOverrideEnabled &&
        widget.selectedStreamQualityProfile == profile;
    return MenuItemButton(
      style: _streamMenuItemStyle(context, width: 230),
      leadingIcon: selected
          ? const Icon(Icons.check_rounded, size: 18)
          : const SizedBox(width: 18, height: 18),
      onPressed: () {
        _streamOptionsMenuController.close();
        widget.onStreamQualitySelected?.call(profile);
      },
      child: SizedBox(
        width: 174,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(profile.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              profile.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildActionButton({
    required IconData icon,
    required String semanticLabel,
    required String persistentLabel,
    required VoidCallback? onPressed,
  }) {
    return CallControlActionButton(
      icon: icon,
      semanticLabel: semanticLabel,
      persistentLabel: persistentLabel,
      onPressed: onPressed,
    );
  }

  Widget buildHiddenPreview(BuildContext context) {
    final canReveal = _tapAction != null;
    final actionLabel = _hiddenPreviewActionLabel(canReveal);
    final detailLabel = _hiddenPreviewDetailLabel;

    return Semantics(
      container: true,
      button: canReveal,
      enabled: canReveal,
      label: _hiddenPreviewStateLabel,
      hint: canReveal
          ? (detailLabel == null ? actionLabel : '$actionLabel. $detailLabel')
          : null,
      onTap: _tapAction,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(138),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withAlpha(44)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_rounded,
                      size: 34,
                      color: Colors.white.withAlpha(218),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hiddenPreviewStateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withAlpha(232),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      actionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withAlpha(188),
                      ),
                    ),
                    if (detailLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        detailLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withAlpha(204),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildLocalPreviewPerformanceWarning(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Stream preview is visible and may affect performance. '
          'Viewers still receive the stream.',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(162),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withAlpha(48)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Colors.amberAccent.withAlpha(230),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Preview visible; may affect performance',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withAlpha(228),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildDefault(BuildContext context) {
    switch (widget.stream.type) {
      case VoipStreamType.audio:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                user.defaultColor.withAlpha(220),
                user.defaultColor.withAlpha(120),
                Theme.of(context).colorScheme.surfaceContainerHighest,
              ],
            ),
          ),
          child: Center(
            child: AnimatedOpacity(
              opacity: widget.isMicrophoneMuted ? 0.55 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: tiamat.Avatar(
                border: Border.all(
                  strokeAlign: 0.5,
                  color: getBorderColor(context),
                  width: clampDouble(audioLevel.value * 15, 0, 5),
                ),
                radius: 58,
                image: user.avatar,
                placeholderColor: user.defaultColor,
                placeholderText: user.displayName,
              ),
            ),
          ),
        );

      case VoipStreamType.video:
      case VoipStreamType.screenshare:
        if (widget.isVideoHidden && _supportsHiddenPreview) {
          // Blank dark panel — no VideoTrackRenderer is created, so LiveKit's
          // adaptiveStream naturally pauses/reduces the inbound video track.
          return const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xFF16181C)),
            child: SizedBox.expand(),
          );
        }
        return DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFF16181C)),
          child: Center(
            child:
                widget.stream.buildVideoRenderer(widget.fit, rendererKey) ??
                buildVisualFallback(context),
          ),
        );
    }
  }

  Widget buildNamePill(BuildContext context) {
    final label = isLocalUser
        ? "You"
        : (user.displayName.isNotEmpty ? user.displayName : user.identifier);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: tiamat.Text.labelLow(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget? get _gameActivityPill {
    return _buildGameActivityPill(
      activity: widget.gameActivity,
      presenceText: widget.gameActivityPresenceText,
      compact: true,
      maxWidth: Layout.mobile ? 150 : 180,
      overlay: true,
    );
  }

  List<Widget> buildStatusBadges(BuildContext context) {
    final badges = <Widget>[];

    if (widget.stream.type == VoipStreamType.screenshare) {
      badges.add(buildBadge(context, Icons.screen_share_rounded));
    }

    if (widget.isMicrophoneMuted) {
      badges.add(buildBadge(context, Icons.mic_off_rounded));
    }

    if (_currentlyLocallyMuted && !isLocalUser) {
      badges.add(buildBadge(context, Icons.volume_off_rounded));
    }

    if (isLocalUser && widget.stream.type == VoipStreamType.video) {
      badges.add(buildBadge(context, Icons.videocam_rounded));
    }

    return badges;
  }

  Widget buildBadge(BuildContext context, IconData icon) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget buildVisualFallback(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            user.defaultColor.withAlpha(200),
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: widget.stream.type == VoipStreamType.screenshare
            ? Icon(
                Icons.screen_share_rounded,
                size: 54,
                color: Theme.of(context).colorScheme.onSurface,
              )
            : tiamat.Avatar(
                radius: 50,
                image: user.avatar,
                placeholderColor: user.defaultColor,
                placeholderText: user.displayName,
              ),
      ),
    );
  }

  Color getBorderColor(BuildContext context) {
    return Color.lerp(
      Theme.of(context).primaryColor,
      Theme.of(context).colorScheme.primary,
      audioLevel.value,
    )!;
  }

  void onStreamChanged(void event) {
    if (!mounted) {
      return;
    }

    setState(() {});
  }
}
