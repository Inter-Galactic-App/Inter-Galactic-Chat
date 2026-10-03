// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';

import 'package:intergalactic/client/bug_report/pending_native_call_crash_guard.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/voip/client_close_call_teardown.dart';
import 'package:intergalactic/client/components/voip/audio/ios_call_audio_session.dart';
import 'package:intergalactic/client/components/voip/voip_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_session_owner.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_session_signal_emitter.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_session.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/voip_settings/voip_turn_fallback_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as mx;
import 'package:webrtc_interface/src/mediadevices.dart';
import 'package:webrtc_interface/src/rtc_peerconnection.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

typedef DirectCallSessionFactory =
    DirectCallSession Function(mx.CallSession session, MatrixClient client);

class MatrixVoipComponent
    implements
        VoipComponent<MatrixClient>,
        EventHandlerComponent,
        DisposableComponent,
        mx.WebRTCDelegate {
  late mx.VoIP voip;

  @override
  MatrixClient client;

  final DirectCallSessionSignalEmitter _sessionSignalEmitter;
  final DirectCallSessionFactory _sessionFactory;
  final DirectCallSessionOwner<DirectCallSession> _sessionOwner =
      DirectCallSessionOwner();

  @override
  Stream<VoipSession> get onSessionStarted =>
      _sessionSignalEmitter.onSessionStarted;

  @override
  Stream<VoipSession> get onSessionEnded =>
      _sessionSignalEmitter.onSessionEnded;

  @override
  bool get canHandleNewCall => true;

  @override
  bool get isWeb => PlatformUtils.isWeb;

  @override
  MediaDevices get mediaDevices => webrtc.navigator.mediaDevices;

  MatrixVoipComponent(
    this.client, {
    DirectCallSessionSignalEmitter? sessionSignalEmitter,
    @visibleForTesting mx.VoIP? voip,
    @visibleForTesting DirectCallSessionFactory? sessionFactory,
    this.hangUpBoundOnClose = clientCloseHangUpBound,
  }) : _sessionSignalEmitter =
           sessionSignalEmitter ?? DirectCallSessionSignalEmitter(),
       _sessionFactory = sessionFactory ?? MatrixVoipSession.new {
    this.voip = voip ?? mx.VoIP(client.getMatrixClient(), this);
  }

  /// How long [dispose] waits for this client's direct calls to hang up.
  ///
  /// [clientCloseHangUpBound] in production; a parameter only so a test can
  /// prove the bound fires without waiting the full five seconds.
  final Duration hangUpBoundOnClose;

  String _sessionOwnerKey(mx.CallSession session) =>
      '${session.room.id}/${session.callId}';

  DirectCallSession _startSession(mx.CallSession session) {
    return _sessionOwner.start(
      _sessionOwnerKey(session),
      () => _sessionFactory(session, client),
    );
  }

  @override
  List<VoipSession> getSessionsInRoom(String roomId) {
    // for (var session
    //     in voip.calls.values.where((element) => element.pc == null).toList()) {
    //   print("Removing invalid call session: $session");
    //   session.hangup();
    // }

    voip.calls.removeWhere((key, value) => value.pc == null);

    return voip.calls.values
        .where((element) => element.room.id == roomId && element.pc != null)
        .map(_startSession)
        .toList();
  }

  @override
  bool canHandleEvent(TimelineEvent event) {
    if (event is! MatrixTimelineEvent) {
      return false;
    }

    return [
      mx.EventTypes.CallHangup,
      mx.EventTypes.CallAnswer,
      mx.EventTypes.CallInvite,
      mx.EventTypes.CallReject,
    ].contains(event.event.type);
  }

  @override
  Widget? displayTimelineEvent(
    TimelineEvent event, {
    required String senderName,
  }) {
    if (event is! MatrixTimelineEvent) {
      return null;
    }

    // switch (event.event.type) {
    //   case mx.EventTypes.CallHangup:
    //     return  GenericRoomEvent(
    //       "$senderName left the call",
    //       icon: Icons.call_end,
    //     );
    //   case mx.EventTypes.CallReject:
    //     return GenericRoomEvent(
    //       "$senderName rejected the call",
    //       icon: Icons.call_end,
    //     );
    //   case mx.EventTypes.CallInvite:
    //     return GenericRoomEvent(
    //       "$senderName started a call",
    //       icon: Icons.call_end,
    //     );
    //   case mx.EventTypes.CallAnswer:
    //     return GenericRoomEvent(
    //       "$senderName answered the call",
    //       icon: Icons.call,
    //     );
    // }

    return Text(event.event.type);
  }

  Future<Map<String, dynamic>> alterPeerConfiguration(
    Map<String, dynamic> configuration,
  ) async {
    List<Map<String, dynamic>> newServers = List.empty(growable: true);

    // Split up the urls in to individual servers, this helps flutter_webrtc to get all candidates correctly
    // If all urls are in one server, it seems to only check one url.
    for (Map<String, dynamic> config in configuration["iceServers"]) {
      for (var url in config["urls"]) {
        var newEntry = {
          if (config.containsKey("username")) "username": config["username"],
          if (config.containsKey("credential"))
            "credential": config["credential"],
          "urls": [url],
        };

        newServers.add(newEntry);
      }
    }
    configuration["iceServers"] = newServers;

    // If the home server does not have any stun server, we can fallback to a default
    var servers = configuration["iceServers"] as List<dynamic>;
    if (servers.isEmpty) {
      if (preferences.useFallbackTurnServer.value == false) {
        var result = await AdaptiveDialog.show<bool>(
          navigator.currentContext!,
          builder: (context) =>
              VoipTurnFallbackDialog(client.getMatrixClient().homeserver!),
          dismissible: false,
          title: "Call Error",
        );

        preferences.useFallbackTurnServer.set(result ?? false);
      }

      if (preferences.useFallbackTurnServer.value) {
        servers = [
          {
            "urls": [preferences.fallbackTurnServer.value],
          },
        ];
        configuration["iceServers"] = servers;
      }
    }

    return configuration;
  }

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) async {
    configuration = await alterPeerConfiguration(configuration);

    var servers = configuration['iceServers'] as List<dynamic>;

    if (servers.isEmpty) {
      throw Exception(
        "No Turn servers are configured, this call cannot be connected",
      );
    }

    var pc = await webrtc.createPeerConnection(configuration, constraints);
    return pc;
  }

  @override
  Future<void> handleCallEnded(mx.CallSession session) async {
    final wrappedSession = _sessionOwner.end(
      _sessionOwnerKey(session),
      () => _sessionFactory(session, client),
    );
    try {
      if (_sessionSignalEmitter.canNotifySessionEnded) {
        _sessionSignalEmitter.notifySessionEnded(wrappedSession);
      }
    } finally {
      await wrappedSession.dispose();
    }
  }

  @override
  Future<void> handleMissedCall(mx.CallSession session) async {}

  @override
  Future<void> handleNewCall(mx.CallSession session) async {
    if (!_sessionSignalEmitter.canNotifySessionStarted) {
      return;
    }

    _sessionSignalEmitter.notifySessionStarted(_startSession(session));
  }

  @override
  Future<void> playRingtone() async {}

  @override
  Future<void> stopRingtone() async {}

  @override
  Future<void> startCall(String roomId, CallType type, {String? userId}) async {
    final callType = switch (type) {
      CallType.voice => mx.CallType.kVoice,
      CallType.video => mx.CallType.kVideo,
    };

    final room = client.getMatrixClient().getRoomById(roomId);
    if (room == null) {
      throw Exception("Direct call room not found: $roomId");
    }

    final nativeCrashGuard = await PendingNativeCallCrashGuard.record(
      source: 'matrix-direct-native-call-start',
      callKind: 'Direct Matrix outgoing call',
    );

    try {
      final audioReady = await IosCallAudioSession.prepareForCall(
        source: "matrix-direct-call-start",
        // Direct 1:1 calls always bypass native voice processing (BUG-168);
        // native NS is scoped to the LiveKit/group path only.
        forceBypassVoiceProcessing: true,
      );
      if (!audioReady) {
        throw Exception("iOS direct call audio session could not be prepared");
      }
      await WebrtcDefaultDevices.selectCallOutputDevice(
        source: "matrix-direct-call-start",
      );

      await IosCallAudioSession.ensureVoiceProcessingConfigured(
        source: "matrix-direct-call-start-invite",
        forceBypassVoiceProcessing: true,
      );
      await voip.inviteToCall(room, callType, userId: userId);
    } finally {
      await nativeCrashGuard?.clear();
    }
  }

  @override
  bool canCallRoom(String roomId) {
    var mxRoom = client.getMatrixClient().getRoomById(roomId);
    if (mxRoom == null) {
      return false;
    }

    return mxRoom.getParticipants().length <= 2;
  }

  @override
  Future<void> handleGroupCallEnded(mx.GroupCallSession groupCall) async {
    Log.i("Group call ended!");
  }

  @override
  Future<void> handleNewGroupCall(mx.GroupCallSession groupCall) async {
    Log.i("New group call started!");
  }

  @override
  mx.EncryptionKeyProvider? get keyProvider => throw UnimplementedError();

  @override
  Future<void> registerListeners(mx.CallSession session) async {}

  /// Hangs up every direct call this client still holds, in any live state -
  /// ringing either way, connecting, or connected.
  ///
  /// Client close calls this first, while the client can still send the
  /// hang-ups. [dispose] calls it again for any other path that disposes this
  /// component; a call already ended is skipped, so the second pass is free.
  Future<void> hangUpCalls() {
    final live = voip.calls.values
        .where((call) => !call.callHasEnded)
        .toList(growable: false);
    return hangUpBeforeClientClose(
      [
        for (final call in live)
          () => call.hangup(reason: mx.CallErrorCode.userHangup),
      ],
      context: 'direct calls',
      bound: hangUpBoundOnClose,
    );
  }

  @override
  Future<void> dispose() async {
    // Calls before the emitter: a hang-up reports its end through it.
    await hangUpCalls();
    await _sessionOwner.dispose((session) => session.dispose());
    await _sessionSignalEmitter.dispose();
  }
}
