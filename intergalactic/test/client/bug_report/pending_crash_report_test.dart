import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report_store.dart';
import 'package:intergalactic/debug/log.dart';

void main() {
  test('fromError redacts sensitive crash details', () {
    final fixtureRoot = _windowsFixtureRoot;
    final report = PendingCrashReport.fromError(
      error: StateError(
        'access_token=secret-token in $fixtureRoot'
        r'\AppData\Local\file.txt',
      ),
      stackTrace: StackTrace.fromString(
        '@alice:example.test in !room:example.test\n'
        '$fixtureRoot'
        r'\project\main.dart 10:2',
      ),
      source: 'run-zoned-guarded',
      content: 'Unhandled app zone error access_token=secret-token',
      occurredAt: DateTime.utc(2026, 6, 9, 12),
    );

    final encoded = report.toJsonString();
    expect(encoded, isNot(contains('secret-token')));
    expect(encoded, isNot(contains('@alice:example.test')));
    expect(encoded, isNot(contains('!room:example.test')));
    expect(encoded, isNot(contains(fixtureRoot)));
    expect(encoded, contains('[REDACTED]'));
    expect(encoded, contains('[LOCAL_PATH]/file.txt'));
  });

  test('store reads and clears pending crash report', () async {
    final directory = await Directory.systemTemp.createTemp(
      'intergalactic-pending-crash-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const store = PendingCrashReportStore();
    final report = PendingCrashReport.fromError(
      error: StateError('boom'),
      stackTrace: StackTrace.fromString('main.dart 1:1'),
      source: 'startup',
      content: 'Fatal startup error: boom',
      occurredAt: DateTime.utc(2026, 6, 9, 12),
    );

    await store.record(report, directoryPath: directory.path);

    final loaded = await store.readPending(directoryPath: directory.path);
    expect(loaded, isNotNull);
    expect(loaded!.source, 'startup');
    expect(loaded.summary, contains('Fatal startup error'));

    await store.clearPending(directoryPath: directory.path);
    expect(await store.readPending(directoryPath: directory.path), isNull);
  });

  test(
    'store keeps trusted startup crash marker with reduced summary',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'intergalactic-startup-crash-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      const store = PendingCrashReportStore();
      final report = PendingCrashReport.fromError(
        error: StateError('database open failed'),
        stackTrace: StackTrace.fromString('startup.dart 1:1'),
        source: 'startup',
        content: 'StateError: database open failed',
        occurredAt: DateTime.utc(2026, 6, 25, 12),
      );

      await store.record(report, directoryPath: directory.path);

      final loaded = await store.readPending(directoryPath: directory.path);
      expect(loaded, isNotNull);
      expect(loaded!.source, 'startup');
      expect(loaded.summary, contains('database open failed'));
    },
  );

  test(
    'native call join guard qualifies for next-launch crash prompt',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'intergalactic-native-call-crash-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      const store = PendingCrashReportStore();
      final report = PendingCrashReport.nativeCallJoinGuard(
        source: 'matrix-livekit-native-call-join',
        callKind: 'LiveKit room join',
        occurredAt: DateTime.utc(2026, 6, 18, 15, 11),
      );

      await store.record(report, directoryPath: directory.path);

      final loaded = await store.readPending(directoryPath: directory.path);
      expect(loaded, isNotNull);
      expect(loaded!.summary, startsWith('Native call join crash guard:'));
      expect(loaded.details, contains('LiveKit room join'));
    },
  );

  test(
    'native call action guard qualifies for next-launch crash prompt',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'intergalactic-native-call-action-crash-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      const store = PendingCrashReportStore();
      final report = PendingCrashReport.nativeCallActionGuard(
        source: 'matrix-livekit-native-call-action-screen-share-start',
        actionKind: 'LiveKit screen share start',
        occurredAt: DateTime.utc(2026, 6, 30, 4, 11),
      );

      await store.record(report, directoryPath: directory.path);

      final loaded = await store.readPending(directoryPath: directory.path);
      expect(loaded, isNotNull);
      expect(loaded!.summary, startsWith('Native call action crash guard:'));
      expect(loaded.details, contains('LiveKit screen share start'));
    },
  );

  test('store keeps trusted native call guard with reduced summary', () async {
    final directory = await Directory.systemTemp.createTemp(
      'intergalactic-native-call-source-crash-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const store = PendingCrashReportStore();
    final report = PendingCrashReport(
      occurredAt: DateTime.utc(2026, 6, 25, 12),
      source: 'matrix-livekit-native-call-join',
      summary: 'LiveKit room join',
      details: 'Native setup started but no Dart completion was observed.',
    );

    await store.record(report, directoryPath: directory.path);

    final loaded = await store.readPending(directoryPath: directory.path);
    expect(loaded, isNotNull);
    expect(loaded!.source, 'matrix-livekit-native-call-join');
    expect(loaded.summary, 'LiveKit room join');
  });

  test(
    'store keeps trusted native call action guard with reduced summary',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'intergalactic-native-call-action-source-crash-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      const store = PendingCrashReportStore();
      final report = PendingCrashReport(
        occurredAt: DateTime.utc(2026, 6, 30, 4, 12),
        source: 'matrix-livekit-native-call-action-screen-share-start',
        summary: 'LiveKit screen share start',
        details:
            'Native call action started but no Dart completion was observed.',
      );

      await store.record(report, directoryPath: directory.path);

      final loaded = await store.readPending(directoryPath: directory.path);
      expect(loaded, isNotNull);
      expect(
        loaded!.source,
        'matrix-livekit-native-call-action-screen-share-start',
      );
      expect(loaded.summary, 'LiveKit screen share start');
    },
  );

  test(
    'store clears native call guard without dropping another source',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'intergalactic-native-call-clear-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      const store = PendingCrashReportStore();
      final report = PendingCrashReport.nativeCallJoinGuard(
        source: 'matrix-livekit-native-call-join',
        callKind: 'LiveKit room join',
        occurredAt: DateTime.utc(2026, 6, 18, 15, 11),
      );

      await store.record(report, directoryPath: directory.path);
      await store.clearPendingFromSource(
        'matrix-direct-native-call-start',
        directoryPath: directory.path,
      );
      expect(await store.readPending(directoryPath: directory.path), isNotNull);

      await store.record(report, directoryPath: directory.path);
      await store.clearPendingFromSource(
        'matrix-livekit-native-call-join',
        directoryPath: directory.path,
      );
      expect(await store.readPending(directoryPath: directory.path), isNull);
    },
  );

  test(
    'single marker store cannot preserve start after nested stop marker',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'intergalactic-native-call-nested-action-test-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      const store = PendingCrashReportStore();
      final startReport = PendingCrashReport.nativeCallActionGuard(
        source: 'matrix-direct-native-call-action-screen-share-start',
        actionKind: 'Direct Matrix screen share start',
        occurredAt: DateTime.utc(2026, 7, 1, 16, 10),
      );
      final stopReport = PendingCrashReport.nativeCallActionGuard(
        source: 'matrix-direct-native-call-action-screen-share-stop',
        actionKind: 'Direct Matrix screen share stop',
        occurredAt: DateTime.utc(2026, 7, 1, 16, 11),
      );

      await store.record(startReport, directoryPath: directory.path);
      await store.record(stopReport, directoryPath: directory.path);
      await store.clearPendingFromSource(
        'matrix-direct-native-call-action-screen-share-stop',
        directoryPath: directory.path,
      );

      expect(await store.readPending(directoryPath: directory.path), isNull);
    },
  );

  test('store normalizes explicit directory overrides', () async {
    final directory = await Directory.systemTemp.createTemp(
      'intergalactic-trimmed-crash-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const store = PendingCrashReportStore();
    final report = PendingCrashReport.fromError(
      error: StateError('boom'),
      stackTrace: StackTrace.fromString('main.dart 1:1'),
      source: 'startup',
      content: 'Fatal startup error: boom',
      occurredAt: DateTime.utc(2026, 6, 11, 12),
    );

    await store.record(report, directoryPath: ' ${directory.path} ');
    expect(await store.readPending(directoryPath: directory.path), isNotNull);

    await store.clearPending(directoryPath: directory.path);
    expect(await store.readPending(directoryPath: directory.path), isNull);
    store.recordSync(report, directoryPath: ' ${directory.path} ');
    expect(await store.readPending(directoryPath: directory.path), isNotNull);
  });

  test('store drops unreadable pending crash report', () async {
    final directory = await Directory.systemTemp.createTemp(
      'intergalactic-bad-crash-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'pending-crash-report.json',
    );
    await file.writeAsString('not-json');

    const store = PendingCrashReportStore();
    expect(await store.readPending(directoryPath: directory.path), isNull);
    expect(await file.exists(), isFalse);
  });

  test('store drops legacy nonfatal app-zone pending crash report', () async {
    final directory = await Directory.systemTemp.createTemp(
      'intergalactic-legacy-crash-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    const store = PendingCrashReportStore();
    final legacyReport = PendingCrashReport.fromError(
      error: StateError('Null check operator used on a null value'),
      stackTrace: StackTrace.fromString(
        '#0 MatrixUrlPreviewComponent.getPreview '
        '(matrix_url_preview_component.dart:117)',
      ),
      source: 'run-zoned-guarded',
      content: 'Unhandled app zone error',
      occurredAt: DateTime.utc(2026, 6, 16, 21),
    );

    await store.record(legacyReport, directoryPath: directory.path);

    expect(await store.readPending(directoryPath: directory.path), isNull);
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}'
        'pending-crash-report.json',
      ).exists(),
      isFalse,
    );
  });

  test('main app zone async errors do not qualify as pending crashes', () {
    expect(
      Log.shouldRecordPendingCrashReportForTesting(
        source: 'run-zoned-guarded',
        content: 'Unhandled app zone error',
      ),
      isFalse,
    );
    expect(
      Log.shouldRecordPendingCrashReportForTesting(
        source: 'zone-uncaught-error',
        content: 'Concurrent modification during iteration',
      ),
      isFalse,
    );
  });

  test(
    'trusted fatal/guard sources and explicit headless boundaries qualify as pending crashes',
    () {
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'startup',
          content: 'Fatal startup error',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'startup',
          content: 'StateError: database open failed',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'platform-dispatcher',
          content: 'Unhandled platform dispatcher error',
        ),
        isFalse,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'unified-push',
          content: 'Generic background warning',
        ),
        isFalse,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'unified-push',
          content: 'Unhandled unified push entrypoint error',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'matrix-livekit-native-call-join',
          content: 'LiveKit room join',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'matrix-livekit-native-call-action-screen-share-start',
          content: 'LiveKit screen share start',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'matrix-livekit-native-call-action-microphone-mute',
          content: 'LiveKit microphone mute',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'matrix-livekit-native-call-action-microphone-unmute',
          content: 'LiveKit microphone unmute',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'matrix-livekit-native-call-action-microphone-sender-detach',
          content: 'LiveKit microphone sender detach',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source:
              'matrix-livekit-native-call-action-microphone-sender-reattach',
          content: 'LiveKit microphone sender reattach',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source:
              'matrix-livekit-native-call-action-microphone-ptt-sender-detach',
          content: 'LiveKit Push to Talk microphone sender detach',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source:
              'matrix-livekit-native-call-action-microphone-ptt-sender-reattach',
          content: 'LiveKit Push to Talk microphone sender reattach',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'matrix-direct-native-call-action-microphone-enable',
          content: 'Direct Matrix microphone enable',
        ),
        isTrue,
      );
      expect(
        Log.shouldRecordPendingCrashReportForTesting(
          source: 'bubble',
          content: 'Unhandled bubble entrypoint error',
        ),
        isTrue,
      );
    },
  );
}

const _windowsFixtureDrive = 'C:';

String get _windowsFixtureRoot =>
    '$_windowsFixtureDrive${r'\redaction-fixtures'}';
