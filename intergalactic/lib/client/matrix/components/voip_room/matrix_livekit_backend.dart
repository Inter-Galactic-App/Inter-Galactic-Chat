import 'dart:async';
import 'dart:convert';

import 'package:intergalactic/client/bug_report/pending_native_call_crash_guard.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/ios_call_audio_session.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

class MatrixLivekitCallJoinPreflightException implements Exception {
  const MatrixLivekitCallJoinPreflightException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MatrixLivekitCallJoinTransientNetworkException implements Exception {
  const MatrixLivekitCallJoinTransientNetworkException({
    required this.attempts,
    required this.lastError,
    this.retryAfter,
  });

  final int attempts;
  final Object lastError;
  final Duration? retryAfter;

  String get message {
    final retryAfter = this.retryAfter;
    if (retryAfter != null && retryAfter > Duration.zero) {
      final retryAfterMilliseconds = retryAfter.inMilliseconds < 1
          ? 1
          : retryAfter.inMilliseconds;
      final retryAfterSeconds =
          (retryAfterMilliseconds + Duration.millisecondsPerSecond - 1) ~/
          Duration.millisecondsPerSecond;
      final retryAfterUnit = retryAfterSeconds == 1 ? 'second' : 'seconds';
      return 'Could not reach the call server after $attempts attempts. '
          'Your connection or DNS may have briefly dropped. Try again in '
          'about $retryAfterSeconds $retryAfterUnit.';
    }

    return 'Could not reach the call server after $attempts attempts. '
        'Your connection or DNS may have briefly dropped. Try joining again '
        'in a moment.';
  }

  @override
  String toString() => message;
}

class MatrixLivekitConnectRetryPolicy {
  const MatrixLivekitConnectRetryPolicy({
    this.retryDelays = defaultRetryDelays,
  });

  static const defaultRetryDelays = <Duration>[
    Duration(milliseconds: 900),
    Duration(milliseconds: 2200),
  ];

  final List<Duration> retryDelays;

  int get maxAttempts => retryDelays.length + 1;

  Duration? retryDelayFor(Object error, {required int failedAttempt}) {
    if (failedAttempt <= 0) {
      return null;
    }

    final delayIndex = failedAttempt - 1;
    if (delayIndex >= retryDelays.length) {
      return null;
    }

    if (!isTransientLiveKitConnectError(error)) {
      return null;
    }

    return retryDelays[delayIndex];
  }

  bool isTransientLiveKitConnectError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('notallowed') ||
        message.contains('not allowed') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        message.contains('invalid token') ||
        message.contains('permission denied') ||
        message.contains('statuscode: 400') ||
        message.contains('status code: 400') ||
        message.contains('statuscode: 401') ||
        message.contains('status code: 401') ||
        message.contains('statuscode: 403') ||
        message.contains('status code: 403')) {
      return false;
    }

    return message.contains('no internet connection') ||
        message.contains('connectexception') ||
        message.contains('socketexception') ||
        message.contains('httpexception') ||
        message.contains('websocketexception') ||
        message.contains('websocketchannelexception') ||
        message.contains('handshakeexception') ||
        message.contains('failed host lookup') ||
        message.contains('temporary failure in name resolution') ||
        message.contains('no address associated with hostname') ||
        message.contains('connection closed before full header') ||
        message.contains('connection reset by peer') ||
        message.contains('network is unreachable') ||
        message.contains('connection timed out') ||
        message.contains('timed out') ||
        message.contains('statuscode: 408') ||
        message.contains('status code: 408') ||
        message.contains('statuscode: 429') ||
        message.contains('status code: 429') ||
        message.contains('statuscode: 500') ||
        message.contains('status code: 500') ||
        message.contains('statuscode: 502') ||
        message.contains('status code: 502') ||
        message.contains('statuscode: 503') ||
        message.contains('status code: 503') ||
        message.contains('statuscode: 504') ||
        message.contains('status code: 504') ||
        message.contains('statuscode: 520') ||
        message.contains('status code: 520') ||
        message.contains('statuscode: 522') ||
        message.contains('status code: 522') ||
        message.contains('statuscode: 524') ||
        message.contains('status code: 524');
  }
}

class MatrixLivekitBackend {
  MatrixRoom room;
  lk.Room? livekitRoom;
  MatrixLivekitBackend(this.room);
  static const _tokenRequestTimeout = Duration(seconds: 10);
  static const _connectRetryPolicy = MatrixLivekitConnectRetryPolicy();
  static const _e2eeTrustRefreshTimeout = Duration(seconds: 4);
  static const _initialMicrophoneEnableTimeout = Duration(seconds: 12);
  static const _staleInitialMicrophoneDisableTimeout = Duration(seconds: 4);
  static const _failedLiveKitRoomDisconnectTimeout = Duration(seconds: 2);
  static const _failedLiveKitRoomDisposeTimeout = Duration(seconds: 2);
  static bool _tokenServiceRejectsClientMetadata = false;
  static bool _loggedTokenMetadataFallback = false;

  Future<List<Uri>> getFociUrl() async {
    final selectedFocus = findSelectedFocus();

    final wellKnown = await room.matrixRoom.client.getWellknown();
    final livekitJwtServiceUrl =
        wellKnown.additionalProperties["org.matrix.msc4143.rtc_foci"];

    if (livekitJwtServiceUrl is! List) {
      return [if (selectedFocus != null) selectedFocus];
    }

    Uri? fociUrl;
    for (var focus in livekitJwtServiceUrl) {
      Log.d("Focus: ${focus}");
      if (focus is! Map) {
        continue;
      }
      final data = <String, dynamic>{
        for (final entry in focus.entries)
          if (entry.key is String) (entry.key as String): entry.value,
      };
      if (data["type"] != "livekit") {
        continue;
      }

      final url = data["livekit_service_url"];
      if (url is! String) {
        continue;
      }
      fociUrl = Uri.tryParse(url);
      if (fociUrl == null) {
        continue;
      }

      return [
        if (selectedFocus != null) selectedFocus,
        if (selectedFocus != fociUrl) fociUrl,
      ];
    }

    return [if (selectedFocus != null) selectedFocus];
  }

  Uri? findSelectedFocus() {
    final states =
        room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent];
    if (states == null) {
      return null;
    }

    final values = states.values.map((event) => event as Event).toList();
    values.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));

    for (var entry in values) {
      final focusActive = entry.content.tryGet<Map<String, dynamic>>(
        "focus_active",
      );

      if (focusActive == null) {
        continue;
      }

      if (focusActive['type'] != "livekit") {
        Log.e("Unknown focus type: ${focusActive['type']}");
        continue;
      }

      if (focusActive['focus_selection'] != "oldest_membership") {
        Log.e(
          "Unknown focus selection algorithm: ${focusActive['focus_selection']}",
        );
        continue;
      }

      final fociPreferred = entry.content.tryGet<List<dynamic>>(
        "foci_preferred",
      );
      Log.d(
        "Selecting LiveKit focus",
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
      if (fociPreferred == null) {
        continue;
      }

      for (var item in fociPreferred) {
        if (item is! Map) {
          continue;
        }
        final map = <String, dynamic>{
          for (final entry in item.entries)
            if (entry.key is String) (entry.key as String): entry.value,
        };
        if (map['type'] != "livekit") continue;
        if (map['livekit_alias'] != room.identifier) continue;
        final url = map['livekit_service_url'];
        if (url is! String) continue;
        return Uri.tryParse(url);
      }
    }

    return null;
  }

  Future<VoipSession?> join() async {
    await _ensureE2eeCallJoinAllowed();

    final nativeCrashGuard = await PendingNativeCallCrashGuard.record(
      source: 'matrix-livekit-native-call-join',
      callKind: 'LiveKit room join',
    );

    try {
      final audioReady = await IosCallAudioSession.prepareForCall(
        source: 'matrix-livekit-backend',
      );
      if (!audioReady) {
        throw Exception('iOS call audio session could not be prepared');
      }

      await WebrtcDefaultDevices.selectOutputDevice();
      await NoiseSuppressionService.instance.ensureInitialized();

      final fociUrl = await getFociUrl();

      if (fociUrl.isEmpty) {
        throw Exception("Failed to find a valid LiveKit service");
      }

      final selectedFocus = fociUrl.first;
      Log.d("Got Foci Url: ${fociUrl}");

      final token = await room.matrixRoom.client.requestOpenIdToken(
        room.matrixRoom.client.userID!,
        {},
      );

      if (selectedFocus.scheme != "https") {
        throw Exception("Selected focus JWT does not use HTTPS");
      }

      final uri = Uri.parse(selectedFocus.toString() + "/sfu/get");

      Map<String, dynamic> buildTokenRequestBody({required bool clientInfo}) =>
          {
            "device_id": room.matrixRoom.client.deviceID!,
            "room": room.matrixRoom.id,
            if (clientInfo)
              MatrixVoipRoomComponent.callClientInfoKey:
                  BuildConfig.matrixClientMetadata,
            "openid_token": {
              "matrix_server_name": token.matrixServerName,
              "access_token": token.accessToken,
              "expires_in": token.expiresIn,
            },
          };

      final includeClientInfo = !_tokenServiceRejectsClientMetadata;
      final body = buildTokenRequestBody(clientInfo: includeClientInfo);
      var result = await http
          .post(
            uri,
            headers: const {"Content-Type": "application/json"},
            body: jsonEncode(body),
          )
          .timeout(_tokenRequestTimeout);
      if (result.statusCode == 400 && includeClientInfo) {
        final fallbackBody = buildTokenRequestBody(clientInfo: false);
        if (!_loggedTokenMetadataFallback) {
          Log.w(
            "LiveKit auth rejected client metadata; retrying token request without it",
            category: LogCategory.livekit,
            source: 'matrix-livekit-backend',
          );
          _loggedTokenMetadataFallback = true;
        }
        _tokenServiceRejectsClientMetadata = true;
        result = await http
            .post(
              uri,
              headers: const {"Content-Type": "application/json"},
              body: jsonEncode(fallbackBody),
            )
            .timeout(_tokenRequestTimeout);
      } else if (result.statusCode == 200 && !includeClientInfo) {
        Log.d(
          "LiveKit token request omitted client metadata after prior server rejection",
          category: LogCategory.livekit,
          source: 'matrix-livekit-backend',
        );
      }

      if (result.statusCode == 400 &&
          !includeClientInfo &&
          _tokenServiceRejectsClientMetadata) {
        final retryBody = buildTokenRequestBody(clientInfo: true);
        try {
          result = await http
              .post(
                uri,
                headers: const {"Content-Type": "application/json"},
                body: jsonEncode(retryBody),
              )
              .timeout(_tokenRequestTimeout);
          if (result.statusCode == 200) {
            _tokenServiceRejectsClientMetadata = false;
            _loggedTokenMetadataFallback = false;
          }
        } catch (_) {
          // Fall through to the original HTTP failure below. The retry is only
          // a recovery probe in case the auth service was upgraded mid-session.
        }
      }
      if (result.statusCode != 200) {
        throw Exception("Failed to get sfu! HTTP Error ${result.statusCode}");
      }

      var data = jsonDecode(result.body) as Map<String, dynamic>;

      final sfuUrl = data["url"];
      Log.d("Got sfu: ${sfuUrl}");
      final jwt = data["jwt"];
      final defaultAudioCaptureOptions =
          NoiseSuppressionCaptureProfile.buildLivekitAudioCaptureOptions(
            inputVolume:
                NoiseSuppressionCaptureProfile.normalizedMicrophoneVolumePreference(
                  preferences.voipMicrophoneVolume.value,
                ),
            bypassVoiceProcessing: PlatformUtils.isIOS,
          );
      final gpuPipelineTestModeEnabled =
          PlatformUtils.isWindows &&
          preferences.developerMode.value &&
          preferences.streamGpuPipelineTestMode.value;
      final defaultScreenShare = ScreenShareProfileConfig.forPreferenceKey(
        gpuPipelineTestModeEnabled
            ? ScreenShareQualityProfile.smooth.storageKey
            : preferences.screenShareQualityProfile.value,
        preferHardwareEncoding:
            PlatformUtils.isWindows &&
            (gpuPipelineTestModeEnabled ||
                preferences.streamHardwareEncodingFirst.value),
      );
      final defaultScreenShareLowLayer = defaultScreenShare.lowLayer;
      final useScreenShareSimulcast =
          defaultScreenShare.useSimulcast && defaultScreenShareLowLayer != null;
      final defaultScreenShareCaptureOptions = lk.ScreenShareCaptureOptions(
        useiOSBroadcastExtension: PlatformUtils.isIOS,
        maxFrameRate: defaultScreenShare.mainLayer.maxFramerate.toDouble(),
        params: lk.VideoParameters(
          dimensions: lk.VideoDimensions(
            defaultScreenShare.mainLayer.width,
            defaultScreenShare.mainLayer.height,
          ),
          encoding: lk.VideoEncoding(
            maxFramerate: defaultScreenShare.mainLayer.maxFramerate,
            maxBitrate: defaultScreenShare.mainLayer.maxBitrateBps,
          ),
        ),
      );

      final roomOptions = lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: defaultAudioCaptureOptions,
        defaultScreenShareCaptureOptions: defaultScreenShareCaptureOptions,
        // Default publish options act as a safety net for any code path that
        // calls publishVideoTrack without explicit options (e.g. Android
        // setScreenShareEnabled).  Camera and desktop screenshare both supply
        // their own VideoPublishOptions, so these only apply to other paths.
        defaultVideoPublishOptions: lk.VideoPublishOptions(
          videoCodec: defaultScreenShare.codec,
          simulcast: useScreenShareSimulcast,
          screenShareEncoding: lk.VideoEncoding(
            maxFramerate: defaultScreenShare.mainLayer.maxFramerate,
            maxBitrate: defaultScreenShare.mainLayer.maxBitrateBps,
          ),
          screenShareSimulcastLayers: [
            if (useScreenShareSimulcast)
              lk.VideoParameters(
                dimensions: lk.VideoDimensions(
                  defaultScreenShareLowLayer.width,
                  defaultScreenShareLowLayer.height,
                ),
                encoding: lk.VideoEncoding(
                  maxFramerate: defaultScreenShareLowLayer.maxFramerate,
                  maxBitrate: defaultScreenShareLowLayer.maxBitrateBps,
                ),
              ),
          ],
          degradationPreference: lk.DegradationPreference.maintainFramerate,
          backupVideoCodec: lk.BackupVideoCodec(enabled: false),
        ),
        // Default camera capture: 360p / 15fps cap.  Applies to any path that
        // reaches setCameraEnabled() without an explicit CameraCaptureOptions.
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          params: lk.VideoParametersPresets.h360_169,
          maxFrameRate: 15,
        ),
      );

      final stateKey = MatrixVoipRoomComponent.callMemberStateKeyFor(
        userId: room.client.self!.identifier,
        deviceId: room.matrixRoom.client.deviceID!,
      );
      final callMemberContent = MatrixVoipRoomComponent.buildCallMemberContent(
        deviceId: room.matrixRoom.client.deviceID!,
        roomId: room.identifier,
        foci: fociUrl,
      );

      await room.matrixRoom.client.setRoomStateWithKey(
        room.matrixRoom.id,
        MatrixVoipRoomComponent.callMemberStateEvent,
        stateKey,
        callMemberContent,
      );

      await IosCallAudioSession.ensureVoiceProcessingBypass(
        source: 'matrix-livekit-backend-connect',
      );

      late final lk.Room lkRoom;
      try {
        Log.i(
          'LiveKit room connect starting',
          category: LogCategory.livekit,
          source: 'matrix-livekit-backend',
        );
        lkRoom = await _connectLiveKitRoom(roomOptions, sfuUrl, jwt);
        Log.i(
          'LiveKit room connect completed',
          category: LogCategory.livekit,
          source: 'matrix-livekit-backend',
        );
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'LiveKit connect failed; clearing MatrixRTC membership',
          category: LogCategory.livekit,
          source: 'matrix-livekit-backend',
        );
        await _clearMatrixRtcMembershipAfterJoinFailure(
          stateKey: stateKey,
          failureContent:
              'Failed to clear MatrixRTC membership after connect error',
        );
        rethrow;
      }

      final initialMicrophoneEnableState =
          MatrixLivekitInitialMicrophoneEnableState();
      try {
        final joinMutedForWindowsPushToTalk =
            PlatformUtils.isWindows && preferences.voipPushToTalkEnabled.value;
        var device = await WebrtcDefaultDevices.getDefaultMicrophoneId();

        Log.d("Using default microphone device: $device");

        // Guard: localParticipant should be non-null after a successful connect(),
        // but log clearly if it isn't so we can diagnose rejoins-to-get-audio issues.
        if (lkRoom.localParticipant == null) {
          Log.e(
            "join: localParticipant is null after connect() - microphone will not be enabled",
            category: LogCategory.livekit,
            source: 'matrix-livekit-backend',
          );
        } else if (joinMutedForWindowsPushToTalk) {
          initialMicrophoneEnableState.markDesiredMicrophoneEnabled(false);
          Log.i(
            'LiveKit initial microphone enable skipped: '
            'reason=windows_push_to_talk_join_muted',
            category: LogCategory.livekit,
            source: 'matrix-livekit-backend',
          );
        } else {
          final audioCaptureOptions = device != null
              ? defaultAudioCaptureOptions.copyWith(deviceId: device)
              : defaultAudioCaptureOptions;
          Log.i(
            "LiveKit microphone capture profile: "
            "${NoiseSuppressionCaptureProfile.captureFrontendSummary(bypassVoiceProcessing: PlatformUtils.isIOS)} "
            "constraints=${NoiseSuppressionCaptureProfile.describeAudioCaptureOptions(audioCaptureOptions)}",
          );

          // Keep desktop capture settings aligned across Matrix 1:1 and LiveKit
          // so built-in suppression is only disabled when the native RNNoise hook
          // actually came up successfully.
          await _enableInitialMicrophoneDuringJoin(
            lkRoom.localParticipant!,
            audioCaptureOptions: audioCaptureOptions,
            hasDeviceOverride: device != null,
            initialMicrophoneEnableState: initialMicrophoneEnableState,
          );
        }

        livekitRoom = lkRoom;
        return MatrixLivekitVoipSession(
          room,
          lkRoom,
          stateKey: stateKey,
          foci: fociUrl,
          initialMicrophoneEnableState: initialMicrophoneEnableState,
        );
      } catch (error, stackTrace) {
        initialMicrophoneEnableState.markCallInactive();
        if (identical(livekitRoom, lkRoom)) {
          livekitRoom = null;
        }
        Log.onError(
          error,
          stackTrace,
          content:
              'LiveKit post-connect initialization failed; cleaning up room',
          category: LogCategory.livekit,
          source: 'matrix-livekit-backend',
        );
        await _clearMatrixRtcMembershipAfterJoinFailure(
          stateKey: stateKey,
          failureContent:
              'Failed to clear MatrixRTC membership after post-connect error',
        );
        await _cleanupFailedLiveKitRoom(
          lkRoom,
          phase: 'post_connect_initialization_failure',
        );
        rethrow;
      }
    } finally {
      await nativeCrashGuard?.clear();
    }
  }

  Future<void> _clearMatrixRtcMembershipAfterJoinFailure({
    required String stateKey,
    required String failureContent,
  }) async {
    try {
      await room.matrixRoom.client.setRoomStateWithKey(
        room.matrixRoom.id,
        MatrixVoipRoomComponent.callMemberStateEvent,
        stateKey,
        {},
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: failureContent,
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    }
  }

  Future<void> _enableInitialMicrophoneDuringJoin(
    lk.LocalParticipant participant, {
    required lk.AudioCaptureOptions audioCaptureOptions,
    required bool hasDeviceOverride,
    required MatrixLivekitInitialMicrophoneEnableState
    initialMicrophoneEnableState,
  }) async {
    final nativeActionGuard = await PendingNativeCallCrashGuard.recordAction(
      source: 'matrix-livekit-native-call-action-initial-microphone-enable',
      actionKind: 'LiveKit initial microphone enable',
    );
    final stopwatch = Stopwatch()..start();
    var clearActionGuard = true;

    Log.i(
      'LiveKit initial microphone enable starting: '
      'timeout_ms=${_initialMicrophoneEnableTimeout.inMilliseconds} '
      'has_device_override=$hasDeviceOverride',
      category: LogCategory.livekit,
      source: 'matrix-livekit-backend',
    );

    final enableFuture = participant.setMicrophoneEnabled(
      true,
      audioCaptureOptions: audioCaptureOptions,
    );

    try {
      if (PlatformUtils.isWindows) {
        await enableFuture.timeout(_initialMicrophoneEnableTimeout);
      } else {
        await enableFuture;
      }
      _logInitialMicrophoneEnableCompleted(stopwatch);
    } on TimeoutException catch (error, stackTrace) {
      if (!PlatformUtils.isWindows) {
        rethrow;
      }
      clearActionGuard = false;
      Log.onError(
        error,
        stackTrace,
        content:
            'LiveKit initial microphone enable timed out during Windows call join; continuing while native publish settles',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
      unawaited(
        _observeLateInitialMicrophoneEnable(
          enableFuture,
          stopwatch,
          nativeActionGuard,
          participant: participant,
          initialMicrophoneEnableState: initialMicrophoneEnableState,
        ),
      );
    } catch (error, stackTrace) {
      if (!PlatformUtils.isWindows) {
        rethrow;
      }
      Log.onError(
        error,
        stackTrace,
        content:
            'LiveKit microphone capture failed during Windows call join; continuing muted',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    } finally {
      if (clearActionGuard) {
        await nativeActionGuard?.clear();
      }
    }
  }

  Future<void> _observeLateInitialMicrophoneEnable(
    Future<void> enableFuture,
    Stopwatch stopwatch,
    PendingNativeCallCrashGuard? nativeActionGuard, {
    required lk.LocalParticipant participant,
    required MatrixLivekitInitialMicrophoneEnableState
    initialMicrophoneEnableState,
  }) async {
    try {
      await enableFuture;
      if (!initialMicrophoneEnableState.shouldKeepLateCompletionEnabled) {
        await _rollbackStaleInitialMicrophoneEnable(
          participant,
          initialMicrophoneEnableState,
          stopwatch,
        );
        return;
      }
      _logInitialMicrophoneEnableCompleted(stopwatch, afterTimeout: true);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'LiveKit initial microphone enable failed after Windows call join timeout',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    } finally {
      await nativeActionGuard?.clear();
    }
  }

  Future<void> _rollbackStaleInitialMicrophoneEnable(
    lk.LocalParticipant participant,
    MatrixLivekitInitialMicrophoneEnableState initialMicrophoneEnableState,
    Stopwatch stopwatch,
  ) async {
    stopwatch.stop();
    Log.w(
      'LiveKit initial microphone enable completed after timeout but is stale; '
      'active=${initialMicrophoneEnableState.isCallActive} '
      'desired_enabled=${initialMicrophoneEnableState.desiredMicrophoneEnabled} '
      'generation=${initialMicrophoneEnableState.generation} '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      category: LogCategory.livekit,
      source: 'matrix-livekit-backend',
    );
    try {
      await _disableStaleInitialMicrophoneEnable(
        participant,
      ).timeout(_staleInitialMicrophoneDisableTimeout);
      Log.i(
        'LiveKit stale initial microphone enable rollback completed',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to disable stale LiveKit initial microphone enable after timeout',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    }
  }

  Future<void> _disableStaleInitialMicrophoneEnable(
    lk.LocalParticipant participant,
  ) async {
    if (PlatformUtils.isWindows) {
      final publication = participant.getTrackPublicationBySource(
        lk.TrackSource.microphone,
      );
      if (publication != null) {
        await _setMicrophoneSenderDetachedForWindows(
          publication,
          reason: 'stale_initial_enable',
        );
        return;
      }
    }

    await participant.setMicrophoneEnabled(false);
  }

  Future<void> _setMicrophoneSenderDetachedForWindows(
    lk.LocalTrackPublication publication, {
    required String reason,
  }) async {
    final track = publication.track;
    if (track == null) {
      Log.w(
        'LiveKit Windows microphone sender detach skipped: '
        'reason=$reason missing_track=true',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
      return;
    }

    final sender = track.sender;
    if (sender == null) {
      Log.w(
        'LiveKit Windows microphone sender detach skipped: '
        'reason=$reason missing_sender=true',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
      if (!publication.muted) {
        // ignore: invalid_use_of_internal_member
        track.updateMuted(true, shouldSendSignal: true);
      }
      return;
    }

    final senderAlreadyDetached = sender.track == null;
    if (senderAlreadyDetached && publication.muted) {
      Log.d(
        'LiveKit Windows microphone sender detach skipped: '
        'reason=$reason already_detached=true',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
      return;
    }

    Log.i(
      'LiveKit Windows microphone sender detach starting: '
      'reason=$reason publication_muted=${publication.muted} '
      'sender_detached=$senderAlreadyDetached',
      category: LogCategory.livekit,
      source: 'matrix-livekit-backend',
    );
    await sender.replaceTrack(null);
    // LiveKit's normal mute path toggles MediaStreamTrack.enabled on Windows,
    // and the local unpublish path removes/disposes native track state. Keep
    // the track alive and only signal the muted metadata.
    // ignore: invalid_use_of_internal_member
    track.updateMuted(true, shouldSendSignal: true);
    Log.i(
      'LiveKit Windows microphone sender detach completed: reason=$reason',
      category: LogCategory.livekit,
      source: 'matrix-livekit-backend',
    );
  }

  void _logInitialMicrophoneEnableCompleted(
    Stopwatch stopwatch, {
    bool afterTimeout = false,
  }) {
    stopwatch.stop();
    NoiseSuppressionService.instance.scheduleHealthRefresh();
    Log.i(
      'LiveKit initial microphone enable completed'
      '${afterTimeout ? ' after timeout' : ''}: '
      'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      category: LogCategory.livekit,
      source: 'matrix-livekit-backend',
    );
  }

  Future<void> _ensureE2eeCallJoinAllowed() async {
    if (!room.isE2EE) {
      return;
    }

    final appClient = room.client;
    if (appClient is! MatrixClient) {
      return;
    }

    try {
      await appClient.refreshE2eeTrustStatus().timeout(
        _e2eeTrustRefreshTimeout,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to refresh Matrix E2EE trust before call join',
        category: LogCategory.matrix,
        source: 'matrix-livekit-backend',
      );
    }

    final status = appClient.e2eeTrustStatus;
    if (status.currentDeviceHealthy) {
      return;
    }

    Log.w(
      'Blocked LiveKit join from unhealthy E2EE session '
      'client=${status.clientIdHash} user=${status.userIdHash} '
      'encryption=${status.encryptionAvailable} '
      'cross_signing=${status.crossSigningEnabled} '
      'known=${status.currentDeviceKnown} '
      'verified=${status.currentDeviceVerified} '
      'blocked=${status.currentDeviceBlocked} '
      'backup=${status.keyBackupEnabled}',
      category: LogCategory.livekit,
      source: 'matrix-livekit-backend',
    );

    throw MatrixLivekitCallJoinPreflightException(
      'Verify this session before joining encrypted calls. '
      'Open Settings > Account > Security and verify this session or enter '
      'your recovery key, then try joining the call again.',
    );
  }

  Future<lk.Room> _connectLiveKitRoom(
    lk.RoomOptions roomOptions,
    String sfuUrl,
    String jwt,
  ) async {
    for (var attempt = 1; ; attempt++) {
      final lkRoom = lk.Room(roomOptions: roomOptions);
      try {
        await lkRoom.prepareConnection(sfuUrl, jwt);
        await lkRoom.connect(sfuUrl, jwt);
        return lkRoom;
      } catch (error, stackTrace) {
        final retryDelay = _connectRetryPolicy.retryDelayFor(
          error,
          failedAttempt: attempt,
        );
        if (retryDelay == null) {
          await _cleanupFailedLiveKitRoom(lkRoom, phase: 'connect_failure');
          if (_connectRetryPolicy.isTransientLiveKitConnectError(error) &&
              attempt >= _connectRetryPolicy.maxAttempts) {
            Error.throwWithStackTrace(
              MatrixLivekitCallJoinTransientNetworkException(
                attempts: attempt,
                lastError: error,
              ),
              stackTrace,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        }

        Log.w(
          "LiveKit connect hit transient network state; "
          "retrying attempt ${attempt + 1}/${_connectRetryPolicy.maxAttempts} "
          "after ${retryDelay.inMilliseconds}ms",
          category: LogCategory.livekit,
          source: 'matrix-livekit-backend',
        );
        await _cleanupFailedLiveKitRoom(lkRoom, phase: 'connect_retry');
        await Future.delayed(retryDelay);
      }
    }
  }

  Future<void> _cleanupFailedLiveKitRoom(
    lk.Room lkRoom, {
    required String phase,
  }) async {
    await _disconnectFailedLiveKitRoom(lkRoom, phase: phase);

    try {
      await lkRoom.dispose().timeout(_failedLiveKitRoomDisposeTimeout);
    } on TimeoutException {
      Log.w(
        'Timed out disposing failed LiveKit room: '
        'phase=$phase '
        'timeout_ms=${_failedLiveKitRoomDisposeTimeout.inMilliseconds}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to dispose LiveKit room after failed join phase=$phase',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    }
  }

  Future<void> _disconnectFailedLiveKitRoom(
    lk.Room lkRoom, {
    required String phase,
  }) async {
    try {
      await lkRoom.disconnect().timeout(_failedLiveKitRoomDisconnectTimeout);
    } on TimeoutException {
      Log.w(
        'Timed out disconnecting failed LiveKit room: '
        'phase=$phase '
        'timeout_ms=${_failedLiveKitRoomDisconnectTimeout.inMilliseconds}',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to disconnect LiveKit room after failed join phase=$phase',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
    }
  }
}
