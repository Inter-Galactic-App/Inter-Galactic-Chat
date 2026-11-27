import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/ios/nse_backup_version_io.dart';
import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late _FakeHost host;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-backup-version');
    host = _FakeHost();
    NseBackupVersion.host = host;
    NseBackupVersion.platformIsIOS = true;
  });

  tearDown(() {
    NseBackupVersion.resetForTests();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('keeps only bounded E2 versions and client identifiers', () {
    final document = NseBackupVersion.build([
      const NseBackupVersionEntry(clientId: 'client-a', version: 'v_1.2-3'),
      const NseBackupVersionEntry(clientId: 'client-b', version: 'bad/value'),
      const NseBackupVersionEntry(clientId: '', version: 'v2'),
    ]);

    expect(document, {
      'version': NseBackupVersion.documentVersion,
      'versions': {'client-a': 'v_1.2-3'},
    });
  });

  test(
    'writes atomically, protects, and excludes the document from backup',
    () async {
      final directory = p.join(tempDir.path, 'nse-key-backup');
      await NseBackupVersion.writeEntries(const [
        NseBackupVersionEntry(clientId: 'client-a', version: 'v1'),
      ], directory: directory);

      final path = p.join(directory, NseBackupVersion.fileName);
      expect(jsonDecode(await File(path).readAsString()), {
        'version': NseBackupVersion.documentVersion,
        'versions': {'client-a': 'v1'},
      });
      expect(host.protected, containsAll([directory, path]));
      expect(host.excluded, [path]);
      expect(File('$path.tmp').existsSync(), isFalse);
    },
  );

  test('removes a prior document when there is no usable version', () async {
    final directory = p.join(tempDir.path, 'nse-key-backup');
    final path = p.join(directory, NseBackupVersion.fileName);
    await Directory(directory).create(recursive: true);
    await File(path).writeAsString('{}');

    await NseBackupVersion.writeEntries(const [
      NseBackupVersionEntry(clientId: 'client-a', version: 'bad/value'),
    ], directory: directory);

    expect(File(path).existsSync(), isFalse);
  });

  test('reprotects an existing handoff directory before writing', () async {
    final directory = p.join(tempDir.path, 'nse-key-backup');
    await Directory(directory).create(recursive: true);

    await NseBackupVersion.writeEntries(const [
      NseBackupVersionEntry(clientId: 'client-a', version: 'v1'),
    ], directory: directory);

    expect(host.protected, contains(directory));
    expect(host.protected.first, directory);
  });
}

class _FakeHost implements AppGroupStorageHost {
  final List<String> protected = [];
  final List<String> excluded = [];

  @override
  Future<String?> containerPath() async => null;

  @override
  Future<bool> excludeFromBackup(String path) async {
    excluded.add(path);
    return true;
  }

  @override
  Future<String?> protectItem(String path) async {
    protected.add(path);
    return AppGroupStorageHost.expectedProtectionClass;
  }

  @override
  Future<String?> readProtectionClass(String path) async =>
      AppGroupStorageHost.expectedProtectionClass;
}
