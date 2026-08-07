import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_media_operation_gate.dart';

void main() {
  group('DirectCallMediaOperationGate', () {
    test('allows active non-ended non-disposed operations', () {
      expect(
        DirectCallMediaOperationGate.shouldRun(
          active: true,
          ended: false,
          disposed: false,
        ),
        isTrue,
      );
    });

    test('blocks after hang-up begins', () {
      expect(
        DirectCallMediaOperationGate.shouldRun(
          active: false,
          ended: false,
          disposed: false,
        ),
        isFalse,
      );
    });

    test('blocks ended calls even when active state is stale', () {
      expect(
        DirectCallMediaOperationGate.shouldRun(
          active: true,
          ended: true,
          disposed: false,
        ),
        isFalse,
      );
    });

    test('blocks disposed resources', () {
      expect(
        DirectCallMediaOperationGate.shouldRun(
          active: true,
          ended: false,
          disposed: true,
        ),
        isFalse,
      );
    });

    test('uses the same lifecycle boundary for stream-list events', () {
      expect(
        DirectCallMediaOperationGate.shouldProcessStreamListEvent(
          active: true,
          ended: false,
          disposed: false,
        ),
        isTrue,
      );
      expect(
        DirectCallMediaOperationGate.shouldProcessStreamListEvent(
          active: false,
          ended: false,
          disposed: false,
        ),
        isFalse,
      );
      expect(
        DirectCallMediaOperationGate.shouldProcessStreamListEvent(
          active: true,
          ended: true,
          disposed: false,
        ),
        isFalse,
      );
      expect(
        DirectCallMediaOperationGate.shouldProcessStreamListEvent(
          active: true,
          ended: false,
          disposed: true,
        ),
        isFalse,
      );
    });

    test('allows notifications for live controllers', () {
      expect(
        DirectCallMediaOperationGate.shouldNotify(
          disposed: false,
          closed: false,
        ),
        isTrue,
      );
    });

    test('blocks notifications after dispose', () {
      expect(
        DirectCallMediaOperationGate.shouldNotify(
          disposed: true,
          closed: false,
        ),
        isFalse,
      );
    });

    test('blocks notifications after stream close', () {
      expect(
        DirectCallMediaOperationGate.shouldNotify(
          disposed: false,
          closed: true,
        ),
        isFalse,
      );
    });

    test('blocks transient notifications outside live call lifecycle', () {
      expect(
        DirectCallMediaOperationGate.shouldNotifyTransient(
          active: true,
          ended: false,
          disposed: false,
          closed: false,
        ),
        isTrue,
      );
      expect(
        DirectCallMediaOperationGate.shouldNotifyTransient(
          active: false,
          ended: false,
          disposed: false,
          closed: false,
        ),
        isFalse,
      );
      expect(
        DirectCallMediaOperationGate.shouldNotifyTransient(
          active: true,
          ended: true,
          disposed: false,
          closed: false,
        ),
        isFalse,
      );
      expect(
        DirectCallMediaOperationGate.shouldNotifyTransient(
          active: true,
          ended: false,
          disposed: true,
          closed: false,
        ),
        isFalse,
      );
      expect(
        DirectCallMediaOperationGate.shouldNotifyTransient(
          active: true,
          ended: false,
          disposed: false,
          closed: true,
        ),
        isFalse,
      );
    });

    test('prevents closed controller notification adds', () async {
      final controller = StreamController<void>.broadcast();
      await controller.close();

      expect(controller.isClosed, isTrue);
      if (DirectCallMediaOperationGate.shouldNotify(
        disposed: false,
        closed: controller.isClosed,
      )) {
        controller.add(null);
      }
    });
  });
}
