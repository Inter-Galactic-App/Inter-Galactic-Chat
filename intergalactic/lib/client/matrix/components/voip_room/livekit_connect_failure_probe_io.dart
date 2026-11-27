import 'dart:io' as io;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_connect_failure_probe_result.dart';

/// Upper bound on the probe. It runs on a failure path that the user is already
/// waiting through, so it must not extend the wait meaningfully. A resolver
/// that has not answered in two seconds has told us what we needed to know.
const _probeTimeout = Duration(seconds: 2);

/// The OS-level error code behind a failed connect, when there is one.
///
/// Lives behind the conditional import so the caller never needs `dart:io`, and
/// so the web build never sees `SocketException`.
int? livekitConnectOsErrorCode(Object error) {
  return error is io.SocketException ? error.osError?.errorCode : null;
}

/// Resolve [host] through the same OS path the failing connect used, and time
/// it.
///
/// This never throws: it is diagnostics on an error path, and a probe that can
/// fail the join it is describing would be worse than no probe.
Future<LivekitConnectFailureProbeResult?> probeLivekitConnectFailure(
  String host,
) async {
  if (host.isEmpty) {
    return null;
  }

  // Started, not awaited. Both halves carry the same [_probeTimeout], so
  // running them back to back spent up to four seconds on a failure path the
  // user is already waiting through - the connectivity read has nothing to do
  // with the resolver and no reason to precede it. Launching both here puts
  // them under one shared deadline.
  final connectivity = _readConnectivity();

  final stopwatch = Stopwatch()..start();
  try {
    final addresses = await io.InternetAddress.lookup(
      host,
    ).timeout(_probeTimeout);
    stopwatch.stop();
    return LivekitConnectFailureProbeResult(
      host: host,
      resolved: addresses.isNotEmpty,
      elapsed: stopwatch.elapsed,
      addresses: addresses.map((a) => a.address).toList(growable: false),
      connectivity: await connectivity,
    );
  } catch (error) {
    stopwatch.stop();
    // `SocketException.osError.errorCode` is the whole point of the probe, and
    // it is lost by `toString()` truncation in the existing log lines.
    final osError = error is io.SocketException ? error.osError : null;
    return LivekitConnectFailureProbeResult(
      host: host,
      resolved: false,
      elapsed: stopwatch.elapsed,
      errorType: error.runtimeType.toString(),
      osErrorCode: osError?.errorCode,
      osErrorMessage: osError?.message,
      connectivity: await connectivity,
    );
  }
}

/// Ask `connectivity_plus` the same question LiveKit asks it.
///
/// `SignalClient.connect` calls `Connectivity().checkConnectivity()` first and
/// throws `ConnectException('no internet connection')` if the answer contains
/// `none` - before any socket is opened. Reading it here, at the moment of
/// failure, is what distinguishes "the network failed" from "the plugin said
/// there is no network". Those look identical in every log we have.
Future<String?> _readConnectivity() async {
  try {
    final results = await Connectivity().checkConnectivity().timeout(
      _probeTimeout,
    );
    return results.map((r) => r.name).join('+');
  } catch (error) {
    return 'read_failed:${error.runtimeType}';
  }
}
