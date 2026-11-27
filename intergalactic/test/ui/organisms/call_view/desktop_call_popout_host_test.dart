import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/desktop_call_popout_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('popout pin refresh stops after frame disposal', (tester) async {
    const channel = MethodChannel('window_manager');
    final setAlwaysOnTopCompleter = Completer<void>();
    var isAlwaysOnTopCalls = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isAlwaysOnTop':
              isAlwaysOnTopCalls++;
              return false;
            case 'setAlwaysOnTop':
              await setAlwaysOnTopCompleter.future;
              return null;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: debugBuildCallPopoutFrameForTesting(
            title: 'Call Room',
            childBuilder: (_) => const SizedBox(width: 240, height: 120),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(isAlwaysOnTopCalls, 1);

    await tester.tap(find.byIcon(Icons.push_pin_outlined));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    setAlwaysOnTopCompleter.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(isAlwaysOnTopCalls, 1);
  });
}
