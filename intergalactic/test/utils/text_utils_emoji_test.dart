import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/text_utils.dart';

void main() {
  test('recognizes newer emoji graphemes in mixed Android text', () {
    const newerEmoji = '\u{1FAE9}';
    const dice = '\u{1F3B2}';

    expect(TextUtils.isEmoji(newerEmoji), isTrue);
    expect(
      TextUtils.containsEmoji('Android sent $newerEmoji and $dice'),
      isTrue,
    );
    expect(TextUtils.isEmojiOnly('$newerEmoji $dice'), isTrue);
  });

  test('native emoji spans isolate newer emoji onto emoji font fallback', () {
    const newerEmoji = '\u{1FAE9}';

    final spans = TextUtils.nativeEmojiTextSpans('before $newerEmoji after');

    expect(spans, hasLength(3));
    final emojiSpan = spans[1] as TextSpan;
    expect(emojiSpan.text, newerEmoji);
    expect(
      emojiSpan.style?.fontFamilyFallback,
      containsAll(TextUtils.nativeEmojiFontFallback),
    );
  });

  test('plain digits stay text but keycap graphemes are emoji', () {
    expect(TextUtils.isEmoji('1'), isFalse);
    expect(TextUtils.isEmoji('1\uFE0F\u20E3'), isTrue);
  });
}
