import 'dart:async';

import 'package:intergalactic/client/components/forum_room/forum_room_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:intergalactic/ui/organisms/forum/forum_compose_dialog.dart';
import 'package:intergalactic/ui/organisms/forum/forum_edit_tags_dialog.dart';
import 'package:intergalactic/ui/organisms/forum/forum_post_card.dart';
import 'package:intergalactic/ui/organisms/forum/forum_tag_label.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ForumRoomView extends StatefulWidget {
  const ForumRoomView(this.forum, {super.key});

  final ForumRoomComponent forum;

  @override
  State<ForumRoomView> createState() => _ForumRoomViewState();
}

class _ForumRoomViewState extends State<ForumRoomView> {
  bool _loading = true;
  String _searchQuery = '';
  final Set<String> _activeTagFilters = {};
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<void>? _postsSub;

  @override
  void initState() {
    super.initState();
    _postsSub = widget.forum.onPostsChanged.listen((_) {
      if (mounted) setState(() {});
    });
    widget.forum.loadPosts().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _postsSub?.cancel();
    super.dispose();
  }

  List<ForumPost> get _filteredPosts {
    var posts = widget.forum.posts;

    if (_activeTagFilters.isNotEmpty) {
      posts =
          posts.where((p) => p.tags.any(_activeTagFilters.contains)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      posts = posts
          .where((p) =>
              p.title.toLowerCase().contains(q) ||
              p.excerpt.toLowerCase().contains(q))
          .toList();
    }

    return posts;
  }

  void _openThread(BuildContext context, ForumPost post) {
    // Use the EventBus openThread stream which the main Chat view listens to.
    // (clientId, roomId, threadRootEventId)
    FocusManager.instance.primaryFocus?.unfocus();
    EventBus.openThread.add((
      widget.forum.client.identifier,
      widget.forum.room.identifier,
      post.eventId,
    ));
    OverlappingPanels.of(context)?.reveal(RevealSide.right);
  }

  /// All unique tags: room-defined presets merged with tags used in posts.
  List<String> get _allAvailableTags {
    final tags = <String>{};
    tags.addAll(widget.forum.availableTags);
    for (final post in widget.forum.posts) {
      tags.addAll(post.tags);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final availableTags = _allAvailableTags;
    final posts = _filteredPosts;

    if (Layout.mobile) {
      return _buildMobile(context, availableTags, posts);
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Search bar ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search posts...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),

              // ── Tag filter chips ──────────────────────────────────────────
              if (availableTags.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: availableTags.map((tag) {
                      final active = _activeTagFilters.contains(tag);
                      return FilterChip(
                        label: ForumTagLabel(tag),
                        selected: active,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _activeTagFilters.add(tag);
                          } else {
                            _activeTagFilters.remove(tag);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),

              if (availableTags.isNotEmpty) const SizedBox(height: 8),

              // ── Post list ─────────────────────────────────────────────────
              Expanded(
                child: posts.isEmpty
                    ? Center(
                        child: tiamat.Text.labelLow(
                          _searchQuery.isNotEmpty ||
                                  _activeTagFilters.isNotEmpty
                              ? 'No posts match your filters.'
                              : 'No posts yet. Be the first to post!',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: posts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => ForumPostCard(
                          post: posts[i],
                          onTap: () => _openThread(context, posts[i]),
                          onEditTags: widget.forum.canEditTags(posts[i])
                              ? () => ForumEditTagsDialog.show(
                                    context,
                                    widget.forum,
                                    posts[i],
                                  )
                              : null,
                        ),
                      ),
              ),
            ],
          ),

          // ── New Post FAB ──────────────────────────────────────────────────
          if (widget.forum.canPost)
            ScaledSafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: FloatingActionButton.extended(
                  onPressed: () =>
                      ForumComposeDialog.show(context, widget.forum),
                  icon: const Icon(Icons.add),
                  label: const Text('New Post'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    List<String> availableTags,
    List<ForumPost> posts,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final hasFilters = _searchQuery.isNotEmpty || _activeTagFilters.isNotEmpty;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surfaceContainerLow.withValues(alpha: 0.52),
                  scheme.surface.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MobileVisuals.screenPadding,
            10,
            MobileVisuals.screenPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMobileHeader(context, posts.length),
              const SizedBox(height: 12),
              _buildMobileSearchField(context),
              if (availableTags.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildMobileTagRail(context, availableTags),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: posts.isEmpty
                    ? _buildMobileEmptyState(context, hasFilters)
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.only(
                          bottom: widget.forum.canPost ? 96 : 20,
                        ),
                        itemCount: posts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => ForumPostCard(
                          post: posts[i],
                          mobileStyle: true,
                          onTap: () => _openThread(context, posts[i]),
                          onEditTags: widget.forum.canEditTags(posts[i])
                              ? () => ForumEditTagsDialog.show(
                                    context,
                                    widget.forum,
                                    posts[i],
                                  )
                              : null,
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (widget.forum.canPost)
          Positioned(
            right: MobileVisuals.screenPadding,
            bottom: MediaQuery.of(context).padding.bottom + 14,
            child: _buildMobileNewPostButton(context),
          ),
      ],
    );
  }

  Widget _buildMobileHeader(BuildContext context, int visiblePostCount) {
    final scheme = Theme.of(context).colorScheme;
    final roomName = widget.forum.room.displayName;
    final allPostCount = widget.forum.posts.length;
    final countLabel = allPostCount == visiblePostCount
        ? '$allPostCount posts'
        : '$visiblePostCount of $allPostCount posts';

    return MobileSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      highlightStyle: MobileGlassHighlightStyle.composer,
      highlightIntensity: 0.22,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.22),
                  scheme.primaryContainer.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.forum_rounded,
                color: scheme.primary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(
                  roomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                tiamat.Text.labelLow(
                  countLabel,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSearchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(24);

    return MobileGlassEdgeHighlight(
      borderRadius: radius,
      style: MobileGlassHighlightStyle.composer,
      intensity: 0.18,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            borderRadius: radius,
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.045),
            ),
          ),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search posts',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: scheme.onSurfaceVariant,
              ),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileTagRail(BuildContext context, List<String> availableTags) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: availableTags.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = availableTags[index];
          final active = _activeTagFilters.contains(tag);
          return _MobileForumTagChip(
            tag: tag,
            active: active,
            onTap: () => setState(() {
              if (active) {
                _activeTagFilters.remove(tag);
              } else {
                _activeTagFilters.add(tag);
              }
            }),
          );
        },
      ),
    );
  }

  Widget _buildMobileEmptyState(BuildContext context, bool hasFilters) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: MobileSectionCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters ? Icons.filter_alt_off_rounded : Icons.forum_outlined,
              color: scheme.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(height: 10),
            Center(
              child: tiamat.Text.labelLow(
                hasFilters
                    ? 'No posts match your filters.'
                    : 'No posts yet. Be the first to post!',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileNewPostButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = MobileVisuals.pillBorderRadius;

    return MobileGlassEdgeHighlight(
      borderRadius: radius,
      highlighted: true,
      style: MobileGlassHighlightStyle.composer,
      intensity: 0.28,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withValues(alpha: 0.96),
                scheme.primary.withValues(alpha: 0.82),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => ForumComposeDialog.show(context, widget.forum),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 13, 20, 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      color: scheme.onPrimary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    tiamat.Text.labelEmphasised(
                      'New Post',
                      color: scheme.onPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileForumTagChip extends StatelessWidget {
  const _MobileForumTagChip({
    required this.tag,
    required this.active,
    required this.onTap,
  });

  final String tag;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = MobileVisuals.pillBorderRadius;
    final accent = active ? scheme.primary : scheme.onSurfaceVariant;

    return MobileGlassEdgeHighlight(
      borderRadius: radius,
      highlighted: active,
      style: MobileGlassHighlightStyle.composer,
      intensity: active ? 0.24 : 0.14,
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: active
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerLow.withValues(alpha: 0.74),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: accent,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
                child: ForumTagLabel(tag),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
