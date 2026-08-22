import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ForumCreatorDescription extends StatelessWidget {
  const ForumCreatorDescription({super.key});

  String get labelForumDescription => Intl.message(
        "Create a structured discussion space with searchable posts, tags, and threaded replies — great for Q&A, announcements, or organised community topics.",
        name: "labelForumDescription",
        desc: "Description shown when creating a Forum room type",
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(labelForumDescription),
        const SizedBox(height: 16),

        // Simple mock showing what a forum looks like
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              spacing: 8,
              children: [
                _FakePostTile(
                  title: 'Welcome to the forum!',
                  tags: const ['Announcement'],
                  replies: 12,
                  color: scheme.secondaryContainer,
                ),
                _FakePostTile(
                  title: 'Bug report: login issue on iOS',
                  tags: const ['Bug'],
                  replies: 4,
                  color: scheme.errorContainer,
                ),
                _FakePostTile(
                  title: 'Feature request: dark mode',
                  tags: const ['Feature'],
                  replies: 27,
                  color: scheme.primaryContainer,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FakePostTile extends StatelessWidget {
  const _FakePostTile({
    required this.title,
    required this.tags,
    required this.replies,
    required this.color,
  });

  final String title;
  final List<String> tags;
  final int replies;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 4,
                  children: tags
                      .map((t) => Chip(
                            label: tiamat.Text.tiny(t),
                            backgroundColor: color,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            side: BorderSide.none,
                          ))
                      .toList(),
                ),
                tiamat.Text.label(title),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chat_bubble_outline,
              size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          tiamat.Text.tiny('$replies'),
        ],
      ),
    );
  }
}

class ForumCreatorForm extends StatefulWidget {
  const ForumCreatorForm({super.key});

  @override
  State<ForumCreatorForm> createState() => _ForumCreatorFormState();
}

class _ForumCreatorFormState extends State<ForumCreatorForm> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
