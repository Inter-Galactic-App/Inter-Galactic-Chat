import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/service/background_service_init_gate.dart';

void main() {
  test(
    'duplicate init waits for registration without reannouncing ready',
    () async {
      final gate = BackgroundServiceInitGate();
      final initialization = Completer<void>();
      var initializeCalls = 0;
      var readyCalls = 0;

      Future<void> initialize() async {
        initializeCalls++;
        await initialization.future;
      }

      final first = gate.run(
        initialize: initialize,
        onReady: () => readyCalls++,
      );
      final second = gate.run(
        initialize: initialize,
        onReady: () => readyCalls++,
      );

      await Future<void>.delayed(Duration.zero);
      expect(initializeCalls, 1);
      expect(readyCalls, 0);

      initialization.complete();
      await Future.wait([first, second]);

      expect(readyCalls, 1);
    },
  );
}
