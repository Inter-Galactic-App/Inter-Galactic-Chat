import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';

@visibleForTesting
abstract class MobileCallBackgroundPlatform {
  bool get isSupported;

  Future<void> setCallBackgroundActive({
    required bool active,
    String? roomName,
    required bool usesMicrophone,
    required bool usesCamera,
  });
}

class MethodChannelMobileCallBackgroundPlatform
    implements MobileCallBackgroundPlatform {
  static const MethodChannel _channel = MethodChannel(
    'chat.intergalactic.app/mobile_call_background',
  );

  @override
  bool get isSupported => PlatformUtils.isAndroid || PlatformUtils.isIOS;

  @override
  Future<void> setCallBackgroundActive({
    required bool active,
    String? roomName,
    required bool usesMicrophone,
    required bool usesCamera,
  }) async {
    await _channel
        .invokeMethod<void>('setCallBackgroundActive', <String, dynamic>{
          'active': active,
          if (roomName != null) 'roomName': roomName,
          'usesMicrophone': usesMicrophone,
          'usesCamera': usesCamera,
        });
  }
}

class MobileCallBackgroundController {
  MobileCallBackgroundController({MobileCallBackgroundPlatform? platform})
    : _platform = platform ?? MethodChannelMobileCallBackgroundPlatform();

  static final MobileCallBackgroundController instance =
      MobileCallBackgroundController();

  final MobileCallBackgroundPlatform _platform;
  _MobileCallBackgroundSignature? _lastApplied;
  Future<void> _lastOperation = Future<void>.value();

  Future<void> syncSessions(Iterable<VoipSession> sessions) {
    final signature = _signatureFor(sessions);
    if (_lastApplied == signature) {
      return _lastOperation;
    }

    // No platform work to serialize when backgrounding is unsupported; keep
    // this path synchronous so shutdown never waits on the operation chain.
    if (!_platform.isSupported) {
      _lastApplied = const _MobileCallBackgroundSignature.inactive();
      _lastOperation = Future<void>.value();
      return _lastOperation;
    }

    _lastOperation = _lastOperation
        .catchError((_) {})
        .then((_) => _apply(signature));
    return _lastOperation;
  }

  Future<void> stopForShutdown() {
    return syncSessions(const []);
  }

  _MobileCallBackgroundSignature _signatureFor(Iterable<VoipSession> sessions) {
    final activeSessions = sessions
        .where(
          (session) => switch (session.state) {
            VoipState.connected ||
            VoipState.connecting ||
            VoipState.outgoing => true,
            _ => false,
          },
        )
        .toList(growable: false);

    if (activeSessions.isEmpty) {
      return const _MobileCallBackgroundSignature.inactive();
    }

    return _MobileCallBackgroundSignature(
      active: true,
      roomName: activeSessions.length == 1
          ? activeSessions.single.roomName
          : '${activeSessions.length} active calls',
      usesMicrophone: activeSessions.any(
        (session) => !session.isMicrophoneMuted,
      ),
      usesCamera: activeSessions.any((session) => session.isCameraEnabled),
    );
  }

  Future<void> _apply(_MobileCallBackgroundSignature signature) async {
    if (!_platform.isSupported) {
      _lastApplied = const _MobileCallBackgroundSignature.inactive();
      return;
    }

    try {
      await _platform.setCallBackgroundActive(
        active: signature.active,
        roomName: signature.roomName,
        usesMicrophone: signature.usesMicrophone,
        usesCamera: signature.usesCamera,
      );
      _lastApplied = signature;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: signature.active
            ? 'Failed to keep mobile call audio active in the background'
            : 'Failed to stop mobile call background audio retention',
        category: LogCategory.livekit,
        source: 'mobile-call-background',
      );
    }
  }
}

@immutable
class _MobileCallBackgroundSignature {
  const _MobileCallBackgroundSignature({
    required this.active,
    this.roomName,
    this.usesMicrophone = false,
    this.usesCamera = false,
  });

  const _MobileCallBackgroundSignature.inactive()
    : active = false,
      roomName = null,
      usesMicrophone = false,
      usesCamera = false;

  final bool active;
  final String? roomName;
  final bool usesMicrophone;
  final bool usesCamera;

  @override
  bool operator ==(Object other) {
    return other is _MobileCallBackgroundSignature &&
        other.active == active &&
        other.roomName == roomName &&
        other.usesMicrophone == usesMicrophone &&
        other.usesCamera == usesCamera;
  }

  @override
  int get hashCode => Object.hash(active, roomName, usesMicrophone, usesCamera);
}
