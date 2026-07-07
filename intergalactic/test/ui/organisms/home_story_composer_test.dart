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
import 'package:intergalactic/ui/organisms/home_screen/story_video_desktop_recorder.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_frame.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_trim_exporter.dart';

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

  test('camera flip control remains mobile-only', () {
    expect(
      homeStoryComposerShouldShowCameraFlip(
        usesNativeMobileCameraCapture: true,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerShouldShowCameraFlip(
        usesNativeMobileCameraCapture: false,
      ),
      isFalse,
    );
  });

  test('desktop recording releases live preview before ffmpeg capture', () {
    expect(
      homeStoryComposerShouldReleaseDesktopPreviewForRecording(
        usesDesktopStoryVideoRecorder: true,
        hasCameraPreview: true,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerShouldReleaseDesktopPreviewForRecording(
        usesDesktopStoryVideoRecorder: true,
        hasCameraPreview: false,
      ),
      isFalse,
    );
    expect(
      homeStoryComposerShouldReleaseDesktopPreviewForRecording(
        usesDesktopStoryVideoRecorder: false,
        hasCameraPreview: true,
      ),
      isFalse,
    );
  });

  test('desktop preview restore is gated to mounted desktop recorder path', () {
    expect(
      homeStoryComposerShouldRestoreDesktopPreviewAfterRecording(
        usesDesktopStoryVideoRecorder: true,
        mounted: true,
      ),
      isTrue,
    );
    expect(
      homeStoryComposerShouldRestoreDesktopPreviewAfterRecording(
        usesDesktopStoryVideoRecorder: true,
        mounted: false,
      ),
      isFalse,
    );
    expect(
      homeStoryComposerShouldRestoreDesktopPreviewAfterRecording(
        usesDesktopStoryVideoRecorder: false,
        mounted: true,
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

  test(
    'video recording cancel target follows platform and session ownership',
    () {
      expect(
        homeStoryComposerRecordingCancelTarget(
          usesNativeMobileCameraCapture: true,
          hasDesktopRecordingSession: false,
        ),
        HomeStoryComposerRecordingCancelTarget.nativeCamera,
      );
      expect(
        homeStoryComposerRecordingCancelTarget(
          usesNativeMobileCameraCapture: true,
          hasDesktopRecordingSession: true,
        ),
        HomeStoryComposerRecordingCancelTarget.nativeCamera,
      );
      expect(
        homeStoryComposerRecordingCancelTarget(
          usesNativeMobileCameraCapture: false,
          hasDesktopRecordingSession: false,
        ),
        HomeStoryComposerRecordingCancelTarget.nativeCamera,
      );
      expect(
        homeStoryComposerRecordingCancelTarget(
          usesNativeMobileCameraCapture: false,
          hasDesktopRecordingSession: true,
        ),
        HomeStoryComposerRecordingCancelTarget.desktopRecorder,
      );
    },
  );

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

  test('media services accept fake probe and desktop recorder seams', () async {
    const probeResult = StoryVideoProbeResult(
      duration: Duration(seconds: 12),
      size: Size(640, 360),
    );
    const desktopDevices = [
      StoryDesktopVideoInputDevice(
        label: 'video=Integrated Camera',
        displayName: 'Integrated Camera',
      ),
    ];
    final services = HomeStoryComposerMediaServices(
      videoProbe: const _FakeStoryVideoProbe(probeResult),
      desktopVideoRecorder: const _FakeDesktopVideoRecorder(desktopDevices),
    );

    expect(
      await services.videoProbe.probe('test-fixtures/story.mp4'),
      same(probeResult),
    );
    expect(
      await services.desktopVideoRecorder.listVideoInputDevices(),
      desktopDevices,
    );
    expect(
      await services.desktopVideoRecorder.start(
        deviceLabel: 'Integrated Camera',
      ),
      isA<StoryDesktopVideoRecordStartResult>()
          .having(
            (result) => result.status,
            'status',
            StoryDesktopVideoRecordStatus.unsupported,
          )
          .having((result) => result.message, 'message', 'fake recorder'),
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

  test('video editor decorations are gated until Prepare', () {
    expect(
      homeStoryVideoEditorCanEditDecorations(
        preparedForDecoration: false,
        exporting: false,
      ),
      isFalse,
    );
    expect(
      homeStoryVideoEditorCanEditDecorations(
        preparedForDecoration: true,
        exporting: false,
      ),
      isTrue,
    );
    expect(
      homeStoryVideoEditorCanEditDecorations(
        preparedForDecoration: true,
        exporting: true,
      ),
      isFalse,
    );
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
    expect(args.where((arg) => arg.contains('pad=')), isEmpty);
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
    expect(args, containsAllInOrder(['-c:v', 'mjpeg']));
    expect(args, contains('-an'));
    expect(args, isNot(contains('libx264')));
    expect(args, isNot(contains('libx265')));
  });

  test('desktop story recording command emits preview frames on stdout', () {
    final args = storyDesktopVideoRecordArguments(
      deviceLabel: 'Integrated Camera',
      outputPath: 'test-fixtures/story-recording.mp4',
    );

    expect(args, contains('test-fixtures/story-recording.mp4'));
    expect(args, containsAllInOrder(['-map', '0:v:0']));
    expect(args, containsAllInOrder(['-vf', 'fps=15,scale=720:-2']));
    expect(args, containsAllInOrder(['-c:v', 'mjpeg']));
    expect(args, containsAllInOrder(['-q:v', '5']));
    expect(args, containsAllInOrder(['-f', 'image2pipe', 'pipe:1']));
  });

  test('desktop recording preview parser keeps split jpeg frames', () {
    final parser = StoryDesktopVideoPreviewFrameParser();

    expect(parser.add(Uint8List.fromList([0xff, 0xd8, 1, 2, 0xff])), isEmpty);
    final frames = parser.add(
      Uint8List.fromList([0xd9, 0, 0xff, 0xd8, 3, 0xff, 0xd9]),
    );

    expect(frames, hasLength(2));
    expect(frames[0], orderedEquals([0xff, 0xd8, 1, 2, 0xff, 0xd9]));
    expect(frames[1], orderedEquals([0xff, 0xd8, 3, 0xff, 0xd9]));
  });

  test('desktop story input list command asks DirectShow for devices', () {
    expect(
      storyDesktopVideoInputListArguments(),
      containsAllInOrder(['-list_devices', 'true', '-f', 'dshow']),
    );
  });

  test('desktop story input parser keeps video device labels only', () {
    final devices = parseStoryDesktopVideoInputDevices('''
[dshow @ 000001] DirectShow video devices
[dshow @ 000001]  "Integrated Camera" (video)
[dshow @ 000001]     Alternative name "@device_pnp_foo"
[dshow @ 000001]  "USB Capture HDMI" (video)
[dshow @ 000001] DirectShow audio devices
[dshow @ 000001]  "Microphone Array" (audio)
''');

    expect(devices.map((device) => device.displayName), [
      'Integrated Camera',
      'USB Capture HDMI',
    ]);
  });

  test(
    'desktop story recording command preserves Windows-style output path',
    () {
      const outputPath = r'<install-dir>\Inter Galactic\story recording.mp4';
      final args = storyDesktopVideoRecordArguments(
        deviceLabel: 'Integrated Camera',
        outputPath: outputPath,
      );

      expect(args, containsAllInOrder(['-y', outputPath]));
    },
  );
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

class _FakeDesktopVideoRecorder implements StoryDesktopVideoRecorder {
  const _FakeDesktopVideoRecorder(this.devices);

  final List<StoryDesktopVideoInputDevice> devices;

  StoryVideoFfmpegTools get tools => const StoryVideoFfmpegTools();

  @override
  Future<List<StoryDesktopVideoInputDevice>> listVideoInputDevices() async {
    return devices;
  }

  @override
  Future<StoryDesktopVideoRecordStartResult> start({
    required String deviceLabel,
    String? sourceName,
  }) async {
    return StoryDesktopVideoRecordStartResult.unsupported('fake recorder');
  }
}
