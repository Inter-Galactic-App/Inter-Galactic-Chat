import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter/material.dart';

class ForumTagLabel extends StatelessWidget {
  const ForumTagLabel(
    this.tag, {
    this.maxLines = 1,
    this.textAlign,
    super.key,
  });

  final String tag;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final style = TextUtils.withNativeEmojiFallback(
      DefaultTextStyle.of(context).style,
    );

    return Text.rich(
      TextSpan(
        children: TextUtils.nativeEmojiTextSpans(tag, style: style),
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}
