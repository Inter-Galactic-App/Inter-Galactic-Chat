import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';

void main() {
  group('MatrixLivekitInitialMicrophoneEnableState', () {
    test(
      'keeps current generation enabled while the call wants microphone',
      () {
        final state = MatrixLivekitInitialMicrophoneEnableState();
        final generation = state.generation;

        expect(state.shouldKeepLateCompletionEnabled, isTrue);
        expect(state.shouldKeepEnabledForGeneration(generation), isTrue);
      },
    );

    test('invalidates pending capture refresh when mute intent changes', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      final refreshGeneration = state.generation;

      state.markDesiredMicrophoneMuted(stopOnMute: true);

      expect(state.desiredMicrophoneEnabled, isFalse);
      expect(state.shouldKeepLateCompletionEnabled, isFalse);
      expect(state.shouldKeepEnabledForGeneration(refreshGeneration), isFalse);

      state.markDesiredMicrophoneEnabled(true);

      expect(state.shouldKeepEnabledForGeneration(refreshGeneration), isFalse);
      expect(state.shouldKeepEnabledForGeneration(state.generation), isTrue);
    });

    test('keeps push-to-talk release ahead of stale profile refreshes', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      final refreshGenerationWhilePressed = state.generation;

      // Push to Talk release mutes the session while a capture-profile refresh
      // may still be between its disable and re-enable awaits.
      state.markDesiredMicrophoneMuted(stopOnMute: false);

      expect(
        state.shouldKeepEnabledForGeneration(refreshGenerationWhilePressed),
        isFalse,
      );

      // A later Push to Talk press should allow current work, not revive the
      // refresh that started before the release.
      state.markDesiredMicrophoneEnabled(true);

      expect(
        state.shouldKeepEnabledForGeneration(refreshGenerationWhilePressed),
        isFalse,
      );
      expect(state.shouldKeepEnabledForGeneration(state.generation), isTrue);
    });

    test('reconciles recreated publications to manual mute intent', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();

      state.markDesiredMicrophoneMuted(stopOnMute: true);

      expect(state.desiredMicrophoneEnabled, isFalse);
      expect(state.desiredMuteStopOnMute, isTrue);
      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isTrue,
      );
      expect(
        state.shouldReconcileMutedPublication(publicationMuted: true),
        isFalse,
      );

      state.markDesiredMicrophoneEnabled(true);

      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isFalse,
      );
    });

    test('reconciles recreated publications to push-to-talk mute intent', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();

      state.markDesiredMicrophoneMuted(stopOnMute: false);

      expect(state.desiredMicrophoneEnabled, isFalse);
      expect(state.desiredMuteStopOnMute, isFalse);
      expect(
        state.shouldReconcileMutedPublication(publicationMuted: false),
        isTrue,
      );
    });

    test('invalidates pending microphone work when the call ends', () {
      final state = MatrixLivekitInitialMicrophoneEnableState();
      final generation = state.generation;

      state.markCallInactive();

      expect(state.isCallActive, isFalse);
      expect(state.shouldKeepLateCompletionEnabled, isFalse);
      expect(state.shouldKeepEnabledForGeneration(generation), isFalse);
    });
  });
}
