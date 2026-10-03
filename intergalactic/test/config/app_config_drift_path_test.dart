import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_database_location.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:path/path.dart' as p;

/// REVIEW R6 on NSE Phase B.
///
/// The dev-profile override (`INTERGALACTIC_DEV_PROFILE_DIR`) used to reach
/// `getDriftDatabasePath()` only by delegation through `getDatabasePath()`.
/// The iOS App Group branch does not go through `getDatabasePath()`, so the
/// override has to be re-consulted inside `getDriftDatabasePath()` itself, or
/// a redirected profile silently stops isolating on iOS.
///
/// WHAT WOULD MAKE THESE WRONG: a test that only checks the override with the
/// App Group root UNSET passes on the old code too, because delegation still
/// wins there. Every override case below sets the App Group root first, so
/// the assertion is specifically that the override beats it. Deleting the
/// override check inside the iOS branch turns them red.
void main() {
  late Directory tempDir;
  String? override;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-drift-path');
    override = null;
    AppConfig.environmentVariable = (name) =>
        name == 'INTERGALACTIC_DEV_PROFILE_DIR' ? override : null;
  });

  tearDown(() {
    AppConfig.environmentVariable = PlatformUtils.environmentVariable;
    DriftDatabaseLocation.debugSetAppGroupDriftRoot(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('dev-profile override (R6)', () {
    test('wins over an authoritative App Group root', () async {
      override = tempDir.path;
      DriftDatabaseLocation.debugSetAppGroupDriftRoot(
        p.join(tempDir.path, 'group', 'db', 'account', 'drift'),
      );

      final path = await AppConfig.getDriftDatabasePath();

      expect(path, p.join(tempDir.path, 'db', 'account', 'drift'));
    });

    test('resolves byte-identically to the previous delegation', () async {
      override = tempDir.path;
      DriftDatabaseLocation.debugSetAppGroupDriftRoot(
        p.join(tempDir.path, 'group', 'db', 'account', 'drift'),
      );

      final direct = await AppConfig.getDriftDatabasePath();
      final delegated = p.join(
        await AppConfig.getDatabasePath(),
        'account',
        'drift',
      );

      expect(direct, delegated);
    });

    test('prepare() does nothing at all under the override', () async {
      override = tempDir.path;
      final host = _RecordingHost();

      await DriftDatabaseLocation.prepare(host: host, platformIsIOS: true);

      expect(host.calls, isEmpty);
      expect(DriftDatabaseLocation.appGroupDriftRoot, isNull);
    });
  });

  group('App Group root', () {
    test('is used when set and no override is active', () async {
      final root = p.join(tempDir.path, 'group', 'db', 'account', 'drift');
      DriftDatabaseLocation.debugSetAppGroupDriftRoot(root);

      expect(await AppConfig.getDriftDatabasePath(), root);
    });

    test('is null until prepare() has made it authoritative', () {
      expect(DriftDatabaseLocation.appGroupDriftRoot, isNull);
    });
  });
}

class _RecordingHost implements AppGroupStorageHost {
  final List<String> calls = [];

  @override
  Future<String?> containerPath() async {
    calls.add('containerPath');
    return null;
  }

  @override
  Future<String?> protectItem(String path) async {
    calls.add('protectItem');
    return AppGroupStorageHost.expectedProtectionClass;
  }

  @override
  Future<String?> readProtectionClass(String path) async {
    calls.add('readProtectionClass');
    return null;
  }

  @override
  Future<bool> excludeFromBackup(String path) async => true;
}
