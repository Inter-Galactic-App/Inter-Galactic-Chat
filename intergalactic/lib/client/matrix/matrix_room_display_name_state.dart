const String matrixRoomDisplayNamesStateEventType =
    "chat.intergalactic.app.room_display_names";

const String matrixRoomDisplayNamesLegacyStateEventType =
    "chat.intergalactic.app.member_profile";

const String _matrixRoomDisplayNamesUsersKey = 'users';

String matrixRoomDisplayNamesLegacyStateKey(String userId) =>
    "member:${Uri.encodeComponent(userId)}";

Map<String, String> matrixRoomDisplayNamesFromStateContent(
    Map<String, dynamic>? content) {
  final users = content?[_matrixRoomDisplayNamesUsersKey];
  if (users is! Map) {
    return const {};
  }

  final result = <String, String>{};
  for (final entry in users.entries) {
    final userId = entry.key;
    if (userId is! String) {
      continue;
    }

    final rawValue = entry.value;
    String? displayName;
    if (rawValue is String) {
      displayName = rawValue;
    } else if (rawValue is Map) {
      final nestedValue = rawValue['displayname'];
      if (nestedValue is String) {
        displayName = nestedValue;
      }
    }

    final trimmed = displayName?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      continue;
    }

    result[userId] = trimmed;
  }

  return result;
}

Map<String, Object?> matrixRoomDisplayNamesToStateContent(
  Map<String, String> displayNames, {
  String? updatedBy,
  DateTime? updatedAt,
}) {
  final users = <String, String>{};
  for (final entry in displayNames.entries) {
    final trimmed = entry.value.trim();
    if (trimmed.isEmpty) {
      continue;
    }

    users[entry.key] = trimmed;
  }

  return <String, Object?>{
    _matrixRoomDisplayNamesUsersKey: users,
    if (updatedBy != null && updatedBy.isNotEmpty) 'updated_by': updatedBy,
    if (updatedAt != null) 'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

String normalizeMatrixMentionLabel(String mention) {
  var normalized = mention.trim();
  if (normalized.startsWith('@')) {
    normalized = normalized.substring(1);
  }

  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }

  return normalized.trim();
}

String? readLegacyMatrixRoomDisplayNameFromContent(
    Map<String, dynamic>? content) {
  final rawValue = content?['room_display_name'] ?? content?['displayname'];
  final value = rawValue is String ? rawValue : null;
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  return trimmed;
}

Map<String, Object?> buildLegacyMatrixRoomDisplayNameStateContent(
  String? displayName, {
  String? updatedBy,
  DateTime? updatedAt,
}) {
  final trimmedDisplayName = displayName?.trim();
  if (trimmedDisplayName == null || trimmedDisplayName.isEmpty) {
    return <String, Object?>{};
  }

  return <String, Object?>{
    'displayname': trimmedDisplayName,
    'room_display_name': trimmedDisplayName,
    if (updatedBy != null && updatedBy.isNotEmpty) 'updated_by': updatedBy,
    if (updatedAt != null) 'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

String buildUserMentionSlug(String displayName, String userId) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('@') ||
      trimmed.contains(':') ||
      trimmed.contains('[') ||
      trimmed.contains(']') ||
      trimmed.contains('\n')) {
    return userId;
  }

  return '@[$trimmed]';
}
