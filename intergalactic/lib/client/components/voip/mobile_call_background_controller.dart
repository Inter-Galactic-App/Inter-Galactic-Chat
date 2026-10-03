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
  MobileCallBackgroundController({
    MobileCallBackgroundPlatform? platform,
    Duration platformCallTimeout = _defaultPlatformCallTimeout,
  }) : _platform = platform ?? MethodChannelMobileCallBackgroundPlatform(),
       _platformCallTimeout = platformCallTimeout;

  static final MobileCallBackgroundController instance =
      MobileCallBackgroundController();

  static const Duration _defaultPlatformCallTimeout = Duration(seconds: 8);

  final MobileCallBackgroundPlatform _platform;
  final Duration _platformCallTimeout;
  _MobileCallBackgroundSignature? _desiredSignature;
  int _desiredGeneration = 0;
  int? _queuedGeneration;
  Future<void> _lastOperation = Future<void>.value();

  Future<void> syncSessions(Iterable<VoipSession> sessions) {
    final signature = _signatureFor(sessions);

    // No platform work to serialize when backgrounding is unsupported; keep
    // this path synchronous so shutdown never waits on the operation chain.
    if (!_platform.isSupported) {
      _desiredSignature = const _MobileCallBackgroundSignature.inactive();
      _desiredGeneration++;
      _queuedGeneration = _desiredGeneration;
      _lastOperation = Future<void>.value();
      return _lastOperation;
    }

    if (_desiredSignature != signature) {
      _desiredSignature = signature;
      _desiredGeneration++;
    }

    return _enqueueLatestDesiredState();
  }

  Future<void> _enqueueLatestDesiredState({bool force = false}) {
    final signature = _desiredSignature;
    if (signature == null) {
      return _lastOperation;
    }
    final generation = _desiredGeneration;
    if (!force && _queuedGeneration == generation) {
      return _lastOperation;
    }

    _queuedGeneration = generation;
    _lastOperation = _lastOperation
        .catchError((_) {})
        .then((_) => _apply(signature, generation));
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

  Future<void> _apply(
    _MobileCallBackgroundSignature signature,
    int generation,
  ) async {
    if (!_platform.isSupported) {
      return;
    }

    final platformOperation = _platform.setCallBackgroundActive(
      active: signature.active,
      roomName: signature.roomName,
      usesMicrophone: signature.usesMicrophone,
      usesCamera: signature.usesCamera,
    );

    try {
      await platformOperation.timeout(_platformCallTimeout);
    } on TimeoutException catch (error, stackTrace) {
      _releaseTimedOutGeneration(generation);
      _reconcileLateCompletion(
        platformOperation,
        generation: generation,
        signature: signature,
      );
      Log.onError(
        error,
        stackTrace,
        content: 'Timed out updating mobile call background retention',
        category: LogCategory.livekit,
        source: 'mobile-call-background',
      );
    } catch (error, stackTrace) {
      _releaseTimedOutGeneration(generation);
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

  void _releaseTimedOutGeneration(int generation) {
    if (_desiredGeneration == generation && _queuedGeneration == generation) {
      _queuedGeneration = null;
    }
  }

  void _reconcileLateCompletion(
    Future<void> operation, {
    required int generation,
    required _MobileCallBackgroundSignature signature,
  }) {
    unawaited(
      operation.then(
        (_) => _reapplyLatestStateAfterLateCompletion(
          generation: generation,
          signature: signature,
        ),
        onError: (Object error, StackTrace stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Mobile call background operation failed after timeout',
            category: LogCategory.livekit,
            source: 'mobile-call-background',
          );
          _reapplyLatestStateAfterLateCompletion(
            generation: generation,
            signature: signature,
          );
        },
      ),
    );
  }

  void _reapplyLatestStateAfterLateCompletion({
    required int generation,
    required _MobileCallBackgroundSignature signature,
  }) {
    if (_desiredGeneration == generation && _desiredSignature == signature) {
      return;
    }
    unawaited(_enqueueLatestDesiredState(force: true));
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
