import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// ignore: must_be_immutable
class EmojiWidget extends StatelessWidget {
  final Emoticon emoji;
  double height;
  EdgeInsetsGeometry padding;

  EmojiWidget(this.emoji,
      {super.key,
      this.height = 24,
      this.padding = const EdgeInsetsGeometry.all(0)});

  @override
  Widget build(BuildContext context) {
    final unicodeEmojiStyle = BuildConfig.IOS
        ? TextUtils.withNativeEmojiFallback(const TextStyle())
        : const TextStyle(
            fontFamilyFallback: [
              'Apple Color Emoji',
              'Segoe UI Emoji',
              'Noto Color Emoji',
              'EmojiFont',
            ],
          );

    return Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
        child: emoji.image != null
            ? SizedBox(
                width: height,
                height: height,
                child: FadeInImage(
                  placeholder: tiamat.transparentImage.image,
                  fadeInDuration: Durations.medium1,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.contain,
                  width: height,
                  height: height,
                  image: emoji.image!,
                ),
              )
            : SizedBox(
                height: height,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: Padding(
                    padding: padding,
                    child: Text(
                      emoji.slug,
                      style: unicodeEmojiStyle,
                    ),
                  ),
                ),
              ));
  }
}
