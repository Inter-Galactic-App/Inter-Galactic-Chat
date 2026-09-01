import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_panel.dart';

void main() {
  test('sets high receive priority for popped-out panel streams', () async {
    final stream = _RecordingVoipStream();

    await debugSetPoppedOutReceivePriorityForTesting(stream);

    expect(stream.priorities, [VoipStreamReceivePriority.high]);
  });

  test('recovers stale stream receive-priority failures', () async {
    final stream = _FailingVoipStream();

    await expectLater(
      debugSetPoppedOutReceivePriorityForTesting(stream),
      completes,
    );

    expect(stream.priorityAttempts, 1);
  });

  test('recovers activity subscription cancellation failures', () async {
    final subscription = _FailingCancelSubscription();

    await expectLater(
      debugCancelCallStreamPopoutSubscriptionForTesting(subscription),
      completes,
    );

    expect(subscription.cancelAttempts, 1);
  });

  test(
    'transparent stream popouts keep wrapped tile geometry with local menus',
    () {
      final opaque = debugResolveCallStreamPopoutSurfaceTreatmentForTesting(
        transparentChrome: false,
      );
      final transparent =
          debugResolveCallStreamPopoutSurfaceTreatmentForTesting(
            transparentChrome: true,
          );

      expect(opaque.padding, const EdgeInsets.all(8));
      expect(opaque.edgeToEdge, isFalse);
      expect(opaque.showTileScrim, isTrue);
      expect(opaque.useRootOverlayForMenus, isTrue);

      expect(transparent.padding, const EdgeInsets.all(8));
      expect(transparent.edgeToEdge, isFalse);
      expect(transparent.showTileScrim, isTrue);
      expect(transparent.useRootOverlayForMenus, isFalse);
    },
  );
}

class _RecordingVoipStream implements VoipStream {
  final List<VoipStreamReceivePriority> priorities = [];

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {
    priorities.add(priority);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingVoipStream extends _RecordingVoipStream {
  int priorityAttempts = 0;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {
    priorityAttempts++;
    throw StateError('stream disposed');
  }
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('popout subscription cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
