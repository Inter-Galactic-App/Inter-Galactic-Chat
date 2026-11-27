import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_app_group_migration.dart';
import 'package:path/path.dart' as p;

/// NSE Phase B migration.
///
/// WHAT WOULD MAKE THESE WRONG, stated before running them: a fake host that
/// always reports the expected class would let the "aborts without
/// protection" cases pass for the wrong reason, so the fake is scriptable per
/// path and the abort tests assert on what is on DISK afterwards, not on the
/// outcome value alone. And every "moved" assertion checks BOTH sides - the
/// file at the destination AND its absence at the source - because a copy
/// that forgot to delete would satisfy a one-sided check.
void main() {
  late Directory tempDir;
  late String appPrivateDb;
  late String appGroupRoot;
  late _FakeHost host;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-app-group-migration');
    appPrivateDb = p.join(tempDir.path, 'private', 'db');
    appGroupRoot = p.join(tempDir.path, 'group');
    host = _FakeHost(containerRoot: appGroupRoot);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String sourceRoot() => p.join(appPrivateDb, 'account', 'drift');

  DriftAppGroupMigration migration({int? registered}) => DriftAppGroupMigration(
    sourceRoot: sourceRoot(),
    appGroupDatabaseRoot: p.join(appGroupRoot, 'db'),
    host: host,
    registeredClientCount: registered,
  );

  void seedAccount(String name, {bool journal = false, String content = 'db'}) {
    final dir = Directory(p.join(sourceRoot(), name))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'data.db')).writeAsStringSync('$content:$name');
    if (journal) {
      File(
        p.join(dir.path, 'data.db-journal'),
      ).writeAsStringSync('journal:$name');
    }
  }

  void seedEmptyAccount(String name) {
    Directory(p.join(sourceRoot(), name)).createSync(recursive: true);
  }

  Future<DriftMigrationStage?> stage() => migration().readStage();

  String destination(String name, [String file = 'data.db']) =>
      p.join(appGroupRoot, 'db', 'account', 'drift', name, file);

  group('fresh install', () {
    test(
      'creates a protected destination and completes with nothing to move',
      () async {
        final outcome = await migration().prepare();

        expect(outcome.appGroupAuthoritative, isTrue);
        expect(await stage(), DriftMigrationStage.complete);
        final drift = p.join(appGroupRoot, 'db', 'account', 'drift');
        expect(Directory(drift).existsSync(), isTrue);
        expect(
          host.protected,
          containsAll([p.join(appGroupRoot, 'db'), drift]),
        );
        expect(Directory(sourceRoot()).existsSync(), isFalse);
      },
    );
  });

  group('protection (B1)', () {
    test(
      'aborts before moving anything when the class cannot be set',
      () async {
        seedAccount('alice', journal: true);
        host.failFor = (path) => path == p.join(appGroupRoot, 'db');

        final outcome = await migration().prepare();

        expect(outcome.appGroupAuthoritative, isFalse);
        expect(outcome.reason, 'protection_unavailable');
        // On disk: nothing moved, no marker, the source untouched.
        expect(await stage(), isNull);
        expect(
          File(p.join(sourceRoot(), 'alice', 'data.db')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(sourceRoot(), 'alice', 'data.db-journal')).existsSync(),
          isTrue,
        );
        expect(File(destination('alice')).existsSync(), isFalse);
      },
    );

    test('a read-back that reports a different class is a failure', () async {
      seedAccount('alice');
      host.reportFor = (path) => 'NSFileProtectionComplete';

      final outcome = await migration().prepare();

      expect(outcome.appGroupAuthoritative, isFalse);
      expect(
        File(p.join(sourceRoot(), 'alice', 'data.db')).existsSync(),
        isTrue,
      );
    });

    test(
      'a later launch that cannot re-assert stays on the App Group',
      () async {
        seedAccount('alice');
        await migration().prepare();
        expect(await stage(), DriftMigrationStage.moved);

        host.failFor = (path) => true;
        final outcome = await migration().prepare();

        expect(outcome.appGroupAuthoritative, isTrue);
        expect(File(destination('alice')).existsSync(), isTrue);
      },
    );

    test(
      're-asserts on every file and directory under the destination',
      () async {
        seedAccount('alice', journal: true);
        seedAccount('bob');
        await migration().prepare();

        host.protected.clear();
        await migration().prepare();

        expect(
          host.protected,
          containsAll([
            p.join(appGroupRoot, 'db', 'account', 'drift'),
            p.join(appGroupRoot, 'db', 'account', 'drift', 'alice'),
            destination('alice'),
            destination('alice', 'data.db-journal'),
            p.join(appGroupRoot, 'db', 'account', 'drift', 'bob'),
            destination('bob'),
          ]),
        );
      },
    );

    test('directories are protected before files land in them', () async {
      seedAccount('alice');
      await migration().prepare();

      final dirIndex = host.protected.indexOf(
        p.join(appGroupRoot, 'db', 'account', 'drift', 'alice'),
      );
      final fileIndex = host.protected.indexOf(destination('alice'));
      expect(dirIndex, isNonNegative);
      expect(fileIndex, greaterThan(dirIndex));
    });
  });

  group('moving', () {
    test('moves the database and its journal for one account', () async {
      seedAccount('alice', journal: true);

      final outcome = await migration().prepare();

      expect(outcome.appGroupAuthoritative, isTrue);
      expect(await stage(), DriftMigrationStage.moved);
      expect(File(destination('alice')).readAsStringSync(), 'db:alice');
      expect(
        File(destination('alice', 'data.db-journal')).readAsStringSync(),
        'journal:alice',
      );
      expect(
        File(p.join(sourceRoot(), 'alice', 'data.db')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(sourceRoot(), 'alice', 'data.db-journal')).existsSync(),
        isFalse,
      );
      // B3: the source tree survives this launch.
      expect(Directory(sourceRoot()).existsSync(), isTrue);
    });

    test('moves every account with data and skips empty directories', () async {
      seedAccount('alice');
      seedAccount('bob', journal: true);
      seedAccount('carol');
      for (var i = 0; i < 7; i++) {
        seedEmptyAccount('empty-$i');
      }

      await migration(registered: 3).prepare();

      final moved =
          Directory(p.join(appGroupRoot, 'db', 'account', 'drift'))
              .listSync()
              .whereType<Directory>()
              .map((d) => p.basename(d.path))
              .toList()
            ..sort();
      expect(moved, ['alice', 'bob', 'carol']);
      for (final name in ['alice', 'bob', 'carol']) {
        expect(File(destination(name)).existsSync(), isTrue);
        expect(
          File(p.join(sourceRoot(), name, 'data.db')).existsSync(),
          isFalse,
        );
      }
    });

    test('resumes an interrupted move from the migrating stage', () async {
      seedAccount('alice');
      seedAccount('bob');
      // Simulate: marker written, alice moved, process died before bob.
      final marker = File(
        p.join(
          appGroupRoot,
          'db',
          'account',
          '.drift-app-group-migration.json',
        ),
      )..createSync(recursive: true);
      marker.writeAsStringSync(
        jsonEncode({'version': 1, 'stage': 'migrating'}),
      );
      Directory(p.dirname(destination('alice'))).createSync(recursive: true);
      File(
        p.join(sourceRoot(), 'alice', 'data.db'),
      ).renameSync(destination('alice'));

      await migration().prepare();

      expect(await stage(), DriftMigrationStage.moved);
      expect(File(destination('alice')).readAsStringSync(), 'db:alice');
      expect(File(destination('bob')).readAsStringSync(), 'db:bob');
      expect(
        File(p.join(sourceRoot(), 'bob', 'data.db')).existsSync(),
        isFalse,
      );
    });

    test('resumes when the journal moved but the database did not', () async {
      // The state journal-first leaves behind if interrupted between the two.
      seedAccount('alice', journal: true);
      final marker = File(
        p.join(
          appGroupRoot,
          'db',
          'account',
          '.drift-app-group-migration.json',
        ),
      )..createSync(recursive: true);
      marker.writeAsStringSync(
        jsonEncode({'version': 1, 'stage': 'migrating'}),
      );
      Directory(p.dirname(destination('alice'))).createSync(recursive: true);
      File(
        p.join(sourceRoot(), 'alice', 'data.db-journal'),
      ).renameSync(destination('alice', 'data.db-journal'));

      await migration().prepare();

      expect(await stage(), DriftMigrationStage.moved);
      expect(File(destination('alice')).readAsStringSync(), 'db:alice');
      expect(
        File(destination('alice', 'data.db-journal')).readAsStringSync(),
        'journal:alice',
      );
    });

    test(
      'quarantines a source whose destination already holds a database',
      () async {
        seedAccount('alice', content: 'old');
        Directory(p.dirname(destination('alice'))).createSync(recursive: true);
        File(destination('alice')).writeAsStringSync('db-at-destination');

        await migration().prepare();

        expect(await stage(), DriftMigrationStage.moved);
        // Destination wins, untouched.
        expect(
          File(destination('alice')).readAsStringSync(),
          'db-at-destination',
        );
        // Source is neither overwritten nor discarded.
        final quarantined = File(
          p.join(
            appPrivateDb,
            'account',
            'drift-quarantine',
            'alice',
            'data.db',
          ),
        );
        expect(quarantined.readAsStringSync(), 'old:alice');
        expect(Directory(p.join(sourceRoot(), 'alice')).existsSync(), isFalse);
      },
    );

    test(
      'a failed account leaves the stage at migrating for the next launch',
      () async {
        seedAccount('alice');
        seedAccount('bob');
        host.failFor = (path) => path == destination('bob');

        final interrupted = await migration().prepare();

        // The stage alone was all this test used to check, and the stage was
        // already right. What was wrong is the OUTCOME: prepare() returned
        // appGroup regardless, so the caller pointed the app at a destination
        // that does not hold bob's database. See the dedicated test below for
        // what that costs.
        expect(
          interrupted.appGroupAuthoritative,
          isFalse,
          reason:
              'bob did not move, so the App Group path does not hold every '
              'account and cannot be authoritative for this launch',
        );
        expect(await stage(), DriftMigrationStage.migrating);
        expect(File(destination('alice')).existsSync(), isTrue);

        host.failFor = null;
        final resumed = await migration().prepare();

        expect(resumed.appGroupAuthoritative, isTrue);
        expect(await stage(), DriftMigrationStage.moved);
        expect(File(destination('bob')).existsSync(), isTrue);
      },
    );

    test(
      'a partly-migrated launch does not strand the account that failed',
      () async {
        // The whole chain this guards, which needs three steps to be visible:
        //
        //  1. _moveAccount creates the destination directory BEFORE moving any
        //     file, so a failure leaves bob with a destination directory and
        //     no data.db.
        //  2. If the app is then pointed at that destination, drift opens
        //     `data.db` there and CREATES it - empty. bob looks logged out.
        //  3. On the next launch data.db exists at BOTH ends, so _moveAccount
        //     takes the collision branch and renames bob's real database into
        //     drift-quarantine, keeping the empty one. Nothing puts it back.
        //
        // Step 2 is the only one under this class's control, and refusing to
        // report the path authoritative is what removes it.
        seedAccount('alice');
        seedAccount('bob');
        // Fails on bob's destination DIRECTORY, which _moveAccount protects
        // after creating it and before the file loop runs. The sibling test
        // above fails on the data.db path instead, and that fires AFTER
        // _moveFile has already succeeded - a real failure, but not this one.
        // Only a failure before the loop leaves the directory without the
        // database, which is step 1 of the chain.
        host.failFor = (path) => path == p.dirname(destination('bob'));

        final outcome = await migration().prepare();

        expect(outcome.appGroupAuthoritative, isFalse);
        expect(
          outcome.reason,
          'move_incomplete',
          reason: 'the log must distinguish this from an unavailable container',
        );
        // Step 1, confirmed: the directory is there and the database is not.
        expect(
          Directory(p.dirname(destination('bob'))).existsSync(),
          isTrue,
          reason: 'the empty destination directory is what step 2 opens into',
        );
        expect(File(destination('bob')).existsSync(), isFalse);
        // bob's real database is still where the app will look for it.
        expect(
          File(p.join(sourceRoot(), 'bob', 'data.db')).readAsStringSync(),
          'db:bob',
        );
      },
    );
  });

  group('source deletion (B3)', () {
    test('deletes the source on the launch after the confirming one', () async {
      seedAccount('alice');
      seedEmptyAccount('stale');

      // Launch 1: move.
      await migration().prepare();
      expect(await stage(), DriftMigrationStage.moved);
      expect(Directory(sourceRoot()).existsSync(), isTrue);

      // Launch 2: nothing at prepare; a client is read; confirmed.
      await migration().prepare();
      expect(await stage(), DriftMigrationStage.moved);
      await migration().confirmLaunchRead();
      expect(await stage(), DriftMigrationStage.confirmed);
      expect(Directory(sourceRoot()).existsSync(), isTrue);

      // Launch 3: the source goes, and its absence is verified.
      await migration().prepare();
      expect(await stage(), DriftMigrationStage.complete);
      expect(Directory(sourceRoot()).existsSync(), isFalse);
      expect(File(destination('alice')).readAsStringSync(), 'db:alice');
    });

    test('confirmLaunchRead is a no-op outside the moved stage', () async {
      await migration().prepare(); // fresh -> complete
      await migration().confirmLaunchRead();
      expect(await stage(), DriftMigrationStage.complete);
    });

    test('quarantine survives source deletion', () async {
      seedAccount('alice');
      Directory(p.dirname(destination('alice'))).createSync(recursive: true);
      File(destination('alice')).writeAsStringSync('db-at-destination');

      await migration().prepare();
      await migration().confirmLaunchRead();
      await migration().prepare();

      expect(await stage(), DriftMigrationStage.complete);
      expect(
        File(
          p.join(
            appPrivateDb,
            'account',
            'drift-quarantine',
            'alice',
            'data.db',
          ),
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('marker (B4)', () {
    test('carries only a version and a stage', () async {
      seedAccount('alice-very-identifying-name');
      await migration().prepare();

      final text = File(
        p.join(
          appGroupRoot,
          'db',
          'account',
          '.drift-app-group-migration.json',
        ),
      ).readAsStringSync();
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {'version', 'stage'});
      expect(text, isNot(contains('alice')));
      expect(text, isNot(contains(tempDir.path)));
    });

    test('an unreadable marker reads as no migration', () async {
      final marker = File(
        p.join(
          appGroupRoot,
          'db',
          'account',
          '.drift-app-group-migration.json',
        ),
      )..createSync(recursive: true);
      marker.writeAsStringSync('{not json');
      expect(await stage(), isNull);
    });
  });
}

class _FakeHost implements AppGroupStorageHost {
  _FakeHost({required this.containerRoot});

  final String containerRoot;

  /// Every path handed to [protectItem], in call order.
  final List<String> protected = [];

  /// Paths for which [protectItem] throws.
  bool Function(String path)? failFor;

  /// Overrides what read-back reports for a path.
  String? Function(String path)? reportFor;

  @override
  Future<String?> containerPath() async => containerRoot;

  @override
  Future<String?> protectItem(String path) async {
    if (failFor?.call(path) ?? false) {
      throw StateError('protect failed');
    }
    protected.add(path);
    return reportFor?.call(path) ?? AppGroupStorageHost.expectedProtectionClass;
  }

  @override
  Future<String?> readProtectionClass(String path) async =>
      AppGroupStorageHost.expectedProtectionClass;

  @override
  Future<bool> excludeFromBackup(String path) async => true;
}
