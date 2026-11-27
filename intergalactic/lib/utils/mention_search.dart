/// Matching rules for the `@` mention autocomplete.
///
/// A member is discoverable by every name they are known under: the room
/// nickname the suggestion row shows, the localpart of their Matrix user id
/// (their "username"), their global account display name, and their full user
/// id. Nicknames are changed often here, so matching the nickname alone made a
/// well known person unfindable the moment they renamed themselves.
library;

/// The identity fields of one member that a mention query may be matched
/// against, in the order they break a ranking tie.
enum MentionSearchField {
  /// The name the suggestion row shows — the room nickname when one is set.
  displayName,

  /// The localpart of the user id, e.g. `alice` for `@alice:example.org`.
  localpart,

  /// The global account display name, independent of any room nickname.
  accountDisplayName,

  /// The full user id, e.g. `@alice:example.org`. Only consulted for a
  /// domain-qualified query — see [_fieldAppliesToQuery].
  userId,
}

/// How strongly a field value matched the query. Lower indexes rank first, so
/// an exact or prefix match is never pushed below a weaker one.
enum _MentionMatchKind { exact, prefix, wordPrefix, contains, subsequence }

/// One room member reduced to the fields the mention search matches against.
class MentionSearchCandidate {
  const MentionSearchCandidate({
    required this.userId,
    required this.displayName,
    this.accountDisplayName,
  });

  /// Full Matrix user id, e.g. `@alice:example.org`.
  final String userId;

  /// What the suggestion row displays: the room nickname when one is set,
  /// otherwise the account display name.
  final String displayName;

  /// The global account display name, when it is known. This is what
  /// [displayName] falls back to when the member has no room nickname, so the
  /// two are often equal — the dedup keeps that from producing two rows.
  final String? accountDisplayName;

  /// Localpart of [userId] — the part a member thinks of as their username.
  String get localpart => matrixLocalpart(userId);
}

/// Localpart of a Matrix user id: `@alice:example.org` -> `alice`.
String matrixLocalpart(String userId) {
  var value = userId;
  if (value.startsWith('@')) {
    value = value.substring(1);
  }

  final separator = value.indexOf(':');
  return separator == -1 ? value : value.substring(0, separator);
}

/// Normalizes the text typed after the `@` trigger for comparison.
String normalizeMentionQuery(String query) {
  var normalized = query.trim();
  while (normalized.startsWith('@')) {
    normalized = normalized.substring(1);
  }

  return normalized.toLowerCase();
}

/// Whether [query] matches the literal [value] under the same rules the
/// candidate search uses. Used for the non-member `@room` suggestion.
bool mentionQueryMatches(String value, String query) {
  final normalizedQuery = normalizeMentionQuery(query);
  if (normalizedQuery.isEmpty) {
    return true;
  }

  return _matchKind(normalizeMentionQuery(value), normalizedQuery) != null;
}

/// Returns the candidates matching [query] on any of their identity fields,
/// best match first, each candidate at most once.
///
/// An empty query returns every candidate in the order given, which is what
/// typing a bare `@` has always shown. [limit] caps the result count; pass
/// null for no cap.
List<MentionSearchCandidate> searchMentionCandidates(
  String query,
  Iterable<MentionSearchCandidate> candidates, {
  int? limit,
}) {
  final all = candidates.toList(growable: false);
  final normalizedQuery = normalizeMentionQuery(query);

  if (normalizedQuery.isEmpty) {
    if (limit == null || all.length <= limit) {
      return all.toList();
    }

    return all.sublist(0, limit);
  }

  final matches = <_MentionSearchMatch>[];
  for (var index = 0; index < all.length; index++) {
    final candidate = all[index];
    for (final field in MentionSearchField.values) {
      if (!_fieldAppliesToQuery(field, normalizedQuery)) {
        continue;
      }

      final value = _fieldValue(candidate, field);
      if (value == null || value.isEmpty) {
        continue;
      }

      final kind = _matchKind(value.toLowerCase(), normalizedQuery);
      if (kind == null) {
        continue;
      }

      matches.add(_MentionSearchMatch(candidate, index, field, kind));
    }
  }

  // Rank before deduplicating so the entry kept for a member is their
  // strongest match, not whichever field happened to be checked first.
  matches.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) {
      return byKind;
    }

    final byField = a.field.index.compareTo(b.field.index);
    if (byField != 0) {
      return byField;
    }

    return a.order.compareTo(b.order);
  });

  // A member who matches on nickname AND username AND account name is still
  // one person, so they get one suggestion.
  final seenUserIds = <String>{};
  final results = <MentionSearchCandidate>[];
  for (final match in matches) {
    if (!seenUserIds.add(match.candidate.userId)) {
      continue;
    }

    results.add(match.candidate);
    if (limit != null && results.length >= limit) {
      break;
    }
  }

  return results;
}

class _MentionSearchMatch {
  const _MentionSearchMatch(this.candidate, this.order, this.field, this.kind);

  final MentionSearchCandidate candidate;

  /// Position in the input list, so equally ranked matches keep member order
  /// even though [List.sort] is not stable.
  final int order;

  final MentionSearchField field;
  final _MentionMatchKind kind;
}

/// The full user id is only searched when the query looks like one.
///
/// [MentionSearchField.localpart] already covers plain username queries, and
/// leaving the id always searchable would let the server domain match — typing
/// `ourgalaxy` would suggest every member of the room.
bool _fieldAppliesToQuery(MentionSearchField field, String normalizedQuery) {
  if (field != MentionSearchField.userId) {
    return true;
  }

  return normalizedQuery.contains(':');
}

String? _fieldValue(
  MentionSearchCandidate candidate,
  MentionSearchField field,
) {
  switch (field) {
    case MentionSearchField.displayName:
      return candidate.displayName;
    case MentionSearchField.localpart:
      return candidate.localpart;
    case MentionSearchField.accountDisplayName:
      return candidate.accountDisplayName;
    case MentionSearchField.userId:
      return candidate.userId;
  }
}

/// Both arguments must already be lowercased.
_MentionMatchKind? _matchKind(String value, String query) {
  if (value == query) {
    return _MentionMatchKind.exact;
  }

  if (value.startsWith(query)) {
    return _MentionMatchKind.prefix;
  }

  if (_hasWordPrefix(value, query)) {
    return _MentionMatchKind.wordPrefix;
  }

  if (value.contains(query)) {
    return _MentionMatchKind.contains;
  }

  if (_isSubsequence(value, query)) {
    return _MentionMatchKind.subsequence;
  }

  return null;
}

const _wordSeparators = {
  ' ', '\t', '\n', '_', '-', '.', ':', '/', ',', '+', '@', '|', //
  '(', ')', '[', ']', '\'', '"',
};

/// Whether [query] starts one of the later words in [value], so that typing
/// `smith` finds `Jane Smith`.
bool _hasWordPrefix(String value, String query) {
  for (var index = 1; index < value.length; index++) {
    if (!_wordSeparators.contains(value[index - 1])) {
      continue;
    }

    if (value.startsWith(query, index)) {
      return true;
    }
  }

  return false;
}

/// Loose fallback that keeps the typo tolerance the fuzzy search used to give:
/// every character of [query] appears in [value], in order.
bool _isSubsequence(String value, String query) {
  var valueIndex = 0;
  var queryIndex = 0;

  while (valueIndex < value.length && queryIndex < query.length) {
    if (value[valueIndex] == query[queryIndex]) {
      queryIndex++;
    }

    valueIndex++;
  }

  return queryIndex == query.length;
}
