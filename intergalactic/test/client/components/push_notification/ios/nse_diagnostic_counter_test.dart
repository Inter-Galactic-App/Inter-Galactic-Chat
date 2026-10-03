import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/ios/nse_diagnostic_counter_io.dart';
import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  group('NseDiagnosticCounter.summarize', () {
    final now = DateTime.utc(2026, 9, 20);

    Map<String, Object?> document() => {
      'version': 1,
      'window_opened_day': '2026-09-05',
      'counters': {
        'ok.unknown': 40,
        'busy.unknown': 3,
        'hot_journal.unknown': 1,
      },
      'extended_codes': {'5': 3, '14': 1, 'other': 2},
      'streak': {'outcome': 'busy', 'runs': 2, 'started_minute': 29800000},
      'closed_streaks': {
        'busy': {'lt5m': 1},
        'hot_journal': {'lt2h': 1},
      },
    };

    test('renders one line of literals and integers, no timestamps', () {
      final summary = NseDiagnosticCounter.summarize(document(), now: now)!;
      expect(
        summary.line,
        'nse_db_read window_age_days=15 ok=40 busy=3 hot_journal=1 missing=0 '
        'timeout=0 streak=busy:2 closed=busy:lt5m=1,hot_journal:lt2h=1 '
        'ext=5:3,14:1,other:2',
      );
      expect(summary.line, isNot(contains('29800000')));
      expect(summary.line, isNot(contains('/')));
      expect(summary.expired, isFalse);
    });

    test('expires after ninety days, not before', () {
      expect(
        NseDiagnosticCounter.summarize(
          document(),
          now: DateTime.utc(2026, 12, 4),
        )!.expired,
        isFalse,
      );
      expect(
        NseDiagnosticCounter.summarize(
          document(),
          now: DateTime.utc(2026, 12, 5),
        )!.expired,
        isTrue,
      );
    });

    test('ignores keys outside the fixed shape', () {
      final doc = document();
      doc['counters'] = {'ok.unknown': 1, 'room_id': 7, 'ok.extra': 2};
      doc['closed_streaks'] = {
        'busy': {'lt5m': 1, 'free_text': 9},
      };
      doc['extended_codes'] = {'5': 1, 'path': 3};
      final summary = NseDiagnosticCounter.summarize(doc, now: now)!;
      expect(summary.line, contains(' ok=3 '));
      expect(summary.line, isNot(contains('room_id')));
      expect(summary.line, isNot(contains('free_text')));
      expect(summary.line, isNot(contains('path')));
    });

    test('returns null for a wrong version or a missing window day', () {
      expect(NseDiagnosticCounter.summarize({'version': 2}, now: now), isNull);
      expect(NseDiagnosticCounter.summarize({'version': 1}, now: now), isNull);
      expect(NseDiagnosticCounter.summarize('text', now: now), isNull);
    });
  });

  // D6 says the host deletes a file it cannot use. `summarize` returning null
  // is only ONE of the two ways that happens - a file that will not decode at
  // all never reaches `summarize`, and used to survive every launch.
  group('NseDiagnosticCounter.onLaunch', () {
    final now = DateTime.utc(2026, 9, 20);
    late Directory tempDir;

    File counterFile() => File(
      p.join(
        tempDir.path,
        NseDiagnosticCounter.directoryName,
        NseDiagnosticCounter.fileName,
      ),
    );

    void writeCounter(String contents) {
      final file = counterFile();
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ig-nse-counter');
      NseDiagnosticCounter.host = _FakeHost(tempDir.path);
      NseDiagnosticCounter.platformIsIOS = true;
    });

    tearDown(() {
      NseDiagnosticCounter.host = null;
      NseDiagnosticCounter.platformIsIOS = null;
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // The likely corruption for a file the extension appends to under a
    // background deadline: the last write was cut short. This takes the DECODE
    // path, not the summarize-returns-null path below.
    test(
      'a truncated file is deleted rather than warned about forever',
      () async {
        writeCounter('{"version": 1, "counters": {"ok');

        await NseDiagnosticCounter.onLaunch(now: now);

        expect(counterFile().existsSync(), isFalse);
      },
    );

    // Positive control for the delete path itself, so the case above cannot
    // pass for a harness that deletes (or never wrote) regardless.
    test('a decodable file of the wrong shape is still deleted', () async {
      writeCounter(jsonEncode({'version': 2}));

      await NseDiagnosticCounter.onLaunch(now: now);

      expect(counterFile().existsSync(), isFalse);
    });

    // The other half of the control: onLaunch must not simply delete whatever
    // it finds, or both cases above would pass with the read removed.
    test('a valid in-window file is read and kept', () async {
      writeCounter(
        jsonEncode({
          'version': 1,
          'window_opened_day': '2026-09-05',
          'counters': {'ok.unknown': 1},
        }),
      );

      await NseDiagnosticCounter.onLaunch(now: now);

      expect(counterFile().existsSync(), isTrue);
    });
  });
}

/// Only [containerPath] is used by the counter; anything else reaching this
/// fake is a test that has drifted into unmodelled behaviour.
class _FakeHost implements AppGroupStorageHost {
  _FakeHost(this.containerRoot);

  final String containerRoot;

  @override
  Future<String?> containerPath() async => containerRoot;

  @override
  Future<String?> protectItem(String path) async =>
      throw UnimplementedError('protectItem');

  @override
  Future<String?> readProtectionClass(String path) async =>
      throw UnimplementedError('readProtectionClass');

  @override
  Future<bool> excludeFromBackup(String path) async =>
      throw UnimplementedError('excludeFromBackup');
}
