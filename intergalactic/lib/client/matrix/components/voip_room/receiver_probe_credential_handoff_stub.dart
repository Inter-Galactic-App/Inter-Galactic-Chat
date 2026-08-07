Future<void> writeReceiverProbeCredentialEnvelope({
  required String controlPipe,
  required Map<String, Object?> envelope,
}) {
  throw UnsupportedError(
    'External receiver probe credential handoff is only supported on native platforms.',
  );
}
