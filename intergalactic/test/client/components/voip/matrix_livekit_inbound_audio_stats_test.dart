import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';

void main() {
  test('collects inbound audio level, energy, and duration', () {
    final stats = debugLiveKitInboundAudioRtpStatsFromReports([
      const _FakeStatsReport(
        type: 'inbound-rtp',
        values: {
          'kind': 'audio',
          'audioLevel': '0.125',
          'totalAudioEnergy': 4.5,
          'totalSamplesDuration': '18.25',
        },
      ),
    ]);

    expect(stats, isNotNull);
    expect(stats!.audioLevel, 0.125);
    expect(stats.totalAudioEnergy, 4.5);
    expect(stats.totalSamplesDuration, 18.25);
  });

  test('ignores non-audio inbound stats', () {
    final stats = debugLiveKitInboundAudioRtpStatsFromReports([
      const _FakeStatsReport(
        type: 'inbound-rtp',
        values: {'kind': 'video', 'audioLevel': 0.8},
      ),
    ]);

    expect(stats, isNull);
  });
}

class _FakeStatsReport {
  const _FakeStatsReport({required this.type, required this.values});

  final String type;
  final Map<dynamic, dynamic> values;
}
