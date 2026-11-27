import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart' as native_camera;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide Uint8List;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:image_picker/image_picker.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_editor.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_upload_result.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_video_editor.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_video_tools.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_image_renderer.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_frame.dart';
import 'package:intergalactic/utils/download_utils.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

@visibleForTesting
const double homeStoryDraftReviewTileWidth = 92;

@visibleForTesting
const double homeStoryDraftReviewTileHeight = 124;

@visibleForTesting
const double homeStoryDraftReviewFrameWidth =
    homeStoryDraftReviewTileHeight * storyEditorAspectRatio;

@visibleForTesting
const int homeStoryComposerIosPhotoLibraryImageQuality = 95;

@visibleForTesting
double homeStoryComposerRecordingProgress({
  required Duration elapsed,
  Duration maxDuration = storyMaxVideoDuration,
}) {
  if (maxDuration <= Duration.zero) {
    return 1;
  }
  return (elapsed.inMicroseconds / maxDuration.inMicroseconds)
      .clamp(0.0, 1.0)
      .toDouble();
}

@visibleForTesting
Duration homeStoryComposerRecordingTimeLeft({
  required Duration elapsed,
  Duration maxDuration = storyMaxVideoDuration,
}) {
  if (maxDuration <= Duration.zero || elapsed >= maxDuration) {
    return Duration.zero;
  }
  return maxDuration - elapsed;
}

@visibleForTesting
bool homeStoryComposerUsesNativePhotoLibraryPicker({required bool isIOS}) =>
    isIOS;

/// Recording is available wherever the `camera` plugin has an implementation
/// this app ships: Android, iOS and — since the bundled `ffmpeg.exe` was
/// removed — Windows via `camera_windows`. macOS, Linux and web still get a
/// preview-only composer.
@visibleForTesting
bool homeStoryComposerCanRecordVideo({required bool usesNativeCameraCapture}) =>
    usesNativeCameraCapture;

/// Front/rear flipping is a mobile affordance. Desktop machines expose their
/// cameras as an unordered list with no lens-direction meaning, so Windows
/// gets the input selector instead.
@visibleForTesting
bool homeStoryComposerShouldShowCameraFlip({
  required bool usesMobileCameraCapture,
}) => usesMobileCameraCapture;

/// Windows shows a camera picker rather than a flip button: `availableCameras`
/// commonly returns several capture devices and none of them is "front".
@visibleForTesting
bool homeStoryComposerShouldShowCameraInputSelector({
  required bool usesNativeCameraCapture,
  required bool usesMobileCameraCapture,
}) => usesNativeCameraCapture && !usesMobileCameraCapture;

@visibleForTesting
bool homeStoryComposerShouldOpenVideoEditor({
  required int sizeBytes,
  required Duration duration,
}) {
  if (duration <= Duration.zero) {
    return false;
  }
  return sizeBytes > 0;
}

@visibleForTesting
bool homeStoryComposerHasNativeRecordingWorkInFlight({
  required bool recordingVideo,
  required bool recordingStarting,
  required bool stoppingVideoRecording,
}) => recordingVideo || recordingStarting || stoppingVideoRecording;

@visibleForTesting
bool homeStoryComposerShouldCancelRecordingBeforeCameraRelease({
  required bool recordingVideo,
  required bool recordingStarting,
  required bool stoppingVideoRecording,
}) => homeStoryComposerHasNativeRecordingWorkInFlight(
  recordingVideo: recordingVideo,
  recordingStarting: recordingStarting,
  stoppingVideoRecording: stoppingVideoRecording,
);

@visibleForTesting
enum HomeStoryComposerDraftStatus { preparing, sharing, sent, failed }

@visibleForTesting
HomeStoryComposerDraftStatus? homeStoryComposerDraftStatus({
  required bool preparingDrafts,
  required bool uploading,
  required bool sent,
  required bool failed,
}) {
  if (failed) {
    return HomeStoryComposerDraftStatus.failed;
  }
  if (sent) {
    return HomeStoryComposerDraftStatus.sent;
  }
  if (uploading) {
    return HomeStoryComposerDraftStatus.sharing;
  }
  if (preparingDrafts) {
    return HomeStoryComposerDraftStatus.preparing;
  }
  return null;
}

@visibleForTesting
class HomeStoryComposerMediaServices {
  const HomeStoryComposerMediaServices({
    this.videoProbe = const StoryVideoProbe(),
  });

  final StoryVideoProbe videoProbe;
}

@visibleForTesting
native_camera.CameraDescription homeStoryComposerSelectNativeCamera(
  List<native_camera.CameraDescription> devices, {
  required bool preferFront,
  String? preferredName,
}) {
  if (devices.isEmpty) {
    throw StateError('No native cameras available');
  }
  // An explicit pick wins over lens-direction scoring. Desktop cameras report
  // no meaningful lens direction, so the name the user chose in the input
  // selector is the only signal that identifies the device they meant.
  if (preferredName != null && preferredName.trim().isNotEmpty) {
    final wanted = preferredName.trim();
    for (final device in devices) {
      if (device.name == wanted) {
        return device;
      }
    }
  }
  final preferredDirection = preferFront
      ? native_camera.CameraLensDirection.front
      : native_camera.CameraLensDirection.back;
  final matchingDevices = devices
      .where((device) => device.lensDirection == preferredDirection)
      .toList(growable: false);
  if (matchingDevices.isEmpty) {
    return devices.first;
  }
  if (preferFront) {
    return matchingDevices.first;
  }
  var best = matchingDevices.first;
  var bestScore = homeStoryComposerNativeBackCameraScore(best);
  for (final device in matchingDevices.skip(1)) {
    final score = homeStoryComposerNativeBackCameraScore(device);
    if (score < bestScore) {
      best = device;
      bestScore = score;
    }
  }
  return best;
}

@visibleForTesting
int homeStoryComposerNativeBackCameraScore(
  native_camera.CameraDescription device,
) {
  final name = device.name.toLowerCase();
  var score = 100;
  final numericId = int.tryParse(name);
  if (numericId != null) {
    score += numericId;
  }
  if (name == '0') {
    score -= 50;
  }
  if (name.contains('main')) {
    score -= 20;
  }
  if (name.contains('wide') && !name.contains('ultra')) {
    score -= 10;
  }
  if (name.contains('back') || name.contains('rear')) {
    score -= 5;
  }
  if (name.contains('ultra') ||
      name.contains('tele') ||
      name.contains('macro') ||
      name.contains('depth')) {
    score += 30;
  }
  return score;
}

class HomeStoryComposer {
  static Future<void> show(
    BuildContext context, {
    required Client client,
    @visibleForTesting
    HomeStoryComposerMediaServices mediaServices =
        const HomeStoryComposerMediaServices(),
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.short,
        ),
        reverseTransitionDuration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.short,
        ),
        pageBuilder: (context, _, __) => _HomeStoryComposerSheet(
          client: client,
          mediaServices: mediaServices,
        ),
        transitionsBuilder: (context, animation, _, child) {
          if (InterGalacticMotion.shouldReduce(context)) {
            return child;
          }
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: InterGalacticMotion.standardOut,
              reverseCurve: InterGalacticMotion.standardIn,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _HomeStoryComposerSheet extends StatefulWidget {
  const _HomeStoryComposerSheet({
    required this.client,
    required this.mediaServices,
  });

  final Client client;
  final HomeStoryComposerMediaServices mediaServices;

  @override
  State<_HomeStoryComposerSheet> createState() =>
      _HomeStoryComposerSheetState();
}

class _HomeStoryComposerSheetState extends State<_HomeStoryComposerSheet>
    with WidgetsBindingObserver {
  // Constraints for the WebRTC preview path, which is what macOS, Linux and
  // web still use. Windows left this path when it moved to `camera_windows`.
  static const int _previewCameraIdealWidth = 1280;
  static const int _previewCameraIdealHeight = 720;
  static const int _previewCameraFrameRate = 30;

  final StoryImageRenderer _renderer = const StoryImageRenderer();
  final ImagePicker _imagePicker = ImagePicker();
  final List<StoryDraft> _drafts = [];
  final List<StoryVideoDraft> _videoDrafts = [];
  final Set<String> _deletingStoryIds = {};
  final Set<String> _mentionedUserIds = {};
  StreamSubscription<void>? _storiesSubscription;
  webrtc.MediaStream? _cameraStream;
  webrtc.RTCVideoRenderer? _cameraRenderer;
  native_camera.CameraController? _nativeCameraController;
  Future<void>? _pendingNativeCameraDisposal;
  Timer? _recordingTimer;
  List<webrtc.MediaDeviceInfo> _cameraDevices = const [];
  String? _selectedCameraDeviceId;
  bool _usingFrontCamera = PlatformUtils.isAndroid || PlatformUtils.isIOS;
  bool _cameraStarting = false;
  List<native_camera.CameraDescription>? _nativeCameraDevicesCache;
  // Windows has no lens direction to flip between, so the chosen capture
  // device is tracked by name instead. Null means "whatever the selector
  // resolves to", which is the first available camera.
  String? _selectedNativeCameraName;
  int _cameraRequestGeneration = 0;
  String? _cameraError;
  bool _recordingVideo = false;
  bool _recordingStarting = false;
  bool _stoppingVideoRecording = false;
  bool _recordingHoldActive = false;
  Future<XFile?>? _nativeStopFuture;
  DateTime? _recordingStartedAt;
  double _recordingProgress = 0;
  bool _uploading = false;
  bool _preparingDrafts = false;
  String? _error;

  StoryVideoProbe get _videoProbe => widget.mediaServices.videoProbe;

  String get homeStoryComposerTitle => Intl.message(
    'Your Story',
    name: 'homeStoryComposerTitle',
    desc: 'Title for the Home story composer sheet',
  );

  String get homeStoryComposerAddPhotos => Intl.message(
    'Album',
    name: 'homeStoryComposerAddPhotos',
    desc: 'Button text for selecting story photos',
  );

  String get homeStoryComposerAddVideos => Intl.message(
    'Video',
    name: 'homeStoryComposerAddVideos',
    desc: 'Button text for selecting story videos',
  );

  String get homeStoryComposerShare => Intl.message(
    'Share',
    name: 'homeStoryComposerShare',
    desc: 'Button text for sharing selected story photos',
  );

  String get homeStoryComposerMention => Intl.message(
    'Mention',
    name: 'homeStoryComposerMention',
    desc: 'Button text for selecting story mentions',
  );

  String get homeStoryComposerMentions => Intl.message(
    'Mentions',
    name: 'homeStoryComposerMentions',
    desc: 'Section label for selected story mentions',
  );

  String get homeStoryComposerDone => Intl.message(
    'Done',
    name: 'homeStoryComposerDone',
    desc: 'Button text for confirming story mention selection',
  );

  String get homeStoryComposerNoMentionContacts => Intl.message(
    'No DM contacts available.',
    name: 'homeStoryComposerNoMentionContacts',
    desc: 'Message shown when story mentions have no selectable contacts',
  );

  String get homeStoryComposerCurrentStories => Intl.message(
    'Current',
    name: 'homeStoryComposerCurrentStories',
    desc: 'Section label for active own stories in the story composer',
  );

  String get homeStoryComposerNoCurrentStories => Intl.message(
    'No active stories yet.',
    name: 'homeStoryComposerNoCurrentStories',
    desc: 'Message shown when the current stories panel is empty',
  );

  String get homeStoryComposerEditDraft => Intl.message(
    'Edit story photo',
    name: 'homeStoryComposerEditDraft',
    desc: 'Tooltip for editing a selected story draft',
  );

  String get homeStoryComposerRemoveDraft => Intl.message(
    'Remove story photo',
    name: 'homeStoryComposerRemoveDraft',
    desc: 'Tooltip for removing a selected story draft',
  );

  String get homeStoryComposerEditVideoDraft => Intl.message(
    'Edit story video',
    name: 'homeStoryComposerEditVideoDraft',
    desc: 'Tooltip for editing a selected story video draft',
  );

  String get homeStoryComposerRemoveVideoDraft => Intl.message(
    'Remove story video',
    name: 'homeStoryComposerRemoveVideoDraft',
    desc: 'Tooltip for removing a selected story video draft',
  );

  String get homeStoryComposerSaveDraft => Intl.message(
    'Save story',
    name: 'homeStoryComposerSaveDraft',
    desc: 'Tooltip for saving a selected story draft before sharing',
  );

  String get homeStoryComposerSaveDraftSuccess => Intl.message(
    'Story saved.',
    name: 'homeStoryComposerSaveDraftSuccess',
    desc: 'Confirmation shown after a story draft is saved locally',
  );

  String get homeStoryComposerSaveDraftError => Intl.message(
    'Story could not be saved.',
    name: 'homeStoryComposerSaveDraftError',
    desc: 'Error shown when a story draft cannot be saved locally',
  );

  String get homeStoryComposerDeleteStory => Intl.message(
    'Delete story',
    name: 'homeStoryComposerDeleteStory',
    desc: 'Tooltip for deleting an active own story from the composer',
  );

  String get homeStoryComposerNoContacts => Intl.message(
    'No DM contacts available.',
    name: 'homeStoryComposerNoContacts',
    desc: 'Message shown when stories cannot be sent to any DM contacts',
  );

  String get homeStoryComposerPickError => Intl.message(
    'Could not add those photos.',
    name: 'homeStoryComposerPickError',
    desc: 'Error shown when story photo selection fails',
  );

  String get homeStoryComposerImageTooLargeError => Intl.message(
    'Story photos must be 50 MB or smaller.',
    name: 'homeStoryComposerImageTooLargeError',
    desc: 'Error shown when selected story photos exceed the size limit',
  );

  String get homeStoryComposerVideoTooLargeError => Intl.message(
    'Story videos must be 100 MB or smaller.',
    name: 'homeStoryComposerVideoTooLargeError',
    desc: 'Error shown when selected story videos exceed the size limit',
  );

  String get homeStoryComposerVideoPickError => Intl.message(
    'Could not add that video.',
    name: 'homeStoryComposerVideoPickError',
    desc: 'Error shown when story video selection fails',
  );

  String get homeStoryComposerVideoTrimUnavailable => Intl.message(
    'Open the video editor and use Done to prepare the selected segment before sharing.',
    name: 'homeStoryComposerVideoTrimUnavailable',
    desc:
        'Error shown when a story video selection has not been prepared for upload',
  );

  String get homeStoryComposerRecordingUnavailable => Intl.message(
    'Story video recording is not available for this camera or build. Use a video from your library.',
    name: 'homeStoryComposerRecordingUnavailable',
    desc: 'Error shown when story video recording is unavailable',
  );

  String get homeStoryComposerRecordVideo => Intl.message(
    'Record video',
    name: 'homeStoryComposerRecordVideo',
    desc: 'Tooltip for starting a story video recording',
  );

  String get homeStoryComposerStopRecording => Intl.message(
    'Stop recording',
    name: 'homeStoryComposerStopRecording',
    desc: 'Tooltip for stopping a story video recording',
  );

  String get homeStoryComposerRecordingFailed => Intl.message(
    'That video could not be recorded. Try again or choose a video from your library.',
    name: 'homeStoryComposerRecordingFailed',
    desc: 'Error shown when story video recording fails',
  );

  String get homeStoryComposerRecordedVideoTooLong => Intl.message(
    'That recording ran over 30 seconds and was not added. Try recording again.',
    name: 'homeStoryComposerRecordedVideoTooLong',
    desc: 'Error shown when a recorded story video exceeds the duration cap',
  );

  String homeStoryComposerRecordingTimeLeftLabel(String time) => Intl.message(
    '$time left',
    name: 'homeStoryComposerRecordingTimeLeftLabel',
    args: [time],
    desc: 'Short label for remaining story video recording time',
  );

  String get homeStoryComposerUploadError => Intl.message(
    'Story photos could not be shared.',
    name: 'homeStoryComposerUploadError',
    desc: 'Error shown when story upload fails',
  );

  String get homeStoryComposerUploadRetry => Intl.message(
    'Retry',
    name: 'homeStoryComposerUploadRetry',
    desc: 'Button label for retrying a failed story upload',
  );

  String get homeStoryComposerDraftPreparing => Intl.message(
    'Preparing',
    name: 'homeStoryComposerDraftPreparing',
    desc: 'Status label shown while selected story drafts are prepared',
  );

  String get homeStoryComposerDraftSharing => Intl.message(
    'Sharing',
    name: 'homeStoryComposerDraftSharing',
    desc: 'Status label shown while story drafts are being shared',
  );

  String get homeStoryComposerDraftSent => Intl.message(
    'Sent',
    name: 'homeStoryComposerDraftSent',
    desc: 'Status label shown after story drafts are shared',
  );

  String get homeStoryComposerDraftFailed => Intl.message(
    'Failed',
    name: 'homeStoryComposerDraftFailed',
    desc: 'Status label shown after story drafts fail to share',
  );

  String get homeStoryComposerUploadSent => Intl.message(
    'Story shared.',
    name: 'homeStoryComposerUploadSent',
    desc: 'Snackbar shown when queued story uploads are sent successfully',
  );

  String get homeStoryComposerUploadPrepareFailed => Intl.message(
    'Story could not be prepared. Try again.',
    name: 'homeStoryComposerUploadPrepareFailed',
    desc: 'Snackbar shown when a queued story upload cannot be rendered',
  );

  String get homeStoryComposerUploadFailed => Intl.message(
    'Story upload failed. Try again.',
    name: 'homeStoryComposerUploadFailed',
    desc: 'Snackbar shown when a queued story upload fails before sending',
  );

  String homeStoryComposerUploadSentNone(
    int storyCount,
    int failedEventCount,
  ) => Intl.message(
    'No story shares were sent. $failedEventCount failed.',
    name: 'homeStoryComposerUploadSentNone',
    args: [storyCount, failedEventCount],
    // Strings, not ints: flutter gen-l10n builds a synthetic localizations
    // package from this ARB and rejects a placeholder whose example is not a
    // non-empty STRING. The extractor copies the literal through unchanged, so
    // an int here fails the build rather than this file.
    examples: const {'storyCount': '2', 'failedEventCount': '2'},
    desc:
        'Snackbar shown when queued story uploads finish without sending any story events',
  );

  String homeStoryComposerUploadPartiallyFailed(
    int sentEventCount,
    int failedEventCount,
  ) => Intl.message(
    'Some story shares failed. $sentEventCount sent, $failedEventCount failed.',
    name: 'homeStoryComposerUploadPartiallyFailed',
    args: [sentEventCount, failedEventCount],
    examples: const {'sentEventCount': '3', 'failedEventCount': '1'},
    desc: 'Snackbar shown when queued story uploads partially fail',
  );

  String get homeStoryComposerRenderError => Intl.message(
    'Story edits could not be applied.',
    name: 'homeStoryComposerRenderError',
    desc: 'Error shown when selected story drafts cannot be rendered',
  );

  String get homeStoryComposerDeleteError => Intl.message(
    'Story could not be deleted.',
    name: 'homeStoryComposerDeleteError',
    desc: 'Error shown when an active story delete fails',
  );

  String get homeStoryComposerCameraStarting => Intl.message(
    'Opening camera...',
    name: 'homeStoryComposerCameraStarting',
    desc: 'Status shown while the story camera preview opens',
  );

  String get homeStoryComposerCameraError => Intl.message(
    'Camera is not available.',
    name: 'homeStoryComposerCameraError',
    desc: 'Error shown when the story camera preview cannot open',
  );

  String get homeStoryComposerCaptureError => Intl.message(
    'Could not capture that photo.',
    name: 'homeStoryComposerCaptureError',
    desc: 'Error shown when a story camera capture fails',
  );

  String get homeStoryComposerTakePhoto => Intl.message(
    'Take photo',
    name: 'homeStoryComposerTakePhoto',
    desc: 'Tooltip for the story camera capture button',
  );

  String get homeStoryComposerSwitchCamera => Intl.message(
    'Switch camera',
    name: 'homeStoryComposerSwitchCamera',
    desc: 'Tooltip for switching story camera devices',
  );

  String get homeStoryComposerCameraInput => Intl.message(
    'Camera input',
    name: 'homeStoryComposerCameraInput',
    desc: 'Label for selecting a desktop story recording camera input',
  );

  String get homeStoryComposerFrontCameraSelected => Intl.message(
    'Front camera',
    name: 'homeStoryComposerFrontCameraSelected',
    desc:
        'Status shown when native mobile story capture prefers the front camera',
  );

  String get homeStoryComposerRearCameraSelected => Intl.message(
    'Rear camera',
    name: 'homeStoryComposerRearCameraSelected',
    desc:
        'Status shown when native mobile story capture prefers the rear camera',
  );

  String get homeStoryComposerTextStory => Intl.message(
    'Text story',
    name: 'homeStoryComposerTextStory',
    desc: 'Tooltip for creating a text-only story draft',
  );

  StoryComponent? get _storyComponent =>
      widget.client.getComponent<StoryComponent>();

  List<StoryItem> get _ownStories {
    final userId = widget.client.self?.identifier;
    if (userId == null) {
      return const [];
    }
    return _storyComponent?.activeStoriesForUser(userId) ?? const [];
  }

  List<_StoryMentionContact> get _mentionContacts {
    final component = widget.client.getComponent<DirectMessagesComponent>();
    final rooms = component?.directMessageRooms ?? const <Room>[];
    final ownUserId = widget.client.self?.identifier;
    final contacts = <String, _StoryMentionContact>{};
    for (final room in rooms) {
      final userId = component?.getDirectMessagePartnerId(room);
      if (userId == null || userId == ownUserId) {
        continue;
      }
      final member = room.getMemberOrFallback(userId);
      contacts.putIfAbsent(
        userId,
        () => _StoryMentionContact(
          userId: userId,
          displayName: member.displayName,
          avatar: member.avatar,
        ),
      );
    }
    final list = contacts.values.toList(growable: false);
    list.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return list;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storiesSubscription = _storyComponent?.onStoriesChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    unawaited(_storyComponent?.refreshStories());
    if (_usesNativeCameraCapture) {
      unawaited(
        _startNativeCameraPreviewForComposerOpen(
          preferFront: _shouldPreferFrontCamera,
        ),
      );
    } else {
      unawaited(_startCamera(preferFront: _shouldPreferFrontCamera));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storiesSubscription?.cancel();
    final shouldCancelRecording =
        homeStoryComposerShouldCancelRecordingBeforeCameraRelease(
          recordingVideo: _recordingVideo,
          recordingStarting: _recordingStarting,
          stoppingVideoRecording: _stoppingVideoRecording,
        );
    _cancelRecordingTimer();
    if (shouldCancelRecording) {
      unawaited(
        _cancelVideoRecording(notify: false).whenComplete(_disposeCamera),
      );
    } else {
      _disposeCamera();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_usesNativeCameraCapture) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        if (_nativeCameraController == null) {
          unawaited(
            _startNativeCameraPreviewForComposerOpen(
              preferFront: _usingFrontCamera,
            ),
          );
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (homeStoryComposerShouldCancelRecordingBeforeCameraRelease(
          recordingVideo: _recordingVideo,
          recordingStarting: _recordingStarting,
          stoppingVideoRecording: _stoppingVideoRecording,
        )) {
          unawaited(_cancelVideoRecording().whenComplete(_disposeNativeCamera));
        } else {
          _disposeNativeCamera();
        }
        break;
    }
  }

  bool get _shouldPreferFrontCamera => _usesMobileCameraCapture;

  /// Android and iOS. These are the platforms with a front/rear lens pair and
  /// a device orientation, so the affordances keyed on this getter are the
  /// ones that only make sense on a handset.
  bool get _usesMobileCameraCapture =>
      PlatformUtils.isAndroid || PlatformUtils.isIOS;

  /// Every platform whose capture runs through the `camera` plugin. Windows
  /// joined this set when the bundled `ffmpeg.exe` DirectShow recorder was
  /// removed in favour of `camera_windows`; macOS, Linux and web are still
  /// preview-only over WebRTC.
  bool get _usesNativeCameraCapture =>
      _usesMobileCameraCapture || PlatformUtils.isWindows;

  StoryVideoCanvasMode _captureCanvasModeFor(BuildContext context) {
    // Mobile only: desktop windows are usually landscape-shaped, but desktop
    // capture always composes onto the portrait canvas.
    if (_usesMobileCameraCapture &&
        MediaQuery.orientationOf(context) == Orientation.landscape) {
      return StoryVideoCanvasMode.landscape;
    }

    return StoryVideoCanvasMode.portrait;
  }

  bool get _canRecordVideo => homeStoryComposerCanRecordVideo(
    usesNativeCameraCapture: _usesNativeCameraCapture,
  );

  bool get _busy =>
      _uploading ||
      _preparingDrafts ||
      _recordingStarting ||
      _stoppingVideoRecording;

  bool get _controlsLocked => _busy || _cameraStarting || _recordingVideo;

  bool get _hasDrafts => _drafts.isNotEmpty || _videoDrafts.isNotEmpty;

  HomeStoryComposerDraftStatus? get _draftStatus =>
      homeStoryComposerDraftStatus(
        preparingDrafts: _preparingDrafts,
        uploading: _uploading,
        sent: false,
        failed: _error != null,
      );

  Duration get _recordingElapsed {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) {
      return Duration.zero;
    }
    final elapsed = DateTime.now().difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration get _recordingRemaining =>
      homeStoryComposerRecordingTimeLeft(elapsed: _recordingElapsed);

  Future<void> _allowBusyIndicatorToPaint() {
    return WidgetsBinding.instance.endOfFrame;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draftStatus = _draftStatus;
    final activeDraftStatus =
        draftStatus == HomeStoryComposerDraftStatus.preparing ||
            draftStatus == HomeStoryComposerDraftStatus.sharing
        ? draftStatus
        : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildCameraStage(context)),
            Positioned(
              left: 12,
              top: 8,
              right: 12,
              child: _buildTopBar(context),
            ),
            if (_hasDrafts)
              Positioned(
                left: 12,
                top: 62,
                right: 12,
                child: _buildDraftReviewBar(context),
              ),
            Positioned(left: 16, bottom: 22, child: _buildLeftRail(context)),
            Positioned(right: 16, bottom: 22, child: _buildRightRail(context)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: _StoryCaptureButton(
                  tooltip: _recordingVideo
                      ? homeStoryComposerStopRecording
                      : homeStoryComposerTakePhoto,
                  busy: _busy || _cameraStarting,
                  recording: _recordingVideo,
                  recordingProgress: _recordingProgress,
                  onPressed: _busy || _cameraStarting
                      ? null
                      : _recordingVideo
                      ? () => unawaited(_stopVideoRecording())
                      : _capturePhoto,
                  onLongPressStart: _usesMobileCameraCapture && !_controlsLocked
                      ? (_) => unawaited(
                          _startNativeVideoRecording(holdToRecord: true),
                        )
                      : null,
                  onLongPressEnd: _usesMobileCameraCapture
                      ? (_) => _finishHoldRecording()
                      : null,
                  onLongPressCancel: _usesMobileCameraCapture
                      ? _finishHoldRecording
                      : null,
                ),
              ),
            ),
            if (_recordingVideo || _stoppingVideoRecording)
              Positioned(
                left: 0,
                right: 0,
                bottom: 108,
                child: Center(
                  child: _StoryRecordingPill(
                    label: homeStoryComposerRecordingTimeLeftLabel(
                      storyVideoDurationLabel(_recordingRemaining),
                    ),
                  ),
                ),
              ),
            if (activeDraftStatus != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 108,
                child: Center(
                  child: _StoryDraftStatusPill(
                    icon: _draftStatusIcon(activeDraftStatus),
                    label: _draftStatusLabel(activeDraftStatus),
                  ),
                ),
              ),
            if (_error != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 118,
                child: _buildErrorBanner(context, _error!, scheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraStage(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasMode = _captureCanvasModeFor(context);
        final size = storyVideoCanvasSizeForConstraints(
          constraints: constraints,
          canvasMode: canvasMode,
          maxDesktopWidth: Layout.desktop ? 620.0 : null,
        );
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRect(child: _buildCameraPreview(context, canvasMode)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraPreview(
    BuildContext context,
    StoryVideoCanvasMode canvasMode,
  ) {
    if (_usesNativeCameraCapture) {
      final controller = _nativeCameraController;
      if (controller != null && controller.value.isInitialized) {
        return _buildNativeCameraPreview(controller);
      }
      // Front/rear is a mobile distinction. A Windows webcam reports no lens
      // direction, so naming it "Rear camera" would be a confident wrong
      // label; it gets the neutral one.
      // Nothing is starting in the idle case, so the non-mobile branch gets no
      // label rather than "Opening camera...". It reached that state after a
      // preview attempt was abandoned by the generation check, and claiming
      // progress that had already been given up on is worse than saying
      // nothing; `_cameraStarting` below still labels a real start.
      final String? idleLabel = _usesMobileCameraCapture
          ? (_usingFrontCamera
                ? homeStoryComposerFrontCameraSelected
                : homeStoryComposerRearCameraSelected)
          : null;
      return _buildCameraPlaceholder(
        context,
        label:
            _cameraError ??
            (_cameraStarting ? homeStoryComposerCameraStarting : idleLabel),
      );
    }
    final renderer = _cameraRenderer;
    if (renderer != null) {
      return webrtc.RTCVideoView(
        renderer,
        mirror: _usingFrontCamera,
        objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        placeholderBuilder: (_) => _buildCameraPlaceholder(context),
      );
    }
    return _buildCameraPlaceholder(context);
  }

  Widget _buildNativeCameraPreview(native_camera.CameraController controller) {
    return ValueListenableBuilder<native_camera.CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final previewSize = value.previewSize;
        if (!value.isInitialized || previewSize == null) {
          return _buildCameraPlaceholder(context);
        }
        // previewSize is landscape-normalized on both platforms, and
        // CameraPreview sizes itself from the same "applicable orientation"
        // it uses internally (recording orientation while recording, else
        // paused/locked/device orientation). Pairing this box with anything
        // else - the old code paired it with the canvas mode - stretches
        // frames whenever the two disagree, e.g. mid-rotation on iOS or for
        // the whole of a landscape recording.
        final orientation = value.isRecordingVideo
            ? value.recordingOrientation ?? value.deviceOrientation
            : value.previewPauseOrientation ??
                  value.lockedCaptureOrientation ??
                  value.deviceOrientation;
        final isLandscape =
            orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: isLandscape ? previewSize.width : previewSize.height,
            height: isLandscape ? previewSize.height : previewSize.width,
            child: native_camera.CameraPreview(controller),
          ),
        );
      },
    );
  }

  Widget _buildCameraPlaceholder(BuildContext context, {String? label}) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveLabel =
        label ??
        _cameraError ??
        (_cameraStarting ? homeStoryComposerCameraStarting : null);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              color: Colors.white.withValues(alpha: 0.76),
              size: 42,
            ),
            if (effectiveLabel != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  effectiveLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _cameraError == null
                        ? Colors.white.withValues(alpha: 0.82)
                        : scheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        _StoryCameraToolButton(
          tooltip: MaterialLocalizations.of(context).closeButtonLabel,
          icon: Icons.close,
          onPressed: _busy || _recordingVideo
              ? null
              : () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.54),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              homeStoryComposerTitle,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDraftReviewBar(BuildContext context) {
    final thumbnailDpr = MediaQuery.devicePixelRatioOf(context);
    final thumbnailCacheWidth = (homeStoryDraftReviewFrameWidth * thumbnailDpr)
        .round();
    final thumbnailCacheHeight = (homeStoryDraftReviewTileHeight * thumbnailDpr)
        .round();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Layout.desktop ? 620.0 : 560.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: homeStoryDraftReviewTileHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _drafts.length + _videoDrafts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        if (index < _drafts.length) {
                          return _StoryDraftTile(
                            draft: _drafts[index],
                            editTooltip: homeStoryComposerEditDraft,
                            removeTooltip: homeStoryComposerRemoveDraft,
                            saveTooltip: homeStoryComposerSaveDraft,
                            thumbnailCacheWidth: thumbnailCacheWidth,
                            thumbnailCacheHeight: thumbnailCacheHeight,
                            onEdit: _controlsLocked
                                ? null
                                : () => _editDraft(index),
                            onSave: _controlsLocked
                                ? null
                                : () => _saveDraft(index),
                            onRemove: _controlsLocked
                                ? null
                                : () => _removeDraft(index),
                          );
                        }
                        final videoIndex = index - _drafts.length;
                        return _StoryVideoDraftTile(
                          draft: _videoDrafts[videoIndex],
                          editTooltip: homeStoryComposerEditVideoDraft,
                          removeTooltip: homeStoryComposerRemoveVideoDraft,
                          thumbnailCacheWidth: thumbnailCacheWidth,
                          thumbnailCacheHeight: thumbnailCacheHeight,
                          onEdit: _controlsLocked
                              ? null
                              : () => _editVideoDraft(videoIndex),
                          onRemove: _controlsLocked
                              ? null
                              : () => _removeVideoDraft(videoIndex),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildShareDraftButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareDraftButton(BuildContext context) {
    final status = _draftStatus;
    final activeStatus =
        status == HomeStoryComposerDraftStatus.preparing ||
            status == HomeStoryComposerDraftStatus.sharing
        ? status
        : null;
    final duration = InterGalacticMotion.duration(
      context,
      InterGalacticMotion.short,
    );
    final label = activeStatus == null
        ? homeStoryComposerShare
        : _draftStatusLabel(activeStatus);
    final icon = activeStatus == null
        ? const Icon(
            Icons.send_outlined,
            key: ValueKey('story-draft-share-icon'),
          )
        : const SizedBox(
            key: ValueKey('story-draft-busy-icon'),
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          );

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132),
      child: FilledButton.icon(
        onPressed: _controlsLocked ? null : _shareStories,
        icon: AnimatedSwitcher(duration: duration, child: icon),
        label: AnimatedSwitcher(
          duration: duration,
          child: Text(label, key: ValueKey(label)),
        ),
      ),
    );
  }

  Widget _buildLeftRail(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StoryCameraToolButton(
          tooltip: homeStoryComposerCurrentStories,
          icon: Icons.collections_bookmark_outlined,
          onPressed: _controlsLocked ? null : _showCurrentStories,
        ),
        const SizedBox(height: 12),
        _StoryCameraToolButton(
          tooltip: homeStoryComposerMention,
          icon: Icons.add,
          badge: _mentionedUserIds.isEmpty
              ? null
              : _mentionedUserIds.length.toString(),
          onPressed: _controlsLocked ? null : _chooseMentions,
        ),
        const SizedBox(height: 12),
        _StoryCameraToolButton(
          tooltip: homeStoryComposerAddPhotos,
          icon: Icons.photo_library_outlined,
          onPressed: _controlsLocked ? null : _pickPhotos,
        ),
        const SizedBox(height: 12),
        _StoryCameraToolButton(
          tooltip: homeStoryComposerAddVideos,
          icon: Icons.video_library_outlined,
          onPressed: _controlsLocked ? null : _pickVideos,
        ),
      ],
    );
  }

  Widget _buildRightRail(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StoryCameraToolButton(
          tooltip: homeStoryComposerTextStory,
          icon: Icons.text_fields,
          onPressed: _controlsLocked ? null : _createTextStory,
        ),
        const SizedBox(height: 12),
        _StoryCameraToolButton(
          tooltip: _recordingVideo
              ? homeStoryComposerStopRecording
              : _canRecordVideo
              ? homeStoryComposerRecordVideo
              : homeStoryComposerRecordingUnavailable,
          icon: _recordingVideo ? Icons.stop : Icons.videocam_outlined,
          onPressed: _busy || _cameraStarting
              ? null
              : _recordingVideo
              ? () => unawaited(_stopVideoRecording())
              : _startVideoRecording,
        ),
        if (homeStoryComposerShouldShowCameraFlip(
          usesMobileCameraCapture: _usesMobileCameraCapture,
        )) ...[
          const SizedBox(height: 12),
          _StoryCameraToolButton(
            tooltip: homeStoryComposerSwitchCamera,
            icon: Icons.flip_camera_ios_outlined,
            onPressed: _controlsLocked ? null : _switchCamera,
          ),
        ] else if (homeStoryComposerShouldShowCameraInputSelector(
          usesNativeCameraCapture: _usesNativeCameraCapture,
          usesMobileCameraCapture: _usesMobileCameraCapture,
        )) ...[
          const SizedBox(height: 12),
          _buildNativeCameraInputSelector(context),
        ],
      ],
    );
  }

  Widget _buildNativeCameraInputSelector(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = _nativeCameraDevicesCache ?? const [];
    if (devices.isEmpty) {
      return _StoryCameraToolButton(
        tooltip: homeStoryComposerCameraInput,
        icon: _cameraStarting
            ? Icons.more_horiz
            : Icons.video_camera_front_outlined,
        onPressed: _controlsLocked
            ? null
            : () => unawaited(_refreshNativeCameraInputs()),
      );
    }

    final selectedLabel = _selectedNativeCameraNameFor(devices);
    return tiamat.Tooltip(
      text: homeStoryComposerCameraInput,
      child: SizedBox(
        width: 210,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.54),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedLabel,
                isExpanded: true,
                dropdownColor: scheme.surface,
                iconEnabledColor: Colors.white.withValues(alpha: 0.84),
                iconDisabledColor: Colors.white.withValues(alpha: 0.32),
                selectedItemBuilder: (context) => [
                  for (final device in devices)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
                items: [
                  for (final device in devices)
                    DropdownMenuItem<String>(
                      value: device.name,
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _controlsLocked
                    ? null
                    : (name) {
                        if (name == null) {
                          return;
                        }
                        unawaited(_selectNativeCameraInput(name));
                      },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message, Color accent) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Layout.desktop ? 520.0 : 560.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _draftStatusLabel(HomeStoryComposerDraftStatus status) {
    return switch (status) {
      HomeStoryComposerDraftStatus.preparing => homeStoryComposerDraftPreparing,
      HomeStoryComposerDraftStatus.sharing => homeStoryComposerDraftSharing,
      HomeStoryComposerDraftStatus.sent => homeStoryComposerDraftSent,
      HomeStoryComposerDraftStatus.failed => homeStoryComposerDraftFailed,
    };
  }

  IconData _draftStatusIcon(HomeStoryComposerDraftStatus status) {
    return switch (status) {
      HomeStoryComposerDraftStatus.preparing => Icons.hourglass_empty,
      HomeStoryComposerDraftStatus.sharing => Icons.cloud_upload_outlined,
      HomeStoryComposerDraftStatus.sent => Icons.check_circle_outline,
      HomeStoryComposerDraftStatus.failed => Icons.error_outline,
    };
  }

  Future<void> _startCamera({
    String? deviceId,
    bool? preferFront,
    bool preserveError = false,
  }) async {
    if (_usesNativeCameraCapture) {
      return;
    }
    final requestGeneration = ++_cameraRequestGeneration;
    final previousStream = _cameraStream;
    final previousRenderer = _cameraRenderer;
    final hasPreviousPreview =
        previousStream != null && previousRenderer != null;
    if (mounted) {
      setState(() {
        if (!hasPreviousPreview) {
          _cameraStream = null;
          _cameraRenderer = null;
        }
        _cameraStarting = true;
        _cameraError = null;
        if (!preserveError) {
          _error = null;
        }
      });
    } else {
      _cameraStream = null;
      _cameraRenderer = null;
    }

    webrtc.MediaStream? stream;
    webrtc.RTCVideoRenderer? renderer;
    try {
      stream = await webrtc.navigator.mediaDevices
          .getUserMedia(<String, dynamic>{
            'audio': false,
            'video': _cameraConstraints(
              deviceId: deviceId,
              preferFront: preferFront,
            ),
          });
      renderer = webrtc.RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;

      final devices = await _availableCameraDevices();
      final track = stream.getVideoTracks().firstOrNull;
      final settings = track?.getSettings() ?? const <String, dynamic>{};
      final selectedDeviceId = deviceId ?? settings['deviceId']?.toString();
      final facingMode = settings['facingMode']?.toString().toLowerCase();
      final frontFacing = _looksFrontFacing(
        facingMode: facingMode,
        deviceId: selectedDeviceId,
        devices: devices,
        fallback: preferFront ?? _usingFrontCamera,
      );

      if (!mounted || requestGeneration != _cameraRequestGeneration) {
        await _disposeCameraResources(stream: stream, renderer: renderer);
        return;
      }
      setState(() {
        _cameraStream = stream;
        _cameraRenderer = renderer;
        _cameraDevices = devices;
        _selectedCameraDeviceId = selectedDeviceId;
        _usingFrontCamera = frontFacing;
        _cameraStarting = false;
        _cameraError = null;
        if (!preserveError) {
          _error = null;
        }
      });
      unawaited(
        _disposeCameraResources(
          stream: previousStream,
          renderer: previousRenderer,
        ),
      );
    } catch (_) {
      await _disposeCameraResources(stream: stream, renderer: renderer);
      if (!mounted || requestGeneration != _cameraRequestGeneration) {
        return;
      }
      setState(() {
        _cameraStarting = false;
        if (hasPreviousPreview) {
          _error = homeStoryComposerCameraError;
        } else {
          _cameraError = homeStoryComposerCameraError;
        }
      });
    }
  }

  Map<String, dynamic> _cameraConstraints({
    String? deviceId,
    bool? preferFront,
  }) {
    final constraints = <String, dynamic>{
      'width': {'ideal': _previewCameraIdealWidth},
      'height': {'ideal': _previewCameraIdealHeight},
      'frameRate': {
        'ideal': _previewCameraFrameRate,
        'max': _previewCameraFrameRate,
      },
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      constraints['deviceId'] = {'exact': deviceId};
    } else if (preferFront != null) {
      constraints['facingMode'] = preferFront ? 'user' : 'environment';
    }
    return constraints;
  }

  Future<List<webrtc.MediaDeviceInfo>> _availableCameraDevices() async {
    try {
      return (await webrtc.navigator.mediaDevices.enumerateDevices())
          .where((device) => device.kind == 'videoinput')
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  bool _looksFrontFacing({
    required String? facingMode,
    required String? deviceId,
    required List<webrtc.MediaDeviceInfo> devices,
    required bool fallback,
  }) {
    if (facingMode == 'user' || facingMode == 'front') {
      return true;
    }
    if (facingMode == 'environment' || facingMode == 'back') {
      return false;
    }
    final device = devices
        .where((candidate) => candidate.deviceId == deviceId)
        .firstOrNull;
    final label = device?.label.toLowerCase() ?? '';
    if (label.contains('front') || label.contains('user')) {
      return true;
    }
    if (label.contains('back') ||
        label.contains('rear') ||
        label.contains('environment')) {
      return false;
    }
    return fallback;
  }

  /// Resolves which entry of [devices] the input selector should show as
  /// current. Falls back to the first device so the dropdown always has a
  /// value present in its own item list.
  String _selectedNativeCameraNameFor(
    List<native_camera.CameraDescription> devices,
  ) {
    final desired = _selectedNativeCameraName?.trim();
    if (desired != null && desired.isNotEmpty) {
      for (final device in devices) {
        if (device.name == desired) {
          return device.name;
        }
      }
    }
    return devices.first.name;
  }

  /// Re-enumerates capture devices. Only reachable from the input selector's
  /// empty state, which is what a machine with no camera attached shows.
  Future<void> _refreshNativeCameraInputs() async {
    if (!_usesNativeCameraCapture) {
      return;
    }
    _nativeCameraDevicesCache = null;
    await _startNativeCameraPreview();
  }

  Future<void> _selectNativeCameraInput(String deviceName) async {
    final trimmed = deviceName.trim();
    if (trimmed.isEmpty || trimmed == _selectedNativeCameraName) {
      return;
    }
    if (mounted) {
      setState(() => _selectedNativeCameraName = trimmed);
    } else {
      _selectedNativeCameraName = trimmed;
    }
    await _startNativeCameraPreview();
  }

  /// Opens the composer preview, warming the session with audio on Android
  /// when the microphone permission is already granted so the first video
  /// recording starts without tearing the camera down to re-open it with
  /// audio. iOS stays audio-less until recording: attaching the audio input
  /// there interrupts other audio playback as soon as the composer opens.
  Future<void> _startNativeCameraPreviewForComposerOpen({
    bool? preferFront,
  }) async {
    var warmAudio = false;
    if (PlatformUtils.isAndroid) {
      try {
        warmAudio = await Permission.microphone.status.isGranted;
      } catch (_) {}
    }
    await _startNativeCameraPreview(
      preferFront: preferFront,
      enableAudio: warmAudio ? true : null,
    );
  }

  Future<void> _startNativeCameraPreview({
    bool? preferFront,
    bool? enableAudio,
  }) async {
    if (!_usesNativeCameraCapture) {
      return;
    }
    final pendingDisposal = _pendingNativeCameraDisposal;
    if (pendingDisposal != null) {
      await pendingDisposal;
    }
    final requestGeneration = ++_cameraRequestGeneration;
    final targetFront = preferFront ?? _usingFrontCamera;
    final previousController = _nativeCameraController;
    // Keep an audio-enabled session across camera flips so video recording
    // does not have to tear the session down and reopen it with audio.
    final targetAudio = enableAudio ?? previousController?.enableAudio ?? false;
    final hasPreviousPreview = previousController?.value.isInitialized == true;
    if (mounted) {
      setState(() {
        if (!hasPreviousPreview) {
          _nativeCameraController = null;
        }
        _cameraStarting = true;
        _cameraError = null;
        _error = null;
      });
    }

    native_camera.CameraController? controller;
    var releasedPreviousController = false;
    try {
      // Enumerating cameras hits the platform channel every time; the device
      // list is stable while the composer is open, so cache it to keep
      // front/rear switching snappy.
      final devices = _nativeCameraDevicesCache ??= await native_camera
          .availableCameras();
      if (devices.isEmpty) {
        throw StateError('No native cameras available');
      }
      final selected = homeStoryComposerSelectNativeCamera(
        devices,
        preferFront: targetFront,
        preferredName: _selectedNativeCameraName,
      );
      Log.d(
        'Story native camera opening target=${_nativeCameraFacingLabel(targetFront)} '
        'devices=${_nativeCameraInventorySummary(devices)} '
        'selected=${_nativeCameraFacingLabelForDirection(selected.lensDirection)} '
        'audio=$targetAudio',
        category: LogCategory.media,
        source: 'story-camera',
      );

      if (previousController != null) {
        // Native camera plugins generally cannot hold front and rear sessions
        // open together. Release the active session before opening the next.
        releasedPreviousController = true;
        if (!mounted || requestGeneration != _cameraRequestGeneration) {
          return;
        }
        setState(() {
          if (_nativeCameraController == previousController) {
            _nativeCameraController = null;
          }
        });
        await _trackNativeCameraDisposal(previousController);
        if (!mounted || requestGeneration != _cameraRequestGeneration) {
          return;
        }
      }

      controller = native_camera.CameraController(
        selected,
        native_camera.ResolutionPreset.high,
        enableAudio: targetAudio,
      );
      await controller.initialize();
      await _configureNativeCamera(controller);

      if (!mounted || requestGeneration != _cameraRequestGeneration) {
        await _disposeNativeCameraController(controller);
        return;
      }
      setState(() {
        _nativeCameraController = controller;
        _usingFrontCamera =
            selected.lensDirection == native_camera.CameraLensDirection.front;
        _cameraStarting = false;
        _cameraError = null;
        _error = null;
      });
      Log.d(
        'Story native camera opened facing=${_nativeCameraFacingLabel(_usingFrontCamera)}',
        category: LogCategory.media,
        source: 'story-camera',
      );
    } catch (error) {
      // Re-enumerate on the next attempt in case the failure came from a
      // stale device list.
      _nativeCameraDevicesCache = null;
      Log.w(
        'Story native camera failed target=${_nativeCameraFacingLabel(targetFront)} '
        'previousReleased=$releasedPreviousController error=$error',
        category: LogCategory.media,
        source: 'story-camera',
      );
      if (controller != null) {
        await _disposeNativeCameraController(controller);
      }
      if (!mounted || requestGeneration != _cameraRequestGeneration) {
        return;
      }
      setState(() {
        _cameraStarting = false;
        if (hasPreviousPreview && !releasedPreviousController) {
          _error = homeStoryComposerCameraError;
        } else {
          _cameraError = homeStoryComposerCameraError;
        }
      });
    }
  }

  String _nativeCameraInventorySummary(
    List<native_camera.CameraDescription> devices,
  ) {
    var front = 0;
    var back = 0;
    var external = 0;
    for (final device in devices) {
      switch (device.lensDirection) {
        case native_camera.CameraLensDirection.front:
          front++;
          break;
        case native_camera.CameraLensDirection.back:
          back++;
          break;
        case native_camera.CameraLensDirection.external:
          external++;
          break;
      }
    }
    return 'total=${devices.length} front=$front back=$back external=$external';
  }

  String _nativeCameraFacingLabel(bool front) {
    return front ? 'front' : 'rear';
  }

  String _nativeCameraFacingLabelForDirection(
    native_camera.CameraLensDirection direction,
  ) {
    switch (direction) {
      case native_camera.CameraLensDirection.front:
        return 'front';
      case native_camera.CameraLensDirection.back:
        return 'rear';
      case native_camera.CameraLensDirection.external:
        return 'external';
    }
  }

  Future<void> _configureNativeCamera(
    native_camera.CameraController controller,
  ) async {
    try {
      await controller.unlockCaptureOrientation();
    } catch (_) {
      // Some platform camera implementations do not expose capture locks.
      // Leaving capture orientation unlocked is intentional: landscape media
      // should be captured as landscape, then fit into the portrait story canvas.
    }
    try {
      await controller.setFlashMode(native_camera.FlashMode.off);
    } catch (_) {
      // Flash mode support varies by camera and platform.
    }
  }

  Future<void> _switchCamera() async {
    if (_usesMobileCameraCapture) {
      await _startNativeCameraPreview(preferFront: !_usingFrontCamera);
      return;
    }
    final devices = _cameraDevices.isNotEmpty
        ? _cameraDevices
        : await _availableCameraDevices();
    if (devices.length > 1) {
      final currentIndex = devices.indexWhere(
        (device) => device.deviceId == _selectedCameraDeviceId,
      );
      final nextIndex = currentIndex < 0
          ? 0
          : (currentIndex + 1) % devices.length;
      await _startCamera(deviceId: devices[nextIndex].deviceId);
      return;
    }
    await _startCamera(preferFront: !_usingFrontCamera);
  }

  Future<void> _capturePhoto() async {
    if (_usesNativeCameraCapture) {
      await _captureMobileNativePhoto();
      return;
    }
    final track = _cameraStream?.getVideoTracks().firstOrNull;
    if (track == null) {
      setState(() {
        _error = _cameraError ?? homeStoryComposerCameraError;
      });
      return;
    }

    setState(() {
      _preparingDrafts = true;
      _error = null;
    });
    if (!mounted) {
      return;
    }

    try {
      final frame = await track.captureFrame();
      final bytes = Uint8List.fromList(Uint8List.view(frame));
      final draft = await StoryImageRenderer.createDraft(
        sourceBytes: bytes,
        sourceName: 'story-camera-${DateTime.now().millisecondsSinceEpoch}.png',
        sourceMimeType: 'image/png',
        previewOnly: true,
      );
      await _addDraftAndEdit(draft);
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (!PlatformUtils.isWeb && !_usesNativeCameraCapture) {
        setState(() {
          _preparingDrafts = false;
          _error = homeStoryComposerCaptureError;
        });
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = null;
      });
      await _captureNativePickerPhoto();
    }
  }

  Future<void> _captureMobileNativePhoto() async {
    final controller = _nativeCameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _captureNativePickerPhoto();
      return;
    }
    if (controller.value.isTakingPicture) {
      return;
    }
    setState(() {
      _preparingDrafts = true;
      _error = null;
    });
    // Let the busy indicator paint before the platform capture call blocks
    // the channel, so the shutter press gives immediate feedback.
    await _allowBusyIndicatorToPaint();
    if (!mounted) {
      return;
    }
    try {
      final file = await controller.takePicture();
      await _processCapturedPhoto(
        length: file.length,
        readAsBytes: file.readAsBytes,
        sourceName: file.name,
        sourceMimeType: file.mimeType,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = homeStoryComposerCaptureError;
      });
    }
  }

  Future<void> _startVideoRecording({bool holdToRecord = false}) async {
    if (_usesNativeCameraCapture) {
      await _startNativeVideoRecording(holdToRecord: holdToRecord);
      return;
    }
    // macOS, Linux and web get a preview but no capture: the `camera` plugin
    // has no implementation this app ships for them.
    _showRecordingUnavailable();
  }

  Future<void> _startNativeVideoRecording({bool holdToRecord = false}) async {
    if (!_usesNativeCameraCapture) {
      _showRecordingUnavailable();
      return;
    }
    if (_recordingVideo ||
        _recordingStarting ||
        _stoppingVideoRecording ||
        _uploading ||
        _preparingDrafts ||
        _cameraStarting) {
      if (holdToRecord) {
        _recordingHoldActive = false;
      }
      return;
    }

    setState(() {
      _recordingStarting = true;
      _recordingHoldActive = holdToRecord;
      _error = null;
    });

    try {
      final controller = await _ensureNativeVideoRecordingController();
      if (controller == null || !controller.value.isInitialized) {
        throw StateError('Native story camera is not available for recording');
      }
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();
      if (!mounted || !_recordingStarting) {
        await _discardNativeVideoRecording(
          controller,
          reason: mounted
              ? 'recording_cancelled_before_start_completed'
              : 'composer_disposed_after_start',
        );
        return;
      }
      setState(() {
        _recordingStarting = false;
        _recordingVideo = true;
        _recordingStartedAt = DateTime.now();
        _recordingProgress = 0;
        _error = null;
      });
      _startRecordingTimer();
      if (holdToRecord && !_recordingHoldActive) {
        unawaited(_stopNativeVideoRecording());
      }
      Log.d(
        'Story native video recording started '
        'facing=${_nativeCameraFacingLabel(_usingFrontCamera)}',
        category: LogCategory.media,
        source: 'story-camera',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to start story video recording '
            '(${error.runtimeType}).',
        category: LogCategory.media,
        source: 'story-camera',
      );
      if (!mounted) {
        return;
      }
      _cancelRecordingTimer();
      setState(() {
        _recordingStarting = false;
        _recordingVideo = false;
        _recordingHoldActive = false;
        _recordingStartedAt = null;
        _recordingProgress = 0;
        _error = homeStoryComposerRecordingFailed;
      });
    }
  }

  Future<native_camera.CameraController?>
  _ensureNativeVideoRecordingController() async {
    var controller = _nativeCameraController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.enableAudio) {
      return controller;
    }

    await _startNativeCameraPreview(
      preferFront: _usingFrontCamera,
      enableAudio: true,
    );
    if (!mounted) {
      return null;
    }
    controller = _nativeCameraController;
    if (controller?.value.isInitialized == true) {
      return controller;
    }
    return null;
  }

  Future<void> _stopVideoRecording() async {
    if (!_usesNativeCameraCapture) {
      return;
    }
    await _stopNativeVideoRecording();
  }

  Future<void> _stopNativeVideoRecording() async {
    if (!_recordingVideo || _stoppingVideoRecording) {
      return;
    }
    final controller = _nativeCameraController;
    if (controller == null || !controller.value.isRecordingVideo) {
      _cancelRecordingTimer();
      if (mounted) {
        setState(() {
          _recordingVideo = false;
          _recordingHoldActive = false;
          _stoppingVideoRecording = false;
          _preparingDrafts = false;
          _recordingStartedAt = null;
          _recordingProgress = 0;
          _error = homeStoryComposerRecordingFailed;
        });
      }
      return;
    }

    _cancelRecordingTimer();
    if (mounted) {
      setState(() {
        _recordingVideo = false;
        _recordingHoldActive = false;
        _stoppingVideoRecording = true;
        _preparingDrafts = true;
        _recordingProgress = 1;
        _error = null;
      });
    }

    try {
      final file = await _stopNativeVideoRecordingOnce(controller);
      if (file == null) {
        return;
      }
      Log.d(
        'Story native video recording stopped',
        category: LogCategory.media,
        source: 'story-camera',
      );
      await _processRecordedVideo(file);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to stop story video recording '
            '(${error.runtimeType}).',
        category: LogCategory.media,
        source: 'story-camera',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = homeStoryComposerRecordingFailed;
      });
    } finally {
      if (mounted) {
        setState(() {
          _stoppingVideoRecording = false;
          _recordingStartedAt = null;
          _recordingProgress = 0;
        });
      }
    }
  }

  Future<void> _cancelVideoRecording({bool notify = true}) async {
    await _cancelNativeVideoRecording(notify: notify);
  }

  Future<void> _cancelNativeVideoRecording({bool notify = true}) async {
    _cancelRecordingTimer();
    final controller = _nativeCameraController;
    final hadRecordingWork = homeStoryComposerHasNativeRecordingWorkInFlight(
      recordingVideo: _recordingVideo,
      recordingStarting: _recordingStarting,
      stoppingVideoRecording: _stoppingVideoRecording,
    );
    _recordingVideo = false;
    _recordingStarting = false;
    _stoppingVideoRecording = false;
    _recordingHoldActive = false;
    _recordingStartedAt = null;
    _recordingProgress = 0;
    _preparingDrafts = false;
    if (controller != null) {
      await _discardNativeVideoRecording(
        controller,
        reason: 'recording_cancelled',
      );
    }
    if (hadRecordingWork && notify && mounted) {
      setState(() {});
    }
  }

  Future<void> _discardNativeVideoRecording(
    native_camera.CameraController controller, {
    required String reason,
  }) async {
    try {
      if (!controller.value.isRecordingVideo) {
        return;
      }
      await _stopNativeVideoRecordingOnce(controller);
      Log.d(
        'Story native video recording discarded reason=$reason',
        category: LogCategory.media,
        source: 'story-camera',
      );
    } catch (error) {
      Log.w(
        'Story native video recording discard failed reason=$reason '
        'error=$error',
        category: LogCategory.media,
        source: 'story-camera',
      );
    }
  }

  Future<XFile?> _stopNativeVideoRecordingOnce(
    native_camera.CameraController controller,
  ) {
    final existing = _nativeStopFuture;
    if (existing != null) {
      return existing;
    }

    late final Future<XFile?> stopFuture;
    stopFuture = controller
        .stopVideoRecording()
        .then<XFile?>((file) => file)
        .whenComplete(() {
          if (identical(_nativeStopFuture, stopFuture)) {
            _nativeStopFuture = null;
          }
        });
    _nativeStopFuture = stopFuture;
    return stopFuture;
  }

  void _finishHoldRecording() {
    if (!_usesMobileCameraCapture) {
      return;
    }
    _recordingHoldActive = false;
    if (_recordingVideo) {
      unawaited(_stopVideoRecording());
    }
  }

  Future<void> _processRecordedVideo(XFile file) async {
    final path = file.path;
    if (path.isEmpty) {
      if (mounted) {
        setState(() {
          _preparingDrafts = false;
          _error = homeStoryComposerRecordingFailed;
        });
      }
      return;
    }

    final probe = await _videoProbe.probe(path);
    if (probe.duration <= Duration.zero) {
      if (mounted) {
        setState(() {
          _preparingDrafts = false;
          _error = homeStoryComposerRecordingFailed;
        });
      }
      return;
    }

    final length = await file.length();
    if (!homeStoryComposerShouldOpenVideoEditor(
      sizeBytes: length,
      duration: probe.duration,
    )) {
      if (mounted) {
        setState(() {
          _preparingDrafts = false;
          _error = homeStoryComposerVideoTooLargeError;
        });
      }
      return;
    }

    final sourceName = file.name.trim().isEmpty
        ? 'story-video-${DateTime.now().millisecondsSinceEpoch}.mp4'
        : file.name;

    // Saves the raw recording from disk, before any trim or overlay is applied.
    unawaited(
      DownloadUtils.autoSaveCapturedMediaIfEnabled(
        filename: sourceName,
        path: path,
        mimeType: file.mimeType ?? Mime.lookupType(sourceName) ?? 'video/mp4',
      ),
    );

    final draft = StoryVideoDraft(
      id: createStoryDraftId(),
      path: path,
      sourceName: sourceName,
      sourceMimeType:
          file.mimeType ?? Mime.lookupType(sourceName) ?? Mime.lookupType(path),
      sizeBytes: length,
      duration: probe.duration,
      trimEnd: probe.duration > storyMaxVideoDuration
          ? storyMaxVideoDuration
          : null,
      width: probe.size?.width.round(),
      height: probe.size?.height.round(),
      displayWidth: probe.visibleContentSize?.width.round(),
      displayHeight: probe.visibleContentSize?.height.round(),
      hasBakedLetterbox: probe.hasBakedLetterbox,
      thumbnailBytes: probe.thumbnailBytes,
      thumbnailMimeType: probe.thumbnailBytes == null
          ? null
          : Mime.lookupType('', data: probe.thumbnailBytes),
      canvasMode: StoryVideoCanvasMode.portrait,
      preparedForDecoration: false,
    );
    final edited = await HomeStoryVideoEditor.show(
      context,
      client: widget.client,
      draft: draft,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (edited != null) {
        _videoDrafts.add(edited);
      }
      _preparingDrafts = false;
      _error = null;
    });
  }

  void _startRecordingTimer() {
    _cancelRecordingTimer();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_recordingVideo || _stoppingVideoRecording) {
        return;
      }
      final elapsed = _recordingElapsed;
      final progress = homeStoryComposerRecordingProgress(elapsed: elapsed);
      if (elapsed >= storyMaxVideoDuration) {
        unawaited(_stopVideoRecording());
        return;
      }
      setState(() {
        _recordingProgress = progress;
      });
    });
  }

  void _cancelRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  Future<void> _captureNativePickerPhoto() async {
    if (_cameraStarting) {
      return;
    }
    setState(() {
      _cameraStarting = true;
      _error = null;
    });
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: _usingFrontCamera
            ? CameraDevice.front
            : CameraDevice.rear,
      );
      if (file == null || !mounted) {
        if (mounted) {
          setState(() {
            _cameraStarting = false;
          });
        }
        return;
      }

      setState(() {
        _cameraStarting = false;
        _preparingDrafts = true;
      });
      await _allowBusyIndicatorToPaint();
      if (!mounted) {
        return;
      }

      await _processCapturedPhoto(
        length: file.length,
        readAsBytes: file.readAsBytes,
        sourceName: file.name,
        sourceMimeType: file.mimeType,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraStarting = false;
        _preparingDrafts = false;
        _error = homeStoryComposerCaptureError;
      });
    }
  }

  Future<void> _processCapturedPhoto({
    required Future<int> Function() length,
    required Future<Uint8List> Function() readAsBytes,
    required String sourceName,
    required String? sourceMimeType,
  }) async {
    final fileLength = await length();
    if (!storyImageSizeIsAllowed(fileLength)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = homeStoryComposerImageTooLargeError;
      });
      return;
    }

    final bytes = await readAsBytes();
    if (!storyImageSizeIsAllowed(bytes.lengthInBytes)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = homeStoryComposerImageTooLargeError;
      });
      return;
    }

    if (!mounted) {
      return;
    }

    final resolvedMimeType =
        sourceMimeType ?? Mime.lookupType(sourceName, data: bytes);

    // Saves the untouched capture, not the rendered story — the edited story is
    // covered separately by [preferences.autoSaveUploadedStories].
    unawaited(
      DownloadUtils.autoSaveCapturedMediaIfEnabled(
        filename: sourceName,
        bytes: bytes,
        mimeType: resolvedMimeType,
      ),
    );

    final draft = await StoryImageRenderer.createDraft(
      sourceBytes: bytes,
      sourceName: sourceName,
      sourceMimeType: resolvedMimeType,
      previewOnly: true,
    );
    await _addDraftAndEdit(draft);
  }

  Future<void> _createTextStory() async {
    setState(() {
      _preparingDrafts = true;
      _error = null;
    });
    await _allowBusyIndicatorToPaint();
    if (!mounted) {
      return;
    }
    try {
      final draft = await StoryImageRenderer.createTextDraft();
      await _addDraftAndEdit(draft);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = homeStoryComposerRenderError;
      });
    }
  }

  Future<void> _addDraftAndEdit(StoryDraft draft) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _preparingDrafts = false;
      _error = null;
    });
    // Open the editor before queueing anything, matching the video flow:
    // backing out without Done discards the capture instead of leaving an
    // unreviewed draft in the share queue.
    final edited = await HomeStoryEditor.show(
      context,
      client: widget.client,
      draft: draft,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (edited != null) {
        _drafts.add(edited);
      }
      _error = null;
    });
  }

  void _disposeCamera() {
    _cameraRequestGeneration++;
    final stream = _cameraStream;
    final renderer = _cameraRenderer;
    _cameraStream = null;
    _cameraRenderer = null;
    _disposeNativeCamera();
    unawaited(_disposeCameraResources(stream: stream, renderer: renderer));
  }

  void _disposeNativeCamera() {
    _cameraRequestGeneration++;
    final controller = _nativeCameraController;
    _nativeCameraController = null;
    if (controller != null) {
      unawaited(_trackNativeCameraDisposal(controller));
    }
  }

  Future<void> _trackNativeCameraDisposal(
    native_camera.CameraController controller,
  ) {
    final disposal = _disposeNativeCameraController(controller);
    _pendingNativeCameraDisposal = disposal;
    unawaited(
      disposal.whenComplete(() {
        if (identical(_pendingNativeCameraDisposal, disposal)) {
          _pendingNativeCameraDisposal = null;
        }
      }),
    );
    return disposal;
  }

  Future<void> _disposeNativeCameraController(
    native_camera.CameraController controller,
  ) async {
    try {
      await controller.dispose();
    } catch (error) {
      Log.w(
        'Story native camera dispose failed error=$error',
        category: LogCategory.media,
        source: 'story-camera',
      );
    }
  }

  Future<void> _disposeCameraResources({
    webrtc.MediaStream? stream,
    webrtc.RTCVideoRenderer? renderer,
  }) async {
    for (final track
        in stream?.getTracks() ?? const <webrtc.MediaStreamTrack>[]) {
      await track.stop();
    }
    renderer?.srcObject = null;
    await renderer?.dispose();
    await stream?.dispose();
  }

  Future<void> _showCurrentStories() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final ownStories = _ownStories;
          final height = math.min(
            MediaQuery.sizeOf(context).height * 0.72,
            520,
          );
          return SafeArea(
            top: false,
            child: SizedBox(
              height: height.toDouble(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      homeStoryComposerCurrentStories,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ownStories.isEmpty
                          ? Center(
                              child: Text(
                                homeStoryComposerNoCurrentStories,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 112,
                                    mainAxisExtent: 144,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                  ),
                              itemCount: ownStories.length,
                              itemBuilder: (context, index) {
                                final story = ownStories[index];
                                final deleting = _deletingStoryIds.contains(
                                  story.storyId,
                                );
                                return _StoryManageTile(
                                  story: story,
                                  reactions:
                                      _storyComponent?.reactionsForStory(
                                        story,
                                      ) ??
                                      const [],
                                  deleting: deleting,
                                  deleteTooltip: homeStoryComposerDeleteStory,
                                  onDelete: deleting
                                      ? null
                                      : () async {
                                          await _deleteStory(story);
                                          if (context.mounted) {
                                            setSheetState(() {});
                                          }
                                        },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _pickPhotoFiles();
      if (files == null || files.isEmpty) {
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = true;
        _error = null;
      });
      await _allowBusyIndicatorToPaint();
      if (!mounted) {
        return;
      }

      final selected = <StoryDraft>[];
      var skippedOversized = false;
      for (final file in files) {
        final length = await file.length();
        if (!storyImageSizeIsAllowed(length)) {
          skippedOversized = true;
          continue;
        }

        final bytes = await file.readAsBytes();
        if (!storyImageSizeIsAllowed(bytes.lengthInBytes)) {
          skippedOversized = true;
          continue;
        }

        selected.add(
          await StoryImageRenderer.createDraft(
            sourceBytes: bytes,
            sourceName: file.name,
            sourceMimeType:
                file.mimeType ?? Mime.lookupType(file.name, data: bytes),
          ),
        );
      }
      if (!mounted) {
        return;
      }
      final firstNewDraftId = selected.firstOrNull?.id;
      setState(() {
        _error = skippedOversized ? homeStoryComposerImageTooLargeError : null;
        _drafts.addAll(selected);
        _preparingDrafts = false;
      });
      if (firstNewDraftId != null) {
        final index = _drafts.indexWhere(
          (draft) => draft.id == firstNewDraftId,
        );
        if (index >= 0) {
          await _editDraft(index);
        }
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to add selected story photos '
            '(${error.runtimeType}).',
        category: LogCategory.media,
        source: 'stories',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = homeStoryComposerPickError;
      });
    }
  }

  Future<List<XFile>?> _pickPhotoFiles() async {
    if (homeStoryComposerUsesNativePhotoLibraryPicker(
      isIOS: PlatformUtils.isIOS,
    )) {
      final files = await _imagePicker.pickMultiImage(
        imageQuality: homeStoryComposerIosPhotoLibraryImageQuality,
        requestFullMetadata: false,
      );
      return files.isEmpty ? null : files;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    return result?.xFiles;
  }

  Future<void> _pickVideos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
        withData: false,
      );
      final files = result?.xFiles ?? const <XFile>[];
      if (files.isEmpty) {
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = true;
        _error = null;
      });
      await _allowBusyIndicatorToPaint();
      if (!mounted) {
        return;
      }

      var oversized = false;
      var failed = false;
      for (final file in files) {
        final path = file.path;
        if (path.isEmpty) {
          failed = true;
          continue;
        }
        try {
          final length = await file.length();
          final probe = await _videoProbe.probe(path);
          if (!homeStoryComposerShouldOpenVideoEditor(
            sizeBytes: length,
            duration: probe.duration,
          )) {
            oversized = true;
            continue;
          }
          final draft = StoryVideoDraft(
            id: createStoryDraftId(),
            path: path,
            sourceName: file.name,
            sourceMimeType: file.mimeType ?? Mime.lookupType(file.name),
            sizeBytes: length,
            duration: probe.duration,
            trimEnd: probe.duration > storyMaxVideoDuration
                ? storyMaxVideoDuration
                : null,
            width: probe.size?.width.round(),
            height: probe.size?.height.round(),
            displayWidth: probe.visibleContentSize?.width.round(),
            displayHeight: probe.visibleContentSize?.height.round(),
            hasBakedLetterbox: probe.hasBakedLetterbox,
            thumbnailBytes: probe.thumbnailBytes,
            thumbnailMimeType: probe.thumbnailBytes == null
                ? null
                : Mime.lookupType('', data: probe.thumbnailBytes),
            canvasMode: StoryVideoCanvasMode.portrait,
            preparedForDecoration: false,
          );
          final edited = await HomeStoryVideoEditor.show(
            context,
            client: widget.client,
            draft: draft,
          );
          if (!mounted) {
            return;
          }
          if (edited != null) {
            setState(() {
              _videoDrafts.add(edited);
            });
          }
        } catch (error, stackTrace) {
          failed = true;
          Log.onError(
            error,
            stackTrace,
            content:
                'Failed to add a selected story video '
                '(${error.runtimeType}).',
            category: LogCategory.media,
            source: 'stories',
          );
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = oversized
            ? homeStoryComposerVideoTooLargeError
            : failed
            ? homeStoryComposerVideoPickError
            : null;
      });
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to add selected story videos '
            '(${error.runtimeType}).',
        category: LogCategory.media,
        source: 'stories',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _preparingDrafts = false;
        _error = homeStoryComposerVideoPickError;
      });
    }
  }

  Future<void> _editDraft(int index) async {
    if (index < 0 || index >= _drafts.length) {
      return;
    }
    final edited = await HomeStoryEditor.show(
      context,
      client: widget.client,
      draft: _drafts[index],
    );
    if (!mounted || edited == null) {
      return;
    }
    setState(() {
      final currentIndex = _drafts.indexWhere((draft) => draft.id == edited.id);
      if (currentIndex >= 0) {
        _drafts[currentIndex] = edited;
      }
      _error = null;
    });
  }

  void _removeDraft(int index) {
    if (index < 0 || index >= _drafts.length) {
      return;
    }
    setState(() {
      _drafts.removeAt(index);
      _error = null;
    });
  }

  Future<void> _editVideoDraft(int index) async {
    if (index < 0 || index >= _videoDrafts.length) {
      return;
    }
    final edited = await HomeStoryVideoEditor.show(
      context,
      client: widget.client,
      draft: _videoDrafts[index],
    );
    if (!mounted || edited == null) {
      return;
    }
    setState(() {
      final currentIndex = _videoDrafts.indexWhere(
        (draft) => draft.id == edited.id,
      );
      if (currentIndex >= 0) {
        _videoDrafts[currentIndex] = edited;
      }
      _error = null;
    });
  }

  void _removeVideoDraft(int index) {
    if (index < 0 || index >= _videoDrafts.length) {
      return;
    }
    setState(() {
      _videoDrafts.removeAt(index);
      _error = null;
    });
  }

  void _showRecordingUnavailable() {
    setState(() {
      _error = homeStoryComposerRecordingUnavailable;
    });
  }

  Future<void> _saveDraft(int index) async {
    if (index < 0 || index >= _drafts.length) {
      return;
    }

    setState(() {
      _preparingDrafts = true;
      _error = null;
    });
    await _allowBusyIndicatorToPaint();
    if (!mounted) {
      return;
    }

    var saved = false;
    try {
      final upload = await _renderer.renderUpload(_drafts[index]);
      saved = await _savePhotoUploadToPhotosIfSupported(upload);
      if (!saved) {
        final saveFileWithBytes =
            PlatformUtils.isAndroid ||
            PlatformUtils.isIOS ||
            PlatformUtils.isWeb;
        final destinationPath = await FilePicker.platform.saveFile(
          fileName: upload.name,
          bytes: saveFileWithBytes ? upload.bytes : null,
        );
        if (PlatformUtils.isWeb) {
          saved = true;
        } else if (destinationPath == null) {
          return;
        } else if (!saveFileWithBytes) {
          await writeLocalFileBytes(destinationPath, upload.bytes);
          saved = true;
        } else {
          saved = true;
        }
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error is StoryImageRenderException
            ? homeStoryComposerRenderError
            : homeStoryComposerSaveDraftError;
      });
      return;
    } finally {
      if (mounted) {
        setState(() {
          _preparingDrafts = false;
        });
      }
    }

    if (!mounted || !saved) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(homeStoryComposerSaveDraftSuccess)));
  }

  Future<bool> _savePhotoUploadToPhotosIfSupported(
    StoryPhotoUpload upload,
  ) async {
    try {
      return await DownloadUtils.saveImageBytesToPhotosIfSupported(
        bytes: upload.bytes,
        filename: upload.name,
        mimeType: upload.mimeType,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to save story photo to Photos',
        category: LogCategory.media,
        source: 'stories',
      );
      return false;
    }
  }

  Future<void> _autoSaveUploadedPhotoStory(StoryPhotoUpload upload) async {
    if (!preferences.autoSaveUploadedStories.value) {
      return;
    }

    final saved = await _savePhotoUploadToPhotosIfSupported(upload);
    if (!saved && PlatformUtils.isIOS) {
      Log.w(
        'Story photo auto-save to Photos was unavailable or denied.',
        category: LogCategory.media,
        source: 'stories',
      );
    }
  }

  Future<void> _chooseMentions() async {
    final contacts = _mentionContacts;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _StoryMentionSheet(
        contacts: contacts,
        selectedUserIds: _mentionedUserIds,
        title: homeStoryComposerMentions,
        doneLabel: homeStoryComposerDone,
        emptyLabel: homeStoryComposerNoMentionContacts,
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _mentionedUserIds
        ..clear()
        ..addAll(selected);
      _error = null;
    });
  }

  Future<void> _shareStories() async {
    final stories = _storyComponent;
    if (stories == null) {
      setState(() {
        _error = homeStoryComposerUploadError;
      });
      return;
    }
    if (!_hasDrafts) {
      return;
    }
    if (_mentionContacts.isEmpty) {
      setState(() {
        _error = homeStoryComposerNoContacts;
      });
      return;
    }

    final drafts = List<StoryDraft>.unmodifiable(_drafts);
    final videoDrafts = List<StoryVideoDraft>.unmodifiable(_videoDrafts);
    final mentionedUserIds = Set<String>.unmodifiable(_mentionedUserIds);
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (videoDrafts.any((draft) {
      final upload = draft.toUpload(mentionedUserIds: mentionedUserIds);
      return !upload.hasValidSelection || !upload.usesFullSource;
    })) {
      setState(() {
        _error = homeStoryComposerVideoTrimUnavailable;
      });
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });

    unawaited(
      _shareStoryDraftsInBackground(
        stories: stories,
        drafts: drafts,
        videoDrafts: videoDrafts,
        mentionedUserIds: mentionedUserIds,
        messenger: messenger,
      ),
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _shareStoryDraftsInBackground({
    required StoryComponent stories,
    required List<StoryDraft> drafts,
    required List<StoryVideoDraft> videoDrafts,
    required Set<String> mentionedUserIds,
    ScaffoldMessengerState? messenger,
  }) async {
    var nextPendingDraftIndex = 0;
    var nextPendingVideoIndex = 0;
    try {
      final result = await stories.trackPendingStoryUpload(
        () => _renderAndUploadStoryDrafts(
          stories: stories,
          drafts: drafts,
          videoDrafts: videoDrafts,
          mentionedUserIds: mentionedUserIds,
          onDraftProgress: (nextIndex) {
            nextPendingDraftIndex = nextIndex;
          },
          onVideoProgress: (nextIndex) {
            nextPendingVideoIndex = nextIndex;
          },
        ),
      );
      final failure = classifyHomeStoryUploadFailure(
        result: result,
        nextPendingDraftIndex: nextPendingDraftIndex,
        nextPendingVideoIndex: nextPendingVideoIndex,
      );
      if (failure == null) {
        _showStoryUploadOutcomeSnackBar(
          messenger: messenger,
          message: homeStoryComposerUploadSent,
        );
        return;
      }

      if (failure.kind == HomeStoryUploadFailureKind.sentNone) {
        Log.w(
          'Story background upload completed without sending events. '
          'stories=${result.storyCount} targets=${result.targetRoomCount} '
          'failed=${result.failedEventCount}',
          category: LogCategory.media,
          source: 'stories',
        );
        _showStoryUploadFailureSnackBar(
          messenger: messenger,
          message: homeStoryComposerUploadSentNone(
            result.storyCount,
            result.failedEventCount,
          ),
          stories: stories,
          drafts: failure.retryDrafts(drafts),
          videoDrafts: failure.retryVideoDrafts(videoDrafts),
          mentionedUserIds: mentionedUserIds,
        );
      } else {
        Log.w(
          'Story background upload partially failed. '
          'stories=${result.storyCount} sent=${result.sentEventCount} '
          'targets=${result.targetRoomCount} failed=${result.failedEventCount}',
          category: LogCategory.media,
          source: 'stories',
        );
        _showStoryUploadFailureSnackBar(
          messenger: messenger,
          message: homeStoryComposerUploadPartiallyFailed(
            result.sentEventCount,
            result.failedEventCount,
          ),
          stories: stories,
          drafts: failure.retryDrafts(drafts),
          videoDrafts: failure.retryVideoDrafts(videoDrafts),
          mentionedUserIds: mentionedUserIds,
        );
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: error is StoryImageRenderException
            ? 'Failed to render queued story upload'
            : 'Failed to share queued story upload',
        category: LogCategory.media,
        source: 'stories',
      );
      _showStoryUploadFailureSnackBar(
        messenger: messenger,
        message: error is StoryImageRenderException
            ? homeStoryComposerUploadPrepareFailed
            : homeStoryComposerUploadFailed,
        stories: stories,
        drafts: drafts.sublist(nextPendingDraftIndex),
        videoDrafts: videoDrafts.sublist(nextPendingVideoIndex),
        mentionedUserIds: mentionedUserIds,
      );
    }
  }

  void _showStoryUploadFailureSnackBar({
    required ScaffoldMessengerState? messenger,
    required String message,
    required StoryComponent stories,
    required List<StoryDraft> drafts,
    required List<StoryVideoDraft> videoDrafts,
    required Set<String> mentionedUserIds,
  }) {
    if (messenger == null) {
      return;
    }

    final retryDrafts = List<StoryDraft>.unmodifiable(drafts);
    final retryVideoDrafts = List<StoryVideoDraft>.unmodifiable(videoDrafts);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: retryDrafts.isEmpty && retryVideoDrafts.isEmpty
              ? null
              : SnackBarAction(
                  label: homeStoryComposerUploadRetry,
                  onPressed: () {
                    unawaited(
                      _shareStoryDraftsInBackground(
                        stories: stories,
                        drafts: retryDrafts,
                        videoDrafts: retryVideoDrafts,
                        mentionedUserIds: mentionedUserIds,
                        messenger: messenger,
                      ),
                    );
                  },
                ),
        ),
      );
  }

  void _showStoryUploadOutcomeSnackBar({
    required ScaffoldMessengerState? messenger,
    required String message,
  }) {
    if (messenger == null) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<StoryUploadResult> _renderAndUploadStoryDrafts({
    required StoryComponent stories,
    required List<StoryDraft> drafts,
    required List<StoryVideoDraft> videoDrafts,
    required Set<String> mentionedUserIds,
    required ValueChanged<int> onDraftProgress,
    required ValueChanged<int> onVideoProgress,
  }) async {
    final normalizedMentionedUserIds = normalizeStoryMentionUserIds(
      mentionedUserIds,
    );
    var storyCount = 0;
    var sentEventCount = 0;
    var targetRoomCount = 0;
    var failedEventCount = 0;

    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      final draftMentionedUserIds = normalizeStoryMentionUserIds([
        ...normalizedMentionedUserIds,
        ...draft.visualMentionUserIds,
      ]);
      final photo = (await _renderer.renderUpload(
        draft,
      )).copyWith(mentionedUserIds: draftMentionedUserIds);
      final result = await stories.uploadPhotos([photo]);
      if (result.sentEventCount > 0) {
        await _autoSaveUploadedPhotoStory(photo);
      }
      storyCount += result.storyCount;
      sentEventCount += result.sentEventCount;
      targetRoomCount = math.max(targetRoomCount, result.targetRoomCount);
      failedEventCount += result.failedEventCount;
      final nextRetryIndex = result.nextRetryIndexAfter(index);
      if (nextRetryIndex > index) {
        onDraftProgress(nextRetryIndex);
      } else {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    for (var index = 0; index < videoDrafts.length; index++) {
      final videoDraft = videoDrafts[index];
      final upload = videoDraft.toUpload(
        mentionedUserIds: normalizedMentionedUserIds,
      );
      if (!upload.hasValidSelection || !upload.usesFullSource) {
        throw StateError('Story video trim export is not available');
      }
      final result = await stories.uploadVideos([upload]);
      storyCount += result.storyCount;
      sentEventCount += result.sentEventCount;
      targetRoomCount = math.max(targetRoomCount, result.targetRoomCount);
      failedEventCount += result.failedEventCount;
      final nextRetryIndex = result.nextRetryIndexAfter(index);
      if (nextRetryIndex > index) {
        onVideoProgress(nextRetryIndex);
      } else {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    return StoryUploadResult(
      storyCount: storyCount,
      sentEventCount: sentEventCount,
      targetRoomCount: targetRoomCount,
      failedEventCount: failedEventCount,
    );
  }

  Future<void> _deleteStory(StoryItem story) async {
    final stories = _storyComponent;
    if (stories == null) {
      return;
    }

    setState(() {
      _deletingStoryIds.add(story.storyId);
      _error = null;
    });
    try {
      await stories.deleteStory(story.storyId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = homeStoryComposerDeleteError;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _deletingStoryIds.remove(story.storyId);
        });
      }
    }
  }
}

class _StoryCameraToolButton extends StatelessWidget {
  const _StoryCameraToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.badge,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return tiamat.Tooltip(
      text: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton.filledTonal(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.58),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.black.withValues(alpha: 0.28),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.38),
              minimumSize: const Size.square(48),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            icon: Icon(icon),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    badge!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StoryCaptureButton extends StatelessWidget {
  const _StoryCaptureButton({
    required this.tooltip,
    required this.busy,
    required this.recording,
    required this.recordingProgress,
    required this.onPressed,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onLongPressCancel,
  });

  final String tooltip;
  final bool busy;
  final bool recording;
  final double recordingProgress;
  final VoidCallback? onPressed;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null || onLongPressStart != null;
    return tiamat.Tooltip(
      text: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: enabled,
        child: FocusableActionDetector(
          enabled: enabled,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: onPressed,
            onLongPressStart: onLongPressStart,
            onLongPressEnd: onLongPressEnd,
            onLongPressCancel: onLongPressCancel,
            child: MouseRegion(
              cursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: SizedBox.square(
                dimension: 78,
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: enabled ? 0.14 : 0.08,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.86),
                          width: 4,
                        ),
                      ),
                    ),
                    if (recording)
                      CircularProgressIndicator(
                        value: recordingProgress.clamp(0.0, 1.0).toDouble(),
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white.withValues(alpha: 0.24),
                        color: scheme.error,
                      ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: busy
                          ? const SizedBox.square(
                              key: ValueKey('busy'),
                              dimension: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : recording
                          ? DecoratedBox(
                              key: const ValueKey('recording'),
                              decoration: BoxDecoration(
                                color: scheme.error,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const SizedBox.square(dimension: 28),
                            )
                          : const DecoratedBox(
                              key: ValueKey('ready'),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox.square(dimension: 54),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryRecordingPill extends StatelessWidget {
  const _StoryRecordingPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 8),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryDraftStatusPill extends StatelessWidget {
  const _StoryDraftStatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.84), size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryMentionContact {
  const _StoryMentionContact({
    required this.userId,
    required this.displayName,
    required this.avatar,
  });

  final String userId;
  final String displayName;
  final ImageProvider? avatar;
}

class _StoryMentionSheet extends StatefulWidget {
  const _StoryMentionSheet({
    required this.contacts,
    required this.selectedUserIds,
    required this.title,
    required this.doneLabel,
    required this.emptyLabel,
  });

  final List<_StoryMentionContact> contacts;
  final Set<String> selectedUserIds;
  final String title;
  final String doneLabel;
  final String emptyLabel;

  @override
  State<_StoryMentionSheet> createState() => _StoryMentionSheetState();
}

class _StoryMentionSheetState extends State<_StoryMentionSheet> {
  late final Set<String> _selected = Set<String>.of(widget.selectedUserIds);

  @override
  Widget build(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.72, 520.0);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(widget.doneLabel),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: widget.contacts.isEmpty
                    ? Center(
                        child: Text(
                          widget.emptyLabel,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        itemCount: widget.contacts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final contact = widget.contacts[index];
                          final selected = _selected.contains(contact.userId);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selected.add(contact.userId);
                                } else {
                                  _selected.remove(contact.userId);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              backgroundImage: contact.avatar,
                              child: contact.avatar == null
                                  ? Text(
                                      contact.displayName.characters
                                          .take(1)
                                          .toString()
                                          .toUpperCase(),
                                    )
                                  : null,
                            ),
                            title: Text(contact.displayName),
                            subtitle: Text(contact.userId),
                            controlAffinity: ListTileControlAffinity.trailing,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryManageTile extends StatelessWidget {
  const _StoryManageTile({
    required this.story,
    required this.reactions,
    required this.deleting,
    required this.deleteTooltip,
    required this.onDelete,
  });

  final StoryItem story;
  final List<StoryReaction> reactions;
  final bool deleting;
  final String deleteTooltip;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = story.image ?? story.thumbnail;
    final reactionCounts = <String, int>{};
    final videoLayout = story.isVideo
        ? storyVideoCompositionLayout(
            canvasSize: const Size(92, 124),
            fitMode: story.fitMode,
            mediaWidth: story.width,
            mediaHeight: story.height,
            displayWidth: story.displayWidth,
            displayHeight: story.displayHeight,
            hasBakedLetterbox: story.hasBakedLetterbox,
          )
        : null;
    for (final reaction in reactions) {
      reactionCounts.update(
        reaction.reaction,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return SizedBox(
      width: 92,
      height: 124,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: DecoratedBox(
                decoration: story.isVideo
                    ? storyVideoBackgroundDecoration(
                        backgroundColor: Color(
                          story.backgroundColor ??
                              storyDefaultVideoBackgroundColor,
                        ),
                        backgroundGradientColor: Color(
                          story.backgroundGradientColor ??
                              storyDefaultVideoBackgroundGradientColor,
                        ),
                        backgroundMode: story.backgroundMode,
                      )
                    : BoxDecoration(color: scheme.surfaceContainerHighest),
                child: preview == null
                    ? Icon(
                        story.isVideo
                            ? Icons.play_circle_outline
                            : Icons.broken_image_outlined,
                        color: story.isVideo
                            ? Colors.white70
                            : scheme.onSurfaceVariant,
                      )
                    : story.isVideo
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fromRect(
                            rect: videoLayout!.mediaDisplayRect,
                            child: StoryVideoMediaLayer(
                              layout: videoLayout,
                              builder: (fit) => Image(image: preview, fit: fit),
                            ),
                          ),
                          StoryVideoBackgroundMatte(
                            rects: videoLayout.nonMediaRects,
                            backgroundColor: Color(
                              story.backgroundColor ??
                                  storyDefaultVideoBackgroundColor,
                            ),
                            backgroundGradientColor: Color(
                              story.backgroundGradientColor ??
                                  storyDefaultVideoBackgroundGradientColor,
                            ),
                            backgroundMode: story.backgroundMode,
                          ),
                        ],
                      )
                    : Image(image: preview, fit: BoxFit.cover),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton.filledTonal(
              tooltip: deleteTooltip,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.84),
                foregroundColor: scheme.error,
                minimumSize: const Size.square(32),
              ),
              onPressed: onDelete,
              icon: deleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 18),
            ),
          ),
          if (reactionCounts.isNotEmpty)
            Positioned(
              left: 5,
              right: 5,
              bottom: 5,
              child: Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  for (final entry in reactionCounts.entries.take(4))
                    _StoryReactionSummaryPill(
                      reaction: entry.key,
                      count: entry.value,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StoryReactionSummaryPill extends StatelessWidget {
  const _StoryReactionSummaryPill({
    required this.reaction,
    required this.count,
  });

  final String reaction;
  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text.rich(
          TextSpan(
            children: TextUtils.nativeEmojiTextSpans(
              count > 1 ? '$reaction $count' : reaction,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _StoryDraftTile extends StatelessWidget {
  const _StoryDraftTile({
    required this.draft,
    required this.editTooltip,
    required this.removeTooltip,
    required this.saveTooltip,
    required this.thumbnailCacheWidth,
    required this.thumbnailCacheHeight,
    required this.onEdit,
    required this.onSave,
    required this.onRemove,
  });

  final StoryDraft draft;
  final String editTooltip;
  final String removeTooltip;
  final String saveTooltip;
  final int thumbnailCacheWidth;
  final int thumbnailCacheHeight;
  final VoidCallback? onEdit;
  final VoidCallback? onSave;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = draft.previewBytes ?? draft.baseBytes;
    return SizedBox(
      width: homeStoryDraftReviewTileWidth,
      height: homeStoryDraftReviewTileHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: homeStoryDraftReviewFrameWidth,
            height: homeStoryDraftReviewTileHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: Colors.black,
                      child: Image.memory(
                        preview,
                        cacheWidth: thumbnailCacheWidth,
                        cacheHeight: thumbnailCacheHeight,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.42),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.42),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: IconButton.filledTonal(
              tooltip: saveTooltip,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.84),
                foregroundColor: scheme.onSurface,
                minimumSize: const Size.square(32),
              ),
              onPressed: onSave,
              icon: const Icon(Icons.download_outlined, size: 18),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: IconButton.filledTonal(
              tooltip: editTooltip,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.84),
                foregroundColor: scheme.onSurface,
                minimumSize: const Size.square(32),
              ),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton.filledTonal(
              tooltip: removeTooltip,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.84),
                foregroundColor: scheme.error,
                minimumSize: const Size.square(32),
              ),
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryVideoDraftTile extends StatelessWidget {
  const _StoryVideoDraftTile({
    required this.draft,
    required this.editTooltip,
    required this.removeTooltip,
    required this.thumbnailCacheWidth,
    required this.thumbnailCacheHeight,
    required this.onEdit,
    required this.onRemove,
  });

  final StoryVideoDraft draft;
  final String editTooltip;
  final String removeTooltip;
  final int thumbnailCacheWidth;
  final int thumbnailCacheHeight;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canvasSize = storyVideoCanvasSizeForConstraints(
      constraints: const BoxConstraints.tightFor(
        width: homeStoryDraftReviewTileWidth,
        height: homeStoryDraftReviewTileHeight,
      ),
      canvasMode: draft.canvasMode,
    );
    final layout = storyVideoCompositionLayout(
      canvasSize: canvasSize,
      fitMode: draft.fitMode,
      mediaWidth: draft.width,
      mediaHeight: draft.height,
      displayWidth: draft.displayWidth,
      displayHeight: draft.displayHeight,
      hasBakedLetterbox: draft.hasBakedLetterbox,
    );
    return SizedBox(
      width: homeStoryDraftReviewTileWidth,
      height: homeStoryDraftReviewTileHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: canvasSize.width,
            height: canvasSize.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DecoratedBox(
                      decoration: storyVideoBackgroundDecoration(
                        backgroundColor: draft.backgroundColor,
                        backgroundGradientColor: draft.backgroundGradientColor,
                        backgroundMode: draft.backgroundMode,
                      ),
                      child: draft.thumbnailBytes == null
                          ? Center(
                              child: Icon(
                                Icons.movie_outlined,
                                color: Colors.white.withValues(alpha: 0.72),
                                size: 34,
                              ),
                            )
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fromRect(
                                  rect: layout.mediaDisplayRect,
                                  child: StoryVideoMediaLayer(
                                    layout: layout,
                                    builder: (fit) => Image.memory(
                                      draft.thumbnailBytes!,
                                      cacheWidth: thumbnailCacheWidth,
                                      cacheHeight: thumbnailCacheHeight,
                                      fit: fit,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ),
                                StoryVideoBackgroundMatte(
                                  rects: layout.nonMediaRects,
                                  backgroundColor: draft.backgroundColor,
                                  backgroundGradientColor:
                                      draft.backgroundGradientColor,
                                  backgroundMode: draft.backgroundMode,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.42),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.42),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 5,
                  right: 5,
                  bottom: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            storyVideoDurationLabel(draft.selectedDuration),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: IconButton.filledTonal(
              tooltip: editTooltip,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.84),
                foregroundColor: scheme.onSurface,
                minimumSize: const Size.square(32),
              ),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton.filledTonal(
              tooltip: removeTooltip,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.84),
                foregroundColor: scheme.error,
                minimumSize: const Size.square(32),
              ),
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
