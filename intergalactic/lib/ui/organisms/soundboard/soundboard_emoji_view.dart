import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';

class SoundboardEmojiView extends StatelessWidget {
  const SoundboardEmojiView({
    required this.value,
    required this.packs,
    required this.size,
    this.textStyle,
    super.key,
  });

  final String value;
  final List<EmoticonPack> packs;
  final double size;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final emoticon = resolveSoundboardEmoji(value, packs);
    if (emoticon != null) {
      return EmojiWidget(emoticon, height: size);
    }

    return Text(
      value,
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

List<EmoticonPack> soundboardEmojiPacksForSpace(Space space) {
  final packs = <String, EmoticonPack>{};

  void addPacks(Iterable<EmoticonPack>? candidates) {
    if (candidates == null) {
      return;
    }
    for (final candidate in candidates) {
      packs.putIfAbsent(candidate.identifier, () => candidate);
    }
  }

  addPacks(space.getComponent<SpaceEmoticonComponent>()?.availablePacks);
  addPacks(space.client.getComponent<EmoticonComponent>()?.availablePacks);
  return packs.values.toList();
}

Emoticon? resolveSoundboardEmoji(
  String value,
  List<EmoticonPack> packs,
) {
  final marker = value.trim();
  if (marker.isEmpty) {
    return null;
  }

  for (final pack in packs) {
    for (final emoji in pack.emoji) {
      final shortcode = emoji.shortcode;
      final slug = shortcode == null ? null : emoji.slug;
      if (slug == marker ||
          shortcode == marker ||
          (shortcode != null && ':$shortcode:' == marker)) {
        return emoji;
      }
    }
  }

  return null;
}
