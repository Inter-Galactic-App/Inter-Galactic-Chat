import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/client/components/voip/call_surface_mode.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';

@immutable
class MobileCallPopoutPresentationState {
  const MobileCallPopoutPresentationState({
    required this.isPictureInPicture,
    required this.isResizedPopout,
    this.sessionId,
  });

  const MobileCallPopoutPresentationState.inactive()
    : isPictureInPicture = false,
      isResizedPopout = false,
      sessionId = null;

  final bool isPictureInPicture;
  final bool isResizedPopout;
  final String? sessionId;

  bool get usesCallOnlySurface => isPictureInPicture || isResizedPopout;

  CallSurfaceMode get surfaceMode {
    if (isPictureInPicture) {
      return CallSurfaceMode.pictureInPicture;
    }
    if (isResizedPopout) {
      return CallSurfaceMode.poppedOut;
    }
    return CallSurfaceMode.inRoom;
  }

  static MobileCallPopoutPresentationState fromPlatformValue(
    Object? value, {
    String? fallbackSessionId,
  }) {
    if (value is! Map) {
      return const MobileCallPopoutPresentationState.inactive();
    }

    final isPictureInPicture = value['pictureInPicture'] == true;
    final isResizedPopout = value['resizedPopout'] == true;
    if (!isPictureInPicture && !isResizedPopout) {
      return const MobileCallPopoutPresentationState.inactive();
    }

    final platformSessionId = _normalizedSessionId(value['sessionId']);
    return MobileCallPopoutPresentationState(
      isPictureInPicture: isPictureInPicture,
      isResizedPopout: isResizedPopout,
      sessionId: platformSessionId ?? _normalizedSessionId(fallbackSessionId),
    );
  }

  static String? _normalizedSessionId(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  @override
  bool operator ==(Object other) {
    return other is MobileCallPopoutPresentationState &&
        other.isPictureInPicture == isPictureInPicture &&
        other.isResizedPopout == isResizedPopout &&
        other.sessionId == sessionId;
  }

  @override
  int get hashCode =>
      Object.hash(isPictureInPicture, isResizedPopout, sessionId);
}

enum MobileCallPopoutAction {
  returnToCall,
  hangUp,
  close,
  fullScreen,
  muteMicrophone,
  toggleCamera,
}

@immutable
class MobileCallPictureInPictureControlsState {
  const MobileCallPictureInPictureControlsState({
    required this.isMicrophoneMuted,
    required this.isCameraEnabled,
  });

  final bool isMicrophoneMuted;
  final bool isCameraEnabled;

  Map<String, dynamic> toPlatformMap({String? sessionId}) {
    return <String, dynamic>{
      if (sessionId != null) 'sessionId': sessionId,
      'isMicrophoneMuted': isMicrophoneMuted,
      'isCameraEnabled': isCameraEnabled,
    };
  }
}

@immutable
class MobileCallNativePiPTarget {
  const MobileCallNativePiPTarget({
    required this.mediaStreamId,
    required this.videoTrackId,
    this.ownerTag,
    this.selectedStreamId,
    this.participantHash,
  });

  final String mediaStreamId;
  final String videoTrackId;
  final String? ownerTag;
  final String? selectedStreamId;
  final String? participantHash;

  bool get isUsable =>
      mediaStreamId.trim().isNotEmpty && videoTrackId.trim().isNotEmpty;

  Map<String, dynamic> toPlatformMap({String? sessionId}) {
    return <String, dynamic>{
      if (sessionId != null) 'sessionId': sessionId,
      'mediaStreamId': mediaStreamId,
      'videoTrackId': videoTrackId,
      if (ownerTag != null && ownerTag!.trim().isNotEmpty) 'ownerTag': ownerTag,
      if (selectedStreamId != null && selectedStreamId!.trim().isNotEmpty)
        'selectedStreamId': selectedStreamId,
      if (participantHash != null && participantHash!.trim().isNotEmpty)
        'participantHash': participantHash,
    };
  }
}

class MobileCallPopoutController {
  MobileCallPopoutController._();

  static const MethodChannel _channel = MethodChannel(
    'chat.intergalactic.app/mobile_call_background',
  );
  static const MethodChannel _webRtcChannel = MethodChannel(
    'FlutterWebRTC.Method',
  );
  static const Duration _platformCallTimeout = Duration(seconds: 8);
  static final StreamController<MobileCallPopoutPresentationState>
  _presentationStateController =
      StreamController<MobileCallPopoutPresentationState>.broadcast();
  static final StreamController<MobileCallPopoutAction> _actionController =
      StreamController<MobileCallPopoutAction>.broadcast();
  static MobileCallPopoutPresentationState _presentationState =
      const MobileCallPopoutPresentationState.inactive();
  static String? _targetSessionId;
  static bool _platformCallbacksRegistered = false;
  @visibleForTesting
  static bool? debugCanRequestPictureInPictureOverride;

  static bool get canRequestPictureInPicture =>
      debugCanRequestPictureInPictureOverride ??
      (PlatformUtils.isAndroid || PlatformUtils.isIOS);
  static String? get targetSessionId => _targetSessionId;
  static MobileCallPopoutPresentationState get presentationState {
    _ensurePlatformCallbacksRegistered();
    return _presentationState;
  }

  static Stream<MobileCallPopoutPresentationState>
  get presentationStateChanges {
    _ensurePlatformCallbacksRegistered();
    return _presentationStateController.stream;
  }

  static Stream<MobileCallPopoutAction> get actionRequests {
    _ensurePlatformCallbacksRegistered();
    return _actionController.stream;
  }

  static Future<bool> enterPictureInPicture({
    String? sessionId,
    int aspectRatioNumerator = 16,
    int aspectRatioDenominator = 9,
    ui.Rect? sourceRect,
    MobileCallNativePiPTarget? nativeVideoTarget,
    MobileCallPictureInPictureControlsState? controlsState,
  }) async {
    if (!canRequestPictureInPicture) {
      return false;
    }

    _ensurePlatformCallbacksRegistered();
    _targetSessionId = sessionId;

    if (PlatformUtils.isIOS) {
      final prepared = await _prepareNativeIOSPictureInPictureTrack(
        sessionId: sessionId,
        nativeVideoTarget: nativeVideoTarget,
      );
      if (!prepared) {
        _targetSessionId = null;
        return false;
      }
    }

    try {
      final entered =
          await _invokePlatformMethod<bool>(
            _channel,
            'enterPictureInPicture',
            <String, dynamic>{
              'aspectRatioNumerator': aspectRatioNumerator,
              'aspectRatioDenominator': aspectRatioDenominator,
              if (sourceRect != null) ...{
                'sourceRectLeft': sourceRect.left.round(),
                'sourceRectTop': sourceRect.top.round(),
                'sourceRectRight': sourceRect.right.round(),
                'sourceRectBottom': sourceRect.bottom.round(),
              },
              if (sessionId != null) 'sessionId': sessionId,
              if (nativeVideoTarget != null)
                ...nativeVideoTarget.toPlatformMap(sessionId: sessionId),
              if (controlsState != null)
                ...controlsState.toPlatformMap(sessionId: sessionId),
            },
          ) ==
          true;
      if (entered) {
        _setPresentationState(
          MobileCallPopoutPresentationState(
            isPictureInPicture: true,
            isResizedPopout: false,
            sessionId: sessionId,
          ),
        );
      } else {
        _targetSessionId = null;
      }
      return entered;
    } catch (error, stackTrace) {
      _targetSessionId = null;
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to enter mobile call picture-in-picture',
        category: LogCategory.livekit,
        source: 'mobile-call-popout',
      );
      return false;
    }
  }

  static Future<bool> updatePictureInPictureControls({
    String? sessionId,
    required MobileCallPictureInPictureControlsState controlsState,
  }) async {
    final canUseAndroidControls =
        PlatformUtils.isAndroid ||
        debugCanRequestPictureInPictureOverride == true;
    if (!canRequestPictureInPicture || !canUseAndroidControls) {
      return false;
    }

    _ensurePlatformCallbacksRegistered();

    try {
      return await _invokePlatformMethod<bool>(
            _channel,
            'updatePictureInPictureControls',
            controlsState.toPlatformMap(sessionId: sessionId),
          ) ==
          true;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to update Android call picture-in-picture controls',
        category: LogCategory.livekit,
        source: 'mobile-call-popout',
      );
      return false;
    }
  }

  static Future<bool> _prepareNativeIOSPictureInPictureTrack({
    required String? sessionId,
    required MobileCallNativePiPTarget? nativeVideoTarget,
  }) async {
    if (nativeVideoTarget == null || !nativeVideoTarget.isUsable) {
      Log.w(
        'iOS call PiP native video target unavailable before start',
        category: LogCategory.livekit,
        source: 'mobile-call-popout',
      );
      return false;
    }

    try {
      final prepared =
          await _invokePlatformMethod<bool>(
            _webRtcChannel,
            'interGalacticPreparePictureInPictureTrack',
            nativeVideoTarget.toPlatformMap(sessionId: sessionId),
          ) ==
          true;
      if (!prepared) {
        Log.w(
          'iOS call PiP native video target preparation failed',
          category: LogCategory.livekit,
          source: 'mobile-call-popout',
        );
      }
      return prepared;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to prepare iOS native call picture-in-picture track',
        category: LogCategory.livekit,
        source: 'mobile-call-popout',
      );
      return false;
    }
  }

  static Future<bool> exitPictureInPicture({String reason = 'close'}) async {
    if (!canRequestPictureInPicture) {
      return false;
    }

    _ensurePlatformCallbacksRegistered();

    try {
      final exited =
          await _invokePlatformMethod<bool>(
            _channel,
            'exitPictureInPicture',
            <String, dynamic>{'reason': reason},
          ) ==
          true;
      if (exited) {
        _setPresentationState(
          const MobileCallPopoutPresentationState.inactive(),
        );
      }
      return exited;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to exit mobile call picture-in-picture',
        category: LogCategory.livekit,
        source: 'mobile-call-popout',
      );
      return false;
    }
  }

  static Future<void> refreshPresentationState() async {
    if (!canRequestPictureInPicture) {
      _setPresentationState(const MobileCallPopoutPresentationState.inactive());
      return;
    }

    _ensurePlatformCallbacksRegistered();

    try {
      final value = await _invokePlatformMethod<Object?>(
        _channel,
        'getPopoutPresentationState',
      );
      _setPresentationState(
        MobileCallPopoutPresentationState.fromPlatformValue(
          value,
          fallbackSessionId: _targetSessionId,
        ),
      );
    } catch (error, stackTrace) {
      _setPresentationState(const MobileCallPopoutPresentationState.inactive());
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to read mobile call popout presentation state',
        category: LogCategory.livekit,
        source: 'mobile-call-popout',
      );
    }
  }

  static Future<T?> _invokePlatformMethod<T>(
    MethodChannel channel,
    String method, [
    Object? arguments,
  ]) {
    return channel
        .invokeMethod<T>(method, arguments)
        .timeout(_platformCallTimeout);
  }

  static void _ensurePlatformCallbacksRegistered() {
    if (_platformCallbacksRegistered ||
        (!PlatformUtils.isAndroid && !PlatformUtils.isIOS)) {
      return;
    }
    _platformCallbacksRegistered = true;
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  static Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'mobileCallPresentationChanged':
        _setPresentationState(
          MobileCallPopoutPresentationState.fromPlatformValue(
            call.arguments,
            fallbackSessionId: _targetSessionId,
          ),
        );
        break;
      case 'mobileCallPictureInPictureAction':
        final action = _actionFromPlatformValue(call.arguments);
        if (action != null) {
          _actionController.add(action);
        }
        break;
      default:
        break;
    }
  }

  static MobileCallPopoutAction? _actionFromPlatformValue(Object? value) {
    final action = value is Map ? value['action']?.toString() : null;
    return switch (action) {
      'returnToCall' => MobileCallPopoutAction.returnToCall,
      'hangUp' => MobileCallPopoutAction.hangUp,
      'close' => MobileCallPopoutAction.close,
      'fullScreen' => MobileCallPopoutAction.fullScreen,
      'muteMicrophone' => MobileCallPopoutAction.muteMicrophone,
      'toggleCamera' => MobileCallPopoutAction.toggleCamera,
      _ => null,
    };
  }

  @visibleForTesting
  static Future<void> debugHandlePlatformCallForTests(MethodCall call) {
    return _handlePlatformCall(call);
  }

  @visibleForTesting
  static void debugResetForTests() {
    debugCanRequestPictureInPictureOverride = null;
    _targetSessionId = null;
    _presentationState = const MobileCallPopoutPresentationState.inactive();
    _platformCallbacksRegistered = false;
    _channel.setMethodCallHandler(null);
  }

  static void _setPresentationState(
    MobileCallPopoutPresentationState nextState,
  ) {
    if (!nextState.usesCallOnlySurface) {
      _targetSessionId = null;
    } else if (nextState.sessionId != null) {
      _targetSessionId = nextState.sessionId;
    }
    if (_presentationState == nextState) {
      return;
    }
    _presentationState = nextState;
    _presentationStateController.add(nextState);
  }
}
