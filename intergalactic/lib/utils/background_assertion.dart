import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/debug/log.dart';

/// Where an assertion is actually held. iOS backs this with
/// `UIApplication.beginBackgroundTask`; every other platform has no equivalent
/// and gets no host, so [BackgroundAssertion.begin] returns an ungranted handle
/// and the caller's work simply runs without one.
abstract class BackgroundAssertionHost {
  /// Returns an opaque token, or null when the OS declined.
  Future<String?> begin(String name);

  Future<void> end(String token);
}

/// One held assertion. Ending twice is harmless; ending an ungranted handle is
/// a no-op. Always end it in a `finally`.
class BackgroundAssertionHandle {
  BackgroundAssertionHandle._(this._host, this.name, this.token);

  final BackgroundAssertionHost? _host;
  final String name;
  final String? token;
  bool _ended = false;

  bool get granted => token != null;

  Future<void> end() async {
    if (_ended) {
      return;
    }
    _ended = true;
    final host = _host;
    final held = token;
    if (host == null || held == null) {
      return;
    }
    try {
      await host.end(held).timeout(BackgroundAssertion.hostTimeout);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to end background assertion',
        category: LogCategory.app,
        source: 'background-assertion',
      );
    }
  }
}

/// Asks the OS for a bounded window of background execution.
///
/// Extracted from the iOS notification-response path (BUG-295), which held a
/// `beginBackgroundTask` so an inline reply could finish after the app was
/// backgrounded. The database release trigger (B5) needs exactly the same
/// thing: the Matrix SDK holds a transaction across sync processing for
/// seconds, and release must wait for it under an assertion rather than let the
/// process suspend holding a lock. Both consume this one primitive so the two
/// cannot drift apart. On the native side both are entries in the same
/// registry (`AppDelegate.swift`, "Background execution assertions").
///
/// This is deliberately a thin, bounded thing: begin, end, and nothing else.
/// It does not decide when to run work, and it does not make the process
/// survive - iOS grants roughly thirty seconds and reclaims the time with an
/// expiry callback, after which the assertion is gone whether or not the work
/// finished. Design for that: keep the work short and treat an expiry as the
/// work not having completed.
class BackgroundAssertion {
  BackgroundAssertion._();

  /// The default host for this platform. Replaceable in tests.
  static BackgroundAssertionHost? host = _defaultHost();

  static BackgroundAssertionHost? _defaultHost() {
    if (kIsWeb) {
      return null;
    }
    return defaultTargetPlatform == TargetPlatform.iOS
        ? const ChannelBackgroundAssertionHost()
        : null;
  }

  /// How long to wait for the host to answer.
  ///
  /// Not a latency budget - a method-channel round trip is sub-millisecond -
  /// but a bound on a wedge. Both calls run on the suspension path inside
  /// `DatabaseReleaseTrigger`'s serialised chain (`begin` before the sweep,
  /// `end` in its `finally`). A platform thread that never answers during a
  /// background transition therefore stops that chain for good: the resume
  /// queued behind it never runs, sync stays stopped and every waiter on
  /// `whenEstablished` blocks for the life of the process. This class already
  /// promises never to throw, so answering "not granted" after a bounded wait
  /// is the same contract, one step further.
  static const Duration hostTimeout = Duration(seconds: 2);

  /// Begins an assertion named [name] (a reverse-DNS style label that shows up
  /// in the native log). Never throws, and never blocks longer than
  /// [hostTimeout]: a declined, failing or unresponsive host yields an
  /// ungranted handle, and the caller proceeds without one.
  static Future<BackgroundAssertionHandle> begin(
    String name, {
    BackgroundAssertionHost? host,
  }) async {
    final target = host ?? BackgroundAssertion.host;
    if (target == null) {
      return BackgroundAssertionHandle._(null, name, null);
    }
    try {
      final pending = target.begin(name);
      final token = await pending.timeout(
        hostTimeout,
        onTimeout: () {
          unawaited(_endLateToken(target, pending));
          return null;
        },
      );
      return BackgroundAssertionHandle._(target, name, token);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to begin background assertion',
        category: LogCategory.app,
        source: 'background-assertion',
      );
      return BackgroundAssertionHandle._(null, name, null);
    }
  }

  /// Ends a token that arrived after [begin] stopped waiting for it.
  ///
  /// Timing out and walking away is not enough on its own: the handle we
  /// returned holds no token, so nothing would ever end this one, and iOS
  /// kills the app when an unended `beginBackgroundTask` expires. Trading a
  /// wedge for a termination is not an improvement.
  static Future<void> _endLateToken(
    BackgroundAssertionHost target,
    Future<String?> pending,
  ) async {
    try {
      // Deliberately unbounded. This wait exists precisely because the host
      // was slower than [hostTimeout], and giving up on it would put the token
      // beyond anyone's reach - which is the termination this method exists to
      // prevent. Nothing is queued behind it: the caller was let go at the
      // timeout.
      final token = await pending;
      if (token != null) {
        // Bounded, unlike the wait above, because once the token is in hand
        // the end has been issued and waiting on the answer buys nothing. An
        // unbounded wait here would retain this cleanup - and the host and
        // token it closes over - for the life of the process, once per
        // timed-out acquisition. The timeout lands in the catch below and is
        // reported like any other failure to end.
        await target.end(token).timeout(hostTimeout);
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to end a late background assertion',
        category: LogCategory.app,
        source: 'background-assertion',
      );
    }
  }

  /// Runs [_endLateToken] so a test can assert that it completes.
  ///
  /// Its production call site is `unawaited` - it has to be, the caller has
  /// already been let go - so nothing else can observe whether that future
  /// ever finishes, which is the whole property being guarded.
  @visibleForTesting
  static Future<void> debugEndLateTokenForTesting(
    BackgroundAssertionHost target,
    Future<String?> pending,
  ) => _endLateToken(target, pending);
}

/// The iOS bridge. `begin` answers with the registry token, or null when
/// `beginBackgroundTask` returned `.invalid`.
class ChannelBackgroundAssertionHost implements BackgroundAssertionHost {
  const ChannelBackgroundAssertionHost();

  static const MethodChannel channel = MethodChannel(
    'chat.intergalactic.app/background_assertion',
  );

  @override
  Future<String?> begin(String name) =>
      channel.invokeMethod<String>('begin', {'name': name});

  @override
  Future<void> end(String token) =>
      channel.invokeMethod<void>('end', {'token': token});
}
