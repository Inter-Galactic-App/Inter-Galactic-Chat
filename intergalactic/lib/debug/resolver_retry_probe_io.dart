import 'dart:async';
import 'dart:io' as io;

import 'package:intergalactic/debug/resolver_retry_probe_result.dart';

const _probeTimeout = Duration(seconds: 2);
final _familyCoordinator = ResolverFamilyProbeCoordinator(probe: _probeFamily);

Future<ResolverFamilyProbeResult>? probeResolverFamilies(String host) =>
    io.Platform.isWindows ? _familyCoordinator.probe(host) : null;

Future<ResolverRetryProbeResult> _probeFamily(
  String host,
  ResolverProbeFamily family,
) => _lookup(
  host,
  type: family == ResolverProbeFamily.ipv4
      ? io.InternetAddressType.IPv4
      : io.InternetAddressType.IPv6,
);

/// Repeats a lookup from the Flutter process without affecting the failed
/// request. The result intentionally carries no host, address, or OS message.
Future<ResolverRetryProbeResult> probeResolverRetry(String host) async {
  return _lookup(host).timeout(
    _probeTimeout,
    onTimeout: () => const ResolverRetryProbeResult(
      outcome: 'timeout',
      elapsed: _probeTimeout,
    ),
  );
}

Future<ResolverRetryProbeResult> _lookup(
  String host, {
  io.InternetAddressType type = io.InternetAddressType.any,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final addresses = await io.InternetAddress.lookup(host, type: type);
    stopwatch.stop();
    return ResolverRetryProbeResult(
      outcome: addresses.isEmpty ? 'empty' : 'resolved',
      elapsed: stopwatch.elapsed,
    );
  } on TimeoutException {
    stopwatch.stop();
    return ResolverRetryProbeResult(
      outcome: 'timeout',
      elapsed: stopwatch.elapsed,
    );
  } on io.SocketException catch (error) {
    stopwatch.stop();
    return ResolverRetryProbeResult(
      outcome: error.osError?.errorCode == 11004 ? 'nodata' : 'socket_error',
      elapsed: stopwatch.elapsed,
    );
  } catch (_) {
    stopwatch.stop();
    return ResolverRetryProbeResult(
      outcome: 'other_error',
      elapsed: stopwatch.elapsed,
    );
  }
}
