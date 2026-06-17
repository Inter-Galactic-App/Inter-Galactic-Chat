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
      source: 'platform-dispatcher',
      content: 'Unhandled platform dispatcher error: boom',
      occurredAt: DateTime.utc(2026, 6, 9, 12),
    );

    await store.record(report, directoryPath: directory.path);

    final loaded = await store.readPending(directoryPath: directory.path);
    expect(loaded, isNotNull);
    expect(loaded!.source, 'platform-dispatcher');
    expect(loaded.summary, contains('Unhandled platform dispatcher error'));

    await store.clearPending(directoryPath: directory.path);
    expect(await store.readPending(directoryPath: directory.path), isNull);
  });

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
      source: 'run-zoned-guarded',
      content: 'Unhandled app zone error: boom',
      occurredAt: DateTime.utc(2026, 6, 11, 12),
    );

    await store.record(report, directoryPath: ' ${directory.path} ');
    expect(
      await store.readPending(directoryPath: directory.path),
      isNotNull,
    );

    await store.clearPending(directoryPath: directory.path);
    expect(
      await store.readPending(directoryPath: directory.path),
      isNull,
    );
    store.recordSync(report, directoryPath: ' ${directory.path} ');
    expect(
      await store.readPending(directoryPath: directory.path),
      isNotNull,
    );
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

    final file = File('${directory.path}${Platform.pathSeparator}'
        'pending-crash-report.json');
    await file.writeAsString('not-json');

    const store = PendingCrashReportStore();
    expect(await store.readPending(directoryPath: directory.path), isNull);
    expect(await file.exists(), isFalse);
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

  test('only explicit fatal and headless boundaries qualify as pending crashes',
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
        source: 'bubble',
        content: 'Unhandled bubble entrypoint error',
      ),
      isTrue,
    );
  });
}

const _windowsFixtureDrive = 'C:';

String get _windowsFixtureRoot =>
    '$_windowsFixtureDrive${r'\redaction-fixtures'}';
