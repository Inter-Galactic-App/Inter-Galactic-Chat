import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_renderer.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';

class LocalActivityPanel extends StatefulWidget {
  const LocalActivityPanel({
    required this.child,
    required this.userPanelHeight,
    this.service,
    this.onHideActivity,
    this.showChildWhenActivity = true,
    super.key,
  });

  final Widget child;
  final double userPanelHeight;
  final ActivityService? service;
  final FutureOr<void> Function()? onHideActivity;
  final bool showChildWhenActivity;

  @override
  State<LocalActivityPanel> createState() => _LocalActivityPanelState();
}

class _LocalActivityPanelState extends State<LocalActivityPanel>
    with TickerProviderStateMixin {
  late ActivityService _service;
  StreamSubscription<UserActivity?>? _subscription;
  UserActivity? _activity;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? activityService;
    _activity = _service.currentActivity;
    _subscription = _service.onActivityChanged.listen((activity) {
      if (!mounted) return;
      setState(() {
        _activity = activity;
      });
    });
  }

  @override
  void didUpdateWidget(covariant LocalActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextService = widget.service ?? activityService;
    if (nextService == _service) {
      return;
    }

    _subscription?.cancel();
    _service = nextService;
    _activity = _service.currentActivity;
    _subscription = _service.onActivityChanged.listen((activity) {
      if (!mounted) return;
      setState(() {
        _activity = activity;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userPanel = SizedBox(
      height: widget.userPanelHeight,
      child: widget.child,
    );

    final activity = _activity;
    if (activity == null) {
      return userPanel;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TutorialAnchor(
            id: TutorialAnchorIds.activityCard,
            padding: const EdgeInsets.all(6),
            child: CompactActivityCard(
              activity: activity,
              service: _service,
              onHideActivity: widget.onHideActivity ?? _hideActivity,
            ),
          ),
          if (widget.showChildWhenActivity) userPanel,
        ],
      ),
    );
  }

  Future<void> _hideActivity() async {
    await preferences.activityHideCurrent.set(true);
    _service.refreshSettings();
  }
}

class CompactActivityCard extends StatelessWidget {
  const CompactActivityCard({
    required this.activity,
    required this.service,
    this.onHideActivity,
    super.key,
  });

  final UserActivity activity;
  final ActivityService service;
  final FutureOr<void> Function()? onHideActivity;

  static const ActivityRenderer _renderer = ActivityRenderer();

  @override
  Widget build(BuildContext context) {
    if (Layout.mobile) {
      return _buildMobile(context);
    }

    final scheme = Theme.of(context).colorScheme;
    final subtitle = _renderer.compactSubtitle(activity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: DecoratedBox(
        key: const Key('local-activity-card'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            children: [
              _ActivityArtwork(activity: activity),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _renderer.compactTitle(activity),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      activity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.secondary,
                            ),
                      ),
                  ],
                ),
              ),
              if (activity.controls.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: activity.controls
                      .map(
                        (control) => _ActivityControlButton(
                          control: control,
                          onPressed: () => service.executeControlForActivity(
                            activity,
                            control,
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (onHideActivity != null)
                Tooltip(
                  message: 'Hide activity',
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: 14,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    onPressed: () => onHideActivity?.call(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = _renderer.compactSubtitle(activity);
    final radius = BorderRadius.circular(MobileVisuals.cardRadius - 4);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: MobileGlassEdgeHighlight(
        key: const Key('local-activity-card'),
        borderRadius: radius,
        highlighted: activity.kind == ActivityKind.music,
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surfaceContainerLow.withValues(alpha: 0.9),
                  scheme.surface.withValues(alpha: 0.74),
                ],
              ),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  _ActivityArtwork(
                    activity: activity,
                    size: 44,
                    borderRadius: 14,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _renderer.compactTitle(activity),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.1,
                                  ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          activity.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (activity.controls.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: activity.controls
                          .map(
                            (control) => _ActivityControlButton(
                              control: control,
                              mobileStyle: true,
                              onPressed: () =>
                                  service.executeControlForActivity(
                                activity,
                                control,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (onHideActivity != null)
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: IconButton(
                        tooltip: 'Hide activity',
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 15,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onPressed: () => onHideActivity?.call(),
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
}

class _ActivityArtwork extends StatelessWidget {
  const _ActivityArtwork({
    required this.activity,
    this.size = 36,
    this.borderRadius = 5,
  });

  final UserActivity activity;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final artworkUrl = activity.artworkUrl;
    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      final imageData = _dataImageBytes(artworkUrl);
      if (imageData != null) {
        return _artworkFrame(
          context,
          Image.memory(
            imageData,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) => _fallback(context),
          ),
        );
      }

      return _artworkFrame(
        context,
        Image.network(
          artworkUrl,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) => _fallback(context),
        ),
      );
    }

    return _fallback(context);
  }

  Widget _artworkFrame(BuildContext context, Widget image) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
        child: SizedBox(
          width: size,
          height: size,
          child: image,
        ),
      ),
    );
  }

  Uint8List? _dataImageBytes(String value) {
    final separator = value.indexOf(',');
    if (!value.startsWith('data:image/') || separator == -1) {
      return null;
    }

    final header = value.substring(0, separator).toLowerCase();
    if (!header.endsWith(';base64')) {
      return null;
    }

    try {
      return base64Decode(value.substring(separator + 1));
    } on FormatException {
      return null;
    }
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: scheme.surfaceContainerHighest,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          _iconForKind(activity.kind),
          size: size * 0.5,
          color: scheme.primary,
        ),
      ),
    );
  }

  IconData _iconForKind(ActivityKind kind) {
    return switch (kind) {
      ActivityKind.music => Icons.music_note,
      ActivityKind.game => Icons.sports_esports,
      ActivityKind.call => Icons.call,
      ActivityKind.screenShare => Icons.screen_share,
      ActivityKind.custom => Icons.star,
    };
  }
}

class _ActivityControlButton extends StatelessWidget {
  const _ActivityControlButton({
    required this.control,
    required this.onPressed,
    this.mobileStyle = false,
  });

  final ActivityControl control;
  final VoidCallback onPressed;
  final bool mobileStyle;

  @override
  Widget build(BuildContext context) {
    if (mobileStyle) {
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(left: 3),
        child: Tooltip(
          message: control.tooltip ?? control.label,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.08),
              ),
            ),
            child: SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                icon: Icon(_iconForControl(control)),
                iconSize: 17,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: control.enabled ? onPressed : null,
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: control.tooltip ?? control.label,
      child: IconButton(
        icon: Icon(_iconForControl(control)),
        iconSize: 15,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 24, height: 26),
        onPressed: control.enabled ? onPressed : null,
      ),
    );
  }

  IconData _iconForControl(ActivityControl control) {
    if (control.kind == ActivityControlKind.playPause) {
      return control.label.toLowerCase() == 'pause'
          ? Icons.pause
          : Icons.play_arrow;
    }

    if (control.kind == ActivityControlKind.like) {
      return control.label.toLowerCase() == 'like'
          ? Icons.favorite_border
          : Icons.favorite;
    }

    return switch (control.kind) {
      ActivityControlKind.playPause => Icons.play_arrow,
      ActivityControlKind.previous => Icons.skip_previous,
      ActivityControlKind.next => Icons.skip_next,
      ActivityControlKind.like => Icons.favorite_border,
      ActivityControlKind.volume => Icons.volume_up,
      ActivityControlKind.openExternal => Icons.open_in_new,
      ActivityControlKind.hide => Icons.visibility_off,
      ActivityControlKind.custom => Icons.more_horiz,
    };
  }
}
