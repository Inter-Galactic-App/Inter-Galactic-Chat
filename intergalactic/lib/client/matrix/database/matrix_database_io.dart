import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:intergalactic/config/app_config.dart';
import 'package:intergalactic/diagnostic/diagnostics.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:path/path.dart' as p;

Future<DatabaseApi> getMatrixDatabaseImplementation(String clientName) async {
  var path = await AppConfig.getDriftDatabasePath();
  path = p.join(path, clientName, "data.db");
  var dir = p.dirname(path);

  if (!await Directory(dir).exists()) {
    await Directory(dir).create(recursive: true);
  }

  final file = File(path);

  // The SDK holds this one connection object for the life of the client and
  // never learns that the server behind it is released before suspension and
  // rebuilt on resume (B5). The wrapper registers itself for the lifecycle
  // trigger's sweep. A fresh DatabaseConnection rather than the isolate's own:
  // the stream-query store the isolate hands out is bound to the executor
  // being swapped, and the Matrix database uses no drift watch streams.
  final connection = await ReleasableConnection.open(file.absolute.path);

  return MatrixSdkDriftDatabase.init(
    DatabaseConnection(connection),
    clientName,
    benchmark: benchmarkFunc,
  );
}

Future<T> benchmarkFunc<T>(
  String name,
  Future<T> Function() func, [
  int? itemCount,
]) {
  return Diagnostics.databaseDiagnostics.timeAsync(name, func);
}

Future<DatabaseApi?> getLegacyMatrixDatabaseImplementation(
  String clientName,
) async {
  return null;
}
