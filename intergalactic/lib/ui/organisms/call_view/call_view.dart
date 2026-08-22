import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:intergalactic/client/bug_report/bug_report_models.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/mobile_call_popout_controller.dart';
import 'package:intergalactic/client/components/voip/call_surface_mode.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_diagnostic_directory.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
import 'package:intergalactic/client/components/voip/call_preference_operation_guard.dart';
import 'package:intergalactic/client/components/voip/call_local_screenshare_auto_hide.dart';
import 'package:intergalactic/client/components/voip/call_local_playback_operation_guard.dart';
import 'package:intergalactic/client/components/voip/call_participant_audio_overrides.dart';
import 'package:intergalactic/client/components/voip/call_health.dart';
import 'package:intergalactic/client/components/voip/call_voice_input_level_monitor.dart';
import 'package:intergalactic/client/components/voip/native_webrtc_diagnostics.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/game_capture_test_target_runner.dart';
import 'package:intergalactic/client/components/voip/game_capture_probe_runner.dart';
import 'package:intergalactic/client/components/voip/stream_test_report_writer.dart';
import 'package:intergalactic/client/components/voip/stream_test_automation_command.dart';
import 'package:intergalactic/client/components/voip/stream_test_runner.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/screenshare_audio_visibility_grace.dart';
import 'package:intergalactic/client/components/voip/voip_receive_quality_policy.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_monitor.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/components/voip/webrtc_screencapture_source.dart';
import 'package:intergalactic/client/components/voip/windows_screen_capture_backend.dart';
import 'package:intergalactic/client/components/activity/activity_room_component.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_receiver_probe.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/call_view/call_diagnostics_path_labels.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_identity.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_fullscreen_stream_view.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_stream_view.dart';
import 'package:intergalactic/ui/pages/settings/app_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/report_bug_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:intergalactic/utils/list_extension.dart';
import 'package:intergalactic/utils/animation/ring_shaker.dart';
import 'package:intergalactic/utils/animation/ripple.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const String _microphoneInputProfileStandardAction = 'standard';
const double _voiceQuickMenuWidth = 280;
const double _voiceQuickMenuTextWidth = 216;
const double _mobileCallControlDockMaxWidth = 420;
const double _callControlRowHorizontalPadding = 8;
const double _callControlRowVerticalPadding = 6;
const double _defaultCallControlSpacing = 8;
const double _desktopCallControlSpacing = 12;
// Some mobile controls include TutorialAnchor padding around a 48px button.
const double _mobileCallControlButtonExtent = 56;
const EdgeInsets _mobileCallControlDockSafeAreaMargin = EdgeInsets.fromLTRB(
  10,
  0,
  10,
  10,
);

class _CallControlsVisibility extends StatelessWidget {
  const _CallControlsVisibility({
    required this.visible,
    required this.duration,
    required this.transparentBackground,
    required this.child,
  });

  final bool visible;
  final Duration duration;
  final bool transparentBackground;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (transparentBackground || InterGalacticMotion.shouldReduce(context)) {
      return visible ? child : const SizedBox.shrink();
    }

    return ExcludeFocus(
      excluding: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: duration,
            curve: InterGalacticMotion.standardOut,
            child: child,
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Future<void> debugSetCallViewReceivePriorityForTesting(
  VoipStream stream,
  VoipStreamReceivePriority priority,
) {
  return _setCallViewReceivePriority(stream, priority);
}

Future<void> _setCallViewReceivePriority(
  VoipStream stream,
  VoipStreamReceivePriority priority,
) async {
  try {
    await stream.setReceivePriority(priority);
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered call view stream priority failure',
      category: LogCategory.media,
      source: 'call-view-receive-priority',
    );
  }
}

@visibleForTesting
({bool edgeToEdge, bool showTileScrim, bool useRootOverlayForMenus})
debugResolveCallTileSurfaceTreatmentForTesting({
  required bool transparentBackground,
}) {
  return _resolveCallTileSurfaceTreatment(
    transparentBackground: transparentBackground,
  );
}

@visibleForTesting
bool debugShouldUseCallMenuRootOverlayForTesting({
  required bool transparentBackground,
}) {
  return _shouldUseCallMenuRootOverlay(
    transparentBackground: transparentBackground,
  );
}

({bool edgeToEdge, bool showTileScrim, bool useRootOverlayForMenus})
_resolveCallTileSurfaceTreatment({required bool transparentBackground}) {
  return (
    edgeToEdge: false,
    showTileScrim: true,
    useRootOverlayForMenus: !transparentBackground,
  );
}

bool _shouldUseCallMenuRootOverlay({required bool transparentBackground}) {
  return !transparentBackground;
}

typedef DebugNativePictureInPictureTileCandidate = ({
  String tileId,
  VoipStreamType type,
  VoipStreamDirection direction,
  bool hidden,
  double audioLevel,
});

@visibleForTesting
int debugSelectNativePictureInPictureTileIndexForTesting({
  required List<DebugNativePictureInPictureTileCandidate> tiles,
  String? focusedTileId,
}) {
  return _selectNativePictureInPictureCandidateIndex(
    tiles,
    focusedTileId: focusedTileId,
    tileId: (tile) => tile.tileId,
    type: (tile) => tile.type,
    direction: (tile) => tile.direction,
    isHidden: (tile) => tile.hidden,
    audioLevel: (tile) => tile.audioLevel,
  );
}

@visibleForTesting
String debugSafePiPHashForTesting(String value) {
  return _safePiPHashValue(value);
}

int _selectNativePictureInPictureCandidateIndex<T>(
  List<T> tiles, {
  required String? focusedTileId,
  required String Function(T tile) tileId,
  required VoipStreamType Function(T tile) type,
  required VoipStreamDirection Function(T tile) direction,
  required bool Function(T tile) isHidden,
  required double Function(T tile) audioLevel,
}) {
  if (tiles.isEmpty) {
    throw ArgumentError.value(tiles, 'tiles', 'must not be empty');
  }

  if (focusedTileId != null) {
    for (var index = 0; index < tiles.length; index++) {
      if (tileId(tiles[index]) == focusedTileId) {
        return index;
      }
    }
  }

  List<int> indicesWhere(bool Function(T tile) test) {
    final indices = <int>[];
    for (var index = 0; index < tiles.length; index++) {
      if (test(tiles[index])) {
        indices.add(index);
      }
    }
    return indices;
  }

  int activeSpeakerIndex(List<int> indices) {
    return indices.reduce((bestIndex, candidateIndex) {
      final best = tiles[bestIndex];
      final candidate = tiles[candidateIndex];
      if (audioLevel(candidate) > audioLevel(best)) {
        return candidateIndex;
      }
      if (direction(best) != VoipStreamDirection.incoming &&
          direction(candidate) == VoipStreamDirection.incoming) {
        return candidateIndex;
      }
      return bestIndex;
    });
  }

  final visibleRemoteVideoIndices = indicesWhere(
    (tile) =>
        type(tile) == VoipStreamType.video &&
        direction(tile) == VoipStreamDirection.incoming &&
        !isHidden(tile),
  );
  if (visibleRemoteVideoIndices.isNotEmpty) {
    return activeSpeakerIndex(visibleRemoteVideoIndices);
  }

  final remoteVideoIndices = indicesWhere(
    (tile) =>
        type(tile) == VoipStreamType.video &&
        direction(tile) == VoipStreamDirection.incoming,
  );
  if (remoteVideoIndices.isNotEmpty) {
    return activeSpeakerIndex(remoteVideoIndices);
  }

  final visibleIndices = indicesWhere((tile) => !isHidden(tile));
  final visibleRemoteIndices = visibleIndices
      .where((index) => direction(tiles[index]) == VoipStreamDirection.incoming)
      .toList(growable: false);
  if (visibleRemoteIndices.isNotEmpty) {
    return activeSpeakerIndex(visibleRemoteIndices);
  }

  if (visibleIndices.isNotEmpty) {
    return activeSpeakerIndex(visibleIndices);
  }

  final remoteIndices = indicesWhere(
    (tile) => direction(tile) == VoipStreamDirection.incoming,
  );
  if (remoteIndices.isNotEmpty) {
    return activeSpeakerIndex(remoteIndices);
  }

  return activeSpeakerIndex([
    for (var index = 0; index < tiles.length; index++) index,
  ]);
}

String _safePiPHashValue(String value) {
  return sha256.convert(utf8.encode(value)).toString().substring(0, 12);
}

@visibleForTesting
Future<void> debugCancelCallViewSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelCallViewSubscription(subscription);
}

Future<void> _cancelCallViewSubscription(
  StreamSubscription? subscription,
) async {
  if (subscription == null) {
    return;
  }

  try {
    await subscription.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered call view subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'call-view-subscription',
    );
  }
}

@visibleForTesting
Future<void> debugCancelCallViewReceiverProbeSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelCallViewReceiverProbeSubscription(subscription);
}

Future<void> _cancelCallViewReceiverProbeSubscription(
  StreamSubscription? subscription,
) async {
  if (subscription == null) {
    return;
  }

  try {
    await subscription.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered call view receiver probe subscription cancel failure',
      category: LogCategory.webrtc,
      source: 'call-view-receiver-probe-subscription',
    );
  }
}

@visibleForTesting
Future<void> debugRunCallViewControlActionForTesting(
  FutureOr<void> Function()? action, {
  void Function()? onFailure,
}) {
  return _runCallViewControlAction(
    action,
    controlLabel: 'test control',
    onFailure: onFailure,
  );
}

/// Runs a call-control action, logging any failure.
///
/// [onFailure] separates the two kinds of guard this surface needs. Without it
/// the guard is *diagnostic best-effort*: a failure is recorded and the user is
/// not interrupted. With it the guard is *the user pressed a button*: the
/// caller is told the action did not happen so it can say so. Leave call and
/// mute must be the second kind — a silently failed leave presents as "the
/// hang-up button does nothing" with the session still marked connected, which
/// is indistinguishable from being locked out of calls entirely.
Future<void> _runCallViewControlAction(
  FutureOr<void> Function()? action, {
  String? controlLabel,
  void Function()? onFailure,
}) async {
  if (action == null) {
    return;
  }

  try {
    await Future<void>.sync(action);
  } catch (error, stackTrace) {
    final label = controlLabel?.trim();
    Log.onError(
      error,
      stackTrace,
      content: label == null || label.isEmpty
          ? 'Recovered call view control action failure'
          : 'Recovered call view control action failure: $label',
      category: LogCategory.webrtc,
      source: 'call-view-control-action',
    );
    onFailure?.call();
  }
}

@visibleForTesting
Future<void> debugRunCallViewMobilePictureInPictureActionForTesting(
  FutureOr<void> Function()? action,
) {
  return _runCallViewMobilePictureInPictureAction(action);
}

Future<void> _runCallViewMobilePictureInPictureAction(
  FutureOr<void> Function()? action,
) {
  return _runCallViewControlAction(
    action,
    controlLabel: 'mobile picture-in-picture',
  );
}

@visibleForTesting
int debugCompactPipTileLimitForTesting(int participantCount) {
  return _compactPipTileLimit(participantCount);
}

int _compactPipTileLimit(int participantCount) {
  if (participantCount <= 0) {
    return 0;
  }
  if (participantCount <= 2) {
    return participantCount;
  }
  return min(4, participantCount);
}

@visibleForTesting
Future<void> debugRunCallViewStreamTestActionForTesting(
  FutureOr<void> Function()? action,
) {
  return _runCallViewStreamTestAction(action, actionLabel: 'test action');
}

Future<void> _runCallViewStreamTestAction(
  FutureOr<void> Function()? action, {
  String? actionLabel,
}) async {
  if (action == null) {
    return;
  }

  try {
    await Future<void>.sync(action);
  } catch (error, stackTrace) {
    final label = actionLabel?.trim();
    Log.onError(
      error,
      stackTrace,
      content: label == null || label.isEmpty
          ? 'Recovered call view stream-test action failure'
          : 'Recovered call view stream-test action failure: $label',
      category: LogCategory.webrtc,
      source: 'call-view-stream-test-action',
    );
  }
}

@visibleForTesting
Future<void> debugRunCallViewVoiceMenuActionForTesting(
  FutureOr<void> Function()? action,
) {
  return _runCallViewVoiceMenuAction(action, actionLabel: 'test action');
}

Future<void> _runCallViewVoiceMenuAction(
  FutureOr<void> Function()? action, {
  String? actionLabel,
}) async {
  if (action == null) {
    return;
  }

  try {
    await Future<void>.sync(action);
  } catch (error, stackTrace) {
    final label = actionLabel?.trim();
    Log.onError(
      error,
      stackTrace,
      content: label == null || label.isEmpty
          ? 'Recovered call voice menu action failure'
          : 'Recovered call voice menu action failure: $label',
      category: LogCategory.webrtc,
      source: 'call-view-voice-menu-action',
    );
  }
}

@visibleForTesting
Future<void> debugRunCallViewStreamMenuActionForTesting(
  FutureOr<void> Function()? action, {
  void Function()? onFailure,
}) {
  return _runCallViewStreamMenuAction(
    action,
    actionLabel: 'test action',
    onFailure: onFailure,
  );
}

Future<void> _runCallViewStreamMenuAction(
  FutureOr<void> Function()? action, {
  String? actionLabel,
  void Function()? onFailure,
}) async {
  if (action == null) {
    return;
  }

  try {
    await Future<void>.sync(action);
  } catch (error, stackTrace) {
    final label = actionLabel?.trim();
    Log.onError(
      error,
      stackTrace,
      content: label == null || label.isEmpty
          ? 'Recovered call stream menu action failure'
          : 'Recovered call stream menu action failure: $label',
      category: LogCategory.webrtc,
      source: 'call-view-stream-menu-action',
    );
    onFailure?.call();
  }
}

@visibleForTesting
bool debugShouldPinMobileHangUpControlForTesting({
  required bool mobile,
  required bool hasHangUpControl,
  required int scrollableControlCount,
  required double maxDockWidth,
}) {
  return _shouldPinMobileHangUpControl(
    mobile: mobile,
    hasHangUpControl: hasHangUpControl,
    scrollableControlCount: scrollableControlCount,
    maxDockWidth: maxDockWidth,
  );
}

bool _shouldPinMobileHangUpControl({
  required bool mobile,
  required bool hasHangUpControl,
  required int scrollableControlCount,
  required double maxDockWidth,
  double controlExtent = _mobileCallControlButtonExtent,
  double spacing = _defaultCallControlSpacing,
  double horizontalPadding = _callControlRowHorizontalPadding,
}) {
  if (!mobile ||
      !hasHangUpControl ||
      scrollableControlCount <= 0 ||
      maxDockWidth <= 0) {
    return false;
  }

  final controlCount = scrollableControlCount + 1;
  final contentWidth =
      (horizontalPadding * 2) +
      (controlExtent * controlCount) +
      (spacing * (controlCount - 1));
  return contentWidth > maxDockWidth;
}

@visibleForTesting
int debugFocusedCallRailRowsForTesting({
  required int itemCount,
  required double maxWidth,
  required double maxHeight,
  bool mobile = false,
}) {
  return _focusedCallRailMetrics(
    itemCount: itemCount,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    mobile: mobile,
  ).rows;
}

@visibleForTesting
int debugFocusedCallRailColumnsForTesting({
  required int itemCount,
  required double maxWidth,
  required double maxHeight,
  bool mobile = false,
}) {
  return _focusedCallRailMetrics(
    itemCount: itemCount,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    mobile: mobile,
  ).columns;
}

@visibleForTesting
double debugFocusedCallRailHeightForTesting({
  required int itemCount,
  required double maxWidth,
  required double maxHeight,
  bool mobile = false,
}) {
  return _focusedCallRailMetrics(
    itemCount: itemCount,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    mobile: mobile,
  ).height;
}

@visibleForTesting
bool debugShouldMuteHiddenTileLocalPlaybackForTesting({
  required bool tileIsScreenshare,
  required bool targetIsScreenShareAudio,
  required bool hasVisibleSurface,
  required bool streamHidden,
}) {
  if (!_shouldVisibilityMuteTileLocalPlayback(
    tileIsScreenshare: tileIsScreenshare,
    targetIsScreenShareAudio: targetIsScreenShareAudio,
  )) {
    return false;
  }

  return VoipReceiveQualityPolicy.shouldMuteLocalPlaybackForVisibility(
    direction: VoipStreamDirection.incoming,
    hasVisibleSurface: hasVisibleSurface,
    streamHidden: streamHidden,
  );
}

@visibleForTesting
VoipStreamReceivePriority debugResolveCallViewReceivePriorityForTesting({
  required VoipStreamType type,
  required VoipStreamDirection direction,
  required bool hidden,
  required bool focused,
  required bool fullscreen,
  required bool poppedOut,
  required int visibleVideoStreamCount,
  required int visibleScreenshareCount,
}) {
  return _resolveCallViewReceivePriority(
    type: type,
    direction: direction,
    hidden: hidden,
    focused: focused,
    fullscreen: fullscreen,
    poppedOut: poppedOut,
    visibleVideoStreamCount: visibleVideoStreamCount,
    visibleScreenshareCount: visibleScreenshareCount,
  );
}

VoipStreamReceivePriority _resolveCallViewReceivePriority({
  required VoipStreamType type,
  required VoipStreamDirection direction,
  required bool hidden,
  required bool focused,
  required bool fullscreen,
  required bool poppedOut,
  required int visibleVideoStreamCount,
  required int visibleScreenshareCount,
}) {
  return VoipReceiveQualityPolicy.resolve(
    type: type,
    direction: direction,
    hidden: hidden && !fullscreen && !poppedOut,
    focused: focused,
    fullscreen: fullscreen,
    poppedOut: poppedOut,
    visibleVideoStreamCount: visibleVideoStreamCount,
    visibleScreenshareCount: visibleScreenshareCount,
  );
}

@visibleForTesting
bool debugShouldApplyVisibilityMuteForTesting({
  required bool shouldMute,
  required bool mutedByVisibility,
  required bool locallyMuted,
}) {
  return _shouldApplyVisibilityMute(
    shouldMute: shouldMute,
    mutedByVisibility: mutedByVisibility,
    locallyMuted: locallyMuted,
  );
}

bool _shouldVisibilityMuteTileLocalPlayback({
  required bool tileIsScreenshare,
  required bool targetIsScreenShareAudio,
}) {
  return tileIsScreenshare && targetIsScreenShareAudio;
}

bool _shouldApplyVisibilityMute({
  required bool shouldMute,
  required bool mutedByVisibility,
  required bool locallyMuted,
}) {
  return shouldMute && (!mutedByVisibility || !locallyMuted);
}

class _FocusedCallRailMetrics {
  const _FocusedCallRailMetrics({
    required this.columns,
    required this.rows,
    required this.height,
    required this.spacing,
    required this.tileWidth,
    required this.tileHeight,
  });

  final int columns;
  final int rows;
  final double height;
  final double spacing;
  final double tileWidth;
  final double tileHeight;
}

_FocusedCallRailMetrics _focusedCallRailMetrics({
  required int itemCount,
  required double maxWidth,
  required double maxHeight,
  required bool mobile,
}) {
  final spacing = mobile ? 8.0 : 12.0;
  const aspectRatio = 16.0 / 9.0;
  final targetHeight = mobile ? 80.0 : 100.0;
  final boundedTargetHeight = maxHeight.isFinite
      ? max(56.0, min(targetHeight, maxHeight * (mobile ? 0.18 : 0.16)))
      : targetHeight;
  final targetWidth = boundedTargetHeight * aspectRatio;

  if (mobile) {
    return _FocusedCallRailMetrics(
      columns: 1,
      rows: 1,
      height: boundedTargetHeight,
      spacing: spacing,
      tileWidth: targetWidth,
      tileHeight: boundedTargetHeight,
    );
  }

  var columns = 1;
  if (maxWidth.isFinite && maxWidth > 0) {
    columns = ((maxWidth + spacing) / (targetWidth + spacing)).ceil();
  }
  columns = max(1, columns);

  final tileWidth = maxWidth.isFinite && maxWidth > 0
      ? max(0.0, maxWidth - (spacing * (columns - 1))) / columns
      : targetWidth;
  final tileHeight = tileWidth / aspectRatio;
  final rowsNeeded = (max(1, itemCount) / columns).ceil();
  var maxRows = 1;
  if (!mobile && rowsNeeded > 1) {
    final maxRailHeight = maxHeight.isFinite
        ? max(56.0, min(220.0, maxHeight * 0.34))
        : 220.0;
    final twoRowHeight = (tileHeight * 2) + spacing;
    if (twoRowHeight <= maxRailHeight) {
      maxRows = 2;
    }
  }

  final rows = min(rowsNeeded, maxRows);
  final height = (tileHeight * rows) + (spacing * (rows - 1));
  return _FocusedCallRailMetrics(
    columns: columns,
    rows: rows,
    height: height,
    spacing: spacing,
    tileWidth: tileWidth,
    tileHeight: tileHeight,
  );
}

class _TransparentCallControlButton extends StatefulWidget {
  const _TransparentCallControlButton({
    required this.radius,
    required this.icon,
    this.onPressed,
    this.color,
    this.iconColor,
    this.semanticLabel,
    this.semanticHint,
    this.minimumSize,
  });

  final double radius;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? iconColor;
  final String? semanticLabel;
  final String? semanticHint;
  final double? minimumSize;

  @override
  State<_TransparentCallControlButton> createState() =>
      _TransparentCallControlButtonState();
}

class _TransparentCallControlButtonState
    extends State<_TransparentCallControlButton> {
  bool _focused = false;

  void _activate() {
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final foreground =
        widget.iconColor ??
        (enabled ? Colors.white.withAlpha(232) : Colors.white.withAlpha(112));
    final background = enabled
        ? widget.color ?? Colors.black.withAlpha(160)
        : Colors.black.withAlpha(96);
    final visualSize = widget.radius * 2;
    final minimumSize = max(widget.minimumSize ?? visualSize, visualSize);

    final visualButton = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: Border.all(
          color: _focused
              ? Colors.white.withAlpha(150)
              : Colors.white.withAlpha(enabled ? 36 : 20),
          width: _focused ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(72),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        width: visualSize,
        height: visualSize,
        child: widget.icon == null
            ? null
            : Icon(widget.icon, color: foreground, size: widget.radius),
      ),
    );

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      onTap: enabled ? _activate : null,
      child: ExcludeSemantics(
        child: SizedBox(
          width: minimumSize,
          height: minimumSize,
          child: Center(child: visualButton),
        ),
      ),
    );

    if (!enabled) {
      return button;
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              _activate();
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (value) {
            setState(() {
              _focused = value;
            });
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _activate,
            child: button,
          ),
        ),
      ),
    );
  }
}

class _VoiceMenuSummaryRow extends StatelessWidget {
  const _VoiceMenuSummaryRow({required this.title, this.summary});

  final String title;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final summary = this.summary;

    return SizedBox(
      width: _voiceQuickMenuTextWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w400,
              height: 1.15,
              letterSpacing: 0,
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 2),
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceMenuSlider extends StatefulWidget {
  const _VoiceMenuSlider({
    required this.title,
    required this.value,
    required this.max,
    required this.onSettled,
  });

  final String title;
  final double value;
  final double max;
  final FutureOr<void> Function(double value) onSettled;

  @override
  State<_VoiceMenuSlider> createState() => _VoiceMenuSliderState();
}

class _VoiceMenuSliderState extends State<_VoiceMenuSlider> {
  late double value;

  @override
  void initState() {
    super.initState();
    value = widget.value.clamp(0.0, widget.max).toDouble();
  }

  @override
  void didUpdateWidget(covariant _VoiceMenuSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.max != widget.max) {
      value = widget.value.clamp(0.0, widget.max).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 9),
      child: SizedBox(
        width: _voiceQuickMenuWidth - 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w400,
                height: 1.15,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: tiamat.Slider(
                    value: value,
                    min: 0,
                    max: widget.max,
                    onChanged: (newValue) {
                      final rounded = newValue.roundToDouble();
                      setState(() {
                        value = rounded;
                      });
                    },
                    onChangeEnd: (newValue) {
                      final rounded = newValue.roundToDouble();
                      setState(() {
                        value = rounded;
                      });
                      unawaited(
                        _runCallViewVoiceMenuAction(
                          () => widget.onSettled(rounded),
                          actionLabel: '${widget.title} slider',
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${value.round()}%',
                    textAlign: TextAlign.end,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceInputLevelMeter extends StatefulWidget {
  const _VoiceInputLevelMeter({required this.session});

  final VoipSession session;

  @override
  State<_VoiceInputLevelMeter> createState() => _VoiceInputLevelMeterState();
}

class _VoiceInputLevelMeterState extends State<_VoiceInputLevelMeter> {
  late final CallVoiceInputLevelMonitor _levelMonitor;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _level = CallVoiceInputLevelMonitor.microphoneLevelFor(widget.session);
    _levelMonitor = CallVoiceInputLevelMonitor(onLevelChanged: _setInputLevel);
    _levelMonitor.attach(widget.session);
  }

  @override
  void didUpdateWidget(covariant _VoiceInputLevelMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) {
      return;
    }
    _levelMonitor.attach(widget.session);
  }

  @override
  void dispose() {
    _levelMonitor.dispose();
    super.dispose();
  }

  void _setInputLevel(double level) {
    if (!mounted || _level == level) {
      return;
    }

    setState(() {
      _level = level;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const bars = 18;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 10),
      child: SizedBox(
        width: _voiceQuickMenuWidth - 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Input Level',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w400,
                height: 1.15,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var index = 0; index < bars; index++) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: CallView.volumeAnimationDuration,
                      curve: InterGalacticMotion.standardOut,
                      height: 13,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: index < (_level * bars).ceil()
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  if (index != bars - 1) const SizedBox(width: 2.5),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceMenuToggleRow extends StatelessWidget {
  const _VoiceMenuToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      toggled: value,
      enabled: enabled,
      label: title,
      onTap: enabled ? () => onChanged(!value) : null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          child: SizedBox(
            width: _voiceQuickMenuWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 7, 10, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: enabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurface.withAlpha(96),
                        fontWeight: FontWeight.w400,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Checkbox(
                    value: value,
                    onChanged: enabled
                        ? (next) => onChanged(next ?? !value)
                        : null,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallTileData {
  const _CallTileData({
    required this.primaryStream,
    required this.tileId,
    this.audioStream,
    this.volumeStream,
  });

  final VoipStream primaryStream;
  final String tileId;
  final VoipStream? audioStream;
  final VoipStream? volumeStream;

  String get userId => primaryStream.streamUserId;
  bool get hasVisual =>
      primaryStream.type == VoipStreamType.video ||
      primaryStream.type == VoipStreamType.screenshare;
  bool get isScreenshare => primaryStream.type == VoipStreamType.screenshare;
}

class _VisibilityAudioTarget {
  const _VisibilityAudioTarget({
    required this.stream,
    required this.hasVisibleSurface,
    required this.streamHidden,
  });

  final MatrixLivekitVoipStream stream;
  final bool hasVisibleSurface;
  final bool streamHidden;
}

class _CallSignalStrengthIndicator extends StatelessWidget {
  const _CallSignalStrengthIndicator({required this.participant});

  final CallHealthParticipantSnapshot participant;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeBars = participant.connectionQuality.signalStrengthBars;
    final activeColor = switch (participant.connectionQuality) {
      CallConnectionQuality.excellent ||
      CallConnectionQuality.good => colorScheme.primary,
      CallConnectionQuality.fair => colorScheme.tertiary,
      CallConnectionQuality.poor ||
      CallConnectionQuality.lost => colorScheme.error,
      CallConnectionQuality.unknown => colorScheme.onSurfaceVariant,
    };
    final inactiveColor = colorScheme.onSurface.withAlpha(70);
    final tooltip =
        '${participant.label}: ${participant.connectionStatusLabel}';
    const heights = <double>[5, 8, 11, 14];

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: 'Connection signal for ${participant.label}',
        value: participant.connectionStatusLabel,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(225),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withAlpha(120),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(45),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < heights.length; index++) ...[
                    if (index > 0) const SizedBox(width: 2),
                    AnimatedContainer(
                      duration: InterGalacticMotion.duration(
                        context,
                        InterGalacticMotion.shortEmphasis,
                      ),
                      curve: InterGalacticMotion.standardOut,
                      width: 3,
                      height: heights[index],
                      decoration: BoxDecoration(
                        color: index < activeBars ? activeColor : inactiveColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiverProbeRenderSurface extends StatefulWidget {
  const _ReceiverProbeRenderSurface({
    required this.session,
    required this.renderer,
  });

  final MatrixLivekitVoipSession session;
  final rtc.RTCVideoRenderer? renderer;

  @override
  State<_ReceiverProbeRenderSurface> createState() =>
      _ReceiverProbeRenderSurfaceState();
}

class _ReceiverProbeRenderSurfaceState
    extends State<_ReceiverProbeRenderSurface> {
  bool _textureReadyRecorded = false;

  @override
  void initState() {
    super.initState();
    widget.session.setInProcessReceiverProbeRendererVisible(true);
  }

  @override
  void didUpdateWidget(_ReceiverProbeRenderSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.setInProcessReceiverProbeRendererVisible(false);
      widget.session.setInProcessReceiverProbeRendererVisible(true);
    }
    if (oldWidget.session != widget.session ||
        oldWidget.renderer != widget.renderer) {
      _textureReadyRecorded = false;
    }
  }

  @override
  void dispose() {
    widget.session.setInProcessReceiverProbeRendererVisible(false);
    super.dispose();
  }

  void _recordTextureReady() {
    widget.session.recordInProcessReceiverProbeTextureReady(
      source: 'in_process_receiver_probe_rtc_video_view',
    );
  }

  void _recordUiPaint() {
    widget.session.recordInProcessReceiverProbeUiPaint(
      source: 'in_process_receiver_probe_custom_painter',
    );
  }

  Widget _buildInstrumentedRenderer(rtc.RTCVideoRenderer renderer) {
    if (!_textureReadyRecorded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _textureReadyRecorded) {
          return;
        }
        _textureReadyRecorded = true;
        _recordTextureReady();
      });
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        rtc.RTCVideoView(
          renderer,
          objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        ),
        CustomPaint(
          painter: _ReceiverProbePaintObserver(onPainted: _recordUiPaint),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final renderer = widget.renderer;
    final size = Layout.mobile ? const Size(144, 81) : const Size(240, 135);
    final colorScheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline.withAlpha(72)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: renderer == null
                ? const SizedBox.expand()
                : _buildInstrumentedRenderer(renderer),
          ),
        ),
      ),
    );
  }
}

class _ReceiverProbePaintObserver extends CustomPainter {
  _ReceiverProbePaintObserver({required this.onPainted});

  final VoidCallback onPainted;

  @override
  void paint(Canvas canvas, Size size) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onPainted());
  }

  @override
  bool shouldRepaint(_ReceiverProbePaintObserver oldDelegate) {
    return oldDelegate.onPainted != onPainted;
  }
}

/// Transient per-call view state.
///
/// Keyed on the session *object* (see `_callViewLocalStateKeyFor`), so a rejoin
/// starts clean: which tiles are hidden and which remote screen shares have
/// been revealed are decisions about this call, not standing preferences.
/// Per-participant volumes are standing preferences and deliberately do **not**
/// live here - see [CallParticipantAudioOverridesStore].
class _CallViewLocalState {
  final Set<String> hiddenUserIds = {};
  final Set<String> hiddenScreenshareStreamIds = {};
  final Set<String> shownScreenshareStreamIds = {};
  final Set<String> autoHiddenLocalScreenshareStreamIds = {};
  final Set<String> visibilityMutedAudioStreamIds = {};
}

class _StreamTestDialogConfig {
  const _StreamTestDialogConfig({
    required this.presets,
    required this.duration,
    required this.warmup,
    this.windowsCaptureBackendMode,
    this.windowsCaptureBackendModes,
    this.windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    this.windowsWindowGdiCaptureModes,
    this.nativeFramePacingEnabled = false,
    this.dummyNv12LiveSender = false,
    this.captureTestTargetEnabled = false,
    this.captureTestTargetWidth = 1920,
    this.captureTestTargetHeight = 1080,
    this.captureTestTargetMode = 'windowed',
    this.captureTestTargetScene = 'gameplay',
    this.captureTestTargetFps = '60',
    this.automationSourceProcessId,
    this.automationSourceTitle,
    this.publicationHandoffMaxWidth,
    this.publicationHandoffMaxHeight,
    this.publicationHandoffTargetFps,
    this.receiverProbe = const StreamTestReceiverProbeConfig(),
    this.gameCaptureProbeEnabled = false,
    this.gameCaptureProofFrames = 0,
  });

  final List<ScreenShareProfileConfig> presets;
  final Duration duration;
  final Duration warmup;
  final WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
  final List<WindowsScreenCaptureBackendMode?>? windowsCaptureBackendModes;
  final WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode;
  final List<WindowsWindowGdiCaptureMode?>? windowsWindowGdiCaptureModes;
  final bool nativeFramePacingEnabled;
  final bool dummyNv12LiveSender;
  final bool captureTestTargetEnabled;
  final int captureTestTargetWidth;
  final int captureTestTargetHeight;
  final String captureTestTargetMode;
  final String captureTestTargetScene;
  final String captureTestTargetFps;
  final int? automationSourceProcessId;
  final String? automationSourceTitle;
  final int? publicationHandoffMaxWidth;
  final int? publicationHandoffMaxHeight;
  final int? publicationHandoffTargetFps;
  final StreamTestReceiverProbeConfig receiverProbe;
  final bool gameCaptureProbeEnabled;
  final int gameCaptureProofFrames;

  GameCaptureTestTargetConfig get captureTestTargetConfig {
    return GameCaptureTestTargetConfig(
      enabled: captureTestTargetEnabled,
      width: captureTestTargetWidth,
      height: captureTestTargetHeight,
      windowMode: captureTestTargetMode,
      scene: captureTestTargetScene,
      fps: captureTestTargetFps,
      title: 'Inter Galactic Capture Target',
    );
  }
}

class _RnnoiseDiagnosticBatchScenario {
  const _RnnoiseDiagnosticBatchScenario({
    required this.scenario,
    required this.hookModePreference,
    required this.noiseSuppressionEnabled,
  });

  final String scenario;
  final String hookModePreference;
  final bool noiseSuppressionEnabled;

  String get label => NoiseSuppressionTapOrderScenario.labelFor(scenario);
}

class _RnnoiseDiagnosticBatchResult {
  const _RnnoiseDiagnosticBatchResult({
    required this.completed,
    required this.writtenFiles,
    required this.canceled,
    required this.failures,
  });

  final int completed;
  final int writtenFiles;
  final bool canceled;
  final List<String> failures;

  String get summary {
    final base = canceled
        ? 'Canceled after $completed capture(s); wrote $writtenFiles WAV files.'
        : 'Completed $completed capture(s); wrote $writtenFiles WAV files.';
    if (failures.isEmpty) {
      return base;
    }
    return '$base ${failures.length} scenario(s) reported no files or errors.';
  }
}

const List<_RnnoiseDiagnosticBatchScenario>
_rnnoiseTapOrderBatchScenarios = <_RnnoiseDiagnosticBatchScenario>[
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseOffDefault,
    // The off/default comparison still needs the native hook installed so the
    // tap-order WAVs prove what WebRTC hands to the hook before RNNoise runs.
    hookModePreference: 'identity',
    noiseSuppressionEnabled: false,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.identitySameConstraints,
    hookModePreference: 'identity',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseSameConstraints,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseNoVolume,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseNo48k,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseAgcOn,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseAgcOff,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseNsOff,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseAecOff,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.identityMinimalFrontend,
    hookModePreference: 'identity',
    noiseSuppressionEnabled: true,
  ),
  _RnnoiseDiagnosticBatchScenario(
    scenario: NoiseSuppressionTapOrderScenario.rnnoiseMinimalFrontend,
    hookModePreference: 'rnnoise',
    noiseSuppressionEnabled: true,
  ),
];

class _CallViewStreamTestTarget implements StreamTestTarget {
  _CallViewStreamTestTarget({required this.session, required this.source});

  final MatrixLivekitVoipSession session;
  final ScreenCaptureSource source;
  final List<Map<String, Object?>> _receiverProbeEvents = [];
  StreamSubscription<MatrixLivekitReceiverProbeEvent>? _receiverProbeEventsSub;
  DateTime? _receiverProbeStartedAt;
  StreamTestReceiverProbeMode _receiverProbeMode =
      StreamTestReceiverProbeMode.decodeOnly;
  bool _receiverProbeInProcess = true;

  @override
  String get label => session.roomName;

  @override
  String get roomId => session.roomId;

  @override
  bool get isSharingScreen => session.isSharingScreen;

  @override
  Future<void> startPreset(
    ScreenShareProfileConfig profile, {
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    bool nativeFramePacingEnabled = false,
    bool dummyNv12LiveSender = false,
  }) {
    return session.setScreenShareForStreamTest(
      source,
      profile,
      windowsCaptureBackendMode: windowsCaptureBackendMode,
      windowsCaptureDirtyRegionMode: windowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureMode: windowsWindowGdiCaptureMode,
      nativeFramePacingEnabled: nativeFramePacingEnabled,
      dummyNv12LiveSender: dummyNv12LiveSender,
    );
  }

  @override
  Future<void> stopShare() => session.stopScreenshare();

  @override
  Future<VoipCallDiagnosticsSnapshot> collectDiagnostics() {
    return session.collectStreamTestDiagnostics();
  }

  @override
  Future<void> startReceiverProbe(StreamTestReceiverProbeConfig config) async {
    await _cancelCallViewReceiverProbeSubscription(_receiverProbeEventsSub);
    _receiverProbeEventsSub = null;
    _receiverProbeEvents.clear();
    _receiverProbeMode = config.mode;
    _receiverProbeInProcess = config.inProcess;
    _receiverProbeStartedAt = DateTime.now();
    if (!config.inProcess) {
      final controlPipe = config.externalControlPipe?.trim();
      if (controlPipe == null || controlPipe.isEmpty) {
        throw StateError(
          'External receiver probe requires a protected control pipe.',
        );
      }
      await session.writeReceiverProbeCredentialsToPipe(
        controlPipe: controlPipe,
      );
      return;
    }

    _receiverProbeEventsSub = session.inProcessReceiverProbeEvents.listen((
      event,
    ) {
      _receiverProbeEvents.add(event.toJson());
    });
    try {
      if (config.mode == StreamTestReceiverProbeMode.localPreview) {
        await session.setLocalPreviewProbeEnabled(true);
        if (!session.isLocalPreviewProbeEnabled) {
          final startError = session.localPreviewProbeError;
          throw StateError(
            'Local preview probe failed to start: '
            '${startError == null || startError.isEmpty ? 'unknown error' : startError}',
          );
        }
        return;
      }
      await session.setInProcessReceiverProbeEnabled(
        true,
        mode: _matrixReceiverProbeMode(config.mode),
      );
      if (!session.isInProcessReceiverProbeEnabled) {
        final startError = session.inProcessReceiverProbeError;
        throw StateError(
          'In-process receiver probe failed to start: '
          '${startError == null || startError.isEmpty ? 'unknown error' : startError}',
        );
      }
    } catch (_) {
      await _cancelCallViewReceiverProbeSubscription(_receiverProbeEventsSub);
      _receiverProbeEventsSub = null;
      rethrow;
    }
  }

  @override
  Future<StreamTestReceiverProbeResult> stopReceiverProbe() async {
    final startedAt = _receiverProbeStartedAt ?? DateTime.now();
    if (!_receiverProbeInProcess) {
      return StreamTestReceiverProbeResult.externalHandoff(
        mode: _receiverProbeMode,
        startedAt: startedAt,
        endedAt: DateTime.now(),
      );
    }
    final snapshot =
        _receiverProbeMode == StreamTestReceiverProbeMode.localPreview
        ? session.localPreviewProbeSnapshot
        : session.inProcessReceiverProbeSnapshot?.toJson();
    try {
      if (_receiverProbeMode == StreamTestReceiverProbeMode.localPreview) {
        await session.setLocalPreviewProbeEnabled(false);
      } else {
        await session.setInProcessReceiverProbeEnabled(false);
      }
    } finally {
      await _cancelCallViewReceiverProbeSubscription(_receiverProbeEventsSub);
      _receiverProbeEventsSub = null;
    }
    return StreamTestReceiverProbeResult.fromEvents(
      mode: _receiverProbeMode,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      events: _receiverProbeEvents
          .map((event) => Map<String, Object?>.from(event))
          .toList(growable: false),
      snapshot: snapshot == null ? null : Map<String, Object?>.from(snapshot),
    );
  }
}

MatrixLivekitReceiverProbeMode _matrixReceiverProbeMode(
  StreamTestReceiverProbeMode mode,
) {
  return switch (mode) {
    StreamTestReceiverProbeMode.decodeOnly =>
      MatrixLivekitReceiverProbeMode.decodeOnly,
    StreamTestReceiverProbeMode.render => MatrixLivekitReceiverProbeMode.render,
    StreamTestReceiverProbeMode.localPreview => throw ArgumentError(
      'local-preview uses MatrixLivekitLocalPreviewProbeController',
    ),
  };
}

class CallView extends StatefulWidget {
  const CallView(
    this.currentSession, {
    this.setMicrophoneMute,
    this.microphoneMuteIntent,
    this.pickScreenshareSource,
    this.stopScreenshare,
    this.pickCamera,
    this.disableCamera,
    this.hangUp,
    this.declineCall,
    this.acceptCall,
    this.showSessionPopoutButton = true,
    this.transparentBackground = false,
    this.forceControlsVisible = false,
    this.suppressControls = false,
    this.surfaceMode = CallSurfaceMode.inRoom,
    super.key,
  });
  final VoipSession currentSession;

  static const Duration volumeAnimationDuration = Duration(milliseconds: 500);

  final Future<void> Function(bool)? setMicrophoneMute;

  /// What the user last ASKED the microphone to be, which the mute button must
  /// toggle away from.
  ///
  /// `currentSession.isMicrophoneMuted` is the applied state and lags the
  /// coalescing drain in `CallManager`. Two quick presses both read the
  /// pre-drain value, so the second re-requests the value already queued, the
  /// manager absorbs it as a duplicate, and the button appears to swallow the
  /// press. Null falls back to the session, which is correct for any surface
  /// with no manager behind it.
  final bool Function()? microphoneMuteIntent;

  final Future<void> Function()? pickScreenshareSource;
  final Future<void> Function()? stopScreenshare;
  final Future<void> Function()? pickCamera;
  final Future<void> Function()? disableCamera;
  final Future<void> Function()? hangUp;
  final Future<void> Function()? declineCall;
  final Future<void> Function()? acceptCall;
  final bool showSessionPopoutButton;
  final bool transparentBackground;
  final bool forceControlsVisible;
  final bool suppressControls;
  final CallSurfaceMode surfaceMode;

  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  static const List<WindowsScreenCaptureBackendMode?>
  _streamTestWindowsCaptureBackendCompareModes = [
    null,
    ...streamTestWindowsCaptureBackendModes,
  ];

  static const int _maxPersistedLocalStateEntries = 12;
  static final Map<String, _CallViewLocalState> _localStateBySession = {};

  StreamSubscription? sub;
  StreamSubscription? _diagnosticsSub;
  StreamSubscription? _participantsSub;
  StreamSubscription<UserActivity?>? _activitySub;
  StreamSubscription? _presenceSub;
  StreamSubscription? _activityRoomSub;
  StreamSubscription<bool>? _callManagerDeafenSub;
  final MenuController _voiceMenuController = MenuController();
  final MenuController _voiceInputDeviceMenuController = MenuController();
  final MenuController _voiceInputProfileMenuController = MenuController();
  final MenuController _voiceOutputDeviceMenuController = MenuController();
  MenuController? _openVoiceSubmenuController;
  List<rtc.MediaDeviceInfo> _microphoneDevices = const [];
  List<rtc.MediaDeviceInfo> _speakerDevices = const [];
  bool _voiceDevicesLoading = false;
  String? _voiceDevicesError;
  bool _voiceMenuOpen = false;
  bool isMouseHovering = false;
  bool showEqualTileLayout = true;
  bool _diagnosticsOverlayVisible = true;
  static const Duration _localScreensharePreviewDuration = Duration(
    seconds: 30,
  );
  static const Duration _streamTestAutoSelectTimeout = Duration(seconds: 8);

  late String _persistedLocalStateKey;
  late _CallViewLocalState _localState;
  late final CallLocalScreenshareAutoHideController
  _localScreenshareAutoHideController = CallLocalScreenshareAutoHideController(
    previewDuration: _localScreensharePreviewDuration,
  );
  final Set<String> _restoredScreenshareAudioVolumeKeys = {};
  bool _streamTestRunning = false;
  String? _streamTestProgressLabel;
  StreamTestRunResult? _lastStreamTestResult;
  StreamTestReportWriteResult? _lastStreamTestReportWriteResult;
  Timer? _streamTestAutomationPollTimer;
  Timer? _pipControlsAutoHideTimer;
  bool _streamTestAutomationPollInFlight = false;
  bool _pipControlsVisible = false;
  final GlobalKey _mobileCallSurfaceKey = GlobalKey(
    debugLabel: 'mobile-call-pip-surface',
  );

  String? focusedTileId;
  final Set<String> _fullscreenTileIds = <String>{};
  final Set<String> _connectionSignalHoveredTileIds = <String>{};
  UserActivity? _localGameActivity;
  final Map<String, UserPresence> _participantPresenceByUserId = {};
  final Set<String> _presenceRequestsInFlight = {};
  Set<String>? _trackedRemoteParticipantUserIdsCache;
  String? _trackedRemoteParticipantUserIdsSignature;

  /// The call's room, or null while it is not loaded on this client.
  ///
  /// Nullable rather than `late Room`. `didUpdateWidget` already treated the
  /// same `getRoom()` lookup as nullable, but `initState` force-unwrapped it -
  /// so a `CallView` first inserted before the room had been loaded threw a
  /// null-check error out of `initState` and the whole call surface failed to
  /// build. Both paths now handle the miss identically; the room is only used
  /// for decoration (avatar, name, colour) and for keying screen-share audio
  /// volume preferences, none of which is worth failing a live call over.
  Room? room;

  /// [room], re-resolved from the client if the insert-time lookup missed.
  ///
  /// [room] is assigned only in `initState` and `didUpdateWidget`, so a
  /// `CallView` inserted before the room finished loading kept a null [room]
  /// for the widget's whole life unless the session object changed. Every
  /// preference keyed on the room's local id then silently no-opped for that
  /// call: screen-share audio volumes were never restored and never persisted,
  /// with no error anywhere - the volume applied, only the memory of it was
  /// lost. `_voipRoomComponent` already re-resolves per access, so the lookup
  /// is cheap enough to retry on the miss path.
  Room? get _resolvedRoom {
    final resolved = widget.currentSession.client.getRoom(
      widget.currentSession.roomId,
    );
    final cached = room;
    // The cache must be validated, not merely null-checked. `didUpdateWidget`
    // assigns `room` only when the new lookup succeeds, so a session swap into
    // a room that has not loaded yet leaves the PREVIOUS room in the field -
    // and `localId` includes the client identifier, so returning it would key
    // screen-share audio volume under the wrong room, and under the wrong
    // account when the swap crossed clients. Prefer the live lookup and fall
    // back to the cache only when it still names the same room.
    if (resolved != null) {
      room = resolved;
      return resolved;
    }
    if (cached != null &&
        cached.identifier == widget.currentSession.roomId &&
        cached.client.identifier == widget.currentSession.client.identifier) {
      return cached;
    }
    return null;
  }

  /// User IDs whose camera video is hidden locally.
  Set<String> get _hiddenUserIds => _localState.hiddenUserIds;

  /// Stable screenshare tile IDs explicitly hidden by the local user from the
  /// context menu.
  Set<String> get _hiddenScreenshareStreamIds =>
      _localState.hiddenScreenshareStreamIds;

  /// Stable screenshare tile IDs that the local user has explicitly chosen to
  /// view.  All remote screenshares default to hidden (blank panel) until the
  /// user taps the eye-toggle on that tile.
  Set<String> get _shownScreenshareStreamIds =>
      _localState.shownScreenshareStreamIds;

  Set<String> get _autoHiddenLocalScreenshareStreamIds =>
      _localState.autoHiddenLocalScreenshareStreamIds;

  Set<String> get _visibilityMutedAudioStreamIds =>
      _localState.visibilityMutedAudioStreamIds;

  /// Rides out single-frame gaps in screenshare-audio tile visibility, so a
  /// tile that momentarily leaves the tile list does not chop the audio. See
  /// [ScreenshareAudioVisibilityGrace] for why the grace timestamp must only
  /// ever be written from a real sighting.
  final ScreenshareAudioVisibilityGrace _screenshareAudioVisibilityGrace =
      ScreenshareAudioVisibilityGrace();

  /// Forces one re-evaluation when a grace window expires, so a tile that is
  /// genuinely gone still gets muted even if nothing else rebuilds the view.
  Timer? _screenshareAudioGraceTimer;

  /// Inputs for the deferred media-control pass. See [_scheduleMediaControl].
  List<_CallTileData>? _pendingMediaControlTiles;
  _CallTileData? _pendingMediaControlFocusedTile;
  bool _mediaControlPassScheduled = false;

  CallParticipantAudioOverrides get _participantAudioVolumeOverrides =>
      CallParticipantAudioOverridesStore.forSession(widget.currentSession);

  @override
  void initState() {
    super.initState();
    _bindPersistedLocalState();
    _diagnosticsOverlayVisible =
        preferences.callStreamStatsOverlayVisible.value;
    _localGameActivity = activityService.currentGameActivity;
    _activitySub = activityService.onActivityChanged.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localGameActivity = activityService.currentGameActivity;
      });
    });
    _callManagerDeafenSub = clientManager?.callManager.onDeafenChanged.listen((
      _,
    ) {
      if (!mounted) {
        return;
      }
      // Unconditional. This used to rebuild only when a deafen indicator was
      // actually on screen, which was a reasonable saving while deafen was
      // purely cosmetic here. It is not: `_syncHiddenTileAudioMute` runs from
      // the build path and is now the *only* thing that makes remote
      // screen-share audio audible again after un-deafen - CallManager
      // deliberately does not un-mute it, because that mute belongs to the
      // tile-visibility policy. Without a rebuild the audio stayed silent
      // until some unrelated event happened to rebuild the view.
      setState(() {});
    });

    room = widget.currentSession.client.getRoom(widget.currentSession.roomId);
    _bindCurrentSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncLocalScreenshareAutoHideTimers();
      unawaited(
        _runCallViewStreamTestAction(
          _pollStreamTestAutomationCommand,
          actionLabel: 'stream-test automation poll',
        ),
      );
    });
    if ((BuildConfig.DEBUG || kDebugMode) && PlatformUtils.isWindows) {
      _streamTestAutomationPollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(
          _runCallViewStreamTestAction(
            _pollStreamTestAutomationCommand,
            actionLabel: 'stream-test automation poll',
          ),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant CallView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.currentSession, widget.currentSession)) {
      return;
    }

    // Every call site builds `CallView` positionally with no key, so leaving
    // and rejoining the same room hands this element a *different* session
    // object. Without rebinding, every listener stays attached to the dead
    // session and the surface silently stops updating.
    _cancelSessionBoundSubscriptions();
    final nextRoom = widget.currentSession.client.getRoom(
      widget.currentSession.roomId,
    );
    if (nextRoom != null) {
      room = nextRoom;
    }
    _participantPresenceByUserId.clear();
    _presenceRequestsInFlight.clear();
    _trackedRemoteParticipantUserIdsCache = null;
    _trackedRemoteParticipantUserIdsSignature = null;
    _restoredScreenshareAudioVolumeKeys.clear();
    _connectionSignalHoveredTileIds.clear();
    _fullscreenTileIds.clear();
    // Session-scoped like everything above it. These hold the OLD session's
    // tiles for a media pass queued to a post-frame callback; if the swap lands
    // after that callback is scheduled but before it runs, the pass applies old
    // tiles while the mute sync reads the new session's streams.
    _pendingMediaControlTiles = null;
    _pendingMediaControlFocusedTile = null;
    focusedTileId = null;
    _bindPersistedLocalState();
    _bindCurrentSession();
    setState(() {});
  }

  void _bindPersistedLocalState() {
    _persistedLocalStateKey = _callViewLocalStateKeyFor(widget.currentSession);
    if (!_localStateBySession.containsKey(_persistedLocalStateKey) &&
        _localStateBySession.length >= _maxPersistedLocalStateEntries) {
      _localStateBySession.remove(_localStateBySession.keys.first);
    }
    _localState = _localStateBySession.putIfAbsent(
      _persistedLocalStateKey,
      _CallViewLocalState.new,
    );
  }

  void _bindCurrentSession() {
    sub = widget.currentSession.onStateChanged.listen((event) {
      if (!mounted) {
        return;
      }
      if (widget.currentSession.state == VoipState.ended) {
        _discardPersistedLocalState();
      }
      _syncLocalScreenshareAutoHideTimers();
      _syncRemoteParticipantPresence();
      setState(() {});
    });

    _initRemoteParticipantPresence();
    // Rebuild tiles when a remote participant's shared rich activity changes.
    _activityRoomSub = _activityRoomComponent?.onActivitiesChanged.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _diagnosticsSub = widget.currentSession.onDiagnosticsChanged.listen((
      event,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });

    // Listen for participant-list changes (e.g. when an admin removes someone
    // from the call) so we can rebuild tiles immediately.
    _participantsSub = _voipRoomComponent?.onParticipantsChanged.listen((_) {
      if (!mounted) {
        return;
      }
      _syncLocalScreenshareAutoHideTimers();
      _syncRemoteParticipantPresence();
      setState(() {});
    });
  }

  /// Cancels only the subscriptions bound to `widget.currentSession`. The
  /// activity-service and call-manager subscriptions outlive a session swap.
  void _cancelSessionBoundSubscriptions() {
    final pendingSubscriptions = <StreamSubscription?>[
      sub,
      _diagnosticsSub,
      _participantsSub,
      _presenceSub,
      _activityRoomSub,
    ];
    sub = null;
    _diagnosticsSub = null;
    _participantsSub = null;
    _presenceSub = null;
    _activityRoomSub = null;
    for (final subscription in pendingSubscriptions) {
      unawaited(_cancelCallViewSubscription(subscription));
    }
  }

  @override
  void dispose() {
    final pendingSubscriptions = <StreamSubscription?>[
      sub,
      _diagnosticsSub,
      _participantsSub,
      _activitySub,
      _presenceSub,
      _activityRoomSub,
      _callManagerDeafenSub,
    ];
    sub = null;
    _diagnosticsSub = null;
    _participantsSub = null;
    _activitySub = null;
    _presenceSub = null;
    _activityRoomSub = null;
    _callManagerDeafenSub = null;
    for (final subscription in pendingSubscriptions) {
      unawaited(_cancelCallViewSubscription(subscription));
    }
    _streamTestAutomationPollTimer?.cancel();
    _pipControlsAutoHideTimer?.cancel();
    _screenshareAudioGraceTimer?.cancel();
    _screenshareAudioGraceTimer = null;
    _voiceMenuController.close();
    _localScreenshareAutoHideController.dispose();
    if (widget.currentSession.state == VoipState.ended) {
      _discardPersistedLocalState();
    }
    super.dispose();
  }

  static String _callViewLocalStateKeyFor(VoipSession session) {
    final stableSessionId = session.sessionId.trim().isEmpty
        ? 'no-session-id'
        : session.sessionId.trim();
    return '${session.client.identifier}:${session.roomId}:'
        '$stableSessionId:${identityHashCode(session)}';
  }

  void _discardPersistedLocalState() {
    _localStateBySession.remove(_persistedLocalStateKey);
  }

  void _initRemoteParticipantPresence() {
    final presenceComponent = widget.currentSession.client
        .getComponent<UserPresenceComponent>();
    if (presenceComponent == null) {
      return;
    }

    _presenceSub = presenceComponent.onPresenceChanged.listen((event) {
      if (!mounted || !_isTrackedRemoteParticipant(event.$1)) {
        return;
      }

      setState(() {
        _participantPresenceByUserId[event.$1] = event.$2;
      });
    });
    _syncRemoteParticipantPresence();
  }

  void _syncRemoteParticipantPresence() {
    final presenceComponent = widget.currentSession.client
        .getComponent<UserPresenceComponent>();
    if (presenceComponent == null) {
      return;
    }

    final trackedUserIds = _trackedRemoteParticipantUserIds();
    _participantPresenceByUserId.removeWhere(
      (userId, _) => !trackedUserIds.contains(userId),
    );
    _presenceRequestsInFlight.removeWhere(
      (userId) => !trackedUserIds.contains(userId),
    );

    for (final userId in trackedUserIds) {
      if (_participantPresenceByUserId.containsKey(userId) ||
          !_presenceRequestsInFlight.add(userId)) {
        continue;
      }

      unawaited(_loadRemoteParticipantPresence(presenceComponent, userId));
    }
  }

  Set<String> _trackedRemoteParticipantUserIds() {
    final selfId = widget.currentSession.client.self?.identifier;
    final streamSignatures =
        widget.currentSession.streams
            .map((stream) => '${stream.streamId}:${stream.streamUserId}')
            .toList(growable: false)
          ..sort();
    final signature = '${selfId ?? ''}|${streamSignatures.join('|')}';
    if (_trackedRemoteParticipantUserIdsSignature == signature) {
      return _trackedRemoteParticipantUserIdsCache ?? const <String>{};
    }

    final userIds = widget.currentSession.streams
        .map((stream) => stream.streamUserId.trim())
        .where((userId) => userId.isNotEmpty && userId != selfId)
        .toSet();
    _trackedRemoteParticipantUserIdsSignature = signature;
    _trackedRemoteParticipantUserIdsCache = Set.unmodifiable(userIds);
    return _trackedRemoteParticipantUserIdsCache!;
  }

  bool _isTrackedRemoteParticipant(String userId) {
    return _trackedRemoteParticipantUserIds().contains(userId);
  }

  Future<void> _loadRemoteParticipantPresence(
    UserPresenceComponent presenceComponent,
    String userId,
  ) async {
    try {
      final presence = await presenceComponent.getUserPresence(userId);
      if (!mounted || !_isTrackedRemoteParticipant(userId)) {
        return;
      }

      setState(() {
        _participantPresenceByUserId[userId] = presence;
      });
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to load call participant presence',
        category: LogCategory.matrix,
        source: 'call-presence',
      );
    } finally {
      _presenceRequestsInFlight.remove(userId);
    }
  }

  // ── Volume / remove helpers ───────────────────────────────────────────────

  /// Returns the `MatrixVoipRoomComponent` for the current room, or null if
  /// the room/session doesn't use the LiveKit/Matrix VoIP stack.
  MatrixVoipRoomComponent? get _voipRoomComponent {
    final r = widget.currentSession.client.getRoom(
      widget.currentSession.roomId,
    );
    final comp = r?.getComponent<VoipRoomComponent>();
    if (comp is MatrixVoipRoomComponent) return comp;
    return null;
  }

  /// The room component that carries participants' shared rich activity, or
  /// null when the room does not use the Matrix VoIP stack.
  ActivityRoomComponent? get _activityRoomComponent {
    return widget.currentSession.client
        .getRoom(widget.currentSession.roomId)
        ?.getComponent<ActivityRoomComponent>();
  }

  bool get _canRemoveParticipants =>
      _voipRoomComponent?.canRemoveParticipants ?? false;

  /// Local visibility state must outlive LiveKit publication SID refreshes.
  /// Windows fallback/profile changes can republish a screenshare while the
  /// user still considers it the same visible tile.
  String _tileIdForStream(VoipStream stream) {
    return callStreamPopoutIdForStream(stream);
  }

  void _markLocalScreenshareAutoHideHandled(String tileId) {
    _localScreenshareAutoHideController.markHandled(
      tileId,
      autoHiddenTileIds: _autoHiddenLocalScreenshareStreamIds,
    );
  }

  double get _defaultParticipantAudioVolume =>
      Preferences.voipSpeakerVolumeToLocalPlayback(
        preferences.voipSpeakerVolume.value,
      );

  bool _supportsLocalPlaybackVolume(VoipStream? stream) {
    return stream is LocalPlaybackVolumeStream &&
        (stream as LocalPlaybackVolumeStream).hasLocalPlaybackAudio;
  }

  VoipStream? _volumeTargetForTile(_CallTileData tile) {
    if (_supportsLocalPlaybackVolume(tile.volumeStream)) {
      return tile.volumeStream;
    }

    final primaryStream = tile.primaryStream;
    if (_supportsLocalPlaybackVolume(primaryStream)) {
      return primaryStream;
    }

    return null;
  }

  VoipStream? _preparedVolumeTargetForTile(_CallTileData tile) {
    final target = _volumeTargetForTile(tile);
    final visibilityMuteTarget =
        target is MatrixLivekitVoipStream &&
        _shouldVisibilityMuteTileLocalPlayback(
          tileIsScreenshare: tile.isScreenshare,
          targetIsScreenShareAudio: target.isScreenShareAudio,
        );
    if (target != null &&
        (!_isTileVideoHidden(tile) || !visibilityMuteTarget)) {
      _restoreParticipantAudioVolume(target);
    }
    return target;
  }

  void _rememberParticipantAudioVolume(VoipStream stream, double volume) {
    _participantAudioVolumeOverrides.remember(
      stream,
      volume: volume,
      defaultVolume: _defaultParticipantAudioVolume,
      isMicrophoneAudio:
          CallParticipantAudioOverridesStore.isParticipantMicrophoneAudio(
            stream,
          ),
    );
  }

  void _restoreParticipantAudioVolume(VoipStream stream) {
    unawaited(
      _participantAudioVolumeOverrides.restore(
        stream,
        isMicrophoneAudio:
            CallParticipantAudioOverridesStore.isParticipantMicrophoneAudio(
              stream,
            ),
        onError: (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content:
                'call_participant_audio_restore '
                'result=recovered_error',
            category: LogCategory.webrtc,
            source: 'call-participant-audio',
          );
        },
      ),
    );
  }

  bool _isServerLoopbackStream(VoipStream stream) {
    return stream is MatrixLivekitVoipStream &&
        stream.participantIdentity.contains('_rnnoise_loopback');
  }

  /// Set the local playback volume for the tile's selected audio stream.
  void _setTileVolume(_CallTileData tile, double volume) {
    final target = _volumeTargetForTile(tile);
    if (target == null) {
      return;
    }

    final volumeTarget = target as LocalPlaybackVolumeStream;
    final clampedVolume = Preferences.clampScreenShareAudioVolume(volume);
    unawaited(
      CallLocalPlaybackOperationGuard.runAsync(
        operation: () => volumeTarget.setLocalVolume(clampedVolume),
        content: 'Recovered call view local playback volume failure',
        source: 'call-view-local-playback',
      ),
    );
    if (target is MatrixLivekitVoipStream && target.isScreenShareAudio) {
      // The preference is keyed by the room's local id, so an unloaded room
      // has nothing to key it by. The volume is still applied above; only the
      // persistence is skipped, which is strictly better than failing the
      // whole surface for a decoration lookup.
      final roomLocalId = _resolvedRoom?.localId;
      if (roomLocalId == null) {
        return;
      }
      unawaited(
        CallPreferenceOperationGuard.run(
          operation: () => preferences.setScreenShareAudioVolume(
            roomLocalId: roomLocalId,
            streamUserId: target.streamUserId,
            volume: clampedVolume,
          ),
          content:
              'Recovered call view screen share audio volume preference failure',
          source: 'call-volume-preference',
        ),
      );
    } else {
      _rememberParticipantAudioVolume(target, clampedVolume);
    }
  }

  void _restoreScreenshareAudioVolume(MatrixLivekitVoipStream stream) {
    if (!stream.isScreenShareAudio) {
      return;
    }

    // Same reasoning as `_setTileVolume`: with no room there is no preference
    // key, so there is nothing stored to restore.
    final roomLocalId = _resolvedRoom?.localId;
    if (roomLocalId == null) {
      return;
    }

    final storedVolumeKey = Preferences.screenShareAudioVolumeKey(
      roomLocalId: roomLocalId,
      streamUserId: stream.streamUserId,
    );
    final restoreKey = "$storedVolumeKey|${stream.streamId}";
    if (!_restoredScreenshareAudioVolumeKeys.add(restoreKey)) {
      return;
    }

    final storedVolume = preferences.getScreenShareAudioVolume(
      roomLocalId: roomLocalId,
      streamUserId: stream.streamUserId,
    );
    if (storedVolume == null) {
      return;
    }

    unawaited(
      CallLocalPlaybackOperationGuard.runAsync(
        operation: () => stream.setLocalVolumePreservingMute(storedVolume),
        content: 'Recovered call view screenshare audio volume restore failure',
        source: 'call-view-local-playback',
      ),
    );
  }

  void _syncHiddenTileAudioMute(List<_CallTileData> tiles) {
    final activeAudioStreamIds = <String>{};
    final visibilityTargets = <String, _VisibilityAudioTarget>{};

    for (final tile in tiles) {
      final target = _volumeTargetForTile(tile);
      if (target is! MatrixLivekitVoipStream ||
          target.direction != VoipStreamDirection.incoming ||
          !target.hasLocalPlaybackAudio) {
        continue;
      }
      if (!_shouldVisibilityMuteTileLocalPlayback(
        tileIsScreenshare: tile.isScreenshare,
        targetIsScreenShareAudio: target.isScreenShareAudio,
      )) {
        continue;
      }

      final fullscreen = _isTileFullscreen(tile);
      visibilityTargets[target.streamId] = _VisibilityAudioTarget(
        stream: target,
        hasVisibleSurface: fullscreen || !_isTileVideoHidden(tile),
        streamHidden: _isTileVideoHidden(tile) && !fullscreen,
      );
    }

    final now = DateTime.now();
    Duration? soonestGraceExpiry;

    // Streams whose screenshare video tile IS in `tiles` were resolved above
    // from a real surface. Record that here so the grace window always counts
    // from a real sighting, never from a grace-held verdict.
    for (final target in visibilityTargets.values) {
      _screenshareAudioVisibilityGrace.resolve(
        streamId: target.stream.streamId,
        realVisible: target.hasVisibleSurface,
        now: now,
      );
    }

    for (final stream in widget.currentSession.streams) {
      if (stream is! MatrixLivekitVoipStream || !stream.isScreenShareAudio) {
        continue;
      }

      if (visibilityTargets.containsKey(stream.streamId)) {
        continue;
      }

      // No tile this frame. A popout surface is the only remaining *real*
      // surface; anything else is usually a transient gap rather than the user
      // hiding the stream, so the grace holds the previous verdict briefly.
      final realVisible = _hasPoppedOutScreenshareSurfaceForAudio(stream);
      final effectiveVisible = _screenshareAudioVisibilityGrace.resolve(
        streamId: stream.streamId,
        realVisible: realVisible,
        now: now,
      );

      if (!realVisible && effectiveVisible) {
        final remaining = _screenshareAudioVisibilityGrace.graceRemaining(
          stream.streamId,
          now,
        );
        final currentSoonest = soonestGraceExpiry;
        if (remaining != null &&
            (currentSoonest == null || remaining < currentSoonest)) {
          soonestGraceExpiry = remaining;
        }
      }

      visibilityTargets[stream.streamId] = _VisibilityAudioTarget(
        stream: stream,
        hasVisibleSurface: effectiveVisible,
        streamHidden: !effectiveVisible,
      );
    }

    // A grace hold is a decision to act later, so schedule the re-evaluation
    // that applies the mute if nothing else rebuilds the view. Armed for the
    // *remaining* time, not the full window: the grace counts from the last
    // real sighting and must not be pushed out by this timer being re-armed on
    // every rebuild.
    _screenshareAudioGraceTimer?.cancel();
    _screenshareAudioGraceTimer = null;
    final graceExpiry = soonestGraceExpiry;
    if (graceExpiry != null) {
      _screenshareAudioGraceTimer = Timer(graceExpiry, () {
        if (!mounted) {
          return;
        }
        setState(() {});
      });
    }

    final deafened = clientManager?.callManager.isDeafened ?? false;

    for (final target in visibilityTargets.values) {
      final stream = target.stream;
      activeAudioStreamIds.add(stream.streamId);
      final shouldMute =
          VoipReceiveQualityPolicy.shouldMuteLocalPlaybackForVisibility(
            direction: stream.direction,
            hasVisibleSurface: target.hasVisibleSurface,
            streamHidden: target.streamHidden,
          );
      final mutedByVisibility = _visibilityMutedAudioStreamIds.contains(
        stream.streamId,
      );
      final shouldUnmute =
          VoipReceiveQualityPolicy.shouldUnmuteLocalPlaybackForVisibility(
            direction: stream.direction,
            hasVisibleSurface: target.hasVisibleSurface,
            streamHidden: target.streamHidden,
            mutedByVisibility: mutedByVisibility,
            locallyMuted: stream.locallyMuted,
            mutedByUser: stream.localVolume <= 0,
            localVolume: stream.localVolume,
            deafened: deafened,
          );

      if (_shouldApplyVisibilityMute(
        shouldMute: shouldMute,
        mutedByVisibility: mutedByVisibility,
        locallyMuted: stream.locallyMuted,
      )) {
        if (!mutedByVisibility) {
          _visibilityMutedAudioStreamIds.add(stream.streamId);
        }
        _setVisibilityMute(stream, true);
      } else if (!shouldMute && shouldUnmute) {
        if (mutedByVisibility) {
          _visibilityMutedAudioStreamIds.remove(stream.streamId);
        }
        _setVisibilityMute(stream, false);
      }
    }

    for (final streamId in _visibilityMutedAudioStreamIds.toList(
      growable: false,
    )) {
      if (!activeAudioStreamIds.contains(streamId)) {
        _visibilityMutedAudioStreamIds.remove(streamId);
      }
    }

    _screenshareAudioVisibilityGrace.retainOnly(activeAudioStreamIds);
  }

  bool _hasPoppedOutScreenshareSurfaceForAudio(MatrixLivekitVoipStream stream) {
    if (!BuildConfig.DESKTOP || !stream.isScreenShareAudio) {
      return false;
    }

    return widget.currentSession.streams.any(
      (candidate) =>
          candidate.type == VoipStreamType.screenshare &&
          candidate.streamUserId == stream.streamUserId &&
          callPopoutController.isStreamPoppedOut(
            widget.currentSession.sessionId,
            _tileIdForStream(candidate),
          ),
    );
  }

  void _setVisibilityMute(MatrixLivekitVoipStream stream, bool muted) {
    scheduleMicrotask(() {
      unawaited(
        CallLocalPlaybackOperationGuard.runAsync(
          operation: () => stream.setLocalMute(muted),
          content: 'Recovered call view visibility mute failure',
          source: 'call-view-local-playback',
        ),
      );
    });
  }

  /// Remove a participant from the call (admin-only).
  Future<void> _removeParticipantFromCall(_CallTileData tile) async {
    await _voipRoomComponent?.removeParticipantFromCall(tile.userId);
  }

  bool get _hasExplicitlyHiddenTiles {
    for (final stream in widget.currentSession.streams) {
      if (stream.type == VoipStreamType.screenshare) {
        if (_hiddenScreenshareStreamIds.contains(_tileIdForStream(stream))) {
          return true;
        }
      } else if (_hiddenUserIds.contains(stream.streamUserId)) {
        return true;
      }
    }

    return false;
  }

  /// Toggle the local context-menu hide state for a tile.
  ///
  /// Camera tiles use the per-user hide set. Screenshare tiles keep a
  /// separate explicit-hide set so incoming auto-hidden screenshares can
  /// remain distinct from user-chosen hide/show state.
  void _toggleTileHidden(_CallTileData tile) {
    final currentlyHidden = _isTileVideoHidden(tile);
    setState(() {
      if (tile.isScreenshare) {
        final local = isLocalTile(tile);
        if (currentlyHidden) {
          _hiddenScreenshareStreamIds.remove(tile.tileId);
          _shownScreenshareStreamIds.add(tile.tileId);
        } else {
          _hiddenScreenshareStreamIds.add(tile.tileId);
        }
        if (local) {
          _markLocalScreenshareAutoHideHandled(tile.tileId);
        }
      } else {
        if (_hiddenUserIds.contains(tile.userId)) {
          _hiddenUserIds.remove(tile.userId);
        } else {
          _hiddenUserIds.add(tile.userId);
        }
      }
    });
  }

  /// Toggle the reveal state for a screenshare tile without changing the
  /// explicit context-menu hide state.
  void _toggleScreenshareVisibility(_CallTileData tile) {
    if (!tile.isScreenshare) return;

    final currentlyHidden = _isTileVideoHidden(tile);
    setState(() {
      final local = isLocalTile(tile);
      if (currentlyHidden) {
        _hiddenScreenshareStreamIds.remove(tile.tileId);
        _shownScreenshareStreamIds.add(tile.tileId);
      } else {
        _hiddenScreenshareStreamIds.remove(tile.tileId);
        _shownScreenshareStreamIds.remove(tile.tileId);
      }
      if (local) {
        _markLocalScreenshareAutoHideHandled(tile.tileId);
      }
    });
  }

  /// Returns true when the video for [tile] should be replaced with the
  /// blank-panel (hidden) overlay.
  ///
  /// - Camera tiles (local and remote): hidden only when explicitly toggled
  ///   via the context menu.
  /// - Remote screenshare tiles: hidden by **default** until the local user
  ///   reveals them, and can also be explicitly re-hidden from the context menu.
  /// - Local screenshare tiles: visible at first so the publisher can verify
  ///   the share, then auto-hidden locally after a short preview window.
  bool _isTileVideoHidden(_CallTileData tile) {
    if (tile.isScreenshare) {
      if (isLocalTile(tile)) {
        // Local screenshares: hidden when explicitly toggled or after the
        // local preview auto-hide timer fires.
        return _hiddenScreenshareStreamIds.contains(tile.tileId);
      }
      // Remote screenshares: hidden by default until revealed.
      return _hiddenScreenshareStreamIds.contains(tile.tileId) ||
          !_shownScreenshareStreamIds.contains(tile.tileId);
    }
    // Camera tiles (local and remote): hidden only when explicitly toggled.
    return _hiddenUserIds.contains(tile.userId);
  }

  void _syncLocalScreenshareAutoHideTimers() {
    final localUserId = widget.currentSession.client.self?.identifier;
    if (localUserId == null) {
      return;
    }

    final localScreenshareIds = widget.currentSession.streams
        .where(
          (stream) =>
              stream.streamUserId == localUserId &&
              stream.type == VoipStreamType.screenshare,
        )
        .map(_tileIdForStream)
        .toSet();

    _localScreenshareAutoHideController.sync(
      localScreenshareTileIds: localScreenshareIds,
      streamTestRunning: _streamTestRunning,
      autoHiddenTileIds: _autoHiddenLocalScreenshareStreamIds,
      hiddenTileIds: _hiddenScreenshareStreamIds,
      shownTileIds: _shownScreenshareStreamIds,
      onAutoHide: _autoHideLocalScreenshare,
    );
  }

  void _autoHideLocalScreenshare(String tileId) {
    if (!mounted) {
      return;
    }

    final localUserId = widget.currentSession.client.self?.identifier;
    final stillSharing = widget.currentSession.streams.any(
      (stream) =>
          _tileIdForStream(stream) == tileId &&
          stream.streamUserId == localUserId &&
          stream.type == VoipStreamType.screenshare,
    );
    if (!stillSharing) {
      return;
    }

    setState(() {
      _autoHiddenLocalScreenshareStreamIds.add(tileId);
      _hiddenScreenshareStreamIds.add(tileId);
      _shownScreenshareStreamIds.remove(tileId);
      if (focusedTileId == tileId) {
        focusedTileId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (widget.currentSession.state) {
      // `leaving` keeps the connected surface rather than falling through to
      // the `_` placeholder: hang-up teardown is bounded but not instant, and
      // this is what the surface rendered for that window before the state
      // existed. Deliberately no behaviour change here - the leaving surface
      // is Slice 5's call, not this one's.
      VoipState.connected || VoipState.leaving => callConnectedView(),
      VoipState.outgoing => callOutgoingView(),
      VoipState.connecting => callOutgoingView(),
      VoipState.ended => callEndedView(),
      VoipState.incoming => callIncomingView(),
      _ => const Placeholder(),
    };

    Widget wrappedContent;
    if (widget.transparentBackground) {
      wrappedContent = Material(color: Colors.transparent, child: content);
    } else {
      wrappedContent = tiamat.Tile.lowest(child: content);
    }

    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      return KeyedSubtree(key: _mobileCallSurfaceKey, child: wrappedContent);
    }

    return wrappedContent;
  }

  Widget callOutgoingView() {
    return callButtons(
      canHangUp: true,
      canPopOutSession: _canPopOutSession,
      child: Center(
        child: RippleAnimation(
          ripplesCount: 3,
          scale: 1,
          color: Theme.of(context).colorScheme.primary,
          repeat: true,
          child: Avatar.large(
            image: room?.avatar,
            placeholderColor: room?.defaultColor,
            placeholderText:
                room?.displayName ?? widget.currentSession.roomName,
          ),
        ),
      ),
    );
  }

  Color _transparentControlColor(Color color) {
    return Color.alphaBlend(color.withAlpha(150), Colors.black.withAlpha(150));
  }

  void _showControlFailureSnack(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// [failureMessage] marks a control as one the user explicitly pressed and
  /// therefore expects to have worked. Controls that only change local view
  /// state, or that already report their own outcome, deliberately leave it
  /// null and stay silent.
  Widget _callControlButton({
    required double radius,
    IconData? icon,
    FutureOr<void> Function()? onPressed,
    Color? color,
    Color? transparentColor,
    Color? iconColor,
    String? tooltip,
    String? semanticLabel,
    String? semanticHint,
    double? minimumSize,
    String? failureMessage,
  }) {
    final resolvedTooltip = tooltip ?? semanticLabel;
    final resolvedSemanticLabel = semanticLabel ?? tooltip;
    final resolvedMinimumSize = minimumSize ?? (Layout.mobile ? 48.0 : 44.0);
    final guardedOnPressed = onPressed == null
        ? null
        : () {
            unawaited(
              _runCallViewControlAction(
                onPressed,
                controlLabel: resolvedSemanticLabel,
                onFailure: failureMessage == null
                    ? null
                    : () => _showControlFailureSnack(failureMessage),
              ),
            );
          };
    final button = widget.transparentBackground
        ? _TransparentCallControlButton(
            radius: radius,
            icon: icon,
            onPressed: guardedOnPressed,
            color: transparentColor,
            iconColor: iconColor,
            semanticLabel: resolvedSemanticLabel,
            semanticHint: semanticHint,
            minimumSize: resolvedMinimumSize,
          )
        : tiamat.CircleButton(
            radius: radius,
            icon: icon,
            onPressed: guardedOnPressed,
            color: color,
            iconColor: iconColor,
            semanticLabel: resolvedSemanticLabel,
            semanticHint: semanticHint,
            tooltip: resolvedTooltip,
            minimumSize: resolvedMinimumSize,
          );

    if (!widget.transparentBackground || resolvedTooltip == null) {
      return button;
    }

    return _transparentAwareTooltip(message: resolvedTooltip, child: button);
  }

  bool get _canPopOutSession =>
      widget.showSessionPopoutButton &&
      (BuildConfig.DESKTOP ||
          MobileCallPopoutController.canRequestPictureInPicture);

  void _popOutSession() {
    if (BuildConfig.DESKTOP) {
      callPopoutController.popOutSession(
        widget.currentSession.sessionId,
        sessionInstance: widget.currentSession,
      );
      return;
    }

    unawaited(
      _runCallViewMobilePictureInPictureAction(_enterMobilePictureInPicture),
    );
  }

  Future<void> _enterMobilePictureInPicture() async {
    final nativeVideoTarget = PlatformUtils.isIOS
        ? _nativePictureInPictureTargetForCurrentSession()
        : null;
    final entered = await MobileCallPopoutController.enterPictureInPicture(
      sessionId: widget.currentSession.sessionId,
      sourceRect: _mobileCallSurfaceRectForPictureInPicture(),
      nativeVideoTarget: nativeVideoTarget,
      controlsState: MobileCallPictureInPictureControlsState(
        isMicrophoneMuted: widget.currentSession.isMicrophoneMuted,
        isCameraEnabled: widget.currentSession.isCameraEnabled,
      ),
    );
    if (entered || !mounted) {
      return;
    }

    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Picture-in-picture is not available on this device'),
        ),
      );
  }

  Rect? _mobileCallSurfaceRectForPictureInPicture() {
    final surfaceContext = _mobileCallSurfaceKey.currentContext;
    final renderObject = surfaceContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final logicalRect = topLeft & renderObject.size;
    final devicePixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
    return Rect.fromLTRB(
      logicalRect.left * devicePixelRatio,
      logicalRect.top * devicePixelRatio,
      logicalRect.right * devicePixelRatio,
      logicalRect.bottom * devicePixelRatio,
    );
  }

  MobileCallNativePiPTarget? _nativePictureInPictureTargetForCurrentSession() {
    final tiles = _buildNativePictureInPictureCandidateTiles()
        .where(
          (tile) => tile.primaryStream is NativePictureInPictureVideoTarget,
        )
        .where(_tileHasUsableNativePiPTarget)
        .toList(growable: false);
    if (tiles.isEmpty) {
      Log.w(
        'iOS call PiP target selection failed: no usable native video tracks',
        category: LogCategory.livekit,
        source: 'call-view',
      );
      return null;
    }

    final selectedTile = _selectNativePictureInPictureTile(tiles);
    final target =
        selectedTile.primaryStream as NativePictureInPictureVideoTarget;
    Log.i(
      'iOS call PiP target selected '
      'stream_hash=${_safePiPHash(selectedTile.primaryStream.streamId)} '
      'participant_hash=${_safePiPHash(selectedTile.userId)} '
      'remote=${selectedTile.primaryStream.direction == VoipStreamDirection.incoming} '
      'hidden=${_isTileVideoHidden(selectedTile)}',
      category: LogCategory.livekit,
      source: 'call-view',
    );
    return MobileCallNativePiPTarget(
      mediaStreamId: target.nativePiPMediaStreamId,
      videoTrackId: target.nativePiPVideoTrackId,
      ownerTag: target.nativePiPOwnerTag,
      selectedStreamId: selectedTile.primaryStream.streamId,
      participantHash: _safePiPHash(selectedTile.userId),
    );
  }

  List<_CallTileData> _buildNativePictureInPictureCandidateTiles() {
    final activeParticipants = _voipRoomComponent
        ?.getCurrentParticipants()
        .toSet();
    final localUserId = widget.currentSession.client.self?.identifier;
    final shouldFilterByMembership = activeParticipants != null;
    final tiles = <_CallTileData>[];

    for (final stream in widget.currentSession.streams) {
      if (_isServerLoopbackStream(stream) ||
          _isScreenShareAudioStream(stream) ||
          stream is! NativePictureInPictureVideoTarget) {
        continue;
      }

      if (shouldFilterByMembership &&
          stream.streamUserId != localUserId &&
          !activeParticipants.contains(stream.streamUserId)) {
        continue;
      }

      final audioStream = stream.type == VoipStreamType.screenshare
          ? _findScreenshareAudioStream(stream)
          : widget.currentSession.streams.tryFirstWhere(
              (candidate) =>
                  candidate.streamUserId == stream.streamUserId &&
                  _isMicrophoneAudioStream(candidate),
            );

      tiles.add(
        _CallTileData(
          primaryStream: stream,
          tileId: _tileIdForStream(stream),
          audioStream: audioStream,
          volumeStream: audioStream,
        ),
      );
    }

    Log.i(
      'iOS call PiP target candidates count=${tiles.length}',
      category: LogCategory.livekit,
      source: 'call-view',
    );
    return tiles;
  }

  bool _tileHasUsableNativePiPTarget(_CallTileData tile) {
    final stream = tile.primaryStream;
    final target = stream is NativePictureInPictureVideoTarget
        ? stream as NativePictureInPictureVideoTarget
        : null;
    if (target == null) {
      return false;
    }
    return target.nativePiPMediaStreamId.trim().isNotEmpty &&
        target.nativePiPVideoTrackId.trim().isNotEmpty;
  }

  _CallTileData _selectNativePictureInPictureTile(List<_CallTileData> tiles) {
    final selectedIndex = _selectNativePictureInPictureCandidateIndex(
      tiles,
      focusedTileId: focusedTileId,
      tileId: (tile) => tile.tileId,
      type: (tile) => tile.primaryStream.type,
      direction: (tile) => tile.primaryStream.direction,
      isHidden: _isTileVideoHidden,
      audioLevel: (tile) =>
          tile.audioStream?.audiolevel ?? tile.primaryStream.audiolevel,
    );
    return tiles[selectedIndex];
  }

  String _safePiPHash(String value) {
    return _safePiPHashValue(value);
  }

  Widget _transparentAwareTooltip({
    required String message,
    required Widget child,
  }) {
    if (!widget.transparentBackground) {
      return Tooltip(
        message: message,
        excludeFromSemantics: true,
        child: child,
      );
    }

    return Tooltip(
      message: message,
      excludeFromSemantics: true,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      textStyle: const TextStyle(color: Colors.white),
      child: child,
    );
  }

  bool get _supportsVoiceQuickMenu =>
      PlatformUtils.isWindows || PlatformUtils.isMacOS;

  List<String> get _microphoneNoiseSuppressionPresetOptions {
    final options = NoiseSuppressionTuningProfile.presetKeys
        .where((preset) => preset != NoiseSuppressionTuningProfile.customKey)
        .toList(growable: true);
    final shouldShowCustom =
        preferences.developerUiVisible ||
        preferences.voipNoiseSuppressionPreset.value ==
            NoiseSuppressionTuningProfile.customKey;

    if (shouldShowCustom &&
        !options.contains(NoiseSuppressionTuningProfile.customKey)) {
      options.add(NoiseSuppressionTuningProfile.customKey);
    }

    return options;
  }

  String _noiseSuppressionPresetLabel(String presetKey) {
    return switch (presetKey) {
      NoiseSuppressionTuningProfile.gentleKey => 'Gentle',
      NoiseSuppressionTuningProfile.balancedKey => 'Balanced',
      NoiseSuppressionTuningProfile.strongKey => 'Strong',
      NoiseSuppressionTuningProfile.customKey => 'Custom',
      _ => 'Balanced',
    };
  }

  String get _microphoneInputProfileSummary {
    if (!preferences.voipNoiseSuppressionEnabled.value) {
      return 'Standard';
    }

    if (preferences.voipNoiseSuppressionCompatibilityMode.value) {
      return 'Compatibility';
    }

    return _noiseSuppressionPresetLabel(
      preferences.voipNoiseSuppressionPreset.value,
    );
  }

  NoiseSuppressionTuningProfile _callNoiseSuppressionTuningProfile({
    String? presetKey,
  }) {
    return NoiseSuppressionTuningProfile.fromPreferenceValues(
      presetKey: presetKey ?? preferences.voipNoiseSuppressionPreset.value,
      customVadThreshold: preferences.voipNoiseSuppressionVadThreshold.value,
      customSpeechGraceMs: preferences.voipNoiseSuppressionSpeechGraceMs.value,
      customClosedGainPercent:
          preferences.voipNoiseSuppressionClosedGainPercent.value,
      customTransientSensitivityPercent:
          preferences.voipNoiseSuppressionTransientSensitivity.value,
    );
  }

  Future<void> _applyCallNoiseSuppressionSettings({
    bool? enabled,
    String? presetKey,
  }) async {
    final effectiveEnabled =
        enabled ?? preferences.voipNoiseSuppressionEnabled.value;

    await NoiseSuppressionService.instance.applyPreference(
      effectiveEnabled,
      tuningProfile: _callNoiseSuppressionTuningProfile(presetKey: presetKey),
    );
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _rnnoisePipelineModeForHookPreference(
        preferences.voipNoiseSuppressionHookMode.value,
      ),
    );

    if (effectiveEnabled) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setMicrophoneInputProfile(String action) async {
    if (action == _microphoneInputProfileStandardAction) {
      await preferences.voipNoiseSuppressionEnabled.set(false);
      await _applyCallNoiseSuppressionSettings(enabled: false);
      return;
    }

    if (!_microphoneNoiseSuppressionPresetOptions.contains(action)) {
      return;
    }

    await preferences.voipNoiseSuppressionPreset.set(action);
    if (!preferences.voipNoiseSuppressionEnabled.value) {
      await preferences.voipNoiseSuppressionEnabled.set(true);
    }
    await _applyCallNoiseSuppressionSettings(enabled: true, presetKey: action);
  }

  Future<void> _refreshVoiceDevices() async {
    if (_voiceDevicesLoading) {
      return;
    }

    setState(() {
      _voiceDevicesLoading = true;
      _voiceDevicesError = null;
    });

    try {
      final devices = await rtc.navigator.mediaDevices.enumerateDevices();
      if (!mounted) {
        return;
      }

      setState(() {
        _microphoneDevices = devices
            .where((device) => device.kind == 'audioinput')
            .toList(growable: false);
        _speakerDevices = devices
            .where((device) => device.kind == 'audiooutput')
            .toList(growable: false);
        _voiceDevicesLoading = false;
      });
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to enumerate call voice devices',
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _voiceDevicesLoading = false;
        _voiceDevicesError = 'Could not load devices';
      });
    }
  }

  Future<void> _setVoiceInputDevice(rtc.MediaDeviceInfo? device) async {
    final previousDeviceId = preferences.voipDefaultAudioInput.value;
    await preferences.voipDefaultAudioInput.set(device?.deviceId);

    try {
      await WebrtcDefaultDevices.selectInputDevice();
    } catch (error, stackTrace) {
      await preferences.voipDefaultAudioInput.set(previousDeviceId);
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to switch call microphone device',
      );
      _showVoiceMenuSnack('Could not switch microphone.');
    }

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _setVoiceOutputDevice(rtc.MediaDeviceInfo? device) async {
    final previousDeviceId = preferences.voipDefaultAudioOutput.value;
    await preferences.voipDefaultAudioOutput.set(device?.deviceId);

    try {
      await WebrtcDefaultDevices.selectOutputDevice();
    } catch (error, stackTrace) {
      await preferences.voipDefaultAudioOutput.set(previousDeviceId);
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to switch call speaker device',
      );
      _showVoiceMenuSnack('Could not switch speaker.');
    }

    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _setCallMicrophoneVolume(double value) async {
    final clamped = value.clamp(0.0, 100.0).toDouble();
    await preferences.voipMicrophoneVolume.set(clamped);
    await NoiseSuppressionService.instance.refresh();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _setCallSpeakerVolume(double value) async {
    final clamped = value
        .clamp(0.0, Preferences.maxVoipSpeakerVolume)
        .toDouble();
    await preferences.voipSpeakerVolume.set(clamped);
    final callManager = clientManager?.callManager;
    if (callManager != null) {
      await callManager.applySpeakerVolumePreference();
    }
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _setPushToTalkEnabled(bool value) async {
    final previousValue = preferences.voipPushToTalkEnabled.value;
    try {
      await preferences.voipPushToTalkEnabled.set(value);
      clientManager?.callManager.applyPushToTalkPreference();
    } catch (error, stackTrace) {
      await preferences.voipPushToTalkEnabled.set(previousValue);
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to apply Push to Talk call preference',
        category: LogCategory.webrtc,
        source: 'voice-quick-menu',
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _setCallDeafened(bool value) {
    clientManager?.callManager.setDeafened(value);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openVoiceSettings() async {
    _voiceMenuController.close();
    if (!mounted) {
      return;
    }

    await SettingsNavigation.show(
      context,
      const AppSettingsPage(
        initialTabId: SettingsCategoryApp.tabIdVoiceAndVideo,
      ),
    );
  }

  void _showVoiceMenuSnack(String message) {
    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || Scaffold.maybeOf(context) == null) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  String _voiceDeviceLabel(rtc.MediaDeviceInfo? device) {
    if (device == null) {
      return 'System default';
    }
    final label = device.label.trim();
    return label.isEmpty ? 'Unnamed device' : label;
  }

  bool _isSelectedVoiceDevice(
    rtc.MediaDeviceInfo? device,
    String? selectedDeviceId,
  ) {
    if (device == null) {
      return selectedDeviceId == null || selectedDeviceId.isEmpty;
    }

    return device.deviceId == selectedDeviceId ||
        device.label == selectedDeviceId;
  }

  rtc.MediaDeviceInfo? _selectedVoiceDevice(
    List<rtc.MediaDeviceInfo> devices,
    String? selectedDeviceId,
  ) {
    if (selectedDeviceId == null || selectedDeviceId.isEmpty) {
      return null;
    }

    return devices.tryFirstWhere(
      (device) =>
          device.deviceId == selectedDeviceId ||
          device.label == selectedDeviceId,
    );
  }

  String _voiceDeviceSummary(
    List<rtc.MediaDeviceInfo> devices,
    String? selectedDeviceId,
  ) {
    if (_voiceDevicesLoading && devices.isEmpty) {
      return 'Loading...';
    }
    if (_voiceDevicesError != null && devices.isEmpty) {
      return 'Unavailable';
    }
    if (selectedDeviceId == null || selectedDeviceId.isEmpty) {
      return 'System default';
    }

    return _voiceDeviceLabel(_selectedVoiceDevice(devices, selectedDeviceId));
  }

  MenuStyle _voiceMenuStyle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll<Color?>(
        colorScheme.surfaceContainer,
      ),
      surfaceTintColor: const WidgetStatePropertyAll<Color?>(
        Colors.transparent,
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(vertical: 6),
      ),
      maximumSize: const WidgetStatePropertyAll<Size?>(Size(306, 560)),
      side: WidgetStatePropertyAll<BorderSide?>(
        BorderSide(color: colorScheme.outlineVariant.withAlpha(120)),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder?>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  ButtonStyle _voiceMenuItemStyle(BuildContext context) {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll<Size?>(
        Size(_voiceQuickMenuWidth, 52),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder?>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  void _activateVoiceSubmenu(MenuController controller) {
    final previous = _openVoiceSubmenuController;
    if (previous != null && previous != controller) {
      previous.close();
    }
    _openVoiceSubmenuController = controller;
  }

  void _clearVoiceSubmenu(MenuController controller) {
    if (_openVoiceSubmenuController == controller) {
      _openVoiceSubmenuController = null;
    }
  }

  void _closeOpenVoiceSubmenu() {
    final controller = _openVoiceSubmenuController;
    if (controller == null) {
      return;
    }
    controller.close();
    _openVoiceSubmenuController = null;
  }

  Widget _closeVoiceSubmenuOnHover(Widget child) {
    return MouseRegion(onEnter: (_) => _closeOpenVoiceSubmenu(), child: child);
  }

  Widget _voiceSubmenuButton({
    required MenuController controller,
    required ButtonStyle style,
    required MenuStyle menuStyle,
    required List<Widget> menuChildren,
    required Widget child,
  }) {
    return SubmenuButton(
      controller: controller,
      style: style,
      menuStyle: menuStyle,
      trailingIcon: const SizedBox.shrink(),
      onHover: (hovering) {
        if (hovering) {
          _activateVoiceSubmenu(controller);
        }
      },
      onOpen: () => _activateVoiceSubmenu(controller),
      onClose: () => _clearVoiceSubmenu(controller),
      menuChildren: menuChildren,
      child: child,
    );
  }

  Widget _voiceMenuDivider(BuildContext context) {
    return _closeVoiceSubmenuOnHover(
      Divider(
        height: 11,
        thickness: 1,
        indent: 14,
        endIndent: 14,
        color: Theme.of(context).colorScheme.outlineVariant.withAlpha(120),
      ),
    );
  }

  Widget _voiceMenuStatusItem(String label) {
    return MenuItemButton(
      onPressed: null,
      child: SizedBox(
        width: _voiceQuickMenuTextWidth,
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _checkedVoiceMenuItem({
    required BuildContext context,
    required String label,
    required bool checked,
    required VoidCallback onPressed,
  }) {
    return MenuItemButton(
      style: _voiceMenuItemStyle(context),
      leadingIcon: checked
          ? const Icon(Icons.check_rounded, size: 18)
          : const SizedBox(width: 18, height: 18),
      onPressed: onPressed,
      child: SizedBox(
        width: _voiceQuickMenuTextWidth,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  List<Widget> _voiceDeviceSubmenuItems({
    required BuildContext context,
    required List<rtc.MediaDeviceInfo> devices,
    required String? selectedDeviceId,
    required String deviceKindLabel,
    required Future<void> Function(rtc.MediaDeviceInfo? device) onSelected,
  }) {
    if (_voiceDevicesLoading && devices.isEmpty) {
      return [_voiceMenuStatusItem('Loading devices...')];
    }

    if (_voiceDevicesError != null && devices.isEmpty) {
      return [
        _voiceMenuStatusItem(_voiceDevicesError!),
        MenuItemButton(
          style: _voiceMenuItemStyle(context),
          leadingIcon: const Icon(Icons.refresh_rounded, size: 18),
          onPressed: () {
            unawaited(
              _runCallViewVoiceMenuAction(
                _refreshVoiceDevices,
                actionLabel: 'refresh voice devices',
              ),
            );
          },
          child: const SizedBox(
            width: _voiceQuickMenuTextWidth,
            child: Text('Retry'),
          ),
        ),
      ];
    }

    return [
      _checkedVoiceMenuItem(
        context: context,
        label: 'System default',
        checked: _isSelectedVoiceDevice(null, selectedDeviceId),
        onPressed: () {
          unawaited(
            _runCallViewVoiceMenuAction(
              () => onSelected(null),
              actionLabel: 'select $deviceKindLabel system default',
            ),
          );
        },
      ),
      if (devices.isEmpty) _voiceMenuStatusItem('No devices found'),
      for (final device in devices)
        _checkedVoiceMenuItem(
          context: context,
          label: _voiceDeviceLabel(device),
          checked: _isSelectedVoiceDevice(device, selectedDeviceId),
          onPressed: () {
            unawaited(
              _runCallViewVoiceMenuAction(
                () => onSelected(device),
                actionLabel: 'select $deviceKindLabel',
              ),
            );
          },
        ),
    ];
  }

  List<Widget> _microphoneInputProfileMenuItems(BuildContext context) {
    final selectedPreset = preferences.voipNoiseSuppressionPreset.value;
    final enabled = preferences.voipNoiseSuppressionEnabled.value;

    return [
      _checkedVoiceMenuItem(
        context: context,
        label: 'Standard',
        checked: !enabled,
        onPressed: () {
          unawaited(
            _runCallViewVoiceMenuAction(
              () => _setMicrophoneInputProfile(
                _microphoneInputProfileStandardAction,
              ),
              actionLabel: 'select standard input profile',
            ),
          );
        },
      ),
      for (final preset in _microphoneNoiseSuppressionPresetOptions)
        _checkedVoiceMenuItem(
          context: context,
          label: _noiseSuppressionPresetLabel(preset),
          checked: enabled && selectedPreset == preset,
          onPressed: () {
            unawaited(
              _runCallViewVoiceMenuAction(
                () => _setMicrophoneInputProfile(preset),
                actionLabel: 'select input profile',
              ),
            );
          },
        ),
    ];
  }

  List<Widget> _voiceMenuChildren(BuildContext context) {
    final callManager = clientManager?.callManager;
    final menuStyle = _voiceMenuStyle(context);
    final itemStyle = _voiceMenuItemStyle(context);

    return [
      _voiceSubmenuButton(
        controller: _voiceInputDeviceMenuController,
        style: itemStyle,
        menuStyle: menuStyle,
        menuChildren: _voiceDeviceSubmenuItems(
          context: context,
          devices: _microphoneDevices,
          selectedDeviceId: preferences.voipDefaultAudioInput.value,
          deviceKindLabel: 'input device',
          onSelected: _setVoiceInputDevice,
        ),
        child: _VoiceMenuSummaryRow(
          title: 'Input Device',
          summary: _voiceDeviceSummary(
            _microphoneDevices,
            preferences.voipDefaultAudioInput.value,
          ),
        ),
      ),
      _voiceSubmenuButton(
        controller: _voiceInputProfileMenuController,
        style: itemStyle,
        menuStyle: menuStyle,
        menuChildren: _microphoneInputProfileMenuItems(context),
        child: _VoiceMenuSummaryRow(
          title: 'Input Profile',
          summary: _microphoneInputProfileSummary,
        ),
      ),
      _voiceSubmenuButton(
        controller: _voiceOutputDeviceMenuController,
        style: itemStyle,
        menuStyle: menuStyle,
        menuChildren: _voiceDeviceSubmenuItems(
          context: context,
          devices: _speakerDevices,
          selectedDeviceId: preferences.voipDefaultAudioOutput.value,
          deviceKindLabel: 'output device',
          onSelected: _setVoiceOutputDevice,
        ),
        child: _VoiceMenuSummaryRow(
          title: 'Output Device',
          summary: _voiceDeviceSummary(
            _speakerDevices,
            preferences.voipDefaultAudioOutput.value,
          ),
        ),
      ),
      _voiceMenuDivider(context),
      _closeVoiceSubmenuOnHover(
        _VoiceMenuSlider(
          title: 'Input Volume',
          value: preferences.voipMicrophoneVolume.value,
          max: 100,
          onSettled: _setCallMicrophoneVolume,
        ),
      ),
      _closeVoiceSubmenuOnHover(
        _VoiceInputLevelMeter(session: widget.currentSession),
      ),
      _closeVoiceSubmenuOnHover(
        _VoiceMenuSlider(
          title: 'Output Volume',
          value: preferences.voipSpeakerVolume.value,
          max: Preferences.maxVoipSpeakerVolume,
          onSettled: _setCallSpeakerVolume,
        ),
      ),
      _voiceMenuDivider(context),
      _closeVoiceSubmenuOnHover(
        _VoiceMenuToggleRow(
          title: 'Push to Talk',
          value: preferences.voipPushToTalkEnabled.value,
          onChanged: (value) {
            unawaited(
              _runCallViewVoiceMenuAction(
                () => _setPushToTalkEnabled(value),
                actionLabel: 'toggle push to talk',
              ),
            );
          },
        ),
      ),
      _closeVoiceSubmenuOnHover(
        _VoiceMenuToggleRow(
          title: 'Deafen',
          value: callManager?.isDeafened ?? false,
          enabled: callManager != null,
          onChanged: (value) {
            unawaited(
              _runCallViewVoiceMenuAction(
                () => _setCallDeafened(value),
                actionLabel: 'toggle deafen',
              ),
            );
          },
        ),
      ),
      _voiceMenuDivider(context),
      _closeVoiceSubmenuOnHover(
        MenuItemButton(
          style: itemStyle,
          leadingIcon: const Icon(Icons.settings_rounded, size: 18),
          onPressed: () {
            unawaited(
              _runCallViewVoiceMenuAction(
                _openVoiceSettings,
                actionLabel: 'open voice settings',
              ),
            );
          },
          child: const SizedBox(
            width: _voiceQuickMenuTextWidth,
            child: Text('Voice Settings'),
          ),
        ),
      ),
    ];
  }

  Widget _voiceQuickMenuButton({required double buttonRadius}) {
    return MenuAnchor(
      controller: _voiceMenuController,
      style: _voiceMenuStyle(context),
      alignmentOffset: const Offset(0, 8),
      consumeOutsideTap: true,
      useRootOverlay: _shouldUseCallMenuRootOverlay(
        transparentBackground: widget.transparentBackground,
      ),
      onOpen: () {
        setState(() {
          _voiceMenuOpen = true;
        });
        unawaited(_refreshVoiceDevices());
      },
      onClose: () {
        if (!mounted) {
          return;
        }
        _closeOpenVoiceSubmenu();
        setState(() {
          _voiceMenuOpen = false;
        });
      },
      menuChildren: _voiceMenuChildren(context),
      builder: (context, controller, child) {
        return _callControlButton(
          radius: buttonRadius,
          icon: Icons.more_horiz_rounded,
          tooltip: _voiceMenuOpen ? 'Close voice controls' : 'Voice controls',
          semanticLabel: _voiceMenuOpen
              ? 'Close voice controls'
              : 'Open voice controls',
          semanticHint:
              'Chooses call devices, volumes, input profile, push to talk, and deafen',
          onPressed: () {
            if (_voiceMenuOpen) {
              controller.close();
              return;
            }

            unawaited(
              _runCallViewVoiceMenuAction(
                _refreshVoiceDevices,
                actionLabel: 'refresh voice devices',
              ),
            );
            controller.open();
          },
        );
      },
    );
  }

  Widget _microphoneControl({required double buttonRadius}) {
    // Icon, label and toggle all read the SAME source, the pending intent.
    // `currentSession.isMicrophoneMuted` is the applied state and lags the
    // coalescing drain: rendering it while toggling from the intent makes the
    // two disagree for the length of the drain, so the icon still says
    // "unmuted" after a press, the user presses again, and the second press
    // correctly flips the intent back - cancelling the mute they asked for.
    // MiniCallMenu fixed the identical defect; this is the same repair on the
    // primary call surface.
    final microphoneMuted =
        widget.microphoneMuteIntent?.call() ??
        widget.currentSession.isMicrophoneMuted;
    final muteButton = _callControlButton(
      radius: buttonRadius,
      icon: microphoneMuted ? Icons.mic_off : Icons.mic,
      semanticLabel: microphoneMuted ? 'Unmute microphone' : 'Mute microphone',
      semanticHint: 'Toggles your microphone in this call',
      failureMessage: 'Could not change your microphone.',
      onPressed: () async {
        final muted =
            widget.microphoneMuteIntent?.call() ??
            widget.currentSession.isMicrophoneMuted;
        // Issue first, then rebuild, then await: the intent is recorded
        // synchronously, so rebuilding immediately makes the control reflect
        // what was asked instead of waiting out the whole drain.
        final pending = widget.setMicrophoneMute?.call(!muted);
        if (mounted) {
          setState(() {});
        }
        await pending;
        if (!mounted) return;
        setState(() {});
      },
    );

    return muteButton;
  }

  Widget callButtons({
    bool canMute = false,
    bool canScreenshare = false,
    bool canHangUp = false,
    bool canToggleCamera = false,
    bool canPopOutSession = false,
    bool canHideStreams = false,
    required Widget child,
  }) {
    if (widget.suppressControls) {
      return child;
    }

    final buttonRadius = Layout.mobile ? 21.0 : 18.0;
    final sharedAudioIndicator = _sharedAudioStatusIndicator(buttonRadius);
    final serverAudioLoopbackButton = _serverAudioLoopbackButton(buttonRadius);
    final popOutCallLabel = BuildConfig.DESKTOP
        ? 'Pop out call'
        : 'Open call picture in picture';
    final remoteTilesLabel = _hasExplicitlyHiddenTiles
        ? 'Show remote call tiles'
        : 'Hide remote call tiles';
    final cameraLabel = widget.currentSession.isCameraEnabled
        ? 'Turn camera off'
        : 'Turn camera on';
    final controls = <Widget>[
      if (canPopOutSession)
        TutorialAnchor(
          id: TutorialAnchorIds.callPopoutButton,
          padding: EdgeInsets.all(Layout.mobile ? 4 : 8),
          child: _callControlButton(
            radius: buttonRadius,
            icon: Icons.open_in_new_rounded,
            onPressed: _popOutSession,
            semanticLabel: popOutCallLabel,
          ),
        ),
      if (canHideStreams)
        _callControlButton(
          radius: buttonRadius,
          icon: _hasExplicitlyHiddenTiles
              ? Icons.videocam_off_outlined
              : Icons.videocam_outlined,
          onPressed: _toggleAllRemoteStreamsVisibility,
          semanticLabel: remoteTilesLabel,
        ),
      if (canScreenshare)
        _callControlButton(
          radius: buttonRadius,
          icon: Icons.screen_share_outlined,
          onPressed: widget.pickScreenshareSource,
          semanticLabel: 'Start screen share',
        ),
      if (sharedAudioIndicator != null) sharedAudioIndicator,
      if (widget.currentSession.isSharingScreen && canScreenshare)
        _callControlButton(
          radius: buttonRadius,
          icon: Icons.stop_screen_share,
          onPressed: widget.stopScreenshare,
          semanticLabel: 'Stop screen share',
          failureMessage: 'Could not stop screen sharing.',
        ),
      if (serverAudioLoopbackButton != null) serverAudioLoopbackButton,
      if (preferences.developerUiVisible)
        _callControlButton(
          radius: buttonRadius,
          icon: Icons.article_outlined,
          tooltip: 'Call diagnostics logs',
          semanticLabel: 'Open call diagnostics logs',
          onPressed: _openCallDiagnosticsLogMenu,
        ),
      if (preferences.developerUiVisible &&
          preferences.showCallStreamStats.value)
        _callControlButton(
          radius: buttonRadius,
          icon: _diagnosticsOverlayVisible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          tooltip: _diagnosticsOverlayVisible
              ? 'Hide developer stats overlay'
              : 'Show developer stats overlay',
          onPressed: () {
            final nextVisible = !_diagnosticsOverlayVisible;
            setState(() {
              _diagnosticsOverlayVisible = nextVisible;
            });
            unawaited(
              preferences.callStreamStatsOverlayVisible.set(nextVisible),
            );
          },
        ),
      if (canMute) _microphoneControl(buttonRadius: buttonRadius),
      if (canToggleCamera)
        _callControlButton(
          radius: buttonRadius,
          icon: widget.currentSession.isCameraEnabled
              ? Icons.no_photography
              : Icons.camera_alt_outlined,
          onPressed: widget.currentSession.isCameraEnabled
              ? widget.disableCamera
              : widget.pickCamera,
          semanticLabel: cameraLabel,
          semanticHint: 'Toggles your camera in this call',
          failureMessage: 'Could not change your camera.',
        ),
      if (canMute && _supportsVoiceQuickMenu)
        _voiceQuickMenuButton(buttonRadius: buttonRadius),
    ];
    final hangUpControl = canHangUp
        ? _callControlButton(
            color: Theme.of(context).colorScheme.errorContainer,
            transparentColor: _transparentControlColor(
              Theme.of(context).colorScheme.error,
            ),
            iconColor: widget.transparentBackground
                ? Theme.of(context).colorScheme.onError
                : null,
            radius: buttonRadius,
            icon: Icons.call_end,
            semanticLabel: 'Leave call',
            failureMessage: 'Could not leave the call. Please try again.',
            onPressed: () async {
              await widget.hangUp?.call();
              if (!mounted) return;
              setState(() {});
            },
          )
        : null;

    return MouseRegion(
      onEnter: (event) {
        setState(() {
          isMouseHovering = true;
        });
      },
      onExit: (event) {
        setState(() {
          isMouseHovering = false;
        });
      },
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _CallControlsVisibility(
              visible:
                  Layout.mobile ||
                  isMouseHovering ||
                  widget.forceControlsVisible,
              duration: InterGalacticMotion.duration(
                context,
                InterGalacticMotion.standard,
              ),
              transparentBackground: widget.transparentBackground,
              child: _buildCallControlDock(
                controls,
                hangUpControl: hangUpControl,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallControlDock(List<Widget> controls, {Widget? hangUpControl}) {
    if (!Layout.mobile) {
      final maxDockWidth = max(0.0, MediaQuery.sizeOf(context).width - 16);
      final desktopControls = [
        ...controls,
        if (hangUpControl != null) hangUpControl,
      ];
      return SafeArea(
        minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxDockWidth),
            child: _buildScrollableControlRow(
              desktopControls,
              spacing: _desktopCallControlSpacing,
            ),
          ),
        ),
      );
    }

    final mediaQuery = MediaQuery.of(context);
    final maxDockWidth = min(
      _mobileCallControlDockMaxWidth,
      max(
        0.0,
        mediaQuery.size.width -
            mediaQuery.padding.horizontal -
            _mobileCallControlDockSafeAreaMargin.horizontal,
      ),
    );
    final pinHangUpControl = _shouldPinMobileHangUpControl(
      mobile: Layout.mobile,
      hasHangUpControl: hangUpControl != null,
      scrollableControlCount: controls.length,
      maxDockWidth: maxDockWidth,
    );
    final mobileControls = [
      ...controls,
      if (hangUpControl != null && !pinHangUpControl) hangUpControl,
    ];
    final content = pinHangUpControl
        ? _buildPinnedMobileControlRow(controls, hangUpControl!)
        : _buildScrollableControlRow(mobileControls);
    final colorScheme = Theme.of(context).colorScheme;
    final dock = widget.transparentBackground
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(190),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withAlpha(32)),
            ),
            child: content,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withAlpha(235),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colorScheme.outline.withAlpha(60)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(45),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: content,
          );

    return SafeArea(
      minimum: _mobileCallControlDockSafeAreaMargin,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxDockWidth),
          child: dock,
        ),
      ),
    );
  }

  Widget _buildPinnedMobileControlRow(
    List<Widget> controls,
    Widget hangUpControl, {
    double spacing = _defaultCallControlSpacing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _callControlRowHorizontalPadding,
        vertical: _callControlRowVerticalPadding,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _withHorizontalSpacing(controls, spacing),
              ),
            ),
          ),
          SizedBox(width: spacing),
          hangUpControl,
        ],
      ),
    );
  }

  Widget _buildScrollableControlRow(
    List<Widget> controls, {
    double spacing = 8,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _callControlRowHorizontalPadding,
        vertical: _callControlRowVerticalPadding,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _withHorizontalSpacing(controls, spacing),
        ),
      ),
    );
  }

  List<Widget> _withHorizontalSpacing(List<Widget> children, double spacing) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        spaced.add(SizedBox(width: spacing));
      }
      spaced.add(children[i]);
    }
    return spaced;
  }

  void _toggleAllRemoteStreamsVisibility() {
    setState(() {
      if (_hasExplicitlyHiddenTiles) {
        _hiddenUserIds.clear();
        _hiddenScreenshareStreamIds.clear();
        final localId = widget.currentSession.client.self?.identifier;
        for (final stream in widget.currentSession.streams) {
          if (stream.streamUserId == localId &&
              stream.type == VoipStreamType.screenshare) {
            _markLocalScreenshareAutoHideHandled(_tileIdForStream(stream));
          } else if (stream.streamUserId != localId &&
              stream.type == VoipStreamType.screenshare) {
            _shownScreenshareStreamIds.add(_tileIdForStream(stream));
          }
        }
        return;
      }

      final localId = widget.currentSession.client.self?.identifier;
      for (final stream in widget.currentSession.streams) {
        if (stream.streamUserId == localId) {
          continue;
        }
        if (stream.type == VoipStreamType.screenshare) {
          _hiddenScreenshareStreamIds.add(_tileIdForStream(stream));
        } else {
          _hiddenUserIds.add(stream.streamUserId);
        }
      }
    });
  }

  bool get _canRepublishCurrentDesktopScreenshare {
    final shareSession = widget.currentSession.currentShareSession;
    return widget.currentSession.isSharingScreen &&
        shareSession?.videoSource is WebrtcScreenVideoSource;
  }

  ScreenShareQualityProfile get _selectedStreamQualityProfile {
    return screenShareQualityProfileFromStorageKey(
      preferences.screenShareQualityProfile.value,
    );
  }

  Future<ScreenCaptureSource?> _currentDesktopScreenshareSource({
    required bool shareAudio,
  }) async {
    final shareSession = widget.currentSession.currentShareSession;
    final videoSource = shareSession?.videoSource;
    if (videoSource is! WebrtcScreenVideoSource) {
      Log.w(
        'Unable to republish active stream tile: current share source is '
        'not a desktop WebRTC source.',
        category: LogCategory.livekit,
        source: 'call-stream-menu',
      );
      return null;
    }

    final nextShareSession = await ShareSession.forDesktopCapturerSource(
      videoSource.source,
      shareAudio: shareAudio,
    );

    return ShareCaptureSource(
      videoSource: WebrtcScreencaptureSource(videoSource.source),
      shareSession: nextShareSession,
    );
  }

  Future<void> _republishCurrentDesktopScreenshare({
    ScreenShareQualityProfile? qualityProfile,
    bool? shareAudio,
  }) async {
    if (!widget.currentSession.isSharingScreen) {
      return;
    }

    final currentShareSession = widget.currentSession.currentShareSession;
    final nextShareAudio =
        shareAudio ?? currentShareSession?.sharedAudioRequested ?? false;

    final source = await _currentDesktopScreenshareSource(
      shareAudio: nextShareAudio,
    );
    if (source == null || !mounted) {
      return;
    }

    if (qualityProfile != null) {
      if (preferences.streamAdvancedOverride.value) {
        await preferences.streamAdvancedOverride.set(false);
      }
      await preferences.screenShareQualityProfile.set(
        qualityProfile.storageKey,
      );
    }

    await widget.currentSession.setScreenShare(source);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _selectStreamQualityProfile(ScreenShareQualityProfile profile) {
    return _republishCurrentDesktopScreenshare(qualityProfile: profile);
  }

  Future<void> _setShareStreamAudio(bool shareAudio) {
    return _republishCurrentDesktopScreenshare(shareAudio: shareAudio);
  }

  Widget? _serverAudioLoopbackButton(double buttonRadius) {
    if (!preferences.developerUiVisible) {
      return null;
    }

    final session = widget.currentSession;
    if (session is! MatrixLivekitVoipSession) {
      return null;
    }

    final starting = session.isServerAudioLoopbackStarting;
    final active = session.isServerAudioLoopbackEnabled;
    final hasError = session.serverAudioLoopbackError != null;
    final label = starting
        ? 'Starting server audio loopback...'
        : active
        ? 'Stop server audio loopback. You are hearing your mic after it '
              'routes through LiveKit.'
        : hasError
        ? 'Retry server audio loopback: '
              '${session.serverAudioLoopbackError}'
        : 'Start server audio loopback to hear your mic after it '
              'routes through LiveKit.';
    final semanticLabel = starting
        ? 'Starting server audio loopback'
        : active
        ? 'Stop server audio loopback'
        : hasError
        ? 'Retry server audio loopback'
        : 'Start server audio loopback';
    final color = active
        ? Theme.of(context).colorScheme.primaryContainer
        : hasError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    final transparentColor = hasError
        ? _transparentControlColor(Theme.of(context).colorScheme.error)
        : active
        ? _transparentControlColor(Theme.of(context).colorScheme.primary)
        : null;

    return _callControlButton(
      radius: buttonRadius,
      color: color,
      transparentColor: transparentColor,
      icon: starting
          ? Icons.sync
          : active
          ? Icons.hearing
          : Icons.hearing_disabled,
      tooltip: label,
      semanticLabel: semanticLabel,
      onPressed: starting
          ? null
          : () async {
              try {
                await session.setServerAudioLoopbackEnabled(!active);
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to toggle server audio loopback',
                );
              } finally {
                if (mounted) {
                  setState(() {});
                }
              }
            },
    );
  }

  Widget? _sharedAudioStatusIndicator(double buttonRadius) {
    final shareSession = widget.currentSession.currentShareSession;
    if (shareSession == null || !shareSession.sharedAudioRequested) {
      return null;
    }

    var (icon, label, color) = switch (shareSession.sharedAudioState) {
      SharedAudioState.active => (
        Icons.volume_up_outlined,
        'Shared audio active',
        Theme.of(context).colorScheme.primaryContainer,
      ),
      SharedAudioState.starting => (
        Icons.sync,
        'Shared audio starting',
        Theme.of(context).colorScheme.secondaryContainer,
      ),
      SharedAudioState.failed || SharedAudioState.unavailable => (
        Icons.volume_off_outlined,
        'Shared audio unavailable',
        Theme.of(context).colorScheme.errorContainer,
      ),
      _ => (
        Icons.volume_off_outlined,
        'Shared audio inactive',
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    };

    // An elevated target (or a session capturing only silence) reports as
    // "active" but carries no sound. Override the happy state with the
    // actionable advisory so the user learns how to fix it.
    final advisory = shareSession.sharedAudioStatus.advisory;
    if (advisory.hasAdvisory) {
      icon = Icons.warning_amber_outlined;
      label = '${advisory.title}\n${advisory.detail}';
      color = Theme.of(context).colorScheme.errorContainer;
    }

    final indicatorColor = widget.transparentBackground
        ? _transparentControlColor(color)
        : color;

    return _transparentAwareTooltip(
      message: label,
      child: Container(
        width: buttonRadius * 2,
        height: buttonRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: indicatorColor,
        ),
        child: Icon(
          icon,
          size: buttonRadius,
          color: widget.transparentBackground ? Colors.white : null,
        ),
      ),
    );
  }

  Widget callConnectedView() {
    final tiles = buildVisibleTiles();
    final hasPoppedStreams = callPopoutController.hasPoppedStreams(
      widget.currentSession.sessionId,
    );
    final focusedTile = resolveFocusedTile(tiles);
    final secondaryTiles = tiles
        .where((tile) => tile.tileId != focusedTile?.tileId)
        .toList(growable: false);
    _scheduleMediaControl(tiles, focusedTile);

    final content = widget.surfaceMode.usesSecondarySurface
        ? _buildSecondaryCallSurface(
            tiles: tiles,
            secondaryTiles: secondaryTiles,
            hasPoppedStreams: hasPoppedStreams,
          )
        : callButtons(
            canMute: true,
            canHangUp: true,
            canScreenshare: widget.currentSession.supportsScreenshare,
            canToggleCamera: true,
            canPopOutSession: _canPopOutSession,
            canHideStreams: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (tiles.isEmpty) {
                  return Center(
                    child: tiamat.Text.labelLow(
                      hasPoppedStreams
                          ? "All streams are currently popped out."
                          : "Waiting for streams...",
                    ),
                  );
                }

                if (Layout.mobile) {
                  return buildMobileCallLayout(
                    tiles,
                    focusedTile,
                    secondaryTiles,
                    constraints,
                  );
                }

                if (showEqualTileLayout ||
                    focusedTile == null ||
                    tiles.length == 1) {
                  return buildEqualTileGrid(tiles);
                }

                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.transparentBackground
                        ? Colors.transparent
                        : const Color(0xFF111214),
                    borderRadius: BorderRadius.circular(
                      widget.transparentBackground ? 0 : 24,
                    ),
                  ),
                  child: Padding(
                    padding: _callTileAreaPadding(constraints),
                    child: LayoutBuilder(
                      builder: (context, tileConstraints) {
                        return Column(
                          children: [
                            Expanded(
                              child: buildFocusedTile(
                                focusedTile,
                                tiles.length,
                              ),
                            ),
                            if (secondaryTiles.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              buildTileRail(secondaryTiles, tileConstraints),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          );

    final receiverProbeRenderSurface = _buildReceiverProbeRenderSurface();
    final showDiagnosticsOverlay =
        preferences.developerUiVisible &&
        preferences.showCallStreamStats.value &&
        _diagnosticsOverlayVisible;
    if (!showDiagnosticsOverlay && receiverProbeRenderSurface == null) {
      return content;
    }

    return Stack(
      children: [
        Positioned.fill(child: content),
        if (showDiagnosticsOverlay)
          Positioned(top: 12, left: 12, child: buildDiagnosticsOverlay()),
        if (receiverProbeRenderSurface != null) receiverProbeRenderSurface,
      ],
    );
  }

  Widget _buildSecondaryCallSurface({
    required List<_CallTileData> tiles,
    required List<_CallTileData> secondaryTiles,
    required bool hasPoppedStreams,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final body = tiles.isEmpty
            ? Center(
                child: tiamat.Text.labelLow(
                  hasPoppedStreams
                      ? "All streams are currently popped out."
                      : "Waiting for streams...",
                ),
              )
            : _buildCompactSecondaryCallLayout(
                tiles: tiles,
                secondaryTiles: secondaryTiles,
                constraints: constraints,
              );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showPictureInPictureControls,
          child: Semantics(
            label: 'Picture in picture call surface',
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  body,
                  if (_pipControlsVisible || widget.forceControlsVisible)
                    _buildPictureInPictureControlsOverlay(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactSecondaryCallLayout({
    required List<_CallTileData> tiles,
    required List<_CallTileData> secondaryTiles,
    required BoxConstraints constraints,
  }) {
    final explicitFocusedTile = focusedTileId == null
        ? null
        : tiles.tryFirstWhere(
            (tile) => tile.tileId == focusedTileId && !_isTileVideoHidden(tile),
          );
    if (tiles.length == 1) {
      return _buildCallTile(
        tiles.first,
        key: ValueKey("call_pip_single_${tiles.first.tileId}"),
        focused: true,
      );
    }

    if (explicitFocusedTile != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildCallTile(
            explicitFocusedTile,
            key: ValueKey("call_pip_focused_${explicitFocusedTile.tileId}"),
            focused: true,
            onTap: showEqualLayout,
          ),
          if (secondaryTiles.isNotEmpty)
            Positioned(
              right: 10,
              bottom: 10,
              child: _buildCompactPipParticipantCountBadge(tiles.length),
            ),
        ],
      );
    }

    if (tiles.length == 2) {
      return Row(
        children: [
          for (final tile in tiles) ...[
            Expanded(
              child: _buildCallTile(
                tile,
                key: ValueKey("call_pip_pair_${tile.tileId}"),
                focused: false,
                onTap: () => focusTile(tile),
              ),
            ),
            if (!identical(tile, tiles.last)) const SizedBox(width: 6),
          ],
        ],
      );
    }

    final visibleTileCount = _compactPipTileLimit(tiles.length);
    final visibleTiles = tiles.take(visibleTileCount).toList(growable: false);
    return Stack(
      fit: StackFit.expand,
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(6),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleTiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: constraints.maxWidth < 220 ? 1 : 2,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: constraints.maxWidth < 220 ? 16 / 9 : 1,
          ),
          itemBuilder: (context, index) {
            final tile = visibleTiles[index];
            return _buildCallTile(
              tile,
              key: ValueKey("call_pip_grid_${tile.tileId}"),
              focused: false,
              onTap: () => focusTile(tile),
            );
          },
        ),
        if (tiles.length > visibleTileCount)
          Positioned(
            right: 10,
            bottom: 10,
            child: _buildCompactPipParticipantCountBadge(tiles.length),
          ),
      ],
    );
  }

  Widget _buildCompactPipParticipantCountBadge(int participantCount) {
    return Semantics(
      label: '$participantCount participants in call',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(190),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withAlpha(60)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: tiamat.Text.labelLow('$participantCount'),
        ),
      ),
    );
  }

  Widget _buildPictureInPictureControlsOverlay() {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withAlpha(70)),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _pictureInPictureControlButton(
                  icon: Icons.close_rounded,
                  semanticLabel: 'Close picture in picture',
                  onPressed: _closePictureInPictureSurface,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _pictureInPictureControlButton(
                  icon: Icons.keyboard_return_rounded,
                  semanticLabel: 'Return to call',
                  onPressed: _returnFromPictureInPictureSurface,
                ),
              ),
            ),
            Center(
              child: _pictureInPictureControlButton(
                icon: Icons.call_end_rounded,
                semanticLabel: 'Hang up call',
                transparentColor: _transparentControlColor(
                  Theme.of(context).colorScheme.error,
                ),
                failureMessage: 'Could not leave the call. Please try again.',
                onPressed: _hangUpFromPictureInPictureSurface,
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _pictureInPictureControlButton(
                  icon: Icons.open_in_full_rounded,
                  semanticLabel: 'Open call full screen',
                  onPressed: _openPictureInPictureFullScreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pictureInPictureControlButton({
    required IconData icon,
    required String semanticLabel,
    required FutureOr<void> Function() onPressed,
    Color? transparentColor,
    String? failureMessage,
  }) {
    return _callControlButton(
      radius: 22,
      icon: icon,
      transparentColor: transparentColor,
      iconColor: Colors.white,
      semanticLabel: semanticLabel,
      minimumSize: 44,
      onPressed: onPressed,
      failureMessage: failureMessage,
    );
  }

  void _showPictureInPictureControls() {
    _pipControlsAutoHideTimer?.cancel();
    setState(() {
      _pipControlsVisible = true;
    });
    if (widget.forceControlsVisible) {
      return;
    }
    _pipControlsAutoHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _pipControlsVisible = false;
      });
    });
  }

  Future<void> _closePictureInPictureSurface() async {
    callPopoutController.restoreSession(widget.currentSession.sessionId);
    await MobileCallPopoutController.exitPictureInPicture(reason: 'close');
  }

  Future<void> _returnFromPictureInPictureSurface() async {
    callPopoutController.restoreSession(widget.currentSession.sessionId);
    await MobileCallPopoutController.exitPictureInPicture(reason: 'return');
    EventBus.openRoom.add((
      widget.currentSession.roomId,
      widget.currentSession.client.identifier,
    ));
  }

  Future<void> _openPictureInPictureFullScreen() async {
    callPopoutController.restoreSession(widget.currentSession.sessionId);
    await MobileCallPopoutController.exitPictureInPicture(reason: 'fullscreen');
    EventBus.openRoom.add((
      widget.currentSession.roomId,
      widget.currentSession.client.identifier,
    ));
  }

  Future<void> _hangUpFromPictureInPictureSurface() async {
    callPopoutController.clearForSession(widget.currentSession.sessionId);
    await (widget.hangUp ?? widget.currentSession.hangUpCall).call();
    await MobileCallPopoutController.exitPictureInPicture(reason: 'hang_up');
  }

  Widget? _buildReceiverProbeRenderSurface() {
    if (!preferences.developerUiVisible) {
      return null;
    }
    final session = widget.currentSession;
    if (session is! MatrixLivekitVoipSession ||
        session.inProcessReceiverProbeSnapshot?.mode !=
            MatrixLivekitReceiverProbeMode.render) {
      return null;
    }

    return Positioned(
      top: 12,
      right: 12,
      child: _ReceiverProbeRenderSurface(
        session: session,
        renderer: session.inProcessReceiverProbeRenderer,
      ),
    );
  }

  /// Run the media-control pass after the frame instead of inside it.
  ///
  /// [_applyReceivePriorities] issues real track mutes, local playback volume
  /// writes and SFU receive-priority changes. Calling it from `build()` made
  /// every rebuild a media-control event, and CallView rebuilds for reasons
  /// that have nothing to do with audio - the 2s diagnostics tick, presence,
  /// activity, one rebuild per `m.call.member` event during backward
  /// pagination. That is the substrate for the volume/mute flapping class.
  ///
  /// Two properties matter here. The pass now runs *outside* the build phase,
  /// so a media write can no longer happen while the tree is being laid out.
  /// And several builds in one frame collapse into one pass against the latest
  /// tile list, instead of re-issuing the same decision five to seven times.
  ///
  /// Deliberately **not** done here: skipping the pass when the inputs are
  /// unchanged. The decision reads live stream state that this widget does not
  /// own, so a signature-based skip needs the desired/applied split from
  /// `docs/plans/local-playback-mute-ownership-structural-plan.md` to be safe -
  /// a wrong skip is permanently silent audio, which is worse than the flapping
  /// it would fix.
  void _scheduleMediaControl(
    List<_CallTileData> tiles,
    _CallTileData? focusedTile,
  ) {
    _pendingMediaControlTiles = tiles;
    _pendingMediaControlFocusedTile = focusedTile;
    if (_mediaControlPassScheduled) {
      return;
    }

    _mediaControlPassScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mediaControlPassScheduled = false;
      final pendingTiles = _pendingMediaControlTiles;
      final pendingFocusedTile = _pendingMediaControlFocusedTile;
      _pendingMediaControlTiles = null;
      _pendingMediaControlFocusedTile = null;
      if (!mounted || pendingTiles == null) {
        return;
      }

      _applyReceivePriorities(pendingTiles, pendingFocusedTile);
    });
  }

  void _applyReceivePriorities(
    List<_CallTileData> tiles,
    _CallTileData? focusedTile,
  ) {
    _syncHiddenTileAudioMute(tiles);

    final visibleVideoStreamCount = tiles
        .where((tile) => tile.hasVisual && _hasVisibleReceiverSurface(tile))
        .length;
    final visibleScreenshareCount = tiles
        .where((tile) => tile.isScreenshare && _hasVisibleReceiverSurface(tile))
        .length;

    for (final tile in tiles) {
      final fullscreen = _isTileFullscreen(tile);
      final priority = _resolveCallViewReceivePriority(
        type: tile.primaryStream.type,
        direction: tile.primaryStream.direction,
        hidden: _isTileVideoHidden(tile),
        focused: focusedTile?.tileId == tile.tileId && !showEqualTileLayout,
        fullscreen: fullscreen,
        poppedOut: false,
        visibleVideoStreamCount: visibleVideoStreamCount,
        visibleScreenshareCount: visibleScreenshareCount,
      );
      unawaited(_setCallViewReceivePriority(tile.primaryStream, priority));
      final audioStream = tile.audioStream;
      if (audioStream != null) {
        unawaited(
          _setCallViewReceivePriority(
            audioStream,
            VoipStreamReceivePriority.high,
          ),
        );
      }
    }
  }

  bool _isTileFullscreen(_CallTileData tile) {
    return _fullscreenTileIds.contains(tile.tileId);
  }

  bool _hasVisibleReceiverSurface(_CallTileData tile) {
    return _isTileFullscreen(tile) || !_isTileVideoHidden(tile);
  }

  Widget buildDiagnosticsOverlay() {
    final lines = _redactCallDiagnosticLines(_diagnosticsOverlayLines());

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430, maxHeight: 230),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(190),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: tiamat.IconButton(
                    icon: Icons.copy,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: lines.join('\n')));
                    },
                  ),
                ),
                ...lines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: tiamat.Text.labelLow(line),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _diagnosticsOverlayLines() {
    return <String>[
      ..._routeSfuDiagnosticsLines(includeHeader: false),
      ..._mediaPipelineDiagnosticsLines(includeHeader: false),
      // Only present while measuring, so the overlay does not grow a permanent
      // empty section for a developer feature that is off by default.
      ...ParticipantLoudnessMonitor.instance.diagnosticLines(),
    ];
  }

  List<String> _routeSfuDiagnosticsLines({bool includeHeader = true}) {
    final snapshot = widget.currentSession.diagnosticsSnapshot;
    final livekitSession = widget.currentSession is MatrixLivekitVoipSession
        ? widget.currentSession as MatrixLivekitVoipSession
        : null;
    return <String>[
      if (includeHeader) 'Route / SFU:',
      'Adaptive: ${snapshot.adaptiveStreamEnabled ? 'on' : 'off'}  '
          'Dynacast: ${snapshot.dynacastEnabled ? 'on' : 'off'}  '
          'Simulcast: ${snapshot.screenShareSimulcastEnabled ? 'on' : 'off'}',
      if (snapshot.adaptiveFallbackEnabled)
        'Fallback: ${snapshot.adaptiveFallbackReason ?? 'watching'}',
      if (livekitSession != null)
        'Server loopback: ${livekitSession.serverAudioLoopbackDiagnosticLabel}',
      if (snapshot.iceTransportSummary != null)
        'ICE: ${snapshot.iceTransportSummary}',
      if (snapshot.hasParticipants) ...[
        'Clients:',
        ...snapshot.participants.map(_participantDiagnosticLine),
      ],
    ];
  }

  List<String> _mediaPipelineDiagnosticsLines({bool includeHeader = true}) {
    final snapshot = widget.currentSession.diagnosticsSnapshot;
    return <String>[
      if (includeHeader) 'Capture / encode / render:',
      'Profile: ${snapshot.screenShareProfileLabel}',
      if (snapshot.screenShareProfileDetails != null)
        'Profile details: ${snapshot.screenShareProfileDetails}',
      if (snapshot.shareSessionDiagnostics != null)
        ...snapshot.shareSessionDiagnostics!.lines(),
      if (!snapshot.hasTracks) 'No LiveKit stats yet.',
      ...snapshot.tracks.map(_diagnosticLine),
    ];
  }

  NoiseSuppressionPipelineMode? _rnnoisePipelineModeForHookPreference(
    String hookMode,
  ) {
    return switch (hookMode) {
      'identity' => NoiseSuppressionPipelineMode.identity,
      'off' => NoiseSuppressionPipelineMode.off,
      _ => null,
    };
  }

  Future<void> _delayForRnnoiseBatch(
    Duration duration,
    bool Function() isCanceled,
  ) async {
    final deadline = DateTime.now().add(duration);
    while (!isCanceled() && DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 250)
            ? remaining
            : const Duration(milliseconds: 250),
      );
    }
  }

  Future<void> _applyRnnoiseDiagnosticBatchScenario(
    _RnnoiseDiagnosticBatchScenario scenario,
  ) async {
    await preferences.voipAudioCaptureTapOrderScenario.set(scenario.scenario);
    await preferences.voipNoiseSuppressionHookMode.set(
      scenario.hookModePreference,
    );
    await preferences.voipNoiseSuppressionEnabled.set(
      scenario.noiseSuppressionEnabled,
    );
    await NoiseSuppressionService.instance.applyPreference(
      scenario.noiseSuppressionEnabled,
    );
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _rnnoisePipelineModeForHookPreference(scenario.hookModePreference),
    );
    if (scenario.noiseSuppressionEnabled) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
  }

  Future<void> _restoreRnnoiseDiagnosticBatchPreferences({
    required bool originalEnabled,
    required String originalHookMode,
    required String originalScenario,
  }) async {
    await preferences.voipAudioCaptureTapOrderScenario.set(originalScenario);
    await preferences.voipNoiseSuppressionHookMode.set(originalHookMode);
    await preferences.voipNoiseSuppressionEnabled.set(originalEnabled);
    await NoiseSuppressionService.instance.applyPreference(originalEnabled);
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _rnnoisePipelineModeForHookPreference(originalHookMode),
    );
    if (originalEnabled) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
  }

  Future<_RnnoiseDiagnosticBatchResult> _runRnnoiseDiagnosticCaptureBatch({
    required bool Function() isCanceled,
    required void Function(String progress) onProgress,
    Duration captureDuration = const Duration(seconds: 10),
    Duration settleDuration = const Duration(seconds: 2),
  }) async {
    final originalEnabled = preferences.voipNoiseSuppressionEnabled.value;
    final originalHookMode = preferences.voipNoiseSuppressionHookMode.value;
    final originalScenario = preferences.voipAudioCaptureTapOrderScenario.value;
    var completed = 0;
    var writtenFiles = 0;
    final failures = <String>[];

    try {
      onProgress('preparing tap-order capture...');
      await NoiseSuppressionService.instance.stopDiagnosticCapture();
      String? wasapiDeviceId;
      try {
        wasapiDeviceId = await WebrtcDefaultDevices.getDefaultMicrophoneId();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to resolve RNNoise batch WASAPI microphone id',
        );
      }

      for (
        var index = 0;
        index < _rnnoiseTapOrderBatchScenarios.length;
        index++
      ) {
        if (isCanceled()) {
          break;
        }

        final scenario = _rnnoiseTapOrderBatchScenarios[index];
        final scenarioNumber = index + 1;
        final prefix =
            '$scenarioNumber/${_rnnoiseTapOrderBatchScenarios.length} '
            '${scenario.label}';

        onProgress('$prefix: applying capture profile...');
        await _applyRnnoiseDiagnosticBatchScenario(scenario);

        // LiveKit recreates the microphone track from the changed capture
        // signature. Give that refresh a short window before recording stages.
        await _delayForRnnoiseBatch(settleDuration, isCanceled);
        if (isCanceled()) {
          break;
        }

        final directoryPath = await createNoiseSuppressionDiagnosticDirectory(
          captureLabel: 'call-batch-$scenarioNumber-${scenario.scenario}',
          stageMask: NoiseSuppressionDiagnosticStageMask.all,
          includeWasapiSidecar: true,
        );
        onProgress('$prefix: recording ${captureDuration.inSeconds}s...');
        final result = await NoiseSuppressionService.instance
            .startDiagnosticCapture(
              directoryPath: directoryPath,
              duration: captureDuration,
              stageMask: NoiseSuppressionDiagnosticStageMask.all,
              includeWasapiSidecar: true,
              wasapiDeviceId: wasapiDeviceId,
            );

        if (!result.status.diagnosticCaptureActive) {
          failures.add('$prefix did not start: ${result.status.reason}');
          continue;
        }

        await _delayForRnnoiseBatch(
          captureDuration + const Duration(seconds: 1),
          isCanceled,
        );

        final stoppedStatus = await NoiseSuppressionService.instance
            .stopDiagnosticCapture();
        await collectNoiseSuppressionDiagnosticReportBundle(
          directoryPath: directoryPath,
        );
        completed++;
        writtenFiles += stoppedStatus.diagnosticCaptureWrittenFiles;
        if (stoppedStatus.diagnosticCaptureWrittenFiles == 0) {
          final reason = stoppedStatus.diagnosticCaptureLastError.isEmpty
              ? stoppedStatus.reason
              : stoppedStatus.diagnosticCaptureLastError;
          failures.add('$prefix wrote no files: $reason');
        }

        // Let native WASAPI/hook shutdown settle before switching constraints.
        await _delayForRnnoiseBatch(
          const Duration(milliseconds: 500),
          isCanceled,
        );
      }
    } finally {
      try {
        await NoiseSuppressionService.instance.stopDiagnosticCapture();
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to stop RNNoise capture during batch cleanup',
        );
      }
      try {
        await _restoreRnnoiseDiagnosticBatchPreferences(
          originalEnabled: originalEnabled,
          originalHookMode: originalHookMode,
          originalScenario: originalScenario,
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to restore RNNoise diagnostic batch preferences',
        );
      }
    }

    return _RnnoiseDiagnosticBatchResult(
      completed: completed,
      writtenFiles: writtenFiles,
      canceled: isCanceled(),
      failures: List.unmodifiable(failures),
    );
  }

  void _openCallDiagnosticsLogMenu() {
    var saving = false;
    var reporting = false;
    var rnnoiseDiagnosticCaptureBusy = false;
    var rnnoiseDiagnosticBatchRunning = false;
    var rnnoiseDiagnosticBatchCancelRequested = false;
    String? rnnoiseDiagnosticCaptureMessage;
    var rnnoiseDiagnosticCaptureId = 0;
    var collapsed = false;
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> finishRnnoiseDiagnosticCapture({
              required int captureId,
            }) async {
              if (captureId != rnnoiseDiagnosticCaptureId) {
                return;
              }
              try {
                final status = await NoiseSuppressionService.instance
                    .stopDiagnosticCapture();
                final path = NoiseSuppressionService
                    .instance
                    .diagnosticCaptureDirectoryPath;
                NoiseSuppressionDiagnosticReportBundle? reportBundle;
                if (path != null) {
                  reportBundle =
                      await collectNoiseSuppressionDiagnosticReportBundle(
                        directoryPath: path,
                      );
                }
                if (!dialogContext.mounted) {
                  return;
                }
                if (captureId != rnnoiseDiagnosticCaptureId) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureBusy = false;
                  rnnoiseDiagnosticCaptureMessage =
                      status.diagnosticCaptureWrittenFiles > 0
                      ? rnnoiseDiagnosticCaptureCompleteDisplayMessage(
                          writtenFiles: status.diagnosticCaptureWrittenFiles,
                          directoryLabel: reportBundle?.directoryLabel,
                        )
                      : 'No RNNoise diagnostic WAV files were written: '
                            '${status.diagnosticCaptureLastError.isEmpty ? status.reason : status.diagnosticCaptureLastError}.';
                });
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to finish RNNoise diagnostic capture',
                );
                if (!dialogContext.mounted ||
                    captureId != rnnoiseDiagnosticCaptureId) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureBusy = false;
                  rnnoiseDiagnosticCaptureMessage =
                      'RNNoise WAV capture stop failed: $error';
                });
              }
            }

            Future<void> toggleRnnoiseDiagnosticCapture() async {
              if (rnnoiseDiagnosticCaptureBusy ||
                  rnnoiseDiagnosticBatchRunning ||
                  !PlatformUtils.isWindows) {
                return;
              }

              setDialogState(() {
                rnnoiseDiagnosticCaptureBusy = true;
                rnnoiseDiagnosticCaptureMessage = null;
              });

              try {
                final status = NoiseSuppressionService.instance.status;
                if (status.diagnosticCaptureActive) {
                  rnnoiseDiagnosticCaptureId++;
                  final stoppedStatus = await NoiseSuppressionService.instance
                      .stopDiagnosticCapture();
                  final path = NoiseSuppressionService
                      .instance
                      .diagnosticCaptureDirectoryPath;
                  NoiseSuppressionDiagnosticReportBundle? reportBundle;
                  if (path != null) {
                    reportBundle =
                        await collectNoiseSuppressionDiagnosticReportBundle(
                          directoryPath: path,
                        );
                  }
                  if (!dialogContext.mounted) {
                    return;
                  }
                  setDialogState(() {
                    rnnoiseDiagnosticCaptureBusy = false;
                    rnnoiseDiagnosticCaptureMessage =
                        stoppedStatus.diagnosticCaptureWrittenFiles > 0
                        ? rnnoiseDiagnosticCaptureCompleteDisplayMessage(
                            writtenFiles:
                                stoppedStatus.diagnosticCaptureWrittenFiles,
                            directoryLabel: reportBundle?.directoryLabel,
                          )
                        : 'No RNNoise diagnostic WAV files were written: '
                              '${stoppedStatus.diagnosticCaptureLastError.isEmpty ? stoppedStatus.reason : stoppedStatus.diagnosticCaptureLastError}.';
                  });
                  return;
                }

                await NoiseSuppressionService.instance.applyDiagnosticHookMode(
                  _rnnoisePipelineModeForHookPreference(
                    preferences.voipNoiseSuppressionHookMode.value,
                  ),
                );
                final directoryPath =
                    await createNoiseSuppressionDiagnosticDirectory(
                      captureLabel: 'call-panel',
                      stageMask: NoiseSuppressionDiagnosticStageMask.all,
                      includeWasapiSidecar: true,
                    );
                final microphoneId =
                    await WebrtcDefaultDevices.getDefaultMicrophoneId();
                final result = await NoiseSuppressionService.instance
                    .startDiagnosticCapture(
                      directoryPath: directoryPath,
                      duration: const Duration(seconds: 10),
                      stageMask: NoiseSuppressionDiagnosticStageMask.all,
                      includeWasapiSidecar: true,
                      wasapiDeviceId: microphoneId,
                    );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureBusy = false;
                  rnnoiseDiagnosticCaptureMessage =
                      result.status.diagnosticCaptureActive
                      ? 'Capturing 10 seconds of local tap-order WAV stages; '
                            'files will write automatically.'
                      : 'Could not start RNNoise WAV capture: '
                            '${result.status.reason}.';
                });
                if (result.status.diagnosticCaptureActive) {
                  final captureId = ++rnnoiseDiagnosticCaptureId;
                  unawaited(
                    Future<void>.delayed(
                      const Duration(seconds: 11),
                      () =>
                          finishRnnoiseDiagnosticCapture(captureId: captureId),
                    ),
                  );
                }
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to toggle RNNoise diagnostic capture',
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureBusy = false;
                  rnnoiseDiagnosticCaptureMessage =
                      'RNNoise WAV capture failed: $error';
                });
              }
            }

            Future<void> cancelRnnoiseDiagnosticBatch() async {
              if (!rnnoiseDiagnosticBatchRunning) {
                return;
              }
              rnnoiseDiagnosticBatchCancelRequested = true;
              rnnoiseDiagnosticCaptureId++;
              setDialogState(() {
                rnnoiseDiagnosticCaptureMessage =
                    'Canceling RNNoise WAV capture batch...';
              });
              try {
                await NoiseSuppressionService.instance.stopDiagnosticCapture();
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to stop RNNoise capture during batch cancel',
                );
              }
            }

            Future<void> runRnnoiseDiagnosticCaptureBatch() async {
              if (rnnoiseDiagnosticCaptureBusy || !PlatformUtils.isWindows) {
                return;
              }

              setDialogState(() {
                rnnoiseDiagnosticCaptureBusy = true;
                rnnoiseDiagnosticBatchRunning = true;
                rnnoiseDiagnosticBatchCancelRequested = false;
                rnnoiseDiagnosticCaptureMessage =
                    'Starting RNNoise WAV capture batch...';
              });

              try {
                final result = await _runRnnoiseDiagnosticCaptureBatch(
                  isCanceled: () =>
                      rnnoiseDiagnosticBatchCancelRequested ||
                      !dialogContext.mounted,
                  onProgress: (progress) {
                    if (!dialogContext.mounted) {
                      return;
                    }
                    setDialogState(() {
                      rnnoiseDiagnosticCaptureMessage = progress;
                    });
                  },
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureMessage = result.summary;
                });
              } catch (error, stackTrace) {
                Log.onError(
                  error,
                  stackTrace,
                  content: 'Failed to run RNNoise diagnostic capture batch',
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  rnnoiseDiagnosticCaptureMessage =
                      'RNNoise WAV capture batch failed: $error';
                });
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    rnnoiseDiagnosticCaptureBusy = false;
                    rnnoiseDiagnosticBatchRunning = false;
                    rnnoiseDiagnosticBatchCancelRequested = false;
                  });
                }
              }
            }

            final summaryLines = _redactCallDiagnosticLines(
              _callDiagnosticsSummaryLines(),
            );
            final routeLines = _redactCallDiagnosticLines(
              _routeSfuDiagnosticsLines(),
            );
            final streamLines = _redactCallDiagnosticLines(
              _mediaPipelineDiagnosticsLines(),
            );
            final logLines = _redactCallDiagnosticLines(_relatedCallLogLines());
            // Already sanitized at the monitor boundary (hashed participant and
            // track keys), but redacted alongside everything else so one policy
            // governs the whole sheet.
            final loudnessLines = _redactCallDiagnosticLines(
              ParticipantLoudnessMonitor.instance.diagnosticLines(),
            );
            final loudnessMeasuring =
                preferences.voipRemoteParticipantLoudnessMeasurement.value;
            final rnnoiseStatus = NoiseSuppressionService.instance.status;
            final rnnoiseCaptureRunning = rnnoiseStatus.diagnosticCaptureActive;
            final allLines = <String>[
              'Inter Galactic Call Diagnostics',
              'Collected: ${DateTime.now().toUtc().toIso8601String()}',
              '',
              '== Summary ==',
              ...summaryLines,
              '',
              '== Route / SFU ==',
              ...routeLines,
              '',
              '== Capture / Encode / Render Stats ==',
              ...streamLines,
              if (loudnessLines.isNotEmpty) ...[
                '',
                '== Participant Loudness (measurement only) ==',
                ...loudnessLines,
              ],
              '',
              '== Related Logs ==',
              ...logLines,
            ];

            return AlertDialog(
              alignment: collapsed ? Alignment.topRight : Alignment.center,
              insetPadding: collapsed
                  ? const EdgeInsets.all(16)
                  : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              titlePadding: EdgeInsets.fromLTRB(
                collapsed ? 16 : 20,
                collapsed ? 12 : 16,
                12,
                0,
              ),
              contentPadding: EdgeInsets.fromLTRB(
                collapsed ? 16 : 16,
                8,
                collapsed ? 16 : 16,
                collapsed ? 12 : 16,
              ),
              title: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Call Diagnostics',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: collapsed
                        ? 'Expand diagnostics'
                        : 'Collapse diagnostics',
                    icon: Icon(
                      collapsed ? Icons.unfold_more : Icons.unfold_less,
                    ),
                    onPressed: () {
                      setDialogState(() => collapsed = !collapsed);
                    },
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setDialogState(() {}),
                  ),
                  IconButton(
                    tooltip: 'Copy all',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: allLines.join('\n')),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: loudnessMeasuring
                        ? 'Stop participant loudness measurement'
                        : 'Measure participant loudness (no playback change)',
                    icon: Icon(
                      loudnessMeasuring
                          ? Icons.graphic_eq
                          : Icons.graphic_eq_outlined,
                    ),
                    onPressed: () {
                      // The monitor follows the call from CallManager and
                      // reconciles on its own timer, so flipping this is all
                      // that is needed to start or stop measuring mid-call.
                      //
                      // The write is guarded rather than discarded: a failed
                      // persist used to be silent while the icon still flipped,
                      // so the toggle looked applied and came back off.
                      unawaited(
                        CallPreferenceOperationGuard.run(
                          operation: () => preferences
                              .voipRemoteParticipantLoudnessMeasurement
                              .set(!loudnessMeasuring),
                          content:
                              'Recovered participant loudness measurement '
                              'preference failure',
                          source: 'call-volume-preference',
                        ),
                      );
                      setDialogState(() {});
                    },
                  ),
                  if (loudnessMeasuring)
                    IconButton(
                      tooltip: 'Export loudness measurement session',
                      icon: const Icon(Icons.download),
                      onPressed: () async {
                        // `exportReport` writes a file, so it can throw as well
                        // as return null. An exception out of this async
                        // callback reaches no handler: no snackbar, no log, and
                        // the press just looks ignored. The null return already
                        // has a message; give the throw the same one.
                        String? path;
                        try {
                          path = await ParticipantLoudnessMonitor.instance
                              .exportReport();
                        } catch (error, stackTrace) {
                          Log.onError(
                            error,
                            stackTrace,
                            content: 'Participant loudness export failed',
                            category: LogCategory.livekit,
                            source: 'participant-loudness',
                          );
                        }
                        if (!context.mounted) {
                          return;
                        }
                        // `maybeOf`, like every other snackbar in this file:
                        // this runs from a dialog context that need not have a
                        // ScaffoldMessenger above it, and `of` throws there.
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              path == null
                                  ? 'Loudness export failed'
                                  : 'Loudness session written to $path',
                            ),
                          ),
                        );
                      },
                    ),
                  if (widget.currentSession is MatrixLivekitVoipSession)
                    IconButton(
                      tooltip: _streamTestRunning
                          ? 'Stream test running: '
                                '${_streamTestProgressLabel ?? 'preparing...'}'
                          : 'Run stream test',
                      icon: _streamTestRunning
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.speed),
                      onPressed: _streamTestRunning
                          ? null
                          : () {
                              unawaited(
                                _runCallViewStreamTestAction(() async {
                                  void updateProgress(String? label) {
                                    if (dialogContext.mounted) {
                                      setDialogState(
                                        () => _streamTestProgressLabel = label,
                                      );
                                    } else if (mounted) {
                                      setState(
                                        () => _streamTestProgressLabel = label,
                                      );
                                    }
                                  }

                                  setDialogState(() {
                                    _streamTestRunning = true;
                                    _streamTestProgressLabel = 'preparing...';
                                  });
                                  try {
                                    final result = await _runStreamTestRunner(
                                      onProgress: updateProgress,
                                      onSourceSelectionStarting: () {
                                        if (!dialogContext.mounted) {
                                          return;
                                        }
                                        setDialogState(() => collapsed = true);
                                      },
                                      onSourceSelected: () {
                                        if (!dialogContext.mounted) {
                                          return;
                                        }
                                        setDialogState(() => collapsed = true);
                                      },
                                    );
                                    if (dialogContext.mounted) {
                                      setDialogState(() {
                                        _lastStreamTestResult = result;
                                        if (result == null) {
                                          _lastStreamTestReportWriteResult =
                                              null;
                                        }
                                      });
                                    }
                                  } finally {
                                    if (dialogContext.mounted) {
                                      setDialogState(() {
                                        _streamTestRunning = false;
                                        _streamTestProgressLabel = null;
                                      });
                                    } else if (mounted) {
                                      setState(() {
                                        _streamTestRunning = false;
                                        _streamTestProgressLabel = null;
                                      });
                                    }
                                  }
                                }, actionLabel: 'manual stream-test run'),
                              );
                            },
                    ),
                  if (PlatformUtils.isWindows)
                    IconButton(
                      tooltip: rnnoiseDiagnosticBatchRunning
                          ? 'Cancel RNNoise WAV batch'
                          : rnnoiseDiagnosticCaptureBusy
                          ? 'Updating RNNoise WAV capture...'
                          : 'Run RNNoise WAV batch',
                      icon: rnnoiseDiagnosticBatchRunning
                          ? const Icon(Icons.stop_circle_outlined)
                          : rnnoiseDiagnosticCaptureBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.playlist_play),
                      onPressed:
                          rnnoiseDiagnosticCaptureBusy &&
                              !rnnoiseDiagnosticBatchRunning
                          ? null
                          : rnnoiseDiagnosticBatchRunning
                          ? cancelRnnoiseDiagnosticBatch
                          : runRnnoiseDiagnosticCaptureBatch,
                    ),
                  if (PlatformUtils.isWindows)
                    IconButton(
                      tooltip: rnnoiseDiagnosticCaptureBusy
                          ? 'Updating RNNoise WAV capture...'
                          : rnnoiseCaptureRunning
                          ? 'Stop RNNoise WAV capture'
                          : 'Capture one RNNoise WAV set',
                      icon: rnnoiseDiagnosticCaptureBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              rnnoiseCaptureRunning
                                  ? Icons.stop_circle_outlined
                                  : Icons.multitrack_audio_outlined,
                            ),
                      onPressed: rnnoiseDiagnosticCaptureBusy
                          ? null
                          : toggleRnnoiseDiagnosticCapture,
                    ),
                  IconButton(
                    tooltip: reporting
                        ? 'Preparing report...'
                        : 'Report stream logs',
                    icon: reporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.outgoing_mail),
                    onPressed: reporting
                        ? null
                        : () async {
                            setDialogState(() => reporting = true);
                            try {
                              await _reportCallDiagnostics(allLines);
                            } finally {
                              if (dialogContext.mounted) {
                                setDialogState(() => reporting = false);
                              }
                            }
                          },
                  ),
                  IconButton(
                    tooltip: saving ? 'Saving...' : 'Save all',
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt),
                    onPressed: saving
                        ? null
                        : () async {
                            setDialogState(() => saving = true);
                            try {
                              await _saveCallDiagnosticsLog(allLines);
                            } finally {
                              if (dialogContext.mounted) {
                                setDialogState(() => saving = false);
                              }
                            }
                          },
                  ),
                ],
              ),
              content: collapsed
                  ? _collapsedCallDiagnosticsSummary()
                  : SizedBox(
                      width: min(MediaQuery.sizeOf(context).width * 0.86, 900),
                      height: min(
                        MediaQuery.sizeOf(context).height * 0.72,
                        620,
                      ),
                      child: DefaultTabController(
                        length: 4,
                        child: Column(
                          children: [
                            if (_streamTestRunning ||
                                _streamTestProgressLabel != null) ...[
                              _streamTestProgressBanner(),
                              const SizedBox(height: 8),
                            ],
                            if (PlatformUtils.isWindows &&
                                (rnnoiseDiagnosticCaptureBusy ||
                                    rnnoiseCaptureRunning ||
                                    rnnoiseDiagnosticCaptureMessage !=
                                        null)) ...[
                              _rnnoiseDiagnosticCaptureBanner(
                                busy: rnnoiseDiagnosticCaptureBusy,
                                running: rnnoiseCaptureRunning,
                                message: rnnoiseDiagnosticCaptureMessage,
                              ),
                              const SizedBox(height: 8),
                            ],
                            const TabBar(
                              tabs: [
                                Tab(text: 'Summary'),
                                Tab(text: 'Route'),
                                Tab(text: 'Stats'),
                                Tab(text: 'Logs'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _diagnosticLogTab(summaryLines),
                                  _diagnosticLogTab(routeLines),
                                  _diagnosticLogTab(streamLines),
                                  _diagnosticLogTab(logLines),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Future<void> _reportCallDiagnostics(List<String> lines) async {
    Log.i(
      'Call diagnostics report snapshot\n'
      '${_redactCallDiagnosticText(lines.join('\n'))}',
      category: LogCategory.webrtc,
      source: 'call-diagnostics-report',
    );

    await showReportBugDialog(
      context,
      template: BugReportTemplate.callStreamLogs,
      includeLogs: true,
      includeDiagnostics: true,
    );
  }

  Future<void> _pollStreamTestAutomationCommand() async {
    if (!(BuildConfig.DEBUG || kDebugMode) ||
        !PlatformUtils.isWindows ||
        _streamTestRunning ||
        widget.currentSession is! MatrixLivekitVoipSession ||
        !mounted) {
      return;
    }
    if (_streamTestAutomationPollInFlight) {
      return;
    }
    _streamTestAutomationPollInFlight = true;
    try {
      await _pollStreamTestAutomationCommandLocked();
    } finally {
      _streamTestAutomationPollInFlight = false;
    }
  }

  Future<void> _pollStreamTestAutomationCommandLocked() async {
    if (_streamTestRunning || !mounted) {
      return;
    }
    final channel = const StreamTestAutomationCommandChannel();
    StreamTestAutomationRequest? request;
    try {
      request = await channel.takePending();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to read stream-test automation command',
      );
      return;
    }
    if (request == null || !mounted || _streamTestRunning) {
      return;
    }

    Log.i(
      'Stream test automation request ${request.id} starting',
      category: LogCategory.webrtc,
      source: 'stream-test-automation',
    );
    setState(() {
      _streamTestRunning = true;
      _streamTestProgressLabel = 'automation ${request!.id}: preparing...';
      _lastStreamTestResult = null;
      _lastStreamTestReportWriteResult = null;
    });

    StreamTestRunResult? result;
    String? error;
    try {
      result = await _runStreamTestRunner(
        automationConfig: _streamTestConfigFromAutomationRequest(request),
        allowManualSourcePicker: false,
        onProgress: (label) {
          if (!mounted) {
            return;
          }
          setState(() {
            _streamTestProgressLabel = label == null
                ? null
                : 'automation ${request!.id}: $label';
          });
        },
      );
      if (mounted) {
        setState(() {
          _lastStreamTestResult = result;
          if (result == null) {
            _lastStreamTestReportWriteResult = null;
          }
        });
      }
      if (result == null) {
        error = 'stream test automation did not produce a result';
      } else if (result.error != null) {
        error = result.error;
      }
    } catch (exception, stackTrace) {
      error = exception.toString();
      Log.onError(
        exception,
        stackTrace,
        content: 'Stream test automation failed',
      );
    } finally {
      try {
        await channel.complete(
          request,
          reportPath:
              _lastStreamTestReportWriteResult?.markdownPath ??
              _lastStreamTestReportWriteResult?.jsonPath,
          error: error,
        );
      } catch (completionError, stackTrace) {
        Log.onError(
          completionError,
          stackTrace,
          content: 'Failed to write stream-test automation completion',
        );
      }
      if (mounted) {
        setState(() {
          _streamTestRunning = false;
          _streamTestProgressLabel = null;
        });
      }
    }
  }

  _StreamTestDialogConfig _streamTestConfigFromAutomationRequest(
    StreamTestAutomationRequest request,
  ) {
    final preferHardwareEncoding =
        request.preferHardwareEncoding ??
        (PlatformUtils.isWindows &&
            preferences.streamHardwareEncodingFirst.value);
    final presets = request.presetKeys
        .map(
          (key) => ScreenShareProfileConfig.forPreferenceKey(
            key,
            preferHardwareEncoding: preferHardwareEncoding,
          ),
        )
        .toList(growable: false);
    final automationPresets = _applyAutomationPublicationHandoffCap(
      presets.isEmpty
          ? [
              ScreenShareProfileConfig.forPreferenceKey(
                ScreenShareQualityProfile.smooth.storageKey,
                preferHardwareEncoding: preferHardwareEncoding,
              ),
              ScreenShareProfileConfig.forPreferenceKey(
                ScreenShareQualityProfile.balanced.storageKey,
                preferHardwareEncoding: preferHardwareEncoding,
              ),
              ScreenShareProfileConfig.forPreferenceKey(
                ScreenShareQualityProfile.highQuality.storageKey,
                preferHardwareEncoding: preferHardwareEncoding,
              ),
            ]
          : presets,
      request,
    );
    final backendMode = _automationBackendMode(request.windowsBackendMode);
    return _StreamTestDialogConfig(
      presets: automationPresets,
      duration: request.duration,
      warmup: request.warmup,
      windowsCaptureBackendMode: backendMode,
      windowsCaptureBackendModes: request.compareWindowsBackends
          ? _streamTestWindowsCaptureBackendCompareModes
          : null,
      windowsCaptureDirtyRegionMode: request.forceFullFrameDirtyRegions
          ? WindowsScreenCaptureDirtyRegionMode.forceFullFrame
          : WindowsScreenCaptureDirtyRegionMode.auto,
      nativeFramePacingEnabled: request.nativeFramePacingEnabled,
      dummyNv12LiveSender: request.dummyNv12LiveSender,
      captureTestTargetEnabled: request.captureTarget.enabled,
      captureTestTargetWidth: request.captureTarget.width,
      captureTestTargetHeight: request.captureTarget.height,
      captureTestTargetMode: request.captureTarget.windowMode,
      captureTestTargetScene: request.captureTarget.scene,
      captureTestTargetFps: request.captureTarget.fps,
      automationSourceProcessId: request.sourceProcessId,
      automationSourceTitle: request.sourceTitle,
      publicationHandoffMaxWidth: request.publicationHandoffMaxWidth,
      publicationHandoffMaxHeight: request.publicationHandoffMaxHeight,
      publicationHandoffTargetFps: request.publicationHandoffTargetFps,
      receiverProbe: request.receiverProbe,
    );
  }

  List<ScreenShareProfileConfig> _applyAutomationPublicationHandoffCap(
    List<ScreenShareProfileConfig> presets,
    StreamTestAutomationRequest request,
  ) {
    final maxWidth = request.publicationHandoffMaxWidth;
    final maxHeight = request.publicationHandoffMaxHeight;
    final maxFps = request.publicationHandoffMaxFps;
    final targetFps = request.publicationHandoffTargetFps;
    final bitrateKbps = request.publicationHandoffBitrateKbps;
    final minBitrateKbps = request.publicationHandoffMinBitrateKbps;
    final singleLayer = request.publicationHandoffSingleLayer;
    if (maxWidth == null &&
        maxHeight == null &&
        maxFps == null &&
        targetFps == null &&
        bitrateKbps == null &&
        minBitrateKbps == null &&
        singleLayer == null) {
      return presets;
    }

    return presets
        .map((profile) {
          final baseLayer = profile.mainLayer;
          final effectiveMaxFps =
              maxFps?.clamp(1, 60).toInt() ?? baseLayer.maxFramerate;
          final maxBitrateBps = bitrateKbps == null
              ? baseLayer.maxBitrateBps
              : bitrateKbps.clamp(100, 64000).toInt() * 1000;
          final int? requestedMinBitrateBps = minBitrateKbps == null
              ? baseLayer.minBitrateBps
              : minBitrateKbps.clamp(1, 64000).toInt() * 1000;
          final minBitrateBps = requestedMinBitrateBps == null
              ? null
              : min(requestedMinBitrateBps, maxBitrateBps);
          final fitted = ScreenShareContainFit.fitWithin(
            sourceWidth: baseLayer.width,
            sourceHeight: baseLayer.height,
            maxWidth: maxWidth ?? baseLayer.width,
            maxHeight: maxHeight ?? baseLayer.height,
          );
          final clampedTargetFps = targetFps?.clamp(1, effectiveMaxFps).toInt();
          final clampedBaseTargetFps = baseLayer.targetFramerate
              ?.clamp(1, effectiveMaxFps)
              .toInt();
          return profile.copyWith(
            mainLayer: baseLayer.copyWith(
              width: fitted.width,
              height: fitted.height,
              maxFramerate: effectiveMaxFps,
              maxBitrateBps: maxBitrateBps,
              minBitrateBps: minBitrateBps,
              targetFramerate: clampedTargetFps ?? clampedBaseTargetFps,
            ),
            useSimulcast: singleLayer == true ? false : profile.useSimulcast,
          );
        })
        .toList(growable: false);
  }

  WindowsScreenCaptureBackendMode? _automationBackendMode(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null ||
        normalized.isEmpty ||
        normalized == 'app-default' ||
        normalized == 'appdefault' ||
        normalized == 'default') {
      return null;
    }
    return WindowsScreenCaptureBackendModeDetails.fromConstraintValue(
      normalized == 'native-default' ? 'default' : normalized,
    );
  }

  Future<String> _streamTestDiagnosticLogText({
    int maxFileBytes = 160 * 1024,
  }) async {
    final appLogs = await Log.recentText(maxFileBytes: maxFileBytes);
    final nativeLogs = await NativeWebrtcDiagnostics.recentText(
      maxFileBytes: maxFileBytes,
    );
    return [
      appLogs,
      nativeLogs,
    ].where((text) => text.trim().isNotEmpty).join('\n');
  }

  Future<StreamTestRunResult?> _runStreamTestRunner({
    void Function(String? label)? onProgress,
    VoidCallback? onSourceSelectionStarting,
    VoidCallback? onSourceSelected,
    _StreamTestDialogConfig? automationConfig,
    bool allowManualSourcePicker = true,
  }) async {
    final session = widget.currentSession;
    if (session is! MatrixLivekitVoipSession) {
      return null;
    }

    onProgress?.call(
      automationConfig == null ? 'choosing presets...' : 'loading command...',
    );
    final runnerConfig =
        automationConfig ?? await _showStreamTestConfigDialog();
    if (runnerConfig == null || runnerConfig.presets.isEmpty || !mounted) {
      return null;
    }

    final captureTargetConfig = runnerConfig.captureTestTargetConfig;
    GameCaptureTestTargetSession? captureTargetSession;
    GameCaptureTestTargetResult? captureTargetResult;
    if (captureTargetConfig.enabled) {
      onProgress?.call('launching capture target...');
      captureTargetSession = await createDefaultGameCaptureTestTargetLauncher()
          .launch(captureTargetConfig);
      captureTargetResult = captureTargetSession.launchResult;
      if (captureTargetResult.status != 'launched') {
        _showStreamTestSnackBar(
          'Capture target unavailable: '
          '${captureTargetResult.reason ?? captureTargetResult.status}',
        );
      }
    }

    ScreenCaptureSource? source;
    onProgress?.call(
      runnerConfig.dummyNv12LiveSender
          ? 'selecting dummy NV12 source...'
          : 'selecting source...',
    );
    onSourceSelectionStarting?.call();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) {
      if (captureTargetSession != null) {
        await captureTargetSession.stopAndCollect();
      }
      return null;
    }

    Log.i(
      'Stream test source picker opening',
      category: LogCategory.webrtc,
      source: 'stream-test-runner',
    );

    if (runnerConfig.dummyNv12LiveSender) {
      source = await _selectDummyNv12LiveSenderPlaceholderSource();
      if (source != null) {
        Log.i(
          'Stream test automation selected dummy NV12 live-sender '
          'placeholder source',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
      }
    }

    if (source == null && captureTargetResult?.status == 'launched') {
      onProgress?.call('selecting capture target window...');
      try {
        Log.i(
          'Stream test capture-target auto-selection starting '
          'timeout=${_streamTestAutoSelectTimeout.inSeconds}s',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        source = await WebrtcScreencaptureSource.findWindowByTitle(
          captureTargetConfig.title,
          shareAudio: false,
        ).timeout(_streamTestAutoSelectTimeout);
        if (source != null) {
          captureTargetResult = captureTargetResult!.withSelection(
            automatic: true,
          );
          Log.i(
            'Stream test auto-selected D3D11 capture target window',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        } else {
          Log.i(
            'Stream test capture-target auto-selection returned no match',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        }
      } on TimeoutException catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content:
              'Stream test capture-target auto-selection timed out '
              'after ${_streamTestAutoSelectTimeout.inSeconds}s',
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test capture-target auto-selection failed',
        );
      }
      if (source == null) {
        _showStreamTestSnackBar(
          'Capture target launched; select its window manually.',
        );
      }
    }

    final automationSourceProcessId = runnerConfig.automationSourceProcessId;
    if (source == null &&
        !allowManualSourcePicker &&
        automationSourceProcessId != null &&
        automationSourceProcessId > 0) {
      onProgress?.call('selecting process $automationSourceProcessId...');
      try {
        Log.i(
          'Stream test automation source-process selection starting '
          'pid=$automationSourceProcessId '
          'timeout=${_streamTestAutoSelectTimeout.inSeconds}s',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        source = await WebrtcScreencaptureSource.findWindowByProcessId(
          automationSourceProcessId,
          shareAudio: false,
        ).timeout(_streamTestAutoSelectTimeout);
        if (source != null) {
          Log.i(
            'Stream test automation auto-selected window pid '
            '$automationSourceProcessId',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        } else {
          Log.i(
            'Stream test automation source-process selection returned no '
            'match pid=$automationSourceProcessId',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        }
      } on TimeoutException catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content:
              'Stream test automation source-process selection timed out '
              'after ${_streamTestAutoSelectTimeout.inSeconds}s '
              'pid=$automationSourceProcessId',
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test automation source-process selection failed',
        );
      }
    }

    final automationSourceTitle = runnerConfig.automationSourceTitle;
    if (source == null &&
        !allowManualSourcePicker &&
        automationSourceTitle != null &&
        automationSourceTitle.trim().isNotEmpty) {
      onProgress?.call('selecting requested automation window...');
      try {
        Log.i(
          'Stream test automation source-title selection starting '
          'timeout=${_streamTestAutoSelectTimeout.inSeconds}s',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        source = await WebrtcScreencaptureSource.findWindowByTitle(
          automationSourceTitle,
          shareAudio: false,
        ).timeout(_streamTestAutoSelectTimeout);
        if (source != null) {
          Log.i(
            'Stream test automation auto-selected window by title',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        } else {
          Log.i(
            'Stream test automation source-title selection returned no match',
            category: LogCategory.webrtc,
            source: 'stream-test-runner',
          );
        }
      } on TimeoutException catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content:
              'Stream test automation source-title selection timed out '
              'after ${_streamTestAutoSelectTimeout.inSeconds}s',
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test automation source-title selection failed',
        );
      }
    }

    if (source == null && allowManualSourcePicker) {
      try {
        source = await session.pickScreenCapture(context);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Stream test source picker failed',
        );
        if (mounted) {
          _showStreamTestSnackBar('Stream test source picker failed: $error');
        }
        if (captureTargetSession != null) {
          await captureTargetSession.stopAndCollect();
        }
        return null;
      }
    }
    if (source == null || !mounted) {
      Log.i(
        allowManualSourcePicker
            ? 'Stream test source picker cancelled'
            : 'Stream test automation did not find an auto-selectable source',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      if (captureTargetSession != null) {
        await captureTargetSession.stopAndCollect();
      }
      return null;
    }
    onSourceSelected?.call();
    Log.i(
      'Stream test source picker selected ${source.runtimeType}',
      category: LogCategory.webrtc,
      source: 'stream-test-runner',
    );

    try {
      await NativeWebrtcDiagnostics.clear();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to clear native WebRTC diagnostics sidecar',
      );
    }

    final streamTestTarget = _CallViewStreamTestTarget(
      session: session,
      source: source,
    );
    final streamTestRunConfig = StreamTestRunConfig(
      presets: runnerConfig.presets,
      durationPerPreset: runnerConfig.duration,
      warmupDuration: runnerConfig.warmup,
      scenarioLabel: 'current-call:${session.roomName}',
      sourceMetadata: _streamTestSourceMetadata(source),
      windowsCaptureBackendMode: runnerConfig.windowsCaptureBackendMode,
      windowsCaptureBackendModes: runnerConfig.windowsCaptureBackendModes,
      windowsCaptureDirtyRegionMode: runnerConfig.windowsCaptureDirtyRegionMode,
      windowsWindowGdiCaptureModes: runnerConfig.windowsWindowGdiCaptureModes,
      nativeFramePacingEnabled: runnerConfig.nativeFramePacingEnabled,
      dummyNv12LiveSender: runnerConfig.dummyNv12LiveSender,
      receiverProbe: runnerConfig.receiverProbe,
      gameCaptureTestTarget: captureTargetConfig.enabled
          ? captureTargetConfig
          : null,
      gameCaptureProbe: runnerConfig.gameCaptureProbeEnabled
          ? GameCaptureProbeConfig(
              enabled: true,
              duration: runnerConfig.duration,
              maxSavedFrames: runnerConfig.gameCaptureProofFrames,
              publicationHandoffMaxWidth:
                  runnerConfig.publicationHandoffMaxWidth ?? 1280,
              publicationHandoffMaxHeight:
                  runnerConfig.publicationHandoffMaxHeight ?? 720,
              publicationHandoffTargetFps:
                  runnerConfig.publicationHandoffTargetFps ?? 30,
            )
          : null,
    );
    final runnerStartedAt = DateTime.now();
    final runner = StreamTestRunner(
      target: streamTestTarget,
      onProgress: (progress) => onProgress?.call(progress.detailLabel),
      gameCaptureProbeRunner: createDefaultGameCaptureProbeRunner(),
      diagnosticLogProvider: () => _streamTestDiagnosticLogText(),
    );
    StreamTestRunResult result;
    try {
      result = await runner.run(
        streamTestRunConfig,
        gameCaptureTestTargetResult: captureTargetResult,
      );
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: 'Stream test runner failed');
      if (captureTargetSession != null) {
        onProgress?.call('stopping capture target...');
        captureTargetResult = await captureTargetSession.stopAndCollect();
      }
      StreamTestRunResult? failureResult;
      try {
        failureResult = await _writeStreamTestFailureReport(
          startedAt: runnerStartedAt,
          target: streamTestTarget,
          config: streamTestRunConfig,
          error: error,
          gameCaptureTestTargetResult: captureTargetResult,
        );
      } catch (reportError, reportStackTrace) {
        Log.onError(
          reportError,
          reportStackTrace,
          content: 'Failed to write stream test failure report',
        );
      }
      if (mounted) {
        final writeResult = _lastStreamTestReportWriteResult;
        if (writeResult != null &&
            writeResult.supported &&
            writeResult.error == null) {
          _showStreamTestSnackBar(
            'Stream test failed; '
            '${_streamTestReportExportLabel(writeResult)}.',
          );
        } else {
          _showStreamTestSnackBar(
            'Stream test failed. Call Diagnostics has details.',
          );
        }
      }
      return failureResult;
    }

    if (captureTargetSession != null) {
      onProgress?.call('stopping capture target...');
      captureTargetResult = await captureTargetSession.stopAndCollect();
      result = result.withGameCaptureTestTargetResult(captureTargetResult);
    }

    final writeResult = await const StreamTestReportWriter().write(result);
    _lastStreamTestReportWriteResult = writeResult;
    final exportLabel = _streamTestReportExportLabel(writeResult);
    final compactResultSummary = result.presetResults
        .map((presetResult) {
          final summary = presetResult.score.summary;
          return '${presetResult.resultLabel}: '
              'score=${presetResult.score.totalScore}, '
              '${summary.capturePipelineLabel}, '
              'bottleneck=${presetResult.score.bottleneck.label}';
        })
        .join('\n');
    Log.i(
      'Stream test runner completed\n'
      'Stream test report export: $exportLabel\n'
      'Preset results: ${result.presetResults.length}\n'
      '$compactResultSummary',
      category: LogCategory.webrtc,
      source: 'stream-test-runner',
    );

    if (!mounted) {
      return result;
    }

    if (writeResult.error != null || !writeResult.supported) {
      _showStreamTestSnackBar(
        'Stream test finished; report export failed. '
        'Call Diagnostics has details.',
      );
    } else {
      _showStreamTestSnackBar(
        'Stream test saved; ${_streamTestReportExportLabel(writeResult)}.',
      );
    }

    return result;
  }

  Future<ScreenCaptureSource?>
  _selectDummyNv12LiveSenderPlaceholderSource() async {
    if (!PlatformUtils.isWindows) {
      return null;
    }
    try {
      final source = await WebrtcScreencaptureSource.findAnyWindowPlaceholder(
        timeout: _streamTestAutoSelectTimeout,
      );
      if (source == null) {
        Log.i(
          'Stream test dummy NV12 live-sender found no window source '
          'placeholder',
          category: LogCategory.webrtc,
          source: 'stream-test-runner',
        );
        return null;
      }
      Log.i(
        'Stream test dummy NV12 live-sender using placeholder window '
        'sourceIdHash=${shortShareSourceIdHash(source.source.id)}',
        category: LogCategory.webrtc,
        source: 'stream-test-runner',
      );
      return source;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Stream test dummy NV12 live-sender placeholder selection '
            'failed',
      );
      return null;
    }
  }

  Future<StreamTestRunResult> _writeStreamTestFailureReport({
    required DateTime startedAt,
    required StreamTestTarget target,
    required StreamTestRunConfig config,
    required Object error,
    required GameCaptureTestTargetResult? gameCaptureTestTargetResult,
  }) async {
    final result = StreamTestRunResult.failure(
      startedAt: startedAt,
      endedAt: DateTime.now(),
      targetLabel: target.label,
      roomId: target.roomId,
      config: config,
      error: error.toString(),
      diagnosticLogText: await _streamTestDiagnosticLogText(),
      gameCaptureTestTargetResult: gameCaptureTestTargetResult,
    );
    final writeResult = await const StreamTestReportWriter().write(result);
    _lastStreamTestReportWriteResult = writeResult;
    Log.i(
      'Stream test runner failed; failure report export: '
      '${_streamTestReportExportLabel(writeResult)}',
      category: LogCategory.webrtc,
      source: 'stream-test-runner',
    );
    return result;
  }

  void _showStreamTestSnackBar(String message) {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = mounted ? ScaffoldMessenger.maybeOf(context) : null;
      if (!mounted || messenger == null || !messenger.mounted) {
        return;
      }
      if (Scaffold.maybeOf(context) == null) {
        return;
      }
      try {
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(message)));
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to show stream test snackbar',
        );
      }
    });
  }

  String _streamTestReportExportLabel(StreamTestReportWriteResult result) {
    if (!result.supported) {
      return 'unsupported platform';
    }
    if (result.error != null) {
      return 'export failed';
    }

    return streamTestReportExportDisplayLabel(
      markdownPath: result.markdownPath,
      jsonPath: result.jsonPath,
    );
  }

  StreamTestSourceMetadata _streamTestSourceMetadata(
    ScreenCaptureSource source,
  ) {
    if (source is ShareCaptureSource) {
      final summary = source.shareSession.diagnosticsSummary(
        includeTitle:
            preferences.developerUiVisible &&
            preferences.showCallStreamStats.value,
      );
      return StreamTestSourceMetadata(
        sourceType: summary.sourceType.name,
        sourceIdHash: summary.sourceIdHash,
        processId: summary.processId,
        audioRequested: summary.audioRequested,
        audioMode: summary.audioMode.name,
        audioState: summary.audioState.name,
        audioReason: summary.audioReason,
        sourceTitle: summary.sourceTitle,
        sourceRuntimeType: source.videoSource.runtimeType.toString(),
      );
    }

    return StreamTestSourceMetadata(
      sourceType: source.runtimeType.toString(),
      sourceIdHash: 'unknown',
      sourceRuntimeType: source.runtimeType.toString(),
    );
  }

  Future<_StreamTestDialogConfig?> _showStreamTestConfigDialog() {
    final allPresets = [
      ScreenShareProfileConfig.forPreferenceKey(
        ScreenShareQualityProfile.smooth.storageKey,
        preferHardwareEncoding:
            PlatformUtils.isWindows &&
            preferences.streamHardwareEncodingFirst.value,
      ),
      ScreenShareProfileConfig.forPreferenceKey(
        ScreenShareQualityProfile.balanced.storageKey,
        preferHardwareEncoding:
            PlatformUtils.isWindows &&
            preferences.streamHardwareEncodingFirst.value,
      ),
      ScreenShareProfileConfig.forPreferenceKey(
        ScreenShareQualityProfile.highQuality.storageKey,
        preferHardwareEncoding:
            PlatformUtils.isWindows &&
            preferences.streamHardwareEncodingFirst.value,
      ),
    ];
    final selectedKeys = allPresets
        .map((profile) => profile.storageKey)
        .toSet();
    var durationSeconds = 30;
    var warmupSeconds = 5;
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode;
    var compareWindowsBackends = false;
    var compareWindowGdiMethods = false;
    var forceFullFrameDirtyRegions = false;
    var nativeFramePacingEnabled = PlatformUtils.isWindows;
    var captureTestTargetEnabled = false;
    var captureTestTargetSize = '1920x1080';
    var captureTestTargetMode = 'windowed';
    var captureTestTargetScene = 'gameplay';
    var captureTestTargetFps = '60';
    var gameCaptureProbeEnabled = false;
    var gameCaptureProofFrames = 0;

    return showDialog<_StreamTestDialogConfig>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedPresets = allPresets
                .where((profile) => selectedKeys.contains(profile.storageKey))
                .toList(growable: false);
            return AlertDialog(
              title: const Text('Stream Test Runner'),
              content: SizedBox(
                width: min(MediaQuery.sizeOf(context).width * 0.78, 520),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: min(
                      MediaQuery.sizeOf(context).height * 0.7,
                      620,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final profile in allPresets)
                          CheckboxListTile(
                            value: selectedKeys.contains(profile.storageKey),
                            title: Text(profile.label),
                            subtitle: Text(profile.description),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedKeys.add(profile.storageKey);
                                } else {
                                  selectedKeys.remove(profile.storageKey);
                                }
                              });
                            },
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(child: Text('Duration per preset')),
                            DropdownButton<int>(
                              value: durationSeconds,
                              items: const [
                                DropdownMenuItem(value: 10, child: Text('10s')),
                                DropdownMenuItem(value: 20, child: Text('20s')),
                                DropdownMenuItem(value: 30, child: Text('30s')),
                                DropdownMenuItem(value: 60, child: Text('60s')),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() => durationSeconds = value);
                              },
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Warmup before sampling'),
                            ),
                            DropdownButton<int>(
                              value: warmupSeconds,
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('Off')),
                                DropdownMenuItem(value: 3, child: Text('3s')),
                                DropdownMenuItem(value: 5, child: Text('5s')),
                                DropdownMenuItem(value: 10, child: Text('10s')),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setDialogState(() => warmupSeconds = value);
                              },
                            ),
                          ],
                        ),
                        if (PlatformUtils.isWindows) ...[
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: compareWindowsBackends,
                            title: const Text('Compare Windows backends'),
                            subtitle: const Text(
                              'Runs each selected preset with app default, '
                              'native default, WGC only, and DirectX only. '
                              'Crop fallback is disabled in stream tests '
                              'because it can capture the wrong monitor or '
                              'crash on BG3.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => compareWindowsBackends = value ?? false,
                              );
                            },
                          ),
                          Row(
                            children: [
                              const Expanded(
                                child: Text('Windows capture backend'),
                              ),
                              DropdownButton<WindowsScreenCaptureBackendMode?>(
                                value: windowsCaptureBackendMode,
                                onChanged: compareWindowsBackends
                                    ? null
                                    : (value) {
                                        setDialogState(
                                          () =>
                                              windowsCaptureBackendMode = value,
                                        );
                                      },
                                items: [
                                  const DropdownMenuItem<
                                    WindowsScreenCaptureBackendMode?
                                  >(value: null, child: Text('App default')),
                                  for (final mode
                                      in streamTestWindowsCaptureBackendModes)
                                    DropdownMenuItem<
                                      WindowsScreenCaptureBackendMode?
                                    >(value: mode, child: Text(mode.label)),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            compareWindowsBackends
                                ? 'Comparison mode keeps the same source and '
                                      'cycles backend overrides for evidence, '
                                      'not as a global default change.'
                                : windowsCaptureBackendMode?.description ??
                                      'Uses the same backend as normal sharing: '
                                          'the patched native default with no '
                                          'debug override.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          CheckboxListTile(
                            value: compareWindowGdiMethods,
                            title: const Text('Compare window GDI methods'),
                            subtitle: const Text(
                              'Diagnostic only. For window sources on the '
                              'DirectX/window-GDI path, cycles current '
                              'PrintWindow, plain PrintWindow, BitBlt-first, '
                              'and BitBlt-only so reports can prove whether '
                              'the fast path is usable or just black.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => compareWindowGdiMethods = value ?? false,
                              );
                            },
                          ),
                          CheckboxListTile(
                            value: nativeFramePacingEnabled,
                            title: const Text('Enable latest-frame pacer'),
                            subtitle: const Text(
                              'Normal Windows default. Keeps the newest native '
                              'capture frame and submits it on the target '
                              'cadence; turn off only for A/B diagnostics.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => nativeFramePacingEnabled = value ?? false,
                              );
                            },
                          ),
                          CheckboxListTile(
                            value: captureTestTargetEnabled,
                            title: const Text('Launch D3D11 capture target'),
                            subtitle: const Text(
                              'Debug only. Starts a deterministic local D3D11 '
                              'window, auto-selects it when possible, and '
                              'adds its Present cadence to the stream-test '
                              'report. Use BG3 later for stress coverage.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => captureTestTargetEnabled = value ?? false,
                              );
                            },
                          ),
                          if (captureTestTargetEnabled) ...[
                            Row(
                              children: [
                                const Expanded(child: Text('Target size')),
                                DropdownButton<String>(
                                  value: captureTestTargetSize,
                                  items: const [
                                    DropdownMenuItem(
                                      value: '1920x1080',
                                      child: Text('1920x1080'),
                                    ),
                                    DropdownMenuItem(
                                      value: '2560x1440',
                                      child: Text('2560x1440'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => captureTestTargetSize = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Target mode')),
                                DropdownButton<String>(
                                  value: captureTestTargetMode,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'windowed',
                                      child: Text('Windowed'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'borderless',
                                      child: Text('Borderless'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => captureTestTargetMode = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Target scene')),
                                DropdownButton<String>(
                                  value: captureTestTargetScene,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'gameplay',
                                      child: Text('Gameplay'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'high-motion',
                                      child: Text('High motion'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'low-motion',
                                      child: Text('Low motion'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'ui-heavy',
                                      child: Text('UI heavy'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => captureTestTargetScene = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Target FPS')),
                                DropdownButton<String>(
                                  value: captureTestTargetFps,
                                  items: const [
                                    DropdownMenuItem(
                                      value: '30',
                                      child: Text('30'),
                                    ),
                                    DropdownMenuItem(
                                      value: '60',
                                      child: Text('60'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'uncapped',
                                      child: Text('Uncapped'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => captureTestTargetFps = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                          CheckboxListTile(
                            value: forceFullFrameDirtyRegions,
                            title: const Text('Force full-frame dirty regions'),
                            subtitle: const Text(
                              'Diagnostic only. Disables updated-region differ '
                              'wrappers where possible so the next report can '
                              'separate dirty-region starvation from native '
                              'capture acquisition stalls.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () =>
                                    forceFullFrameDirtyRegions = value ?? false,
                              );
                            },
                          ),
                          CheckboxListTile(
                            value: gameCaptureProbeEnabled,
                            title: const Text('Run D3D11 game probe'),
                            subtitle: const Text(
                              'Debug only. Attaches the local D3D11 Present '
                              'probe to the selected window process and writes '
                              'cadence metadata; it does not publish frames to '
                              'LiveKit.',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => gameCaptureProbeEnabled = value ?? false,
                              );
                            },
                          ),
                          if (gameCaptureProbeEnabled)
                            Row(
                              children: [
                                const Expanded(
                                  child: Text('Game probe proof frames'),
                                ),
                                DropdownButton<int>(
                                  value: gameCaptureProofFrames,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 0,
                                      child: Text('Off'),
                                    ),
                                    DropdownMenuItem(
                                      value: 5,
                                      child: Text('5 frames'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setDialogState(
                                      () => gameCaptureProofFrames = value,
                                    );
                                  },
                                ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedPresets.isEmpty
                      ? null
                      : () {
                          final targetSizeParts = captureTestTargetSize.split(
                            'x',
                          );
                          final targetWidth =
                              int.tryParse(targetSizeParts.first) ?? 1920;
                          final targetHeight = targetSizeParts.length > 1
                              ? int.tryParse(targetSizeParts[1]) ?? 1080
                              : 1080;
                          Navigator.of(dialogContext).pop(
                            _StreamTestDialogConfig(
                              presets: selectedPresets,
                              duration: Duration(seconds: durationSeconds),
                              warmup: Duration(seconds: warmupSeconds),
                              windowsCaptureBackendMode: PlatformUtils.isWindows
                                  ? windowsCaptureBackendMode
                                  : null,
                              windowsCaptureBackendModes:
                                  PlatformUtils.isWindows &&
                                      compareWindowsBackends
                                  ? _streamTestWindowsCaptureBackendCompareModes
                                  : null,
                              windowsCaptureDirtyRegionMode:
                                  PlatformUtils.isWindows &&
                                      forceFullFrameDirtyRegions
                                  ? WindowsScreenCaptureDirtyRegionMode
                                        .forceFullFrame
                                  : WindowsScreenCaptureDirtyRegionMode.auto,
                              windowsWindowGdiCaptureModes:
                                  PlatformUtils.isWindows &&
                                      compareWindowGdiMethods
                                  ? streamTestWindowsWindowGdiCaptureModes
                                  : null,
                              nativeFramePacingEnabled:
                                  PlatformUtils.isWindows &&
                                  nativeFramePacingEnabled,
                              captureTestTargetEnabled:
                                  PlatformUtils.isWindows &&
                                  captureTestTargetEnabled,
                              captureTestTargetWidth: targetWidth,
                              captureTestTargetHeight: targetHeight,
                              captureTestTargetMode: captureTestTargetMode,
                              captureTestTargetScene: captureTestTargetScene,
                              captureTestTargetFps: captureTestTargetFps,
                              gameCaptureProbeEnabled:
                                  PlatformUtils.isWindows &&
                                  gameCaptureProbeEnabled,
                              gameCaptureProofFrames: PlatformUtils.isWindows
                                  ? gameCaptureProofFrames
                                  : 0,
                            ),
                          );
                        },
                  child: const Text('Run'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveCallDiagnosticsLog(List<String> lines) async {
    try {
      final data = _redactCallDiagnosticText(lines.join('\n'));
      final bytes = Uint8List.fromList(utf8.encode(data));
      final fileName =
          'inter-galactic-call-diagnostics-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.txt';
      String? destinationPath;

      if (kIsWeb || PlatformUtils.isAndroid || PlatformUtils.isIOS) {
        destinationPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          bytes: bytes,
        );
      } else {
        destinationPath = await FilePicker.platform.saveFile(
          fileName: fileName,
        );
        if (destinationPath != null) {
          await writeLocalFileBytes(destinationPath, bytes);
        }
      }

      if (!mounted || destinationPath == null) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(savedCallDiagnosticsDisplayMessage(destinationPath)),
        ),
      );
    } catch (error, trace) {
      Log.onError(error, trace, content: 'Failed to save call diagnostics');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Failed to save call diagnostics')),
        );
      }
    }
  }

  Widget _diagnosticLogTab(List<String> lines) {
    final text = _redactCallDiagnosticText(lines.join('\n'));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.3),
        ),
      ),
    );
  }

  Widget _streamTestProgressBanner() {
    final theme = Theme.of(context);
    final progress = _streamTestProgressLabel ?? 'preparing...';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Running: $progress',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rnnoiseDiagnosticCaptureBanner({
    required bool busy,
    required bool running,
    required String? message,
  }) {
    final theme = Theme.of(context);
    final directoryPath =
        NoiseSuppressionService.instance.diagnosticCaptureDirectoryPath;
    final statusText =
        message ??
        (running
            ? 'Capturing 10 seconds of local RNNoise WAV stages.'
            : 'RNNoise WAV capture is ready.');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (busy || running) ...[
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ] else ...[
              Icon(
                Icons.multitrack_audio_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                [
                  statusText,
                  'Local-only. WAV bug-report submission is disabled.',
                  if (directoryPath != null)
                    rnnoiseDiagnosticFolderDisplayLine(directoryPath),
                ].join('\n'),
                style: theme.textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collapsedCallDiagnosticsSummary() {
    final textTheme = Theme.of(context).textTheme;
    final report = _lastStreamTestReportWriteResult;
    final testResult = _lastStreamTestResult;
    final streamTestStatus = _streamTestRunning
        ? 'Stream test: ${_streamTestProgressLabel ?? 'running...'}'
        : testResult == null
        ? 'Stream test: ready'
        : 'Stream test: ${testResult.presetResults.length} presets complete';
    final reportStatus = report == null
        ? 'Report: not saved in this dialog'
        : 'Report: ${_streamTestReportExportLabel(report)}';

    return SizedBox(
      width: min(MediaQuery.sizeOf(context).width * 0.32, 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            streamTestStatus,
            style: textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            reportStatus,
            style: textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  List<String> _callDiagnosticsSummaryLines() {
    final session = widget.currentSession;
    final shareSession = session.currentShareSession;
    final noiseSuppressionService = NoiseSuppressionService.instance;
    final noiseStatus = noiseSuppressionService.status;
    final livekitSession = session is MatrixLivekitVoipSession ? session : null;
    final snapshot = session.diagnosticsSnapshot;
    final streamCounts = <VoipStreamType, int>{};
    for (final stream in session.streams) {
      streamCounts.update(stream.type, (count) => count + 1, ifAbsent: () => 1);
    }
    final participantAudioMutedOverrideCount = _participantAudioVolumeOverrides
        .storedVolumes
        .where((volume) => volume == 0.0)
        .length;
    final activeStreamTestPrefix = _streamTestRunning
        ? '${_streamTestProgressLabel ?? 'running'}; '
        : '';
    final developerStatsOverlayState = !preferences.showCallStreamStats.value
        ? 'off'
        : _diagnosticsOverlayVisible
        ? 'shown'
        : 'hidden locally';

    return <String>[
      'Room: ${session.roomName} (${session.roomId})',
      'State: ${session.state.name}',
      'Session: ${session.sessionId.isEmpty ? 'none' : session.sessionId}',
      'Mic muted: ${session.isMicrophoneMuted}',
      'Camera enabled: ${session.isCameraEnabled}',
      'Sharing screen: ${session.isSharingScreen}',
      'Streams: total=${session.streams.length} '
          'audio=${streamCounts[VoipStreamType.audio] ?? 0} '
          'cam=${streamCounts[VoipStreamType.video] ?? 0} '
          'share=${streamCounts[VoipStreamType.screenshare] ?? 0}',
      'Local participant audio overrides: '
          'participants=${_participantAudioVolumeOverrides.length} '
          'muted=$participantAudioMutedOverrideCount',
      'Developer stats overlay: $developerStatsOverlayState',
      'Profile: ${snapshot.screenShareProfileLabel}',
      if (snapshot.screenShareProfileDetails != null)
        'Profile details: ${snapshot.screenShareProfileDetails}',
      'ICE: ${snapshot.iceTransportSummary ?? 'unknown'}',
      if (livekitSession != null)
        'Server loopback: ${livekitSession.serverAudioLoopbackDiagnosticLabel}',
      if (_lastStreamTestResult == null)
        _streamTestRunning
            ? 'Stream test runner: running '
                  '${_streamTestProgressLabel ?? 'unknown preset/backend'}'
            : 'Stream test runner: no run in this diagnostics session'
      else
        'Stream test runner: '
            '$activeStreamTestPrefix'
            '${_lastStreamTestResult!.presetResults.length} presets '
            'last scores=${_lastStreamTestResult!.presetResults.map((result) => '${result.profile.label}:${result.score.totalScore}').join(', ')}',
      if (_lastStreamTestReportWriteResult != null)
        'Stream test report: '
            '${_streamTestReportExportLabel(_lastStreamTestReportWriteResult!)}',
      'RNNoise: reason=${noiseStatus.reason} '
          'available=${noiseStatus.available} '
          'enabled=${noiseStatus.enabled} '
          'active=${noiseStatus.active} '
          'frames=${noiseStatus.framesProcessed} '
          'bypass=${noiseStatus.bypassFrames} '
          'gated=${noiseStatus.gatedFrames} '
          'vad=${noiseStatus.lastVadProbability.toStringAsFixed(2)} '
          'ratio=${noiseStatus.lastOutputRatio.toStringAsFixed(2)} '
          'formatMismatch=${noiseStatus.formatMismatchDetected} '
          'suspicious=${noiseStatus.suspiciousOutputDetected}',
      ...noiseSuppressionService.diagnosticsLines(),
      ..._soundboardSummaryLines(session),
      if (shareSession == null)
        'Share audio: no active share session'
      else
        ..._shareSessionSummaryLines(shareSession),
    ];
  }

  List<String> _soundboardSummaryLines(VoipSession session) {
    final client = session.client;
    if (client is! MatrixClient) {
      return const ['Soundboard: unavailable (non-Matrix client)'];
    }

    final room = client.getRoom(session.roomId);
    if (room is! MatrixRoom) {
      return const ['Soundboard: unavailable (call room not loaded)'];
    }

    MatrixSpace? callSpace;
    for (final space in client.spaces.whereType<MatrixSpace>()) {
      if (space.identifier == room.identifier ||
          space.roomsWithChildren.any(
            (candidate) => candidate.identifier == room.identifier,
          )) {
        callSpace = space;
        break;
      }
    }

    final soundboard = callSpace?.getComponent<SoundboardComponent>();
    if (callSpace == null || soundboard == null) {
      return const ['Soundboard: unavailable (no containing space)'];
    }

    return <String>[
      'Soundboard: space=${callSpace.displayName} sounds=${soundboard.sounds.length} '
          'canUpload=${soundboard.canUploadSound} '
          'memberUploads=${soundboard.memberUploadsEnabled} '
          'canManageUploads=${soundboard.canEnableMemberUploads} '
          'activeCallMatch=${soundboardPlaybackService.hasActiveSessionForRoom(client, room)} '
          'deafened=${soundboardPlaybackService.isDeafened} '
          'localVolume=${preferences.soundboardVolume.value.toStringAsFixed(0)}%',
      'Soundboard upload power: required=${soundboard.soundUploadPowerLevel} '
          'defaultUser=${soundboard.defaultUserPowerLevel} '
          'currentUser=${soundboard.currentUserPowerLevel}',
    ];
  }

  List<String> _shareSessionSummaryLines(ShareSession shareSession) {
    final status = shareSession.sharedAudioStatus;
    final summary = shareSession.diagnosticsSummary(
      includeTitle:
          preferences.developerUiVisible &&
          preferences.showCallStreamStats.value,
    );
    return <String>[
      ...summary.lines(),
      'Share audio format: ${status.sampleRateHz}Hz '
          '${status.numChannels}ch ${status.bitsPerSample}bit '
          'packets=${status.packetsCaptured} '
          'frames=${status.framesCaptured} bytes=${status.bytesCaptured} '
          'pcmBridge=${status.pcmBridgeSupported}',
      'Mic source: enabled=${shareSession.micSource.enabled} '
          'rnnoise=${shareSession.micSource.rnnoiseApplies}',
    ];
  }

  List<String> _relatedCallLogLines() {
    final roomId = widget.currentSession.roomId.toLowerCase();
    final sessionId = widget.currentSession.sessionId.toLowerCase();
    final entries = Log.log.reversed
        .where((entry) {
          final content = _normalizeLogSearchText(entry.content);
          return (roomId.isNotEmpty && content.contains(roomId)) ||
              (sessionId.isNotEmpty && content.contains(sessionId)) ||
              _callLogKeywords.any(
                (keyword) => _matchesCallLogKeyword(content, keyword),
              );
        })
        .take(180)
        .toList(growable: false)
        .reversed;

    final lines = <String>[];
    for (final entry in entries) {
      lines.add(_formatLogEntryForMenu(entry));
    }

    return lines.isEmpty ? ['No related Log entries yet.'] : lines;
  }

  static const List<String> _callLogKeywords = [
    'livekit',
    'matrixrtc',
    'call',
    'voip',
    'webrtc',
    'screen share',
    'screenshare',
    'stream',
    'rnnoise',
    'noise suppression',
    'soundboard',
    'media kit',
    'media_kit',
    'mxc',
    'forbidden',
    'permission',
    'shared-content audio',
    'share audio',
    'sharesession',
    'sfu',
    'ice',
    'turn',
    'microphone',
    'audio loopback',
    'getdisplaymedia',
    'capture',
    'encoder',
    'bitrate',
  ];

  bool _matchesCallLogKeyword(String content, String keyword) {
    final contentTokens = _logSearchTokens(content);
    final keywordTokens = _logSearchTokens(keyword);
    if (contentTokens.length < keywordTokens.length || keywordTokens.isEmpty) {
      return false;
    }

    for (
      var index = 0;
      index <= contentTokens.length - keywordTokens.length;
      index++
    ) {
      var matches = true;
      for (
        var keywordIndex = 0;
        keywordIndex < keywordTokens.length;
        keywordIndex++
      ) {
        if (contentTokens[index + keywordIndex] !=
            keywordTokens[keywordIndex]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }

    return false;
  }

  String _formatLogEntryForMenu(LogEntry entry) {
    final buffer = StringBuffer()
      ..writeln(
        '[${entry.time.toUtc().toIso8601String()}] '
        '${entry.type.name.toUpperCase()} x${entry.count}',
      )
      ..writeln(_cleanLogText(entry.content).trim());

    final trace = entry is LogEntryException && entry.trace != null
        ? _cleanLogText(entry.trace.toString()).trim()
        : null;
    if (trace != null && trace.isNotEmpty) {
      buffer
        ..writeln('Stack Trace:')
        ..writeln(trace);
    }

    return buffer.toString().trimRight();
  }

  String _normalizeLogSearchText(String value) {
    return _cleanLogText(value).toLowerCase();
  }

  String _cleanLogText(String value) {
    return value.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }

  String _redactCallDiagnosticText(String value) {
    var redacted = Log.redactSensitiveInfo(value);
    final buildDetails = <String>{
      BuildConfig.forkDeveloper,
      BuildConfig.BUILD_DETAIL.trim(),
      BuildConfig.buildDetailDisplay.trim(),
    }..removeWhere((detail) => detail.isEmpty || detail == 'default');
    for (final detail in buildDetails) {
      redacted = redacted.replaceAll(detail, '[BUILD_DETAIL]');
    }
    return redacted;
  }

  List<String> _redactCallDiagnosticLines(Iterable<String> lines) {
    return _redactCallDiagnosticText(lines.join('\n')).split('\n');
  }

  List<String> _logSearchTokens(String value) {
    return _normalizeLogSearchText(value)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  String _participantDiagnosticLine(VoipParticipantDiagnostics participant) {
    return '${_redactCallDiagnosticText(participant.userId)}: '
        '${_redactCallDiagnosticText(participant.clientLabel)}';
  }

  String _diagnosticLine(VoipTrackDiagnostics track) {
    final direction = track.direction == VoipDiagnosticsTrackDirection.sender
        ? 'send'
        : 'recv';
    final type = switch (track.type) {
      VoipStreamType.audio => 'audio',
      VoipStreamType.video => 'cam',
      VoipStreamType.screenshare => 'share',
    };
    final priority = track.receivePriority == null
        ? ''
        : ' ${track.receivePriority!.name.toUpperCase()}';
    final codec = track.codec == null ? '' : ' ${track.codec}';
    final limitation =
        track.qualityLimitationReason == null ||
            track.qualityLimitationReason == 'none'
        ? ''
        : ' webrtc_limit:${track.qualityLimitationReason}';
    final engine = track.encoderImplementation ?? track.decoderImplementation;
    final hardware = track.hardwareEncodeActive == null
        ? ''
        : ' hw:${track.hardwareEncodeActive! ? 'yes' : 'no'}';
    final remoteAudio = track.remoteAudioSummaryLabel == null
        ? ''
        : ' remote_audio:${track.remoteAudioSummaryLabel}';
    final stageSize = track.direction == VoipDiagnosticsTrackDirection.sender
        ? _formatSenderStageSize(track)
        : _formatReceiverStageSize(track);
    return '$direction $type$priority '
        '${_formatRequestedMedia(track)}'
        '${track.resolutionLabel}$stageSize '
        '${_formatFps(track.fps)} '
        '${_formatFpsBreakdown(track)}'
        '${_formatBitrate(track.bitrateBps)}'
        '${_formatTargetBitrate(track)}$codec'
        '${_formatLoss(track.packetLossPercent)}'
        '${_formatPacketCounts(track)}'
        '${_formatJitter(track.jitterMs)}'
        '${_formatMs("rtt", track.roundTripTimeMs)}'
        '${_formatMs("jbuf", track.jitterBufferDelayMs)}'
        '${_formatMs("enc", track.averageEncodeTimeMs)}'
        '${_formatMs("dec", track.averageDecodeTimeMs)}'
        '${_formatLayer(track)}'
        '${_formatCount("sent", track.framesSent)}'
        '${_formatCount("cap", track.framesCaptured)}'
        '${_formatCount("encd", track.framesEncoded)}'
        '${_formatCount("recv", track.framesReceived)}'
        '${_formatCount("drop", track.framesDropped)}'
        '${_formatCount("dropPre", track.framesDroppedBeforeEncode)}'
        '${_formatCount("dropEnc", track.framesDroppedByEncoder)}'
        '${_formatCount("dec", track.framesDecoded)}'
        '${_formatCount("rend", track.framesRendered)}'
        '${_formatCount("nack", track.nackCount)}'
        '${_formatCount("pli", track.pliCount)}'
        '${_formatCount("fir", track.firCount)}'
        '${_formatCount("freeze", track.freezeCount)}'
        '${_formatResolutionMismatch(track)}'
        '${engine == null ? "" : " $engine"}$hardware'
        '$limitation'
        '$remoteAudio';
  }

  String _formatRequestedMedia(VoipTrackDiagnostics track) {
    if (track.requestedWidth == null && track.requestedHeight == null) {
      return '';
    }
    return 'req:${track.requestedWidth ?? '?'}x${track.requestedHeight ?? '?'} '
        '${_formatFps(track.requestedFps)} '
        '${_formatBitrate(track.requestedBitrateBps)} -> ';
  }

  String _formatSenderStageSize(VoipTrackDiagnostics track) {
    final parts = <String>[
      if (track.preEncodeResolutionLabel != 'unknown')
        'pre:${track.preEncodeResolutionLabel}',
      if (track.resolutionLabel != 'unknown') 'enc:${track.resolutionLabel}',
    ];
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }

  String _formatReceiverStageSize(VoipTrackDiagnostics track) {
    if (track.resolutionLabel == 'unknown') {
      return '';
    }
    return ' recv:${track.resolutionLabel}';
  }

  String _formatResolutionMismatch(VoipTrackDiagnostics track) {
    if (track.direction != VoipDiagnosticsTrackDirection.sender ||
        track.requestedWidth == null ||
        track.requestedHeight == null ||
        track.width == null ||
        track.height == null ||
        track.requestedWidth! <= 0 ||
        track.requestedHeight! <= 0 ||
        track.width! <= 0 ||
        track.height! <= 0) {
      return '';
    }

    final encodedTooWide =
        track.width! > track.requestedWidth! + 32 &&
        track.width! > track.requestedWidth! * 1.1;
    final encodedTooTall =
        track.height! > track.requestedHeight! + 18 &&
        track.height! > track.requestedHeight! * 1.1;
    if (!encodedTooWide && !encodedTooTall) {
      return '';
    }

    return ' mismatch:req${track.requestedWidth}x${track.requestedHeight}'
        '/enc${track.width}x${track.height}';
  }

  String _formatFpsBreakdown(VoipTrackDiagnostics track) {
    final parts = <String>[
      if (track.captureFps != null)
        'capfps:${track.captureFps!.toStringAsFixed(0)}',
      if (track.direction == VoipDiagnosticsTrackDirection.sender &&
          track.captureFps != null)
        'prefps:${track.captureFps!.toStringAsFixed(0)}',
      if (track.encodeFps != null)
        'encfps:${track.encodeFps!.toStringAsFixed(0)}',
      if (track.sendFps != null) 'sendfps:${track.sendFps!.toStringAsFixed(0)}',
      if (track.decodeFps != null)
        'decfps:${track.decodeFps!.toStringAsFixed(0)}',
      if (track.renderFps != null)
        'rendfps:${track.renderFps!.toStringAsFixed(0)}',
    ];
    return parts.isEmpty ? '' : '${parts.join(' ')} ';
  }

  String _formatTargetBitrate(VoipTrackDiagnostics track) {
    final parts = <String>[
      if (track.targetBitrateBps != null)
        'target:${_formatBitrateValue(track.targetBitrateBps)}',
      if (track.availableOutgoingBitrateBps != null)
        'availOut:${_formatBitrateValue(track.availableOutgoingBitrateBps)}',
      if (track.availableIncomingBitrateBps != null)
        'availIn:${_formatBitrateValue(track.availableIncomingBitrateBps)}',
      if (track.retransmitBitrateBps != null)
        'reTx:${_formatBitrateValue(track.retransmitBitrateBps)}',
    ];
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }

  String _formatPacketCounts(VoipTrackDiagnostics track) {
    final parts = <String>[
      if (track.packetsSent != null) 'pkts:${track.packetsSent}',
      if (track.packetsReceived != null) 'pktr:${track.packetsReceived}',
      if (track.packetsLost != null) 'pktlost:${track.packetsLost}',
    ];
    return parts.isEmpty ? '' : ' ${parts.join(' ')}';
  }

  String _formatLayer(VoipTrackDiagnostics track) {
    final layer = track.activeLayer ?? track.rid;
    return layer == null ? '' : ' layer:$layer';
  }

  String _formatFps(double? fps) {
    if (fps == null || fps <= 0) {
      return 'fps:?';
    }
    return 'fps:${fps.toStringAsFixed(0)}';
  }

  String _formatBitrate(int? bitrateBps) {
    if (bitrateBps == null || bitrateBps <= 0) {
      return 'rate:?';
    }
    return 'rate:${_formatBitrateValue(bitrateBps)}';
  }

  String _formatBitrateValue(int? bitrateBps) {
    if (bitrateBps == null || bitrateBps <= 0) {
      return '?';
    }
    if (bitrateBps >= 1000000) {
      return '${(bitrateBps / 1000000).toStringAsFixed(1)}Mbps';
    }
    return '${(bitrateBps / 1000).toStringAsFixed(0)}kbps';
  }

  String _formatLoss(double? loss) {
    if (loss == null) {
      return '';
    }
    return ' loss:${loss.toStringAsFixed(1)}%';
  }

  String _formatJitter(double? jitterMs) {
    if (jitterMs == null) {
      return '';
    }
    return ' jitter:${jitterMs.toStringAsFixed(0)}ms';
  }

  String _formatMs(String label, double? value) {
    if (value == null) {
      return '';
    }
    return ' $label:${value.toStringAsFixed(0)}ms';
  }

  String _formatCount(String label, int? value) {
    if (value == null) {
      return '';
    }
    return ' $label:$value';
  }

  Widget buildMobileCallLayout(
    List<_CallTileData> tiles,
    _CallTileData? focusedTile,
    List<_CallTileData> secondaryTiles,
    BoxConstraints constraints,
  ) {
    final showFocusedPanel =
        focusedTile != null && !showEqualTileLayout && tiles.length > 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.transparentBackground
            ? Colors.transparent
            : const Color(0xFF111214),
        borderRadius: BorderRadius.circular(
          widget.transparentBackground ? 0 : 18,
        ),
      ),
      child: Padding(
        padding: _mobileCallTileAreaPadding(constraints),
        child: showFocusedPanel
            ? Column(
                children: [
                  Expanded(child: buildFocusedTile(focusedTile, tiles.length)),
                  if (secondaryTiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    buildMobileParticipantStrip(secondaryTiles, constraints),
                  ],
                ],
              )
            : buildMobileCompactParticipantGrid(tiles, constraints),
      ),
    );
  }

  Widget buildMobileCompactParticipantGrid(
    List<_CallTileData> tiles,
    BoxConstraints constraints,
  ) {
    final columns = _mobileCompactGridColumns(
      itemCount: tiles.length,
      maxWidth: constraints.maxWidth,
    );
    const spacing = 8.0;

    return LayoutBuilder(
      builder: (context, innerConstraints) {
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: tiles.length > 4
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          itemCount: tiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: _mobileCompactGridAspectRatio(
              columns,
              tiles.length,
              innerConstraints,
            ),
          ),
          itemBuilder: (context, index) {
            final tile = tiles[index];
            return _buildCallTile(
              tile,
              key: ValueKey("call_mobile_grid_${tile.tileId}"),
              focused: false,
              onTap: () => focusTile(tile),
            );
          },
        );
      },
    );
  }

  Widget buildMobileParticipantStrip(
    List<_CallTileData> tiles,
    BoxConstraints constraints,
  ) {
    final tileHeight = _mobileParticipantStripHeight(constraints);
    const aspectRatio = 4.0 / 3.0;
    const spacing = 8.0;

    return SizedBox(
      height: tileHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: spacing),
        itemBuilder: (context, index) {
          final tile = tiles[index];
          return SizedBox(
            width: tileHeight * aspectRatio,
            height: tileHeight,
            child: _buildCallTile(
              tile,
              key: ValueKey("call_mobile_strip_${tile.tileId}"),
              focused: false,
              onTap: () => focusTile(tile),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCallTile(
    _CallTileData tile, {
    required Key key,
    required bool focused,
    VoidCallback? onTap,
  }) {
    return _buildVoipStreamTile(tile, key: key, focused: focused, onTap: onTap);
  }

  Widget _buildVoipStreamTile(
    _CallTileData tile, {
    required Key key,
    required bool focused,
    VoidCallback? onTap,
  }) {
    final remote = !isLocalTile(tile);
    final localScreenshare = !remote && tile.isScreenshare;
    final isVideoHidden = _isTileVideoHidden(tile);
    final localPreviewWasAutoPaused =
        localScreenshare &&
        _autoHiddenLocalScreenshareStreamIds.contains(tile.tileId);
    final canRepublishDesktopScreenshare =
        localScreenshare && _canRepublishCurrentDesktopScreenshare;
    final volumeTarget = _preparedVolumeTargetForTile(tile);
    final surfaceTreatment = _resolveCallTileSurfaceTreatment(
      transparentBackground: widget.transparentBackground,
    );
    final streamTile = VoipStreamView(
      tile.primaryStream,
      widget.currentSession,
      fit: tile.isScreenshare ? BoxFit.contain : BoxFit.cover,
      isFocused: focused,
      edgeToEdge: surfaceTreatment.edgeToEdge,
      showTileScrim: surfaceTreatment.showTileScrim,
      isMicrophoneMuted: tile.audioStream?.isMuted ?? false,
      isVideoHidden: isVideoHidden,
      localPreviewAutoPaused: localPreviewWasAutoPaused && isVideoHidden,
      showLocalPreviewPerformanceWarning:
          localPreviewWasAutoPaused && !isVideoHidden,
      borderColor: focused
          ? Theme.of(context).colorScheme.primary.withAlpha(180)
          : null,
      onTap: onTap,
      gameActivity: _gameActivityForTile(tile),
      gameActivityPresenceText: _gameActivityPresenceTextForTile(tile),
      onPopout: BuildConfig.DESKTOP && widget.showSessionPopoutButton
          ? () => popOutTile(tile)
          : null,
      volumeStream: volumeTarget,
      defaultVolume: _defaultParticipantAudioVolume,
      forceActionButtonsVisible: widget.forceControlsVisible,
      useRootOverlayForMenus: surfaceTreatment.useRootOverlayForMenus,
      onFullscreen: () {
        showFullscreenTile(tile);
      },
      onVolumeChanged: remote && volumeTarget != null
          ? (vol) => _setTileVolume(tile, vol)
          : null,
      onRemoveFromCall: remote && _canRemoveParticipants
          ? () => _removeParticipantFromCall(tile)
          : null,
      onVisibilityToggle: tile.isScreenshare && remote
          ? () => _toggleScreenshareVisibility(tile)
          : null,
      onHideToggle: () => _toggleTileHidden(tile),
      onStopStreaming: localScreenshare
          ? () {
              unawaited(
                _runCallViewStreamMenuAction(
                  widget.stopScreenshare,
                  actionLabel: 'stop streaming from tile menu',
                  onFailure: () => _showControlFailureSnack(
                    'Could not stop screen sharing.',
                  ),
                ),
              );
            }
          : null,
      streamQualityProfiles: canRepublishDesktopScreenshare
          ? ScreenShareQualityProfile.values
          : const [],
      selectedStreamQualityProfile: _selectedStreamQualityProfile,
      streamAdvancedOverrideEnabled: preferences.streamAdvancedOverride.value,
      onStreamQualitySelected: canRepublishDesktopScreenshare
          ? (profile) {
              unawaited(
                _runCallViewStreamMenuAction(
                  () => _selectStreamQualityProfile(profile),
                  actionLabel: 'select stream quality from tile menu',
                ),
              );
            }
          : null,
      shareStreamAudio: localScreenshare
          ? widget.currentSession.currentShareSession?.sharedAudioRequested ??
                false
          : null,
      canChangeShareStreamAudio: canRepublishDesktopScreenshare,
      onShareStreamAudioChanged: canRepublishDesktopScreenshare
          ? (value) {
              unawaited(
                _runCallViewStreamMenuAction(
                  () => _setShareStreamAudio(value),
                  actionLabel: 'toggle stream audio from tile menu',
                ),
              );
            }
          : null,
    );

    return _buildConnectionSignalWrappedTile(
      tile,
      key: key,
      showSignal: remote,
      child: streamTile,
    );
  }

  Widget _buildConnectionSignalWrappedTile(
    _CallTileData tile, {
    required Key key,
    required bool showSignal,
    required Widget child,
  }) {
    final participant = showSignal ? _connectionHealthForTile(tile) : null;
    if (participant == null) {
      return KeyedSubtree(key: key, child: child);
    }

    final shouldShow =
        Layout.mobile ||
        widget.forceControlsVisible ||
        _connectionSignalHoveredTileIds.contains(tile.tileId);
    final content = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: child),
        if (shouldShow)
          Positioned(
            left: 10,
            top: 10,
            child: _CallSignalStrengthIndicator(participant: participant),
          ),
      ],
    );

    if (!Layout.desktop) {
      return KeyedSubtree(key: key, child: content);
    }

    return KeyedSubtree(
      key: key,
      child: MouseRegion(
        onEnter: (_) =>
            _setConnectionSignalTileHover(tile.tileId, hovering: true),
        onExit: (_) =>
            _setConnectionSignalTileHover(tile.tileId, hovering: false),
        child: content,
      ),
    );
  }

  void _setConnectionSignalTileHover(String tileId, {required bool hovering}) {
    final changed = hovering
        ? _connectionSignalHoveredTileIds.add(tileId)
        : _connectionSignalHoveredTileIds.remove(tileId);
    if (changed && mounted) {
      setState(() {});
    }
  }

  CallHealthParticipantSnapshot? _connectionHealthForTile(_CallTileData tile) {
    final health = widget.currentSession.diagnosticsSnapshot.callHealth;
    final userMatch = health.participants.tryFirstWhere(
      (participant) => participant.userId == tile.userId,
    );
    if (userMatch != null) {
      return userMatch;
    }

    final remoteParticipants = health.remoteParticipants.toList(
      growable: false,
    );
    if (remoteParticipants.length == 1 && !isLocalTile(tile)) {
      return remoteParticipants.single;
    }

    return null;
  }

  EdgeInsets _mobileCallTileAreaPadding(BoxConstraints constraints) {
    return EdgeInsets.fromLTRB(
      8,
      8,
      8,
      widget.suppressControls
          ? 8
          : _callControlsReservedInset(constraints.maxHeight),
    );
  }

  int _mobileCompactGridColumns({
    required int itemCount,
    required double maxWidth,
  }) {
    if (itemCount <= 1) {
      return 1;
    }
    if (maxWidth.isFinite && maxWidth < 320) {
      return 1;
    }
    if (maxWidth.isFinite && maxWidth >= 520 && itemCount > 4) {
      return 3;
    }
    return 2;
  }

  double _mobileCompactGridAspectRatio(
    int columns,
    int itemCount,
    BoxConstraints constraints,
  ) {
    if (itemCount <= 1 &&
        constraints.maxWidth.isFinite &&
        constraints.maxHeight.isFinite &&
        constraints.maxHeight > 0) {
      return (constraints.maxWidth / constraints.maxHeight)
          .clamp(0.5, 1.8)
          .toDouble();
    }

    if (columns <= 1) {
      return 16.0 / 9.0;
    }

    return constraints.maxWidth.isFinite && constraints.maxWidth < 360
        ? 0.82
        : 1.0;
  }

  double _mobileParticipantStripHeight(BoxConstraints constraints) {
    const defaultHeight = 86.0;
    if (!constraints.maxHeight.isFinite) {
      return defaultHeight;
    }

    return max(64.0, min(defaultHeight, constraints.maxHeight * 0.18));
  }

  Widget buildFocusedTile(_CallTileData tile, int tileCount) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: SizedBox.expand(
        key: ValueKey("focused_call_tile_${tile.tileId}"),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _buildVoipStreamTile(
            tile,
            key: ValueKey("call_stage_${tile.tileId}"),
            focused: true,
            onTap: tileCount > 1 ? showEqualLayout : null,
          ),
        ),
      ),
    );
  }

  Widget buildEqualTileGrid(List<_CallTileData> tiles) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.transparentBackground
            ? Colors.transparent
            : const Color(0xFF111214),
        borderRadius: BorderRadius.circular(
          widget.transparentBackground ? 0 : 24,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          return Padding(
            padding: _callTileAreaPadding(outerConstraints),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final spacing = Layout.mobile ? 8.0 : 12.0;
                final columns = calculateBestGridColumns(
                  itemCount: tiles.length,
                  maxWidth: constraints.maxWidth,
                  maxHeight: constraints.maxHeight,
                );

                return GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tiles.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: calculateGridAspectRatio(
                      columns,
                      tiles.length,
                      constraints,
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final tile = tiles[index];
                    return _buildVoipStreamTile(
                      tile,
                      key: ValueKey("call_grid_${tile.tileId}"),
                      focused: false,
                      onTap: () => focusTile(tile),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget buildTileRail(List<_CallTileData> tiles, BoxConstraints constraints) {
    final metrics = _focusedCallRailMetrics(
      itemCount: tiles.length,
      maxWidth: constraints.maxWidth,
      maxHeight: constraints.maxHeight,
      mobile: Layout.mobile,
    );

    if (Layout.mobile) {
      return SizedBox(
        height: metrics.height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: tiles.length,
          separatorBuilder: (_, __) => SizedBox(width: metrics.spacing),
          itemBuilder: (context, index) {
            final tile = tiles[index];
            return SizedBox(
              width: metrics.tileWidth,
              height: metrics.tileHeight,
              child: _buildVoipStreamTile(
                tile,
                key: ValueKey("call_rail_${tile.tileId}"),
                focused: false,
                onTap: () => focusTile(tile),
              ),
            );
          },
        ),
      );
    }

    final scrolls = tiles.length > metrics.columns * metrics.rows;

    return SizedBox(
      height: metrics.height,
      child: SingleChildScrollView(
        physics: scrolls
            ? const BouncingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        child: Align(
          alignment: Alignment.topCenter,
          child: Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.start,
            spacing: metrics.spacing,
            runSpacing: metrics.spacing,
            children: [
              for (final tile in tiles)
                SizedBox(
                  width: metrics.tileWidth,
                  height: metrics.tileHeight,
                  child: _buildVoipStreamTile(
                    tile,
                    key: ValueKey("call_rail_${tile.tileId}"),
                    focused: false,
                    onTap: () => focusTile(tile),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  EdgeInsets _callTileAreaPadding(BoxConstraints constraints) {
    final compactWidth =
        constraints.maxWidth.isFinite &&
        constraints.maxWidth < (Layout.mobile ? 360 : 440);
    final compactHeight =
        constraints.maxHeight.isFinite &&
        constraints.maxHeight < (Layout.mobile ? 320 : 360);
    final horizontal = compactWidth ? 8.0 : 16.0;
    final top = compactHeight ? 8.0 : 16.0;
    final bottom = widget.suppressControls
        ? top
        : _callControlsReservedInset(constraints.maxHeight);

    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  double _callControlsReservedInset(double maxHeight) {
    const defaultInset = 72.0;
    if (!maxHeight.isFinite) {
      return defaultInset;
    }

    return max(36.0, min(defaultInset, maxHeight * 0.2));
  }

  bool _isScreenShareAudioStream(VoipStream stream) {
    return stream is MatrixLivekitVoipStream && stream.isScreenShareAudio;
  }

  bool _isMicrophoneAudioStream(VoipStream stream) {
    return stream.type == VoipStreamType.audio &&
        (stream is! MatrixLivekitVoipStream || stream.isMicrophoneAudio);
  }

  VoipStream? _findScreenshareAudioStream(VoipStream screenshareStream) {
    return widget.currentSession.streams.tryFirstWhere(
      (stream) =>
          stream.streamUserId == screenshareStream.streamUserId &&
          _isScreenShareAudioStream(stream),
    );
  }

  List<_CallTileData> buildVisibleTiles() {
    _syncLocalScreenshareAutoHideTimers();

    final participantStreams = <String, List<VoipStream>>{};
    final tiles = <_CallTileData>[];

    // Build the set of Matrix user IDs that are still active call members.
    // If the LiveKit SFU hasn't disconnected a removed user yet, we hide
    // their tiles so the call view stays consistent with the participant list.
    final activeParticipants = _voipRoomComponent
        ?.getCurrentParticipants()
        .toSet();
    final localUserId = widget.currentSession.client.self?.identifier;
    final shouldFilterByMembership = activeParticipants != null;

    for (final stream in widget.currentSession.streams) {
      if (_isServerLoopbackStream(stream)) {
        continue;
      }

      if (BuildConfig.DESKTOP &&
          callPopoutController.isStreamPoppedOut(
            widget.currentSession.sessionId,
            _tileIdForStream(stream),
          )) {
        continue;
      }

      // Skip streams from users who have been removed from the call, but
      // always keep the local user's own streams visible.
      if (shouldFilterByMembership &&
          stream.streamUserId != localUserId &&
          !activeParticipants.contains(stream.streamUserId)) {
        continue;
      }

      if (stream.type == VoipStreamType.screenshare) {
        // Always add screenshare tiles to the list; visibility is controlled
        // by isVideoHidden via _isTileVideoHidden().  Remote screenshares
        // default to hidden (blank panel) until the user taps the eye-toggle.
        final audioStream = _findScreenshareAudioStream(stream);
        if (audioStream is MatrixLivekitVoipStream) {
          _restoreScreenshareAudioVolume(audioStream);
        }
        tiles.add(
          _CallTileData(
            primaryStream: stream,
            tileId: _tileIdForStream(stream),
            audioStream: audioStream,
            volumeStream: audioStream,
          ),
        );
        continue;
      }

      if (_isScreenShareAudioStream(stream)) {
        continue;
      }

      participantStreams.putIfAbsent(stream.streamUserId, () => []).add(stream);
    }

    for (final entry in participantStreams.entries) {
      final audioStream = entry.value.tryFirstWhere(_isMicrophoneAudioStream);
      // Always prefer video as the primary stream; VoipStreamView renders a
      // blank dark panel when isVideoHidden is true rather than switching tile
      // type.  No VideoTrackRenderer is created when hidden, so LiveKit's
      // adaptiveStream naturally pauses/reduces the inbound video track.
      final primaryStream =
          entry.value.tryFirstWhere(
            (stream) => stream.type == VoipStreamType.video,
          ) ??
          audioStream;

      if (primaryStream == null) {
        continue;
      }

      tiles.add(
        _CallTileData(
          primaryStream: primaryStream,
          tileId: _tileIdForStream(primaryStream),
          audioStream: audioStream,
          volumeStream: audioStream,
        ),
      );
    }

    tiles.sort(
      (a, b) => streamSortPriority(a).compareTo(streamSortPriority(b)),
    );
    return tiles;
  }

  void focusTile(_CallTileData tile) {
    setState(() {
      focusedTileId = tile.tileId;
      showEqualTileLayout = false;
    });
  }

  int calculateBestGridColumns({
    required int itemCount,
    required double maxWidth,
    required double maxHeight,
  }) {
    const targetAspect = 16.0 / 9.0;
    var bestColumns = 1;
    var bestScore = double.infinity;

    for (var columns = 1; columns <= itemCount; columns++) {
      final rows = (itemCount / columns).ceil();
      final tileWidth = maxWidth / columns;
      final tileHeight = maxHeight / rows;
      if (tileHeight <= 0) continue;
      final aspect = tileWidth / tileHeight;
      final score = (aspect - targetAspect).abs();

      if (score < bestScore) {
        bestScore = score;
        bestColumns = columns;
      }
    }

    return bestColumns;
  }

  double calculateGridAspectRatio(
    int columns,
    int itemCount,
    BoxConstraints constraints,
  ) {
    final rows = (itemCount / columns).ceil();
    final spacing = Layout.mobile ? 8.0 : 12.0;
    final width = (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
    final height = (constraints.maxHeight - ((rows - 1) * spacing)) / rows;

    if (height <= 0) {
      return 16 / 9;
    }

    return width / height;
  }

  void showEqualLayout() {
    setState(() {
      focusedTileId = null;
      showEqualTileLayout = true;
    });
  }

  void popOutTile(_CallTileData tile) {
    unawaited(
      _setCallViewReceivePriority(
        tile.primaryStream,
        VoipStreamReceivePriority.high,
      ),
    );
    callPopoutController.popOutStream(
      widget.currentSession.sessionId,
      tile.tileId,
      sessionInstance: widget.currentSession,
    );

    setState(() {
      if (focusedTileId == tile.tileId) {
        focusedTileId = null;
      }
      showEqualTileLayout = false;
    });
  }

  void showFullscreenTile(_CallTileData tile) {
    unawaited(_showFullscreenTile(tile));
  }

  Future<void> _showFullscreenTile(_CallTileData tile) async {
    final tileId = tile.tileId;
    if (_fullscreenTileIds.add(tileId) && mounted) {
      setState(() {});
    }

    try {
      await _setCallViewReceivePriority(
        tile.primaryStream,
        VoipStreamReceivePriority.high,
      );

      if (!mounted) {
        return;
      }

      await showVoipStreamFullscreen(
        context,
        session: widget.currentSession,
        stream: tile.primaryStream,
      );
    } finally {
      if (_fullscreenTileIds.remove(tileId) && mounted) {
        setState(() {});
      }
    }
  }

  _CallTileData? resolveFocusedTile(List<_CallTileData> tiles) {
    if (tiles.isEmpty) {
      return null;
    }

    if (focusedTileId != null) {
      final current = tiles.tryFirstWhere(
        (tile) => tile.tileId == focusedTileId,
      );
      if (current != null && !_isTileVideoHidden(current)) {
        return current;
      }
    }

    return tiles.tryFirstWhere(
          (tile) => tile.isScreenshare && !_isTileVideoHidden(tile),
        ) ??
        tiles.tryFirstWhere(
          (tile) =>
              tile.hasVisual && !isLocalTile(tile) && !_isTileVideoHidden(tile),
        ) ??
        tiles.tryFirstWhere((tile) => !_isTileVideoHidden(tile)) ??
        tiles.first;
  }

  int streamSortPriority(_CallTileData tile) {
    var priority = 0;

    if (tile.isScreenshare) {
      priority -= 20;
    } else if (tile.hasVisual) {
      priority -= 10;
    }

    if (isLocalTile(tile)) {
      priority += 5;
    }

    return priority;
  }

  bool isLocalTile(_CallTileData tile) {
    return tile.userId == widget.currentSession.client.self?.identifier;
  }

  UserActivity? _gameActivityForTile(_CallTileData tile) {
    if (tile.isScreenshare) {
      return null;
    }

    if (isLocalTile(tile)) {
      return _localGameActivity;
    }

    // Remote participants' rich activity arrives as a structured room state
    // event (reliable, not presence-rate-limited). The tile falls back to
    // parsing their presence status text via _gameActivityPresenceTextForTile.
    return _activityRoomComponent?.activityForUser(tile.userId);
  }

  String? _gameActivityPresenceTextForTile(_CallTileData tile) {
    if (isLocalTile(tile) || tile.isScreenshare) {
      return null;
    }

    return _participantPresenceByUserId[tile.userId]?.message?.message;
  }

  Widget callEndedView() {
    return const Center(child: tiamat.Text.label("Call ended"));
  }

  Widget callIncomingView() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Center(
          child: RingShakerAnimation(
            child: Avatar.large(
              image: room?.avatar,
              placeholderColor: room?.defaultColor,
              placeholderText:
                  room?.displayName ?? widget.currentSession.roomName,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 5,
            children: [
              if (_canPopOutSession)
                TutorialAnchor(
                  id: TutorialAnchorIds.callPopoutButton,
                  padding: const EdgeInsets.all(8),
                  child: _callControlButton(
                    radius: 15,
                    icon: Icons.open_in_new_rounded,
                    onPressed: _popOutSession,
                    semanticLabel: BuildConfig.DESKTOP
                        ? 'Pop out call'
                        : 'Open call picture in picture',
                  ),
                ),
              _callControlButton(
                radius: 15,
                icon: Icons.call,
                transparentColor: _transparentControlColor(
                  Theme.of(context).colorScheme.primary,
                ),
                semanticLabel: 'Accept call',
                failureMessage: 'Could not answer the call.',
                onPressed: () async {
                  await widget.acceptCall?.call();
                  if (!mounted) return;
                  setState(() {});
                },
              ),
              _callControlButton(
                radius: 15,
                icon: Icons.call_end,
                color: Theme.of(context).colorScheme.errorContainer,
                transparentColor: _transparentControlColor(
                  Theme.of(context).colorScheme.error,
                ),
                iconColor: widget.transparentBackground
                    ? Theme.of(context).colorScheme.onError
                    : null,
                semanticLabel: 'Decline call',
                failureMessage: 'Could not decline the call.',
                onPressed: () async {
                  await widget.declineCall?.call();
                  if (!mounted) return;
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
