import 'package:intergalactic/client/components/message_effects/automatic_message_effects.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_types.dart';
import 'package:test/test.dart';

void main() {
  test('matches trigger words case-insensitively', () {
    expect(
      detectAutomaticMessageEffect('CONGRATULATIONS on the win'),
      MessageEffectKind.confetti,
    );
  });

  test('matches trigger words with surrounding punctuation', () {
    expect(
      detectAutomaticMessageEffect('congrats!'),
      MessageEffectKind.confetti,
    );
  });

  test('matches whole words without substring false positives', () {
    expect(detectAutomaticMessageEffect('Happy Pride!'),
        MessageEffectKind.rainbow);
    expect(detectAutomaticMessageEffect('prideful shortcut'), isNull);
    expect(detectAutomaticMessageEffect('eggs are ready'), isNull);
  });

  test('matches phrases and apostrophe variants', () {
    expect(
      detectAutomaticMessageEffect('It\u2019s snowing!'),
      MessageEffectKind.snowfall,
    );
    expect(
      detectAutomaticMessageEffect('passed the exam today'),
      MessageEffectKind.confetti,
    );
  });

  test('matches plus-sign trigger aliases', () {
    expect(
      detectAutomaticMessageEffect('Happy LGBTQ+ meetup'),
      MessageEffectKind.rainbow,
    );
  });

  test('uses deterministic priority when multiple triggers match', () {
    expect(
      detectAutomaticMessageEffect('congrats and happy pride'),
      MessageEffectKind.confetti,
    );
  });

  test('returns only one effect per message', () {
    final effect = detectAutomaticMessageEffect('snow day and game on');

    expect(effect, MessageEffectKind.snowfall);
  });

  test('honors disabled automatic effect setting', () {
    expect(
      detectAutomaticMessageEffect('congrats', enabled: false),
      isNull,
    );
  });

  test('ignores manual slash-command effect messages', () {
    expect(
      detectAutomaticMessageEffect('/confetti congratulations'),
      isNull,
    );
  });

  test('ignores unsupported messages', () {
    expect(detectAutomaticMessageEffect('ordinary status update'), isNull);
  });

  test('ignores triggers hidden inside spoiler-only content', () {
    expect(detectAutomaticMessageEffect('||congratulations||'), isNull);
  });

  test('matches visible text outside spoiler content', () {
    expect(
      detectAutomaticMessageEffect('congrats ||quiet snow day||'),
      MessageEffectKind.confetti,
    );
  });

  test('matches required manual-validation examples', () {
    expect(
      detectAutomaticMessageEffect('snow day'),
      MessageEffectKind.snowfall,
    );
    expect(detectAutomaticMessageEffect('gg'), MessageEffectKind.spaceInvaders);
    expect(
      detectAutomaticMessageEffect('mission complete'),
      MessageEffectKind.spaceInvaders,
    );
  });
}
