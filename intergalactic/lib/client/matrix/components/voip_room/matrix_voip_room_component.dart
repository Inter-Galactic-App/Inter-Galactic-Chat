import 'dart:async';

import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/matrix/components/matrix_sync_listener.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:matrix/matrix.dart';

class MatrixVoipRoomComponent
    implements
        VoipRoomComponent<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener {
  static const callMemberStateEvent = "org.matrix.msc3401.call.member";
  static const callMemberExpiresTsKey = "m.expires_ts";
  static const callMembershipsKey = "memberships";
  static const callMembershipExpiresTsKey = "expires_ts";
  static const callClientInfoKey = "chat.intergalactic.client_info";
  static const callMembershipExpiry = Duration(seconds: 75);
  static const callMembershipRefreshInterval = Duration(seconds: 25);
  static const legacyMembershipMaxAge = Duration(minutes: 2);

  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  late MatrixLivekitBackend backend;

  VoipSession? currentSession;
  Timer? _participantExpiryTimer;
  final Set<String> _locallyClearedStateKeys = {};
  Future<VoipSession?>? _joinInFlight;

  MatrixVoipRoomComponent(this.client, this.room) {
    backend = MatrixLivekitBackend(room);
  }

  static bool isVoipRoom(MatrixRoom room) {
    return room.matrixRoom.getState(EventTypes.RoomCreate)?.content['type'] ==
        "org.matrix.msc3417.call";
  }

  StreamController _onParticipantsChanged = StreamController.broadcast();

  @override
  onSync(JoinedRoomUpdate update) {
    if (update.timeline?.events == null) {
      return;
    }

    for (var event in update.timeline!.events!) {
      if (event.type == callMemberStateEvent) {
        final stateKey = event.stateKey;
        if (stateKey != null && event.content.isNotEmpty) {
          _locallyClearedStateKeys.remove(stateKey);
        }

        _notifyParticipantsChanged();
      }
    }
  }

  static String callMemberStateKeyFor({
    required String userId,
    required String deviceId,
  }) {
    return "_${userId}_${deviceId}_m.call";
  }

  static Map<String, dynamic> buildCallMemberContent({
    required String deviceId,
    required String roomId,
    required Iterable<Uri> foci,
  }) {
    final expiresAt =
        DateTime.now().add(callMembershipExpiry).millisecondsSinceEpoch;
    final clientInfo = BuildConfig.matrixClientMetadata;

    return {
      "application": "m.call",
      "call_id": "",
      callClientInfoKey: clientInfo,
      "device_id": deviceId,
      "expires": callMembershipExpiry.inMilliseconds,
      callMemberExpiresTsKey: expiresAt,
      callMembershipsKey: [
        {
          "application": "m.call",
          "call_id": "",
          callClientInfoKey: clientInfo,
          "device_id": deviceId,
          "expires_ts": expiresAt,
          "foci_active": foci
              .map((e) => {
                    "type": "livekit",
                    "livekit_alias": roomId,
                    "livekit_service_url": e.toString()
                  })
              .toList(),
          "membershipID": deviceId,
          "scope": "m.room"
        }
      ],
      "foci_preferred": foci
          .map((e) => {
                "type": "livekit",
                "livekit_alias": roomId,
                "livekit_service_url": e.toString()
              })
          .toList(),
      "focus_active": {
        "focus_selection": "oldest_membership",
        "type": "livekit"
      },
      "scope": "m.room"
    };
  }

  static Map<String, dynamic>? getClientInfoFromCallMemberContent(
    Map<String, Object?> content,
  ) {
    final topLevel = content[callClientInfoKey];
    if (topLevel is Map) {
      return Map<String, dynamic>.from(topLevel);
    }

    final legacyTopLevel = _legacyClientInfoFromMap(content);
    if (legacyTopLevel != null) {
      return legacyTopLevel;
    }

    final memberships = content[callMembershipsKey];
    if (memberships is List) {
      for (final membership in memberships) {
        if (membership is! Map) continue;
        final membershipClientInfo = membership[callClientInfoKey];
        if (membershipClientInfo is Map) {
          return Map<String, dynamic>.from(membershipClientInfo);
        }

        final legacyMembership = _legacyClientInfoFromMap(membership);
        if (legacyMembership != null) {
          return legacyMembership;
        }
      }
    }

    return null;
  }

  static Map<String, dynamic>? _legacyClientInfoFromMap(Map content) {
    final legacyClientInfo = <String, dynamic>{};
    final app = content["app"];
    final appName = content["app_name"];
    final userAgent = content["user_agent"];

    if (app is String) legacyClientInfo["app"] = app;
    if (appName is String) legacyClientInfo["app_name"] = appName;
    if (userAgent is String) legacyClientInfo["user_agent"] = userAgent;

    if (legacyClientInfo.isEmpty) {
      return null;
    }

    return legacyClientInfo;
  }

  static bool _hasInterGalacticClientInfo(Map<String, Object?> content) {
    final clientInfo = getClientInfoFromCallMemberContent(content);
    if (clientInfo == null) {
      return false;
    }

    final app = clientInfo["app"];
    final appName = clientInfo["app_name"];
    final userAgent = clientInfo["user_agent"];

    return app == BuildConfig.app ||
        (appName is String && appName.contains(BuildConfig.app)) ||
        (userAgent is String && userAgent.startsWith("InterGalactic/"));
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return null;
  }

  static int? getCallMembershipExpiryMs(StrippedStateEvent event) {
    final content = event.content;
    final topLevelExpiry = _readInt(content[callMemberExpiresTsKey]) ??
        _readInt(content[callMembershipExpiresTsKey]);
    if (topLevelExpiry != null) {
      return topLevelExpiry;
    }

    final membershipExpiries = _readMembershipExpiries(content).toList();
    if (membershipExpiries.isEmpty) {
      return null;
    }

    return membershipExpiries.reduce((a, b) => a > b ? a : b);
  }

  static Iterable<int> _readMembershipExpiries(
    Map<String, Object?> content,
  ) sync* {
    final memberships = content[callMembershipsKey];
    if (memberships is! List) {
      return;
    }

    for (final membership in memberships) {
      if (membership is! Map) {
        continue;
      }

      final expiresTs = _readInt(membership[callMembershipExpiresTsKey]);
      if (expiresTs != null) {
        yield expiresTs;
      }
    }
  }

  static bool isCallMembershipActive(StrippedStateEvent event, {int? nowMs}) {
    final content = event.content;

    if (content.isEmpty) {
      return false;
    }

    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final memberships = content[callMembershipsKey];
    if (memberships is List && memberships.isEmpty) {
      return false;
    }

    if (memberships is List) {
      final membershipExpiries = _readMembershipExpiries(content).toList();
      if (membershipExpiries.isNotEmpty) {
        return membershipExpiries.any((expiresAt) => expiresAt > now);
      }
    }

    final calls = content["m.calls"];
    if (calls is List && calls.isEmpty) {
      return false;
    }

    final expiresAt = getCallMembershipExpiryMs(event);
    if (expiresAt != null && expiresAt <= now) {
      return false;
    }

    if (expiresAt == null) {
      if (calls is List && calls.isNotEmpty) {
        return true;
      }

      final legacyExpires = _readInt(content["expires"]);

      if (legacyExpires == null || legacyExpires <= 0) {
        return false;
      }

      // Older Inter Galactic builds wrote a four-hour relative expiry without
      // the absolute MSC3401 timestamp we need for deterministic UI pruning.
      // Only prune memberships we can identify as ours; other clients may use
      // long relative values for active MatrixRTC memberships.
      if (legacyExpires > legacyMembershipMaxAge.inMilliseconds &&
          _hasInterGalacticClientInfo(content)) {
        return false;
      }
    }

    return true;
  }

  String? get localCallStateKey {
    final userId = client.matrixClient.userID;
    final deviceId = client.matrixClient.deviceID;
    if (userId == null || deviceId == null) {
      return null;
    }

    return callMemberStateKeyFor(userId: userId, deviceId: deviceId);
  }

  @override
  List<String> getCurrentParticipants() {
    final state = room.matrixRoom.states[callMemberStateEvent];
    if (state == null) {
      return [];
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final localKey = localCallStateKey;
    List<String> participants = List.empty(growable: true);
    for (var pair in state.entries) {
      if (_locallyClearedStateKeys.contains(pair.key)) continue;
      if (pair.key == localKey && currentSession == null) continue;
      if (!isCallMembershipActive(pair.value, nowMs: now)) continue;

      final sender = pair.value.senderId;
      if (participants.contains(sender)) continue;

      participants.add(sender);
    }

    _scheduleParticipantExpiryRefresh(state.values);
    return participants;
  }

  @override
  Stream<void> get onParticipantsChanged => _onParticipantsChanged.stream;

  @override
  Future<VoipSession?> joinCall() async {
    final activeSession = currentSession;
    if (activeSession != null && activeSession.state != VoipState.ended) {
      return activeSession;
    }

    final existingJoin = _joinInFlight;
    if (existingJoin != null) {
      return existingJoin;
    }

    final joinFuture = _joinCall();
    _joinInFlight = joinFuture;
    try {
      return await joinFuture;
    } finally {
      if (identical(_joinInFlight, joinFuture)) {
        _joinInFlight = null;
      }
    }
  }

  Future<VoipSession?> _joinCall() async {
    final localKey = localCallStateKey;
    if (localKey != null) {
      _locallyClearedStateKeys.remove(localKey);
    }

    try {
      currentSession = await backend.join();
    } catch (_) {
      currentSession = null;
      if (localKey != null) {
        _locallyClearedStateKeys.add(localKey);
      }
      _notifyParticipantsChanged();
      rethrow;
    }

    currentSession?.onStateChanged.listen(onStateChanged);
    _notifyParticipantsChanged();
    return currentSession;
  }

  @override
  Future<String?> getCallServerUrl() async {
    final url = await backend.getFociUrl();
    return url.firstOrNull?.authority.toString();
  }

  void onStateChanged(void event) {
    final state = currentSession?.state;
    print("Got call state: ${state}");

    if (state == VoipState.ended) {
      final localKey = localCallStateKey;
      if (localKey != null) {
        _locallyClearedStateKeys.add(localKey);
      }

      currentSession = null;
      _notifyParticipantsChanged();
    }
  }

  @override
  bool get canJoinCall => room.matrixRoom.canChangeStateEvent(
        MatrixVoipRoomComponent.callMemberStateEvent,
      );

  /// Whether the local user has permission to remove others from the call.
  /// We reuse the `canKick` power-level check as the appropriate bar.
  bool get canRemoveParticipants => room.matrixRoom.canKick;

  /// Remove a participant from the call by clearing all of their
  /// `org.matrix.msc3401.call.member` state keys.  This does not kick the
  /// user from the room — it only clears their call membership.
  Future<void> removeParticipantFromCall(String userId) async {
    try {
      final state = room.matrixRoom.states[callMemberStateEvent];
      if (state == null) return;

      // State keys follow the format `_${userId}_${deviceId}_m.call`.
      // Match on both the state key prefix and the event senderId so we catch
      // entries regardless of who originally set the state (the user themselves
      // or a room admin acting on their behalf).
      bool belongsToUser(MapEntry<String, dynamic> entry) {
        if (entry.value.senderId == userId) return true;
        if (entry.key.startsWith('_${userId}_')) return true;
        if (entry.key == userId) return true;
        return false;
      }

      final futures = [
        for (final entry in state.entries)
          if (entry.value.content.isNotEmpty && belongsToUser(entry)) ...[
            Future.sync(() {
              _locallyClearedStateKeys.add(entry.key);
            }),
            client.matrixClient.setRoomStateWithKey(
              room.identifier,
              callMemberStateEvent,
              entry.key,
              {},
            ),
          ],
      ];

      if (futures.isEmpty) return;

      await Future.wait(futures);

      // Notify listeners immediately so the UI updates without waiting for the
      // next /sync response.
      _notifyParticipantsChanged();
    } catch (e) {
      // Log but don't rethrow — the UI should not break if a server error
      // occurs while removing a participant from the call.
      print('removeParticipantFromCall failed for $userId: $e');
    }
  }

  @override
  Future<void> clearAllCallMembershipStatus() async {
    final state = room.matrixRoom.states[callMemberStateEvent];
    if (state == null) {
      return;
    }

    var futures = [
      for (var entry in state.entries)
        if (entry.value.senderId == client.matrixClient.userID) ...[
          Future.sync(() {
            _locallyClearedStateKeys.add(entry.key);
          }),
          client.matrixClient.setRoomStateWithKey(
            room.identifier,
            MatrixVoipRoomComponent.callMemberStateEvent,
            entry.key,
            {},
          ),
        ],
    ];

    await Future.wait(futures);
    _notifyParticipantsChanged();
  }

  void _notifyParticipantsChanged() {
    _onParticipantsChanged.add(null);
    _scheduleParticipantExpiryRefresh(
      room.matrixRoom.states[callMemberStateEvent]?.values ?? const [],
    );
  }

  void _scheduleParticipantExpiryRefresh(Iterable<StrippedStateEvent> events) {
    _participantExpiryTimer?.cancel();
    _participantExpiryTimer = null;

    final now = DateTime.now().millisecondsSinceEpoch;
    int? nextExpiry;

    for (final event in events) {
      if (!isCallMembershipActive(event, nowMs: now)) {
        continue;
      }

      final expiresAt = getCallMembershipExpiryMs(event);
      if (expiresAt == null || expiresAt <= now) {
        continue;
      }

      nextExpiry =
          nextExpiry == null || expiresAt < nextExpiry ? expiresAt : nextExpiry;
    }

    if (nextExpiry == null) {
      return;
    }

    final delay = Duration(
      milliseconds: (nextExpiry - now + 1000).clamp(1000, 2147483647),
    );
    _participantExpiryTimer = Timer(delay, _notifyParticipantsChanged);
  }
}
