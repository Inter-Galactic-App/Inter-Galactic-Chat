import 'dart:convert';

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

class MatrixLivekitBackend {
  MatrixRoom room;
  lk.Room? livekitRoom;
  MatrixLivekitBackend(this.room);
  static const _tokenRequestTimeout = Duration(seconds: 10);
  static const _connectRetryDelay = Duration(milliseconds: 900);
  static const _e2eeTrustRefreshTimeout = Duration(seconds: 4);
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

    Map<String, dynamic> buildTokenRequestBody({required bool clientInfo}) => {
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
    final gpuPipelineTestModeEnabled = PlatformUtils.isWindows &&
        preferences.developerMode.value &&
        preferences.streamGpuPipelineTestMode.value;
    final defaultScreenShare = ScreenShareProfileConfig.forPreferenceKey(
      gpuPipelineTestModeEnabled
          ? ScreenShareQualityProfile.smooth.storageKey
          : preferences.screenShareQualityProfile.value,
      preferHardwareEncoding: PlatformUtils.isWindows &&
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

    final lkRoom = lk.Room(roomOptions: roomOptions);
    await lkRoom.prepareConnection(sfuUrl, jwt);
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

    try {
      await _connectLiveKitRoom(lkRoom, sfuUrl, jwt);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'LiveKit connect failed; clearing MatrixRTC membership',
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
      try {
        await room.matrixRoom.client.setRoomStateWithKey(
          room.matrixRoom.id,
          MatrixVoipRoomComponent.callMemberStateEvent,
          stateKey,
          {},
        );
      } catch (clearError, clearStackTrace) {
        Log.onError(
          clearError,
          clearStackTrace,
          content: 'Failed to clear MatrixRTC membership after connect error',
          category: LogCategory.livekit,
          source: 'matrix-livekit-backend',
        );
      }
      rethrow;
    }

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
    } else {
      final audioCaptureOptions = device != null
          ? defaultAudioCaptureOptions.copyWith(deviceId: device)
          : defaultAudioCaptureOptions;
      Log.i(
        "LiveKit microphone capture profile: "
        "${NoiseSuppressionCaptureProfile.captureFrontendSummary(
          bypassVoiceProcessing: PlatformUtils.isIOS,
        )} "
        "constraints=${NoiseSuppressionCaptureProfile.describeAudioCaptureOptions(audioCaptureOptions)}",
      );

      // Keep desktop capture settings aligned across Matrix 1:1 and LiveKit
      // so built-in suppression is only disabled when the native RNNoise hook
      // actually came up successfully.
      try {
        await lkRoom.localParticipant!.setMicrophoneEnabled(
          true,
          audioCaptureOptions: audioCaptureOptions,
        );
        NoiseSuppressionService.instance.scheduleHealthRefresh();
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
      }
    }

    livekitRoom = lkRoom;
    return MatrixLivekitVoipSession(
      room,
      lkRoom,
      stateKey: stateKey,
      foci: fociUrl,
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
      await appClient
          .refreshE2eeTrustStatus()
          .timeout(_e2eeTrustRefreshTimeout);
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

  Future<void> _connectLiveKitRoom(
    lk.Room lkRoom,
    String sfuUrl,
    String jwt,
  ) async {
    try {
      await lkRoom.connect(sfuUrl, jwt);
      return;
    } catch (error, stackTrace) {
      if (!_isTransientLiveKitConnectError(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      Log.w(
        "LiveKit connect hit transient network state; retrying once",
        category: LogCategory.livekit,
        source: 'matrix-livekit-backend',
      );
      await Future.delayed(_connectRetryDelay);
    }

    await lkRoom.connect(sfuUrl, jwt);
  }

  bool _isTransientLiveKitConnectError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('notallowed') ||
        message.contains('not allowed') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        message.contains('statuscode: 401') ||
        message.contains('statuscode: 403')) {
      return false;
    }

    return message.contains('no internet connection') ||
        message.contains('connectexception') ||
        message.contains('socketexception') ||
        message.contains('httpexception') ||
        message.contains('failed host lookup') ||
        message.contains('connection closed before full header') ||
        message.contains('connection timed out') ||
        message.contains('timed out');
  }
}
