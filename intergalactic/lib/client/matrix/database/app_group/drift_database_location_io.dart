import 'dart:io';

import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_app_group_migration.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

/// iOS-only resolution of the account database root; a no-op elsewhere.
///
/// [prepare] runs the App Group migration and, when the App Group path is
/// authoritative for this launch, publishes it through [appGroupDriftRoot].
/// It runs before any client opens a database and is the only writer of that
/// root. If it has not run, or declined, the root is null and
/// `AppConfig.getDriftDatabasePath` falls back to the app-private path - the
/// same answer as before Phase B, byte for byte.
class DriftDatabaseLocation {
  DriftDatabaseLocation._();

  static const String _source = 'drift-app-group';

  static String? _appGroupDriftRoot;
  static DriftAppGroupMigration? _migration;

  /// `<App Group>/db/account/drift` when authoritative, else null.
  static String? get appGroupDriftRoot => _appGroupDriftRoot;

  /// Test-only: stand in for a completed [prepare] so the path resolution in
  /// `AppConfig.getDriftDatabasePath` can be exercised without a container.
  @visibleForTesting
  static void debugSetAppGroupDriftRoot(String? root) {
    _appGroupDriftRoot = root;
    if (root == null) {
      _migration = null;
    }
  }

  /// Resolves the location for this launch. iOS only; every other platform
  /// returns immediately. A dev-profile override wins outright (REVIEW R6):
  /// with `INTERGALACTIC_DEV_PROFILE_DIR` set nothing moves and the root stays
  /// null, so the override keeps isolating exactly as it did before.
  ///
  /// [host] is replaceable for tests; [platformIsIOS] likewise.
  static Future<void> prepare({
    AppGroupStorageHost? host,
    bool? platformIsIOS,
  }) async {
    if (!(platformIsIOS ?? PlatformUtils.isIOS)) {
      return;
    }
    if (await AppConfig.hasDevProfileOverride()) {
      Log.i(
        'App Group migration skipped: dev profile override active',
        category: LogCategory.app,
        source: _source,
      );
      return;
    }

    final storage = host ?? const ChannelAppGroupStorageHost();
    String? container;
    try {
      container = await storage.containerPath();
    } catch (error) {
      Log.e(
        'App Group container lookup failed: ${error.runtimeType}',
        category: LogCategory.app,
        source: _source,
      );
    }
    if (container == null || container.isEmpty) {
      Log.e(
        'App Group container unavailable; app-private path remains '
        'authoritative',
        category: LogCategory.app,
        source: _source,
      );
      return;
    }

    final sourceRoot = p.join(
      await AppConfig.getDatabasePath(),
      'account',
      'drift',
    );
    final migration = DriftAppGroupMigration(
      sourceRoot: sourceRoot,
      appGroupDatabaseRoot: p.join(container, 'db'),
      host: storage,
      registeredClientCount: _registeredClientCount(),
    );

    // The container lookup above is guarded and this call was not, though it
    // can throw just as easily: _writeStage does create/write/rename and
    // _reportQuarantine lists a directory, neither inside a handler. An escape
    // here fails startup before any client loads - on the exact iOS path this
    // migration exists to make safe - so the failure has to degrade to the
    // app-private path rather than take the launch down with it.
    final DriftMigrationOutcome outcome;
    try {
      outcome = await migration.prepare();
    } catch (error, stackTrace) {
      // onError rather than Log.e alone: this is the one path here whose
      // cause is not already named by the message, so the stack is the only
      // way to tell _writeStage from _reportQuarantine after the fact.
      Log.onError(
        error,
        stackTrace,
        content:
            'App Group migration threw; app-private path remains authoritative',
      );
      _appGroupDriftRoot = null;
      _migration = null;
      return;
    }
    if (outcome.appGroupAuthoritative) {
      _appGroupDriftRoot = migration.destinationRoot;
      _migration = migration;
    } else {
      _appGroupDriftRoot = null;
      _migration = null;
    }
    Log.i(
      'Account database location resolved: ${outcome.reason}',
      category: LogCategory.app,
      source: _source,
    );
  }

  /// B3: call once `ClientManager.init` has loaded clients from the resolved
  /// location. No-op unless a migration is live for this launch.
  static Future<void> confirmLaunchRead() async {
    final migration = _migration;
    if (migration == null) {
      return;
    }
    await migration.confirmLaunchRead();
  }

  /// Integration-test isolation: removes the App Group account tree and the
  /// migration marker so `clearUserData()` keeps clearing the account database
  /// on iOS (REVIEW R5). Never called on a user's device.
  static Future<void> resetAppGroupStorage() async {
    final migration = _migration;
    if (migration == null) {
      return;
    }
    final root = Directory(migration.destinationRoot);
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    final marker = File(migration.markerPath);
    if (await marker.exists()) {
      await marker.delete();
    }
    final quarantine = Directory(migration.quarantineRoot);
    if (await quarantine.exists()) {
      await quarantine.delete(recursive: true);
    }
    _appGroupDriftRoot = null;
    _migration = null;
  }

  static int? _registeredClientCount() {
    try {
      return (preferences.getRegisteredMatrixClients() ?? const <String>[])
          .length;
    } catch (_) {
      // Preferences not initialised in this process: the cross-check is
      // optional and the migration must not depend on it.
      return null;
    }
  }
}
