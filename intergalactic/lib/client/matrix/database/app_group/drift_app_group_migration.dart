import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:path/path.dart' as p;

/// Where the migration stands, persisted in a marker file inside the App
/// Group so every launch resumes from the truth on disk rather than from a
/// preference that can disagree with it.
///
/// The marker is written BEFORE the first file moves. From that moment the
/// App Group path is authoritative, even if the process dies halfway: a
/// launch that finds `migrating` finishes the move before any client opens a
/// database, so no client ever opens the app-private copy again and creates
/// the "both copies exist" state the quarantine rule guards against.
enum DriftMigrationStage {
  /// Marker written, moves in progress or interrupted.
  migrating,

  /// Every account moved. The app-private copy still exists.
  moved,

  /// A launch has read from the new location (B3's "confirming launch").
  confirmed,

  /// The app-private copy is deleted and verified gone.
  complete,
}

/// How a launch resolved the account database location.
class DriftMigrationOutcome {
  const DriftMigrationOutcome._(this.appGroupAuthoritative, this.reason);

  /// True when the App Group path is where the account databases live.
  final bool appGroupAuthoritative;

  /// A coarse reason, safe to log: no path, no account, no contents.
  final String reason;

  static const DriftMigrationOutcome appGroup = DriftMigrationOutcome._(
    true,
    'app_group',
  );
  static const DriftMigrationOutcome protectionUnavailable =
      DriftMigrationOutcome._(false, 'protection_unavailable');
  static const DriftMigrationOutcome containerUnavailable =
      DriftMigrationOutcome._(false, 'container_unavailable');

  /// At least one account could not be moved this launch, so the App Group
  /// path does not yet hold every account and must not be treated as
  /// authoritative. The marker stays at `migrating` and the next launch
  /// resumes.
  static const DriftMigrationOutcome moveIncomplete = DriftMigrationOutcome._(
    false,
    'move_incomplete',
  );
}

/// Thrown when the filesystem does not report the class that was just set.
class DriftProtectionException implements Exception {
  DriftProtectionException(this.reported);

  /// What the filesystem reported, or null when it reported nothing.
  final String? reported;

  @override
  String toString() =>
      'DriftProtectionException(reported: ${reported ?? 'none'})';
}

/// Moves every Matrix account database from the app-private container into
/// the App Group container, once, resumably, and under the data-protection
/// class the Notification Service Extension will depend on.
///
/// The contract this implements is recorded in
/// `docs/agent-control/ios/nse-phase-b-queue-record-2026-08-21.md` (workspace
/// repo). The parts of it that shaped this class, so the shape is not
/// re-derived:
///
/// - **Enumerate the source directory, not the preferences list** (REVIEW R4).
///   A `<clientName>` directory whose preferences entry was lost is invisible
///   to `getRegisteredMatrixClients()` and would be stranded. The registered
///   list is a cross-check that is logged as a count, never the input.
/// - **Run once, before any client opens a database, for every account**
///   (REVIEW R4). The per-client open path cannot do that. The caller runs
///   this from startup ahead of `ClientManager.init`.
/// - **Rollback-journal mode, not WAL** (REVIEW R1, decided). The files that
///   can exist beside `data.db` are `data.db-journal` - possibly a HOT journal
///   if the writer died - and, defensively, `-wal`/`-shm`. The journal moves
///   BEFORE the database: a database without its hot journal reads as
///   consistent when it is not, whereas a journal without its database is
///   inert. An interruption between the two leaves a state the next launch
///   resumes from correctly.
/// - **Never silently discard a database.** If the destination already holds
///   a `data.db` for an account that still has one at the source, the
///   destination wins and the source directory is moved to a quarantine
///   sibling rather than overwritten. Quarantine is never deleted by this
///   class; it is counted and reported every launch until someone acts on it.
/// - **B1**: the class is set on directories before files land in them (so
///   new files inherit it), then on every moved file, read back each time,
///   and re-asserted over the whole destination tree on every launch. If it
///   cannot be set before the first move, nothing moves and the app-private
///   path stays authoritative.
/// - **B3**: the source copy is deleted on the launch AFTER the one that read
///   from the new location, and the deletion is verified.
/// - **B4**: every log line here carries a coarse stage, counts, and an error
///   class or errno. No path, no account name, no listing, no contents. A
///   `FileSystemException` is never logged through `toString()`, which
///   includes the path; only its `osError.errorCode` is.
class DriftAppGroupMigration {
  DriftAppGroupMigration({
    required this.sourceRoot,
    required this.appGroupDatabaseRoot,
    required this.host,
    this.registeredClientCount,
  });

  /// `<app-private>/db/account/drift` - where the databases have always been.
  final String sourceRoot;

  /// `<App Group>/db` - the shared root the account tree is created under.
  final String appGroupDatabaseRoot;

  final AppGroupStorageHost host;

  /// `preferences.getRegisteredMatrixClients().length`, for the cross-check
  /// log line only. Never used to decide what moves.
  final int? registeredClientCount;

  /// `<App Group>/db/account/drift` - the new home.
  String get destinationRoot =>
      p.join(appGroupDatabaseRoot, 'account', 'drift');

  /// Sibling of the source, in the app-private container: an account whose
  /// database already existed at the destination lands here instead of being
  /// overwritten or discarded.
  String get quarantineRoot =>
      p.join(p.dirname(sourceRoot), 'drift-quarantine');

  /// Beside the destination, not inside it, so the account enumeration the
  /// extension performs by `client_id` never meets it.
  String get markerPath => p.join(
    appGroupDatabaseRoot,
    'account',
    '.drift-app-group-migration.json',
  );

  /// Journal-family files first, the database last. See the class comment.
  static const List<String> databaseFileNames = [
    'data.db-journal',
    'data.db-wal',
    'data.db-shm',
    'data.db',
  ];

  static const String _source = 'drift-app-group';
  static const int _markerVersion = 1;

  /// Resolves the location for this launch, moving or finishing a move if one
  /// is owed. Safe to call on every launch; it is designed to be.
  Future<DriftMigrationOutcome> prepare() async {
    final stage = await readStage();

    final directoriesProtected = await _ensureProtectedDirectories();
    if (!directoriesProtected) {
      if (stage == null) {
        // B1: nothing has moved, and nothing will. The app-private path
        // stays authoritative and no marker exists to say otherwise.
        Log.w(
          'App Group migration aborted: protection class unavailable; '
          'app-private path remains authoritative',
          category: LogCategory.app,
          source: _source,
        );
        return DriftMigrationOutcome.protectionUnavailable;
      }
      // The data already lives in the App Group. Re-assertion failing on a
      // later launch is reported loudly, but it cannot move the data back.
      Log.e(
        'App Group protection re-assert failed at stage ${stage.name}; '
        'continuing with the App Group path',
        category: LogCategory.app,
        source: _source,
      );
    }

    switch (stage) {
      // A failed move must not leave the App Group path authoritative. The
      // destination directory is created before any file is moved
      // (_moveAccount), so an account whose data.db did not arrive opens an
      // EMPTY database there and looks logged out - and drift creating that
      // empty file is what makes the next launch see data.db on both sides,
      // take the collision branch, and rename the account's REAL database
      // into quarantine. Staying on the app-private path costs a launch and
      // strands nothing.
      case null:
        if (!await _migrate(resuming: false)) {
          return DriftMigrationOutcome.moveIncomplete;
        }
      case DriftMigrationStage.migrating:
        if (!await _migrate(resuming: true)) {
          return DriftMigrationOutcome.moveIncomplete;
        }
      case DriftMigrationStage.moved:
        break;
      case DriftMigrationStage.confirmed:
        await _deleteSource();
      case DriftMigrationStage.complete:
        break;
    }

    await _reassertProtection();
    await _reportQuarantine();
    return DriftMigrationOutcome.appGroup;
  }

  /// B3's confirming launch: call once a client has been loaded from the new
  /// location. Advances `moved` to `confirmed`; the next launch deletes the
  /// source. Any other stage is left alone.
  Future<void> confirmLaunchRead() async {
    final stage = await readStage();
    if (stage != DriftMigrationStage.moved) {
      return;
    }
    await _writeStage(DriftMigrationStage.confirmed);
    Log.i(
      'App Group migration stage=confirmed',
      category: LogCategory.app,
      source: _source,
    );
  }

  /// The persisted stage, or null when no migration has begun. An unreadable
  /// or unrecognised marker reads as null: the safe reading, because it means
  /// "look at the source directory and move whatever is there", which the
  /// quarantine rule makes safe even if something already moved.
  Future<DriftMigrationStage?> readStage() async {
    final file = File(markerPath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final name = decoded['stage'];
      if (name is! String) {
        return null;
      }
      for (final stage in DriftMigrationStage.values) {
        if (stage.name == name) {
          return stage;
        }
      }
      return null;
    } on FormatException {
      Log.w(
        'App Group migration marker unreadable: format',
        category: LogCategory.app,
        source: _source,
      );
      return null;
    } on FileSystemException catch (error) {
      Log.w(
        'App Group migration marker unreadable: errno ${_errno(error)}',
        category: LogCategory.app,
        source: _source,
      );
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Moving

  /// Returns false when at least one account could not be moved.
  ///
  /// Partial success is reported as failure ON PURPOSE, and it is not free:
  /// an account that DID move is invisible for the launch that stays on the
  /// app-private path, because its database is no longer at the source. That
  /// is a self-healing gap - the next launch resumes and both accounts come
  /// back - whereas continuing onto the App Group path quarantines the failed
  /// account's real database, which nothing recovers.
  Future<bool> _migrate({required bool resuming}) async {
    final pending = await _enumerateSourceAccounts();

    final registered = registeredClientCount;
    if (registered != null) {
      Log.i(
        'App Group migration cross-check: registered=$registered '
        'on_disk=${pending.length}',
        category: LogCategory.app,
        source: _source,
      );
    }

    if (!resuming) {
      if (pending.isEmpty) {
        // Fresh install, or nothing left at the source. There is no copy to
        // confirm against and nothing to delete, so the marker goes straight
        // to complete and the (empty) source tree is removed now.
        await _writeStage(DriftMigrationStage.complete);
        await _deleteSource();
        Log.i(
          'App Group migration stage=complete accounts=0',
          category: LogCategory.app,
          source: _source,
        );
        // Fresh install: no account failed to move because none had to. The
        // App Group path is authoritative from the first launch.
        return true;
      }
      await _logSourceProtectionClass(pending);
      await _writeStage(DriftMigrationStage.migrating);
    }

    var moved = 0;
    var quarantined = 0;
    var failed = 0;
    String? failureClass;

    for (final account in pending) {
      try {
        final result = await _moveAccount(account);
        if (result == _MoveResult.quarantined) {
          quarantined++;
        } else {
          moved++;
        }
      } on FileSystemException catch (error) {
        failed++;
        failureClass = 'errno_${_errno(error)}';
      } on DriftProtectionException catch (error) {
        failed++;
        failureClass =
            'protection_${error.reported == null ? 'none' : 'mismatch'}';
      } catch (error) {
        failed++;
        failureClass = error.runtimeType.toString();
      }
    }

    if (failed == 0) {
      await _writeStage(DriftMigrationStage.moved);
    }

    final line =
        'App Group migration stage=${failed == 0 ? 'moved' : 'migrating'} '
        'resumed=$resuming accounts=${pending.length} moved=$moved '
        'quarantined=$quarantined failed=$failed'
        '${failureClass == null ? '' : ' error=$failureClass'}';
    if (failed == 0) {
      Log.i(line, category: LogCategory.app, source: _source);
    } else {
      Log.e(line, category: LogCategory.app, source: _source);
    }
    return failed == 0;
  }

  /// Account directory names at the source that hold any database file.
  /// Empty `<clientName>` directories - the maintainer's device had seven of
  /// ten - are not accounts and are not moved.
  Future<List<String>> _enumerateSourceAccounts() async {
    final root = Directory(sourceRoot);
    if (!await root.exists()) {
      return const [];
    }
    final accounts = <String>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) {
        continue;
      }
      for (final name in databaseFileNames) {
        if (await File(p.join(entry.path, name)).exists()) {
          accounts.add(p.basename(entry.path));
          break;
        }
      }
    }
    accounts.sort();
    return accounts;
  }

  Future<_MoveResult> _moveAccount(String account) async {
    final sourceDir = p.join(sourceRoot, account);
    final destinationDir = p.join(destinationRoot, account);

    final sourceDatabase = File(p.join(sourceDir, 'data.db'));
    final destinationDatabase = File(p.join(destinationDir, 'data.db'));
    if (await sourceDatabase.exists() && await destinationDatabase.exists()) {
      await _quarantine(account);
      return _MoveResult.quarantined;
    }

    await Directory(destinationDir).create(recursive: true);
    await _protect(destinationDir);

    for (final name in databaseFileNames) {
      final source = File(p.join(sourceDir, name));
      if (!await source.exists()) {
        continue;
      }
      final destinationPath = p.join(destinationDir, name);
      await _moveFile(source, destinationPath);
      await _protect(destinationPath);
    }
    return _MoveResult.moved;
  }

  /// Rename first: within one volume it is atomic, and the app container and
  /// the group container share the data volume on iOS. The copy fallback is
  /// for any host where they do not; it lands under a temporary name and is
  /// renamed into place so a partial copy is never mistaken for the database.
  Future<void> _moveFile(File source, String destinationPath) async {
    try {
      await source.rename(destinationPath);
      return;
    } on FileSystemException {
      // Fall through to copy.
    }
    final staging = '$destinationPath.moving';
    await source.copy(staging);
    await File(staging).rename(destinationPath);
    await source.delete();
  }

  Future<void> _quarantine(String account) async {
    final target = Directory(p.join(quarantineRoot, account));
    await Directory(quarantineRoot).create(recursive: true);
    if (await target.exists()) {
      // A second collision for the same account keeps both: number the new
      // one rather than merge into or replace the earlier quarantine.
      var suffix = 1;
      while (await Directory('${target.path}-$suffix').exists()) {
        suffix++;
      }
      await Directory(
        p.join(sourceRoot, account),
      ).rename('${target.path}-$suffix');
    } else {
      await Directory(p.join(sourceRoot, account)).rename(target.path);
    }
    Log.w(
      'App Group migration quarantined an account: destination already held '
      'a database',
      category: LogCategory.app,
      source: _source,
    );
  }

  // ---------------------------------------------------------------------------
  // Deleting the source (B3)

  Future<void> _deleteSource() async {
    final root = Directory(sourceRoot);
    if (await root.exists()) {
      try {
        await root.delete(recursive: true);
      } on FileSystemException catch (error) {
        Log.e(
          'App Group migration source delete failed: errno ${_errno(error)}',
          category: LogCategory.app,
          source: _source,
        );
        return;
      }
    }
    // Verified, not assumed: B3 asks for the deletion to be checked.
    if (await root.exists()) {
      Log.e(
        'App Group migration source still present after delete',
        category: LogCategory.app,
        source: _source,
      );
      return;
    }
    final stage = await readStage();
    if (stage != DriftMigrationStage.complete) {
      await _writeStage(DriftMigrationStage.complete);
    }
    Log.i(
      'App Group migration stage=complete source_deleted=true',
      category: LogCategory.app,
      source: _source,
    );
  }

  Future<void> _reportQuarantine() async {
    final root = Directory(quarantineRoot);
    if (!await root.exists()) {
      return;
    }
    var count = 0;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory) {
        count++;
      }
    }
    if (count > 0) {
      Log.w(
        'App Group migration quarantine holds $count account(s); '
        'not deleted automatically',
        category: LogCategory.app,
        source: _source,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Protection (B1)

  /// Creates `<group>/db`, `/account`, `/account/drift` and protects each,
  /// outermost first so inner items inherit. False when any read-back fails.
  Future<bool> _ensureProtectedDirectories() async {
    final directories = [
      appGroupDatabaseRoot,
      p.join(appGroupDatabaseRoot, 'account'),
      destinationRoot,
    ];
    for (final directory in directories) {
      try {
        await Directory(directory).create(recursive: true);
        await _protect(directory);
      } on FileSystemException catch (error) {
        Log.e(
          'App Group directory setup failed: errno ${_errno(error)}',
          category: LogCategory.app,
          source: _source,
        );
        return false;
      } on DriftProtectionException catch (error) {
        Log.e(
          'App Group directory protection read-back failed: '
          '${error.reported == null ? 'no class reported' : 'unexpected class'}',
          category: LogCategory.app,
          source: _source,
        );
        return false;
      } catch (error) {
        Log.e(
          'App Group directory protection failed: ${error.runtimeType}',
          category: LogCategory.app,
          source: _source,
        );
        return false;
      }
    }
    return true;
  }

  /// Sets the class and requires the read-back to match.
  Future<void> _protect(String path) async {
    final reported = await host.protectItem(path);
    if (reported != AppGroupStorageHost.expectedProtectionClass) {
      throw DriftProtectionException(reported);
    }
  }

  /// B1's "re-assert on every launch": every directory and file under the
  /// destination, counted, never named.
  Future<void> _reassertProtection() async {
    final root = Directory(destinationRoot);
    if (!await root.exists()) {
      return;
    }
    var items = 0;
    var failed = 0;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      items++;
      try {
        await _protect(entry.path);
      } catch (_) {
        failed++;
      }
    }
    if (failed > 0) {
      Log.e(
        'App Group protection re-assert: items=$items failed=$failed',
        category: LogCategory.app,
        source: _source,
      );
    } else {
      Log.d(
        'App Group protection re-assert: items=$items failed=0',
        category: LogCategory.app,
        source: _source,
      );
    }
  }

  /// The measurement the "drift database's actual iOS file protection class"
  /// queue row asks for, taken once, from the files as they are before they
  /// move. Logs the OS constant and a count - nothing that identifies a file.
  Future<void> _logSourceProtectionClass(List<String> accounts) async {
    final counts = <String, int>{};
    for (final account in accounts) {
      final path = p.join(sourceRoot, account, 'data.db');
      if (!await File(path).exists()) {
        continue;
      }
      String value;
      try {
        value = await host.readProtectionClass(path) ?? 'none';
      } catch (_) {
        value = 'unreadable';
      }
      counts[value] = (counts[value] ?? 0) + 1;
    }
    for (final entry in counts.entries) {
      Log.i(
        'App Group migration source_protection_class=${entry.key} '
        'count=${entry.value}',
        category: LogCategory.app,
        source: _source,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Marker

  /// Atomic: written beside the marker and renamed over it, so a crash leaves
  /// the previous stage rather than a torn file. Carries the stage and a
  /// version - no timestamp, no path, no account.
  Future<void> _writeStage(DriftMigrationStage stage) async {
    final marker = File(markerPath);
    await marker.parent.create(recursive: true);
    final staging = File('$markerPath.tmp');
    await staging.writeAsString(
      jsonEncode({'version': _markerVersion, 'stage': stage.name}),
      flush: true,
    );
    await staging.rename(markerPath);
    try {
      await _protect(markerPath);
    } catch (_) {
      // The directory class already covers it; a failed explicit set on the
      // marker is not worth failing the stage transition over.
    }
  }

  static int? _errno(FileSystemException error) => error.osError?.errorCode;
}

enum _MoveResult { moved, quarantined }
