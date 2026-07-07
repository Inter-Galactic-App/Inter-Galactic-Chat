import 'dart:async';

import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/invitation/invitation.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_history_sharing.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_peer.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/notifying_list.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixInvitationComponent
    implements
        InvitationComponent<MatrixClient>,
        NeedsPostLoginInit,
        DisposableComponent {
  @override
  final MatrixClient client;

  @override
  NotifyingList<Invitation> invitations = NotifyingList.empty(growable: true);

  final Set<String> _locallyResolvedInviteRoomIds = {};
  final Map<String, String?> _locallyAcceptedInviteSendersByRoomId = {};
  final Set<String> _sharedHistoryImportsInFlight = {};
  StreamSubscription<void>? _syncSubscription;

  MatrixInvitationComponent(this.client);

  @override
  Future<void> acceptInvitation(Invitation invitation) async {
    var mx = client.getMatrixClient();
    _locallyAcceptedInviteSendersByRoomId[invitation.roomId] =
        invitation.senderId;
    try {
      await mx.joinRoom(invitation.roomId);
    } catch (_) {
      _locallyAcceptedInviteSendersByRoomId.remove(invitation.roomId);
      rethrow;
    }

    _locallyResolvedInviteRoomIds.add(invitation.roomId);
    invitations.removeWhere((entry) => entry.roomId == invitation.roomId);

    try {
      final historyReport = await client.acceptPendingSharedHistoryForRoom(
        invitation.roomId,
        inviterUserId: invitation.senderId,
      );
      _showSharedHistoryImportResult(historyReport);
    } catch (error, stack) {
      Log.onError(
        error,
        stack,
        content: "inviteHistoryImport: failed after join "
            "room=${MatrixClient.hash(invitation.roomId).substring(0, 12)} "
            "sender=${MatrixClient.hash(invitation.senderId ?? '').substring(0, 12)}",
      );
    }
  }

  @override
  Future<void> rejectInvitation(Invitation invitation) async {
    var mx = client.getMatrixClient();
    await mx.leaveRoom(invitation.roomId);
    _locallyResolvedInviteRoomIds.add(invitation.roomId);
    _locallyAcceptedInviteSendersByRoomId.remove(invitation.roomId);
    invitations.removeWhere((entry) => entry.roomId == invitation.roomId);
  }

  @override
  void postLoginInit() {
    Log.i("Loading invite list!");
    client.startSharedHistoryBundleListener(
      onPendingBundle: _handlePendingSharedHistoryBundle,
    );
    _updateInviteList();

    _syncSubscription ??= client.onSync.listen((_) => _updateInviteList());
  }

  @override
  Future<void> dispose() async {
    await _syncSubscription?.cancel();
    _syncSubscription = null;
    await client.stopSharedHistoryBundleListener();
  }

  void _updateInviteList() async {
    var mx = client.getMatrixClient();
    var invitedRooms =
        mx.rooms.where((element) => element.membership.isInvite).toList();
    var invitedRoomIds = invitedRooms.map((room) => room.id).toSet();
    final joinedRoomIds = mx.rooms
        .where((room) => room.membership.isJoin)
        .map((room) => room.id)
        .toSet();
    _locallyAcceptedInviteSendersByRoomId.removeWhere(
      (roomId, _) =>
          !joinedRoomIds.contains(roomId) && !invitedRoomIds.contains(roomId),
    );
    _locallyResolvedInviteRoomIds
        .removeWhere((roomId) => !invitedRoomIds.contains(roomId));

    for (var invitation in invitations.toList()) {
      if (!invitedRoomIds.contains(invitation.roomId)) {
        invitations.remove(invitation);
      }
    }

    for (var room in invitedRooms) {
      if (_locallyResolvedInviteRoomIds.contains(room.id)) {
        continue;
      }

      if (invitations
          .where((element) => element.roomId == room.id)
          .isNotEmpty) {
        continue;
      }

      var state = room.states[matrix.EventTypes.RoomMember]?[mx.userID];
      var sender = state?.senderId;

      var avatar =
          room.avatar != null ? MatrixMxcImage(room.avatar!, mx) : null;

      var entry = Invitation(
          roomId: room.id,
          avatar: avatar,
          senderId: sender,
          color: MatrixPeer.hashColor(room.id),
          displayName: room.getLocalizedDisplayname());

      invitations.add(entry);
    }
  }

  void _handlePendingSharedHistoryBundle(
    String roomId,
    String senderUserId,
  ) {
    final acceptedInviteKnown =
        _locallyAcceptedInviteSendersByRoomId.containsKey(roomId);
    final acceptedInviterUserId = _locallyAcceptedInviteSendersByRoomId[roomId];
    if (!matrixHistoryShouldImportLatePendingBundle(
      roomIsJoined: _isJoinedRoom(roomId),
      acceptedInviteKnown: acceptedInviteKnown,
      acceptedInviterUserId: acceptedInviterUserId,
      bundleSenderUserId: senderUserId,
    )) {
      return;
    }

    final importKey = '$roomId|$senderUserId';
    if (!_sharedHistoryImportsInFlight.add(importKey)) {
      return;
    }
    unawaited(_importLateSharedHistoryBundle(
      roomId,
      acceptedInviterUserId ?? senderUserId,
      importKey,
    ));
  }

  bool _isJoinedRoom(String roomId) {
    return client
        .getMatrixClient()
        .rooms
        .any((room) => room.id == roomId && room.membership.isJoin);
  }

  Future<void> _importLateSharedHistoryBundle(
    String roomId,
    String inviterUserId,
    String importKey,
  ) async {
    try {
      final report = await client.acceptPendingSharedHistoryForRoom(
        roomId,
        inviterUserId: inviterUserId,
      );
      _showSharedHistoryImportResult(report);
    } catch (error, stack) {
      Log.onError(
        error,
        stack,
        content: "lateInviteHistoryImport: failed "
            "room=${MatrixClient.hash(roomId).substring(0, 12)} "
            "sender=${MatrixClient.hash(inviterUserId).substring(0, 12)}",
      );
    } finally {
      _sharedHistoryImportsInFlight.remove(importKey);
    }
  }

  @override
  Future<void> inviteUserToRoom(
      {required String userId, required String roomId}) async {
    var mx = client.getMatrixClient();
    await mx.inviteUser(roomId, userId);

    final room = client.getRoom(roomId);
    if (room is! MatrixRoom) {
      Log.i(
        "inviteHistoryShare: skipped reason=room_not_loaded "
        "room=${MatrixClient.hash(roomId).substring(0, 12)} "
        "target=${MatrixClient.hash(userId).substring(0, 12)}",
      );
      return;
    }
    if (!room.isE2EE) {
      return;
    }
    if (!matrixHistoryVisibilityAllowsInviteSharing(
      room.matrixRoom.historyVisibility,
    )) {
      Log.i(
        "inviteHistoryShare: skipped reason=history_visibility_not_shared "
        "room=${MatrixClient.hash(roomId).substring(0, 12)} "
        "target=${MatrixClient.hash(userId).substring(0, 12)} "
        "visibility=${room.matrixRoom.historyVisibility?.text ?? 'unknown'}",
      );
      return;
    }

    try {
      final report = await client.shareHistoryBundleForInvite(room, userId);
      _showInviteHistoryShareResult(roomId, report);
    } catch (error, stack) {
      Log.onError(
        error,
        stack,
        content: "inviteHistoryShare: failed "
            "room=${MatrixClient.hash(roomId).substring(0, 12)} "
            "target=${MatrixClient.hash(userId).substring(0, 12)}",
      );
    }
  }

  @override
  Future<List<Profile>> searchUsers(String term) async {
    var mx = client.getMatrixClient();
    var result = await mx.searchUserDirectory(term);

    var finalResult =
        result.results.map((e) => MatrixProfile(client, e)).toList();
    if (term.isValidMatrixId && !finalResult.any((i) => i.identifier == term)) {
      finalResult = [
        MatrixProfile(
            client, matrix.Profile(userId: term, displayName: term.localpart)),
        ...finalResult
      ];
    }

    return finalResult;
  }

  void _showInviteHistoryShareResult(
    String roomId,
    MatrixHistoryShareReport report,
  ) {
    if (report.bundleCount > 0 && report.sharedDeviceDeliveries > 0) {
      return;
    }

    final message = _inviteHistoryShareWarning(report);
    if (message == null) {
      return;
    }

    clientManager?.alertManager.addAlert(
      Alert(
        AlertType.warning,
        id: 'invite-history-share-${client.identifier}-'
            '${MatrixClient.hash(roomId).substring(0, 12)}',
        titleGetter: () => 'Encrypted history not shared',
        messageGetter: () => message,
      ),
    );
  }

  String? _inviteHistoryShareWarning(MatrixHistoryShareReport report) {
    if (report.eligibleDeviceCount == 0) {
      return 'Encrypted history was not shared because the invited user has no '
          'devices eligible under your current Matrix key-sharing policy. Ask '
          'them to open the room and request keys, then use /sharehistory if '
          'you still want to share history.';
    }

    if (report.availableSessionCount == 0) {
      return 'Encrypted history was not shared because this device has no '
          'locally available room keys for the room history.';
    }

    if (report.failures.isNotEmpty) {
      return 'Encrypted history could not be shared. The invite still worked, '
          'but old messages may stay undecryptable until keys are requested.';
    }

    return 'Encrypted history was not shared. The invite still worked, but '
        'old messages may stay undecryptable until keys are requested.';
  }

  void _showSharedHistoryImportResult(
    MatrixHistoryBundleImportReport report,
  ) {
    if (!report.hadPendingBundle) {
      return;
    }

    final alertType = report.didImport ? AlertType.info : AlertType.warning;
    clientManager?.alertManager.addAlert(
      Alert(
        alertType,
        id: 'shared-history-${client.identifier}-${report.roomId}',
        titleGetter: () => 'Shared encrypted history',
        messageGetter: report.summaryForUser,
        autoClearAfter: report.didImport ? const Duration(seconds: 10) : null,
      ),
    );
  }
}
