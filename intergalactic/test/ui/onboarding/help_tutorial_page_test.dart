import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/main.dart' as app_globals;
import 'package:intergalactic/ui/onboarding/demo_tutorial_content.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/help_tutorial_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/settings_category_help.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final previousClientManager = app_globals.clientManager;
    final clientManager = ClientManager();
    app_globals.clientManager = clientManager;
    addTearDown(() {
      app_globals.clientManager = previousClientManager;
      return clientManager.close();
    });
    await globals.preferences.init();
    // These cases assert the desktop tutorial surface. Pin the layout instead
    // of relying on BuildConfig's platform fallback: under `flutter test`
    // defaultTargetPlatform is android, so the unpinned default is mobile.
    // Cases that want the mobile surface override this themselves.
    await globals.preferences.layoutOverride.set('desktop');
  });

  test('Help category includes Tutorial tab', () {
    final tabs = SettingsCategoryHelp().tabs;

    expect(tabs.any((tab) => tab.label == 'Tutorial'), isTrue);
  });

  test('Help category includes Tutorial tab on mobile layout', () async {
    await globals.preferences.layoutOverride.set('mobile');
    final tabs = SettingsCategoryHelp().tabs;

    expect(tabs.any((tab) => tab.label == 'Tutorial'), isTrue);
  });

  testWidgets('Mobile tutorial page offers replay', (tester) async {
    await globals.preferences.layoutOverride.set('mobile');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(
          useMaterial3: true,
        ).copyWith(extensions: [const ThemeSettings()]),
        home: const Scaffold(body: HelpTutorialPage()),
      ),
    );

    expect(find.text('Tutorial'), findsOneWidget);
    expect(find.text('Replay tutorial'), findsOneWidget);
  });

  testWidgets('Replay tutorial button opens onboarding', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(
          useMaterial3: true,
        ).copyWith(extensions: [const ThemeSettings()]),
        home: const Scaffold(body: HelpTutorialPage()),
      ),
    );

    await tester.tap(find.text('Replay tutorial'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('Welcome to Inter Galactic'), findsWidgets);
    expect(find.text('1 of ${demoTutorialSteps.length}'), findsOneWidget);
  });

  testWidgets('Mobile replay uses the mobile guided tour', (tester) async {
    await globals.preferences.layoutOverride.set('mobile');
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(
          useMaterial3: true,
        ).copyWith(extensions: [const ThemeSettings()]),
        home: const Scaffold(body: HelpTutorialPage()),
      ),
    );

    await tester.tap(find.text('Replay tutorial'));
    await _pumpTutorialAnimation(tester);

    expect(find.byKey(const ValueKey('mobile-tutorial-sheet')), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('Developer placeholder button opens legacy onboarding', (
    tester,
  ) async {
    await globals.preferences.developerMode.set(true);

    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(
          useMaterial3: true,
        ).copyWith(extensions: [const ThemeSettings()]),
        home: const Scaffold(body: HelpTutorialPage()),
      ),
    );

    expect(find.text('Open placeholder tutorial'), findsOneWidget);

    await tester.tap(find.text('Open placeholder tutorial'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('Welcome to Inter Galactic'), findsWidgets);
    expect(find.text('1 of 10'), findsOneWidget);
  });
}

Future<void> _pumpTutorialAnimation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}
