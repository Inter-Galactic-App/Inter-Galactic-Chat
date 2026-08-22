import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/stream_live_tuning_harness_base.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';

class StreamLiveTuningHarness {
  StreamLiveTuningHarness._();

  static final instance = StreamLiveTuningHarness._();

  bool get isSupported => false;

  Future<StreamLiveTuningConfig> readConfig() async {
    return StreamLiveTuningConfig.disabled();
  }

  Future<void> writeStatus({
    required StreamLiveTuningConfig config,
    required bool activeScreenShare,
    required List<String> applicationNotes,
    ScreenShareProfileConfig? activeProfile,
    String? windowsCaptureBackendLabel,
  }) async {}

  Future<void> appendSnapshot({
    required StreamLiveTuningConfig config,
    required VoipCallDiagnosticsSnapshot snapshot,
    required ScreenShareProfileConfig activeProfile,
    required bool activeScreenShare,
    required String windowsCaptureBackendLabel,
    required List<String> applicationNotes,
    String? nativeDiagnosticLogText,
  }) async {}
}
