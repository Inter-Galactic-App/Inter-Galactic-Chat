import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_filter.dart';

void main() {
  test('every story filter matrix has 20 values', () {
    for (final preset in StoryFilterPreset.values) {
      expect(storyFilterPresetMatrix(preset), hasLength(20));
      expect(storyFilterMatrix(preset), hasLength(20));
    }
  });

  test('original and zero intensity return identity', () {
    expect(
      storyFilterMatrix(StoryFilterPreset.original),
      storyFilterIdentityMatrix,
    );
    expect(
      storyFilterMatrix(StoryFilterPreset.sepia, intensity: 0),
      storyFilterIdentityMatrix,
    );
  });

  test('full intensity returns the preset matrix', () {
    expect(
      storyFilterMatrix(StoryFilterPreset.contrast, intensity: 1),
      storyFilterPresetMatrix(StoryFilterPreset.contrast),
    );
  });

  test('intensity clamps below zero and above one', () {
    expect(
      storyFilterMatrix(StoryFilterPreset.warm, intensity: -0.5),
      storyFilterIdentityMatrix,
    );
    expect(
      storyFilterMatrix(StoryFilterPreset.cool, intensity: 2),
      storyFilterPresetMatrix(StoryFilterPreset.cool),
    );
  });
}
