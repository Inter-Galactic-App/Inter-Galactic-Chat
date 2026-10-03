import 'package:drift/drift.dart';
import 'package:intergalactic/utils/database/database_platform_types.dart';

/// Web has no drift isolate server and no releasable database.
///
/// GUARDED BY CI. `.forgejo/workflows/forgejo-ci.yml` compiles for the web
/// whenever a file under `intergalactic/lib` changes, which is what stops this
/// seam being quietly undone the way the original import was. Do not remove
/// that step and this file together.
///
/// WHY THIS FILE EXISTS AT ALL. Web reaches `ReleasableConnection` only through
/// two static reads - `ReleasableConnection.live`, which is empty because
/// nothing ever calls `open`, and `staleTransactionUses` - both pulled in by
/// `main.dart` and `database_release_trigger.dart`. It never opens, releases or
/// re-establishes anything: `matrix_database.dart` selects
/// `matrix_database_html.dart` on web, which does not use this class.
///
/// Without this seam the whole chain reached dart2js -
/// `main.dart` → `releasable_connection.dart` → `multiple_database_server.dart`
/// → `package:drift/native.dart` → the sqlite3 FFI bindings - and the web build
/// failed with "Only JS interop members may be 'external'". It failed that way
/// from 2026-08-14 until this fix, unnoticed because the Web job is skipped on
/// draft pull requests.
///
/// These throw rather than return a plausible value. A silent no-op here would
/// mean a future web caller gets `established` from a database that was never
/// opened, which is the failure mode `RE-2` in `releasable_connection.dart`
/// exists to prevent. If web ever does need a releasable database, that is a
/// real implementation, not a relaxation of these.
Never _unsupported(String what) {
  throw UnsupportedError(
    '$what is not available on web: there is no drift isolate server here. '
    'Web uses matrix_database_html.dart, which does not release databases.',
  );
}

Future<DatabaseConnection> platformConnectDatabase(String databaseName) async =>
    _unsupported('platformConnectDatabase');

Future<bool> platformReleaseDatabase(String databaseName) async =>
    _unsupported('platformReleaseDatabase');

ReestablishResult platformProbeDatabaseReadable(String databaseName) =>
    _unsupported('platformProbeDatabaseReadable');
