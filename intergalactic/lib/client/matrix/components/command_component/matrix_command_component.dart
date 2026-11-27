import 'dart:async';
import 'dart:convert';

import 'package:intergalactic/client/components/command/command_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_formatting.dart';
import 'package:intergalactic/client/matrix/matrix_history_sharing.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_room_migration.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/chat/chat.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart'
    show SelectableText, SizedBox, TextButton, Theme;
import 'package:flutter/widgets.dart';
import 'package:matrix/encryption.dart' as matrix_crypto;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite/generated/model.dart';
import 'package:uuid/uuid.dart';

class MatrixCommandComponent extends CommandComponent<MatrixClient> {
  @override
  MatrixClient client;

  static RegExp sed_pattern = RegExp(r'^s\/([^\/]+)\/([^\n\r]*?)\/?\s*$');
  final Set<String> _localCommands = const {
    "inviteall",
    "roomupgrade",
    "sharehistory",
  };

  MatrixCommandComponent(this.client) {
    client.getMatrixClient().addCommand("sendjson", sendJson);
    client.getMatrixClient().addCommand("status", setStatus);
    client.getMatrixClient().addCommand("clearemojistats", clearEmojiStats);
    client.getMatrixClient().addCommand("setprofile", setProfile);
    client.getMatrixClient().addCommand("addwidget", addWidget);
    client.getMatrixClient().addCommand("rainbow", sendRainbow);
  }

  @override
  List<String> getCommands() {
    return {
      ...client.getMatrixClient().commands.keys,
      ..._localCommands.where(
        (command) =>
            command != 'roomupgrade' || preferences.developerMode.value,
      ),
    }.toList()..sort();
  }

  @override
  Future<void> executeCommand(
    String string,
    Room room, {
    TimelineEvent? interactingEvent,
    EventInteractionType? type,
  }) async {
    var mxRoom = (room as MatrixRoom).matrixRoom;
    matrix.Event? event;
    if (interactingEvent != null) {
      event = (interactingEvent as MatrixTimelineEvent).event;
    }

    final localCommandHandled = await _executeLocalCommand(string, room);
    if (localCommandHandled) {
      return;
    }

    var match = sed_pattern.firstMatch(string);

    if (match != null && interactingEvent == null && type == null) {
      TimelineEvent? editingEvent;
      for (final event in room.timeline!.events.take(20)) {
        if (event.senderId != room.client.self!.identifier) continue;
        if (event is! TimelineEventMessage) continue;
        editingEvent = event;
        break;
      }
      if (editingEvent != null) {
        await room.sendMessage(
          message: editingEvent.plainTextBody.replaceFirst(
            match[1]!,
            match[2]!,
          ),
          replaceEvent: editingEvent,
        );
        return;
      }
    }

    await client.getMatrixClient().parseAndRunCommand(
      mxRoom,
      string,
      inReplyTo: type == EventInteractionType.reply ? event : null,
      editEventId: type == EventInteractionType.edit ? event?.eventId : null,
    );
  }

  @override
  bool isExecutable(String string) {
    if (string.startsWith("/")) {
      var command = string.substring(1).split(" ").first;
      return client.getMatrixClient().commands.containsKey(command) ||
          _localCommands.contains(command);
    } else if (sed_pattern.firstMatch(string) != null)
      return true;

    return false;
  }

  FutureOr<String?> sendJson(matrix.CommandArgs args, StringBuffer? out) {
    var json = const JsonDecoder().convert(args.msg) as Map<String, dynamic>;

    var tx = client.getMatrixClient().generateUniqueTransactionId();
    client.getMatrixClient().sendMessage(
      args.room!.id,
      json["type"],
      tx,
      json['content'],
    );

    return null;
  }

  @override
  bool isPossiblyCommand(String string) {
    return string.startsWith("/");
  }

  FutureOr<String?> setStatus(
    matrix.CommandArgs args,
    StringBuffer? out,
  ) async {
    client.getComponent<UserProfileComponent>()?.setStatus(args.msg);

    await client.getMatrixClient().setPresence(
      client.getMatrixClient().userID!,
      PresenceType.online,
      statusMsg: args.msg,
    );

    return null;
  }

  FutureOr<String?> clearEmojiStats(
    matrix.CommandArgs args,
    StringBuffer? out,
  ) async {
    var c = client.getComponent<RecentEmoticonComponent>();
    c?.clear();
    return null;
  }

  FutureOr<String?> setProfile(
    matrix.CommandArgs args,
    StringBuffer? stdout,
  ) async {
    final parts = args.msg.split(" ");
    final field = parts[0];
    final content = parts.sublist(1).join(" ");
    dynamic result = content;
    try {
      result = jsonDecode(content);
    } catch (e, s) {
      Log.onError(e, s);
    }

    var comp = client.getComponent<MatrixProfileComponent>();
    comp?.setField(field, result);

    return null;
  }

  FutureOr<String?> addWidget(
    matrix.CommandArgs args,
    StringBuffer? out,
  ) async {
    if (args.room == null) return null;

    var url = Uri.parse(args.msg);
    var uuid = const Uuid();
    var id = uuid.v4();

    var content = {
      "type": "m.custom",
      "url": url.toString(),
      "name": "Custom",
      "id": id,
      "creatorUserId": client.self!.identifier,
      "roomId": args.room!.id,
    };

    if (url.host == "calendar-widget.ourgalaxy.space") {
      content["type"] = "chat.commet.widgets.calendar";
      content["name"] = "Calendar";
    }

    await client.matrixClient.setRoomStateWithKey(
      args.room!.id,
      "im.vector.modular.widgets",
      id,
      content,
    );

    return null;
  }

  FutureOr<String?> sendRainbow(
    matrix.CommandArgs args,
    StringBuffer? out,
  ) async {
    if (args.room == null) return null;
    if (args.msg.isEmpty) return null;

    final content = {
      "msgtype": "m.text",
      "body": args.msg,
      "formatted_body": rainbowFormattedBody(args.msg),
      "format": "org.matrix.custom.html",
    };

    return await args.room!.sendEvent(
      content,
      inReplyTo: args.inReplyTo,
      editEventId: args.editEventId,
      txid: args.txid,
    );
  }

  Future<bool> _executeLocalCommand(String input, MatrixRoom room) async {
    if (!input.startsWith("/")) {
      return false;
    }

    final parts = input.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) {
      return false;
    }

    final command = parts.first.substring(1).toLowerCase();
    switch (command) {
      case "inviteall":
        return _executeInviteAll(parts, room);
      case "roomupgrade":
        if (!preferences.developerMode.value) {
          await _showRoomUpgradeCommandIssue(
            '/roomupgrade is available only in developer mode.',
          );
          return true;
        }
        return _executeRoomUpgrade(parts, room);
      case "sharehistory":
        return _executeShareHistory(parts, room);
      default:
        return false;
    }
  }

  Future<bool> _executeRoomUpgrade(List<String> parts, MatrixRoom room) async {
    final version = parts.length > 1 ? parts[1].trim() : '';
    if (version.isEmpty) {
      await _showRoomUpgradeCommandIssue('Usage: /roomupgrade <room version>.');
      return true;
    }

    final context = navigator.currentContext;
    try {
      final result = await MatrixRoomMigration(
        client,
      ).upgrade(source: room, targetVersion: version);
      if (context != null) {
        await AdaptiveDialog.show(
          context,
          title: result.isComplete
              ? 'Migration ready'
              : 'Migration needs attention',
          builder: (_) => SelectableText(
            result.isComplete
                ? 'The successor room is ready. ${result.invitedMemberIds.length} member(s) were invited.'
                : '${result.invitedMemberIds.length} member(s) were invited. '
                      '${_roomUpgradeResultIssues(result)} need another attempt. '
                      'Open Room Admin settings and use Recover missing members to retry safely.',
          ),
        );
      }
      if (result.isComplete) {
        EventBus.openRoom.add((result.successorRoomId, client.identifier));
      }
    } catch (error, stackTrace) {
      if (context != null) {
        await AdaptiveDialog.showError(context, error, stackTrace);
      }
    }
    return true;
  }

  String _roomUpgradeResultIssues(MatrixRoomMigrationResult result) {
    final issues = <String>[];
    if (result.failedMemberIds.isNotEmpty) {
      issues.add('${result.failedMemberIds.length} invite(s)');
    }
    if (result.failedSpaceIds.isNotEmpty) {
      issues.add(
        '${result.failedSpaceIds.length} Space change(s)'
        '${_roomUpgradeFailureDetail(result.spaceFailure)}',
      );
    }
    if (!result.permissionsRestored) {
      issues.add(
        'the permission restore${_roomUpgradeFailureDetail(result.permissionFailure)}',
      );
    }
    return issues.join(', ');
  }

  String _roomUpgradeFailureDetail(String? label) {
    return label == null ? '' : ' [$label]';
  }

  Future<void> _showRoomUpgradeCommandIssue(String message) async {
    final context = navigator.currentContext;
    if (context == null) return;
    await AdaptiveDialog.show(
      context,
      title: 'Room migration unavailable',
      builder: (_) => SelectableText(message),
    );
  }

  Future<bool> _executeShareHistory(List<String> parts, MatrixRoom room) async {
    if (!room.isE2EE) {
      await _showShareHistoryCommandIssue(
        "/sharehistory only works in encrypted rooms.",
      );
      return true;
    }

    if (!room.matrixRoom.canChangeStateEvent("m.room.history_visibility")) {
      await _showShareHistoryCommandIssue(
        "Only room admins can use /sharehistory.",
      );
      return true;
    }

    final participants = await room.matrixRoom.requestParticipants();
    final joinedUserIds = participants
        .where((member) => member.membership == matrix.Membership.join)
        .map((member) => member.id)
        .toSet();

    final targetResolution = matrixHistoryResolveShareTargets(
      explicitTargetUserIds: parts.skip(1),
      joinedUserIds: joinedUserIds,
      selfUserId: client.matrixClient.userID,
    );
    if (!targetResolution.canProceed) {
      await _showShareHistoryCommandIssue(
        targetResolution.issue ?? "No users were selected for /sharehistory.",
      );
      return true;
    }
    final targetUserIds = targetResolution.targetUserIds;
    if (targetResolution.inferredSingleTarget) {
      Log.i(
        "sharehistory: inferred single joined target "
        "target=${MatrixClient.hash(targetUserIds.single).substring(0, 12)}",
      );
    }

    final preview = await client.previewHistoryShare(room, targetUserIds);

    final context = navigator.currentContext;
    if (context == null) {
      Log.w(
        "sharehistory: no context available - cannot show listener dialog.",
      );
      return true;
    }

    final decision = await _showShareHistoryConfirmation(preview);
    if (decision == null || decision == _HistoryShareDecision.cancel) {
      Log.i(
        "sharehistory: cancelled by admin "
        "targets=${targetUserIds.length}",
      );
      return true;
    }

    final report = await client.shareHistoryKeys(
      room,
      targetUserIds,
      preview: preview,
    );

    Log.i(
      "sharehistory: dispatched available sessions "
      "targets=${targetUserIds.length} "
      "eligibleDevices=${preview.eligibleDevices.length} "
      "sessions=${report.sharedSessionCount} "
      "deliveries=${report.sharedDeviceDeliveries}",
    );

    await AdaptiveDialog.show(
      context,
      title: "Waiting for Key Requests",
      builder: (_) => _HistoryShareListenerWidget(
        client: client,
        room: room,
        targetUserIds: targetUserIds,
        allowBreakGlassPrompts: decision == _HistoryShareDecision.breakGlass,
        report: report,
      ),
    );

    await _showLocalReport(report);
    return true;
  }

  Future<bool> _executeInviteAll(List<String> parts, MatrixRoom room) async {
    if (parts.length > 1) {
      throw Exception("Usage: /inviteall");
    }

    final space = _singleContainingSpaceFor(room);
    if (space == null) {
      throw Exception(
        "/inviteall requires this channel to belong to exactly one server/space.",
      );
    }

    if (space is! MatrixSpace) {
      throw Exception(
        "/inviteall is not supported for this server/space provider.",
      );
    }

    final selfId = client.matrixClient.userID;
    if (selfId == null ||
        !space.matrixRoom.canChangeStateEvent(
          matrix.EventTypes.RoomPowerLevels,
        )) {
      throw Exception("Only server admins can use /inviteall.");
    }

    if (!room.matrixRoom.canInvite) {
      throw Exception(
        "You do not have permission to invite users to this channel.",
      );
    }

    final spaceMembers = await _requestParticipants(
      space.matrixRoom,
      memberships: [matrix.Membership.join],
      suppressWarning: true,
      cache: true,
    );
    if (spaceMembers.isEmpty) {
      throw Exception(
        "No joined server/space members were available to invite.",
      );
    }

    final currentRoomMembers = await _requestParticipants(
      room.matrixRoom,
      memberships: [matrix.Membership.join, matrix.Membership.invite],
      suppressWarning: true,
      cache: true,
    );
    final currentRoomMemberIds = currentRoomMembers
        .map((member) => member.id)
        .toSet();

    final candidateUserIds = spaceMembers
        .map((member) => member.id)
        .where((userId) => userId != selfId)
        .toSet();

    final targetUserIds =
        candidateUserIds
            .where((userId) => !currentRoomMemberIds.contains(userId))
            .toList()
          ..sort();

    final report = MatrixInviteAllReport(
      spaceName: space.displayName,
      roomName: room.displayName,
      candidateCount: candidateUserIds.length,
      skippedCount: candidateUserIds.length - targetUserIds.length,
    );

    for (final userId in targetUserIds) {
      try {
        await room.matrixRoom.invite(
          userId,
          reason: "Invited by /inviteall from ${space.displayName}",
        );
        await _shareEncryptedHistoryAfterInvite(room, userId);
        report.invitedUserIds.add(userId);
      } catch (error, stack) {
        Log.onError(error, stack);
        report.failedUserIds[userId] = error.toString();
      }
    }

    await _showInviteAllReport(report);
    return true;
  }

  Future<List<matrix.User>> _requestParticipants(
    matrix.Room room, {
    required List<matrix.Membership> memberships,
    required bool suppressWarning,
    bool? cache,
  }) {
    return room.requestParticipants(memberships, suppressWarning, cache);
  }

  Space? _singleContainingSpaceFor(MatrixRoom room) {
    final containingSpaces = client.spaces
        .where((space) => space.containsRoom(room.identifier))
        .toList();

    if (containingSpaces.length != 1) {
      return null;
    }

    return containingSpaces.single;
  }

  Future<void> _showInviteAllReport(MatrixInviteAllReport report) async {
    final context = navigator.currentContext;
    if (context == null) {
      Log.w("Unable to show /inviteall report because no context exists.");
      return;
    }

    await AdaptiveDialog.show(
      context,
      title: "Invite All Report",
      builder: (_) => SizedBox(
        width: 460,
        child: SelectableText(report.toMultilineString()),
      ),
    );
  }

  Future<void> _showShareHistoryCommandIssue(String message) async {
    final context = navigator.currentContext;
    if (context == null) {
      Log.w("sharehistory: $message");
      return;
    }

    await AdaptiveDialog.show(
      context,
      title: "Share History",
      builder: (_) => SizedBox(width: 460, child: SelectableText(message)),
    );
  }

  Future<_HistoryShareDecision?> _showShareHistoryConfirmation(
    MatrixHistorySharePreview preview,
  ) {
    final context = navigator.currentContext;
    if (context == null) {
      return Future.value(null);
    }

    final report = preview.report;
    return AdaptiveDialog.show<_HistoryShareDecision>(
      context,
      title: "Share Encrypted History?",
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        return SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "This sends locally available room keys to eligible target "
                "devices now, then waits briefly for any new key requests from "
                "the target user. Devices allowed by your current Matrix "
                "key-sharing policy are used by default.",
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                "Targets: ${report.targetUserIds.length}\n"
                "Stored sessions: ${report.availableSessionCount}\n"
                "Eligible devices: ${report.eligibleDeviceCount}\n"
                "Ineligible devices: ${report.ineligibleDeviceCount}\n"
                "Verified devices seen: ${report.verifiedDeviceCount}\n"
                "Unverified devices seen: ${report.unverifiedDeviceCount}",
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                "Break-glass prompts for each ineligible requesting device. "
                "Use it only when you can confirm the device belongs to the "
                "user through another trusted channel.",
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(_HistoryShareDecision.eligibleOnly),
                child: const Text("Share to eligible devices"),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_HistoryShareDecision.breakGlass),
                child: const Text("Share and prompt for requests"),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_HistoryShareDecision.cancel),
                child: const Text("Cancel"),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareEncryptedHistoryAfterInvite(
    MatrixRoom room,
    String userId,
  ) async {
    if (!room.isE2EE) {
      return;
    }
    if (!matrixHistoryVisibilityAllowsInviteSharing(
      room.matrixRoom.historyVisibility,
    )) {
      Log.i(
        "inviteHistoryShare: skipped reason=history_visibility_not_shared "
        "room=${MatrixClient.hash(room.identifier).substring(0, 12)} "
        "target=${MatrixClient.hash(userId).substring(0, 12)} "
        "visibility=${room.matrixRoom.historyVisibility?.text ?? 'unknown'}",
      );
      return;
    }

    try {
      await client.shareHistoryBundleForInvite(room, userId);
    } catch (error, stack) {
      Log.onError(
        error,
        stack,
        content:
            "inviteHistoryShare: failed "
            "room=${MatrixClient.hash(room.identifier).substring(0, 12)} "
            "target=${MatrixClient.hash(userId).substring(0, 12)}",
      );
    }
  }

  Future<void> _showLocalReport(MatrixHistoryShareReport report) async {
    final context = navigator.currentContext;
    if (context == null) {
      Log.w("Unable to show /sharehistory report because no context exists.");
      return;
    }

    await AdaptiveDialog.show(
      context,
      title: "History Share Report",
      builder: (_) => SizedBox(
        width: 460,
        child: SelectableText(report.toMultilineString()),
      ),
    );
  }
}

enum _HistoryShareDecision { eligibleOnly, breakGlass, cancel }

class MatrixInviteAllReport {
  MatrixInviteAllReport({
    required this.spaceName,
    required this.roomName,
    required this.candidateCount,
    required this.skippedCount,
  });

  final String spaceName;
  final String roomName;
  final int candidateCount;
  final int skippedCount;
  final List<String> invitedUserIds = [];
  final Map<String, String> failedUserIds = {};

  String toMultilineString() {
    final lines = <String>[
      "Server/space: $spaceName",
      "Channel: $roomName",
      "Joined server/space members checked: $candidateCount",
      "Already in or invited to channel: $skippedCount",
      "Invites sent: ${invitedUserIds.length}",
      "Invite failures: ${failedUserIds.length}",
    ];

    if (invitedUserIds.isEmpty && failedUserIds.isEmpty) {
      lines.add("");
      lines.add("No invites were needed.");
    }

    if (invitedUserIds.isNotEmpty) {
      lines.add("");
      lines.add("Invited:");
      lines.addAll(invitedUserIds.map((userId) => "- $userId"));
    }

    if (failedUserIds.isNotEmpty) {
      lines.add("");
      lines.add("Failed:");
      failedUserIds.forEach((userId, error) {
        lines.add("- $userId: $error");
      });
    }

    return lines.join("\n");
  }
}

// Listener dialog.

class _HistoryShareListenerWidget extends StatefulWidget {
  const _HistoryShareListenerWidget({
    required this.client,
    required this.room,
    required this.targetUserIds,
    required this.allowBreakGlassPrompts,
    required this.report,
  });

  final MatrixClient client;
  final MatrixRoom room;
  final List<String> targetUserIds;
  final bool allowBreakGlassPrompts;
  final MatrixHistoryShareReport report;

  @override
  State<_HistoryShareListenerWidget> createState() =>
      _HistoryShareListenerWidgetState();
}

class _HistoryShareListenerWidgetState
    extends State<_HistoryShareListenerWidget> {
  static const _timeoutSeconds = 60;

  late final Timer _countdown;
  late final StreamSubscription<matrix_crypto.RoomKeyRequest> _eventSub;
  final Set<String> _breakGlassConfirmedDevices = <String>{};
  int _remaining = _timeoutSeconds;

  @override
  void initState() {
    super.initState();

    _eventSub = widget.client.matrixClient.onRoomKeyRequest.stream
        .where(
          (request) =>
              widget.targetUserIds.contains(request.sender) &&
              request.room.id == widget.room.identifier,
        )
        .listen(_onKeyRequest);

    _countdown = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    _countdown.cancel();
    _eventSub.cancel();
    super.dispose();
  }

  void _tick(Timer _) {
    if (!mounted) return;
    setState(() => _remaining--);
    if (_remaining <= 0) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onKeyRequest(matrix_crypto.RoomKeyRequest request) async {
    final device = request.requestingDevice;
    if (device.blocked) {
      await widget.client.respondToRoomKeyRequest(
        widget.room,
        request,
        widget.report,
        allowIneligibleDevice: false,
      );
      if (mounted) setState(() {});
      return;
    }

    final deviceKey = _deviceConfirmationKey(device);
    final eligibleDevice = matrixHistoryDeviceEligibleForKeyShare(device);
    var allowIneligibleDevice = false;

    if (!eligibleDevice) {
      if (!widget.allowBreakGlassPrompts ||
          !_breakGlassConfirmedDevices.contains(deviceKey)) {
        final confirmed = widget.allowBreakGlassPrompts
            ? await _confirmIneligibleDevice(request)
            : false;
        if (confirmed != true) {
          widget.report.ineligibleRequestsIgnored += 1;
          Log.w(
            "sharehistory: ineligible key request not approved "
            "user=${MatrixClient.hash(device.userId).substring(0, 12)} "
            "device=${MatrixClient.hash(device.deviceId ?? '').substring(0, 12)}",
          );
          if (mounted) setState(() {});
          return;
        }
        _breakGlassConfirmedDevices.add(deviceKey);
      }
      allowIneligibleDevice = true;
    }

    final outcome = await widget.client.respondToRoomKeyRequest(
      widget.room,
      request,
      widget.report,
      allowIneligibleDevice: allowIneligibleDevice,
    );
    if (outcome == MatrixKeyRequestOutcome.deferred) {
      // The break-glass approval above is deliberately KEPT. The user
      // consented to this device and nothing was refused, so a repeat request
      // should be answered rather than prompt them a second time.
      Log.w(
        "sharehistory: key request deferred, encryption storage resuming "
        "user=${MatrixClient.hash(device.userId).substring(0, 12)} "
        "device=${MatrixClient.hash(device.deviceId ?? '').substring(0, 12)}",
      );
    }
    // Refresh on EVERY outcome. Refreshing only on a send is what made a
    // deferral invisible here: the report had counted it and the dialog never
    // redrew, so a user-consented share failed silently in exactly the
    // suspend/resume window the gate exists for.
    if (mounted) setState(() {});
  }

  Future<bool?> _confirmIneligibleDevice(matrix_crypto.RoomKeyRequest request) {
    if (!mounted) {
      return Future.value(false);
    }

    final device = request.requestingDevice;
    return AdaptiveDialog.show<bool>(
      context,
      title: "Share With Ineligible Device?",
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        return SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "This device is not eligible under your current Matrix "
                "key-sharing policy. Only continue if you confirmed through "
                "another trusted channel that it belongs to the target user.",
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SelectableText(
                "User: ${device.userId}\nDevice: ${device.deviceId ?? 'unknown'}",
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Share with this device"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Do not share"),
              ),
            ],
          ),
        );
      },
    );
  }

  String _deviceConfirmationKey(matrix.DeviceKeys device) {
    return '${device.userId}|${device.deviceId ?? ''}|'
        '${device.curve25519Key ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final deliveries = widget.report.sharedDeviceDeliveries;
    final sessions = widget.report.sharedSessionCount;

    return SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Ask the target user to open any undecryptable message and choose "
            "Re-request encryption keys. Keys are sent as each request arrives.",
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text("Listening for requests from:", style: textTheme.labelLarge),
          const SizedBox(height: 6),
          for (final id in widget.targetUserIds)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text("- $id", style: textTheme.bodySmall),
            ),
          if (widget.report.usersWithoutEligibleDevices.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final id in widget.report.usersWithoutEligibleDevices)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Text(
                  "- $id: no eligible devices found",
                  style: textTheme.bodySmall,
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            deliveries == 0
                ? "Waiting for first key request..."
                : "Keys dispatched: $deliveries / Sessions fulfilled: $sessions",
            style: textTheme.bodyMedium,
          ),
          if (widget.report.ineligibleRequestsIgnored > 0) ...[
            const SizedBox(height: 8),
            Text(
              "Ignored ineligible requests: "
              "${widget.report.ineligibleRequestsIgnored}",
              style: textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Auto-closing in ${_remaining}s",
                style: textTheme.bodySmall,
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Done"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
