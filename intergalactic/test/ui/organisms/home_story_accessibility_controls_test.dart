import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';

void main() {
  test('story overlay keyboard movement clamps to canvas bounds', () {
    expect(
      storyOverlayMovedCenter(
        center: const Offset(0.5, 0.5),
        delta: const Offset(storyOverlayKeyboardMoveStep, 0),
      ),
      const Offset(0.54, 0.5),
    );

    expect(
      storyOverlayMovedCenter(
        center: const Offset(0.95, 0.03),
        delta: const Offset(0.20, -0.20),
      ),
      const Offset(0.96, 0.04),
    );
  });
}
