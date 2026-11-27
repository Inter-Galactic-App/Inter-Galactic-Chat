import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/forum_room/forum_room_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/forum/forum_tag_label.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ForumComposeDialog extends StatefulWidget {
  const ForumComposeDialog({
    required this.forum,
    this.mobileSheet = false,
    super.key,
  });

  final ForumRoomComponent forum;
  final bool mobileSheet;

  /// Show the compose dialog and, if confirmed, create the post.
  static Future<void> show(BuildContext context, ForumRoomComponent forum) {
    if (Layout.mobile) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final media = MediaQuery.of(sheetContext);
          final availableHeight =
              media.size.height - media.viewInsets.bottom - media.padding.top;
          final sheetHeight = availableHeight
              .clamp(
                0.0,
                media.size.height * 0.92,
              )
              .toDouble();

          return AnimatedPadding(
            duration: Durations.short2,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: SizedBox(
              height: sheetHeight,
              child: ForumComposeDialog(
                forum: forum,
                mobileSheet: true,
              ),
            ),
          );
        },
      );
    }

    return AdaptiveDialog.show(
      context,
      title: 'New Post',
      scrollable: true,
      builder: (ctx) => ForumComposeDialog(forum: forum),
    );
  }

  @override
  State<ForumComposeDialog> createState() => _ForumComposeDialogState();
}

class _ForumComposeDialogState extends State<ForumComposeDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _tagInputController = TextEditingController();
  final Set<String> _selectedTags = {};
  bool _submitting = false;

  bool get _isValid =>
      _titleController.text.trim().isNotEmpty &&
      _bodyController.text.trim().isNotEmpty;

  /// Union of room-defined preset tags and tags used in existing posts.
  List<String> get _allKnownTags {
    final tags = <String>{};
    tags.addAll(widget.forum.availableTags);
    for (final post in widget.forum.posts) {
      tags.addAll(post.tags);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addCustomTag() {
    final tag = _tagInputController.text.trim();
    if (tag.isEmpty) return;
    setState(() {
      _selectedTags.add(tag);
      _tagInputController.clear();
    });
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;

    setState(() => _submitting = true);
    var shouldClose = false;
    try {
      await widget.forum.createPost(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        tags: _selectedTags.toList(),
      );
      shouldClose = true;
    } catch (error, trace) {
      Log.onError(error, trace, content: 'Failed to create forum post');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
              content: Text('Could not create post. Please try again.')),
        );
      }
      // Keep the dialog open so the user can retry without losing draft text.
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }

    if (shouldClose && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobileSheet) {
      return _buildMobileSheet(context);
    }

    return SizedBox(
      width: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ..._buildFields(context),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildMobileSheet(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.vertical(
      top: Radius.circular(MobileVisuals.panelRadius),
    );

    return ClipRRect(
      borderRadius: radius,
      child: MobileGlassEdgeHighlight(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surfaceContainerLow.withValues(alpha: 0.94),
                scheme.surface.withValues(alpha: 0.9),
              ],
            ),
          ),
          child: PopScope(
            canPop: !_submitting,
            child: ScaledSafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const SizedBox(width: 40, height: 4),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: tiamat.Text(
                            'New Post',
                            type: tiamat.TextType.largeTitle,
                            color: scheme.onSurface,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.48),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: _buildFields(context),
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.48),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: tiamat.Button.secondary(
                            text: 'Cancel',
                            onTap: _submitting
                                ? null
                                : () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _buildSubmitButton()),
                      ],
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

  List<Widget> _buildFields(BuildContext context) {
    final knownTags = _allKnownTags;
    final customSelectedTags =
        _selectedTags.where((t) => !knownTags.contains(t)).toList()..sort();

    return [
      TextField(
        controller: _titleController,
        decoration: _fieldDecoration('Post title'),
        onChanged: (_) => setState(() {}),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.Text.label('Tags'),
          const SizedBox(height: 6),
          if (knownTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: knownTags.map((tag) {
                  final selected = _selectedTags.contains(tag);
                  return FilterChip(
                    label: ForumTagLabel(tag),
                    selected: selected,
                    visualDensity: widget.mobileSheet
                        ? VisualDensity.compact
                        : VisualDensity.standard,
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
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagInputController,
                  decoration: _fieldDecoration(
                    knownTags.isEmpty ? 'Add a tag...' : 'Add a custom tag...',
                    dense: true,
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
          if (customSelectedTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
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
            ),
        ],
      ),
      TextField(
        controller: _bodyController,
        maxLines: widget.mobileSheet ? 5 : 6,
        decoration: _fieldDecoration('Write your post...'),
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  InputDecoration _fieldDecoration(String hintText, {bool dense = false}) {
    if (!widget.mobileSheet) {
      return InputDecoration(
        hintText: hintText,
        alignLabelWithHint: true,
        isDense: dense,
      );
    }

    return InputDecoration(
      hintText: hintText,
      alignLabelWithHint: true,
      isDense: dense,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.66),
      contentPadding: EdgeInsets.symmetric(
        vertical: dense ? 10 : 13,
        horizontal: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(dense ? 16 : 20),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(dense ? 16 : 20),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(dense ? 16 : 20),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.34),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return IgnorePointer(
      ignoring: !_isValid || _submitting,
      child: Opacity(
        opacity: _isValid && !_submitting ? 1.0 : 0.4,
        child: tiamat.Button(
          text: _submitting ? 'Posting...' : 'Post',
          isLoading: _submitting,
          onTap: _submit,
        ),
      ),
    );
  }
}
