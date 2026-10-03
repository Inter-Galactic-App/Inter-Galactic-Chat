/// Returns the canonical Space ancestry for a room, nearest parent first.
///
/// MSC2545 says that image packs from a room's canonical Space hierarchy are
/// suggested recursively. The caller supplies the state-derived parent ids so
/// this stays independent of the Matrix SDK and is straightforward to test.
/// Malformed cyclic hierarchies are tolerated: each id is returned at most once.
List<String> canonicalSpaceAncestorIds({
  required String roomId,
  required Iterable<String> Function(String roomId) canonicalParentIdsFor,
}) {
  final pending = List<String>.of(canonicalParentIdsFor(roomId));
  final visited = <String>{roomId};
  final ancestors = <String>[];

  // A malicious or malformed Space graph must not cause unbounded discovery.
  while (pending.isNotEmpty && ancestors.length < 128) {
    final candidate = pending.removeAt(0);
    if (!visited.add(candidate)) continue;

    ancestors.add(candidate);
    pending.addAll(canonicalParentIdsFor(candidate));
  }

  return ancestors;
}

/// Extracts canonical parent ids directly from `m.space.parent` state.
///
/// A canonical flag alone does not establish a valid Space parent. The caller
/// must validate the event's `via` and the parent's reciprocal link or sender
/// authority. Multiple valid canonical links resolve to the lowest room ID.
Iterable<String> canonicalSpaceParentIds<T>({
  required Map<String, T>? parentState,
  required bool Function(T state) isCanonical,
  required bool Function(T state) hasValidVia,
  required bool Function(String parentId, T state) isLegitimateParent,
}) {
  final valid = parentState?.entries
      .where(
        (entry) =>
            isCanonical(entry.value) &&
            hasValidVia(entry.value) &&
            isLegitimateParent(entry.key, entry.value),
      )
      .map((entry) => entry.key)
      .toList();
  if (valid == null || valid.isEmpty) return const <String>[];
  valid.sort();
  return [valid.first];
}
