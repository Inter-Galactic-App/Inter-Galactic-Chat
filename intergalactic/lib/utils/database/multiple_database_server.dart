import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

/// Message verb for the release protocol. A connect request is a two-element
/// list and a release request is a three-element list led by this, so older
/// callers that only ever send `[name, port]` are unaffected.
const String kDatabaseReleaseCommand = '__release__';

final class MultiDatabaseServer {
  final Map<String, DriftIsolate> _activeIsolates = {};

  /// Release chains in progress, by database name. See [_release].
  final Map<String, Future<void>> _releasesInFlight = {};

  final ReceivePort _receiveConnections = ReceivePort();

  MultiDatabaseServer() {
    _receiveConnections.listen((message) {
      if (message is! List) {
        Log.e("Expected to receive a list");
        return;
      }

      if (message.length == 3 && message[0] == kDatabaseReleaseCommand) {
        final name = message[1];
        final ack = message[2];
        if (name is! String || ack is! SendPort) {
          Log.e("Malformed database release request");
          if (ack is SendPort) ack.send(false);
          return;
        }
        unawaited(_release(name, ack));
        return;
      }

      if (message.length != 2) {
        Log.e("Received list of incorrect length");
        return;
      }

      final name = message[0];
      final port = message[1];

      if (name is! String) {
        Log.e("list[0] was not a string");
        return;
      }

      if (port is! SendPort) {
        Log.e("list[1] was not a SendPort");
        return;
      }

      final isolate = _activeIsolates.putIfAbsent(name, () {
        return DriftIsolate.inCurrent(
          serialize: true,
          // obviously you can pass a path instead of a name and use that to open the right NativeDatabase
          () => NativeDatabase(File(name), setup: _applyJournalMode),
        );
      });

      port.send(isolate.connectPort);
    });
  }

  /// Rollback-journal mode, stated rather than inherited.
  ///
  /// This is sqlite3's default, so nothing changes today - but the iOS
  /// Notification Service Extension opens the account database with
  /// `SQLITE_OPEN_READONLY`, and a read-only open of a WAL database FAILS when
  /// the `-shm` file is absent. That is precisely the state Phase C serves: the
  /// app is not running, and B5 released the connection before suspension, so
  /// nothing has recreated `-shm`. Enabling WAL here - the obvious performance
  /// move, and the one drift's own `readPool` documentation suggests - would
  /// make every push notification silently fall back to the gateway's generic
  /// payload, with no Swift test target anywhere to catch it.
  ///
  /// `drift_app_group_migration.dart` records this as a decision (REVIEW R1)
  /// and the migration only moves `-journal`. It is declared here so the
  /// decision lives where the database is actually opened, and
  /// `multiple_database_server_journal_mode_test.dart` reads it back.
  static void _applyJournalMode(CommonDatabase db) {
    db.execute('PRAGMA journal_mode = DELETE;');
  }

  /// Shuts down the drift server for [name] and **evicts it from the map**.
  ///
  /// The eviction is not tidiness, it is the whole correctness requirement.
  /// `_activeIsolates` is a `putIfAbsent` cache: shutting a server down without
  /// removing its entry leaves the dead server in the map, the next connect
  /// returns it, and `serve()` throws `StateError` — so that account's database
  /// never reopens until the process restarts. A release that half-works is
  /// strictly worse than no release at all, which is why shutdown and eviction
  /// ship together.
  ///
  /// Evicting *first* also means a connect racing this release creates a fresh
  /// server rather than adopting the one being torn down.
  Future<void> _release(String name, SendPort ack) async {
    // Serialised per name. `_release` is dispatched with `unawaited`, so a
    // second release message for the same name is processed during the first
    // one's `await`: it finds the entry already evicted and acknowledges
    // success while the first shutdown is still running, and the caller
    // records a release that has not happened. Waiting for the one in flight
    // and THEN reading the map keeps the answer true in both interleavings -
    // including a connect that lands between the two, which rebuilds the
    // server and which this release must then shut down rather than report
    // the earlier call's result for.
    final inFlight = _releasesInFlight[name];
    final completer = Completer<void>();
    _releasesInFlight[name] = completer.future;
    try {
      if (inFlight != null) {
        await inFlight;
      }
      await _releaseNow(name, ack);
    } finally {
      completer.complete();
      if (identical(_releasesInFlight[name], completer.future)) {
        _releasesInFlight.remove(name);
      }
    }
  }

  Future<void> _releaseNow(String name, SendPort ack) async {
    final isolate = _activeIsolates.remove(name);
    if (isolate == null) {
      // Nothing open for this database. Releasing twice, or releasing something
      // never opened, is not an error - the caller wants "not holding it", and
      // that is already true.
      ack.send(true);
      return;
    }

    try {
      await isolate.shutdownAll();
      ack.send(true);
    } catch (error, stackTrace) {
      // The entry is already evicted, so the next connect will build a fresh
      // server regardless. Report failure so the caller does not record a
      // release that may not have completed.
      Log.w("Failed to shut down database server");
      Log.onError(error, stackTrace);
      ack.send(false);
    }
  }
}

/// The release half of the B5 mechanism. The re-establish half is
/// `ReleasableConnection`, and the lifecycle trigger drives the two together.
///
/// [DatabaseIsolate.release] shuts the drift server down and evicts it, so a
/// *new* [DatabaseIsolate.connect] rebuilds cleanly. On its own that is not
/// enough: a holder that was handed a connection - the Matrix SDK through
/// `matrix_database_io.dart` - would keep a connection whose server is gone.
/// That is why the account database is opened through
/// `ReleasableConnection`, which can rebuild its inner executor, and why the
/// trigger sweeps the wrappers rather than calling into this class directly.
/// The media/file cache is opened here directly and is not released; it
/// stays app-private and has no `0xdead10cc` exposure.
class DatabaseIsolate {
  static final receiveConnectPort = ReceivePort();
  static SendPort? connectToServer;
  static const isolateName =
      "${BuildConfig.windowsTempNamespace}.database_isolate";

  static Future<void> start() async {
    connectToServer = IsolateNameServer.lookupPortByName(isolateName);
    if (connectToServer == null) {
      Isolate.spawn(
        (SendPort port) {
          final server = MultiDatabaseServer();
          port.send(server._receiveConnections.sendPort);
        },
        receiveConnectPort.sendPort,
        debugName: "Database Isolate",
      );

      connectToServer = await receiveConnectPort.first as SendPort;
      IsolateNameServer.registerPortWithName(connectToServer!, isolateName);
    }
  }

  /// Databases opted in to release tracking.
  ///
  /// Only databases with a `0xdead10cc` exposure belong here. The media/file
  /// cache does not: it stays at the app-private path under Phase B, so
  /// releasing it buys nothing and only widens the surface that re-establish
  /// has to cover.
  ///
  /// Per-isolate static state, not global. An isolate that calls [connect]
  /// populates its own copy, so [releaseAll] from the main isolate does not see
  /// a connection opened in a background isolate. Immaterial on iOS today;
  /// stated so nobody assumes otherwise.
  static final Set<String> _connected = {};

  static Set<String> get connectedDatabases => Set.unmodifiable(_connected);

  /// How long to wait for the database isolate to answer a release.
  ///
  /// Release runs on the path to suspension, where iOS grants roughly five
  /// seconds after `didEnterBackground` without a background-task assertion. An
  /// unbounded wait on a wedged server isolate is the worst case: neither
  /// released nor cleanly suspended. Timing out and reporting false is strictly
  /// better, and every caller already handles false.
  static const Duration releaseTimeout = Duration(seconds: 2);

  /// Opens a connection to [databaseName].
  ///
  /// Pass [trackForRelease] for databases that a release sweep should cover.
  /// Defaults to false so a new caller is excluded until someone has thought
  /// about whether releasing it is safe.
  static Future<DatabaseConnection> connect(
    String databaseName, {
    bool trackForRelease = false,
  }) async {
    if (connectToServer == null) {
      await start();
    }

    final response = ReceivePort();

    connectToServer!.send([databaseName, response.sendPort]);

    final connectPort = await response.first as SendPort;
    if (trackForRelease) {
      _connected.add(databaseName);
    }
    return DriftIsolate.fromConnectPort(connectPort, serialize: true).connect();
  }

  /// Releases the drift server for [databaseName] so no file handle or lock is
  /// held across suspension.
  ///
  /// This exists for `0xdead10cc`: iOS terminates a suspended process that still
  /// holds a lock on a file in a shared container. Locks in rollback-journal
  /// mode are transaction-scoped, so an idle connection holds none — meaning the
  /// exposure is suspension **mid-transaction**, and the caller's job is to
  /// release at a point where no transaction is in flight.
  ///
  /// CALLERS MUST NOT key this on `AppLifecycleState.paused` alone. Flutter
  /// reports `paused` while the app runs under the `audio` background mode, so a
  /// release keyed on it would close the database out from under an active call
  /// — worse than the failure this prevents. The trigger is lifecycle state AND
  /// the absence of live background execution.
  ///
  /// Call this through `ReleasableConnection.release()`, which refuses while
  /// anything is in flight and drops its executor first; calling it directly
  /// while a holder is live leaves that holder with a dead server. Returns
  /// true when the database is no longer held, including when it was never
  /// open, and false on failure or timeout.
  static Future<bool> release(String databaseName) async {
    if (connectToServer == null) {
      return true;
    }

    final response = ReceivePort();
    try {
      connectToServer!.send([
        kDatabaseReleaseCommand,
        databaseName,
        response.sendPort,
      ]);
      final released =
          await response.first.timeout(
            releaseTimeout,
            onTimeout: () => false,
          ) ==
          true;
      if (released) {
        _connected.remove(databaseName);
      }
      return released;
    } finally {
      response.close();
    }
  }

  /// Releases every database opted in via `connect(trackForRelease: true)`.
  ///
  /// This is deliberately NOT "every database this isolate opened" — the media
  /// cache is excluded, because it stays app-private under Phase B and has no
  /// `0xdead10cc` exposure.
  ///
  /// Test-only surface. The lifecycle trigger does NOT use it and must not:
  /// it sweeps `ReleasableConnection.live`, because only the wrappers can
  /// re-establish, and a server shut down behind a wrapper that is not told
  /// is exactly the "release without re-establish" failure. This exists so
  /// tests can tear the isolate down between cases. Returns true only when
  /// all tracked databases released.
  @visibleForTesting
  static Future<bool> releaseAll() async {
    var allReleased = true;
    for (final name in _connected.toList()) {
      if (!await release(name)) {
        allReleased = false;
      }
    }
    return allReleased;
  }
}
