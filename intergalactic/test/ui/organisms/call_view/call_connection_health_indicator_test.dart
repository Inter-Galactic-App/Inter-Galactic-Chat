import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_health.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_connection_health_indicator.dart';

void main() {
  testWidgets('shows collapsed call health label and expands details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: CallConnectionHealthIndicator(
              developerMode: false,
              snapshot: CallHealthSnapshot.derive(
                collectedAt: DateTime.utc(2026, 7, 3),
                lifecycle: CallConnectionLifecycle.connected,
                participants: const [
                  CallHealthParticipantSnapshot(
                    sanitizedId: 'local',
                    label: 'You',
                    isLocal: true,
                    connectionQuality: CallConnectionQuality.excellent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Strong connection'), findsOneWidget);
    expect(find.text('Your connection'), findsNothing);

    await tester.tap(find.text('Strong connection'));
    await tester.pump();

    expect(find.text('Your connection'), findsOneWidget);
    expect(find.text('Excellent connection'), findsOneWidget);
    expect(find.text('Issue codes'), findsNothing);
  });

  testWidgets('shows issue codes only in developer mode', (tester) async {
    final snapshot = CallHealthSnapshot.derive(
      collectedAt: DateTime.utc(2026, 7, 3),
      lifecycle: CallConnectionLifecycle.connected,
      participants: const [
        CallHealthParticipantSnapshot(
          sanitizedId: 'remote_1',
          label: 'Remote participant 1',
          isLocal: false,
          connectionQuality: CallConnectionQuality.good,
          hasExpectedMicrophoneAudio: true,
          audioPublicationExists: true,
          audioTrackSubscribed: true,
          audioSinkAttached: false,
          remoteAudioReason: 'remote_audio_sink_missing',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: CallConnectionHealthIndicator(
              developerMode: true,
              initiallyExpanded: true,
              snapshot: snapshot,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Audio issue detected'), findsOneWidget);
    expect(find.text('Issue codes'), findsOneWidget);
    expect(find.textContaining('remote_audio_sink_missing'), findsOneWidget);
  });
}
