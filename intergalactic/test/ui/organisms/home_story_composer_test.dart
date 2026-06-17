import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_composer.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_video_editor.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_video_tools.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_desktop_recorder.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_trim_exporter.dart';

void main() {
  test('iOS story photo library import uses the native image picker path', () {
    expect(
      homeStoryComposerUsesNativePhotoLibraryPicker(isIOS: true),
      isTrue,
    );
    expect(
      homeStoryComposerUsesNativePhotoLibraryPicker(isIOS: false),
      isFalse,
    );
    expect(
        homeStoryComposerIosPhotoLibraryImageQuality, inInclusiveRange(1, 100));
  });

  test('draft review frame keeps the story canvas aspect ratio', () {
    expect(
      homeStoryDraftReviewFrameWidth / homeStoryDraftReviewTileHeight,
      closeTo(storyEditorAspectRatio, 0.001),
    );
    expect(
      homeStoryDraftReviewTileWidth,
      greaterThan(homeStoryDraftReviewFrameWidth),
    );
  });

  test('recording progress and time left clamp to the story cap', () {
    const maxDuration = Duration(seconds: 30);

    expect(
      homeStoryComposerRecordingProgress(
        elapsed: Duration.zero,
        maxDuration: maxDuration,
      ),
      0,
    );
    expect(
      homeStoryComposerRecordingProgress(
        elapsed: const Duration(seconds: 15),
        maxDuration: maxDuration,
      ),
      closeTo(0.5, 0.001),
    );
    expect(
      homeStoryComposerRecordingProgress(
        elapsed: const Duration(seconds: 45),
        maxDuration: maxDuration,
      ),
      1,
    );

    expect(
      homeStoryComposerRecordingTimeLeft(
        elapsed: const Duration(seconds: 12),
        maxDuration: maxDuration,
      ),
      const Duration(seconds: 18),
    );
    expect(
      homeStoryComposerRecordingTimeLeft(
        elapsed: const Duration(seconds: 31),
        maxDuration: maxDuration,
      ),
      Duration.zero,
    );
  });

  test('story video recording is available on mobile and Windows desktop', () {
    expect(
      homeStoryComposerCanRecordVideo(
        usesNativeMobileCameraCapture: true,
        isWindows: false,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerCanRecordVideo(
        usesNativeMobileCameraCapture: false,
        isWindows: true,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerCanRecordVideo(
        usesNativeMobileCameraCapture: false,
        isWindows: false,
      ),
      isFalse,
    );
  });

  test('video editor opens for valid oversized sources so trim can export', () {
    expect(
      homeStoryComposerShouldOpenVideoEditor(
        sizeBytes: 1024,
        duration: const Duration(seconds: 12),
      ),
      isTrue,
    );
    expect(
      homeStoryComposerShouldOpenVideoEditor(
        sizeBytes: 150 * 1024 * 1024,
        duration: const Duration(seconds: 45),
      ),
      isTrue,
    );
    expect(
      homeStoryComposerShouldOpenVideoEditor(
        sizeBytes: 150 * 1024 * 1024,
        duration: const Duration(seconds: 12),
      ),
      isTrue,
    );
    expect(
      homeStoryComposerShouldOpenVideoEditor(
        sizeBytes: 0,
        duration: const Duration(seconds: 12),
      ),
      isFalse,
    );
    expect(
      homeStoryComposerShouldOpenVideoEditor(
        sizeBytes: 1024,
        duration: Duration.zero,
      ),
      isFalse,
    );
  });

  test('video editor exports changed trims or oversized full-source clips', () {
    expect(
      homeStoryVideoEditorShouldExportBeforeUpload(
        usesFullSource: true,
        duration: const Duration(seconds: 12),
        sizeBytes: 8 * 1024 * 1024,
      ),
      isFalse,
    );
    expect(
      homeStoryVideoEditorShouldExportBeforeUpload(
        usesFullSource: true,
        duration: const Duration(seconds: 12),
        sizeBytes: 150 * 1024 * 1024,
      ),
      isTrue,
    );
    expect(
      homeStoryVideoEditorShouldExportBeforeUpload(
        usesFullSource: false,
        duration: const Duration(seconds: 45),
        sizeBytes: 8 * 1024 * 1024,
      ),
      isTrue,
    );
  });

  test('native recording cleanup treats start stop and active states as busy',
      () {
    expect(
      homeStoryComposerHasNativeRecordingWorkInFlight(
        recordingVideo: false,
        recordingStarting: false,
        stoppingVideoRecording: false,
      ),
      isFalse,
    );
    expect(
      homeStoryComposerHasNativeRecordingWorkInFlight(
        recordingVideo: true,
        recordingStarting: false,
        stoppingVideoRecording: false,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerHasNativeRecordingWorkInFlight(
        recordingVideo: false,
        recordingStarting: true,
        stoppingVideoRecording: false,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerHasNativeRecordingWorkInFlight(
        recordingVideo: false,
        recordingStarting: false,
        stoppingVideoRecording: true,
      ),
      isTrue,
    );
  });

  test('video draft carries background color into upload metadata', () {
    const background = Color(0xFF10303A);
    final draft = StoryVideoDraft(
      id: 'video-1',
      path: 'test-fixtures/story.mp4',
      sourceName: 'story.mp4',
      sourceMimeType: 'video/mp4',
      sizeBytes: 1024,
      duration: const Duration(seconds: 12),
      width: 640,
      height: 360,
      backgroundColor: background,
    );

    expect(draft.toUpload().backgroundColor, background.toARGB32());
  });

  test('video draft carries visual mention overlays into upload metadata', () {
    final draft = StoryVideoDraft(
      id: 'video-mention-1',
      path: 'test-fixtures/story.mp4',
      sourceName: 'story.mp4',
      sourceMimeType: 'video/mp4',
      sizeBytes: 1024,
      duration: const Duration(seconds: 12),
      width: 640,
      height: 360,
      overlays: const [
        StoryMentionOverlay(
          id: 'mention-1',
          center: Offset(0.5, 0.5),
          userId: '@alice:example.org',
          displayName: 'Alice',
        ),
      ],
    );

    expect(
      draft.toUpload(
        mentionedUserIds: const [
          '@bob:example.org',
          '@alice:example.org',
        ],
      ).mentionedUserIds,
      ['@bob:example.org', '@alice:example.org'],
    );

    expect(
      draft.toUpload().mentionedUserIds,
      ['@alice:example.org'],
    );
  });

  test('video trim region drag preserves duration and clamps to source', () {
    final shiftedRight = storyVideoShiftTrimRange(
      sourceDuration: const Duration(seconds: 60),
      trimStart: const Duration(seconds: 10),
      trimEnd: const Duration(seconds: 25),
      delta: const Duration(seconds: 20),
    );

    expect(shiftedRight.trimStart, const Duration(seconds: 30));
    expect(shiftedRight.trimEnd, const Duration(seconds: 45));
    expect(shiftedRight.trimEnd - shiftedRight.trimStart,
        const Duration(seconds: 15));

    final shiftedPastStart = storyVideoShiftTrimRange(
      sourceDuration: const Duration(seconds: 60),
      trimStart: const Duration(seconds: 10),
      trimEnd: const Duration(seconds: 25),
      delta: const Duration(seconds: -30),
    );

    expect(shiftedPastStart.trimStart, Duration.zero);
    expect(shiftedPastStart.trimEnd, const Duration(seconds: 15));

    final shiftedPastEnd = storyVideoShiftTrimRange(
      sourceDuration: const Duration(seconds: 60),
      trimStart: const Duration(seconds: 45),
      trimEnd: const Duration(seconds: 60),
      delta: const Duration(seconds: 30),
    );

    expect(shiftedPastEnd.trimStart, const Duration(seconds: 45));
    expect(shiftedPastEnd.trimEnd, const Duration(seconds: 60));
  });

  test('video trim export command uses LGPL-only ffmpeg encoders', () {
    final args = storyVideoTrimExportArguments(
      sourcePath: 'test-fixtures/source.mp4',
      trimStart: const Duration(seconds: 2),
      selectedDuration: const Duration(seconds: 12),
      outputPath: 'test-fixtures/story-trim.mp4',
    );

    expect(args, containsAllInOrder(['-c:v', 'mpeg4']));
    expect(args, containsAllInOrder(['-tag:v', 'mp4v']));
    expect(args, containsAllInOrder(['-c:a', 'aac']));
    expect(args, isNot(contains('libx264')));
    expect(args, isNot(contains('libx265')));
  });

  test('mobile video trim export bridge passes trim range in milliseconds', () {
    final args = storyVideoMobileTrimExportArguments(
      sourcePath: 'test-fixtures/source.mp4',
      sourceName: 'source.mp4',
      trimStart: const Duration(seconds: 3),
      trimEnd: const Duration(seconds: 18),
    );

    expect(args['sourcePath'], 'test-fixtures/source.mp4');
    expect(args['sourceName'], 'source.mp4');
    expect(args['trimStartMs'], 3000);
    expect(args['trimEndMs'], 18000);
  });

  test('desktop story recording command uses LGPL-only ffmpeg encoders', () {
    final args = storyDesktopVideoRecordArguments(
      deviceLabel: 'Integrated Camera',
      outputPath: 'test-fixtures/story-recording.mp4',
    );

    expect(args, containsAllInOrder(['-f', 'dshow']));
    expect(args, contains('video=Integrated Camera'));
    expect(args, containsAllInOrder(['-c:v', 'mpeg4']));
    expect(args, containsAllInOrder(['-tag:v', 'mp4v']));
    expect(args, contains('-an'));
    expect(args, isNot(contains('libx264')));
    expect(args, isNot(contains('libx265')));
  });

  test('desktop story recording command preserves Windows-style output path',
      () {
    const outputPath = r'<install-dir>\Inter Galactic\story recording.mp4';
    final args = storyDesktopVideoRecordArguments(
      deviceLabel: 'Integrated Camera',
      outputPath: outputPath,
    );

    expect(args, containsAllInOrder(['-y', outputPath]));
  });
}
