import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/ui/onboarding/demo_tutorial_content.dart';
import 'package:intergalactic/ui/onboarding/mobile_tutorial_content.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/onboarding/tutorial_scene.dart';
import 'package:test/test.dart';

void main() {
  test('call demo scenes stay wired to the offline voice room controls', () {
    for (final id in [
      'rooms-voice',
      'calls-controls',
      'calls-popout',
      'soundboard-popup',
    ]) {
      expect(
        tutorialSceneSpecs[id]!.roomId,
        DemoClient.demoVoiceRoomId,
        reason: '$id should render the offline demo voice room.',
      );
    }

    expect(
      tutorialSceneSpecs['calls-controls']!.overlay,
      TutorialDemoOverlay.callMemberControls,
    );
    expect(
      tutorialSceneSpecs['calls-controls']!.focus!.anchorId,
      TutorialAnchorIds.callView,
    );
    expect(
      tutorialSceneSpecs['calls-popout']!.focus!.anchorId,
      TutorialAnchorIds.callPopoutButton,
    );
    expect(
      tutorialSceneSpecs['soundboard-popup']!.focus!.anchorId,
      TutorialAnchorIds.soundboardPopup,
    );
  });

  test('every mobile step has a mobile scene and stable anchor contract', () {
    final desktopStepsById = {
      for (final step in demoTutorialSteps) step.id: step,
    };

    for (final step in mobileTutorialSteps) {
      expect(
        step.targetAnchorId,
        isNotEmpty,
        reason: '${step.id} needs an anchor id.',
      );
      expect(
        mobileTutorialSceneSpecs,
        contains(step.id),
        reason: '${step.id} needs a mobile scene.',
      );
      expect(
        desktopOnlyTutorialStepIds,
        isNot(contains(step.id)),
        reason: '${step.id} is desktop-only.',
      );

      final desktopStep = desktopStepsById[step.id];
      if (desktopStep != null) {
        expect(
          step.icon,
          desktopStep.icon,
          reason: '${step.id} should retain its shared icon.',
        );
      }
    }

    for (final id in mobileOnlyTutorialStepIds) {
      expect(mobileTutorialSceneSpecs, contains(id));
    }
  });

  test('mobile lower-panel targets use the top tutorial sheet', () {
    const lowerTargets = {
      TutorialAnchorIds.composer,
      TutorialAnchorIds.composerPopup,
      TutorialAnchorIds.effectsMenu,
      TutorialAnchorIds.callView,
      TutorialAnchorIds.soundboardPopup,
      TutorialAnchorIds.activityCard,
      TutorialAnchorIds.accountPopup,
    };

    for (final entry in mobileTutorialSceneSpecs.entries) {
      final scene = entry.value;
      if (lowerTargets.contains(scene.focus?.anchorId)) {
        expect(
          scene.mobileCardPlacement,
          entry.key == 'soundboard-popup'
              ? TutorialMobileCardPlacement.bottom
              : TutorialMobileCardPlacement.top,
        );
      }
    }
  });

  test('mobile tutorial uses the requested card placements', () {
    expect(
      mobileTutorialSceneSpecs['welcome-1']!.mobileCardPlacement,
      TutorialMobileCardPlacement.top,
    );
    expect(mobileTutorialSceneSpecs['mobile-navigation']!.focus, isNull);
    expect(
      mobileTutorialSceneSpecs['rooms-chat']!.mobileCardPlacement,
      TutorialMobileCardPlacement.top,
    );
    expect(
      mobileTutorialSceneSpecs['messaging-effects-demo']!.mobileCardPlacement,
      TutorialMobileCardPlacement.top,
    );
    expect(
      mobileTutorialSceneSpecs['soundboard-popup']!.mobileCardPlacement,
      TutorialMobileCardPlacement.bottom,
    );
    expect(
      mobileTutorialSceneSpecs['privacy-default']!.mobileCardPlacement,
      TutorialMobileCardPlacement.top,
    );
    expect(
      mobileTutorialSceneSpecs['privacy-sessions']!.mobileCardPlacement,
      TutorialMobileCardPlacement.top,
    );
  });

  test('mobile direct messages spotlights the measured room list', () {
    final scene = mobileTutorialSceneSpecs['rooms-dms']!;

    expect(scene.mobilePanel, TutorialMobilePanel.navigation);
    expect(scene.overlay, TutorialDemoOverlay.roomList);
    expect(scene.focus!.anchorId, TutorialAnchorIds.roomList);
  });
}
