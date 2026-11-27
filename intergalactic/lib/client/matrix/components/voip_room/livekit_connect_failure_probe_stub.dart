import 'package:intergalactic/client/matrix/components/voip_room/livekit_connect_failure_probe_result.dart';

/// Web has no `SocketException` to unwrap.
int? livekitConnectOsErrorCode(Object error) => null;

/// Web has no `dart:io` resolver to measure, and the failure this probe exists
/// for is a Windows `getaddrinfo` behaviour. Returning null keeps the caller
/// free of platform checks.
Future<LivekitConnectFailureProbeResult?> probeLivekitConnectFailure(
  String host,
) async {
  return null;
}
