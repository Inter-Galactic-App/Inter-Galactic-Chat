import 'dart:async';

/// A redacted result from a Windows native resolver diagnostic.
///
/// [errorCode] is the numeric Winsock/GetAddrInfoW result only. Hosts and
/// returned addresses stay inside the probe implementation.
class NativeResolverProbeResult {
  const NativeResolverProbeResult({
    required this.outcome,
    required this.elapsed,
    this.errorCode,
  });

  final String outcome;
  final Duration elapsed;
  final int? errorCode;
}

/// Shares a native lookup that is still running after a caller's bounded wait.
/// A timeout is diagnostic evidence, not permission to start another native
/// lookup for the same host while the first one remains in flight.
class NativeResolverProbeCoordinator {
  NativeResolverProbeCoordinator({
    required Future<NativeResolverProbeResult> Function(String host) probe,
    required Duration timeout,
  }) : _probe = probe,
       _timeout = timeout;

  final Future<NativeResolverProbeResult> Function(String host) _probe;
  final Duration _timeout;
  final Map<String, Future<NativeResolverProbeResult>> _inFlight = {};

  Future<NativeResolverProbeResult> probe(String host) {
    final active = _inFlight[host];
    if (active != null) {
      return _awaitBounded(active);
    }

    final started = _probe(host);
    _inFlight[host] = started;
    unawaited(
      started.whenComplete(() {
        if (identical(_inFlight[host], started)) {
          _inFlight.remove(host);
        }
      }),
    );
    return _awaitBounded(started);
  }

  Future<NativeResolverProbeResult> _awaitBounded(
    Future<NativeResolverProbeResult> probe,
  ) {
    return probe.timeout(
      _timeout,
      onTimeout: () =>
          NativeResolverProbeResult(outcome: 'timeout', elapsed: _timeout),
    );
  }
}
