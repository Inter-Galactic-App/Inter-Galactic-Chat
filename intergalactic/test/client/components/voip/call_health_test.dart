import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/call_health.dart';

void main() {
  group('CallConnectionQualityLabels', () {
    test('maps connection quality to signal bar count', () {
      expect(CallConnectionQuality.excellent.signalStrengthBars, 4);
      expect(CallConnectionQuality.good.signalStrengthBars, 3);
      expect(CallConnectionQuality.fair.signalStrengthBars, 2);
      expect(CallConnectionQuality.poor.signalStrengthBars, 1);
      expect(CallConnectionQuality.lost.signalStrengthBars, 0);
      expect(CallConnectionQuality.unknown.signalStrengthBars, 0);
    });
  });

  group('CallHealthSnapshot', () {
    test('reports good when a connected call has no issues', () {
      final snapshot = CallHealthSnapshot.derive(
        collectedAt: DateTime.utc(2026, 7, 3),
        lifecycle: CallConnectionLifecycle.connected,
        participants: const [
          CallHealthParticipantSnapshot(
            sanitizedId: 'local',
            label: 'You',
            isLocal: true,
            connectionQuality: CallConnectionQuality.excellent,
          ),
          CallHealthParticipantSnapshot(
            sanitizedId: 'remote_1',
            label: 'Remote participant 1',
            isLocal: false,
            connectionQuality: CallConnectionQuality.good,
            hasExpectedMicrophoneAudio: true,
            audioPublicationExists: true,
            audioTrackSubscribed: true,
            audioSinkAttached: true,
            remoteAudioAudible: true,
            remoteAudioReason: 'audible',
          ),
        ],
      );

      expect(snapshot.state, CallConnectionHealthState.good);
      expect(snapshot.summaryLabel, 'Strong connection');
      expect(snapshot.issueCodes, isEmpty);
    });

    test('reports fair when any participant is slightly unstable', () {
      final snapshot = CallHealthSnapshot.derive(
        collectedAt: DateTime.utc(2026, 7, 3),
        lifecycle: CallConnectionLifecycle.connected,
        participants: const [
          CallHealthParticipantSnapshot(
            sanitizedId: 'remote_1',
            label: 'Remote participant 1',
            isLocal: false,
            connectionQuality: CallConnectionQuality.fair,
          ),
        ],
      );

      expect(snapshot.state, CallConnectionHealthState.fair);
      expect(snapshot.summaryLabel, 'Call slightly unstable');
      expect(
        snapshot.issueCodes,
        contains(CallHealthIssueCodes.remoteConnectionFair),
      );
    });

    test('reports poor when any participant connection is poor or lost', () {
      final snapshot = CallHealthSnapshot.derive(
        collectedAt: DateTime.utc(2026, 7, 3),
        lifecycle: CallConnectionLifecycle.connected,
        participants: const [
          CallHealthParticipantSnapshot(
            sanitizedId: 'remote_1',
            label: 'Remote participant 1',
            isLocal: false,
            connectionQuality: CallConnectionQuality.lost,
          ),
        ],
      );

      expect(snapshot.state, CallConnectionHealthState.poor);
      expect(snapshot.summaryLabel, 'Someone has a poor connection');
      expect(
        snapshot.issueCodes,
        contains(CallHealthIssueCodes.remoteConnectionLost),
      );
    });

    test('reports reconnecting before participant quality', () {
      final snapshot = CallHealthSnapshot.derive(
        collectedAt: DateTime.utc(2026, 7, 3),
        lifecycle: CallConnectionLifecycle.reconnecting,
        participants: const [
          CallHealthParticipantSnapshot(
            sanitizedId: 'remote_1',
            label: 'Remote participant 1',
            isLocal: false,
            connectionQuality: CallConnectionQuality.poor,
          ),
        ],
      );

      expect(snapshot.state, CallConnectionHealthState.reconnecting);
      expect(snapshot.summaryLabel, 'Reconnecting...');
      expect(
        snapshot.issueCodes,
        contains(CallHealthIssueCodes.roomReconnecting),
      );
    });

    test('reports connecting before participant quality', () {
      final snapshot = CallHealthSnapshot.derive(
        collectedAt: DateTime.utc(2026, 7, 3),
        lifecycle: CallConnectionLifecycle.connecting,
        participants: const [
          CallHealthParticipantSnapshot(
            sanitizedId: 'remote_1',
            label: 'Remote participant 1',
            isLocal: false,
            connectionQuality: CallConnectionQuality.poor,
          ),
        ],
      );

      expect(snapshot.state, CallConnectionHealthState.connecting);
      expect(snapshot.summaryLabel, 'Connecting...');
      expect(
        snapshot.issueCodes,
        contains(CallHealthIssueCodes.callConnecting),
      );
    });

    test('reports disconnected for ended or disconnected lifecycles', () {
      final snapshot = CallHealthSnapshot.derive(
        collectedAt: DateTime.utc(2026, 7, 3),
        lifecycle: CallConnectionLifecycle.disconnected,
      );

      expect(snapshot.state, CallConnectionHealthState.disconnected);
      expect(snapshot.summaryLabel, 'Call disconnected');
      expect(
        snapshot.issueCodes,
        contains(CallHealthIssueCodes.roomDisconnected),
      );
    });

    test('reports app issue for missing remote audio sink', () {
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
            remoteAudioAudible: false,
            remoteAudioReason: 'remote_audio_sink_missing',
          ),
        ],
      );

      expect(snapshot.state, CallConnectionHealthState.appIssueSuspected);
      expect(snapshot.summaryLabel, 'Audio issue detected');
      expect(
        snapshot.issueCodes,
        contains(CallHealthIssueCodes.remoteAudioSinkMissing),
      );
    });

    test('reports app issue for missing microphone publication', () {
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
          ),
        ],
      );

      expect(snapshot.state, CallConnectionHealthState.appIssueSuspected);
      expect(
        snapshot.issueCodes,
        contains(CallHealthIssueCodes.remoteAudioPublicationMissing),
      );
    });

    test('does not treat intentional remote mute as app issue', () {
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
            audioPublicationMuted: true,
          ),
        ],
      );

      expect(snapshot.state, CallConnectionHealthState.good);
      expect(
        snapshot.issueCodes,
        contains(CallHealthIssueCodes.remoteAudioPublicationMuted),
      );
    });

    test('keeps diagnostics sanitized', () {
      final snapshot = CallHealthSnapshot.derive(
        collectedAt: DateTime.utc(2026, 7, 3),
        lifecycle: CallConnectionLifecycle.connected,
        participants: const [
          CallHealthParticipantSnapshot(
            sanitizedId: 'remote_1',
            label: 'Captain Ari',
            isLocal: false,
            userId: '@ari:example.org',
          ),
        ],
      );

      final diagnostics = snapshot.toDiagnosticsJson().toString();
      expect(diagnostics, contains('remote_1'));
      expect(diagnostics, isNot(contains('Captain Ari')));
      expect(diagnostics, isNot(contains('@')));
      expect(diagnostics, isNot(contains('!')));
    });
  });

  group('CallHealthController', () {
    test('recovers from poor to good on later snapshots', () {
      final controller = CallHealthController();
      controller.update(
        CallHealthSnapshot.derive(
          collectedAt: DateTime.utc(2026, 7, 3),
          lifecycle: CallConnectionLifecycle.connected,
          participants: const [
            CallHealthParticipantSnapshot(
              sanitizedId: 'remote_1',
              label: 'Remote participant 1',
              isLocal: false,
              connectionQuality: CallConnectionQuality.poor,
            ),
          ],
        ),
      );
      controller.update(
        CallHealthSnapshot.derive(
          collectedAt: DateTime.utc(2026, 7, 3, 0, 0, 1),
          lifecycle: CallConnectionLifecycle.connected,
          participants: const [
            CallHealthParticipantSnapshot(
              sanitizedId: 'remote_1',
              label: 'Remote participant 1',
              isLocal: false,
              connectionQuality: CallConnectionQuality.good,
            ),
          ],
        ),
      );

      expect(controller.snapshot.state, CallConnectionHealthState.good);
    });

    test('ignores late updates after dispose', () async {
      final controller = CallHealthController();
      await controller.dispose();

      controller.update(
        CallHealthSnapshot.derive(
          collectedAt: DateTime.utc(2026, 7, 3),
          lifecycle: CallConnectionLifecycle.connected,
        ),
      );

      expect(controller.snapshot.state, CallConnectionHealthState.unknown);
    });
  });
}
