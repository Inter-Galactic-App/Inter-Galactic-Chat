import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/ui/molecules/composer_bracket_formatter.dart';
import 'package:intergalactic/ui/molecules/message_input.dart';

void main() {
  test(
    'inserting an app emoji without selection appends without leading space',
    () {
      final value = insertEmoticonIntoComposerValue(
        TextEditingValue.empty,
        const _TestEmoticon(':party:'),
      );

      expect(value.text, ':party:');
      expect(value.selection.baseOffset, value.text.length);
    },
  );

  test('inserting an app emoji into existing text adds safe spacing', () {
    const original = TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
    );

    final value = insertEmoticonIntoComposerValue(
      original,
      const _TestEmoticon(':party:'),
    );

    expect(value.text, 'hello :party: ');
    expect(value.selection.baseOffset, value.text.length);
  });

  test('inserting an app emoji over selection replaces selected text', () {
    const original = TextEditingValue(
      text: 'hello world',
      selection: TextSelection(baseOffset: 6, extentOffset: 11),
    );

    final value = insertEmoticonIntoComposerValue(
      original,
      const _TestEmoticon(':party:'),
    );

    expect(value.text, 'hello :party: ');
    expect(value.selection.baseOffset, value.text.length);
  });

  test('message effects convert draft text to slash command send text', () {
    final confetti = composerMessageEffects.firstWhere(
      (effect) => effect.label == 'Confetti',
    );

    expect(
      composerEffectSendText(confetti, 'hello there'),
      '/confetti hello there',
    );
  });

  test('hidden and loud effects transform draft text directly', () {
    final hidden = composerMessageEffects.firstWhere(
      (effect) => effect.label == 'Hidden',
    );
    final loud = composerMessageEffects.firstWhere(
      (effect) => effect.label == 'Loud',
    );

    expect(composerEffectSendText(hidden, 'secret'), '||secret||');
    expect(composerEffectSendText(loud, 'important'), '### important');
  });

  test(
    'empty message effect drafts prime the composer with cursor placement',
    () {
      final hidden = composerMessageEffects.firstWhere(
        (effect) => effect.label == 'Hidden',
      );
      final rainbow = composerMessageEffects.firstWhere(
        (effect) => effect.label == 'Rainbow',
      );

      final hiddenDraft = composerEffectDraftValue(hidden)!;
      final rainbowDraft = composerEffectDraftValue(rainbow)!;

      expect(hiddenDraft.text, '||||');
      expect(hiddenDraft.selection.baseOffset, 2);
      expect(rainbowDraft.text, '/rainbow ');
      expect(rainbowDraft.selection.baseOffset, rainbowDraft.text.length);
    },
  );

  test('emoji effects send standalone commands', () {
    final cuddle = composerEmojiEffects.firstWhere(
      (effect) => effect.label == 'Cuddle',
    );

    expect(composerEffectSendText(cuddle, ''), '/cuddle');
  });

  test('composer bracket typing inserts pair with cursor inside', () {
    const original = TextEditingValue.empty;
    const typed = TextEditingValue(
      text: '(',
      selection: TextSelection.collapsed(offset: 1),
    );

    final value = applyComposerBracketTypingValue(original, typed);

    expect(value.text, '()');
    expect(value.selection.baseOffset, 1);
  });

  test('composer bracket typing wraps selected text', () {
    const original = TextEditingValue(
      text: 'hello world',
      selection: TextSelection(baseOffset: 6, extentOffset: 11),
    );
    const typed = TextEditingValue(
      text: 'hello (',
      selection: TextSelection.collapsed(offset: 7),
    );

    final value = applyComposerBracketTypingValue(original, typed);

    expect(value.text, 'hello (world)');
    expect(value.selection.baseOffset, value.text.length);
  });

  test('composer bracket typing skips duplicate closer', () {
    const original = TextEditingValue(
      text: '(hello)',
      selection: TextSelection.collapsed(offset: 6),
    );
    const typed = TextEditingValue(
      text: '(hello))',
      selection: TextSelection.collapsed(offset: 7),
    );

    final value = applyComposerBracketTypingValue(original, typed);

    expect(value.text, '(hello)');
    expect(value.selection.baseOffset, 7);
  });

  test(
    'composer bracket typing exits bracket on second space before closer',
    () {
      const original = TextEditingValue(
        text: '(hello )',
        selection: TextSelection.collapsed(offset: 7),
      );
      const typed = TextEditingValue(
        text: '(hello  )',
        selection: TextSelection.collapsed(offset: 8),
      );

      final value = applyComposerBracketTypingValue(original, typed);

      expect(value.text, '(hello) ');
      expect(value.selection.baseOffset, value.text.length);
    },
  );

  test('composer bracket typing keeps normal spaces before closer text', () {
    const original = TextEditingValue(
      text: 'a )',
      selection: TextSelection.collapsed(offset: 2),
    );
    const typed = TextEditingValue(
      text: 'a  )',
      selection: TextSelection.collapsed(offset: 3),
    );

    final value = applyComposerBracketTypingValue(original, typed);

    expect(value.text, 'a  )');
    expect(value.selection.baseOffset, 3);
  });

  test('composer bracket shortcut wraps selection in parentheses', () {
    const original = TextEditingValue(
      text: 'hello world',
      selection: TextSelection(baseOffset: 0, extentOffset: 5),
    );

    final value = wrapComposerSelectionInBracketsValue(original);

    expect(value.text, '(hello) world');
    expect(value.selection.baseOffset, 7);
  });

  test('composer bracket shortcut ignores collapsed selection', () {
    const original = TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
    );

    expect(wrapComposerSelectionInBracketsValue(original), original);
  });
}

class _TestEmoticon implements Emoticon {
  const _TestEmoticon(this.slug);

  @override
  final String slug;

  @override
  ImageProvider<Object>? get image => null;

  @override
  String get key => slug;

  @override
  String? get shortcode => slug;

  @override
  EmoticonUsage get usage => EmoticonUsage.emoji;

  @override
  bool get isEmoji => true;

  @override
  bool get isSticker => false;
}
