/// One measurement taken at the moment a LiveKit connect attempt failed.
///
/// The point of this type is to answer a question the logs could not: when a
/// join fails, is name resolution working *right then*, from inside this
/// process? Every prior investigation had to infer that from outside the app,
/// which measures a different thing - `Resolve-DnsName` queries a chosen server
/// directly, while the app goes through `getaddrinfo` and therefore through the
/// Windows DNS client cache and its multi-homed interface race. An external
/// check succeeding told us nothing about the app's own resolver path, and was
/// twice read as if it had.
class LivekitConnectFailureProbeResult {
  const LivekitConnectFailureProbeResult({
    required this.host,
    required this.resolved,
    required this.elapsed,
    this.addresses = const <String>[],
    this.errorType,
    this.osErrorCode,
    this.osErrorMessage,
    this.connectivity,
  });

  final String host;
  final bool resolved;
  final Duration elapsed;
  final List<String> addresses;
  final String? errorType;

  /// What `connectivity_plus` claims about the network at the moment of
  /// failure, verbatim.
  ///
  /// This is the highest-value field here, because LiveKit's `SignalClient`
  /// refuses to connect **at all** when this reports `none` - it throws
  /// `ConnectException('no internet connection')` from `signal_client.dart:117`
  /// before opening a socket, resolving a name, or contacting the SFU. A
  /// captured stack trace put the lockout on exactly that line. On Windows the
  /// plugin answers from a single `INetworkListManager` COM object created once
  /// per process, so a wrong verdict there persists for the life of the process
  /// - which is precisely the "only a restart fixes it" symptom.
  final String? connectivity;

  /// The OS-level code, which is the field that actually identifies the
  /// failure. On Windows `11004` is `WSANO_DATA` ("name is valid, but no data
  /// of the requested type") - a *negative answer*, not an unreachable network.
  final int? osErrorCode;
  final String? osErrorMessage;

  /// A resolution that returns in under this long did not reach a DNS server;
  /// it came from the OS cache. Measured on the affected machine: a cold lookup
  /// takes ~9 ms and a warm one ~0 ms, while the failures seen during lockout
  /// land at 13-22 ms. Treat it as a hint in the log line, not a verdict.
  static const cacheHitCeiling = Duration(milliseconds: 30);

  bool get looksCached => elapsed < cacheHitCeiling;

  String toLogFields() {
    final buffer = StringBuffer()
      ..write('probe_connectivity=${connectivity ?? "unknown"} ')
      ..write('probe_resolved=$resolved ')
      ..write('probe_ms=${elapsed.inMilliseconds} ')
      ..write('probe_likely_cached=$looksCached');

    if (resolved) {
      buffer.write(' probe_address_count=${addresses.length}');
    } else {
      buffer
        ..write(' probe_error_type=$errorType')
        ..write(' probe_os_error=${osErrorCode ?? "none"}');
      if (osErrorMessage != null) {
        buffer.write(' probe_os_message_present=true');
      }
    }

    return buffer.toString();
  }
}

/// Formats only the safe, structural facts of a LiveKit connection failure.
///
/// These fields feed developer logs and bug reports, so endpoint names,
/// resolved addresses, and exception text are deliberately omitted. The
/// probe's resolution result, timing, OS error code, and error type retain the
/// information needed to distinguish a DNS, connectivity, or transport fault.
String formatLivekitConnectFailureLogFields({
  required Object error,
  required int attempt,
  required int maxAttempts,
  required bool classifiedTransient,
  required int? osErrorCode,
  LivekitConnectFailureProbeResult? probe,
}) {
  final fields = StringBuffer()
    ..write('livekit_connect_attempt_failed ')
    ..write('attempt=$attempt/$maxAttempts ')
    ..write('error_type=${error.runtimeType} ')
    ..write('classified_transient=$classifiedTransient ')
    ..write('os_error=${osErrorCode ?? "none"} ')
    ..write('error_message=redacted');

  if (probe != null) {
    fields.write(' ${probe.toLogFields()}');
  }

  return fields.toString();
}
