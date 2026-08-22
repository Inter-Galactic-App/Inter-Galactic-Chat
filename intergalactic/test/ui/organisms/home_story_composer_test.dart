import 'dart:typed_data';

import 'package:camera/camera.dart' as native_camera;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_composer.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_video_editor.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_video_tools.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_frame.dart';

void main() {
  test('iOS story photo library import uses the native image picker path', () {
    expect(homeStoryComposerUsesNativePhotoLibraryPicker(isIOS: true), isTrue);
    expect(
      homeStoryComposerUsesNativePhotoLibraryPicker(isIOS: false),
      isFalse,
    );
    expect(
      homeStoryComposerIosPhotoLibraryImageQuality,
      inInclusiveRange(1, 100),
    );
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

  test('story video recording follows the native camera plugin', () {
    expect(
      homeStoryComposerCanRecordVideo(usesNativeCameraCapture: true),
      isTrue,
    );
    expect(
      homeStoryComposerCanRecordVideo(usesNativeCameraCapture: false),
      isFalse,
    );
  });

  test('camera flip control remains mobile-only', () {
    expect(
      homeStoryComposerShouldShowCameraFlip(usesMobileCameraCapture: true),
      isTrue,
    );
    expect(
      homeStoryComposerShouldShowCameraFlip(usesMobileCameraCapture: false),
      isFalse,
    );
  });

  test('Windows gets the camera input selector instead of the flip button', () {
    // Windows: native capture, but no lens direction to flip between.
    expect(
      homeStoryComposerShouldShowCameraInputSelector(
        usesNativeCameraCapture: true,
        usesMobileCameraCapture: false,
      ),
      isTrue,
    );
    // Mobile gets the flip button, not the selector.
    expect(
      homeStoryComposerShouldShowCameraInputSelector(
        usesNativeCameraCapture: true,
        usesMobileCameraCapture: true,
      ),
      isFalse,
    );
    // macOS/Linux/web cannot capture at all, so neither control applies.
    expect(
      homeStoryComposerShouldShowCameraInputSelector(
        usesNativeCameraCapture: false,
        usesMobileCameraCapture: false,
      ),
      isFalse,
    );
  });

  test('video editor opens for any real video, including unusable ones', () {
    // It still opens for oversized sources: the editor is where the person is
    // told the clip cannot be posted, now that nothing can re-encode it.
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

  test('a postable clip is one that is short enough and small enough', () {
    expect(
      homeStoryVideoEditorSourceIsUnusable(
        duration: const Duration(seconds: 12),
        sizeBytes: 8 * 1024 * 1024,
      ),
      isFalse,
    );
    // Too big. There is no re-encoder any more, so this is now a refusal
    // rather than a trigger for an ffmpeg export.
    expect(
      homeStoryVideoEditorSourceIsUnusable(
        duration: const Duration(seconds: 12),
        sizeBytes: 150 * 1024 * 1024,
      ),
      isTrue,
    );
    // Too long, same reason.
    expect(
      homeStoryVideoEditorSourceIsUnusable(
        duration: const Duration(seconds: 45),
        sizeBytes: 8 * 1024 * 1024,
      ),
      isTrue,
    );
  });

  test('overlay editing unlocks once the draft is prepared', () {
    expect(
      homeStoryVideoEditorCanEditDecorations(preparedForDecoration: true),
      isTrue,
    );
    expect(
      homeStoryVideoEditorCanEditDecorations(preparedForDecoration: false),
      isFalse,
    );
  });

  test(
    'native recording cleanup treats start stop and active states as busy',
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
    },
  );

  test('camera release cancels only while recording work is in flight', () {
    expect(
      homeStoryComposerShouldCancelRecordingBeforeCameraRelease(
        recordingVideo: false,
        recordingStarting: false,
        stoppingVideoRecording: false,
      ),
      isFalse,
    );
    expect(
      homeStoryComposerShouldCancelRecordingBeforeCameraRelease(
        recordingVideo: true,
        recordingStarting: false,
        stoppingVideoRecording: false,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerShouldCancelRecordingBeforeCameraRelease(
        recordingVideo: false,
        recordingStarting: true,
        stoppingVideoRecording: false,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerShouldCancelRecordingBeforeCameraRelease(
        recordingVideo: false,
        recordingStarting: false,
        stoppingVideoRecording: true,
      ),
      isTrue,
    );
  });

  test('story draft status prefers terminal then active states', () {
    expect(
      homeStoryComposerDraftStatus(
        preparingDrafts: false,
        uploading: false,
        sent: false,
        failed: false,
      ),
      isNull,
    );
    expect(
      homeStoryComposerDraftStatus(
        preparingDrafts: true,
        uploading: false,
        sent: false,
        failed: false,
      ),
      HomeStoryComposerDraftStatus.preparing,
    );
    expect(
      homeStoryComposerDraftStatus(
        preparingDrafts: true,
        uploading: true,
        sent: false,
        failed: false,
      ),
      HomeStoryComposerDraftStatus.sharing,
    );
    expect(
      homeStoryComposerDraftStatus(
        preparingDrafts: true,
        uploading: true,
        sent: true,
        failed: false,
      ),
      HomeStoryComposerDraftStatus.sent,
    );
    expect(
      homeStoryComposerDraftStatus(
        preparingDrafts: true,
        uploading: true,
        sent: true,
        failed: true,
      ),
      HomeStoryComposerDraftStatus.failed,
    );
  });

  test('media services accept a fake video probe seam', () async {
    const probeResult = StoryVideoProbeResult(
      duration: Duration(seconds: 12),
      size: Size(640, 360),
    );
    final services = HomeStoryComposerMediaServices(
      videoProbe: const _FakeStoryVideoProbe(probeResult),
    );

    expect(
      await services.videoProbe.probe('test-fixtures/story.mp4'),
      same(probeResult),
    );
  });

  test('native camera selection prefers front or main rear camera', () {
    const front = native_camera.CameraDescription(
      name: 'front camera',
      lensDirection: native_camera.CameraLensDirection.front,
      sensorOrientation: 90,
    );
    const teleRear = native_camera.CameraDescription(
      name: '2 tele rear',
      lensDirection: native_camera.CameraLensDirection.back,
      sensorOrientation: 90,
    );
    const mainRear = native_camera.CameraDescription(
      name: 'main wide rear',
      lensDirection: native_camera.CameraLensDirection.back,
      sensorOrientation: 90,
    );
    const ultraRear = native_camera.CameraDescription(
      name: 'ultra wide back',
      lensDirection: native_camera.CameraLensDirection.back,
      sensorOrientation: 90,
    );

    expect(
      homeStoryComposerSelectNativeCamera([
        teleRear,
        front,
        mainRear,
        ultraRear,
      ], preferFront: true),
      front,
    );
    expect(
      homeStoryComposerSelectNativeCamera([
        teleRear,
        front,
        ultraRear,
        mainRear,
      ], preferFront: false),
      mainRear,
    );
    expect(
      homeStoryComposerNativeBackCameraScore(mainRear),
      lessThan(homeStoryComposerNativeBackCameraScore(ultraRear)),
    );
  });

  test(
    'native camera selection falls back to first camera if direction absent',
    () {
      const external = native_camera.CameraDescription(
        name: 'external usb camera',
        lensDirection: native_camera.CameraLensDirection.external,
        sensorOrientation: 0,
      );
      const rear = native_camera.CameraDescription(
        name: 'rear camera',
        lensDirection: native_camera.CameraLensDirection.back,
        sensorOrientation: 90,
      );

      expect(
        homeStoryComposerSelectNativeCamera([
          external,
          rear,
        ], preferFront: true),
        external,
      );
    },
  );

  test('video draft carries background choice into upload metadata', () {
    const background = Color(0xFF10303A);
    const gradient = Color(0xFF4DD0E1);
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
      backgroundGradientColor: gradient,
      backgroundMode: StoryBackgroundMode.gradient,
    );

    expect(draft.toUpload().backgroundColor, background.toARGB32());
    expect(draft.toUpload().backgroundGradientColor, gradient.toARGB32());
    expect(draft.toUpload().backgroundMode, StoryBackgroundMode.gradient);
  });

  test('contain-fit wide video frame leaves background visible', () {
    final size = storyVideoMediaFrameSize(
      canvasSize: const Size(1080, 1920),
      fitMode: StoryVideoFitMode.fit,
      mediaWidth: 1920,
      mediaHeight: 1080,
    );

    expect(size.width, 1080);
    expect(size.height, closeTo(607.5, 0.01));
    expect(
      storyVideoMediaFrameSize(
        canvasSize: const Size(1080, 1920),
        fitMode: StoryVideoFitMode.fill,
        mediaWidth: 1920,
        mediaHeight: 1080,
      ),
      const Size(1080, 1920),
    );
  });

  test('video probe visible size ignores encoded black letterbox bars', () {
    final thumbnail = _letterboxedVideoThumbnail(
      width: 1080,
      height: 1920,
      contentTop: 656,
      contentHeight: 608,
    );

    final analysis = storyVideoVisibleContentAnalysisFromThumbnail(
      reportedSize: const Size(1080, 1920),
      thumbnailBytes: thumbnail,
    );
    final visibleSize = storyVideoVisibleContentSizeFromThumbnail(
      reportedSize: const Size(1080, 1920),
      thumbnailBytes: thumbnail,
    );

    expect(analysis, isNotNull);
    expect(analysis!.hasVerticalBars, isTrue);
    expect(analysis.hasHorizontalBars, isFalse);
    expect(visibleSize, isNotNull);
    expect(visibleSize!.width, 1080);
    expect(visibleSize.height, closeTo(608, 0.01));
    expect(
      storyVideoMediaFrameSize(
        canvasSize: const Size(1080, 1920),
        fitMode: StoryVideoFitMode.fit,
        mediaWidth: 1080,
        mediaHeight: 1920,
        displayWidth: visibleSize.width.round(),
        displayHeight: visibleSize.height.round(),
      ).height,
      closeTo(608, 0.01),
    );
  });

  test('video probe does not treat dark frames as baked letterbox content', () {
    final thumbnail = _letterboxedVideoThumbnail(
      width: 1080,
      height: 1920,
      contentTop: 656,
      contentHeight: 608,
      contentColor: img.ColorRgb8(24, 24, 24),
    );

    final analysis = storyVideoVisibleContentAnalysisFromThumbnail(
      reportedSize: const Size(1080, 1920),
      thumbnailBytes: thumbnail,
    );

    expect(analysis, isNull);
    expect(
      storyVideoVisibleContentSizeFromThumbnail(
        reportedSize: const Size(1080, 1920),
        thumbnailBytes: thumbnail,
      ),
      const Size(1080, 1920),
    );
  });

  test('fit-mode video content stays contained for direct inner players', () {
    expect(storyVideoInnerFit(StoryVideoFitMode.fit), BoxFit.contain);
    expect(
      storyVideoInnerFit(StoryVideoFitMode.fit, hasBakedLetterbox: true),
      BoxFit.contain,
    );
    expect(storyVideoInnerFit(StoryVideoFitMode.fill), BoxFit.cover);
  });

  test('story video canvas sizing keeps the portrait story frame', () {
    final portrait = storyVideoCanvasSizeForConstraints(
      constraints: const BoxConstraints.tightFor(width: 1920, height: 1080),
      canvasMode: StoryVideoCanvasMode.portrait,
    );

    expect(portrait.width, closeTo(607.5, 0.01));
    expect(portrait.height, 1080);
  });

  test('video draft carries fit mode into upload metadata', () {
    final draft = StoryVideoDraft(
      id: 'video-fit-1',
      path: 'test-fixtures/story.mp4',
      sourceName: 'story.mp4',
      sourceMimeType: 'video/mp4',
      sizeBytes: 1024,
      duration: const Duration(seconds: 12),
      width: 640,
      height: 360,
      fitMode: StoryVideoFitMode.fill,
    );

    expect(draft.toUpload().fitMode, StoryVideoFitMode.fill);
    expect(draft.toUpload().fitMode.boxFit, BoxFit.cover);
  });

  test('video draft keeps landscape media but uploads on portrait canvas', () {
    final draft = StoryVideoDraft(
      id: 'video-canvas-1',
      path: 'test-fixtures/story.mp4',
      sourceName: 'story.mp4',
      sourceMimeType: 'video/mp4',
      sizeBytes: 1024,
      duration: const Duration(seconds: 12),
      width: 1920,
      height: 1080,
      displayWidth: 1080,
      displayHeight: 608,
      hasBakedLetterbox: true,
      canvasMode: StoryVideoCanvasMode.landscape,
      preparedForDecoration: false,
    );

    expect(draft.preparedForDecoration, isFalse);
    expect(draft.canvasMode, StoryVideoCanvasMode.landscape);
    final upload = draft.toUpload();
    expect(upload.width, 1920);
    expect(upload.height, 1080);
    expect(upload.displayWidth, 1080);
    expect(upload.displayHeight, 608);
    expect(upload.hasBakedLetterbox, isTrue);
    expect(upload.canvasMode, StoryVideoCanvasMode.portrait);
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
      draft
          .toUpload(
            mentionedUserIds: const ['@bob:example.org', '@alice:example.org'],
          )
          .mentionedUserIds,
      ['@bob:example.org', '@alice:example.org'],
    );

    expect(draft.toUpload().mentionedUserIds, ['@alice:example.org']);
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
    expect(
      shiftedRight.trimEnd - shiftedRight.trimStart,
      const Duration(seconds: 15),
    );

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
}

Uint8List _letterboxedVideoThumbnail({
  required int width,
  required int height,
  required int contentTop,
  required int contentHeight,
  img.Color? contentColor,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0, 0, 0));
  final contentBottom = contentTop + contentHeight;
  final fillColor = contentColor ?? img.ColorRgb8(77, 208, 225);
  for (var y = contentTop; y < contentBottom; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixel(x, y, fillColor);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

class _FakeStoryVideoProbe implements StoryVideoProbe {
  const _FakeStoryVideoProbe(this.result);

  final StoryVideoProbeResult result;

  @override
  Future<StoryVideoProbeResult> probe(String path) async {
    return result;
  }
}
