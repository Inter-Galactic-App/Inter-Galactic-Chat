import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_e2ee_diagnostics.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';

/// What a silent wake did. Logged as a literal; returned to native as the
/// fetch result.
enum RemoteWakeOutcome {
  /// The app is in the foreground and sync is live; nothing to catch up.
  foreground,

  /// Databases re-established, one sync drained per account, released again.
  caughtUp,

  /// The database is unreadable before the device's first unlock (B5's
  /// deferred path). Nothing synced; the next resume retries.
  deferred,

  /// The sync did not finish inside the budget; released anyway.
  timedOut,

  /// Re-establish or sync failed; released anyway.
  failed,
}

/// Route metadata from the APNs wake. It is transient: no route identifiers
/// are logged or persisted by the E10 measurement.
class IosRemoteWakeRoute {
  const IosRemoteWakeRoute({
    required this.clientId,
    required this.roomId,
    required this.eventId,
  });

  final String clientId;
  final String roomId;
  final String eventId;

  static IosRemoteWakeRoute? fromPlatformPayload(Object? payload) {
    if (payload is! Map) return null;
    final clientId = payload['client_id'];
    final roomId = payload['room_id'];
    final eventId = payload['event_id'];
    if (clientId is! String || roomId is! String || eventId is! String) {
      return null;
    }
    if (clientId.isEmpty || roomId.isEmpty || eventId.isEmpty) return null;
    return IosRemoteWakeRoute(
      clientId: clientId,
      roomId: roomId,
      eventId: eventId,
    );
  }
}

/// The catch-up a `content-available` wake performs, with every dependency
/// injected so the ORDER is testable: re-establish, sync, release. The order
/// is the point. B5 releases the account database before suspension, so a
/// wake that syncs without re-establishing throws, and a wake that
/// re-establishes without releasing again leaves the file locked when iOS
/// suspends the process a moment later, which is the 0xdead10cc kill B5
/// exists to prevent. Release therefore runs in `finally`, unless the app
/// reached the foreground meanwhile, where the lifecycle owns the database.
class RemoteWakeCatchUp {
  const RemoteWakeCatchUp({
    required this.isForeground,
    required this.resume,
    required this.syncAll,
    required this.abortSync,
    required this.suspend,
    this.budget = const Duration(seconds: 15),
  });

  final bool Function() isForeground;
  final Future<DatabaseResumeOutcome> Function() resume;
  final Future<void> Function() syncAll;

  /// Stops whatever [syncAll] left running. `Future.timeout` only completes
  /// the future it returns - the sync itself keeps going - so the release in
  /// `run`'s `finally` would otherwise happen under a live sync, which is the
  /// 0xdead10cc kill this class exists to prevent.
  final Future<void> Function() abortSync;
  final Future<DatabaseSuspendOutcome> Function() suspend;
  final Duration budget;

  Future<RemoteWakeOutcome> run() async {
    if (isForeground()) {
      return RemoteWakeOutcome.foreground;
    }
    var outcome = RemoteWakeOutcome.failed;
    var established = false;
    try {
      final resumed = await resume();
      if (resumed == DatabaseResumeOutcome.deferredRetryOnNextResume ||
          resumed == DatabaseResumeOutcome.failed) {
        return resumed == DatabaseResumeOutcome.failed
            ? RemoteWakeOutcome.failed
            : RemoteWakeOutcome.deferred;
      }
      established = true;
      if (budget <= Duration.zero) {
        // A slow cold launch can spend the whole deadline before we get here,
        // and `syncBudgetAfter` then returns zero. Starting a sync we cannot
        // wait for would leave it running under the release below, so skip it
        // and let the next wake catch up.
        outcome = RemoteWakeOutcome.timedOut;
        return outcome;
      }
      try {
        await syncAll().timeout(budget);
        outcome = RemoteWakeOutcome.caughtUp;
      } on TimeoutException {
        outcome = RemoteWakeOutcome.timedOut;
        await _quiesceSync();
      }
      return outcome;
    } finally {
      if (established && !isForeground()) {
        await suspend();
      }
    }
  }

  /// Stops the timed-out sync before the release. Swallows its failure on
  /// purpose: the release in `finally` has to happen either way, and an abort
  /// that throws must not become the wake's reported outcome.
  Future<void> _quiesceSync() async {
    try {
      await abortSync();
    } catch (error) {
      Log.w(
        'remote_wake abort_failed error=${error.runtimeType}',
        category: LogCategory.notifications,
        source: IosRemoteWake._source,
      );
    }
  }
}

/// The host side of the iOS silent wake.
class IosRemoteWake {
  IosRemoteWake._();

  static const String _source = 'ios-remote-wake';

  /// Server-side long-poll timeout for the catch-up sync: short, because the
  /// point is to collect what is already pending, not to wait for more.
  static const Duration _syncLongPoll = Duration(seconds: 3);

  /// Native's hard deadline for one wake. Dart must finish inside it: once
  /// native completes the fetch it drops the background assertion, and a
  /// catch-up still holding the database past that point is the 0xdead10cc
  /// kill B5 exists to prevent.
  static const Duration nativeDeadline = Duration(seconds: 25);

  /// Left for the release itself, plus the channel round trip, after the sync
  /// budget is spent. The release waits on quiescence, so it is not free.
  static const Duration releaseReserve = Duration(seconds: 6);

  /// Held back from [releaseReserve] for `completeRemoteWake` itself. Native
  /// must hear the answer before its deadline; everything before this belongs
  /// to the release.
  static const Duration completionReserve = Duration(seconds: 1);

  /// How long the release may keep waiting for quiescence, given that
  /// [spent] of the deadline is already gone when the catch-up begins.
  ///
  /// The reserve exists to be spent here. On 2026-09-09 it was not: the
  /// trigger's own fixed 4 s wait expired with the sync's leftovers still
  /// holding a transaction, the account database was left open with 1.8 s of
  /// the deadline unused, and `database_release` logged
  /// `timed_out reason=not_quiescent`, `released=0 of=1`. An open database at
  /// suspension is the 0xdead10cc kill; unused time next to it is not a
  /// trade-off, it is waste.
  ///
  /// Derived from [spent] and NOT from the sync budget, which is the same
  /// quantity only while the budget is unclamped. `syncBudgetAfter` floors at
  /// zero past 19 s, so `budget + releaseReserve - completionReserve` stops
  /// shrinking exactly where the deadline is tightest and promises a window
  /// running past 25 s - 27 s at `spent` of 22. Stated in terms of what is
  /// actually left, the window never pushes the finish past the cutoff, and
  /// never past where it already was:
  /// `spent + releaseWindowAfter(spent) <= max(spent, nativeDeadline -
  /// completionReserve)`, for every value rather than the comfortable ones.
  ///
  /// Not the stronger `<= nativeDeadline - completionReserve`, which is what
  /// this comment first claimed. Past a `spent` of 24 s that bound is already
  /// broken by `spent` alone, so no window - zero included - can satisfy it,
  /// and a wake that late is late whatever happens here. The sweep in
  /// `ios_remote_wake_test.dart` asserts the weaker property because it is the
  /// true one; equality with the cutoff is asserted separately, over the range
  /// where time actually remains, because leaving any of the window unspent is
  /// the original defect.
  ///
  /// Zero past the deadline is not the release giving up. The floor lives in
  /// [DatabaseReleaseTrigger.suspend], which refuses to shorten below its own
  /// `quiescenceTimeout` - a caller already late gains nothing by giving up
  /// sooner - so a window of zero still buys the release that wait. One floor,
  /// in the class that owns the polling, instead of a second copy here that
  /// could only disagree with it.
  static Duration releaseWindowAfter(Duration spent) {
    final window = nativeDeadline - spent - completionReserve;
    return window > Duration.zero ? window : Duration.zero;
  }

  /// The elapsed time native reports with a wake, clamped into a range that
  /// cannot make the budget lie.
  ///
  /// Native measures from the moment iOS handed it the push; on a cold
  /// background launch that includes the Flutter engine boot, which Dart
  /// cannot see and which can be most of the deadline. A missing or
  /// unreadable value falls back to zero, which is the old behaviour rather
  /// than a guess; a value at or beyond the deadline is kept, so
  /// [syncBudgetAfter] returns zero and no sync starts.
  static Duration nativeElapsedFrom(Object? arguments) {
    if (arguments is! Map) {
      return Duration.zero;
    }
    return clampNativeElapsed(arguments['native_elapsed_ms']) ?? Duration.zero;
  }

  /// A raw millisecond count from native, clamped, or `null` when there is no
  /// usable number in it.
  ///
  /// Separate from [nativeElapsedFrom] because the two callers want different
  /// answers to "native said nothing": a wake payload falls back to zero,
  /// while a mid-handling query falls back to the value the payload already
  /// carried. Only `null` can tell them apart.
  static Duration? clampNativeElapsed(Object? raw) {
    final milliseconds = raw is int
        ? raw
        : raw is num
        ? raw.toInt()
        : null;
    if (milliseconds == null || milliseconds <= 0) {
      return null;
    }
    final elapsed = Duration(milliseconds: milliseconds);
    return elapsed > nativeDeadline ? nativeDeadline : elapsed;
  }

  /// The sync budget for a wake that has already spent [elapsed] on app
  /// initialisation and on whatever native spent before Dart was reached.
  ///
  /// The old flat 15 s only bounded the SYNC, so a cold background launch could
  /// spend most of native's deadline in `initNecessary()` and then start a
  /// fresh 15 s sync - finishing, if at all, after native had completed the
  /// fetch and dropped the assertion. Deriving the budget from what is left
  /// keeps the release inside the deadline no matter how slow the launch was.
  static Duration syncBudgetAfter(Duration elapsed) {
    final remaining = nativeDeadline - elapsed - releaseReserve;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  /// Runs the catch-up for one wake and reports the outcome. Never throws.
  static Future<RemoteWakeOutcome> handle({
    required ClientManager manager,
    DatabaseReleaseTrigger? trigger,
    Duration? budget,
    Duration nativeElapsed = Duration.zero,
    Duration spent = Duration.zero,
    IosRemoteWakeRoute? route,
  }) async {
    final releaseTrigger = trigger ?? DatabaseReleaseTrigger.instance;
    final stopwatch = Stopwatch()..start();
    final matrixClients = manager.clients.whereType<MatrixClient>().toList(
      growable: false,
    );
    // Resolved once: the budget is both passed to the catch-up and reported
    // in the log line below, and two copies of the same default can drift.
    final syncBudget = budget ?? const Duration(seconds: 15);
    // Absolute, and fixed here rather than when the release runs: the release
    // is serialised behind any sweep already in progress, and a duration
    // computed at that point would restart the clock the wake is racing.
    final releaseBy = DateTime.now().add(releaseWindowAfter(spent));
    var suspendOutcome = DatabaseSuspendOutcome.nothingToRelease;
    final backupProbeScope = MatrixE2eeBackupProbeScope(
      enabled:
          preferences.isInit &&
          preferences.developerMode.value &&
          route != null,
      budget: syncBudget,
      routeClientId: route?.clientId,
      routeRoomId: route?.roomId,
      routeEventId: route?.eventId,
    );
    // Diagnostic labels only: never include any APNs route value in logs.
    var backupProbeRoute = route == null ? 'absent' : 'unmatched';
    final catchUp = RemoteWakeCatchUp(
      isForeground: () =>
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      resume: () async =>
          releaseTrigger?.resume() ?? DatabaseResumeOutcome.nothingReleased,
      syncAll: () async {
        for (final client in matrixClients) {
          final wakeRoute = route;
          if (wakeRoute != null && wakeRoute.clientId == client.identifier) {
            backupProbeRoute = 'matched';
            await backupProbeScope.recordForRoute(
              clientId: client.identifier,
              roomId: wakeRoute.roomId,
              eventId: wakeRoute.eventId,
              probe: (timeout) =>
                  MatrixE2eeDiagnostics.probePushedEncryptedEvent(
                    client: client.getMatrixClient(),
                    roomId: wakeRoute.roomId,
                    eventId: wakeRoute.eventId,
                    timeout: timeout,
                  ),
            );
          }
          // Cut any long poll the resume restarted, then one short sync so
          // pending to-device traffic is processed and stored.
          await client.matrixClient.abortSync();
          await client.matrixClient.oneShotSync(timeout: _syncLongPoll);
        }
      },
      abortSync: () async {
        for (final client in matrixClients) {
          await client.matrixClient.abortSync();
        }
      },
      suspend: () async {
        suspendOutcome =
            await releaseTrigger?.suspend(quiescenceDeadline: releaseBy) ??
            DatabaseSuspendOutcome.nothingToRelease;
        return suspendOutcome;
      },
      budget: syncBudget,
    );
    RemoteWakeOutcome outcome;
    late MatrixE2eeBackupProbeSummary backupProbeSummary;
    try {
      outcome = await MatrixE2eeDiagnostics.withBackupProbeScope(
        backupProbeScope,
        catchUp.run,
      );
      backupProbeSummary = await backupProbeScope.finish();
    } catch (error) {
      outcome = RemoteWakeOutcome.failed;
      backupProbeSummary = await backupProbeScope.finish();
      Log.w(
        'remote_wake error=${error.runtimeType}',
        category: LogCategory.notifications,
        source: _source,
      );
    }
    if (backupProbeScope.enabled && outcome != RemoteWakeOutcome.foreground) {
      Log.i(
        'backup_probe candidates=${backupProbeSummary.candidates} '
        'in_backup=${backupProbeSummary.inBackup} '
        'not_in_backup=${backupProbeSummary.notInBackup} '
        'version_unusable=${backupProbeSummary.versionUnusable} '
        'skipped_budget=${backupProbeSummary.skippedBudget} '
        'route=$backupProbeRoute',
        category: LogCategory.notifications,
        source: _source,
      );
    }
    Log.i(
      'remote_wake outcome=${outcome.name} clients=${matrixClients.length} '
      'sync_budget_ms=${syncBudget.inMilliseconds} '
      // What native had already spent when Dart began handling the wake, as
      // distinct from what Dart then spent itself. Reported separately
      // because the two are the only way to tell, from the device, whether
      // the handling-time query is reaching the engine boot at all: the
      // budget alone cannot say which half consumed it.
      'native_elapsed_ms=${nativeElapsed.inMilliseconds} '
      // Whether the database actually came back. A wake that caught up and
      // left the file open is not a success, and the outcome above cannot
      // say so on its own.
      'release=${suspendOutcome.name} '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      category: LogCategory.notifications,
      source: _source,
    );
    return outcome;
  }
}
