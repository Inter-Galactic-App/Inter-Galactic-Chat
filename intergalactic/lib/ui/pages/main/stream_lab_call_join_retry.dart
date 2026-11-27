bool shouldRetryStreamLabTrustPreflight({
  required bool encryptionAvailable,
  required bool currentDeviceKnown,
  required bool? currentDeviceBlocked,
}) =>
    encryptionAvailable && !currentDeviceKnown && currentDeviceBlocked != true;
