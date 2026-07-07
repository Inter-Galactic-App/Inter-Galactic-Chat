import 'dart:math' as math;

import 'package:flutter/services.dart';

const Map<String, String> composerBracketPairs = {
  "(": ")",
  "[": "]",
  "{": "}",
  "<": ">",
};

const Set<String> composerBracketClosers = {")", "]", "}", ">"};

class ComposerBracketInputFormatter extends TextInputFormatter {
  const ComposerBracketInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return applyComposerBracketTypingValue(oldValue, newValue);
  }
}

TextEditingValue applyComposerBracketTypingValue(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
    return newValue;
  }

  final edit = _singleInsertedCharacterEdit(oldValue, newValue);
  if (edit == null) {
    return newValue;
  }

  final inserted = edit.inserted;
  final openerCloser = composerBracketPairs[inserted];
  if (openerCloser != null) {
    final selectedText = oldValue.text.substring(edit.start, edit.end);
    final replacement = "$inserted$selectedText$openerCloser";
    final text = oldValue.text.replaceRange(edit.start, edit.end, replacement);
    final cursorOffset = selectedText.isEmpty
        ? edit.start + inserted.length
        : edit.start + replacement.length;

    return oldValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
  }

  if (composerBracketClosers.contains(inserted) &&
      edit.start == edit.end &&
      edit.start < oldValue.text.length &&
      oldValue.text[edit.start] == inserted) {
    return oldValue.copyWith(
      selection: TextSelection.collapsed(offset: edit.start + 1),
      composing: TextRange.empty,
    );
  }

  if (inserted == " " &&
      edit.start == edit.end &&
      edit.start > 1 &&
      edit.start < oldValue.text.length &&
      oldValue.text[edit.start - 1] == " " &&
      _hasMatchingUnclosedOpenerBefore(
        oldValue.text,
        edit.start - 1,
        oldValue.text[edit.start],
      )) {
    final closer = oldValue.text[edit.start];
    final text = oldValue.text.replaceRange(
      edit.start - 1,
      edit.start + 1,
      "$closer ",
    );
    return oldValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: edit.start + 1),
      composing: TextRange.empty,
    );
  }

  return newValue;
}

TextEditingValue wrapComposerSelectionInBracketsValue(
  TextEditingValue value, {
  String opener = "(",
  String closer = ")",
}) {
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) {
    return value;
  }

  final start = math.min(selection.start, selection.end);
  final end = math.max(selection.start, selection.end);
  final selectedText = value.text.substring(start, end);
  final replacement = "$opener$selectedText$closer";
  final text = value.text.replaceRange(start, end, replacement);

  return value.copyWith(
    text: text,
    selection: TextSelection.collapsed(offset: start + replacement.length),
    composing: TextRange.empty,
  );
}

bool _hasMatchingUnclosedOpenerBefore(
  String text,
  int endExclusive,
  String closer,
) {
  String? opener;
  for (final entry in composerBracketPairs.entries) {
    if (entry.value == closer) {
      opener = entry.key;
      break;
    }
  }
  if (opener == null) {
    return false;
  }

  var nestedClosers = 0;
  for (var i = endExclusive - 1; i >= 0; i--) {
    final character = text[i];
    if (character == closer) {
      nestedClosers++;
      continue;
    }
    if (character == opener) {
      if (nestedClosers == 0) {
        return true;
      }
      nestedClosers--;
    }
  }
  return false;
}

_ComposerBracketEdit? _singleInsertedCharacterEdit(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final selection = oldValue.selection;
  if (selection.isValid) {
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final insertedLength =
        newValue.text.length - oldValue.text.length + end - start;
    if (insertedLength == 1 && start + insertedLength <= newValue.text.length) {
      final inserted = newValue.text.substring(start, start + insertedLength);
      if (oldValue.text.replaceRange(start, end, inserted) == newValue.text) {
        return _ComposerBracketEdit(start: start, end: end, inserted: inserted);
      }
    }
  }

  if (newValue.text.length <= oldValue.text.length) {
    return null;
  }

  var prefix = 0;
  final shortestLength = math.min(oldValue.text.length, newValue.text.length);
  while (prefix < shortestLength &&
      oldValue.text[prefix] == newValue.text[prefix]) {
    prefix++;
  }

  var oldSuffix = oldValue.text.length;
  var newSuffix = newValue.text.length;
  while (oldSuffix > prefix &&
      newSuffix > prefix &&
      oldValue.text[oldSuffix - 1] == newValue.text[newSuffix - 1]) {
    oldSuffix--;
    newSuffix--;
  }

  final inserted = newValue.text.substring(prefix, newSuffix);
  if (inserted.length != 1) {
    return null;
  }

  return _ComposerBracketEdit(
    start: prefix,
    end: oldSuffix,
    inserted: inserted,
  );
}

class _ComposerBracketEdit {
  const _ComposerBracketEdit({
    required this.start,
    required this.end,
    required this.inserted,
  });

  final int start;
  final int end;
  final String inserted;
}
