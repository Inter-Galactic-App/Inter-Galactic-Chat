import 'package:intergalactic/client/components/forum_room/forum_room_component.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/forum/forum_tag_label.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ForumEditTagsDialog extends StatefulWidget {
  const ForumEditTagsDialog({
    required this.forum,
    required this.post,
    super.key,
  });

  final ForumRoomComponent forum;
  final ForumPost post;

  /// Show the tag-edit dialog; if confirmed, updates the post's tags.
  static Future<void> show(
    BuildContext context,
    ForumRoomComponent forum,
    ForumPost post,
  ) {
    return AdaptiveDialog.show(
      context,
      title: 'Edit Tags',
      scrollable: true,
      builder: (ctx) => ForumEditTagsDialog(forum: forum, post: post),
    );
  }

  @override
  State<ForumEditTagsDialog> createState() => _ForumEditTagsDialogState();
}

class _ForumEditTagsDialogState extends State<ForumEditTagsDialog> {
  final _tagInputController = TextEditingController();
  late final Set<String> _selectedTags;
  List<String> _cachedAllKnownTags = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the post's current tags.
    _selectedTags = {...widget.post.tags};
    _rebuildKnownTagsCache();
  }

  @override
  void didUpdateWidget(covariant ForumEditTagsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forum != widget.forum || oldWidget.post != widget.post) {
      _rebuildKnownTagsCache();
      _selectedTags
        ..clear()
        ..addAll(widget.post.tags);
      _tagInputController.clear();
    }
  }

  @override
  void dispose() {
    _tagInputController.dispose();
    super.dispose();
  }

  void _rebuildKnownTagsCache() {
    final tags = <String>{};
    tags.addAll(widget.forum.availableTags);
    for (final post in widget.forum.posts) {
      tags.addAll(post.tags);
    }
    _cachedAllKnownTags = tags.toList()..sort();
  }

  void _addCustomTag() {
    final tag = _tagInputController.text.trim();
    if (tag.isEmpty) return;
    setState(() {
      _selectedTags.add(tag);
      _tagInputController.clear();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.forum.editPostTags(widget.post, _selectedTags.toList());
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Could not save tags for "${widget.post.title}": $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final knownTags = _cachedAllKnownTags;
    // Custom tags: user-added free-form tags not in the known/preset list.
    final customSelectedTags =
        _selectedTags.where((t) => !knownTags.contains(t)).toList()..sort();

    return SizedBox(
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          // Post context label.
          tiamat.Text.labelLow(
            'Post: ${widget.post.title}',
            overflow: TextOverflow.ellipsis,
          ),

          // Preset / known tags as toggle chips.
          if (knownTags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: knownTags.map((tag) {
                final selected = _selectedTags.contains(tag);
                return FilterChip(
                  label: ForumTagLabel(tag),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selectedTags.add(tag);
                    } else {
                      _selectedTags.remove(tag);
                    }
                  }),
                );
              }).toList(),
            ),

          // Free-form custom tag input row.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagInputController,
                  decoration: InputDecoration(
                    hintText: 'Add a custom tag...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) => _addCustomTag(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addCustomTag,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add tag',
              ),
            ],
          ),

          // Dismissible chips for free-form tags the user has typed.
          if (customSelectedTags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: customSelectedTags
                  .map(
                    (tag) => Chip(
                      label: ForumTagLabel(tag),
                      onDeleted: () =>
                          setState(() => _selectedTags.remove(tag)),
                    ),
                  )
                  .toList(),
            ),

          // Save button.
          IgnorePointer(
            ignoring: _saving,
            child: Opacity(
              opacity: _saving ? 0.4 : 1.0,
              child: tiamat.Button(
                text: _saving ? 'Saving...' : 'Save Tags',
                isLoading: _saving,
                onTap: _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
