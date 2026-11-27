import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/debug/diagnostic_log_store.dart';
import 'package:path/path.dart' as path;

void main() {
  test('writes and reads recent diagnostic log text', () async {
    final temp = await Directory.systemTemp.createTemp('ig_logs_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final store = DiagnosticLogStore();
    await store.initialize(directoryPath: temp.path);
    await store.append('warning line\n', flush: true);

    final recent = await store.recentText();
    expect(recent, contains('warning line'));
  });

  test('rotates logs and keeps only the configured log files', () async {
    final temp = await Directory.systemTemp.createTemp('ig_logs_rotate_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final store = DiagnosticLogStore();
    await store.initialize(
      directoryPath: temp.path,
      maxFileBytes: 120,
      maxFiles: 3,
      maxTotalBytes: 1024,
    );

    final payload = List.filled(80, 'x').join();
    for (var i = 0; i < 12; i++) {
      await store.append('line-$i $payload\n', flush: true);
    }

    final logFiles = temp
        .listSync()
        .whereType<File>()
        .where((file) => path.basename(file.path).startsWith('intergalactic-'))
        .toList();

    expect(logFiles.length, lessThanOrEqualTo(3));
    expect(await store.recentText(), contains('line-11'));
  });

  test('clear removes only diagnostic log files', () async {
    final temp = await Directory.systemTemp.createTemp('ig_logs_clear_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final sentinel = File(path.join(temp.path, 'keep.txt'));
    await sentinel.writeAsString('do not delete');

    final store = DiagnosticLogStore();
    await store.initialize(directoryPath: temp.path);
    await store.append('clear me\n', flush: true);
    await store.clear();

    expect(await sentinel.exists(), isTrue);
    final remainingLogs = temp
        .listSync()
        .whereType<File>()
        .where((file) => path.basename(file.path).startsWith('intergalactic-'));
    expect(remainingLogs, isEmpty);
  });
}
