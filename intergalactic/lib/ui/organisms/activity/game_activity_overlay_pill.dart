import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/game_activity_overlay.dart';

class GameActivityOverlayPill extends StatelessWidget {
  const GameActivityOverlayPill({
    required this.title,
    this.artworkUrl,
    this.compact = false,
    this.maxWidth = 190,
    this.overlay = true,
    super.key,
  });

  final String title;
  final String? artworkUrl;
  final bool compact;
  final double maxWidth;
  final bool overlay;

  static Widget? maybeFromActivity(
    UserActivity? activity, {
    bool compact = false,
    double maxWidth = 190,
    bool overlay = true,
  }) {
    if (!isGameActivityRenderable(activity)) {
      return null;
    }

    return GameActivityOverlayPill(
      key: const Key('game-activity-overlay-pill'),
      title: gameActivityTitle(activity!),
      artworkUrl: activity.artworkUrl,
      compact: compact,
      maxWidth: maxWidth,
      overlay: overlay,
    );
  }

  static Widget? maybeFromPresenceText(
    String? statusText, {
    bool compact = false,
    double maxWidth = 190,
    bool overlay = true,
  }) {
    final title = gameActivityTitleFromPresenceText(statusText);
    if (title == null) {
      return null;
    }

    return GameActivityOverlayPill(
      key: const Key('game-activity-overlay-pill'),
      title: title,
      compact: compact,
      maxWidth: maxWidth,
      overlay: overlay,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconSize = compact ? 18.0 : 22.0;
    final horizontalPadding = compact ? 7.0 : 9.0;
    final verticalPadding = compact ? 4.0 : 6.0;
    final textStyle = (compact
            ? Theme.of(context).textTheme.labelSmall
            : Theme.of(context).textTheme.bodySmall)
        ?.copyWith(
      color: overlay ? Colors.white : scheme.onSurface,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.1,
    );

    final background = overlay
        ? Colors.black.withAlpha(150)
        : scheme.surfaceContainerHigh.withValues(alpha: 0.9);
    final borderColor = overlay
        ? Colors.white.withAlpha(36)
        : scheme.outline.withValues(alpha: 0.22);

    return Semantics(
      label: 'Playing $title',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(compact ? 9 : 12),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GameActivityIcon(
                  artworkUrl: artworkUrl,
                  size: iconSize,
                  overlay: overlay,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
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

class _GameActivityIcon extends StatelessWidget {
  const _GameActivityIcon({
    required this.size,
    required this.overlay,
    this.artworkUrl,
  });

  final String? artworkUrl;
  final double size;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final artworkUrl = this.artworkUrl;
    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      final imageData = _dataImageBytes(artworkUrl);
      if (imageData != null) {
        return _frame(
          Image.memory(
            imageData,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _fallback(context),
          ),
        );
      }

      return _frame(
        Image.network(
          artworkUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallback(context),
        ),
      );
    }

    return _fallback(context);
  }

  Widget _frame(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: size,
        height: size,
        child: child,
      ),
    );
  }

  Uint8List? _dataImageBytes(String value) {
    final separator = value.indexOf(',');
    if (separator == -1) {
      return null;
    }

    final header = value.substring(0, separator).toLowerCase();
    if (!header.startsWith('data:image/') || !header.endsWith(';base64')) {
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
    final iconColor = overlay ? Colors.white : scheme.primary;
    final background =
        overlay ? Colors.white.withAlpha(26) : scheme.surfaceContainerHighest;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.sports_esports_rounded,
          size: size * 0.68,
          color: iconColor,
        ),
      ),
    );
  }
}
