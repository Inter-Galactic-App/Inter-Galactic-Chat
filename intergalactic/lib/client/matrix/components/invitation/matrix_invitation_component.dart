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

  /// Rooms this account has an outstanding knock on. When an invite arrives
  /// for one of these (an admin approved the knock), the invite is accepted
  /// automatically so approving a knock reads as a direct join rather than a
  /// second invite the knocker must accept.
  final Set<String> _outstandingKnockRoomIds = {};

  /// Rooms whose knock auto-accept already failed this session. Held in memory
  /// only (not persisted) so the failing join is retried at most once per
  /// launch: after a failure the invite falls back to the normal list for
  /// manual acceptance for the rest of the session, and the persisted knock
  /// (which survives restart) drives a single retry on the next launch.
  final Set<String> _failedKnockAutoAcceptRoomIds = {};
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
        content:
            "inviteHistoryImport: failed after join "
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
    var invitedRooms = mx.rooms
        .where((element) => element.membership.isInvite)
        .toList();
    var invitedRoomIds = invitedRooms.map((room) => room.id).toSet();
    final joinedRoomIds = mx.rooms
        .where((room) => room.membership.isJoin)
        .map((room) => room.id)
        .toSet();
    final knockingRoomIds = mx.rooms
        .where((room) => room.membership.isKnock)
        .map((room) => room.id)
        .toSet();
    final leftRoomIds = mx.rooms
        .where((room) => room.membership.isLeave)
        .map((room) => room.id)
        .toSet();
    // Seed outstanding knocks from persistent storage (recorded at knock time)
    // so the invite an approval produces is auto-accepted even across an app
    // restart or when the knock membership is never observed live, and fold in
    // any knock we can see in the current sync.
    _outstandingKnockRoomIds.addAll(
      preferences.getKnockedRoomIds(client.identifier),
    );
    _outstandingKnockRoomIds.addAll(knockingRoomIds);
    for (final roomId in knockingRoomIds) {
      unawaited(preferences.addKnockedRoomId(client.identifier, roomId));
    }
    // Only forget a knock once it has positively resolved - joined or left.
    // A room that is merely absent from the sync yet may still be pending, so
    // it is kept to avoid dropping a knock before its invite arrives. This runs
    // before the failed-auto-accept pruning below so a room that failed
    // auto-accept and has since resolved is still cleared from the failed set
    // and persistence rather than lingering there for the rest of the session.
    final resolvedKnockRoomIds = _outstandingKnockRoomIds
        .where(
          (roomId) =>
              joinedRoomIds.contains(roomId) || leftRoomIds.contains(roomId),
        )
        .toList();
    _outstandingKnockRoomIds.removeAll(resolvedKnockRoomIds);
    for (final roomId in resolvedKnockRoomIds) {
      _failedKnockAutoAcceptRoomIds.remove(roomId);
      unawaited(preferences.removeKnockedRoomId(client.identifier, roomId));
    }
    // A knock whose auto-accept already failed this session must not be retried
    // on every sync: drop it from the outstanding set so its invite falls
    // through to the normal list below for manual acceptance. The persisted
    // knock is deliberately kept so a single retry still happens on next launch
    // (when this in-memory guard is empty again).
    _outstandingKnockRoomIds.removeAll(_failedKnockAutoAcceptRoomIds);
    _locallyAcceptedInviteSendersByRoomId.removeWhere(
      (roomId, _) =>
          !joinedRoomIds.contains(roomId) && !invitedRoomIds.contains(roomId),
    );
    _locallyResolvedInviteRoomIds.removeWhere(
      (roomId) => !invitedRoomIds.contains(roomId),
    );

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

      var avatar = room.avatar != null
          ? MatrixMxcImage(room.avatar!, mx)
          : null;

      var entry = Invitation(
        roomId: room.id,
        avatar: avatar,
        senderId: sender,
        color: MatrixPeer.hashColor(room.id),
        displayName: room.getLocalizedDisplayname(),
      );

      // If we previously knocked on this room, an admin approving the knock
      // surfaces as this invite. Accept it automatically instead of listing it
      // so the requester is dropped straight into the room.
      if (_outstandingKnockRoomIds.remove(room.id)) {
        _locallyResolvedInviteRoomIds.add(room.id);
        Log.i(
          "Auto-accepting invite for previously-knocked room "
          "room=${MatrixClient.hash(room.id).substring(0, 12)} "
          "client=${MatrixClient.hash(client.identifier).substring(0, 12)}",
        );
        unawaited(_autoAcceptKnockedInvite(entry));
        continue;
      }

      invitations.add(entry);
    }
  }

  Future<void> _autoAcceptKnockedInvite(Invitation invitation) async {
    try {
      await acceptInvitation(invitation);
      _failedKnockAutoAcceptRoomIds.remove(invitation.roomId);
      await preferences.removeKnockedRoomId(
        client.identifier,
        invitation.roomId,
      );
      Log.i(
        "Auto-accepted invite for previously-knocked room "
        "room=${MatrixClient.hash(invitation.roomId).substring(0, 12)}",
      );
    } catch (error, stack) {
      // Mark this session's attempt as failed so the knock is dropped from the
      // outstanding set instead of retrying the failing join on every sync. The
      // persisted knock is intentionally kept so exactly one retry happens on
      // the next launch (when the in-memory guard is empty again).
      _failedKnockAutoAcceptRoomIds.add(invitation.roomId);
      _locallyResolvedInviteRoomIds.remove(invitation.roomId);
      // Surface the invite for manual acceptance immediately: a failed join may
      // not emit another sync, so waiting for the next _updateInviteList could
      // otherwise leave the invite hidden until the next launch.
      if (!invitations.any((entry) => entry.roomId == invitation.roomId)) {
        invitations.add(invitation);
      }
      Log.onError(
        error,
        stack,
        content:
            "autoAcceptKnockedInvite: failed to join "
            "room=${MatrixClient.hash(invitation.roomId).substring(0, 12)}",
      );
    }
  }

  void _handlePendingSharedHistoryBundle(String roomId, String senderUserId) {
    final acceptedInviteKnown = _locallyAcceptedInviteSendersByRoomId
        .containsKey(roomId);
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
    unawaited(
      _importLateSharedHistoryBundle(
        roomId,
        acceptedInviterUserId ?? senderUserId,
        importKey,
      ),
    );
  }

  bool _isJoinedRoom(String roomId) {
    return client.getMatrixClient().rooms.any(
      (room) => room.id == roomId && room.membership.isJoin,
    );
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
        content:
            "lateInviteHistoryImport: failed "
            "room=${MatrixClient.hash(roomId).substring(0, 12)} "
            "sender=${MatrixClient.hash(inviterUserId).substring(0, 12)}",
      );
    } finally {
      _sharedHistoryImportsInFlight.remove(importKey);
    }
  }

  @override
  Future<void> inviteUserToRoom({
    required String userId,
    required String roomId,
  }) async {
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
        content:
            "inviteHistoryShare: failed "
            "room=${MatrixClient.hash(roomId).substring(0, 12)} "
            "target=${MatrixClient.hash(userId).substring(0, 12)}",
      );
    }
  }

  @override
  Future<List<Profile>> searchUsers(String term) async {
    var mx = client.getMatrixClient();
    var result = await mx.searchUserDirectory(term);

    var finalResult = result.results
        .map((e) => MatrixProfile(client, e))
        .toList();
    if (term.isValidMatrixId && !finalResult.any((i) => i.identifier == term)) {
      finalResult = [
        MatrixProfile(
          client,
          matrix.Profile(userId: term, displayName: term.localpart),
        ),
        ...finalResult,
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
        id:
            'invite-history-share-${client.identifier}-'
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

  void _showSharedHistoryImportResult(MatrixHistoryBundleImportReport report) {
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
