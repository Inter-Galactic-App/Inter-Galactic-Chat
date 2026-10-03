import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';

/// Web: there is no filesystem and no App Group. Every call is a no-op and the
/// root is never set, so `getDriftDatabasePath` keeps its web answer.
///
/// Signatures mirror the io implementation exactly: the analyzer resolves the
/// conditional export to this file, so a parameter missing here is an
/// analysis error at every call site even though it never runs.
class DriftDatabaseLocation {
  DriftDatabaseLocation._();

  static String? get appGroupDriftRoot => null;

  static Future<void> prepare({
    AppGroupStorageHost? host,
    bool? platformIsIOS,
  }) async {}

  static Future<void> confirmLaunchRead() async {}

  static Future<void> resetAppGroupStorage() async {}

  static void debugSetAppGroupDriftRoot(String? root) {}
}
