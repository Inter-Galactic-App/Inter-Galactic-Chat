enum WebRestoreDisposition {
  restored,
  missingStoredSession,
  recoverableInitFailure,
  corruptInitFailure,
}

class WebRestoreSnapshot {
  const WebRestoreSnapshot({
    required this.candidateClientIds,
    required this.restoredClientIds,
    required this.missingStoredSessionClientIds,
    required this.recoverableFailureClientIds,
    required this.corruptFailureClientIds,
    required this.storageDiagnostics,
    required this.notesByClientId,
  });

  const WebRestoreSnapshot.empty()
      : candidateClientIds = const <String>[],
        restoredClientIds = const <String>[],
        missingStoredSessionClientIds = const <String>[],
        recoverableFailureClientIds = const <String>[],
        corruptFailureClientIds = const <String>[],
        storageDiagnostics = const <String, dynamic>{},
        notesByClientId = const <String, String>{};

  final List<String> candidateClientIds;
  final List<String> restoredClientIds;
  final List<String> missingStoredSessionClientIds;
  final List<String> recoverableFailureClientIds;
  final List<String> corruptFailureClientIds;
  final Map<String, dynamic> storageDiagnostics;
  final Map<String, String> notesByClientId;

  bool get hasAnyHints => candidateClientIds.isNotEmpty;

  bool get hasRecoverableLoss =>
      missingStoredSessionClientIds.isNotEmpty ||
      recoverableFailureClientIds.isNotEmpty;

  bool get hasCorruptFailures => corruptFailureClientIds.isNotEmpty;
}
