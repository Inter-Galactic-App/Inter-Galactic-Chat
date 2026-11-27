import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:matrix/encryption.dart' as matrix_crypto;
import 'package:matrix/matrix.dart' as matrix;

const matrixSharedHistoryFlag = 'org.matrix.msc3061.shared_history';
const matrixRoomKeyBundleEventType = 'io.element.msc4268.room_key_bundle';

const _matrixRoomKeyBundleVersion =
    'chat.intergalactic.msc4268.room_key_bundle.v1';
const _pendingBundleLifetime = Duration(minutes: 10);
const _maxEncryptedBundleBytes = 5 * 1024 * 1024;
const _maxBundleSessions = 5000;
const _encryptedBundleDownloadTimeout = Duration(seconds: 20);
const _autoSharedRequestMemoryLimit = 256;

String _matrixHistoryLogHash(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return 'none';
  }
  return MatrixClient.hash(text).substring(0, 12);
}

String _matrixHistoryLogHashes(Iterable<Object?> values) {
  final hashes = values.map(_matrixHistoryLogHash).toList();
  if (hashes.isEmpty) {
    return 'none';
  }
  return hashes.join(', ');
}

String _matrixHistoryLogError(Object error) => error.runtimeType.toString();

bool matrixHistoryVisibilityAllowsInviteSharing(
  matrix.HistoryVisibility? visibility,
) {
  return visibility == matrix.HistoryVisibility.shared ||
      visibility == matrix.HistoryVisibility.worldReadable;
}

bool matrixHistorySessionPayloadIsShareable(Map<String, dynamic> payload) {
  return payload[matrixSharedHistoryFlag] == true ||
      payload['shared_history'] == true;
}

bool matrixHistoryDeviceEligibleForKeyShare(matrix.DeviceKeys device) {
  return device.deviceId != null && !device.blocked && device.encryptToDevice;
}

bool matrixHistoryBundleDeclaredFileSizesAreSafe(Map<String, dynamic> file) {
  final plaintextSize = _nonNegativeIntValue(file['size']);
  final encryptedSize = _nonNegativeIntValue(file['encrypted_size']);
  return plaintextSize != null &&
      encryptedSize != null &&
      plaintextSize <= _maxEncryptedBundleBytes &&
      encryptedSize <= _maxEncryptedBundleBytes;
}

bool matrixHistoryShouldImportLatePendingBundle({
  required bool roomIsJoined,
  required bool acceptedInviteKnown,
  required String? acceptedInviterUserId,
  required String bundleSenderUserId,
}) {
  if (!roomIsJoined) {
    return false;
  }
  if (!acceptedInviteKnown || acceptedInviterUserId == null) {
    return true;
  }
  return acceptedInviterUserId == bundleSenderUserId;
}

String? matrixHistoryAutoKeyShareSkipReason({
  required bool requestCanceled,
  required bool requesterIsSelf,
  required bool roomIsE2EE,
  required bool visibilityAllowsSharing,
  required bool requesterIsJoined,
  required bool deviceEligible,
}) {
  if (requestCanceled) {
    return 'request_canceled';
  }
  if (requesterIsSelf) {
    return 'requester_is_self';
  }
  if (!roomIsE2EE) {
    return 'room_not_e2ee';
  }
  if (!visibilityAllowsSharing) {
    return 'history_visibility_not_shared';
  }
  if (!requesterIsJoined) {
    return 'requester_not_joined';
  }
  if (!deviceEligible) {
    return 'requesting_device_not_eligible';
  }
  return null;
}

bool matrixHistoryShouldAutoShareRequestedKey({
  required bool requestCanceled,
  required bool requesterIsSelf,
  required bool roomIsE2EE,
  required bool visibilityAllowsSharing,
  required bool requesterIsJoined,
  required bool deviceEligible,
}) {
  return matrixHistoryAutoKeyShareSkipReason(
        requestCanceled: requestCanceled,
        requesterIsSelf: requesterIsSelf,
        roomIsE2EE: roomIsE2EE,
        visibilityAllowsSharing: visibilityAllowsSharing,
        requesterIsJoined: requesterIsJoined,
        deviceEligible: deviceEligible,
      ) ==
      null;
}

String _matrixHistoryAutoKeyShareRequestKey({
  required String requesterUserId,
  required String requesterDeviceId,
  required String roomId,
  required String sessionId,
  required String requestId,
}) {
  return <String>[
    requesterUserId,
    requesterDeviceId,
    roomId,
    sessionId,
    requestId,
  ].join('\u0000');
}

/// What a key-request response did.
///
/// A `bool` could not carry the difference between "we declined this" and "we
/// could not act yet", and the interactive break-glass path is the caller that
/// needs it: the user has already approved an ineligible device by the time
/// the response is attempted, so a deferral that reads as a refusal spends a
/// consent and shows nothing.
enum MatrixKeyRequestOutcome {
  /// The forwarded key was dispatched.
  fulfilled,

  /// Declined on policy, or the session is not available here. Retrying with
  /// the same inputs would decline again.
  refused,

  /// Not attempted, because the encryption store was released and did not
  /// come back. The same request can succeed later, so callers must not treat
  /// it as an answer.
  deferred,
}

class MatrixHistoryShareReport {
  MatrixHistoryShareReport({required this.targetUserIds});

  final List<String> targetUserIds;
  final List<String> usersWithEligibleDevices = <String>[];
  final List<String> usersWithoutEligibleDevices = <String>[];
  final List<String> skippedSessionIds = <String>[];
  final List<String> withheldSessionIds = <String>[];
  final List<String> failures = <String>[];
  final Set<String> _sharedSessionIds = <String>{};

  int availableSessionCount = 0;
  int loadedSessionCount = 0;
  int eligibleDeviceCount = 0;
  int ineligibleDeviceCount = 0;
  int verifiedDeviceCount = 0;
  int unverifiedDeviceCount = 0;
  int sharedDeviceDeliveries = 0;
  int bundleCount = 0;
  int bundleImportedSessionCount = 0;
  int ineligibleRequestsIgnored = 0;
  int blockedRequestsIgnored = 0;

  /// Requests that could not be answered because the encryption store was
  /// released. Counted separately from the ignored ones: those are decisions,
  /// this is a deferral, and a reader who cannot tell them apart will conclude
  /// the device was refused.
  int deferredRequests = 0;

  bool get hasFailures => failures.isNotEmpty;

  int get sharedSessionCount => _sharedSessionIds.length;

  void markSessionShared(String sessionId) {
    _sharedSessionIds.add(sessionId);
  }

  String toMultilineString() {
    final lines = <String>[
      "History sharing complete for ${targetUserIds.length} user(s).",
      "",
      "-- Targets ----------------------------------",
      "Users targeted:              ${targetUserIds.join(', ')}",
      "Users with eligible devices: ${usersWithEligibleDevices.isEmpty ? 'None' : usersWithEligibleDevices.join(', ')}",
      "Users with no eligible devices: ${usersWithoutEligibleDevices.isEmpty ? 'None' : usersWithoutEligibleDevices.join(', ')}",
      "Policy-eligible devices:     $eligibleDeviceCount",
      "Policy-ineligible devices:   $ineligibleDeviceCount",
      "Verified devices seen:       $verifiedDeviceCount",
      "Unverified devices seen:     $unverifiedDeviceCount",
      "",
      "-- Sessions ---------------------------------",
      "Sessions in DB:              $availableSessionCount",
      "Sessions loaded:             $loadedSessionCount",
      "Sessions sent/imported:      $sharedSessionCount",
      "Withheld records:            ${withheldSessionIds.length}",
      "Skipped (failed to load):    ${skippedSessionIds.length}",
      "",
      "-- Delivery ---------------------------------",
      "To-device sends dispatched:  $sharedDeviceDeliveries",
      "Bundles sent:                $bundleCount",
      "Ineligible requests ignored: $ineligibleRequestsIgnored",
      "Blocked requests ignored:    $blockedRequestsIgnored",
      "Deferred (storage resuming): $deferredRequests",
    ];

    if (failures.isNotEmpty) {
      lines.add("");
      lines.add("-- Issues -----------------------------------");
      lines.addAll(failures.map((failure) => "- $failure"));
    }

    if (deferredRequests > 0) {
      lines.add("");
      lines.add(
        "NOTE: $deferredRequests request(s) arrived while encryption storage "
        "was resuming and were not answered. Nothing was refused - ask the "
        "target to request the keys again.",
      );
    }

    if (usersWithoutEligibleDevices.isNotEmpty) {
      lines.add("");
      lines.add(
        "NOTE: Users with no devices eligible under your key-sharing "
        "policy will not receive automatic history.",
      );
    }

    if (sharedDeviceDeliveries > 0 && sharedSessionCount > 0) {
      lines.add("");
      lines.add(
        "Keys were dispatched to eligible devices. If the target "
        "still cannot decrypt, ask them to open an undecryptable message "
        "and re-request encryption keys, then run /sharehistory again.",
      );
    }

    return lines.join('\n');
  }
}

class MatrixHistorySharePreview {
  MatrixHistorySharePreview({
    required this.report,
    required this.eligibleDevices,
    required this.ineligibleDevices,
  });

  final MatrixHistoryShareReport report;
  final List<matrix.DeviceKeys> eligibleDevices;
  final List<matrix.DeviceKeys> ineligibleDevices;
}

class MatrixHistoryShareTargetResolution {
  const MatrixHistoryShareTargetResolution({
    required this.targetUserIds,
    this.issue,
    this.inferredSingleTarget = false,
  });

  final List<String> targetUserIds;
  final String? issue;
  final bool inferredSingleTarget;

  bool get canProceed => issue == null && targetUserIds.isNotEmpty;
}

MatrixHistoryShareTargetResolution matrixHistoryResolveShareTargets({
  required Iterable<String> explicitTargetUserIds,
  required Iterable<String> joinedUserIds,
  required String? selfUserId,
}) {
  const usage = 'Usage: /sharehistory @user:server [@user2:server ...]';
  final joined = joinedUserIds.toSet();
  final explicit =
      explicitTargetUserIds
          .where((userId) => userId.trim().isNotEmpty)
          .map((userId) => userId.trim())
          .toSet()
          .toList()
        ..sort();

  if (explicit.isEmpty) {
    final candidates = joined.where((userId) => userId != selfUserId).toList()
      ..sort();
    if (candidates.length == 1) {
      return MatrixHistoryShareTargetResolution(
        targetUserIds: candidates,
        inferredSingleTarget: true,
      );
    }

    if (candidates.isEmpty) {
      return const MatrixHistoryShareTargetResolution(
        targetUserIds: <String>[],
        issue: '$usage\n\nNo other joined members were found in this room.',
      );
    }

    return MatrixHistoryShareTargetResolution(
      targetUserIds: const <String>[],
      issue:
          '$usage\n\nI found ${candidates.length} other joined members. '
          'Add the full Matrix user ID for each member you want to help.',
    );
  }

  final invalidTargets = explicit
      .where((userId) => !userId.isValidMatrixId)
      .toList();
  if (invalidTargets.isNotEmpty) {
    return MatrixHistoryShareTargetResolution(
      targetUserIds: const <String>[],
      issue:
          'These targets are not full Matrix user IDs: '
          '${invalidTargets.join(', ')}\n\n$usage',
    );
  }

  final missingUsers = explicit
      .where((userId) => !joined.contains(userId))
      .toList();
  if (missingUsers.isNotEmpty) {
    return MatrixHistoryShareTargetResolution(
      targetUserIds: const <String>[],
      issue:
          'These users are not currently joined to the room: '
          '${missingUsers.join(', ')}\n\nIf they just joined, wait for the '
          'member list to sync and try again.',
    );
  }

  return MatrixHistoryShareTargetResolution(targetUserIds: explicit);
}

class MatrixHistoryBundleImportReport {
  MatrixHistoryBundleImportReport({required this.roomId});

  final String roomId;
  int pendingBundleCount = 0;
  int importedBundleCount = 0;
  int importedSessionCount = 0;
  int expiredBundleCount = 0;
  int rejectedBundleCount = 0;
  final List<String> failures = <String>[];

  bool get didImport => importedSessionCount > 0;
  bool get hadPendingBundle => pendingBundleCount > 0;
  bool get hasFailures => failures.isNotEmpty || rejectedBundleCount > 0;

  String summaryForUser() {
    if (didImport) {
      return "Shared encrypted history was imported for this room.";
    }
    if (expiredBundleCount > 0) {
      return "A shared encrypted history bundle expired before it could be imported.";
    }
    if (hasFailures) {
      return "A shared encrypted history bundle was rejected or could not be imported.";
    }
    if (!hadPendingBundle) {
      return "No shared encrypted history bundle was available for this invite.";
    }
    return "No shared encrypted history was imported.";
  }
}

extension MatrixHistorySharing on MatrixClient {
  Future<List<dynamic>> getInboundGroupSessionsForRoom(String roomId) async {
    final sessions = await matrixClient.database.getAllInboundGroupSessions();
    return sessions.where((session) => session.roomId == roomId).toList();
  }

  Future<MatrixHistorySharePreview> previewHistoryShare(
    MatrixRoom room,
    List<String> targetUserIds,
  ) async {
    Log.i(
      "historySharePreview: room=${_matrixHistoryLogHash(room.identifier)} "
      "targets=${targetUserIds.length} "
      "target_hashes=${_matrixHistoryLogHashes(targetUserIds)}",
    );

    final encryption = matrixClient.encryption;
    if (encryption == null || !matrixClient.encryptionEnabled) {
      throw StateError("Encryption is not available for this account.");
    }

    await matrixClient.updateUserDeviceKeys(
      additionalUsers: targetUserIds.toSet(),
    );

    final report = MatrixHistoryShareReport(targetUserIds: targetUserIds);
    final eligibleDevices = <matrix.DeviceKeys>[];
    final ineligibleDevices = <matrix.DeviceKeys>[];

    for (final userId in targetUserIds) {
      final devices = _knownTargetDevicesForUser(matrixClient, userId);
      final verified = devices.where((device) => device.verified).toList();
      final unverified = devices
          .where((device) => !device.verified)
          .toList(growable: false);
      final eligible = devices
          .where(matrixHistoryDeviceEligibleForKeyShare)
          .toList(growable: false);
      final ineligible = devices
          .where((device) => !matrixHistoryDeviceEligibleForKeyShare(device))
          .toList(growable: false);

      eligibleDevices.addAll(eligible);
      ineligibleDevices.addAll(ineligible);
      report.eligibleDeviceCount += eligible.length;
      report.ineligibleDeviceCount += ineligible.length;
      report.unverifiedDeviceCount += unverified.length;
      report.verifiedDeviceCount += verified.length;

      if (eligible.isEmpty) {
        report.usersWithoutEligibleDevices.add(userId);
      } else {
        report.usersWithEligibleDevices.add(userId);
      }
    }

    Log.i(
      "historySharePreview: devices room=${_matrixHistoryLogHash(room.identifier)} "
      "targets=${targetUserIds.length} known=${eligibleDevices.length + ineligibleDevices.length} "
      "eligible=${eligibleDevices.length} ineligible=${ineligibleDevices.length} "
      "verified=${report.verifiedDeviceCount} unverified=${report.unverifiedDeviceCount} "
      "without_eligible=${report.usersWithoutEligibleDevices.length}",
    );

    final storedSessions = await getInboundGroupSessionsForRoom(
      room.identifier,
    );
    report.availableSessionCount = storedSessions.length;

    return MatrixHistorySharePreview(
      report: report,
      eligibleDevices: eligibleDevices,
      ineligibleDevices: ineligibleDevices,
    );
  }

  Future<MatrixHistoryShareReport> shareHistoryBundleForInvite(
    MatrixRoom room,
    String targetUserId,
  ) async {
    final preview = await previewHistoryShare(room, <String>[targetUserId]);
    final report = preview.report;

    if (!matrixHistoryVisibilityAllowsInviteSharing(
      room.matrixRoom.historyVisibility,
    )) {
      Log.i(
        "shareHistoryBundleForInvite: skipped room=${_matrixHistoryLogHash(room.identifier)} "
        "visibility=${room.matrixRoom.historyVisibility?.text ?? 'unknown'}",
      );
      return report;
    }

    if (preview.eligibleDevices.isEmpty) {
      Log.i(
        "shareHistoryBundleForInvite: no eligible target devices "
        "room=${_matrixHistoryLogHash(room.identifier)} "
        "target=${_matrixHistoryLogHash(targetUserId)}",
      );
      return report;
    }

    final bundle = await _buildRoomKeyBundle(room, report);
    if (bundle.sessions.isEmpty && bundle.withheld.isEmpty) {
      Log.i(
        "shareHistoryBundleForInvite: no locally available sessions "
        "room=${_matrixHistoryLogHash(room.identifier)}",
      );
      return report;
    }

    final encrypted = await matrix.encryptFile(bundle.encodedBytes);
    final mxc = await matrixClient.uploadContent(
      encrypted.data,
      filename: 'room-key-bundle.json',
      contentType: 'application/octet-stream',
    );

    await matrixClient.sendToDeviceEncrypted(
      List<matrix.DeviceKeys>.from(preview.eligibleDevices),
      matrixRoomKeyBundleEventType,
      _bundleToDeviceContent(
        roomId: room.identifier,
        encrypted: encrypted,
        mxc: mxc,
        plaintextSize: bundle.encodedBytes.length,
        encryptedSize: encrypted.data.length,
        sessionCount: bundle.sessions.length,
        withheldCount: bundle.withheld.length,
      ),
      onlyVerified: false,
    );

    report.bundleCount += 1;
    report.sharedDeviceDeliveries += preview.eligibleDevices.length;
    for (final session in bundle.sessions) {
      report.markSessionShared(session['session_id'] as String);
    }

    Log.i(
      "shareHistoryBundleForInvite: sent bundle "
      "room=${_matrixHistoryLogHash(room.identifier)} "
      "target=${_matrixHistoryLogHash(targetUserId)} "
      "devices=${preview.eligibleDevices.length} "
      "sessions=${bundle.sessions.length} "
      "withheld=${bundle.withheld.length}",
    );

    return report;
  }

  Future<MatrixKeyRequestOutcome> respondToRoomKeyRequest(
    MatrixRoom room,
    matrix_crypto.RoomKeyRequest request,
    MatrixHistoryShareReport report, {
    required bool allowIneligibleDevice,
  }) async {
    final encryption = matrixClient.encryption;
    if (encryption == null || !matrixClient.encryptionEnabled) {
      return MatrixKeyRequestOutcome.refused;
    }

    if (request.request.canceled) {
      return MatrixKeyRequestOutcome.refused;
    }

    if (!report.targetUserIds.contains(request.sender)) {
      return MatrixKeyRequestOutcome.refused;
    }

    if (request.room.id != room.identifier) {
      return MatrixKeyRequestOutcome.refused;
    }

    final device = request.requestingDevice;
    if (device.blocked) {
      report.blockedRequestsIgnored += 1;
      Log.w(
        "respondToRoomKeyRequest: ignored blocked device "
        "room=${_matrixHistoryLogHash(room.identifier)} "
        "user=${_matrixHistoryLogHash(device.userId)} "
        "device=${_matrixHistoryLogHash(device.deviceId)}",
      );
      return MatrixKeyRequestOutcome.refused;
    }

    final eligibleDevice = matrixHistoryDeviceEligibleForKeyShare(device);
    if (!eligibleDevice && !allowIneligibleDevice) {
      report.ineligibleRequestsIgnored += 1;
      Log.w(
        "respondToRoomKeyRequest: ignored ineligible device "
        "room=${_matrixHistoryLogHash(room.identifier)} "
        "user=${_matrixHistoryLogHash(device.userId)} "
        "device=${_matrixHistoryLogHash(device.deviceId)}",
      );
      return MatrixKeyRequestOutcome.refused;
    }

    final sessionId = request.request.sessionId;

    // Same gate the presence reads use, for the same reason. An inbound key
    // request served just after a database release reaches
    // loadInboundGroupSession on a released connection, which throws by
    // design - 76 times in each of two phone logs on builds with no wake
    // code, so this predates the release trigger and is only made more
    // frequent by it. Deferring here rather than throwing lets the caller
    // report it and the requester retry.
    //
    // TIMING, because the name suggests otherwise: `waitForDatabase` does not
    // answer false the moment a database is released. It WAITS, and answers
    // false only when a resume fails under it - and a failed resume re-arms
    // the gate, so a caller that starts after the failure waits for the
    // following resume. A request arriving mid-suspension therefore blocks
    // here until the store comes back, which is what we want on this path:
    // the answer is worth more late than never, and the caller is already
    // async.
    if (!await DatabaseReleaseTrigger.waitForDatabase('key_request.respond')) {
      Log.w(
        "respondToRoomKeyRequest: deferred, database unavailable "
        "room=${_matrixHistoryLogHash(room.identifier)} "
        "session=${_matrixHistoryLogHash(sessionId)}",
      );
      report.deferredRequests += 1;
      // DEFERRED, not refused. Nothing was decided about this device: the
      // store was released and did not come back in time, and the same
      // request can be answered later.
      return MatrixKeyRequestOutcome.deferred;
    }

    final session = await encryption.keyManager.loadInboundGroupSession(
      room.identifier,
      sessionId,
    );

    if (session?.inboundGroupSession == null) {
      Log.w(
        "respondToRoomKeyRequest: session=${_matrixHistoryLogHash(sessionId)} "
        "not available locally",
      );
      return MatrixKeyRequestOutcome.refused;
    }

    final payload = _buildForwardedRoomKeyPayload(encryption, session!);

    try {
      await matrixClient.sendToDeviceEncrypted(
        <matrix.DeviceKeys>[device],
        matrix.EventTypes.ForwardedRoomKey,
        Map<String, dynamic>.from(payload),
        onlyVerified: false,
      );
      report.sharedDeviceDeliveries += 1;
      report.markSessionShared(sessionId);
      Log.i(
        "respondToRoomKeyRequest: fulfilled "
        "room=${_matrixHistoryLogHash(room.identifier)} "
        "session=${_matrixHistoryLogHash(sessionId)} "
        "user=${_matrixHistoryLogHash(device.userId)} "
        "device=${_matrixHistoryLogHash(device.deviceId)} "
        "eligible=$eligibleDevice "
        "verified=${device.verified}",
      );
      return MatrixKeyRequestOutcome.fulfilled;
    } catch (error, stack) {
      final msg =
          "Failed to fulfil key request "
          "session=${_matrixHistoryLogHash(sessionId)} "
          "user=${_matrixHistoryLogHash(device.userId)} "
          "error=${_matrixHistoryLogError(error)}";
      report.failures.add(msg);
      Log.onError(error, stack, content: "respondToRoomKeyRequest: $msg");
      return MatrixKeyRequestOutcome.refused;
    }
  }

  Future<MatrixHistoryShareReport> shareHistoryKeys(
    MatrixRoom room,
    List<String> targetUserIds, {
    MatrixHistorySharePreview? preview,
  }) async {
    if (preview != null) {
      final requestedTargets = targetUserIds.toSet();
      final previewTargets = preview.report.targetUserIds.toSet();
      if (requestedTargets.length != previewTargets.length ||
          !requestedTargets.containsAll(previewTargets)) {
        throw ArgumentError('preview targets must match targetUserIds');
      }
      if (preview.eligibleDevices.any(
        (device) => !requestedTargets.contains(device.userId),
      )) {
        throw ArgumentError('preview devices must match targetUserIds');
      }
    } else {
      preview = await previewHistoryShare(room, targetUserIds);
    }
    final report = preview.report;
    final storedSessions = await getInboundGroupSessionsForRoom(
      room.identifier,
    );
    report.availableSessionCount = storedSessions.length;

    for (final storedSession in storedSessions) {
      await _sendStoredSessionToDevices(
        room: room,
        storedSession: storedSession,
        devices: preview.eligibleDevices,
        report: report,
        onlyVerified: false,
      );
    }

    return report;
  }

  void startSharedHistoryBundleListener({
    void Function(String roomId, String senderUserId)? onPendingBundle,
  }) {
    _historySharingRuntimes[this] ??= _MatrixHistorySharingRuntime(this);
    _historySharingRuntimes[this]!.start(onPendingBundle: onPendingBundle);
  }

  Future<void> stopSharedHistoryBundleListener() async {
    await _historySharingRuntimes[this]?.stop();
  }

  /// Test-only entry to the auto-share handler for one key request.
  ///
  /// The database gate lives inside `_handleRoomKeyRequest`, on a private
  /// runtime reached only through an [Expando] and driven only by the SDK's
  /// `onRoomKeyRequest` stream. A test that pushed an event through that
  /// stream would be asserting the SDK's controller and the listener wiring;
  /// this enters the unit that contains the gate, which is the thing that
  /// must not be removed. The handler is also `unawaited` in production, so
  /// this returning a future is what lets a test observe it mid-flight.
  @visibleForTesting
  Future<void> debugHandleRoomKeyRequestForTesting(
    matrix_crypto.RoomKeyRequest request,
  ) {
    _historySharingRuntimes[this] ??= _MatrixHistorySharingRuntime(this);
    return _historySharingRuntimes[this]!._handleRoomKeyRequest(request);
  }

  Future<MatrixHistoryBundleImportReport> acceptPendingSharedHistoryForRoom(
    String roomId, {
    String? inviterUserId,
  }) async {
    _historySharingRuntimes[this] ??= _MatrixHistorySharingRuntime(this);
    return _historySharingRuntimes[this]!.acceptPendingSharedHistoryForRoom(
      roomId,
      inviterUserId: inviterUserId,
    );
  }

  Future<void> _sendStoredSessionToDevices({
    required MatrixRoom room,
    required dynamic storedSession,
    required List<matrix.DeviceKeys> devices,
    required MatrixHistoryShareReport report,
    required bool onlyVerified,
  }) async {
    final encryption = matrixClient.encryption;
    if (encryption == null || devices.isEmpty) {
      return;
    }

    final sessionId = storedSession.sessionId as String;
    final session = await encryption.keyManager.loadInboundGroupSession(
      room.identifier,
      sessionId,
    );

    if (session?.inboundGroupSession == null) {
      report.skippedSessionIds.add(sessionId);
      return;
    }

    report.loadedSessionCount += 1;
    final payload = _buildForwardedRoomKeyPayload(encryption, session!);

    try {
      await matrixClient.sendToDeviceEncrypted(
        List<matrix.DeviceKeys>.from(devices),
        matrix.EventTypes.ForwardedRoomKey,
        Map<String, dynamic>.from(payload),
        onlyVerified: onlyVerified,
      );
      report.sharedDeviceDeliveries += devices.length;
      report.markSessionShared(sessionId);
    } catch (error, stack) {
      final msg =
          "Failed sending session=${_matrixHistoryLogHash(sessionId)} "
          "error=${_matrixHistoryLogError(error)}";
      report.failures.add(msg);
      Log.onError(error, stack, content: "shareHistoryKeys: $msg");
    }
  }

  Future<_RoomKeyBundle> _buildRoomKeyBundle(
    MatrixRoom room,
    MatrixHistoryShareReport report,
  ) async {
    final encryption = matrixClient.encryption;
    if (encryption == null) {
      throw StateError("Encryption is not available for this account.");
    }

    final storedSessions = await getInboundGroupSessionsForRoom(
      room.identifier,
    );
    report.availableSessionCount = storedSessions.length;

    final sessions = <Map<String, dynamic>>[];
    final withheld = <Map<String, dynamic>>[];

    for (final storedSession in storedSessions.take(_maxBundleSessions)) {
      final sessionId = storedSession.sessionId as String;
      final session = await encryption.keyManager.loadInboundGroupSession(
        room.identifier,
        sessionId,
      );

      if (session?.inboundGroupSession == null) {
        report.skippedSessionIds.add(sessionId);
        report.withheldSessionIds.add(sessionId);
        withheld.add(
          _withheldRecord(room.identifier, sessionId, 'm.unavailable'),
        );
        continue;
      }

      report.loadedSessionCount += 1;
      final payload = _buildForwardedRoomKeyPayload(encryption, session!)
        ..[matrixSharedHistoryFlag] = true;

      if (!matrixHistorySessionPayloadIsShareable(payload)) {
        report.withheldSessionIds.add(sessionId);
        withheld.add(
          _withheldRecord(room.identifier, sessionId, 'm.unshareable'),
        );
        continue;
      }

      sessions.add(payload);
    }

    if (storedSessions.length > _maxBundleSessions) {
      report.failures.add(
        "History bundle was capped at $_maxBundleSessions sessions.",
      );
    }

    final bundle = <String, dynamic>{
      'version': _matrixRoomKeyBundleVersion,
      'room_id': room.identifier,
      'sender': matrixClient.userID,
      'sender_device_id': matrixClient.deviceID,
      'created_ts': DateTime.now().millisecondsSinceEpoch,
      'sessions': sessions,
      'withheld': withheld,
    };
    final encoded = Uint8List.fromList(utf8.encode(jsonEncode(bundle)));
    if (encoded.length > _maxEncryptedBundleBytes) {
      throw StateError("History bundle is too large to upload safely.");
    }

    return _RoomKeyBundle(
      encodedBytes: encoded,
      sessions: sessions,
      withheld: withheld,
    );
  }

  Map<String, dynamic> _buildForwardedRoomKeyPayload(
    dynamic encryption,
    dynamic session,
  ) {
    final payload = Map<String, dynamic>.from(
      (session.content as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );

    payload['forwarding_curve25519_key_chain'] = List<String>.from(
      session.forwardingCurve25519KeyChain,
    );

    if ((session.senderKey as String).isNotEmpty) {
      payload['sender_key'] = session.senderKey;
    }

    final claimedEd25519 =
        (session.senderClaimedKeys as Map)['ed25519'] as String?;
    payload['sender_claimed_ed25519_key'] =
        claimedEd25519 ?? encryption.fingerprintKey;
    payload['session_key'] = session.inboundGroupSession.exportAt(
      session.inboundGroupSession.firstKnownIndex,
    );

    return payload;
  }
}

final Expando<_MatrixHistorySharingRuntime> _historySharingRuntimes =
    Expando<_MatrixHistorySharingRuntime>('matrixHistorySharingRuntime');

class _MatrixHistorySharingRuntime {
  _MatrixHistorySharingRuntime(this.client);

  final MatrixClient client;
  final List<_PendingRoomKeyBundle> _pendingBundles = <_PendingRoomKeyBundle>[];
  final Set<String> _autoSharedRequestKeys = <String>{};
  StreamSubscription<matrix.ToDeviceEvent>? _bundleSubscription;
  StreamSubscription<matrix_crypto.RoomKeyRequest>? _keyRequestSubscription;
  void Function(String roomId, String senderUserId)? _onPendingBundle;

  void start({
    void Function(String roomId, String senderUserId)? onPendingBundle,
  }) {
    _onPendingBundle = onPendingBundle;
    if (_bundleSubscription == null) {
      _bundleSubscription = client.matrixClient.onToDeviceEvent.stream
          .where((event) => event.type == matrixRoomKeyBundleEventType)
          .listen(_handleBundleEvent);
    }
    _keyRequestSubscription ??= client.matrixClient.onRoomKeyRequest.stream
        .listen((request) => unawaited(_handleRoomKeyRequest(request)));
  }

  Future<void> _handleRoomKeyRequest(
    matrix_crypto.RoomKeyRequest request,
  ) async {
    final room = client.getRoom(request.room.id);
    if (room is! MatrixRoom) {
      Log.i(
        "autoHistoryShare: skipped reason=room_not_loaded "
        "room=${_matrixHistoryLogHash(request.room.id)} "
        "request=${_matrixHistoryLogHash(request.request.requestId)}",
      );
      return;
    }

    final requestingDevice = request.requestingDevice;
    final requesterUserId = requestingDevice.userId;
    final visibilityAllowsSharing = matrixHistoryVisibilityAllowsInviteSharing(
      room.matrixRoom.historyVisibility,
    );
    // `_requesterIsJoined` reads the participant list, which reaches
    // `client.database.getUsers` in the SDK - the same released-store hazard
    // `respondToRoomKeyRequest` gates against, met earlier in the same
    // request. It is also OUTSIDE the try below, so a throw here does not
    // become the `autoHistoryShare: failed` line: it escapes the unawaited
    // listener into the zone and the request disappears with no record at
    // all. Gate first, so one released store produces one outcome for the
    // whole request rather than a different one per read.
    if (!await DatabaseReleaseTrigger.waitForDatabase(
      'key_request.participants',
    )) {
      Log.w(
        "autoHistoryShare: deferred, database unavailable "
        "room=${_matrixHistoryLogHash(room.identifier)} "
        "target=${_matrixHistoryLogHash(requesterUserId)} "
        "session=${_matrixHistoryLogHash(request.request.sessionId)}",
      );
      return;
    }

    final requesterIsJoined = await _requesterIsJoined(
      room.matrixRoom,
      requesterUserId,
    );
    final skipReason = matrixHistoryAutoKeyShareSkipReason(
      requestCanceled: request.request.canceled,
      requesterIsSelf: requesterUserId == client.matrixClient.userID,
      roomIsE2EE: room.isE2EE,
      visibilityAllowsSharing: visibilityAllowsSharing,
      requesterIsJoined: requesterIsJoined,
      deviceEligible: matrixHistoryDeviceEligibleForKeyShare(requestingDevice),
    );
    if (skipReason != null) {
      if (room.isE2EE && visibilityAllowsSharing) {
        Log.i(
          "autoHistoryShare: skipped reason=$skipReason "
          "room=${_matrixHistoryLogHash(room.identifier)} "
          "target=${_matrixHistoryLogHash(requesterUserId)} "
          "device=${_matrixHistoryLogHash(requestingDevice.deviceId)} "
          "session=${_matrixHistoryLogHash(request.request.sessionId)}",
        );
      }
      return;
    }

    final requesterDeviceId = requestingDevice.deviceId;
    if (requesterDeviceId == null) {
      return;
    }
    final requestKey = _matrixHistoryAutoKeyShareRequestKey(
      requesterUserId: requesterUserId,
      requesterDeviceId: requesterDeviceId,
      roomId: room.identifier,
      sessionId: request.request.sessionId,
      requestId: request.request.requestId,
    );

    if (!_rememberAutoSharedRequestKey(requestKey)) {
      return;
    }

    final report = MatrixHistoryShareReport(
      targetUserIds: <String>[requesterUserId],
    );
    try {
      final outcome = await client.respondToRoomKeyRequest(
        room,
        request,
        report,
        allowIneligibleDevice: false,
      );
      final sent = outcome == MatrixKeyRequestOutcome.fulfilled;
      Log.i(
        "autoHistoryShare: ${outcome.name} "
        "room=${_matrixHistoryLogHash(room.identifier)} "
        "target=${_matrixHistoryLogHash(requesterUserId)} "
        "device=${_matrixHistoryLogHash(requestingDevice.deviceId)} "
        "session=${_matrixHistoryLogHash(request.request.sessionId)} "
        "deliveries=${report.sharedDeviceDeliveries}",
      );
      if (!sent) {
        _forgetAutoSharedRequestKey(requestKey);
      }
    } catch (error, stack) {
      _forgetAutoSharedRequestKey(requestKey);
      Log.onError(
        error,
        stack,
        content:
            "autoHistoryShare: failed "
            "room=${_matrixHistoryLogHash(room.identifier)} "
            "target=${_matrixHistoryLogHash(requesterUserId)} "
            "device=${_matrixHistoryLogHash(requestingDevice.deviceId)} "
            "error=${_matrixHistoryLogError(error)}",
      );
    }
  }

  Future<void> stop() async {
    await _bundleSubscription?.cancel();
    _bundleSubscription = null;
    await _keyRequestSubscription?.cancel();
    _keyRequestSubscription = null;
    _onPendingBundle = null;
    _pendingBundles.clear();
    _autoSharedRequestKeys.clear();
  }

  bool _rememberAutoSharedRequestKey(String requestKey) {
    if (requestKey.isEmpty) {
      return false;
    }
    if (!_autoSharedRequestKeys.add(requestKey)) {
      return false;
    }
    while (_autoSharedRequestKeys.length > _autoSharedRequestMemoryLimit) {
      _autoSharedRequestKeys.remove(_autoSharedRequestKeys.first);
    }
    return true;
  }

  void _forgetAutoSharedRequestKey(String requestKey) {
    _autoSharedRequestKeys.remove(requestKey);
  }

  Future<bool> _requesterIsJoined(
    matrix.Room room,
    String requesterUserId,
  ) async {
    final participants = await room.requestParticipants(
      [matrix.Membership.join],
      true,
      true,
    );
    return participants.any((member) => member.id == requesterUserId);
  }

  void _handleBundleEvent(matrix.ToDeviceEvent event) {
    final encryptedContent = event.encryptedContent;
    if (encryptedContent == null) {
      Log.w("historyBundle: rejected unencrypted to-device event");
      return;
    }

    final roomId = _stringValue(event.content['room_id']);
    final file = _mapValue(event.content['file']);
    if (roomId == null || file == null) {
      Log.w("historyBundle: rejected malformed bundle metadata");
      return;
    }

    _dropExpiredPendingBundles();
    _pendingBundles.add(
      _PendingRoomKeyBundle(
        roomId: roomId,
        senderUserId: event.sender,
        senderCurve25519Key: _stringValue(encryptedContent['sender_key']),
        content: Map<String, dynamic>.from(event.content),
        receivedAt: DateTime.now(),
      ),
    );

    Log.i(
      "historyBundle: stored pending bundle "
      "room=${_matrixHistoryLogHash(roomId)} "
      "sender=${_matrixHistoryLogHash(event.sender)}",
    );
    _onPendingBundle?.call(roomId, event.sender);
  }

  Future<MatrixHistoryBundleImportReport> acceptPendingSharedHistoryForRoom(
    String roomId, {
    String? inviterUserId,
  }) async {
    final report = MatrixHistoryBundleImportReport(roomId: roomId);
    _dropExpiredPendingBundles(report: report);

    final roomBundles = _pendingBundles
        .where((bundle) => bundle.roomId == roomId)
        .toList(growable: false);
    final matching = roomBundles
        .where(
          (bundle) =>
              inviterUserId == null || bundle.senderUserId == inviterUserId,
        )
        .toList(growable: false);
    final mismatched = roomBundles
        .where((bundle) => !matching.contains(bundle))
        .toList(growable: false);
    for (final bundle in mismatched) {
      _pendingBundles.remove(bundle);
    }
    report.rejectedBundleCount += mismatched.length;
    report.pendingBundleCount = _pendingBundles
        .where((bundle) => bundle.roomId == roomId)
        .length;

    if (matching.isEmpty) {
      Log.i(
        "historyBundle: no pending bundle "
        "room=${_matrixHistoryLogHash(roomId)} "
        "inviter=${_matrixHistoryLogHash(inviterUserId)} "
        "pending=${report.pendingBundleCount} "
        "rejected=${report.rejectedBundleCount} "
        "expired=${report.expiredBundleCount}",
      );
      return report;
    }

    for (final bundle in matching) {
      _pendingBundles.remove(bundle);

      try {
        final imported = await _importPendingBundle(bundle, report);
        if (imported > 0) {
          report.importedBundleCount += 1;
          report.importedSessionCount += imported;
        }
      } catch (error, stack) {
        report.rejectedBundleCount += 1;
        report.failures.add(_matrixHistoryLogError(error));
        Log.onError(
          error,
          stack,
          content:
              "historyBundle: failed import "
              "room=${_matrixHistoryLogHash(roomId)} "
              "sender=${_matrixHistoryLogHash(bundle.senderUserId)} "
              "error=${_matrixHistoryLogError(error)}",
        );
      }
    }
    report.pendingBundleCount = _pendingBundles
        .where((bundle) => bundle.roomId == roomId)
        .length;

    Log.i(
      "historyBundle: import result "
      "room=${_matrixHistoryLogHash(roomId)} "
      "pending=${report.pendingBundleCount} "
      "importedSessions=${report.importedSessionCount} "
      "rejected=${report.rejectedBundleCount} "
      "expired=${report.expiredBundleCount}",
    );

    return report;
  }

  Future<int> _importPendingBundle(
    _PendingRoomKeyBundle bundle,
    MatrixHistoryBundleImportReport report,
  ) async {
    if (bundle.isExpired) {
      report.expiredBundleCount += 1;
      return 0;
    }

    final senderDevice = await _eligibleBundleSenderDevice(bundle);
    if (senderDevice == null) {
      throw StateError("Bundle sender device is not eligible.");
    }

    final file = _mapValue(bundle.content['file']);
    if (file == null) {
      throw StateError("Bundle file metadata is missing.");
    }

    final decrypted = await _downloadAndDecryptBundleFile(file);
    final decoded = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;

    if (_stringValue(decoded['version']) != _matrixRoomKeyBundleVersion) {
      throw StateError("Unsupported room-key bundle version.");
    }
    if (_stringValue(decoded['room_id']) != bundle.roomId) {
      throw StateError("Room-key bundle room mismatch.");
    }
    if (_stringValue(decoded['sender']) != bundle.senderUserId) {
      throw StateError("Room-key bundle sender mismatch.");
    }

    final sessions = _listValue(decoded['sessions']);
    if (sessions == null) {
      throw StateError("Room-key bundle sessions are malformed.");
    }
    if (sessions.length > _maxBundleSessions) {
      throw StateError("Room-key bundle has too many sessions.");
    }

    var imported = 0;
    for (final entry in sessions) {
      final payload = _mapValue(entry);
      if (payload == null) {
        continue;
      }
      if (!matrixHistorySessionPayloadIsShareable(payload)) {
        continue;
      }
      if (_stringValue(payload['room_id']) != bundle.roomId) {
        continue;
      }
      if (_stringValue(payload['algorithm']) !=
          matrix.AlgorithmTypes.megolmV1AesSha2) {
        continue;
      }

      final sessionId = _stringValue(payload['session_id']);
      final senderKey = _stringValue(payload['sender_key']);
      final sessionKey = _stringValue(payload['session_key']);
      final claimedEd25519 =
          _stringValue(payload['sender_claimed_ed25519_key']) ??
          _stringValue(_mapValue(payload['sender_claimed_keys'])?['ed25519']);

      if (sessionId == null ||
          senderKey == null ||
          sessionKey == null ||
          claimedEd25519 == null) {
        continue;
      }

      await client.matrixClient.encryption?.keyManager.setInboundGroupSession(
        bundle.roomId,
        sessionId,
        senderKey,
        Map<String, dynamic>.from(payload),
        forwarded: true,
        senderClaimedKeys: {'ed25519': claimedEd25519},
      );
      imported += 1;
    }

    return imported;
  }

  Future<matrix.DeviceKeys?> _eligibleBundleSenderDevice(
    _PendingRoomKeyBundle bundle,
  ) async {
    final senderKey = bundle.senderCurve25519Key;
    if (senderKey == null || senderKey.isEmpty) {
      return null;
    }

    await client.matrixClient.updateUserDeviceKeys(
      additionalUsers: {bundle.senderUserId},
    );

    final device = client.matrixClient.getUserDeviceKeysByCurve25519Key(
      senderKey,
    );
    if (device == null ||
        device.userId != bundle.senderUserId ||
        !matrixHistoryDeviceEligibleForKeyShare(device)) {
      return null;
    }
    return device;
  }

  Future<Uint8List> _downloadAndDecryptBundleFile(
    Map<String, dynamic> file,
  ) async {
    final url = _stringValue(file['url']);
    final key = _mapValue(file['key']);
    final hashes = _mapValue(file['hashes']);
    final iv = _stringValue(file['iv']);
    final k = _stringValue(key?['k']);
    final sha256 = _stringValue(hashes?['sha256']);

    if (url == null || iv == null || k == null || sha256 == null) {
      throw StateError("Encrypted bundle file metadata is incomplete.");
    }
    if (!matrixHistoryBundleDeclaredFileSizesAreSafe(file)) {
      throw StateError("Encrypted bundle file size metadata is unsafe.");
    }
    final plaintextSize = _nonNegativeIntValue(file['size'])!;
    final encryptedSize = _nonNegativeIntValue(file['encrypted_size'])!;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'mxc' || uri.pathSegments.isEmpty) {
      throw StateError("Encrypted bundle file URL is not an MXC URI.");
    }

    final encryptedBytes = await _downloadBundleFileContent(
      uri,
      maxBytes: _maxEncryptedBundleBytes,
    );
    if (encryptedBytes.length != encryptedSize) {
      throw StateError("Encrypted bundle file size mismatch.");
    }

    final decrypted = await client.matrixClient.nativeImplementations
        .decryptFile(
          matrix.EncryptedFile(
            data: encryptedBytes,
            k: k,
            iv: iv,
            sha256: sha256,
          ),
        );

    if (decrypted == null || decrypted.length > _maxEncryptedBundleBytes) {
      throw StateError("Encrypted bundle file could not be decrypted.");
    }
    if (decrypted.length != plaintextSize) {
      throw StateError("Encrypted bundle file plaintext size mismatch.");
    }
    return decrypted;
  }

  Future<Uint8List> _downloadBundleFileContent(
    Uri mxcUri, {
    required int maxBytes,
  }) async {
    final downloadUri = await matrix.MxcUriExtension(
      mxcUri,
    ).getDownloadUri(client.matrixClient);
    final request = http.Request('GET', downloadUri);
    final accessToken = client.matrixClient.accessToken;
    if (accessToken != null) {
      request.headers['authorization'] = 'Bearer $accessToken';
    }

    late final http.StreamedResponse response;
    try {
      response = await client.matrixClient.httpClient
          .send(request)
          .timeout(_encryptedBundleDownloadTimeout);
    } on TimeoutException {
      throw StateError("Encrypted bundle file download timed out.");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError("Encrypted bundle file download failed.");
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      throw StateError("Encrypted bundle file is too large.");
    }

    final bytes = BytesBuilder(copy: false);
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        _encryptedBundleDownloadTimeout,
      )) {
        received += chunk.length;
        if (received > maxBytes) {
          throw StateError("Encrypted bundle file is too large.");
        }
        bytes.add(chunk);
      }
    } on TimeoutException {
      throw StateError("Encrypted bundle file download timed out.");
    }
    return bytes.takeBytes();
  }

  void _dropExpiredPendingBundles({MatrixHistoryBundleImportReport? report}) {
    final before = _pendingBundles.length;
    _pendingBundles.removeWhere((bundle) => bundle.isExpired);
    final dropped = before - _pendingBundles.length;
    if (dropped > 0) {
      report?.expiredBundleCount += dropped;
      Log.i("historyBundle: dropped expired pending bundles count=$dropped");
    }
  }
}

class _PendingRoomKeyBundle {
  _PendingRoomKeyBundle({
    required this.roomId,
    required this.senderUserId,
    required this.senderCurve25519Key,
    required this.content,
    required this.receivedAt,
  });

  final String roomId;
  final String senderUserId;
  final String? senderCurve25519Key;
  final Map<String, dynamic> content;
  final DateTime receivedAt;

  bool get isExpired =>
      DateTime.now().difference(receivedAt) > _pendingBundleLifetime;
}

class _RoomKeyBundle {
  _RoomKeyBundle({
    required this.encodedBytes,
    required this.sessions,
    required this.withheld,
  });

  final Uint8List encodedBytes;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> withheld;
}

bool _isThisDevice(matrix.DeviceKeys device, matrix.Client client) {
  return device.userId == client.userID && device.deviceId == client.deviceID;
}

List<matrix.DeviceKeys> _knownTargetDevicesForUser(
  matrix.Client client,
  String userId,
) {
  final deviceKeys = client.userDeviceKeys[userId]?.deviceKeys.values;
  if (deviceKeys == null) {
    return <matrix.DeviceKeys>[];
  }
  return deviceKeys
      .where(
        (device) =>
            device.userId == userId &&
            !device.blocked &&
            !_isThisDevice(device, client),
      )
      .toList(growable: false);
}

Map<String, dynamic> _bundleToDeviceContent({
  required String roomId,
  required matrix.EncryptedFile encrypted,
  required Uri mxc,
  required int plaintextSize,
  required int encryptedSize,
  required int sessionCount,
  required int withheldCount,
}) {
  return <String, dynamic>{
    'version': _matrixRoomKeyBundleVersion,
    'room_id': roomId,
    'algorithm': matrix.AlgorithmTypes.megolmV1AesSha2,
    'created_ts': DateTime.now().millisecondsSinceEpoch,
    'session_count': sessionCount,
    'withheld_count': withheldCount,
    'file': <String, dynamic>{
      'url': mxc.toString(),
      'v': 'v2',
      'mimetype': 'application/json',
      'size': plaintextSize,
      'encrypted_size': encryptedSize,
      'iv': encrypted.iv,
      'key': <String, dynamic>{
        'alg': 'A256CTR',
        'ext': true,
        'k': encrypted.k,
        'key_ops': <String>['encrypt', 'decrypt'],
        'kty': 'oct',
      },
      'hashes': <String, dynamic>{'sha256': encrypted.sha256},
    },
  };
}

Map<String, dynamic> _withheldRecord(
  String roomId,
  String sessionId,
  String code,
) {
  return <String, dynamic>{
    'room_id': roomId,
    'session_id': sessionId,
    'code': code,
  };
}

String? _stringValue(Object? value) => value is String ? value : null;

int? _nonNegativeIntValue(Object? value) {
  if (value is int && value >= 0) {
    return value;
  }
  if (value is num && value.isFinite && value >= 0) {
    final rounded = value.round();
    return rounded == value ? rounded : null;
  }
  return null;
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
  return null;
}

List<dynamic>? _listValue(Object? value) => value is List ? value : null;
