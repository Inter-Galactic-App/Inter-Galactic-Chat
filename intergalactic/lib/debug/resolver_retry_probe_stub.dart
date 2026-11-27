import 'package:intergalactic/debug/resolver_retry_probe_result.dart';

Future<ResolverFamilyProbeResult>? probeResolverFamilies(String host) => null;

/// Web has no dart:io resolver to retry.
Future<ResolverRetryProbeResult> probeResolverRetry(String host) async {
  return const ResolverRetryProbeResult(
    outcome: 'unavailable',
    elapsed: Duration.zero,
  );
}
