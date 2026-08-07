import 'package:flutter/material.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/components/photo_album_room/photo.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/matrix/components/photo_album_room/matrix_photo.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reactions.dart';

class PhotoAlbumThreadHeader extends StatelessWidget {
  const PhotoAlbumThreadHeader({
    required this.component,
    required this.threadRootEventId,
    super.key,
  });

  final PhotoAlbumRoom component;
  final String threadRootEventId;

  @override
  Widget build(BuildContext context) {
    final timeline = component.room.timeline;
    if (timeline == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<PhotoAlbumEntry?>(
      future: _findEntry(),
      builder: (context, snapshot) {
        final entry = snapshot.data;
        if (entry == null) {
          return const SizedBox.shrink();
        }

        final scheme = Theme.of(context).colorScheme;
        final root = entry.rootPhoto;
        final comments = root.threadReplyCount;
        final isMobile = Layout.mobile;
        final radius = isMobile
            ? MobileVisuals.cardBorderRadius
            : BorderRadius.circular(8);
        final content = DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow
                .withValues(alpha: isMobile ? 0.72 : 1),
            borderRadius: radius,
            border: Border.all(
              color: scheme.outlineVariant
                  .withValues(alpha: isMobile ? 0.32 : 0.48),
            ),
            boxShadow: [
              if (isMobile)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: isMobile ? 86 : 92,
                  height: isMobile ? 86 : 74,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isMobile ? 20 : 8),
                    child: _PhotoAlbumThreadPreview(entry: entry),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.isStack ? 'Photo Stack' : 'Photo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.isStack
                            ? '${entry.displayCount} photos'
                            : _attachmentLabel(entry.coverPhoto),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _HeaderPill(
                            icon: Icons.mode_comment_outlined,
                            label: comments == 0
                                ? 'Comments'
                                : '$comments ${comments == 1 ? "comment" : "comments"}',
                          ),
                          if (entry.isStack)
                            _HeaderPill(
                              icon: Icons.filter_none_rounded,
                              label: '${entry.displayCount}',
                            ),
                        ],
                      ),
                      _buildReactions(context, timeline, entry),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(10, isMobile ? 8 : 10, 10, 0),
          child: isMobile
              ? MobileGlassEdgeHighlight(
                  borderRadius: radius,
                  style: MobileGlassHighlightStyle.composer,
                  intensity: 0.7,
                  child: content,
                )
              : content,
        );
      },
    );
  }

  Future<PhotoAlbumEntry?> _findEntry() async {
    final timeline = await component.getTimeline();
    for (final entry in timeline.entries) {
      if (entry.rootPhoto.id == threadRootEventId) {
        return entry;
      }
    }

    return null;
  }

  Widget _buildReactions(
    BuildContext context,
    Timeline timeline,
    PhotoAlbumEntry entry,
  ) {
    final root = entry.rootPhoto;
    if (root is! MatrixPhoto ||
        root.event is! TimelineEventFeatureReactions ||
        !(root.event as TimelineEventFeatureReactions).hasReactions(timeline)) {
      return const SizedBox.shrink();
    }

    final index = timeline.events.indexWhere(
      (event) => event.eventId == root.event.eventId,
    );
    if (index < 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TimelineEventViewReactions(
        key: ValueKey('photo-thread-header-reactions-${root.event.eventId}'),
        initialIndex: index,
        timeline: timeline,
      ),
    );
  }

  String _attachmentLabel(Photo photo) {
    final attachment = photo.attachment;
    if (attachment is VideoAttachment) {
      return 'Video';
    }

    return 'Individual photo';
  }
}

class _PhotoAlbumThreadPreview extends StatelessWidget {
  const _PhotoAlbumThreadPreview({required this.entry});

  final PhotoAlbumEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.isStack) {
      final photos = entry.photos;
      final primary = photos.isNotEmpty ? photos.first : entry.coverPhoto;
      final secondary = photos.length > 1 ? photos[1] : primary;
      final isMobile = Layout.mobile;
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            left: isMobile ? 16 : 14,
            top: isMobile ? 14 : 12,
            child: Opacity(
              opacity: 0.48,
              child: _StackPreviewTile(photoPreview: _previewFor(secondary)),
            ),
          ),
          Positioned.fill(
            right: isMobile ? 10 : 10,
            bottom: isMobile ? 10 : 10,
            child: _StackPreviewTile(photoPreview: _previewFor(primary)),
          ),
        ],
      );
    }

    return _previewFor(entry.coverPhoto);
  }

  Widget _previewFor(Photo photo) {
    final attachment = photo.attachment;
    if (attachment is ImageAttachment) {
      return Image(
        image: attachment.image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }

    if (attachment is VideoAttachment && attachment.thumbnail != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: attachment.thumbnail!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
          const Align(
            alignment: Alignment.center,
            child: Icon(Icons.play_arrow_rounded, color: Colors.white),
          ),
        ],
      );
    }

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.16),
      child: const Icon(Icons.photo_outlined),
    );
  }
}

class _StackPreviewTile extends StatelessWidget {
  const _StackPreviewTile({required this.photoPreview});

  final Widget photoPreview;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Layout.mobile ? 16 : 8);
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          photoPreview,
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = Layout.mobile;
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            scheme.surfaceContainerHigh.withValues(alpha: isMobile ? 0.7 : 1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isMobile ? 0.34 : 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
