enum HomeActivityStatusKind {
  game,
  music,
}

HomeActivityStatusKind? homeActivityStatusKindForStatusText(
  String? statusText,
) {
  final normalized = statusText?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  if (_matchesGameActivityStatus(normalized)) {
    return HomeActivityStatusKind.game;
  }
  if (_matchesMusicActivityStatus(normalized)) {
    return HomeActivityStatusKind.music;
  }
  return null;
}

bool isGameActivityStatusText(String? statusText) {
  return homeActivityStatusKindForStatusText(statusText) ==
      HomeActivityStatusKind.game;
}

bool isMusicActivityStatusText(String? statusText) {
  return homeActivityStatusKindForStatusText(statusText) ==
      HomeActivityStatusKind.music;
}

String? homeActivityStatusBubbleText(String? statusText) {
  final trimmed = statusText?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final normalized = trimmed.toLowerCase();
  if (_matchesMusicActivityStatus(normalized)) {
    return _dropStatusPrefix(
      value: trimmed,
      prefix: 'listening to',
    );
  }
  if (_matchesGameActivityStatus(normalized)) {
    if (normalized.startsWith('playing:')) {
      final title = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      return title.isEmpty ? trimmed : title;
    }
    return _dropStatusPrefix(
      value: trimmed,
      prefix: 'playing',
    );
  }
  return trimmed;
}

bool _matchesGameActivityStatus(String normalized) {
  return normalized == 'playing' ||
      normalized.startsWith('playing ') ||
      normalized.startsWith('playing:');
}

bool _matchesMusicActivityStatus(String normalized) {
  return normalized == 'listening to' || normalized.startsWith('listening to ');
}

String _dropStatusPrefix({
  required String value,
  required String prefix,
}) {
  final title = value.substring(prefix.length).trim();
  return title.isEmpty ? value : title;
}
