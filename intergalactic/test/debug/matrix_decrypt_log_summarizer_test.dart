import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/debug/matrix_decrypt_log_summarizer.dart';

void main() {
  test('classifies known Matrix room decrypt log spam', () {
    expect(
      MatrixDecryptLogSummarizer.classifyRoomDecryptLog(
        '[Matrix] Could not decrypt event - The sender has not sent us the session key.',
      ),
      'missing_room_session',
    );
    expect(
      MatrixDecryptLogSummarizer.classifyRoomDecryptLog(
        'Matrix SDK debug: Could not decrypt event reason=missing_room_session',
      ),
      'missing_room_session',
    );
    expect(
      MatrixDecryptLogSummarizer.classifyRoomDecryptLog(
        'Could not decrypt event because the sender has not sent us a session key.',
      ),
      'missing_room_session',
    );
    expect(
      MatrixDecryptLogSummarizer.classifyRoomDecryptLog(
        'Could not decrypt event: unable to decrypt with any olm session',
      ),
      'unable_to_decrypt_olm',
    );
    expect(
      MatrixDecryptLogSummarizer.classifyRoomDecryptLog(
        '[Vodozemac] Could not decrypt to device event',
      ),
      isNull,
    );
    expect(
      MatrixDecryptLogSummarizer.classifyRoomDecryptLog('Regular sync update'),
      isNull,
    );
  });

  test('classifies bare reason= decrypt logs without the event prefix', () {
    const reasons = [
      'unknown_one_time_key',
      'missing_room_session',
      'unverified_or_withheld',
      'unable_to_decrypt_olm',
      'olm_decryption_failed',
      'corrupted_session',
      'not_sent_for_this_device',
    ];

    for (final reason in reasons) {
      expect(
        MatrixDecryptLogSummarizer.classifyRoomDecryptLog(
          'Matrix SDK decrypt failure reason=$reason session=redacted',
        ),
        reason,
        reason: 'bare reason=$reason should classify without the prefix',
      );
    }

    // A reason marker without any decrypt context stays unclassified.
    expect(
      MatrixDecryptLogSummarizer.classifyRoomDecryptLog(
        'key request queued reason=unknown_one_time_key',
      ),
      isNull,
    );
  });

  test('summarizes repeated room decrypt logs by interval', () {
    var now = DateTime.utc(2026, 6, 21, 12);
    final emitted = <String>[];
    final summarizer = MatrixDecryptLogSummarizer(
      sourceLabel: 'sdk-log',
      interval: const Duration(seconds: 30),
      now: () => now,
    );

    final handledFirst = summarizer.record(
      'Could not decrypt event - The sender has not sent us the session key.',
      emit: emitted.add,
    );
    final handledSecond = summarizer.record(
      'Could not decrypt event - The sender has not sent us the session key.',
      emit: emitted.add,
    );

    expect(handledFirst, isTrue);
    expect(handledSecond, isTrue);
    expect(emitted, hasLength(1));
    expect(emitted.single, contains('source=sdk-log'));
    expect(emitted.single, contains('reason=missing_room_session'));
    expect(emitted.single, contains('count=1'));

    now = now.add(const Duration(seconds: 31));
    summarizer.record(
      'Could not decrypt event - The sender has not sent us the session key.',
      emit: emitted.add,
    );

    expect(emitted, hasLength(2));
    expect(emitted.last, contains('count=2'));
  });

  test('does not handle unrelated SDK logs', () {
    final emitted = <String>[];
    final summarizer = MatrixDecryptLogSummarizer(sourceLabel: 'sdk-log');

    final handled = summarizer.record(
      'Ignoring call event org.matrix.msc3401.call.member',
      emit: emitted.add,
    );

    expect(handled, isFalse);
    expect(emitted, isEmpty);
  });
}
