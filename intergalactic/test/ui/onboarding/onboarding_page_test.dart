import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/onboarding/demo_tutorial_content.dart';
import 'package:intergalactic/ui/onboarding/onboarding_page.dart';
import 'package:intergalactic/ui/onboarding/onboarding_service.dart';
import 'package:intergalactic/ui/onboarding/onboarding_step.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/onboarding/tutorial_mode.dart';
import 'package:intergalactic/ui/onboarding/tutorial_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Preferences preferences;
  late OnboardingService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = Preferences();
    await preferences.init();
    await globals.preferences.init();
    // These cases assert the desktop tutorial surface. Pin the layout instead
    // of relying on BuildConfig's platform fallback: under `flutter test`
    // defaultTargetPlatform is android, so the unpinned default is mobile.
    // Cases that want the mobile surface override this themselves.
    await globals.preferences.layoutOverride.set('desktop');
    service = OnboardingService(preferences);
  });

  test('demo tutorial steps have scene mappings and anchors', () {
    for (final step in demoTutorialSteps) {
      expect(tutorialSceneSpecs, contains(step.id));
      expect(step.targetAnchorId, isNotNull);
      expect(step.targetAnchorId!.isNotEmpty, isTrue);
    }
  });

  test('key demo scenes use measured tutorial anchors', () {
    expect(
      tutorialSceneSpecs['spaces-1']!.focus!.anchorId,
      TutorialAnchorIds.spaceRail,
    );
    expect(
      tutorialSceneSpecs['rooms-1']!.focus!.anchorId,
      TutorialAnchorIds.roomList,
    );
    expect(
      tutorialSceneSpecs['messaging-1']!.focus!.anchorId,
      TutorialAnchorIds.composer,
    );
    expect(
      tutorialSceneSpecs['messaging-menus']!.focus!.anchorId,
      TutorialAnchorIds.composerPopup,
    );
    expect(tutorialSceneSpecs['rooms-photo']!.focus, isNull);
    expect(tutorialSceneSpecs['rooms-photo']!.sidePanel, isNull);
    expect(
      tutorialSceneSpecs['privacy-padlock']!.focus!.anchorId,
      TutorialAnchorIds.encryptedRoomPadlock,
    );
    expect(
      tutorialSceneSpecs['privacy-padlock']!.sidePanel,
      TutorialDemoSidePanel.defaultView,
    );
  });

  test('broad settings demo scenes do not dim the backdrop', () {
    const broadSettingsScenes = [
      'emoticons-room',
      'emoticons-app',
      'calls-settings',
      'soundboard-space',
      'soundboard-app',
      'notifications-settings',
      'notifications-overrides',
      'desktop-companion-settings',
      'customization-appearance',
      'customization-room',
      'customization-theme-editor',
      'activity-settings',
      'privacy-security-settings',
      'help-safety',
      'help-report-bug',
    ];

    for (final id in broadSettingsScenes) {
      expect(
        tutorialSceneSpecs[id]!.focus,
        isNull,
        reason: '$id should show the full settings page without dimming it.',
      );
    }
  });

  testWidgets('renders the first step controls', (tester) async {
    await _pumpTutorialLauncher(tester, service: service);

    expect(find.text('1 of ${demoTutorialSteps.length}'), findsOneWidget);
    expect(find.text('Welcome to Inter Galactic'), findsWidgets);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('mobile layout does not open tutorial route', (tester) async {
    await globals.preferences.layoutOverride.set('mobile');

    await _pumpTutorialLauncher(tester, service: service);

    expect(find.text('Welcome to Inter Galactic'), findsNothing);
    expect(find.text('Open tutorial'), findsOneWidget);
    expect(service.state.completed, isFalse);
  });

  testWidgets('Next advances progress and Back returns', (tester) async {
    await _pumpTutorialLauncher(tester, service: service);

    await tester.tap(find.text('Next'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('2 of ${demoTutorialSteps.length}'), findsOneWidget);
    expect(find.text('Spaces and Servers'), findsWidgets);

    await tester.tap(find.text('Back'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('1 of ${demoTutorialSteps.length}'), findsOneWidget);
    expect(find.text('Welcome to Inter Galactic'), findsWidgets);
  });

  testWidgets('Skip records completion and pops', (tester) async {
    await _pumpTutorialLauncher(tester, service: service);

    await tester.tap(find.text('Skip'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('Open tutorial'), findsOneWidget);
    expect(service.state.completed, isTrue);
    expect(service.state.version, OnboardingService.currentVersion);
  });

  testWidgets('Finish on final step records completion and pops', (
    tester,
  ) async {
    await _pumpTutorialLauncher(
      tester,
      service: service,
      steps: [demoTutorialSteps.first],
    );

    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('Open tutorial'), findsOneWidget);
    expect(service.state.completed, isTrue);
  });

  testWidgets('replay mode opens when onboarding is already completed', (
    tester,
  ) async {
    await service.markCompleted();

    await _pumpTutorialLauncher(tester, service: service, replay: true);

    expect(find.text('Tutorial replay'), findsOneWidget);
    expect(find.text('1 of ${demoTutorialSteps.length}'), findsOneWidget);
  });

  testWidgets('demo preview Skip does not record completion', (tester) async {
    await _pumpTutorialLauncher(
      tester,
      service: service,
      replay: true,
      mode: TutorialMode.demoPreview,
    );

    expect(find.text('Tutorial replay'), findsOneWidget);
    expect(find.text('1 of ${demoTutorialSteps.length}'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('Open tutorial'), findsOneWidget);
    expect(service.state.completed, isFalse);
    expect(service.state.version, 0);
  });

  testWidgets('demo preview Finish does not record completion', (tester) async {
    await _pumpTutorialLauncher(
      tester,
      service: service,
      replay: true,
      mode: TutorialMode.demoPreview,
      steps: [demoTutorialSteps.first],
    );

    expect(find.text('1 of 1'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('Open tutorial'), findsOneWidget);
    expect(service.state.completed, isFalse);
    expect(service.state.version, 0);
  });

  testWidgets('demo preview Next advances progress and Back returns', (
    tester,
  ) async {
    await _pumpTutorialLauncher(
      tester,
      service: service,
      replay: true,
      mode: TutorialMode.demoPreview,
    );

    await tester.tap(find.text('Next'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('2 of ${demoTutorialSteps.length}'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('1 of ${demoTutorialSteps.length}'), findsOneWidget);
    expect(service.state.completed, isFalse);
  });
}

Future<void> _pumpTutorialLauncher(
  WidgetTester tester, {
  required OnboardingService service,
  bool replay = false,
  TutorialMode mode = TutorialMode.realAccount,
  List<OnboardingStep>? steps,
}) async {
  if (mode.usesGuidedDemoBackdrop) {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(
        useMaterial3: true,
      ).copyWith(extensions: [const ThemeSettings()]),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: TextButton(
                onPressed: () {
                  OnboardingPage.show(
                    context,
                    replay: replay,
                    mode: mode,
                    service: service,
                    steps: steps,
                  );
                },
                child: const Text('Open tutorial'),
              ),
            );
          },
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open tutorial'));
  await _pumpTutorialAnimation(tester);
}

Future<void> _pumpTutorialAnimation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}
