import 'dart:io';

import 'package:drift/drift.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/database/database_platform_types.dart';
import 'package:intergalactic/utils/database/multiple_database_server.dart';

/// Opens a drift server connection for [databaseName], tracked for release.
Future<DatabaseConnection> platformConnectDatabase(String databaseName) {
  return DatabaseIsolate.connect(databaseName, trackForRelease: true);
}

/// Shuts the drift server for [databaseName] down. True when it is no longer
/// held, including when it was never open.
Future<bool> platformReleaseDatabase(String databaseName) {
  return DatabaseIsolate.release(databaseName);
}

/// Distinguishes "cannot read it yet" from "cannot read it at all", app-side.
///
/// Under the App Group migration the file carries
/// `completeUntilFirstUserAuthentication`, so before first unlock the open
/// fails with a permission error and that is a NORMAL state to retry, not a
/// fault. A missing file is not deferred - a database that does not exist yet
/// is created on open.
///
/// The exact errno for protected-data-unavailable on iOS is covered by the
/// batched device check ("can an extension write a
/// completeUntilFirstUserAuthentication file while locked"); EPERM and EACCES
/// are treated as deferred until that answers, which fails in the safe
/// direction — a deferred retry, rather than a permanent failure.
ReestablishResult platformProbeDatabaseReadable(String databaseName) {
  final file = File(databaseName);
  try {
    if (!file.existsSync()) {
      return ReestablishResult.established;
    }
    file.openSync(mode: FileMode.read).closeSync();
    return ReestablishResult.established;
  } on FileSystemException catch (error) {
    const eperm = 1;
    const eacces = 13;
    final code = error.osError?.errorCode;
    if (code == eperm || code == eacces) {
      Log.i(
        "Database re-establish deferred; protected data unavailable "
        "(errno $code)",
        category: LogCategory.app,
        source: 'database-release',
      );
      return ReestablishResult.deferred;
    }
    Log.w("Database re-establish probe failed (errno ${code ?? 'unknown'})");
    return ReestablishResult.failed;
  }
}
