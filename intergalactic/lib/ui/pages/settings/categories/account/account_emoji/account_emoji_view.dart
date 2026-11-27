import 'dart:async';

import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AccountEmojiView extends StatefulWidget {
  const AccountEmojiView(this.component, {super.key});
  final EmoticonComponent component;
  @override
  State<AccountEmojiView> createState() => _AccountEmojiViewState();
}

class _AccountEmojiViewState extends State<AccountEmojiView> {
  late List<EmoticonPack> globalPacks;
  StreamSubscription? sub;

  @override
  void initState() {
    sub = widget.component.onStateChanged.listen((_) => updateState());
    updateState();
    super.initState();
  }

  void updateState() {
    setState(() {
      globalPacks = widget.component.globalPacks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: "Favorite Packs",
      children: [
        SettingsControlRow(
          title: 'Pinned emoji and sticker packs',
          description:
              'Favorite packs are available from the emoji and sticker pickers across the app.',
          child: Column(
            children: [
              for (final pack in globalPacks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: packSummary(pack),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget packSummary(EmoticonPack pack) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.72),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _PackImage(pack: pack),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _ownerLabel(pack),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              tiamat.Tooltip(
                text: 'Remove from favorites',
                child: tiamat.CircleButton(
                  icon: Icons.heart_broken,
                  onPressed: () => pack.markAsGlobal(false),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _ownerLabel(EmoticonPack pack) {
    final ownerName = pack.ownerDisplayName.trim();
    if (ownerName.isNotEmpty) {
      return ownerName;
    }

    return pack.ownerId;
  }
}

class _PackImage extends StatelessWidget {
  const _PackImage({required this.pack});

  final EmoticonPack pack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: pack.image == null
          ? Icon(
              pack.icon ?? Icons.emoji_emotions_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : Image(
              image: pack.image!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}
