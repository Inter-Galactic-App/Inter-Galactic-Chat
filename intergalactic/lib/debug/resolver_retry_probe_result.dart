import 'dart:async';

/// A deliberately redacted outcome from one diagnostic-only resolver retry.
///
/// The retry host and returned addresses never leave the probe implementation.
/// Callers may log only [outcome] and [elapsed].
class ResolverRetryProbeResult {
  const ResolverRetryProbeResult({
    required this.outcome,
    required this.elapsed,
  });

  final String outcome;
  final Duration elapsed;
}

enum ResolverProbeFamily { ipv4, ipv6 }

class ResolverFamilyProbeResult {
  const ResolverFamilyProbeResult(this.ipv4, this.ipv6);
  final ResolverRetryProbeResult ipv4;
  final ResolverRetryProbeResult ipv6;
}

/// The reporting timeout does not cancel a lookup. Keep the global guard
/// until both raw operations settle, even when their results are discarded.
class ResolverFamilyProbeCoordinator {
  ResolverFamilyProbeCoordinator({
    required Future<ResolverRetryProbeResult> Function(
      String,
      ResolverProbeFamily,
    )
    probe,
    this.timeout = const Duration(seconds: 2),
    this.cooldown = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _probe = probe,
       _now = now ?? DateTime.now;

  final Future<ResolverRetryProbeResult> Function(String, ResolverProbeFamily)
  _probe;
  final DateTime Function() _now;
  final Duration timeout;
  final Duration cooldown;
  final Map<String, DateTime> _lastStarted = {};
  bool _busy = false;

  Future<ResolverFamilyProbeResult>? probe(String host) {
    if (_busy) return null;
    final now = _now();
    final last = _lastStarted[host];
    if (last != null && now.difference(last) < cooldown) return null;
    _busy = true;
    _lastStarted[host] = now;
    Future<ResolverRetryProbeResult> start(ResolverProbeFamily family) =>
        Future<ResolverRetryProbeResult>.sync(() => _probe(host, family)).then(
          (value) => value,
          onError: (Object _, StackTrace __) => const ResolverRetryProbeResult(
            outcome: 'other_error',
            elapsed: Duration.zero,
          ),
        );
    final ipv4 = start(ResolverProbeFamily.ipv4);
    final ipv6 = start(ResolverProbeFamily.ipv6);
    unawaited(
      Future.wait([ipv4, ipv6]).then<void>((_) {
        _busy = false;
      }),
    );
    Future<ResolverRetryProbeResult> bounded(
      Future<ResolverRetryProbeResult> raw,
    ) => raw.timeout(
      timeout,
      onTimeout: () =>
          ResolverRetryProbeResult(outcome: 'timeout', elapsed: timeout),
    );
    return Future.wait([
      bounded(ipv4),
      bounded(ipv6),
    ]).then((results) => ResolverFamilyProbeResult(results[0], results[1]));
  }
}

String resolverFamilyProbeFields(ResolverFamilyProbeResult result) {
  String outcome(ResolverRetryProbeResult value) => switch (value.outcome) {
    'resolved' ||
    'empty' ||
    'nodata' ||
    'socket_error' ||
    'timeout' ||
    'unavailable' => value.outcome,
    _ => 'other_error',
  };
  return ' ipv4_outcome=${outcome(result.ipv4)} ipv4_ms=${result.ipv4.elapsed.inMilliseconds}'
      ' ipv6_outcome=${outcome(result.ipv6)} ipv6_ms=${result.ipv6.elapsed.inMilliseconds}';
}
