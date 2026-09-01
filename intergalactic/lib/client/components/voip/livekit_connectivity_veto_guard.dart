import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';

import 'livekit_connectivity_veto_guard_platform.dart';

/// Stops a false "there is no network" verdict from permanently disabling
/// calling.
///
/// **The defect this exists for (BUG-296, confirmed 2026-08-17).** LiveKit's
/// `SignalClient.connect` asks `connectivity_plus` before it does anything else,
/// and throws `ConnectException('no internet connection')` when the answer
/// contains [ConnectivityResult.none] - before opening a socket, resolving a
/// name, or contacting the SFU. On Windows that answer comes from a single
/// `INetworkListManager` COM object created once at plugin registration and held
/// for the life of the process, so once it is wrong it stays wrong and **only an
/// app restart restores calling**.
///
/// It was measured wrong. In the confirming capture the plugin reported `none`
/// while the same process resolved the SFU host to four addresses in six
/// milliseconds, after four successful join/leave cycles:
///
/// ```text
/// livekit_connect_attempt_failed attempt=3/3 error_type=ConnectException
///   os_error=none probe_connectivity=none probe_resolved=true
///   probe_address_count=4 probe_ms=6
/// ```
///
/// **What this guard does.** It treats `none` as *unproven* rather than
/// authoritative, and overrides it only when the machine demonstrably has a
/// usable address. Every other verdict is passed through untouched.
///
/// **What it deliberately gives up.** When the device is genuinely offline, the
/// join now proceeds and fails on a real socket error instead of being refused
/// up front. That is a worse error path and a better outcome: the retry policy
/// and the failure toast already handle a real network failure, and a real
/// failure recovers on its own once the network returns. A false `none` does
/// not - it bricks calling until the process exits.
class LivekitConnectivityVetoGuard extends ConnectivityPlatform {
  LivekitConnectivityVetoGuard(this._delegate, {NetworkAddressProbe? probe})
    : _probe = probe ?? defaultNetworkAddressProbe;

  /// Installs the guard over whatever platform implementation is registered.
  ///
  /// Windows-only by default. The bug is a Windows COM-lifetime problem, and on
  /// mobile a `none` verdict is both trustworthy and load-bearing - it is how
  /// the OS reports a genuinely absent radio, and overriding it there would
  /// trade a real signal for no benefit.
  ///
  /// Returns whether the guard was installed, so startup can log it. Safe to
  /// call more than once; a second call is a no-op rather than a stack of
  /// guards, which would multiply the probe cost per query.
  ///
  /// The host check comes from a conditional import rather than `dart:io`:
  /// `main.dart` imports this library unconditionally, so a `dart:io` import
  /// here fails the web compile outright, long before `Platform.isWindows`
  /// would ever be evaluated.
  static bool installIfSupported({bool? isWindowsOverride}) {
    final isWindows = isWindowsOverride ?? isWindowsHost;
    if (!isWindows) {
      return false;
    }

    final current = ConnectivityPlatform.instance;
    if (current is LivekitConnectivityVetoGuard) {
      return false;
    }

    ConnectivityPlatform.instance = LivekitConnectivityVetoGuard(current);
    return true;
  }

  final ConnectivityPlatform _delegate;
  final NetworkAddressProbe _probe;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    final reported = await _delegate.checkConnectivity();
    return _correct(reported);
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _delegate.onConnectivityChanged.asyncMap(_correct);
  }

  /// Passes everything through except an unsupported `none`.
  Future<List<ConnectivityResult>> _correct(
    List<ConnectivityResult> reported,
  ) async {
    if (!reported.contains(ConnectivityResult.none)) {
      return reported;
    }

    if (!await _probe()) {
      return reported;
    }

    // Deliberately `other` rather than guessing ethernet or wifi. The only claim
    // this guard can support is "a usable address exists"; naming a transport
    // would be inventing detail it did not measure.
    return const <ConnectivityResult>[ConnectivityResult.other];
  }
}

/// Answers "does this machine hold a usable address right now?".
typedef NetworkAddressProbe = Future<bool> Function();
