/// The seam that keeps the sqlite3 FFI bindings out of the web build.
///
/// Same shape as the `database_server.dart` seam next to it. Everything
/// platform-specific that `releasable_connection.dart` needs goes through here:
/// the drift isolate server, and the `dart:io` file probe. `drift/drift.dart`
/// itself is platform-agnostic, so only `drift/native.dart` - reached via
/// `multiple_database_server.dart` - had to be hidden.
library;

export 'database_platform_stub.dart'
    if (dart.library.io) 'database_platform_io.dart';
export 'database_platform_types.dart';
