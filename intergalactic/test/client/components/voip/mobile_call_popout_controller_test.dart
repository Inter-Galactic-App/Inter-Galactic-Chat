import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_surface_mode.dart';
import 'package:intergalactic/client/components/voip/mobile_call_popout_controller.dart';

void main() {
  _MobileCallPopoutTestBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(
    'chat.intergalactic.app/mobile_call_background',
  );

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    MobileCallPopoutController.debugResetForTests();
  });

  group('MobileCallPopoutPresentationState', () {
    test('parses inactive platform payloads defensively', () {
      expect(
        MobileCallPopoutPresentationState.fromPlatformValue(null),
        const MobileCallPopoutPresentationState.inactive(),
      );
      expect(
        MobileCallPopoutPresentationState.fromPlatformValue(const {
          'pictureInPicture': false,
          'resizedPopout': false,
        }),
        const MobileCallPopoutPresentationState.inactive(),
      );
    });

    test('separates PiP from resizeable popout state', () {
      final pip = MobileCallPopoutPresentationState.fromPlatformValue(const {
        'pictureInPicture': true,
        'resizedPopout': false,
      });
      final resized = MobileCallPopoutPresentationState.fromPlatformValue(
        const {'pictureInPicture': false, 'resizedPopout': true},
      );

      expect(pip.isPictureInPicture, isTrue);
      expect(pip.isResizedPopout, isFalse);
      expect(pip.usesCallOnlySurface, isTrue);
      expect(resized.isPictureInPicture, isFalse);
      expect(resized.isResizedPopout, isTrue);
      expect(resized.usesCallOnlySurface, isTrue);
    });
  });

  group('MobileCallPopoutController', () {
    test('enterPictureInPicture owns target session and emits state', () async {
      MobileCallPopoutController.debugCanRequestPictureInPictureOverride = true;
      final emitted = <MobileCallPopoutPresentationState>[];
      final subscription = MobileCallPopoutController.presentationStateChanges
          .listen(emitted.add);

      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'enterPictureInPicture');
        expect(call.arguments, {
          'aspectRatioNumerator': 4,
          'aspectRatioDenominator': 3,
          'sourceRectLeft': 1,
          'sourceRectTop': 2,
          'sourceRectRight': 101,
          'sourceRectBottom': 202,
          'sessionId': 'call-session',
          'isMicrophoneMuted': true,
          'isCameraEnabled': false,
        });
        return true;
      });

      final entered = await MobileCallPopoutController.enterPictureInPicture(
        sessionId: 'call-session',
        aspectRatioNumerator: 4,
        aspectRatioDenominator: 3,
        sourceRect: const ui.Rect.fromLTWH(1, 2, 100, 200),
        controlsState: const MobileCallPictureInPictureControlsState(
          isMicrophoneMuted: true,
          isCameraEnabled: false,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(entered, isTrue);
      expect(MobileCallPopoutController.targetSessionId, 'call-session');
      expect(
        MobileCallPopoutController.presentationState,
        const MobileCallPopoutPresentationState(
          isPictureInPicture: true,
          isResizedPopout: false,
          sessionId: 'call-session',
        ),
      );
      expect(emitted, hasLength(1));
      expect(emitted.single.isPictureInPicture, isTrue);
      expect(emitted.single.surfaceMode, CallSurfaceMode.pictureInPicture);

      await subscription.cancel();
    });

    test('enterPictureInPicture clears target session on failure', () async {
      MobileCallPopoutController.debugCanRequestPictureInPictureOverride = true;
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'pip-denied');
      });

      final entered = await MobileCallPopoutController.enterPictureInPicture(
        sessionId: 'stale-session',
      );

      expect(entered, isFalse);
      expect(MobileCallPopoutController.targetSessionId, isNull);
      expect(
        MobileCallPopoutController.presentationState,
        const MobileCallPopoutPresentationState.inactive(),
      );
    });

    test('refreshPresentationState clears stale state on failure', () async {
      MobileCallPopoutController.debugCanRequestPictureInPictureOverride = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'enterPictureInPicture':
            return true;
          case 'getPopoutPresentationState':
            throw PlatformException(code: 'state-unavailable');
        }
        return null;
      });

      final entered = await MobileCallPopoutController.enterPictureInPicture(
        sessionId: 'stale-session',
      );
      expect(entered, isTrue);
      expect(MobileCallPopoutController.targetSessionId, 'stale-session');
      expect(
        MobileCallPopoutController.presentationState.usesCallOnlySurface,
        isTrue,
      );

      await MobileCallPopoutController.refreshPresentationState();

      expect(MobileCallPopoutController.targetSessionId, isNull);
      expect(
        MobileCallPopoutController.presentationState,
        const MobileCallPopoutPresentationState.inactive(),
      );
    });

    test(
      'platform presentation callback broadcasts and clears inactive target',
      () async {
        MobileCallPopoutController.debugCanRequestPictureInPictureOverride =
            true;
        final emitted = <MobileCallPopoutPresentationState>[];
        final subscription = MobileCallPopoutController.presentationStateChanges
            .listen(emitted.add);
        messenger.setMockMethodCallHandler(channel, (_) async => true);
        await MobileCallPopoutController.enterPictureInPicture(
          sessionId: 'callback-session',
        );

        await MobileCallPopoutController.debugHandlePlatformCallForTests(
          const MethodCall('mobileCallPresentationChanged', {
            'pictureInPicture': false,
            'resizedPopout': true,
            'sessionId': 'callback-session',
          }),
        );
        await Future<void>.delayed(Duration.zero);

        expect(MobileCallPopoutController.targetSessionId, 'callback-session');
        expect(emitted.last.isResizedPopout, isTrue);
        expect(emitted.last.surfaceMode, CallSurfaceMode.poppedOut);

        await MobileCallPopoutController.debugHandlePlatformCallForTests(
          const MethodCall('mobileCallPresentationChanged', {
            'pictureInPicture': false,
            'resizedPopout': false,
          }),
        );
        await Future<void>.delayed(Duration.zero);

        expect(MobileCallPopoutController.targetSessionId, isNull);
        expect(emitted.last.usesCallOnlySurface, isFalse);

        await subscription.cancel();
      },
    );

    test(
      'exitPictureInPicture emits inactive state after platform exit',
      () async {
        MobileCallPopoutController.debugCanRequestPictureInPictureOverride =
            true;
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'enterPictureInPicture':
              return true;
            case 'exitPictureInPicture':
              expect(call.arguments, {'reason': 'return'});
              return true;
          }
          return null;
        });

        await MobileCallPopoutController.enterPictureInPicture(
          sessionId: 'return-session',
        );
        expect(MobileCallPopoutController.targetSessionId, 'return-session');

        final exited = await MobileCallPopoutController.exitPictureInPicture(
          reason: 'return',
        );

        expect(exited, isTrue);
        expect(MobileCallPopoutController.targetSessionId, isNull);
        expect(
          MobileCallPopoutController.presentationState,
          const MobileCallPopoutPresentationState.inactive(),
        );
      },
    );

    test('updates Android picture-in-picture controls', () async {
      MobileCallPopoutController.debugCanRequestPictureInPictureOverride = true;

      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'updatePictureInPictureControls');
        expect(call.arguments, {
          'sessionId': 'call-session',
          'isMicrophoneMuted': false,
          'isCameraEnabled': true,
        });
        return true;
      });

      final updated =
          await MobileCallPopoutController.updatePictureInPictureControls(
            sessionId: 'call-session',
            controlsState: const MobileCallPictureInPictureControlsState(
              isMicrophoneMuted: false,
              isCameraEnabled: true,
            ),
          );

      expect(updated, isTrue);
    });

    test(
      'updatePictureInPictureControls returns false when platform update fails',
      () async {
        MobileCallPopoutController.debugCanRequestPictureInPictureOverride =
            true;

        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'updatePictureInPictureControls');
          throw PlatformException(
            code: 'pip_failed',
            message: 'Could not update controls',
          );
        });

        final updated =
            await MobileCallPopoutController.updatePictureInPictureControls(
              sessionId: 'call-session',
              controlsState: const MobileCallPictureInPictureControlsState(
                isMicrophoneMuted: true,
                isCameraEnabled: false,
              ),
            );

        expect(updated, isFalse);
      },
    );

    test('parses close fullscreen mute and camera platform actions', () async {
      MobileCallPopoutController.debugCanRequestPictureInPictureOverride = true;
      final emitted = <MobileCallPopoutAction>[];
      final subscription = MobileCallPopoutController.actionRequests.listen(
        emitted.add,
      );

      await MobileCallPopoutController.debugHandlePlatformCallForTests(
        const MethodCall('mobileCallPictureInPictureAction', {
          'action': 'close',
        }),
      );
      await MobileCallPopoutController.debugHandlePlatformCallForTests(
        const MethodCall('mobileCallPictureInPictureAction', {
          'action': 'fullScreen',
        }),
      );
      await MobileCallPopoutController.debugHandlePlatformCallForTests(
        const MethodCall('mobileCallPictureInPictureAction', {
          'action': 'muteMicrophone',
        }),
      );
      await MobileCallPopoutController.debugHandlePlatformCallForTests(
        const MethodCall('mobileCallPictureInPictureAction', {
          'action': 'toggleCamera',
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted, [
        MobileCallPopoutAction.close,
        MobileCallPopoutAction.fullScreen,
        MobileCallPopoutAction.muteMicrophone,
        MobileCallPopoutAction.toggleCamera,
      ]);

      await subscription.cancel();
    });
  });
}

class _MobileCallPopoutTestBinding extends BindingBase
    with SchedulerBinding, ServicesBinding, TestDefaultBinaryMessengerBinding {
  static void ensureInitialized() {
    try {
      TestDefaultBinaryMessengerBinding.instance;
    } catch (_) {
      _MobileCallPopoutTestBinding();
    }
  }
}
