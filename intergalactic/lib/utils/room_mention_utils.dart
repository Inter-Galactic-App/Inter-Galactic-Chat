const String matrixRoomMention = '@room';

class RoomMentionPart {
  const RoomMentionPart(this.text, {this.isMention = false});

  final String text;
  final bool isMention;
}

bool isRoomMentionText(String text) => text == matrixRoomMention;

bool containsRoomMentionText(String text) =>
    splitRoomMentionParts(text).any((part) => part.isMention);

List<RoomMentionPart> splitRoomMentionParts(String text) {
  if (text.isEmpty) {
    return const [];
  }

  final parts = <RoomMentionPart>[];
  var index = 0;

  while (index < text.length) {
    final matchStart = text.indexOf(matrixRoomMention, index);
    if (matchStart == -1) {
      parts.add(RoomMentionPart(text.substring(index)));
      break;
    }

    final matchEnd = matchStart + matrixRoomMention.length;
    if (!_isRoomMentionBoundary(text, matchStart, matchEnd)) {
      parts.add(RoomMentionPart(text.substring(index, matchStart + 1)));
      index = matchStart + 1;
      continue;
    }

    if (matchStart > index) {
      parts.add(RoomMentionPart(text.substring(index, matchStart)));
    }

    parts.add(const RoomMentionPart(matrixRoomMention, isMention: true));
    index = matchEnd;
  }

  if (parts.isEmpty) {
    return [RoomMentionPart(text)];
  }

  return parts;
}

bool _isRoomMentionBoundary(String text, int start, int end) {
  final previous = start > 0 ? text[start - 1] : null;
  final next = end < text.length ? text[end] : null;

  return _isBoundaryCharacter(previous) && _isBoundaryCharacter(next);
}

bool _isBoundaryCharacter(String? char) {
  if (char == null) {
    return true;
  }

  return !RegExp(r'[A-Za-z0-9_]').hasMatch(char);
}
