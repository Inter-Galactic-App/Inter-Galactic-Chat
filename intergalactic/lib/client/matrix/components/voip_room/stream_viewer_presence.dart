import 'dart:convert';

const streamViewerIntentTopic = 'intergalactic.stream_viewers.v1';

Map<String, Set<String>> groupWatchedScreenSharesByPublisher({
  required Iterable<({String streamId, String publisherIdentity})> remoteShares,
  required Set<String> watchedIds,
}) {
  final byPublisher = <String, Set<String>>{};
  for (final share in remoteShares) {
    if (!watchedIds.contains(share.streamId)) continue;
    byPublisher
        .putIfAbsent(share.publisherIdentity, () => <String>{})
        .add(share.streamId);
  }
  return byPublisher;
}

class StreamViewerIntent {
  const StreamViewerIntent(this.streamIds);

  final Set<String> streamIds;

  List<int> encode() => utf8.encode(
    jsonEncode({'version': 1, 'streamIds': streamIds.toList(growable: false)}),
  );

  static StreamViewerIntent? decode(String? topic, List<int> data) {
    if (topic != streamViewerIntentTopic || data.length > 2048) return null;
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map || decoded['version'] != 1) return null;
      final ids = decoded['streamIds'];
      if (ids is! List || ids.length > 16) return null;
      final streamIds = <String>{};
      for (final id in ids) {
        if (id is! String || id.isEmpty || id.length > 128) return null;
        streamIds.add(id);
      }
      return StreamViewerIntent(streamIds);
    } catch (_) {
      return null;
    }
  }
}

class StreamViewerPresence {
  StreamViewerPresence({this.ttl = const Duration(seconds: 45)});

  final Duration ttl;
  final Map<String, _ViewerEntry> _entries = {};

  Set<String> get viewerIdentities => _entries.keys.toSet();

  bool update({
    required String participantIdentity,
    required Set<String> publishedStreamIds,
    required Set<String> reportedStreamIds,
    required DateTime now,
  }) {
    final validIds = reportedStreamIds.intersection(publishedStreamIds);
    final before = _entries[participantIdentity]?.streamIds;
    if (validIds.isEmpty) {
      return _entries.remove(participantIdentity) != null;
    }
    _entries[participantIdentity] = _ViewerEntry(validIds, now);
    return before == null || !_sameIds(before, validIds);
  }

  bool removeParticipant(String participantIdentity) =>
      _entries.remove(participantIdentity) != null;

  bool prune({required Set<String> publishedStreamIds, required DateTime now}) {
    var changed = false;
    for (final entry in _entries.entries.toList(growable: false)) {
      final validIds = entry.value.streamIds.intersection(publishedStreamIds);
      if (now.difference(entry.value.updatedAt) >= ttl || validIds.isEmpty) {
        _entries.remove(entry.key);
        changed = true;
      } else if (!_sameIds(validIds, entry.value.streamIds)) {
        _entries[entry.key] = _ViewerEntry(validIds, entry.value.updatedAt);
        changed = true;
      }
    }
    return changed;
  }

  static bool _sameIds(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

class _ViewerEntry {
  const _ViewerEntry(this.streamIds, this.updatedAt);

  final Set<String> streamIds;
  final DateTime updatedAt;
}
