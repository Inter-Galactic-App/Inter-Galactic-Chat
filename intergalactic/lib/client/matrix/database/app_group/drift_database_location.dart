/// Where the Matrix account databases live on this platform.
///
/// On iOS, once the App Group migration has run, that is the shared container
/// (NSE Phase B). Everywhere else it is the app-private path it has always
/// been, and this resolves to "nothing to add". `AppConfig.getDriftDatabasePath`
/// consults [DriftDatabaseLocation.appGroupDriftRoot]; startup calls
/// [DriftDatabaseLocation.prepare] before any client opens a database.
export 'drift_database_location_stub.dart'
    if (dart.library.io) 'drift_database_location_io.dart';
