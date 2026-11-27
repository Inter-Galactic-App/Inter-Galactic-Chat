import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/ui/windows/developer_title_bar_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.developerMode.set(true);
  });

  testWidgets('developer menu closes after pointer leaves menu stack', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData.light(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: DeveloperTitleBarMenu(navigatorKey: navigatorKey),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);

    await gesture.moveTo(tester.getCenter(find.text('Developer')));
    await tester.pump();

    expect(find.text('Logs'), findsOneWidget);

    await gesture.moveTo(tester.getCenter(find.text('Logs')));
    await tester.pump();

    expect(find.text('Logs'), findsOneWidget);

    await gesture.moveTo(const Offset(700, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Logs'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Logs'), findsNothing);
  });

  testWidgets('developer menu closes after pointer leaves open submenu', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData.light(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: DeveloperTitleBarMenu(navigatorKey: navigatorKey),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);

    await gesture.moveTo(tester.getCenter(find.text('Developer')));
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.text('Noise Suppression')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Hook Mode'), findsOneWidget);

    await gesture.moveTo(const Offset(700, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Noise Suppression'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Noise Suppression'), findsNothing);
    expect(find.text('Hook Mode'), findsNothing);
  });

  testWidgets(
    'developer menu closes after pointer leaves nested submenu item',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData.light(useMaterial3: true),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: DeveloperTitleBarMenu(navigatorKey: navigatorKey),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);

      await gesture.moveTo(tester.getCenter(find.text('Developer')));
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.text('Noise Suppression')));
      await tester.pump(const Duration(milliseconds: 400));

      await gesture.moveTo(tester.getCenter(find.text('Hook Mode')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Enhanced DeepFilterNet'), findsOneWidget);

      await gesture.moveTo(
        tester.getCenter(find.text('Enhanced DeepFilterNet')),
      );
      await tester.pump();

      await gesture.moveTo(const Offset(780, 560));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Noise Suppression'), findsOneWidget);
      expect(find.text('Enhanced DeepFilterNet'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Noise Suppression'), findsNothing);
      expect(find.text('Hook Mode'), findsNothing);
      expect(find.text('Enhanced DeepFilterNet'), findsNothing);
    },
  );

  testWidgets('developer menu releases app input after it closes', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final textController = TextEditingController();
    final scrollController = ScrollController();
    var tapCount = 0;
    addTearDown(textController.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData.light(useMaterial3: true),
        home: Scaffold(
          body: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: DeveloperTitleBarMenu(navigatorKey: navigatorKey),
              ),
              TextField(
                key: const Key('app-input-field'),
                controller: textController,
              ),
              ElevatedButton(
                key: const Key('app-input-button'),
                onPressed: () => tapCount += 1,
                child: const Text('Underlying action'),
              ),
              Expanded(
                child: ListView.builder(
                  key: const Key('app-scroll-list'),
                  controller: scrollController,
                  itemCount: 30,
                  itemBuilder: (context, index) =>
                      SizedBox(height: 48, child: Text('Row $index')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('app-input-field')));
    await tester.pump();
    final inputFocusBeforeMenu = FocusManager.instance.primaryFocus;
    expect(inputFocusBeforeMenu, isNotNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);

    await gesture.moveTo(tester.getCenter(find.text('Developer')));
    await tester.pump();

    expect(find.text('Logs'), findsOneWidget);

    await gesture.moveTo(const Offset(700, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Logs'), findsNothing);

    // Closing the menu must hand focus back to whatever held it before the
    // menu opened, not leave it captured by the menu stack.
    expect(FocusManager.instance.primaryFocus, same(inputFocusBeforeMenu));

    await tester.tap(find.byKey(const Key('app-input-button')));
    await tester.pump();

    expect(tapCount, 1);

    await tester.tap(find.byKey(const Key('app-input-field')));
    await tester.enterText(find.byKey(const Key('app-input-field')), 'ready');
    await tester.pump();

    expect(textController.text, 'ready');

    expect(scrollController.offset, 0);

    await tester.drag(
      find.byKey(const Key('app-scroll-list')),
      const Offset(0, -180),
    );
    await tester.pump();

    expect(scrollController.offset, greaterThan(0));
  });
}
