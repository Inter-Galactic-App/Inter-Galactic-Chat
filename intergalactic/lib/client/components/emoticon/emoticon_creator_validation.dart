enum EmoticonShortcodeValidationCode {
  valid,
  empty,
  spaces,
  uppercase,
  invalidCharacters,
  duplicate,
}

class EmoticonShortcodeValidationResult {
  const EmoticonShortcodeValidationResult({
    required this.code,
    required this.normalized,
    this.message,
  });

  final EmoticonShortcodeValidationCode code;
  final String normalized;
  final String? message;

  bool get isValid => code == EmoticonShortcodeValidationCode.valid;
}

EmoticonShortcodeValidationResult validateEmoticonShortcode(
  String value, {
  Iterable<String> existingShortcodes = const [],
  String? previousShortcode,
}) {
  final trimmed = value.trim();
  final normalized = trimmed.toLowerCase();

  if (trimmed.isEmpty) {
    return const EmoticonShortcodeValidationResult(
      code: EmoticonShortcodeValidationCode.empty,
      normalized: '',
      message: 'Enter a shortcode before saving.',
    );
  }

  if (trimmed.contains(RegExp(r'\s'))) {
    return EmoticonShortcodeValidationResult(
      code: EmoticonShortcodeValidationCode.spaces,
      normalized: normalized,
      message: 'Shortcodes cannot contain spaces.',
    );
  }

  if (trimmed != normalized) {
    return EmoticonShortcodeValidationResult(
      code: EmoticonShortcodeValidationCode.uppercase,
      normalized: normalized,
      message: 'Use lowercase letters for shortcodes.',
    );
  }

  if (!RegExp(r'^[a-z0-9_:-]+$').hasMatch(trimmed)) {
    return EmoticonShortcodeValidationResult(
      code: EmoticonShortcodeValidationCode.invalidCharacters,
      normalized: normalized,
      message: 'Use letters, numbers, hyphens, underscores, or colons.',
    );
  }

  final previous = previousShortcode?.toLowerCase();
  final duplicates = existingShortcodes
      .map((shortcode) => shortcode.toLowerCase())
      .where((shortcode) => shortcode != previous);
  if (duplicates.contains(normalized)) {
    return EmoticonShortcodeValidationResult(
      code: EmoticonShortcodeValidationCode.duplicate,
      normalized: normalized,
      message: 'That shortcode is already used in this pack.',
    );
  }

  return EmoticonShortcodeValidationResult(
    code: EmoticonShortcodeValidationCode.valid,
    normalized: normalized,
  );
}
