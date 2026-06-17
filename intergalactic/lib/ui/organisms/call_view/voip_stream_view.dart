import 'dart:async';

import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class VoipStreamView extends StatefulWidget {
  const VoipStreamView(this.stream, this.session,
      {super.key,
      this.fit = BoxFit.cover,
      this.borderColor,
      this.canFullscreen = true,
      this.isFocused = false,
      this.edgeToEdge = false,
      this.showTileChrome = true,
      this.showTileScrim = true,
      this.isMicrophoneMuted = false,
      this.isVideoHidden = false,
      this.onFullscreen,
      this.onTap,
      this.onPopout,
      this.volumeStream,
      this.defaultVolume = 1.0,
      this.onVolumeChanged,
      this.onVisibilityToggle,
      this.onRemoveFromCall,
      this.onHideToggle});
  final VoipStream stream;
  final VoipSession session;
  final BoxFit fit;
  final Function()? onFullscreen;
  final VoidCallback? onTap;
  final VoidCallback? onPopout;
  final Color? borderColor;
  final bool canFullscreen;
  final bool isFocused;
  final bool edgeToEdge;
  final bool showTileChrome;
  final bool showTileScrim;
  final bool isMicrophoneMuted;
  final VoipStream? volumeStream;
  final double defaultVolume;

  /// Whether this stream's visual content is currently hidden behind the
  /// blank reveal panel.
  final bool isVideoHidden;

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

  @override
  State<VoipStreamView> createState() => _VoipStreamViewState();
}

class _VoipStreamViewState extends State<VoipStreamView>
    with TickerProviderStateMixin {
  late Member user;

  late AnimationController audioLevel;
  late List<StreamSubscription> subs;
  StreamSubscription? _volumeStreamSub;

  late GlobalKey rendererKey = GlobalKey();
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    Log.d("Initializing stream view!");
    final room = widget.session.client.getRoom(widget.session.roomId)!;
    subs = [];
    _subscribeToStreamSignals();
    user = room.getMemberOrFallback(widget.stream.streamUserId);

    audioLevel = AnimationController(
        vsync: this, duration: CallView.volumeAnimationDuration);
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
      _volumeStreamSub?.cancel();
      _volumeStreamSub = null;
      _subscribeToVolumeStream();
    }
  }

  @override
  void dispose() {
    audioLevel.stop();
    _volumeStreamSub?.cancel();
    _cancelStreamSignalSubscriptions();
    super.dispose();
  }

  void _subscribeToStreamSignals() {
    subs = [
      widget.stream.onStreamChanged.listen(onStreamChanged),
      widget.session.onUpdateVolumeVisualizers.listen((_) => timer()),
    ];
  }

  void _cancelStreamSignalSubscriptions() {
    for (final sub in subs) {
      sub.cancel();
    }
    subs = [];
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
      items.add(tiamat.ContextMenuItem(
        text: muted ? "Unmute" : "Mute",
        icon: muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        onPressed: () {
          final newVolume = muted ? widget.defaultVolume : 0.0;
          widget.onVolumeChanged?.call(newVolume);
          setState(() {});
        },
      ));

      // Volume slider — desktop only.  The mobile bottom sheet renders items
      // via TextButton and ignores customBuilder, so the slider would be
      // invisible on mobile; the mute toggle above is sufficient there.
      if (Layout.desktop)
        items.add(tiamat.ContextMenuItem(
          text: "Volume",
          customBuilder: (context, close) => StatefulBuilder(
            builder: (context, setSliderState) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
        ));
    }

    if (widget.onHideToggle != null) {
      items.add(tiamat.ContextMenuItem(
        text: widget.isVideoHidden ? "Show video" : "Hide video",
        icon: widget.isVideoHidden
            ? Icons.visibility_rounded
            : Icons.visibility_off_rounded,
        onPressed: widget.onHideToggle,
      ));
    }

    if (widget.onRemoveFromCall != null) {
      items.add(tiamat.ContextMenuItem(
        text: "Remove from call",
        icon: Icons.phone_disabled_rounded,
        color: Colors.red,
        onPressed: widget.onRemoveFromCall,
      ));
    }

    return items;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: audioLevel,
        builder: (context, child) {
          final borderRadius =
              BorderRadius.circular(widget.edgeToEdge ? 0 : 22);
          final baseBorderColor = widget.borderColor ??
              Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withAlpha(widget.isFocused ? 220 : 110);
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
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
                      Center(
                        child: IgnorePointer(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility_off_rounded,
                                size: 36,
                                color: Colors.white.withAlpha(
                                    _isHovering || Layout.mobile ? 210 : 80),
                              ),
                              if (_isHovering || Layout.mobile) ...[
                                const SizedBox(height: 6),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(120),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    child: tiamat.Text.labelLow("Tap to show"),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (widget.showTileChrome &&
                        _showsActionButtons &&
                        (Layout.mobile || _isHovering))
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showsVisibilityButton)
                              buildActionButton(
                                icon: Icons.visibility_off_rounded,
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
                                  top: _showsVisibilityButton ||
                                          _showsVolumeButton
                                      ? 8
                                      : 0,
                                ),
                                child: buildActionButton(
                                  icon: Icons.open_in_new_rounded,
                                  onPressed: widget.onPopout,
                                ),
                              ),
                            if (_canShowFullscreen)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: widget.onPopout != null ||
                                          _showsVisibilityButton ||
                                          _showsVolumeButton
                                      ? 8
                                      : 0,
                                ),
                                child: buildActionButton(
                                  icon: Icons.fullscreen,
                                  onPressed: widget.onFullscreen,
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (widget.showTileChrome)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(child: buildNamePill(context)),
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
              onExit: (_) => setState(() => _isHovering = false),
              child: tile,
            );
          }

          return tile;
        });
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

  Widget buildActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.black.withAlpha(110),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 36,
        height: 36,
        child: tiamat.IconButton(
          icon: icon,
          size: 18,
          onPressed: onPressed,
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
            child: widget.stream.buildVideoRenderer(widget.fit, rendererKey) ??
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
        child: tiamat.Text.labelLow(
          label,
          overflow: TextOverflow.ellipsis,
        ),
      ),
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
    return Color.lerp(Theme.of(context).primaryColor,
        Theme.of(context).colorScheme.primary, audioLevel.value)!;
  }

  void onStreamChanged(void event) {
    if (!mounted) {
      return;
    }

    setState(() {});
  }
}
