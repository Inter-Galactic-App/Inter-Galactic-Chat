import 'package:intergalactic/client/components/forum_room/forum_room_component.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/organisms/forum/forum_tag_label.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ForumPostCard extends StatelessWidget {
  const ForumPostCard({
    required this.post,
    required this.onTap,
    this.onEditTags,
    this.mobileStyle = false,
    super.key,
  });

  final ForumPost post;
  final VoidCallback onTap;

  /// Called when the user selects "Edit Tags" from the card context menu.
  /// When null no context menu is shown.
  final VoidCallback? onEditTags;
  final bool mobileStyle;

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  void _showContextMenu(BuildContext context, Offset globalOffset) {
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalOffset.dx,
        globalOffset.dy,
        globalOffset.dx + 1,
        globalOffset.dy + 1,
      ),
      items: [
        PopupMenuItem<void>(
          onTap: onEditTags,
          child: const ListTile(
            leading: Icon(Icons.label_outline),
            title: Text('Edit Tags'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mobileStyle) {
      return _buildMobile(context);
    }

    final scheme = Theme.of(context).colorScheme;

    final card = tiamat.Tile.surfaceContainer(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag chips
                if (post.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: post.tags
                          .map(
                            (tag) => Chip(
                              label: ForumTagLabel(tag),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide.none,
                              backgroundColor: scheme.secondaryContainer,
                            ),
                          )
                          .toList(),
                    ),
                  ),

                // Title
                tiamat.Text.labelEmphasised(post.title),

                const SizedBox(height: 4),

                if (post.previewImage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: ColoredBox(
                          color: scheme.surfaceContainerHighest,
                          child: Image(
                            image: post.previewImage!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Excerpt
                if (post.excerpt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: tiamat.Text.labelLow(
                      post.excerpt,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),

                // Footer row: avatar + name, reply count, timestamp
                Row(
                  children: [
                    // Author avatar
                    tiamat.Avatar(
                      radius: 10,
                      image: post.senderAvatar,
                      placeholderText: post.senderDisplayName ?? post.senderId,
                    ),
                    const SizedBox(width: 6),
                    // Author name
                    Expanded(
                      child: tiamat.Text.tiny(
                        post.senderDisplayName ?? post.senderId,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Reply count
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    tiamat.Text.tiny('${post.replyCount}'),
                    const SizedBox(width: 10),
                    // Timestamp
                    tiamat.Text.tiny(_relativeTime(post.timestamp),
                        color: scheme.onSurfaceVariant),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Only wrap in a gesture detector when the context menu is available.
    if (onEditTags == null) return card;

    return GestureDetector(
      // Desktop right-click — exact cursor position.
      onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
      // Mobile / desktop long-press — position where the press started.
      onLongPressStart: (d) => _showContextMenu(context, d.globalPosition),
      child: card,
    );
  }

  Widget _buildMobile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(24);

    final card = MobileGlassEdgeHighlight(
      borderRadius: radius,
      style: MobileGlassHighlightStyle.composer,
      intensity: 0.18,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surfaceContainerLow.withValues(alpha: 0.66),
                scheme.surface.withValues(alpha: 0.5),
              ],
            ),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.045),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: tiamat.Text.labelEmphasised(
                            post.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onEditTags != null)
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                color: scheme.onSurfaceVariant,
                              ),
                              onPressed: onEditTags,
                            ),
                          ),
                      ],
                    ),
                    if (post.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: post.tags
                            .map(
                              (tag) => _MobilePostTagChip(tag),
                            )
                            .toList(),
                      ),
                    ],
                    if (post.previewImage != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          height: 158,
                          width: double.infinity,
                          child: ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Image(
                              image: post.previewImage!,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (post.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      tiamat.Text.labelLow(
                        post.excerpt,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        tiamat.Avatar(
                          radius: 11,
                          image: post.senderAvatar,
                          placeholderText:
                              post.senderDisplayName ?? post.senderId,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: tiamat.Text.tiny(
                            post.senderDisplayName ?? post.senderId,
                            overflow: TextOverflow.ellipsis,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Icon(
                          Icons.mode_comment_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        tiamat.Text.tiny(
                          '${post.replyCount}',
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        tiamat.Text.tiny(
                          _relativeTime(post.timestamp),
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return card;
  }
}

class _MobilePostTagChip extends StatelessWidget {
  const _MobilePostTagChip(this.tag);

  final String tag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: MobileVisuals.pillBorderRadius,
        color: scheme.secondaryContainer.withValues(alpha: 0.42),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: scheme.onSecondaryContainer,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          child: ForumTagLabel(tag),
        ),
      ),
    );
  }
}
