class MatrixDecryptLogSummarizer {
  MatrixDecryptLogSummarizer({
    required this.sourceLabel,
    this.interval = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String sourceLabel;
  final Duration interval;
  final DateTime Function() _now;
  final Map<String, _MatrixDecryptLogBucket> _buckets =
      <String, _MatrixDecryptLogBucket>{};

  bool record(String text, {required void Function(String message) emit}) {
    final reason = classifyRoomDecryptLog(text);
    if (reason == null) {
      return false;
    }

    final bucket = _buckets.putIfAbsent(
      reason,
      () => _MatrixDecryptLogBucket(),
    );
    bucket.countSinceLastLog++;

    final now = _now();
    final lastLoggedAt = bucket.lastLoggedAt;
    if (lastLoggedAt != null && now.difference(lastLoggedAt) < interval) {
      return true;
    }

    emit(
      'Matrix SDK room decrypt logs summarized source=$sourceLabel '
      'reason=$reason count=${bucket.countSinceLastLog}',
    );
    bucket.countSinceLastLog = 0;
    bucket.lastLoggedAt = now;
    return true;
  }

  static String? classifyRoomDecryptLog(String text) {
    final lower = text.toLowerCase();
    if (!_looksLikeRoomDecryptLog(lower)) {
      return null;
    }

    if (lower.contains('reason=unknown_one_time_key') ||
        lower.contains('unknown one-time key')) {
      return 'unknown_one_time_key';
    }
    if (lower.contains('reason=missing_room_session') ||
        lower.contains('has not sent us a session key') ||
        lower.contains('has not sent us the session key') ||
        lower.contains('unknown inbound group session') ||
        lower.contains('unknown session')) {
      return 'missing_room_session';
    }
    if (lower.contains('reason=unverified_or_withheld') ||
        lower.contains('m.unverified') ||
        lower.contains('unverified device') ||
        lower.contains('not verified')) {
      return 'unverified_or_withheld';
    }
    if (lower.contains('reason=unable_to_decrypt_olm') ||
        lower.contains('unabletodecryptwithanyolmsession') ||
        lower.contains('unable to decrypt with any olm session')) {
      return 'unable_to_decrypt_olm';
    }
    if (lower.contains('reason=olm_decryption_failed') ||
        lower.contains('decryption failed')) {
      return 'olm_decryption_failed';
    }
    if (lower.contains('reason=corrupted_session') ||
        lower.contains('channel corrupted') ||
        lower.contains('corrupted session')) {
      return 'corrupted_session';
    }
    if (lower.contains('reason=not_sent_for_this_device') ||
        lower.contains('is not sent for this device')) {
      return 'not_sent_for_this_device';
    }
    return 'other_room_decrypt_failure';
  }

  static const List<String> _knownReasonMarkers = [
    'reason=unknown_one_time_key',
    'reason=missing_room_session',
    'reason=unverified_or_withheld',
    'reason=unable_to_decrypt_olm',
    'reason=olm_decryption_failed',
    'reason=corrupted_session',
    'reason=not_sent_for_this_device',
  ];

  static bool _looksLikeRoomDecryptLog(String lower) {
    if (lower.contains('could not decrypt event')) {
      return true;
    }
    if (lower.contains('bad encrypted') && lower.contains('decrypt')) {
      return true;
    }
    return lower.contains('decrypt') && _knownReasonMarkers.any(lower.contains);
  }
}

class _MatrixDecryptLogBucket {
  DateTime? lastLoggedAt;
  int countSinceLastLog = 0;
}
