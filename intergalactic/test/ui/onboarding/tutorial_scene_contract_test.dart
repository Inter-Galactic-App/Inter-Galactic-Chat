import 'package:intergalactic/client/demo/demo_client.dart';
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
}
