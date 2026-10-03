import 'package:intergalactic/debug/resolver_native_probe_result.dart';

Future<NativeResolverProbeResult> probeNativeResolver(String host) async {
  return const NativeResolverProbeResult(
    outcome: 'unavailable',
    elapsed: Duration.zero,
  );
}
