import 'dart:math';

import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';
import 'package:intergalactic/ui/atoms/message_attachment.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reactions.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu_dialog.dart';
import 'package:intergalactic/utils/mobile_share_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventViewAttachments extends StatelessWidget {
  const TimelineEventViewAttachments({
    required this.attachments,
    this.previewMedia = false,
    this.alignRight = false,
    this.bubbleColor,
    this.timeline,
    this.event,
    this.isThreadTimeline = false,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.onOpenThread,
    super.key,
  });

  final List<Attachment> attachments;
  final bool previewMedia;
  final bool alignRight;
  final Color? bubbleColor;
  final Timeline? timeline;
  final TimelineEvent? event;
  final bool isThreadTimeline;
  final Function(TimelineEvent event)? setEditingEvent;
  final Function(TimelineEvent event)? setReplyingEvent;
  final VoidCallback? onOpenThread;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: attachments
          .map(
            (e) => Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
              child: RepaintBoundary(
                child: MessageAttachment(
                  e,
                  previewMedia: previewMedia,
                  alignRight: alignRight,
                  bubbleColor: bubbleColor,
                  lightboxActionsBuilder: _hasTimelineMenu
                      ? (context) =>
                            TimelineEventLightboxActions(menu: _buildMenu(e))
                      : null,
                  mobileLightboxActionsBuilder:
                      _hasTimelineMenu && e is FileAttachment
                      ? (context, dismiss) => MobileFocusedMediaActions(
                          menu: _buildMenu(e, onActionFinished: dismiss),
                          attachment: e,
                          onClose: dismiss,
                          onOpenThread: onOpenThread,
                        )
                      : null,
                  onFullscreenLongPress: _hasTimelineMenu && BuildConfig.MOBILE
                      ? (context) => _showMobileMenu(context, e)
                      : null,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  bool get _hasTimelineMenu => timeline != null && event != null;

  TimelineEventMenu _buildMenu(
    Attachment attachment, {
    VoidCallback? onActionFinished,
  }) {
    return TimelineEventMenu(
      timeline: timeline!,
      event: event!,
      isThreadTimeline: isThreadTimeline,
      setEditingEvent: setEditingEvent,
      setReplyingEvent: setReplyingEvent,
      onActionFinished: onActionFinished,
      attachmentForDownload: attachment,
    );
  }

  Future<void> _showMobileMenu(
    BuildContext context,
    Attachment attachment,
  ) async {
    if (!_hasTimelineMenu) {
      return;
    }

    await showModalBottomSheet(
      isScrollControlled: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      context: context,
      builder: (sheetContext) {
        return TimelineEventMenuDialog(
          event: event!,
          timeline: timeline!,
          menu: _buildMenu(
            attachment,
            onActionFinished: () => Navigator.of(sheetContext).pop(),
          ),
        );
      },
    );
  }
}

class PhotoStackAttachmentItem {
  const PhotoStackAttachmentItem({
    required this.event,
    required this.index,
    required this.attachment,
  });

  final TimelineEventMessage event;
  final int index;
  final ImageAttachment attachment;
}

class PhotoStackAttachmentView extends StatelessWidget {
  const PhotoStackAttachmentView({
    required this.items,
    required this.timeline,
    this.previewMedia = true,
    this.isThreadTimeline = false,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.onOpenThread,
    super.key,
  });

  final List<PhotoStackAttachmentItem> items;
  final Timeline timeline;
  final bool previewMedia;
  final bool isThreadTimeline;
  final Function(TimelineEvent event)? setEditingEvent;
  final Function(TimelineEvent event)? setReplyingEvent;
  final VoidCallback? onOpenThread;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final attachments = items.map((item) => item.attachment).toList();
    final count = attachments.length;
    if (count == 1) {
      final item = items.single;
      return MessageAttachment(
        item.attachment,
        previewMedia: previewMedia,
        lightboxActionsBuilder: (context) =>
            TimelineEventLightboxActions(menu: _buildMenu(item)),
        mobileLightboxActionsBuilder: (context, dismiss) =>
            MobileFocusedMediaActions(
              menu: _buildMenu(item, onActionFinished: dismiss),
              attachment: item.attachment,
              onClose: dismiss,
              onOpenThread: onOpenThread,
            ),
        onFullscreenLongPress: BuildConfig.MOBILE
            ? (context) => _showMobileMenu(context, item)
            : null,
      );
    }

    final primary = attachments.first;
    final secondary = attachments.length > 1 ? attachments[1] : primary;
    final tertiary = attachments.length > 2 ? attachments[2] : secondary;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final constrainedWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth - 8
            : 278.0;
        final availableWidth = min(278.0, max(180.0, constrainedWidth));
        final scale = availableWidth / 278.0;

        return SelectionContainer.disabled(
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 8, 18 * scale, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: availableWidth,
                  height: 214 * scale,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 26 * scale,
                        top: 16 * scale,
                        child: _PhotoStackLayer(
                          attachment: tertiary,
                          previewMedia: previewMedia,
                          width: 240 * scale,
                          height: 178 * scale,
                          opacity: 0.42,
                        ),
                      ),
                      Positioned(
                        left: 14 * scale,
                        top: 8 * scale,
                        child: _PhotoStackLayer(
                          attachment: secondary,
                          previewMedia: previewMedia,
                          width: 248 * scale,
                          height: 186 * scale,
                          opacity: 0.66,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        child: _PhotoStackLayer(
                          attachment: primary,
                          previewMedia: previewMedia,
                          width: 254 * scale,
                          height: 194 * scale,
                          onTap: () => PhotoStackLightbox.show(
                            context,
                            items: items,
                            timeline: timeline,
                            isThreadTimeline: isThreadTimeline,
                            setEditingEvent: setEditingEvent,
                            setReplyingEvent: setReplyingEvent,
                            onOpenThread: onOpenThread,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 6 * scale,
                        bottom: 8 * scale,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.92,
                            ),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              8 * scale,
                              4 * scale,
                              8 * scale,
                              4 * scale,
                            ),
                            child: Text(
                              _photoStackCountLabel(count),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _PhotoStackReactionIndicators(items: items, timeline: timeline),
              ],
            ),
          ),
        );
      },
    );
  }

  TimelineEventMenu _buildMenu(
    PhotoStackAttachmentItem item, {
    VoidCallback? onActionFinished,
  }) {
    return TimelineEventMenu(
      timeline: timeline,
      event: item.event,
      isThreadTimeline: isThreadTimeline,
      setEditingEvent: setEditingEvent,
      setReplyingEvent: setReplyingEvent,
      onActionFinished: onActionFinished,
      attachmentForDownload: item.attachment,
    );
  }

  Future<void> _showMobileMenu(
    BuildContext context,
    PhotoStackAttachmentItem item,
  ) async {
    await showModalBottomSheet(
      isScrollControlled: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      context: context,
      builder: (sheetContext) {
        return TimelineEventMenuDialog(
          event: item.event,
          timeline: timeline,
          menu: _buildMenu(
            item,
            onActionFinished: () => Navigator.of(sheetContext).pop(),
          ),
        );
      },
    );
  }
}

class _PhotoStackLayer extends StatelessWidget {
  const _PhotoStackLayer({
    required this.attachment,
    required this.previewMedia,
    required this.width,
    required this.height,
    this.opacity = 1,
    this.onTap,
  });

  final ImageAttachment attachment;
  final bool previewMedia;
  final double width;
  final double height;
  final double opacity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: scheme.onSurfaceVariant,
        size: min(42.0, height * 0.28),
      ),
    );
    final child = previewMedia
        ? Stack(
            fit: StackFit.expand,
            children: [
              PausedAnimatedImage(
                image: attachment.image,
                width: width,
                height: height,
                fit: BoxFit.cover,
              ),
              if (onTap != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onTap),
                ),
            ],
          )
        : (onTap == null
              ? placeholder
              : InkWell(onTap: onTap, child: placeholder));
    return SizedBox(
      width: width,
      height: height,
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Material(color: scheme.surfaceContainerLow, child: child),
          ),
        ),
      ),
    );
  }
}

class _PhotoStackReactionIndicators extends StatelessWidget {
  const _PhotoStackReactionIndicators({
    required this.items,
    required this.timeline,
  });

  final List<PhotoStackAttachmentItem> items;
  final Timeline timeline;

  @override
  Widget build(BuildContext context) {
    final reactedItems = items
        .where((item) => _hasReactions(item.event, timeline))
        .toList(growable: false);
    if (reactedItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final item in reactedItems)
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${items.indexOf(item) + 1}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    TimelineEventViewReactions(
                      key: ValueKey(
                        'photo-stack-reactions-${item.event.eventId}-${item.index}',
                      ),
                      initialIndex: item.index,
                      timeline: timeline,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasReactions(TimelineEvent event, Timeline timeline) {
    return switch (event) {
      TimelineEventFeatureReactions reactionEvent => reactionEvent.hasReactions(
        timeline,
      ),
      _ => false,
    };
  }
}

String _photoStackCountLabel(int count) {
  return Intl.plural(
    count,
    one: '1 photo',
    other: '$count photos',
    name: 'photoStackCountLabel',
    args: [count],
  );
}

class PhotoStackLightbox extends StatefulWidget {
  const PhotoStackLightbox({
    required this.items,
    required this.timeline,
    this.initialIndex = 0,
    this.isThreadTimeline = false,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.onOpenThread,
    super.key,
  });

  final List<PhotoStackAttachmentItem> items;
  final Timeline timeline;
  final int initialIndex;
  final bool isThreadTimeline;
  final Function(TimelineEvent event)? setEditingEvent;
  final Function(TimelineEvent event)? setReplyingEvent;
  final VoidCallback? onOpenThread;

  static Future<void> show(
    BuildContext context, {
    required List<PhotoStackAttachmentItem> items,
    required Timeline timeline,
    int initialIndex = 0,
    bool isThreadTimeline = false,
    Function(TimelineEvent event)? setEditingEvent,
    Function(TimelineEvent event)? setReplyingEvent,
    VoidCallback? onOpenThread,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PHOTO_STACK',
      barrierColor: Colors.black.withValues(alpha: 0.88),
      pageBuilder: (context, _, __) {
        return PhotoStackLightbox(
          items: items,
          timeline: timeline,
          initialIndex: initialIndex,
          isThreadTimeline: isThreadTimeline,
          setEditingEvent: setEditingEvent,
          setReplyingEvent: setReplyingEvent,
          onOpenThread: onOpenThread,
          key: ValueKey('photo-stack-lightbox-$initialIndex'),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        );
      },
    );
  }

  @override
  State<PhotoStackLightbox> createState() => _PhotoStackLightboxState();
}

class _PhotoStackLightboxState extends State<PhotoStackLightbox> {
  late PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final lastIndex = widget.items.isEmpty ? 0 : widget.items.length - 1;
    _index = widget.initialIndex.clamp(0, lastIndex).toInt();
    _pageController = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(covariant PhotoStackLightbox oldWidget) {
    super.didUpdateWidget(oldWidget);

    final lastIndex = widget.items.isEmpty ? 0 : widget.items.length - 1;
    final nextIndex = oldWidget.initialIndex != widget.initialIndex
        ? widget.initialIndex.clamp(0, lastIndex).toInt()
        : _index.clamp(0, lastIndex).toInt();
    final shouldAdjustController =
        oldWidget.items.length != widget.items.length || nextIndex != _index;

    if (!shouldAdjustController) {
      return;
    }

    _index = nextIndex;
    if (_pageController.hasClients) {
      // Reuse the existing _pageController when jumpToPage can handle the
      // update; only the replacement branch below owns an oldController to
      // dispose.
      _pageController.jumpToPage(_index);
      return;
    }

    final oldController = _pageController;
    _pageController = PageController(initialPage: _index);
    oldController.dispose();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: count,
              onPageChanged: (index) {
                setState(() {
                  _index = index;
                });
              },
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return Padding(
                  padding: EdgeInsets.all(BuildConfig.MOBILE ? 14 : 64),
                  child: GestureDetector(
                    onLongPress: BuildConfig.MOBILE
                        ? () => _showMobileMenu(context, item)
                        : null,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: PausedAnimatedImage(
                          image: item.attachment.image,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 14,
              right: 14,
              child: _FocusedMediaCloseButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (count > 0 && !BuildConfig.MOBILE)
              Positioned(
                top: 14,
                right: 62,
                child: TimelineEventLightboxActions(
                  menu: _buildMenu(widget.items[_index]),
                ),
              ),
            if (count > 1 && !BuildConfig.MOBILE) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: IconButton.filledTonal(
                    tooltip: 'Previous photo',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _index == 0
                        ? null
                        : () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                          ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: IconButton.filledTonal(
                    tooltip: 'Next photo',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _index >= count - 1
                        ? null
                        : () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                          ),
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.all(BuildConfig.MOBILE ? 92 : 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    child: Text(
                      count == 0 ? '0 / 0' : '${_index + 1} / $count',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (count > 0 && BuildConfig.MOBILE)
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: MobileFocusedMediaActions(
                  menu: _buildMenu(
                    widget.items[_index],
                    onActionFinished: () => Navigator.of(context).pop(),
                  ),
                  attachment: widget.items[_index].attachment,
                  onClose: () => Navigator.of(context).pop(),
                  onOpenThread: widget.onOpenThread,
                ),
              ),
          ],
        ),
      ),
    );
  }

  TimelineEventMenu _buildMenu(
    PhotoStackAttachmentItem item, {
    VoidCallback? onActionFinished,
  }) {
    return TimelineEventMenu(
      timeline: widget.timeline,
      event: item.event,
      isThreadTimeline: widget.isThreadTimeline,
      setEditingEvent: widget.setEditingEvent,
      setReplyingEvent: widget.setReplyingEvent,
      onActionFinished: onActionFinished,
      attachmentForDownload: item.attachment,
    );
  }

  Future<void> _showMobileMenu(
    BuildContext context,
    PhotoStackAttachmentItem item,
  ) async {
    await showModalBottomSheet(
      isScrollControlled: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      context: context,
      builder: (sheetContext) {
        return TimelineEventMenuDialog(
          event: item.event,
          timeline: widget.timeline,
          menu: _buildMenu(
            item,
            onActionFinished: () => Navigator.of(sheetContext).pop(),
          ),
        );
      },
    );
  }
}

class MobileFocusedMediaActions extends StatefulWidget {
  const MobileFocusedMediaActions({
    required this.menu,
    required this.attachment,
    required this.onClose,
    this.onOpenThread,
    super.key,
  });

  final TimelineEventMenu menu;
  final FileAttachment? attachment;
  final VoidCallback onClose;
  final VoidCallback? onOpenThread;

  @override
  State<MobileFocusedMediaActions> createState() =>
      _MobileFocusedMediaActionsState();
}

class _MobileFocusedMediaActionsState extends State<MobileFocusedMediaActions> {
  bool _showQuickReactions = false;
  bool _sharing = false;

  TimelineEventMenuEntry? get _replyAction {
    for (final entry in widget.menu.primaryActions) {
      if (entry.icon == Icons.reply) {
        return entry;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final replyAction = _replyAction;
    final hasQuickReactions = widget.menu.quickReactions.isNotEmpty;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: _showQuickReactions ? 124 : 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_showQuickReactions)
              Positioned(
                left: 0,
                right: 0,
                bottom: 70,
                child: _MobileFocusedQuickReactions(
                  menu: widget.menu,
                  onPicked: () {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _showQuickReactions = false;
                    });
                  },
                ),
              ),
            Align(
              alignment: Alignment.bottomLeft,
              child: _FocusedMediaActionCluster(
                children: [
                  _FocusedMediaActionButton(
                    tooltip: 'React',
                    icon: Icons.add_reaction_outlined,
                    selected: _showQuickReactions,
                    enabled: hasQuickReactions,
                    onPressed: hasQuickReactions
                        ? () => setState(() {
                            _showQuickReactions = !_showQuickReactions;
                          })
                        : null,
                  ),
                  _FocusedMediaActionButton(
                    tooltip: 'Reply',
                    icon: Icons.reply_rounded,
                    enabled: replyAction != null,
                    onPressed: replyAction == null
                        ? null
                        : () => replyAction.action?.call(context),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: _FocusedMediaActionCluster(
                children: [
                  if (widget.onOpenThread != null)
                    _FocusedMediaActionButton(
                      tooltip: 'Threads',
                      icon: Icons.forum_outlined,
                      onPressed: _openThread,
                    ),
                  _FocusedMediaActionButton(
                    tooltip: 'Share',
                    icon: _sharing
                        ? Icons.hourglass_top_rounded
                        : Icons.ios_share_rounded,
                    enabled: widget.attachment != null && !_sharing,
                    onPressed: widget.attachment == null || _sharing
                        ? null
                        : _share,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openThread() {
    final onOpenThread = widget.onOpenThread;
    if (onOpenThread == null) {
      return;
    }

    widget.onClose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onOpenThread();
    });
  }

  Future<void> _share() async {
    final attachment = widget.attachment;
    if (attachment == null) {
      return;
    }

    setState(() {
      _sharing = true;
    });

    var shared = false;
    try {
      shared = await MobileShareUtils.shareAttachment(attachment);
    } catch (_) {
      shared = false;
    } finally {
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }

    if (!mounted) {
      return;
    }

    if (!shared) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Unable to open the share sheet for this photo.'),
        ),
      );
    }
  }
}

class _MobileFocusedQuickReactions extends StatelessWidget {
  const _MobileFocusedQuickReactions({
    required this.menu,
    required this.onPicked,
  });

  final TimelineEventMenu menu;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    var reactions = menu.quickReactions;
    if (reactions.length > RecentEmoticonComponent.quickReactionCount) {
      reactions = reactions.sublist(
        0,
        RecentEmoticonComponent.quickReactionCount,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final emote in reactions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _FocusedMediaReactionButton(
                      tooltip: emote.shortcode ?? 'Reaction',
                      child: EmojiWidget(
                        emote,
                        height: 32,
                        padding: const EdgeInsets.all(2),
                      ),
                      onPressed: () {
                        menu.timeline.room.addReaction(menu.event, emote);
                        onPicked();
                      },
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

class _FocusedMediaActionCluster extends StatelessWidget {
  const _FocusedMediaActionCluster({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _FocusedMediaActionButton extends StatelessWidget {
  const _FocusedMediaActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final background = selected
        ? scheme.primaryContainer.withValues(alpha: 0.9)
        : scheme.surface.withValues(alpha: 0.34);
    final disabledColor = scheme.onSurfaceVariant.withValues(alpha: 0.45);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: enabled ? background : Colors.transparent,
            disabledForegroundColor: disabledColor,
            foregroundColor: enabled ? foreground : disabledColor,
            shape: const CircleBorder(),
          ),
          icon: Icon(icon),
          onPressed: enabled ? onPressed : null,
        ),
      ),
    );
  }
}

class _FocusedMediaReactionButton extends StatelessWidget {
  const _FocusedMediaReactionButton({
    required this.tooltip,
    required this.child,
    required this.onPressed,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: tooltip,
          style: IconButton.styleFrom(shape: const CircleBorder()),
          icon: child,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _FocusedMediaCloseButton extends StatelessWidget {
  const _FocusedMediaCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close_rounded),
        color: scheme.onSurface,
        onPressed: onPressed,
      ),
    );
  }
}

class TimelineEventLightboxActions extends StatefulWidget {
  const TimelineEventLightboxActions({required this.menu, super.key});

  final TimelineEventMenu menu;

  @override
  State<TimelineEventLightboxActions> createState() =>
      _TimelineEventLightboxActionsState();
}

class _TimelineEventLightboxActionsState
    extends State<TimelineEventLightboxActions> {
  TimelineEventMenuEntry? _selectedEntry;

  @override
  void didUpdateWidget(covariant TimelineEventLightboxActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.menu.event.eventId != widget.menu.event.eventId ||
        !identical(oldWidget.menu, widget.menu)) {
      _selectedEntry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    var reactions = widget.menu.quickReactions;
    if (reactions.length > RecentEmoticonComponent.quickReactionCount) {
      reactions = reactions.sublist(
        0,
        RecentEmoticonComponent.quickReactionCount,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_selectedEntry != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Tile.surfaceContainer(
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: _selectedEntry!.secondaryMenuBuilder?.call(
                    context,
                    () {
                      setState(() {
                        _selectedEntry = null;
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceDim,
            border: Border.all(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final emote in reactions)
                  _buildAction(
                    name: emote.shortcode,
                    child: EmojiWidget(
                      emote,
                      height: 20,
                      padding: const EdgeInsets.all(2),
                    ),
                    onTap: () {
                      widget.menu.timeline.room.addReaction(
                        widget.menu.event,
                        emote,
                      );
                    },
                  ),
                if (widget.menu.addReactionAction != null)
                  _buildAction(
                    name: widget.menu.addReactionAction!.name,
                    child: Icon(
                      widget.menu.addReactionAction!.icon,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 20,
                    ),
                    onTap: () =>
                        _togglePopupMenu(widget.menu.addReactionAction!),
                  ),
                if (widget.menu.addReactionAction != null)
                  const SizedBox(height: 24, child: VerticalDivider()),
                for (final entry in widget.menu.primaryActions)
                  _buildAction(
                    name: entry.name,
                    child: Icon(
                      entry.icon,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 20,
                    ),
                    onTap: entry.secondaryMenuBuilder != null
                        ? () => _togglePopupMenu(entry)
                        : () => entry.action?.call(context),
                  ),
                if (widget.menu.secondaryActions.isNotEmpty)
                  _buildAction(
                    name: 'Options',
                    child: const Icon(Icons.more_vert),
                    contextMenuItems: widget.menu.secondaryActions
                        .map(
                          (entry) => ContextMenuItem(
                            text: entry.name,
                            icon: entry.icon,
                            onPressed: entry.secondaryMenuBuilder != null
                                ? () => _togglePopupMenu(entry)
                                : () => entry.action?.call(context),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _togglePopupMenu(TimelineEventMenuEntry entry) {
    setState(() {
      _selectedEntry = _selectedEntry == entry ? null : entry;
    });
  }

  Widget _buildAction({
    required Widget child,
    String? name,
    VoidCallback? onTap,
    List<ContextMenuItem>? contextMenuItems,
  }) {
    const size = 30.0;
    const pad = EdgeInsets.all(2);
    Widget result = Padding(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: size,
            height: size,
            child: contextMenuItems != null
                ? ContextMenu(
                    modal: true,
                    items: contextMenuItems,
                    child: Padding(padding: pad, child: child),
                  )
                : InkWell(
                    onTap: onTap,
                    child: Padding(padding: pad, child: child),
                  ),
          ),
        ),
      ),
    );

    if (name == null) {
      return result;
    }

    result = AccessibleInteractiveRegion(
      semanticLabel: name,
      semanticHint: contextMenuItems != null ? 'Open more actions' : null,
      onActivate: contextMenuItems == null ? onTap : null,
      borderRadius: BorderRadius.circular(size / 2),
      minimumSize: 36,
      excludeChildSemantics: true,
      persistentLabel: name,
      persistentLabelMaxWidth: 84,
      child: result,
    );

    return tiamat.Tooltip(text: name, child: result);
  }
}
