import 'package:intergalactic/client/components/message_effects/message_effect_types.dart';

class AutomaticMessageEffectTrigger {
  const AutomaticMessageEffectTrigger({
    required this.effect,
    required this.phrase,
  });

  final MessageEffectKind effect;
  final String phrase;
}

const automaticMessageEffectPriority = <MessageEffectKind>[
  MessageEffectKind.confetti,
  MessageEffectKind.rainbow,
  MessageEffectKind.snowfall,
  MessageEffectKind.spaceInvaders,
];

const automaticMessageEffectTriggers = <AutomaticMessageEffectTrigger>[
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "congratulations",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "congrats",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "well done",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "great job",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "you did it",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "we did it",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "promotion",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "graduated",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "graduation",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "passed the exam",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "passed my boards",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "engaged",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "engagement",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "married",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "wedding",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "anniversary",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "happy birthday",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "birthday",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "mission accomplished",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "success",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.confetti,
    phrase: "victory",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.rainbow,
    phrase: "pride",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.rainbow,
    phrase: "happy pride",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.rainbow,
    phrase: "pride month",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.rainbow,
    phrase: "lgbt",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.rainbow,
    phrase: "lgbtq",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.rainbow,
    phrase: "lgbtqia",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.rainbow,
    phrase: "lgbtq+",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.rainbow,
    phrase: "love is love",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "it's snowing",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "its snowing",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "snow day",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "first snowfall",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "let it snow",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "winter is here",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "blizzard",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "merry christmas",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.snowfall,
    phrase: "happy holidays",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "game on",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "high score",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "level up",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "achievement unlocked",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "gg",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "ggs",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "victory royale",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "new record",
  ),
  AutomaticMessageEffectTrigger(
    effect: MessageEffectKind.spaceInvaders,
    phrase: "mission complete",
  ),
];

MessageEffectKind? detectAutomaticMessageEffect(
  String message, {
  bool enabled = true,
}) {
  if (!enabled) {
    return null;
  }

  final visibleMessage = _visibleMessageForAutomaticEffects(message);
  final normalized = _normalizeForAutomaticEffects(visibleMessage.trim());
  if (normalized.isEmpty || normalized.startsWith('/')) {
    return null;
  }

  for (final effect in automaticMessageEffectPriority) {
    for (final trigger in automaticMessageEffectTriggers) {
      if (trigger.effect != effect) {
        continue;
      }
      if (_matchesTrigger(normalized, trigger.phrase)) {
        return effect;
      }
    }
  }

  return null;
}

String _visibleMessageForAutomaticEffects(String message) {
  final result = StringBuffer();
  var cursor = 0;

  while (cursor < message.length) {
    final start = message.indexOf('||', cursor);
    if (start == -1) {
      result.write(message.substring(cursor));
      break;
    }

    final end = message.indexOf('||', start + 2);
    if (end == -1) {
      result.write(message.substring(cursor));
      break;
    }

    result.write(message.substring(cursor, start));
    result.write(' ');
    cursor = end + 2;
  }

  return result.toString();
}

String _normalizeForAutomaticEffects(String value) {
  var result = value.toLowerCase();
  for (final codePoint in const [
    0x2018,
    0x2019,
    0x201A,
    0x201B,
    0x2032,
    0x02BC,
    0x0060,
  ]) {
    result = result.replaceAll(String.fromCharCode(codePoint), "'");
  }
  return result;
}

bool _matchesTrigger(String normalizedMessage, String phrase) {
  final normalizedPhrase = _normalizeForAutomaticEffects(phrase.trim());
  if (normalizedPhrase.isEmpty) {
    return false;
  }

  final phrasePattern = normalizedPhrase
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map(RegExp.escape)
      .join(r'\s+');
  final pattern = RegExp('(^|[^a-z0-9])$phrasePattern(?=\$|[^a-z0-9])');
  return pattern.hasMatch(normalizedMessage);
}
