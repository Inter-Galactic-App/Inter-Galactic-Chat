import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class NoiseSuppressionCaptureProfile {
  static const int rnnoisePreferredSampleRateHz = 48000;
  static const int rnnoisePreferredChannelCount = 1;
  static const String localProcessedCaptureLabel = 'Local processed capture';

  static bool get _useNativeSuppression =>
      NoiseSuppressionService.instance.shouldDisableBuiltInNoiseSuppression;
  static bool get _requestRnnoiseReferenceFormat =>
      NoiseSuppressionService.instance.shouldRequestReferenceCaptureFormat;

  static Map<String, dynamic> buildWebrtcAudioConstraints({
    String? deviceId,
    double? inputVolume,
    bool bypassVoiceProcessing = false,
  }) {
    final frontend = bypassVoiceProcessing
        ? voiceProcessingBypassFrontendOptions()
        : captureFrontendOptions();
    return buildWebrtcAudioConstraintsForFrontend(
      frontend,
      deviceId: deviceId,
      inputVolume: inputVolume,
    );
  }

  @visibleForTesting
  static Map<String, dynamic> buildWebrtcAudioConstraintsForFrontend(
    NoiseSuppressionCaptureFrontendOptions frontend, {
    String? deviceId,
    double? inputVolume,
  }) {
    final constraints = <String, dynamic>{
      'echoCancellation': frontend.echoCancellation,
      'noiseSuppression': frontend.noiseSuppression,
      'autoGainControl': frontend.autoGainControl,
    };

    final optional = <Map<String, dynamic>>[
      ..._webrtcOptionalConstraints(frontend),
      if (frontend.requestRnnoiseReferenceFormat)
        ..._referenceOptionalConstraints(),
    ];
    if (optional.isNotEmpty) {
      constraints['optional'] = optional;
    }

    if (frontend.requestRnnoiseReferenceFormat) {
      constraints['sampleRate'] = {'ideal': rnnoisePreferredSampleRateHz};
      constraints['channelCount'] = {'ideal': rnnoisePreferredChannelCount};
    }

    if (deviceId != null && deviceId.isNotEmpty) {
      constraints['deviceId'] = {'exact': deviceId};
    }

    final volume = volumeConstraintValue(
      inputVolume,
      includeVolumeConstraint: frontend.includeVolumeConstraint,
    );
    if (volume != null) {
      constraints['volume'] = volume;
    }

    return constraints;
  }

  static Map<String, dynamic> buildLocalProcessedMediaConstraints({
    String? deviceId,
    double? inputVolume,
  }) {
    return <String, dynamic>{
      'audio': buildWebrtcAudioConstraints(
        deviceId: deviceId,
        inputVolume: inputVolume,
      ),
      'video': false,
    };
  }

  static NoiseSuppressionAudioProcessingStatus audioProcessingStatus() {
    final frontend = captureFrontendOptions();
    final service = NoiseSuppressionService.instance;
    final nativeStatus = service.status;
    return NoiseSuppressionAudioProcessingStatus(
      debugOverrideActive: frontend.debugOverrideActive,
      compatibilityModeEnabled: frontend.usesRnnoiseCompatibilityMode,
      echoCancellationEnabled: frontend.echoCancellation,
      webrtcNoiseSuppressionEnabled: frontend.noiseSuppression,
      autoGainControlEnabled: frontend.autoGainControl,
      highPassFilterEnabled: frontend.highPassFilter,
      typingNoiseDetectionEnabled: frontend.typingNoiseDetection,
      rnnoiseReferenceFormatRequested: frontend.requestRnnoiseReferenceFormat,
      volumeConstraintEnabled: frontend.includeVolumeConstraint,
      rnnoiseEnabled: service.desiredEnabled,
      rnnoisePreset: service.tuningProfile.presetKey,
      nativeAvailable: nativeStatus.available,
      nativeActive: nativeStatus.active,
      nativeReason: nativeStatus.reason,
    );
  }

  static NoiseSuppressionCaptureFrontendOptions captureFrontendOptions() {
    final scenario = preferences.developerMode.value
        ? NoiseSuppressionTapOrderScenario.fromKey(
            preferences.voipAudioCaptureTapOrderScenario.value,
          )
        : NoiseSuppressionTapOrderScenario.manual;
    if (scenario != NoiseSuppressionTapOrderScenario.manual) {
      return NoiseSuppressionTapOrderScenario.optionsFor(scenario);
    }

    final debugOverrideActive =
        preferences.developerMode.value &&
        preferences.voipAudioCaptureDebugOverride.value;
    if (debugOverrideActive) {
      return NoiseSuppressionCaptureFrontendOptions(
        debugOverrideActive: true,
        tapOrderScenario: NoiseSuppressionTapOrderScenario.manual,
        echoCancellation: preferences.voipAudioCaptureEchoCancellation.value,
        noiseSuppression: preferences.voipAudioCaptureNoiseSuppression.value,
        autoGainControl: preferences.voipAudioCaptureAutoGainControl.value,
        highPassFilter: preferences.voipAudioCaptureHighPassFilter.value,
        typingNoiseDetection:
            preferences.voipAudioCaptureTypingNoiseDetection.value,
        requestRnnoiseReferenceFormat:
            preferences.voipAudioCaptureRequestReferenceFormat.value,
        includeVolumeConstraint:
            preferences.voipAudioCaptureVolumeConstraint.value,
      );
    }

    final requestRnnoiseReferenceFormat = _requestRnnoiseReferenceFormat;
    if (requestRnnoiseReferenceFormat &&
        preferences.voipNoiseSuppressionCompatibilityMode.value) {
      return rnnoiseCompatibilityFrontendOptions();
    }

    return NoiseSuppressionCaptureFrontendOptions(
      debugOverrideActive: false,
      tapOrderScenario: NoiseSuppressionTapOrderScenario.manual,
      echoCancellation: true,
      noiseSuppression: !_useNativeSuppression,
      autoGainControl: false,
      highPassFilter: false,
      typingNoiseDetection: true,
      requestRnnoiseReferenceFormat: requestRnnoiseReferenceFormat,
      includeVolumeConstraint: true,
    );
  }

  static NoiseSuppressionCaptureFrontendOptions
  rnnoiseCompatibilityFrontendOptions() {
    return const NoiseSuppressionCaptureFrontendOptions(
      debugOverrideActive: false,
      tapOrderScenario: NoiseSuppressionTapOrderScenario.rnnoiseCompatibility,
      echoCancellation: true,
      noiseSuppression: false,
      autoGainControl: false,
      highPassFilter: false,
      typingNoiseDetection: true,
      requestRnnoiseReferenceFormat: true,
      includeVolumeConstraint: true,
    );
  }

  static NoiseSuppressionCaptureFrontendOptions
  voiceProcessingBypassFrontendOptions() {
    return const NoiseSuppressionCaptureFrontendOptions(
      debugOverrideActive: false,
      tapOrderScenario: NoiseSuppressionTapOrderScenario.manual,
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      highPassFilter: false,
      typingNoiseDetection: false,
      requestRnnoiseReferenceFormat: false,
      includeVolumeConstraint: true,
    );
  }

  static String captureFrontendSignature({
    double? inputVolume,
    bool bypassVoiceProcessing = false,
  }) {
    final frontend = bypassVoiceProcessing
        ? voiceProcessingBypassFrontendOptions()
        : captureFrontendOptions();
    final volume = volumeConstraintValue(
      inputVolume ??
          normalizedMicrophoneVolumePreference(
            preferences.voipMicrophoneVolume.value,
          ),
      includeVolumeConstraint: frontend.includeVolumeConstraint,
    );
    return <String>[
      'override=${frontend.debugOverrideActive}',
      'scenario=${frontend.tapOrderScenario}',
      'aec=${frontend.echoCancellation}',
      'ns=${frontend.noiseSuppression}',
      'agc=${frontend.autoGainControl}',
      'highPass=${frontend.highPassFilter}',
      'typing=${frontend.typingNoiseDetection}',
      'ref48k=${frontend.requestRnnoiseReferenceFormat}',
      'volume=${volume?.toStringAsFixed(2) ?? 'omitted'}',
    ].join(';');
  }

  static String captureFrontendSummary({
    double? inputVolume,
    bool bypassVoiceProcessing = false,
  }) {
    final frontend = bypassVoiceProcessing
        ? voiceProcessingBypassFrontendOptions()
        : captureFrontendOptions();
    final volume = volumeConstraintValue(
      inputVolume ??
          normalizedMicrophoneVolumePreference(
            preferences.voipMicrophoneVolume.value,
          ),
      includeVolumeConstraint: frontend.includeVolumeConstraint,
    );
    return 'override=${frontend.debugOverrideActive} '
        'scenario=${frontend.tapOrderScenario} '
        'AEC=${_onOff(frontend.echoCancellation)} '
        'NS=${_onOff(frontend.noiseSuppression)} '
        'AGC=${_onOff(frontend.autoGainControl)} '
        'highPass=${_onOff(frontend.highPassFilter)} '
        'typing=${_onOff(frontend.typingNoiseDetection)} '
        '48k=${_onOff(frontend.requestRnnoiseReferenceFormat)} '
        'volume=${volume?.toStringAsFixed(2) ?? 'omitted'}';
  }

  static String describeConstraints(Map<String, dynamic> constraints) {
    final optional = constraints['optional'];
    final optionalSummary = <String, dynamic>{};
    if (optional is Iterable) {
      for (final entry in optional) {
        if (entry is Map && entry.length == 1) {
          optionalSummary[entry.keys.first.toString()] = entry.values.first;
        }
      }
    }
    final parts = <String>[
      'echoCancellation=${constraints['echoCancellation']}',
      'noiseSuppression=${constraints['noiseSuppression']}',
      'autoGainControl=${constraints['autoGainControl']}',
      'sampleRate=${_idealValue(constraints['sampleRate']) ?? 'default'}',
      'channelCount=${_idealValue(constraints['channelCount']) ?? 'default'}',
      'volume=${constraints.containsKey('volume') ? constraints['volume'] : 'omitted'}',
      'device=${constraints.containsKey('deviceId') ? 'set' : 'default'}',
    ];
    if (optionalSummary.isNotEmpty) {
      parts.add('optional=$optionalSummary');
    }
    return parts.join(' ');
  }

  static String describeAudioCaptureOptions(lk.AudioCaptureOptions options) {
    return describeConstraints(options.toMediaConstraintsMap());
  }

  static double normalizedMicrophoneVolumePreference(double percent) {
    return (percent / 100).clamp(0.0, 1.0).toDouble();
  }

  static double? volumeConstraintValue(
    double? inputVolume, {
    required bool includeVolumeConstraint,
  }) {
    if (!includeVolumeConstraint || inputVolume == null) {
      return null;
    }
    final volume = inputVolume.clamp(0.0, 1.0).toDouble();
    if ((volume - 1.0).abs() < 0.0001) {
      return null;
    }
    return volume;
  }

  static lk.AudioCaptureOptions buildLivekitAudioCaptureOptions({
    String? deviceId,
    double? inputVolume,
    bool bypassVoiceProcessing = false,
  }) {
    final frontend = bypassVoiceProcessing
        ? voiceProcessingBypassFrontendOptions()
        : captureFrontendOptions();
    return _IntergalacticAudioCaptureOptions(
      deviceId: deviceId,
      inputVolume: inputVolume,
      noiseSuppression: frontend.noiseSuppression,
      echoCancellation: frontend.echoCancellation,
      autoGainControl: frontend.autoGainControl,
      highPassFilter: frontend.highPassFilter,
      typingNoiseDetection: frontend.typingNoiseDetection,
      requestRnnoiseReferenceFormat: frontend.requestRnnoiseReferenceFormat,
      includeVolumeConstraint: frontend.includeVolumeConstraint,
    );
  }

  static Map<String, dynamic> addRnnoiseReferenceConstraints(
    Map<String, dynamic> constraints,
  ) {
    constraints['sampleRate'] = {
      'ideal': NoiseSuppressionCaptureProfile.rnnoisePreferredSampleRateHz,
    };
    constraints['channelCount'] = {
      'ideal': NoiseSuppressionCaptureProfile.rnnoisePreferredChannelCount,
    };

    final mergedOptional = <Map<String, dynamic>>[];
    final optional = constraints['optional'];
    if (optional is Iterable) {
      for (final entry in optional) {
        if (entry is Map) {
          mergedOptional.add(Map<String, dynamic>.from(entry));
        }
      }
    }

    mergedOptional.addAll(_referenceOptionalConstraints());
    constraints['optional'] = mergedOptional;

    return constraints;
  }

  static List<Map<String, dynamic>> _referenceOptionalConstraints() {
    return <Map<String, dynamic>>[
      <String, dynamic>{'sampleRate': rnnoisePreferredSampleRateHz},
      <String, dynamic>{'channelCount': rnnoisePreferredChannelCount},
    ];
  }

  static List<Map<String, dynamic>> _webrtcOptionalConstraints(
    NoiseSuppressionCaptureFrontendOptions frontend,
  ) {
    return <Map<String, dynamic>>[
      <String, dynamic>{'echoCancellation': frontend.echoCancellation},
      <String, dynamic>{'noiseSuppression': frontend.noiseSuppression},
      <String, dynamic>{'autoGainControl': frontend.autoGainControl},
      <String, dynamic>{'voiceIsolation': frontend.noiseSuppression},
      <String, dynamic>{'googDAEchoCancellation': frontend.echoCancellation},
      <String, dynamic>{'googEchoCancellation': frontend.echoCancellation},
      <String, dynamic>{'googEchoCancellation2': frontend.echoCancellation},
      <String, dynamic>{'googNoiseSuppression': frontend.noiseSuppression},
      <String, dynamic>{'googNoiseSuppression2': frontend.noiseSuppression},
      <String, dynamic>{'googAutoGainControl': frontend.autoGainControl},
      <String, dynamic>{'googHighpassFilter': frontend.highPassFilter},
      <String, dynamic>{
        'googTypingNoiseDetection': frontend.typingNoiseDetection,
      },
    ];
  }

  static Object? _idealValue(Object? constraint) {
    if (constraint is Map) {
      return constraint['ideal'];
    }
    return constraint;
  }

  static String _onOff(bool value) => value ? 'on' : 'off';
}

class NoiseSuppressionCaptureFrontendOptions {
  const NoiseSuppressionCaptureFrontendOptions({
    required this.debugOverrideActive,
    required this.tapOrderScenario,
    required this.echoCancellation,
    required this.noiseSuppression,
    required this.autoGainControl,
    required this.highPassFilter,
    required this.typingNoiseDetection,
    required this.requestRnnoiseReferenceFormat,
    required this.includeVolumeConstraint,
  });

  final bool debugOverrideActive;
  final String tapOrderScenario;
  final bool echoCancellation;
  final bool noiseSuppression;
  final bool autoGainControl;
  final bool highPassFilter;
  final bool typingNoiseDetection;
  final bool requestRnnoiseReferenceFormat;
  final bool includeVolumeConstraint;

  bool get usesRnnoiseCompatibilityMode =>
      !debugOverrideActive &&
      tapOrderScenario == NoiseSuppressionTapOrderScenario.rnnoiseCompatibility;
}

class NoiseSuppressionTapOrderScenario {
  const NoiseSuppressionTapOrderScenario._();

  static const String manual = 'manual';
  static const String rnnoiseOffDefault = 'rnnoise_off_default';
  static const String identitySameConstraints = 'identity_same_constraints';
  static const String rnnoiseSameConstraints = 'rnnoise_same_constraints';
  static const String rnnoiseNoVolume = 'rnnoise_no_volume';
  static const String rnnoiseNo48k = 'rnnoise_no_48k';
  static const String rnnoiseAgcOn = 'rnnoise_agc_on';
  static const String rnnoiseAgcOff = 'rnnoise_agc_off';
  static const String rnnoiseNsOff = 'rnnoise_ns_off';
  static const String rnnoiseCompatibility =
      NoiseSuppressionService.diagnosticRnnoiseCompatibilityScenarioKey;
  static const String rnnoiseAecOff = 'rnnoise_aec_off';
  static const String identityMinimalFrontend = 'identity_minimal_frontend';
  static const String rnnoiseMinimalFrontend = 'rnnoise_minimal_frontend';

  static const List<String> options = <String>[
    manual,
    rnnoiseOffDefault,
    identitySameConstraints,
    rnnoiseSameConstraints,
    rnnoiseNoVolume,
    rnnoiseNo48k,
    rnnoiseAgcOn,
    rnnoiseAgcOff,
    rnnoiseNsOff,
    rnnoiseCompatibility,
    rnnoiseAecOff,
    identityMinimalFrontend,
    rnnoiseMinimalFrontend,
  ];

  static const List<String> comparisonBatchOptions = <String>[
    rnnoiseOffDefault,
    identitySameConstraints,
    rnnoiseSameConstraints,
    rnnoiseNoVolume,
    rnnoiseNo48k,
    rnnoiseAgcOn,
    rnnoiseAgcOff,
    rnnoiseNsOff,
    rnnoiseAecOff,
    identityMinimalFrontend,
    rnnoiseMinimalFrontend,
  ];

  static String fromKey(String key) {
    return options.contains(key) ? key : manual;
  }

  static String labelFor(String key) {
    return switch (fromKey(key)) {
      rnnoiseOffDefault => 'Native pipeline off / default capture',
      identitySameConstraints => 'Hook identity / normal frontend',
      rnnoiseSameConstraints => 'RNNoise legacy / normal frontend',
      rnnoiseNoVolume => 'RNNoise legacy / no volume',
      rnnoiseNo48k => 'RNNoise legacy / no 48 kHz',
      rnnoiseAgcOn => 'RNNoise legacy / AGC on',
      rnnoiseAgcOff => 'RNNoise legacy / AGC off',
      rnnoiseNsOff => 'RNNoise legacy / WebRTC NS off',
      rnnoiseCompatibility => 'RNNoise legacy / compatibility mode',
      rnnoiseAecOff => 'RNNoise legacy / AEC off',
      identityMinimalFrontend => 'Identity / minimal frontend',
      rnnoiseMinimalFrontend => 'RNNoise legacy / minimal frontend',
      _ => 'Manual',
    };
  }

  static NoiseSuppressionCaptureFrontendOptions optionsFor(String key) {
    final scenario = fromKey(key);
    const sameConstraints = NoiseSuppressionCaptureFrontendOptions(
      debugOverrideActive: true,
      tapOrderScenario: rnnoiseSameConstraints,
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: false,
      highPassFilter: false,
      typingNoiseDetection: true,
      requestRnnoiseReferenceFormat: true,
      includeVolumeConstraint: true,
    );

    switch (scenario) {
      case rnnoiseOffDefault:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseOffDefault,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: false,
          includeVolumeConstraint: true,
        );
      case identitySameConstraints:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: identitySameConstraints,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: true,
          includeVolumeConstraint: true,
        );
      case rnnoiseNoVolume:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseNoVolume,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: true,
          includeVolumeConstraint: false,
        );
      case rnnoiseNo48k:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseNo48k,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: false,
          includeVolumeConstraint: true,
        );
      case rnnoiseAgcOn:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseAgcOn,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: true,
          includeVolumeConstraint: true,
        );
      case rnnoiseAgcOff:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseAgcOff,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: true,
          includeVolumeConstraint: true,
        );
      case rnnoiseNsOff:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseNsOff,
          echoCancellation: true,
          noiseSuppression: false,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: true,
          includeVolumeConstraint: true,
        );
      case rnnoiseCompatibility:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseCompatibility,
          echoCancellation: true,
          noiseSuppression: false,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: true,
          includeVolumeConstraint: true,
        );
      case rnnoiseAecOff:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseAecOff,
          echoCancellation: false,
          noiseSuppression: true,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: true,
          includeVolumeConstraint: true,
        );
      case identityMinimalFrontend:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: identityMinimalFrontend,
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: false,
          requestRnnoiseReferenceFormat: false,
          includeVolumeConstraint: false,
        );
      case rnnoiseMinimalFrontend:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: true,
          tapOrderScenario: rnnoiseMinimalFrontend,
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: false,
          requestRnnoiseReferenceFormat: false,
          includeVolumeConstraint: false,
        );
      case rnnoiseSameConstraints:
        return sameConstraints;
      case manual:
      default:
        return const NoiseSuppressionCaptureFrontendOptions(
          debugOverrideActive: false,
          tapOrderScenario: manual,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: false,
          highPassFilter: false,
          typingNoiseDetection: true,
          requestRnnoiseReferenceFormat: false,
          includeVolumeConstraint: true,
        );
    }
  }
}

class NoiseSuppressionAudioProcessingStatus {
  const NoiseSuppressionAudioProcessingStatus({
    required this.debugOverrideActive,
    required this.compatibilityModeEnabled,
    required this.echoCancellationEnabled,
    required this.webrtcNoiseSuppressionEnabled,
    required this.autoGainControlEnabled,
    required this.highPassFilterEnabled,
    required this.typingNoiseDetectionEnabled,
    required this.rnnoiseReferenceFormatRequested,
    required this.volumeConstraintEnabled,
    required this.rnnoiseEnabled,
    required this.rnnoisePreset,
    required this.nativeAvailable,
    required this.nativeActive,
    required this.nativeReason,
  });

  final bool debugOverrideActive;
  final bool compatibilityModeEnabled;
  final bool echoCancellationEnabled;
  final bool webrtcNoiseSuppressionEnabled;
  final bool autoGainControlEnabled;
  final bool highPassFilterEnabled;
  final bool typingNoiseDetectionEnabled;
  final bool rnnoiseReferenceFormatRequested;
  final bool volumeConstraintEnabled;
  final bool rnnoiseEnabled;
  final String rnnoisePreset;
  final bool nativeAvailable;
  final bool nativeActive;
  final String nativeReason;

  List<String> get lines => <String>[
    'Capture override: ${_onOff(debugOverrideActive)}',
    'Native compatibility mode: ${_onOff(compatibilityModeEnabled)}',
    'WebRTC echo cancellation: ${_onOff(echoCancellationEnabled)}',
    'WebRTC noise suppression: ${_onOff(webrtcNoiseSuppressionEnabled)}',
    'WebRTC auto gain: ${_onOff(autoGainControlEnabled)}',
    'WebRTC high-pass filter: ${_onOff(highPassFilterEnabled)}',
    'WebRTC typing noise detection: ${_onOff(typingNoiseDetectionEnabled)}',
    'Native 48 kHz reference request: '
        '${_onOff(rnnoiseReferenceFormatRequested)}',
    'Mic volume constraint: ${_onOff(volumeConstraintEnabled)}',
    'Native noise suppression: ${_onOff(rnnoiseEnabled)} '
        'preset=$rnnoisePreset',
    'Native status: available=$nativeAvailable active=$nativeActive '
        'reason=$nativeReason',
  ];

  static String _onOff(bool value) => value ? 'on' : 'off';
}

class _IntergalacticAudioCaptureOptions extends lk.AudioCaptureOptions {
  const _IntergalacticAudioCaptureOptions({
    super.deviceId,
    super.noiseSuppression,
    super.echoCancellation,
    super.autoGainControl,
    super.highPassFilter,
    super.typingNoiseDetection,
    this.inputVolume,
    this.requestRnnoiseReferenceFormat = false,
    this.includeVolumeConstraint = true,
  });

  final double? inputVolume;
  final bool requestRnnoiseReferenceFormat;
  final bool includeVolumeConstraint;

  @override
  Map<String, dynamic> toMediaConstraintsMap() {
    final constraints = super.toMediaConstraintsMap();

    final volume = NoiseSuppressionCaptureProfile.volumeConstraintValue(
      inputVolume,
      includeVolumeConstraint: includeVolumeConstraint,
    );
    if (volume != null) {
      constraints['volume'] = volume;
    }

    if (requestRnnoiseReferenceFormat) {
      return NoiseSuppressionCaptureProfile.addRnnoiseReferenceConstraints(
        constraints,
      );
    }

    return constraints;
  }

  @override
  lk.AudioCaptureOptions copyWith({
    String? deviceId,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? autoGainControl,
    bool? highPassFilter,
    bool? typingNoiseDetection,
  }) {
    return _IntergalacticAudioCaptureOptions(
      deviceId: deviceId ?? this.deviceId,
      inputVolume: inputVolume,
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      autoGainControl: autoGainControl ?? this.autoGainControl,
      highPassFilter: highPassFilter ?? this.highPassFilter,
      typingNoiseDetection: typingNoiseDetection ?? this.typingNoiseDetection,
      requestRnnoiseReferenceFormat: requestRnnoiseReferenceFormat,
      includeVolumeConstraint: includeVolumeConstraint,
    );
  }
}
