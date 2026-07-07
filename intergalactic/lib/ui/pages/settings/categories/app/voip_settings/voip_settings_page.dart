import 'dart:async';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_diagnostic_directory.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/string_preference_options.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/voip_settings/voip_debug_settings.dart';
import 'package:flutter/material.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class VoipSettingsPage extends StatefulWidget {
  const VoipSettingsPage({super.key});

  @override
  State<VoipSettingsPage> createState() => _VoipSettingsPage();
}

class _VoipSettingsPage extends _VoipSettingsPageBase<VoipSettingsPage> {}

class VoipDeveloperSettings extends StatefulWidget {
  const VoipDeveloperSettings({super.key});

  @override
  State<VoipDeveloperSettings> createState() => _VoipDeveloperSettingsState();
}

class _VoipDeveloperSettingsState
    extends _VoipSettingsPageBase<VoipDeveloperSettings> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: headerVoipSettingsCallConnection,
          children: [
            BooleanPreferenceToggle(
              preference: preferences.useFallbackTurnServer,
              title: labelVoipSettingsStunFallback,
              description: labelVoipSettingsStunFallbackDescription(
                preferences.fallbackTurnServer.value,
              ),
            ),
          ],
        ),
        if (supportsNativeRnnoise)
          SettingsSection(
            title: labelVoipNoiseSuppressionDiagnostics,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  StringPreferenceOptionsPicker(
                    preference: preferences.voipNoiseSuppressionPreset,
                    title: labelVoipNoiseSuppressionPreset,
                    description: labelVoipNoiseSuppressionPresetDescription,
                    options: NoiseSuppressionTuningProfile.presetKeys,
                    onChanged: (preset) {
                      unawaited(
                        _applyNoiseSuppressionSettings(presetKey: preset),
                      );
                    },
                  ),
                  if (preferences.voipNoiseSuppressionPreset.value ==
                      NoiseSuppressionTuningProfile.customKey) ...[
                    DoublePreferenceSlider(
                      preference: preferences.voipNoiseSuppressionVadThreshold,
                      min: 0.75,
                      max: 0.99,
                      numDecimals: 2,
                      title: labelVoipNoiseSuppressionVadThreshold,
                      description:
                          labelVoipNoiseSuppressionVadThresholdDescription,
                      onChanged: (value) {
                        unawaited(
                          _applyNoiseSuppressionSettings(
                            customVadThreshold: value,
                          ),
                        );
                      },
                    ),
                    DoublePreferenceSlider(
                      preference: preferences.voipNoiseSuppressionSpeechGraceMs,
                      min: 0,
                      max: 300,
                      numDecimals: 0,
                      units: "ms",
                      title: labelVoipNoiseSuppressionGrace,
                      description: labelVoipNoiseSuppressionGraceDescription,
                      onChanged: (value) {
                        unawaited(
                          _applyNoiseSuppressionSettings(
                            customSpeechGraceMs: value,
                          ),
                        );
                      },
                    ),
                    DoublePreferenceSlider(
                      preference:
                          preferences.voipNoiseSuppressionClosedGainPercent,
                      min: 0,
                      max: 10,
                      numDecimals: 1,
                      units: "%",
                      title: labelVoipNoiseSuppressionClosedGain,
                      description:
                          labelVoipNoiseSuppressionClosedGainDescription,
                      onChanged: (value) {
                        unawaited(
                          _applyNoiseSuppressionSettings(
                            customClosedGainPercent: value,
                          ),
                        );
                      },
                    ),
                    DoublePreferenceSlider(
                      preference:
                          preferences.voipNoiseSuppressionTransientSensitivity,
                      min: 0,
                      max: 100,
                      numDecimals: 0,
                      units: "%",
                      title: labelVoipNoiseSuppressionTransientSensitivity,
                      description:
                          labelVoipNoiseSuppressionTransientSensitivityDescription,
                      onChanged: (value) {
                        unawaited(
                          _applyNoiseSuppressionSettings(
                            customTransientSensitivityPercent: value,
                          ),
                        );
                      },
                    ),
                  ],
                  StringPreferenceOptionsPicker(
                    preference: preferences.voipNoiseSuppressionHookMode,
                    title: 'Noise suppression hook mode',
                    description:
                        'Developer diagnostic hook mode. Enhanced runs the bundled DeepFilterNet callback processor for live call-room testing.',
                    options: const [
                      'rnnoise',
                      NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
                      'identity',
                      'off',
                    ],
                    optionLabelBuilder: _noiseSuppressionHookModeLabel,
                    onChanged: (mode) {
                      unawaited(_onNoiseSuppressionHookModeChanged(mode));
                    },
                  ),
                  BooleanPreferenceToggle(
                    preference: preferences
                        .voipNoiseSuppressionDeepFilterNetTransientSuppression,
                    title: 'Transient click guard',
                    description:
                        'Experimental post-DeepFilterNet layer for short keyboard and mouse spikes. Leave off to compare Enhanced DeepFilterNet alone.',
                    onChanged: (_) {
                      unawaited(_applyNoiseSuppressionSettings());
                    },
                  ),
                  BooleanPreferenceToggle(
                    preference: preferences
                        .voipNoiseSuppressionDeepFilterNetHushSuppression,
                    title: 'Hush voice isolation',
                    description:
                        'Experimental post-DeepFilterNet support layer for background voices and speaker bleed. Leave off to compare Enhanced DeepFilterNet alone.',
                    onChanged: (_) {
                      unawaited(_applyNoiseSuppressionSettings());
                    },
                  ),
                  StringPreferenceOptionsPicker(
                    preference: preferences.voipAudioCaptureTapOrderScenario,
                    title: 'Audio pipeline capture scenario',
                    description:
                        'Freezes one WebRTC audio constraint set for tap-order comparisons.',
                    options: NoiseSuppressionTapOrderScenario.options,
                    optionLabelBuilder:
                        NoiseSuppressionTapOrderScenario.labelFor,
                    onChanged: (scenario) {
                      unawaited(
                        _onAudioCaptureTapOrderScenarioChanged(scenario),
                      );
                    },
                  ),
                  audioCaptureFrontendControls(),
                  noiseSuppressionDiagnosticCaptureControls(),
                  noiseSuppressionDiagnostics(),
                  enhancedBackendStatus(),
                  audioProcessingStatus(),
                ],
              ),
            ],
          ),
        SettingsSection(
          title: "Stream developer controls",
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                BooleanPreferenceToggle(
                  preference: preferences.streamAdvancedOverride,
                  title: labelVoipAdvancedStreamOverride,
                  description: labelVoipAdvancedStreamOverrideDescription,
                ),
                BooleanPreferenceToggle(
                  preference: preferences.streamAdaptiveFallbackEnabled,
                  title: labelVoipAdaptiveFallback,
                  description: labelVoipAdaptiveFallbackDescription,
                ),
                if (PlatformUtils.isWindows)
                  BooleanPreferenceToggle(
                    preference: preferences.streamGpuPipelineTestMode,
                    title: labelVoipStreamGpuPipelineTestMode,
                    description: labelVoipStreamGpuPipelineTestModeDescription,
                  ),
                if (PlatformUtils.isWindows)
                  BooleanPreferenceToggle(
                    preference: preferences.streamHardwareEncodingFirst,
                    title: labelVoipStreamHardwareEncodingFirst,
                    description:
                        labelVoipStreamHardwareEncodingFirstDescription,
                  ),
                BooleanPreferenceToggle(
                  preference: preferences.showCallStreamStats,
                  title: "Show call/stream stats",
                  description:
                      "Display LiveKit sender and receiver diagnostics during calls.",
                ),
                if (preferences.streamAdvancedOverride.value) ...[
                  BooleanPreferenceToggle(
                    preference: preferences.doSimulcast,
                    title: labelVoipUseSimulcast,
                    description: labelVoipUseSimulcastDescription,
                  ),
                  DoublePreferenceSlider(
                    preference: preferences.streamBitrate,
                    min: 1,
                    max: 32,
                    units: "Mbps",
                    title: labelVoipStreamMaximumBitrate,
                    description: labelVoipStreamMaximumBitrateDescription,
                  ),
                  DoublePreferenceSlider(
                    preference: preferences.streamFramerate,
                    min: 5,
                    max: 60,
                    numDecimals: 0,
                    units: "FPS",
                    title: labelVoipStreamFramerate,
                    description: labelVoipStreamFramerateDescription,
                  ),
                  StringPreferenceOptionsPicker(
                    preference: preferences.streamCodec,
                    title: labelVoipStreamPreferredCodec,
                    description: labelVoipStreamPreferredCodecDescription,
                    options: ["h264", "h265", "vp9", "vp8", "av1"],
                  ),
                  StringPreferenceOptionsPicker(
                    preference: preferences.streamResolution,
                    title: labelVoipStreamResolution,
                    description: labelVoipStreamResolutionDescription,
                    options: [
                      "640x360",
                      "960x540",
                      "1280x720",
                      "1920x1080",
                      "2560x1440",
                    ],
                  ),
                  activeStreamOverrideSummary(),
                ],
              ],
            ),
          ],
        ),
        const SettingsSection(
          title: "WebRTC Debug Menu",
          showDivider: false,
          children: [VoipDebugSettings()],
        ),
      ],
    );
  }
}

class _VoipDeveloperStatusCard extends StatelessWidget {
  const _VoipDeveloperStatusCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.72),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.35,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoiceDeviceColumn extends StatelessWidget {
  const _VoiceDeviceColumn({required this.picker, required this.slider});

  final Widget picker;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [picker, slider],
    );
  }
}

class _VolumePreferenceSlider extends StatefulWidget {
  const _VolumePreferenceSlider({
    required this.title,
    required this.value,
    required this.onSettled,
    this.max = 100,
  });

  final String title;
  final double value;
  final double max;
  final FutureOr<void> Function(double value) onSettled;

  @override
  State<_VolumePreferenceSlider> createState() =>
      _VolumePreferenceSliderState();
}

class _VolumePreferenceSliderState extends State<_VolumePreferenceSlider> {
  late double value;

  @override
  void initState() {
    super.initState();
    value = widget.value.clamp(0.0, widget.max).toDouble();
  }

  @override
  void didUpdateWidget(covariant _VolumePreferenceSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.max != widget.max) {
      value = widget.value.clamp(0.0, widget.max).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(
          widget.title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: tiamat.Slider(
                value: value,
                min: 0,
                max: widget.max,
                onChanged: (newValue) {
                  final rounded = double.parse(newValue.toStringAsFixed(0));
                  setState(() {
                    value = rounded;
                  });
                },
                onChangeEnd: (newValue) {
                  final rounded = double.parse(newValue.toStringAsFixed(0));
                  setState(() {
                    value = rounded;
                  });
                  unawaited(Future.sync(() => widget.onSettled(rounded)));
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              child: Text(
                '${value.round()}%',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AudioLevelMeter extends StatelessWidget {
  const _AudioLevelMeter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clampedLevel = level.clamp(0.0, 1.0).toDouble();
    const barCount = 42;
    final activeBars = (clampedLevel * barCount).round();

    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          final active = index < activeBars;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: active ? 30 : 24,
                decoration: BoxDecoration(
                  color: active
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

abstract class _VoipSettingsPageBase<T extends StatefulWidget>
    extends State<T> {
  StreamSubscription? sub;
  StreamSubscription? noiseSuppressionStatusSub;

  List<webrtc.MediaDeviceInfo>? devices;

  List<webrtc.MediaDeviceInfo>? microphones = [];
  List<webrtc.MediaDeviceInfo>? speakers = [];
  List<webrtc.MediaDeviceInfo>? cameras = [];
  webrtc.MediaStream? micCheckStream;
  webrtc.RTCPeerConnection? micCheckPeerConnection;
  webrtc.RTCRtpSender? micCheckSender;
  Timer? micCheckLevelTimer;
  bool micCheckStarting = false;
  bool micCheckStatsPolling = false;
  double micCheckLevel = 0;
  String? micCheckError;
  bool rnnoiseDiagnosticCaptureBusy = false;
  String? rnnoiseDiagnosticCaptureMessage;
  webrtc.MediaStream? cameraTestStream;
  webrtc.RTCVideoRenderer? cameraTestRenderer;
  bool cameraTestStarting = false;
  String? cameraTestError;

  bool get supportsNativeRnnoise =>
      PlatformUtils.isWindows || PlatformUtils.isMacOS;

  String get headerVoipSettingsCallConnection => Intl.message(
    "Call Connection",
    name: "headerVoipSettingsCallConnection",
    desc:
        "Header for the settings tile containing configuration relating to the initial connection of a call",
  );

  String get labelVoipSettingsStunFallback => Intl.message(
    "Use STUN Fallback",
    name: "labelVoipSettingsStunFallback",
    desc: "label for the setting to enable STUN callback for connecting calls",
  );

  String labelVoipSettingsStunFallbackDescription(
    String stunServer,
  ) => Intl.message(
    "Calls cannot be connected without a STUN server. If your homeserver does not provide a STUN server, fall back to using '${stunServer}'. Your IP address will be revealed to this server when establishing calls",
    args: [stunServer],
    name: "labelVoipSettingsStunFallbackDescription",
  );

  String get headerVoipSettingsDevices => Intl.message(
    "Devices",
    name: "headerVoipSettingsDevices",
    desc:
        "Header for settings tile containing device configuration, for default audio / video inputs",
  );

  String get headerVoipSettingsVoice => Intl.message(
    "Voice",
    name: "headerVoipSettingsVoice",
    desc: "Header for the settings section containing voice call controls",
  );

  String get headerVoipSettingsVideo => Intl.message(
    "Video",
    name: "headerVoipSettingsVideo",
    desc: "Header for the settings section containing camera controls",
  );

  String get labelVoipDefaultAudioInput => Intl.message(
    "Microphone",
    name: "labelVoipDefaultAudioInput",
    desc: "Label for the default microphone device picker",
  );

  String get labelVoipDefaultAudioOutput => Intl.message(
    "Speaker",
    name: "labelVoipDefaultAudioOutput",
    desc: "Label for the default speaker device picker",
  );

  String get labelVoipDefaultVideoInput => Intl.message(
    "Camera",
    name: "labelVoipDefaultVideoInput",
    desc: "Label for the default camera device picker",
  );

  String get labelVoipMicrophoneVolume => Intl.message(
    "Microphone Volume",
    name: "labelVoipMicrophoneVolume",
    desc: "Label for the microphone volume slider",
  );

  String get labelVoipSpeakerVolume => Intl.message(
    "Speaker Volume",
    name: "labelVoipSpeakerVolume",
    desc: "Label for the speaker volume slider",
  );

  String get labelVoipMicTest => Intl.message(
    "Mic Test",
    name: "labelVoipMicTest",
    desc: "Label for the microphone test button",
  );

  String get labelVoipStopMicTest => Intl.message(
    "Stop",
    name: "labelVoipStopMicTest",
    desc: "Label for stopping the microphone test",
  );

  String get labelVoipCameraTest => Intl.message(
    "Camera Test",
    name: "labelVoipCameraTest",
    desc: "Label for the camera test button",
  );

  String get labelVoipStopCameraTest => Intl.message(
    "Stop Camera",
    name: "labelVoipStopCameraTest",
    desc: "Label for stopping the camera test",
  );

  String get labelVoipPushToTalk => Intl.message(
    "Push to Talk",
    name: "labelVoipPushToTalk",
    desc: "Label for the push-to-talk setting",
  );

  String get labelVoipPushToTalkDescription => Intl.message(
    "Hold the Push to Talk shortcut to speak. Set the keybind from Shortcuts.",
    name: "labelVoipPushToTalkDescription",
    desc: "Description for the push-to-talk setting",
  );

  String get headerVoipSettingsStreamSettings => Intl.message(
    "Stream Settings",
    name: "headerVoipSettingsStreamSettings",
    desc: "Header for settings tile containing stream quality configuration",
  );

  String get labelVoipUseSimulcast => Intl.message(
    "Use Simulcast",
    name: "labelVoipUseSimulcast",
    desc: "label for setting toggle to enable use of Simulcast",
  );

  String get labelVoipUseSimulcastDescription => Intl.message(
    "Uploads your streams at multiple different levels of quality, so other users can decide which to use. This will use more bandwidth and system resources.",
    name: "labelVoipUseSimulcastDescription",
    desc: "description for setting toggle to enable use of Simulcast",
  );

  String get labelVoipScreenShareQuality =>
      Intl.message("Screen Share Quality", name: "labelVoipScreenShareQuality");

  String get labelVoipScreenShareQualityDescription => Intl.message(
    "Smooth is the default for stable gameplay streams and rooms with several viewers. Windows hardware H.264 is available in developer controls when you want to test it.",
    name: "labelVoipScreenShareQualityDescription",
  );

  String get labelVoipAdvancedStreamOverride => Intl.message(
    "Advanced stream override",
    name: "labelVoipAdvancedStreamOverride",
  );

  String get labelVoipAdvancedStreamOverrideDescription => Intl.message(
    "Use developer bitrate, FPS, codec, resolution, encoder, and simulcast controls instead of the selected quality profile.",
    name: "labelVoipAdvancedStreamOverrideDescription",
  );

  String get labelVoipStreamHardwareEncodingFirst => Intl.message(
    "Prefer hardware encoder",
    name: "labelVoipStreamHardwareEncodingFirst",
  );

  String get labelVoipStreamHardwareEncodingFirstDescription => Intl.message(
    "Use single-layer H.264 first so Windows can use Media Foundation hardware encoding. Leave this off if a stream starts black or the encoder times out.",
    name: "labelVoipStreamHardwareEncodingFirstDescription",
  );

  String get labelVoipStreamGpuPipelineTestMode => Intl.message(
    "GPU pipeline test mode",
    name: "labelVoipStreamGpuPipelineTestMode",
  );

  String get labelVoipStreamGpuPipelineTestModeDescription => Intl.message(
    "Developer-only: lock Windows game-window streams to Smooth 720p30, D3D11 game hook capture, Media Foundation H.264, native frame pacing, and no adaptive republish while testing.",
    name: "labelVoipStreamGpuPipelineTestModeDescription",
  );

  String get labelVoipAdaptiveFallback => Intl.message(
    "Adaptive stream fallback",
    name: "labelVoipAdaptiveFallback",
  );

  String get labelVoipAdaptiveFallbackDescription => Intl.message(
    "Experimental: lower the sender's screen-share limit after sustained low FPS, packet loss, CPU, or bandwidth pressure.",
    name: "labelVoipAdaptiveFallbackDescription",
  );

  String get labelVoipNoiseSuppression => Intl.message(
    "Noise Suppression",
    name: "labelVoipNoiseSuppression",
    desc: "Title for the native noise suppression call setting",
  );

  String get labelVoipNoiseSuppressionDescription => Intl.message(
    "Use the native desktop audio pipeline to clean microphone audio before it reaches the call encoder. Enhanced DeepFilterNet is used where available; calls continue with standard capture processing if the native backend is unavailable.",
    name: "labelVoipNoiseSuppressionDescription",
    desc: "Description for the native noise suppression desktop toggle",
  );

  String get labelVoipNoiseSuppressionCompatibilityMode => Intl.message(
    "RNNoise compatibility mode",
    name: "labelVoipNoiseSuppressionCompatibilityMode",
    desc: "Title for the affected-user RNNoise compatibility toggle",
  );

  String
  get labelVoipNoiseSuppressionCompatibilityModeDescription => Intl.message(
    "For microphones that pop with Noise Suppression on, keep RNNoise and echo cancellation on, use the safer RNNoise path, and turn off WebRTC's extra noise suppression for new mic captures. Turn this off if speech sounds worse.",
    name: "labelVoipNoiseSuppressionCompatibilityModeDescription",
    desc: "Description for the affected-user RNNoise compatibility toggle",
  );

  String get labelVoipNoiseSuppressionFallbackNotice => Intl.message(
    "Native noise suppression is not active on this device right now, so calls will continue without the extra suppression layer.",
    name: "labelVoipNoiseSuppressionFallbackNotice",
    desc: "Fallback notice shown when native noise suppression is unavailable",
  );

  String get labelVoipNoiseSuppressionDiagnostics => Intl.message(
    "Audio pipeline diagnostics",
    name: "labelVoipNoiseSuppressionDiagnostics",
    desc: "Header for the native audio pipeline diagnostic readout",
  );

  String get labelVoipNoiseSuppressionStartWavCapture => Intl.message(
    "Capture pipeline WAVs",
    name: "labelVoipNoiseSuppressionStartWavCapture",
    desc: "Button text to start developer audio pipeline WAV capture",
  );

  String get labelVoipNoiseSuppressionStopWavCapture => Intl.message(
    "Stop capture",
    name: "labelVoipNoiseSuppressionStopWavCapture",
    desc: "Button text to stop developer audio pipeline WAV capture",
  );

  String get labelVoipNoiseSuppressionWavCaptureDescription => Intl.message(
    "Developer-only local capture: raw mic sidecar, WebRTC hook input, native processor stage outputs, optional click/Hush support stages, and final WebRTC output. WAV bug-report upload is disabled; captures stay local for developer review.",
    name: "labelVoipNoiseSuppressionWavCaptureDescription",
    desc: "Description for developer audio pipeline WAV stage capture",
  );

  String get labelVoipNoiseSuppressionPreset => Intl.message(
    "Noise suppression preset",
    name: "labelVoipNoiseSuppressionPreset",
    desc: "Title for the RNNoise tuning preset setting",
  );

  String get labelVoipNoiseSuppressionPresetDescription => Intl.message(
    "Gentle keeps the current fallback behavior, Balanced is the default, and Strong mutes transient noises more aggressively.",
    name: "labelVoipNoiseSuppressionPresetDescription",
    desc: "Description for the RNNoise tuning preset setting",
  );

  String get labelVoipNoiseSuppressionVadThreshold => Intl.message(
    "RNNoise VAD threshold",
    name: "labelVoipNoiseSuppressionVadThreshold",
    desc: "Title for the custom RNNoise VAD threshold slider",
  );

  String get labelVoipNoiseSuppressionVadThresholdDescription => Intl.message(
    "Higher values require stronger speech confidence before the gate opens.",
    name: "labelVoipNoiseSuppressionVadThresholdDescription",
    desc: "Description for the custom RNNoise VAD threshold slider",
  );

  String get labelVoipNoiseSuppressionGrace => Intl.message(
    "RNNoise speech grace",
    name: "labelVoipNoiseSuppressionGrace",
    desc: "Title for the custom RNNoise speech grace slider",
  );

  String get labelVoipNoiseSuppressionGraceDescription => Intl.message(
    "Keeps the gate open briefly after speech so words do not clip.",
    name: "labelVoipNoiseSuppressionGraceDescription",
    desc: "Description for the custom RNNoise speech grace slider",
  );

  String get labelVoipNoiseSuppressionClosedGain => Intl.message(
    "RNNoise closed gain",
    name: "labelVoipNoiseSuppressionClosedGain",
    desc: "Title for the custom RNNoise closed gain slider",
  );

  String get labelVoipNoiseSuppressionClosedGainDescription => Intl.message(
    "Lower values make gated keyboard taps and clicks quieter.",
    name: "labelVoipNoiseSuppressionClosedGainDescription",
    desc: "Description for the custom RNNoise closed gain slider",
  );

  String get labelVoipNoiseSuppressionTransientSensitivity => Intl.message(
    "RNNoise transient sensitivity",
    name: "labelVoipNoiseSuppressionTransientSensitivity",
    desc: "Title for the custom RNNoise transient sensitivity slider",
  );

  String get labelVoipNoiseSuppressionTransientSensitivityDescription =>
      Intl.message(
        "Higher values catch shorter, sharper sounds sooner.",
        name: "labelVoipNoiseSuppressionTransientSensitivityDescription",
        desc: "Description for the custom RNNoise transient sensitivity slider",
      );

  String get labelVoipAudioCaptureFrontend => Intl.message(
    "Audio capture frontend override",
    name: "labelVoipAudioCaptureFrontend",
    desc: "Title for developer WebRTC audio capture override controls",
  );

  String get labelVoipAudioCaptureFrontendDescription => Intl.message(
    "Developer-only: override the WebRTC microphone capture constraints used by calls and the local mic check.",
    name: "labelVoipAudioCaptureFrontendDescription",
    desc: "Description for developer WebRTC audio capture override",
  );

  String get labelVoipAudioCaptureEchoCancellation => Intl.message(
    "WebRTC echo cancellation",
    name: "labelVoipAudioCaptureEchoCancellation",
    desc: "Title for WebRTC echo cancellation developer toggle",
  );

  String get labelVoipAudioCaptureEchoCancellationDescription => Intl.message(
    "Request WebRTC echo cancellation for microphone capture.",
    name: "labelVoipAudioCaptureEchoCancellationDescription",
    desc: "Description for WebRTC echo cancellation developer toggle",
  );

  String get labelVoipAudioCaptureNoiseSuppression => Intl.message(
    "WebRTC noise suppression",
    name: "labelVoipAudioCaptureNoiseSuppression",
    desc: "Title for WebRTC noise suppression developer toggle",
  );

  String get labelVoipAudioCaptureNoiseSuppressionDescription => Intl.message(
    "Request WebRTC noise suppression in addition to the optional RNNoise native hook.",
    name: "labelVoipAudioCaptureNoiseSuppressionDescription",
    desc: "Description for WebRTC noise suppression developer toggle",
  );

  String get labelVoipAudioCaptureAutoGain => Intl.message(
    "WebRTC auto gain",
    name: "labelVoipAudioCaptureAutoGain",
    desc: "Title for WebRTC auto gain developer toggle",
  );

  String get labelVoipAudioCaptureAutoGainDescription => Intl.message(
    "Request WebRTC automatic microphone gain. Leave off unless isolating capture clipping.",
    name: "labelVoipAudioCaptureAutoGainDescription",
    desc: "Description for WebRTC auto gain developer toggle",
  );

  String get labelVoipAudioCaptureHighPass => Intl.message(
    "WebRTC high-pass filter",
    name: "labelVoipAudioCaptureHighPass",
    desc: "Title for WebRTC high-pass developer toggle",
  );

  String get labelVoipAudioCaptureHighPassDescription => Intl.message(
    "Request the WebRTC high-pass filter when the platform honors it.",
    name: "labelVoipAudioCaptureHighPassDescription",
    desc: "Description for WebRTC high-pass developer toggle",
  );

  String get labelVoipAudioCaptureTypingNoise => Intl.message(
    "WebRTC typing noise detection",
    name: "labelVoipAudioCaptureTypingNoise",
    desc: "Title for WebRTC typing noise developer toggle",
  );

  String get labelVoipAudioCaptureTypingNoiseDescription => Intl.message(
    "Request WebRTC typing-noise detection if the Windows capture path supports it.",
    name: "labelVoipAudioCaptureTypingNoiseDescription",
    desc: "Description for WebRTC typing noise developer toggle",
  );

  String get labelVoipAudioCaptureReferenceFormat => Intl.message(
    "Request 48 kHz mono",
    name: "labelVoipAudioCaptureReferenceFormat",
    desc: "Title for RNNoise reference capture format developer toggle",
  );

  String get labelVoipAudioCaptureReferenceFormatDescription => Intl.message(
    "Ask getUserMedia for 48 kHz mono before the RNNoise post-processor. Logs show the actual native callback format separately.",
    name: "labelVoipAudioCaptureReferenceFormatDescription",
    desc: "Description for RNNoise reference capture format toggle",
  );

  String get labelVoipAudioCaptureVolumeConstraint => Intl.message(
    "Send mic volume constraint",
    name: "labelVoipAudioCaptureVolumeConstraint",
    desc: "Title for microphone volume constraint developer toggle",
  );

  String get labelVoipAudioCaptureVolumeConstraintDescription => Intl.message(
    "Include a getUserMedia volume constraint only when microphone volume is below 100%.",
    name: "labelVoipAudioCaptureVolumeConstraintDescription",
    desc: "Description for microphone volume constraint developer toggle",
  );

  String get labelVoipStreamMaximumBitrate => Intl.message(
    "Stream Maximum Bitrate",
    name: "labelVoipStreamMaximumBitrate",
    desc:
        "label for setting slider to set the maximum bitrate that can be used when streaming",
  );

  String get labelVoipStreamMaximumBitrateDescription => Intl.message(
    "Determines the overall quality of your stream. Higher is better, but also uses more resources",
    name: "labelVoipStreamMaximumBitrateDescription",
  );

  String get labelVoipStreamFramerate => Intl.message(
    "Stream Framerate",
    name: "labelVoipStreamFramerate",
    desc:
        "label for setting slider to set the framerate at which the screen should be captured when streaming",
  );

  String get labelVoipStreamFramerateDescription => Intl.message(
    "Target frames per second for screen sharing. Higher has smoother motion, but maybe reduce visual clarity.",
    name: "labelVoipStreamFramerateDescription",
  );

  String get labelVoipStreamPreferredCodec => Intl.message(
    "Preferred Stream Codec",
    name: "labelVoipStreamPreferredCodec",
  );

  String get labelVoipStreamPreferredCodecDescription => Intl.message(
    "Choose which format to encode your stream in. Different codecs may run faster on certain devices, and may be unsupported on others. Most devices should support vp8 and h264.",
    name: "labelVoipStreamPreferredCodecDescription",
    desc:
        "Explains the preferred stream codec setting. This is just a preference, and the picked codec may not be used if the user's device does not support it",
  );

  String get labelVoipStreamResolution =>
      Intl.message("Stream Resolution", name: "labelVoipStreamResolution");

  String get labelVoipStreamResolutionDescription => Intl.message(
    "The resolution of your stream, higher is better",
    name: "labelVoipStreamResolutionDescription",
  );

  @override
  void initState() {
    super.initState();
    sub = preferences.onSettingChanged.listen((event) {
      if (!preferences.developerMode.value) {
        if (preferences.streamAdvancedOverride.value) {
          unawaited(preferences.streamAdvancedOverride.set(false));
        }
        if (preferences.streamGpuPipelineTestMode.value) {
          unawaited(preferences.streamGpuPipelineTestMode.set(false));
        }
        if (preferences.streamAdaptiveFallbackEnabled.value) {
          unawaited(preferences.streamAdaptiveFallbackEnabled.set(false));
        }
        if (preferences.voipAudioCaptureDebugOverride.value ||
            preferences.voipAudioCaptureTapOrderScenario.value !=
                NoiseSuppressionTapOrderScenario.manual ||
            preferences.voipNoiseSuppressionHookMode.value !=
                NoiseSuppressionService.diagnosticEnhancedBackendModeKey) {
          unawaited(_resetHiddenDeveloperNoiseSuppressionDiagnostics());
        }
        if (preferences.voipNoiseSuppressionPreset.value ==
            NoiseSuppressionTuningProfile.customKey) {
          unawaited(_resetHiddenCustomNoiseSuppressionPreset());
        }
      }
      if (mounted) {
        setState(() {});
      }
    });
    noiseSuppressionStatusSub = NoiseSuppressionService.instance.onStatusChanged
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
        });
    unawaited(_refreshEnhancedBackendStatus());

    webrtc.navigator.mediaDevices.enumerateDevices().then((v) {
      if (!mounted) {
        return;
      }

      setState(() {
        Log.i(v);
        devices = v;

        microphones = v.where((i) => i.kind == "audioinput").toList();
        speakers = v.where((i) => i.kind == "audiooutput").toList();
        cameras = v.where((i) => i.kind == "videoinput").toList();
      });
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    noiseSuppressionStatusSub?.cancel();
    _disposeMicCheck();
    _disposeCameraTest();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsSection(
          title: headerVoipSettingsVoice,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                voiceControls(),
                if (PlatformUtils.isWindows) micCheckPanel(),
                BooleanPreferenceToggle(
                  preference: preferences.voipPushToTalkEnabled,
                  title: labelVoipPushToTalk,
                  description: labelVoipPushToTalkDescription,
                  onChanged: (_) {
                    clientManager?.callManager.applyPushToTalkPreference();
                  },
                ),
              ],
            ),
          ],
        ),
        SettingsSection(
          title: headerVoipSettingsVideo,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [cameraControls(), cameraTestPanel()],
            ),
          ],
        ),
        SettingsSection(
          title: headerVoipSettingsStreamSettings,
          showDivider: false,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                StringPreferenceOptionsPicker(
                  preference: preferences.screenShareQualityProfile,
                  title: labelVoipScreenShareQuality,
                  description: labelVoipScreenShareQualityDescription,
                  options: ScreenShareQualityProfile.values
                      .map((profile) => profile.storageKey)
                      .toList(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
                  child: tiamat.Text.labelLow(
                    ScreenShareProfileConfig.forPreferenceKey(
                      preferences.screenShareQualityProfile.value,
                      preferHardwareEncoding:
                          PlatformUtils.isWindows &&
                          preferences.streamHardwareEncodingFirst.value,
                    ).description,
                  ),
                ),
                if (supportsNativeRnnoise)
                  BooleanPreferenceToggle(
                    preference: preferences.voipNoiseSuppressionEnabled,
                    title: labelVoipNoiseSuppression,
                    description: labelVoipNoiseSuppressionDescription,
                    onChanged: (value) async {
                      await _applyNoiseSuppressionSettings(
                        enabled: value,
                        refreshMicCheckCapture: true,
                      );
                    },
                  ),
                if (supportsNativeRnnoise &&
                    preferences.voipNoiseSuppressionEnabled.value)
                  BooleanPreferenceToggle(
                    preference:
                        preferences.voipNoiseSuppressionCompatibilityMode,
                    title: labelVoipNoiseSuppressionCompatibilityMode,
                    description:
                        labelVoipNoiseSuppressionCompatibilityModeDescription,
                    onChanged: (_) async {
                      await _applyNoiseSuppressionSettings(
                        refreshMicCheckCapture: true,
                      );
                    },
                  ),
                if (supportsNativeRnnoise)
                  StringPreferenceOptionsPicker(
                    preference: preferences.voipNoiseSuppressionPreset,
                    title: labelVoipNoiseSuppressionPreset,
                    description: labelVoipNoiseSuppressionPresetDescription,
                    options: userNoiseSuppressionPresetOptions,
                    onChanged: (preset) {
                      unawaited(
                        _applyNoiseSuppressionSettings(presetKey: preset),
                      );
                    },
                  ),
                if (supportsNativeRnnoise &&
                    preferences.voipNoiseSuppressionEnabled.value &&
                    !NoiseSuppressionService.instance.isAvailable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    child: tiamat.Text.labelLow(
                      labelVoipNoiseSuppressionFallbackNotice,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  List<String> get userNoiseSuppressionPresetOptions {
    final options = NoiseSuppressionTuningProfile.presetKeys
        .where((preset) => preset != NoiseSuppressionTuningProfile.customKey)
        .toList();
    if (preferences.voipNoiseSuppressionPreset.value ==
        NoiseSuppressionTuningProfile.customKey) {
      options.add(NoiseSuppressionTuningProfile.customKey);
    }
    return options;
  }

  Widget noiseSuppressionDiagnostics() {
    final lines = NoiseSuppressionService.instance.diagnosticsLines(
      header: labelVoipNoiseSuppressionDiagnostics,
    );

    return _VoipDeveloperStatusCard(
      icon: Icons.analytics_outlined,
      title: lines.firstOrNull ?? labelVoipNoiseSuppressionDiagnostics,
      body: lines.skip(1).join('\n'),
    );
  }

  Widget enhancedBackendStatus() {
    final status = NoiseSuppressionService.instance.enhancedBackendStatus;
    return _VoipDeveloperStatusCard(
      icon: Icons.graphic_eq_outlined,
      title: 'Enhanced DeepFilterNet',
      body: status.diagnosticsLines.join('\n'),
    );
  }

  Widget noiseSuppressionDiagnosticCaptureControls() {
    final status = NoiseSuppressionService.instance.status;
    final running = status.diagnosticCaptureActive;
    final path =
        NoiseSuppressionService.instance.diagnosticCaptureDirectoryPath;
    final body = <String>[
      labelVoipNoiseSuppressionWavCaptureDescription,
      if (path != null) 'Last folder: $path',
      if (rnnoiseDiagnosticCaptureMessage != null)
        rnnoiseDiagnosticCaptureMessage!,
    ].join('\n');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            children: [
              SizedBox(
                width: 180,
                child: tiamat.Button.secondary(
                  text: running
                      ? labelVoipNoiseSuppressionStopWavCapture
                      : labelVoipNoiseSuppressionStartWavCapture,
                  isLoading: rnnoiseDiagnosticCaptureBusy,
                  onTap: rnnoiseDiagnosticCaptureBusy
                      ? null
                      : () {
                          if (running) {
                            unawaited(_stopNoiseSuppressionDiagnosticCapture());
                          } else {
                            unawaited(
                              _startNoiseSuppressionDiagnosticCapture(),
                            );
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: tiamat.Text.labelLow(
                  running
                      ? 'Capturing local audio pipeline stage WAVs.'
                      : path == null
                      ? 'Creates local WAV files after you start capture.'
                      : 'Latest WAV set is saved locally for developer review.',
                ),
              ),
            ],
          ),
          tiamat.Text.labelLow(body),
        ],
      ),
    );
  }

  Widget audioCaptureFrontendControls() {
    final overrideActive = preferences.voipAudioCaptureDebugOverride.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          BooleanPreferenceToggle(
            preference: preferences.voipAudioCaptureDebugOverride,
            title: labelVoipAudioCaptureFrontend,
            description: labelVoipAudioCaptureFrontendDescription,
            onChanged: _onAudioCaptureFrontendChanged,
          ),
          if (overrideActive) ...[
            BooleanPreferenceToggle(
              preference: preferences.voipAudioCaptureEchoCancellation,
              title: labelVoipAudioCaptureEchoCancellation,
              description: labelVoipAudioCaptureEchoCancellationDescription,
              onChanged: _onAudioCaptureFrontendChanged,
            ),
            BooleanPreferenceToggle(
              preference: preferences.voipAudioCaptureNoiseSuppression,
              title: labelVoipAudioCaptureNoiseSuppression,
              description: labelVoipAudioCaptureNoiseSuppressionDescription,
              onChanged: _onAudioCaptureFrontendChanged,
            ),
            BooleanPreferenceToggle(
              preference: preferences.voipAudioCaptureAutoGainControl,
              title: labelVoipAudioCaptureAutoGain,
              description: labelVoipAudioCaptureAutoGainDescription,
              onChanged: _onAudioCaptureFrontendChanged,
            ),
            BooleanPreferenceToggle(
              preference: preferences.voipAudioCaptureHighPassFilter,
              title: labelVoipAudioCaptureHighPass,
              description: labelVoipAudioCaptureHighPassDescription,
              onChanged: _onAudioCaptureFrontendChanged,
            ),
            BooleanPreferenceToggle(
              preference: preferences.voipAudioCaptureTypingNoiseDetection,
              title: labelVoipAudioCaptureTypingNoise,
              description: labelVoipAudioCaptureTypingNoiseDescription,
              onChanged: _onAudioCaptureFrontendChanged,
            ),
            BooleanPreferenceToggle(
              preference: preferences.voipAudioCaptureRequestReferenceFormat,
              title: labelVoipAudioCaptureReferenceFormat,
              description: labelVoipAudioCaptureReferenceFormatDescription,
              onChanged: _onAudioCaptureFrontendChanged,
            ),
            BooleanPreferenceToggle(
              preference: preferences.voipAudioCaptureVolumeConstraint,
              title: labelVoipAudioCaptureVolumeConstraint,
              description: labelVoipAudioCaptureVolumeConstraintDescription,
              onChanged: _onAudioCaptureFrontendChanged,
            ),
            tiamat.Text.labelLow(
              NoiseSuppressionCaptureProfile.captureFrontendSummary(),
            ),
          ],
        ],
      ),
    );
  }

  Widget activeStreamOverrideSummary() {
    final profile = ScreenShareProfileConfig.resolve(
      profileKey: preferences.screenShareQualityProfile.value,
      advancedOverrideEnabled: true,
      allowSimulcast: preferences.doSimulcast.value,
      advancedBitrateMbps: preferences.streamBitrate.value,
      advancedFramerate: preferences.streamFramerate.value,
      advancedCodec: preferences.streamCodec.value,
      advancedResolution: preferences.streamResolution.value,
      preferHardwareEncoding:
          PlatformUtils.isWindows &&
          preferences.streamHardwareEncodingFirst.value,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: tiamat.Text.labelLow(
        'Active stream override: ${profile.description} '
        'Simulcast ${profile.useSimulcast ? 'on' : 'off'}.',
      ),
    );
  }

  Widget audioProcessingStatus() {
    final status = NoiseSuppressionCaptureProfile.audioProcessingStatus().lines;
    return _VoipDeveloperStatusCard(
      icon: Icons.graphic_eq_rounded,
      title: 'Audio processing',
      body: status.join('\n'),
    );
  }

  Widget micCheckPanel() {
    final running = micCheckStream != null;
    final level = micCheckLevel.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: tiamat.Button(
                  text: running ? labelVoipStopMicTest : labelVoipMicTest,
                  isLoading: micCheckStarting,
                  onTap: micCheckStarting
                      ? null
                      : () {
                          if (running) {
                            unawaited(_stopMicCheck());
                          } else {
                            unawaited(_startMicCheck());
                          }
                        },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _AudioLevelMeter(level: running ? level : 0)),
            ],
          ),
          tiamat.Text.labelLow(
            running
                ? 'Input level ${(level * 100).round()}%'
                : 'Uses ${NoiseSuppressionCaptureProfile.localProcessedCaptureLabel.toLowerCase()} with your microphone volume.',
          ),
          if (micCheckError != null)
            tiamat.Text.labelLow('Mic check error: $micCheckError'),
        ],
      ),
    );
  }

  Future<void> _startMicCheck() async {
    if (micCheckStarting || micCheckStream != null) {
      return;
    }

    setState(() {
      micCheckStarting = true;
      micCheckError = null;
      micCheckLevel = 0;
    });

    webrtc.MediaStream? stream;
    webrtc.RTCPeerConnection? peerConnection;
    try {
      final deviceId = await WebrtcDefaultDevices.getDefaultMicrophoneId();
      stream = await webrtc.navigator.mediaDevices.getUserMedia(
        NoiseSuppressionCaptureProfile.buildLocalProcessedMediaConstraints(
          deviceId: deviceId,
          inputVolume: _normalizedMicrophoneVolume(),
        ),
      );
      final audioTrack = stream.getAudioTracks().firstOrNull;
      peerConnection = await webrtc.createPeerConnection(<String, dynamic>{
        'iceServers': <Map<String, dynamic>>[],
      });
      final sender = audioTrack == null
          ? null
          : await peerConnection.addTrack(audioTrack, stream);

      if (!mounted) {
        await _disposeMicCheckResources(
          stream: stream,
          peerConnection: peerConnection,
        );
        return;
      }

      setState(() {
        micCheckStream = stream;
        micCheckPeerConnection = peerConnection;
        micCheckSender = sender;
        micCheckStarting = false;
      });
      NoiseSuppressionService.instance.scheduleHealthRefresh();
      micCheckLevelTimer?.cancel();
      micCheckLevelTimer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => unawaited(_pollMicCheckLevel()),
      );
      await _pollMicCheckLevel();
    } catch (error, stackTrace) {
      await _disposeMicCheckResources(
        stream: stream,
        peerConnection: peerConnection,
      );
      Log.onError(error, stackTrace, content: 'Failed to start mic check');
      if (!mounted) {
        return;
      }
      setState(() {
        micCheckStarting = false;
        micCheckError = error.toString();
      });
    }
  }

  Future<void> _pollMicCheckLevel() async {
    if (micCheckStatsPolling) {
      return;
    }

    final sender = micCheckSender;
    if (sender == null) {
      return;
    }

    micCheckStatsPolling = true;
    try {
      final reports = await sender.getStats();
      final level = _audioLevelFromStats(reports);
      if (!mounted || level == null) {
        return;
      }
      setState(() {
        micCheckLevel = level;
      });
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: 'Failed to poll mic check level');
    } finally {
      micCheckStatsPolling = false;
    }
  }

  double? _audioLevelFromStats(Iterable<dynamic> reports) {
    for (final report in reports) {
      final values = report.values;
      if (values is! Map) {
        continue;
      }
      final level = values['audioLevel'];
      if (level is num) {
        return level.toDouble().clamp(0.0, 1.0).toDouble();
      }
    }

    return null;
  }

  Future<void> _stopMicCheck() async {
    await _disposeMicCheckResources(
      stream: micCheckStream,
      peerConnection: micCheckPeerConnection,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      micCheckStream = null;
      micCheckPeerConnection = null;
      micCheckSender = null;
      micCheckStarting = false;
      micCheckLevel = 0;
    });
  }

  void _disposeMicCheck() {
    final stream = micCheckStream;
    final peerConnection = micCheckPeerConnection;
    micCheckStream = null;
    micCheckPeerConnection = null;
    micCheckSender = null;
    micCheckLevelTimer?.cancel();
    micCheckLevelTimer = null;
    for (final track
        in stream?.getTracks() ?? const <webrtc.MediaStreamTrack>[]) {
      unawaited(track.stop());
    }
    unawaited(peerConnection?.close());
    unawaited(peerConnection?.dispose());
    unawaited(stream?.dispose());
  }

  Future<void> _disposeMicCheckResources({
    webrtc.MediaStream? stream,
    webrtc.RTCPeerConnection? peerConnection,
  }) async {
    micCheckLevelTimer?.cancel();
    micCheckLevelTimer = null;
    for (final track
        in stream?.getTracks() ?? const <webrtc.MediaStreamTrack>[]) {
      await track.stop();
    }
    await peerConnection?.close();
    await peerConnection?.dispose();
    await stream?.dispose();
  }

  NoiseSuppressionTuningProfile _noiseSuppressionTuningProfile({
    String? presetKey,
    double? customVadThreshold,
    double? customSpeechGraceMs,
    double? customClosedGainPercent,
    double? customTransientSensitivityPercent,
  }) {
    return NoiseSuppressionTuningProfile.fromPreferenceValues(
      presetKey: presetKey ?? preferences.voipNoiseSuppressionPreset.value,
      customVadThreshold:
          customVadThreshold ??
          preferences.voipNoiseSuppressionVadThreshold.value,
      customSpeechGraceMs:
          customSpeechGraceMs ??
          preferences.voipNoiseSuppressionSpeechGraceMs.value,
      customClosedGainPercent:
          customClosedGainPercent ??
          preferences.voipNoiseSuppressionClosedGainPercent.value,
      customTransientSensitivityPercent:
          customTransientSensitivityPercent ??
          preferences.voipNoiseSuppressionTransientSensitivity.value,
    );
  }

  Future<void> _applyNoiseSuppressionSettings({
    bool? enabled,
    String? presetKey,
    double? customVadThreshold,
    double? customSpeechGraceMs,
    double? customClosedGainPercent,
    double? customTransientSensitivityPercent,
    bool refreshMicCheckCapture = false,
  }) async {
    final effectiveEnabled =
        enabled ?? preferences.voipNoiseSuppressionEnabled.value;
    await NoiseSuppressionService.instance.applyPreference(
      effectiveEnabled,
      tuningProfile: _noiseSuppressionTuningProfile(
        presetKey: presetKey,
        customVadThreshold: customVadThreshold,
        customSpeechGraceMs: customSpeechGraceMs,
        customClosedGainPercent: customClosedGainPercent,
        customTransientSensitivityPercent: customTransientSensitivityPercent,
      ),
    );
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _developerHookPipelineMode(),
    );
    if (effectiveEnabled) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
    if (refreshMicCheckCapture && micCheckStream != null) {
      await _stopMicCheck();
      await _startMicCheck();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startNoiseSuppressionDiagnosticCapture() async {
    if (rnnoiseDiagnosticCaptureBusy) {
      return;
    }

    setState(() {
      rnnoiseDiagnosticCaptureBusy = true;
      rnnoiseDiagnosticCaptureMessage = null;
    });

    try {
      await NoiseSuppressionService.instance.applyDiagnosticHookMode(
        _developerHookPipelineMode(),
      );
      final includeWasapiSidecar = PlatformUtils.isWindows;
      final microphoneId = includeWasapiSidecar
          ? await WebrtcDefaultDevices.getDefaultMicrophoneId()
          : null;
      final directoryPath = await createNoiseSuppressionDiagnosticDirectory(
        captureLabel: 'voip-settings',
        stageMask: NoiseSuppressionDiagnosticStageMask.all,
        includeWasapiSidecar: includeWasapiSidecar,
      );
      final result = await NoiseSuppressionService.instance
          .startDiagnosticCapture(
            directoryPath: directoryPath,
            duration: const Duration(seconds: 10),
            stageMask: NoiseSuppressionDiagnosticStageMask.all,
            includeWasapiSidecar: includeWasapiSidecar,
            wasapiDeviceId: microphoneId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        rnnoiseDiagnosticCaptureBusy = false;
        rnnoiseDiagnosticCaptureMessage = result.status.diagnosticCaptureActive
            ? includeWasapiSidecar
                  ? 'Capturing 10 seconds. Stop capture to write pipeline-stage and WASAPI WAV files.'
                  : 'Capturing 10 seconds. Stop capture to write audio pipeline stage WAV files.'
            : 'Could not start capture: ${result.status.reason}.';
      });
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to start audio pipeline diagnostic capture',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        rnnoiseDiagnosticCaptureBusy = false;
        rnnoiseDiagnosticCaptureMessage = 'Capture start failed: $error';
      });
    }
  }

  Future<void> _stopNoiseSuppressionDiagnosticCapture() async {
    if (rnnoiseDiagnosticCaptureBusy) {
      return;
    }

    setState(() {
      rnnoiseDiagnosticCaptureBusy = true;
    });

    try {
      final status = await NoiseSuppressionService.instance
          .stopDiagnosticCapture();
      final path =
          NoiseSuppressionService.instance.diagnosticCaptureDirectoryPath;
      NoiseSuppressionDiagnosticReportBundle? reportBundle;
      if (path != null) {
        reportBundle = await collectNoiseSuppressionDiagnosticReportBundle(
          directoryPath: path,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        rnnoiseDiagnosticCaptureBusy = false;
        rnnoiseDiagnosticCaptureMessage =
            status.diagnosticCaptureWrittenFiles > 0
            ? 'Wrote ${status.diagnosticCaptureWrittenFiles} WAV files. '
                  '${reportBundle?.userMessage ?? 'WAV bug-report upload is disabled; captures stay local.'}'
            : 'No WAV files were written: ${status.diagnosticCaptureLastError.isEmpty ? status.reason : status.diagnosticCaptureLastError}.';
      });
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to stop audio pipeline diagnostic capture',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        rnnoiseDiagnosticCaptureBusy = false;
        rnnoiseDiagnosticCaptureMessage = 'Capture stop failed: $error';
      });
    }
  }

  Future<void> _resetHiddenCustomNoiseSuppressionPreset() async {
    const defaultPresetKey = NoiseSuppressionTuningProfile.defaultPresetKey;
    await preferences.voipNoiseSuppressionPreset.set(defaultPresetKey);
    await _applyNoiseSuppressionSettings(presetKey: defaultPresetKey);
  }

  Future<void> _resetHiddenDeveloperNoiseSuppressionDiagnostics() async {
    if (preferences.voipAudioCaptureDebugOverride.value) {
      await preferences.voipAudioCaptureDebugOverride.set(false);
    }
    if (preferences.voipAudioCaptureTapOrderScenario.value !=
        NoiseSuppressionTapOrderScenario.manual) {
      await preferences.voipAudioCaptureTapOrderScenario.set(
        NoiseSuppressionTapOrderScenario.manual,
      );
    }
    if (preferences.voipNoiseSuppressionHookMode.value !=
        NoiseSuppressionService.diagnosticEnhancedBackendModeKey) {
      await preferences.voipNoiseSuppressionHookMode.set(
        NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
      );
    }
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(null);
  }

  Widget voiceControls() {
    final showMicrophone = microphones != null && !PlatformUtils.isAndroid;
    final showSpeaker = speakers != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = <Widget>[
            if (showMicrophone)
              _VoiceDeviceColumn(
                picker: buildCompactPicker(
                  labelVoipDefaultAudioInput,
                  preferences.voipDefaultAudioInput.value,
                  microphones!,
                  onSelected: _selectMicrophone,
                ),
                slider: _VolumePreferenceSlider(
                  title: labelVoipMicrophoneVolume,
                  value: preferences.voipMicrophoneVolume.value,
                  onSettled: _setMicrophoneVolume,
                ),
              ),
            if (showSpeaker)
              _VoiceDeviceColumn(
                picker: buildCompactPicker(
                  labelVoipDefaultAudioOutput,
                  preferences.voipDefaultAudioOutput.value,
                  speakers!,
                  onSelected: _selectSpeaker,
                ),
                slider: _VolumePreferenceSlider(
                  title: labelVoipSpeakerVolume,
                  value: preferences.voipSpeakerVolume.value,
                  max: Preferences.maxVoipSpeakerVolume,
                  onSettled: _setSpeakerVolume,
                ),
              ),
          ];

          if (columns.isEmpty) {
            return tiamat.Text.labelLow('No voice devices found.');
          }

          if (constraints.maxWidth < 720 || columns.length == 1) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 18,
              children: columns,
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: columns[0]),
              const SizedBox(width: 24),
              Expanded(child: columns[1]),
            ],
          );
        },
      ),
    );
  }

  Widget cameraControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: buildCompactPicker(
        labelVoipDefaultVideoInput,
        preferences.voipDefaultVideoInput.value,
        cameras ?? const <webrtc.MediaDeviceInfo>[],
        onSelected: _selectCamera,
      ),
    );
  }

  Widget cameraTestPanel() {
    final running = cameraTestStream != null && cameraTestRenderer != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            children: [
              SizedBox(
                width: 140,
                child: tiamat.Button.secondary(
                  text: running ? labelVoipStopCameraTest : labelVoipCameraTest,
                  isLoading: cameraTestStarting,
                  onTap: cameraTestStarting
                      ? null
                      : () {
                          if (running) {
                            unawaited(_stopCameraTest());
                          } else {
                            unawaited(_startCameraTest());
                          }
                        },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: tiamat.Text.labelLow(
                  running
                      ? 'Showing your selected camera locally.'
                      : 'Preview your selected camera before joining a call.',
                ),
              ),
            ],
          ),
          if (running)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: webrtc.RTCVideoView(
                    cameraTestRenderer!,
                    mirror: true,
                    objectFit:
                        webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
          if (cameraTestError != null)
            tiamat.Text.labelLow('Camera test error: $cameraTestError'),
        ],
      ),
    );
  }

  Future<void> _startCameraTest() async {
    if (cameraTestStarting || cameraTestStream != null) {
      return;
    }

    setState(() {
      cameraTestStarting = true;
      cameraTestError = null;
    });

    webrtc.MediaStream? stream;
    webrtc.RTCVideoRenderer? renderer;
    try {
      final camera = await WebrtcDefaultDevices.getDefaultCamera();
      final videoConstraints = camera == null
          ? true
          : <String, dynamic>{
              'deviceId': {'exact': camera.deviceId},
            };

      stream = await webrtc.navigator.mediaDevices.getUserMedia(
        <String, dynamic>{'audio': false, 'video': videoConstraints},
      );
      renderer = webrtc.RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;

      if (!mounted) {
        await _disposeCameraTestResources(stream: stream, renderer: renderer);
        return;
      }

      setState(() {
        cameraTestStream = stream;
        cameraTestRenderer = renderer;
        cameraTestStarting = false;
      });
    } catch (error, stackTrace) {
      await _disposeCameraTestResources(stream: stream, renderer: renderer);
      Log.onError(error, stackTrace, content: 'Failed to start camera test');
      if (!mounted) {
        return;
      }
      setState(() {
        cameraTestStarting = false;
        cameraTestError = error.toString();
      });
    }
  }

  Future<void> _stopCameraTest() async {
    await _disposeCameraTestResources(
      stream: cameraTestStream,
      renderer: cameraTestRenderer,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      cameraTestStream = null;
      cameraTestRenderer = null;
      cameraTestStarting = false;
    });
  }

  void _disposeCameraTest() {
    final stream = cameraTestStream;
    final renderer = cameraTestRenderer;
    cameraTestStream = null;
    cameraTestRenderer = null;
    for (final track
        in stream?.getTracks() ?? const <webrtc.MediaStreamTrack>[]) {
      unawaited(track.stop());
    }
    renderer?.srcObject = null;
    unawaited(renderer?.dispose());
    unawaited(stream?.dispose());
  }

  Future<void> _disposeCameraTestResources({
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

  Future<void> _selectMicrophone(webrtc.MediaDeviceInfo? device) async {
    final previousDeviceId = preferences.voipDefaultAudioInput.value;
    await preferences.voipDefaultAudioInput.set(device?.deviceId);
    try {
      await WebrtcDefaultDevices.selectInputDevice();
    } catch (error, stackTrace) {
      await preferences.voipDefaultAudioInput.set(previousDeviceId);
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to switch default audio input',
      );
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _selectSpeaker(webrtc.MediaDeviceInfo? device) async {
    final previousDeviceId = preferences.voipDefaultAudioOutput.value;
    await preferences.voipDefaultAudioOutput.set(device?.deviceId);
    try {
      await WebrtcDefaultDevices.selectOutputDevice();
    } catch (error, stackTrace) {
      await preferences.voipDefaultAudioOutput.set(previousDeviceId);
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to switch default audio output',
      );
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _selectCamera(webrtc.MediaDeviceInfo? device) async {
    await preferences.voipDefaultVideoInput.set(device?.deviceId);
    if (cameraTestStream != null) {
      await _stopCameraTest();
      await _startCameraTest();
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setMicrophoneVolume(double value) async {
    await preferences.voipMicrophoneVolume.set(value);
    await NoiseSuppressionService.instance.refresh();
    if (micCheckStream != null) {
      await _stopMicCheck();
      await _startMicCheck();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setSpeakerVolume(double value) async {
    await preferences.voipSpeakerVolume.set(value);
    final callManager = clientManager?.callManager;
    if (callManager != null) {
      unawaited(callManager.applySpeakerVolumePreference());
    }
    if (mounted) {
      setState(() {});
    }
  }

  double _normalizedMicrophoneVolume() {
    return NoiseSuppressionCaptureProfile.normalizedMicrophoneVolumePreference(
      preferences.voipMicrophoneVolume.value,
    );
  }

  Future<void> _onAudioCaptureFrontendChanged(bool _) async {
    await NoiseSuppressionService.instance.refresh();
    if (micCheckStream != null) {
      await _stopMicCheck();
      await _startMicCheck();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onNoiseSuppressionHookModeChanged(String mode) async {
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _developerHookPipelineModeForPreference(mode),
    );
    await _refreshEnhancedBackendStatus();
  }

  Future<void> _refreshEnhancedBackendStatus() async {
    await NoiseSuppressionService.instance.refreshEnhancedBackendStatus();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onAudioCaptureTapOrderScenarioChanged(
    String scenarioKey,
  ) async {
    final scenario = NoiseSuppressionTapOrderScenario.fromKey(scenarioKey);
    final hookMode = _hookModePreferenceForTapOrderScenario(scenario);
    if (hookMode != null) {
      await preferences.voipNoiseSuppressionHookMode.set(hookMode);
    }
    final enabled = _noiseSuppressionEnabledForTapOrderScenario(scenario);
    if (enabled != null) {
      await preferences.voipNoiseSuppressionEnabled.set(enabled);
      await _applyNoiseSuppressionSettings(enabled: enabled);
    } else {
      await NoiseSuppressionService.instance.applyDiagnosticHookMode(
        _developerHookPipelineMode(),
      );
    }
    await _onAudioCaptureFrontendChanged(true);
  }

  NoiseSuppressionPipelineMode? _developerHookPipelineMode() {
    if (!preferences.developerMode.value) {
      return null;
    }
    return _developerHookPipelineModeForPreference(
      preferences.voipNoiseSuppressionHookMode.value,
    );
  }

  NoiseSuppressionPipelineMode? _developerHookPipelineModeForPreference(
    String hookMode,
  ) {
    if (!supportsNativeRnnoise) {
      return null;
    }
    return switch (hookMode) {
      'identity' => NoiseSuppressionPipelineMode.identity,
      'off' => NoiseSuppressionPipelineMode.off,
      NoiseSuppressionService.diagnosticEnhancedBackendModeKey =>
        NoiseSuppressionPipelineMode.deepFilterNet,
      _ => null,
    };
  }

  String? _hookModePreferenceForTapOrderScenario(String scenario) {
    return switch (scenario) {
      NoiseSuppressionTapOrderScenario.rnnoiseOffDefault => 'identity',
      NoiseSuppressionTapOrderScenario.identitySameConstraints => 'identity',
      NoiseSuppressionTapOrderScenario.rnnoiseSameConstraints ||
      NoiseSuppressionTapOrderScenario.rnnoiseNoVolume ||
      NoiseSuppressionTapOrderScenario.rnnoiseNo48k ||
      NoiseSuppressionTapOrderScenario.rnnoiseAgcOn ||
      NoiseSuppressionTapOrderScenario.rnnoiseAgcOff ||
      NoiseSuppressionTapOrderScenario.rnnoiseNsOff ||
      NoiseSuppressionTapOrderScenario.rnnoiseAecOff ||
      NoiseSuppressionTapOrderScenario.rnnoiseMinimalFrontend => 'rnnoise',
      NoiseSuppressionTapOrderScenario.identityMinimalFrontend => 'identity',
      _ => null,
    };
  }

  bool? _noiseSuppressionEnabledForTapOrderScenario(String scenario) {
    return switch (scenario) {
      NoiseSuppressionTapOrderScenario.rnnoiseOffDefault => false,
      NoiseSuppressionTapOrderScenario.identitySameConstraints ||
      NoiseSuppressionTapOrderScenario.rnnoiseSameConstraints ||
      NoiseSuppressionTapOrderScenario.rnnoiseNoVolume ||
      NoiseSuppressionTapOrderScenario.rnnoiseNo48k ||
      NoiseSuppressionTapOrderScenario.rnnoiseAgcOn ||
      NoiseSuppressionTapOrderScenario.rnnoiseAgcOff ||
      NoiseSuppressionTapOrderScenario.rnnoiseNsOff ||
      NoiseSuppressionTapOrderScenario.rnnoiseAecOff ||
      NoiseSuppressionTapOrderScenario.identityMinimalFrontend ||
      NoiseSuppressionTapOrderScenario.rnnoiseMinimalFrontend => true,
      _ => null,
    };
  }

  String _noiseSuppressionHookModeLabel(String option) {
    return switch (option) {
      NoiseSuppressionService.diagnosticEnhancedBackendModeKey =>
        'Enhanced DeepFilterNet',
      'identity' => 'Identity',
      'off' => 'Off',
      _ => 'RNNoise',
    };
  }

  Widget buildCompactPicker(
    String label,
    String? selected,
    List<webrtc.MediaDeviceInfo> devices, {
    Function(webrtc.MediaDeviceInfo? device)? onSelected,
  }) {
    final selectedDevice = devices.firstWhereOrNull(
      (i) => i.deviceId == selected || i.label == selected,
    );
    final items = <webrtc.MediaDeviceInfo?>[null, ...devices];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        tiamat.DropdownSelector<webrtc.MediaDeviceInfo?>(
          color: ColorScheme.of(context).surfaceContainer,
          items: items,
          onItemSelected: onSelected,
          itemBuilder: (item) {
            if (item == null) {
              return tiamat.Text.labelLow("No Default Selected");
            } else {
              return tiamat.Text(item.label);
            }
          },
          value: selectedDevice,
        ),
      ],
    );
  }
}
