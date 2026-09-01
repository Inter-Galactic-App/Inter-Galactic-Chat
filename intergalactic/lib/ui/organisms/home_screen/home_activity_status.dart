import 'package:intergalactic/client/components/activity/game_activity_overlay.dart';

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

  if (gameActivityTitleFromPresenceText(statusText) != null) {
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

  final gameTitle = gameActivityTitleFromPresenceText(trimmed);
  if (gameTitle != null) {
    return gameTitle;
  }

  final normalized = trimmed.toLowerCase();
  if (_matchesMusicActivityStatus(normalized)) {
    return _dropStatusPrefix(
      value: trimmed,
      prefix: 'listening to',
    );
  }
  return trimmed;
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
